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
local curves = {}   -- kind (TANKS...) -> { below, floor, [step] = its curve (false: none on this client) }
local hovered = false
local reveal, revealStep = 0, 0 -- the mouse's fade: how far in (0-1), and as a step
local sinceScan, sinceUpdate = RESCAN_EVERY, 0

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

local function Forbidden(frame)
	return frame.IsForbidden and frame:IsForbidden()
end

-- Each kind of member's health and opacity settings (Vision section).
-- (Damage, and anyone without a role: the group titles go by their opacity too.)
local TANKS = { below = "healVisionTankBelow", alpha = "healVisionTankAlpha" }
local HEALERS = { below = "healVisionHealerBelow", alpha = "healVisionHealerAlpha" }
local OTHERS = { below = "healVisionShowBelow", alpha = "healVisionMinAlpha" }
local PETS = { below = "healVisionPetBelow", alpha = "healVisionPetAlpha" }
local DEAD = { alpha = "healVisionDeadAlpha" } -- (no health setting for these two)
local OFFLINE = { alpha = "healVisionOfflineAlpha" }
local FAR = { alpha = "healVisionFarAlpha" } -- (100%: off)

-- The alpha a hidden member of this kind has at this step of the mouse's
-- fade: its opacity setting at 0, full at STEPS.
local function Shown(step, kind)
	local floor = ns.db and tonumber(ns.db[kind.alpha]) or 0
	floor = math.max(0, math.min(floor, 1))
	return floor + (1 - floor) * step / STEPS
end

-- Health percent to alpha: 1 below the kind's health setting; at or above
-- it, Shown(step). 100% there means any damage (full is 1), 0% never.
local function Curve(step, kind)
	local floor = ns.db and ns.db[kind.alpha]
	local below = ns.db and ns.db[kind.below]
	local made = curves[kind]
	if not made or made.floor ~= floor or made.below ~= below then
		made = { floor = floor, below = below }
		curves[kind] = made
	end
	if made[step] ~= nil then return made[step] end
	made[step] = false
	if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum.LuaCurveType and UnitHealthPercent) then
		return false
	end
	local ok, curve = pcall(C_CurveUtil.CreateCurve)
	if ok and curve then
		curve:SetType(Enum.LuaCurveType.Step)
		below = math.min(tonumber(below) or 0.95, 0.9995)
		if below > 0 then
			curve:AddPoint(0, 1)
			curve:AddPoint(below, Shown(step, kind))
		else
			curve:AddPoint(0, Shown(step, kind)) -- (0%: never by health)
		end
		made[step] = curve
	end
	return made[step]
end

local function Plain(value)
	if Secret(value) then return nil end
	return value
end

-- The group's tanks (by role, or main tank in a raid): their own health setting.
local function Tank(unit)
	if Plain(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) == "TANK" then return true end
	return IsInRaid() and GetPartyAssignment and Plain(GetPartyAssignment("MAINTANK", unit)) == true
end

-- The settings a member goes by: pets', tanks', healers' or everyone else's.
local function KindOf(unit)
	if unit:find("pet") then return PETS end
	if Tank(unit) then return TANKS end
	if Plain(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) == "HEALER" then return HEALERS end
	return OTHERS
end

-- A debuff on them that the game's filters find: ones you can dispel
-- (newer filter first, the older one if this client doesn't know it), or any.
-- Long ones (over LONG_DEBUFF, or for good: seasonal and other hour-long
-- ones) don't count, nothing on the frame needs a heal or a dispel. A secret
-- answer is yes: only a debuff comes back secret (nothing is nil). No answer,
-- or an error (WoW Forever won't let addons see members' auras while they're
-- secret: in fights, battlegrounds): no, they go by their health.
local LONG_DEBUFF = 120 -- seconds
local DISPEL_FILTERS = { "HARMFUL|RAID_PLAYER_DISPELLABLE", "HARMFUL|RAID" }
local ANY_FILTERS = { "HARMFUL" }
local function Counts(duration)
	if Secret(duration) then return true end
	return type(duration) == "number" and duration > 0 and duration <= LONG_DEBUFF
end
local function Debuffed(unit, filters, oldFilter)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for _, filter in ipairs(filters) do
			local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, filter)
			if ok then
				for i = 1, 40 do
					if i > 1 then
						ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
						if not ok then return false end
					end
					if Secret(data) then return true end
					if type(data) ~= "table" then return false end
					local okDuration, duration = pcall(function() return data.duration end)
					if okDuration and Counts(duration) then return true end
				end
				return false
			end
		end
		return false
	end
	if UnitDebuff then
		for i = 1, 40 do
			local ok, name, _, _, _, duration = pcall(UnitDebuff, unit, i, oldFilter)
			if not ok then return false end
			if Secret(name) then return true end
			if type(name) ~= "string" then return false end
			if Counts(duration) then return true end
		end
	end
	return false
