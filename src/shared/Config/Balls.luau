--!strict
-- Balls: tiers in unlock order, bought with Cash only (never Robux), each a permanent unlock for
-- the run (they reset on stadium promotion). Every hit uses the best ball owned (the last one in
-- this list that the save owns). A ball sets the base odds of each rarity; Luck from distance
-- then shifts them toward rarer Mascots (Tuning.Catch). The shop shows each ball's odds from the
-- same Formulas.catchOdds the server rolls with.
-- Names are original placeholders.

export type Ball = {
	id: string,
	displayName: string,
	price: number, -- Cash; 0 = owned from the start
	weights: { [string]: number }, -- rarity id -> relative weight (any scale)
}

local Balls: { Ball } = {
	{
		id = "basic",
		displayName = "Basic Ball",
		price = 0,
		weights = { common = 70, uncommon = 22, rare = 6, epic = 1.6, legendary = 0.35, mythic = 0.05 },
	},
	{
		id = "leather",
		displayName = "Leather Ball",
		price = 500,
		weights = { common = 60, uncommon = 26, rare = 10, epic = 3, legendary = 0.8, mythic = 0.2 },
	},
	{
		id = "red_stitch",
		displayName = "Red-Stitch Ball",
		price = 5000,
		weights = { common = 50, uncommon = 28, rare = 14, epic = 5.5, legendary = 2, mythic = 0.5 },
	},
	{
		id = "pro",
		displayName = "Pro Ball",
		price = 50000,
		weights = { common = 40, uncommon = 30, rare = 18, epic = 8, legendary = 3, mythic = 1 },
	},
	{
		id = "comet",
		displayName = "Comet Ball",
		price = 500000,
		weights = { common = 30, uncommon = 30, rare = 22, epic = 11, legendary = 5, mythic = 2 },
	},
	{
		id = "galaxy",
		displayName = "Galaxy Ball",
		price = 5000000,
		weights = { common = 22, uncommon = 28, rare = 25, epic = 14, legendary = 7.5, mythic = 3.5 },
	},
}

return Balls
