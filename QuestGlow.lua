-- Cinematic: Quest Vision's glow on quest objects (questObjectGlow, Vision
-- page): the thing on the ground you pick up or use for a quest objective
-- glows gold, with the quest mark over it. The game's soft targeting picks
-- one object to interact with at a time (the "softinteract" unit, the
-- nearest in front of you) and, with the settings below, gives it a
-- nameplate: the glow goes on that plate. So it's one object at a time, the
-- one your interact key would use.
-- A quest object: the game shows its quest cursor over it, or says it's
-- related to a quest you're on, or its name is in an objective you haven't
-- finished. Unreadable (secret) counts as no.
local _, ns = ...

local SOFT = "softinteract"
local CHECK_EVERY = 0.15

-- The game settings held while it's on (the player's own come back after):
-- soft targeting of things to interact with, keyboard and mouse too, out to
-- 20 yards in front of you (out of reach too), with a plate and icon for
-- objects (the game gives objects no plate without their icon). The icons
-- it brings are hidden bar the ones you'd see anyway (see UpdateIcon).
-- (Secure: nameplate settings wait for the end of a fight.) Not playerWins:
-- the game changes some of these itself (the object icon as you log in,
-- soft targeting with gamepad mode), which would have let go of them and
-- lost your own values. Held instead: written again (KeepHeld) and put back
-- as they were when you untick it.
local CVARS = { secure = true, values = {
	SoftTargetInteract = "3", SoftTargetInteractRange = "20", SoftTargetInteractArc = "1",
	SoftTargetInteractOnlyInRange = "0", SoftTargetNameplateInteract = "1",
	SoftTargetIconGameObject = "1", nameplateGameObjectMaxDistance = "60",
} }

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function Ask(fn, ...)
	if not fn then
		return false
	end
	local ok, value = pcall(fn, ...)
	return ok and Known(value) and value and true or false
end

-- The game's quest cursors (Interface\Cursor), by file number as a texture
-- reads them back: made once, from their names.
local QUEST_CURSORS = { "Quest", "QuestRepeatable", "QuestTurnIn", "QuestInteract", "CampaignQuest",
	"CampaignQuestTurnIn", "LegendaryQuest", "LegendaryQuestTurnIn", "Important", "ImportantTurnIn", "Recurring",
	"RecurringTurnIn", "Wrapper", "WrapperTurnIn" }
local probe = CreateFrame("Frame"):CreateTexture()
local questCursorFiles

local function QuestCursorFiles()
	if not questCursorFiles then
		questCursorFiles = {}
		for _, name in ipairs(QUEST_CURSORS) do
			probe:SetTexture(nil)
			pcall(probe.SetTexture, probe, "Interface\\Cursor\\" .. name)
			local file = probe:GetTexture()
			if type(file) == "number" and Known(file) then
				questCursorFiles[file] = true
			end
		end
	end
	return questCursorFiles
end

-- The cursor the game would show over the unit: its file (number or path)
-- or atlas, or nil.
local function CursorOf(unit)
	if not SetUnitCursorTexture then
		return nil
	end
	probe:SetTexture(nil)
	if not pcall(SetUnitCursorTexture, probe, unit, nil, true) then
		return nil
	end
	local file = probe:GetTexture()
	local atlas = probe.GetAtlas and probe:GetAtlas()
	if file ~= nil and Known(file) then
		return file
	end
	if atlas ~= nil and Known(atlas) then
		return atlas
	end
	return nil
end

local function QuestCursor(cursor)
	if type(cursor) == "number" then
		return QuestCursorFiles()[cursor] or false
	end
	if type(cursor) == "string" then
		local name = cursor:lower()
		return (name:find("quest", 1, true) or name:find("important", 1, true) or name:find("recurring", 1, true)
			or name:find("wrapper", 1, true)) and not name:find("unable", 1, true) and true or false
	end
	return false
end

-- The objectives you haven't finished, in lower case (made as needed, again
-- when the quest log changes).
local objectives

