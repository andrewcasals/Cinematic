-- Cinematic: EllesmereUI, a whole-UI suite: one addon per part, each set up
-- only once it has loaded. It swaps the game's unit frames, action bars and
-- the like for its own, which fade with the frames they stand in for and
-- follow the same rows on the Standard Frames page. Its parts with no game
-- frame to follow get rows of their own on the Advanced Frames page.
--
-- It sets its frames' alpha all the time (target changes, combat, mouseover):
-- its own frames are hooked, and game frames it sets are checked every frame.
local _, ns = ...
local L = ns.L

-- A frame by its Unlock Mode entry, which hands it out: most of its parts'
-- frames have no name.
local function UnlockFrame(key)
	local eui = _G.EllesmereUI
	local elems = type(eui) == "table" and eui._unlockRegisteredElements
	local elem = type(elems) == "table" and elems[key]
	if type(elem) ~= "table" or type(elem.getFrame) ~= "function" then
		return nil
	end
	local ok, frame = pcall(elem.getFrame)
	return ok and type(frame) == "table" and frame or nil
end

-- A row's match (it's asked about each unnamed frame): whether the frame is
-- one of these entries'. Looked up once per scan.
local function MatchUnlockFrames(keys)
	local frames, lookedAt = {}, nil
	return function(frame)
		local now = GetTime()
		if lookedAt ~= now then
			lookedAt = now
			wipe(frames)
			for _, key in ipairs(keys) do
				local found = UnlockFrame(key)
				if found then
					frames[found] = true
				end
			end
		end
		return frames[frame] or false
	end
end

