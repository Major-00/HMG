--!strict
-- HotbarController: the 4 hotbar slots and the On Deck slot, bottom-left, clear of the SWING
-- button. Hotbar and On Deck Mascots don't earn; seat them to earn.
-- Tap a slot for its actions (a small menu above it):
--   hotbar:  Seat it (into an empty seat, else swaps with your weakest seated Mascot), Lock, Sell
--   On Deck: Swap in (into an empty hotbar slot, else swaps with the weakest unlocked one), Lock, Sell
-- Sell asks for a second tap for Rare and up. Every action goes to the server (MascotController);
-- the bar redraws from the save when it changes. Swinging is never blocked: only the bar and the
-- open menu take taps.
-- Its height is UILayout.BOTTOM_BAR; other UI stays above it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))

local MascotController = require(script.Parent.MascotController)
local StateController = require(script.Parent.StateController)
local Modules = script.Parent.Parent:WaitForChild("Modules")
local MascotInfo = require(Modules:WaitForChild("MascotInfo"))
local UILayout = require(Modules:WaitForChild("UILayout"))

local SLOT = UILayout.SLOT
local GAP = 6
local DECK_GAP = 14
local MARGIN = UILayout.MARGIN
local LABEL = UILayout.BAR_LABEL

local HotbarController = {}

type Slot = {
	button: TextButton,
	stroke: UIStroke,
	name: TextLabel,
	cash: TextLabel,
	lock: TextLabel,
	place: "hotbar" | "onDeck",
	index: number,
}

local gui: ScreenGui
local slots: { Slot } = {}
local menu: Frame
local menuFor: Slot? = nil
local menuUid: string? = nil -- the Mascot the open menu acts on
local menuLocked: boolean? = nil -- its lock state when the menu opened

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.5
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function uidIn(slot: Slot): string?
	local data = StateController.Get()
	if data == nil then
		return nil
	end
	local uid = if slot.place == "onDeck" then data.onDeck else data.hotbar[slot.index]
	return if uid then uid else nil
end

