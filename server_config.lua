--[[
    car_dealer_2 — SERVER-ONLY config

    Loaded under server_scripts, so clients NEVER receive this file. The car pool,
    weights and daily count live here so players can't read rarity odds or the
    full line-up by inspecting their game cache.

    `Config = Config or {}` extends the table set up by the shared config.lua
    instead of resetting it. (On the server, shared scripts load first, so the
    client-visible values already exist when this runs.)
]]

Config = Config or {}

-- How many distinct cars are offered each day.
Config.DailyMaxCars = 4

-- Where a purchased car is delivered (the server spawns it here and warps the
-- buyer in). Server-only: the client never needs it.
Config.CoordsToSpawnTheCar = vector4(-15.94, -1081.92, 25.67, 249.01)

-- The full pool. Higher `weight` = more likely to appear in a day's line-up
-- (weight is a probability of being picked, not a quantity). Players never see
-- this file, so the odds stay hidden.
Config.CarPool = {
    -- Common (high weight, low price)
    { spawn = 'blista',    label = 'Blista Compact',   price = 15000,   weight = 50 },
    { spawn = 'sultan',    label = 'Karin Sultan',     price = 35000,   weight = 40 },
    { spawn = 'futo',      label = 'Karin Futo',       price = 20000,   weight = 45 },

    -- Uncommon (medium weight, medium price)
    { spawn = 'elegy',     label = 'Annis Elegy RH8',  price = 95000,   weight = 25 },
    { spawn = 'dominator', label = 'Vapid Dominator',  price = 80000,   weight = 30 },

    -- Rare (low weight, high price)
    { spawn = 'banshee',   label = 'Bravado Banshee',  price = 150000,  weight = 10 },
    { spawn = 'comet2',    label = 'Pfister Comet',    price = 180000,  weight = 8 },

    -- Legendary (extremely low weight, luxury price)
    { spawn = 'adder',     label = 'Truffade Adder',   price = 1000000, weight = 2 },
    { spawn = 't20',       label = 'Progen T20',       price = 2200000, weight = 1 },
}
