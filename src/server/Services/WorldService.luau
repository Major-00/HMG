--!strict
-- WorldService: builds the ballparks and the shared hitting zone at startup and gives each player
-- their own lane.
--   * workspace.HittingZone: one dirt strip across every lane (Tuning.World.HIT_ZONE, shared/HitZone)
--     with a chalk hit line at its front. Players walk anywhere and tap; the client starts the
--     ball inside the zone and flies it straight down +Z from the batter's X.
--   * Per lane: a batter spawn in the zone in front of the player's ballpark plot (Config/Park:
--     10 seat pads, an owner sign, upgrade spots) and a hidden StrikePoint at the lane's centre
--     on the hit line. The pad, plate and pitching machine are only built when the machine is the
--     default pitcher (Tuning.Pitch.DEFAULT_PITCHER); its pitches fly to the StrikePoint.
-- The lane model carries the owner (attribute "Owner") and what's seated ("Seats").
-- Lanes sit side by side along X. Lane models and the zone are Persistent so streaming never
-- hides them.
--   WorldService.GetLane(player)                  -> lane number or nil
--   WorldService.GetLandingPosition(player, dist) -> world position `dist` studs down the lane

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BatPose = require(ReplicatedStorage.Shared.BatPose)
local HitZone = require(ReplicatedStorage.Shared.HitZone)
local Park = require(ReplicatedStorage.Shared.Config.Park)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local FOLDER_NAME = "BattingAreas"
local ZONE_NAME = "HittingZone"
local DIRT = Color3.fromRGB(176, 132, 88)
local CHALK = Color3.fromRGB(245, 240, 230)
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

-- The ballpark plot behind the plate: a floor, a raised back row, 10 seat pads (each with a
-- "Spot" attachment the client seats a Mascot on), an owner sign, and spots for upgrades.
-- Nothing on it collides or can be queried, so it never blocks the player or the camera.
local function buildPlot(lane: Model, origin: Vector3)
	local L = Park.Layout
	local plot = Instance.new("Model")
	plot.Name = "Plot"

	local function flat(props: { [string]: any }): Part
		local p = part(props)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = plot
		return p
	end

	flat({
		Name = "Floor",
		Size = Vector3.new(L.FLOOR_WIDTH, 0.2, L.FLOOR_DEPTH),
		Position = origin + Vector3.new(0, 0.1, L.FLOOR_FRONT - L.FLOOR_DEPTH / 2),
		Color = Color3.fromRGB(86, 150, 78),
		Material = Enum.Material.Grass,
	})
	for rowIndex, row in L.ROWS do
		if row.height > 0 then
			flat({
				Name = `Riser{rowIndex}`,
				Size = Vector3.new(L.FLOOR_WIDTH - 2, row.height, 6),
				Position = origin + Vector3.new(0, row.height / 2 + 0.2, row.z),
				Color = Color3.fromRGB(150, 150, 160),
				Material = Enum.Material.Concrete,
			})
		end
	end

	local seats = Instance.new("Folder")
	seats.Name = "Seats"
	seats.Parent = plot
	local seat = 0
	for _, row in L.ROWS do
		for _, x in L.SEAT_X do
			seat += 1
			local pad = flat({
				Name = `Seat{seat}`,
				Size = L.SEAT_SIZE,
				Position = origin + Vector3.new(x, row.height + 0.2 + L.SEAT_SIZE.Y / 2, row.z),
				Color = Color3.fromRGB(200, 60, 60),
			})
			pad.Parent = seats
			local spot = Instance.new("Attachment")
			spot.Name = "Spot"
			-- On top of the pad, facing the field: a Mascot built facing -Z is turned to face +Z.
			spot.CFrame = CFrame.new(0, L.SEAT_SIZE.Y / 2, 0) * CFrame.Angles(0, math.pi, 0)
			spot.Parent = pad
		end
	end

	local post = flat({
		Name = "SignPost",
		Size = Vector3.new(0.6, L.SIGN_HEIGHT, 0.6),
		Position = origin + Vector3.new(0, L.SIGN_HEIGHT / 2 + 0.2, L.SIGN_Z),
		Color = Color3.fromRGB(110, 80, 50),
		Material = Enum.Material.Wood,
	})
	-- Behind the back row and above everyone's heads, so it never covers a Mascot.
	local sign = Instance.new("BillboardGui")
	sign.Name = "OwnerSign"
	sign.Size = UDim2.fromScale(9, 1.8) -- in studs, so it shrinks with distance like the park
	sign.StudsOffset = Vector3.new(0, L.SIGN_HEIGHT / 2 + 1.5, 0)
	sign.MaxDistance = 120
	sign.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Owner"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	label.BackgroundTransparency = 0.25
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = "Open ballpark"
	label.Parent = sign
	Instance.new("UICorner").Parent = label
	sign.Parent = post

	-- Upgrade1..5 attachments on the floor mark where park upgrades will stand.
	local floor = plot:FindFirstChild("Floor") :: BasePart
	for i, at in L.UPGRADE_SPOTS do
		local marker = Instance.new("Attachment")
		marker.Name = `Upgrade{i}`
		marker.Parent = floor
		marker.WorldPosition = origin + at
	end

	plot.Parent = lane
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
end

