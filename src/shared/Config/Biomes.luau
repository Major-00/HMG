--!strict
-- Biomes: World 1 biomes in flight order. WorldController builds each strip from this.
-- landmark = model name under ReplicatedStorage.Landmarks (assets/Landmarks/).
-- challenge = per-biome challenge slot, empty in the MVP.
-- Where each biome starts is in Config/Tuning (BiomeStarts); colors come with biome visuals.

local HookTypes = require(script.Parent.Parent.HookTypes)

local Biomes: { HookTypes.BiomeConfig } = {
	{ id = "sandlot", displayName = "Sandlot", landmark = "Sandlot", challenge = nil },
	{ id = "boardwalk", displayName = "Boardwalk", landmark = "Boardwalk", challenge = nil },
	{ id = "candy_land", displayName = "Candy Land", landmark = "CandyLand", challenge = nil },
	{ id = "tundra", displayName = "Tundra", landmark = "Tundra", challenge = nil },
	{ id = "jungle_ruins", displayName = "Jungle Ruins", landmark = "JungleRuins", challenge = nil },
	{ id = "canyon", displayName = "Canyon", landmark = "Canyon", challenge = nil },
}

return Biomes
