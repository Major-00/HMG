--!strict
-- MascotInventoryTest: checks every MascotInventory rule. Run from Studio through
-- DevData:Invoke("selftest", userId) (DevService). Changes no save.
--   1. Scripted scenarios, one per rule.
--   2. Random actions (catch, sell, lock, Auto-Sell, move, Equip Best). After each one: the
--      inventory passes Check, no locked Mascot has disappeared, no seated Mascot was sold by a
--      catch, every sale paid full value, and there are never more than 15 Mascots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local MascotInventory = require(script.Parent.Parent.Services.MascotInventory)

type Inventory = MascotInventory.Inventory

local Test = {}

-- Sandlot species, weakest to strongest Cash/s: 1, 3, 10, 35, 150, 1000.
local BY_STRENGTH =
	{ "dust_bunny", "glove_gopher", "sunny_hound", "dugout_badger", "grand_slam_lion", "sandstorm_drake" }

local function empty(): Inventory
	return {
		mascots = {},
		seats = { false, false, false, false, false, false, false, false, false, false },
		hotbar = { false, false, false, false },
		onDeck = false,
		autoSell = true,
	}
end

local function mascot(strength: number, variant: string?, size: string?): any
	return {
		species = BY_STRENGTH[strength],
		variant = variant or "none",
		size = size or "normal",
		locked = false,
	}
end

-- A full inventory: 10 seats of strength `seatStrength`, hotbar of `hotbarStrengths`.
local function full(seatStrength: number, hotbarStrengths: { number }): (Inventory, number)
	local inv = empty()
	local n = 0
	for _ = 1, 10 do
		n += 1
		MascotInventory.Place(inv, `m{n}`, mascot(seatStrength))
	end
	for _, s in hotbarStrengths do
		n += 1
		MascotInventory.Place(inv, `m{n}`, mascot(s))
	end
	return inv, n
end

