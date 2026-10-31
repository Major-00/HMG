--!strict
-- RateLimit: a per-player token bucket for remotes. A few actions a second is plenty for a
-- tapping player; extra calls are refused (and do nothing).
--   local limit = RateLimit.new(10)  -- 10 actions per second, bursts up to 10
--   if not limit:Allow(player) then return { ok = false, err = "too fast" } end

local Players = game:GetService("Players")

local RateLimit = {}
RateLimit.__index = RateLimit

export type RateLimit = typeof(setmetatable(
	{} :: { perSecond: number, buckets: { [Player]: { tokens: number, at: number } } },
	RateLimit
))

function RateLimit.new(perSecond: number): RateLimit
	local self = setmetatable({ perSecond = perSecond, buckets = {} }, RateLimit)
	Players.PlayerRemoving:Connect(function(player)
		self.buckets[player] = nil
	end)
	return self
end

function RateLimit.Allow(self: RateLimit, player: Player): boolean
	local now = os.clock()
	local b = self.buckets[player]
	if b == nil then
		b = { tokens = self.perSecond, at = now }
		self.buckets[player] = b
	end
	b.tokens = math.min(self.perSecond, b.tokens + (now - b.at) * self.perSecond)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

return RateLimit
