--!strict
-- Template: the save a brand-new player starts with. On every load, ProfileStore
-- fills in any keys missing from an older save using these values.
-- Keep it in sync with shared/Types (PlayerData) and Migrations.CURRENT_VERSION.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local Template: Types.PlayerData = {
	version = 2,

	-- Run progress: reset on stadium promotion
	power = 0,
	cash = 0,
	bats = {
		owned = { starter = true },
		equipped = "starter",
	},
	balls = {
		owned = { basic = true },
		notified = {}, -- ball ids whose "New ball unlocked" notice was shown this run
	},
	park = {
		bleachers = 0,
		concessions = 0,
		scoreboard = 0,
		lights = 0,
		jumbotron = 0,
	},
	highestBiome = 1,

	-- Kept forever (Safe at home)
	mascots = {},
	nextMascotUid = 1,
	seats = { false, false, false, false, false, false, false, false, false, false },
	hotbar = { false, false, false, false },
	onDeck = false,
	autoSell = true,
	index = {},
	stadiumTier = 1,
	pitcher = "pitching_machine",

	settings = {
		music = true,
		sfx = true,
		lowGraphics = false,
		tipsSeen = {},
	},

	-- Lifetime stats (never reset)
	lifetime = {
		swings = 0,
		cashEarned = 0,
		mascotsCaught = 0,
		bestDistance = 0,
	},

	firstJoin = 0,
	lastJoin = 0,
	lastOnline = 0,
}

return Template