local function Objectives()
	if objectives then
		return objectives
	end
	objectives = {}
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetQuestIDForLogIndex and log.GetQuestObjectives) then
		return objectives
	end
	pcall(function()
		for index = 1, log.GetNumQuestLogEntries() or 0 do
			local questID = log.GetQuestIDForLogIndex(index)
			for _, objective in ipairs(type(questID) == "number" and log.GetQuestObjectives(questID) or {}) do
				local text = objective.text
				if not objective.finished and type(text) == "string" and Known(text) then
					objectives[#objectives + 1] = text:lower()
				end
			end
		end
	end)
	return objectives
end

local function NamedInObjective(unit)
	local ok, name = pcall(UnitName, unit)
	if not (ok and type(name) == "string" and Known(name) and #name > 2) then
		return false
	end
	name = name:lower()
	for _, text in ipairs(Objectives()) do
		if text:find(name, 1, true) then
			return true
		end
	end
	return false
end

-- Why an object counts (for the debug line), or nil.
local function QuestReason(unit)
	local cursor = CursorOf(unit)
	if QuestCursor(cursor) then
		return "cursor"
	end
	local log = C_QuestLog
	if Ask(log and log.UnitIsRelatedToActiveQuest, unit) then
		return "related"
	end
	if NamedInObjective(unit) then
		return "objective"
	end
	return nil
end

-- Answers by GUID until the quest log changes.
local answers = {}

local function IsQuestObject(unit)
	local ok, guid = pcall(UnitGUID, unit)
	if not (ok and type(guid) == "string" and Known(guid)) then
		return QuestReason(unit) ~= nil
	end
	if answers[guid] == nil then
		answers[guid] = QuestReason(unit) ~= nil
	end
	return answers[guid]
end

-- An object, not a creature: the game says so, or (older clients) it doesn't
-- "exist" as a unit.
local function IsObject(unit)
	if UnitIsGameObject then
		return Ask(UnitIsGameObject, unit)
	end
	return not Ask(UnitExists, unit)
end

-- The glow: a soft gold light round the object (below its plate) and the
-- quest mark over it, drawn whatever the plate's own fade (CineMode fades it).
-- The light only for LIGHT_TIME seconds per object, then it fades out over
-- LIGHT_FADE (it hides a small object), the mark staying.
local LIGHT_TIME, LIGHT_FADE = 2.5, 1
local glow = CreateFrame("Frame")
glow:Hide()
glow:SetSize(110, 110)
glow:SetIgnoreParentAlpha(true)
do
	local lightFrame = CreateFrame("Frame", nil, glow)
	lightFrame:SetAllPoints()
	glow.light = lightFrame
	local light = lightFrame:CreateTexture(nil, "BACKGROUND")
	light:SetAllPoints()
	light:SetTexture("Interface\\Cooldown\\star4")
	light:SetBlendMode("ADD")
	light:SetVertexColor(1, 0.82, 0.2)
	local mark = glow:CreateTexture(nil, "OVERLAY")
	mark:SetSize(24, 24)
	mark:SetPoint("BOTTOM", glow, "TOP", 0, -30)
	mark:SetTexture(ns.QUEST_MOB_TEXTURE)
	local pulse = light:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.45)
	fade:SetDuration(0.9)
	fade:SetSmoothing("IN_OUT")
	glow.pulse = pulse
end
glow:SetScript("OnUpdate", function(self)
	local left = LIGHT_TIME + LIGHT_FADE - (GetTime() - (self.litAt or 0))
	local alpha = math.max(0, math.min(1, left / LIGHT_FADE))
	if self.light:GetAlpha() ~= alpha then
		self.light:SetAlpha(alpha)
	end
end)

-- guid: the object's, so the light comes back only for another one (kept
-- after the glow goes: back on the same object, no light again).
local function GlowOn(plate, guid)
	if glow.guid ~= guid or (not guid and glow.plate ~= plate) then
		glow.guid = guid
		glow.litAt = GetTime()
	end
	if glow.plate ~= plate then
		glow.plate = plate
		glow:SetParent(plate)
		glow:SetIgnoreParentAlpha(true)
		glow:SetFrameLevel((plate.GetFrameLevel and plate:GetFrameLevel() or 0) + 10)
		glow:ClearAllPoints()
		glow:SetPoint("CENTER", plate, "CENTER", 0, -40)
	end
	if not glow:IsShown() then
		glow:Show()
		glow.pulse:Play()
	end
