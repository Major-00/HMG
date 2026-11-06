--!strict
-- Biomes: the lane's biomes in flight order. There is one world (Biomes[1]).
-- Where each biome starts is Tuning.BiomeStarts, measured from the hit line.

local HookTypes = require(script.Parent.Parent.HookTypes)

local Biomes: { { HookTypes.BiomeConfig } } = {
	{
		{ id = "meadow", displayName = "Meadow" },
		{ id = "windy_highlands", displayName = "Windy Highlands" },
		{ id = "tundra", displayName = "Tundra" },
		{ id = "jungle_ruins", displayName = "Jungle Ruins" },
		{ id = "coral_reef", displayName = "Coral Reef" },
		{ id = "geyser_flats", displayName = "Geyser Flats" },
	},
}

return Biomes