-- The shared hitting zone: a dirt strip you can stand on, plus the chalk hit line at its front.
local function buildHittingZone(): Model
	local zone = Tuning.World.HIT_ZONE
	local width = 2 * (HitZone.halfWidth() + 2)
	local depth = zone.front - zone.back
	local model = Instance.new("Model")
	model.Name = ZONE_NAME
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	part({
		Name = "Dirt",
		Size = Vector3.new(width, 1, depth),
		Position = Vector3.new(0, -0.5, zone.back + depth / 2), -- top at Y = 0
		Color = DIRT,
		Parent = model,
	})
	part({
		Name = "HitLine",
		Size = Vector3.new(width, 0.05, 0.5),
		Position = Vector3.new(0, 0.03, zone.front - 0.25),
		Color = CHALK,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	return model
end

local function buildLane(lane: number): Model
	local w = Tuning.World
	local origin = plateOrigin(lane)
	local facing = CFrame.lookAt(origin, origin + Vector3.zAxis) -- looks down the field (+Z)
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
		-- Dirt from the hit line out to the machine, and a plate under the strike point.
		local padFront = w.PITCH_DISTANCE + 7
		part({
			Name = "Pad",
			Size = Vector3.new(18, 1, padFront),
			Position = origin + Vector3.new(0, -0.5, padFront / 2),
			Color = DIRT,
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
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "BatterSpawn"
	spawn.Anchored = true
	spawn.CastShadow = false
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Size = Vector3.new(4, 0.2, 4)
	-- In the zone, in front of the player's own plot (local -Z is down the field).
	spawn.CFrame = facing * CFrame.new(0, 0.1, -(w.HIT_ZONE.back + 5))
	spawn.Color = Color3.fromRGB(120, 90, 60)
	spawn.Duration = 0 -- no spawn forcefield
	spawn.Neutral = true
	spawn.Parent = model

	if useMachine then
		buildPitchingMachine(model, origin)
	end
	buildPlot(model, origin)
	return model
end

local function setOwnerSign(lane: number, text: string)
	local label = laneModels[lane]:FindFirstChild("Owner", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function assignLane(player: Player)
	for lane = 1, #laneModels do
		if laneOwner[lane] == nil then
			laneOwner[lane] = player
			playerLane[player] = lane
			player:SetAttribute("Lane", lane)
			player.RespawnLocation = laneModels[lane]:FindFirstChild("BatterSpawn") :: SpawnLocation
			laneModels[lane]:SetAttribute("Owner", player.UserId)
			setOwnerSign(lane, `{player.DisplayName}'s Ballpark`)
			return
		end
	end
	-- They still swing normally (the ball flies from their own X); the client shows a toast.
	player:SetAttribute("Lane", nil)
	warn(`[WorldService] No free lane for {player.Name}; raise Tuning.World.LANE_COUNT or lower max players`)
end

local function releaseLane(player: Player)
	local lane = playerLane[player]
	playerLane[player] = nil
	if lane and laneOwner[lane] == player then
		laneOwner[lane] = nil
		local model = laneModels[lane]
		model:SetAttribute("Owner", nil)
		model:SetAttribute("Seats", nil) -- empties the park for everyone
		model:SetAttribute("Park", nil)
		setOwnerSign(lane, "Open ballpark")
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
	local barrel =
		batPart("BatBarrel", BatPose.BARREL_LENGTH, BatPose.BARREL_WIDTH, Color3.fromRGB(200, 155, 95))

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

-- Publishes what sits in a player's ballpark seats (a short encoded string, see ParkService) on
-- their lane model, so every client can draw every park. Display only.
function WorldService.SetParkSeats(player: Player, encoded: string)
	local lane = playerLane[player]
	if lane and laneOwner[lane] == player then
		laneModels[lane]:SetAttribute("Seats", encoded)
	end
end

-- Publishes a player's park upgrade levels (see ParkService) on their lane model. Display only.
function WorldService.SetParkLevels(player: Player, encoded: string)
	local lane = playerLane[player]
	if lane and laneOwner[lane] == player then
		laneModels[lane]:SetAttribute("Park", encoded)
	end
end

-- The lane-centre approximation of where a hit lands. The client flies the ball from the
-- batter's own X; the server never uses (or checks) the client's position.
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
	buildHittingZone().Parent = workspace
end

function WorldService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(releaseLane)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return WorldService
