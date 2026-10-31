--!strict
-- Remotes: every client<->server message, by name. The server creates them all at
-- startup under ReplicatedStorage.Remotes (CreateAll); the client waits for them.
-- The server validates every argument. The client never sends stat values.
-- Payload types are in HookTypes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- Client -> Server (RemoteEvent)
Remotes.Events = {
	"Swing", -- (pitchId: number). Always a hit if it matches the pitch in play; otherwise ignored.
	"Ready", -- (hitId: number). The catch reveal for that hit was skipped; the next pitch may come sooner.
}

-- Client -> Server (RemoteFunction, returns { ok: boolean, err: string?, ... })
Remotes.Functions = {
	"GetData", -- () -> full snapshot of the caller's own save, or nil if it never loaded
	"BuyBat", -- (batId: string) the next bat in order; equips it
	"EquipBat", -- (batId: string) a bat you own
	"BuyBall", -- (ballId: string) the next ball tier in order; Cash only
	"SellMascot", -- (uid: string) -> { ok, err?, cash?, species? }; refused if locked
	"LockMascot", -- (uid: string, locked: boolean)
	"MoveMascot", -- (uid: string, place: "seats" | "hotbar" | "onDeck", slot: number); swaps if taken
	"EquipBest", -- () seats the top 10 earners
	"SetAutoSell", -- (on: boolean) sells nothing by itself
	"GetWelcomeBack", -- () -> { seconds, cash } once after offline earnings were paid, else nil
}

-- Server -> Client (RemoteEvent)
Remotes.ServerEvents = {
	"Pitch", -- HookTypes.Pitch
	"HitResult", -- { hitId, powerGained, pitcherBonus, segments: {FlightSegment}, distance, biomeIndex, catch: HookTypes.Catch? }
	"Highlight", -- HookTypes.Highlight without the player field
	"DataChanged", -- { [topLevelKey]: newValue } for keys changed since the last frame
	"ShopNotice", -- { kind = "ball", id }: your Cash first covers this ball (once per tier per run)
}

local FOLDER_NAME = "Remotes"

local classByName: { [string]: string } = {}
for _, name in Remotes.Events do
	classByName[name] = "RemoteEvent"
end
for _, name in Remotes.ServerEvents do
	classByName[name] = "RemoteEvent"
end
for _, name in Remotes.Functions do
	classByName[name] = "RemoteFunction"
end

local function getFolder(): Instance
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Instance
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function get(name: string, className: string): Instance
	assert(classByName[name] == className, `Unknown {className} "{name}"`)
	local folder = getFolder()
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
		return remote :: Instance
	end
	return folder:WaitForChild(name)
end

-- Server only: create every remote up front so clients never wait on a missing one.
function Remotes.CreateAll()
	assert(RunService:IsServer(), "Remotes.CreateAll is server-only")
	for name, className in classByName do
		get(name, className)
	end
end

function Remotes.Event(name: string): RemoteEvent
	return get(name, "RemoteEvent") :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	return get(name, "RemoteFunction") :: RemoteFunction
end

return Remotes
