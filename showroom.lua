--[[
    car_dealer_2 — showroom (client)

    A cinematic preview: the selected car is spawned locally on a pad and a
    scripted camera orbits it. The player looks around with the mouse, scrolls to
    zoom, switches cars with the arrows, and presses E to buy. The NUI is a purely
    visual overlay (no cursor) while browsing; we only grab focus for the styled
    "are you sure?" confirm modal.

    Nothing here is authoritative: buying just calls the server callback, which
    validates, charges, spawns the real car and warps the player in.
]]

-- Control ids (https://docs.fivem.net/docs/game-references/controls/)
local CONTROL = {
    lookLR   = 1,
    lookUD   = 2,
    wheelUp  = 15,  -- INPUT_WEAPON_WHEEL_PREV  (scroll up)
    wheelDn  = 14,  -- INPUT_WEAPON_WHEEL_NEXT  (scroll down)
    prev     = 174, -- arrow left
    next     = 175, -- arrow right
    buy      = 38,  -- E
    sit      = 23,  -- F
    exit     = 177, -- backspace
}

-- Tunables
local PITCH_MIN, PITCH_MAX = -8.0, 55.0
local DIST_MIN, DIST_MAX   = 2.8, 8.0

local CLASS_NAMES = {
    [0] = 'Compact', [1] = 'Sedan', [2] = 'SUV', [3] = 'Coupe', [4] = 'Muscle',
    [5] = 'Sports Classic', [6] = 'Sports', [7] = 'Super', [8] = 'Motorcycle',
    [9] = 'Off-road', [10] = 'Industrial', [11] = 'Utility', [12] = 'Van',
    [13] = 'Cycle', [14] = 'Boat', [15] = 'Helicopter', [16] = 'Plane',
    [17] = 'Service', [18] = 'Emergency', [19] = 'Military', [20] = 'Commercial',
    [21] = 'Train', [22] = 'Open Wheel',
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local isOpen      = false
local confirming  = false   -- true while the buy modal is up (input paused)
local busy        = false   -- true while a purchase round-trips
local stock       = {}      -- daily stock from the server
local index       = 1       -- currently previewed entry
local previewVeh  = nil
local cam         = nil
local seatedIn    = false
local pedHome     = nil      -- ped coords/heading to restore on exit
local confirmingCar = nil    -- exact car the confirm modal is showing

-- Camera orbit state
local camYaw, camPitch, camDist = 35.0, 14.0, 5.0

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

---Normalised (0..1) performance figures straight from the model's handling.
local function modelStats(hash)
    local function norm(v, max)
        return clamp((v or 0.0) / max, 0.06, 1.0)
    end
    return {
        speed    = norm(GetVehicleModelEstimatedMaxSpeed(hash), 55.0),
        accel    = norm(GetVehicleModelAcceleration(hash), 0.55),
        braking  = norm(GetVehicleModelMaxBraking(hash), 1.2),
        handling = norm(GetVehicleModelMaxTraction(hash), 2.6),
    }
end

local function currentCar()
    return stock[index]
end

---Payload describing the previewed car for the NUI.
local function carPayload()
    local car = currentCar()
    if not car then return nil end
    local hash = GetHashKey(car.spawn)
    return {
        id    = car.id,
        name  = car.label,
        price = car.price,
        class = CLASS_NAMES[GetVehicleClassFromName(hash)] or 'Vehicle',
        index = index,
        total = #stock,
        stats = modelStats(hash),
    }
end

local function sendShow()
    SendNUIMessage({
        action = 'show',
        labels = {
            brand        = locale('dealer_title'),
            daily        = locale('daily_sub'),
            statSpeed    = locale('stat_speed'),
            statAccel    = locale('stat_accel'),
            statBraking  = locale('stat_braking'),
            statHandling = locale('stat_handling'),
            hintRotate   = locale('hint_rotate'),
            hintZoom     = locale('hint_zoom'),
            hintSwitch   = locale('hint_switch'),
            hintBuy      = locale('hint_buy'),
            hintSit      = locale('hint_sit'),
            hintExit     = locale('hint_exit'),
            confirmTitle = locale('confirm_title'),
            confirmBody  = locale('confirm_body'),
            confirmYes   = locale('confirm_yes'),
            confirmNo    = locale('confirm_no'),
        },
        car = carPayload(),
    })
end

local function notifyResult(result, car)
    if result and result.success then
        lib.notify({ title = locale('bought_title'), description = locale('bought_desc', result.label or car.name), type = 'success', duration = 5000 })
        return
    end
    local reason = result and result.reason
    if reason == 'insufficient_funds' then
        lib.notify({ title = locale('funds_title'), description = locale('funds_desc', car.price), type = 'error', duration = 5000 })
    elseif reason == 'unavailable' then
        lib.notify({ title = locale('unavailable_title'), description = locale('unavailable_desc'), type = 'error', duration = 5000 })
    else
        lib.notify({ title = locale('failed_title'), description = locale('failed_desc'), type = 'error', duration = 5000 })
    end
end

--------------------------------------------------------------------------------
-- Preview vehicle
--------------------------------------------------------------------------------

local function deletePreview()
    -- Note: we intentionally keep `seatedIn` as-is so switching cars while seated
    -- can re-seat the player in the freshly spawned vehicle.
    if previewVeh and DoesEntityExist(previewVeh) then
        DeleteEntity(previewVeh)
    end
    previewVeh = nil
end

---Spawn the currently-indexed car as a LOCAL (non-networked) preview entity.
local function spawnPreview()
    deletePreview()

    local car = currentCar()
    if not car then return false end

    local hash = GetHashKey(car.spawn)
    if not lib.requestModel(hash, 7500) then
        return false
    end

    local p = Config.PreviewCoords -- vector4
    -- isNetwork=false => only this client sees it; netMissionEntity=false.
    previewVeh = CreateVehicle(hash, p.x, p.y, p.z, p.w, false, false)
    SetModelAsNoLongerNeeded(hash)

    SetEntityInvincible(previewVeh, true)
    SetVehicleDoorsLocked(previewVeh, 2)
    SetVehicleDirtLevel(previewVeh, 0.0)
    SetVehicleNumberPlateText(previewVeh, 'PREVIEW')
    SetVehicleOnGroundProperly(previewVeh)
    FreezeEntityPosition(previewVeh, true) -- after ground placement so it holds
    return true
end

local function reseatPed()
    -- Keep the seated player inside whatever car is currently previewed.
    if seatedIn and previewVeh and DoesEntityExist(previewVeh) then
        TaskWarpPedIntoVehicle(cache.ped, previewVeh, -1)
    end
end

local function toggleSeat()
    local ped = cache.ped
    if seatedIn then
        seatedIn = false
        SetEntityCoordsNoOffset(ped, pedHome.x, pedHome.y, pedHome.z, false, false, false)
        SetEntityHeading(ped, pedHome.w)
        FreezeEntityPosition(ped, true)
    elseif previewVeh and DoesEntityExist(previewVeh) then
        seatedIn = true
        FreezeEntityPosition(ped, false)
        TaskWarpPedIntoVehicle(ped, previewVeh, -1)
    end
end

--------------------------------------------------------------------------------
-- Camera
--------------------------------------------------------------------------------

local function updateCam()
    if not (cam and previewVeh and DoesEntityExist(previewVeh)) then return end

    local c = GetEntityCoords(previewVeh)
    local cx, cy, cz = c.x, c.y, c.z + 0.45

    local yaw, pitch = math.rad(camYaw), math.rad(camPitch)
    local cosP = math.cos(pitch)
    local x = cx + camDist * cosP * math.sin(yaw)
    local y = cy - camDist * cosP * math.cos(yaw)
    local z = cz + camDist * math.sin(pitch)

    SetCamCoord(cam, x, y, z)
    PointCamAtCoord(cam, cx, cy, cz)
end

local function startCam()
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 50.0, false, 0)
    updateCam()
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 600, true, false)
end

