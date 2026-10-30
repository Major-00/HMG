--!strict
-- server entry point: creates all remotes, then loads every module in Services,
-- calls Init() on all, then Start() on all.
-- Init sets up state with no cross-module calls; Start may use other modules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
