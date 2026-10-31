--!strict
-- HudController: placeholder HUD (the UI pass comes later).
--   Top-left: Power, Cash (counting up smoothly between the server's payouts) and Cash/s.
--   Top-center: distance bar with one equal-width section per biome,
--   filled to the last hit. A short "+Power" popup per hit (bottom-right). There is no SWING
--   button: a tap anywhere on the game view swings (InputController).
-- Display only: every value comes from the server (StateController and HitResult).
--   HudController.Celebrate(hitId) -> "PERFECT!" (once per hit). Given on milestones, never for skill.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Format = require(Shared:WaitForChild("Format"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Config:WaitForChild("Tuning"))

local BallController = require(script.Parent.BallController)
local StateController = require(script.Parent.StateController)
local UILayout = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("UILayout"))

local HudController = {}

local powerLabel: TextLabel
local cashLabel: TextLabel
local rateLabel: TextLabel
local barFill: Frame
-- Cash counts up smoothly between the server's once-a-second payouts: the last Cash the server
-- sent, when it arrived, and the earning rate (Formulas.cashRate, the same number the server pays).
local cashBase = 0
local cashBaseAt = 0
local cashRate = 0
local cashShown = 0 -- what the label shows; only goes down when Cash is spent
local bestMarker: Frame
local hitLabel: TextLabel
local popup: TextLabel
local judgement: TextLabel

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

local barNames: { TextLabel } = {}

-- The world the player is in (stadium tier N plays World N), World 1 before the first snapshot.
local function currentWorld(): number
	local data = StateController.Get()
	return if data then Formulas.world(data) else 1
end

-- 0..1 position on the bar. Each biome gets an equal share, so early biomes aren't squashed.
local function barPosition(distance: number): number
	local starts = Tuning.BiomeStarts
	local count = #Formulas.biomes(currentWorld())
	local index = Formulas.biomeIndexAt(distance, currentWorld())
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
	stats.Size = UDim2.fromOffset(190, 100)
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
	cashLabel = label({
		Name = "Cash",
		Text = "Cash: ...",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 220, 90),
		Position = UDim2.fromOffset(10, 40),
		Size = UDim2.new(1, -20, 0, 30),
		Parent = stats,
	})
	rateLabel = label({
		Name = "CashRate",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 235, 160),
		Position = UDim2.fromOffset(10, 72),
		Size = UDim2.new(1, -20, 0, 20),
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
	local biomes = Formulas.biomes(1) -- names follow the world (refreshWorld); every world has as many biomes
	for i, biome in biomes do
		local x = (i - 1) / #biomes
		local tick = Instance.new("Frame")
		tick.Name = `Marker{i}`
		tick.BorderSizePixel = 0
		tick.BackgroundColor3 = Color3.new(1, 1, 1)
		tick.Position = UDim2.fromScale(x, 0)
		tick.Size = UDim2.new(0, 2, 1, 6)
		tick.Parent = bar
		barNames[i] = label({
			Name = `Name{i}`,
			Text = biome.displayName,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.new(x, 4, 1, 4),
			Size = UDim2.new(1 / #biomes, -6, 0, 14),
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

	popup = label({
		Name = "Popup",
		Text = "",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24 - UILayout.BOTTOM_BAR),
		Size = UDim2.fromOffset(200, 28),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = gui,
	})

	judgement = label({
		Name = "Judgement",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.new(0.5, 0, 0, 48),
		Font = Enum.Font.GothamBlack,
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
	if data.lifetime.bestDistance > 0 then
		bestMarker.Visible = true
		bestMarker.Position = UDim2.fromScale(barPosition(data.lifetime.bestDistance), 0)
	end
end

-- A new Cash value from the server.
local function refreshCash()
	local data = StateController.Get()
	if data == nil then
		return
	end
	if data.cash < cashBase then
		cashShown = 0 -- Cash really went down (a purchase): let the display drop with it
	end
	cashBase = data.cash
	cashBaseAt = os.clock()
end

-- The earning rate changes when seats, Mascots or the stadium tier change.
local function refreshRate()
	local data = StateController.Get()
	if data == nil then
		return
	end
	cashRate = Formulas.cashRate(data)
	rateLabel.Text = if cashRate > 0 then `+${Format.number(cashRate)}/s` else "Seat Mascots to earn"
end

-- Every frame: the last server Cash plus what's been earned since, for at most a little over
-- one payout (so a late or stopped update never runs the number away). Never counts backwards
-- when a payout arrives a little late; it only drops for a real spend.
local function tickCash()
	local since = math.min(os.clock() - cashBaseAt, Tuning.Income.PAY_EVERY * 1.5)
	cashShown = math.max(cashShown, cashBase + cashRate * since)
	cashLabel.Text = `Cash: ${Format.number(cashShown)}`
end

local popupTween: Tween? = nil
local judgementTween: Tween? = nil
local lastCelebrated: number? = nil

-- "PERFECT!" for a given moment (a record milestone or a new biome). Once per hit.
function HudController.Celebrate(hitId: number)
	if lastCelebrated == hitId then
		return
	end
	lastCelebrated = hitId
	judgement.Text = "PERFECT!"
	judgement.TextColor3 = Color3.fromRGB(255, 215, 70)
	judgement.TextTransparency = 0
	judgement.TextStrokeTransparency = 0.3
	if judgementTween then
		judgementTween:Cancel()
	end
	judgementTween = TweenService:Create(
		judgement,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	);
	(judgementTween :: Tween):Play()
end

local function showHit(result: any)
	barFill.Size = UDim2.fromScale(barPosition(result.distance), 1)
	hitLabel.Text = `Last hit: {Format.number(result.distance)} studs - {Formulas.biomeNameAt(
		result.distance,
		currentWorld()
	)}`

	popup.Text = `+{Format.number(result.powerGained)} Power`
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

-- The bar's biome names for the current world.
local function refreshWorld()
	for i, biome in Formulas.biomes(currentWorld()) do
		if barNames[i] then
			barNames[i].Text = biome.displayName
		end
	end
end

function HudController.Init()
	local gui = build()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function HudController.Start()
	local function refreshAll()
		refresh()
		refreshCash()
		refreshRate()
		refreshWorld()
	end
	StateController.Ready:Connect(refreshAll)
	StateController.Changed:Connect(function(key: string)
		if key == "power" or key == "lifetime" then
			refresh()
		elseif key == "cash" then
			refreshCash()
		elseif key == "seats" or key == "mascots" or key == "stadiumTier" or key == "park" then
			refreshRate()
		end
		if key == "stadiumTier" then
			refreshWorld()
		end
	end)
	refreshAll()
	RunService.RenderStepped:Connect(tickCash)
	-- Show each hit's numbers at bat-on-ball, not when the server's result arrives (with Fungo
	-- that's usually during the toss, before the ball leaves the bat).
	local waiting: { [number]: { result: any, at: number } } = {} -- results whose ball hasn't launched yet
	local launched: { [number]: number } = {} -- launched balls whose result hasn't come yet
	local function prune(now: number)
		for id, at in launched do
			if now - at > 15 then
				launched[id] = nil
			end
		end
		for id, entry in waiting do
			if now - entry.at > 15 then
				waiting[id] = nil
			end
		end
	end
	Remotes.Event("HitResult").OnClientEvent:Connect(function(result: any)
		if type(result) ~= "table" or type(result.hitId) ~= "number" then
			return
		end
		if launched[result.hitId] then
			launched[result.hitId] = nil
			showHit(result)
		else
			waiting[result.hitId] = { result = result, at = os.clock() }
		end
	end)
	BallController.Launched:Connect(function(hitId: number)
		local now = os.clock()
		prune(now)
		local entry = waiting[hitId]
		if entry then
			waiting[hitId] = nil
			showHit(entry.result)
		else
			launched[hitId] = now
		end
	end)
end

return HudController
