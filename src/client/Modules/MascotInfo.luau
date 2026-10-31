--!strict
-- MascotInfo: how a saved Mascot is described in the UI (hotbar, Mascots panel), and the little
-- helpers both use: picking a slot to move into, and the sell button with a second-tap confirm
-- for Rare and up. Display only: every action still goes to the server (MascotController).
--   MascotInfo.Describe(mascot) -> { name, rarityName, rarityColor, details, cashPerSec, sellValue, rarePlus }
--   MascotInfo.SeatTarget(data)    -> seat index to move a Mascot into (empty, else the weakest)
--   MascotInfo.HotbarTarget(data)  -> hotbar index to move a Mascot into (empty, else the weakest unlocked)
--   MascotInfo.SellButton(button, uid, mascot) -> wires a button: tap to sell (twice for Rare+)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Format = require(Shared:WaitForChild("Format"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Mascots = require(Config:WaitForChild("Mascots"))
local Tuning = require(Config:WaitForChild("Tuning"))

local MascotInfo = {}

local CONFIRM_SECONDS = 3 -- a Rare+ sell needs a second tap within this time
local FRESH_SECONDS = 0.35 -- a newly drawn Sell button ignores taps this long
local CONFIRM_FROM_RANK = Mascots.RarityRank.rare

export type Info = {
	name: string,
	rarityName: string,
	rarityColor: Color3,
	details: string, -- "Rare · Gold Glove · Big"
	cashPerSec: number,
	sellValue: number,
	rarePlus: boolean,
}

local function displayNameIn(list: { any }, id: string): string?
	for _, entry in list do
		if entry.id == id then
			return entry.displayName
		end
	end
	return nil
end

function MascotInfo.Describe(mascot: any): Info
	local species = Mascots.ById[mascot.species]
	local rank = if species then Mascots.RarityRank[species.rarity] or 1 else 1
	local rarity = Mascots.Rarities[rank]
	local parts = { rarity.displayName }
	local variant = displayNameIn(Tuning.Catch.VARIANTS, mascot.variant)
	if variant then
		table.insert(parts, variant)
	end
	local size = displayNameIn(Tuning.Catch.SIZES, mascot.size)
	if size then
		table.insert(parts, size)
	end
	return {
		name = if species then species.displayName else "???",
		rarityName = rarity.displayName,
		rarityColor = rarity.color,
		details = table.concat(parts, " · "),
		cashPerSec = Formulas.mascotCashPerSec(mascot),
		sellValue = Formulas.mascotSellValue(mascot),
		rarePlus = rank >= CONFIRM_FROM_RANK,
	}
end

local function weakestIndex(data: any, slots: { any }, skipLocked: boolean): number?
	local best: number?, bestValue = nil, math.huge
	for i, uid in slots do
		local mascot = if uid then data.mascots[uid] else nil
		if mascot and not (skipLocked and mascot.locked) then
			local value = Formulas.mascotCashPerSec(mascot)
			if value < bestValue then
				best, bestValue = i, value
			end
		end
	end
	return best
end

local function firstEmpty(slots: { any }): number?
	for i, uid in slots do
		if uid == false then
			return i
		end
	end
	return nil
end

function MascotInfo.SeatTarget(data: any): number?
	return firstEmpty(data.seats) or weakestIndex(data, data.seats, false)
end

function MascotInfo.HotbarTarget(data: any): number?
	return firstEmpty(data.hotbar)
		or weakestIndex(data, data.hotbar, true)
		or weakestIndex(data, data.hotbar, false)
end

-- Wires `button` to sell Mascot `uid`. Locked Mascots can't be sold (the button says so).
-- Rare and up ask for a second tap within CONFIRM_SECONDS. A button ignores taps for its first
-- FRESH_SECONDS, so a tap aimed at the button that was just replaced can't sell the new Mascot.
-- `sell` is MascotController.Sell; if the server refuses, the button goes back to normal.
function MascotInfo.SellButton(button: TextButton, uid: string, mascot: any, sell: (uid: string) -> any)
	local info = MascotInfo.Describe(mascot)
	local idle = if mascot.locked then "Locked" else `Sell ${Format.number(info.sellValue)}`
	button.Text = idle
	button.AutoButtonColor = not mascot.locked
	local createdAt = os.clock()
	local armedAt: number? = nil
	button.Activated:Connect(function()
		if mascot.locked or os.clock() - createdAt < FRESH_SECONDS then
			return
		end
		if info.rarePlus and (armedAt == nil or os.clock() - armedAt > CONFIRM_SECONDS) then
			armedAt = os.clock()
			button.Text = "Tap again to sell"
			task.delay(CONFIRM_SECONDS, function()
				if armedAt and os.clock() - armedAt >= CONFIRM_SECONDS and button.Parent then
					armedAt = nil
					button.Text = idle
				end
			end)
			return
		end
		armedAt = nil
		button.Text = "Selling..."
		task.spawn(function()
			local result = sell(uid)
			if not (type(result) == "table" and result.ok) and button.Parent then
				button.Text = idle -- refused (e.g. it was just locked): nothing was sold
			end
		end)
	end)
end

return MascotInfo
