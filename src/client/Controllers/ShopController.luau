--!strict
-- ShopController: the Cash shop, opened with the "Shop" button next to "Mascots" (one side
-- panel at a time, never over the SWING button; swinging keeps working while it's open).
--   Balls: each tier in order with its price and its rarity odds at your best distance (from
--     Formulas.rarityOdds, the same numbers the server rolls with). Buy the next one; the best
--     ball you own is used on every hit. Cash only.
--   Bats: each tier with its Power multiplier. Buy the next one (it's equipped), or equip any
--     bat you own.
--   Park: the five park upgrades (Config/Park) with their level, bonus and next cost; each level
--     raises your park's Cash rate.
-- The server checks and charges every purchase (BallService, BatService, ParkService); this only asks.
-- It also shows the server's one-time "New ball unlocked" notice, and the Shop button glows
-- until you open the shop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balls = require(Config:WaitForChild("Balls"))
local Bats = require(Config:WaitForChild("Bats"))
local Format = require(Shared:WaitForChild("Format"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Mascots = require(Config:WaitForChild("Mascots"))
local Park = require(Config:WaitForChild("Park"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HighlightController = require(script.Parent.HighlightController)
local StateController = require(script.Parent.StateController)
local UILayout = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("UILayout"))

local MARGIN = UILayout.MARGIN
local BUTTON_H = UILayout.PANEL_BUTTON.Y
local ROW_H = 64
local GLOW = Color3.fromRGB(255, 190, 60)
local SHOP_COLOR = Color3.fromRGB(200, 150, 50)

local ShopController = {}

type Tab = "balls" | "bats" | "park"
type Row = { frame: Frame, signature: string }

local panel: Frame
local list: ScrollingFrame
local note: TextLabel
local ballsTab: TextButton
local batsTab: TextButton
local parkTab: TextButton
local openButton: TextButton
local tab: Tab = "balls"
local shownTab: Tab? = nil
local rows: { Row } = {}
local busy = false -- one purchase at a time from this panel

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
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = b
	b.Parent = parent
	return b
end

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

local function percent(x: number): string
	local p = x * 100
	if p >= 10 then
		return `{math.floor(p + 0.5)}%`
	elseif p >= 1 then
		return `{math.floor(p * 10 + 0.5) / 10}%`
	end
	return `{math.floor(p * 100 + 0.5) / 100}%`
end

-- Where the odds are shown for: the player's best distance (Luck and biome follow it).
local function oddsPlace(data: any): (number, number, number)
	local distance = data.lifetime.bestDistance
	local world = Formulas.world(data)
	return world, Formulas.biomeIndexAt(distance, world), distance
end

local function buy(remoteName: string, id: string)
	if busy then
		return
	end
	busy = true
	local remote = Remotes.Function(remoteName)
	pcall(remote.InvokeServer, remote, id)
	busy = false
end

local function rowFrame(name: string, order: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Active = true -- taps on a row never reach the world
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, -8, 0, ROW_H)
	frame.BackgroundColor3 = Color3.fromRGB(32, 38, 50)
	frame.Parent = list
	Instance.new("UICorner").Parent = frame
	return frame
end

local function actionButton(frame: Frame, label: string, color: Color3, enabled: boolean): TextButton
	local b = button(frame, label, color, {
		Name = "Action",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0.34, 0, 0, 44),
		AutoButtonColor = enabled,
	})
	if not enabled then
		b.BackgroundColor3 = Color3.fromRGB(70, 74, 86)
		b.TextColor3 = Color3.fromRGB(180, 184, 192)
	end
	return b
end

-- The ball row's state, and the signature that decides whether it needs redrawing.
local function ballRow(data: any, ball: Balls.Ball, order: number, next: Balls.Ball?, best: Balls.Ball): Row
	local owned = data.balls.owned[ball.id] == true
	local isNext = next ~= nil and next.id == ball.id
	local canBuy = isNext and data.cash >= ball.price
	local world, biome, distance = oddsPlace(data)
	local signature = `{owned}:{isNext}:{canBuy}:{ball.id == best.id}:{world}:{biome}:{distance}`

	local frame = rowFrame(ball.id, order)
	text(frame, {
		Name = "BallName",
		Text = ball.displayName,
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.new(0.62, -12, 0, 22),
	})
	local odds = Formulas.rarityOdds(world, ball.id, biome, distance)
	local parts = {}
	for _, rarity in Mascots.Rarities do
		local chance = odds[rarity.id]
		if chance then
			table.insert(parts, `{string.sub(rarity.displayName, 1, 1)} {percent(chance)}`)
		end
	end
	text(frame, {
		Name = "Odds",
		Text = table.concat(parts, "  "),
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(12, 32),
		Size = UDim2.new(0.62, -12, 0, 20),
	})

	local action: TextButton
	if ball.id == best.id then
		action = actionButton(frame, "Using", Color3.fromRGB(60, 150, 90), false)
	elseif owned then
		action = actionButton(frame, "Owned", Color3.fromRGB(60, 150, 90), false)
	elseif isNext then
		action = actionButton(frame, `Buy ${Format.number(ball.price)}`, SHOP_COLOR, canBuy)
		if canBuy then
			action.Activated:Connect(function()
				buy("BuyBall", ball.id)
			end)
		end
	else
		action = actionButton(frame, `${Format.number(ball.price)}`, SHOP_COLOR, false)
	end
	return { frame = frame, signature = signature }
end

local function nextBat(data: any): Bats.Bat?
	for _, bat in Bats.List do
		if not data.bats.owned[bat.id] then
			return bat
		end
	end
	return nil
end

local function batRow(data: any, bat: Bats.Bat, order: number, next: Bats.Bat?): Row
	local owned = data.bats.owned[bat.id] == true
	local equipped = data.bats.equipped == bat.id
	local isNext = next ~= nil and next.id == bat.id
	local canBuy = isNext and data.cash >= bat.price
	local signature = `{owned}:{equipped}:{isNext}:{canBuy}`

	local frame = rowFrame(bat.id, order)
	text(frame, {
		Name = "BatName",
		Text = bat.displayName,
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.new(0.62, -12, 0, 22),
	})
	text(frame, {
		Name = "Power",
		Text = `Power per hit ×{bat.powerMultiplier}`,
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(12, 32),
		Size = UDim2.new(0.62, -12, 0, 20),
	})
	if equipped then
		actionButton(frame, "Equipped", Color3.fromRGB(60, 150, 90), false)
	elseif owned then
		actionButton(frame, "Equip", Color3.fromRGB(70, 110, 200), true).Activated:Connect(function()
			buy("EquipBat", bat.id)
		end)
	elseif isNext then
		local b = actionButton(frame, `Buy ${Format.number(bat.price)}`, SHOP_COLOR, canBuy)
		if canBuy then
			b.Activated:Connect(function()
				buy("BuyBat", bat.id)
			end)
		end
	else
		actionButton(frame, `${Format.number(bat.price)}`, SHOP_COLOR, false)
	end
	return { frame = frame, signature = signature }
end

local function parkRow(data: any, upgrade: Park.Upgrade, order: number): Row
	local level = data.park[upgrade.id] or 0
	local cost = Formulas.parkUpgradeCost(upgrade.id, level)
	local canBuy = cost ~= nil and data.cash >= cost
	local frame = rowFrame(upgrade.id, order)
	text(frame, {
		Name = "UpgradeName",
		Text = `{upgrade.displayName}  Lv {level}/{Park.MAX_LEVEL}`,
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.new(0.62, -12, 0, 22),
	})
	text(frame, {
		Name = "Bonus",
		Text = `+{math.floor(upgrade.bonusPerLevel * 100 + 0.5)}% Cash/s per level`,
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(12, 32),
		Size = UDim2.new(0.62, -12, 0, 20),
	})
	if cost == nil then
		actionButton(frame, "MAX", Color3.fromRGB(60, 150, 90), false)
	else
		local b = actionButton(frame, `Buy ${Format.number(cost)}`, SHOP_COLOR, canBuy)
		if canBuy then
			b.Activated:Connect(function()
				buy("BuyParkUpgrade", upgrade.id)
			end)
		end
	end
	return { frame = frame, signature = `{level}:{canBuy}` }
end

local function redraw(force: boolean?)
	local data = StateController.Get()
	if data == nil or not panel.Visible then
		return
	end
	ballsTab.BackgroundColor3 = if tab == "balls"
		then Color3.fromRGB(70, 110, 200)
		else Color3.fromRGB(50, 56, 70)
	batsTab.BackgroundColor3 = if tab == "bats"
		then Color3.fromRGB(70, 110, 200)
		else Color3.fromRGB(50, 56, 70)
	parkTab.BackgroundColor3 = if tab == "park"
		then Color3.fromRGB(70, 110, 200)
		else Color3.fromRGB(50, 56, 70)
	local world, biome, distance = oddsPlace(data)
	if tab == "balls" then
		note.Text =
			`Odds at your best hit: {Format.number(distance)} studs, {Formulas.biomes(world)[biome].displayName}`
	elseif tab == "park" then
		note.Text = `Park bonus: ×{math.floor(Formulas.parkMultiplier(data) * 100 + 0.5) / 100} Cash/s`
	else
		note.Text = `Cash: ${Format.number(data.cash)}`
	end

	if force or shownTab ~= tab then
		for _, row in rows do
			row.frame:Destroy()
		end
		table.clear(rows)
		shownTab = tab
	end
	-- Rebuild a row only when what it shows changed (Cash ticks every second).
	local function place(i: number, make: () -> Row, signature: string)
		local row = rows[i]
		if row == nil or row.signature ~= signature then
			if row then
				row.frame:Destroy()
			end
			rows[i] = make()
		end
	end
	if tab == "balls" then
		local next = Formulas.nextBall(data)
		local best = Formulas.bestBall(data)
		for i, ball in Balls do
			local owned = data.balls.owned[ball.id] == true
			local isNext = next ~= nil and next.id == ball.id
			local canBuy = isNext and data.cash >= ball.price
			place(i, function()
				return ballRow(data, ball, i, next, best)
			end, `{owned}:{isNext}:{canBuy}:{ball.id == best.id}:{world}:{biome}:{distance}`)
		end
	elseif tab == "park" then
		for i, upgrade in Park.Upgrades do
			local level = data.park[upgrade.id] or 0
			local cost = Formulas.parkUpgradeCost(upgrade.id, level)
			place(i, function()
				return parkRow(data, upgrade, i)
			end, `{level}:{cost ~= nil and data.cash >= cost}`)
		end
	else
		local next = nextBat(data)
		for i, bat in Bats.List do
			local owned = data.bats.owned[bat.id] == true
			local isNext = next ~= nil and next.id == bat.id
			local canBuy = isNext and data.cash >= bat.price
			place(i, function()
				return batRow(data, bat, i, next)
			end, `{owned}:{data.bats.equipped == bat.id}:{isNext}:{canBuy}`)
		end
	end
end

function ShopController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Shop"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 17

	local barTop = UILayout.BOTTOM_BAR + 8
	openButton = button(gui, "Shop", SHOP_COLOR, {
		Name = "OpenButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, MARGIN + UILayout.PANEL_BUTTON.X + 8, 1, -barTop),
		Size = UDim2.fromOffset(UILayout.PANEL_BUTTON.X, BUTTON_H),
	})

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

	ballsTab = button(panel, "Balls", Color3.fromRGB(70, 110, 200), {
		Name = "BallsTab",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(0.27, -8, 0, BUTTON_H),
	})
	batsTab = button(panel, "Bats", Color3.fromRGB(50, 56, 70), {
		Name = "BatsTab",
		Position = UDim2.new(0.27, 4, 0, 8),
		Size = UDim2.new(0.27, -8, 0, BUTTON_H),
	})
	parkTab = button(panel, "Park", Color3.fromRGB(50, 56, 70), {
		Name = "ParkTab",
		Position = UDim2.new(0.54, 0, 0, 8),
		Size = UDim2.new(0.27, -8, 0, BUTTON_H),
	})
	local close = button(panel, "X", Color3.fromRGB(90, 60, 60), {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0.19, -8, 0, BUTTON_H),
	})
	note = text(panel, {
		Name = "Note",
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(10, 8 + BUTTON_H + 4),
		Size = UDim2.new(1, -20, 0, 18),
		TextColor3 = Color3.fromRGB(200, 205, 215),
	})

	local top = 8 + BUTTON_H + 4 + 18 + 6
	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(8, top)
	list.Size = UDim2.new(1, -8, 1, -(top + 8))
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local function show(visible: boolean)
		panel.Visible = visible
		if visible then
			openButton.BackgroundColor3 = SHOP_COLOR -- stop glowing once seen
		end
		redraw(true)
		UILayout.PanelChanged:Fire(if visible then "shop" else nil)
	end
	UILayout.PanelChanged:Connect(function(name: string?)
		if name ~= "shop" then
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
	ballsTab.Activated:Connect(function()
		tab = "balls"
		redraw(true)
	end)
	batsTab.Activated:Connect(function()
		tab = "bats"
		redraw(true)
	end)
	parkTab.Activated:Connect(function()
		tab = "park"
		redraw(true)
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function ShopController.Start()
	StateController.Changed:Connect(function(key: string)
		if
			key == "cash"
			or key == "balls"
			or key == "bats"
			or key == "park"
			or key == "lifetime"
			or key == "stadiumTier"
		then
			redraw()
		end
	end)
	Remotes.Event("ShopNotice").OnClientEvent:Connect(function(notice: any)
		if type(notice) ~= "table" or notice.kind ~= "ball" then
			return
		end
		for _, ball in Balls do
			if ball.id == notice.id then
				HighlightController.ShowNotice(
					"New ball unlocked!",
					`{ball.displayName}: open the Shop`,
					GLOW
				)
				if not panel.Visible then
					openButton.BackgroundColor3 = GLOW
				end
			end
		end
	end)
end

return ShopController
