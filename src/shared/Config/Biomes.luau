--!strict
-- Biomes: World 1 biomes in flight order. WorldController builds each strip from this.
-- landmark = model name under ReplicatedStorage.Landmarks (assets/Landmarks/).
-- challenge = per-biome challenge slot, empty in the MVP.
-- visual = ground, side band, props and lighting. Placeholder looks; no assets.
-- Where each biome starts is in Config/Tuning (BiomeStarts).

local HookTypes = require(script.Parent.Parent.HookTypes)

local M = Enum.Material
local rgb = Color3.fromRGB
local v3 = Vector3.new

local UP = v3(0, 0, 90) -- stands a cylinder upright

-- Small helpers so props read as shapes, not numbers.
local function block(
	size: Vector3,
	y: number,
	color: Color3,
	material: Enum.Material?,
	x: number?,
	z: number?
): HookTypes.PropPiece
	return { shape = "Block", size = size, offset = v3(x or 0, y, z or 0), color = color, material = material }
end
local function ball(
	d: number,
	y: number,
	color: Color3,
	material: Enum.Material?,
	x: number?,
	z: number?
): HookTypes.PropPiece
	return {
		shape = "Ball",
		size = v3(d, d, d),
		offset = v3(x or 0, y, z or 0),
		color = color,
		material = material,
	}
end
local function pole(
	height: number,
	width: number,
	color: Color3,
	material: Enum.Material?,
	x: number?,
	z: number?
): HookTypes.PropPiece
	return {
		shape = "Cylinder",
		size = v3(height, width, width),
		offset = v3(x or 0, height / 2, z or 0),
		color = color,
		material = material,
		rot = UP,
	}
end

