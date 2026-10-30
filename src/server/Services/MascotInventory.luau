--!strict
-- MascotInventory: every rule for where a player's Mascots sit. Pure: it only changes the
-- `Inventory` table it's given and returns what happened; the caller writes the result to the
-- save (MascotService) and pays out any sales. No services, no yields, so it's testable alone
-- (server/Dev/MascotInventoryTest).
--
-- Slots: 10 seats (earn Cash), 4 hotbar slots and 1 On Deck slot (don't earn). Max 15 Mascots.
-- A new catch (Place):
--   1. takes the first free seat, else the first free hotbar slot.
--   2. Full, Auto-Sell ON: compared with the weakest UNLOCKED hotbar Mascot by Cash/s; the weaker
--      one sells at full value (on a tie the newer one sells, so the catch).
--   3. Full and every hotbar Mascot locked, or Auto-Sell OFF: the catch goes to On Deck if it's
--      empty. If On Deck is taken, the weaker of the two sells; if the On Deck Mascot is locked,
--      the catch sells.
-- A locked Mascot is never sold by these rules and can't be sold by tap either (unlock first).
-- Turning Auto-Sell on sells nothing; the rules apply from the next catch.
-- Equip Best seats the top 10 earners, then fills the hotbar, then On Deck.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Types = require(ReplicatedStorage.Shared.Types)

local MascotInventory = {}

MascotInventory.SEATS = 10
MascotInventory.HOTBAR = 4

export type Inventory = {
	mascots: { [string]: Types.MascotEntry },
	seats: { Types.Slot },
	hotbar: { Types.Slot },
	onDeck: Types.Slot,
	autoSell: boolean,
}

export type Place = "seats" | "hotbar" | "onDeck"

export type Sold = { uid: string, mascot: Types.MascotEntry, cash: number }

export type PlaceResult = {
	placedIn: "seat" | "hotbar" | "onDeck" | "sold",
	slot: number?, -- seat or hotbar index
	sold: Sold?, -- what was sold to make room (the catch itself when placedIn = "sold")
}

local function copyEntry(m: Types.MascotEntry): Types.MascotEntry
	return { species = m.species, variant = m.variant, size = m.size, locked = m.locked }
end

-- A deep copy of the inventory part of a save, safe to change.
function MascotInventory.FromData(data: any): Inventory
	local mascots = {}
	for uid, m in data.mascots do
		mascots[uid] = copyEntry(m)
	end
	return {
		mascots = mascots,
		seats = table.clone(data.seats),
		hotbar = table.clone(data.hotbar),
		onDeck = data.onDeck,
		autoSell = data.autoSell,
	}
end

local function uidNumber(uid: string): number
	return tonumber(string.match(uid, "%d+")) or 0
end

local function value(inv: Inventory, uid: string): number
	return Formulas.mascotCashPerSec(inv.mascots[uid])
end

-- True if `a` is the weaker of two Mascots: lower Cash/s, or on a tie the newer (higher uid).
local function weaker(inv: Inventory, a: string, b: string): boolean
	local va, vb = value(inv, a), value(inv, b)
	if va ~= vb then
		return va < vb
	end
	return uidNumber(a) > uidNumber(b)
end

local function firstFree(slots: { Types.Slot }): number?
	for i, uid in slots do
		if uid == false then
			return i
		end
	end
	return nil
end

-- Where a Mascot sits: (place, slot), or nil if it's not placed.
function MascotInventory.Find(inv: Inventory, uid: string): (Place?, number?)
	for i, at in inv.seats do
		if at == uid then
			return "seats", i
		end
	end
	for i, at in inv.hotbar do
		if at == uid then
			return "hotbar", i
		end
	end
	if inv.onDeck == uid then
		return "onDeck", 1
	end
	return nil, nil
end

local function clearSlot(inv: Inventory, place: Place, slot: number)
	if place == "seats" then
		inv.seats[slot] = false
	elseif place == "hotbar" then
		inv.hotbar[slot] = false
	else
		inv.onDeck = false
	end
end

local function slotAt(inv: Inventory, place: Place, slot: number): Types.Slot
	if place == "seats" then
		return inv.seats[slot]
	elseif place == "hotbar" then
		return inv.hotbar[slot]
	end
	return inv.onDeck
end

local function setSlot(inv: Inventory, place: Place, slot: number, uid: Types.Slot)
	if place == "seats" then
		inv.seats[slot] = uid
	elseif place == "hotbar" then
		inv.hotbar[slot] = uid
	else
		inv.onDeck = uid
	end
end

-- Removes a Mascot entirely and returns its sale. The only place a Mascot leaves the inventory.
local function sell(inv: Inventory, uid: string): Sold
	local mascot = inv.mascots[uid]
	assert(mascot ~= nil, "sell: unknown Mascot")
	assert(not mascot.locked, "sell: a locked Mascot is never sold")
	local place, slot = MascotInventory.Find(inv, uid)
	if place and slot then
		clearSlot(inv, place, slot)
	end
	inv.mascots[uid] = nil
	return { uid = uid, mascot = mascot, cash = Formulas.mascotSellValue(mascot) }
end

-- The weakest unlocked hotbar Mascot (slot, uid), or nil if there is none.
local function weakestUnlockedHotbar(inv: Inventory): (number?, string?)
	local bestSlot: number?, bestUid: string? = nil, nil
	for i, uid in inv.hotbar do
		if uid and not inv.mascots[uid].locked then
			if bestUid == nil or weaker(inv, uid, bestUid) then
				bestSlot, bestUid = i, uid
			end
		end
	end
	return bestSlot, bestUid
end

-- The On Deck rule: the catch goes On Deck if it's empty; otherwise the weaker of the two sells,
-- and a locked On Deck Mascot always stays.
local function placeOnDeck(inv: Inventory, uid: string): PlaceResult
	local current = inv.onDeck
	if current == false then
		inv.onDeck = uid
		return { placedIn = "onDeck", slot = nil, sold = nil }
	end
	local held = current :: string
	if inv.mascots[held].locked or weaker(inv, uid, held) then
		return { placedIn = "sold", slot = nil, sold = sell(inv, uid) }
	end
	local sold = sell(inv, held)
	inv.onDeck = uid
	return { placedIn = "onDeck", slot = nil, sold = sold }
end

-- Adds a new catch under `uid` and places it by the rules above. The new Mascot must be unlocked.
function MascotInventory.Place(inv: Inventory, uid: string, mascot: Types.MascotEntry): PlaceResult
	assert(inv.mascots[uid] == nil, "Place: uid already used")
	inv.mascots[uid] = copyEntry(mascot)
	inv.mascots[uid].locked = false

	local seat = firstFree(inv.seats)
	if seat then
		inv.seats[seat] = uid
		return { placedIn = "seat", slot = seat, sold = nil }
	end
	local hotbarSlot = firstFree(inv.hotbar)
	if hotbarSlot then
		inv.hotbar[hotbarSlot] = uid
		return { placedIn = "hotbar", slot = hotbarSlot, sold = nil }
	end

	if inv.autoSell then
		local weakSlot, weakUid = weakestUnlockedHotbar(inv)
		if weakSlot and weakUid then
			if weaker(inv, uid, weakUid) then
				return { placedIn = "sold", slot = nil, sold = sell(inv, uid) }
			end
			local sold = sell(inv, weakUid)
			inv.hotbar[weakSlot] = uid
			return { placedIn = "hotbar", slot = weakSlot, sold = sold }
		end
	end
	return placeOnDeck(inv, uid)
end

-- The player's own sell tap. Refused for a locked or unknown Mascot.
function MascotInventory.Sell(inv: Inventory, uid: string): (Sold?, string?)
	local mascot = inv.mascots[uid]
	if mascot == nil then
		return nil, "unknown"
	end
	if mascot.locked then
		return nil, "locked"
	end
	return sell(inv, uid), nil
end

function MascotInventory.SetLock(inv: Inventory, uid: string, locked: boolean): (boolean, string?)
	local mascot = inv.mascots[uid]
	if mascot == nil then
		return false, "unknown"
	end
	mascot.locked = locked
	return true, nil
end

-- Sells nothing by itself; the rules apply from the next catch.
function MascotInventory.SetAutoSell(inv: Inventory, on: boolean)
	inv.autoSell = on
end

-- Moves a Mascot to a seat, hotbar slot or On Deck. If that slot is taken, the two swap places.
function MascotInventory.Move(inv: Inventory, uid: string, place: Place, slot: number): (boolean, string?)
	local fromPlace, fromSlot = MascotInventory.Find(inv, uid)
	if fromPlace == nil or fromSlot == nil then
		return false, "unknown"
	end
	if place ~= "seats" and place ~= "hotbar" and place ~= "onDeck" then
		return false, "bad place"
	end
	if type(slot) ~= "number" then
		return false, "bad slot"
	end
	local size = if place == "seats"
		then MascotInventory.SEATS
		elseif place == "hotbar" then MascotInventory.HOTBAR
		else 1
	if slot ~= math.floor(slot) or slot < 1 or slot > size then
		return false, "bad slot"
	end
	local other = slotAt(inv, place, slot)
	setSlot(inv, place, slot, uid)
	setSlot(inv, fromPlace, fromSlot, other)
	return true, nil
end

-- Seats the top 10 earners (on a tie the older one first), then fills the hotbar, then On Deck.
function MascotInventory.EquipBest(inv: Inventory)
	local all = {}
	for uid in inv.mascots do
		table.insert(all, uid)
	end
	table.sort(all, function(a, b)
		return weaker(inv, b, a)
	end)
	for i = 1, MascotInventory.SEATS do
		inv.seats[i] = all[i] or false
	end
	for i = 1, MascotInventory.HOTBAR do
		inv.hotbar[i] = all[MascotInventory.SEATS + i] or false
	end
	inv.onDeck = all[MascotInventory.SEATS + MascotInventory.HOTBAR + 1] or false
end

-- Checks the inventory is consistent: 10 seats, 4 hotbar slots, every Mascot in exactly one
-- slot, and every slot pointing at a real Mascot. Returns ok, reason.
function MascotInventory.Check(inv: Inventory): (boolean, string?)
	if #inv.seats ~= MascotInventory.SEATS then
		return false, `{#inv.seats} seats`
	end
	if #inv.hotbar ~= MascotInventory.HOTBAR then
		return false, `{#inv.hotbar} hotbar slots`
	end
	local seen: { [string]: boolean } = {}
	local function visit(uid: Types.Slot): string?
		if uid == false then
			return nil
		end
		if type(uid) ~= "string" or inv.mascots[uid] == nil then
			return `slot points at missing Mascot {tostring(uid)}`
		end
		if seen[uid] then
			return `Mascot {uid} is in two slots`
		end
		seen[uid] = true
		return nil
	end
	for _, uid in inv.seats do
		local err = visit(uid)
		if err then
			return false, err
		end
	end
	for _, uid in inv.hotbar do
		local err = visit(uid)
		if err then
			return false, err
		end
	end
	local err = visit(inv.onDeck)
	if err then
		return false, err
	end
	for uid in inv.mascots do
		if not seen[uid] then
			return false, `Mascot {uid} isn't in any slot`
		end
	end
	return true, nil
end

return MascotInventory
