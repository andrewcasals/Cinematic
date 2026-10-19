-- Cinematic: FlareUI, a whole-UI suite (one addon, a module per part). It
-- swaps the game's unit frames, buffs, quest tracker, party and raid frames
-- and XP bar for its own, which fade with the frames they stand in for and
-- follow the same rows on the Standard Frames page. It keeps the game's
-- action bars, minimap and damage meter, skinned. Its boss frames, with no
-- game frame to follow, get a row on the 3rd Party Frames page.
--
-- It sets alphas itself: its unit frames' fade-out (out of combat with no
-- target) and its quest items' are its own frames, so they're hooked; its
-- Show choices (Mouseover, Combat...) set the game's action bars, bag bar and
-- micro menu, and its damage meter fade the game's meter: followed.
local _, ns = ...
local L = ns.L

-- 3rd Party Frames row.
table.insert(ns.ADDON_FRAMES, {
	key = "flareBoss", addon = "FlareUI",
	label = "FlareUI Boss Frames", short = "FlareUI bosses",
	about = L["its boss frames"],
	note = L["Its unit frames, cast bar, resource bars, buffs, quest tracker, party and raid frames, " ..
		"XP bar and totems are rows on the Standard Frames page."],
	names = { "FlareUI_Boss" },
	hookAlpha = true,
})

-- Its frames standing in for the game's, by Standard Frames row: the row,
-- the fade group, and the frames. (Its health bar under your character is
-- the personal health bar; its power, druid mana and combo points the
-- personal resource bar.)
local ROWS = {
	{ "player", "player", "FlareUI_UF_Player", "FlareUI_Totems" },
	{ "petframe", "player", "FlareUI_UF_Pet" },
	{ "target", "target", "FlareUI_UF_Target" },
	{ "tot", "target", "FlareUI_UF_TargetOfTarget" },
	{ "focus", "target", "FlareUI_UF_Focus", "FlareUI_UF_TargetOfFocus" },
	{ "castbar", "castbar", "FlareUI_UF_PlayerCastBar" },
	{ "prd", "prd", "FlareUI_Resource_health" },
	{ "prdpower", "prdpower", "FlareUI_Resource_power", "FlareUI_Resource_mana", "FlareUI_Resource_combo" },
	{ "swing", "swing", "FlareUI_Resource_swingMain", "FlareUI_Resource_swingOff", "FlareUI_Resource_swingRanged" },
	{ "buffs", "buffs", "FlareUI_Buffs", "FlareUI_Debuffs" },
	{ "quests", "quests", "FlareUI_ObjectiveTracker" },
	{ "party", "party", "FlareUI_Party" },
	{ "xp", "bars", "FlareUI_XPBar" },
	-- (The panel its minimap's buttons are gathered into.)
	{ "minimap", "minimap", "FlareUI_MinimapBag" },
}

-- The game's frames its Show choices and damage meter fade.
local FOLLOWED = {
	"MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
	"MultiBar5", "MultiBar6", "MultiBar7", "PetActionBar", "StanceBar", "BagsBar", "MicroMenuContainer",
	"DamageMeter",
}

ns.WhenAddonLoads("FlareUI", function()
	for _, row in ipairs(ROWS) do
		ns.FadeWithRow(row[1], row[2], { unpack(row, 3) }, true, true)
	end
	-- (A bar set to a Show choice other than Always is stepped towards its
	-- alpha every frame, so it's faded again every frame, not just each tick.)
	ns.FollowOwnAlpha(FOLLOWED)
	ns.syncEveryFrame = true
	ns.AddScanner(function()
		-- Its raid frames (the main tanks' apart) fade with the game's, as Players.
		for _, name in ipairs({ "FlareUI_Raid", "FlareUI_RaidTanks" }) do
			local frame = _G[name]
			if type(frame) == "table" and not ns.IsFaded(frame) then
				ns.AddFoundFrame(frame, "raidplayers", true, true)
			end
		end
		-- Its quest item buttons, numbered as they're made (on UIParent: they're
		-- secure, so not in the tracker).
		local i = 1
		while _G["FlareUI_TrackerItem" .. i] do
			local button = _G["FlareUI_TrackerItem" .. i]
			if not ns.IsFaded(button) then
				ns.AddFoundFrame(button, "quests", true, true)
			end
			i = i + 1
		end
		-- The bar behind its minimap's zone name and clock (unnamed, in the
		-- minimap cluster): the Minimap header row.
		local flare = _G.FlareUI
		local header = type(flare) == "table" and type(flare.Minimap) == "table" and flare.Minimap.Header
		if type(header) == "table" and header.GetAlpha and not ns.IsFaded(header) then
			ns.AddFoundFrame(header, "minimapheader", false, false)
		end
	end)
end)
