--!strict
-- SwingAnimator: the batter's animations, on the local character (animations played there
-- replicate, so everyone sees the swing). Visual only (CLAUDE.md guardrail 4).
--   Stance (loop, Idle priority): bat on the shoulder, breathing and a small weight shift. Only
--     while standing on the ground: the default walk and jump animations are Core priority, below
--     Idle, so it's stopped while moving or in the air.
--   Carry (loop, Action priority, upper body): bat on the shoulder while walking.
--   Swing, one per Power tier (Action4): toss, load, swing, contact, follow-through. Each is a
--     pair: the full-body track and its upper-body version (FungoSwingUpper...), started together.
--     The full track always plays and owns the timing and markers; while walking its weight
--     drops to almost nothing and the upper track takes over, so the legs walk. Markers:
--     "Release" (the glove hand lets go of the ball), "SwooshOn"/"SwooshOff" (the bat's arc),
--     "Contact" (bat on ball: the hit-stop starts), "Finish" (the follow-through's last pose,
--     held until the camera is back).
-- Where the animations come from (Tuning.Fungo.ANIMATIONS):
--   a published id ("rbxassetid://...") when one is set; otherwise, in Studio only, the
--   KeyframeSequence of the same name in ReplicatedStorage.Animations (assets/Animations, made
--   by tools/animations/generate.py), registered with KeyframeSequenceProvider. With neither
--   (or an R6 character) Swing returns false and FungoController uses its simple swing. No upper
--   track: the full one plays alone. A published swing whose length doesn't match SwingData is
--   an old upload: Studio plays the repo's version instead, a live server the simple swing.
--   SwingAnimator.HasSwing(tierIndex) -> true if that tier's swing animation is loaded
--   SwingAnimator.Swing(tierIndex, handlers) -> true if the swing animation plays
--     handlers = { release: () -> (), contact: () -> (), swooshOn: (() -> ())?, swooshOff: (() -> ())? }
--   SwingAnimator.CancelHold() -> ends a held follow-through now (fades back to the stance)

local ContentProvider = game:GetService("ContentProvider")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local SwingData = require(script.Parent:WaitForChild("SwingData"))

local player = Players.LocalPlayer

local MOVING = 0.1 -- MoveDirection magnitude that counts as walking
local CARRY_FADE = 0.3
local SWING_FADE = 0.03 -- blend into a swing (short, so the toss arm isn't faded out)
local WALK_FADE = 0.15 -- swap between the full-body and upper-body swing
local CUT_FADE = 0.2 -- a follow-through cut short by a new toss
local HOLD_AFTER_CAMERA = 1.2 -- seconds the finish pose stays once the camera is back
local RELEASE_FADE = 0.6 -- settle back into the stance after the hold
-- The full track's weight while walking. It keeps playing (it owns the markers), but this low
-- the legs follow the walk.
local TINY = 0.0001
local STALE_BY = 0.02 -- seconds a published swing's length may differ from SwingData

type Handlers = {
	release: () -> (),
	contact: () -> (),
	swooshOn: (() -> ())?,
	swooshOff: (() -> ())?,
}
-- One swing: the full-body track and, if loaded, its upper-body version.
type Pair = { full: AnimationTrack, upper: AnimationTrack? }
type TierSwings = {
	pairs: { Pair },
	checkFull: boolean, -- the full track is published and not yet checked against SwingData
	checkUpper: boolean,
}

local SwingAnimator = {}

local registered: { [string]: string } = {} -- KeyframeSequence name -> temporary id (Studio)
local stance: AnimationTrack? = nil
local carry: AnimationTrack? = nil
local animatorRef: Animator? = nil
-- Two pairs per tier, used in turn, so a new toss of the same tier can blend out of the last
-- follow-through instead of restarting the one track.
local swings: { [number]: TierSwings } = {}
local active: Pair? = nil -- the swing playing or held
local handlers: Handlers? = nil
local held = false
local upperOn = false -- the upper-body track leads (walking)
local noUpper = false -- this swing has no upper track to switch to
local contactPassed = false -- this swing's ball has left the bat
local cameraBackAt: number? = nil
local warned = false -- the missing-animations warning, once per session
local warnedAccess = false -- the can't-load warning, once per session
local warnedStale = false -- the old-upload warning, once per session
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

local function isPublished(id: string?): boolean
	return id ~= nil and id ~= ""
end

local function stopPair(pair: Pair, fade: number)
	pair.full:Stop(fade)
	if pair.upper then
		pair.upper:Stop(fade)
	end
end

-- Unloads tracks that were replaced (an old published upload), unless one is playing now.
local function discard(track: AnimationTrack?)
	if track and not (active and (active.full == track or active.upper == track)) then
		track:Stop(0)
		track:Destroy()
	end
end

local function endHold(fade: number)
	local pair = active
	active = nil
	handlers = nil
	held = false
	upperOn = false
	noUpper = false
	contactPassed = false
	cameraBackAt = nil
	if pair then
		stopPair(pair, fade)
	end
end

-- A full-body swing track; its markers drive the handlers and hold both tracks at the finish.
local function fullTrack(animator: Animator, name: string, published: string?): AnimationTrack?
	local track = load(animator, name, published)
	if track == nil then
		return nil
	end
	local t = track :: AnimationTrack
	t.Priority = Enum.AnimationPriority.Action4
	local function mine(): boolean
		return active ~= nil and (active :: Pair).full == t
	end
	t:GetMarkerReachedSignal("Release"):Connect(function()
		if mine() and handlers then
			handlers.release()
		end
	end)
	t:GetMarkerReachedSignal("Contact"):Connect(function()
		if mine() and handlers then
			handlers.contact()
		end
	end)
	t:GetMarkerReachedSignal("SwooshOn"):Connect(function()
		local h = handlers
		if mine() and h and h.swooshOn then
			h.swooshOn()
		end
	end)
	t:GetMarkerReachedSignal("SwooshOff"):Connect(function()
		local h = handlers
		if mine() and h and h.swooshOff then
			h.swooshOff()
		end
	end)
	t:GetMarkerReachedSignal("Finish"):Connect(function()
		if mine() then
			-- Hold the finish pose, on both tracks.
			local pair = active :: Pair
			pair.full:AdjustSpeed(0)
			if pair.upper then
				pair.upper:AdjustSpeed(0)
			end
			held = true
		end
	end)
	return t
end

local function upperTrack(animator: Animator, name: string, published: string?): AnimationTrack?
	local track = load(animator, name, published)
	if track then
		track.Priority = Enum.AnimationPriority.Action4
	end
	return track
end

local checkStale: (tierIndex: number, set: TierSwings, pair: Pair) -> () -- defined below

local function setup(character: Model)
	stance, carry, active, handlers, held, upperOn, animatorRef = nil, nil, nil, nil, false, false, nil
	table.clear(swings)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid == nil or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return -- R6: FungoController keeps its simple swing
	end
	local animator = humanoid:WaitForChild("Animator", 10) :: Animator?
	if animator == nil then
		return
	end
	animatorRef = animator
	local ids = Tuning.Fungo.ANIMATIONS
	local upperIds: { string } = ids.upperSwings or {}
	table.clear(preload)
	stance = load(animator, SwingData.STANCE, ids.stance)
	carry = load(animator, SwingData.CARRY, ids.carry)
	for i, tier in SwingData.TIERS do
		local made: { Pair } = {}
		for _ = 1, 2 do
			local full = fullTrack(animator, tier.name, ids.swings[i])
			if full == nil then
				break
			end
			table.insert(made, { full = full, upper = upperTrack(animator, tier.upperName, upperIds[i]) })
		end
		if #made < 2 then
			table.clear(swings) -- all tiers or none, so every tier swings the same way
			break
		end
		swings[i] = {
			pairs = made,
			checkFull = isPublished(ids.swings[i]),
			checkUpper = isPublished(upperIds[i]),
		}
	end
	if next(swings) == nil and not warned then
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
	-- A published one that can't load is almost always a permission: the experience needs access
	-- to it (the animation's owner grants it once). Say which, and how.
	local list = table.clone(preload)
	task.spawn(function()
		local failed: { string } = {}
		pcall(
			ContentProvider.PreloadAsync,
			ContentProvider,
			list,
			function(id: string, status: Enum.AssetFetchStatus)
				if status == Enum.AssetFetchStatus.Failure and string.find(id, "rbxassetid://", 1, true) then
					table.insert(failed, id)
				end
			end
		)
		-- Check published swings against SwingData now, so an old upload is swapped out before the
		-- first tap (Studio: the repo's version; live: the simple swing).
		local before = #preload
		for i, set in table.clone(swings) do
			local pair = set.pairs[1]
			local waited = 0
			while
				(pair.full.Length <= 0 or (pair.upper and (pair.upper :: AnimationTrack).Length <= 0))
				and waited < 5
			do
				waited += task.wait(0.1)
			end
			if swings[i] == set and (set.checkFull or set.checkUpper) then
				checkStale(i, set, pair)
			end
		end
		if #preload > before then
			pcall(ContentProvider.PreloadAsync, ContentProvider, { table.unpack(preload, before + 1) })
		end
		if #failed > 0 and not warnedAccess then
			warnedAccess = true
			warn(
				`[SwingAnimator] {#failed} animation(s) couldn't load: {table.concat(failed, ", ")}. Give this`
					.. " experience access: Creator Hub > this experience > Configure > Permissions > Assets tab,"
					.. " add the ids, Save (or click 'Click to share access' in the Output). Until then the simple"
					.. " swing plays."
			)
		end
	end)
end

local function isStale(track: AnimationTrack, tierIndex: number): boolean
	return math.abs(track.Length - SwingData.TIERS[tierIndex].length) > STALE_BY
end

local function warnStale(name: string)
	if warnedStale then
		return
	end
	warnedStale = true
	warn(
		`[SwingAnimator] The published {name} is an old version (its length doesn't match SwingData).`
			.. (if RunService:IsStudio()
				then " Studio plays the repo's version instead."
				else " The simple swing plays instead.")
			.. " Re-publish the swing animations: see docs/ARCHITECTURE.md, 'Publishing the animations'."
	)
end

-- An old published upload (its length doesn't match SwingData): in Studio swap in the repo's
-- KeyframeSequence, live drop it. Checked once per id, as soon as it has loaded.
function checkStale(tierIndex: number, set: TierSwings, pair: Pair)
	local tier = SwingData.TIERS[tierIndex]
	local animator = animatorRef
	if set.checkFull and pair.full.Length > 0 then
		set.checkFull = false
		if isStale(pair.full, tierIndex) then
			warnStale(tier.name)
			local fresh: { Pair } = {}
			if animator then
				for _, old in set.pairs do
					local full = fullTrack(animator, tier.name, nil)
					if full == nil then
						break
					end
					table.insert(fresh, { full = full, upper = old.upper })
				end
			end
			if #fresh < 2 then
				-- Live: every tier plays the simple swing, so all tiers swing the same way.
				for _, other in swings do
					for _, p in other.pairs do
						discard(p.full)
						discard(p.upper)
					end
				end
				table.clear(swings)
				return
			end
			for _, old in set.pairs do
				discard(old.full)
			end
			set.pairs = fresh
		end
	end
	local upper = pair.upper
	if set.checkUpper and upper and upper.Length > 0 then
		set.checkUpper = false
		if isStale(upper, tierIndex) then
			warnStale(tier.upperName)
			for _, p in set.pairs do
				local old = p.upper
				if old and old.IsPlaying then
					old:Stop(WALK_FADE)
				end
				discard(old)
				p.upper = if animator then upperTrack(animator, tier.upperName, nil) else nil
			end
		end
	end
end

-- The tier's next pair (the one not playing), or nil if it isn't loaded yet.
local function nextPair(tierIndex: number): Pair?
	local set = swings[tierIndex]
	if set == nil then
		return nil
	end
	local pair = if active == set.pairs[1] then set.pairs[2] else set.pairs[1]
	if pair.full.Length <= 0 then
		return nil
	end
	if set.checkFull or set.checkUpper then
		checkStale(tierIndex, set, pair)
		set = swings[tierIndex]
		if set == nil then
			return nil
		end
		pair = if active == set.pairs[1] then set.pairs[2] else set.pairs[1]
		if pair.full.Length <= 0 then
			return nil -- the repo's version is still loading
		end
	end
	return pair
end

-- The upper track, if it can lead right now (loaded, and not waiting on its length check).
local function readyUpper(tierIndex: number, pair: Pair): AnimationTrack?
	local set = swings[tierIndex]
	local upper = pair.upper
	if set == nil or upper == nil or upper.Length <= 0 then
		return nil
	end
	if set.checkUpper then
		checkStale(tierIndex, set, pair)
		upper = pair.upper
		if upper == nil or upper.Length <= 0 then
			return nil
		end
	end
	return upper
end

local function isMoving(humanoid: Humanoid): boolean
	return humanoid.MoveDirection.Magnitude > MOVING and humanoid.WalkSpeed > 0
end

local activeTier = 0

-- Walking: the upper track leads and the full one fades to almost nothing (it keeps playing for
-- its markers). Standing: the reverse.
local function lead(upper: boolean, fade: number)
	local pair = active
	if pair == nil then
		return
	end
	local track = if upper then readyUpper(activeTier, pair) else pair.upper
	if upper and track == nil then
		noUpper = true -- no upper track: the full one plays alone
		return
	end
	upperOn = upper
	if track then
		local t = track :: AnimationTrack
		local weight = if upper then 1 else TINY
		if not t.IsPlaying then
			-- It loaded after the swing started: join in step.
			t:Play(fade, weight, if held then 0 else 1)
			t.TimePosition = pair.full.TimePosition
		else
			if math.abs(t.TimePosition - pair.full.TimePosition) > 0.02 then
				t.TimePosition = pair.full.TimePosition
			end
			t:AdjustWeight(weight, fade)
		end
	end
	pair.full:AdjustWeight(if upper then TINY else 1, fade)
end

function SwingAnimator.HasSwing(tierIndex: number): boolean
	return nextPair(tierIndex) ~= nil
end

function SwingAnimator.Swing(tierIndex: number, swingHandlers: Handlers): boolean
	local pair = nextPair(tierIndex)
	if pair == nil then
		return false -- not loaded (yet): the caller plays the simple swing
	end
	if active then
		-- A new toss cancels the last follow-through cleanly.
		local old = active :: Pair
		active = nil
		stopPair(old, CUT_FADE)
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local walking = humanoid ~= nil and isMoving(humanoid)
	local upper = readyUpper(tierIndex, pair)
	local upperLeads = walking and upper ~= nil
	active = pair
	activeTier = tierIndex
	handlers = swingHandlers
	held = false
	upperOn = upperLeads
	noUpper = false
	contactPassed = false
	cameraBackAt = nil
	pair.full:Play(SWING_FADE, if upperLeads then TINY else 1, 1)
	pair.full.TimePosition = 0
	if upper then
		upper:Play(SWING_FADE, if upperLeads then 1 else TINY, 1)
		upper.TimePosition = 0
	end
	return true
end

function SwingAnimator.CancelHold()
	if active then
		endHold(RELEASE_FADE)
	end
end

-- `away` says whether the ball-cam is away (CameraController.IsActive); held finishes wait for it.
function SwingAnimator.Start(away: () -> boolean)
	isCameraAway = away
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
		local moving = isMoving(humanoid)
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
		local pair = active
		if pair == nil then
			return
		end
		if not pair.full.IsPlaying then
			endHold(0)
			return
		end
		-- Walking mid-swing: the upper body keeps swinging while the legs walk. With no upper
		-- track, walking after contact cuts the follow-through (planted feet would slide).
		if moving and noUpper then
			if contactPassed then
				endHold(CUT_FADE)
				return
			end
		elseif moving ~= upperOn then
			lead(moving, WALK_FADE)
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

-- The swing's contact has passed (FungoController): without an upper track, walking from now
-- on cuts the follow-through.
function SwingAnimator.ContactDone()
	contactPassed = true
end

return SwingAnimator
