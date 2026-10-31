--!strict
-- PitchService: the pitcher slot. Each player has one active Pitcher and at most one ball per
-- cycle. Every tap is a hit (CLAUDE.md guardrail 1): there is no timing judgement. One hit per
-- cycle, so tapping faster than the cycle gains nothing.
-- Two kinds of pitcher (HookTypes.Pitcher.mode):
--   "toss"  (Fungo, the default): the tap tosses and swings at once. Swing(tossId) is allowed
--           once the last cycle is over (less Pitch.TOSS_GRACE for network jitter). One that
--           comes a little earlier (up to Pitch.TOSS_MAX_HOLD) is held until then, not refused,
--           because the player has already seen it hit. tossId is the client's own counter and
--           must go up. No Pitch is sent.
--   "throw" (the pitching machine): the server throws each Pitch; Swing(pitchId) hits the one
--           in play. It stays open until LATE_WINDOW after it reaches the plate, plus
--           SERVER_GRACE for slow connections. An unswung pitch brings the next after the cooldown.
-- After a hit, SwingService calls QueueNext once it knows how long the ball-cam takes.
--   PitchService.ConsumePitch(player, id)      -> the hit's id if `id` may hit now; else nil and,
--                                                 for a toss that's held, the seconds to wait
--   PitchService.QueueNext(player, delay, hitId?, floor?)
--       -> the next ball after `delay` (at least the cooldown). With a hitId and floor, a
--          Ready(hitId) from the client (the catch reveal was skipped) can bring it forward, but
--          never sooner than `floor` seconds from now.
--   PitchService.GetLead(player)               -> seconds to add to the ball-cam time (see below)
--   PitchService.SetPitcher(player, pitcher)   -> swap the active Pitcher
--   PitchService.GetPowerBonus(player)         -> the active pitcher's Power bonus (1 if none)
--   PitchService.GetRejected(player)           -> swings refused so far (dev metrics)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local HookTypes = require(Shared.HookTypes)
local Remotes = require(Shared.Remotes)
local Tuning = require(Shared.Config.Tuning)

local DataService = require(script.Parent.DataService)

-- Most a toss id may jump past the last one (a client counter, so it only ever goes up by one;
-- the slack covers tosses the server refused).
local MAX_TOSS_JUMP = 1000

type State = {
	pitcher: HookTypes.Pitcher,
	pending: HookTypes.Pitch?, -- "throw": the pitch in play
	lastId: number, -- the last pitch thrown or toss accepted
	token: number, -- bumps on every schedule; stale timers check it and stop
	throwAt: number, -- os.clock() the next ball is due: the next throw, or when a toss may hit
	-- After a hit: the earliest a Ready for that hit may bring the next ball to. Cleared once used.
	skip: { hitId: number, floorAt: number }?,
	rejected: number,
	held: number?, -- "toss": the toss id held until its cycle opens
	resync: boolean, -- "toss": just switched to toss; take the client's next id as it is
}

local PitchService = {}

local pitchers: { [string]: HookTypes.Pitcher } = {}
local states: { [Player]: State } = {}

local schedule: (player: Player, state: State, delay: number) -> ()

local function throw(player: Player, state: State)
	if player.Parent ~= Players or states[player] ~= state then
		return
	end
	state.skip = nil -- a Ready for the last hit can't move anything once the next pitch is out
	local now = workspace:GetServerTimeNow()
	local arriveAt = now + state.pitcher.travelTime(player)
	state.lastId += 1
	local pitch: HookTypes.Pitch = {
		pitchId = state.lastId,
		pitcherId = state.pitcher.id,
		releaseAt = now,
		arriveAt = arriveAt,
		expiresAt = arriveAt + Tuning.Pitch.LATE_WINDOW,
	}
	state.pending = pitch
	Remotes.Event("Pitch"):FireClient(player, pitch)

	-- Not swung at: throw the next one (after the grace for taps still on their way).
	task.delay(pitch.expiresAt - now + Tuning.Pitch.SERVER_GRACE, function()
		if states[player] == state and state.pending == pitch then
			state.pending = nil
			schedule(player, state, state.pitcher.cooldown(player))
		end
	end)
end

-- Sets when the next ball is due. "throw" throws it then; "toss" just allows the next tap from then.
schedule = function(player: Player, state: State, delay: number)
	state.token += 1
	state.throwAt = os.clock() + delay
	if state.pitcher.mode == "toss" then
		return
	end
	local token = state.token
	task.delay(delay, function()
		if states[player] == state and state.token == token then
			throw(player, state)
		end
	end)
end

local function publish(player: Player, pitcher: HookTypes.Pitcher)
	-- The client reads these to know how a tap plays (InputController).
	player:SetAttribute("Pitcher", pitcher.id)
	player:SetAttribute("PitcherMode", pitcher.mode)
end

local function startPitching(player: Player, data: any)
	local state: State = {
		pitcher = pitchers[data.pitcher] or pitchers[Tuning.Pitch.DEFAULT_PITCHER],
		pending = nil,
		lastId = 0,
		token = 0,
		throwAt = 0,
		skip = nil,
		rejected = 0,
		held = nil,
		resync = false,
	}
	states[player] = state
	publish(player, state.pitcher)
	if state.pitcher.mode == "toss" then
		schedule(player, state, 0) -- the first tap may hit straight away
		return
	end
	if player.Character == nil then
		player.CharacterAdded:Wait()
	end
	schedule(player, state, Tuning.Pitch.FIRST_PITCH_DELAY)
