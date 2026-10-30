--!strict
-- MascotService: the catch phase of the on-land hook. Every landing catches one Mascot:
--   1. Roll the species from Formulas.catchOdds (landing biome and distance, best ball owned),
--      then its variant and size, with the server's Random. The client never sends anything here.
--   2. Unlock or update its Index card and count it in lifetime.mascotsCaught (even if it's sold
--      right away).
--   3. Place it with MascotInventory's rules (seat, hotbar, Auto-Sell, On Deck, Lock) and pay out
--      any sale at full value.
-- Inventory changes are checked (MascotInventory.Check) before they're written, so a broken
-- rule can never corrupt a save. Never yields, and never blocks the swing loop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local HookTypes = require(Shared.HookTypes)
local Mascots = require(Shared.Config.Mascots)

local Services = script.Parent
local DataService = require(Services.DataService)
local LandingService = require(Services.LandingService)
local MascotInventory = require(Services.MascotInventory)

local MascotService = {}

local rng = Random.new()

local function addCash(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	DataService.Update(player, "cash", function(cash)
		return cash + amount
	end)
	DataService.Update(player, "lifetime", function(lifetime)
		lifetime.cashEarned += amount
		return lifetime
	end)
end

-- Writes a changed inventory back to the save, after checking it. Returns false (and writes
-- nothing) if the check fails.
local function commit(player: Player, inv: MascotInventory.Inventory): boolean
	local ok, reason = MascotInventory.Check(inv)
	if not ok then
		warn(`[MascotService] Inventory check failed for {player.Name}, nothing saved: {reason}`)
		return false
	end
	DataService.Update(player, "mascots", function()
		return inv.mascots
	end)
	DataService.Update(player, "seats", function()
		return inv.seats
	end)
	DataService.Update(player, "hotbar", function()
		return inv.hotbar
	end)
	DataService.Update(player, "onDeck", function()
		return inv.onDeck
	end)
	DataService.Update(player, "autoSell", function()
		return inv.autoSell
	end)
	return true
end

local function catchAt(ctx: HookTypes.LandingContext): HookTypes.Catch?
	local player = ctx.player
	local data = DataService.Get(player) :: any
	if data == nil then
		return nil
	end

	-- 1. Roll.
	local odds =
		Formulas.catchOdds(data.stadiumTier, Formulas.bestBall(data).id, ctx.biomeIndex, ctx.landedAt)
	local speciesId = Formulas.rollSpecies(odds, rng)
	local species = if speciesId then Mascots.ById[speciesId] else nil
	if species == nil then
		return nil -- no Mascots configured for this biome
	end
	local entry = {
		species = species.id,
		variant = Formulas.rollVariant(rng),
		size = Formulas.rollSize(rng),
		locked = false,
	}
	local uid = `m{data.nextMascotUid}`
	local isNewSpecies = data.index[species.id] == nil

	-- 3 (worked out first, so nothing is recorded if the inventory is broken). Place.
	local inv = MascotInventory.FromData(data)
	local placed = MascotInventory.Place(inv, uid, entry)
	if not commit(player, inv) then
		return nil
	end
	local sold = placed.sold
	if sold then
		addCash(player, sold.cash)
	end

	-- 2. Record: the Index and lifetime count include Mascots sold right away.
	DataService.Update(player, "nextMascotUid", function(n)
		return n + 1
	end)
	DataService.Update(player, "index", function(index)
		local card = index[species.id]
		if card == nil then
			card = { count = 0, variants = {}, sizes = {} }
			index[species.id] = card
		end
		card.count += 1
		card.variants[entry.variant] = true
		card.sizes[entry.size] = true
		return index
	end)
	DataService.Update(player, "lifetime", function(lifetime)
		lifetime.mascotsCaught += 1
		return lifetime
	end)

	return {
		uid = uid,
		species = species.id,
		rarity = species.rarity,
		variant = entry.variant,
		size = entry.size,
		cashPerSec = Formulas.mascotCashPerSec(entry),
		placedIn = placed.placedIn,
		slot = placed.slot,
		isNewSpecies = isNewSpecies,
		sold = if sold
			then {
				species = sold.mascot.species,
				variant = sold.mascot.variant,
				size = sold.mascot.size,
				cash = sold.cash,
			}
			else nil,
	}
end

function MascotService.Start()
	LandingService.SetCatcher(catchAt)
end

return MascotService
