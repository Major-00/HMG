--!strict
-- ParkProps: the placeholder model for each park upgrade, growing with its level (1-10).
-- Built on the ground at `base` (a CFrame on the plot facing the field, +Z), from a handful of
-- anchored parts that can't collide, be queried or be touched. Visual only.
-- Final art replaces this later; callers only use Build.
--   ParkProps.Build(upgradeId, level, base) -> Model? (nil for level 0 or an unknown id)

local ParkProps = {}

local rgb = Color3.fromRGB

local function part(model: Model, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- `base` faces the field (+Z): its LookVector points at home plate, so "back" is -LookVector.
local builders: { [string]: (model: Model, level: number, base: CFrame) -> () } = {
	-- Rows of benches, stepping up and back: one more row every few levels.
	bleachers = function(model, level, base)
		local rows = 1 + math.floor(level / 3)
		local width = 5 + level * 0.2
		for row = 0, rows - 1 do
			local height = 0.6 + row * 0.9
			part(
				model,
				Vector3.new(width, height, 1.3),
				base * CFrame.new(0, height / 2, row * 1.3),
				if row % 2 == 0 then rgb(70, 110, 200) else rgb(60, 90, 170)
			)
		end
	end,
	-- A snack stand with a striped awning; bigger with each level, a sign from level 5.
	concessions = function(model, level, base)
		local s = 0.8 + level * 0.06
		part(model, Vector3.new(4, 2.6, 2.6) * s, base * CFrame.new(0, 1.3 * s, 0), rgb(240, 230, 210))
		part(model, Vector3.new(4.6, 0.3, 1.6) * s, base * CFrame.new(0, 2.8 * s, -1.4 * s), rgb(220, 60, 60))
		part(
			model,
			Vector3.new(4.6, 0.32, 0.5) * s,
			base * CFrame.new(0, 2.81 * s, -1.4 * s),
			rgb(250, 250, 250)
		)
		if level >= 5 then
			part(
				model,
				Vector3.new(3, 0.9, 0.3) * s,
				base * CFrame.new(0, 3.6 * s, 0),
				rgb(255, 200, 60),
				Enum.Material.Neon
			)
		end
	end,
	-- A board on two posts; taller and wider with each level.
	scoreboard = function(model, level, base)
		local postHeight = 4 + level * 0.6
		local width = 4 + level * 0.3
		local height = 2.5 + level * 0.15
		for _, x in { -width / 2 + 0.4, width / 2 - 0.4 } do
			part(
				model,
				Vector3.new(0.4, postHeight, 0.4),
				base * CFrame.new(x, postHeight / 2, 0),
				rgb(90, 90, 100)
			)
		end
		part(
			model,
			Vector3.new(width, height, 0.5),
			base * CFrame.new(0, postHeight + height / 2, 0),
			rgb(25, 40, 30)
		)
		part(
			model,
			Vector3.new(width - 0.6, 0.25, 0.1),
			base * CFrame.new(0, postHeight + height * 0.7, -0.3),
			rgb(255, 210, 80),
			Enum.Material.Neon
		)
	end,
	-- A light tower; taller each level, a second tower from level 6.
	lights = function(model, level, base)
		local function tower(x: number)
			local height = 6 + level * 1.2
			local lamp = 1.4 + level * 0.1
			part(
				model,
				Vector3.new(0.5, height, 0.5),
				base * CFrame.new(x, height / 2, 0),
				rgb(150, 150, 160)
			)
			part(
				model,
				Vector3.new(lamp * 1.6, lamp, 0.4),
				base * CFrame.new(x, height + lamp / 2, -0.2),
				rgb(255, 250, 220),
				Enum.Material.Neon
			)
		end
		tower(0)
		if level >= 6 then
			tower(-2.5)
		end
	end,
	-- A big screen high on legs (above the owner sign); bigger each level.
	jumbotron = function(model, level, base)
		local legs = 12 + level * 0.3
		local width = 5 + level * 0.5
		local height = 3.5 + level * 0.3
		for _, x in { -width / 3, width / 3 } do
			part(model, Vector3.new(0.5, legs, 0.5), base * CFrame.new(x, legs / 2, 0), rgb(70, 70, 80))
		end
		part(
			model,
			Vector3.new(width + 0.6, height + 0.6, 0.6),
			base * CFrame.new(0, legs + height / 2, 0),
			rgb(30, 30, 36)
		)
		part(
			model,
			Vector3.new(width, height, 0.1),
			base * CFrame.new(0, legs + height / 2, -0.35),
			rgb(60, 140, 255),
			Enum.Material.Neon
		)
	end,
}

function ParkProps.Build(upgradeId: string, level: number, base: CFrame): Model?
	local build = builders[upgradeId]
	if build == nil or level <= 0 then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = `{upgradeId}{level}`
	build(model, level, base)
	return model
end

return ParkProps
