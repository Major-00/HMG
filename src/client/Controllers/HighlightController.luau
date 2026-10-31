--!strict
-- HighlightController: the big moments of a hit. Display only.
--   * Highlight "biome" (from HighlightService, first time this run): when the ball crosses that
--     biome's start line, "PERFECT!" plus a big banner with the biome name and the crossing
--     distance. Several new biomes in one hit queue one after another. The catch reveal hooks in later.
--   * Highlight "record" (the best distance passed a milestone): "PERFECT!" as the ball passes it.
--     Celebrations are given on milestones, never for tap skill (CLAUDE.md guardrail 5).
--   * Every landing: the distance pops up at the landing spot, then `Landed` fires.
--   * The Mascot caught (HitResult.catch): a toast with where it went and anything sold to make
--     room ("Sold Frog +$120"). Shown when the catch reveal ends (CatchRevealController shows the
--     Mascot itself), or at the landing / when the result arrives if there was no reveal.
--   HighlightController.Landed -> Signal ({ hitId, segmentIndex, position, distance, biomeName, isFinal })
--     The client side of the on-land hook, at the moment the ball visibly lands. The server's
--     on-land hook (LandingService) already ran at hit time, because the catch depends on it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Biomes = require(Config:WaitForChild("Biomes"))[1] -- World 1 (the world follows stadiumTier from the World 2 step)
local Format = require(Shared:WaitForChild("Format"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Mascots = require(Config:WaitForChild("Mascots"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Tuning = require(Config:WaitForChild("Tuning"))

local BallController = require(script.Parent.BallController)
local UILayout = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("UILayout"))
local CameraController = require(script.Parent.CameraController)
local HudController = require(script.Parent.HudController)

local LAUNCH_WAIT = 1 -- seconds to wait for a highlight's flight before showing the banner anyway
local POPUP_LIFETIME = 1.4
local POPUP_POOL = 3

type Popup = { anchor: Part, gui: BillboardGui, distance: TextLabel, biome: TextLabel, scale: UIScale }

local HighlightController = {}

HighlightController.Landed = Signal.new()

local bannerFrame: Frame
local bannerTitle: TextLabel
local bannerSub: TextLabel
local bannerQueue: { number } = {}
local bannerBusy = false
-- A celebration waiting for the ball to pass `distance`.
type Moment = { distance: number, show: () -> () }
local waiting: { [number]: { Moment } } = {} -- hitId -> moments whose flight hasn't started
local popups: { Popup } = {}
local nextPopup = 1
local worldFolder: Folder

local CATCH_TOAST_TIME = 1.8 -- seconds the catch toast stays fully visible
local CATCH_MEMORY = 20 -- seconds a catch or landing is remembered while waiting for the other

local toastFrame: Frame
local toastTitle: TextLabel
local toastDetail: TextLabel
local toastSold: TextLabel
local toastShownAt = 0
local toastFades: { Tween } = {} -- the fade-out playing, cancelled when a new toast shows
local catchesWaiting: { [number]: { catch: any, at: number } } = {} -- hitId -> catch not landed yet
local landedHits: { [number]: number } = {} -- hitId -> when its final landing showed
local catchShown: { [number]: boolean } = {}
local revealing: { [number]: boolean } = {} -- hitId -> its catch reveal is playing

local function text(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.2
	l.TextScaled = true
	for key, value in props do
		(l :: any)[key] = value
	end
	return l
end

local function setBannerAlpha(alpha: number)
	bannerTitle.TextTransparency = alpha
	bannerTitle.TextStrokeTransparency = 0.2 + 0.8 * alpha
	bannerSub.TextTransparency = alpha
	bannerSub.TextStrokeTransparency = 0.2 + 0.8 * alpha
end

local playNextBanner: () -> ()

local function showBanner(biomeIndex: number)
	table.insert(bannerQueue, biomeIndex)
	if not bannerBusy then
		playNextBanner()
	end
end

playNextBanner = function()
	local index = table.remove(bannerQueue, 1)
	if index == nil then
		bannerBusy = false
		bannerFrame.Visible = false
		return
	end
	bannerBusy = true
	local biome = Biomes[index]
	bannerTitle.Text = string.upper(biome.displayName)
	bannerTitle.TextColor3 = biome.visual.accent
	bannerSub.Text = `NEW BIOME!  {Format.number(Tuning.BiomeStarts[index])} studs`
	bannerFrame.Position = UDim2.fromScale(0.5, 0.08)
	bannerFrame.Visible = true
	setBannerAlpha(0)

	local slideIn = TweenService:Create(
		bannerFrame,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.24) }
	)
	slideIn:Play()
	task.spawn(function()
		-- Hold for BANNER_TIME, or less when the ball has already crossed into another new biome.
		local h = Tuning.Highlight
		local shownAt = os.clock()
		repeat
			task.wait()
			local held = os.clock() - shownAt - 0.35
		until held >= h.BANNER_TIME or (held >= h.BANNER_QUEUED_TIME and #bannerQueue > 0)
		local start = os.clock()
		local fadeTime = 0.35
		while os.clock() - start < fadeTime do
			setBannerAlpha((os.clock() - start) / fadeTime)
			task.wait()
		end
		setBannerAlpha(1)
		playNextBanner()
	end)
end

local function watch(hitId: number, moment: Moment): boolean
	return BallController.WatchDistance(hitId, moment.distance, moment.show)
end

local function onHighlight(highlight: any)
	if type(highlight) ~= "table" or type(highlight.hitId) ~= "number" then
		return
	end
	local hitId = highlight.hitId
	local moment: Moment
	if highlight.kind == "biome" then
		local index = highlight.biomeIndex
		if type(index) ~= "number" or Biomes[index] == nil then
			return
		end
		moment = {
			distance = Tuning.BiomeStarts[index],
			show = function()
				HudController.Celebrate(hitId)
				showBanner(index)
			end,
		}
	elseif highlight.kind == "record" and type(highlight.distance) == "number" then
		moment = {
			distance = highlight.distance,
			show = function()
				HudController.Celebrate(hitId)
			end,
		}
	else
		return
	end

	if watch(hitId, moment) then
		return
	end
	-- No flight for this hit yet (or it was dropped). Wait briefly, then show it regardless.
	local list = waiting[hitId]
	if list == nil then
		list = {}
		waiting[hitId] = list
		task.delay(LAUNCH_WAIT, function()
			local left = waiting[hitId]
			waiting[hitId] = nil
			for _, m in left or {} do
				m.show()
			end
		end)
	end
	table.insert(list, moment)
end

local function onLaunched(hitId: number)
	local list = waiting[hitId]
	if list == nil then
		return
	end
	waiting[hitId] = nil
	for _, moment in list do
		if not watch(hitId, moment) then
			moment.show()
		end
	end
end

local function makePopup(): Popup
	local anchor = Instance.new("Part")
	anchor.Name = "LandingPopup"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 90)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Adornee = anchor
	gui.Parent = anchor

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local distance = text({ Size = UDim2.fromScale(1, 0.65), Parent = holder })
	local biome = text({
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0, 0.65),
		Size = UDim2.fromScale(1, 0.35),
		Parent = holder,
	})
	return { anchor = anchor, gui = gui, distance = distance, biome = biome, scale = scale }
end

local function showLanding(position: Vector3, distance: number)
	local popup = popups[nextPopup]
	nextPopup = nextPopup % #popups + 1

	local index = Formulas.biomeIndexAt(distance)
	popup.anchor.Position = position
	popup.anchor.Parent = worldFolder
	popup.distance.Text = `{Format.number(distance)} studs`
	popup.biome.Text = Biomes[index].displayName
	popup.biome.TextColor3 = Biomes[index].visual.accent
	popup.gui.Enabled = true
	for _, l in { popup.distance, popup.biome } do
		l.TextTransparency = 0
		l.TextStrokeTransparency = 0.2
	end
	popup.scale.Scale = 0.3
	TweenService:Create(popup.scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	local shownAt = os.clock()
	popup.anchor:SetAttribute("ShownAt", shownAt)
	local fadeInfo = TweenInfo.new(0.4)
	task.delay(POPUP_LIFETIME - 0.4, function()
		if popup.anchor:GetAttribute("ShownAt") ~= shownAt then
			return -- reused for a newer landing
		end
		for _, l in { popup.distance, popup.biome } do
			TweenService:Create(l, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
		task.delay(0.4, function()
			if popup.anchor:GetAttribute("ShownAt") == shownAt then
				popup.gui.Enabled = false
				popup.anchor.Parent = nil
			end
		end)
	end)
end

local function displayNameIn(list: { any }, id: string): string?
	for _, entry in list do
		if entry.id == id then
			return entry.displayName
		end
	end
	return nil
end

local function rarityOf(id: string): any
	return Mascots.Rarities[Mascots.RarityRank[id] or 1]
end

local playToast: (notice: any?) -> ()

local function showCatch(hitId: number, catch: any)
	if catchShown[hitId] then
		return
	end
	catchShown[hitId] = true
	local species = Mascots.ById[catch.species]
	if species == nil then
		return
	end
	local rarity = rarityOf(species.rarity)
	toastTitle.Text = `{if catch.isNewSpecies then "NEW! " else ""}Caught {species.displayName}!`
	toastTitle.TextColor3 = rarity.color

	local parts = { rarity.displayName }
	local variant = displayNameIn(Tuning.Catch.VARIANTS, catch.variant)
	if variant then
		table.insert(parts, variant)
	end
	local size = displayNameIn(Tuning.Catch.SIZES, catch.size)
	if size then
		table.insert(parts, size)
	end
	table.insert(parts, `${Format.number(catch.cashPerSec)}/s`)
	if catch.placedIn == "seat" then
		table.insert(parts, `Seat {catch.slot}`)
	elseif catch.placedIn == "hotbar" then
		table.insert(parts, `Hotbar {catch.slot}`)
	elseif catch.placedIn == "onDeck" then
		table.insert(parts, "On Deck")
	end
	toastDetail.Text = table.concat(parts, "  ·  ")

	local sold = catch.sold
	local soldSpecies = if type(sold) == "table" then Mascots.ById[sold.species] else nil
	if soldSpecies then
		toastSold.Text = `Sold {soldSpecies.displayName} +${Format.number(sold.cash)}`
		toastSold.Visible = true
	else
		toastSold.Visible = false
	end
	playToast()
end

-- Notices ("New ball unlocked!") wait for the toast to be free, so they never cut off a catch,
-- and one that a catch interrupts within NOTICE_MIN_SECONDS is shown again afterwards.
type Notice = { title: string, detail: string, color: Color3 }
local NOTICE_MIN_SECONDS = 1
local notices: { Notice } = {}
local showingNotice: { notice: Notice, at: number }? = nil
local pumpNotices: () -> ()

-- Shows whatever is in the toast labels, then fades it out after CATCH_TOAST_TIME.
-- `notice` is set when the toast is showing a queued notice.
playToast = function(notice: Notice?)
	local current = showingNotice
	if current and os.clock() - current.at < NOTICE_MIN_SECONDS then
		table.insert(notices, 1, current.notice) -- cut short: show it again later
	end
	showingNotice = if notice then { notice = notice, at = os.clock() } else nil
	-- Stop the previous toast's fade, or it would keep fading this one out.
	for _, tween in toastFades do
		tween:Cancel()
	end
	table.clear(toastFades)
	toastFrame.Visible = true
	toastFrame.BackgroundTransparency = 0.35
	for _, l in { toastTitle, toastDetail, toastSold } do
		l.TextTransparency = 0
		l.TextStrokeTransparency = 0.3
	end
	local shownAt = os.clock()
	toastShownAt = shownAt
	task.delay(CATCH_TOAST_TIME, function()
		if toastShownAt ~= shownAt then
			return -- a newer catch took over the toast
		end
		local fade = TweenInfo.new(0.4)
		table.insert(toastFades, TweenService:Create(toastFrame, fade, { BackgroundTransparency = 1 }))
		for _, l in { toastTitle, toastDetail, toastSold } do
			table.insert(
				toastFades,
				TweenService:Create(l, fade, { TextTransparency = 1, TextStrokeTransparency = 1 })
			)
		end
		for _, tween in toastFades do
			tween:Play()
		end
		task.delay(0.4, function()
			if toastShownAt == shownAt then
				toastFrame.Visible = false
				showingNotice = nil
				pumpNotices()
			end
		end)
	end)
end

-- A Mascot the player sold by tap: "Sold Gumdrop Frog +$300". Shares the catch toast.
function HighlightController.ShowSold(speciesId: string, cash: number)
	local species = Mascots.ById[speciesId]
	if species == nil then
		return
	end
	toastTitle.Text = `Sold {species.displayName}`
	toastTitle.TextColor3 = Color3.fromRGB(255, 220, 90)
	toastDetail.Text = `+${Format.number(cash)}`
	toastSold.Visible = false
	playToast()
end

-- Shows the next queued notice if the toast is free.
pumpNotices = function()
	if toastFrame.Visible then
		return
	end
	local notice = table.remove(notices, 1)
	if notice == nil then
		return
	end
	toastTitle.Text = notice.title
	toastTitle.TextColor3 = notice.color
	toastDetail.Text = notice.detail
	toastSold.Visible = false
	playToast(notice)
end

-- A short notice in the same toast (e.g. "New ball unlocked!"), shown once the toast is free.
function HighlightController.ShowNotice(title: string, detail: string, color: Color3)
	table.insert(notices, { title = title, detail = detail, color = color })
	pumpNotices()
end

local function forgetOld()
	local cutoff = os.clock() - CATCH_MEMORY
	for hitId, at in landedHits do
		if at < cutoff then
			landedHits[hitId] = nil
			catchShown[hitId] = nil
		end
	end
	for hitId, waitingCatch in catchesWaiting do
		if waitingCatch.at < cutoff then
			catchesWaiting[hitId] = nil
		end
	end
end

local function onHitResult(result: any)
	if type(result) ~= "table" or type(result.hitId) ~= "number" or type(result.catch) ~= "table" then
		return
	end
	if landedHits[result.hitId] then
		showCatch(result.hitId, result.catch) -- the ball already landed: show it now
	else
		catchesWaiting[result.hitId] = { catch = result.catch, at = os.clock() }
	end
end

local function onRevealStarted(hitId: number)
	revealing[hitId] = true
end

-- The reveal is over (played out or skipped): now show the catch toast with its details.
local function onRevealEnded(hitId: number)
	revealing[hitId] = nil
	local waitingCatch = catchesWaiting[hitId]
	if waitingCatch then
		catchesWaiting[hitId] = nil
		showCatch(hitId, waitingCatch.catch)
	end
end

local function onTouchdown(
	hitId: number,
	segmentIndex: number,
	position: Vector3,
	distance: number,
	isFinal: boolean
)
	showLanding(position, distance)
	if isFinal then
		forgetOld()
		landedHits[hitId] = landedHits[hitId] or os.clock()
		if catchesWaiting[hitId] then
			-- Let the camera react to this landing first: if it starts the catch reveal, the toast
			-- waits for the reveal to end (so the Mascot's name isn't shown twice).
			task.defer(function()
				local waitingCatch = catchesWaiting[hitId]
				if waitingCatch and not revealing[hitId] then
					catchesWaiting[hitId] = nil
					showCatch(hitId, waitingCatch.catch)
				end
			end)
		end
	end
	HighlightController.Landed:Fire({
		hitId = hitId,
		segmentIndex = segmentIndex,
		position = position,
		distance = distance,
		biomeName = Formulas.biomeNameAt(distance),
		isFinal = isFinal,
	})
end

function HighlightController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Highlights"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.IgnoreGuiInset = true

	bannerFrame = Instance.new("Frame")
	bannerFrame.Name = "Banner"
	bannerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	bannerFrame.BackgroundTransparency = 1
	bannerFrame.Size = UDim2.fromScale(0.8, 0.22)
	bannerFrame.Visible = false
	bannerFrame.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(900, 200)
	limit.Parent = bannerFrame
	bannerTitle = text({ Name = "Title", Size = UDim2.fromScale(1, 0.68), Parent = bannerFrame })
	bannerSub = text({
		Name = "Sub",
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0, 0.7),
		Size = UDim2.fromScale(1, 0.3),
		Parent = bannerFrame,
	})
	-- Catch toast: bottom center, clear of the SWING button (bottom right).
	toastFrame = Instance.new("Frame")
	toastFrame.Name = "CatchToast"
	toastFrame.AnchorPoint = Vector2.new(0.5, 1)
	-- Above the hotbar and the Mascots / Shop buttons, so it never hides them.
	toastFrame.Position = UDim2.new(0.5, 0, 1, -(UILayout.BOTTOM_BAR + 8 + UILayout.PANEL_BUTTON.Y + 8))
	toastFrame.Size = UDim2.fromScale(0.44, 0.17) -- narrow enough to clear SWING on small phones
	toastFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	toastFrame.BackgroundTransparency = 1
	toastFrame.Visible = false
	-- Its own ScreenGui with the default insets, the same as the hotbar's, so "above the hotbar"
	-- holds on notched phones too (the banner gui ignores the insets).
	local toastGui = Instance.new("ScreenGui")
	toastGui.Name = "CatchToast"
	toastGui.ResetOnSpawn = false
	toastGui.DisplayOrder = 20
	toastGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	toastFrame.Parent = toastGui
	local toastLimit = Instance.new("UISizeConstraint")
	toastLimit.MaxSize = Vector2.new(520, 120)
	toastLimit.Parent = toastFrame
	Instance.new("UICorner").Parent = toastFrame
	toastTitle = text({
		Name = "Title",
		Position = UDim2.fromScale(0.04, 0.06),
		Size = UDim2.fromScale(0.92, 0.42),
		Parent = toastFrame,
	})
	toastDetail = text({
		Name = "Detail",
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0.04, 0.5),
		Size = UDim2.fromScale(0.92, 0.22),
		Parent = toastFrame,
	})
	toastSold = text({
		Name = "Sold",
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(255, 220, 90),
		Position = UDim2.fromScale(0.04, 0.74),
		Size = UDim2.fromScale(0.92, 0.2),
		Parent = toastFrame,
	})

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	worldFolder = Instance.new("Folder")
	worldFolder.Name = "ClientPopups"
	worldFolder.Parent = workspace
	for i = 1, POPUP_POOL do
		popups[i] = makePopup()
	end
end

function HighlightController.Start()
	Remotes.Event("Highlight").OnClientEvent:Connect(onHighlight)
	Remotes.Event("HitResult").OnClientEvent:Connect(onHitResult)
	BallController.Launched:Connect(onLaunched)
	BallController.Touchdown:Connect(onTouchdown)
	CameraController.RevealStarted:Connect(onRevealStarted)
	CameraController.RevealEnded:Connect(onRevealEnded)
end

return HighlightController
