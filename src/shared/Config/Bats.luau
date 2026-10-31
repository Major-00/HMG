--!strict
-- Bats: bought with Cash, in order. Buying one equips it; any bat you own can be equipped again.
-- A bat multiplies the Power each hit gives (Formulas.multiplier), so it also makes distance
-- grow faster. Bats reset on stadium promotion. Never sold for Robux.
-- Names are original placeholders.

export type Bat = {
	id: string,
	displayName: string,
	price: number, -- Cash; 0 = owned from the start
	powerMultiplier: number,
}

local Bats = {}

Bats.List = {
	{ id = "starter", displayName = "Sandlot Stick", price = 0, powerMultiplier = 1 },
	{ id = "maple", displayName = "Maple Bat", price = 300, powerMultiplier = 1.5 },
	{ id = "ash", displayName = "Ash Bat", price = 3000, powerMultiplier = 2.5 },
	{ id = "aluminum", displayName = "Aluminum Bat", price = 30000, powerMultiplier = 4 },
	{ id = "carbon", displayName = "Carbon Bat", price = 300000, powerMultiplier = 7 },
	{ id = "titanium", displayName = "Titanium Bat", price = 3000000, powerMultiplier = 12 },
} :: { Bat }

-- id -> bat, and id -> position in List.
Bats.ById = {} :: { [string]: Bat }
Bats.Order = {} :: { [string]: number }
for i, bat in Bats.List do
	Bats.ById[bat.id] = bat
	Bats.Order[bat.id] = i
end

return Bats
