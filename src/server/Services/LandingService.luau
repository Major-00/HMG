--!strict
-- LandingService: the on-land hook. After a hit, works out where the ball lands, lets each
-- registered handler push it further (e.g. a bounce), runs the catch phase on the final landing
-- (the Mascot caught there), then fires Landed with the result.
-- No push handlers are registered yet; MascotService sets the catcher.
--   LandingService.AddHandler(fn)  -> register a HookTypes.LandingHandler (must not yield)
--   LandingService.SetCatcher(fn)  -> set the HookTypes.Catcher (must not yield)
--   LandingService.Landed          -> Signal (ctx: HookTypes.LandingContext), after the catch
--   LandingService.Resolve(...)    -> used by SwingService; returns the final context

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local HookTypes = require(Shared.HookTypes)
local Signal = require(Shared.Signal)

local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

local LandingService = {}

LandingService.Landed = Signal.new()

local handlers: { HookTypes.LandingHandler } = {}
local catcher: HookTypes.Catcher? = nil

local function context(
	player: Player,
	hitId: number,
	segments: { HookTypes.FlightSegment }
): HookTypes.LandingContext
	local landedAt = segments[#segments].to
	local data = DataService.Get(player)
	local world = if data then Formulas.world(data) else 1
	return {
		player = player,
		hitId = hitId,
		segments = table.clone(segments),
		landedAt = landedAt,
		biomeIndex = Formulas.biomeIndexAt(landedAt, world),
		biomeName = Formulas.biomeNameAt(landedAt, world), -- in the player's world
		position = WorldService.GetLandingPosition(player, landedAt),
	}
end

function LandingService.AddHandler(handler: HookTypes.LandingHandler)
	table.insert(handlers, handler)
end

function LandingService.SetCatcher(fn: HookTypes.Catcher)
	catcher = fn
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
	if catcher then
		-- A failed catch never stops the hit: the swing still counts, there's just no Mascot.
		local ok, caught = pcall(catcher, final)
		if ok then
			final.catch = caught
		else
			warn(`[LandingService] Catch failed: {caught}`)
		end
	end
	LandingService.Landed:Fire(final)
	return final
end

return LandingService
