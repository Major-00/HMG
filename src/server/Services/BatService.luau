--!strict
-- BatService: buying and equipping bats with Cash. Bats are bought in order (Config/Bats);
-- buying one equips it, and any owned bat can be equipped again. The equipped bat multiplies
-- the Power each hit gives (Formulas.multiplier). Cash only: no Robux path to a bat.
--   BuyBat(batId)   (RemoteFunction) -> { ok, err? }: the next bat, and affordable
--   EquipBat(batId) (RemoteFunction) -> { ok, err? }: a bat you own

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Bats = require(Shared.Config.Bats)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)

local BatService = {}

local limit = RateLimit.new(5)

type Result = { ok: boolean, err: string? }

-- The next bat to buy: the first in order you don't own.
local function nextBat(data: any): Bats.Bat?
	for _, bat in Bats.List do
		if not data.bats.owned[bat.id] then
			return bat
		end
	end
	return nil
end

function BatService.Buy(player: Player, batId: string): Result
	local data = DataService.Get(player)
	if data == nil then
		return { ok = false, err = "not loaded" }
	end
	local bat = nextBat(data)
	if bat == nil or bat.id ~= batId then
		return { ok = false, err = "not next" }
	end
	if data.cash < bat.price then
		return { ok = false, err = "not enough cash" }
	end
	DataService.Update(player, "cash", function(cash)
		return cash - bat.price
	end)
	DataService.Update(player, "bats", function(bats)
		bats.owned[bat.id] = true
		bats.equipped = bat.id
		return bats
	end)
	return { ok = true }
end

function BatService.Equip(player: Player, batId: string): Result
	local data = DataService.Get(player)
	if data == nil then
		return { ok = false, err = "not loaded" }
	end
	if not data.bats.owned[batId] or Bats.ById[batId] == nil then
		return { ok = false, err = "not owned" }
	end
	DataService.Update(player, "bats", function(bats)
		bats.equipped = batId
		return bats
	end)
	return { ok = true }
end

local function handle(name: string, fn: (Player, string) -> Result)
	Remotes.Function(name).OnServerInvoke = function(player: Player, batId: unknown): Result
		if not limit:Allow(player) then
			return { ok = false, err = "too fast" }
		end
		if type(batId) ~= "string" or #batId > 40 then
			return { ok = false, err = "bad args" }
		end
		return fn(player, batId)
	end
end

function BatService.Start()
	handle("BuyBat", BatService.Buy)
	handle("EquipBat", BatService.Equip)
end

return BatService
