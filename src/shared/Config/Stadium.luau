--!strict
-- Stadium: the stadium tiers (the rebirth ladder). Tier N plays World N.
-- Each tier has two separate multipliers, tuned independently:
--   powerMultiplier: multiplies Power gained per hit
--   cashMultiplier:  multiplies what seated Mascots earn per second
-- Promoting to a tier needs `requires`: Cash on hand and a biome reached this run (the Cash
-- is not spent separately; promotion resets Cash anyway). PromotionService checks and applies it.
-- Promotion resets Power, Cash, bats, balls, park upgrades and biome progress, and keeps every
-- Mascot, lock and the Index. It can never be bought with Robux.

export type Requirement = {
	cash: number,
	biome: number, -- highestBiome this run must be at least this (Config/Biomes order)
}

export type StadiumTier = {
	id: string,
	displayName: string,
	powerMultiplier: number,
	cashMultiplier: number,
	requires: Requirement?, -- to promote INTO this tier (nil for the first)
}

local Stadium: { StadiumTier } = {
	{ id = "sandlot_field", displayName = "Sandlot Field", powerMultiplier = 1, cashMultiplier = 1 },
	{
		id = "minor_league",
		displayName = "Minor League",
		powerMultiplier = 2,
		cashMultiplier = 2,
		requires = { cash = 1000000, biome = 5 },
	},
	{
		id = "big_stadium",
		displayName = "Big Stadium",
		powerMultiplier = 4,
		cashMultiplier = 4,
		requires = { cash = 50000000, biome = 6 },
	},
	{
		id = "space_dome",
		displayName = "Space Dome",
		powerMultiplier = 8,
		cashMultiplier = 8,
		requires = { cash = 2000000000, biome = 6 },
	},
}

return Stadium
