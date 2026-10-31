--!strict
-- SwingService: handles Swing(id): a Fungo toss id, or the id of the machine's pitch in play.
-- Every allowed tap is a hit (CLAUDE.md), one per cycle (PitchService):
-- +Power (x multiplier), then distance from total Power, the on-land hook, and a HitResult.
-- Hits don't pay Cash; seated Mascots do. The client has already drawn the hit; this confirms
-- the numbers.
-- The client sends only the id; every number is decided here, from stats only. Where the
-- player stands in the hitting circle never matters.

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

local onSwing: (player: Player, id: unknown) -> ()
onSwing = function(player: Player, id: unknown)
	if type(id) ~= "number" then
		return
	end
	local data = DataService.Get(player)
	if data == nil then
		return -- never play on a save that isn't loaded
	end
	local hitId, holdFor = PitchService.ConsumePitch(player, id)
	if hitId == nil then
		if holdFor then
			-- A toss that came a moment before its cycle opened (network jitter): the player
			-- already saw it hit, so play it as soon as the cycle opens.
			task.delay(holdFor, onSwing, player, id)
		end
		return -- a repeat tap in the same cycle, a stale id, or no pitch in play
	end

	local gain = Formulas.powerGain(StatService.GetMultiplier(player))
	local power = data.power + gain
	DataService.Update(player, "power", function()
		return power
	end)

	local landing = LandingService.Resolve(player, hitId, {
		from = 0,
		to = Formulas.distance(power),
		source = "hit",
	})
	local distance = landing.landedAt

	-- Hold the next ball until the ball-cam (flight, catch reveal, return) is back. The client
	-- timed this cycle from its own tap, before this swing reached the server, so its camera is
	-- always back first. A skipped reveal (Ready) can bring it forward, but never sooner than a
	-- reveal of Reveal.MIN_SHOWN.
	local lead = PitchService.GetLead(player)
	PitchService.QueueNext(
		player,
		Formulas.ballCamTime(distance, Formulas.revealTime(landing.catch)) + lead,
		hitId,
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
		hitId = hitId,
		powerGained = gain,
		pitcherBonus = PitchService.GetPowerBonus(player), -- lets the client predict the next hit exactly
		segments = landing.segments,
		distance = distance,
		biomeIndex = landing.biomeIndex,
		catch = landing.catch, -- the Mascot caught (HookTypes.Catch), nil if the catch failed
	})
	HighlightService.Evaluate(player, hitId, distance, previousHighest, previousBest)
end

function SwingService.Start()
	Remotes.Event("Swing").OnServerEvent:Connect(onSwing)
end

return SwingService
