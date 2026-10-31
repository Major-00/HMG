--!strict
-- Park: each lane's ballpark plot. It sits behind home plate (toward -Z), like stands behind
-- the plate, with its seats facing the field. Positions are relative to the lane's home plate.
-- The camera never pops on it: plot parts can't be queried.
-- Park upgrades (Bleachers, Concessions, Scoreboard, Lights, Jumbotron) come in a later step and
-- use the reserved UPGRADE_SPOTS.

local Park = {}

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
	-- Where the five park upgrades will stand (x, z), around the edge of the plot.
	UPGRADE_SPOTS = {
		Vector3.new(-12, 0, -40),
		Vector3.new(-6, 0, -42),
		Vector3.new(0, 0, -43),
		Vector3.new(6, 0, -42),
		Vector3.new(12, 0, -40),
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
