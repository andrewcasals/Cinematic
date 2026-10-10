-- Cinematic: Details! Damage Meter.
local _, ns = ...

table.insert(ns.ADDON_FRAMES, {
	key = "details", addon = "Details", label = "Details! Damage Meter", short = "Details!",
	about = "its meter windows",
	-- Each window is several frames side by side on UIParent (the bars sit
	-- in their own frame), so hovering one and using /cine add misses the rest.
	patterns = { "^DetailsBaseFrame%d+$", "^DetailsRowFrame%d+$", "^Details_SwitchButtonFrame%d+$" },
})