local function stopCam()
    RenderScriptCams(false, true, 600, true, false)
    if cam then
        DestroyCam(cam, false)
        cam = nil
    end
end

--------------------------------------------------------------------------------
-- Switching / buying
--------------------------------------------------------------------------------

local function switchTo(newIndex)
    if #stock == 0 then return end
    index = ((newIndex - 1) % #stock) + 1
    if spawnPreview() then
        reseatPed()
        updateCam()
        SendNUIMessage({ action = 'update', car = carPayload() })
    end
end

-- forward declaration
local CloseShowroom

local function requestBuy()
    if confirming or busy then return end
    local car = carPayload()
    if not car then return end
    confirmingCar = car -- lock the buy to exactly this car, even if the lot shifts
    confirming = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'confirm', car = car })
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------

function OpenShowroom()
    if isOpen then return end

    stock = lib.callback.await('car_dealer_2:getDailyStock', false)
    if not stock then
        lib.notify({ title = locale('error_title'), description = locale('error_fetch'), type = 'error', duration = 5000 })
        return
    end
    if #stock == 0 then
        lib.notify({ title = locale('error_title'), description = locale('sold_out'), type = 'info', duration = 5000 })
        return
    end

    isOpen, confirming, busy, seatedIn = true, false, false, false
    index = 1
    camYaw, camPitch, camDist = 35.0, 14.0, 5.0

    local ped = cache.ped
    local pc = GetEntityCoords(ped)
    pedHome = vector4(pc.x, pc.y, pc.z, GetEntityHeading(ped))
    FreezeEntityPosition(ped, true)

    if not spawnPreview() then
        FreezeEntityPosition(ped, false)
        isOpen = false
        lib.notify({ title = locale('error_title'), description = locale('error_fetch'), type = 'error', duration = 5000 })
        return
    end

    startCam()
    sendShow()

    -- Main interaction loop. NUI has no focus while browsing, so we read the
    -- mouse/keys natively and drive the camera ourselves.
    CreateThread(function()
        while isOpen do
            DisableAllControlActions(0)

            if not confirming and not busy then
                -- Orbit with the mouse. The look "normal" already reflects mouse
                -- speed; CameraSensitivity just scales it to degrees-per-frame.
                local sens = Config.CameraSensitivity
                camYaw   = camYaw - GetDisabledControlNormal(0, CONTROL.lookLR) * sens
                camPitch = clamp(camPitch + GetDisabledControlNormal(0, CONTROL.lookUD) * sens, PITCH_MIN, PITCH_MAX)

                -- Zoom with the wheel.
                if GetDisabledControlNormal(0, CONTROL.wheelUp) ~= 0 then
                    camDist = clamp(camDist - 0.4, DIST_MIN, DIST_MAX)
                elseif GetDisabledControlNormal(0, CONTROL.wheelDn) ~= 0 then
                    camDist = clamp(camDist + 0.4, DIST_MIN, DIST_MAX)
                end

                updateCam()

                if IsDisabledControlJustPressed(0, CONTROL.next) then
                    switchTo(index + 1)
                elseif IsDisabledControlJustPressed(0, CONTROL.prev) then
                    switchTo(index - 1)
                elseif IsDisabledControlJustPressed(0, CONTROL.sit) then
                    toggleSeat()
                elseif IsDisabledControlJustPressed(0, CONTROL.buy) then
                    requestBuy()
                elseif IsDisabledControlJustPressed(0, CONTROL.exit) then
                    CloseShowroom()
                end
            end

            Wait(0)
        end
    end)
