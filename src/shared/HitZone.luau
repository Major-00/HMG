--!strict
-- HitZone: the shared hitting zone, one dirt strip across every lane between the ballparks and
-- the hit line (Tuning.World.HIT_ZONE). Players walk anywhere and tap; the ball always starts
-- inside the zone and flies straight down the field (+Z) from the batter's X. Distances are
-- measured from the hit line, so biome crossings match the server, which never reads position.
--   HitZone.halfWidth()      -> studs from the field's centre line to the zone's side edge
--   HitZone.contains(pos)    -> true if pos (X, Z) is inside the zone
--   HitZone.clamp(pos)       -> the nearest point inside the zone (Y kept)
--   HitZone.lineOrigin(x)    -> where the ball's flight line starts for a hit at X = x

local Tuning = require(script.Parent:WaitForChild("Config"):WaitForChild("Tuning"))

local HitZone = {}

function HitZone.halfWidth(): number
	local w = Tuning.World
	return w.LANE_COUNT * w.LANE_SPACING / 2
end

function HitZone.contains(pos: Vector3): boolean
	local z = Tuning.World.HIT_ZONE
	return math.abs(pos.X) <= HitZone.halfWidth() and pos.Z >= z.back and pos.Z <= z.front
end

function HitZone.clamp(pos: Vector3): Vector3
	local z = Tuning.World.HIT_ZONE
	local half = HitZone.halfWidth()
	return Vector3.new(math.clamp(pos.X, -half, half), pos.Y, math.clamp(pos.Z, z.back, z.front))
end

function HitZone.lineOrigin(x: number): Vector3
	local half = HitZone.halfWidth()
	return Vector3.new(math.clamp(x, -half, half), Tuning.World.STRIKE_HEIGHT, Tuning.World.HIT_ZONE.front)
end

return HitZone