end

-- What the debuff options would make of a member (for /cine debug auras),
-- on WoW Forever too, where they're hidden for now.
function ns.HealVisionDebuffs(unit)
	return ("dispellable %s, any %s"):format(tostring(Debuffed(unit, DISPEL_FILTERS, "RAID")),
		tostring(Debuffed(unit, ANY_FILTERS, nil)))
end

-- Shown whatever their health, as the Vision page's options say: tanks at
-- 100%, and those with a debuff. (Your target goes before everything, in Rule.)
-- The debuff ones are off for now, their options hidden (the choices kept):
-- neither client lets addons see members' auras in fights in instances or
-- battlegrounds (C_Secrets.ShouldAurasBeSecret says so then, see /cine debug
-- auras), only out of combat.
ns.HEAL_VISION_DEBUFFS = false
local function ShownAnyway(unit)
	local db = ns.db
	local debuffs = ns.HEAL_VISION_DEBUFFS
	return ((tonumber(db.healVisionTankBelow) or 1) >= 1 and Tank(unit)) -- (100%: always)
		or (debuffs and db.healVisionAnyDebuff and Debuffed(unit, ANY_FILTERS, nil))
		or (debuffs and db.healVisionDispel and Debuffed(unit, DISPEL_FILTERS, "RAID"))
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

-- How far a member is from you in yards (math.huge: another instance), or
-- nil when the game won't say (secret, or hidden in dungeons and raids).
function ns.HealVisionDistance(unit)
	if UnitDistanceSquared then
		local ok, squared, checked = pcall(UnitDistanceSquared, unit)
		if ok and Plain(checked) == true and type(Plain(squared)) == "number" then
			return math.sqrt(squared)
		end
	end
	local okYou, y, x, _, instance = pcall(UnitPosition, "player")
	local okThem, theirY, theirX, _, theirInstance = pcall(UnitPosition, unit)
	if not (okYou and okThem) then return nil end
	y, x, theirY, theirX = Plain(y), Plain(x), Plain(theirY), Plain(theirX)
	instance, theirInstance = Plain(instance), Plain(theirInstance)
	if type(instance) == "number" and type(theirInstance) == "number" and instance ~= theirInstance then
		return math.huge
	end
	if type(y) ~= "number" or type(x) ~= "number" or type(theirY) ~= "number" or type(theirX) ~= "number" then
		return nil
	end
	return math.sqrt((y - theirY) ^ 2 + (x - theirX) ^ 2)
end

-- Where you are: "pvp" and "arena" (battlegrounds), "party", "raid" and
-- "scenario" (instances), or "none" (the open world).
local function PlaceType()
	local ok, inside, kind = pcall(IsInInstance)
	if not ok or Plain(inside) ~= true then return "none" end
	return Plain(kind) or "none"
end

-- A map as a zone: up through the small maps inside it (caves, city
-- districts) to the zone or dungeon map they're in.
local function ZoneMap(map)
	for _ = 1, 5 do
		local ok, info = pcall(C_Map.GetMapInfo, map)
		if not ok or type(Plain(info)) ~= "table" then return map end
		local mapType, parent = Plain(info.mapType), Plain(info.parentMapID)
		if type(mapType) ~= "number" or mapType <= Enum.UIMapType.Dungeon
			or type(parent) ~= "number" or parent == 0 then
			return map
		end
		map = parent
	end
	return map
end

local function UnitMap(unit)
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo and Enum and Enum.UIMapType) then return nil end
	local ok, map = pcall(C_Map.GetBestMapForUnit, unit)
	map = ok and Plain(map)
	if type(map) ~= "number" then return nil end
	return ZoneMap(map)
