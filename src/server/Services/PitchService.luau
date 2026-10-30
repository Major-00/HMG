--!strict
-- PitchService: the pitcher slot. Each player has one active Pitcher and at most one pitch in play.
-- One swing per pitch. The swing is judged by when it happened relative to the ball reaching
-- the plate (Formulas.judgeSwing): Perfect or Good is a hit, early or late is a whiff, and either
-- way the pitch is over. The client reports its tap time; it's trusted only within the player's
-- ping (plus Timing.LAG_SLACK), so laggy phones aren't punished and nobody can claim an old time.
-- A whiff or an unswung pitch brings the next pitch after the pitcher's cooldown; after a hit,
-- SwingService calls QueueNext once it knows how long the ball-cam will take.
--   PitchService.ConsumePitch(player, pitchId, tapTime) -> (pitch, quality) for a hit,
--                                                          (nil, "early"/"late") for a whiff,
--                                                          (nil, nil) if it doesn't match the pitch in play
--   PitchService.QueueNext(player, delay)      -> throw the next pitch after `delay` (at least the cooldown)
--   PitchService.GetTravelTime(player)         -> the active pitcher's release-to-plate seconds
--   PitchService.SetPitcher(player, pitcher)   -> swap the active Pitcher (pitcher pets later)
--   PitchService.GetPowerBonus(player)         -> the active pitcher's Power bonus (1 if none)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local HookTypes = require(Shared.HookTypes)
local Remotes = require(Shared.Remotes)
local Tuning = require(Shared.Config.Tuning)

local DataService = require(script.Parent.DataService)

local DEFAULT_PITCHER = "pitching_machine"

type State = {
	pitcher: HookTypes.Pitcher,
	pending: HookTypes.Pitch?,
	expired: HookTypes.Pitch?, -- the last pitch nobody swung at, so a very late swing still gets "late"
	lastId: number,
	token: number, -- bumps on every schedule; stale timers check it and stop
}

local PitchService = {}

local pitchers: { [string]: HookTypes.Pitcher } = {}
local states: { [Player]: State } = {}

local schedule: (player: Player, state: State, delay: number) -> ()

-- How far back a reported tap time may be: the player's latency (capped) plus slack.
local function lagAllowance(player: Player): number
	return math.clamp(player:GetNetworkPing(), 0, Tuning.Camera.MAX_PING_ALLOWANCE) + Tuning.Timing.LAG_SLACK
end

-- The most lag allowance anyone can get; pitches wait this long for a late swing.
local MAX_ALLOWANCE = Tuning.Camera.MAX_PING_ALLOWANCE + Tuning.Timing.LAG_SLACK

-- Seconds until a pitch's ball has flown past the plate and gone, plus the cooldown:
-- the next pitch never shows up while the last one is still on screen.
local function afterBallGone(player: Player, state: State, pitch: HookTypes.Pitch): number
	local gone = pitch.arriveAt + Tuning.Timing.MISS_FLY_TIME - workspace:GetServerTimeNow()
	return math.max(gone, 0) + state.pitcher.cooldown(player)
end

local function throw(player: Player, state: State)
	if player.Parent ~= Players or states[player] ~= state then
		return
	end
	local now = workspace:GetServerTimeNow()
	local arriveAt = now + state.pitcher.travelTime(player)
	state.lastId += 1
	local pitch: HookTypes.Pitch = {
		pitchId = state.lastId,
		pitcherId = state.pitcher.id,
		releaseAt = now,
		arriveAt = arriveAt,
		expiresAt = arriveAt + Tuning.Timing.GOOD_LATE,
	}
	state.pending = pitch
	Remotes.Event("Pitch"):FireClient(player, pitch)

	-- Not swung at: once even the laggiest accepted swing can no longer arrive, throw the next one.
	task.delay(pitch.expiresAt - now + MAX_ALLOWANCE, function()
		if states[player] == state and state.pending == pitch then
			state.pending = nil
			state.expired = pitch
			schedule(player, state, afterBallGone(player, state, pitch))
		end
	end)
end

schedule = function(player: Player, state: State, delay: number)
	state.token += 1
	local token = state.token
	task.delay(delay, function()
		if states[player] == state and state.token == token then
			throw(player, state)
		end
	end)
end

local function startPitching(player: Player, data: any)
	local state: State = {
		pitcher = pitchers[data.pitcher] or pitchers[DEFAULT_PITCHER],
		pending = nil,
		expired = nil,
		lastId = 0,
		token = 0,
	}
	states[player] = state
	if player.Character == nil then
		player.CharacterAdded:Wait()
	end
	schedule(player, state, Tuning.Pitch.FIRST_PITCH_DELAY)
end

-- Judges a swing at the pitch in play and ends that pitch.
function PitchService.ConsumePitch(
	player: Player,
	pitchId: number,
	tapTime: unknown
): (HookTypes.Pitch?, HookTypes.SwingQuality?)
	local state = states[player]
	if state == nil then
		return nil, nil
	end
	local pitch = state.pending
	if pitch == nil or pitch.pitchId ~= pitchId then
		local expired = state.expired
		if expired and expired.pitchId == pitchId then
			state.expired = nil -- answer once; repeats are ignored
			return nil, "late"
		end
		return nil, nil
	end

	-- The client's tap time, held to what's plausible for this player's lag.
	local now = workspace:GetServerTimeNow()
	local swungAt = now
	if type(tapTime) == "number" and tapTime == tapTime then -- a number, not NaN
		swungAt = math.clamp(tapTime, now - lagAllowance(player), now + 0.05)
	end

	state.pending = nil
	state.expired = nil
	local quality = Formulas.judgeSwing(swungAt - pitch.arriveAt)
	if quality == "early" or quality == "late" then
		schedule(player, state, afterBallGone(player, state, pitch))
		return nil, quality
	end
	-- The caller calls QueueNext with the real delay. This backup (the longest possible ball-cam)
	-- keeps pitches coming if anything fails before that.
	schedule(player, state, Formulas.ballCamTime(math.huge))
	return pitch, quality
end

function PitchService.QueueNext(player: Player, delay: number)
	local state = states[player]
	if state == nil then
		return
	end
	schedule(player, state, math.max(delay, state.pitcher.cooldown(player)))
end

function PitchService.GetTravelTime(player: Player): number
	local state = states[player]
	return if state then state.pitcher.travelTime(player) else Tuning.Pitch.MACHINE_TRAVEL_TIME
end

function PitchService.SetPitcher(player: Player, pitcher: HookTypes.Pitcher)
	local state = states[player]
	if state then
		state.pitcher = pitcher
	end
end

function PitchService.GetPowerBonus(player: Player): number
	local state = states[player]
	local bonus = state and state.pitcher.powerBonus
	return if bonus then bonus(player) else 1
end

function PitchService.Init()
	for _, module in script.Parent.Parent.Pitchers:GetChildren() do
		if module:IsA("ModuleScript") then
			local pitcher = (require :: any)(module) :: HookTypes.Pitcher
			pitchers[pitcher.id] = pitcher
		end
	end
	assert(pitchers[DEFAULT_PITCHER], "PitchingMachine pitcher is missing")
end

function PitchService.Start()
	DataService.Loaded:Connect(startPitching)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return PitchService