end

local function GlowOff()
	if glow:IsShown() then
		glow.pulse:Stop()
		glow:Hide()
	end
	glow.plate = nil
	glow:SetParent(nil)
end

local function Wanted()
	return ns.db and ns.QuestVisionSetting("questObjectGlow") and true or false
end

-- The object soft targeting picked and its plate, if it has one: plate, or nil.
local function SoftPlate()
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return nil
	end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, SOFT)
	return ok and plate or nil
end

-- Soft targeting switches between objects as you walk and turn, so the glow
-- stays on the object it lit up (lock) for at least LOCK_TIME seconds, and
-- after that until you've moved LOCK_YARDS from where it lit up (by time
-- alone where the game won't say where you are). It lets go sooner when that
-- object loses its plate (looted, out of range) or stops counting for a quest.
local LOCK_TIME, LOCK_YARDS = 2, 5
local lock -- { guid, at, x, y }

local function Position()
	if not UnitPosition then
		return nil
	end
	local ok, y, x = pcall(UnitPosition, "player")
	if ok and type(x) == "number" and type(y) == "number" and Known(x) and Known(y) then
		return x, y
	end
	return nil
end

local function GUIDOf(unit)
	local ok, guid = pcall(UnitGUID, unit)
	return ok and type(guid) == "string" and Known(guid) and guid or nil
end

-- The plate the locked object has now, and its unit, if any.
local function LockedPlate()
	local guid = lock.guid
	if GUIDOf(SOFT) == guid then
		return SoftPlate(), SOFT
	end
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken
		if unit and GUIDOf(unit) == guid then
			return plate, unit
		end
	end
	return nil
end

local function LockReleased()
	if GetTime() - lock.at < LOCK_TIME then
		return false
	end
	local x, y = Position()
	if not (x and lock.x) then
		return true
	end
	local dx, dy = x - lock.x, y - lock.y
	return dx * dx + dy * dy >= LOCK_YARDS * LOCK_YARDS
end

local function Usable(plate)
	return plate and not (plate.IsForbidden and plate:IsForbidden())
end

-- Your own value for a game setting (put back once the glow lets go).
local function Own(cvar)
	local saved = ns.db.savedCVars[cvar]
	if saved ~= nil then
		return saved
	end
	return GetCVar(cvar)
end

-- The soft targeting held above gives a plate to whatever it picks, a dead
-- mob you can loot included: that plate stays up until you loot it. While
-- the settings are ours, a dead unit's plate is hidden (Effects asks here),
-- and so is a living one's that only got its plate from us (an NPC you face,
-- with your own plates for its kind off): the glow only needs objects'.
function ns.SoftPlateHidden(unit)
	if not (CVARS.active and unit and Ask(UnitIsUnit, unit, SOFT)) then
		return false
	end
	if Ask(UnitIsDead, unit) then
		return true
	end
	return Own("SoftTargetNameplateInteract") ~= "1" and not IsObject(unit)
		and not (ns.PlateShownAnyway and ns.PlateShownAnyway(unit))
end

-- The soft plate hidden last tick: refreshed as one turns up or goes, so
-- Effects hides it (or gives it back) at once.
local hiddenSoftPlate

local function UpdateHiddenSoftPlate()
	local plate = SoftPlate()
	local unit = plate and plate.namePlateUnitToken
	if not (unit and ns.SoftPlateHidden(unit)) then
		plate = nil
	end
	if plate == hiddenSoftPlate then
		return
	end
	local old = hiddenSoftPlate
	hiddenSoftPlate = plate
	for _, changed in ipairs({ old or false, plate or false }) do
		if changed and ns.RefreshPlate and not (changed.IsForbidden and changed:IsForbidden()) then
			ns.RefreshPlate(changed, changed.namePlateUnitToken)
		end
	end
