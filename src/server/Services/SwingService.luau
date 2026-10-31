--!strict
-- SwingService: handles Swing(pitchId). Any tap on the pitch in play is a hit (CLAUDE.md):
-- +Power (x multiplier), then distance from total Power, the on-land hook, and a HitResult.
-- Hits don't pay Cash; seated Mascots do. The client has already drawn the hit; this confirms
-- the numbers.
-- The client sends only the pitch id; every number is decided here, from stats only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Tuning = require(Shared.Config.Tuning)

local Services = script.Parent
local DataService = require(Services.DataService)
local HighlightService = require(Services.HighlightService)
local LandingService = require(Services.LandingService)
local PitchService = require(Services.PitchService)
local StatService = require(Services.StatService)

local SwingService = {}

local function onSwing(player: Player, pitchId: unknown)
	if type(pitchId) ~= "number" then
		return
	end
	local data = DataService.Get(player)
	if data == nil then
		return -- never play on a save that isn't loaded
	end
	local pitch = PitchService.ConsumePitch(player, pitchId)
	if pitch == nil then
		return -- no pitch in play, a stale id, or a repeat tap on the same pitch
	end

	local gain = Formulas.powerGain(StatService.GetMultiplier(player))
	local power = data.power + gain
	DataService.Update(player, "power", function()
		return power
	end)

	local landing = LandingService.Resolve(player, pitch.pitchId, {
		from = 0,
		to = Formulas.distance(power),
		source = "hit",
	})
	local distance = landing.landedAt

	-- Hold the next pitch until the ball-cam (flight, catch reveal, return) is back, so the ball
	-- reaches the plate just after. The client's camera started at the tap, before this swing
	-- reached the server, so it is always back before the pitch arrives. A skipped reveal
	-- (Ready) can bring it forward, but never sooner than a reveal of Reveal.MIN_SHOWN.
	local lead = Tuning.Camera.PITCH_ARRIVE_AFTER_RETURN - PitchService.GetTravelTime(player)
	PitchService.QueueNext(
		player,
		Formulas.ballCamTime(distance, Formulas.revealTime(landing.catch)) + lead,
		pitch.pitchId,
		Formulas.ballCamTime(distance, Tuning.Reveal.MIN_SHOWN) + lead
	)
	local previousHighest = data.highestBiome
	local previousBest = data.lifetime.bestDistance

	DataService.Update(player, "lifetime", function(lifetime)
		lifetime.swings += 1
		lifetime.bestDistance = math.max(lifetime.bestDistance, distance)
		return lifetime
	end)
	if landing.biomeIndex > previousHighest then
		DataService.Update(player, "highestBiome", function()
			return landing.biomeIndex
		end)
	end

	Remotes.Event("HitResult"):FireClient(player, {
		hitId = pitch.pitchId,
		powerGained = gain,
		pitcherBonus = PitchService.GetPowerBonus(player), -- lets the client predict the next hit exactly
		segments = landing.segments,
		distance = distance,
		biomeIndex = landing.biomeIndex,
		catch = landing.catch, -- the Mascot caught (HookTypes.Catch), nil if the catch failed
	})
	HighlightService.Evaluate(player, pitch.pitchId, distance, previousHighest, previousBest)
end

function SwingService.Start()
	Remotes.Event("Swing").OnServerEvent:Connect(onSwing)
end

return SwingService
