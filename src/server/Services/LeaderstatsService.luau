--!strict
-- LeaderstatsService: shows each player's stadium tier and best distance in the player list.
-- Read-only mirror of the save; it never changes stats. Cash isn't shown because it drops
-- every time it's spent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)

local DataService = require(script.Parent.DataService)

local LeaderstatsService = {}

type Stats = { stadium: StringValue, best: IntValue }

local stats: { [Player]: Stats } = {}

local function update(player: Player)
	local s = stats[player]
	local data = DataService.Get(player)
	if s == nil or data == nil then
		return
	end
	s.stadium.Value = Formulas.stadiumTier(data).displayName
	s.best.Value = math.floor(data.lifetime.bestDistance)
end

local function setup(player: Player)
	if stats[player] ~= nil or player.Parent ~= Players then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	-- Player-list columns, in this order.
	local stadium = Instance.new("StringValue")
	stadium.Name = "Stadium"
	stadium.Parent = folder
	local best = Instance.new("IntValue")
	best.Name = "Best"
	best.Parent = folder

	stats[player] = { stadium = stadium, best = best }
	update(player)
	folder.Parent = player
end

function LeaderstatsService.Start()
	DataService.Loaded:Connect(setup)
	DataService.Changed:Connect(function(player: Player, key: string)
		if key == "stadiumTier" or key == "lifetime" then
			update(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		stats[player] = nil
	end)
	-- Saves that loaded before this service started.
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			setup(player)
		end
	end
end

return LeaderstatsService
