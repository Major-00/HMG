--!strict
-- HighlightService: the highlight event. After a hit is final, checks whether the ball reached
-- a biome for the first time this run (above `highestBiome`, which rebirth resets) and, for each
-- such biome in order, fires `Fired` on the server and the `Highlight` remote to that player.
-- "record" highlights are not fired yet: early on every hit is a new best, which would be spam.
-- A camera pet listens to `Fired` later.
--   HighlightService.Fired                                    -> Signal (highlight: HookTypes.Highlight)
--   HighlightService.Evaluate(player, hitId, dist, prevHigh)  -> called by SwingService

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local HookTypes = require(Shared.HookTypes)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local HighlightService = {}

HighlightService.Fired = Signal.new()

function HighlightService.Evaluate(player: Player, hitId: number, distance: number, previousHighest: number)
	local reached = Formulas.biomeIndexAt(distance)
	for index = previousHighest + 1, reached do
		local highlight: HookTypes.Highlight = {
			player = player,
			hitId = hitId,
			kind = "biome",
			distance = distance,
			biomeIndex = index,
		}
		HighlightService.Fired:Fire(highlight)
		Remotes.Event("Highlight"):FireClient(player, {
			hitId = hitId,
			kind = highlight.kind,
			distance = distance,
			biomeIndex = index,
		})
	end
end

return HighlightService
