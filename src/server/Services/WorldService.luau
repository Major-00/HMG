--!strict
-- WorldService: gives each player a batting lane and puts them on the island map.
--   * Lanes sit side by side along X across the launch strip (Tuning.World). The client starts
--     the ball inside the strip (shared/HitZone) and flies it straight down +Z from the batter's X.
--     Each lane has a hidden StrikePoint on the hit line; the pitching machine (when it's the
--     pitcher, Tuning.Pitch.DEFAULT_PITCHER) gets its pad, plate and machine.
--   * Everyone spawns on the hub overlook: the map's "Spawn" marker under Workspace.Map. Until the
--     map is in the place, a plain test pad stands at the launch strip so the swing still plays.
--   * Every character gets the placeholder bat the swing animations move.
-- Lane models are Persistent so streaming never hides them.
--   WorldService.GetLane(player)                  -> lane number or nil
--   WorldService.GetLandingPosition(player, dist) -> world position `dist` studs down the lane

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BatPose = require(ReplicatedStorage.Shared.BatPose)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local FOLDER_NAME = "BattingAreas"
local TEST_PAD_NAME = "TestPad"
local BAT_NAME = "Bat"

local WorldService = {}

local laneModels: { Model } = {}
local laneOwner: { [number]: Player } = {}
local playerLane: { [Player]: number } = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function plateOrigin(lane: number): Vector3
	local w = Tuning.World
	return Vector3.new((lane - (w.LANE_COUNT + 1) / 2) * w.LANE_SPACING, 0, 0)
end

-- The map's spawn on the hub overlook, facing the lane; or, with no map yet, the middle of the
-- launch strip.
local function spawnCFrame(): CFrame
	local map = workspace:FindFirstChild("Map")
	local marker = map and map:FindFirstChild("Spawn", true)
	if marker and marker:IsA("BasePart") then
		return CFrame.lookAt(marker.Position, marker.Position + Vector3.zAxis)
	end
	local zone = Tuning.World.HIT_ZONE
	local at = Vector3.new(0, 0.1, (zone.back + zone.front) / 2)
	return CFrame.lookAt(at, at + Vector3.zAxis)
end

-- A plain floor under the launch strip, only while the place has no map.
local function buildTestPad(): Part?
	if workspace:FindFirstChild("Map") then
		return nil
	end
	return part({
		Name = TEST_PAD_NAME,
		Size = Vector3.new(60, 1, 60),
		Position = Vector3.new(0, -0.5, -20), -- top at Y = 0, the hit line's height
		Color = Color3.fromRGB(150, 155, 165),
	})
end

-- The pitching machine (a "throw" pitcher, not the default): the machine and its release point.
local function buildPitchingMachine(model: Model, origin: Vector3)
	local w = Tuning.World
	local machine = Instance.new("Model")
	machine.Name = "PitchingMachine"
	local machineAt = origin + Vector3.new(0, 0, w.PITCH_DISTANCE)
	part({
		Name = "Base",
		Size = Vector3.new(3, 2.5, 3),
		Position = machineAt + Vector3.new(0, 1.25, 0),
		Color = Color3.fromRGB(90, 96, 110),
		Parent = machine,
	})
	local barrel = part({
		Name = "Barrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.5, 1.2, 1.2),
		-- Cylinders run along X; turn it to run along Z, pointing at the plate.
		CFrame = CFrame.new(machineAt + Vector3.new(0, w.STRIKE_HEIGHT, -1)) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(240, 140, 40),
		Parent = machine,
	})
	local release = Instance.new("Attachment")
	release.Name = "ReleasePoint"
	release.Parent = barrel
	release.WorldPosition = machineAt + Vector3.new(0, w.STRIKE_HEIGHT, -2.4)
	machine.Parent = model
end

