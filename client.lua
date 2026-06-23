--[[
    car_dealer_2 — client entrypoint

    This file only owns the dealer ped and the interaction that opens the
    showroom. All the showroom/camera/buy logic lives in showroom.lua, which
    exposes the global OpenShowroom(). The client never decides anything
    authoritative — the server validates and spawns every purchase.
]]

local dealerPed

local function spawnDealer()
    local model = Config.NPCModel
    if not lib.requestModel(model, 5000) then
        print('^1[car_dealer_2] Could not load the dealer ped model.^0')
        return
    end

    local coords = Config.NPCCoords -- vector4
    dealerPed = CreatePed(Config.NPCType, model, coords.x, coords.y, coords.z, coords.w, false, false)
    SetModelAsNoLongerNeeded(model)
    FreezeEntityPosition(dealerPed, true)
    SetEntityInvincible(dealerPed, true)
    SetBlockingOfNonTemporaryEvents(dealerPed, true)

    exports.ox_target:addLocalEntity(dealerPed, {
        {
            name = 'car_dealer_2_buy',
            icon = 'fas fa-car',
            label = locale('target_buy'),
            distance = 2.5,
            onSelect = function() OpenShowroom() end,
        },
    })
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    spawnDealer()
end)

-- Clean up the ped (and its target) on restart so we don't leak peds.
AddEventHandler('onClientResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if dealerPed and DoesEntityExist(dealerPed) then
        exports.ox_target:removeLocalEntity(dealerPed)
        DeleteEntity(dealerPed)
    end
end)
