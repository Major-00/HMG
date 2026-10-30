--!strict
-- MascotController: the client side of the Mascot actions. It only asks the server; every rule
-- and every number is decided there (MascotService / MascotInventory). The hotbar and Mascots
-- panel (a later step) call these. Each returns the server's { ok, err?, cash?, species? }.
-- Calls run on their own thread inside the remote, so they never hold up swinging.
--   MascotController.Sell(uid)               -> shows "Sold X +$N" on success
--   MascotController.SetLock(uid, locked)
--   MascotController.Move(uid, place, slot)  -> place: "seats" | "hotbar" | "onDeck"; swaps if taken
--   MascotController.EquipBest()
--   MascotController.SetAutoSell(on)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local HighlightController = require(script.Parent.HighlightController)

local MascotController = {}

export type Result = { ok: boolean, err: string?, cash: number?, species: string? }

local function invoke(name: string, ...: any): Result
	local remote = Remotes.Function(name)
	local ok, result = pcall(remote.InvokeServer, remote, ...)
	if not ok or type(result) ~= "table" then
		return { ok = false, err = "no response" }
	end
	return result
end

function MascotController.Sell(uid: string): Result
	local result = invoke("SellMascot", uid)
	if result.ok and result.species and result.cash then
		HighlightController.ShowSold(result.species, result.cash)
	end
	return result
end

function MascotController.SetLock(uid: string, locked: boolean): Result
	return invoke("LockMascot", uid, locked)
end

function MascotController.Move(uid: string, place: string, slot: number): Result
	return invoke("MoveMascot", uid, place, slot)
end

function MascotController.EquipBest(): Result
	return invoke("EquipBest")
end

function MascotController.SetAutoSell(on: boolean): Result
	return invoke("SetAutoSell", on)
end

return MascotController
