--!strict
-- IncomeService: seated Mascots are the only income (hits don't pay).
--   * While playing: every Tuning.Income.PAY_EVERY seconds, pays Formulas.cashRate(data) for the
--     time that passed (seated Mascots x park x stadium tier). Hotbar and On Deck don't earn.
--   * Offline: when a save loads, pays the same rate for the time since the save was last
--     written (DataService stamps lastOnline on every save), capped at 3 hours
--     (Formulas.offlineSeconds). The rate comes from the seats as saved, never from the client.
--     Credited before the player sees anything; the Welcome Back screen only shows the amount.
--   GetWelcomeBack (RemoteFunction) -> { seconds, cash } once per session, or nil.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Tuning = require(Shared.Config.Tuning)

local DataService = require(script.Parent.DataService)

local IncomeService = {}

type Welcome = { seconds: number, cash: number }

-- Offline pay done and live pay running: os.clock() up to which this player has been paid.
-- Per player, so a join never gets paid for time before it loaded.
local paidUntil: { [Player]: number } = {}
local welcome: { [Player]: Welcome } = {} -- shown once, then cleared

local function pay(player: Player, amount: number)
	if amount <= 0 or amount ~= amount or amount == math.huge then
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

local function onLoaded(player: Player)
	if paidUntil[player] then
		return
	end
	local data = DataService.Get(player)
	if data == nil then
		return
	end
	paidUntil[player] = os.clock()

	local seconds = Formulas.offlineSeconds(data.lastOnline, os.time())
	local cash = Formulas.cashRate(data) * seconds
	pay(player, cash)
	-- Count from now: a crash before the next save shouldn't pay this stretch twice.
	DataService.Update(player, "lastOnline", function()
		return os.time()
	end)
	if cash > 0 and seconds >= Tuning.Offline.MIN_WELCOME_SECONDS then
		welcome[player] = { seconds = seconds, cash = cash }
	end
end

-- Studio only (DevService): pretend the player was away `seconds` (negative = a clock in the
-- future), then run the same offline payout a real load runs. Returns the Welcome, if any.
function IncomeService.SimulateOffline(player: Player, seconds: number): Welcome?
	DataService.Update(player, "lastOnline", function()
		return os.time() - seconds
	end)
	paidUntil[player] = nil
	welcome[player] = nil
	onLoaded(player)
	return welcome[player]
end

function IncomeService.Start()
	DataService.Loaded:Connect(onLoaded)
	Players.PlayerRemoving:Connect(function(player)
		paidUntil[player] = nil
		welcome[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			onLoaded(player)
		end
	end

	Remotes.Function("GetWelcomeBack").OnServerInvoke = function(player: Player): Welcome?
		local w = welcome[player]
		welcome[player] = nil
		return w
	end

	-- Live pay: each player is paid for the measured time since they were last paid, so a slow
	-- frame or a mid-interval join never loses or doubles income.
	task.spawn(function()
		while true do
			task.wait(Tuning.Income.PAY_EVERY)
			local now = os.clock()
			for player, since in paidUntil do
				local data = DataService.Get(player)
				if data then
					paidUntil[player] = now
					pay(player, Formulas.cashRate(data) * (now - since))
				end
			end
		end
	end)
end

return IncomeService
