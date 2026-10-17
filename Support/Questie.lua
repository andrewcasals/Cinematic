-- Cinematic: Questie, whose tracker stands in for the game's quest tracker.
-- Its tracker and its quest item buttons fade with the Quest tracker row on
-- the Standard Frames page, so they come up with it as you make progress.
--
-- The item buttons are top-level (on UIParent, beside the tracker or in it)
-- and set their own alpha (its fade-out option): they're its own frames, so
-- they're hooked. The tracker leaves its own alpha alone.
local _, ns = ...
local L = ns.L

-- 3rd Party Frames page (no columns: it follows the Quest tracker row).
table.insert(ns.ADDON_NOTES, {
	addon = "Questie", label = "Questie",
	works = L["Follows the Quest tracker row"],
	about = L["Questie's quest tracker and its quest item buttons fade with the Quest tracker row on the " ..
		"Standard Frames page."],
})

-- Its item buttons, one per quest you can hold (made up front).
local ITEM_BUTTONS = 35

ns.WhenAddonLoads("Questie", function()
	ns.FadeWithRow("quests", "quests", { "Questie_BaseFrame" })
	local buttons = {}
	for i = 1, ITEM_BUTTONS do
		buttons[i] = "Questie_ItemButton" .. i
	end
	ns.FadeWithRow("quests", "quests", buttons, true, true)
end)
