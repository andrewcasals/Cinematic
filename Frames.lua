-- Cinematic: the frames that fade. The built-in fade list, fading and
-- nesting, the minimap shrink, scanning for frames created later, the Issue
-- Reporter, hover, and the 3rd Party Frames page's lists.
local ADDON_NAME, ns = ...
local L = ns.L

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
		-- The leave vehicle / stop flight button: in the main bar, unless an
		-- action bar addon moves it out (EllesmereUI does).
		"MainMenuBarVehicleLeaveButton",
	},
	sidebars = { "MultiBarLeft", "MultiBarRight" },
	player = { "PlayerFrame", "PetFrame", "TotemFrame" },
	-- The personal resource bars (health, power and class resources under
	-- your character). Retail's is a frame placed in Edit Mode, which the
	-- game only shows or hides, never its alpha; Forever's is your own
	-- nameplate, so a stand-in fades for it (see below).
	prd = { "PersonalResourceDisplayFrame", "CinematicPersonalResource" },
	totems = {
		"MultiCastActionBarFrame", "MultiCastSummonSpellButton", "MultiCastRecallSpellButton",
		"MultiCastFlyoutFrame", "MultiCastSlotButton1", "MultiCastSlotButton2",
		"MultiCastSlotButton3", "MultiCastSlotButton4",
		"MultiCastActionPage1", "MultiCastActionPage2", "MultiCastActionPage3",
	},
	target = { "TargetFrame", "TargetFrameToT", "FocusFrame" },
	-- The party frames when they aren't raid-style (portraits down the left,
	-- their pets' with them): Classic's by name; retail's are found in
	-- PartyFrame (see ScanPartyFrames).
	party = {
		"PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
		"PartyMemberBackground",
	},
	-- In a group, the tab at the left edge and the panel it opens. (The raid
	-- frames themselves, raidplayers and raidpets, are found by ScanRaidFrames.)
	raidmanager = { "CompactRaidFrameManager" },
	-- In battlegrounds, the flag carriers' frames (the arena enemy frames, reused).
	flags = { "ArenaEnemyFramesContainer" },
	-- (With the queue eyes for the dungeon finder and battlegrounds, which can
	-- sit outside the minimap: named differently by client.)
	minimap = {
		"MinimapCluster", "Minimap", "GameTimeFrame", "CinematicMinimapButton",
		"LFGMinimapFrame", "MiniMapLFGFrame", "QueueStatusMinimapButton", "MiniMapBattlefieldFrame",
	},
	buffs = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" },
	quests = { "QuestWatchFrame", "WatchFrame", "ObjectiveTrackerFrame" },
	-- Classic's quest timer box: its own group, so it can stay up without the tracker.
	questtimer = { "QuestTimerFrame" },
	misc = { "DurabilityFrame" },
	swing = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" },
	-- Your cast bars: retail's, Classic's, the pet's (vehicles, mind control)
	-- and Forever's in gamepad mode. (Target and focus cast bars sit inside
	-- their unit frames and fade with them.)
	castbar = {
		"PlayerCastingBarFrame", "OverlayPlayerCastingBarFrame", "CastingBarFrame", "PetCastingBarFrame",
		"GamepadPlayerCastingBarFrame",
	},
	meters = { "DamageMeter" },
	-- The Cooldown Manager (retail and Forever). Made when its addon loads,
	-- so a later scan picks it up.
	cooldowns = {
		"EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer",
	},
	-- Retail's quest waypoint: the marker in the world, with its distance,
	-- that shows where a tracked quest or map pin is.
	waypoint = { "SuperTrackedFrame" },
	-- WoW Forever's gamepad mode: its action bars, the button hints top left
	-- and the aiming dot in the middle of the screen.
	gamepadbars = { "GamepadMainActionBarFrame" },
	gamepadlegend = { "GamepadPersistentInputLegend" },
	gamepadreticle = { "GamepadReticle" },
	-- Action bar art from addons (Bartender4's art bar); the game's own is
	-- found by FindBarArt.
	barart = {},
	chat = {
		"GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
		"QuickJoinToastButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
	},
}

-- Forever's personal resource bars are your own nameplate, which comes and
-- goes as the game likes: this stand-in fades with the row instead, and the
-- plate takes its alpha (ns.SetPersonalPlateAlpha, Effects). (Clients with
-- no personal resource display have no setting for it.)
local personalStandIn
if not ns.isRetail and GetCVar("nameplateShowSelf") ~= nil then
	personalStandIn = CreateFrame("Frame", "CinematicPersonalResource", UIParent)
end

-- The queue eye (dungeon finder, battlegrounds): Forever pins it to the
-- minimap, retail puts it beside the micro menu, so it goes with either.
table.insert(FRAME_GROUPS[ns.isRetail and "bars" or "minimap"], "QueueStatusButton")

local function AddName(list, name)
	for _, existing in ipairs(list) do
		if existing == name then
			return
		end
	end
	list[#list + 1] = name
end

-- Top-level frames whose names contain any of these are faded too. This picks
-- up client features (and addons) whose exact frame names vary, like the
-- built-in damage meter and swing timer.
local AUTO_PATTERNS = { DamageMeter = "meters", SwingTimer = "swing" }
ns.SCAN_INTERVAL = 5

-- Other addons' frames: ns.ADDON_FRAMES (AddonSupport.lua), filled by Support/.

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
-- (The party frames dim members out of range.)
local OWN_ALPHA = {
	chat = true, waypoint = true, cooldowns = true, raidplayers = true, raidpets = true, party = true,
}
-- Parts of the raid frames with rows of their own (role icons, names, group
-- titles, buffs, debuffs and the threat highlight). They sit inside the frames
-- they're part of but fade apart from them (not nested), and they don't take
-- the mouse: hovering the raid frames brings them up (their Mouseover group).
local PART_GROUPS = {
	raidroles = true, raidnames = true, raidpetnames = true, raidtitles = true, raidbuffs = true, raiddebuffs = true,
	raidthreat = true, partyroles = true, partynames = true,
}
-- Parts that go only while a row's frames are up (part -> row): the "Party"
-- title sits in no faded frame (the party members fade one by one), so its
-- Always tick would leave it alone on screen.
local followsRow = {}

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

-- How far a frame's alpha can read back from what was set (it's stored with
-- less precision) before it counts as the frame setting its own.
local ALPHA_SLACK = 0.005