local Biomes: { HookTypes.BiomeConfig } = {
	{
		id = "sandlot",
		displayName = "Sandlot",
		landmark = "Sandlot",
		challenge = nil,
		visual = {
			ground = rgb(214, 178, 120),
			material = M.Sand,
			side = rgb(96, 158, 72),
			sideMaterial = M.Grass,
			accent = rgb(255, 214, 120),
			lighting = {
				clockTime = 13,
				brightness = 3,
				ambient = rgb(90, 85, 75),
				outdoorAmbient = rgb(140, 130, 110),
				atmosphereColor = rgb(214, 196, 160),
				atmosphereDecay = rgb(120, 100, 70),
				density = 0.3,
				haze = 0.5,
			},
			props = {
				{ block(v3(16, 6, 1), 3, rgb(150, 105, 60), M.WoodPlanks) }, -- fence panel
				{ pole(5, 1.2, rgb(110, 75, 45), M.Wood), ball(7, 7, rgb(70, 140, 60), M.Grass) }, -- tree
				{
					block(v3(8, 1, 3), 2, rgb(170, 130, 80), M.WoodPlanks),
					block(v3(8, 2, 1), 1, rgb(120, 90, 60)),
				}, -- bench
			},
		},
	},
	{
		id = "boardwalk",
		displayName = "Boardwalk",
		landmark = "Boardwalk",
		challenge = nil,
		visual = {
			ground = rgb(176, 128, 82),
			material = M.WoodPlanks,
			side = rgb(40, 140, 200),
			sideMaterial = M.Glass,
			accent = rgb(80, 200, 255),
			lighting = {
				clockTime = 11,
				brightness = 3.2,
				ambient = rgb(80, 95, 110),
				outdoorAmbient = rgb(130, 160, 185),
				atmosphereColor = rgb(170, 215, 240),
				atmosphereDecay = rgb(90, 140, 190),
				density = 0.32,
				haze = 1,
			},
			props = {
				{ pole(6, 0.4, rgb(240, 240, 240)), block(v3(9, 0.6, 9), 6.3, rgb(240, 80, 80)) }, -- umbrella
				{ pole(10, 1.4, rgb(120, 85, 55), M.Wood) }, -- pier post
				{
					block(v3(5, 1, 5), 6, rgb(240, 240, 240)),
					pole(5.5, 0.6, rgb(240, 240, 240), nil, -2, -2),
					pole(5.5, 0.6, rgb(240, 240, 240), nil, 2, 2),
					block(v3(5, 3, 5), 8, rgb(230, 70, 60)),
				}, -- lifeguard stand
			},
		},
	},
	{
		id = "candy_land",
		displayName = "Candy Land",
		landmark = "CandyLand",
		challenge = nil,
		visual = {
			ground = rgb(255, 170, 210),
			material = M.SmoothPlastic,
			side = rgb(120, 70, 45),
			sideMaterial = M.SmoothPlastic,
			accent = rgb(255, 120, 200),
			lighting = {
				clockTime = 14,
				brightness = 3,
				ambient = rgb(120, 90, 110),
				outdoorAmbient = rgb(200, 160, 190),
				atmosphereColor = rgb(255, 200, 230),
				atmosphereDecay = rgb(200, 120, 200),
				density = 0.33,
				haze = 1.2,
			},
			props = {
				{ pole(8, 0.5, rgb(250, 250, 250)), ball(5, 9.5, rgb(255, 80, 160)) }, -- lollipop
				{
					{
						shape = "Ball",
						size = v3(6, 4, 6),
						offset = v3(0, 1.5, 0),
						color = rgb(120, 230, 170),
					},
				}, -- gumdrop
				{ pole(9, 1.2, rgb(240, 40, 60)), ball(1.4, 9, rgb(250, 250, 250)) }, -- candy cane
			},
		},
	},
	{
		id = "tundra",
		displayName = "Tundra",
		landmark = "Tundra",
		challenge = nil,
		visual = {
			ground = rgb(235, 242, 250),
			material = M.Snow,
			side = rgb(170, 215, 240),
			sideMaterial = M.Ice,
			accent = rgb(170, 230, 255),
			lighting = {
				clockTime = 16.2,
				brightness = 2.6,
				ambient = rgb(110, 125, 150),
				outdoorAmbient = rgb(170, 190, 220),
				atmosphereColor = rgb(210, 230, 250),
				atmosphereDecay = rgb(130, 160, 210),
				density = 0.4,
				haze = 2,
			},
			props = {
				{
					pole(2, 1, rgb(90, 60, 40), M.Wood),
					block(v3(7, 3, 7), 3.5, rgb(40, 100, 70)),
					block(v3(5, 3, 5), 6.5, rgb(50, 115, 80)),
					block(v3(3, 3, 3), 9.5, rgb(235, 245, 255), M.Snow),
				}, -- snowy pine
				{ block(v3(6, 5, 6), 2.5, rgb(160, 220, 245), M.Ice) }, -- ice block
				{ ball(5, 2.5, rgb(250, 250, 255), M.Snow), ball(3.5, 6.2, rgb(250, 250, 255), M.Snow) }, -- snowman
			},
		},
	},
	{
		id = "jungle_ruins",
		displayName = "Jungle Ruins",
		landmark = "JungleRuins",
		challenge = nil,
		visual = {
			ground = rgb(78, 128, 58),
			material = M.Grass,
			side = rgb(50, 90, 45),
			sideMaterial = M.LeafyGrass,
			accent = rgb(140, 230, 90),
			lighting = {
				clockTime = 12,
				brightness = 2.4,
				ambient = rgb(70, 95, 70),
				outdoorAmbient = rgb(110, 150, 105),
				atmosphereColor = rgb(170, 200, 150),
				atmosphereDecay = rgb(70, 110, 60),
				density = 0.36,
				haze = 1.4,
			},
			props = {
				{ block(v3(3, 12, 3), 6, rgb(130, 130, 120), M.Slate) }, -- stone pillar
				{
					block(v3(2.5, 9, 2.5), 4.5, rgb(125, 125, 115), M.Slate, -4),
					block(v3(2.5, 9, 2.5), 4.5, rgb(125, 125, 115), M.Slate, 4),
					block(v3(11, 2, 3), 10, rgb(115, 115, 105), M.Slate),
				}, -- ruined arch
				{ ball(6, 2.5, rgb(40, 110, 40), M.Grass), ball(4, 2, rgb(60, 130, 50), M.Grass, 3) }, -- bush
			},
		},
	},
	{
		id = "canyon",
		displayName = "Canyon",
		landmark = "Canyon",
		challenge = nil,
		visual = {
			ground = rgb(214, 130, 80),
			material = M.Sandstone,
			side = rgb(160, 80, 50),
			sideMaterial = M.Rock,
			accent = rgb(255, 150, 70),
			lighting = {
				clockTime = 17.4,
				brightness = 2.8,
				ambient = rgb(120, 80, 60),
				outdoorAmbient = rgb(190, 130, 95),
				atmosphereColor = rgb(240, 180, 130),
				atmosphereDecay = rgb(190, 90, 50),
				density = 0.35,
				haze = 1.5,
			},
			props = {
				{ block(v3(14, 18, 12), 9, rgb(190, 95, 60), M.Sandstone) }, -- mesa
				{
					pole(7, 1.4, rgb(70, 140, 70), M.Grass),
					pole(3, 0.9, rgb(70, 140, 70), M.Grass, 1.4),
					block(v3(1.6, 0.9, 0.9), 3.5, rgb(70, 140, 70), M.Grass, 0.9),
				}, -- cactus
				{ ball(5, 2, rgb(150, 90, 65), M.Rock) }, -- boulder
			},
		},
	},
}

return Biomes