local function closeMenu()
	menuFor = nil
	menuUid = nil
	menuLocked = nil
	menu.Visible = false
	for _, child in menu:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function menuButton(label: string, color: Color3, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = label
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(150, 44)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = label
	Instance.new("UICorner").Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = b
	b.Parent = menu
	return b
end

local function openMenu(slot: Slot)
	local data = StateController.Get()
	local uid = uidIn(slot)
	if data == nil or uid == nil then
		closeMenu()
		return
	end
	local mascot = data.mascots[uid]
	if mascot == nil then
		closeMenu()
		return
	end
	closeMenu()
	menuFor = slot
	menuUid = uid
	menuLocked = mascot.locked

	if slot.place == "hotbar" then
		menuButton("Seat it", Color3.fromRGB(60, 150, 90), 1).Activated:Connect(function()
			local now = StateController.Get()
			local target = now and MascotInfo.SeatTarget(now)
			closeMenu()
			if target then
				MascotController.Move(uid, "seats", target)
			end
		end)
	else
		menuButton("Swap in", Color3.fromRGB(60, 150, 90), 1).Activated:Connect(function()
			local now = StateController.Get()
			local target = now and MascotInfo.HotbarTarget(now)
			closeMenu()
			if target then
				MascotController.Move(uid, "hotbar", target)
			end
		end)
	end
	menuButton(if mascot.locked then "Unlock" else "Lock", Color3.fromRGB(80, 90, 120), 2).Activated:Connect(
		function()
			closeMenu()
			MascotController.SetLock(uid, not mascot.locked)
		end
	)
	local sell = menuButton("Sell", Color3.fromRGB(190, 70, 60), 3)
	MascotInfo.SellButton(sell, uid, mascot, function(id)
		closeMenu()
		return MascotController.Sell(id)
	end)

	-- Above the tapped slot.
	local at = slot.button.AbsolutePosition - gui.AbsolutePosition
	menu.Position = UDim2.fromOffset(at.X, at.Y - 8)
	menu.Visible = true
end

local function redraw()
	local data = StateController.Get()
	if data == nil then
		return
	end
	for _, slot in slots do
		local uid = uidIn(slot)
		local mascot = if uid then data.mascots[uid] else nil
		if mascot then
			local info = MascotInfo.Describe(mascot)
			slot.name.Text = info.name
			slot.cash.Text = `${Format.number(info.cashPerSec)}/s`
			slot.stroke.Color = info.rarityColor
			slot.stroke.Thickness = 3
			slot.lock.Visible = mascot.locked
			slot.button.BackgroundTransparency = 0.15
		else
			slot.name.Text = "Empty"
			slot.cash.Text = ""
			slot.stroke.Color = Color3.fromRGB(120, 120, 130)
			slot.stroke.Thickness = 1
			slot.lock.Visible = false
			slot.button.BackgroundTransparency = 0.5
		end
	end
	-- Keep an open menu while its slot still holds the same Mascot (catches change the save
	-- every few seconds); close it if that Mascot moved, sold or changed.
	if
		menuFor
		and (
			uidIn(menuFor) ~= menuUid
			or menuLocked ~= (menuUid and data.mascots[menuUid] and data.mascots[menuUid].locked)
		)
	then
		closeMenu()
	end
end

local function makeSlot(bar: Frame, place: "hotbar" | "onDeck", index: number, x: number): Slot
	local button = Instance.new("TextButton")
	button.Name = if place == "onDeck" then "OnDeck" else `Hotbar{index}`
	button.Text = ""
	button.AutoButtonColor = true
	button.Position = UDim2.fromOffset(x, LABEL)
	button.Size = UDim2.fromOffset(SLOT, SLOT)
	button.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	button.Parent = bar
	Instance.new("UICorner").Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local name = text(button, {
		Name = "MascotName",
		Position = UDim2.fromScale(0.06, 0.08),
		Size = UDim2.fromScale(0.88, 0.5),
		TextWrapped = true,
	})
	local cash = text(button, {
		Name = "Cash",
		Position = UDim2.fromScale(0.06, 0.62),
		Size = UDim2.fromScale(0.88, 0.3),
		TextColor3 = Color3.fromRGB(255, 220, 90),
	})
	local lock = text(button, {
		Name = "Lock",
		Text = "🔒",
		Position = UDim2.new(1, -18, 0, -6),
		Size = UDim2.fromOffset(20, 20),
		Visible = false,
	})
	local slot: Slot = {
		button = button,
		stroke = stroke,
		name = name,
		cash = cash,
		lock = lock,
		place = place,
		index = index,
	}
	button.Activated:Connect(function()
		if menuFor == slot then
			closeMenu()
		else
			openMenu(slot)
		end
	end)
	return slot
end

function HotbarController.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Hotbar"
	gui.ResetOnSpawn = false
	-- Above the Mascots panel (18) and the catch toast (20), so an open slot menu is never
	-- covered or has its taps taken.
	gui.DisplayOrder = 21

	local width = 4 * SLOT + 3 * GAP + DECK_GAP + SLOT
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundTransparency = 1
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, MARGIN, 1, -MARGIN)
	bar.Size = UDim2.fromOffset(width, SLOT + LABEL)
	bar.Parent = gui

	text(bar, {
		Name = "HotbarLabel",
		Text = "HOTBAR (doesn't earn)",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(4 * SLOT + 3 * GAP, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(220, 225, 235),
	})
	text(bar, {
		Name = "OnDeckLabel",
		Text = "ON DECK",
		Position = UDim2.fromOffset(width - SLOT, 0),
		Size = UDim2.fromOffset(SLOT, 14),
		TextColor3 = Color3.fromRGB(255, 200, 120),
	})
	for i = 1, 4 do
		table.insert(slots, makeSlot(bar, "hotbar", i, (i - 1) * (SLOT + GAP)))
	end
	table.insert(slots, makeSlot(bar, "onDeck", 1, width - SLOT))

	menu = Instance.new("Frame")
	menu.Name = "SlotMenu"
	menu.AnchorPoint = Vector2.new(0, 1)
	menu.AutomaticSize = Enum.AutomaticSize.XY
	menu.BackgroundTransparency = 1
	menu.Visible = false
	menu.ZIndex = 5
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = menu
	menu.Parent = gui

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function HotbarController.Start()
	StateController.Ready:Connect(redraw)
	StateController.Changed:Connect(function(key: string)
		if key == "hotbar" or key == "onDeck" or key == "mascots" or key == "seats" then
			redraw()
		end
	end)
	redraw()
end

return HotbarController
