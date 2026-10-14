-- Cinematic: Cooldown Manager Centered.
local _, ns = ...
local L = ns.L

table.insert(ns.ADDON_FRAMES, {
	key = "cmc", addon = "CooldownManagerCentered", label = "Cooldown Manager Centered",
	about = L["its buff containers, trackers and aura overlays"],
	note = L["The game's Cooldown Manager itself is a row on the Standard Frames page."],
	-- Its icons sit in unnamed copies of these frames, which follow their
	-- alpha, so fading these fades them too.
	names = { "CMCUtilityLayoutHost", "CMCEssentialCustomTrackerHost" },
	patterns = { "^CMCBuffContainer%d+$", "^CMCTracker%d+$" },
	-- Its aura overlays: unnamed screen-sized AuraContainers.
	match = function(frame)
		return frame:GetObjectType() == "AuraContainer"
	end,
})