end

CloseShowroom = function()
    if not isOpen then return end
    isOpen = false
    confirming = false

    local ped = cache.ped
    if seatedIn then
        seatedIn = false
    end

    stopCam()
    deletePreview()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })

    if pedHome then
        SetEntityCoordsNoOffset(ped, pedHome.x, pedHome.y, pedHome.z, false, false, false)
        SetEntityHeading(ped, pedHome.w)
    end
    FreezeEntityPosition(ped, false)
end

--------------------------------------------------------------------------------
-- NUI callbacks
--------------------------------------------------------------------------------

RegisterNUICallback('confirmResult', function(data, cb)
    cb({})
    if not confirming then return end
    confirming = false
    SetNuiFocus(false, false)

    local car = confirmingCar
    confirmingCar = nil

    if not data or not data.confirm or not car then
        -- Back to browsing.
        SendNUIMessage({ action = 'browse' })
        return
    end

    -- Confirmed: tear the showroom down first so the server's warp-into-vehicle
    -- lands on a normal player, then run the authoritative purchase. We buy the
    -- exact car the modal showed; if it sold during confirmation the server
    -- simply rejects it as unavailable.
    busy = true
    CloseShowroom()

    local result = lib.callback.await('car_dealer_2:buyCar', false, car.id)
    busy = false
    notifyResult(result, car)
end)

--------------------------------------------------------------------------------
-- Live stock sync (keeps concurrent viewers consistent)
--------------------------------------------------------------------------------

local function removeFromStock(id)
    for i, c in ipairs(stock) do
        if c.id == id then
            table.remove(stock, i)
            return true
        end
    end
    return false
end

-- Another player bought a car. Drop it from our open showroom so we can never
-- try to buy a unit that's already gone (previews are local, so two people
-- viewing the same model never collide — only the stock list needs syncing).
RegisterNetEvent('car_dealer_2:onSold', function(soldId)
    if not isOpen then return end

    local viewing = currentCar()
    local viewingId = viewing and viewing.id

    if not removeFromStock(soldId) then return end -- wasn't in our list

    if #stock == 0 then
        lib.notify({ title = locale('dealer_title'), description = locale('sold_out'), type = 'info', duration = 5000 })
        CloseShowroom()
        return
    end

    if viewingId == soldId then
        -- The car we were looking at just sold; slide to a valid one.
        index = clamp(index, 1, #stock)
        if spawnPreview() then
            reseatPed()
            updateCam()
        end
        SendNUIMessage({ action = 'update', car = carPayload() })
        lib.notify({ title = locale('unavailable_title'), description = locale('unavailable_desc'), type = 'info', duration = 5000 })
    else
        -- Keep pointing at the same car; just refresh the index + counter.
        for i, c in ipairs(stock) do
            if c.id == viewingId then index = i break end
        end
        SendNUIMessage({ action = 'update', car = carPayload() })
    end
end)

-- The daily stock rolled over while someone was browsing — close cleanly.
RegisterNetEvent('car_dealer_2:onRefresh', function()
    if not isOpen then return end
    CloseShowroom()
    lib.notify({ title = locale('dealer_title'), description = locale('refreshed'), type = 'info', duration = 5000 })
end)

-- Safety: release focus and clean up if the resource stops mid-showroom.
AddEventHandler('onClientResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if isOpen then
        CloseShowroom()
    end
end)
