--!strict
-- SwingAnimator: the batter's full-body animations, on the local character (animations played
-- there replicate, so everyone sees the swing). Visual only (CLAUDE.md guardrail 4).
--   Stance (loop, Idle priority): bat on the shoulder, breathing and a small weight shift. Only
--     while standing on the ground: the default walk and jump animations are Core priority, below
--     Idle, so it's stopped while moving or in the air.
--   Carry (loop, Action priority, upper body): bat on the shoulder while walking.
--   Swing, one per Power tier (Action4): toss, load, swing, contact, follow-through. Markers:
--     "Release" (the glove hand lets go of the ball), "Contact" (bat on ball: the hit-stop
--     starts), "Finish" (the follow-through's last pose, held until the camera is back).
-- Where the animations come from (Tuning.Fungo.ANIMATIONS):
--   a published id ("rbxassetid://...") when one is set; otherwise, in Studio only, the
--   KeyframeSequence of the same name in ReplicatedStorage.Animations (assets/Animations, made
--   by tools/animations/generate.py), registered with KeyframeSequenceProvider. With neither
--   (or an R6 character) Swing returns false and FungoController uses its simple swing.
--   SwingAnimator.HasSwing(tierIndex) -> true if that tier's swing animation is loaded
--   SwingAnimator.Swing(tierIndex, handlers) -> true if the swing animation plays
--     handlers = { release: () -> (), contact: () -> () }
--   SwingAnimator.CancelHold() -> ends a held follow-through now (fades back to the stance)

local ContentProvider = game:GetService("ContentProvider")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local SwingData = require(script.Parent:WaitForChild("SwingData"))

local player = Players.LocalPlayer

local MOVING = 0.1 -- MoveDirection magnitude that counts as walking
local CARRY_FADE = 0.3
local SWING_FADE = 0.12 -- blend into a swing (the toss starts slowly, so contact still lands on time)
local CUT_FADE = 0.2 -- a follow-through cut short by walking or a new toss
local HOLD_AFTER_CAMERA = 1.2 -- seconds the finish pose stays once the camera is back
local RELEASE_FADE = 0.6 -- settle back into the stance after the hold

type Handlers = { release: () -> (), contact: () -> () }

local SwingAnimator = {}

local registered: { [string]: string } = {} -- KeyframeSequence name -> temporary id (Studio)
local stance: AnimationTrack? = nil
local carry: AnimationTrack? = nil
-- Two tracks per tier, used in turn, so a new toss of the same tier can blend out of the last
-- follow-through instead of restarting the one track.
local swings: { { AnimationTrack } } = {}
local active: AnimationTrack? = nil -- the swing playing or held
local handlers: Handlers? = nil
local held = false
local cameraBackAt: number? = nil
local warned = false -- the missing-animations warning, once per session
local isCameraAway: () -> boolean = function()
	return false
end

-- The animation id for a name: the published one, else (Studio) the repo's KeyframeSequence.
local function resolve(name: string, published: string?): string?
	if published and published ~= "" then
		return published
	end
	if not RunService:IsStudio() then
		return nil
	end
	if registered[name] then
		return registered[name]
	end
	local folder = ReplicatedStorage:FindFirstChild("Animations")
	local kfs = folder and folder:FindFirstChild(name)
	if kfs == nil or not kfs:IsA("KeyframeSequence") then
		return nil
	end
	local ok, id = pcall(KeyframeSequenceProvider.RegisterKeyframeSequence, KeyframeSequenceProvider, kfs)
	if ok then
		registered[name] = id
		return id
	end
	return nil
end

local preload: { Instance } = {}

local function load(animator: Animator, name: string, published: string?): AnimationTrack?
	local id = resolve(name, published)
	if id == nil then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	table.insert(preload, animation)
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	return if ok then track else nil
end

local function endHold(fade: number)
	local track = active
	active = nil
	handlers = nil
	held = false
	cameraBackAt = nil
	if track then
		track:Stop(fade)
	end
end

local function setup(character: Model)
	stance, carry, active, handlers, held = nil, nil, nil, nil, false
	table.clear(swings)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid == nil or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return -- R6: FungoController keeps its simple swing
	end
	local animator = humanoid:WaitForChild("Animator", 10) :: Animator?
	if animator == nil then
		return
	end
	local ids = Tuning.Fungo.ANIMATIONS
	table.clear(preload)
	stance = load(animator, SwingData.STANCE, ids.stance)
	carry = load(animator, SwingData.CARRY, ids.carry)
	local function swingTrack(name: string, published: string?): AnimationTrack?
		local track = load(animator, name, published)
		if track == nil then
			return nil
		end
		local t = track :: AnimationTrack
		t.Priority = Enum.AnimationPriority.Action4
		t:GetMarkerReachedSignal("Release"):Connect(function()
			if active == t and handlers then
				handlers.release()
			end
		end)
		t:GetMarkerReachedSignal("Contact"):Connect(function()
			if active == t and handlers then
				handlers.contact()
			end
		end)
		t:GetMarkerReachedSignal("Finish"):Connect(function()
			if active == t then
				t:AdjustSpeed(0) -- hold the finish pose
				held = true
			end
		end)
		return t
	end
	for i, tier in SwingData.TIERS do
		local a = swingTrack(tier.name, ids.swings[i])
		local b = a and swingTrack(tier.name, ids.swings[i])
		if a == nil or b == nil then
			table.clear(swings) -- all tiers or none, so every tier swings the same way
			break
		end
		swings[i] = { a, b }
	end
	if #swings == 0 and not warned then
		warned = true
		warn(
			"[SwingAnimator] The swing animations aren't published yet (Tuning.Fungo.ANIMATIONS is empty, and"
				.. " only a Studio play test can preview them), so the simple swing plays. Publish them and paste"
				.. " the ids: see docs/ARCHITECTURE.md, 'Publishing the animations'."
		)
	end
	if stance then
		stance.Looped = true
	end
	-- Fetch the animations now, during the stance, so the first swing is ready on the first tap.
	local list = table.clone(preload)
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
	end)
