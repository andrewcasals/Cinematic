-- Cinematic: Heal Vision on the game's own party and raid frames (the
-- Vision page). Members (pets too) show only while below full health, or as
-- the page's options say tanks and those with a debuff (you can dispel, or
-- any), and the group titles ("Group 1", "Party") hide. The mouse over the
-- frames fades everyone back in while it's there, out of combat.
--
-- As in HealerFrame.lua, the addon never knows anyone's health: their health
-- percent goes through a curve (1 below full, 0 at full) straight into
-- SetAlpha. (The mouse fading them in: a curve whose value at full health
-- goes up in steps, as the fade goes.) The game's frames can't be moved by addons in a fight, so a
-- hidden member leaves a gap rather than the others closing up.
--
-- Raid-style frames (raid, and raid-style party): the fade goes on the member
-- frame itself, so the aura icons inside it go too (on WoW Forever they're
-- forbidden frames, out of reach on their own). The game dims members out of
-- range with that same alpha, so the dimming moves to its parts instead, and
-- the game's own setting is followed straight away by ours (script hooks, as
-- Frames.lua does for the party frames). The plain party frames keep their
-- own alpha: the fade goes on their parts. Either way, parts that ignore the
-- frame's alpha (your target's outline) are skipped, and so is anything
-- CineMode is fading right now (a row unticked), so nothing fights.
local _, ns = ...

local RESCAN_EVERY = 5   -- seconds between finding each member's parts again
local UPDATE_EVERY = 0.5 -- and between going over every member (health changes come by event)
local RANGE_DIM = 0.55   -- the game's own for members out of range
local STEPS = 20         -- the mouse's fade, in this many steps

local members = {}  -- member frame -> { unit, parts, whole, alpha }, the ones faded now
local byUnit = {}   -- unit -> { member frames showing it }
local managed = {}  -- frame -> its CineMode entry (Frames.lua's ns.managed)
local titles = {}   -- group titles hidden now
local touched = {}  -- frame or part -> true: its alpha was set here (put back to 1 once let go)
local hooked = {}   -- member frames whose scripts are followed
local curves = {}   -- step -> the curve for it (false: none on this client)
local curvesFloor   -- the opacity setting those curves were made for
local hovered = false
local reveal, revealStep = 0, 0 -- the mouse's fade: how far in (0-1), and as a step
local sinceScan, sinceUpdate = RESCAN_EVERY, 0

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

local function Forbidden(frame)
	return frame.IsForbidden and frame:IsForbidden()
end

-- The alpha a hidden member has at this step of the mouse's fade: the
-- opacity setting (Vision section) at 0, full at STEPS.
local function Shown(step)
	local floor = ns.db and tonumber(ns.db.healVisionMinAlpha) or 0
	floor = math.max(0, math.min(floor, 1))
	return floor + (1 - floor) * step / STEPS
end

-- Health percent to alpha: 1 when hurt; at full, Shown(step).
local function Curve(step)
	local floor = ns.db and ns.db.healVisionMinAlpha
	if floor ~= curvesFloor then
		wipe(curves)
		curvesFloor = floor
	end
	if curves[step] ~= nil then return curves[step] end
	curves[step] = false
	if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum.LuaCurveType and UnitHealthPercent) then
		return false
	end
	local ok, made = pcall(C_CurveUtil.CreateCurve)
	if ok and made then
		made:SetType(Enum.LuaCurveType.Step)
		made:AddPoint(0, 1)
		made:AddPoint(0.9995, Shown(step))
		curves[step] = made
	end
	return curves[step]
end

local function Plain(value)
	if Secret(value) then return nil end
	return value
end

-- The group's tanks (by role, or main tank in a raid): always shown.
local function Tank(unit)
	if Plain(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) == "TANK" then return true end
	return IsInRaid() and GetPartyAssignment and Plain(GetPartyAssignment("MAINTANK", unit)) == true
end

-- A debuff on them that the game's filters find: ones you can dispel
-- (newer filter first), or any. Unsure (secret, or no such filter here): no,
-- so they go by their health.
local DISPEL_FILTERS = { "HARMFUL|RAID_PLAYER_DISPELLABLE", "HARMFUL|RAID" }
local ANY_FILTERS = { "HARMFUL" }
local function Debuffed(unit, filters, oldFilter)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for _, filter in ipairs(filters) do
			local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, filter)
			if ok and not Secret(data) and type(data) == "table" then
				return true
			end
		end
		return false
	end
	if UnitDebuff then
		local ok, name = pcall(UnitDebuff, unit, 1, oldFilter)
		return ok and not Secret(name) and type(name) == "string"
	end
	return false
end

