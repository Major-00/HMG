--!strict
-- server entry point: creates all remotes, then loads every module in Services,
-- calls Init() on all, then Start() on all.
-- Init sets up state with no cross-module calls; Start may use other modules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ReplicatedStorage.Animations holds the batter's KeyframeSequences for previewing in Studio
-- (SwingAnimator). Live servers play the published ids instead, so clients never download it.
if not RunService:IsStudio() then
	local previews = ReplicatedStorage:FindFirstChild("Animations")
	if previews then
		previews:Destroy()
	end
end

require(ReplicatedStorage.Shared.Remotes).CreateAll()

local modules = {}
for _, child in script.Services:GetChildren() do
	if child:IsA("ModuleScript") then
		table.insert(modules, (require :: any)(child))
	end
end

for _, m in modules do
	if m.Init then
		m.Init()
	end
end

for _, m in modules do
	if m.Start then
		task.spawn(m.Start)
	end
end
