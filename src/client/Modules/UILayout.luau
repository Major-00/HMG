--!strict
-- UILayout: screen space shared by several controllers, so they never overlap on a phone.
--   Bottom-left: the hotbar bar (HotbarController), BOTTOM_BAR points tall incl. its margin,
--     with the "Mascots" and "Shop" buttons just above it.
--   Bottom-right: the SWING button (HudController), 140 points plus a 24-point margin.
--   Left side: one panel at a time (Mascots or Shop), from the top margin down to the buttons.
--   Toasts and reveal text sit centered, above BOTTOM_BAR.
--   UILayout.PanelChanged -> Signal (name or nil): a side panel opened (others close) or closed

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))

local UILayout = {}

UILayout.MARGIN = 12
UILayout.SLOT = 60 -- hotbar slot size: a comfortable touch target
UILayout.BAR_LABEL = 16 -- the "HOTBAR" / "ON DECK" labels above the slots
UILayout.BOTTOM_BAR = UILayout.SLOT + UILayout.BAR_LABEL + UILayout.MARGIN
UILayout.PANEL_BUTTON = Vector2.new(120, 40) -- "Mascots", "Shop"

UILayout.PanelChanged = Signal.new()

return UILayout
