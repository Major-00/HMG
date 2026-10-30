--!strict
-- Balls: ball tiers in unlock order. Every hit uses the best ball owned (the last one in this
-- list that the save owns). A ball sets the base odds of each rarity; Luck from distance then
-- shifts them toward rarer Mascots (Tuning.Catch). Balls are bought with Cash only, never Robux.
-- More tiers and prices come in the shop step.

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
		weights = {
			common = 70,
			uncommon = 22,
			rare = 6,
			epic = 1.6,
			legendary = 0.35,
			mythic = 0.05,
		},
	},
}

return Balls
