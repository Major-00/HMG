--!strict
-- PitcherController: for "throw" pitchers (the pitching machine, not the default), receives each
-- Pitch, plays the pitcher's throw, and keeps the pitch in play so a tap can be sent for it. One
-- swing per pitch: TakePending clears it. Fungo (the default) sends no Pitch: FungoController.
--   PitcherController.TakePending() -> the pitch in play (and clears it), or nil if there is none
--   PitcherController.GetLane()     -> this player's lane model, or nil

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HookTypes = require(Shared:WaitForChild("HookTypes"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BallController = require(script.Parent.BallController)

local MACHINE = "pitching_machine"

local player = Players.LocalPlayer
local visuals = script.Parent.Parent:WaitForChild("PitcherVisuals")

local PitcherController = {}

local pending: HookTypes.Pitch? = nil

function PitcherController.GetLane(): Model?
	local lane = player:GetAttribute("Lane")
	local areas = workspace:FindFirstChild("BattingAreas")
	if lane == nil or areas == nil then
		return nil
	end
	return areas:FindFirstChild(`Lane{lane}`) :: Model?
end

function PitcherController.TakePending(): HookTypes.Pitch?
	local pitch = pending
	if pitch == nil or workspace:GetServerTimeNow() > pitch.expiresAt then
		return nil
	end
	pending = nil
	return pitch
end

local function onPitch(pitch: HookTypes.Pitch)
	pending = pitch
	local lane = PitcherController.GetLane()
	if lane == nil then
		return -- lane not replicated yet; the next pitch will draw
	end

	-- Show the pitching machine only while it's the active pitcher.
	local machine = lane:FindFirstChild("PitchingMachine")
	if machine then
		local hidden = pitch.pitcherId ~= MACHINE
		for _, part in machine:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end

	local visual = visuals:FindFirstChild(pitch.pitcherId)
	if visual and visual:IsA("ModuleScript") then
		(require :: any)(visual).Throw(lane)
	end

	local release = lane:FindFirstChild("ReleasePoint", true) :: Attachment?
	local strike = lane:FindFirstChild("StrikePoint", true) :: Attachment?
	if release and strike then
		BallController.ShowPitch(pitch, release.WorldPosition, strike.WorldPosition)
	end
end

function PitcherController.Start()
	Remotes.Event("Pitch").OnClientEvent:Connect(onPitch)
end

return PitcherController
