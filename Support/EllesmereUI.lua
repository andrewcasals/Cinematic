-- Cinematic: EllesmereUI, a whole-UI suite: one addon per part, each set up
-- only once it has loaded. It swaps the game's unit frames, action bars and
-- the like for its own, which fade with the frames they stand in for and
-- follow the same rows on the Standard Frames page. Its parts with no game
-- frame to follow get rows of their own on the 3rd Party Frames page.
--
-- It sets its frames' alpha all the time (target changes, combat, mouseover):
-- its own frames are hooked, and game frames it sets are checked every frame.
local _, ns = ...

-- 3rd Party Frames rows.
for _, known in ipairs({
	{
		key = "euiBars", addon = "EllesmereUIActionBars",
		label = "EllesmereUI Action Bars 6-10", short = "EllesmereUI bars 6-10",
		about = "its action bars 6 to 10",
		note = "Its bars 1-5, pet, stance and XP bars are rows on the Standard Frames page, " ..
			"with its unit frames and quest tracker.",
		names = { "EABBar_Bar6", "EABBar_Bar7", "EABBar_Bar8", "EABBar_Bar9", "EABBar_Bar10" },
	},
	{
		key = "euiCooldowns", addon = "EllesmereUICooldownManager",
		label = "EllesmereUI Cooldown Manager", short = "EllesmereUI cooldowns",
		about = "its cooldown bars",
		patterns = { "^ECME_CDMBar_" },
	},
	{
		key = "euiResource", addon = "EllesmereUIResourceBars",
		label = "EllesmereUI Resource Bars", short = "EllesmereUI resource bars",
		about = "its health, power and totem bars",
		note = "Its cast bar isn't faded, like the game's. Its swing timer is the Swing timer row on " ..
			"the Standard Frames page.",
		names = { "EllesmereUIResourceBarsFrame", "ERB_TotemBarFrame", "ERB_CallTotemBarFrame" },
	},
	{
		key = "euiMeters", addon = "EllesmereUIDamageMeters",
		label = "EllesmereUI Damage Meters", short = "EllesmereUI meters",
		about = "its meter windows",
		patterns = { "^EllesmereUIDMFrame%d+$" },
	},
	{
		key = "euiDataBars", addon = "EllesmereUIDataBars",
		label = "EllesmereUI Data Bars", short = "EllesmereUI data bars",
		about = "its data bars",
		patterns = { "^EllesmereUIDataBarsBar%d+$" },
	},
	{
		key = "euiReminders", addon = "EllesmereUIAuraBuffReminders",
		label = "EllesmereUI Buff Reminders", short = "EllesmereUI reminders",
		about = "its missing-buff reminders",
		names = { "EABR_Anchor", "EABR_CombatAnchor", "EABR_TalentAnchor", "EABR_BeaconAnchor", "EABR_CursorAnchor" },
	},
}) do
	known.suite, known.hookAlpha = "EllesmereUI", true
	table.insert(ns.ADDON_FRAMES, known)
end

-- Its frames standing in for the game's, by Standard Frames row: the row,
-- the fade group, and the frames.
local function FadeWithRows(rows)
	for _, row in ipairs(rows) do
		ns.FadeWithRow(row[1], row[2], { unpack(row, 3) }, true, true)
	end
end

