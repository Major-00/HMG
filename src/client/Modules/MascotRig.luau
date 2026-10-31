--!strict
-- MascotRig: the placeholder Mascot model, shared by the catch reveal and the ballpark seats.
-- Round body and head in the species color, eyes, ears, feet, a disc in the rarity color, and a
-- mark for its variant (All-Star star, Gold Glove glove, Hall of Fame crown); Big and Giant are
-- drawn bigger. Built around a root at its feet, facing -Z of the root CFrame.
-- All parts are anchored and can't collide, be queried (so the camera never pops on them) or
-- be touched. `simple` drops the tummy and feet for the ballpark, where 80 can be on screen.
-- Final Mascot models replace this later; callers only use Build and Pose.
--   MascotRig.Build(mascot, simple?) -> Rig ({ model, pieces, carried, scale }) or nil
--   MascotRig.Pose(rig, root)        -> places every part around `root` (feet, facing -Z)
--   MascotRig.Scale(size)            -> how big a size is drawn (Tuning.Reveal.SIZE_SCALE)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Mascots = require(Config:WaitForChild("Mascots"))
local Tuning = require(Config:WaitForChild("Tuning"))

local MascotRig = {}

MascotRig.REACH = 1.45 -- studs (times the scale) in front of its feet where it holds a ball

export type Piece = { part: BasePart, offset: CFrame }
export type Rig = {
	model: Model,
	pieces: { Piece },
	carried: BasePart, -- a ball in its hands; hidden (Transparency 1) until shown by the caller
	scale: number,
}

local GOLD = Color3.fromRGB(255, 200, 60)
local EYE = Color3.new(0.08, 0.08, 0.1)
local CARRIED_BALL = Color3.fromRGB(250, 250, 245)

function MascotRig.Scale(size: string): number
	return Tuning.Reveal.SIZE_SCALE[size] or 1
end

-- `mascot` is { species, variant, size } (a saved MascotEntry or a Catch). Nil if the species
-- is unknown.
function MascotRig.Build(mascot: any, simple: boolean?): Rig?
	local species = Mascots.ById[mascot.species]
	if species == nil then
		return nil
	end
	local rarity = Mascots.Rarities[Mascots.RarityRank[species.rarity] or 1]
	local s = MascotRig.Scale(mascot.size)

	local model = Instance.new("Model")
	model.Name = species.id
	local pieces: { Piece } = {}

	local function piece(
		shape: Enum.PartType,
		size: Vector3,
		at: Vector3,
		color: Color3,
		material: Enum.Material?,
		rot: CFrame?
	): BasePart
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size * s
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = model
		table.insert(pieces, { part = p, offset = CFrame.new(at * s) * (rot or CFrame.identity) })
		return p
	end

	local body = species.color
	local light = body:Lerp(Color3.new(1, 1, 1), 0.45)
	local ball = Enum.PartType.Ball
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- stands a cylinder up
	piece(ball, Vector3.new(2.4, 2.4, 2.4), Vector3.new(0, 1.4, 0), body)
	piece(ball, Vector3.new(1.9, 1.9, 1.9), Vector3.new(0, 3.1, -0.1), body) -- head
	piece(ball, Vector3.new(0.38, 0.38, 0.38), Vector3.new(-0.38, 3.25, -0.9), EYE)
	piece(ball, Vector3.new(0.38, 0.38, 0.38), Vector3.new(0.38, 3.25, -0.9), EYE)
	piece(ball, Vector3.new(0.7, 0.7, 0.7), Vector3.new(-0.6, 4.0, 0), body) -- ears
	piece(ball, Vector3.new(0.7, 0.7, 0.7), Vector3.new(0.6, 4.0, 0), body)
	if not simple then
		piece(ball, Vector3.new(1.5, 1.5, 1.5), Vector3.new(0, 1.3, -0.55), light) -- tummy
		-- Feet: blocks, since Roblox makes every Ball part perfectly round.
		piece(Enum.PartType.Block, Vector3.new(0.8, 0.4, 1.1), Vector3.new(-0.55, 0.2, -0.15), light)
		piece(Enum.PartType.Block, Vector3.new(0.8, 0.4, 1.1), Vector3.new(0.55, 0.2, -0.15), light)
	end
	-- Plain color, not neon: neon washes out to white in daylight.
	local ring = piece(
		Enum.PartType.Cylinder,
		Vector3.new(0.1, 3.6, 3.6),
		Vector3.new(0, 0.06, 0),
		rarity.color,
		Enum.Material.SmoothPlastic,
		upright
	)
	ring.Transparency = 0.15

	if mascot.variant == "allStar" then
		piece(ball, Vector3.new(0.6, 0.6, 0.6), Vector3.new(0, 4.6, 0), GOLD, Enum.Material.Neon)
	elseif mascot.variant == "goldGlove" then
		piece(ball, Vector3.new(1, 1, 1), Vector3.new(1.15, 1.6, -0.6), GOLD, Enum.Material.Metal)
	elseif mascot.variant == "hallOfFame" then
		local crown = piece(
			Enum.PartType.Cylinder,
			Vector3.new(0.5, 1.5, 1.5),
			Vector3.new(0, 4.05, -0.1),
			GOLD,
			Enum.Material.Neon,
			upright
		)
		crown.Transparency = 0.1
	end

	local carried = piece(ball, Vector3.new(1, 1, 1), Vector3.new(0, 1.9, -MascotRig.REACH), CARRIED_BALL)
	carried.Transparency = 1
	return { model = model, pieces = pieces, carried = carried, scale = s }
end

function MascotRig.Pose(rig: Rig, root: CFrame)
	for _, piece in rig.pieces do
		piece.part.CFrame = root * piece.offset
	end
end

return MascotRig
