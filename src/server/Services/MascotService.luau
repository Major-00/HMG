--!strict
-- MascotService: the catch phase of the on-land hook. Every landing catches one Mascot:
--   1. Roll the species from Formulas.catchOdds (landing biome and distance, best ball owned),
--      then its variant and size, with the server's Random. The client never sends anything here.
--   2. Add it to the save, unlock or update its Index card, count it in lifetime.mascotsCaught.
--   3. Place it: the first free seat, else the first free hotbar slot.
--      Roster full (temporary rule until the inventory step adds On Deck and the Auto-Sell
--      toggle): the new catch is compared with the weakest unlocked hotbar Mascot by Cash/s and
--      the weaker one sells at full value (on a tie the newer one sells). If every hotbar Mascot
--      is locked, the new catch sells. A locked Mascot is never sold (Safe at home).
-- Never yields, and never blocks the swing loop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local HookTypes = require(Shared.HookTypes)
local Mascots = require(Shared.Config.Mascots)

local Services = script.Parent
local DataService = require(Services.DataService)
local LandingService = require(Services.LandingService)

local MascotService = {}

local rng = Random.new()

local function uidNumber(uid: string): number
	return tonumber(string.match(uid, "%d+")) or 0
end

local function firstFree(slots: { any }): number?
	for i, uid in slots do
		if uid == false then
			return i
		end
	end
	return nil
end

-- The weakest unlocked hotbar Mascot: lowest Cash/s, and on a tie the newest (it sells first).
local function weakestUnlockedHotbar(data: any): (number?, string?, number)
	local bestSlot: number? = nil
	local bestUid: string? = nil
	local bestValue = math.huge
	for i, uid in data.hotbar do
		local mascot = if uid then data.mascots[uid] else nil
		if mascot and not mascot.locked then
			local value = Formulas.mascotCashPerSec(mascot)
			local weaker = value < bestValue
				or (value == bestValue and bestUid ~= nil and uidNumber(uid) > uidNumber(bestUid))
			if weaker then
				bestSlot, bestUid, bestValue = i, uid, value
			end
		end
	end
	return bestSlot, bestUid, bestValue
end

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

local function catchAt(ctx: HookTypes.LandingContext): HookTypes.Catch?
	local player = ctx.player
	local data = DataService.Get(player) :: any
	if data == nil then
		return nil
	end

	-- 1. Roll.
	local world = data.stadiumTier
	local odds = Formulas.catchOdds(world, Formulas.bestBall(data).id, ctx.biomeIndex, ctx.landedAt)
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
	local cashPerSec = Formulas.mascotCashPerSec(entry)
	local isNewSpecies = data.index[species.id] == nil

	-- 2. Record: Index and lifetime count happen even if this Mascot is sold right away.
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

	local catch: HookTypes.Catch = {
		uid = uid,
		species = species.id,
		rarity = species.rarity,
		variant = entry.variant,
		size = entry.size,
		cashPerSec = cashPerSec,
		placedIn = "sold",
		slot = nil,
		isNewSpecies = isNewSpecies,
		sold = nil,
	}

	-- 3. Place.
	local seat = firstFree(data.seats)
	local hotbarSlot = if seat then nil else firstFree(data.hotbar)
	local place: ("seats" | "hotbar")? = nil
	local slot: number? = nil
	if seat then
		place, slot = "seats", seat
	elseif hotbarSlot then
		place, slot = "hotbar", hotbarSlot
	else
		local weakSlot, weakUid, weakValue = weakestUnlockedHotbar(data)
		if weakSlot and weakUid and cashPerSec > weakValue then
			-- The new catch is stronger: sell the weakest unlocked hotbar Mascot to make room.
			local old = data.mascots[weakUid]
			local value = Formulas.mascotSellValue(old)
			catch.sold = { species = old.species, variant = old.variant, size = old.size, cash = value }
			DataService.Update(player, "mascots", function(mascots)
				mascots[weakUid] = nil
				return mascots
			end)
			addCash(player, value)
			place, slot = "hotbar", weakSlot
		end
	end

	if place and slot then
		local key = place :: string
		local at = slot :: number
		DataService.Update(player, "mascots", function(mascots)
			mascots[uid] = entry
			return mascots
		end)
		DataService.Update(player, key, function(slots)
			slots[at] = uid
			return slots
		end)
		catch.placedIn = if key == "seats" then "seat" else "hotbar"
		catch.slot = at
	else
		-- The new catch is the weaker one (or every hotbar Mascot is locked): it sells at once.
		local value = Formulas.mascotSellValue(entry)
		catch.sold = { species = entry.species, variant = entry.variant, size = entry.size, cash = value }
		addCash(player, value)
	end
	return catch
end

function MascotService.Start()
	LandingService.SetCatcher(catchAt)
end

return MascotService
