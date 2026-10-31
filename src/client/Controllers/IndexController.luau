--!strict
-- IndexController: the Mascot Index, opened with the "Index" button (third beside Mascots and
-- Shop; one side panel at a time, never over the SWING button).
--   World tabs (every world reached so far; it opens on the current one, and earlier worlds
--   stay viewable), a ◀ biome ▶ switcher, and that biome's 8 cards in a grid:
--     caught:      species color, name, rarity, how many caught, and the variants and sizes seen
--     not caught:  a dark silhouette with only its rarity as a hint
--     open slot:   "Coming soon" (biomes have 6 species at launch)
--   A card stays after every Mascot of that species is sold: the Index is permanent.
--   "NEW" marks species caught since you last opened the Index, and the Index button shows a
--   red dot while there are any. Opening the Index tells the server they've been seen.
-- Display only: everything comes from the save (index, settings.indexSeen).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Format = require(Shared:WaitForChild("Format"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Mascots = require(Config:WaitForChild("Mascots"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Config:WaitForChild("Tuning"))

local StateController = require(script.Parent.StateController)
local UILayout = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("UILayout"))

local MARGIN = UILayout.MARGIN
local BUTTON_H = UILayout.PANEL_BUTTON.Y
local CARD = Vector2.new(0.25, 118) -- a quarter of the width, this many points tall
local DARK = Color3.fromRGB(45, 48, 58)
local TAB_H = 26
local TAB_W = 96
local TAB_ON = Color3.fromRGB(150, 90, 200)
local TAB_OFF = Color3.fromRGB(50, 56, 70)

local IndexController = {}

local panel: Frame
local grid: ScrollingFrame
local biomeLabel: TextLabel
local totalLabel: TextLabel
local openButton: TextButton
local dot: Frame
local tabRow: Frame
local tabs: { TextButton } = {}
local shownWorld: number? = nil -- the world tab picked; nil = the current world
local biomeIndex = 1
local newAtOpen: { [string]: boolean } = {} -- species that were new when the panel opened
local knownIndex: { [string]: boolean } = {} -- species this client already knows are caught

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
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

-- The world the Index shows: the picked tab, or the current world.
local function world(data: any): number
	return math.clamp(shownWorld or Formulas.world(data), 1, Formulas.world(data))
end

-- Species caught but not yet seen in the Index.
local function newSpecies(data: any): { [string]: boolean }
	local seen = data.settings.indexSeen or {}
	local out = {}
	for species in data.index do
		if not seen[species] then
			out[species] = true
		end
	end
	return out
end

local function card(order: number): Frame
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.BackgroundColor3 = Color3.fromRGB(32, 38, 50)
	frame.Parent = grid
	Instance.new("UICorner").Parent = frame
	return frame
end

local function caughtCard(species: any, entry: any, order: number, isNew: boolean)
	local rarity = Mascots.Rarities[Mascots.RarityRank[species.rarity] or 1]
	local frame = card(order)
	frame.Name = species.id
	local stroke = Instance.new("UIStroke")
	stroke.Color = rarity.color
	stroke.Thickness = 2
	stroke.Parent = frame
	-- A round "portrait" in the species color.
	local portrait = Instance.new("Frame")
	portrait.AnchorPoint = Vector2.new(0.5, 0)
	portrait.Position = UDim2.new(0.5, 0, 0, 6)
	portrait.Size = UDim2.fromOffset(36, 36)
	portrait.BackgroundColor3 = species.color
	portrait.Parent = frame
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = portrait
	text(frame, {
		Name = "MascotName",
		Text = species.displayName,
		Position = UDim2.fromOffset(4, 44),
		Size = UDim2.new(1, -8, 0, 18),
	})
	text(frame, {
		Name = "Rarity",
		Text = `{rarity.displayName}  ×{Format.number(entry.count)}`,
		Font = Enum.Font.Gotham,
		TextColor3 = rarity.color,
		Position = UDim2.fromOffset(4, 64),
		Size = UDim2.new(1, -8, 0, 15),
	})
	local found = {}
	for _, v in Tuning.Catch.VARIANTS do
		if entry.variants[v.id] then
			table.insert(found, v.displayName)
		end
	end
	for _, s in Tuning.Catch.SIZES do
		if entry.sizes[s.id] then
			table.insert(found, s.displayName)
		end
	end
	text(frame, {
		Name = "Found",
		Text = if #found > 0 then table.concat(found, " · ") else "—",
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(255, 220, 90),
		TextWrapped = true,
		Position = UDim2.fromOffset(4, 82),
		Size = UDim2.new(1, -8, 0, 30),
	})
	if isNew then
		local badge = text(frame, {
			Name = "New",
			Text = "NEW",
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(230, 60, 60),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(34, 16),
		})
		Instance.new("UICorner").Parent = badge
	end
end

local function silhouetteCard(species: any, order: number)
	local rarity = Mascots.Rarities[Mascots.RarityRank[species.rarity] or 1]
	local frame = card(order)
	frame.Name = species.id
	frame.BackgroundColor3 = DARK
	local portrait = Instance.new("Frame")
	portrait.AnchorPoint = Vector2.new(0.5, 0)
	portrait.Position = UDim2.new(0.5, 0, 0, 6)
	portrait.Size = UDim2.fromOffset(36, 36)
	portrait.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	portrait.Parent = frame
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = portrait
	text(frame, {
		Name = "MascotName",
		Text = "???",
		TextColor3 = Color3.fromRGB(150, 150, 160),
		Position = UDim2.fromOffset(4, 44),
		Size = UDim2.new(1, -8, 0, 18),
	})
	text(frame, {
		Name = "Rarity",
		Text = rarity.displayName,
		Font = Enum.Font.Gotham,
		TextColor3 = rarity.color,
		Position = UDim2.fromOffset(4, 64),
		Size = UDim2.new(1, -8, 0, 15),
	})
end

local function comingSoonCard(order: number)
	local frame = card(order)
	frame.Name = `ComingSoon{order}`
	frame.BackgroundTransparency = 0.5
	text(frame, {
		Name = "ComingSoon",
		Text = "Coming soon",
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(150, 150, 160),
		Position = UDim2.new(0, 6, 0.4, 0),
		Size = UDim2.new(1, -12, 0, 18),
	})
end

local function updateDot()
	local data = StateController.Get()
	dot.Visible = data ~= nil and next(newSpecies(data)) ~= nil
end

local redraw: () -> ()
redraw = function()
	updateDot()
	local data = StateController.Get()
	if data == nil or not panel.Visible then
		return
	end
	local w = world(data)
	local biomes = Formulas.biomes(w)
	biomeIndex = math.clamp(biomeIndex, 1, #biomes)
	local biome = biomes[biomeIndex]
	local list = Mascots.Worlds[w][biome.id] or {}

	local caughtHere, caughtAll, totalAll = 0, 0, 0
	for _, speciesList in Mascots.Worlds[w] do
		for _, species in speciesList do
			totalAll += 1
			if data.index[species.id] then
				caughtAll += 1
			end
		end
	end
	for _, species in list do
		if data.index[species.id] then
			caughtHere += 1
		end
	end
	biomeLabel.Text = `{biome.displayName}  {caughtHere}/{#list}`
	biomeLabel.TextColor3 = biome.visual.accent
	totalLabel.Text = `World {w}: {caughtAll}/{totalAll} species caught`

	-- One tab per world reached; there's no way back to play one, but its cards stay viewable.
	local reached = Formulas.world(data)
	for i = 1, math.max(reached, #tabs) do
		local tab = tabs[i]
		if tab == nil then
			local index = i
			tab = button(tabRow, `World {i}`, TAB_OFF, {
				Name = `World{i}`,
				LayoutOrder = i,
				Size = UDim2.fromOffset(TAB_W, TAB_H),
			})
			tab.Activated:Connect(function()
				shownWorld = index
				biomeIndex = 1
				redraw()
			end)
			tabs[i] = tab
		end
		tab.Visible = i <= reached
		tab.BackgroundColor3 = if i == w then TAB_ON else TAB_OFF
	end
	-- The tab row only takes space once there's a second world to pick (small phones need it).
	tabRow.Visible = reached > 1
	local extra = if tabRow.Visible then TAB_H + 6 else 0
	totalLabel.Position = UDim2.fromOffset(10, 8 + BUTTON_H + 4 + extra)
	local top = 8 + BUTTON_H + 4 + extra + 18 + 6
	grid.Position = UDim2.fromOffset(8, top)
	grid.Size = UDim2.new(1, -8, 1, -(top + 8))

	for _, child in grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i = 1, Mascots.SLOTS_PER_BIOME do
		local species = list[i]
		if species == nil then
			comingSoonCard(i)
		elseif data.index[species.id] then
			caughtCard(species, data.index[species.id], i, newAtOpen[species.id] == true)
		else
			silhouetteCard(species, i)
		end
	end
end

local function markSeen()
	local remote = Remotes.Function("MarkIndexSeen")
	task.spawn(pcall, remote.InvokeServer, remote)
end

function IndexController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Index"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 17

	local barTop = UILayout.BOTTOM_BAR + 8
	openButton = button(gui, "Index", Color3.fromRGB(150, 90, 200), {
		Name = "OpenButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, MARGIN + 2 * (UILayout.PANEL_BUTTON.X + 8), 1, -barTop),
		Size = UDim2.fromOffset(UILayout.PANEL_BUTTON.X, BUTTON_H),
	})
	dot = Instance.new("Frame")
	dot.Name = "NewDot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.new(1, -4, 0, 4)
	dot.Size = UDim2.fromOffset(14, 14)
	dot.BackgroundColor3 = Color3.fromRGB(230, 60, 60)
	dot.Visible = false
	dot.Parent = openButton
	local dotRound = Instance.new("UICorner")
	dotRound.CornerRadius = UDim.new(0.5, 0)
	dotRound.Parent = dot

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

	local prev = button(panel, "◀", Color3.fromRGB(50, 56, 70), {
		Name = "Prev",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(BUTTON_H, BUTTON_H),
	})
	biomeLabel = text(panel, {
		Name = "Biome",
		Position = UDim2.fromOffset(8 + BUTTON_H + 6, 8),
		Size = UDim2.new(1, -(16 + 3 * BUTTON_H + 18), 0, BUTTON_H),
	})
	local nextButton = button(panel, "▶", Color3.fromRGB(50, 56, 70), {
		Name = "Next",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(8 + BUTTON_H + 6), 0, 8),
		Size = UDim2.fromOffset(BUTTON_H, BUTTON_H),
	})
	local close = button(panel, "X", Color3.fromRGB(90, 60, 60), {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(BUTTON_H, BUTTON_H),
	})
	tabRow = Instance.new("Frame")
	tabRow.Name = "WorldTabs"
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromOffset(8, 8 + BUTTON_H + 6)
	tabRow.Size = UDim2.new(1, -16, 0, TAB_H)
	tabRow.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabRow

	totalLabel = text(panel, {
		Name = "Total",
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(200, 205, 215),
		Position = UDim2.fromOffset(10, 8 + BUTTON_H + 6 + TAB_H + 4),
		Size = UDim2.new(1, -20, 0, 18),
	})

	local top = 8 + BUTTON_H + 6 + TAB_H + 4 + 18 + 6
	grid = Instance.new("ScrollingFrame")
	grid.Name = "Cards"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(8, top)
	grid.Size = UDim2.new(1, -8, 1, -(top + 8))
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollBarThickness = 6
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(CARD.X, -8, 0, CARD.Y)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local function show(visible: boolean)
		panel.Visible = visible
		if visible then
			shownWorld = nil -- open on the current world, at its first biome
			biomeIndex = 1
			local data = StateController.Get()
			newAtOpen = if data then newSpecies(data) else {}
			markSeen()
		end
		redraw()
		UILayout.PanelChanged:Fire(if visible then "index" else nil)
	end
	UILayout.PanelChanged:Connect(function(name: string?)
		if name ~= "index" then
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
	prev.Activated:Connect(function()
		local data = StateController.Get()
		local count = if data then #Formulas.biomes(world(data)) else 1
		biomeIndex = (biomeIndex - 2) % count + 1
		redraw()
	end)
	nextButton.Activated:Connect(function()
		local data = StateController.Get()
		local count = if data then #Formulas.biomes(world(data)) else 1
		biomeIndex = biomeIndex % count + 1
		redraw()
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function IndexController.Start()
	StateController.Ready:Connect(redraw)
	StateController.Changed:Connect(function(key: string)
		if key == "index" or key == "settings" or key == "stadiumTier" then
			if key == "stadiumTier" and shownWorld == nil then
				biomeIndex = 1 -- the shown world just changed under the panel
			end
			local data = StateController.Get()
			if key == "index" and data then
				-- A species is new here if this client hadn't seen it in the Index yet. Compared
				-- with our own last copy, not settings.indexSeen, which may arrive first in the
				-- same update and already include it.
				local added = false
				for species in data.index do
					if not knownIndex[species] then
						knownIndex[species] = true
						added = true
						if panel.Visible then
							newAtOpen[species] = true -- caught while looking: it gets its badge
						end
					end
				end
				if added and panel.Visible then
					markSeen()
				end
			end
			redraw()
		end
	end)
	local function learnIndex()
		local data = StateController.Get()
		if data then
			for species in data.index do
				knownIndex[species] = true
			end
		end
	end
	StateController.Ready:Connect(learnIndex)
	learnIndex() -- the save may already have arrived before this started
	redraw()
end

return IndexController
