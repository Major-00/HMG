--!strict
-- Stadium: the stadium tiers (the rebirth ladder). Tier N plays World N.
-- Each tier has two separate multipliers, tuned independently:
--   powerMultiplier: multiplies Power gained per hit
--   cashMultiplier:  multiplies what seated Mascots earn per second
-- Tiers 2-4 are placeholders until the promotion step tunes them and adds requirements.

export type StadiumTier = {
	id: string,
	displayName: string,
	powerMultiplier: number,
	cashMultiplier: number,
}

local Stadium: { StadiumTier } = {
	{ id = "sandlot_field", displayName = "Sandlot Field", powerMultiplier = 1, cashMultiplier = 1 },
	{ id = "minor_league", displayName = "Minor League", powerMultiplier = 2, cashMultiplier = 2 },
	{ id = "big_stadium", displayName = "Big Stadium", powerMultiplier = 4, cashMultiplier = 4 },
	{ id = "space_dome", displayName = "Space Dome", powerMultiplier = 8, cashMultiplier = 8 },
}

return Stadium
