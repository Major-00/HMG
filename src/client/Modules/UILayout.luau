--!strict
-- UILayout: screen space shared by several controllers, so they never overlap on a phone.
--   Bottom-left: the hotbar bar (HotbarController), BOTTOM_BAR points tall incl. its margin,
--     with the "Mascots" button just above it.
--   Bottom-right: the SWING button (HudController), 140 points plus a 24-point margin.
--   Toasts and reveal text sit centered, above BOTTOM_BAR.

local UILayout = {}

UILayout.MARGIN = 12
UILayout.SLOT = 60 -- hotbar slot size: a comfortable touch target
UILayout.BAR_LABEL = 16 -- the "HOTBAR" / "ON DECK" labels above the slots
UILayout.BOTTOM_BAR = UILayout.SLOT + UILayout.BAR_LABEL + UILayout.MARGIN

return UILayout
