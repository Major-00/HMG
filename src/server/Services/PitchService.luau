--!strict
-- PitchService: the pitcher slot. Each player has one active Pitcher and at most one pitch in play.
-- A pitch is hittable from release until `expiresAt`. A miss throws the next pitch after the
-- pitcher's cooldown; after a hit, SwingService calls QueueNext once it knows how long the
-- ball-cam will take. Swings that don't match the pitch in play do nothing, so tapping faster
-- than the pitcher throws gains nothing.
--   PitchService.ConsumePitch(player, pitchId) -> the pitch if it's a valid hit, else nil
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
	lastId: number,
	token: number, -- bumps on every schedule; stale timers check it and stop
}

local PitchService = {}

local pitchers: { [string]: HookTypes.Pitcher } = {}
local states: { [Player]: State } = {}

local schedule: (player: Player, state: State, delay: number) -> ()

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
		expiresAt = arriveAt + Tuning.Pitch.LATE_WINDOW,
	}
	state.pending = pitch
	Remotes.Event("Pitch"):FireClient(player, pitch)

	-- Miss: nobody hit it in time, so throw the next one.
	task.delay(pitch.expiresAt - now, function()
		if states[player] == state and state.pending == pitch then
			state.pending = nil
			schedule(player, state, state.pitcher.cooldown(player))
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
		lastId = 0,
		token = 0,
	}
	states[player] = state
	if player.Character == nil then
		player.CharacterAdded:Wait()
	end
	schedule(player, state, Tuning.Pitch.FIRST_PITCH_DELAY)
end

-- Returns the pitch and ends it if `pitchId` is the pitch in play and still hittable.
function PitchService.ConsumePitch(player: Player, pitchId: number): HookTypes.Pitch?
	local state = states[player]
	if state == nil then
		return nil
	end
	local pitch = state.pending
	if pitch == nil or pitch.pitchId ~= pitchId or workspace:GetServerTimeNow() > pitch.expiresAt then
		return nil
	end
	state.pending = nil
	-- The caller calls QueueNext with the real delay. This backup (the longest possible ball-cam)
	-- keeps pitches coming if anything fails before that.
	schedule(player, state, Formulas.ballCamTime(math.huge))
	return pitch
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
