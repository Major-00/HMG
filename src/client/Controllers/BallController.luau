--!strict
-- BallController: draws balls. Cosmetic only; no stat math.
--   ShowPitch(pitch, from, to) -> ball travels from the pitcher to the strike point (and past it on a miss)
--   Contact(pitchId)           -> on tap, holds the ball at the strike point until the server answers
--   HitResult (remote)         -> flies the ball along each flight segment in an arc with a short trail
-- Balls are pooled and capped (Tuning.Flight.MAX_BALLS) to stay cheap on low-end phones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HookTypes = require(Shared:WaitForChild("HookTypes"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

local FIELD_DIRECTION = Vector3.zAxis -- lanes fire down +Z (see WorldService)
local BALL_SIZE = 0.9
local GROUND_OFFSET = BALL_SIZE / 2

type Ball = { part: BasePart, trail: Trail }

type PitchBall = {
	ball: Ball,
	pitch: HookTypes.Pitch,
	from: Vector3,
	to: Vector3,
	contactUntil: number?, -- set on tap: hold at the strike point until this os.clock()
}

type Leg = { startPos: Vector3, endPos: Vector3, height: number, startT: number, endT: number }

type Flight = {
	ball: Ball,
	startedAt: number,
	landAt: number,
	legs: { Leg },
}

local BallController = {}

local folder: Folder
local pool: { Ball } = {}
local pitches: { [number]: PitchBall } = {}
local flights: { Flight } = {}
local liveCount = 0
local lastStrike: Vector3? = nil -- strike point of the latest pitch, for hits whose ball was dropped

local function newBall(): Ball
	local part = Instance.new("Part")
	part.Name = "Ball"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE)
	part.Color = Color3.fromRGB(250, 250, 245)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false

	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 0.3, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -0.3, 0)
	bottom.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = Tuning.Flight.TRAIL_LIFETIME
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Enabled = false
	trail.Parent = part

	return { part = part, trail = trail }
end

local function release(ball: Ball)
	ball.trail.Enabled = false
	ball.trail:Clear()
	ball.part.Parent = nil
	liveCount -= 1
	table.insert(pool, ball)
end

local function acquire(): Ball?
	if liveCount >= Tuning.Flight.MAX_BALLS then
		-- Make room by dropping the oldest flight.
		local oldest = table.remove(flights, 1)
		if oldest == nil then
			return nil
		end
		release(oldest.ball)
	end
	liveCount += 1
	local ball = table.remove(pool) or newBall()
	ball.part.Parent = folder
	return ball
end

function BallController.ShowPitch(pitch: HookTypes.Pitch, from: Vector3, to: Vector3)
	local ball = acquire()
	if ball == nil then
		return
	end
	ball.part.Position = from
	lastStrike = to
	pitches[pitch.pitchId] = { ball = ball, pitch = pitch, from = from, to = to }
end

function BallController.Contact(pitchId: number)
	local entry = pitches[pitchId]
	if entry then
		entry.contactUntil = os.clock() + Tuning.Flight.CONTACT_TIMEOUT
		entry.ball.part.Position = entry.to
	end
end

local function launch(entry: PitchBall?, result: any)
	local strike = if entry then entry.to else lastStrike
	if strike == nil then
		return
	end
	local ball = if entry then entry.ball else acquire()
	if ball == nil then
		return
	end
	local ground = strike - Vector3.new(0, Tuning.World.STRIKE_HEIGHT - GROUND_OFFSET, 0)
	local f = Tuning.Flight

	local total = result.distance
	local duration = math.clamp(f.MIN_TIME + total * f.SECONDS_PER_STUD, f.MIN_TIME, f.MAX_TIME)
	local now = os.clock()
	local legs: { Leg } = {}
	local t = now
	for i, segment in result.segments do
		local length = math.max(segment.to - segment.from, 0)
		local legTime = if total > 0 then duration * length / total else duration
		table.insert(legs, {
			startPos = if i == 1 then strike else ground + FIELD_DIRECTION * segment.from,
			endPos = ground + FIELD_DIRECTION * segment.to,
			height = math.min(length * f.ARC_HEIGHT_RATIO, f.MAX_ARC_HEIGHT),
			startT = t,
			endT = t + legTime,
		})
		t += legTime
	end

	ball.trail.Enabled = true
	table.insert(flights, { ball = ball, startedAt = now, landAt = t, legs = legs })
end

local function onHitResult(result: any)
	local entry = pitches[result.hitId]
	pitches[result.hitId] = nil
	launch(entry, result)
end

local function step()
	local serverNow = workspace:GetServerTimeNow()
	local now = os.clock()

	for id, entry in pitches do
		if entry.contactUntil then
			if now > entry.contactUntil then
				-- The server never confirmed the hit (too late or rejected).
				pitches[id] = nil
				release(entry.ball)
			end
		elseif serverNow > entry.pitch.expiresAt then
			pitches[id] = nil -- missed, gone
			release(entry.ball)
		else
			local p = entry.pitch
			local alpha = (serverNow - p.releaseAt) / math.max(p.arriveAt - p.releaseAt, 0.01)
			-- Past alpha 1 the ball keeps going behind the plate.
			entry.ball.part.Position = entry.from:Lerp(entry.to, math.max(alpha, 0))
		end
	end

	for i = #flights, 1, -1 do
		local flight = flights[i]
		if now >= flight.landAt + Tuning.Flight.LINGER_TIME then
			table.remove(flights, i)
			release(flight.ball)
		elseif now >= flight.landAt then
			flight.ball.trail.Enabled = false
			flight.ball.part.Position = flight.legs[#flight.legs].endPos
		else
			for _, leg in flight.legs do
				if now <= leg.endT then
					local a = math.clamp((now - leg.startT) / math.max(leg.endT - leg.startT, 0.001), 0, 1)
					local arc = 4 * leg.height * a * (1 - a)
					flight.ball.part.Position = leg.startPos:Lerp(leg.endPos, a) + Vector3.new(0, arc, 0)
					break
				end
			end
		end
	end
end

function BallController.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientBalls"
	folder.Parent = workspace
end

function BallController.Start()
	Remotes.Event("HitResult").OnClientEvent:Connect(onHitResult)
	RunService.RenderStepped:Connect(step)
end

return BallController
