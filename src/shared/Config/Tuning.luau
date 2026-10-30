--!strict
-- Tuning: global knobs. Balance numbers for gameplay are added here as features land.

local Tuning = {
	-- Data
	AUTOSAVE_SECONDS = 120, -- how often each save is written while playing (ProfileStore default is 300)
	DATA_LOAD_TIMEOUT = 30, -- seconds GetData waits for a save to load before giving up
	-- Seconds before a player whose save won't load is kicked. Keep above ~45s: ProfileStore
	-- waits that long to take a save over from a server that crashed.
	DATA_LOAD_KICK_SECONDS = 60,
}

return Tuning