end

-- A raid member's zone by the raid list (pets: their owner's), or nil.
local function RosterZone(unit)
	local index = unit:match("^raid(%d+)$") or unit:match("^raidpet(%d+)$")
	if not index or not GetRaidRosterInfo then return nil end
	local ok, _, _, _, _, _, _, zone = pcall(GetRaidRosterInfo, tonumber(index))
	zone = ok and Plain(zone)
	if type(zone) ~= "string" or zone == "" then return nil end
	return zone
end

-- Whether a member's in another zone than you: true, false, or nil (the game
-- won't say). The raid list's zone names first, then the maps (the floors
-- of one dungeon are one zone: the same map group).
function ns.HealVisionOtherZone(unit)
	local theirs = RosterZone(unit)
	local ok, yours = pcall(GetRealZoneText)
	yours = ok and Plain(yours)
	if theirs and type(yours) == "string" and yours ~= "" then return theirs ~= yours end
	local myMap, theirMap = UnitMap("player"), UnitMap(unit)
	if not (myMap and theirMap) then return nil end
	if myMap == theirMap then return false end
	if C_Map.GetMapGroupID then
		local okMine, myGroup = pcall(C_Map.GetMapGroupID, myMap)
		local okTheirs, theirGroup = pcall(C_Map.GetMapGroupID, theirMap)
		myGroup, theirGroup = okMine and Plain(myGroup), okTheirs and Plain(theirGroup)
		if type(myGroup) == "number" and myGroup ~= 0 and myGroup == theirGroup then return false end
	end
	return true
end

-- Far away: in battlegrounds by distance only (more than 100 yards); in
-- dungeons and raids, out of your zone (the instance), else by distance; in
-- the open world by distance, else by zone. Unknown: not far.
local FAR_YARDS = 100
local function Far(unit)
	local place = PlaceType()
	if place == "pvp" or place == "arena" then
		local yards = ns.HealVisionDistance(unit)
		return yards ~= nil and yards > FAR_YARDS
	end
	if place ~= "none" and ns.HealVisionOtherZone(unit) == true then return true end
	local yards = ns.HealVisionDistance(unit)
	if yards ~= nil then return yards > FAR_YARDS end
	return place == "none" and ns.HealVisionOtherZone(unit) == true
end