end

-- The tier's next track (the one not playing), or nil if it isn't loaded yet.
local function nextTrack(tierIndex: number): AnimationTrack?
	local pair = swings[tierIndex]
	if pair == nil then
		return nil
	end
	local track = if active == pair[1] then pair[2] else pair[1]
	return if track.Length > 0 then track else nil
end

function SwingAnimator.HasSwing(tierIndex: number): boolean
	return nextTrack(tierIndex) ~= nil
end

function SwingAnimator.Swing(tierIndex: number, swingHandlers: Handlers): boolean
	local track = nextTrack(tierIndex)
	if track == nil then
		return false -- not loaded (yet): the caller plays the simple swing
	end
	if active then
		-- A new toss cancels the last follow-through cleanly.
		local old = active
		active = nil
		old:Stop(CUT_FADE)
	end
	active = track
	handlers = swingHandlers
	held = false
	cameraBackAt = nil
	track:Play(SWING_FADE, 1, 1)
	track.TimePosition = 0
	return true
end

function SwingAnimator.CancelHold()
	if active then
		endHold(RELEASE_FADE)
	end
end

-- Studio only: an animation must be owned by whoever owns the experience (the user, or its
-- group), or live servers can't play it. Warn about any set id that isn't.
local function checkOwners()
	local ids = Tuning.Fungo.ANIMATIONS
	local list = { { "FungoStance", ids.stance }, { "FungoCarry", ids.carry } }
	for i, tier in SwingData.TIERS do
		table.insert(list, { tier.name, ids.swings[i] })
	end
	local owner = if game.CreatorType == Enum.CreatorType.Group then "Group" else "User"
	for _, entry in list do
		local name, id = entry[1], entry[2]
		local number = id and tonumber(string.match(id, "%d+"))
		if number then
			local ok, info =
				pcall(MarketplaceService.GetProductInfo, MarketplaceService, number, Enum.InfoType.Asset)
			local creator = ok and info and info.Creator
			if creator and (creator.CreatorType ~= owner or creator.CreatorTargetId ~= game.CreatorId) then
				warn(
					`[SwingAnimator] {name} ({id}) is owned by {creator.CreatorType} {creator.CreatorTargetId}, but this`
						.. ` experience is owned by {owner} {game.CreatorId}: live servers can't play it. Publish it`
						.. " again with Creator set to the experience's owner and paste the new id."
				)
			end
		end
	end
end

-- `away` says whether the ball-cam is away (CameraController.IsActive); held finishes wait for it.
function SwingAnimator.Start(away: () -> boolean)
	isCameraAway = away
	if RunService:IsStudio() and game.CreatorId ~= 0 then
		task.spawn(checkOwners)
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(setup, character)
	end)
	if player.Character then
		task.spawn(setup, player.Character)
	end

	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil then
			return
		end
		local moving = humanoid.MoveDirection.Magnitude > MOVING and humanoid.WalkSpeed > 0
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		if stance then
			local idle = not moving and grounded
			if idle and not stance.IsPlaying then
				stance:Play(CARRY_FADE)
			elseif not idle and stance.IsPlaying then
				stance:Stop(CARRY_FADE)
			end
		end
		if carry then
			if moving and not carry.IsPlaying then
				carry:Play(CARRY_FADE)
			elseif not moving and carry.IsPlaying then
				carry:Stop(CARRY_FADE)
			end
		end
		local track = active
		if track == nil then
			return
		end
		if not track.IsPlaying then
			active, handlers, held = nil, nil, false
			return
		end
		-- Walking during the follow-through: let the legs walk (planted feet would slide).
		if moving and handlers == nil then
			endHold(CUT_FADE)
			return
		end
		if held and not isCameraAway() then
			local now = os.clock()
			cameraBackAt = cameraBackAt or now
			if now - cameraBackAt >= HOLD_AFTER_CAMERA then
				endHold(RELEASE_FADE)
			end
		end
	end)
end

-- The swing's contact has passed (FungoController): from now on walking may cut it short.
function SwingAnimator.ContactDone()
	handlers = nil
end

return SwingAnimator
