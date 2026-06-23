--[[
    car_dealer_2 — SHARED config (client-visible)

    This file is a shared_script, so it is downloaded by every client. Keep ONLY
    things players are allowed to see here. The car pool, weights and daily count
    live in server_config.lua (server-only) so rarity odds and the full line-up
    stay hidden from players. See CLAUDE.md §2/§5.
]]

Config = {}

-- Dealer ped (the client spawns it).
Config.NPCCoords = vector4(-33.4, -1086.24, 25.42, 170.01)
Config.NPCModel  = `cs_martinmadrazo`
Config.NPCType   = 4

-- Showroom preview pad — a LOCAL preview car only the buyer sees is placed here.
-- A flat, open spot works best; point it at an interior for a true showroom look.
Config.PreviewCoords = vector4(-15.94, -1081.92, 25.67, 249.01)

-- Mouse look speed in the showroom (orbit degrees per unit of mouse input).
-- Raise for faster rotation, lower for slower.
Config.CameraSensitivity = 8.0