-- Shown whatever their health, as the Vision page's options say.
local function AlwaysShown(unit)
	local db = ns.db
	return (db.healVisionTanks and Tank(unit))
		or (db.healVisionAnyDebuff and Debuffed(unit, ANY_FILTERS, nil))
		or (db.healVisionDispel and Debuffed(unit, DISPEL_FILTERS, "RAID"))
end

-- (kind: its setting, as the Vision grid's row has it: on here, see ns.HealVisionHere.)
local function Wanted(kind)
	local db = ns.db
	return db and kind == "healVision" and ns.HealVisionHere(db) and not ns.IsSuspended()
end

-- Not while CineMode is fading it (it fades it its own way, back to full once shown).
local function Free(frame)
	local entry = managed[frame]
	return not (entry and entry.alpha < 1)
end

-- The game set a raid-style member's alpha (out of range dimming): ours back.
local function Reassert(frame)
	local member = members[frame]
	if member and member.whole and type(member.alpha) ~= "nil" and Free(frame) then
		pcall(frame.SetAlpha, frame, member.alpha)
	end
end
if ns.Profiled then Reassert = ns.Profiled("Heal Vision frame alpha hook", Reassert) end

local function Hook(frame)
	if hooked[frame] or not frame.HookScript then return end
	hooked[frame] = true
	frame:HookScript("OnEvent", Reassert)
	frame:HookScript("OnShow", Reassert)
	frame:HookScript("OnUpdate", Reassert)
end

-- A member's parts: its regions and child frames, less the ones that ignore its alpha.
local function Parts(frame)
	local parts = {}
	local function Add(part)
		if Forbidden(part) or not part.SetAlpha then return end
		local ignoring = part.IsIgnoringParentAlpha and part:IsIgnoringParentAlpha()
		if not Secret(ignoring) and ignoring then return end
		parts[#parts + 1] = part
	end
	for _, region in ipairs({ frame:GetRegions() }) do Add(region) end
	for _, child in ipairs({ frame:GetChildren() }) do Add(child) end
	return parts
end

local function Unit(frame)
	local unit = frame.displayedUnit or frame.unit
	if Secret(unit) or type(unit) ~= "string" then return nil end
	return unit
end

-- (whole: a raid-style frame, faded itself.)
local function AddMember(frame, kind, found, whole)
	if not frame or Forbidden(frame) or not Wanted(kind) then return end
	local unit = Unit(frame)
	if not unit then return end
	-- (Found afresh each time: the game adds parts as it needs them.)
	found[frame] = { unit = unit, parts = Parts(frame), whole = whole }
	if whole then Hook(frame) end
end

-- A group's title ("Group 1", "Party"): hidden while its kind is on, as the
-- members under it come and go.
local function GroupTitle(group)
	local name = group:GetName()
	return group.title or (name and _G[name .. "Title"])
end

local function AddTitle(group, kind, list)
	if not Wanted(kind) then return end
	local title = GroupTitle(group)
	if title and not Forbidden(title) and title.SetAlpha then list[#list + 1] = title end
end

-- The frames the members are in: the mouse over any brings everyone back,
-- out of combat only (in a fight, the hurt stay the only ones shown).
local HOLDERS = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer",
	"PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }

local function Hovered()
	if InCombatLockdown() then return false end
	for _, name in ipairs(HOLDERS) do
		local holder = _G[name]
		if holder and not Forbidden(holder) then
			local okVisible, visible = pcall(holder.IsVisible, holder)
			local okOver, over = pcall(holder.IsMouseOver, holder)
			if okVisible and okOver and not Secret(visible) and not Secret(over) and visible and over then
				return true
			end
		end
	end
	return false
end

-- Every party and raid member's frame now up (pets too), with its parts.
local function Scan()
	local found, foundTitles = {}, {}
	-- Party frames: Classic's, retail's (in PartyFrame) and the raid-style ones.
	for i = 1, 4 do AddMember(_G["PartyMemberFrame" .. i], "healVision", found) end
	local holder = _G.PartyFrame
	if holder and not Forbidden(holder) then
		for _, child in ipairs({ holder:GetChildren() }) do
			if child ~= _G.CompactPartyFrame then AddMember(child, "healVision", found) end
		end
	end
	holder = _G.CompactPartyFrame
	if holder and not Forbidden(holder) then
		AddTitle(holder, "healVision", foundTitles)
		for _, child in ipairs({ holder:GetChildren() }) do
			if child ~= GroupTitle(holder) then AddMember(child, "healVision", found, true) end
		end
	end
	-- Raid frames: members on their own, or in their groups' frames.
	holder = _G.CompactRaidFrameContainer
	if holder and not Forbidden(holder) then
		for _, child in ipairs({ holder:GetChildren() }) do
			local name = not Forbidden(child) and child:GetName()
			if name and name:find("^CompactRaidGroup%d+$") then
				AddTitle(child, "healVision", foundTitles)
				for _, member in ipairs({ child:GetChildren() }) do
					if member ~= GroupTitle(child) then AddMember(member, "healVision", found, true) end
				end
			else
				AddMember(child, "healVision", found, true)
			end
		end
	end
	wipe(managed)
	for _, entry in ipairs(ns.managed or {}) do
		if not entry.removed then managed[entry.frame] = entry end
	end
	-- What's no longer faded here: back to full.
	local still = {}
	for frame, member in pairs(found) do
		if member.whole then still[frame] = true end
		for _, part in ipairs(member.parts) do still[part] = true end
	end
	for _, title in ipairs(foundTitles) do still[title] = true end
	for frame in pairs(touched) do
		if not still[frame] then
			if Free(frame) then frame:SetAlpha(1) end
			touched[frame] = nil
		end
	end
	members, titles = found, foundTitles
	wipe(byUnit)
	for frame, member in pairs(members) do
		byUnit[member.unit] = byUnit[member.unit] or {}
		table.insert(byUnit[member.unit], frame)
	end
end

-- Whether a member is in range, for the parts' dimming: a boolean (maybe
-- secret, straight to the game), or nil when there's nothing to dim.
local function InRange(unit)
	if not UnitInRange or unit == "player" then return nil end
	local isYou = UnitIsUnit(unit, "player")
	if not Secret(isYou) and isYou then return nil end
	local inRange, checked = UnitInRange(unit)
	if not Secret(checked) and not checked then return nil end
	return inRange
end

local function Update(frame)
	local member = members[frame]
	local fade = Curve(revealStep)
	if not member or not fade then return end
	local unit = member.unit
	local alpha = 1
	if revealStep < STEPS and UnitExists(unit) and not AlwaysShown(unit) then
		-- (Health as it is, not with heals being cast. Secret: straight to the game.)
		local ok, value = pcall(UnitHealthPercent, unit, false, fade)
		if ok and type(value) ~= "nil" then alpha = value end
	end
	member.alpha = alpha
	if member.whole then
		if Free(frame) then
			if not pcall(frame.SetAlpha, frame, alpha) then frame:SetAlpha(1) end
			touched[frame] = true
		end
		local inRange = InRange(unit)
		for _, part in ipairs(member.parts) do
			if Free(part) then
				if type(inRange) == "nil" or not part.SetAlphaFromBoolean
					or not pcall(part.SetAlphaFromBoolean, part, inRange, 1, RANGE_DIM) then
					part:SetAlpha(1)
				end
				touched[part] = true
			end
		end
	else
		for _, part in ipairs(member.parts) do
			if Free(part) then
				if not pcall(part.SetAlpha, part, alpha) then part:SetAlpha(1) end
				touched[part] = true
			end
		end
	end
end

local function UpdateAll()
	for frame in pairs(members) do Update(frame) end
	for _, title in ipairs(titles) do
		if Free(title) then
			title:SetAlpha(Shown(revealStep))
			touched[title] = true
		end
	end
end

-- After a setting changes (Options.lua's Heal Vision page).
function ns.ApplyHealVisionFrames()
	sinceScan = RESCAN_EVERY
	Scan()
	UpdateAll()
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_IN_RANGE_UPDATE",
	"UNIT_AURA", "PLAYER_SPECIALIZATION_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
	pcall(watcher.RegisterEvent, watcher, event) -- (not every client has every event)
end
watcher:SetScript("OnEvent", function(_, event, unit)
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_CONNECTION"
		or event == "UNIT_IN_RANGE_UPDATE" or event == "UNIT_AURA" then
		if Secret(unit) or not byUnit[unit] then return end
		for _, frame in ipairs(byUnit[unit]) do Update(frame) end
	else
		-- (After the game has set its frames up for the new group, or place:
		-- the Vision grid may say otherwise there.)
		C_Timer.After(0.5, ns.ApplyHealVisionFrames)
	end
end)
watcher:SetScript("OnUpdate", function(_, elapsed)
	if not next(members) and not next(touched) and not ns.HealVisionAny() then
		return
	end
	-- The mouse over the frames: everyone fades in (as fast as CineMode's
	-- frames), and out again once it's gone.
	if next(members) then
		hovered = Hovered()
		local target = hovered and 1 or 0
		if reveal ~= target then
			reveal = ns.Approach(reveal, target, elapsed, hovered and ns.FadeInTime() or ns.FadeOutTime())
			local step = math.floor(reveal * STEPS + 0.5)
			if step ~= revealStep then
				revealStep = step
				UpdateAll()
			end
		end
	end
	sinceScan, sinceUpdate = sinceScan + elapsed, sinceUpdate + elapsed
	if sinceUpdate < UPDATE_EVERY then return end
	sinceUpdate = 0
	if sinceScan >= RESCAN_EVERY then
		sinceScan = 0
		Scan()
	end
	UpdateAll()
end)
