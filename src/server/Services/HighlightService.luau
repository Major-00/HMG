--!strict
-- HighlightService: the highlight event. Celebrations are given, never earned by skill (CLAUDE.md).
-- After a hit is final it fires `Fired` on the server and the `Highlight` remote to that player for:
--   "biome"  - each biome reached for the first time this run (above `highestBiome`; rebirth resets it)
--   "record" - when the hit pushes the lifetime best past a milestone (Tuning.Highlight.RECORD_MILESTONES);
--              `distance` is that milestone. Not every new best: early on that's every hit.
-- A camera pet listens to `Fired` later.
--   HighlightService.Fired -> Signal (highlight: HookTypes.Highlight)
--   HighlightService.Evaluate(player, hitId, distance, previousHighest, previousBest) -> called by SwingService

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local HookTypes = require(Shared.HookTypes)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local HighlightService = {}

HighlightService.Fired = Signal.new()

local function fire(highlight: HookTypes.Highlight)
	HighlightService.Fired:Fire(highlight)
	Remotes.Event("Highlight"):FireClient(highlight.player, {
		hitId = highlight.hitId,
		kind = highlight.kind,
		distance = highlight.distance,
		biomeIndex = highlight.biomeIndex,
		previousBest = highlight.previousBest,
	})
end

function HighlightService.Evaluate(
	player: Player,
	hitId: number,
	distance: number,
	previousHighest: number,
	previousBest: number
)
	local milestone = Formulas.recordMilestone(previousBest, distance)
	if milestone then
		fire({
			player = player,
			hitId = hitId,
			kind = "record",
			distance = milestone,
			biomeIndex = Formulas.biomeIndexAt(milestone),
			previousBest = previousBest,
		})
	end

	local reached = Formulas.biomeIndexAt(distance)
	for index = previousHighest + 1, reached do
		local highlight: HookTypes.Highlight = {
			player = player,
			hitId = hitId,
			kind = "biome",
			distance = distance,
			biomeIndex = index,
		}
		fire(highlight)
	end
end

return HighlightService