function Test.Run(randomOps: number?): { [string]: any }
	local failures: { string } = {}
	local passed = 0
	local function check(name: string, condition: boolean, detail: string?)
		if condition then
			passed += 1
		else
			table.insert(failures, name .. (if detail then `: {detail}` else ""))
		end
	end
	local function valid(name: string, inv: Inventory)
		local ok, reason = MascotInventory.Check(inv)
		check(name .. " (inventory valid)", ok, reason)
	end

	-- 1. Fill order: seats 1-10, then hotbar 1-4.
	do
		local inv, _ = full(1, { 1, 1, 1, 1 })
		local seatsOk = true
		for i = 1, 10 do
			seatsOk = seatsOk and inv.seats[i] == `m{i}`
		end
		check("fill: seats in order", seatsOk)
		check("fill: hotbar in order", inv.hotbar[1] == "m11" and inv.hotbar[4] == "m14")
		valid("fill", inv)
	end

	-- 2. Auto-Sell ON, full, stronger catch: the weakest unlocked hotbar Mascot sells.
	do
		local inv, n = full(1, { 3, 2, 4, 3 })
		local r = MascotInventory.Place(inv, `m{n + 1}`, mascot(5))
		check("autosell stronger: catch kept", r.placedIn == "hotbar" and r.slot == 2)
		check("autosell stronger: weakest sold", r.sold ~= nil and (r.sold :: any).uid == "m12")
		check(
			"autosell stronger: full value",
			r.sold ~= nil and (r.sold :: any).cash == Formulas.mascotSellValue(mascot(2))
		)
		valid("autosell stronger", inv)
	end

	-- 3. Auto-Sell ON, weaker catch: the catch sells.
	do
		local inv, n = full(1, { 3, 3, 3, 3 })
		local r = MascotInventory.Place(inv, `m{n + 1}`, mascot(2))
		check("autosell weaker: catch sold", r.placedIn == "sold" and (r.sold :: any).uid == `m{n + 1}`)
		check("autosell weaker: hotbar unchanged", inv.hotbar[1] == "m11" and inv.hotbar[4] == "m14")
		valid("autosell weaker", inv)
	end

	-- 4. Tie between the catch and the weakest: the newer one (the catch) sells.
	do
		local inv, n = full(1, { 3, 3, 3, 3 })
		local r = MascotInventory.Place(inv, `m{n + 1}`, mascot(3))
		check("tie: catch sells", r.placedIn == "sold")
	end

	-- 5. Tie inside the hotbar: the newer of the two weakest sells.
	do
		local inv, n = full(1, { 2, 4, 2, 4 })
		local r = MascotInventory.Place(inv, `m{n + 1}`, mascot(5))
		check(
			"hotbar tie: newer sells",
			r.sold ~= nil and (r.sold :: any).uid == "m13",
			r.sold and (r.sold :: any).uid
		)
	end

	-- 5b. A locked Mascot that's the weakest is skipped: the weakest UNLOCKED one sells.
	do
		local inv, n = full(1, { 1, 3, 2, 4 })
		MascotInventory.SetLock(inv, "m11", true) -- the weakest, locked
		local r = MascotInventory.Place(inv, `m{n + 1}`, mascot(5))
		check(
			"locked weakest skipped",
			r.sold ~= nil and (r.sold :: any).uid == "m13" and inv.mascots.m11 ~= nil,
			r.sold and (r.sold :: any).uid
		)
	end

	-- 6. Variant and size count: an All-Star Giant Dust Bunny (1 x 1.5 x 3 = 4.5) beats a plain
	--    Glove Gopher (3).
	do
		local inv, n = full(1, { 2, 4, 4, 4 })
		local r = MascotInventory.Place(inv, `m{n + 1}`, mascot(1, "allStar", "giant"))
		check("variant and size count", r.placedIn == "hotbar" and (r.sold :: any).uid == "m11")
	end

	-- 7. Every hotbar Mascot locked, Auto-Sell ON: the catch goes On Deck, and locked ones stay.
	do
		local inv, n = full(1, { 1, 1, 1, 1 })
		for i = 11, 14 do
			MascotInventory.SetLock(inv, `m{i}`, true)
		end
		local r = MascotInventory.Place(inv, `m{n + 1}`, mascot(3))
		check(
			"all locked: catch On Deck",
			r.placedIn == "onDeck" and inv.onDeck == `m{n + 1}` and r.sold == nil
		)
		-- A stronger catch replaces the On Deck one; a weaker one sells.
		local r2 = MascotInventory.Place(inv, `m{n + 2}`, mascot(4))
		check(
			"all locked: stronger replaces On Deck",
			inv.onDeck == `m{n + 2}` and (r2.sold :: any).uid == `m{n + 1}`
		)
		local r3 = MascotInventory.Place(inv, `m{n + 3}`, mascot(2))
		check("all locked: weaker catch sells", r3.placedIn == "sold" and inv.onDeck == `m{n + 2}`)
		local lockedKept = true
		for i = 11, 14 do
			lockedKept = lockedKept and inv.mascots[`m{i}`] ~= nil
		end
		check("all locked: locked kept", lockedKept)
		valid("all locked", inv)
	end

	-- 8. Locked On Deck Mascot: the catch sells, even when it's stronger.
	do
		local inv, n = full(1, { 1, 1, 1, 1 })
		MascotInventory.SetAutoSell(inv, false)
		MascotInventory.Place(inv, `m{n + 1}`, mascot(2))
		MascotInventory.SetLock(inv, `m{n + 1}`, true)
		local r = MascotInventory.Place(inv, `m{n + 2}`, mascot(6))
		check("locked On Deck: catch sells", r.placedIn == "sold" and inv.onDeck == `m{n + 1}`)
		valid("locked On Deck", inv)
	end

	-- 9. Auto-Sell OFF: overflow goes On Deck; weak unlocked hotbar Mascots are left alone.
	do
		local inv, n = full(1, { 1, 1, 1, 1 })
		MascotInventory.SetAutoSell(inv, false)
		local r = MascotInventory.Place(inv, `m{n + 1}`, mascot(5))
		check("autosell off: On Deck", r.placedIn == "onDeck" and r.sold == nil)
		check("autosell off: hotbar untouched", inv.hotbar[1] == "m11" and inv.mascots.m11 ~= nil)
		local r2 = MascotInventory.Place(inv, `m{n + 2}`, mascot(3))
		check("autosell off: weaker of two sells", r2.placedIn == "sold" and inv.onDeck == `m{n + 1}`)
		-- Turning Auto-Sell on sells nothing by itself.
		local before = 0
		for _ in inv.mascots do
			before += 1
		end
		MascotInventory.SetAutoSell(inv, true)
		local after = 0
		for _ in inv.mascots do
			after += 1
		end
		check("autosell on: sells nothing", before == after and inv.onDeck == `m{n + 1}`)
		valid("autosell off", inv)
	end

	-- 10. Seated Mascots are never sold by a catch, however weak.
	do
		local inv, n = full(1, { 6, 6, 6, 6 })
		MascotInventory.Place(inv, `m{n + 1}`, mascot(6))
		local seatsKept = true
		for i = 1, 10 do
			seatsKept = seatsKept and inv.mascots[`m{i}`] ~= nil
		end
		check("seats never auto-sold", seatsKept)
	end

	-- 11. Sell by tap: refused when locked or unknown; otherwise full value and the slot is freed.
	do
		local inv, _ = full(2, {})
		MascotInventory.SetLock(inv, "m3", true)
		local s1, e1 = MascotInventory.Sell(inv, "m3")
		check("sell locked refused", s1 == nil and e1 == "locked" and inv.mascots.m3 ~= nil)
		local s2, e2 = MascotInventory.Sell(inv, "nope")
		check("sell unknown refused", s2 == nil and e2 == "unknown")
		local s3 = MascotInventory.Sell(inv, "m4")
		check("sell: full value", s3 ~= nil and (s3 :: any).cash == Formulas.mascotSellValue(mascot(2)))
		check("sell: seat freed", inv.seats[4] == false and inv.mascots.m4 == nil)
		valid("sell", inv)
	end

	-- 12. Move swaps when the target slot is taken.
	do
		local inv, n = full(1, { 2, 3 })
		local ok1 = MascotInventory.Move(inv, "m11", "seats", 1)
		check("move swap", ok1 and inv.seats[1] == "m11" and inv.hotbar[1] == "m1")
		local ok2 = MascotInventory.Move(inv, "m12", "hotbar", 4)
		check("move to empty", ok2 and inv.hotbar[4] == "m12" and inv.hotbar[2] == false)
		MascotInventory.SetAutoSell(inv, false)
		MascotInventory.Place(inv, `m{n + 1}`, mascot(1))
		MascotInventory.Place(inv, `m{n + 2}`, mascot(1))
		MascotInventory.Place(inv, `m{n + 3}`, mascot(4)) -- hotbar full now -> On Deck
		local ok3 = MascotInventory.Move(inv, `m{n + 3}`, "hotbar", 1)
		check("On Deck swaps into hotbar", ok3 and inv.hotbar[1] == `m{n + 3}` and inv.onDeck == "m1")
		local ok4, e4 = MascotInventory.Move(inv, "m2", "seats", 11)
		check("move bad slot refused", not ok4 and e4 == "bad slot")
		local ok5, e5 = MascotInventory.Move(inv, "m2", "nowhere" :: any, 1)
		check("move bad place refused", not ok5 and e5 == "bad place")
		valid("move", inv)
	end

	-- 13. Equip Best: top 10 by Cash/s in seats, then hotbar, then On Deck.
	do
		local inv = empty()
		MascotInventory.SetAutoSell(inv, false)
		local strengths = { 1, 6, 2, 5, 1, 3, 4, 1, 2, 6, 3, 1, 5, 2, 4 }
		for i, s in strengths do
			MascotInventory.Place(inv, `m{i}`, mascot(s))
		end
		MascotInventory.EquipBest(inv)
		local seatMin, restMax = math.huge, 0
		for _, uid in inv.seats do
			seatMin = math.min(seatMin, Formulas.mascotCashPerSec(inv.mascots[uid :: string]))
		end
		for _, uid in { inv.hotbar[1], inv.hotbar[2], inv.hotbar[3], inv.hotbar[4], inv.onDeck } do
			restMax = math.max(restMax, Formulas.mascotCashPerSec(inv.mascots[uid :: string]))
		end
		check("equip best: seats are the top 10", seatMin >= restMax, `{seatMin} vs {restMax}`)
		valid("equip best", inv)
	end

	-- 2. Random actions.
	local ops = randomOps or 10000
	local rng = Random.new(12345)
	local inv = empty()
	local nextUid = 1
	local variants = { "none" }
	for _, v in Tuning.Catch.VARIANTS do
		table.insert(variants, v.id)
	end
	local sizes = { "normal" }
	for _, s in Tuning.Catch.SIZES do
		table.insert(sizes, s.id)
	end
	local randomFailures = 0
	local function fail(msg: string)
		randomFailures += 1
		if randomFailures <= 5 then
			table.insert(failures, `random: {msg}`)
		end
	end
	local function anyUid(): string?
		local all = {}
		for uid in inv.mascots do
			table.insert(all, uid)
		end
		return if #all > 0 then all[rng:NextInteger(1, #all)] else nil
	end

	for step = 1, ops do
		local locked: { string } = {}
		local seated: { string } = {}
		for uid, m in inv.mascots do
			if m.locked then
				table.insert(locked, uid)
			end
		end
		for _, uid in inv.seats do
			if uid then
				table.insert(seated, uid)
			end
		end

		local roll = rng:NextInteger(1, 100)
		local action
		if roll <= 55 then
			action = "catch"
			local m = {
				species = BY_STRENGTH[rng:NextInteger(1, #BY_STRENGTH)],
				variant = variants[rng:NextInteger(1, #variants)],
				size = sizes[rng:NextInteger(1, #sizes)],
				locked = false,
			}
			local r = MascotInventory.Place(inv, `m{nextUid}`, m)
			nextUid += 1
			local sold = r.sold
			if sold and sold.cash ~= Formulas.mascotSellValue(sold.mascot) then
				fail(`step {step}: sale not at full value`)
			end
			for _, uid in seated do
				if inv.mascots[uid] == nil then
					fail(`step {step}: a catch sold seated Mascot {uid}`)
				end
			end
		elseif roll <= 67 then
			action = "sell"
			local uid = anyUid()
			if uid then
				local wasLocked = inv.mascots[uid].locked
				local sold = MascotInventory.Sell(inv, uid)
				if wasLocked and sold ~= nil then
					fail(`step {step}: sold a locked Mascot by tap`)
				end
			end
		elseif roll <= 82 then
			action = "lock"
			local uid = anyUid()
			if uid then
				MascotInventory.SetLock(inv, uid, rng:NextNumber() < 0.6)
			end
		elseif roll <= 86 then
			action = "autosell"
			MascotInventory.SetAutoSell(inv, rng:NextNumber() < 0.5)
		elseif roll <= 97 then
			action = "move"
			local uid = anyUid()
			if uid then
				local places = { "seats", "hotbar", "onDeck" }
				local place = places[rng:NextInteger(1, 3)] :: MascotInventory.Place
				local maxSlot = if place == "seats" then 10 elseif place == "hotbar" then 4 else 1
				MascotInventory.Move(inv, uid, place, rng:NextInteger(1, maxSlot))
			end
		else
			action = "equipbest"
			MascotInventory.EquipBest(inv)
		end

		local ok, reason = MascotInventory.Check(inv)
		if not ok then
			fail(`step {step} ({action}): {reason}`)
		end
		for _, uid in locked do
			if inv.mascots[uid] == nil then
				fail(`step {step} ({action}): locked Mascot {uid} disappeared`)
			end
		end
		local count = 0
		for _ in inv.mascots do
			count += 1
		end
		if count > 15 then
			fail(`step {step} ({action}): {count} Mascots`)
		end
	end
	check(`random: {ops} actions`, randomFailures == 0, `{randomFailures} failures`)

	return { passed = passed, failed = #failures, failures = failures, randomOps = ops }
end

return Test
