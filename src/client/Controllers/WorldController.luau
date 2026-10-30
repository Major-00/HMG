--!strict
-- WorldController: builds the biome field on the client from Config/Biomes, streamed around the
-- camera so only a few hundred studs exist at once (cheap on low-end phones).
--   * Each biome's stretch is cut into ground tiles (Tuning.World.TILE_LENGTH) starting at its own
--     start, so a tile never straddles a biome line. A tile is the field ground across every lane,
--     a side band on each side, and a few props in the bands (placed from the tile number, so the
--     same tile always looks the same).
--   * Each biome after the first gets a start line and two gate posts in its accent color.
--   * Landmarks are cloned from ReplicatedStorage.Landmarks, one per biome, when near the camera.
--   * Lighting and the Atmosphere blend to the biome under the camera.
-- Visual only: nothing here touches stats. Parts are pooled and reused.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Biomes = require(Config:WaitForChild("Biomes"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local HookTypes = require(Shared:WaitForChild("HookTypes"))
local Tuning = require(Config:WaitForChild("Tuning"))

local GROUND_TOP = -0.05 -- just under the batting pads (top at 0) so they don't flicker
local GROUND_THICKNESS = 1
local LINE_DEPTH = 2
local POST_SIZE = Vector3.new(3, 22, 3)
local WINDOW_STEP = 50 -- rebuild the tile set when the camera moves this far

type Tile = {
	parts: { BasePart },
	props: { { key: string, model: Model } },
}

local WorldController = {}

local folder: Folder
local landmarkSource: Instance?
local partPool: { BasePart } = {}
local propPools: { [string]: { Model } } = {}
local tiles: { [string]: Tile } = {}
local landmarks: { [number]: Model } = {}
local lastWindow: number? = nil
local currentBiome: number? = nil
local atmosphere: Atmosphere

local W = Tuning.World
local HALF_FIELD = (W.LANE_COUNT - 1) / 2 * W.LANE_SPACING + W.LANE_SPACING / 2 + W.FIELD_MARGIN

local function setPlain(p: BasePart)
	p.Anchored = true
	p.CastShadow = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

local function takePart(): Part
	local p = table.remove(partPool) :: Part?
	if p == nil then
		local fresh = Instance.new("Part")
		setPlain(fresh)
		return fresh
	end
	return p
end

local function placePart(
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	collide: boolean
): Part
	local p = takePart()
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.CanCollide = collide
	p.Parent = folder
	return p
end

-- Builds a prop model from its pieces, pivoted at its ground point.
local function buildProp(prop: HookTypes.Prop): Model
	local model = Instance.new("Model")
	for _, piece in prop do
		local p: BasePart
		if piece.shape == "Wedge" then
			p = Instance.new("WedgePart")
		else
			local part = Instance.new("Part")
			part.Shape = if piece.shape == "Ball"
				then Enum.PartType.Ball
				elseif piece.shape == "Cylinder" then Enum.PartType.Cylinder
				else Enum.PartType.Block
			p = part
		end
		setPlain(p)
		p.CanCollide = false
		p.Size = piece.size
		p.Color = piece.color
		p.Material = piece.material or Enum.Material.SmoothPlastic
		local rot = piece.rot or Vector3.zero
		p.CFrame = CFrame.new(piece.offset) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
		p.Parent = model
	end
	model.WorldPivot = CFrame.new()
	return model
end

local function takeProp(biomeIndex: number, propIndex: number): (string, Model)
	local key = `{biomeIndex}:{propIndex}`
	local pool = propPools[key]
	local model = pool and table.remove(pool)
	if model == nil then
		model = buildProp(Biomes[biomeIndex].visual.props[propIndex])
	end
	return key, model :: Model
end

local function biomeStart(index: number): number
	return if index == 1 then -W.BEHIND_PLATE else Tuning.BiomeStarts[index]
end

local function biomeEnd(index: number): number
	return Tuning.BiomeStarts[index + 1] or math.huge
end

local function buildTile(biomeIndex: number, k: number): Tile
	local visual = Biomes[biomeIndex].visual
	local z0 = biomeStart(biomeIndex) + k * W.TILE_LENGTH
	local z1 = math.min(z0 + W.TILE_LENGTH, biomeEnd(biomeIndex))
	local length = z1 - z0
	local midZ = (z0 + z1) / 2
	local y = GROUND_TOP - GROUND_THICKNESS / 2
	local tile: Tile = { parts = {}, props = {} }

	table.insert(
		tile.parts,
		placePart(
			Vector3.new(HALF_FIELD * 2, GROUND_THICKNESS, length),
			CFrame.new(0, y, midZ),
			visual.ground,
			visual.material,
			true
		)
	)
	for _, side in { -1, 1 } do
		table.insert(
			tile.parts,
			placePart(
				Vector3.new(W.PROP_BAND, GROUND_THICKNESS, length),
				CFrame.new(side * (HALF_FIELD + W.PROP_BAND / 2), y, midZ),
				visual.side,
				visual.sideMaterial,
				true
			)
		)
	end

	-- Start line and gate posts where this biome begins.
	if k == 0 and biomeIndex > 1 then
		table.insert(
			tile.parts,
			placePart(
				Vector3.new(HALF_FIELD * 2, 0.2, LINE_DEPTH),
				CFrame.new(0, GROUND_TOP + 0.1, z0 + LINE_DEPTH / 2),
				visual.accent,
				Enum.Material.Neon,
				false
			)
		)
		for _, side in { -1, 1 } do
			table.insert(
				tile.parts,
				placePart(
					POST_SIZE,
					CFrame.new(side * (HALF_FIELD + POST_SIZE.X / 2), POST_SIZE.Y / 2, z0 + LINE_DEPTH / 2),
					visual.accent,
					Enum.Material.SmoothPlastic,
					false
				)
			)
		end
	end

	-- Props: same tile number, same layout every time.
	local rng = Random.new(biomeIndex * 7919 + k * 104729)
	local count = rng:NextInteger(1, W.PROPS_PER_TILE)
	for i = 1, count do
		local propIndex = rng:NextInteger(1, #visual.props)
		local key, model = takeProp(biomeIndex, propIndex)
		local side = if i % 2 == 0 then -1 else 1
		local x = side * (HALF_FIELD + rng:NextNumber(8, W.PROP_BAND - 8))
		local z = rng:NextNumber(z0 + 5, math.max(z1 - 5, z0 + 5))
		model:PivotTo(CFrame.new(x, GROUND_TOP, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
		model.Parent = folder
		table.insert(tile.props, { key = key, model = model })
	end
	return tile
end

local function releaseTile(tile: Tile)
	for _, p in tile.parts do
		p.Parent = nil
		table.insert(partPool, p)
	end
	for _, entry in tile.props do
		entry.model.Parent = nil
		local pool = propPools[entry.key]
		if pool == nil then
			pool = {}
			propPools[entry.key] = pool
		end
		table.insert(pool, entry.model)
	end
end

local function landmarkFor(index: number): Model?
	local existing = landmarks[index]
	if existing then
		return existing
	end
	local source = landmarkSource and landmarkSource:FindFirstChild(Biomes[index].landmark)
	if source == nil or not source:IsA("Model") then
		return nil
	end
	local model = source:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CastShadow = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	-- Stand it on the ground, outside the field's right edge.
	local z = Tuning.BiomeStarts[index] + W.LANDMARK_OFFSET_Z
	local x = HALF_FIELD + W.LANDMARK_SIDE
	model:PivotTo(CFrame.new(x, 0, z))
	local box, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, GROUND_TOP - (box.Position.Y - size.Y / 2), 0))
	landmarks[index] = model
	return model
end

-- Adds every tile overlapping [zMin, zMax] to `wanted`.
local function addTiles(wanted: { [string]: { number } }, zMin: number, zMax: number)
	for i = 1, #Biomes do
		local s, e = biomeStart(i), biomeEnd(i)
		if zMax >= s and zMin < e then
			local kFrom = math.max(0, math.floor((zMin - s) / W.TILE_LENGTH))
			local kTo = math.floor((math.min(zMax, e - 0.001) - s) / W.TILE_LENGTH)
			for k = kFrom, kTo do
				wanted[`{i}:{k}`] = { i, k }
			end
		end
	end
end

-- Keeps the tiles and landmarks inside [zMin, zMax] built, plus the ground around the batting
-- lanes at all times: players stand on it, so it must not vanish while the camera is away.
local function stream(zMin: number, zMax: number)
	local wanted: { [string]: { number } } = {}
	addTiles(wanted, zMin, zMax)
	addTiles(wanted, -W.BEHIND_PLATE, W.PITCH_DISTANCE + W.TILE_LENGTH / 2)

	for key, tile in tiles do
		if wanted[key] == nil then
			releaseTile(tile)
			tiles[key] = nil
		end
	end
	for key, pair in wanted do
		if tiles[key] == nil then
			tiles[key] = buildTile(pair[1], pair[2])
		end
	end

	for i = 1, #Biomes do
		local z = Tuning.BiomeStarts[i] + W.LANDMARK_OFFSET_Z
		local inside = z >= zMin and z <= zMax
		local model = if inside then landmarkFor(i) else landmarks[i]
		if model then
			model.Parent = if inside then folder else nil
		end
	end
end

local function applyLighting(index: number, instant: boolean)
	local l = Biomes[index].visual.lighting
	local info = TweenInfo.new(if instant then 0 else W.LIGHTING_TWEEN, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, {
		ClockTime = l.clockTime,
		Brightness = l.brightness,
		Ambient = l.ambient,
		OutdoorAmbient = l.outdoorAmbient,
	}):Play()
	TweenService:Create(atmosphere, info, {
		Color = l.atmosphereColor,
		Decay = l.atmosphereDecay,
		Density = l.density,
		Haze = l.haze,
	}):Play()
end

local function step()
	local z = workspace.CurrentCamera.CFrame.Position.Z

	local window = math.floor(z / WINDOW_STEP)
	if window ~= lastWindow then
		lastWindow = window
		local base = window * WINDOW_STEP
		stream(base - W.STREAM_BEHIND, base + WINDOW_STEP + W.STREAM_AHEAD)
	end

	local biome = Formulas.biomeIndexAt(math.max(z, 0))
	if biome ~= currentBiome then
		applyLighting(biome, currentBiome == nil)
		currentBiome = biome
	end
end

function WorldController.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientWorld"
	folder.Parent = workspace

	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then
		atmosphere = existing
	else
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
end

function WorldController.Start()
	landmarkSource = ReplicatedStorage:WaitForChild("Landmarks", 10)
	if landmarkSource == nil then
		warn("[WorldController] ReplicatedStorage.Landmarks is missing; biomes will have no landmarks")
	end
	-- After the camera (and ball-cam) so streaming follows this frame's camera.
	RunService:BindToRenderStep("WorldStream", Enum.RenderPriority.Camera.Value + 2, step)
end

return WorldController
