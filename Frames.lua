-- Cinematic: the frames that fade. The built-in fade list, fading and
-- nesting, the minimap shrink, scanning for frames created later, the Issue
-- Reporter, hover, and the 3rd Party Frames page's lists.
local _, ns = ...

-- Frames to fade, grouped so hovering one member reveals the whole group.
-- Names differ between Classic Era, progression Classic and Retail; missing
-- ones are skipped.
local FRAME_GROUPS = {
	bars = {
		"MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
		"MultiBar5", "MultiBar6", "MultiBar7", "StanceBarFrame", "StanceBar",
		"PetActionBarFrame", "PetActionBar", "PossessBarFrame", "PossessActionBar",
		"MicroButtonAndBagsBar", "MicroMenuContainer", "BagsBar",
		"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
		"StatusTrackingBarManager", "ExtraActionBarFrame", "ZoneAbilityFrame",
	},
	sidebars = { "MultiBarLeft", "MultiBarRight" },
	player = { "PlayerFrame", "PetFrame", "TotemFrame" },
	totems = {
		"MultiCastActionBarFrame", "MultiCastSummonSpellButton", "MultiCastRecallSpellButton",
		"MultiCastFlyoutFrame", "MultiCastSlotButton1", "MultiCastSlotButton2",
		"MultiCastSlotButton3", "MultiCastSlotButton4",
		"MultiCastActionPage1", "MultiCastActionPage2", "MultiCastActionPage3",
	},
	target = { "TargetFrame", "TargetFrameToT", "FocusFrame" },
	minimap = { "MinimapCluster", "Minimap", "GameTimeFrame", "CinematicMinimapButton" },
	buffs = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" },
	quests = { "QuestWatchFrame", "WatchFrame", "ObjectiveTrackerFrame", "QuestTimerFrame" },
	misc = { "DurabilityFrame" },
	swing = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" },
	meters = { "DamageMeter" },
	-- The Cooldown Manager (retail and Forever). Made when its addon loads,
	-- so a later scan picks it up.
	cooldowns = {
		"EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer",
	},
	-- Retail's quest waypoint: the marker in the world, with its distance,
	-- that shows where a tracked quest or map pin is.
	waypoint = { "SuperTrackedFrame" },
	chat = {
		"GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
		"QuickJoinToastButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
	},
}

-- Top-level frames whose names contain any of these are faded too. This picks
-- up client features (and addons) whose exact frame names vary, like the
-- built-in damage meter and swing timer.
local AUTO_PATTERNS = { DamageMeter = "meters", SwingTimer = "swing" }
ns.SCAN_INTERVAL = 5

