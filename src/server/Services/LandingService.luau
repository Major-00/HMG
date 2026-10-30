--!strict
-- LandingService: the on-land hook. After a hit, works out where the ball lands, lets each
-- registered handler push it further (e.g. a bounce), then fires Landed with the result.
-- No handlers are registered yet.
--   LandingService.AddHandler(fn)  -> register a HookTypes.LandingHandler (must not yield)
--   LandingService.Landed          -> Signal (ctx: HookTypes.LandingContext), after all handlers
--   LandingService.Resolve(...)    -> used by SwingService; returns the final context

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local HookTypes = require(Shared.HookTypes)
local Signal = require(Shared.Signal)

local WorldService = require(script.Parent.WorldService)

local LandingService = {}

LandingService.Landed = Signal.new()

local handlers: { HookTypes.LandingHandler } = {}

local function context(
	player: Player,
	hitId: number,
	segments: { HookTypes.FlightSegment }
): HookTypes.LandingContext
	local landedAt = segments[#segments].to
	return {
		player = player,
		hitId = hitId,
		segments = table.clone(segments),
		landedAt = landedAt,
		biomeIndex = Formulas.biomeIndexAt(landedAt),
		biomeName = Formulas.biomeNameAt(landedAt),
		position = WorldService.GetLandingPosition(player, landedAt),
	}
end

function LandingService.AddHandler(handler: HookTypes.LandingHandler)
	table.insert(handlers, handler)
end

-- Runs the hit through every handler and returns the final landing.
function LandingService.Resolve(
	player: Player,
	hitId: number,
	hit: HookTypes.FlightSegment
): HookTypes.LandingContext
	local segments = { hit }
	for _, handler in handlers do
		local ok, extra = pcall(handler, context(player, hitId, segments))
		if not ok then
			warn(`[LandingService] Landing handler failed: {extra}`)
		elseif extra ~= nil then
			local landedAt = segments[#segments].to
			-- A handler can only push the ball further, never back.
			if type(extra.to) == "number" and extra.to > landedAt then
				table.insert(
					segments,
					{ from = landedAt, to = math.floor(extra.to), source = tostring(extra.source) }
				)
			end
		end
	end
	local final = context(player, hitId, segments)
	LandingService.Landed:Fire(final)
	return final
end

return LandingService
