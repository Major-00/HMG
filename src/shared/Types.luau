--!strict
-- Types: the player save shape. When it changes, bump Migrations.CURRENT_VERSION,
-- add a migration step, and update server/Data/Template.

export type PlayerData = {
	version: number,

	power: number,
	highestBiome: number, -- furthest biome index reached
	pitcher: string, -- active Pitcher id ("fungo"; server/Pitchers)

	-- Player preferences
	settings: {
		music: boolean,
		sfx: boolean,
		lowGraphics: boolean,
	},

	-- Lifetime stats (never reset)
	lifetime: {
		swings: number,
		bestDistance: number,
	},

	firstJoin: number, -- os.time()
	lastJoin: number,
	lastOnline: number, -- os.time() at the last save or leave
}

return {}
