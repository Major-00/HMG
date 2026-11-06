--!strict
-- Rarities: the six rarity tiers, lowest first. One colour per tier, used everywhere a rarity
-- shows (the catch vignette, the orb's glow and shake, the reveal pop, the Index frame, the
-- trail). Mythic's colour is the base of its rainbow.
--   rank 1 and 2 are baseline (yours at once); 3 and up need taming (Checklist decision pending).

export type Rarity = {
	id: string,
	displayName: string,
	rank: number,
	color: Color3,
}

local Rarities: { Rarity } = {
	{ id = "common", displayName = "Common", rank = 1, color = Color3.fromRGB(190, 196, 204) },
	{ id = "uncommon", displayName = "Uncommon", rank = 2, color = Color3.fromRGB(88, 214, 96) },
	{ id = "rare", displayName = "Rare", rank = 3, color = Color3.fromRGB(64, 156, 255) },
	{ id = "epic", displayName = "Epic", rank = 4, color = Color3.fromRGB(176, 92, 255) },
	{ id = "legendary", displayName = "Legendary", rank = 5, color = Color3.fromRGB(255, 196, 40) },
	{ id = "mythic", displayName = "Mythic", rank = 6, color = Color3.fromRGB(255, 84, 170) },
}

return Rarities
