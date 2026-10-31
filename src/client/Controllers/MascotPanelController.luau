--!strict
-- MascotPanelController: the Mascots panel, opened with the "Mascots" button above the hotbar.
-- Down the left side, never over the SWING button, so you can keep swinging while it's open.
--   Tabs: Seated (earning) and Hotbar (+ On Deck).
--   Equip Best (seats your 10 best earners) and the Auto-Sell toggle.
--   One fixed row per slot (Seat 1-10, or Hotbar 1-4 and On Deck), so rows never move under
--   your finger when a catch arrives: name, rarity · variant · size, Cash/s, and its actions:
--     seated: Lock, Sell        hotbar: Seat it, Lock, Sell        On Deck: Swap in, Lock, Sell
--   Sell asks for a second tap for Rare and up; locked Mascots can't be sold.
-- Every action goes to the server (MascotController). Only rows whose Mascot changed are
-- redrawn (so a pending "Tap again to sell" survives other changes). The panel takes taps on
-- itself, so tapping it never swings; everywhere else still does.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))

local MascotController = require(script.Parent.MascotController)
local StateController = require(script.Parent.StateController)
local Modules = script.Parent.Parent:WaitForChild("Modules")
local MascotInfo = require(Modules:WaitForChild("MascotInfo"))
local UILayout = require(Modules:WaitForChild("UILayout"))

local MARGIN = UILayout.MARGIN
local BUTTON_H = 40
local CARD_H = 56

local MascotPanelController = {}

type Tab = "seated" | "hotbar"

local panel: Frame
local list: ScrollingFrame
local seatedTab: TextButton
local hotbarTab: TextButton
local autoSellButton: TextButton
local tab: Tab = "seated"
type Row = { frame: Frame, signature: string }
local rows: { Row } = {}
local shownTab: Tab? = nil
local openButton: TextButton

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

-- The rows this tab shows, in a fixed order: { label, uid (or false), where }.
local function slotsOf(data: any): { { label: string, uid: any, where: string } }
	local out = {}
	if tab == "seated" then
		for i, uid in data.seats do
			table.insert(out, { label = `Seat {i}`, uid = uid, where = "seat" })
		end
	else
		for i, uid in data.hotbar do
			table.insert(out, { label = `Hotbar {i}`, uid = uid, where = "hotbar" })
		end
		table.insert(out, { label = "On Deck", uid = data.onDeck, where = "onDeck" })
	end
	return out
end

local function card(data: any, slot: { label: string, uid: any, where: string }, order: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = slot.label
	frame.Active = true -- taps on a card never reach the world
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, -8, 0, CARD_H)
	frame.BackgroundColor3 = Color3.fromRGB(32, 38, 50)
	frame.Parent = list
	Instance.new("UICorner").Parent = frame

	local uid = slot.uid
	local mascot = if uid then data.mascots[uid] else nil
	if mascot == nil then
		frame.BackgroundTransparency = 0.5
		text(frame, {
			Name = "Empty",
			Text = `{slot.label}: empty`,
			TextColor3 = Color3.fromRGB(160, 165, 175),
			Position = UDim2.fromOffset(14, 16),
			Size = UDim2.new(1, -28, 0, 22),
		})
		return frame
	end

	local info = MascotInfo.Describe(mascot)
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 6, 1, 0)
	stripe.BackgroundColor3 = info.rarityColor
	stripe.BorderSizePixel = 0
	stripe.Parent = frame

	text(frame, {
		Name = "MascotName",
		Text = (if mascot.locked then "🔒 " else "") .. info.name,
		TextColor3 = info.rarityColor,
		Position = UDim2.fromOffset(14, 5),
		Size = UDim2.new(0.5, -14, 0, 22),
	})
	text(frame, {
		Name = "Details",
		Text = `{slot.label} · {info.details} · ${Format.number(info.cashPerSec)}/s`,
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(14, 30),
		Size = UDim2.new(0.5, -14, 0, 18),
	})

	-- Actions, right-aligned.
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.BackgroundTransparency = 1
	actions.AnchorPoint = Vector2.new(1, 0.5)
	actions.Position = UDim2.new(1, -8, 0.5, 0)
	actions.Size = UDim2.new(0.5, 0, 0, 44)
	actions.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = actions

	if slot.where == "hotbar" then
		button(
			actions,
			"Seat it",
			Color3.fromRGB(60, 150, 90),
			{ Name = "SeatIt", LayoutOrder = 1, Size = UDim2.fromScale(0.3, 1) }
		).Activated:Connect(function()
			local now = StateController.Get()
			local target = now and MascotInfo.SeatTarget(now)
			if target then
				MascotController.Move(uid, "seats", target)
			end
		end)
	elseif slot.where == "onDeck" then
		button(
			actions,
			"Swap in",
			Color3.fromRGB(60, 150, 90),
			{ Name = "SwapIn", LayoutOrder = 1, Size = UDim2.fromScale(0.3, 1) }
		).Activated:Connect(function()
			local now = StateController.Get()
			local target = now and MascotInfo.HotbarTarget(now)
			if target then
				MascotController.Move(uid, "hotbar", target)
			end
		end)
	end
	button(
		actions,
		if mascot.locked then "Unlock" else "Lock",
		Color3.fromRGB(80, 90, 120),
		{ Name = "Lock", LayoutOrder = 2, Size = UDim2.fromScale(0.28, 1) }
	).Activated:Connect(function()
		MascotController.SetLock(uid, not mascot.locked)
	end)
	local sell = button(
		actions,
		"Sell",
		Color3.fromRGB(190, 70, 60),
		{ Name = "Sell", LayoutOrder = 3, Size = UDim2.fromScale(0.38, 1) }
	)
	MascotInfo.SellButton(sell, uid, mascot, MascotController.Sell)
	return frame