local function buildLane(lane: number): Model
	local w = Tuning.World
	local origin = plateOrigin(lane)
	local useMachine = Tuning.Pitch.DEFAULT_PITCHER == "pitching_machine"

	local model = Instance.new("Model")
	model.Name = `Lane{lane}`
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("Lane", lane)

	-- The lane's centre on the hit line: the machine's pitches fly here. Hidden, so it's on an
	-- invisible anchor that never collides or blocks the camera.
	local anchor = part({
		Name = "StrikeAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = origin,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	local strike = Instance.new("Attachment")
	strike.Name = "StrikePoint"
	strike.Parent = anchor
	strike.WorldPosition = origin + Vector3.new(0, w.STRIKE_HEIGHT, 0)

	if useMachine then
		local padFront = w.PITCH_DISTANCE + 7
		part({
			Name = "Pad",
			Size = Vector3.new(18, 1, padFront),
			Position = origin + Vector3.new(0, -0.5, padFront / 2),
			Color = Color3.fromRGB(150, 155, 165),
			Parent = model,
		})
		part({
			Name = "Plate",
			Size = Vector3.new(2.5, 0.2, 2.5),
			Position = origin + Vector3.new(0, 0.1, 0),
			Color = Color3.fromRGB(245, 245, 245),
			CanCollide = false,
			Parent = model,
		})
		buildPitchingMachine(model, origin)
	end

	-- Every lane spawns at the same place; the pad is invisible so whatever is under it shows.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "BatterSpawn"
	spawn.Anchored = true
	spawn.CastShadow = false
	spawn.Size = Vector3.new(4, 0.2, 4)
	spawn.CFrame = spawnCFrame()
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0 -- no spawn forcefield
	spawn.Neutral = true
	spawn.Parent = model
	return model
end

local function assignLane(player: Player)
	for lane = 1, #laneModels do
		if laneOwner[lane] == nil then
			laneOwner[lane] = player
			playerLane[player] = lane
			player:SetAttribute("Lane", lane)
			player.RespawnLocation = laneModels[lane]:FindFirstChild("BatterSpawn") :: SpawnLocation
			return
		end
	end
	-- They still swing normally (the ball flies from their own X).
	player:SetAttribute("Lane", nil)
	warn(`[WorldService] No free lane for {player.Name}; raise Tuning.World.LANE_COUNT or lower max players`)
end

local function releaseLane(player: Player)
	local lane = playerLane[player]
	playerLane[player] = nil
	if lane and laneOwner[lane] == player then
		laneOwner[lane] = nil
	end
end

-- Placeholder bat in the right hand: a handle plus a thicker barrel, held up over the right
-- shoulder (BatPose.READY) so it's visible from the camera behind the batter.
-- Cosmetic; the client swings it locally.
local function batPart(name: string, length: number, width: number, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, width, width)
	p.Color = color
	p.Material = Enum.Material.Wood
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	return p
end

local function giveBat(character: Model)
	local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
	if hand == nil or not hand:IsA("BasePart") then
		return
	end
	local handle = batPart(BAT_NAME, BatPose.HANDLE_LENGTH, BatPose.HANDLE_WIDTH, Color3.fromRGB(120, 80, 45))
	local barrel = batPart("BatBarrel", BatPose.BARREL_LENGTH, BatPose.BARREL_WIDTH, Color3.fromRGB(200, 155, 95))

	local join = Instance.new("Weld")
	join.Part0 = handle
	join.Part1 = barrel
	join.C0 = CFrame.new((BatPose.HANDLE_LENGTH + BatPose.BARREL_LENGTH) / 2 - 0.1, 0, 0)
	join.Parent = barrel

	-- A Motor6D, so the swing animations can move the bat (a pose named "Bat" under RightHand).
	local grip = Instance.new("Motor6D")
	grip.Name = "BatGrip"
	grip.Part0 = hand
	grip.Part1 = handle
	grip.C0 = BatPose.grip(BatPose.READY, hand.Name == "Right Arm")
	grip.Parent = handle

	-- The client's swing trail runs between these (along the bat, +X is toward the tip).
	local tipX = (BatPose.HANDLE_LENGTH + BatPose.BARREL_LENGTH) / 2 - 0.1 + BatPose.BARREL_LENGTH / 2
	local trailBase = Instance.new("Attachment")
	trailBase.Name = "TrailBase"
	trailBase.Position = Vector3.new((tipX - BatPose.HANDLE_LENGTH / 2) / 2, 0, 0) -- mid-bat
	trailBase.Parent = handle
	local trailTip = Instance.new("Attachment")
	trailTip.Name = "TrailTip"
	trailTip.Position = Vector3.new(tipX, 0, 0)
	trailTip.Parent = handle

	handle.Parent = character
	barrel.Parent = character
end

local function onCharacterAdded(player: Player, character: Model)
	-- Backup for the spawn: if the character didn't appear there, move it there.
	local lane = playerLane[player]
	if lane then
		local spawn = laneModels[lane]:FindFirstChild("BatterSpawn") :: BasePart
		task.defer(function()
			if character.Parent and (character:GetPivot().Position - spawn.Position).Magnitude > 8 then
				character:PivotTo(spawn.CFrame * CFrame.new(0, 3, 0))
			end
		end)
	end
	giveBat(character)
end

local function onPlayerAdded(player: Player)
	assignLane(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

function WorldService.GetLane(player: Player): number?
	return playerLane[player]
end

-- The lane-centre approximation of where a hit lands. The client flies the ball from the
-- batter's own X; the server never uses (or checks) the client's position.
function WorldService.GetLandingPosition(player: Player, distance: number): Vector3
	local lane = playerLane[player] or 1
	return plateOrigin(lane) + Vector3.new(0, 0, distance)
end

function WorldService.Init()
	local pad = buildTestPad()
	if pad then
		pad.Parent = workspace
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for lane = 1, Tuning.World.LANE_COUNT do
		local model = buildLane(lane)
		model.Parent = folder
		laneModels[lane] = model
	end
	folder.Parent = workspace
end

function WorldService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(releaseLane)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return WorldService
