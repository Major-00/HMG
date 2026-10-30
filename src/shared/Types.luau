--!strict
-- Types: the player save shape. When it changes, bump Migrations.CURRENT_VERSION,
-- add a migration step, and update server/Data/Template.

-- One caught Mascot. Where it sits is stored in seats / hotbar / onDeck, by uid.
export type MascotEntry = {
	species: string, -- key into Config/Mascots
	variant: string, -- "none" | "allStar" | "goldGlove" | "hallOfFame"
	size: string, -- "normal" | "big" | "giant"
	locked: boolean, -- never auto-sold, never chosen as weakest
}

-- A seat, hotbar slot or On Deck: a Mascot uid, or false when empty.
export type Slot = string | false

-- One species card in the Index. Kept even after every Mascot of that species is sold.
export type IndexEntry = {
	count: number, -- total caught
	variants: { [string]: boolean }, -- variants seen
	sizes: { [string]: boolean }, -- sizes seen
}

export type PlayerData = {
	version: number,

	-- Run progress: reset on stadium promotion
	power: number,
	cash: number,
	bats: {
		owned: { [string]: boolean },
		equipped: string,
	},
	balls: {
		owned: { [string]: boolean }, -- every hit uses the best ball owned
	},
	park: { [string]: number }, -- upgrade id -> level (0 = not bought)
	highestBiome: number, -- furthest biome index reached this run

	-- Kept forever (Safe at home)
	mascots: { [string]: MascotEntry }, -- key = unique Mascot uid
	nextMascotUid: number,
	seats: { Slot }, -- 10; only seated Mascots earn Cash
	hotbar: { Slot }, -- 4; doesn't earn
	onDeck: Slot, -- 1; overflow when Auto-Sell is off or the hotbar is all locked
	autoSell: boolean,
	index: { [string]: IndexEntry }, -- key = species id
	stadiumTier: number, -- 1 = Sandlot Field; tier N plays World N
	pitcher: string, -- active Pitcher id ("pitching_machine")

	-- Player preferences
	settings: {
		music: boolean,
		sfx: boolean,
		lowGraphics: boolean,
		tipsSeen: { [string]: boolean }, -- one-time tutorial tips already shown
	},

	-- Lifetime stats (never reset)
	lifetime: {
		swings: number,
		cashEarned: number,
		mascotsCaught: number,
		bestDistance: number,
	},

	firstJoin: number, -- os.time()
	lastJoin: number,
	lastOnline: number, -- os.time() at the last save or leave; drives offline earnings
}

return {}