-- The core: its visibility pass sets its frames' alpha (and some of the
-- game's) a frame after target changes and the like. Fade them again
-- straight after, from its own list of visibility updates (kept last in it:
-- its parts may add theirs later), and check every frame for the rest.
ns.WhenAddonLoads("EllesmereUI", function()
	ns.syncEveryFrame = true
	ns.FollowOwnAlpha({ "MicroMenuContainer", "BagsBar", "Minimap", "ObjectiveTrackerFrame" })
	-- (Its cooldown manager sets the game's cooldown viewers' alpha, which
	-- can't be hooked, from a second list run after the first: joined once,
	-- at the first scan, after its parts have joined. It can't be left.)
	local eui = _G.EllesmereUI
	if type(eui) ~= "table" then
		return
	end
	local followingVisEdges = false
	ns.AddScanner(function()
		if type(eui.RegisterVisibilityUpdater) == "function"
			and type(eui.UnregisterVisibilityUpdater) == "function" then
			eui.UnregisterVisibilityUpdater(ns.SyncOwnAlphas)
			eui.RegisterVisibilityUpdater(ns.SyncOwnAlphas)
		end
		if not followingVisEdges and type(eui.RegisterVisEdge) == "function" then
			followingVisEdges = true
			eui.RegisterVisEdge(ns.SyncOwnAlphas)
		end
	end)
end)

ns.WhenAddonLoads("EllesmereUIUnitFrames", function()
	FadeWithRows({
		{ "player", "player", "EllesmereUIUnitFrames_Player", "EllesmereUIUnitFrames_Pet" },
		{ "target", "target", "EllesmereUIUnitFrames_Target" },
		{ "tot", "target", "EllesmereUIUnitFrames_TargetTarget" },
		{ "focus", "target", "EllesmereUIUnitFrames_Focus", "EllesmereUIUnitFrames_FocusTarget" },
		{ "buffs", "buffs", "EllesmereUIPlayerAuraBars_Buffs", "EllesmereUIPlayerAuraBars_Debuffs" },
	})
	ns.AddPortraitFrame("EllesmereUIUnitFrames_Player")
end)

ns.WhenAddonLoads("EllesmereUIActionBars", function()
	FadeWithRows({
		{ "mainbar", "bars", "EABBar_MainBar" },
		{ "bottomleft", "bars", "EABBar_Bar2" },
		{ "bottomright", "bars", "EABBar_Bar3" },
		{ "right1", "sidebars", "EABBar_Bar4" },
		{ "right2", "sidebars", "EABBar_Bar5" },
		{ "pet", "bars", "EABBar_PetBar" },
		{ "stance", "bars", "EABBar_StanceBar" },
		{ "xp", "bars", "EllesmereEAB_XPBar", "EllesmereEAB_RepBar", "EllesmereEAB_FavorBar" },
	})
	-- It keeps retail's main bar at alpha 0.
	ns.LeaveAlone({ "MainActionBar" })
end)

ns.WhenAddonLoads("EllesmereUIQuestTracker", function()
	FadeWithRows({ { "quests", "quests", "EllesmereUIQTBackground" } })
end)

ns.WhenAddonLoads("EllesmereUIResourceBars", function()
	FadeWithRows({ { "swing", "swing", "ERB_SwingTimerFrame" } })
end)

-- It moves the map out of the cluster and keeps the cluster at alpha 0.
-- Its zone name bar is sized to the name, measured only when the name
-- changes: measured while the map is shrunk away (faded), the text reads far
-- too wide (it's never drawn smaller than a few pixels), and the bar stays
-- the width of the screen. So measure it again once the map has its size
-- back, the way it does (a frame later, once the text has its size again).
local function RefitLocationBar()
	local bar = _G._EBS_LocationBg
	if type(bar) ~= "table" or type(bar.GetRegions) ~= "function" then
		return
	end
	for _, region in ipairs({ bar:GetRegions() }) do
		if region:GetObjectType() == "FontString" then
			local width = region:GetStringWidth()
			if type(width) == "number" and width > 0 then
				bar:SetSize(width + 20, 18)
			end
			return
		end
	end
end

ns.WhenAddonLoads("EllesmereUIMinimap", function()
	ns.LeaveAlone({ "MinimapCluster" })
	ns.OnMinimapRestored(function()
		RefitLocationBar()
		C_Timer.After(0, RefitLocationBar)
	end)
end)

-- Its chat draws its panel, sidebar, border and tab strip in its own unnamed
-- frames on UIParent, so they don't fade with the chat frames. The panel and
-- sidebar are found through its per-chat-frame data; the rest by what
-- they're anchored to (those parts, or the tab dock).
local function IsUsable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and type(frame.SetAlpha) == "function" and not (frame.IsForbidden and frame:IsForbidden())
end

local function IsAnchoredTo(frame, targets)
	for i = 1, frame:GetNumPoints() do
		local ok, _, relativeTo = pcall(frame.GetPoint, frame, i)
		if ok and relativeTo and targets[relativeTo] then
			return true
		end
	end
	return false
end

local function FindChat()
	local chatData = _G.EllesmereUI and _G.EllesmereUI._chatCFD
	if type(chatData) ~= "function" then
		return
	end
	local parts = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local chatFrame = _G["ChatFrame" .. i]
		local ok, data = false, nil
		if chatFrame then
			ok, data = pcall(chatData, chatFrame)
		end
		if ok and type(data) == "table" then
			for _, key in ipairs({ "bg", "sidebar", "scrollBtn" }) do
				if IsUsable(data[key]) then
					parts[data[key]] = true
					ns.AddFoundFrame(data[key], "chat", true, true)
				end
			end
		end
	end
	if not next(parts) then
		return
	end
	if _G.GeneralDockManager then
		parts[_G.GeneralDockManager] = true
	end
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if not ns.IsFaded(frame) and IsUsable(frame) and not frame:GetName()
			and IsAnchoredTo(frame, parts) then
			ns.AddFoundFrame(frame, "chat", true, true)
		end
	end
end

ns.WhenAddonLoads("EllesmereUIChat", function()
	ns.AddScanner(FindChat)
end)
