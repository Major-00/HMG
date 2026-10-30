--!strict
-- Template: the save a brand-new player starts with. On every load, ProfileStore
-- fills in any keys missing from an older save using these values.
-- Keep it in sync with shared/Types (PlayerData) and Migrations.CURRENT_VERSION.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local Template: Types.PlayerData = {
	version = 1,

	-- Reset on rebirth
	power = 0,
	wins = 0,
	bats = {
		owned = { starter = true },
		equipped = "starter",
	},
	highestBiome = 1,

	-- Kept through rebirth
	pets = {},
	nextPetUid = 1,
	pitcher = "pitching_machine",
	rebirths = 0,
	worldsUnlocked = 1,
	currentWorld = 1,

	settings = {
		music = true,
		sfx = true,
		lowGraphics = false,
	},

	-- Lifetime stats (never reset)
	lifetime = {
		swings = 0,
		winsEarned = 0,
		bestDistance = 0,
		eggsHatched = 0,
	},

	firstJoin = 0,
	lastJoin = 0,
}

return Template
