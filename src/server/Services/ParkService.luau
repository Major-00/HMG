--!strict
-- ParkService: each player's ballpark. For now it publishes what sits in their 10 seats on their
-- lane model (WorldService.SetParkSeats), so every client can draw every park (ParkController).
-- Display only: the save stays the source of truth, and income reads the save, not this.
-- Encoding: one entry per seat, joined by ";": "species,variant,size", or "" for an empty seat.
-- Park upgrades (Bleachers, Concessions, Scoreboard, Lights, Jumbotron) come in a later step.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Services = script.Parent
local DataService = require(Services.DataService)
local WorldService = require(Services.WorldService)

local ParkService = {}

local dirty: { [Player]: boolean } = {}

local function encode(data: any): string
	local seats = {}
	for i, uid in data.seats do
		local mascot = if uid then data.mascots[uid] else nil
		seats[i] = if mascot then `{mascot.species},{mascot.variant},{mascot.size}` else ""
	end
	return table.concat(seats, ";")
end

local function publish(player: Player)
	local data = DataService.Get(player)
	if data then
		WorldService.SetParkSeats(player, encode(data))
	end
end

function ParkService.Start()
	DataService.Loaded:Connect(publish)
	-- A catch or an action changes several keys at once: publish once per frame.
	DataService.Changed:Connect(function(player: Player, key: string)
		if key == "seats" or key == "mascots" then
			dirty[player] = true
		end
	end)
	RunService.Heartbeat:Connect(function()
		for player in dirty do
			dirty[player] = nil
			if player.Parent == Players then
				publish(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			publish(player)
		end
	end
end

return ParkService
