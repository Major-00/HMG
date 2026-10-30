--!strict
-- WorldService: builds the batting lanes at startup and gives each player their own lane.
-- A lane is a dirt pad, a home plate, a batter spawn, and a pitching machine.
-- Lanes sit side by side along X; every ball flies along +Z from its lane's plate.
-- Lane models are Persistent so streaming never hides a player's plate or machine.
--   WorldService.GetLane(player)                  -> lane number or nil
--   WorldService.GetLandingPosition(player, dist) -> world position `dist` studs down the lane

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local FOLDER_NAME = "BattingAreas"
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

local function buildLane(lane: number): Model
	local w = Tuning.World
	local origin = plateOrigin(lane)
	local facing = CFrame.lookAt(origin, origin + Vector3.zAxis) -- looks down the field (+Z)

	local model = Instance.new("Model")
	model.Name = `Lane{lane}`
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("Lane", lane)

	part({
		Name = "Pad",
		Size = Vector3.new(16, 1, w.PITCH_DISTANCE + 14),
		Position = origin + Vector3.new(0, -0.5, w.PITCH_DISTANCE / 2),
		Color = Color3.fromRGB(176, 132, 88),
		Parent = model,
	})

	local plate = part({
		Name = "Plate",
		Size = Vector3.new(2.5, 0.2, 2.5),
		Position = origin + Vector3.new(0, 0.1, 0),
		Color = Color3.fromRGB(245, 245, 245),
		CanCollide = false,
		Parent = model,
	})
	local strike = Instance.new("Attachment")
	strike.Name = "StrikePoint"
	strike.Parent = plate
	strike.WorldPosition = origin + Vector3.new(0, w.STRIKE_HEIGHT, 0)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "BatterSpawn"
	spawn.Anchored = true
	spawn.CastShadow = false
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Size = Vector3.new(4, 0.2, 4)
	spawn.CFrame = facing * CFrame.new(-2.5, 0.1, 3) -- beside and just behind the plate
	spawn.Color = Color3.fromRGB(120, 90, 60)
	spawn.Duration = 0 -- no spawn forcefield
	spawn.Neutral = true
	spawn.Parent = model

	-- Pitching machine: the default pitcher. Hidden by the client when another pitcher is active.
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
		CFrame = CFrame.new(machineAt + Vector3.new(0, w.STRIKE_HEIGHT, -1))
			* CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(240, 140, 40),
		Parent = machine,
	})
	local release = Instance.new("Attachment")
	release.Name = "ReleasePoint"
	release.Parent = barrel
	release.WorldPosition = machineAt + Vector3.new(0, w.STRIKE_HEIGHT, -2.4)
	machine.Parent = model

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
	warn(`[WorldService] No free lane for {player.Name}; raise Tuning.World.LANE_COUNT or lower max players`)
end

local function releaseLane(player: Player)
	local lane = playerLane[player]
	playerLane[player] = nil
	if lane and laneOwner[lane] == player then
		laneOwner[lane] = nil
	end
end

-- Placeholder bat in the right hand. Cosmetic; the client swings it locally.
local function giveBat(character: Model)
	local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
	if hand == nil or not hand:IsA("BasePart") then
		return
	end
	local bat = Instance.new("Part")
	bat.Name = BAT_NAME
	bat.Size = Vector3.new(0.35, 3, 0.35)
	bat.Color = Color3.fromRGB(150, 105, 60)
	bat.Material = Enum.Material.SmoothPlastic
	bat.CanCollide = false
	bat.CanQuery = false
	bat.CanTouch = false
	bat.Massless = true
	bat.CastShadow = false
	local weld = Instance.new("Weld")
	weld.Name = "BatGrip"
	weld.Part0 = hand
	weld.Part1 = bat
	weld.C0 = CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(-60), 0, 0) * CFrame.new(0, 1.4, 0)
	weld.Parent = bat
	bat.Parent = character
end

local function onCharacterAdded(player: Player, character: Model)
	-- Backup for the spawn: if the character didn't appear on its lane, move it there.
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

function WorldService.GetLandingPosition(player: Player, distance: number): Vector3
	local lane = playerLane[player] or 1
	return plateOrigin(lane) + Vector3.new(0, 0, distance)
end

function WorldService.Init()
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
