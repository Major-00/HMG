--!strict
-- Starts the stud textures downloading the moment the client boots, while Roblox's own loading
-- screen is still up, so the map doesn't paint its studs in from blurry to sharp as you look around.
--
-- These are the maps of the two MaterialVariants in MaterialService (LobStudsRaised, LobStudsSunk).
-- If they change there, change them here. Once the game has loaded, MaterialService itself is
-- preloaded too, so a changed ID still loads early, just not quite as early.

local ContentProvider = game:GetService("ContentProvider")

local STUD_TEXTURES = {
	"rbxassetid://77403595683989", -- raised, colour
	"rbxassetid://129646140521921", -- raised, normal
	"rbxassetid://72379681101881", -- sunk, colour
	"rbxassetid://87905202063084", -- sunk, normal
}

task.spawn(function()
	pcall(ContentProvider.PreloadAsync, ContentProvider, STUD_TEXTURES)
end)

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local MaterialService = game:GetService("MaterialService")
pcall(ContentProvider.PreloadAsync, ContentProvider, MaterialService:GetChildren())