-- Other addons' frames faded out of the box, listed on the 3rd Party Frames page.
-- Each fades as its own group ("addon:<key>") while its addon is loaded and
-- it isn't switched off (db.addonFrames[key] = false). names: its named
-- frames. about: what they are, for the options page (note: more to say there).
-- patterns: name patterns for top-level frames numbered per window.
-- match(frame): whether an unnamed frame on UIParent is one of its
-- own, for addons that don't name their frames (those can't be added with
-- /cine add, which saves frames by name). short: a shorter label, if needed.
ns.ADDON_FRAMES = {
	{
		key = "details", addon = "Details", label = "Details! Damage Meter", short = "Details!",
		about = "its meter windows",
		-- Each window is several frames side by side on UIParent (the bars sit
		-- in their own frame), so hovering one and using /cine add misses the rest.
		patterns = { "^DetailsBaseFrame%d+$", "^DetailsRowFrame%d+$", "^Details_SwitchButtonFrame%d+$" },
	},
	{
		key = "cmc", addon = "CooldownManagerCentered", label = "Cooldown Manager Centered",
		about = "its buff containers, trackers and aura overlays",
		note = "The game's Cooldown Manager itself is a row on the Standard Frames page.",
		-- Its icons sit in unnamed copies of these frames, which follow their
		-- alpha, so fading these fades them too.
		names = { "CMCUtilityLayoutHost", "CMCEssentialCustomTrackerHost" },
		patterns = { "^CMCBuffContainer%d+$", "^CMCTracker%d+$" },
		-- Its aura overlays: unnamed screen-sized AuraContainers.
		match = function(frame)
			return frame:GetObjectType() == "AuraContainer"
		end,
	},
	{
		key = "fecm", addon = "ForeverEnhancedCooldownManager", label = "Forever Enhanced Cooldown Manager",
		short = "Enhanced Cooldown Manager", -- (the Standard Frames page's label column is narrow)
		about = "its cooldown and buff bars, and the pulse when a cooldown is ready",
		names = { "FECMPulse" },
		-- Its bars are unnamed: told apart by the parts each bar is made with.
		match = function(frame)
			return (frame.kind == "cooldown" or frame.kind == "aura")
				and type(frame.icons) == "table" and type(frame.mover) == "table"
		end,
	},
}

local function AddOnLoaded(name)
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	return isLoaded and isLoaded(name) and true or false
end

-- Installed, loaded or not (missing ones error or say "MISSING").
function ns.AddOnInstalled(name)
	local getInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
	if not getInfo then
		return false
	end
	local ok, _, _, _, _, reason = pcall(getInfo, name)
	return ok and reason ~= "MISSING"
end
ns.AddOnLoaded = AddOnLoaded

function ns.IsAddonFramesOn(key)
	return ns.db.addonFrames[key] ~= false
end

-- Groups whose frames set their own alpha (see AddFrame).
local OWN_ALPHA = { chat = true, waypoint = true, cooldowns = true }

ns.managed = {}       -- { frame, name, group, alpha, baseAlpha }
local seen = {}
-- A managed frame inside another managed frame already fades with its
-- parent; fading it too would multiply the two and make it lag (half way
-- through a fade-in it would show at 25%, not 50%). Nested frames still track
-- their own fade state (the minimap needs it to know when to shrink) but are
-- drawn at full alpha.
-- The minimap's map image breaks if the minimap sits at alpha 0 while full
-- size, so it's only ever at 0 while shrunk. When nested it follows its
-- parent's fade but runs its own fade MINIMAP_ALPHA_BOOST times faster: nearly
-- opaque straight away (no lag), yet never jumping from 0 to 1 at full size.
local MINIMAP_ALPHA_BOOST = 20

local function VisualAlpha(entry)
	if entry.shrunk then
		return 0
	end
	if not entry.nested then
		return entry.alpha
	end
	if entry.shrinkWhenFaded then
		return math.min(1, entry.alpha * MINIMAP_ALPHA_BOOST)
	end
	return 1
end

local function ApplyAlpha(entry)
	entry.settingAlpha = true
	entry.frame:SetAlpha(VisualAlpha(entry) * (entry.baseAlpha or 1))
	entry.settingAlpha = false
end

local function AddFrame(frame, group)
	if not frame or seen[frame] or not frame.SetAlpha or frame == ns.letterbox then
		return false
	end
	if frame.IsForbidden and frame:IsForbidden() then
		return false
	end
	local name = frame:GetName()
	if name and ns.db.ignoredFrames[name] then
		return false
	end
	seen[frame] = true
	local entry = {
		frame = frame, name = name, group = group, alpha = 1,
		shrinkWhenFaded = frame == Minimap,
	}
	ns.managed[#ns.managed + 1] = entry

	-- Chat frames manage their own alpha (the input bar sits faint until you
	-- press Enter), and so do the waypoint (it dims as you look past it), the
	-- Cooldown Manager (its opacity setting) and other addons' frames (their
	-- own fades). Track the alpha last asked for, fade relative to it, and
	-- return to it rather than to fully opaque. Only these are hooked, to keep
	-- away from protected frames like action bars.
	if OWN_ALPHA[group] or group:find("^addon:") then
		entry.baseAlpha = frame:GetAlpha()
		hooksecurefunc(frame, "SetAlpha", function(self, alpha)
			if entry.settingAlpha or entry.removed then
				return
			end
			entry.baseAlpha = alpha
			if VisualAlpha(entry) < 1 then
				entry.settingAlpha = true
				self:SetAlpha(alpha * VisualAlpha(entry))
				entry.settingAlpha = false
			end
		end)
	end
	return true
end

-- Frames that fade on their own even though they sit inside another faded
-- frame, so they can be shown separately (target of target during combat).
local NEVER_NESTED = { TargetFrameToT = true }

local function RecomputeNesting()
	for _, entry in ipairs(ns.managed) do
		local nested = false
		local parent = entry.frame:GetParent()
		while parent and parent ~= UIParent and not NEVER_NESTED[entry.name] do
			if seen[parent] then
				nested = true
				break
			end
			parent = parent:GetParent()
		end
		if nested ~= (entry.nested or false) then
			entry.nested = nested
			ApplyAlpha(entry)
		end
	end
end

local function RemoveFrame(frame)
	for i, entry in ipairs(ns.managed) do
		if entry.frame == frame then
			entry.settingAlpha = true
			frame:SetAlpha(entry.baseAlpha or 1)
			entry.settingAlpha = false
			if entry.shrunk then frame:SetScale(entry.savedScale or 1) end
			entry.removed = true -- its SetAlpha hook (if any) can't be undone, only ignored
			table.remove(ns.managed, i)
			seen[frame] = nil
			RecomputeNesting()
			return true
		end
	end
	return false
end

-- The built-in group a frame name belongs to by pattern, if any.
local function AutoPatternGroup(name)
	for pattern, group in pairs(AUTO_PATTERNS) do
		if name:find(pattern) then
			return group
		end
	end
end

-- Windows (settings, spellbook, popups) are never faded as extras: fading
-- one you're using leaves it invisible but still taking your clicks and keys.
-- Escape-closable and panel windows, ones the reveal lists know, and anything
-- drawn in the dialog strata or above.
local WINDOW_STRATA = { DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }

local function IsWindow(frame, name)
	if ns.WINDOWS[name] or (UIPanelWindows and UIPanelWindows[name]) then
		return true
	end
	for _, special in ipairs(UISpecialFrames or {}) do
		if special == name then
			return true
		end
	end
	return WINDOW_STRATA[frame:GetFrameStrata()] or false
end

local function ScanTopLevelFrames()
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if not seen[frame] and not (frame.IsForbidden and frame:IsForbidden()) then
			local name = frame:GetName()
			if name then
				local group = AutoPatternGroup(name)
				if group then
					AddFrame(frame, group)
				elseif ns.db.extraFrames[name] and not IsWindow(frame, name) then
					AddFrame(frame, "extra:" .. name)
				end
			end
		end
	end
	for name in pairs(ns.db.extraFrames) do
		local frame = _G[name]
		if type(frame) == "table" and frame.GetFrameStrata and not (frame.IsForbidden and frame:IsForbidden())
			and not IsWindow(frame, name) then
			AddFrame(frame, "extra:" .. name)
		end
	end
end

local function ScanAddonFrames()
	for _, known in ipairs(ns.ADDON_FRAMES) do
		if ns.IsAddonFramesOn(known.key) and AddOnLoaded(known.addon) then
			local group = "addon:" .. known.key
			for _, name in ipairs(known.names or {}) do
				AddFrame(_G[name], group)
			end
			if known.match or known.patterns then
				for _, frame in ipairs({ UIParent:GetChildren() }) do
					if not seen[frame] and not (frame.IsForbidden and frame:IsForbidden()) then
						local name = frame:GetName()
						if name then
							for _, pattern in ipairs(known.patterns or {}) do
								if name:find(pattern) then
									AddFrame(frame, group)
									break
								end
							end
						elseif known.match and known.match(frame) then
							AddFrame(frame, group)
						end
					end
				end
			end
		end
	end
end

-- Blizzard's PTR/beta Issue Reporter is built from unnamed frames, so it
-- can't be added by name. Find it through its global table, or failing that
-- by an unnamed top-level frame showing the text "Issue Reporter".
-- Forbidden frames error on almost any method call, so check this first.
local function IsForbidden(frame)
	return frame.IsForbidden and frame:IsForbidden()
end

local function IsFrame(value)
	return type(value) == "table" and type(value.GetObjectType) == "function"
		and type(value.SetAlpha) == "function"
end

local function TopLevelAncestor(frame)
	while frame do
		local parent = frame:GetParent()
		if parent == UIParent then
			return frame
		elseif parent == nil then
			return nil
		end
		frame = parent
	end
end

-- A frame's regions or children as a list, or nil when it's off limits:
-- a frame that isn't forbidden itself can still hold forbidden parts, and
-- then GetRegions/GetChildren error.
local function ReadParts(frame, method)
	local parts = { pcall(frame[method], frame) }
	if not table.remove(parts, 1) then
		return nil
	end
	return parts
end

local function HasIssueReporterText(frame, depth)
	if IsForbidden(frame) then
		return false
	end
	for _, region in ipairs(ReadParts(frame, "GetRegions") or {}) do
		if not IsForbidden(region) and region.GetText then
			local text = region:GetText()
			if type(text) == "string" and not (issecretvalue and issecretvalue(text))
				and text:find("Issue") and text:find("Reporter") then
				return true
			end
		end
	end
	if depth > 0 then
		for _, child in ipairs(ReadParts(frame, "GetChildren") or {}) do
			if HasIssueReporterText(child, depth - 1) then
				return true
			end
		end
	end
	return false
end

local function FindIssueReporter()
	local reporter = _G.PTR_IssueReporter
	if type(reporter) == "table" then
		if IsFrame(reporter) then
			AddFrame(TopLevelAncestor(reporter), "issueReporter")
		end
		for _, value in pairs(reporter) do
			if IsFrame(value) and not IsForbidden(value) then
				AddFrame(TopLevelAncestor(value), "issueReporter")
			end
		end
	end
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if not seen[frame] and not IsForbidden(frame) and not frame:GetName()
			and HasIssueReporterText(frame, 2) then
			AddFrame(frame, "issueReporter")
		end
	end
end

-- Saved extras that are really built-in frames (added before /cine add
-- checked for that) would show in the extras list, where Stop would break the
-- built-in fade. Drop them.
function ns.PruneBuiltInExtras()
	for _, names in pairs(FRAME_GROUPS) do
		for _, name in ipairs(names) do
			ns.db.extraFrames[name] = nil
		end
	end
end

-- Safe to call repeatedly: frames already managed are skipped, and frames
-- created after login get picked up on a later call.
function ns.BuildManagedList()
	for group, names in pairs(FRAME_GROUPS) do
		for _, name in ipairs(names) do
			AddFrame(_G[name], group)
		end
	end
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		AddFrame(_G["ChatFrame" .. i], "chat")
		AddFrame(_G["ChatFrame" .. i .. "EditBox"], "chat")
	end
	ScanTopLevelFrames()
	ScanAddonFrames()
	FindIssueReporter()
	RecomputeNesting()
end

-- Switching a supported addon off puts its frames back at once;
-- switching it on fades them from the next scan.
function ns.SetAddonFramesOn(key, on)
	ns.db.addonFrames[key] = on
	if on then
		ns.BuildManagedList()
		return
	end
	local group = "addon:" .. key
	for i = #ns.managed, 1, -1 do
		local entry = ns.managed[i]
		if entry.group == group then
			RemoveFrame(entry.frame)
		end
	end
end

-- The minimap's player arrow and icons ignore alpha, and hiding the minimap
-- leaves its map image blank once it's shown again. So once fully faded it's
-- shrunk to almost nothing instead (icons shrink with it), and its size is put
-- back as soon as it starts to fade in. Its on-screen rect is saved first so
-- hover still works over the empty spot.
local SHRUNK_SCALE = 0.01
-- Once shrunk, stay shrunk (at alpha 0) for a minimum time, so fading out and
-- hovering straight back doesn't shrink and unshrink in quick succession.
local MIN_SHRUNK_TIME = 0.5

local function ShrinkEntry(entry)
	local frame = entry.frame
	entry.savedScale = frame:GetScale()
	entry.savedRect = { frame:GetRect() }
	entry.savedEffectiveScale = frame:GetEffectiveScale()
	frame:SetScale(SHRUNK_SCALE)
	entry.shrunk = true
	entry.shrunkAt = GetTime()
end

local function UnshrinkEntry(entry)
	entry.frame:SetScale(entry.savedScale or 1)
	entry.shrunk = false
end

function ns.SetEntryAlpha(entry, alpha)
	entry.alpha = alpha
	if entry.shrinkWhenFaded then
		if alpha > 0 then
			if entry.shrunk and GetTime() - entry.shrunkAt >= MIN_SHRUNK_TIME then
				UnshrinkEntry(entry)
			end
		elseif not entry.shrunk then
			-- Shrink in the same step it reaches 0, so it's never at alpha 0
			-- while full size.
			ShrinkEntry(entry)
		end
	end
	ApplyAlpha(entry)
end

local function IsCursorInSavedRect(entry)
	local left, bottom, width, height = unpack(entry.savedRect)
	if not left then
		return false
	end
	local x, y = GetCursorPosition()
	x, y = x / entry.savedEffectiveScale, y / entry.savedEffectiveScale
	return x >= left and x <= left + width and y >= bottom and y <= bottom + height
end

-- The UI element the mouse is actually over (nil over the 3D world).
local function MouseFocus()
	local focus
	if GetMouseFoci then
		focus = GetMouseFoci()[1]
	elseif GetMouseFocus then
		focus = GetMouseFocus()
	end
	if focus == WorldFrame then
		return nil
	end
	return focus
end

local function IsInside(frame, ancestor)
	while frame do
		if frame == ancestor then
			return true
		end
		if IsForbidden(frame) then
			return false
		end
		frame = frame:GetParent()
	end
	return false
end

-- Buff icons are small, so they count as hovered from a little way off, and
-- across the gaps between them: the cursor within buffHoverPadX/Y (UI units)
-- of any shown icon. Icons are the mouse-enabled frames up to a few levels down
-- (BuffButtonN on Classic, the aura frames in each AuraContainer on retail).
local BUFF_HOVER_DEPTH = 3

local function IsNearIcon(depth, padX, padY, ...)
	for i = 1, select("#", ...) do
		local child = select(i, ...)
		if not IsForbidden(child) and child:IsVisible() then
			if child:IsMouseEnabled() and child:IsMouseOver(padY, -padY, -padX, padX) then
				return true
			end
			if depth > 1 and IsNearIcon(depth - 1, padX, padY, child:GetChildren()) then
				return true
			end
		end
	end
	return false
end

function ns.IsEntryHovered(entry)
	if entry.shrunk then
		return IsCursorInSavedRect(entry)
	end
	if entry.group == "buffs" then
		return entry.frame:IsVisible() and IsNearIcon(BUFF_HOVER_DEPTH,
			ns.db.buffHoverPadX or 20, ns.db.buffHoverPadY or 20, entry.frame:GetChildren())
	end
	if not (entry.frame:IsVisible() and entry.frame:IsMouseOver()) then
		return false
	end
	-- Container frames (the action bar holders, status bar managers, the
	-- quest tracker) can cover far more of the screen than their buttons, so
	-- the mouse resting in an empty corner would reveal them. Only count it
	-- when the mouse is on something that belongs to the frame. Chat windows
	-- don't always take the mouse, so they keep the plain rect test.
	if entry.group == "chat" then
		return true
	end
	return IsInside(MouseFocus(), entry.frame)
end

-- Frames the player can choose to show while fighting when staying cinematic
-- in combat (db.combatShow[key], missing = the default here).
ns.COMBAT_SHOW = {
	{ key = "player", label = "Player portrait (and pet)", default = true, frames = { "PlayerFrame", "PetFrame" } },
	{ key = "target", label = "Target", default = true, frames = { "TargetFrame" } },
	{ key = "tot", label = "Target of target", default = true, frames = { "TargetFrameToT" } },
	{ key = "focus", label = "Focus", default = true, frames = { "FocusFrame" } },
	{ key = "buffs", label = "Buffs and debuffs", default = true,
		frames = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" } },
	-- Numbered as retail's Edit Mode numbers them; Classic doesn't number its
	-- bars, so there each also says where it sits.
	{ key = "mainbar", label = "Action bar 1", default = true, frames = { "MainMenuBar", "MainActionBar" } },
	{ key = "bottomleft", label = ns.isRetail and "Action bar 2" or "Action bar 2 (bottom left)", default = true,
		frames = { "MultiBarBottomLeft" } },
	{ key = "bottomright", label = ns.isRetail and "Action bar 3" or "Action bar 3 (bottom right)", default = true,
		frames = { "MultiBarBottomRight" } },
	{ key = "right1", label = ns.isRetail and "Action bar 4" or "Action bar 4 (right)", default = false,
		frames = { "MultiBarRight" } },
	{ key = "right2", label = ns.isRetail and "Action bar 5" or "Action bar 5 (right 2)", default = false,
		frames = { "MultiBarLeft" } },
	-- Retail only (the frames don't exist on Classic, so the rows are skipped).
	{ key = "bar6", label = "Action bar 6", default = false, frames = { "MultiBar5" } },
	{ key = "bar7", label = "Action bar 7", default = false, frames = { "MultiBar6" } },
	{ key = "bar8", label = "Action bar 8", default = false, frames = { "MultiBar7" } },
	{ key = "pet", label = "Pet bar", default = true, frames = { "PetActionBarFrame", "PetActionBar" } },
	{ key = "stance", label = "Stance bar", default = true, frames = { "StanceBarFrame", "StanceBar" } },
	{ key = "totems", label = "Totem bar", default = true, frames = {
		"MultiCastActionBarFrame", "MultiCastSummonSpellButton", "MultiCastRecallSpellButton",
		"MultiCastFlyoutFrame", "MultiCastSlotButton1", "MultiCastSlotButton2",
		"MultiCastSlotButton3", "MultiCastSlotButton4",
		"MultiCastActionPage1", "MultiCastActionPage2", "MultiCastActionPage3", "TotemFrame",
	} },
	{ key = "swing", label = "Swing timer", default = true, retail = false,
		frames = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" } },
	{ key = "micro", label = "Micro menu and bags", default = true,
		frames = { "MicroButtonAndBagsBar", "MicroMenuContainer", "BagsBar" } },
	{ key = "xp", label = "Experience and reputation bars", default = true, frames = {
		"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
		"StatusTrackingBarManager",
	} },
	{ key = "extra", label = "Extra action and zone ability", default = true, retail = true,
		frames = { "ExtraActionBarFrame", "ZoneAbilityFrame" } },
	{ key = "cooldowns", label = "Cooldown Manager", default = false, addon = "Blizzard_CooldownViewer",
		frames = FRAME_GROUPS.cooldowns },
}
-- Then the Other addons, by group (their frames may have no names).
for _, known in ipairs(ns.ADDON_FRAMES) do
	ns.COMBAT_SHOW[#ns.COMBAT_SHOW + 1] = {
		key = "addon:" .. known.key, label = known.short or known.label, default = true, addon = known.addon,
		groups = { "addon:" .. known.key },
	}
end

-- Whether an option belongs on this client, for the options pages to skip
-- the rest: retail = true or false limits it to retail or to Classic clients.
-- Otherwise an option about frames needs one of them to exist. (Frames made
-- later, like the swing timer, are marked by client instead, since the pages
-- are built as the addon loads.)
function ns.OptionAvailable(item)
	if item.retail ~= nil then
		return item.retail == ns.isRetail
	end
	-- (Frames from an addon that loads later don't exist yet.)
	if item.addon then
		return ns.AddOnInstalled(item.addon)
	end
	if item.frames then
		for _, name in ipairs(item.frames) do
			if _G[name] then
				return true
			end
		end
		return false
	end
	return true
end

-- When an enemy is targeted out of combat, a separate list applies
-- (db.targetShow); by default just the target and its target.
local TARGET_SHOW_DEFAULT = { target = true, tot = true }
-- Enemy targeted: also the action bars, buffs and the like.
local ENEMY_SHOW_DEFAULT = {
	player = true, target = true, tot = true, focus = true, buffs = true, mainbar = true, bottomleft = true,
	bottomright = true, pet = true, stance = true, totems = true, micro = true, xp = true, extra = true,
}
-- Other addons' frames too.
for _, known in ipairs(ns.ADDON_FRAMES) do
	ENEMY_SHOW_DEFAULT["addon:" .. known.key] = true
end

function ns.IsCombatShowOn(key)
	local on = ns.db.combatShow[key]
	if on == nil then
		for _, item in ipairs(ns.COMBAT_SHOW) do
			if item.key == key then return item.default end
		end
	end
	return on
end

local function IsListOn(list, key, defaults)
	local on = ns.db[list][key]
	if on == nil then
		return defaults[key] or false
	end
	return on
end

-- Standard Frames page's CineMode column: ticked, a row's frames stay shown all through CineMode.
function ns.IsCineShowOn(key) return ns.db.cineShow[key] or false end
function ns.IsEnemyShowOn(key) return IsListOn("enemyShow", key, ENEMY_SHOW_DEFAULT) end
function ns.IsFriendlyShowOn(key) return IsListOn("friendlyShow", key, TARGET_SHOW_DEFAULT) end

-- Frame names to show right now: only while staying cinematic and fighting
-- (in combat, or with an enemy targeted). Also returns whether the player is
-- actually in combat, since the fast fade-in only applies then.
-- Anything targeted (friend or foe).
local function HasAnyTarget()
	return ns.HasTarget()
end

-- Frame names to show right now, from the Standard Frames page's column that
-- applies: In combat (while staying cinematic), Tar Enemy (out of combat with
-- a living enemy targeted) or Tar Friendly (anything else targeted: friends,
-- NPCs, dead enemies).
-- Rows with CineMode ticked are always in it: they don't fade in CineMode at all.
local function GetCombatShownFrames()
	local inCombat = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	local isOn
	if inCombat then
		if ns.db.stayInCombat then
			isOn = ns.IsCombatShowOn
		end
	elseif HasAnyTarget() then
		if ns.Flag(UnitCanAttack("player", "target")) and not ns.Flag(UnitIsDeadOrGhost("target")) then
			isOn = ns.IsEnemyShowOn
		else
			isOn = ns.IsFriendlyShowOn
		end
	end
	local shown = {}
	for _, item in ipairs(ns.COMBAT_SHOW) do
		if ns.IsCineShowOn(item.key) or (isOn and isOn(item.key)) then
			for _, name in ipairs(item.frames or {}) do
				shown[name] = true
			end
			for _, group in ipairs(item.groups or {}) do
				shown["group:" .. group] = true
			end
		end
	end
	return shown
end

-- Power types that sit empty at rest (rage, runic power) don't count: leftover
-- rage draining after a fight isn't recovering, so only health matters.
local EMPTY_AT_REST = { RAGE = true, RUNIC_POWER = true }

local function IsSecretValue(value)
	return issecretvalue and issecretvalue(value) or false
end

-- Does the player's power count toward recovery? (Yes when unsure.)
local function PowerCounts()
	local _, powerToken = UnitPowerType("player")
	return IsSecretValue(powerToken) or not EMPTY_AT_REST[powerToken]
end

-- Is the player's health or power not at its resting level? Where the values
-- can be read, compare them directly. This client hides current health and
-- power as secret values (even out of combat), so otherwise fall back on the
-- change events: they keep firing every couple of seconds while health or
-- power regenerates (or rage drains) and stop once it's back at rest. The
-- window covers mana's 5-second pause in regeneration after a cast; with no
-- cast that recent, ticks come every 2 seconds, so a shorter wait will do and
-- the portrait starts fading soon after you're full.
local RECOVERY_WINDOW = 6
local TICK_WINDOW = 3
local CAST_PAUSE = 5
local lastVitalsChange = 0
local lastCastAt = -math.huge

-- Fall damage brings the portrait up like a fight does. Health changing while
-- falling or just after landing (the damage arrives a moment later) counts.
local FALL_LANDING_GRACE = 1
local lastFallingAt = -math.huge
local lastFallDamageAt = -math.huge

-- Buff peek: a new or refreshed buff/debuff briefly shows the buffs group.
-- UNIT_AURA says what changed (added, updated, removed) without needing the
-- aura details, which may be secret. Removals and the full refresh at login or
-- zoning don't count. Clients that don't say what changed count every change.
local buffPeekUntil = 0

-- When the player was last in combat (for "only after combat").
local lastCombatAt = -math.huge

-- In combat the update details are secret: lists can't be looked into and the
-- flag can't be tested. A secret list is still present (so something was
-- added or refreshed); a secret flag counts as "not a full refresh".
local function HasEntries(list)
	if issecretvalue and issecretvalue(list) then
		return true
	end
	local ok, hasAny = pcall(function() return list ~= nil and next(list) ~= nil end)
	return ok and hasAny
end

local function IsFullUpdate(flag)
	if issecretvalue and issecretvalue(flag) then
		return false
	end
	return flag == true
end

-- Flights don't peek at buffs: nothing gained on the way matters, and landing
-- adds Honorless Target. So no peek on a flight or just after landing, and
-- Honorless Target never counts.
-- Buffs that never bring the buffs up: the player's list (buffPeekIgnore), spell
-- IDs or names (names match your game language), parsed when it changes.
local ignoredIDs, ignoredNames, ignoredFrom = {}, {}, nil
local function IgnoreLists()
	local text = ns.db.buffPeekIgnore or ""
	if text ~= ignoredFrom then
		ignoredIDs, ignoredNames, ignoredFrom = {}, {}, text
		for entry in text:gmatch("[^,]+") do
			entry = entry:match("^%s*(.-)%s*$")
			local id = tonumber(entry)
			if id then
				ignoredIDs[id] = true
			elseif entry ~= "" then
				ignoredNames[entry:lower()] = true
			end
		end
	end
	return ignoredIDs, ignoredNames
end
local LANDING_QUIET = 5 -- seconds after landing with no buff peek
local landedQuietUntil = 0

-- Called by the flight code on landing.
function ns.OnLandedForBuffs()
	landedQuietUntil = GetTime() + LANDING_QUIET
end

-- One aura's data: on the ignore list? (False when unsure, e.g. secret values.)
local function IsIgnoredAura(aura)
	if type(aura) ~= "table" then
		return false
	end
	local id, name = aura.spellId, aura.name
	if issecretvalue and (issecretvalue(id) or issecretvalue(name)) then
		return false
	end
	local ids, names = IgnoreLists()
	return ids[id] or (type(name) == "string" and names[name:lower()]) or false
end

-- Only ignored auras added (false when unsure).
local function OnlyIgnoredAdded(list)
	if list == nil or (issecretvalue and issecretvalue(list)) then
		return false
	end
	local ok, onlyIgnored = pcall(function()
		local any = false
		for _, aura in pairs(list) do
			any = true
			if not IsIgnoredAura(aura) then
				return false
			end
		end
		return any
	end)
	return ok and onlyIgnored
end

-- Only ignored auras updated (a stack ticking up, say). Updates only give
-- instance IDs, so each is looked up. False when unsure.
local function OnlyIgnoredUpdated(ids)
	if ids == nil or (issecretvalue and issecretvalue(ids))
		or not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then
		return false
	end
	local ok, onlyIgnored = pcall(function()
		local any = false
		for _, instanceID in pairs(ids) do
			any = true
			if not IsIgnoredAura(C_UnitAuras.GetAuraDataByAuraInstanceID("player", instanceID)) then
				return false
			end
		end
		return any
	end)
	return ok and onlyIgnored
end

local auraWatcher = CreateFrame("Frame")
auraWatcher:RegisterUnitEvent("UNIT_AURA", "player")
auraWatcher:SetScript("OnEvent", function(_, _, _, updateInfo)
	if not (ns.db and ns.db.buffPeek) then
		return
	end
	if ns.db.buffPeekAfterCombat and GetTime() - lastCombatAt > ns.db.calmTime then
		return
	end
	-- (wasOnTaxi: landed this instant, before the flight code has noticed.)
	if UnitOnTaxi("player") or ns.wasOnTaxi or GetTime() < landedQuietUntil then
		return
	end
	local changed
	if type(updateInfo) == "table" then
		local added = HasEntries(updateInfo.addedAuras) and not OnlyIgnoredAdded(updateInfo.addedAuras)
		local updated = HasEntries(updateInfo.updatedAuraInstanceIDs)
			and not OnlyIgnoredUpdated(updateInfo.updatedAuraInstanceIDs)
		changed = not IsFullUpdate(updateInfo.isFullUpdate) and (added or updated)
	else
		changed = true
	end
	if changed then
		buffPeekUntil = GetTime() + ns.HoldTime("buffPeekTime")
	end
end)

local vitalsWatcher = CreateFrame("Frame")
vitalsWatcher:RegisterUnitEvent("UNIT_HEALTH", "player")
vitalsWatcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
vitalsWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
vitalsWatcher:SetScript("OnEvent", function(_, event)
	local now = GetTime()
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		lastCastAt = now
		return
	end
	if event == "UNIT_POWER_UPDATE" and not PowerCounts() then
		return
	end
	if event == "UNIT_HEALTH" and (ns.Flag(IsFalling()) or now - lastFallingAt <= FALL_LANDING_GRACE) then
		lastFallDamageAt = now
	end
	lastVitalsChange = now
end)

local function IsPlayerRecovering()
	local health, maxHealth = UnitHealth("player"), UnitHealthMax("player")
	local countPower = PowerCounts()
	local power, maxPower = UnitPower("player"), UnitPowerMax("player")
	if IsSecretValue(health) or IsSecretValue(maxHealth)
		or (countPower and (IsSecretValue(power) or IsSecretValue(maxPower))) then
		local now = GetTime()
		local window = now - lastCastAt < CAST_PAUSE + TICK_WINDOW and RECOVERY_WINDOW or TICK_WINDOW
		return now - lastVitalsChange < window
	end
	if maxHealth > 0 and health < maxHealth then
		return true
	end
	return countPower and maxPower > 0 and power < maxPower
end

ns.IsPlayerRecovering = IsPlayerRecovering
ns.GetSecondsSinceVitalsChange = function() return GetTime() - lastVitalsChange end

-- How long a group stays after the mouse leaves it: its own setting when it
-- overrides the shared one, otherwise the shared "stays after mouseover".
local function HoverHoldKey(group)
	if ns.db[group .. "HoverOverride"] then
		return group .. "HoverHold"
	end
	return "mouseoverHold"
end
local hoverHeldUntil = {}

local DEATH_FADE_TIME = 0.5 -- seconds for the UI to go when you die (death camera)

function ns.UpdateFrames(cinematic, elapsed)
	local now = GetTime()
	local combatShown
	if cinematic then
		combatShown = GetCombatShownFrames()
	end
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		lastCombatAt = now
	end
	if ns.Flag(IsFalling()) then
		lastFallingAt = now
	end
	local portraitAllowed = ns.db.portraitWhenNotFull and (not ns.db.portraitAfterCombat
		or now - math.max(lastCombatAt, lastFallDamageAt) < ns.db.calmTime)
	if ns.IsChatActive() then
		ns.chatTypingUntil = now + ns.HoldTime("chatPeekTime")
	end
	local typing = ns.chatTypingUntil > now
	-- Chat stays put when it isn't faded at all, or in a place chosen under
	-- "Always show in" (Chat page).
	local place = ns.GetOptionPlace()
	local fadeChat = not (place and ns.db[ns.CHAT_IN[place]])
	local keepMinimapForTracking = ns.IsKeepingMinimapForTracking(now)
	-- Work out which groups are hovered so the whole group reveals together.
	local hovered = {}
	if cinematic and ns.db.mouseover then
		for _, entry in ipairs(ns.managed) do
			if ns.IsEntryHovered(entry) then
				hovered[entry.group] = true
			end
		end
		-- Groups linger after the mouse leaves. The hold time counts the fade
		-- out, so a group is gone that long after the mouse leaves; a hold
		-- shorter than the fade just starts the fade straight away.
		for group in pairs(hovered) do
			local hold = ns.HoldTime(HoverHoldKey(group)) - ns.db.fadeOutTime
			hoverHeldUntil[group] = now + math.max(0, hold)
		end
		for group, untilTime in pairs(hoverHeldUntil) do
			if untilTime > now then
				hovered[group] = true
			end
		end
	end

	-- "Except when standing still or flying": tracking doesn't hold the minimap
	-- open on flights or once you've stood still for the standing-still delay.
	-- Nor in the places ticked under "Except in" (cities and the like).
	-- Dead, with the death camera watching: everything goes, quickly, whatever
	-- would normally keep it up (the release button is a popup: it stays).
	local deathFade = cinematic and ns.IsDeathCinematic and ns.IsDeathCinematic()

	local trackingPaused = ns.IsTrackingOffHere()
	if not trackingPaused and ns.db.trackingHideWhenIdle then
		local stillSince = ns.GetStillSince()
		trackingPaused = UnitOnTaxi("player")
			or (stillSince ~= nil and now - stillSince >= ns.db.idleOrbitDelay)
	end

	for _, entry in ipairs(ns.managed) do
		local target = 1
		local chatShowing = (ns.chatPeekUntil[entry.frame] or 0) > now
			or (typing and entry.group == "chat")
		local tracking = ((ns.db.alwaysShowMinimap
				or (ns.db.minimapForTracking and keepMinimapForTracking and not trackingPaused))
			and entry.group == "minimap")
			or (ns.db.alwaysShowWaypoint and entry.group == "waypoint")
		local listShown = combatShown
			and (entry.name and combatShown[entry.name] or combatShown["group:" .. entry.group])
		local fightingShown = listShown
		if not fightingShown and entry.group == "buffs" and cinematic and buffPeekUntil > now then
			fightingShown = true -- new or refreshed aura: show buffs briefly, normal fade speeds
		end
		if not fightingShown and entry.name == "PlayerFrame" and cinematic
			and portraitAllowed and IsPlayerRecovering() then
			fightingShown = true -- shown like a combat frame, at the normal fade speeds
		end
		if cinematic and not hovered[entry.group] and not chatShowing and not tracking
			and not fightingShown and (fadeChat or entry.group ~= "chat") then
			target = 0
		end
		if deathFade and not (typing and entry.group == "chat") then
			target = 0
		end
		if typing and entry.group == "chat" and entry.alpha < 1 then
			-- Pressing Enter shows the chat input (and its window) at once.
			ns.SetEntryAlpha(entry, 1)
		-- Keep re-applying 0 while hidden in case Blizzard code resets the alpha;
		-- once fully revealed, leave the frame alone.
		elseif entry.alpha ~= target or target == 0 or entry.shrunk then
			local duration
			if target > entry.alpha then
				duration = ns.db.fadeInTime
			else
				duration = deathFade and DEATH_FADE_TIME or ns.db.fadeOutTime
			end
			ns.SetEntryAlpha(entry, ns.Approach(entry.alpha, target, elapsed, duration))
		end
	end
end

-- Frames beyond the built-in list (and built-in ones kept up): added ones (including auto-matched) and
-- ones the player chose to stop fading. Sorted for stable display.
-- Lists saved names rather than managed frames, so frames that don't exist
-- yet (created later in the session) still show.
function ns.GetExtraFrames()
	local faded, ignored = {}, {}
	for name in pairs(ns.db.extraFrames) do
		faded[#faded + 1] = name
	end
	for name in pairs(ns.db.ignoredFrames) do
		ignored[#ignored + 1] = name -- (built-in frames kept with /cine keep too)
	end
	table.sort(faded)
	table.sort(ignored)
	return faded, ignored
end

function ns.StopFading(name)
	ns.db.extraFrames[name] = nil
	ns.db.ignoredFrames[name] = true
	if _G[name] then RemoveFrame(_G[name]) end
end

-- Built-in and auto-matched frames come back on the next scan.
function ns.UnignoreFrame(name)
	ns.db.ignoredFrames[name] = nil
end

-- Drops a frame from the extras list altogether: an added one stops fading
-- (without being remembered as stopped), a stopped one is no longer ignored.
function ns.ForgetExtraFrame(name)
	if ns.db.extraFrames[name] and _G[name] then RemoveFrame(_G[name]) end
	ns.db.extraFrames[name] = nil
	ns.db.ignoredFrames[name] = nil
end

-- Frames that don't take the mouse (the Cooldown Manager's icons, many
-- addons' bars) are invisible to GetMouseFoci, so failing that, the smallest
-- named, shown top-level frame the cursor is over. Smallest, so a frame
-- covering the whole screen doesn't win over the one actually being pointed at.
local function GetTopLevelFrameUnderCursor()
	local best, bestArea
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if not IsForbidden(frame) and frame ~= ns.letterbox and frame:GetName()
			and frame:IsVisible() and frame:IsMouseOver() then
			local width, height = frame:GetSize()
			local area = (width or 0) * (height or 0)
			if area > 0 and (not bestArea or area < bestArea) then
				best, bestArea = frame, area
			end
		end
	end
	return best
end

-- The top-level (direct child of UIParent) frame under the cursor, so adding
-- e.g. a damage meter's bar picks up the whole meter window.
local function GetTopLevelFrameUnderMouse()
	local focus = MouseFocus()
	while focus and focus ~= UIParent do
		local parent = focus:GetParent()
		if parent == UIParent or parent == nil then
			if focus:GetName() then
				return focus
			end
			break
		end
		focus = parent
	end
	return GetTopLevelFrameUnderCursor()
end

-- name: a frame's global name (/cine add <name>), for frames that are hard
-- to hover; nil to use the one under the mouse.
function ns.AddUnderMouse(name)
	local frame
	if name and name ~= "" then
		frame = _G[name]
		if not IsFrame(frame) then
			ns.Print("no frame called " .. name .. " (frame names are case-sensitive; /fstack shows them).")
			return
		end
	else
		frame = GetTopLevelFrameUnderMouse()
		name = frame and frame:GetName()
	end
	if not name then
		ns.Print("hover over a named UI element, then type /cine add and press Enter " ..
			"(or /cine add <FrameName>). Frames without a name can't be added: the 3rd Party Frames " ..
			"settings page lists the addons faded out of the box.")
		return
	end
	if IsWindow(frame, name) then
		ns.Print(name .. " is a window, so it isn't faded (it would stay there invisible). " ..
			"Move the mouse off it onto the frame you want, then try again.")
		return
	end
	for _, entry in ipairs(ns.managed) do
		if entry.frame == frame and not entry.group:find("^extra:") then
			ns.Print(name .. " is already faded as part of the built-in \"" .. entry.group .. "\" group.")
			return
		end
	end
	ns.db.ignoredFrames[name] = nil
	ns.db.extraFrames[name] = true
	AddFrame(frame, "extra:" .. name)
	ns.Print("now fading " .. name)
end

function ns.RemoveUnderMouse()
	local frame = GetTopLevelFrameUnderMouse()
	local name = frame and frame:GetName()
	if not name then
		ns.Print("hover over a faded UI element, then type /cine keep and press Enter.")
		return
	end
	ns.StopFading(name)
	ns.Print(name .. " will always be shown (undo under Custom frames on the 3rd Party Frames options page).")
end

function ns.ListExtras()
	local faded, ignored = ns.GetExtraFrames()
	for _, name in ipairs(faded) do ns.Print("fading " .. name) end
	for _, name in ipairs(ignored) do ns.Print("ignoring " .. name) end
	if #faded + #ignored == 0 then
		ns.Print("no extra frames.")
	end
end
