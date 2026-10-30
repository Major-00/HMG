--!strict
-- WelcomeBackController: after time away, shows what seated Mascots earned offline.
-- The server already paid it at load (IncomeService); this only shows the amount, once.
-- It never blocks play: a small card at the top, away from the SWING button, that closes by
-- itself. It ignores input, so a tap on it still swings (every tap succeeds).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

local StateController = require(script.Parent.StateController)

local WelcomeBackController = {}

-- "2h 14m", "45m", "1m".
local function duration(seconds: number): string
	local minutes = math.floor(seconds / 60)
	local hours = math.floor(minutes / 60)
	minutes %= 60
	if hours > 0 then
		return if minutes > 0 then `{hours}h {minutes}m` else `{hours}h`
	end
	return `{math.max(minutes, 1)}m`
end

local function show(seconds: number, cash: number)
	local gui = Instance.new("ScreenGui")
	gui.Name = "WelcomeBack"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 25

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Active = false -- doesn't take taps
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.fromScale(0.5, 0.2)
	card.Size = UDim2.fromScale(0.42, 0.18)
	card.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	card.BackgroundTransparency = 0.2
	card.Parent = gui
	Instance.new("UICorner").Parent = card
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(460, 130)
	limit.Parent = card

	local function text(name: string, value: string, y: number, h: number, color: Color3, font: Enum.Font)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Text = value
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.4
		l.Position = UDim2.fromScale(0.05, y)
		l.Size = UDim2.fromScale(0.9, h)
		l.Parent = card
		return l
	end
	text("Title", "Welcome back!", 0.06, 0.32, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
	text("Cash", `+${Format.number(cash)}`, 0.38, 0.34, Color3.fromRGB(255, 220, 90), Enum.Font.GothamBlack)
	text(
		"Detail",
		`Your Mascots earned this in {duration(seconds)} away`,
		0.74,
		0.2,
		Color3.fromRGB(220, 225, 235),
		Enum.Font.GothamBold
	)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		local fade = TweenInfo.new(0.3)
		TweenService:Create(card, fade, { BackgroundTransparency = 1 }):Play()
		for _, child in card:GetChildren() do
			if child:IsA("TextLabel") then
				TweenService:Create(child, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end
		task.delay(0.3, function()
			gui:Destroy()
		end)
	end
	task.delay(Tuning.Offline.WELCOME_TIME, close)
end

function WelcomeBackController.Start()
	StateController.WaitForData()
	local remote = Remotes.Function("GetWelcomeBack")
	local ok, result = pcall(remote.InvokeServer, remote)
	if
		ok
		and type(result) == "table"
		and type(result.cash) == "number"
		and type(result.seconds) == "number"
	then
		show(result.seconds, result.cash)
	end
end

return WelcomeBackController