end

local function redraw(force: boolean?)
	local data = StateController.Get()
	if data == nil then
		return
	end
	local seated, hotbar = 0, 0
	for _, uid in data.seats do
		if uid then
			seated += 1
		end
	end
	for _, uid in data.hotbar do
		if uid then
			hotbar += 1
		end
	end
	seatedTab.Text = `Seated {seated}/10`
	hotbarTab.Text = `Hotbar {hotbar}/4` .. (if data.onDeck then " +1" else "")
	seatedTab.BackgroundColor3 = if tab == "seated"
		then Color3.fromRGB(70, 110, 200)
		else Color3.fromRGB(50, 56, 70)
	hotbarTab.BackgroundColor3 = if tab == "hotbar"
		then Color3.fromRGB(70, 110, 200)
		else Color3.fromRGB(50, 56, 70)
	autoSellButton.Text = if data.autoSell then "Auto-Sell ON" else "Auto-Sell OFF"
	autoSellButton.BackgroundColor3 = if data.autoSell
		then Color3.fromRGB(60, 150, 90)
		else Color3.fromRGB(110, 110, 120)

	if not panel.Visible then
		return
	end
	if force or shownTab ~= tab then
		for _, row in rows do
			row.frame:Destroy()
		end
		table.clear(rows)
		shownTab = tab
	end
	-- Rebuild only the rows whose Mascot (or its lock) changed; rows never move.
	for i, slot in slotsOf(data) do
		local mascot = if slot.uid then data.mascots[slot.uid] else nil
		local signature = if mascot then `{slot.uid}:{mascot.locked}` else "empty"
		local row = rows[i]
		if row == nil or row.signature ~= signature then
			if row then
				row.frame:Destroy()
			end
			rows[i] = { frame = card(data, slot, i), signature = signature }
		end
	end
end

local function setTab(t: Tab)
	tab = t
	redraw(true)
end

function MascotPanelController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MascotsPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 18

	local barTop = UILayout.BOTTOM_BAR + 8
	openButton = button(gui, "Mascots", Color3.fromRGB(70, 110, 200), {
		Name = "OpenButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, MARGIN, 1, -barTop),
		Size = UDim2.fromOffset(120, BUTTON_H),
	})
	local open = openButton

	-- From the top margin down to just above the hotbar (it covers the Mascots button, which
	-- hides while it's open), and never as far right as the SWING button.
	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = true -- taps on the panel never reach the world (no accidental swings)
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

	-- One header row, so short phone screens keep room for the list.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(8, 8)
	header.Size = UDim2.new(1, -16, 0, BUTTON_H)
	header.Parent = panel
	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.Padding = UDim.new(0, 6)
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Parent = header
	seatedTab = button(header, "Seated", Color3.fromRGB(70, 110, 200), {
		Name = "SeatedTab",
		LayoutOrder = 1,
		Size = UDim2.new(0.23, -5, 1, 0),
	})
	hotbarTab = button(header, "Hotbar", Color3.fromRGB(50, 56, 70), {
		Name = "HotbarTab",
		LayoutOrder = 2,
		Size = UDim2.new(0.23, -5, 1, 0),
	})
	local equipBest = button(header, "Equip Best", Color3.fromRGB(200, 150, 50), {
		Name = "EquipBest",
		LayoutOrder = 3,
		Size = UDim2.new(0.2, -5, 1, 0),
	})
	autoSellButton = button(header, "Auto-Sell", Color3.fromRGB(60, 150, 90), {
		Name = "AutoSell",
		LayoutOrder = 4,
		Size = UDim2.new(0.22, -5, 1, 0),
	})
	local close = button(header, "X", Color3.fromRGB(90, 60, 60), {
		Name = "Close",
		LayoutOrder = 5,
		Size = UDim2.new(0.12, -5, 1, 0),
	})

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(8, 8 + BUTTON_H + 6)
	list.Size = UDim2.new(1, -8, 1, -(16 + BUTTON_H + 6))
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
		openButton.Visible = not visible
		redraw(true)
	end
	open.Activated:Connect(function()
		show(true)
	end)
	close.Activated:Connect(function()
		show(false)
	end)
	seatedTab.Activated:Connect(function()
		setTab("seated")
	end)
	hotbarTab.Activated:Connect(function()
		setTab("hotbar")
	end)
	equipBest.Activated:Connect(function()
		MascotController.EquipBest()
	end)
	autoSellButton.Activated:Connect(function()
		local data = StateController.Get()
		if data then
			MascotController.SetAutoSell(not data.autoSell)
		end
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function MascotPanelController.Start()
	StateController.Ready:Connect(function()
		redraw(true)
	end)
	StateController.Changed:Connect(function(key: string)
		if key == "seats" or key == "hotbar" or key == "onDeck" or key == "mascots" or key == "autoSell" then
			redraw()
		end
	end)
	redraw(true)
end

return MascotPanelController
