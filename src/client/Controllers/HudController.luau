--!strict
-- HudController: placeholder HUD (the UI pass comes later).
--   Top-left: Power and Wins. Top-center: distance bar with one equal-width section per biome,
--   filled to the last hit. Bottom-right: the big SWING button. A short "+Power +Wins" popup per hit.
-- Display only: every value comes from the server (StateController and HitResult).
--   HudController.SwingPressed -> Signal fired when the SWING button is pressed

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Biomes = require(Config:WaitForChild("Biomes"))
local Format = require(Shared:WaitForChild("Format"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Tuning = require(Config:WaitForChild("Tuning"))

local StateController = require(script.Parent.StateController)

local HudController = {}

HudController.SwingPressed = Signal.new()

local powerLabel: TextLabel
local winsLabel: TextLabel
local barFill: Frame
local bestMarker: Frame
local hitLabel: TextLabel
local popup: TextLabel
local swingButton: TextButton

local function label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.TextScaled = true
	for key, value in props do
		(l :: any)[key] = value
	end
	return l
end

-- 0..1 position on the bar. Each biome gets an equal share, so early biomes aren't squashed.
local function barPosition(distance: number): number
	local starts = Tuning.BiomeStarts
	local count = #Biomes
	local index = Formulas.biomeIndexAt(distance)
	local from = starts[index]
	local to = starts[index + 1]
	local within = if to
		then (distance - from) / (to - from)
		else math.min((distance - from) / math.max(from, 1), 1)
	return math.clamp((index - 1 + within) / count, 0, 1)
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Stats
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	stats.BackgroundTransparency = 0.35
	stats.Position = UDim2.fromOffset(12, 12)
	stats.Size = UDim2.fromOffset(190, 78)
	Instance.new("UICorner").Parent = stats
	stats.Parent = gui
	powerLabel = label({
		Name = "Power",
		Text = "Power: ...",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 30),
		Parent = stats,
	})
	winsLabel = label({
		Name = "Wins",
		Text = "Wins: ...",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 220, 90),
		Position = UDim2.fromOffset(10, 40),
		Size = UDim2.new(1, -20, 0, 30),
		Parent = stats,
	})

	-- Distance bar
	local bar = Instance.new("Frame")
	bar.Name = "DistanceBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 12)
	bar.Size = UDim2.new(0.5, 0, 0, 22)
	bar.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	bar.BackgroundTransparency = 0.35
	bar.Parent = gui
	barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.BorderSizePixel = 0
	barFill.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.Parent = bar
	bestMarker = Instance.new("Frame")
	bestMarker.Name = "Best"
	bestMarker.BorderSizePixel = 0
	bestMarker.BackgroundColor3 = Color3.fromRGB(255, 220, 90)
	bestMarker.AnchorPoint = Vector2.new(0.5, 0)
	bestMarker.Size = UDim2.new(0, 3, 1, 0)
	bestMarker.Visible = false
	bestMarker.Parent = bar
	for i, biome in Biomes do
		local x = (i - 1) / #Biomes
		local tick = Instance.new("Frame")
		tick.Name = `Marker{i}`
		tick.BorderSizePixel = 0
		tick.BackgroundColor3 = Color3.new(1, 1, 1)
		tick.Position = UDim2.fromScale(x, 0)
		tick.Size = UDim2.new(0, 2, 1, 6)
		tick.Parent = bar
		label({
			Name = `Name{i}`,
			Text = biome.displayName,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.new(x, 4, 1, 4),
			Size = UDim2.new(1 / #Biomes, -6, 0, 14),
			Parent = bar,
		})
	end
	hitLabel = label({
		Name = "LastHit",
		Text = "Tap to swing!",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.new(0.5, 0, 0, 20),
		Parent = gui,
	})

	-- Swing button: big touch target, bottom-right (thumb reach on phones).
	swingButton = Instance.new("TextButton")
	swingButton.Name = "SwingButton"
	swingButton.AnchorPoint = Vector2.new(1, 1)
	swingButton.Position = UDim2.new(1, -24, 1, -24)
	swingButton.Size = UDim2.fromOffset(140, 140)
	swingButton.BackgroundColor3 = Color3.fromRGB(230, 70, 60)
	swingButton.Font = Enum.Font.GothamBlack
	swingButton.Text = "SWING"
	swingButton.TextScaled = true
	swingButton.TextColor3 = Color3.new(1, 1, 1)
	swingButton.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = swingButton
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.18, 0)
	padding.PaddingRight = UDim.new(0.18, 0)
	padding.Parent = swingButton
	swingButton.Parent = gui
	swingButton.Activated:Connect(function()
		HudController.SwingPressed:Fire()
	end)

	popup = label({
		Name = "Popup",
		Text = "",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -176),
		Size = UDim2.fromOffset(200, 28),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = gui,
	})

	return gui
end

local function refresh()
	local data = StateController.Get()
	if data == nil then
		return
	end
	powerLabel.Text = `Power: {Format.number(data.power)}`
	winsLabel.Text = `Wins: {Format.number(data.wins)}`
	if data.lifetime.bestDistance > 0 then
		bestMarker.Visible = true
		bestMarker.Position = UDim2.fromScale(barPosition(data.lifetime.bestDistance), 0)
	end
end

local popupTween: Tween? = nil

local function onHit(result: any)
	barFill.Size = UDim2.fromScale(barPosition(result.distance), 1)
	hitLabel.Text =
		`Last hit: {Format.number(result.distance)} studs - {Formulas.biomeNameAt(result.distance)}`

	popup.Text = `+{Format.number(result.powerGained)} Power  +{Format.number(result.winsGained)} Wins`
	popup.TextTransparency = 0
	popup.TextStrokeTransparency = 0.4
	if popupTween then
		popupTween:Cancel()
	end
	popupTween = TweenService:Create(
		popup,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	);
	(popupTween :: Tween):Play()
end

function HudController.Init()
	local gui = build()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function HudController.Start()
	StateController.Ready:Connect(refresh)
	StateController.Changed:Connect(function(key: string)
		if key == "power" or key == "wins" or key == "lifetime" then
			refresh()
		end
	end)
	refresh()
	Remotes.Event("HitResult").OnClientEvent:Connect(onHit)
end

return HudController
