--!strict
-- SwingService: handles Swing(pitchId). A swing only counts if it matches the pitch in play.
-- On a hit: +Power (x multiplier), then distance from total Power, the on-land hook,
-- Wins from the final distance, and a HitResult to the client to draw.
-- The client sends only the pitch id; every number is decided here.

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
		return -- no pitch in play, wrong id, or too late: a whiff
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
	local wins = Formulas.wins(distance)

	-- Hold the next pitch until the ball-cam is back, so the ball reaches the plate just after.
	-- The client's camera starts only when HitResult arrives, so add the player's latency (capped).
	PitchService.QueueNext(
		player,
		Formulas.ballCamTime(distance)
			- PitchService.GetTravelTime(player)
			+ Tuning.Camera.PITCH_ARRIVE_AFTER_RETURN
			+ math.clamp(player:GetNetworkPing(), 0, Tuning.Camera.MAX_PING_ALLOWANCE)
	)
	local previousHighest = data.highestBiome

	DataService.Update(player, "wins", function(current)
		return current + wins
	end)
	DataService.Update(player, "lifetime", function(lifetime)
		lifetime.swings += 1
		lifetime.winsEarned += wins
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
		segments = landing.segments,
		distance = distance,
		biomeIndex = landing.biomeIndex,
		winsGained = wins,
	})
	HighlightService.Evaluate(player, pitch.pitchId, distance, previousHighest)
end

function SwingService.Start()
	Remotes.Event("Swing").OnServerEvent:Connect(onSwing)
end

return SwingService
