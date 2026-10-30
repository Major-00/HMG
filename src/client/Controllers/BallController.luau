--!strict
-- BallController: draws balls. Cosmetic only; no stat math.
--   ShowPitch(pitch, from, to) -> ball travels from the pitcher to the strike point (and past it on a miss)
--   Contact(pitchId)           -> on tap, holds the ball at the strike point until the server answers
--   HitResult (remote)         -> flies the ball along each flight segment in an arc with a short trail;
--                                 the end of the final descent plays in slow motion for the ball-cam
-- Events for the camera and highlights:
--   BallController.Launched      -> Signal (hitId, info) when a hit's flight starts;
--                                   info = { distance, landing: Vector3, airTime }
--   BallController.Touchdown     -> Signal (hitId, segmentIndex, position, distance, isFinal) at each landing
--   BallController.GetBallPosition(hitId)    -> where that hit's ball is now, or nil once it's gone
--   BallController.WatchDistance(hitId, d, fn) -> calls fn once the ball passes `d` studs down the
--                                   track; returns false if that hit has no flight (fn not called)
-- Balls are pooled and capped (Tuning.Flight.MAX_BALLS) to stay cheap on low-end phones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared:WaitForChild("Formulas"))
local HookTypes = require(Shared:WaitForChild("HookTypes"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
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

-- startT/endT are in flight time (0..airTime, before slow motion); see flightTime().
type Leg = {
	startPos: Vector3,
	endPos: Vector3,
	height: number,
	startT: number,
	endT: number,
	fromDist: number,
	toDist: number,
}

type Watch = { distance: number, fn: () -> () }

type Flight = {
	hitId: number,
	ball: Ball,
	startedAt: number,
	airTime: number, -- flight time without slow motion
	landAt: number, -- os.clock() of the final landing (slow motion included)
	legs: { Leg },
	touched: number, -- legs whose landing has fired Touchdown
	watches: { Watch },
}

local BallController = {}

BallController.Launched = Signal.new()
BallController.Touchdown = Signal.new()

local folder: Folder
local pool: { Ball } = {}
local pitches: { [number]: PitchBall } = {}
local flights: { Flight } = {}
local liveCount = 0
local lastStrike: Vector3? = nil -- strike point of the latest pitch, for hits whose ball was dropped

-- Defined below; acquire() needs them to finish a flight it drops.
local checkWatches: (flight: Flight, along: number, final: boolean) -> ()
local checkTouchdowns: (flight: Flight, t: number) -> ()

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
		-- Still owe its landing to listeners (camera, highlights).
		checkTouchdowns(oldest, math.huge)
		checkWatches(oldest, math.huge, true)
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

-- Flight time for `elapsed` real seconds: normal speed, then the last SLOWMO_PORTION of the
-- flight at SLOWMO_SPEED. Matches Formulas.slowedAirTime, which the server uses for pacing.
local function flightTime(flight: Flight, elapsed: number): number
	local c = Tuning.Camera
	local knee = flight.airTime * (1 - c.SLOWMO_PORTION)
	local t = if elapsed <= knee then elapsed else knee + (elapsed - knee) * c.SLOWMO_SPEED
	return math.min(t, flight.airTime)
end

local function findFlight(hitId: number): Flight?
	for _, flight in flights do
		if flight.hitId == hitId then
			return flight
		end
	end
	return nil
end

local function launch(entry: PitchBall?, result: any)
	local strike = if entry then entry.to else lastStrike
	if strike == nil or type(result.segments) ~= "table" or #result.segments == 0 then
		if entry then
			release(entry.ball)
		end
		return
	end
	local ball = if entry then entry.ball else acquire()
	if ball == nil then
		return
	end
	local ground = strike - Vector3.new(0, Tuning.World.STRIKE_HEIGHT - GROUND_OFFSET, 0)
	local f = Tuning.Flight

	local total = result.distance
	local airTime = Formulas.airTime(total)
	local legs: { Leg } = {}
	local t = 0
	for i, segment in result.segments do
		local length = math.max(segment.to - segment.from, 0)
		local legTime = if total > 0 then airTime * length / total else airTime
		table.insert(legs, {
			startPos = if i == 1 then strike else ground + FIELD_DIRECTION * segment.from,
			endPos = ground + FIELD_DIRECTION * segment.to,
			height = math.min(length * f.ARC_HEIGHT_RATIO, f.MAX_ARC_HEIGHT),
			startT = t,
			endT = t + legTime,
			fromDist = segment.from,
			toDist = segment.to,
		})
		t += legTime
	end

	local now = os.clock()
	local flight: Flight = {
		hitId = result.hitId,
		ball = ball,
		startedAt = now,
		airTime = airTime,
		landAt = now + Formulas.slowedAirTime(total),
		legs = legs,
		touched = 0,
		watches = {},
	}
	ball.trail.Enabled = true
	table.insert(flights, flight)
	BallController.Launched:Fire(result.hitId, {
		distance = total,
		landing = legs[#legs].endPos,
		airTime = flight.landAt - now,
	})
end

function BallController.GetBallPosition(hitId: number): Vector3?
	local flight = findFlight(hitId)
	return if flight then flight.ball.part.Position else nil
end

function BallController.WatchDistance(hitId: number, distance: number, fn: () -> ()): boolean
	local flight = findFlight(hitId)
	if flight == nil then
		return false
	end
	table.insert(flight.watches, { distance = distance, fn = fn })
	return true
end

-- Fires watches the ball has passed. `final` fires every remaining one (the ball has landed).
checkWatches = function(flight: Flight, along: number, final: boolean)
	if #flight.watches == 0 then
		return
	end
	local due = {}
	local i = 1
	while i <= #flight.watches do
		local watch = flight.watches[i]
		if final or along >= watch.distance then
			table.remove(flight.watches, i)
			table.insert(due, watch)
		else
			i += 1
		end
	end
	-- Nearest first, so banners for several biomes in one hit show in flight order.
	table.sort(due, function(a, b)
		return a.distance < b.distance
	end)
	for _, watch in due do
		task.spawn(watch.fn)
	end
end

-- Fires Touchdown for every leg that has ended by flight time `t`.
checkTouchdowns = function(flight: Flight, t: number)
	while flight.touched < #flight.legs and t >= flight.legs[flight.touched + 1].endT do
		flight.touched += 1
		local leg = flight.legs[flight.touched]
		BallController.Touchdown:Fire(
			flight.hitId,
			flight.touched,
			leg.endPos,
			leg.toDist,
			flight.touched == #flight.legs
		)
	end
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
			checkTouchdowns(flight, math.huge)
			checkWatches(flight, math.huge, true)
			flight.ball.trail.Enabled = false
			flight.ball.part.Position = flight.legs[#flight.legs].endPos
		else
			local t = flightTime(flight, now - flight.startedAt)
			for _, leg in flight.legs do
				if t <= leg.endT then
					local a = math.clamp((t - leg.startT) / math.max(leg.endT - leg.startT, 0.001), 0, 1)
					local arc = 4 * leg.height * a * (1 - a)
					flight.ball.part.Position = leg.startPos:Lerp(leg.endPos, a) + Vector3.new(0, arc, 0)
					checkWatches(flight, leg.fromDist + (leg.toDist - leg.fromDist) * a, false)
					break
				end
			end
			checkTouchdowns(flight, t)
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
	-- Just before the camera, so the ball-cam always reads this frame's ball position.
	RunService:BindToRenderStep("BallStep", Enum.RenderPriority.Camera.Value - 1, step)
end

return BallController