end

-- The longest a cycle can take: a backup that keeps balls coming if anything fails before
-- QueueNext sets the real time.
local function backupDelay(player: Player, state: State): number
	local lead = if state.pitcher.mode == "toss" then state.pitcher.travelTime(player) else 0
	return Formulas.ballCamTime(math.huge, Tuning.Reveal.FULL) + lead
end

-- Returns the hit's id if `id` may hit now, ending this cycle. Otherwise nil (repeat taps in a
-- cycle, stale ids) and, for a toss that came a little early and is now held, the seconds until
-- the caller should try it again. Any allowed tap is a hit.
function PitchService.ConsumePitch(player: Player, id: number): (number?, number?)
	local state = states[player]
	if state == nil or id ~= id or id % 1 ~= 0 then
		return nil
	end
	if state.pitcher.mode == "toss" then
		if state.held ~= nil and state.held ~= id then
			state.rejected += 1 -- a second tap while one is held for this cycle
			return nil
		end
		local fresh = state.resync or (id > state.lastId and id <= state.lastId + MAX_TOSS_JUMP)
		if not fresh then
			state.rejected += 1 -- a repeat or old id
			return nil
		end
		local wait = state.throwAt - Tuning.Pitch.TOSS_GRACE - os.clock()
		if wait > 0 then
			if state.held == id or wait <= Tuning.Pitch.TOSS_MAX_HOLD then
				state.held = id -- network jitter: play it as soon as the cycle opens
				return nil, wait
			end
			state.rejected += 1 -- far too early: spam, not jitter
			return nil
		end
		state.held = nil
		state.resync = false
		state.lastId = id
		state.skip = nil
		schedule(player, state, backupDelay(player, state))
		return id
	end
	local pitch = state.pending
	if pitch == nil or pitch.pitchId ~= id then
		state.rejected += 1
		return nil
	end
	state.pending = nil
	state.skip = nil
	schedule(player, state, backupDelay(player, state))
	return pitch.pitchId
end

function PitchService.QueueNext(player: Player, delay: number, hitId: number?, floor: number?)
	local state = states[player]
	if state == nil then
		return
	end
	local cooldown = state.pitcher.cooldown(player)
	schedule(player, state, math.max(delay, cooldown))
	state.skip = if hitId and floor
		then { hitId = hitId, floorAt = os.clock() + math.max(floor, cooldown) }
		else nil
end

-- The client skipped the catch reveal for `hitId`: bring the next ball forward to the floor
-- set by QueueNext. Once per hit; ignored for any other hit, or if it wouldn't be sooner.
local function onReady(player: Player, hitId: unknown)
	local state = states[player]
	local skip = state and state.skip
	if state == nil or skip == nil or type(hitId) ~= "number" or skip.hitId ~= hitId then
		return
	end
	state.skip = nil
	if state.pending ~= nil then
		return -- the next pitch is already in play
	end
	local now = os.clock()
	if skip.floorAt < state.throwAt then
		schedule(player, state, math.max(skip.floorAt - now, 0))
	end
end

-- Seconds to add to Formulas.ballCamTime for when the next ball is due, measured from when the
-- server handles the swing:
--   "toss":  the ball launches travelTime (CONTACT_AT) after the tap, and the client times its
--            cycle from its own tap, which reached the server just now.
--   "throw": the next pitch reaches the plate PITCH_ARRIVE_AFTER_RETURN after the camera is back.
function PitchService.GetLead(player: Player): number
	local state = states[player]
	if state == nil then
		return 0
	end
	if state.pitcher.mode == "toss" then
		return state.pitcher.travelTime(player)
	end
	return Tuning.Camera.PITCH_ARRIVE_AFTER_RETURN - state.pitcher.travelTime(player)
end

function PitchService.SetPitcher(player: Player, pitcher: HookTypes.Pitcher)
	local state = states[player]
	if state then
		if pitcher.mode == "toss" and state.pitcher.mode ~= "toss" then
			state.resync = true -- the client's toss counter doesn't know the pitch ids thrown so far
		end
		state.pitcher = pitcher
		state.pending = nil
		state.held = nil
		publish(player, pitcher)
		schedule(player, state, pitcher.cooldown(player))
	end
end

function PitchService.GetPowerBonus(player: Player): number
	local state = states[player]
	local bonus = state and state.pitcher.powerBonus
	return if bonus then bonus(player) else 1
end

function PitchService.GetRejected(player: Player): number
	local state = states[player]
	return if state then state.rejected else 0
end

function PitchService.Init()
	for _, module in script.Parent.Parent.Pitchers:GetChildren() do
		if module:IsA("ModuleScript") then
			local pitcher = (require :: any)(module) :: HookTypes.Pitcher
			pitchers[pitcher.id] = pitcher
		end
	end
	assert(
		pitchers[Tuning.Pitch.DEFAULT_PITCHER],
		`Default pitcher "{Tuning.Pitch.DEFAULT_PITCHER}" is missing`
	)
end

function PitchService.Start()
	DataService.Loaded:Connect(startPitching)
	Remotes.Event("Ready").OnServerEvent:Connect(onReady)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return PitchService
