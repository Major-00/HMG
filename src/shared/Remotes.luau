--!strict
-- Remotes: every client<->server message, by name. The server creates these at
-- startup under ReplicatedStorage.Remotes; the client waits for them.
-- The server validates every argument. The client never sends stat values.
-- Payload types are in HookTypes.

local Remotes = {}

-- Client -> Server (RemoteEvent)
Remotes.Events = {
	"Swing", -- (pitchId: number). Ignored if it doesn't match the pending pitch.
}

-- Client -> Server (RemoteFunction, returns { ok: boolean, err: string?, ... })
Remotes.Functions = {
	"GetData", -- () -> full snapshot of the caller's own save
	"BuyBat", -- (batId: string)
	"EquipBat", -- (batId: string)
	"HatchEgg", -- (eggId: string, count: number) -> pets rolled
	"EquipPet", -- (petUid: string)
	"UnequipPet", -- (petUid: string)
	"Rebirth", -- ()
}

-- Server -> Client (RemoteEvent)
Remotes.ServerEvents = {
	"Pitch", -- HookTypes.Pitch
	"HitResult", -- { hitId, powerGained, segments: {FlightSegment}, distance, biomeIndex, winsGained }
	"Highlight", -- HookTypes.Highlight without the player field
	"DataChanged", -- partial snapshot: only the changed top-level keys
}

return Remotes