end

-- The game's icon over what soft targeting picked, or your target when it's
-- something to interact with (the plate's SoftTargetFrame: a gear, a herb, a
-- hearthstone, a gamepad button...), on any plate.
-- While the settings are ours it shows only where your own settings would
-- have shown it: soft targeting on for the way you're playing (keyboard and
-- mouse, or gamepad) and the icon on for that kind of thing. Elsewhere it's
-- hidden (quest objects have our mark). [icon frame] = true while hidden by us.
local hiddenIcons = {}

local function OwnIconShows(object)
	local mode = tonumber(Own("SoftTargetInteract")) or 0
	local pad = ns.IsGamePadOn and ns.IsGamePadOn() or false
	local covered = mode == 3 or (mode == 1 and pad) or (mode == 2 and not pad)
	return covered and Own(object and "SoftTargetIconGameObject" or "SoftTargetIconInteract") == "1"
end

local function IconOf(plate)
	local frame = plate and plate.UnitFrame and plate.UnitFrame.SoftTargetFrame
	if type(frame) == "table" and frame.SetAlpha and not (frame.IsForbidden and frame:IsForbidden()) then
		return frame
	end
	return nil
end

-- A plate's unit (some clients only give it on the unit frame).
local function UnitOf(plate)
	return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

local hideNow = {}
local function UpdateIcon()
	wipe(hideNow)
	if CVARS.active then
		-- (Your own settings decide objects and creatures apart: each asked once.)
		local shows = {}
		for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
			local frame = IconOf(plate)
			local unit = UnitOf(plate)
			if frame and unit then
				local object = IsObject(unit)
				if shows[object] == nil then
					shows[object] = OwnIconShows(object)
				end
				if not shows[object] then
					hideNow[frame] = true
				end
			end
		end
	end
	for frame in pairs(hiddenIcons) do
		if not hideNow[frame] then
			hiddenIcons[frame] = nil
			frame:SetAlpha(1)
		end
	end
	for frame in pairs(hideNow) do
		hiddenIcons[frame] = true
		frame:SetAlpha(0) -- (again each time: the game may set it back)
	end
end

-- The held settings written again where the game changed them (once a
-- second; nameplate ones out of fights).
local KEEP_EVERY = 1
local keepAt = 0
local function KeepHeld()
	local now = GetTime()
	if not CVARS.active or now < keepAt then
		return
	end
	keepAt = now + KEEP_EVERY
	for cvar, value in pairs(CVARS.values) do
		local current = GetCVar(cvar)
		if current ~= nil and current ~= value and tonumber(current) ~= tonumber(value)
			and not (cvar:find("^nameplate") and InCombatLockdown()) then
			SetCVar(cvar, value)
		end
	end
end

-- "Your own" interact settings saved as exactly ours (lost to an earlier
-- build, or saved again after one): the game's defaults go back instead, or
-- unticking would leave soft targeting and its icons on.
local HEAL = { "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetInteractArc",
	"SoftTargetNameplateInteract", "SoftTargetIconGameObject" }
local healed = false

local function HealSaved()
	if healed or not CVARS.active then
		return
	end
	healed = true
	local saved = ns.db.savedCVars
	local Default = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
	if not Default then
		return
	end
	for _, cvar in ipairs(HEAL) do
		if saved[cvar] == nil or tonumber(saved[cvar]) ~= tonumber(CVARS.values[cvar]) then
			return
		end
	end
	for _, cvar in ipairs(HEAL) do
		local ok, value = pcall(Default, cvar)
		if ok and value ~= nil then
			ns.Log("cvar", ("%s: saved value was the glow's, the game's default (%s) goes back"):format(cvar,
				tostring(value)))
			saved[cvar] = value
		end
	end
end

