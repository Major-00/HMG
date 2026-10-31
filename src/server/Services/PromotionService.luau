--!strict
-- PromotionService: stadium promotion (the rebirth). Promote() (RemoteFunction) -> { ok, err? }.
-- Needs the next tier's requirements (Config/Stadium, checked with Formulas.promotionStatus).
-- Then, all on the server and in one go (no yields):
--   resets  Cash (first, so the shop's "next ball" notice never fires on the way down), balls,
--           bats, park upgrades, Power and this run's biome progress, back to new-run values;
--   keeps   every Mascot (seats, hotbar, On Deck), locks, the Index, settings, lifetime stats;
--   raises  stadiumTier by one: its Power and Cash multipliers apply from now on, and tier N
--           plays World N.
-- Promotion can never be bought with Robux; there's no other way to raise the tier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local Server = script.Parent.Parent
local Template = require(Server.Data.Template)
local DataService = require(script.Parent.DataService)
local RateLimit = require(Server.Util.RateLimit)

local PromotionService = {}

local limit = RateLimit.new(1)

type Result = { ok: boolean, err: string? }

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Run progress that promotion resets, in this order (Cash first; see the header).
local RESETS = { "cash", "balls", "bats", "park", "power", "highestBiome" }

function PromotionService.Promote(player: Player): Result
	local data = DataService.Get(player)
	if data == nil then
		return { ok = false, err = "not loaded" }
	end
	local status = Formulas.promotionStatus(data)
	if status.next == nil then
		return { ok = false, err = "top tier" }
	end
	if not status.ready then
		return { ok = false, err = "requirements not met" }
	end
	local template = Template :: any
	for _, key in RESETS do
		DataService.Update(player, key, function()
			return deepCopy(template[key])
		end)
	end
	DataService.Update(player, "stadiumTier", function(tier)
		return tier + 1
	end)
	return { ok = true }
end

function PromotionService.Start()
	Remotes.Function("Promote").OnServerInvoke = function(player: Player): Result
		if not limit:Allow(player) then
			return { ok = false, err = "too fast" }
		end
		return PromotionService.Promote(player)
	end
end

return PromotionService
