--!strict
-- MascotService: the catch phase of the on-land hook. Every landing catches one Mascot:
--   1. Roll the species from Formulas.catchOdds (landing biome and distance, best ball owned),
--      then its variant and size, with the server's Random. The client never sends anything here.
--   2. Unlock or update its Index card and count it in lifetime.mascotsCaught (even if it's sold
--      right away).
--   3. Place it with MascotInventory's rules (seat, hotbar, Auto-Sell, On Deck, Lock) and pay out
--      any sale at full value.
-- Player actions (remotes, each returns { ok, err?, cash?, species? }):
--   SellMascot(uid), LockMascot(uid, locked), MoveMascot(uid, place, slot) (swaps if taken; this
--   is also how On Deck is swapped into the hotbar), EquipBest(), SetAutoSell(on).
-- Inventory changes are checked (MascotInventory.Check) before they're written, so a broken
-- rule can never corrupt a save. Never yields, and never blocks the swing loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local HookTypes = require(Shared.HookTypes)
local Mascots = require(Shared.Config.Mascots)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

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

-- Adds a new Mascot to the player's save: places it, pays any sale, updates the Index and the
-- lifetime count. Used by every catch (and by Studio's DevData "grant").
local function add(player: Player, entry: Types.MascotEntry): HookTypes.Catch?
	local data = DataService.Get(player) :: any
	local species = Mascots.ById[entry.species]
	if data == nil or species == nil then
		return nil
	end
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

-- The catch phase: rolls the Mascot for this landing, then adds it.
local function catchAt(ctx: HookTypes.LandingContext): HookTypes.Catch?
	local data = DataService.Get(ctx.player) :: any
	if data == nil then
		return nil
	end
	local odds =
		Formulas.catchOdds(data.stadiumTier, Formulas.bestBall(data).id, ctx.biomeIndex, ctx.landedAt)
	local speciesId = Formulas.rollSpecies(odds, rng)
	if speciesId == nil then
		return nil -- no Mascots configured for this biome
	end
	return add(ctx.player, {
		species = speciesId,
		variant = Formulas.rollVariant(rng),
		size = Formulas.rollSize(rng),
		locked = false,
	})
end

-- PLAYER ACTIONS ----------------------------------------------------------------------------
-- Every action works on a copy of the inventory, is checked, then saved. It never touches the
-- swing loop. Sales pay full value; locked Mascots can't be sold.

export type ActionResult = { ok: boolean, err: string?, cash: number?, species: string? }

local function act(
	player: Player,
	fn: (inv: MascotInventory.Inventory) -> (boolean, string?, MascotInventory.Sold?)
): ActionResult
	local data = DataService.Get(player)
	if data == nil then
		return { ok = false, err = "not loaded" }
	end
	local inv = MascotInventory.FromData(data)
	local ok, err, sold = fn(inv)
	if not ok then
		return { ok = false, err = err }
	end
	if not commit(player, inv) then
		return { ok = false, err = "check failed" }
	end
	if sold then
		addCash(player, sold.cash)
		return { ok = true, cash = sold.cash, species = sold.mascot.species }
	end
	return { ok = true }
end

function MascotService.Sell(player: Player, uid: string): ActionResult
	return act(player, function(inv)
		local sold, err = MascotInventory.Sell(inv, uid)
		return sold ~= nil, err, sold
	end)
end

function MascotService.SetLock(player: Player, uid: string, locked: boolean): ActionResult
	return act(player, function(inv)
		local ok, err = MascotInventory.SetLock(inv, uid, locked)
		return ok, err, nil
	end)
end

function MascotService.Move(player: Player, uid: string, place: string, slot: number): ActionResult
	return act(player, function(inv)
		local ok, err = MascotInventory.Move(inv, uid, place :: any, slot)
		return ok, err, nil
	end)
end

function MascotService.EquipBest(player: Player): ActionResult
	return act(player, function(inv)
		MascotInventory.EquipBest(inv)
		return true, nil, nil
	end)
end

function MascotService.SetAutoSell(player: Player, on: boolean): ActionResult
	return act(player, function(inv)
		MascotInventory.SetAutoSell(inv, on)
		return true, nil, nil
	end)
end

-- Studio only (DevService): adds a Mascot as if it was caught.
function MascotService.Grant(
	player: Player,
	speciesId: string,
	variant: string?,
	size: string?
): HookTypes.Catch?
	if Mascots.ById[speciesId] == nil then
		return nil
	end
	return add(
		player,
		{ species = speciesId, variant = variant or "none", size = size or "normal", locked = false }
	)
end

-- Remotes: argument types are checked here, ids and slots by MascotInventory. A few actions per
-- second is plenty for a tapping player; more is ignored.
local ACTIONS_PER_SECOND = 10
local budget: { [Player]: { tokens: number, at: number } } = {}

local function allow(player: Player): boolean
	local now = os.clock()
	local b = budget[player]
	if b == nil then
		b = { tokens = ACTIONS_PER_SECOND, at = now }
		budget[player] = b
	end
	b.tokens = math.min(ACTIONS_PER_SECOND, b.tokens + (now - b.at) * ACTIONS_PER_SECOND)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function isUid(value: unknown): boolean
	return type(value) == "string" and #value <= 20
end

local function handle(name: string, fn: (player: Player, ...any) -> ActionResult)
	Remotes.Function(name).OnServerInvoke = function(player: Player, ...): ActionResult
		if not allow(player) then
			return { ok = false, err = "too fast" }
		end
		return fn(player, ...)
	end
end

function MascotService.Start()
	LandingService.SetCatcher(catchAt)

	handle("SellMascot", function(player, uid)
		if not isUid(uid) then
			return { ok = false, err = "bad args" }
		end
		return MascotService.Sell(player, uid)
	end)
	handle("LockMascot", function(player, uid, locked)
		if not isUid(uid) or type(locked) ~= "boolean" then
			return { ok = false, err = "bad args" }
		end
		return MascotService.SetLock(player, uid, locked)
	end)
	handle("MoveMascot", function(player, uid, place, slot)
		if not isUid(uid) or type(place) ~= "string" or type(slot) ~= "number" or slot ~= slot then
			return { ok = false, err = "bad args" }
		end
		return MascotService.Move(player, uid, place, slot)
	end)
	handle("EquipBest", function(player)
		return MascotService.EquipBest(player)
	end)
	handle("SetAutoSell", function(player, on)
		if type(on) ~= "boolean" then
			return { ok = false, err = "bad args" }
		end
		return MascotService.SetAutoSell(player, on)
	end)
	-- The player opened the Index: every species caught so far counts as seen (clears "new").
	-- Display bookkeeping only; the server copies its own Index, the client sends nothing.
	handle("MarkIndexSeen", function(player)
		local data = DataService.Get(player)
		if data == nil then
			return { ok = false, err = "not loaded" }
		end
		DataService.Update(player, "settings", function(settings)
			settings.indexSeen = settings.indexSeen or {}
			for species in data.index do
				settings.indexSeen[species] = true
			end
			return settings
		end)
		return { ok = true }
	end)

	Players.PlayerRemoving:Connect(function(player)
		budget[player] = nil
	end)
end

return MascotService
