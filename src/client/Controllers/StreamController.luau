--!strict
-- Keeps the area where the ball is going loaded.
--
-- Every lane biome is Persistent (MaP/EXPORT_SPEC.md), so the map itself is always there. Anything
-- else streams in around the player's character (StreamingTargetRadius 1,024), but a hit can fly
-- about 2,294 studs and the camera follows it. The moment a flight starts, this asks the engine to
-- stream in the area around where it will land, so whatever is there has loaded by the time the
-- camera arrives instead of filling in on screen.
--
-- It only listens to BallController.Launched; it never changes the flight or the camera.

local Players = game:GetService("Players")

local BallController = require(script.Parent.BallController)

local StreamController = {}

local TIMEOUT = 2 -- seconds; the flight is longer than this, and the request must not pile up
local pending = false

local function streamAround(position: Vector3)
	if pending then
		return
	end
	pending = true
	task.spawn(function()
		pcall(function()
			Players.LocalPlayer:RequestStreamAroundAsync(position, TIMEOUT)
		end)
		pending = false
	end)
end

function StreamController.Start()
	if not workspace.StreamingEnabled then
		return
	end
	BallController.Launched:Connect(function(_hitId: number, info: { landing: Vector3 })
		if typeof(info) == "table" and typeof(info.landing) == "Vector3" then
			streamAround(info.landing)
		end
	end)
end

return StreamController