-- Advanced Frames rows.
for _, known in ipairs({
	{
		key = "euiBars", addon = "EllesmereUIActionBars",
		label = "EllesmereUI Action Bars 6-10", short = "EllesmereUI bars 6-10",
		about = L["its action bars 6 to 10"],
		note = L["Its bars 1-5, pet, stance and XP bars are rows on the Standard Frames page, " ..
			"with its unit frames and quest tracker."],
		names = { "EABBar_Bar6", "EABBar_Bar7", "EABBar_Bar8", "EABBar_Bar9", "EABBar_Bar10" },
	},
	{
		key = "euiCooldowns", addon = "EllesmereUICooldownManager",
		label = "EllesmereUI Cooldown Manager", short = "EllesmereUI cooldowns",
		about = L["its cooldown bars"],
		patterns = { "^ECME_CDMBar_" },
	},
	{
		key = "euiResource", addon = "EllesmereUIResourceBars",
		label = "EllesmereUI Resource Bars", short = "EllesmereUI resource bars",
		about = L["its health, power and totem bars"],
		note = L["Its cast bar isn't faded, like the game's. Its swing timer is the Swing timer row on " ..
			"the Standard Frames page."],
		names = { "EllesmereUIResourceBarsFrame", "ERB_TotemBarFrame", "ERB_CallTotemBarFrame" },
	},
	{
		key = "euiMeters", addon = "EllesmereUIDamageMeters",
		label = "EllesmereUI Damage Meters", short = "EllesmereUI meters",
		about = L["its meter windows"],
		patterns = { "^EllesmereUIDMFrame%d+$" },
	},
	{
		key = "euiDataBars", addon = "EllesmereUIDataBars",
		label = "EllesmereUI Data Bars", short = "EllesmereUI data bars",
		about = L["its data bars"],
		patterns = { "^EllesmereUIDataBarsBar%d+$" },
	},
	{
		key = "euiReminders", addon = "EllesmereUIAuraBuffReminders",
		label = "EllesmereUI Buff Reminders", short = "EllesmereUI reminders",
		about = L["its missing-buff reminders"],
		names = { "EABR_Anchor", "EABR_CombatAnchor", "EABR_TalentAnchor", "EABR_BeaconAnchor", "EABR_CursorAnchor" },
	},
	{
		key = "euiQoL", addon = "EllesmereUIQoL",
		label = "EllesmereUI QoL Displays", short = "EllesmereUI QoL",
		about = L["its stats, FPS, battle res, Bloodlust and movement displays and its crosshair"],
		names = {
			"EUI_SecondaryStats", "EUI_FPSCounter", "EllesmereUIBattleResIcon", "EllesmereUIBloodlustIcon",
			"EUI_MovementAlertFrame", "EUI_TimeSpiralFrame", "EUI_GatewayShardFrame", "EUI_CharacterCrosshair",
		},
	},
	{
		-- (Unnamed and not taking the mouse, so /cine add can't find it.)
		key = "euiDistance", addon = "EllesmereUIQoL",
		label = "EllesmereUI Target Distance", short = "EllesmereUI distance",
		about = L["its target distance (range) text"],
		match = MatchUnlockFrames({ "EUI_TargetDistance" }),
	},
	{
		key = "euiCombatText", addon = "EllesmereUIQoL",
		label = "EllesmereUI Self Combat Text", short = "EllesmereUI combat text",
		about = L["its combat text over your character"],
		match = MatchUnlockFrames({ "EUI_SelfCombatText" }),
	},
	{
		key = "euiEssentials", addon = "EllesmereUIForeverEssentials",
		label = "EllesmereUI Forever Essentials", short = "EllesmereUI essentials",
		about = L["its flight timer, loot feed, threat meter and junk list"],
		names = { "EllesmereUIThreatMeterFrame", "EllesmereUIJunkList" },
		match = MatchUnlockFrames({ "EUI_FlightTimer", "EUI_LootFeed" }),
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

-- Its raid and party frames fade with the game's on the Standard Frames page:
-- the raid ones (with its healer mana, boss and extra frames) as Players, the
-- party ones (unnamed) as Party frames.
ns.WhenAddonLoads("EllesmereUIRaidFrames", function()
	ns.AddScanner(function()
		for _, name in ipairs({
			"EllesmereUIRaidFrameContainer", "ERF_HealerMana", "ERFExtraFramesContainer", "ERFFriendlyBossContainer",
		}) do
			local frame = _G[name]
			if type(frame) == "table" and not ns.IsFaded(frame) then
				ns.AddFoundFrame(frame, "raidplayers", true, true)
			end
		end
		local party = UnlockFrame("RF_PartyFrames")
		if party and not ns.IsFaded(party) then
			ns.AddFoundFrame(party, "party", true, true)
		end
	end)
end)

-- Its nameplates are its own frames on the game's plates (its plate, or the
-- name over a friendly NPC), beside the game's unit frame, which it keeps at
-- alpha 0. The fade only reached that unit frame, so its plates popped up and
-- went at full as plates were switched on and off. Its frames on a plate fade
-- with it, as Plater's do: its alpha (target and range fading) times ours,
-- hooked. They're pooled and move from plate to plate: one moved takes the
-- alpha of the plate it lands on.
do
	local pieces = setmetatable({}, { __mode = "k" }) -- [game plate] = its frames on it (and how many children it had)
	local applying = false

	local function Apply(frame)
		applying = true
		frame:SetAlpha((frame.cinematicOwnAlpha or 1) * (frame.cinematicPlateAlpha or 1))
		applying = false
	end

	local function SetPieceAlpha(frame, alpha)
		alpha = alpha and alpha < 1 and alpha or nil
		if frame.cinematicPlateAlpha ~= alpha then
			frame.cinematicPlateAlpha = alpha
			Apply(frame) -- (back to its own alpha at full)
		end
	end

	local function HookPiece(frame)
		if frame.cinematicHooked then
			return
		end
		frame.cinematicHooked = true
		local alpha = frame:GetAlpha()
		frame.cinematicOwnAlpha = not (issecretvalue and issecretvalue(alpha)) and alpha or nil
		hooksecurefunc(frame, "SetAlpha", ns.Profiled("EllesmereUI plate SetAlpha hook", function(self, own)
			if applying then
				return
			end
			self.cinematicOwnAlpha = type(own) == "number" and not (issecretvalue and issecretvalue(own)) and own or nil
			if self.cinematicPlateAlpha then
				Apply(self)
			end
		end))
		hooksecurefunc(frame, "SetParent", function(self, parent)
			local unitFrame = type(parent) == "table" and not (parent.IsForbidden and parent:IsForbidden())
				and parent.UnitFrame
			SetPieceAlpha(self, type(unitFrame) == "table" and unitFrame.cinematicAlpha or nil)
		end)
	end

	-- Its frames on a plate: the plate's unnamed children but the game's own
	-- (the widgets and interact prompt it moves off the unit frame). Game
	-- frames' methods aren't hooked: that breaks the game's calls to them.
	-- Looked for again when the plate's number of children changes.
	local function Pieces(plate)
		local count = plate:GetNumChildren()
		local list = pieces[plate]
		if list and list.count == count then
			return list
		end
		list = { count = count }
		local unitFrame = plate.UnitFrame
		for _, child in ipairs({ plate:GetChildren() }) do
			if child ~= unitFrame and not child:GetName() and not (unitFrame and (child == unitFrame.WidgetContainer
				or child == unitFrame.SoftTargetFrame)) and not (child.IsForbidden and child:IsForbidden()) then
				HookPiece(child)
				list[#list + 1] = child
			end
		end
		pieces[plate] = list
		return list
	end

	local function SetPlateAlpha(plate, alpha)
		for _, frame in ipairs(Pieces(plate)) do
			if frame:GetParent() == plate then
				SetPieceAlpha(frame, alpha)
			end
		end
	end

	ns.WhenAddonLoads("EllesmereUINameplates", function()
		local other = ns.addonPlateAlpha
		ns.addonPlateAlpha = function(plate, alpha)
			if other then
				other(plate, alpha)
			end
			SetPlateAlpha(plate, alpha)
		end
		-- A new plate's frames are put on it in its own handler, which runs
		-- after ours (Core: NAME_PLATE_UNIT_ADDED): give them the plate's
		-- alpha straight after, before they're drawn. That handler also sets
		-- the game's unit frame of a friendly plate to 1 if it's below 0.01
		-- (ours, faded): put ours back too, or the name flashed up for a
		-- frame on every plate coming into view (turning the camera round in
		-- a city).
		local watcher = CreateFrame("Frame")
		watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
		watcher:SetScript("OnEvent", function(_, _, unit)
			local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
			local unitFrame = plate and not (plate.IsForbidden and plate:IsForbidden()) and plate.UnitFrame
			if unitFrame then
				SetPlateAlpha(plate, unitFrame.cinematicAlpha)
				if unitFrame.cinematicAlpha then
					unitFrame:SetAlpha(unitFrame.cinematicAlpha)
				end
			end
		end)
	end)
end

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