-- Which rule a member goes by, first that fits (unknown, secret: it doesn't):
-- your target (shown), offline, dead (or a ghost), far away (its slider below
-- 100%), shown anyway (tanks at 100%, debuffs), else their health. The second
-- value: the opacity setting the hidden ones go by (DEAD...).
local function Rule(unit)
	local db = ns.db
	if db.healVisionTarget and Plain(UnitIsUnit(unit, "target")) == true then return "target" end
	if UnitIsConnected and Plain(UnitIsConnected(unit)) == false then return "offline", OFFLINE end
	if UnitIsDeadOrGhost and Plain(UnitIsDeadOrGhost(unit)) == true then return "dead", DEAD end
	if (tonumber(db.healVisionFarAlpha) or 1) < 1 and Far(unit) then return "far", FAR end
	if ShownAnyway(unit) then return "shown" end
	return "health"
end

-- In battlegrounds where the game won't say how far anyone is (WoW Forever),
-- out of range of your heals stands in for far away: the game's own range
-- dimming goes to the Far away opacity instead (raid-style frames). The
-- addon never knows who's out of range (secret), so it's on top of the
-- rules that show members (health, tanks, debuffs), not one of them.
local function RangeFar(unit, rule)
	if rule ~= "health" and rule ~= "shown" then return false end
	if (tonumber(ns.db.healVisionFarAlpha) or 1) >= 1 then return false end
	local place = PlaceType()
	return (place == "pvp" or place == "arena") and ns.HealVisionDistance(unit) == nil
end

-- What Heal Vision makes of a member, for /cine debug health.
function ns.HealVisionDebug(unit)
	local db = ns.db
	if not db then return "no settings" end
	local frames = byUnit[unit] or {}
	local alpha = frames[1] and members[frames[1]] and members[frames[1]].alpha
	local otherZone = ns.HealVisionOtherZone(unit)
	-- (Off: why, as ns.HealVisionHere goes.)
	local on = Wanted("healVision") and "true"
	if not on then
		local role = ns.PlayerRole()
		local list = role == "TANK" and "tankHide" or role == "HEALER" and "healerHide"
			or role == "DAMAGER" and "damageHide"
		on = ns.IsSuspended() and "false (stopped for this session)"
			or (list and ns.RoleHidden(db, list, "healVision") and ("false (role button: off as " .. role .. ")"))
			or (db.handleVision == false and "false (Vision page switched off)")
			or "false (Show in grid: not ticked here)"
	end
	local rule = Rule(unit)
	if RangeFar(unit, rule) then rule = rule .. " (out of range: far away opacity)" end
	-- Each frame: its name, shown or not, faded whole (raid-style) or by
	-- parts, held by CineMode (not free), and the opacity it really has.
	local function Show(value)
		if Secret(value) then return "secret" end
		if type(value) == "number" then return ("%.2f"):format(value) end
		return tostring(value)
	end
	local list = {}
	for _, frame in ipairs(frames) do
		local okShown, shown = pcall(frame.IsShown, frame)
		local okAlpha, frameAlpha = pcall(frame.GetAlpha, frame)
		local okEffective, effective = pcall(frame.GetEffectiveAlpha, frame)
		list[#list + 1] = ("%s shown %s %s free %s alpha %s effective %s"):format(
			tostring(frame:GetName()), okShown and Show(shown) or "?", members[frame].whole and "whole" or "parts",
			tostring(Free(frame)), okAlpha and Show(frameAlpha) or "?", okEffective and Show(effective) or "?")
	end
	return ("on %s, %d frame(s), rule %s, place %s, other zone %s, far slider %s, hover step %d/%d, alpha %s [%s]"):format(
		on, #frames, rule, PlaceType(),
		tostring(otherZone), tostring(db.healVisionFarAlpha), revealStep, STEPS,
		Secret(alpha) and "secret" or tostring(alpha), table.concat(list, "; "))
end

local function Update(frame)
	local member = members[frame]
	if not member then return end
	local unit = member.unit
	local kind = KindOf(unit)
	local fade = Curve(revealStep, kind)
	if not fade then return end
	local alpha, gone, rule = 1, nil, nil
	if revealStep < STEPS and UnitExists(unit) then
		rule, gone = Rule(unit)
		if gone then
			alpha = Shown(revealStep, gone)
		elseif rule == "health" then
			-- (Health as it is, not with heals being cast. Secret: straight to the game.)
			local ok, value = pcall(UnitHealthPercent, unit, false, fade)
			if ok and type(value) ~= "nil" then alpha = value end
		end
	end
	member.alpha = alpha
	if member.whole then
		if Free(frame) then
			if not pcall(frame.SetAlpha, frame, alpha) then frame:SetAlpha(1) end
			touched[frame] = true
		end
		-- (The dead, offline and far count as out of range: no dimming on top
		-- of their slider's opacity, it's theirs as set.)
		-- (Battlegrounds: out of range dims to Far away, see RangeFar.)
		local inRange = nil
		if not gone then inRange = InRange(unit) end
		local dim = RangeFar(unit, rule) and Shown(revealStep, FAR) or RANGE_DIM
		for _, part in ipairs(member.parts) do
			if Free(part) then
				if type(inRange) == "nil" or not part.SetAlphaFromBoolean
					or not pcall(part.SetAlphaFromBoolean, part, inRange, 1, dim) then
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
			title:SetAlpha(Shown(revealStep, OTHERS))
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
	"UNIT_AURA", "PLAYER_SPECIALIZATION_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
	"PLAYER_TARGET_CHANGED" }) do
	pcall(watcher.RegisterEvent, watcher, event) -- (not every client has every event)
end
watcher:SetScript("OnEvent", function(_, event, unit)
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_CONNECTION"
		or event == "UNIT_IN_RANGE_UPDATE" or event == "UNIT_AURA" then
		if Secret(unit) or not byUnit[unit] then return end
		for _, frame in ipairs(byUnit[unit]) do Update(frame) end
	elseif event == "PLAYER_TARGET_CHANGED" then
		UpdateAll()
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
