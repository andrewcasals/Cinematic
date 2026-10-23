-- Cinematic: RestedXP Guides, whose guide window stands in for the game's
-- quest tracker. Its guide, its waypoint arrow, its quest item and target
-- buttons and its level splits fade with the Quest tracker row on the
-- Standard Frames page, so they come up with it as you make progress.
--
-- The guide (its mouseover fading), the arrow and the splits (their opacity
-- settings) set their own alpha: they're its own frames, so they're hooked.
local _, ns = ...
local L = ns.L

-- Advanced Frames page (no columns: it follows the Quest tracker row).
table.insert(ns.ADDON_NOTES, {
	addon = "RXPGuides", label = "RestedXP Guides",
	works = L["Follows the Quest tracker row"],
	about = L["RestedXP's guide window, waypoint arrow, quest item and target buttons and level splits fade " ..
		"with the Quest tracker row on the Standard Frames page."],
})

ns.WhenAddonLoads("RXPGuides", function()
	ns.FadeWithRow("quests", "quests",
		{ "RXPFrame", "RXPG_ARROW", "RXPItemFrame", "RXPTargetFrame", "RXPLevelSplits" }, true, true)
end)