-- For frames that set their own alpha (see AddFrame): one now at something
-- other than what was last applied set it itself, so take that as its new
-- base alpha and fade relative to it. Checked before every change too, or
-- an alpha it set since would be written over unseen and its new base lost
-- (EllesmereUI's bars start at 0 and come up a moment after login).
-- An alpha set from a secret value reads back secret (EllesmereUI's
-- show-when-health-missing): it can't be compared, so ours just goes back.
-- /cine debug alpha: report frames setting their own alpha (at most twice a
-- second each), to track down one flashing up.
local alphaReportedAt = {}
local function ReportOwnAlpha(entry, alpha, how)
	if not ns.alphaWatch then
		return
	end
	local now = GetTime()
	if (alphaReportedAt[entry.frame] or 0) > now - 0.5 then
		return
	end
	alphaReportedAt[entry.frame] = now
	local shown = (issecretvalue and issecretvalue(alpha)) and "secret" or ("%.2f"):format(alpha)
	ns.Print(("%s [%s] set its alpha to %s (ours %.2f, %s)"):format(entry.name or entry.frame:GetDebugName(),
		entry.group, shown, entry.applied or -1, how))
end

-- (Second result: the alpha it set reads back secret.)
local function TakeOwnAlpha(entry)
	local alpha = entry.frame:GetAlpha()
	if issecretvalue and issecretvalue(alpha) then
		ReportOwnAlpha(entry, alpha, "seen")
		return true, true
	elseif math.abs(alpha - entry.applied) > ALPHA_SLACK then
		ReportOwnAlpha(entry, alpha, "seen")
		entry.baseAlpha = alpha
		return true
	end
	return false
end

-- Parts of a raid frame that ignore its alpha (the outline round your
-- target's frame, which stays bright when out of range dims the rest): found
-- once per frame, a few levels down (a group's frame holds its members').
local LOOSE_PART_GROUPS = { raidplayers = true, raidpets = true }
local function LooseParts(frame, depth, found)
	found = found or {}
	for _, region in ipairs({ frame:GetRegions() }) do
		local ignoring = region.IsIgnoringParentAlpha and region:IsIgnoringParentAlpha()
		-- (A secret answer counts as no.)
		if not (issecretvalue and issecretvalue(ignoring)) and ignoring then
			found[#found + 1] = region
		end
	end
	if depth > 0 then
		for _, child in ipairs({ frame:GetChildren() }) do
			if not (child.IsForbidden and child:IsForbidden()) then
				LooseParts(child, depth - 1, found)
			end
		end
	end
	return found
end

-- Those parts follow the fade too, back to their own alpha once it's over.
-- (Not ones with a row of their own, like the threat highlight: they fade as
-- that, and may have been found before they got it.)
local function FadeLooseParts(entry, alpha)
	entry.looseParts = entry.looseParts or LooseParts(entry.frame, 2)
	for _, part in ipairs(entry.looseParts) do
		if seen[part] then
			part.cinematicAlpha = nil
		elseif alpha < 1 then
			if not part.cinematicAlpha then
				local own = part:GetAlpha()
				part.cinematicAlpha = (issecretvalue and issecretvalue(own)) and 1 or own
			end
			part:SetAlpha(alpha * part.cinematicAlpha)
		elseif part.cinematicAlpha then
			part:SetAlpha(part.cinematicAlpha)
			part.cinematicAlpha = nil
		end
	end
end

local function ApplyAlpha(entry)
	local secret
	if entry.ownAlpha then
		secret = select(2, TakeOwnAlpha(entry))
	end
	local visual = VisualAlpha(entry)
	-- The raid frames dim members out of range with an alpha that reads back
	-- secret on retail: it can't be faded relative to, but while they're
	-- fully up it's left as it is (written over, every member looked in range).
	if not (secret and visual == 1 and LOOSE_PART_GROUPS[entry.group]) then
		entry.applied = visual * (entry.baseAlpha or 1)
		-- (The cast bar while it shows Fishing is kept hidden: hideFishingCastBar, Camera.)
		if entry.frame.cinematicFishingHidden then
			entry.applied = 0
		end
		entry.settingAlpha = true
		entry.frame:SetAlpha(entry.applied)
		entry.settingAlpha = false
		if ns.profiling then
			ns.ProfileCount("SetAlpha on faded frames")
		end
	end
	if LOOSE_PART_GROUPS[entry.group] then
		FadeLooseParts(entry, visual)
	end
end

-- A faded frame's alpha put back if something (Blizzard code, say) changed it.
local function ReapplyIfChanged(entry)
	local alpha = entry.frame:GetAlpha()
	if (issecretvalue and issecretvalue(alpha)) or math.abs(alpha - (entry.applied or -1)) > ALPHA_SLACK then
		ApplyAlpha(entry)
	end
end
ReapplyIfChanged = ns.Profiled("ReapplyIfChanged", ReapplyIfChanged)

local function SyncOwnAlpha(entry)
	if TakeOwnAlpha(entry) then
		ApplyAlpha(entry)
	end
end

-- The cast bars set themselves to full alpha as each cast starts, so while
-- faded they'd flash up until the next tick put ours back. Their own events
-- (and showing) are followed by ours straight away instead. Script hooks,
-- not method hooks (see AddFrame); one for a frame no longer faded does
-- nothing. Once fully shown they're left alone, so their own fade-out as a
-- cast ends still plays.
-- (One local for all of it: the file is near Lua's 200 locals.)
-- entries: frame -> its entry while managed (false once not); fades: frame -> its fade animations.
local castBars = { entries = {}, fades = {}, none = {} }
-- A fade animation can't be stopped as it starts (see onFadeAnim): one left
-- over would carry on once the bar shows again, and a cast started soon after
-- another was stopped flashed up. So they're stopped after the bar's own
-- events, as it shows and as it updates.
function castBars.StopFades(frame)
	for _, group in ipairs(castBars.fades[frame] or castBars.none) do
		if ns.Flag(group:IsPlaying()) then
			group:Stop()
		end
	end
end
-- A bar finishing while faded doesn't hide itself: it hides at the end of its
-- fade-out, which the game skips for a bar at alpha 0 (as at every login and
-- /reload, where it "finishes" the cast you aren't making). It then showed,
-- full, once the UI came back. So a faded bar with nothing being cast is
-- hidden, as that fade would have. (Not in Edit Mode, which shows the bar.)
function castBars.HideIfIdle(frame)
	if frame.casting or frame.channeling or frame.reverseChanneling or frame.isInEditMode
		or not ns.Flag(frame:IsShown()) then
		return
	end
	frame:Hide()
end
function ns.ReapplyCastBar(frame)
	local entry = castBars.entries[frame]
	if entry and entry.alpha < 1 then
		castBars.StopFades(frame)
		ApplyAlpha(entry)
		castBars.HideIfIdle(frame)
	end
end
-- (Camera's Fishing cast bar hiding calls it too, after setting the bar's alpha itself.)
castBars.onScript = ns.Profiled("Cast bar fade hook", ns.ReapplyCastBar)
-- And after each of their updates while shown, before they're drawn: a bar
-- can be shown and set to full alpha by something other than its own events
-- (it flashed up as some casts started until the next tick).
castBars.onUpdate = ns.Profiled("Cast bar update hook", function(frame)
	local entry = castBars.entries[frame]
	if entry and entry.alpha < 1 then
		castBars.StopFades(frame)
		ReapplyIfChanged(entry)
		castBars.HideIfIdle(frame)
	end
end)

-- Their fade-out as a cast ends, or is interrupted (held a moment first), is
-- an alpha animation, which shows them whatever alpha they're set to: an
-- interrupted cast stayed up. While faded the bar is hidden instead, as at the
-- animation's end, and the animation stopped once its start is over (see
-- StopFades). (Not in Edit Mode, which shows the bar.)
castBars.onFadeAnim = ns.Profiled("Cast bar fade animation", function(group)
	local frame = group:GetParent()
	local entry = castBars.entries[frame]
	if not entry or entry.alpha >= 1 then
		return
	end
	local editMode = _G.EditModeManagerFrame
	if editMode and editMode.IsEditModeActive and ns.Flag(editMode:IsEditModeActive()) then
		return
	end
	frame:Hide()
end)

-- Whether an animation group fades the bar itself (not its spark, glow and the like).
function castBars.FadesFrame(group, frame)
	for _, anim in ipairs({ group:GetAnimations() }) do
		if anim:GetObjectType() == "Alpha" and (anim:GetTarget() or group:GetParent()) == frame then
			return true
		end
	end
	return false
end

function castBars.Hook(entry)
	local frame = entry.frame
	if castBars.entries[frame] == nil and frame.HookScript then
		frame:HookScript("OnEvent", castBars.onScript)
		frame:HookScript("OnShow", castBars.onScript)
		frame:HookScript("OnUpdate", castBars.onUpdate)
		if frame.GetAnimationGroups then
			for _, group in ipairs({ frame:GetAnimationGroups() }) do
				local ok, fades = pcall(castBars.FadesFrame, group, frame)
				if ok and fades then
					group:HookScript("OnPlay", castBars.onFadeAnim)
					castBars.fades[frame] = castBars.fades[frame] or {}
					table.insert(castBars.fades[frame], group)
				end
			end
		end
	end
	castBars.entries[frame] = entry
end

-- Some addons set their own frames' alpha all the time (EllesmereUI: target
-- changes, combat, mouseover), and a frame caught at that alpha even for a
-- moment flashes up. So their frames (only those: never the game's, whose own
-- calls a hook would get in the way of) have SetAlpha followed straight away by
-- ours, taking what it set as the new base. A hook can't be taken off: one
-- for a frame no longer faded does nothing.
local alphaHooked = {} -- frame -> its entry while managed (false once not)

local OnOwnSetAlpha = ns.Profiled("Own SetAlpha hook", function(frame, alpha)
	local entry = alphaHooked[frame]
	if not entry or entry.settingAlpha then
		return
	end
	if (issecretvalue and issecretvalue(alpha)) or math.abs(alpha - (entry.applied or -1)) > ALPHA_SLACK then
		ReportOwnAlpha(entry, alpha, "hooked")
	end
	if not (issecretvalue and issecretvalue(alpha)) then
		entry.baseAlpha = alpha
	end
	entry.applied = alpha -- (so ApplyAlpha doesn't take it again)
	ApplyAlpha(entry)
end)

local function HookOwnAlpha(entry)
	if alphaHooked[entry.frame] == nil then
		hooksecurefunc(entry.frame, "SetAlpha", OnOwnSetAlpha)
	end
	alphaHooked[entry.frame] = entry
end

-- What supported addons' setups (Support/) ask for, filled only once the
-- addon has loaded. Frames that set their own alpha (by name, or the frame
-- itself for unnamed ones), those of them hooked as well, and game frames an
-- addon hides for good (fading them in again would bring them back).
local ownAlphaNames, ownAlphaFrames = {}, {}
local hookedNames, hookedFrames = {}, {}
local leftAlone = {}
-- 3rd Party Frames groups hooked (hookAlpha), from their rows.
local HOOKED_GROUPS = {}
for _, known in ipairs(ns.ADDON_FRAMES) do
	if known.hookAlpha then
		HOOKED_GROUPS["addon:" .. known.key] = true
	end
end

-- The options pages' master switches (handle<...>, all on to start with):
-- off, the frames in their groups aren't faded (let go, their own alpha
-- back). The Standard Frames page's covers every built-in group but the chat
-- and gamepad ones (their own pages'); the page switches below it come on
-- top. The 3rd Party Frames page's covers other addons' and added frames.
local GROUP_SWITCH = {
	minimap = "handleMinimap", quests = "handleQuests", questtimer = "handleQuests", waypoint = "handleQuests",
	buffs = "handleBuffs", cooldowns = "handleCooldowns", chat = "handleChat", swing = "handleSwing",
	gamepadbars = "handleGamepad", gamepadlegend = "handleGamepad", gamepadreticle = "handleGamepad",
}
local OWN_PAGE_GROUPS = { chat = true, gamepadbars = true, gamepadlegend = true, gamepadreticle = true }
ns.HANDLE_SWITCHES = {
	"handleFrames", "handleAddonFrames", "handleGamepad", "handleMinimap", "handleQuests", "handleBuffs",
	"handleCooldowns", "handleChat", "handleSwing",
}
local function GroupHandled(group)
	local db = ns.db
	if group:find("^addon:") or group:find("^extra:") then
		return db.handleAddonFrames and true or false
	end
	if not OWN_PAGE_GROUPS[group] and not db.handleFrames then
		return false
	end
	local switch = GROUP_SWITCH[group]
	return not switch or (db[switch] and true or false)
end
ns.GroupHandled = GroupHandled

local function AddFrame(frame, group)
	if not frame or seen[frame] or not frame.SetAlpha or frame == ns.letterbox then
		return false
	end
	if frame.IsForbidden and frame:IsForbidden() then
		return false
	end
	local name = frame:GetName()
	if name and (ns.db.ignoredFrames[name] or leftAlone[name]) then
		return false
	end
	-- (Its page's master switch off: left alone.)
	if not GroupHandled(group) then
		return false
	end
	seen[frame] = true
	local entry = {
		frame = frame, name = name, group = group, alpha = 1,
		shrinkWhenFaded = frame == Minimap,
	}
	ns.managed[#ns.managed + 1] = entry
	-- (Cast bars too, so their row alone decides: see castBars.)
	if (group == "questtimer" or group == "castbar") and frame.SetIgnoreParentAlpha then
		frame:SetIgnoreParentAlpha(true)
	end
	if group == "castbar" then
		castBars.Hook(entry)
	end
	-- Classic clients' raid frames sit inside the Raid Frame Manager: they
	-- don't fade with it (their own rows fade them).
	local raidFrames = _G.CompactRaidFrameContainer
	if group == "raidmanager" and raidFrames and raidFrames.SetIgnoreParentAlpha
		and raidFrames:GetParent() == frame then
		raidFrames:SetIgnoreParentAlpha(true)
	end
	-- Classic clients' pet frame sits inside the player frame: it fades on its
	-- own, so an unhappy pet can stay up while the portrait goes.
	if name == "PetFrame" and frame.SetIgnoreParentAlpha and frame:GetParent() == _G.PlayerFrame then
		frame:SetIgnoreParentAlpha(true)
	end

	-- Chat frames manage their own alpha (the input bar sits faint until you
	-- press Enter), and so do the waypoint (it dims as you look past it), the
	-- Cooldown Manager (its opacity setting) and other addons' frames (their
	-- own fades). Track the alpha last asked for, fade relative to it, and
	-- return to it rather than to fully opaque. Watched each frame rather than
	-- by hooking SetAlpha: hooking a game frame's methods breaks the game's
	-- own calls to them ("attempt to call a nil value"). Some addons' own
	-- frames are hooked as well (see HookOwnAlpha).
	local hooked = (name and hookedNames[name]) or hookedFrames[frame] or HOOKED_GROUPS[group]
	if hooked or OWN_ALPHA[group] or group:find("^addon:") or (name and ownAlphaNames[name])
		or ownAlphaFrames[frame] then
		local alpha = frame:GetAlpha()
		entry.baseAlpha = (issecretvalue and issecretvalue(alpha)) and 1 or alpha
		entry.applied = entry.baseAlpha
		entry.ownAlpha = true
		if hooked then
			HookOwnAlpha(entry)
		end
	end
	return true
end

-- Frames that fade on their own even though they sit inside another faded
-- frame, so they can be shown separately (target of target during combat).
-- The quest timer can sit inside the quest tracker: it ignores the tracker's
-- fade (see AddFrame) so it can stay up while the tracker is faded.
-- The cast bars too (retail's can be locked to the player frame).
local NEVER_NESTED = { TargetFrameToT = true, QuestTimerFrame = true }
for _, name in ipairs(FRAME_GROUPS.castbar) do
	NEVER_NESTED[name] = true
end

local function RecomputeNesting()
	for _, entry in ipairs(ns.managed) do
		local nested = false
		local frame = entry.frame
		local parent = frame:GetParent()
		while parent and parent ~= UIParent and not NEVER_NESTED[entry.name] and not PART_GROUPS[entry.group] do
			-- (A parent's fade doesn't reach through a frame ignoring it.)
			local ignoring = frame.IsIgnoringParentAlpha and frame:IsIgnoringParentAlpha()
			if not (issecretvalue and issecretvalue(ignoring)) and ignoring then
				break
			end
			if seen[parent] then
				nested = true
				break
			end
			frame, parent = parent, parent:GetParent()
		end
		if nested ~= (entry.nested or false) then
			entry.nested = nested
			ApplyAlpha(entry)
		end
	end
end

-- The minimap's size can't change in combat if an addon put a secure button
-- on it (that makes it protected): the shrink waits for the fight to end.
function ns.ScaleBlocked(frame)
	return InCombatLockdown() and ns.Flag(frame:IsProtected())
end

local function RemoveFrame(frame)
	for i, entry in ipairs(ns.managed) do
		if entry.frame == frame then
			if alphaHooked[frame] then
				alphaHooked[frame] = false
			end
			if castBars.entries[frame] then
				castBars.entries[frame] = false
			end
			frame:SetAlpha(frame.cinematicFishingHidden and 0 or entry.baseAlpha or 1)
			if entry.looseParts then FadeLooseParts(entry, 1) end
			if entry.shrunk and ns.ScaleBlocked(frame) then
				local scale = entry.savedScale or 1
				local waiter = CreateFrame("Frame")
				waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
				waiter:SetScript("OnEvent", function(self)
					self:UnregisterAllEvents()
					frame:SetScale(scale)
				end)
			elseif entry.shrunk then
				frame:SetScale(entry.savedScale or 1)
			end
			table.remove(ns.managed, i)
			entry.removed = true -- (for script hooks still holding it: see HookPartyScripts)
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
		if known.loaded and ns.IsAddonFramesOn(known.key) then
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

-- The Issue Reporter's text is never in a frame this big. Unpacking a frame
-- with thousands of regions (EllesmereUI's unlock-mode tools) overflows the
-- Lua stack in the game's GetRegions: a client crash pcall can't catch.
local MAX_PARTS = 100
local COUNT_METHOD = { GetRegions = "GetNumRegions", GetChildren = "GetNumChildren" }

-- A frame's regions or children as a list, or nil when it's off limits:
-- a frame that isn't forbidden itself can still hold forbidden parts, and
-- then GetRegions/GetChildren error. Frames with too many parts are skipped.
local function ReadParts(frame, method)
	local countMethod = frame[COUNT_METHOD[method]]
	if type(countMethod) ~= "function" then
		return nil
	end
	local ok, count = pcall(countMethod, frame)
	if not ok or type(count) ~= "number" or count > MAX_PARTS then
		return nil
	end
	local parts = { pcall(frame[method], frame) }
	if not table.remove(parts, 1) then
		return nil
	end
	return parts
end

-- Hidden frames are skipped: a hidden reporter gets found by a later scan once
-- it shows, and addons build pages off-screen in hidden frames (EllesmereUI's
-- search index), which crash the client when read mid-build.
local function HasIssueReporterText(frame, depth)
	if IsForbidden(frame) or not ns.Flag(frame:IsShown()) then
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

-- Action bar 1's art (the Standard Frames page's Action bar art row): the
-- end caps and the bar the buttons sit on, by name on older clients and by
-- parentKey on newer ones. The pieces are textures (which the fade's frame
-- code can't take), so a frame of ours over the bar stands in for them in
-- the fade, and its alpha is copied onto them. They ignore the bar's own
-- alpha, so they can stay up while its buttons fade, or the other way round.
local BAR_ART_NAMES = {
	"MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarArtFrameBackground",
	"MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
}
local BAR_ART_KEYS = {
	MainMenuBarArtFrame = { "LeftEndCap", "RightEndCap" },
	MainMenuBar = { "EndCaps", "BorderArt" },
	MainActionBar = { "EndCaps", "BorderArt" },
}
local barArt, barArtSeen = {}, {}
local artStandIn

local function AddBarArt(region)
	if type(region) ~= "table" or barArtSeen[region] or type(region.SetAlpha) ~= "function"
		or IsForbidden(region) then
		return
	end
	-- (A bar an addon took over is left alone, its art with it.)
	local bar = TopLevelAncestor(region)
	if bar and bar:GetName() and leftAlone[bar:GetName()] then
		return
	end
	barArtSeen[region] = true
	barArt[#barArt + 1] = { region = region, bar = bar and bar:GetName() }
	if region.SetIgnoreParentAlpha then
		region:SetIgnoreParentAlpha(true)
	end
	if not artStandIn then
		artStandIn = CreateFrame("Frame", nil, UIParent)
		artStandIn:SetAllPoints(bar or region)
		hooksecurefunc(artStandIn, "SetAlpha", function(_, alpha)
			for _, art in ipairs(barArt) do
				art.region:SetAlpha(alpha)
			end
		end)
	end
	region:SetAlpha(artStandIn:GetAlpha())
end

local function FindBarArt()
	for _, name in ipairs(BAR_ART_NAMES) do
		AddBarArt(_G[name])
	end
	for barName, keys in pairs(BAR_ART_KEYS) do
		local bar = _G[barName]
		if type(bar) == "table" then
			for _, key in ipairs(keys) do
				AddBarArt(bar[key])
			end
		end
	end
	if artStandIn then
		AddFrame(artStandIn, "barart")
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

local function SyncAllOwnAlpha()
	for _, entry in ipairs(ns.managed) do
		if entry.ownAlpha then
			SyncOwnAlpha(entry)
		elseif ns.alphaWatch and entry.applied then
			-- (/cine debug alpha: the rest are only reported, to find a frame
			-- that should count as setting its own.)
			local alpha = entry.frame:GetAlpha()
			if (issecretvalue and issecretvalue(alpha)) or math.abs(alpha - entry.applied) > ALPHA_SLACK then
				ReportOwnAlpha(entry, alpha, "not followed")
			end
		end
	end
end

-- Every frame, not just on the update tick, when a supported addon asks
-- (ns.syncEveryFrame): a frame it sets the alpha of would otherwise show at
-- it for several frames until the next tick at a high frame rate. Otherwise
-- the tick does (see UpdateFrames).
ns.SyncOwnAlphas = SyncAllOwnAlpha

-- Supported addons' own searches for their frames (Support/), run with each scan.
local scanners = {}

-- Safe to call repeatedly: frames already managed are skipped, and frames
-- created after login get picked up on a later call.
function ns.BuildManagedList()
	for group, names in pairs(FRAME_GROUPS) do
		for _, name in ipairs(names) do
			AddFrame(_G[name], group)
		end
	end
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		-- The input box sits on UIParent, not in its chat frame, so it's
		-- faded on its own (it sets its own alpha too: see AddFrame).
		AddFrame(_G["ChatFrame" .. i], "chat")
		AddFrame(_G["ChatFrame" .. i .. "EditBox"], "chat")
	end
	for _, scan in ipairs(scanners) do
		scan()
	end
	ScanTopLevelFrames()
	ScanAddonFrames()
	FindIssueReporter()
	FindBarArt()
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

-- Run once the minimap has its size back (see ns.OnMinimapRestored): an addon
-- laying it out while shrunk can leave its parts out of place.
local restoredHandlers = {}

-- Indoors (buildings, caves, Ironforge) the game stops updating the minimap's
-- indoor map while it's hidden (shrunk, or at any alpha below full), so after
-- walking around it comes back blank, black or half drawn. Outdoors it keeps
-- up. A zoom step and back on the next frame makes it draw the map again with
-- no visible flicker, but only once it's fully shown: so each time it grows
-- back indoors, that's done at the end of its fade-in. (Or the minimap can
-- stay up indoors: minimapIndoors, Minimap page.)
local minimapNeedsRedraw = false

local function RedrawMinimapWhenShown()
	if not minimapNeedsRedraw or not ns.Flag(Minimap:IsVisible()) or Minimap:GetEffectiveAlpha() < 0.99 then
		return
	end
	minimapNeedsRedraw = false
	local zoom = Minimap:GetZoom()
	local other = zoom > 0 and zoom - 1 or zoom + 1
	if other > Minimap:GetZoomLevels() - 1 then
		return
	end
	Minimap:SetZoom(other)
	C_Timer.After(0, function()
		if Minimap:GetZoom() == other then -- (unless you zoomed meanwhile)
			Minimap:SetZoom(zoom)
		end
	end)
end

local function UnshrinkEntry(entry)
	entry.frame:SetScale(entry.savedScale or 1)
	entry.shrunk = false
	if entry.frame == Minimap and Minimap.GetZoomLevels and IsIndoors and ns.Flag(IsIndoors()) then
		minimapNeedsRedraw = true
	end
	for _, handler in ipairs(restoredHandlers) do
		pcall(handler)
	end
end

function ns.SetEntryAlpha(entry, alpha)
	entry.alpha = alpha
	if entry.shrinkWhenFaded then
		if alpha > 0 then
			-- (Blocked in combat: it stays shrunk, and grows back once the fight ends.)
			if entry.shrunk and GetTime() - entry.shrunkAt >= MIN_SHRUNK_TIME and not ns.ScaleBlocked(entry.frame) then
				UnshrinkEntry(entry)
			end
		elseif ns.ScaleBlocked(entry.frame) then
			-- Can't shrink in combat: it sits at alpha 0 full size until the
			-- fight ends (tried again each tick), and is redrawn once shown.
			if not entry.shrunk and entry.frame == Minimap and Minimap.GetZoomLevels and IsIndoors
				and ns.Flag(IsIndoors()) then
				minimapNeedsRedraw = true
			end
		elseif not entry.shrunk then
			-- Shrink in the same step it reaches 0, so it's never at alpha 0
			-- while full size.
			ShrinkEntry(entry)
		elseif math.abs(entry.frame:GetScale() - SHRUNK_SCALE) > SHRUNK_SCALE / 2 then
			-- Something put its size back (EllesmereUI does when it lays the
			-- minimap out again): take that as its size and shrink it again.
			ShrinkEntry(entry)
		end
	end
	ApplyAlpha(entry)
end
ns.SetEntryAlpha = ns.Profiled("SetEntryAlpha", ns.SetEntryAlpha)

local function IsCursorInSavedRect(entry)
	local left, bottom, width, height = unpack(entry.savedRect)
	if not left then
		return false
	end
	local x, y = GetCursorPosition()
	x, y = x / entry.savedEffectiveScale, y / entry.savedEffectiveScale
	return x >= left and x <= left + width and y >= bottom and y <= bottom + height
end

-- The UI element the mouse is actually over (nil over the 3D world). Asked
-- for every faded frame each tick, so worked out once a frame (GetMouseFoci
-- makes a table each call).
local MouseFocus
do
	local focusAt, focus = -1, nil
	function MouseFocus()
		local now = GetTime()
		if focusAt ~= now then
			focusAt = now
			if GetMouseFoci then
				focus = GetMouseFoci()[1]
			elseif GetMouseFocus then
				focus = GetMouseFocus()
			else
				focus = nil
			end
			if focus == WorldFrame then
				focus = nil
			end
		end
		return focus
	end
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
		-- (Any of these can come back secret on Forever: ns.Flag reads that as false.)
		if not IsForbidden(child) and ns.Flag(child:IsVisible()) then
			if ns.Flag(child:IsMouseEnabled()) and ns.Flag(child:IsMouseOver(padY, -padY, -padX, padX)) then
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
	if PART_GROUPS[entry.group] then
		return false
	end
	if entry.shrunk then
		return IsCursorInSavedRect(entry)
	end
	if entry.group == "buffs" then
		return ns.Flag(entry.frame:IsVisible()) and IsNearIcon(BUFF_HOVER_DEPTH,
			ns.db.buffHoverPadX or 20, ns.db.buffHoverPadY or 20, entry.frame:GetChildren())
	end
	-- (The mouse over the 3D world, as it mostly is in CineMode: none of the
	-- rest can be hovered, so no need to ask each frame.)
	if entry.group ~= "chat" and not MouseFocus() then
		return false
	end
	if not (ns.Flag(entry.frame:IsVisible()) and ns.Flag(entry.frame:IsMouseOver())) then
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
	local focus = MouseFocus()
	-- Classic clients' raid frames sit inside the Raid Frame Manager: the
	-- mouse on them isn't on the manager.
	local raidFrames = _G.CompactRaidFrameContainer
	if entry.group == "raidmanager" and raidFrames and IsInside(focus, raidFrames) then
		return false
	end
	return IsInside(focus, entry.frame)
end
ns.IsEntryHovered = ns.Profiled("IsEntryHovered", ns.IsEntryHovered)

-- Frames the player can choose to show while fighting when staying cinematic
-- in combat (db.combatShow[key], missing = the default here).
ns.COMBAT_SHOW = {
	{ key = "player", label = L["Player portrait (and pet)"], default = true, frames = { "PlayerFrame", "PetFrame" } },
	{ key = "prd", label = L["Personal resource bars"], default = true,
		frames = { "PersonalResourceDisplayFrame", "CinematicPersonalResource" } },
	{ key = "target", label = L["Target"], default = true, frames = { "TargetFrame" } },
	{ key = "tot", label = L["Target of target"], default = true, frames = { "TargetFrameToT" } },
	{ key = "focus", label = L["Focus"], default = true, frames = { "FocusFrame" } },
	-- The Standard Frames page's Party frames section (page = "party"); the
	-- raid-style ones are the Raid frames section's.
	{ key = "party", label = L["Party frames"], default = true, page = "party", groups = { "party" } },
	-- Their parts, Always ticked to start with (CINE_SHOW_DEFAULT), as the raid frames' are.
	{ key = "partyroles", label = L["Role icons"], default = true, page = "party", groups = { "partyroles" }, part = true },
	{ key = "partynames", label = L["Names"], default = true, page = "party", groups = { "partynames" }, part = true },
	-- The raid frames (raid-style party frames too), members and pets apart,
	-- and the Raid Frame Manager (the tab at the left edge): the Standard
	-- Frames page's Raid frames section (page = "raid").
	{ key = "raidplayers", label = L["Players"], default = true, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidplayers" } },
	{ key = "raidpets", label = L["Pets"], default = true, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidpets" } },
	-- Parts of them, Always ticked to start with (CINE_SHOW_DEFAULT): untick
	-- one to hide it in CineMode (names and role icons while you heal, say).
	-- (part: Always means whenever its frame shows, over its Mouseover groups.)
	{ key = "raidroles", label = L["Role icons"], default = true, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidroles" }, part = true },
	-- The glow round a member with threat. (tip: the row name's tooltip.)
	{ key = "raidthreat", label = L["Threat highlight"], default = true, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidthreat" }, part = true,
		tip = L["The glow round a member with threat (aggro). To hide it all the time, CineMode or not, " ..
			"turn off the game's own Display Aggro Highlight raid frame option."] },
	{ key = "raidnames", label = L["Player names"], default = true, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidnames" }, part = true },
	{ key = "raidpetnames", label = L["Pet names"], default = true, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidpetnames" }, part = true },
	{ key = "raidtitles", label = L["Group titles"], default = true, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidtitles" }, part = true },
	{ key = "raidbuffs", label = L["Buffs"], default = true, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raidbuffs" }, part = true },
	{ key = "raiddebuffs", label = L["Debuffs"], default = true, addon = "Blizzard_CompactRaidFrames",
		page = "raid", groups = { "raiddebuffs" }, part = true },
	{ key = "raidmanager", label = L["Raid Frame Manager"], default = false, addon = "Blizzard_CompactRaidFrames",
		page = "raid", frames = { "CompactRaidFrameManager" } },
	-- The battlegrounds' flag carriers: its Battlegrounds section (page = "bg").
	-- Always shown to start with (CINE_SHOW_DEFAULT), as before it had a row.
	{ key = "flags", label = L["Flag carriers"], default = true, addon = "Blizzard_Deprecated_ArenaUI",
		page = "bg", frames = { "ArenaEnemyFramesContainer" } },
	-- morePage: the options page with more settings for it, which can keep it up besides.
	{ key = "minimap", label = L["Minimap"], default = true, groups = { "minimap" }, morePage = "Minimap",
		handledBy = "handleMinimap" },
	{ key = "quests", label = L["Quest tracker"], default = false, frames = FRAME_GROUPS.quests,
		morePage = "Quest tracker", handledBy = "handleQuests" },
	-- Retail's quest waypoint: its Always tick is the Minimap page's "Always
	-- show the quest waypoint" (CINE_SHOW_SETTING).
	{ key = "waypoint", label = L["Quest waypoint"], default = false, retail = true, groups = { "waypoint" },
		morePage = "Minimap", handledBy = "handleQuests" },
	{ key = "buffs", label = L["Buffs and debuffs"], default = true, morePage = "Buffs/debuffs", handledBy = "handleBuffs",
		frames = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" } },
	{ key = "swing", label = L["Swing timer"], default = true, retail = false, handledBy = "handleSwing",
		tip = L["The Swing timer page can fade out the bars of weapons you aren't using, and the off-hand's."],
		frames ={ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" } },
	-- Always ticked to start with (CINE_SHOW_DEFAULT), as before it had a row:
	-- untick it to hide your cast bar in CineMode but for fights.
	{ key = "castbar", label = L["Cast bar"], default = true, frames = FRAME_GROUPS.castbar },
	-- The game's own damage meter (made when first opened).
	{ key = "meters", label = L["Damage meter (the game's)"], default = false, frames = FRAME_GROUPS.meters },
	-- (handledBy: a master switch that, off, leaves its frames alone: its row greys out.)
	{ key = "cooldowns", label = L["Cooldown Manager"], default = false, addon = "Blizzard_CooldownViewer",
		frames = FRAME_GROUPS.cooldowns, morePage = "Cooldown Manager", handledBy = "handleCooldowns" },
	-- Numbered as retail's Edit Mode numbers them; Classic doesn't number its
	-- bars, so there each also says where it sits.
	{ key = "mainbar", label = L["Action bar 1"], default = true,
		frames = { "MainMenuBar", "MainActionBar", "MainMenuBarVehicleLeaveButton" } },
	-- The game's art round action bar 1 (end caps, the bar behind the buttons),
	-- left up or faded apart from its buttons, which an action bar addon may
	-- have taken away. Follows Action bar 1's ticks until set (see ROW_FALLBACK).
	-- noHoverRow: hovering it is hovering action bar 1.
	{ key = "art", label = L["Action bar art"], default = true, groups = { "barart" }, noHoverRow = true },
	{ key = "bottomleft", label = ns.isRetail and L["Action bar 2"] or L["Action bar 2 (bottom left)"], default = true,
		frames = { "MultiBarBottomLeft" } },
	{ key = "bottomright", label = ns.isRetail and L["Action bar 3"] or L["Action bar 3 (bottom right)"], default = true,
		frames = { "MultiBarBottomRight" } },
	{ key = "right1", label = ns.isRetail and L["Action bar 4"] or L["Action bar 4 (right)"], default = false,
		frames = { "MultiBarRight" } },
	{ key = "right2", label = ns.isRetail and L["Action bar 5"] or L["Action bar 5 (right 2)"], default = false,
		frames = { "MultiBarLeft" } },
	-- Retail only (the frames don't exist on Classic, so the rows are skipped).
	{ key = "bar6", label = L["Action bar 6"], default = false, frames = { "MultiBar5" } },
	{ key = "bar7", label = L["Action bar 7"], default = false, frames = { "MultiBar6" } },
	{ key = "bar8", label = L["Action bar 8"], default = false, frames = { "MultiBar7" } },
	{ key = "pet", label = L["Pet bar"], default = true, frames = { "PetActionBarFrame", "PetActionBar" } },
	{ key = "stance", label = L["Stance bar"], default = true, frames = { "StanceBarFrame", "StanceBar" } },
	{ key = "totems", label = L["Totem bar"], default = true, frames = {
		"MultiCastActionBarFrame", "MultiCastSummonSpellButton", "MultiCastRecallSpellButton",
		"MultiCastFlyoutFrame", "MultiCastSlotButton1", "MultiCastSlotButton2",
		"MultiCastSlotButton3", "MultiCastSlotButton4",
		"MultiCastActionPage1", "MultiCastActionPage2", "MultiCastActionPage3", "TotemFrame",
	} },
	{ key = "micro", label = L["Micro menu and bags"], default = true,
		frames = { "MicroButtonAndBagsBar", "MicroMenuContainer", "BagsBar" } },
	-- (In gamepad mode the Gamepad page's row has them instead: notGamepad.)
	{ key = "xp", label = L["Experience and reputation bars"], default = true, notGamepad = true, frames = {
		"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
		"StatusTrackingBarManager",
	} },
	-- Always ticked to start with (CINE_SHOW_DEFAULT): it's what a quest or fight asks you to press.
	{ key = "extra", label = L["Extra action and zone ability"], default = true, retail = true,
		frames = { "ExtraActionBarFrame", "ZoneAbilityFrame" } },
	-- WoW Forever's gamepad mode, on the Gamepad page (page = "gamepad") rather
	-- than the Standard Frames page.
	{ key = "gamepadbars", label = L["Gamepad action bars"], default = true, retail = false, page = "gamepad",
		frames = FRAME_GROUPS.gamepadbars },
	{ key = "gamepadlegend", label = L["Button hints (top left)"], default = false, retail = false, page = "gamepad",
		frames = FRAME_GROUPS.gamepadlegend },
	{ key = "gamepadreticle", label = L["Reticle (center dot)"], default = true, retail = false, page = "gamepad",
		frames = FRAME_GROUPS.gamepadreticle },
	-- The game's experience bars again, used only in gamepad mode (gamepadOnly).
	{ key = "gamepadxp", label = L["Experience and reputation bars"], default = false, retail = false,
		page = "gamepad", gamepadOnly = true, frames = {
		"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
		"StatusTrackingBarManager",
	} },
}
-- The Standard Frames page's sections (page) for the rows not given one
-- above. (Kept in the order above within each.)
local ROW_SECTIONS = {
	player = "units", prd = "units", target = "units", tot = "units", focus = "units",
	buffs = "combat", swing = "combat", castbar = "combat", meters = "combat", cooldowns = "combat",
	mainbar = "bars", art = "bars", bottomleft = "bars", bottomright = "bars", right1 = "bars", right2 = "bars",
	bar6 = "bars", bar7 = "bars", bar8 = "bars", pet = "bars", stance = "bars", totems = "bars", extra = "bars",
	minimap = "interface", quests = "interface", waypoint = "interface", micro = "interface", xp = "interface",
}
for _, item in ipairs(ns.COMBAT_SHOW) do
	item.page = item.page or ROW_SECTIONS[item.key]
end

-- Then the Other addons, by group (their frames may have no names).
for _, known in ipairs(ns.ADDON_FRAMES) do
	ns.COMBAT_SHOW[#ns.COMBAT_SHOW + 1] = {
		key = "addon:" .. known.key, label = known.short or known.label, default = true, addon = known.addon,
		groups = { "addon:" .. known.key },
	}
end

-- Mouseover groups (Mouseover page): frames in the same group come up
-- together when the mouse is on any of them, and with the events ticked for
-- the group. A frame can be in several groups; one in none comes up alone.
-- Groups are lists of rows: the Standard Frames rows above (with the
-- supported addons; not the Gamepad page's copy of the XP bars), a few
-- frames that have no row there, and the 3rd Party Frames additions
-- ("extra:<name>"). These only decide what reveals together: the fade groups
-- (FRAME_GROUPS) still drive everything else.
local HOVER_EXTRA_ROWS = {
	{ key = "totemtimers", label = L["Totem timers (by the portrait)"], frames = { "TotemFrame" } },
	{ key = "durability", label = L["Durability figure"], frames = { "DurabilityFrame" } },
	{ key = "chat", label = L["Chat tabs and buttons"], frames = FRAME_GROUPS.chat },
	{ key = "questtimer", label = L["Quest timer"], frames = { "QuestTimerFrame" } },
	{ key = "waypoint", label = L["Quest waypoint"], frames = { "SuperTrackedFrame" } },
}
ns.HOVER_ROWS = {}
local HOVER_ROW_BY_NAME = {} -- frame name -> row key (the first row listing it)
for _, list in ipairs({ HOVER_EXTRA_ROWS, ns.COMBAT_SHOW }) do
	for _, item in ipairs(list) do
		if item.key ~= "gamepadxp" and not item.noHoverRow then
			ns.HOVER_ROWS[#ns.HOVER_ROWS + 1] = item
			for _, name in ipairs(item.frames or {}) do
				HOVER_ROW_BY_NAME[name] = HOVER_ROW_BY_NAME[name] or item.key
			end
		end
	end
end
-- Frames no row lists by name go with their fade group's row (the possess
-- bar with action bar 1, the minimap's clock with the minimap...); an
-- addon's or added frame's row is its fade group ("addon:<key>", "extra:<name>").
local HOVER_ROW_BY_GROUP = {
	bars = "mainbar", sidebars = "right1", player = "player", prd = "prd", totems = "totems", target = "target",
	party = "party",
	raidplayers = "raidplayers", raidpets = "raidpets", raidmanager = "raidmanager", flags = "flags",
	raidroles = "raidroles", raidnames = "raidnames", raidpetnames = "raidpetnames", raidtitles = "raidtitles",
	partyroles = "partyroles", partynames = "partynames",
	raidbuffs = "raidbuffs", raiddebuffs = "raiddebuffs", raidthreat = "raidthreat",
	minimap = "minimap", buffs = "buffs", quests = "quests", questtimer = "questtimer", misc = "durability",
	swing = "swing", castbar = "castbar", meters = "meters", cooldowns = "cooldowns", waypoint = "waypoint",
	gamepadbars = "gamepadbars", gamepadlegend = "gamepadlegend", gamepadreticle = "gamepadreticle",
	chat = "chat", barart = "mainbar",
}
function ns.HoverRowFor(entry)
	return (entry.name and HOVER_ROW_BY_NAME[entry.name]) or HOVER_ROW_BY_GROUP[entry.group] or entry.group
end

-- The events that can bring a group up besides the mouse ("Also bring this
-- group up for"). Each still needs its own setting on: the Chat page's peek,
-- buff peeks on the Buffs/debuffs page, the Minimap and Quest tracker pages'
-- options, the gamepad's press reveal.
ns.HOVER_TRIGGERS = {
	{ key = "chat", label = L["Chat message"], tip = L["A chat window peeking for a new message (Chat page)."] },
	{ key = "whisper", label = L["Unread whisper"],
		tip = L["A whisper tab waiting to be read, while that keeps chat up (Chat page)."] },
	{ key = "typing", label = L["Typing"], tip = L["Typing in chat."] },
	{ key = "aura", label = L["New buff or debuff"], tip = L["A buff or debuff peek (Buffs/debuffs page)."] },
	{ key = "ping", label = L["Minimap ping"], tip = L["A group member pinging the minimap (Minimap page)."] },
	{ key = "tracking", label = L["Tracking"],
		tip = L["While the minimap stays up for herb, mineral or other tracking (Minimap page)."] },
	{ key = "quest", label = L["Quest progress"], tip = L["Accepting a quest or progress on one (Quest tracker page)."] },
	{ key = "gamepad", label = L["Gamepad input"], gamepad = true, tip = L["Pressing a gamepad button (Gamepad page)."] },
	{ key = "roster", label = L["Group joins or leaves"],
		tip = L["Someone joining or leaving your party or raid, or you joining or leaving one."] },
	{ key = "cooldown", label = L["Cooldown recharging"], tip = L["While a spell in the Cooldown Manager (or " ..
		"Enhanced Cooldown Manager's cooldown bars) is still recharging, until they're all ready. Not " ..
		"the global cooldown (Cooldown Manager page)."] },
}

-- What it's like before you change anything: today's groups that do
-- something (more than one frame, or brought up by more than the mouse).
ns.HOVER_GROUPS_DEFAULT = {
	{ name = L["Action bars"], members = { "mainbar", "bottomleft", "bottomright",
		"pet", "stance", "totems", "micro", "xp", "extra" } },
	{ name = L["Action bars 6-8"], members = { "bar6", "bar7", "bar8" } },
	{ name = L["Side bars"], members = { "right1", "right2" } },
	{ name = L["Player"], members = { "player", "prd", "totemtimers", "castbar" } },
	{ name = L["Target and focus"], members = { "target", "tot", "focus" } },
	-- (Raid-style party frames are the raid frames; the Raid Frame Manager
	-- goes with both.)
	{ name = L["Raid frames"], members = { "raidplayers", "raidpets", "raidroles", "raidthreat", "raidnames",
		"raidpetnames", "raidtitles", "raidbuffs", "raiddebuffs", "raidmanager" }, triggers = { roster = true } },
	{ name = L["Party frames"], members = { "party", "partyroles", "partynames", "raidmanager" },
		triggers = { roster = true } },
	{ name = L["Minimap"], members = { "minimap" }, triggers = { ping = true, tracking = true } },
	{ name = L["Buffs"], members = { "buffs" }, triggers = { aura = true } },
	{ name = L["Quest tracker"], members = { "quests" }, triggers = { quest = true } },
	{ name = L["Gamepad action bars"], members = { "gamepadbars" }, triggers = { gamepad = true } },
	{ name = L["Chat"], members = { "chat" }, triggers = { whisper = true, typing = true } },
	{ name = L["Cooldowns"], members = { "cooldowns", "addon:fecm" }, triggers = { cooldown = true } },
}

-- The groups in use: the player's (db.hoverGroups), or the defaults until
-- they change them.
function ns.GetHoverGroups()
	return ns.db.hoverGroups or ns.HOVER_GROUPS_DEFAULT
end

-- A copy of the groups in use, to change (the Mouseover page's first edit).
function ns.CopyHoverGroups()
	local copy = {}
	for _, group in ipairs(ns.GetHoverGroups()) do
		local members, triggers = {}, {}
		for i, key in ipairs(group.members or {}) do members[i] = key end
		for key, on in pairs(group.triggers or {}) do triggers[key] = on end
		copy[#copy + 1] = { name = group.name, members = members, triggers = triggers }
	end
	return copy
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
	player = true, prd = true, raidroles = true, raidnames = true, partyroles = true, partynames = true,
	raidpetnames = true, raidtitles = true, raidbuffs = true, raiddebuffs = true, raidthreat = true, target = true, tot = true, focus = true, buffs = true, mainbar = true, bottomleft = true,
	bottomright = true, pet = true, stance = true, totems = true, micro = true, xp = true, extra = true,
	gamepadbars = true, gamepadreticle = true, castbar = true,
}
-- Other addons' frames too.
for _, known in ipairs(ns.ADDON_FRAMES) do
	ENEMY_SHOW_DEFAULT["addon:" .. known.key] = true
end

-- Gamepad mode on. On WoW Forever: its gamepad bars are showing (the game
-- shows and hides them; the fade only sets their alpha). GamePadEnable stays
-- on there with the gamepad UI off, so it can't tell. Retail has no gamepad
-- UI of its own: the setting it is.
function ns.IsGamePadOn()
	if not ns.isRetail then
		local bar = _G.GamepadMainActionBarFrame
		return bar ~= nil and ns.Flag(bar:IsShown())
	end
	return C_GamePad ~= nil and GetCVarBool("GamePadEnable")
end

-- Frames added on the 3rd Party Frames page ("extra:<name>") start out like
-- the supported addons': up in combat and with an enemy targeted.
local function IsExtraKey(key)
	return key:find("^extra:") ~= nil
end

-- Rows that take another row's tick in a column until given their own: the
-- bar art follows action bar 1, so profiles and lists from before it was a
-- row (the Cooldown Manager profile's: no action bars) still hold.
local ROW_FALLBACK = { art = "mainbar" }

function ns.IsCombatShowOn(key)
	local on = ns.db.combatShow[key]
	if on == nil then
		if ROW_FALLBACK[key] then
			return ns.IsCombatShowOn(ROW_FALLBACK[key])
		end
		if IsExtraKey(key) then
			return true
		end
		for _, item in ipairs(ns.COMBAT_SHOW) do
			if item.key == key then return item.default end
		end
	end
	return on
end

local function IsListOn(list, key, defaults)
	local on = ns.db[list][key]
	if on == nil then
		if ROW_FALLBACK[key] then
			return IsListOn(list, ROW_FALLBACK[key], defaults)
		end
		if IsExtraKey(key) then
			return defaults == ENEMY_SHOW_DEFAULT
		end
		return defaults[key] or false
	end
	return on
end

-- Standard Frames page's Always column (cineShow): ticked, a row's frames stay shown all through CineMode.
-- Some rows' Always tick is an option elsewhere too (the same setting).
ns.CINE_SHOW_SETTING = { minimap = "alwaysShowMinimap", waypoint = "alwaysShowWaypoint" }
-- Rows ticked there until changed (no profile lists them, so none hides them).
local CINE_SHOW_DEFAULT = {
	flags = true, castbar = true, partyroles = true, partynames = true,
	raidroles = true, raidnames = true, raidpetnames = true, raidtitles = true, raidbuffs = true,
	raiddebuffs = true, raidthreat = true, extra = true,
}
function ns.IsCineShowOn(key)
	local setting = ns.CINE_SHOW_SETTING[key]
	if setting then
		return ns.db[setting] or false
	end
	local on = ns.db.cineShow[key]
	if on == nil and ROW_FALLBACK[key] then
		return ns.IsCineShowOn(ROW_FALLBACK[key])
	end
	if on == nil then
		return CINE_SHOW_DEFAULT[key] or false
	end
	return on
end
function ns.IsEnemyShowOn(key) return IsListOn("enemyShow", key, ENEMY_SHOW_DEFAULT) end
function ns.IsFriendlyShowOn(key) return IsListOn("friendlyShow", key, TARGET_SHOW_DEFAULT) end

-- The frames pages' place columns, after the others: ticked, a row's frames
-- stay shown all through CineMode there, in fights and out, as the Always
-- column does everywhere. Grouped isn't a place: a party or raid, anywhere.
-- Places as the Nameplates page has them (bar its PvP flagged column, which
-- goes with the open world here). Their defaults are below.
ns.PLACE_SHOW = {
	{ list = "bgShow", label = L["BGs & Arenas"], tip = L["Show all through CineMode in battlegrounds and arenas."] },
	{ list = "worldShow", label = L["Open World"],
		tip = L["Show all through CineMode everywhere else, cities and inns included."] },
	{ list = "groupShow", label = L["Grouped"],
		tip = L["Show all through CineMode while you're in a party or raid, wherever you are."] },
	{ list = "instanceShow", label = L["Instances"],
		tip = L["Show all through CineMode in dungeons, scenarios and raids."] },
}
local NO_DEFAULTS = {}
-- Ticked to start with: every row in dungeons, scenarios and raids (not
-- 3rd party frames), the raid and party frames in battlegrounds and
-- arenas, where you're always in a group, and the party frames and raid
-- frames' players whenever you're grouped.
local PLACE_SHOW_DEFAULTS = {
	bgShow = { raidplayers = true, raidpets = true, party = true },
	groupShow = { raidplayers = true, party = true },
	instanceShow = setmetatable({}, { __index = function() return true end }),
}
local function PlaceDefaults(list)
	return PLACE_SHOW_DEFAULTS[list] or NO_DEFAULTS
end
function ns.IsPlaceShowOn(list, key) return IsListOn(list, key, PlaceDefaults(list)) end

-- The place columns that apply where you are now.
-- Tables UpdateFrames (and what it calls) fills afresh each tick, kept rather
-- than made anew: making them 33 times a second was a lot of garbage.
local tickTables = {
	hovered = {}, triggered = {}, pinged = {}, mouseRows = {}, mouseGroups = {}, events = {},
	combatShown = {}, placeLists = {},
}

-- "group:<group>", a group's key in the shown lists, made once for each
-- group: built every tick for each faded frame's group, it was garbage.
local GROUP_KEY = setmetatable({}, { __index = function(keys, group)
	local key = "group:" .. group
	keys[group] = key
	return key
end })

local function PlaceListsHere()
	local place = ns.GetPlaceType()
	local lists = wipe(tickTables.placeLists)
	lists[1] = (place == "pvp" and "bgShow")
		or ((place == "dungeon" or place == "raid") and "instanceShow") or "worldShow"
	if ns.InGroup() then
		lists[2] = "groupShow"
	end
	return lists
end

-- Frame names to show right now: only while staying cinematic and fighting
-- (in combat, or with an enemy targeted). Also returns whether the player is
-- actually in combat, since the fast fade-in only applies then.
-- Anything targeted (friend or foe).
local function HasAnyTarget()
	return ns.HasTarget()
end

-- When the player was last in combat (for "only after combat").
local lastCombatAt = -math.huge

-- Frame names to show right now, from the Standard Frames page's column that
-- applies: In combat (while staying cinematic, and with combatShowCalm on
-- until the Calm Timer has run out after the fight), Tar Enemy (out of combat
-- with a living enemy targeted) or Tar Friendly (anything else targeted:
-- friends, NPCs, dead enemies).
-- Rows with Always ticked are always in it: they don't fade in CineMode at all.
-- Rows with a Calm Timer option of their own on their page: their In combat
-- tick lasts until the Calm Timer runs out even with combatShowCalm off.
local GetCombatShownFrames
do
	local CALM_ROW_SETTING = { quests = "questCombatCalm" }
	-- Whether a row is ticked in one of the place columns that apply here.
	-- (Kept out of GetCombatShownFrames: a closure made each tick was garbage.)
	local function KeptHere(placeLists, key)
		for _, list in ipairs(placeLists) do
			if IsListOn(list, key, PlaceDefaults(list)) then
				return true
			end
		end
		return false
	end
	function GetCombatShownFrames()
		local fighting = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
		local calm = not fighting and GetTime() - lastCombatAt < (ns.db.calmTime or 0)
		local inCombat = fighting or (calm and ns.db.combatShowCalm)
		local isOn
		if inCombat then
			if ns.db.stayInCombat then
				isOn = ns.IsCombatShowOn
			end
		elseif HasAnyTarget() then
			if ns.IsEnemyUnit("target") and not ns.Flag(UnitIsDeadOrGhost("target")) then
				isOn = ns.IsEnemyShowOn
			else
				isOn = ns.IsFriendlyShowOn
			end
		end
		-- (And the rows ticked for where you are.)
		local placeLists = PlaceListsHere()
		local shown = wipe(tickTables.combatShown)
		-- Rows for gamepad mode only, and the ones they stand in for then.
		local gamepad = ns.IsGamePadOn()
		for _, item in ipairs(ns.COMBAT_SHOW) do
			local applies = not (gamepad and item.notGamepad) and not (item.gamepadOnly and not gamepad)
			local calmRow = calm and ns.db.stayInCombat and ns.db[CALM_ROW_SETTING[item.key] or ""]
				and ns.IsCombatShowOn(item.key)
			if applies and (ns.IsCineShowOn(item.key) or KeptHere(placeLists, item.key) or (isOn and isOn(item.key)) or calmRow) then
				for _, name in ipairs(item.frames or NO_DEFAULTS) do
					shown[name] = true
				end
				for _, group in ipairs(item.groups or NO_DEFAULTS) do
					shown[GROUP_KEY[group]] = true
				end
			end
		end
		-- Added frames, by their rows on the 3rd Party Frames page.
		for name in pairs(ns.db.extraFrames) do
			local key = "extra:" .. name
			if KeptHere(placeLists, key) or (isOn and isOn(key)) then
				shown[GROUP_KEY[key]] = true
			end
		end
		return shown
	end
end
GetCombatShownFrames = ns.Profiled("GetCombatShownFrames", GetCombatShownFrames)

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

-- Coming back to life does too, until health and power are full (however
-- long that takes).
local resurrectRecovering = false
do
	local resurrectWatcher = CreateFrame("Frame")
	resurrectWatcher:RegisterEvent("PLAYER_ALIVE") -- (also as you release to a ghost)
	resurrectWatcher:RegisterEvent("PLAYER_UNGHOST")
	resurrectWatcher:SetScript("OnEvent", function()
		if not ns.Flag(UnitIsDeadOrGhost("player")) then
			resurrectRecovering = true
		end
	end)
end

-- Buff peek: a new or refreshed buff/debuff briefly shows the buffs group.
-- UNIT_AURA says what changed (added, updated, removed) without needing the
-- aura details, which may be secret. Removals and the full refresh at login or
-- zoning don't count. Clients that don't say what changed count every change.
local buffPeekUntil = 0
-- A debuff brought them up with debuffPeekUntilGone: held until you have no
-- debuffs left (bar ignored ones).
local debuffHeld = false

local COMBAT_END_AURA_GRACE = 1 -- seconds after a fight its aura changes don't bring the buffs up

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

-- A buff you cast on yourself (buffPeekIgnoreSelf passes these over): its
-- caster is you or your pet. (False when unsure: no data, or a secret caster.)
local function IsSelfCast(aura)
	if type(aura) ~= "table" then
		return false
	end
	local source = aura.sourceUnit
	if source == nil or (issecretvalue and issecretvalue(source)) then
		return false
	end
	for _, unit in ipairs({ "player", "pet" }) do
		local ok, mine = pcall(UnitIsUnit, source, unit)
		if ok and mine == true then
			return true
		end
	end
	return false
end

-- Buffs and debuffs each bring the buffs up on their own switch (buffPeek,
-- debuffPeek), each with its own "Only after combat" (within the Calm Timer).
local function PeekAllowed(harmful)
	local prefix = harmful and "debuffPeek" or "buffPeek"
	if not ns.db[prefix] then
		return false
	end
	return not (ns.db[prefix .. "AfterCombat"] and GetTime() - lastCombatAt > ns.db.calmTime)
end

-- How long a peek of this kind holds the buffs up (buffPeekTime,
-- debuffPeekTime), or nil when its kind doesn't bring them up.
local function PeekHold(harmful)
	if PeekAllowed(harmful) then
		return ns.HoldTime(harmful and "debuffPeekTime" or "buffPeekTime")
	end
end

-- The longer of the two kinds' holds, for when it's unclear which kind it was.
local function EitherHold()
	local buff, debuff = PeekHold(false), PeekHold(true)
	if buff and debuff then
		return math.max(buff, debuff)
	end
	return buff or debuff
end

-- One aura gained or refreshed: how long it brings the buffs up, or nil. Not
-- at all if it's on the ignore list, or a buff you cast on yourself with
-- buffPeekIgnoreSelf; otherwise as its kind allows. When unsure (no data,
-- secret values), either kind will do.
local function AuraHold(aura)
	if IsIgnoredAura(aura) then
		return nil
	end
	local harmful = type(aura) == "table" and aura.isHarmful
	if harmful == nil or (issecretvalue and issecretvalue(harmful)) then
		return EitherHold()
	end
	if not harmful and ns.db.buffPeekIgnoreSelf and IsSelfCast(aura) then
		return nil
	end
	local hold = PeekHold(harmful and true or false)
	if hold and harmful and ns.db.debuffPeekUntilGone then
		debuffHeld = true
	end
	return hold
end

-- Any debuff on you that isn't on the ignore list? (Yes when unsure: secret
-- values. The fight clears the hold anyway.)
local function HasDebuff()
	for i = 1, 40 do
		local aura
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			-- (Errors rather than returning nil while auras are secret.)
			local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
			if not ok or (issecretvalue and issecretvalue(data)) then
				return true
			end
			aura = data
		elseif UnitDebuff then
			local values = { UnitDebuff("player", i) }
			aura = values[1] and { name = values[1], spellId = values[10] }
		end
		if not aura then
			return false
		end
		if (issecretvalue and issecretvalue(aura.name)) or not IsIgnoredAura(aura) then
			return true
		end
	end
	return false
end

-- The longest hold of any aura gained or refreshed, or nil. Updates (a stack
-- ticking up, say) only give instance IDs, so each is looked up. Either kind
-- when unsure.
local function AnyAuraHold(updateInfo)
	local ok, hold = pcall(function()
		local longest
		local function Consider(seconds)
			if seconds and (not longest or seconds > longest) then
				longest = seconds
			end
		end
		local added, updated = updateInfo.addedAuras, updateInfo.updatedAuraInstanceIDs
		if HasEntries(added) then
			if issecretvalue and issecretvalue(added) then
				return AuraHold(nil)
			end
			for _, aura in pairs(added) do
				Consider(AuraHold(aura))
			end
		end
		if HasEntries(updated) then
			if (issecretvalue and issecretvalue(updated))
				or not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then
				return AuraHold(nil)
			end
			for _, instanceID in pairs(updated) do
				Consider(AuraHold(C_UnitAuras.GetAuraDataByAuraInstanceID("player", instanceID)))
			end
		end
		return longest
	end)
	if not ok then
		return EitherHold()
	end
	return hold
end

do
	local auraWatcher = CreateFrame("Frame")
	auraWatcher:RegisterUnitEvent("UNIT_AURA", "player")
	auraWatcher:SetScript("OnEvent", ns.Profiled("UNIT_AURA (peeks)", function(_, _, _, updateInfo)
		-- (Removals count here: the last debuff going lets them fade.)
		if debuffHeld and not (ns.db and ns.db.debuffPeekUntilGone and HasDebuff()) then
			debuffHeld = false
		end
		if not (ns.db and (PeekAllowed(false) or PeekAllowed(true))) then
			return
		end
		-- In a fight the buffs follow the fight's own frames, and a peek started
		-- then would hold them up past its end: leaving combat, they fade with the
		-- rest of the UI at the usual fade out time. (Nor auras the fight's end
		-- itself changes, in the moment after it.)
		if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
			or GetTime() - lastCombatAt < COMBAT_END_AURA_GRACE then
			return
		end
		-- (wasOnTaxi: landed this instant, before the flight code has noticed.)
		if UnitOnTaxi("player") or ns.wasOnTaxi or GetTime() < landedQuietUntil then
			return
		end
		local hold
		if type(updateInfo) == "table" then
			hold = not IsFullUpdate(updateInfo.isFullUpdate) and AnyAuraHold(updateInfo)
		else
			hold = EitherHold()
		end
		if hold then
			-- (a short buff peek doesn't cut a longer debuff one short)
			buffPeekUntil = math.max(buffPeekUntil, GetTime() + hold)
		end
	end))
end

do
	local vitalsWatcher = CreateFrame("Frame")
	vitalsWatcher:RegisterUnitEvent("UNIT_HEALTH", "player")
	vitalsWatcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
	vitalsWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	vitalsWatcher:SetScript("OnEvent", ns.Profiled("Health/power events", function(_, event)
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
	end))
end

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

local hoverHeldUntil = {} -- [row key] = when the mouse's hold on it ends (Mouseover groups)

-- Accepting a quest, or progress on one's objectives, brings the quest
-- tracker up as a mouseover would: it fades in, then is gone the quest
-- tracker's mouseover time later.
local questRevealUntil = 0
do
	local QUEST_REVEAL_EVENTS = { QUEST_ACCEPTED = "questRevealOnAccept", QUEST_WATCH_UPDATE = "questRevealOnProgress" }
	local questWatcher = CreateFrame("Frame")
	for event in pairs(QUEST_REVEAL_EVENTS) do
		pcall(questWatcher.RegisterEvent, questWatcher, event)
	end
	local function Reveal(setting)
		if ns.db and ns.db[setting] then
			local hold = ns.HoldTime("mouseoverHold") - ns.FadeOutTime()
			questRevealUntil = GetTime() + ns.FadeInTime() + math.max(0, hold)
		end
	end
	questWatcher:SetScript("OnEvent", function(_, event)
		Reveal(QUEST_REVEAL_EVENTS[event])
	end)

	-- Retail: QUEST_WATCH_UPDATE misses progress-bar objectives (a percentage
	-- going up) and some counted ones, so each quest's progress (its counts
	-- plus its bar's percent) is summed after a quest log update, and a quest
	-- whose sum went up reveals. A quest seen for the first time doesn't.
	local questLog = C_QuestLog
	if ns.isRetail and questLog and questLog.GetNumQuestLogEntries and questLog.GetQuestObjectives then
		local progress, seen = {}, {}
		local pending = false
		local function Progress(questID)
			local sum = 0
			local objectives = questLog.GetQuestObjectives(questID)
			if objectives then
				for i = 1, #objectives do
					local count = objectives[i].numFulfilled
					if type(count) == "number" then
						sum = sum + count
					end
				end
			end
			if GetQuestProgressBarPercent then
				local percent = GetQuestProgressBarPercent(questID)
				if type(percent) == "number" then
					sum = sum + percent
				end
			end
			return sum
		end
		local function Scan()
			pending = false
			local advanced = false
			for questID in pairs(seen) do
				seen[questID] = nil
			end
			for i = 1, questLog.GetNumQuestLogEntries() do
				local info = questLog.GetInfo(i)
				local questID = info and not info.isHeader and info.questID
				if type(questID) == "number" and questID > 0 then
					local sum = Progress(questID)
					local before = progress[questID]
					if before and sum > before then
						advanced = true
					end
					progress[questID] = sum
					seen[questID] = true
				end
			end
			for questID in pairs(progress) do
				if not seen[questID] then
					progress[questID] = nil
				end
			end
			if advanced then
				Reveal("questRevealOnProgress")
			end
		end
		local logWatcher = CreateFrame("Frame")
		logWatcher:RegisterEvent("QUEST_LOG_UPDATE")
		logWatcher:SetScript("OnEvent", function()
			if not pending then
				pending = true
				C_Timer.After(0.2, Scan)
			end
		end)
	end
end

-- Gear damaged (yellow) or broken (red): the game shows the durability
-- figure then, and it stays up in CineMode while it does (durabilityShow).
-- Asked of each equipped slot when durability changes, not every tick. (A
-- secret status counts as fine.)
do
	local alert = false
	local function Check()
		alert = false
		if not GetInventoryAlertStatus then
			local frame = _G.DurabilityFrame
			alert = frame ~= nil and ns.Flag(frame:IsShown())
			return
		end
		for slot = 1, 19 do
			local status = GetInventoryAlertStatus(slot)
			if type(status) == "number" and status > 0 then
				alert = true
				return
			end
		end
	end
	local durabilityWatcher = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_DURABILITY", "UNIT_INVENTORY_CHANGED" }) do
		pcall(durabilityWatcher.RegisterEvent, durabilityWatcher, event)
	end
	durabilityWatcher:SetScript("OnEvent", function(_, event, unit)
		if event ~= "UNIT_INVENTORY_CHANGED" or unit == "player" then
			Check()
		end
	end)
	function ns.HasDurabilityAlert()
		return alert
	end
end

-- Hunter pet not happy (content or unhappy, not green): the pet frame stays up
-- in CineMode while it is (petUnhappyShow). Not retail, which has no happiness.
-- (A secret value counts as happy.) Forever has no GetPetHappiness: its pet
-- frame's happiness icon asks with GetHappinessStats, and updates itself.
do
	local unhappy = false
	local function Happiness()
		if GetPetHappiness then
			return GetPetHappiness()
		end
		local icon = _G.PetFrameHappiness
		if icon and icon.GetHappinessStats then
			local ok, happiness = pcall(icon.GetHappinessStats, icon)
			return ok and happiness or nil
		end
	end
	local function Check()
		local happiness = Happiness()
		unhappy = type(happiness) == "number" and happiness < 3
	end
	local icon = _G.PetFrameHappiness
	if icon and icon.UpdateHappiness then
		hooksecurefunc(icon, "UpdateHappiness", Check)
	end
	local petWatcher = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_PET", "UNIT_HAPPINESS", "PET_UI_UPDATE" }) do
		pcall(petWatcher.RegisterEvent, petWatcher, event)
	end
	petWatcher:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_PET" and unit ~= "player" then
			return
		end
		Check()
	end)
	-- (Not while the pet is dead, or dismissed: nothing to feed.)
	function ns.IsPetUnhappy()
		return unhappy and ns.Flag(UnitExists("pet")) and not ns.Flag(UnitIsDead("pet"))
	end
end

-- A group member pinging the minimap brings it up the same way
-- (minimapRevealOnPing), even in a camera mode that hides it. Your own pings don't.
local pingRevealUntil = 0
do
	local pingWatcher = CreateFrame("Frame")
	pcall(pingWatcher.RegisterEvent, pingWatcher, "MINIMAP_PING")
	pingWatcher:SetScript("OnEvent", function(_, _, unit)
		if not (ns.db and ns.db.minimapRevealOnPing) then
			return
		end
		local ok, mine = pcall(UnitIsUnit, unit or "player", "player")
		if ok and ns.Flag(mine) then
			return
		end
		local hold = ns.HoldTime("mouseoverHold") - ns.FadeOutTime()
		pingRevealUntil = GetTime() + ns.FadeInTime() + math.max(0, hold)
	end)
end

-- Someone joining or leaving your group (or you joining or leaving one)
-- brings up the Mouseover groups with it ticked the same way: the raid
-- frames by default. Just the group's size changing, not every roster update.
local rosterRevealUntil = 0
do
	local groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
	local rosterRevealWatcher = CreateFrame("Frame")
	rosterRevealWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	rosterRevealWatcher:SetScript("OnEvent", function()
		local size = GetNumGroupMembers()
		if (issecretvalue and issecretvalue(size)) or type(size) ~= "number" or size == groupSize or not ns.db then
			return
		end
		groupSize = size
		local hold = ns.HoldTime("mouseoverHold") - ns.FadeOutTime()
		rosterRevealUntil = GetTime() + ns.FadeInTime() + math.max(0, hold)
	end)
end

-- Gamepad mode: pressing a gamepad button brings its action bars up, as
-- hovering does with the mouse (gamepadPressReveal): they fade in, then are
-- gone the bars' mouseover time later. The pad's buttons are read each
-- frame (C_GamePad), which leaves the presses to the game; the button event,
-- where the client has one, counts too.
-- Which buttons count is the player's choice (the Gamepad page's list).
-- Besides that,
-- not while fishing (the fish camera on, a cast going, or looting), nor
-- buttons bound to moving, turning or the camera, nor the fishing button
-- while it casts: going by what the button does now (override bindings too).
-- (Not by watching whether you moved or turned after a press: in gamepad mode
-- you turn with the camera all the time, so presses on the move never counted.)
local NO_REVEAL = {
	MOVEFORWARD = true, MOVEBACKWARD = true, TURNLEFT = true, TURNRIGHT = true,
	STRAFELEFT = true, STRAFERIGHT = true, TOGGLEAUTORUN = true, SITORSTAND = true,
	CAMERAZOOMIN = true, CAMERAZOOMOUT = true,
}
-- The buttons a press can come from, for the Gamepad page's list (each
-- ticked or not: db.gamepadPressButtons[key], missing = the default here).
-- Off by default: the right stick (the camera), clicking a stick in (ping
-- and auto-run) and the menu buttons. (Jumping is seen as it happens, so the
-- jump button can stay ticked.) Face buttons go by where they sit: pads print different
-- letters there (a Nintendo-style pad's A is on the right, Xbox's B). The left stick's directions are left to
-- the moving check: they don't always walk you.
ns.GAMEPAD_BUTTONS = {
	{ key = "PAD1", label = L["Bottom face button"], default = true },
	{ key = "PAD2", label = L["Right face button"], default = true },
	{ key = "PAD3", label = L["Left face button"], default = true },
	{ key = "PAD4", label = L["Top face button"], default = true },
	{ key = "PADDUP", label = L["D-pad up"], default = true },
	{ key = "PADDDOWN", label = L["D-pad down"], default = true },
	{ key = "PADDLEFT", label = L["D-pad left"], default = true },
	{ key = "PADDRIGHT", label = L["D-pad right"], default = true },
	{ key = "PADLSHOULDER", label = L["Left bumper (LB)"], default = true },
	{ key = "PADRSHOULDER", label = L["Right bumper (RB)"], default = true },
	{ key = "PADLTRIGGER", label = L["Left trigger (LT)"], default = true },
	{ key = "PADRTRIGGER", label = L["Right trigger (RT)"], default = true },
	{ key = "PADLSTICKUP", label = L["Left stick up"], default = true },
	{ key = "PADLSTICKDOWN", label = L["Left stick down"], default = true },
	{ key = "PADLSTICKLEFT", label = L["Left stick left"], default = true },
	{ key = "PADLSTICKRIGHT", label = L["Left stick right"], default = true },
	{ key = "PADRSTICKUP", label = L["Right stick up"], default = false },
	{ key = "PADRSTICKDOWN", label = L["Right stick down"], default = false },
	{ key = "PADRSTICKLEFT", label = L["Right stick left"], default = false },
	{ key = "PADRSTICKRIGHT", label = L["Right stick right"], default = false },
	{ key = "PADLSTICK", label = L["Left stick click"], default = false },
	{ key = "PADRSTICK", label = L["Right stick click"], default = false },
	{ key = "PADFORWARD", label = L["Start / Menu"], default = false },
	{ key = "PADBACK", label = L["Back / View"], default = false },
}
-- The labels above were made before the language was known: translated again.
ns.OnLanguage(function()
	ns.TranslateFields(ns.COMBAT_SHOW, "label", "tip")
	ns.TranslateFields(ns.HOVER_ROWS, "label", "tip")
	ns.TranslateFields(ns.HOVER_TRIGGERS, "label", "tip")
	ns.TranslateFields(ns.HOVER_GROUPS_DEFAULT, "name")
	ns.TranslateFields(ns.PLACE_SHOW, "label", "tip")
	ns.TranslateFields(ns.GAMEPAD_BUTTONS, "label")
end)
local PAD_BUTTON_DEFAULT = {}
for _, item in ipairs(ns.GAMEPAD_BUTTONS) do
	PAD_BUTTON_DEFAULT[item.key] = item.default
end

-- The game's own name for a button, as your pad labels it ("" if none).
function ns.PadButtonText(button)
	local ok, text = pcall(GetBindingText, button)
	if ok and type(text) == "string" and text ~= button then
		return text
	end
	return ""
end

-- Whether presses of this button reveal the bars (buttons not listed do).
function ns.IsPadButtonOn(button)
	local on = ns.db.gamepadPressButtons[button]
	if on == nil then
		on = PAD_BUTTON_DEFAULT[button]
	end
	return on ~= false
end

local function RevealsBars(button)
	if not ns.IsPadButtonOn(button) then
		return false
	end
	local ok, action = pcall(GetBindingAction, button, true)
	if not ok or type(action) ~= "string" then
		return true
	end
	return not (NO_REVEAL[action] or action:find("^CLICK CinematicFishingCastButton"))
end
local padRevealUntil = 0
-- A press that starts a cast is seen just before the cast begins, so presses
-- wait CAST_WAIT seconds and don't count if you're fishing by then. Nor if
-- you're in the air by then: that press jumped, whichever button jumps on
-- your pad.
local CAST_WAIT = 0.25
local pendingPress -- { at, button } while a press waits
local function Fishing()
	return (ns.IsFishingNow and ns.IsFishingNow()) or (LootFrame and ns.Flag(LootFrame:IsShown())) or false
end
local function DebugPress(button, text)
	if ns.padDebug then
		ns.Print(("pad %s: %s"):format(tostring(button), text))
	end
end
local function OnPadButton(button, via)
	local ok, action = pcall(GetBindingAction, button, true)
	DebugPress(button, ("%s (the game calls it %s), bound to \"%s\""):format(via, ns.PadButtonText(button),
		ok and tostring(action) or "?"))
	-- Fishing (casting, catching, looting): presses are for that.
	if Fishing() then
		DebugPress(button, "not revealing (fishing)")
		return
	end
	if not RevealsBars(button) then
		DebugPress(button, ("not revealing (%s)"):format(not ns.IsPadButtonOn(button)
			and "unticked on the Gamepad page" or "what it's bound to"))
		return
	end
	if ns.db and ns.db.gamepadPressReveal and not pendingPress then
		pendingPress = { at = GetTime(), button = button }
	end
end
-- A waiting press: dropped if it started fishing, else the bars come up.
local function CheckPendingPress()
	local press = pendingPress
	if not press then
		return
	end
	if Fishing() then
		pendingPress = nil
		DebugPress(press.button, "not revealing (started fishing)")
	elseif ns.Flag(IsFalling()) then
		pendingPress = nil
		DebugPress(press.button, "not revealing (jumped)")
	elseif GetTime() - press.at >= CAST_WAIT then
		pendingPress = nil
		DebugPress(press.button, "reveals")
		-- (The bars' own times, Gamepad page: see GroupFadeTime.)
		local hold = ns.db.gamepadPressHold - ns.db.gamepadBarsFadeOut
		padRevealUntil = GetTime() + ns.db.gamepadBarsFadeIn + math.max(0, hold)
	end
end
local padWatcher = CreateFrame("Frame")
ns.padEventOK = pcall(padWatcher.RegisterEvent, padWatcher, "GAME_PAD_BUTTON_DOWN")
padWatcher:SetScript("OnEvent", function(_, _, button)
	OnPadButton(button, "event")
end)
-- Buttons held last frame (index -> true), to see new presses.
local padHeld = {}
local function ButtonName(index)
	local ok, name = pcall(C_GamePad.ButtonIndexToBinding, index)
	return ok and name or ("button" .. index)
end
-- Moving and auto-run in gamepad mode: the left stick walks you and clicking
-- it toggles auto-run, all handled by the gamepad UI itself (no bindings, so
-- none of the Move*/ToggleAutoRun functions Core.lua hooks are called). So
-- the stick's directions held count as movement keys (ns.PadMovementHeld),
-- up or down ends auto-run as forward and back do, and the click toggles it.
local PAD_MOVE = { PADLSTICKUP = true, PADLSTICKDOWN = true, PADLSTICKLEFT = true, PADLSTICKRIGHT = true }
local PAD_ENDS_AUTORUN = { PADLSTICKUP = true, PADLSTICKDOWN = true }
local padMoveHeld = false
function ns.PadMovementHeld()
	return padMoveHeld
end
padWatcher:SetScript("OnUpdate", ns.Profiled("Gamepad watch", function()
	CheckPendingPress()
	if not (ns.db and C_GamePad and C_GamePad.GetDeviceMappedState and ns.IsGamePadOn()) then
		padMoveHeld = false
		return
	end
	local ok, state = pcall(C_GamePad.GetDeviceMappedState, C_GamePad.GetActiveDeviceID
		and C_GamePad.GetActiveDeviceID() or nil)
	if not ok or type(state) ~= "table" or type(state.buttons) ~= "table" then
		padMoveHeld = false
		return
	end
	local moving = false
	for index, down in ipairs(state.buttons) do
		local name = (down or padHeld[index]) and ButtonName(index)
		if down and PAD_MOVE[name] then
			moving = true
		end
		if down and not padHeld[index] then
			if name == "PADLSTICK" and ns.OnAutoRunToggle then
				ns.OnAutoRunToggle()
			elseif PAD_ENDS_AUTORUN[name] then
				ns.autoRunning = false
			end
			OnPadButton(name, "read")
		end
		padHeld[index] = down or nil
	end
	padMoveHeld = moving
end))

-- A quest timer running (Classic clients; retail has no quest timer box).
-- Clients without GetQuestTimers go by the box: the game only shows it while
-- a timer runs (the fade only changes its alpha).
local function HasQuestTimer()
	if ns.isRetail then
		return false
	end
	if GetQuestTimers then
		return select("#", GetQuestTimers()) > 0
	end
	local frame = _G.QuestTimerFrame
	return frame ~= nil and ns.Flag(frame:IsShown())
end

-- A cooldown still recharging in the Cooldown Manager's spell bars (not its
-- buff bars) or Enhanced Cooldown Manager's cooldown bars, longer than the
-- global cooldown. Each icon's spell is asked about first; failing that, the
-- cooldown swipe on it. Looked at a few times a second. The game keeps some
-- of this secret (in fights, and on some clients whether the bars are shown):
-- a secret time counts as ready, a secret "shown" as shown.
local COOLDOWN_VIEWERS = { EssentialCooldownViewer = true, UtilityCooldownViewer = true }
local GCD = 1.6
local cooldownCheckedAt, cooldownRecharging = 0, false

local function Secret(...)
	if not issecretvalue then return false end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then return true end
	end
	return false
end

-- Hidden for sure (a secret answer isn't).
local function Hidden(frame)
	local ok, shown = pcall(frame.IsShown, frame)
	return ok and not Secret(shown) and not shown
end

-- The spell an icon shows, if it says.
local function ItemSpell(item)
	if item.GetSpellID then
		local ok, id = pcall(item.GetSpellID, item)
		if ok and not Secret(id) and type(id) == "number" and id > 0 then return id end
	end
	-- (Only type() and Secret() on values that may be secret: testing one errors.)
	local cooldownID = item.cooldownID
	if type(cooldownID) == "nil" and item.GetCooldownID then
		local ok, id = pcall(item.GetCooldownID, item)
		if ok then cooldownID = id end
	end
	if type(cooldownID) == "number" and not Secret(cooldownID)
		and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
		local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
		if ok and type(info) == "table" then
			for _, field in ipairs({ "overrideSpellID", "spellID" }) do
				local id = info[field]
				if type(id) == "number" and not Secret(id) and id > 0 then return id end
			end
		end
	end
end

-- A spell's cooldown: start and duration in seconds, or nil if the game won't say.
local function SpellCooldown(id)
	local ok, start, duration
	if C_Spell and C_Spell.GetSpellCooldown then
		local info
		ok, info = pcall(C_Spell.GetSpellCooldown, id)
		if ok and type(info) == "table" then
			start, duration = info.startTime, info.duration
		end
	elseif GetSpellCooldown then
		ok, start, duration = pcall(GetSpellCooldown, id)
	end
	if not ok or Secret(start, duration) or type(start) ~= "number" or type(duration) ~= "number" then
		return nil
	end
	return start, duration
end

-- A cooldown swipe's start and duration, in seconds, or nil.
local function SwipeTimes(cooldown)
	if not cooldown.GetCooldownTimes then return nil end
	local ok, start, duration = pcall(cooldown.GetCooldownTimes, cooldown)
	if not ok or Secret(start, duration) or type(start) ~= "number" or type(duration) ~= "number" then
		return nil
	end
	return start / 1000, duration / 1000
end

-- Calls visit(frame, kind) for each icon ("item", one with a spell) and each
-- cooldown swipe ("swipe") under frame.
local function EachCooldownPart(frame, depth, visit)
	for _, child in ipairs({ frame:GetChildren() }) do
		if not Hidden(child) then
			local isCooldown = child.GetObjectType and child:GetObjectType() == "Cooldown"
			if isCooldown then
				visit(child, "swipe")
			elseif child.GetSpellID or child.GetCooldownID or type(child.cooldownID) ~= "nil" then
				visit(child, "item")
			end
			if not isCooldown and depth > 0 then
				EachCooldownPart(child, depth - 1, visit)
			end
		end
	end
end

local function Recharging(start, duration, now)
	return duration > GCD and start + duration > now
end

-- The Cooldown Manager frames to look in.
local function EachCooldownFrame(visit)
	for _, entry in ipairs(ns.managed) do
		local frame = entry.frame
		if COOLDOWN_VIEWERS[entry.name] or (entry.group == "addon:fecm" and frame.kind == "cooldown") then
			visit(entry, frame)
		end
	end
end

local function AnyCooldownRecharging(now)
	if now - cooldownCheckedAt < 0.25 then
		return cooldownRecharging
	end
	cooldownCheckedAt = now
	local found = false
	EachCooldownFrame(function(_, frame)
		if found or Hidden(frame) then return end
		EachCooldownPart(frame, 3, function(part, kind)
			if found then return end
			local start, duration
			if kind == "item" then
				local id = ItemSpell(part)
				if id then start, duration = SpellCooldown(id) end
			else
				start, duration = SwipeTimes(part)
			end
			if start and Recharging(start, duration, now) then found = true end
		end)
	end)
	cooldownRecharging = found
	return found
end

-- The Cooldown Manager page's "Only when ready in combat" spells
-- (db.cooldownReadyOnly: spell ID -> true): out of fights, and in fights
-- while it's recharging, a spell's icon fades out, the rest of its bar as
-- usual (the icon's place stays: it leaves a gap). It comes back once it's
-- ready, or with Show Early (db.cooldownEarlyOn[spell ID]) a little before:
-- db.cooldownReadyEarly[spell ID] seconds, or by default READY_EARLY of its
-- cooldown. Recharging: its swipe
-- says so, when the game lets it be read; in fights WoW Forever keeps it
-- secret, so then it goes by when you last cast the spell and how long its
-- cooldown is. Not knowing (say, cast before a reload), it shows.
-- (Sec: quicker than the CineMode fades, it's a cue. Coming back eases in;
-- going, as it's cast, it's out of the way at once.)
local READY_FADE_IN, READY_FADE_OUT = 0.5, 0.25
ns.READY_EARLY = 0.15 -- (of its cooldown)
local lastCastOf = {} -- spell ID -> when you last cast it
local cooldownLength = {} -- spell ID -> its cooldown (sec), last read off its swipe
local iconSpell = setmetatable({}, { __mode = "k" }) -- icon -> its spell, last read (for when it's secret)
local readyTargets = {} -- icon -> 0 or 1, for the ticked spells' icons
local readyAlpha = {} -- icon -> its alpha, while not full
local readyCheckedAt = 0

do
	local castWatcher = CreateFrame("Frame")
	castWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	castWatcher:SetScript("OnEvent", function(_, _, _, _, spellID)
		if not Secret(spellID) and type(spellID) == "number" then
			lastCastOf[spellID] = GetTime()
		end
	end)
end

function ns.CooldownLength(id)
	if cooldownLength[id] then
		return cooldownLength[id]
	end
	if GetSpellBaseCooldown then
		local ok, ms = pcall(GetSpellBaseCooldown, id)
		if ok and not Secret(ms) and type(ms) == "number" and ms > 0 then
			return ms / 1000
		end
	end
end

local CooldownLength = ns.CooldownLength

-- How long before a spell's icon is ready it comes back (sec), or nil until its cooldown's known.
local function ReadyEarly(id, length)
	if not ns.db.cooldownEarlyOn[id] then
		return 0 -- (Show Early unticked: back once it's ready)
	end
	return ns.db.cooldownReadyEarly[id] or (length and length * ns.READY_EARLY)
end

-- How long until an icon's spell is ready (sec, 0 when it is), and its
-- cooldown; nil when it can't tell.
local function IconTimeLeft(icon, id, now)
	local start, duration = SpellCooldown(id)
	if not start then
		EachCooldownPart(icon, 1, function(part, kind)
			if kind == "swipe" and not start then
				start, duration = SwipeTimes(part)
			end
		end)
	end
	if start then
		if not Recharging(start, duration, now) then
			return 0, CooldownLength(id)
		end
		cooldownLength[id] = duration
		return start + duration - now, duration
	end
	local cast, length = lastCastOf[id], CooldownLength(id)
	if cast and length then
		return math.max(0, cast + length - now), length
	end
	return nil
end

-- Whether a ticked spell's icon shows: in fights, once it's nearly ready (or
-- when it can't tell).
local function IconShows(icon, id, now)
	local left, length = IconTimeLeft(icon, id, now)
	return left == nil or left <= (ReadyEarly(id, length) or 0)
end

-- Calls visit(icon, spell) for each icon in the Cooldown Manager's spell bars.
local function EachCooldownIcon(visit)
	EachCooldownFrame(function(entry, frame)
		if COOLDOWN_VIEWERS[entry.name] then
			EachCooldownPart(frame, 3, function(part, kind)
				if kind == "item" then
					local id = ItemSpell(part)
					if id then
						iconSpell[part] = id
					end
					id = id or iconSpell[part]
					if id then
						visit(part, id)
					end
				end
			end)
		end
	end)
end

-- The spells in the Cooldown Manager's spell bars now, in the order found (for its page).
function ns.CooldownManagerSpells()
	local ids, listed = {}, {}
	EachCooldownIcon(function(_, id)
		if not listed[id] then
			listed[id] = true
			ids[#ids + 1] = id
		end
	end)
	return ids
end

-- Every icon faded here back to full.
local function ReleaseReadyIcons()
	wipe(readyTargets)
	for icon in pairs(readyAlpha) do
		if not IsForbidden(icon) then
			icon:SetAlpha(1)
		end
		readyAlpha[icon] = nil
	end
end

-- The master switches changing (on their pages, or with a profile): frames
-- no longer handled are let go, and switched back on they're picked up and
-- fade from now. Looked at each frame.
local switchesWere = {}
local function SyncSwitches()
	local changed, turnedOn = false, false
	for _, key in ipairs(ns.HANDLE_SWITCHES) do
		local on = ns.db[key] and true or false
		if switchesWere[key] ~= nil and switchesWere[key] ~= on then
			changed = true
			turnedOn = turnedOn or on
		end
		switchesWere[key] = on
	end
	if not changed then
		return
	end
	for i = #ns.managed, 1, -1 do
		local entry = ns.managed[i]
		if not GroupHandled(entry.group) then
			RemoveFrame(entry.frame)
		end
	end
	if not GroupHandled("cooldowns") then
		ReleaseReadyIcons() -- (the "Only when ready in combat" icons)
	end
	if not GroupHandled("prd") then
		ns.SetPersonalPlateAlpha(1) -- (Forever's: your own nameplate)
	end
	if turnedOn then
		ns.BuildManagedList()
	end
end
ns.SyncSwitches = SyncSwitches

local function UpdateReadyOnly(elapsed, now)
	SyncSwitches()
	if not GroupHandled("cooldowns") then
		return
	end
	if now - readyCheckedAt >= 0.1 then
		readyCheckedAt = now
		wipe(readyTargets)
		local list = ns.db.cooldownReadyOnly
		if next(list) then
			local inCombat = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
			EachCooldownIcon(function(icon, id)
				if list[id] then
					readyTargets[icon] = (inCombat and IconShows(icon, id, now)) and 1 or 0
				end
			end)
		end
	end
	for icon, target in pairs(readyTargets) do
		if target < 1 and not readyAlpha[icon] then
			readyAlpha[icon] = 1
		end
	end
	-- (Re-applied while faded, in case the game sets it; back to full, and
	-- unticked or reused for another spell, it's left alone again.)
	for icon, alpha in pairs(readyAlpha) do
		local target = readyTargets[icon] or 1
		alpha = ns.Approach(alpha, target, elapsed, target > alpha and READY_FADE_IN or READY_FADE_OUT)
		if not IsForbidden(icon) then
			icon:SetAlpha(alpha)
		end
		readyAlpha[icon] = alpha < 1 and alpha or nil
	end
end
UpdateReadyOnly = ns.Profiled("UpdateReadyOnly", UpdateReadyOnly)

-- /cine debug cooldowns: what the Cooldown Manager check sees.
function ns.ReportCooldowns()
	local now = GetTime()
	local any = false
	local function Show(value)
		if Secret(value) then return "secret" end
		return type(value) == "number" and ("%.1f"):format(value) or tostring(value)
	end
	EachCooldownFrame(function(entry, frame)
		any = true
		local ok, shown = pcall(frame.IsShown, frame)
		ns.Print(("%s: shown=%s"):format(entry.name or entry.group, ok and Show(shown) or "?"))
		local count = 0
		EachCooldownPart(frame, 3, function(part, kind)
			count = count + 1
			if count > 20 then return end
			if kind == "item" then
				local id = ItemSpell(part)
				local start, duration
				if id then start, duration = SpellCooldown(id) end
				print(("  icon spell=%s cooldown %s"):format(tostring(id), start
					and ("%.1fs left of %.1fs"):format(math.max(0, start + duration - now), duration)
					or "unreadable"))
				if id and ns.db.cooldownReadyOnly[id] then
					local left, length = IconTimeLeft(part, id, now)
					local early = ReadyEarly(id, length)
					local cast = lastCastOf[id]
					print(("    only when ready in combat: %s, back %s early (last cast %s, cooldown %s)"):format(
						left == nil and "can't tell, shown" or (left > 0 and ("%.0fs left"):format(left) or "ready"),
						early and ("%.0fs"):format(early) or "?",
						cast and ("%.0fs ago"):format(now - cast) or "not seen",
						length and ("%.0fs"):format(length) or "unknown"))
				end
			else
				local start, duration = SwipeTimes(part)
				print(("  swipe %s"):format(start
					and ("%.1fs left of %.1fs"):format(math.max(0, start + duration - now), duration)
					or "unreadable"))
			end
		end)
		if count == 0 then print("  (no icons or swipes found)") end
	end)
	if not any then
		ns.Print("no Cooldown Manager frames found among the faded frames")
	end
	cooldownCheckedAt = 0
	ns.Print("recharging now: " .. tostring(AnyCooldownRecharging(now)))
end

-- /cine debug frame <text>: how the faded frames with <text> in their name
-- stand (the name is matched ignoring case: slash commands come lowercased).
function ns.ReportFrames(text)
	local found = false
	for _, entry in ipairs(ns.managed) do
		local name = entry.name or entry.frame:GetDebugName()
		if name:lower():find(text, 1, true) then
			found = true
			local frame = entry.frame
			local function Number(value)
				if issecretvalue and issecretvalue(value) then
					return "secret"
				end
				return value and ("%.2f"):format(value) or "-"
			end
			local parent = frame:GetParent()
			ns.Print(("%s [%s] shown=%s visible=%s nested=%s"):format(name, entry.group,
				tostring(frame:IsShown()), tostring(frame:IsVisible()), tostring(entry.nested or false)))
			ns.Print(("  alpha now %s, fade %s, applied %s, base %s, own=%s hooked=%s scale %s"):format(
				Number(frame:GetAlpha()), Number(entry.alpha), Number(entry.applied), Number(entry.baseAlpha),
				tostring(entry.ownAlpha or false), tostring(alphaHooked[frame] == entry),
				Number(frame:GetScale())))
			ns.Print(("  parent %s (shown=%s, alpha %s, on screen %s)"):format(
				parent and (parent:GetName() or parent:GetDebugName()) or "none",
				tostring(parent and parent:IsShown()), Number(parent and parent:GetAlpha()),
				Number(frame.GetEffectiveAlpha and frame:GetEffectiveAlpha())))
		end
	end
	if not found then
		ns.Print("no faded frames with " .. text .. " in the name")
	end
end

-- /cine debug frames: the shown top-level frames not faded, and every global
-- frame with GamePad in its name, to the log (and chat), for finding frames
-- a client feature adds (WoW Forever's gamepad mode).
function ns.ReportUnfadedFrames()
	local function Report(text)
		ns.Print(text)
		ns.Log("frames", text)
	end
	local cvar = C_CVar and C_CVar.GetCVar or GetCVar
	Report(("GamePadEnable=%s C_GamePad=%s"):format(tostring(cvar and cvar("GamePadEnable")),
		tostring(C_GamePad ~= nil)))
	local function Describe(frame)
		local measured, left, bottom, width, height = pcall(frame.GetRect, frame)
		if not measured then
			left, bottom, width, height = nil, nil, nil, nil
		end
		local parent = frame:GetParent()
		return ("%s %s %s strata=%s rect=%d,%d %dx%d parent=%s"):format(frame:GetName() or "(unnamed)",
			frame:GetDebugName(), frame:GetObjectType(), frame.GetFrameStrata and frame:GetFrameStrata() or "-",
			left or -1, bottom or -1,
			width or 0, height or 0, parent and (parent:GetName() or parent:GetDebugName()) or "none")
	end
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if not IsForbidden(frame) and not seen[frame] and ns.Flag(frame:IsVisible()) and frame ~= ns.letterbox then
			Report("unfaded: " .. Describe(frame))
		end
	end
	-- Small things at the middle of the screen (gamepad mode's dot), a few
	-- levels down, with what they draw.
	local centerX, centerY = UIParent:GetCenter()
	local function Textures(frame)
		local list = {}
		for _, region in ipairs(ReadParts(frame, "GetRegions") or {}) do
			if not IsForbidden(region) and region.GetTexture and ns.Flag(region:IsVisible()) then
				list[#list + 1] = tostring(region.GetAtlas and region:GetAtlas() or region:GetTexture())
			end
		end
		return table.concat(list, ",")
	end
	local function AtCenter(frame, depth)
		if IsForbidden(frame) or not ns.Flag(frame:IsVisible()) then
			return
		end
		-- (Nameplates can't be measured: they error. They're reported below.)
		local measured, left, bottom, width, height = pcall(frame.GetRect, frame)
		if not measured then
			return
		end
		if left and width < 100 and height < 100 and left <= centerX and left + width >= centerX
			and bottom <= centerY and bottom + height >= centerY then
			Report(("center: %s alpha=%.2f textures=%s"):format(Describe(frame), frame:GetEffectiveAlpha(),
				Textures(frame)))
		end
		if depth > 0 then
			for _, child in ipairs(ReadParts(frame, "GetChildren") or {}) do
				AtCenter(child, depth - 1)
			end
		end
	end
	AtCenter(UIParent, 5)
	AtCenter(WorldFrame, 2)
	-- The soft targets' plates (gamepad mode's interact prompt sits on one),
	-- with what's shown inside them.
	local function Inside(frame, depth, indent)
		for _, child in ipairs(ReadParts(frame, "GetChildren") or {}) do
			if not IsForbidden(child) and ns.Flag(child:IsShown()) then
				Report(("%s%s %s textures=%s"):format(indent, child:GetDebugName(), child:GetObjectType(),
					Textures(child)))
				if depth > 0 then
					Inside(child, depth - 1, indent .. "  ")
				end
			end
		end
	end
	for _, unit in ipairs({ "softinteract", "softenemy", "softfriend", "target" }) do
		local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
			and C_NamePlate.GetNamePlateForUnit(unit)
		Report(("unit %s: exists=%s plate=%s"):format(unit, tostring(UnitExists(unit)),
			plate and (IsForbidden(plate) and "forbidden" or plate:GetDebugName()) or "none"))
		if plate and not IsForbidden(plate) then
			Inside(plate, 4, "  ")
		end
	end
	-- Settings that may draw it (C_Console lists every setting the game has).
	if C_Console and C_Console.GetAllCommands then
		local cvar = C_CVar and C_CVar.GetCVar or GetCVar
		for _, command in ipairs(C_Console.GetAllCommands()) do
			local name = command.command
			if type(name) == "string" then
				local lower = name:lower()
				if lower:find("reticle") or lower:find("crosshair") or lower:find("cursor")
					or lower:find("gamepad") or lower:find("softtarget") then
					Report(("cvar %s = %s"):format(name, tostring(cvar(name))))
				end
			end
		end
	end
	for name, value in pairs(_G) do
		if type(name) == "string" and name:lower():find("gamepad") and IsFrame(value)
			and value.GetRect and not IsForbidden(value) then
			Report(("gamepad global: %s shown=%s faded=%s"):format(Describe(value), tostring(value:IsVisible()),
				tostring(seen[value] or false)))
		end
	end
end

-- /cine debug questtimer: why the quest timer is or isn't kept up.
function ns.ReportQuestTimer()
	local frame = _G.QuestTimerFrame
	local timers = {}
	for i, seconds in ipairs(GetQuestTimers and { GetQuestTimers() } or {}) do
		timers[i] = tostring(seconds)
	end
	ns.Print(("quest timer: running=%s option=%s retail=%s timers=%s"):format(tostring(HasQuestTimer()),
		tostring(ns.db.questTimerShow), tostring(ns.isRetail),
		GetQuestTimers and table.concat(timers, ",") or "no API"))
	if not frame then
		ns.Print("no QuestTimerFrame")
		return
	end
	local parents = {}
	local parent = frame:GetParent()
	while parent do
		parents[#parents + 1] = (parent:GetName() or "?") .. (seen[parent] and "(faded)" or "")
		parent = parent:GetParent()
	end
	ns.Print("parents: " .. table.concat(parents, " > "))
	for _, entry in ipairs(ns.managed) do
		if entry.frame == frame then
			ns.Print(("group=%s alpha=%.2f nested=%s shown=%s ignoreParentAlpha=%s"):format(entry.group,
				entry.alpha, tostring(entry.nested or false), tostring(frame:IsShown()),
				tostring(frame.IsIgnoringParentAlpha and frame:IsIgnoringParentAlpha())))
			return
		end
	end
	ns.Print("QuestTimerFrame isn't managed")
end

local DEATH_FADE_TIME = 0.5 -- seconds for the UI to go when you die (death camera)

-- How long a group takes to fade in or out: the shared fade times, but for
-- gamepad mode's action bars, which have their own (Gamepad page) so they
-- come and go quickly with button presses.
local function GroupFadeTime(group, fadeIn)
	if group == "gamepadbars" then
		return fadeIn and ns.db.gamepadBarsFadeIn or ns.db.gamepadBarsFadeOut
	end
	return fadeIn and ns.FadeInTime() or ns.FadeOutTime()
end
-- The portrait shown while health or power recovers (addons' can stand in
-- for the game's: see ns.AddPortraitFrame).
local PORTRAIT_FRAMES = { PlayerFrame = true }

-- Swing timer page (Classic clients' own swing timer): a bar fades out once
-- its weapon hasn't been used for a while, and the off-hand's can go for
-- good. A bar counts as used while it runs down (after a real swing or
-- shot). Without a bar to read, melee counts while auto-attack is on and the
-- target is in melee range, ranged while Auto Shot or a wand repeats and the
-- target is in its range, and on single shots (Shoot Bow or Throw).
-- Each holds on past its last use for the bar to run down to 0 and the
-- swingHideAfter seconds after.
-- (In a do block: the file is near Lua's 200 locals.)
do
	local BAR_WEAPON = {
		SwingTimerMainHandFrame = "melee", SwingTimerOffHandFrame = "melee", SwingTimerRangedFrame = "ranged",
	}
	-- Auto Shot, Shoot (wands; and Shoot as later clients name every ranged weapon's), Throw,
	-- Shoot Bow, Shoot Gun, Shoot Crossbow.
	local RANGED_SHOTS = { [75] = true, [5019] = true, [3018] = true, [2764] = true, [2480] = true,
		[7918] = true, [7919] = true }
	local usedAt = { melee = -math.huge, ranged = -math.huge }
	local inUse = { melee = false, ranged = false }

	local function Number(value)
		if type(value) ~= "number" or (issecretvalue and issecretvalue(value)) then
			return nil
		end
		return value
	end

	-- Seconds the weapon's bar takes to run down.
	local function Speed(weapon)
		local speed
		if weapon == "ranged" then
			speed = UnitRangedDamage and Number((UnitRangedDamage("player")))
		else
			speed = UnitAttackSpeed and Number((UnitAttackSpeed("player")))
		end
		return math.min(speed or 2, 5)
	end

	-- (Switching off doesn't count as a use: a hunter's /startattack plus
	-- /cast !Auto Shot macro switches auto-attack on and straight off again.
	-- While a weapon's switched on and in reach, each check counts instead.)
	local function SetInUse(weapon, on)
		inUse[weapon] = on
	end

	-- Spells whose range says whether the target is in reach of each weapon:
	-- Auto Attack, then a hunter's melee strikes (in case the game won't range
	-- check Auto Attack); Auto Shot (too close counts as out of range), then Shoot.
	local RANGE_SPELLS = { melee = { 6603, 2973, 2974, 1495 }, ranged = { 75, 5019 } }

	-- Whether the target is in range of the weapon: true, false, or nil when
	-- the game can't say (no target, a secret answer), which counts as in range.
	local function InRange(weapon)
		if not UnitExists("target") then
			return nil
		end
		for _, spellID in ipairs(RANGE_SPELLS[weapon]) do
			local ok, inRange
			if C_Spell and C_Spell.IsSpellInRange then
				ok, inRange = pcall(C_Spell.IsSpellInRange, spellID, "target")
			elseif IsSpellInRange and GetSpellInfo then
				local spellName = GetSpellInfo(spellID)
				if spellName then
					ok, inRange = pcall(IsSpellInRange, spellName, "target")
				end
			end
			if ok and not (issecretvalue and issecretvalue(inRange)) then
				if inRange == true or inRange == 1 then
					return true
				elseif inRange == false or inRange == 0 then
					return false
				end
			end
		end
		return nil
	end

	if not ns.isRetail then
		-- (No combat log for the swings themselves: registering for it gets the
		-- addon blocked on Forever.)
		local watcher = CreateFrame("Frame")
		watcher:RegisterEvent("PLAYER_ENTER_COMBAT") -- (auto-attack on)
		watcher:RegisterEvent("PLAYER_LEAVE_COMBAT")
		watcher:RegisterEvent("START_AUTOREPEAT_SPELL")
		watcher:RegisterEvent("STOP_AUTOREPEAT_SPELL")
		watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		watcher:SetScript("OnEvent", function(_, event, _, _, spellID)
			if event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT" then
				SetInUse("melee", event == "PLAYER_ENTER_COMBAT")
			elseif event == "START_AUTOREPEAT_SPELL" or event == "STOP_AUTOREPEAT_SPELL" then
				SetInUse("ranged", event == "START_AUTOREPEAT_SPELL")
			elseif Number(spellID) and RANGED_SHOTS[spellID] then
				usedAt.ranged = GetTime()
			end
		end)
		-- (Auto-attack already on after a /reload.)
		local ok, attacking = pcall(IsCurrentSpell, 6603)
		inUse.melee = ok and attacking == true
	end

	-- The game's own bar shows whether the weapon has really been used: it
	-- sits still (at 0.0) until a swing or shot, then runs down. Its status
	-- bar's value, or nil when there's none to read (a secret value, say).
	local statusBars = {}
	local function FindStatusBar(frame, depth)
		if frame:IsObjectType("StatusBar") then
			return frame
		end
		if depth > 0 then
			for _, child in ipairs({ frame:GetChildren() }) do
				local bar = FindStatusBar(child, depth - 1)
				if bar then
					return bar
				end
			end
		end
	end
	local function BarValue(name)
		local bar = statusBars[name]
		if bar == nil then
			local frame = _G[name]
			if not frame then
				return nil
			end
			local ok, found = pcall(FindStatusBar, frame, 2)
			bar = ok and found or false
			statusBars[name] = bar
		end
		if not bar then
			return nil
		end
		local ok, value = pcall(bar.GetValue, bar)
		return ok and Number(value) or nil
	end
	local lastValue, moves, lastDecision = {}, {}, {}

	-- /cine debug swing: each bar's showing or fading, as it changes, and why.
	local function DebugSwing(name, unused, why)
		if ns.swingDebug and lastDecision[name] ~= unused then
			ns.Print(("swing %s: %s (%s)"):format(name, unused and "fades" or "shows", why))
		end
		lastDecision[name] = unused
		return unused
	end

	function ns.ReportSwing()
		for name in pairs(BAR_WEAPON) do
			local frame = _G[name]
			local value = BarValue(name)
			local bar = statusBars[name]
			local minValue, maxValue
			if bar then
				local ok, a, b = pcall(bar.GetMinMaxValues, bar)
				minValue, maxValue = ok and Number(a), ok and Number(b)
			end
			local weapon = BAR_WEAPON[name]
			ns.Print(("%s: frame %s, status bar %s, value %s (%s-%s), %s switched on %s, in range %s, last used %s sec ago"):format(
				name, frame and "yes" or "no", bar and (bar:GetName() or "unnamed") or "none", tostring(value),
				tostring(minValue), tostring(maxValue), weapon, tostring(inUse[weapon]), tostring(InRange(weapon)),
				usedAt[weapon] > -math.huge and ("%.1f"):format(GetTime() - usedAt[weapon]) or "never"))
		end
	end

	-- Whether the swing timer frame is to be faded out (it fades at the usual speed).
	function ns.IsSwingBarUnused(name)
		local weapon = BAR_WEAPON[name]
		if not weapon then
			return false
		end
		if not ns.db.handleSwing then
			return false
		end
		if name == "SwingTimerOffHandFrame" and ns.db.swingHideOffHand then
			return true
		end
		if not ns.db.swingSmartShow then
			return false
		end
		-- The bar moving: a real swing or shot (switched on with nothing in
		-- reach, it stays still). It has to move on two checks running: auto-
		-- attack switching on can jump it once without a swing.
		local value = BarValue(name)
		if value then
			if lastValue[name] and value ~= lastValue[name] then
				moves[name] = (moves[name] or 0) + 1
				if moves[name] >= 2 then
					usedAt[weapon] = GetTime()
				end
			else
				moves[name] = 0
			end
			local previous = lastValue[name]
			lastValue[name] = value
			return DebugSwing(name, GetTime() - usedAt[weapon] > ns.db.swingHideAfter,
				("bar %s -> %s"):format(tostring(previous), tostring(value)))
		end
		-- No bar to read: switched on and the target in reach: in use (and it holds on from
		-- here once it isn't). Switched on out of reach doesn't count: a
		-- hunter's /startattack plus /cast !Auto Shot macro turns on both.
		local inRange = InRange(weapon)
		if inUse[weapon] and inRange ~= false then
			usedAt[weapon] = GetTime()
			return DebugSwing(name, false, "no bar to read; switched on, in range " .. tostring(inRange))
		end
		return DebugSwing(name, GetTime() - usedAt[weapon] > Speed(weapon) + ns.db.swingHideAfter,
			"no bar to read; switched on " .. tostring(inUse[weapon]) .. ", in range " .. tostring(inRange))
	end

	-- Ranged bar on top (swingRangedOnTop<CLASS>, for your class): the main hand and ranged bars
	-- trade places. Each takes the other's anchors, and one anchored to the
	-- other (stacked) is anchored the other way round. The game's own anchors
	-- are kept (and taken afresh whenever it moves a bar), so it can be undone.
	local order = { swapped = false, game = {}, moving = false }

	local function ReadPoints(frame)
		local points = {}
		for i = 1, frame:GetNumPoints() do
			local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
			if not (Number(x) and Number(y)) then
				return nil -- (secret: leave it alone)
			end
			points[i] = { point, relativeTo, relativePoint, x, y }
		end
		return points
	end

	local function SetPoints(frame, points, from, to)
		order.moving = true
		frame:ClearAllPoints()
		for _, p in ipairs(points) do
			frame:SetPoint(p[1], p[2] == from and to or p[2], p[3], p[4], p[5])
		end
		order.moving = false
	end

	local function Apply(swap)
		local main, ranged = _G.SwingTimerMainHandFrame, _G.SwingTimerRangedFrame
		if not (main and ranged) or InCombatLockdown() and (main:IsProtected() or ranged:IsProtected()) then
			return
		end
		local mainPoints = order.game[main] or ReadPoints(main)
		local rangedPoints = order.game[ranged] or ReadPoints(ranged)
		if not (mainPoints and rangedPoints and #mainPoints > 0 and #rangedPoints > 0) then
			return
		end
		order.game[main], order.game[ranged] = mainPoints, rangedPoints
		if not order.hooked then
			order.hooked = true
			-- The game moving a bar: its new anchors are the game's, and the swap is done again.
			local function OnMoved(frame)
				if order.moving then return end
				order.game[frame] = nil
				order.swapped = nil -- (looked at next tick)
			end
			hooksecurefunc(main, "SetPoint", OnMoved)
			hooksecurefunc(ranged, "SetPoint", OnMoved)
		end
		if swap then
			SetPoints(main, rangedPoints, main, ranged)
			SetPoints(ranged, mainPoints, ranged, main)
		else
			SetPoints(main, mainPoints)
			SetPoints(ranged, rangedPoints)
		end
		order.swapped = swap
	end

	-- Each tick: the bars as the setting (and the page's master switch) say.
	function ns.UpdateSwingOrder()
		local swap = ns.db.handleSwing and ns.db["swingRangedOnTop" .. select(2, UnitClass("player"))]
			and true or false
		if order.swapped ~= swap then
			-- (Not swapped and the game's anchors not taken yet: nothing to put back.)
			if swap or next(order.game) then
				if not pcall(Apply, swap) then
					order.swapped = swap -- (an error: not tried again every tick)
				end
			else
				order.swapped = false
			end
		end
	end
end

function ns.UpdateFrames(cinematic, elapsed)
	local now = GetTime()
	UpdateReadyOnly(elapsed, now)
	if not ns.isRetail then
		ns.UpdateSwingOrder()
	end
	local combatShown
	if cinematic then
		combatShown = GetCombatShownFrames()
	end
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		lastCombatAt = now
		buffPeekUntil = 0 -- (a peek from just before the fight doesn't outlast it)
		debuffHeld = false
	end
	if ns.Flag(IsFalling()) then
		lastFallingAt = now
	end
	if resurrectRecovering and not IsPlayerRecovering() then
		resurrectRecovering = false
	end
	local portraitAllowed = ns.db.portraitWhenNotFull and (not ns.db.portraitAfterCombat
		or now - math.max(lastCombatAt, lastFallDamageAt) < ns.db.calmTime
		or (ns.db.portraitAfterResurrect and resurrectRecovering))
	if ns.IsChatActive() then
		ns.chatTypingUntil = now + ns.HoldTime("chatPeekTime")
	end
	local typing = ns.chatTypingUntil > now
	-- A whisper tab waiting to be read keeps the whole chat window up, tabs
	-- and all, so it can be clicked (Chat page).
	local whisperUnread = cinematic and ns.db.chatUntilWhisperRead and ns.HasUnreadWhisper()
	-- A docked chat window peeking brings its tabs up with it.
	local dockPeek = false
	for chatFrame, untilTime in pairs(ns.chatPeekUntil) do
		if untilTime > now and (chatFrame.isDocked or chatFrame == DEFAULT_CHAT_FRAME) then
			dockPeek = true
			break
		end
	end
	-- Chat stays put when it isn't faded at all, or in a place chosen under
	-- "Always show in" (Chat page).
	local place = ns.GetOptionPlace()
	local fadeChat = not (place and ns.db[ns.CHAT_IN[place]])
	local keepMinimapForTracking = ns.IsKeepingMinimapForTracking(now)
	local questTimerUp = ns.db.questTimerShow and HasQuestTimer()
	-- (Hide in camera modes: not while one is running, it goes with the rest.)
	local durabilityUp = ns.db.durabilityShow and not (ns.db.durabilityHideInCam and ns.activeCam)
		and ns.HasDurabilityAlert()
	local petUnhappyUp = ns.db.petUnhappyShow and not (ns.db.petUnhappyHideInCam and ns.activeCam)
		and ns.IsPetUnhappy()
	local questReveal = questRevealUntil > now
	local padReveal = padRevealUntil > now
	local pingReveal = pingRevealUntil > now
	local rosterReveal = rosterRevealUntil > now
	-- Tracking doesn't hold the minimap open in the places ticked under
	-- "Except in" (cities and the like).
	local trackingPaused = ns.IsTrackingOffHere()
	-- Mouseover groups: the rows the mouse is on (each held a while after it
	-- leaves), and the events going on now, bring up every row in their groups.
	local hoverGroups = ns.GetHoverGroups()
	local hovered, triggered, pinged = wipe(tickTables.hovered), wipe(tickTables.triggered), wipe(tickTables.pinged)
	if cinematic and ns.db.mouseover then
		local mouseRows = wipe(tickTables.mouseRows)
		for _, entry in ipairs(ns.managed) do
			entry.row = entry.row or ns.HoverRowFor(entry)
			if ns.IsEntryHovered(entry) then
				mouseRows[entry.row] = true
			end
		end
		-- Rows linger after the mouse leaves. The hold time counts the fade
		-- out, so a row is gone that long after the mouse leaves; a hold
		-- shorter than the fade just starts the fade straight away.
		local heldUntil = now + math.max(0, ns.HoldTime("mouseoverHold") - ns.FadeOutTime())
		-- (Under the mouse counts even with no hold: the camera modes' is 0.)
		for row in pairs(mouseRows) do
			hoverHeldUntil[row] = heldUntil
			hovered[row] = true
		end
		for row, untilTime in pairs(hoverHeldUntil) do
			if untilTime > now then
				hovered[row] = true
			end
		end
		-- (Only groups a hovered row is in directly: groups sharing a row don't chain.)
		local mouseGroups = wipe(tickTables.mouseGroups)
		for _, group in ipairs(hoverGroups) do
			for _, key in ipairs(group.members) do
				if hovered[key] then
					mouseGroups[#mouseGroups + 1] = group
					break
				end
			end
		end
		for _, group in ipairs(mouseGroups) do
			for _, member in ipairs(group.members) do
				hovered[member] = true
			end
		end
	end
	local events = tickTables.events
	events.chat, events.whisper, events.typing = dockPeek, whisperUnread, typing
	events.aura = cinematic and (buffPeekUntil > now or (debuffHeld and ns.db.debuffPeekUntilGone))
	events.ping = pingReveal
	events.tracking = ns.db.minimapForTracking and keepMinimapForTracking and not trackingPaused
	events.quest, events.gamepad, events.roster = questReveal, padReveal, rosterReveal
	events.cooldown = cinematic and ns.db.cooldownWhileRecharging
		and (not ns.db.cooldownAfterCombat or now - lastCombatAt < ns.db.calmTime)
		and AnyCooldownRecharging(now)
	for _, group in ipairs(hoverGroups) do
		for key, on in pairs(group.triggers or NO_DEFAULTS) do
			if on and events[key] then
				for _, member in ipairs(group.members) do
					triggered[member] = true
					if key == "ping" then pinged[member] = true end
				end
			end
		end
	end

	-- Dead, with the death camera watching: everything goes, quickly, whatever
	-- would normally keep it up (the release button is a popup: it stays).
	local deathFade = cinematic and ns.IsDeathCinematic and ns.IsDeathCinematic()

	-- Hide in camera modes (Minimap page): the camera running now fades the
	-- minimap, whatever would keep it up. Hovering still shows it.
	local camHidesMinimap = ns.activeCam and ns.db[ns.activeCam .. "HideMinimap"]
	-- Keep minimap open indoors (Minimap page): see RedrawMinimapWhenShown.
	local keepIndoors = ns.db.minimapIndoors and IsIndoors and ns.Flag(IsIndoors())

	for _, entry in ipairs(ns.managed) do
		if entry.ownAlpha then
			SyncOwnAlpha(entry)
		end
		local target = 1
		local chatShowing = (ns.chatPeekUntil[entry.frame] or 0) > now
			-- (Typing always shows chat, to see what you type; an unread whisper
			-- brings up the Mouseover groups with it ticked, chat by default.)
			or (typing and entry.group == "chat")
			or (dockPeek and entry.name == "GeneralDockManager")
		entry.row = entry.row or ns.HoverRowFor(entry)
		-- (Kept up by a setting, or brought up by an event ticked for one of its Mouseover groups.)
		local tracking = ((ns.db.alwaysShowMinimap or keepIndoors) and entry.group == "minimap")
			or (ns.db.alwaysShowWaypoint and entry.group == "waypoint")
			or (questTimerUp and entry.group == "questtimer")
			or (durabilityUp and entry.group == "misc")
			or (petUnhappyUp and entry.name == "PetFrame")
			or triggered[entry.row]
		local listShown = combatShown
			and (entry.name and combatShown[entry.name] or combatShown[GROUP_KEY[entry.group]])
		local fightingShown = listShown
		if not fightingShown and PORTRAIT_FRAMES[entry.name] and cinematic
			and portraitAllowed and IsPlayerRecovering() then
			fightingShown = true -- shown like a combat frame, at the normal fade speeds
		end
		if cinematic and not hovered[entry.row] and not chatShowing and not tracking
			and not fightingShown and (fadeChat or entry.group ~= "chat") then
			target = 0
		end
		if deathFade and not (typing and entry.group == "chat") then
			target = 0
		end
		-- (Swing timer page: in CineMode and out, hovering included.)
		if entry.group == "swing" and ns.IsSwingBarUnused(entry.name) then
			target = 0
		end
		local follows = followsRow[entry.frame]
		if follows and cinematic and not hovered[follows] and not triggered[follows]
			and not (combatShown and combatShown[GROUP_KEY[follows]]) then
			target = 0
		end
		-- (/cine debug pad: why the gamepad bars come up, as they start to.)
		if ns.padDebug and entry.group == "gamepadbars" then
			local up = target > 0 and cinematic
			if up and not entry.debugUp then
				ns.Print(("gamepad bars up: %s%s%s%s"):format(hovered[entry.row] and "hovered " or "",
					padReveal and "button press " or "", listShown and "fight/target column " or "",
					tracking and not padReveal and "kept up " or ""))
			end
			entry.debugUp = up
		end
		if camHidesMinimap and entry.group == "minimap" and not hovered[entry.row] and not pinged[entry.row] then
			target = 0
		end
		if entry.frame == Minimap then
			RedrawMinimapWhenShown()
		end
		if typing and entry.group == "chat" and entry.alpha < 1 then
			-- Pressing Enter shows the chat input (and its window) at once.
			ns.SetEntryAlpha(entry, 1)
		elseif target == 0 and entry.alpha == 0 and not entry.shrinkWhenFaded
			and not LOOSE_PART_GROUPS[entry.group] and entry.frame ~= artStandIn then
			-- Faded and staying so: put back only if something changed its alpha
			-- (frames setting their own were seen to above).
			if not entry.ownAlpha then
				ReapplyIfChanged(entry)
			end
		-- Keep re-applying 0 while hidden in case Blizzard code resets the alpha;
		-- once fully revealed, leave the frame alone.
		elseif entry.alpha ~= target or target == 0 or entry.shrunk then
			local duration
			if target > entry.alpha then
				duration = GroupFadeTime(entry.group, true)
			else
				duration = deathFade and DEATH_FADE_TIME or GroupFadeTime(entry.group, false)
			end
			ns.SetEntryAlpha(entry, ns.Approach(entry.alpha, target, elapsed, duration))
		end
		if entry.frame == personalStandIn then
			ns.SetPersonalPlateAlpha(entry.alpha)
		end
	end
end

-- Frames beyond the built-in list (and built-in ones kept up): added ones (including auto-matched) and
-- ones the player chose to stop fading (an added one stays in extraFrames
-- then too, so it fades again when let go). Sorted for stable display.
-- Lists saved names rather than managed frames, so frames that don't exist
-- yet (created later in the session) still show.
function ns.GetExtraFrames()
	local faded, ignored = {}, {}
	for name in pairs(ns.db.extraFrames) do
		if not ns.db.ignoredFrames[name] then
			faded[#faded + 1] = name
		end
	end
	for name in pairs(ns.db.ignoredFrames) do
		ignored[#ignored + 1] = name -- (built-in frames kept with /cine keep too)
	end
	table.sort(faded)
	table.sort(ignored)
	return faded, ignored
end

function ns.StopFading(name)
	ns.db.ignoredFrames[name] = true
	if _G[name] then RemoveFrame(_G[name]) end
end

-- Built-in, auto-matched and added frames come back on the next scan.
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
-- accept(frame): only frames it says yes to (add mode: ones not picked yet).
local function GetTopLevelFrameUnderCursor(accept)
	local best, bestArea
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if not IsForbidden(frame) and frame ~= ns.letterbox and frame:GetName()
			and ns.Flag(frame:IsVisible()) and ns.Flag(frame:IsMouseOver()) and (not accept or accept(frame)) then
			local width, height = frame:GetSize()
			local area = (width or 0) * (height or 0)
			if not (issecretvalue and issecretvalue(area)) and area > 0 and (not bestArea or area < bestArea) then
				best, bestArea = frame, area
			end
		end
	end
	return best
end

-- The top-level (direct child of UIParent) frame under the cursor, so adding
-- e.g. a damage meter's bar picks up the whole meter window. Also the
-- outermost named frame below it that accept(frame) takes (any named one
-- without accept): an addon's button on one of the game's frames, like a
-- copy button on the chat window.
local function GetTopLevelFrameUnderMouse(accept)
	local focus = MouseFocus()
	local inner
	while focus and focus ~= UIParent do
		local parent = focus:GetParent()
		if parent == UIParent or parent == nil then
			if focus:GetName() then
				return focus, inner
			end
			break
		end
		if focus:GetName() and (not accept or accept(focus)) then
			inner = focus
		end
		focus = parent
	end
	return GetTopLevelFrameUnderCursor(), inner
end

-- name: a frame's global name (/cine add <name>), for frames that are hard
-- to hover; nil to use the one under the mouse.
function ns.AddUnderMouse(name)
	local frame
	if name and name ~= "" then
		frame = _G[name]
		if not IsFrame(frame) then
			ns.Print(L["no frame called %s (frame names are case-sensitive; /fstack shows them)."]:format(name))
			return
		end
	else
		local inner
		frame, inner = GetTopLevelFrameUnderMouse(function(f) return not seen[f] end)
		-- On a frame faded already (the chat window), its own named part.
		if inner and frame and seen[frame] then
			frame = inner
		end
		name = frame and frame:GetName()
	end
	if not name then
		ns.Print(L["hover over a named UI element, then type /cine add and press Enter " ..
			"(or /cine add <FrameName>). Frames without a name can't be added: the 3rd Party Frames " ..
			"settings page lists the addons faded out of the box."])
		return
	end
	if IsWindow(frame, name) then
		ns.Print(L["%s is a window, so it isn't faded (it would stay there invisible). " ..
			"Move the mouse off it onto the frame you want, then try again."]:format(name))
		return
	end
	for _, entry in ipairs(ns.managed) do
		if entry.frame == frame and not entry.group:find("^extra:") then
			ns.Print(L["%s is already faded as part of the built-in \"%s\" group."]:format(name, entry.group))
			return
		end
	end
	ns.db.ignoredFrames[name] = nil
	ns.db.extraFrames[name] = true
	AddFrame(frame, "extra:" .. name)
	ns.Print(L["now fading %s"]:format(name))
end

function ns.RemoveUnderMouse()
	local frame = GetTopLevelFrameUnderMouse()
	local name = frame and frame:GetName()
	if not name then
		ns.Print(L["hover over a faded UI element, then type /cine keep and press Enter."])
		return
	end
	ns.StopFading(name)
	ns.Print(L["%s will always be shown (untick its CineMode box under Custom frames on the 3rd Party Frames " ..
		"options page to undo)."]:format(name))
end

-- Add mode (/cine add mode): hovering frames collects them, and the second
-- /cine add mode fades them all. Only frames /cine add would take and that
-- aren't faded yet: not the game's own, not this addon's, not windows.
-- (In a do block: the file is near Lua's 200 locals.)
do
	local ADD_MODE_CHECK = 0.1 -- seconds between looks under the cursor
	local addMode            -- the ticker while on
	local pending = {}       -- names picked, in order
	local overlays = {}      -- name: its gold box
	local skipped = {}       -- names not to pick again this time: dropped, or kept (and told so)

	-- Whether the game made the frame's global (an addon's CreateFrame taints
	-- it), and if not, the addon that did.
	local function GlobalSource(name)
		if type(issecurevariable) ~= "function" then
			return false
		end
		local ok, secure, source = pcall(issecurevariable, name)
		if not ok then
			return false
		end
		return secure == true, type(source) == "string" and source or nil
	end

	-- A gold box over a collected frame, so it's clear what was picked.
	-- Unnamed and not taking the mouse, so the cursor checks never find it.
	local function ShowOverlay(frame, name)
		local overlay = CreateFrame("Frame", nil, UIParent)
		overlay:SetFrameStrata("TOOLTIP")
		overlay:SetAllPoints(frame)
		local fill = overlay:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints()
		fill:SetColorTexture(1, 0.82, 0, 0.2)
		local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("TOPLEFT", 2, -2)
		label:SetText(name)
		overlays[name] = overlay
	end

	-- The 3rd Party Frames page's button and list (see Options.lua).
	local function AddModeChanged()
		if ns.OnAddModeChanged then
			ns.OnAddModeChanged()
		end
	end

	-- Whether add mode can pick the frame: not picked or faded already, not the
	-- game's own or this addon's, not a window.
	local function Pickable(frame)
		local name = frame:GetName()
		if not name or overlays[name] or skipped[name] or seen[frame] or ns.db.extraFrames[name]
			or leftAlone[name] then
			return false
		end
		local game, source = GlobalSource(name)
		return not (game or source == ADDON_NAME or IsWindow(frame, name))
	end

	local function CheckUnderMouse()
		local frame, inner = GetTopLevelFrameUnderMouse(Pickable)
		-- One already picked or faded can sit over one that isn't (an action bar
		-- addon's buttons over its art bar): the smallest one under the cursor
		-- that is, then. (Not under a window or the game's frames: what's behind
		-- the settings window isn't being pointed at.) On one of the game's
		-- frames, an addon's named frame on it (a copy button on the chat window).
		local name = frame and frame:GetName()
		if name and inner and GlobalSource(name) then
			frame = inner
		elseif name and (overlays[name] or seen[frame] or ns.db.extraFrames[name]) then
			frame = GetTopLevelFrameUnderCursor(Pickable)
		elseif not (frame and Pickable(frame)) then
			return
		end
		if not frame then
			return
		end
		name = frame:GetName()
		local _, source = GlobalSource(name)
		if ns.db.ignoredFrames[name] then
			skipped[name] = true
			ns.Print(L["%s skipped: you set it to always show (untick its CineMode box under Custom frames " ..
				"on the 3rd Party Frames page)."]:format(name))
			return
		end
		pending[#pending + 1] = name
		ShowOverlay(frame, name)
		ns.Print(L["found %s"]:format(name) .. (source and (" (" .. source .. ")") or ""))
		AddModeChanged()
	end

	-- The frames picked so far, in the order found.
	function ns.GetPickedFrames()
		return pending
	end

	-- Takes a picked frame back out (the list's Drop), and doesn't pick it again.
	function ns.DropPickedFrame(name)
		for i, picked in ipairs(pending) do
			if picked == name then
				table.remove(pending, i)
				break
			end
		end
		if overlays[name] then
			overlays[name]:Hide()
			overlays[name] = nil
		end
		skipped[name] = true
		AddModeChanged()
	end

	local function EndAddMode()
		addMode:Cancel()
		addMode = nil
		for _, overlay in pairs(overlays) do
			overlay:Hide()
		end
		local names = pending
		pending, overlays, skipped = {}, {}, {}
		return names
	end

	function ns.IsAddModeOn()
		return addMode ~= nil
	end

	function ns.ToggleAddMode()
		if not addMode then
			addMode = C_Timer.NewTicker(ADD_MODE_CHECK, CheckUnderMouse)
			ns.Print(L["add mode: hover over the frames to fade. Type /cine add mode again to fade them " ..
				"(or /cine add cancel to drop them). The game's own frames and ones already faded are left out."])
			AddModeChanged()
			return
		end
		local added = 0
		for _, name in ipairs(EndAddMode()) do
			local frame = _G[name]
			if IsFrame(frame) then
				ns.db.ignoredFrames[name] = nil
				ns.db.extraFrames[name] = true
				AddFrame(frame, "extra:" .. name)
				added = added + 1
			end
		end
		ns.Print(added == 0 and L["add mode off: nothing found to add."]
			or (added == 1 and L["add mode off: now fading %d frame."] or L["add mode off: now fading %d frames."])
				:format(added))
		AddModeChanged()
	end

	function ns.CancelAddMode()
		if not addMode then
			ns.Print(L["add mode isn't on (/cine add mode starts it)."])
			return
		end
		local count = #EndAddMode()
		ns.Print((count == 1 and L["add mode cancelled: %d frame left as it was."]
			or L["add mode cancelled: %d frames left as they were."]):format(count))
		AddModeChanged()
	end
end

function ns.ListExtras()
	local faded, ignored = ns.GetExtraFrames()
	for _, name in ipairs(faded) do ns.Print(L["fading %s"]:format(name)) end
	for _, name in ipairs(ignored) do ns.Print(L["ignoring %s"]:format(name)) end
	if #faded + #ignored == 0 then
		ns.Print(L["no extra frames."])
	end
end

-- For supported addons' setups (Support/), which run only once their addon
-- has loaded. A frame already faded is let go, to be picked up again by the
-- next scan the new way.
local function LetGo(name)
	local frame = _G[name]
	if frame and seen[frame] then
		RemoveFrame(frame)
	end
end

-- Its frames that stand in for the game's: they fade in that group and follow
-- the Standard Frames page's row (by key, see COMBAT_SHOW). own: they set
-- their own alpha; hook: follow it at once (the addon's own frames only).
function ns.FadeWithRow(rowKey, group, names, own, hook)
	local row
	for _, item in ipairs(ns.COMBAT_SHOW) do
		if item.key == rowKey then
			row = item
		end
	end
	for _, name in ipairs(names) do
		AddName(FRAME_GROUPS[group], name)
		if row and row.frames then
			AddName(row.frames, name)
		end
		ownAlphaNames[name] = own or nil
		hookedNames[name] = hook or nil
		LetGo(name)
	end
end

-- Game frames whose alpha the addon sets: followed (checked, never hooked).
function ns.FollowOwnAlpha(names)
	for _, name in ipairs(names) do
		ownAlphaNames[name] = true
		LetGo(name)
	end
end

-- Game frames the addon hides for good: never faded.
-- An addon took the bar over (and may keep it at alpha 0): its art goes back
-- to following the bar.
local function ReleaseBarArt(barName)
	for i = #barArt, 1, -1 do
		local art = barArt[i]
		if art.bar == barName then
			if art.region.SetIgnoreParentAlpha then
				art.region:SetIgnoreParentAlpha(false)
			end
			art.region:SetAlpha(1)
			table.remove(barArt, i)
		end
	end
end

function ns.LeaveAlone(names)
	for _, name in ipairs(names) do
		leftAlone[name] = true
		ReleaseBarArt(name)
		LetGo(name)
	end
end

-- A frame its own search found (see ns.AddScanner), unnamed ones too. own and
-- hook as for ns.FadeWithRow.
function ns.AddFoundFrame(frame, group, own, hook)
	ownAlphaFrames[frame] = own or nil
	hookedFrames[frame] = hook or nil
	return AddFrame(frame, group)
end

function ns.IsFaded(frame)
	return seen[frame] or false
end

-- fn runs with each scan for the frames to fade.
function ns.AddScanner(fn)
	table.insert(scanners, fn)
end

-- fn runs each time the minimap gets its size back after being faded.
function ns.OnMinimapRestored(fn)
	table.insert(restoredHandlers, fn)
end

-- Its player frame, shown like the game's while health or power recovers.
function ns.AddPortraitFrame(name)
	PORTRAIT_FRAMES[name] = true
end

-- The raid frames (and raid-style party frames): each member's frame, or
-- each group's when groups are kept together, in raidplayers; pets in
-- raidpets; and their parts (PART_GROUPS) in theirs. The game makes and
-- reuses them as the group changes (one can go from a player to a pet), so
-- they're sorted afresh at each scan, and soon after the group changes.
do
	local function SortRaidPart(part, group)
		if not part or IsForbidden(part) then
			return
		end
		if seen[part] then
			for _, entry in ipairs(ns.managed) do
				if entry.frame == part then
					if entry.group == group then
						return
					end
					RemoveFrame(part) -- (sorted again below)
					break
				end
			end
		end
		AddFrame(part, group)
	end

	local function GroupTitle(group)
		local name = group:GetName()
		return group.title or (name and _G[name .. "Title"])
	end

	-- A member's or pet's frame (inGroup: inside a group's frame, which fades
	-- for it), and its parts.
	local function SortUnitFrame(frame, inGroup)
		local unit = frame.unit or frame.displayedUnit
		if Secret(unit) or type(unit) ~= "string" then
			return
		end
		local isPet = unit:find("pet") ~= nil
		if not inGroup then
			SortRaidPart(frame, isPet and "raidpets" or "raidplayers")
		end
		SortRaidPart(frame.roleIcon, "raidroles")
		-- (The game only shows and hides it, never sets its alpha.)
		SortRaidPart(frame.aggroHighlight, "raidthreat")
		SortRaidPart(frame.name, isPet and "raidpetnames" or "raidnames")
		for _, aura in ipairs(frame.buffFrames or {}) do
			SortRaidPart(aura, "raidbuffs")
		end
		for _, list in ipairs({ frame.debuffFrames or {}, frame.dispelDebuffFrames or {} }) do
			for _, aura in ipairs(list) do
				SortRaidPart(aura, "raiddebuffs")
			end
		end
	end

	local function ScanRaidFrames()
		for _, holderName in ipairs({ "CompactRaidFrameContainer", "CompactPartyFrame" }) do
			local holder = _G[holderName]
			if holder and not IsForbidden(holder) then
				if holderName == "CompactPartyFrame" then
					local title = GroupTitle(holder) -- ("Party")
					SortRaidPart(title, "raidtitles")
					if title then
						followsRow[title] = "raidplayers"
					end
				end
				for _, child in ipairs({ holder:GetChildren() }) do
					if not IsForbidden(child) then
						local name = child:GetName()
						if name and name:find("^CompactRaidGroup%d+$") then
							SortRaidPart(child, "raidplayers")
							SortRaidPart(GroupTitle(child), "raidtitles") -- ("Group 1")
							for _, member in ipairs({ child:GetChildren() }) do
								if not IsForbidden(member) then
									SortUnitFrame(member, true)
								end
							end
						else
							SortUnitFrame(child, false)
						end
					end
				end
			end
		end
	end
	ns.AddScanner(ScanRaidFrames)

	-- A party member's frame, with its role icon and name (retail's are
	-- parent keys, Classic's named after the frame).
	-- The party frames dim members out of range (and light them back up) with
	-- their own SetAlpha, so while faded one flashed up until the next tick
	-- put ours back. Their own scripts are followed by ours straight away
	-- instead, as for the cast bars. Script hooks, not method hooks (see
	-- AddFrame); one for a frame no longer faded does nothing.
	local partyEntries = {} -- frame -> its entry (entry.removed once let go)
	local onPartyScript = ns.Profiled("Party frame alpha hook", function(frame)
		local entry = partyEntries[frame]
		if entry and not entry.removed and entry.alpha < 1 then
			ReapplyIfChanged(entry)
		end
	end)
	local function HookPartyScripts(frame)
		if partyEntries[frame] == nil and frame.HookScript then
			frame:HookScript("OnEvent", onPartyScript)
			frame:HookScript("OnShow", onPartyScript)
			frame:HookScript("OnUpdate", onPartyScript)
		end
		partyEntries[frame] = ns.managed[#ns.managed]
	end

	local function SortPartyFrame(frame)
		if not frame or IsForbidden(frame) then
			return
		end
		if AddFrame(frame, "party") then
			HookPartyScripts(frame)
		end
		local name = frame:GetName()
		local overlay = frame.PartyMemberOverlay
		SortRaidPart((overlay and overlay.RoleIcon) or frame.RoleIcon or (name and _G[name .. "RoleIcon"]),
			"partyroles")
		SortRaidPart(frame.Name or (name and _G[name .. "Name"]), "partynames")
		-- The icon for a member phased or elsewhere ignores its frame's alpha
		-- (it stays bright as the frame dims), so it fades on its own.
		SortRaidPart(frame.NotPresentIcon or (name and _G[name .. "NotPresentIcon"]), "party")
	end

	-- Retail's party frames (unnamed, from a pool) are in PartyFrame, and so
	-- are the raid-style ones (CompactPartyFrame): fading the holder would
	-- fade those too, so its members fade instead.
	local function ScanPartyFrames()
		for i = 1, 4 do
			SortPartyFrame(_G["PartyMemberFrame" .. i])
		end
		local holder = _G.PartyFrame
		if not holder or IsForbidden(holder) then
			return
		end
		for _, child in ipairs({ holder:GetChildren() }) do
			if child ~= _G.CompactPartyFrame then
				SortPartyFrame(child)
			end
		end
	end
	ns.AddScanner(ScanPartyFrames)

	local rosterWatcher = CreateFrame("Frame")
	rosterWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	rosterWatcher:SetScript("OnEvent", function()
		-- (After the game has set its frames up for the new group.)
		C_Timer.After(0.5, function()
			if ns.db then
				ScanRaidFrames()
				RecomputeNesting()
			end
		end)
	end)
end
