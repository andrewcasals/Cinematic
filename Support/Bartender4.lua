-- Cinematic: Bartender4, which swaps the game's action bars for its own. Its
-- bars fade with the game's bars they stand in for and follow the same rows
-- on the Standard Frames page; its art bar (the gryphons) is the Action bar
-- art row. The bars with no game bar to follow (its bar 2, class and bonus
-- bars) get a row of their own on the 3rd Party Frames page.
--
-- Its bars set their own alpha (each bar's opacity and fade-out settings):
-- they're its own frames, so they're hooked.
local _, ns = ...
local L = ns.L

-- 3rd Party Frames row.
table.insert(ns.ADDON_FRAMES, {
	key = "bt4Bars", addon = "Bartender4",
	label = "Bartender4 other bars", short = "Bartender4 bars",
	about = L["its bar 2, class bars and bonus bar"],
	note = L["Its other bars, pet, stance, bag, micro menu, status and art bars are rows on the Standard " ..
		"Frames page."],
	names = { "BT4Bar2", "BT4Bar7", "BT4Bar8", "BT4Bar9", "BT4Bar10", "BT4Bar11", "BT4Bar12" },
	hookAlpha = true,
})

-- Its frames standing in for the game's, by Standard Frames row: the row,
-- the fade group, and the frames. (Its bars 1 and 3-6 show the game's action
-- pages 1 and 3-6, so the bars that page sits on; 13-15 are retail's bars 6-8.)
local ROWS = {
	{ "mainbar", "bars", "BT4Bar1", "BT4BarVehicle" },
	{ "right1", "sidebars", "BT4Bar3" },
	{ "right2", "sidebars", "BT4Bar4" },
	{ "bottomright", "bars", "BT4Bar5" },
	{ "bottomleft", "bars", "BT4Bar6" },
	{ "bar6", "bars", "BT4Bar13" },
	{ "bar7", "bars", "BT4Bar14" },
	{ "bar8", "bars", "BT4Bar15" },
	{ "pet", "bars", "BT4BarPetBar" },
	{ "stance", "bars", "BT4BarStanceBar" },
	{ "micro", "bars", "BT4BarMicroMenu", "BT4BarBagBar" },
	{ "xp", "bars", "BT4BarStatusTrackingBar", "BT4BarStatus", "BT4BarXP", "BT4BarRep" },
	{ "extra", "bars", "BT4BarExtraActionBar", "BT4BarZoneAbilityBar" },
	{ "art", "barart", "BT4BarBlizzardArt" },
	-- The queue eye's bar goes where the game's eye does (see Frames.lua).
	ns.isRetail and { "micro", "bars", "BT4BarQueueStatus" } or { "minimap", "minimap", "BT4BarQueueStatus" },
}

ns.WhenAddonLoads("Bartender4", function()
	for _, row in ipairs(ROWS) do
		ns.FadeWithRow(row[1], row[2], { unpack(row, 3) }, true, true)
	end
end)
