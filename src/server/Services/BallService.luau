--!strict
-- BallService: buying balls with Cash. Tiers are bought in order (Config/Balls), each a
-- permanent unlock for the run; every hit then uses the best ball owned (Formulas.bestBall).
-- Cash only: there is no Robux path to a ball.
--   BuyBall(ballId) (RemoteFunction) -> { ok, err? }: must be the next tier, and affordable.
-- It also tells the player once per tier per run when their Cash first covers the next ball
-- (ShopNotice { kind = "ball", id }), remembered in balls.notified so it never repeats.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)

local BallService = {}

local limit = RateLimit.new(5)

type Result = { ok: boolean, err: string? }

function BallService.Buy(player: Player, ballId: string): Result
	local data = DataService.Get(player)
	if data == nil then
		return { ok = false, err = "not loaded" }
	end
	local ball = Formulas.nextBall(data)
	if ball == nil or ball.id ~= ballId then
		return { ok = false, err = "not next" } -- owned already, unknown, or a tier ahead
	end
	if data.cash < ball.price then
		return { ok = false, err = "not enough cash" }
	end
	-- No yields between the check and the spend, so two quick buys can't both pass.
	DataService.Update(player, "cash", function(cash)
		return cash - ball.price
	end)
	DataService.Update(player, "balls", function(balls)
		balls.owned[ball.id] = true
		return balls
	end)
	return { ok = true }
end

-- When Cash first covers the next ball, say so once (per tier, per run).
local function checkNotice(player: Player)
	local data = DataService.Get(player)
	if data == nil then
		return
	end
	local ball = Formulas.nextBall(data)
	if ball == nil or data.cash < ball.price or data.balls.notified[ball.id] then
		return
	end
	DataService.Update(player, "balls", function(balls)
		balls.notified[ball.id] = true
		return balls
	end)
	Remotes.Event("ShopNotice"):FireClient(player, { kind = "ball", id = ball.id })
end

function BallService.Start()
	Remotes.Function("BuyBall").OnServerInvoke = function(player: Player, ballId: unknown): Result
		if not limit:Allow(player) then
			return { ok = false, err = "too fast" }
		end
		if type(ballId) ~= "string" or #ballId > 40 then
			return { ok = false, err = "bad args" }
		end
		return BallService.Buy(player, ballId)
	end
	DataService.Changed:Connect(function(player: Player, key: string)
		if key == "cash" or key == "balls" then
			checkNotice(player)
		end
	end)
	DataService.Loaded:Connect(checkNotice)
end

return BallService
