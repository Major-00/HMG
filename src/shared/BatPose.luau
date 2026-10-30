--!strict
-- BatPose: where the bat sits in the batter's right hand. Shared so the server's grip (WorldService)
-- and the client's swing animation (InputController) agree. Directions are in the hand's own space:
-- +X = batter's right, +Y = up the arm, -Z = forward. Cosmetic only.

local BatPose = {}

BatPose.HANDLE_LENGTH = 1.8
BatPose.HANDLE_WIDTH = 0.3
BatPose.BARREL_LENGTH = 2.2
BatPose.BARREL_WIDTH = 0.55

BatPose.READY = Vector3.new(0.55, 1, 0.45) -- up over the right shoulder, leaning back
BatPose.CONTACT = Vector3.new(0.6, 0.05, -0.8) -- level, reaching the strike point in front
BatPose.FOLLOW = Vector3.new(-0.9, 0.35, -0.3) -- swept across to the left

-- Grip weld C0 that points the bat (a cylinder, which runs along its X axis) along `direction`,
-- with the bottom of the handle in the hand. R6 holds it at the end of the arm.
function BatPose.grip(direction: Vector3, isR6: boolean): CFrame
	local hand = if isR6 then CFrame.new(0, -0.9, 0) else CFrame.new(0, -0.1, 0)
	return hand
		* CFrame.lookAt(Vector3.zero, direction.Unit)
		* CFrame.Angles(0, math.rad(90), 0) -- local X now points along `direction`
		* CFrame.new(BatPose.HANDLE_LENGTH / 2 - 0.3, 0, 0)
end

return BatPose
