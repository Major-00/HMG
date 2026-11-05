--!strict
-- Migrations: upgrade older saves one version at a time.
-- To change the save shape: bump CURRENT_VERSION, then add Steps[old] that turns a
-- version-`old` save into version old + 1. New keys with simple defaults don't need a
-- step; the Template fills them in.

local Migrations = {}

Migrations.CURRENT_VERSION = 4

-- Steps[n] upgrades a version-n save to version n + 1, editing it in place.
local Steps: { [number]: (data: any) -> () } = {
	-- v1 -> v2 (history): this project started as another game, HomeRun Mascots, and v2 was
	-- that game's save. There were no live players, only test saves, so v1 saves are wiped and
	-- the Template refills them on load. ProfileStore's Reconcile only adds missing keys and
	-- never removes old ones, so the wipe has to be explicit. Run bumps the version after this
	-- step.
	[1] = function(data)
		table.clear(data)
		data.version = 1
	end,
	-- v2 -> v3: Fungo hitting replaces the pitching machine as everyone's pitcher. The machine
	-- is still a pitcher, so saves that had it as the default move to Fungo.
	[2] = function(data)
		if data.pitcher == "pitching_machine" then
			data.pitcher = "fungo"
		end
	end,
	-- v3 -> v4: Lob an Orb! keeps only the hit: the old game's Cash, bats, balls, park, Mascots,
	-- Index, stadium tiers and their settings are removed. Reconcile never removes keys, so
	-- they go here. Only test saves exist.
	[3] = function(data)
		local oldKeys = {
			"cash",
			"bats",
			"balls",
			"park",
			"mascots",
			"nextMascotUid",
			"seats",
			"hotbar",
			"onDeck",
			"autoSell",
			"index",
			"stadiumTier",
		}
		for _, key in oldKeys do
			data[key] = nil
		end
		if type(data.settings) == "table" then
			data.settings.tipsSeen = nil
			data.settings.indexSeen = nil
		end
		if type(data.lifetime) == "table" then
			data.lifetime.cashEarned = nil
			data.lifetime.mascotsCaught = nil
		end
		data.highestBiome = 1 -- the biomes changed
	end,
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Upgrades `data` in place. Works on a copy first, so a failed or erroring step never
-- leaves a half-migrated save. Returns ok, reason ("newer" | message) on failure.
function Migrations.Run(data: any): (boolean, string?)
	local version = data.version
	if type(version) ~= "number" then
		return false, "save has no version number"
	end
	if version > Migrations.CURRENT_VERSION then
		return false, "newer"
	end
	if version == Migrations.CURRENT_VERSION then
		return true
	end

	local working = deepCopy(data)
	while working.version < Migrations.CURRENT_VERSION do
		local step = Steps[working.version]
		if not step then
			return false, `no migration step from version {working.version}`
		end
		local ok, err = pcall(step, working)
		if not ok then
			return false, `migration from version {working.version} failed: {err}`
		end
		working.version += 1
	end

	-- Success: replace the save's contents with the migrated copy.
	table.clear(data)
	for k, v in working do
		data[k] = v
	end
	return true
end

return Migrations
