--!strict
-- Park: each lane's ballpark plot. It sits behind home plate (toward -Z), like stands behind
-- the plate, with its seats facing the field. Positions are relative to the lane's home plate.
-- The camera never pops on it: plot parts can't be queried.
-- Park upgrades (Upgrades below) are bought with Cash in the Shop's Park tab; each level adds to
-- the park's Cash rate (Formulas.parkMultiplier), online and offline, and its prop on the plot
-- grows. They reset on stadium promotion. Never sold for Robux.

export type Upgrade = {
	id: string, -- key in the save's `park`
	displayName: string,
	baseCost: number, -- Cash for level 1
	costGrowth: number, -- each next level costs this many times more
	bonusPerLevel: number, -- added to the park multiplier per level (0.05 = +5%)
}

local Park = {}

Park.MAX_LEVEL = 10

-- In order: Upgrades[i] stands on Layout.UPGRADE_SPOTS[i].
Park.Upgrades = {
	{ id = "bleachers", displayName = "Bleachers", baseCost = 200, costGrowth = 1.8, bonusPerLevel = 0.05 },
	{
		id = "concessions",
		displayName = "Concessions",
		baseCost = 1000,
		costGrowth = 1.85,
		bonusPerLevel = 0.08,
	},
	{
		id = "scoreboard",
		displayName = "Scoreboard",
		baseCost = 5000,
		costGrowth = 1.9,
		bonusPerLevel = 0.12,
	},
	{ id = "lights", displayName = "Lights", baseCost = 25000, costGrowth = 1.95, bonusPerLevel = 0.18 },
	{ id = "jumbotron", displayName = "Jumbotron", baseCost = 120000, costGrowth = 2, bonusPerLevel = 0.25 },
} :: { Upgrade }

Park.UpgradeById = {} :: { [string]: Upgrade }
for _, upgrade in Park.Upgrades do
	Park.UpgradeById[upgrade.id] = upgrade
end

Park.Layout = {
	SEAT_COUNT = 10, -- must match the save's seats (Template)
	FLOOR_FRONT = -22, -- studs behind the plate where the plot starts ...
	FLOOR_DEPTH = 24, -- ... and how deep it is
	FLOOR_WIDTH = 26, -- fits inside the 30-stud lane spacing
	-- Two rows of five, the back row raised, all facing the field (+Z).
	ROWS = {
		{ z = -27, height = 0 },
		{ z = -34, height = 2 },
	},
	SEAT_X = { -10.4, -5.2, 0, 5.2, 10.4 }, -- wide enough that even Giants' bodies don't touch
	SEAT_SIZE = Vector3.new(3.6, 0.4, 3.6),
	SIGN_Z = -38.5, -- the owner sign: behind the back row ...
	SIGN_HEIGHT = 9, -- ... on a post this tall, so it shows above the Mascots
	-- Where each park upgrade stands (x, z), in Upgrades order: Bleachers and Concessions at the
	-- plot's back corners; Scoreboard, Lights and the Jumbotron just behind the plot (the ground
	-- there is free), the Jumbotron in the middle and raised above the owner sign.
	UPGRADE_SPOTS = {
		Vector3.new(-8.5, 0, -41),
		Vector3.new(8.5, 0, -41),
		Vector3.new(-9, 0, -49),
		Vector3.new(9, 0, -49),
		Vector3.new(0, 0, -47),
	},
}

-- Client drawing of seated Mascots (visual only).
Park.Draw = {
	DISTANCE = 140, -- parks farther than this from the camera aren't drawn
	CHECK_EVERY = 0.4, -- seconds between distance checks
	TAG_DISTANCE = 60, -- Cash/s tags only show within this distance
	IDLE_BOB = 0.25, -- studs your own Mascots bob while idle (off in low graphics)
	IDLE_SPEED = 2.2,
}

return Park
