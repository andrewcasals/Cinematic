-- Cinematic: Horizon Suite, whose Focus module stands in for the game's quest
-- tracker (hidden for good, under a hidden frame of its own). Its tracker
-- fades with the Quest tracker row on the Standard Frames page.
--
-- It sets its tracker's alpha itself (fading in as it shows, which it does
-- again on zone changes, and its own mouseover and combat fades): caught at
-- that alpha between ticks, the tracker flickered while faded. Its frames are
-- its own, so they're hooked.
local _, ns = ...
local L = ns.L

-- 3rd Party Frames page (no columns: it follows the Quest tracker row).
table.insert(ns.ADDON_NOTES, {
	addon = "HorizonSuite", label = "Horizon Suite",
	works = L["Follows the Quest tracker row"],
	about = L["Horizon Suite's quest tracker (Focus), its dungeon banner and its floating quest " ..
		"item button fade with the Quest tracker row on the Standard Frames page."],
})

-- Its dungeon banner (and retail's Mythic+ one) sit on UIParent rather than
-- in the tracker, unnamed: found through its addon table.
local BLOCKS = ns.isRetail and { "runBlock", "mplusBlock" } or { "runBlock" }

ns.WhenAddonLoads("HorizonSuite", function()
	ns.FadeWithRow("quests", "quests", { "HSFrame", "HSFloatingQuestItem" }, true, true)
	ns.AddScanner(function()
		local hs = _G.HorizonSuite
		if type(hs) ~= "table" then
			return
		end
		for _, key in ipairs(BLOCKS) do
			local block = hs[key]
			if type(block) == "table" and block.GetAlpha and not ns.IsFaded(block) then
				ns.AddFoundFrame(block, "quests", true, true)
			end
		end
	end)
end)
