--!strict
-- HighlightController: the big moments of a hit. Display only.
--   * Highlight "biome" (from HighlightService, first time this run): when the ball crosses that
--     biome's start line, "PERFECT!" plus a big banner with the biome name and the crossing
--     distance. Several new biomes in one hit queue one after another. A camera pet hooks in later.
--   * Highlight "record" (the best distance passed a milestone): "PERFECT!" as the ball passes it.
--     Celebrations are given on milestones, never for tap skill (CLAUDE.md guardrail 5).
--   * Every landing: the distance pops up at the landing spot, then `Landed` fires.
--   HighlightController.Landed -> Signal ({ hitId, segmentIndex, position, distance, biomeName, isFinal })
--     The client side of the on-land hook, at the moment the ball visibly lands. The server's
--     on-land hook (LandingService) already ran at hit time, because Wins depend on it.

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

local BallController = require(script.Parent.BallController)
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

local function onTouchdown(
	hitId: number,
	segmentIndex: number,
	position: Vector3,
	distance: number,
	isFinal: boolean
)
	showLanding(position, distance)
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
	BallController.Launched:Connect(onLaunched)
	BallController.Touchdown:Connect(onTouchdown)
end

return HighlightController
