--[[
    car_dealer_2 — server (authoritative)

    The server is the only authority here:
      • it owns the daily stock list,
      • it validates the purchase (stock membership + availability, funds),
      • it takes the money, creates a proper garage-managed owned vehicle, spawns
        it, links it for persistence, and hands over the keys.

    Each car in the daily list is a single unit. Buying one removes it from the
    list, and a per-unit reservation stops two players racing for the same one.

    Spawning server-side (via qbx.spawnVehicle) is what keeps this safe: the
    client never hands us a network id, so it can never trick us into handing out
    keys to a vehicle it didn't actually buy.
]]

local CarPool      = Config.CarPool
local DailyMaxCars = Config.DailyMaxCars

math.randomseed(os.time())

--------------------------------------------------------------------------------
-- Daily stock
--------------------------------------------------------------------------------

local DailyStock = {}   -- array of { id, spawn, label, price }
local reserved   = {}   -- [stockId] = true while a purchase for that unit is in flight
local stockSeq   = 0    -- monotonic id source, so ids never collide across days
local stockDate  = nil  -- 'YYYY-MM-DD' the current stock was generated for

-- Persistence via FiveM KVP (a small server-side key/value store that survives
-- restarts and is never exposed to clients). We snapshot the lot so a same-day
-- restart restores the exact same lineup (and remembers what's already sold)
-- instead of re-rolling. `reserved` is intentionally NOT saved — nothing is
-- mid-purchase across a restart.
local KVP_KEY = 'car_dealer_2:stock'

local function saveStock()
    SetResourceKvp(KVP_KEY, json.encode({
        date  = stockDate,
        seq   = stockSeq,
        stock = DailyStock,
    }))
end

---@return { date: string, seq: integer, stock: table[] }?
local function loadStock()
    local raw = GetResourceKvpString(KVP_KEY)
    if not raw then return nil end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == 'table' then return data end
    return nil
end

---Weighted random pick from a list of `{ weight = n, ... }` entries.
---@param items table[]
---@return integer? index
local function getWeightedIndex(items)
    local total = 0
    for _, item in ipairs(items) do
        total = total + item.weight
    end
    if total <= 0 then return nil end

    local threshold = math.random(total)
    local cumulative = 0
    for i, item in ipairs(items) do
        cumulative = cumulative + item.weight
        if threshold <= cumulative then
            return i
        end
    end
end

---Build a fresh, duplicate-free stock list for the current day and log it.
local function generateDailyStock()
    -- Work on a copy so we can remove picks and never show the same model twice.
    local pool = {}
    for i, item in ipairs(CarPool) do
        pool[i] = item
    end

    local stock = {}
    local count = math.min(DailyMaxCars, #pool)
    for _ = 1, count do
        local pickIndex = getWeightedIndex(pool)
        if not pickIndex then break end
        local pick = table.remove(pool, pickIndex)

        stockSeq = stockSeq + 1
        stock[#stock + 1] = {
            id    = stockSeq,
            spawn = pick.spawn,
            label = pick.label,
            price = pick.price,
        }
    end

    DailyStock = stock
    reserved   = {}
    stockDate  = os.date('%Y-%m-%d')
    saveStock()

    print(('^2--- TODAY\'S SHOWROOM CARS (%s) ---^0'):format(stockDate))
    for index, car in ipairs(DailyStock) do
        print(('^3%d.^0 %s (Price: $%s)'):format(index, car.label, car.price))
    end
    print('^2-------------------------------------^0')

    -- Close any showroom that's open across the day rollover (harmless at boot).
    TriggerClientEvent('car_dealer_2:onRefresh', -1)
end

-- Restore the saved lot if it's still the same day; otherwise roll a fresh one.
-- Then keep checking once a minute so the lot rotates when the day changes.
-- (A once-a-minute check is free on the server.)
CreateThread(function()
    local saved = loadStock()
    if saved and saved.stock and saved.date == os.date('%Y-%m-%d') then
        DailyStock = saved.stock
        stockSeq   = saved.seq or 0
        stockDate  = saved.date
        reserved   = {}
        print(('^2[car_dealer_2] Restored %d saved showroom car(s) for %s.^0'):format(#DailyStock, stockDate))
    else
        generateDailyStock()
    end

    while true do
        Wait(60000)
        if os.date('%Y-%m-%d') ~= stockDate then
            generateDailyStock()
        end
    end
end)

local function findStockEntry(id)
    for _, car in ipairs(DailyStock) do
        if car.id == id then
            return car
        end
    end
end

local function removeStockEntry(id)
    for index, car in ipairs(DailyStock) do
        if car.id == id then
            table.remove(DailyStock, index)
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Purchase flow
--------------------------------------------------------------------------------

-- Authoritative per-citizen lock so a player can't run two purchases at once.
local purchaseInProgress = {}

lib.callback.register('car_dealer_2:getDailyStock', function()
    -- Hide units that are sold (removed) or currently being bought (reserved).
    local available = {}
    for _, car in ipairs(DailyStock) do
        if not reserved[car.id] then
            available[#available + 1] = car
        end
    end
    return available
end)

lib.callback.register('car_dealer_2:buyCar', function(source, stockId)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return { success = false, reason = 'no_player' }
    end

    local citizenid = player.PlayerData.citizenid

    if purchaseInProgress[citizenid] then
        return { success = false, reason = 'busy' }
    end
    purchaseInProgress[citizenid] = true

    local claimedId -- set once we reserve a unit; released by finish()

    -- Every exit path goes through finish() so both the per-citizen lock and the
    -- per-unit reservation are always cleaned up. `sold = true` consumes the unit;
    -- otherwise it goes back on the lot.
    local function finish(result, sold)
        purchaseInProgress[citizenid] = nil
        if claimedId then
            if sold then
                removeStockEntry(claimedId)
                saveStock() -- persist so a restart doesn't resurrect a sold car
                -- Tell everyone so any open showroom drops this unit live.
                TriggerClientEvent('car_dealer_2:onSold', -1, claimedId)
            else
                reserved[claimedId] = nil
            end
        end
        return result
    end

    -- 1. The requested unit must exist and not already be claimed/sold.
    local car = findStockEntry(stockId)
    if not car then
        return finish({ success = false, reason = 'unavailable' })
    end
    if reserved[car.id] then
        return finish({ success = false, reason = 'unavailable' })
    end

    -- Reserve the unit synchronously, before any await, so a second buyer racing
    -- for the same car loses the race here.
    reserved[car.id] = true
    claimedId = car.id

    -- 2. They must be able to afford it. We only CHECK here; the money is taken
    --    at the very end, once the car actually exists, so that no failure (even
    --    an uncaught error in a qbx export) can ever take money without delivery.
    local balance = exports.qbx_core:GetMoney(src, 'bank')
    if not balance or balance < car.price then
        return finish({ success = false, reason = 'insufficient_funds' })
    end

    -- 3. Create a real garage-managed owned vehicle. qbx_vehicles generates the
    --    unique plate + default props and does the DB insert. No `garage` field
    --    => it's created as OUT (we hand it over now); storing it sets its garage.
    local vehicleId = exports.qbx_vehicles:CreatePlayerVehicle({
        model = car.spawn,
        citizenid = citizenid,
    })
    if not vehicleId then
        print(('^1[car_dealer_2] CreatePlayerVehicle failed for %s (id %s)^0'):format(GetPlayerName(src), src))
        return finish({ success = false, reason = 'db_error' })
    end

    -- Read the stored props back — we MUST spawn from these. Exports copy table
    -- args across the resource boundary, so the plate qbx_vehicles generated only
    -- exists in the DB row, not in any table we passed in.
    local owned = exports.qbx_vehicles:GetPlayerVehicle(vehicleId)
    local props = owned and owned.props
    if not props then
        exports.qbx_vehicles:DeletePlayerVehicles('vehicleId', vehicleId)
        print(('^1[car_dealer_2] Could not read back vehicle %s for %s^0'):format(vehicleId, GetPlayerName(src)))
        return finish({ success = false, reason = 'db_error' })
    end

    -- 4. Spawn server-side (plate matches the DB), then link + key it. Wrapped in
    --    pcall: if qbx.spawnVehicle or the keys/state calls throw, we clean up the
    --    DB row and bail WITHOUT charging the player.
    local ok, veh = pcall(function()
        local _, vehicle = qbx.spawnVehicle({
            model       = car.spawn,
            spawnSource = Config.CoordsToSpawnTheCar, -- vector4
            warp        = GetPlayerPed(src),          -- drop the buyer into the seat
            props       = props,                      -- carries the DB plate + defaults
        })
        assert(vehicle and DoesEntityExist(vehicle), 'vehicle did not spawn')
        Entity(vehicle).state:set('vehicleid', vehicleId, false) -- garages/persistence link
        exports.qbx_vehiclekeys:GiveKeys(src, vehicle)
        return vehicle
    end)

    if not ok or not veh then
        exports.qbx_vehicles:DeletePlayerVehicles('vehicleId', vehicleId)
        print(('^1[car_dealer_2] Delivery failed for %s (%s): %s^0')
            :format(GetPlayerName(src), car.spawn, tostring(veh)))
        return finish({ success = false, reason = 'spawn_failed' })
    end

    -- 5. The car is delivered — charge LAST. Nothing after this can fail, so money
    --    is only ever taken once the player actually has the vehicle.
    if not exports.qbx_core:RemoveMoney(src, 'bank', car.price, 'car_dealer_2: bought ' .. car.label) then
        if DoesEntityExist(veh) then DeleteEntity(veh) end
        exports.qbx_vehicles:DeletePlayerVehicles('vehicleId', vehicleId)
        return finish({ success = false, reason = 'payment_failed' })
    end

    -- Sold: this unit leaves the daily lot.
    return finish({ success = true, label = car.label }, true)
end)

-- Safety net: never leak the lock if a player drops mid-purchase. (The unit's
-- reservation is still released by the in-flight callback's finish().)
AddEventHandler('playerDropped', function()
    local player = exports.qbx_core:GetPlayer(source)
    if player then
        purchaseInProgress[player.PlayerData.citizenid] = nil
    end
end)

--------------------------------------------------------------------------------
-- Admin commands
--------------------------------------------------------------------------------

-- /restockdealer — re-roll today's lineup using the weighted algorithm.
lib.addCommand('restockdealer', {
    help = 'Re-roll the dealership\'s daily lineup (weighted random)',
    restricted = 'group.admin',
}, function(source)
    generateDailyStock() -- regenerates, persists, and broadcasts onRefresh
    if source > 0 then
        exports.qbx_core:Notify(source, locale('admin_restocked'), 'success')
    end
end)

-- /adddealercar <model> <price> — add ONE specific car to today's lineup without
-- touching the weighted pool. Useful for one-off promos/specials.
lib.addCommand('adddealercar', {
    help = 'Add a specific car to today\'s dealership lineup',
    params = {
        { name = 'model', type = 'string', help = 'Vehicle spawn name, e.g. sultan' },
        { name = 'price', type = 'number', help = 'Price in $ (must be > 0)' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local model = args.model and args.model:lower()
    local price = args.price

    if not price or price <= 0 then
        if source > 0 then exports.qbx_core:Notify(source, locale('admin_invalid_price'), 'error') end
        return
    end

    -- Validate the model against the framework's known vehicles so we never add
    -- garbage that can't spawn.
    local vehicles = exports.qbx_core:GetVehiclesByName()
    local vehicle = model and vehicles[model]
    if not vehicle then
        if source > 0 then exports.qbx_core:Notify(source, locale('admin_invalid_model', tostring(args.model)), 'error') end
        return
    end

    local label = ('%s %s'):format(vehicle.brand or '', vehicle.name or model):gsub('^%s+', '')

    stockSeq = stockSeq + 1
    DailyStock[#DailyStock + 1] = {
        id    = stockSeq,
        spawn = model,
        label = label,
        price = math.floor(price),
    }
    saveStock()
    TriggerClientEvent('car_dealer_2:onRefresh', -1) -- open showrooms reopen to see it

    if source > 0 then
        exports.qbx_core:Notify(source, locale('admin_added', label, math.floor(price)), 'success')
    end
    print(('^2[car_dealer_2] %s added to the lineup ($%s).^0'):format(label, math.floor(price)))
end)