local function Update()
	local on = Wanted()
	ns.ApplyCVarSet(CVARS, on)
	HealSaved()
	KeepHeld()
	UpdateHiddenSoftPlate()
	UpdateIcon()
	if not on then
		lock = nil
		GlowOff()
		return
	end
	if lock then
		local plate, unit = LockedPlate()
		if Usable(plate) and IsQuestObject(unit) and not LockReleased() then
			GlowOn(plate, lock.guid)
			return
		end
		lock = nil
	end
	local plate = SoftPlate()
	if Usable(plate) and IsObject(SOFT) and IsQuestObject(SOFT) then
		local guid = GUIDOf(SOFT)
		GlowOn(plate, guid)
		if guid then
			local x, y = Position()
			lock = { guid = guid, at = GetTime(), x = x, y = y }
		end
	else
		GlowOff()
	end
end
ns.UpdateQuestGlow = Update

local ticker = CreateFrame("Frame")
ticker.at = 0
ticker:SetScript("OnUpdate", function(self)
	local now = GetTime()
	if now < self.at then
		return
	end
	self.at = now + CHECK_EVERY
	if Wanted() or CVARS.active or glow:IsShown() or next(hiddenIcons) then
		Update()
	end
end)

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
	"QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD", "PLAYER_SOFT_INTERACT_CHANGED" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_SOFT_INTERACT_CHANGED" then
		ticker.at = 0 -- (looked at on the next frame)
		return
	end
	wipe(answers)
	objectives = nil
end)

-- /cine debug questglow: what soft targeting has picked and why it glows or not.
function ns.PrintQuestGlowDebug()
	local cvars = {}
	for _, name in ipairs({ "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetNameplateInteract",
		"SoftTargetIconGameObject" }) do
		cvars[#cvars + 1] = name .. "=" .. tostring(GetCVar(name))
	end
	ns.Print(("quest object glow: %s, settings held: %s (%s)"):format(Wanted() and "on" or "off",
		tostring(CVARS.active or false), table.concat(cvars, ", ")))
	local x = Position()
	ns.Print(lock and ("locked for %.1fs (your position %s)"):format(GetTime() - lock.at,
		x and (lock.x and "known" or "unknown at lock") or "unknown: by time alone") or "not locked")
	local okTarget, targetPlate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	local targetIcon = okTarget and IconOf(targetPlate)
	ns.Print(("your target's plate: %s (unit %s), its icon: %s"):format(okTarget and targetPlate and "yes" or "no",
		tostring(targetPlate and UnitOf(targetPlate)),
		not targetIcon and "none" or hiddenIcons[targetIcon] and "hidden by us" or "left alone"))
	ns.Print(("your own: SoftTargetInteract=%s, SoftTargetIconInteract=%s, SoftTargetIconGameObject=%s, " ..
		"gamepad mode=%s: creature icons %s, object icons %s"):format(tostring(Own("SoftTargetInteract")),
		tostring(Own("SoftTargetIconInteract")), tostring(Own("SoftTargetIconGameObject")),
		tostring(ns.IsGamePadOn and ns.IsGamePadOn() or false), OwnIconShows(false) and "shown" or "hidden",
		OwnIconShows(true) and "shown" or "hidden"))
	local okName, name = pcall(UnitName, SOFT)
	if not (okName and name ~= nil) then
		ns.Print("nothing soft targeted")
		return
	end
	local cursor = CursorOf(SOFT)
	local plate = SoftPlate()
	local okAlpha, alpha = pcall(function() return ("%.2f"):format(plate.UnitFrame:GetAlpha()) end)
	local icon = plate and plate.UnitFrame and plate.UnitFrame.SoftTargetFrame
	ns.Print(("soft target: %s, object=%s, plate=%s, cursor=%s, reason=%s, glowing=%s"):format(
		Known(name) and tostring(name) or "(secret)", tostring(IsObject(SOFT)),
		plate and ("yes, alpha " .. (okAlpha and alpha or "?")) or "no",
		tostring(cursor), tostring(QuestReason(SOFT)), tostring(glow:IsShown())))
	ns.Print(("game's icon: %s, your own settings would show it: %s"):format(
		type(icon) ~= "table" and "none" or hiddenIcons[icon] and "hidden by us" or "left alone",
		tostring(OwnIconShows(IsObject(SOFT)))))
end
