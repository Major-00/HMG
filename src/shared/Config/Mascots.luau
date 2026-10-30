--!strict
-- Mascots: every species, keyed by world and then by biome id (matching Config/Biomes).
-- Rarity is fixed per species. Each biome has SLOTS_PER_BIOME cards in the Index; at launch 6
-- are filled (one per rarity) and the rest show as "coming soon".
-- How much a Mascot earns comes from its rarity and biome (Tuning.Catch), times its variant and
-- size. Names and colors are original placeholders; final models come later.

export type Rarity = {
	id: string,
	displayName: string,
	color: Color3, -- toast, card and rig color hint
}

export type Species = {
	id: string, -- unique across all worlds; saved in each Mascot
	displayName: string,
	rarity: string, -- a Rarity id
	color: Color3, -- placeholder body color
	-- Filled in below from where the species is listed:
	world: number,
	biomeId: string,
	biomeIndex: number, -- position of the biome in Config/Biomes[world]
}

local rgb = Color3.fromRGB

local Mascots = {}

Mascots.SLOTS_PER_BIOME = 8

-- Rarest last. The order matters: Luck boosts each rarity by its position (Tuning.Catch).
Mascots.Rarities = {
	{ id = "common", displayName = "Common", color = rgb(190, 190, 190) },
	{ id = "uncommon", displayName = "Uncommon", color = rgb(90, 200, 100) },
	{ id = "rare", displayName = "Rare", color = rgb(70, 150, 255) },
	{ id = "epic", displayName = "Epic", color = rgb(170, 90, 255) },
	{ id = "legendary", displayName = "Legendary", color = rgb(255, 180, 40) },
	{ id = "mythic", displayName = "Mythic", color = rgb(255, 70, 110) },
} :: { Rarity }

-- Rarity id -> position in Rarities (1 = Common).
Mascots.RarityRank = {} :: { [string]: number }
for i, rarity in Mascots.Rarities do
	Mascots.RarityRank[rarity.id] = i
end

local function s(id: string, displayName: string, rarity: string, color: Color3): any
	return { id = id, displayName = displayName, rarity = rarity, color = color }
end

-- Worlds[world][biomeId] = species list, Common first. Launch: one per rarity; the 2 open slots
-- per biome are for a second Common and a second Uncommon later.
Mascots.Worlds = {
	-- World 1
	{
		sandlot = {
			s("dust_bunny", "Dust Bunny", "common", rgb(205, 180, 140)),
			s("glove_gopher", "Glove Gopher", "uncommon", rgb(160, 110, 70)),
			s("sunny_hound", "Sunny Hound", "rare", rgb(240, 190, 90)),
			s("dugout_badger", "Dugout Badger", "epic", rgb(90, 90, 100)),
			s("grand_slam_lion", "Grand Slam Lion", "legendary", rgb(230, 160, 50)),
			s("sandstorm_drake", "Sandstorm Drake", "mythic", rgb(220, 120, 60)),
		},
		boardwalk = {
			s("gull_buddy", "Gull Buddy", "common", rgb(235, 235, 240)),
			s("pier_otter", "Pier Otter", "uncommon", rgb(140, 100, 70)),
			s("surf_turtle", "Surf Turtle", "rare", rgb(70, 170, 120)),
			s("ferris_fox", "Ferris Fox", "epic", rgb(240, 120, 50)),
			s("lighthouse_pelican", "Lighthouse Pelican", "legendary", rgb(250, 240, 220)),
			s("tidal_kraken", "Tidal Kraken", "mythic", rgb(60, 90, 200)),
		},
		candy_land = {
			s("gumdrop_frog", "Gumdrop Frog", "common", rgb(120, 220, 120)),
			s("lolly_lamb", "Lolly Lamb", "uncommon", rgb(255, 230, 240)),
			s("sprinkle_bee", "Sprinkle Bee", "rare", rgb(255, 210, 60)),
			s("cotton_candy_cat", "Cotton Candy Cat", "epic", rgb(200, 170, 255)),
			s("caramel_unicorn", "Caramel Unicorn", "legendary", rgb(230, 170, 90)),
			s("rock_candy_golem", "Rock Candy Golem", "mythic", rgb(120, 220, 255)),
		},
		tundra = {
			s("snow_hare", "Snow Hare", "common", rgb(245, 245, 250)),
			s("ice_seal", "Ice Seal", "uncommon", rgb(180, 200, 220)),
			s("glacier_penguin", "Glacier Penguin", "rare", rgb(90, 140, 200)),
			s("aurora_owl", "Aurora Owl", "epic", rgb(110, 230, 190)),
			s("yeti_slugger", "Yeti Slugger", "legendary", rgb(210, 225, 240)),
			s("blizzard_phoenix", "Blizzard Phoenix", "mythic", rgb(140, 200, 255)),
		},
		jungle_ruins = {
			s("leaf_frog", "Leaf Frog", "common", rgb(90, 180, 70)),
			s("totem_toucan", "Totem Toucan", "uncommon", rgb(250, 150, 40)),
			s("temple_jaguar", "Temple Jaguar", "rare", rgb(220, 170, 60)),
			s("jade_chameleon", "Jade Chameleon", "epic", rgb(60, 190, 130)),
			s("idol_gorilla", "Idol Gorilla", "legendary", rgb(90, 80, 70)),
			s("sun_serpent", "Sun Serpent", "mythic", rgb(255, 200, 40)),
		},
		canyon = {
			s("cactus_wren", "Cactus Wren", "common", rgb(170, 130, 90)),
			s("dust_coyote", "Dust Coyote", "uncommon", rgb(190, 150, 100)),
			s("canyon_eagle", "Canyon Eagle", "rare", rgb(120, 80, 50)),
			s("bison_bomber", "Bison Bomber", "epic", rgb(100, 70, 50)),
			s("thunder_ram", "Thunder Ram", "legendary", rgb(180, 170, 160)),
			s("sky_thunderbird", "Sky Thunderbird", "mythic", rgb(80, 120, 230)),
		},
	},
} :: { { [string]: { Species } } }

-- Species id -> species, with world, biomeId and biomeIndex filled in.
Mascots.ById = {} :: { [string]: Species }

local Biomes = require(script.Parent.Biomes)

for world, biomes in Mascots.Worlds do
	local biomeList = Biomes[world]
	assert(biomeList, `Config/Mascots: world {world} has no biomes in Config/Biomes`)
	for biomeId, list in biomes do
		local biomeIndex: number? = nil
		for i, biome in biomeList do
			if biome.id == biomeId then
				biomeIndex = i
			end
		end
		assert(biomeIndex, `Config/Mascots: unknown biome "{biomeId}" in world {world}`)
		assert(#list <= Mascots.SLOTS_PER_BIOME, `Config/Mascots: too many species in {biomeId}`)
		for _, species in list do
			assert(Mascots.ById[species.id] == nil, `Config/Mascots: duplicate species id "{species.id}"`)
			assert(Mascots.RarityRank[species.rarity], `Config/Mascots: unknown rarity on "{species.id}"`)
			species.world = world
			species.biomeId = biomeId
			species.biomeIndex = biomeIndex :: number
			Mascots.ById[species.id] = species
		end
	end
end

return Mascots
