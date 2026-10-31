--!strict
-- PromotionController: stadium promotion. A "Stadium" button under the HUD stats (it glows when
-- you can promote) opens a panel on the left (one side panel at a time; SWING stays reachable):
--   what the next tier needs (Cash on hand, a biome reached this run) with ticks,
--   what it gives (its Power and Cash multipliers), what you keep (every Mascot, locks, the
--   Index) and what resets (Power, Cash, bats, balls, park upgrades, biome progress),
--   and a Promote button that needs a second tap to confirm.
-- The server checks and applies everything (PromotionService); this only shows and asks, using
-- the same Formulas.promotionStatus.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local StateController = require(script.Parent.StateController)
local UILayout = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("UILayout"))

local MARGIN = UILayout.MARGIN
local BUTTON_H = UILayout.PANEL_BUTTON.Y
local CONFIRM_SECONDS = 3
local PROMOTE_H = 46
local GOOD = Color3.fromRGB(110, 220, 120)
local BAD = Color3.fromRGB(240, 110, 100)
local GOLD = Color3.fromRGB(255, 190, 60)
local IDLE = Color3.fromRGB(60, 70, 95)

local PromotionController = {}

local openButton: TextButton
local panel: Frame
local lines: { [string]: TextLabel } = {}
local promoteButton: TextButton
local armedAt: number? = nil
local busy = false

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function button(parent: Instance, label: string, color: Color3, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = label
	for key, value in props do
		(b :: any)[key] = value
	end
	Instance.new("UICorner").Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = b
	b.Parent = parent
	return b
end

local function biomeName(data: any, index: number): string
	local biomes = Formulas.biomes(data.stadiumTier)
	local biome = biomes[index] or biomes[#biomes]
	return biome.displayName
end

local function refresh()
	local data = StateController.Get()
	if data == nil then
		return
	end
	local tier = Formulas.stadiumTier(data)
	local status = Formulas.promotionStatus(data)
	openButton.Text = `{tier.displayName} ▸`
	openButton.BackgroundColor3 = if status.ready then GOLD else IDLE
	if not panel.Visible then
		return
	end

	lines.Now.Text = `Now: {tier.displayName}  (Power ×{tier.powerMultiplier}, Cash ×{tier.cashMultiplier})`
	local nextTier = status.next
	if nextTier == nil then
		lines.Title.Text = "Top stadium reached!"
		lines.Cash.Text = ""
		lines.Biome.Text = ""
		lines.Gives.Text = ""
		lines.Keeps.Text = ""
		lines.Resets.Text = ""
		promoteButton.Visible = false
		return
	end
	local requires = nextTier.requires :: any
	lines.Title.Text = `Promote to {nextTier.displayName}`
	lines.Cash.Text =
		`{if status.cashOk then "✓" else "×"} Have ${Format.number(requires.cash)} Cash  (you have ${Format.number(
			data.cash
		)})`
	lines.Cash.TextColor3 = if status.cashOk then GOOD else BAD
	lines.Biome.Text =
		`{if status.biomeOk then "✓" else "×"} Reach {biomeName(data, requires.biome)} this run  (best: {biomeName(
			data,
			data.highestBiome
		)})`
	lines.Biome.TextColor3 = if status.biomeOk then GOOD else BAD
	lines.Gives.Text =
		`New tier: Power ×{nextTier.powerMultiplier} per hit · Cash ×{nextTier.cashMultiplier} per second`
	lines.Keeps.Text = "You keep: every Mascot (seats, hotbar, On Deck), locks, the Index"
	lines.Resets.Text = "Resets: Power, Cash, bats, balls, park upgrades, biome progress"
	promoteButton.Visible = true
	if not status.ready then
		armedAt = nil
		promoteButton.Text = "Not yet"
		promoteButton.BackgroundColor3 = Color3.fromRGB(70, 74, 86)
		promoteButton.AutoButtonColor = false
	elseif armedAt == nil then
		promoteButton.Text = `Promote to {nextTier.displayName}`
		promoteButton.BackgroundColor3 = GOLD
		promoteButton.AutoButtonColor = true
	end
end

local function onPromote()
	local data = StateController.Get()
	if data == nil or busy or not Formulas.promotionStatus(data).ready then
		return
	end
	if armedAt == nil or os.clock() - armedAt > CONFIRM_SECONDS then
		armedAt = os.clock()
		promoteButton.Text = "Tap again to promote"
		task.delay(CONFIRM_SECONDS, function()
			if armedAt and os.clock() - armedAt >= CONFIRM_SECONDS then
				armedAt = nil
				refresh()
			end
		end)
		return
	end
	armedAt = nil
	busy = true
	promoteButton.Text = "Promoting..."
	local remote = Remotes.Function("Promote")
	pcall(remote.InvokeServer, remote)
	busy = false
	refresh()
end

function PromotionController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Promotion"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 17

	-- Under the HUD stats box (12, 12, 190 x 100).
	openButton = button(gui, "Stadium", IDLE, {
		Name = "OpenButton",
		Position = UDim2.fromOffset(MARGIN, MARGIN + 100 + 6),
		Size = UDim2.fromOffset(170, 34), -- narrow enough to stay clear of the catch toast
	})

	local barTop = UILayout.BOTTOM_BAR + 8
	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = true -- taps on the panel never reach the world
	panel.Visible = false
	panel.Position = UDim2.fromOffset(MARGIN, MARGIN)
	panel.Size = UDim2.new(0.6, 0, 1, -(MARGIN + barTop))
	panel.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	panel.BackgroundTransparency = 0.08
	panel.Parent = gui
	Instance.new("UICorner").Parent = panel
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(480, math.huge)
	limit.Parent = panel

	local close = button(panel, "X", Color3.fromRGB(90, 60, 60), {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(BUTTON_H, BUTTON_H),
	})

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(10, 8)
	body.Size = UDim2.new(1, -(20 + BUTTON_H), 1, -(16 + PROMOTE_H + 8)) -- above the Promote button
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	body.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body

	local order = 0
	local function line(name: string, height: number, props: { [string]: any }?)
		order += 1
		local l = text(body, { Name = name, LayoutOrder = order, Size = UDim2.new(1, -6, 0, height) })
		for key, value in props or {} do
			(l :: any)[key] = value
		end
		lines[name] = l
	end
	line("Title", 30, { TextColor3 = GOLD })
	line("Now", 18, { Font = Enum.Font.Gotham })
	line("Cash", 20)
	line("Biome", 20)
	line("Gives", 18, { Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(255, 220, 90) })
	line("Keeps", 18, { Font = Enum.Font.Gotham, TextColor3 = GOOD })
	line("Resets", 18, { Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(220, 200, 200) })
	-- Pinned to the bottom of the panel, outside the scrolling text, so it's always in view.
	promoteButton = button(panel, "Promote", GOLD, {
		Name = "Promote",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -8),
		Size = UDim2.new(1, -20, 0, PROMOTE_H),
	})

	local function show(visible: boolean)
		panel.Visible = visible
		armedAt = nil
		refresh()
		UILayout.PanelChanged:Fire(if visible then "promotion" else nil)
	end
	UILayout.PanelChanged:Connect(function(name: string?)
		if name ~= "promotion" then
			panel.Visible = false
		end
		openButton.Visible = name == nil
	end)
	openButton.Activated:Connect(function()
		show(true)
	end)
	close.Activated:Connect(function()
		show(false)
	end)
	promoteButton.Activated:Connect(onPromote)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function PromotionController.Start()
	StateController.Ready:Connect(refresh)
	StateController.Changed:Connect(function(key: string)
		if key == "cash" or key == "highestBiome" or key == "stadiumTier" then
			refresh()
		end
	end)
	refresh()
end

return PromotionController
