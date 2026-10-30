--!strict
-- Types: the player save shape. Bump DATA_VERSION and add a migration when it changes.

export type PetEntry = {
	id: string, -- key into Config/Pets
	equipped: boolean,
}

export type PlayerData = {
	version: number,

	-- Reset on rebirth
	power: number,
	wins: number,
	bats: {
		owned: { [string]: boolean },
		equipped: string,
	},
	highestBiome: number, -- furthest biome index reached this run

	-- Kept through rebirth
	pets: { [string]: PetEntry }, -- key = unique pet id
	nextPetUid: number,
	pitcher: string, -- active Pitcher id ("pitching_machine"); a pitcher pet later
	rebirths: number,
	worldsUnlocked: number, -- 1 = World 1 only
	currentWorld: number,

	-- Lifetime stats (never reset)
	lifetime: {
		swings: number,
		winsEarned: number,
		bestDistance: number,
		eggsHatched: number,
	},

	firstJoin: number, -- os.time()
	lastJoin: number,
}

return {}
