--!strict
-- ParkController: draws the Mascots seated in every lane's ballpark (from the lane model's
-- "Seats" attribute, published by the server's ParkService), so you see your park and everyone
-- else's. Display only.
--   * Only seats whose Mascot changed are rebuilt (MascotRig, the simple version).
--   * Each Mascot has a small Cash/s tag (its own earning, before park and stadium bonuses),
--     shown only up close.
--   * Parks far from the camera aren't drawn at all (Config/Park Draw.DISTANCE), which also
--     hides them during long ball-cam flights.
--   * Your own Mascots bob gently while idle, unless low graphics is on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Format = require(Shared:WaitForChild("Format"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Park = require(Config:WaitForChild("Park"))

local StateController = require(script.Parent.StateController)
local MascotRig = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("MascotRig"))

local player = Players.LocalPlayer

type SeatView = {
	key: string, -- "species,variant,size", or "" when empty
	rig: MascotRig.Rig?,
	base: CFrame, -- where the Mascot stands on this seat
}

type ParkView = {
	model: Model,
	center: Vector3,
	folder: Folder, -- holds this park's Mascots; parented only while near the camera
	seats: { SeatView },
}

local ParkController = {}

local parks: { [Model]: ParkView } = {}
local root: Folder
local wasBobbing = false

local function makeTag(rig: MascotRig.Rig, cashPerSec: number)
	local body = rig.pieces[1].part
	local tag = Instance.new("BillboardGui")
	tag.Name = "CashTag"
	tag.Size = UDim2.fromOffset(80, 22)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3.8 * rig.scale, 0)
	tag.MaxDistance = Park.Draw.TAG_DISTANCE
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 90)
	label.TextStrokeTransparency = 0.3
	label.Text = `${Format.number(cashPerSec)}/s`
	label.Parent = tag
	tag.Parent = body
end

local function setSeat(view: ParkView, seat: SeatView, key: string)
	if seat.key == key then
		return
	end
	seat.key = key
	if seat.rig then
		seat.rig.model:Destroy()
		seat.rig = nil
	end
	if key == "" then
		return
	end
	local species, variant, size = string.match(key, "^([^,]+),([^,]+),([^,]+)$")
	if species == nil then
		return
	end
	local mascot = { species = species, variant = variant, size = size }
	local rig = MascotRig.Build(mascot, true)
	if rig == nil then
		return
	end
	MascotRig.Pose(rig, seat.base)
	makeTag(rig, Formulas.mascotCashPerSec(mascot))
	rig.model.Parent = view.folder
	seat.rig = rig
end

local function refresh(view: ParkView)
	local encoded = view.model:GetAttribute("Seats")
	local keys = if type(encoded) == "string" then string.split(encoded, ";") else {}
	for i, seat in view.seats do
		setSeat(view, seat, keys[i] or "")
	end
end

local function addLane(model: Instance)
	if not model:IsA("Model") or parks[model] then
		return
	end
	local plot = model:WaitForChild("Plot", 10)
	local seatsFolder = plot and plot:WaitForChild("Seats", 10)
	local floor = plot and plot:WaitForChild("Floor", 10)
	if seatsFolder == nil or floor == nil or not floor:IsA("BasePart") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = model.Name
	local view: ParkView = { model = model, center = floor.Position, folder = folder, seats = {} }
	for i = 1, Park.Layout.SEAT_COUNT do
		local pad = seatsFolder:WaitForChild(`Seat{i}`, 10)
		local spot = pad and pad:FindFirstChild("Spot")
		local base = if spot and spot:IsA("Attachment") then spot.WorldCFrame else floor.CFrame
		view.seats[i] = { key = "", rig = nil, base = base }
	end
	parks[model] = view
	refresh(view)
	model:GetAttributeChangedSignal("Seats"):Connect(function()
		refresh(view)
	end)
	model.Destroying:Connect(function()
		folder:Destroy()
		parks[model] = nil
	end)
end

-- Draws only the parks near the camera.
local function cull()
	local camera = workspace.CurrentCamera.CFrame.Position
	for _, view in parks do
		local near = (view.center - camera).Magnitude <= Park.Draw.DISTANCE
		view.folder.Parent = if near then root else nil
	end
end

-- Your own Mascots bob gently (not in low graphics, and not while your park isn't drawn).
local function idle()
	local data = StateController.Get()
	local still = data ~= nil and data.settings.lowGraphics
	if still then
		if wasBobbing then
			-- Low graphics just turned on: settle everyone back onto their seats once.
			wasBobbing = false
			for _, view in parks do
				for _, seat in view.seats do
					if seat.rig then
						MascotRig.Pose(seat.rig, seat.base)
					end
				end
			end
		end
		return
	end
	wasBobbing = true
	local d = Park.Draw
	local t = os.clock()
	for model, view in parks do
		if model:GetAttribute("Owner") == player.UserId and view.folder.Parent then
			for i, seat in view.seats do
				local rig = seat.rig
				if rig then
					local bob = (math.sin(t * d.IDLE_SPEED + i) * 0.5 + 0.5) * d.IDLE_BOB * rig.scale
					MascotRig.Pose(rig, seat.base + Vector3.yAxis * bob)
				end
			end
		end
	end
end

function ParkController.Init()
	root = Instance.new("Folder")
	root.Name = "ParkMascots"
	root.Parent = workspace
end

function ParkController.Start()
	local areas = workspace:WaitForChild("BattingAreas")
	areas.ChildAdded:Connect(function(child)
		task.spawn(addLane, child)
	end)
	for _, child in areas:GetChildren() do
		task.spawn(addLane, child)
	end
	task.spawn(function()
		while true do
			cull()
			task.wait(Park.Draw.CHECK_EVERY)
		end
	end)
	RunService.RenderStepped:Connect(idle)
end

return ParkController
