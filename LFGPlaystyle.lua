-- Cinematic: the Looking For Group window's "Select Playstyle (required)"
-- dropdown starts on the playstyle you picked last time (lfgPlaystyle, saved
-- in the profile), instead of empty every session (rememberPlaystyle, on the
-- Quality of life page). Only where the game's window has one (WoW Forever's
-- group finder, Blizzard_GroupFinder_VanillaStyle, loaded on demand).
local _, ns = ...

local function Enabled()
	return ns.db and ns.db.rememberPlaystyle
end

local VALID = {}
if Enum and Enum.LFGEntryGeneralPlaystyle then
	for _, value in pairs(Enum.LFGEntryGeneralPlaystyle) do
		if type(value) == "number" and value > 0 then
			VALID[value] = true
		end
	end
end

-- Pick the saved playstyle as the view shows, if none is picked yet.
local function Restore(view)
	if not Enabled() or view.generalPlaystyle or not view.PlayStyleDropdown then
		return
	end
	local saved = ns.db.lfgPlaystyle
	if not VALID[saved] then
		return
	end
	LFGListingActivityView_OnPlayStyleSelectedInternal(view, saved)
	if view.PlayStyleDropdown.GenerateMenu then
		view.PlayStyleDropdown:GenerateMenu() -- its text shows the choice
	end
end

local hooked = false
local function SetUp()
	local view = LFGListingFrame and LFGListingFrame.ActivityView
	if hooked or not view or type(LFGListingActivityView_OnPlayStyleSelectedInternal) ~= "function" then
		return
	end
	hooked = true
	-- (The dropdown's own pick goes through this too.)
	hooksecurefunc("LFGListingActivityView_OnPlayStyleSelectedInternal", function(_, playstyle)
		if Enabled() and VALID[playstyle] then
			ns.db.lfgPlaystyle = playstyle
		end
	end)
	view:HookScript("OnShow", Restore)
	if ns.Flag(view:IsShown()) then
		Restore(view)
	end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function()
	SetUp()
	if hooked then
		watcher:UnregisterAllEvents()
	end
end)
