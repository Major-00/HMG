--!strict
-- PitchService: the pitcher slot. Each player has one active Pitcher and at most one pitch in play.
-- Every tap on the pitch in play is a hit (CLAUDE.md guardrail 1): there is no timing judgement.
-- One hit per pitch, so tapping faster than the pitcher throws gains nothing.
-- The pitch stays open until LATE_WINDOW after it reaches the plate, plus SERVER_GRACE on the
-- server so a tap from a slow connection still lands. An unswung pitch brings the next one after
-- the cooldown; after a hit, SwingService calls QueueNext once it knows how long the ball-cam takes.
--   PitchService.ConsumePitch(player, pitchId) -> the pitch if it's the one in play, else nil
--   PitchService.QueueNext(player, delay, hitId?, floor?)
--       -> throw the next pitch after `delay` (at least the cooldown). With a hitId and floor, a
--          Ready(hitId) from the client (the catch reveal was skipped) can bring it forward, but
--          never sooner than `floor` seconds from now.
--   PitchService.GetTravelTime(player)         -> the active pitcher's release-to-plate seconds
--   PitchService.SetPitcher(player, pitcher)   -> swap the active Pitcher (other pitchers later)
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
	lastId: number,
	token: number, -- bumps on every schedule; stale timers check it and stop
	throwAt: number, -- os.clock() the next throw is scheduled for
	-- After a hit: the earliest a Ready for that hit may bring the next pitch to. Cleared once used.
	skip: { hitId: number, floorAt: number }?,
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

schedule = function(player: Player, state: State, delay: number)
	state.token += 1
	state.throwAt = os.clock() + delay
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
		lastId = 0,
		token = 0,
		throwAt = 0,
		skip = nil,
	}
	states[player] = state
	if player.Character == nil then
		player.CharacterAdded:Wait()
	end
	schedule(player, state, Tuning.Pitch.FIRST_PITCH_DELAY)
end

-- Ends the pitch in play and returns it if `pitchId` matches it; otherwise nil (repeat taps,
-- stale ids). Any tap on the pitch in play is a hit.
function PitchService.ConsumePitch(player: Player, pitchId: number): HookTypes.Pitch?
	local state = states[player]
	if state == nil then
		return nil
	end
	local pitch = state.pending
	if pitch == nil or pitch.pitchId ~= pitchId then
		return nil
	end
	state.pending = nil
	-- The caller calls QueueNext with the real delay. This backup (the longest possible ball-cam)
	-- keeps pitches coming if anything fails before that.
	state.skip = nil
	schedule(player, state, Formulas.ballCamTime(math.huge, Tuning.Reveal.FULL))
	return pitch
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

-- The client skipped the catch reveal for `hitId`: bring the next pitch forward to the floor
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
	Remotes.Event("Ready").OnServerEvent:Connect(onReady)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return PitchService
