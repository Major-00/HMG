--!strict
-- Template: the save a brand-new player starts with. On every load, ProfileStore
-- fills in any keys missing from an older save using these values.
-- Keep it in sync with shared/Types (PlayerData) and Migrations.CURRENT_VERSION.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local Template: Types.PlayerData = {
	version = 4,

	power = 0,
	highestBiome = 1,
	pitcher = "fungo",

	settings = {
		music = true,
		sfx = true,
		lowGraphics = false,
	},

	lifetime = {
		swings = 0,
		bestDistance = 0,
	},

	firstJoin = 0,
	lastJoin = 0,
	lastOnline = 0,
}

return Template
