-- Cinematic: the Nameplates page's Plate Parts grid. In CineMode each part of
-- the game's nameplates (health bar, name, cast bar, auras...) shows as its
-- row says, fading like the plates themselves. Outside CineMode, or with the
-- page's master switch off, the parts are left to the game.
local _, ns = ...

-- Each part's frame on a plate's unit frame: the first of these it has, or
-- (all) every one of them, for parts drawn by several textures. The
-- containers (health and cast bars with their borders) go first. WoW
-- Forever's level is the PlayerLevelDiffFrame box (its LevelFrame stays hidden).
-- A dotted field is one on a frame on the unit frame.
local PART_FRAMES = {
	Health = { "HealthBarsContainer", "healthBar" },
	Name = { "name" },
	CastBar = { "CastBarsContainer", "castBar", "CastBar" },
	-- (Clients whose plates keep buffs and debuffs in one frame, BuffFrame,
	-- mostly show your debuffs there: it goes with Debuffs.)
	Buffs = { "AurasFrame.BuffListFrame" },
	Debuffs = { "AurasFrame.DebuffListFrame", "AurasFrame.CrowdControlListFrame", all = true,
		fallback = { "BuffFrame" } },
	-- (On the plates that are up. Over the rest, the Names grid's Raid Marker
	-- row keeps one of Effects' own.)
	RaidMarker = { "RaidTargetFrame" },
	Classification = { "ClassificationFrame", "classificationIndicator", all = true },
	Level = { "PlayerLevelDiffFrame", "LevelFrame", "levelText" },
	Threat = { "aggroHighlight", "aggroHighlightBase", "aggroHighlightAdditive", "aggroFlash", all = true },
	-- (Forever's is the health bar's gold border, on your target.)
	Highlight = { "selectionHighlight", "healthBar.selectedBorder", all = true },
	Widgets = { "WidgetContainer" },
}

-- How far each part shows, 0 to 1, faded at the UI's fade speeds.
local levels = {}

-- A plate held up only for its name (see ns.SetPlateBody): how much of its
-- alpha the rest of it gets ([plate] = 0 to 1, nil for all of it), and the
-- name ([plate] = 0 to 1, nil for none of its own).
local bodyShare, nameShare = {}, {}

local function Usable(frame)
	return type(frame) == "table" and frame.SetAlpha and not (frame.IsForbidden and frame:IsForbidden())
end

local function Field(unitFrame, field)
	local value = unitFrame
	for name in field:gmatch("[^.]+") do
		if type(value) ~= "table" then
			return nil
		end
		value = value[name]
	end
	return value
end

-- Calls fn(frame, ...) for each of a part's frames on a unit frame (or its
-- fallback's, when it has none of them).
local function EachPartFrame(unitFrame, part, fn, ...)
	local fields = PART_FRAMES[part]
	local found = false
	for _, field in ipairs(fields) do
		local frame = Field(unitFrame, field)
		if Usable(frame) then
			found = true
			fn(frame, ...)
			if not fields.all then
				return
			end
		end
	end
	if not found and fields.fallback then
		for _, field in ipairs(fields.fallback) do
			local frame = Field(unitFrame, field)
			if Usable(frame) then
				fn(frame, ...)
				return
			end
		end
	end
end

-- The game sets some of these parts' alpha itself (the cast bar fades out
-- after a cast), so while a part is faded its alpha is put back to ours every
-- frame, as with the plates. [part frame] = alpha.
local held = {}
local keeper = CreateFrame("Frame")
keeper:Hide()
keeper:SetScript("OnUpdate", ns.Profiled("Plate parts keeper", function(self)
	for frame, wanted in pairs(held) do
		-- (A secret alpha can't be compared: set ours again.)
		local alpha = frame:GetAlpha()
		if (issecretvalue and issecretvalue(alpha)) or alpha ~= wanted then
			frame:SetAlpha(wanted)
		end
	end
	if not next(held) then
		self:Hide()
	end
end))

-- WoW Forever's personal resource bars are a plate too: theirs are left alone.
local function PersonalPlate()
	return C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("player")
end

local function Fade(frame, alpha)
	if alpha < 1 then
		held[frame] = alpha
		frame:SetAlpha(alpha)
	elseif held[frame] then
		held[frame] = nil -- (let go: back to full, then the game's again)
		frame:SetAlpha(1)
	end
end

-- A plate showing its name alone has it centred over where the health bar
-- was (retail's sits at the bar's left end): its own justification is put
-- back once the rest of the plate shows. [name text] = the game's justification.
local centred = {}

local function CentreName(unitFrame, on)
	local name = unitFrame.name
	if not (Usable(name) and name.SetJustifyH and name.GetJustifyH) then
		return
	end
	if on then
		if not centred[name] then
			centred[name] = name:GetJustifyH() or "LEFT"
		end
		if name:GetJustifyH() ~= "CENTER" then
			name:SetJustifyH("CENTER")
		end
	elseif centred[name] then
		name:SetJustifyH(centred[name])
		centred[name] = nil
	end
end

-- And coloured as the game colours names over heads (red hostile, yellow
-- neutral, green friendly): the plate's own name is white or grey, the
-- health bar giving its colour. Friendly players too (blue), unless the
-- style keeps the game's class colours on them. The game sets the name's colour again on its own updates, so ours
-- is put back every frame; WoW Forever's colours can be secret, so they go
-- straight from the game to the text. Its text and vertex colours both get
-- it (on WoW Forever they're one: the game sets both), their alpha left as
-- it is for the fades. [name text] = { unit, the game's text colour, its
-- vertex colour }.
local tinted = {}

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function Ask(fn, ...)
	local ok, value = pcall(fn, ...)
	return ok and Known(value) and value and true or false
end

local Style -- (below, with the rest of the name style)

local function TintUnit(unit)
	local okGuid, guid = pcall(UnitGUID, unit)
	if okGuid and Known(guid) and type(guid) == "string" and guid:find("^Player%-") then
		return not Style("classColours") or Ask(UnitCanAttack, "player", unit)
	end
	return true
end

-- Sets a name's colour, keeping its alpha.
local painting -- (so our own setting doesn't paint it again)
local function SetNameColor(name, r, g, b)
	painting = true
	pcall(name.SetTextColor, name, r, g, b, select(4, name:GetTextColor()))
	if name.SetVertexColor and name.GetVertexColor then
		pcall(name.SetVertexColor, name, r, g, b, select(4, name:GetVertexColor()))
	end
	painting = nil
end

local function PaintName(name, unit)
	if UnitSelectionColor then
		SetNameColor(name, UnitSelectionColor(unit))
	else
		local reaction = Ask(UnitReaction, unit, "player") and UnitReaction(unit, "player")
		local color = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
		if color then
			SetNameColor(name, color.r, color.g, color.b)
		end
	end
end

-- Drawn like those names too: the nameplate font's outline taken off, a
-- drop shadow in its place. The game's font comes back with the rest of the
-- plate (by its font object where it has one: the object may hold other
-- alphabets than its file). [name text] = { font object, file, size, flags,
-- shadow colour, shadow offset; base, baseFlags: the game's size and flags
-- ours start from; oursSize, oursFlags: what ours came out as }.
local styled = {}

-- How names on name-only plates look. The dev build's Name Style page
-- (NameStyleDev.lua) tries others in ns.db.devNameStyle; everyone else gets these.
-- outline: 0 none, 1 thin, 2 thick. size: times the game's. classColours:
-- friendly players' names left in the class colours the game gives them.
local NAME_STYLE = { colour = true, classColours = false, outline = 0, size = 1, shadow = true,
	shadowX = 1, shadowY = -1, shadowAlpha = 1 }
ns.NAME_STYLE_DEFAULTS = NAME_STYLE

function Style(key)
	local own = ns.db and ns.db.devNameStyle
	local value = own and own[key]
	if value == nil then
		return NAME_STYLE[key]
	end
	return value
end

local OUTLINES = { [0] = "", "OUTLINE", "THICKOUTLINE" }

local function Outlined(flags, outline)
	flags = (flags or ""):gsub("THICKOUTLINE", ""):gsub("OUTLINE", "")
	if OUTLINES[outline] ~= "" then
		flags = flags .. "," .. OUTLINES[outline]
	end
	return (flags:gsub("^,+", ""):gsub(",+$", ""):gsub(",,+", ","))
end

local function KeepStyle(name, saved)
	local file, size, flags = name:GetFont()
	if file and (saved.dirty or flags ~= saved.oursFlags or size ~= saved.oursSize) then
		if not saved.dirty or not saved.base then
			saved.base, saved.baseFlags = size, flags -- (the game's own, set again)
		end
		saved.dirty = nil
		pcall(name.SetFont, name, file, saved.base * Style("size"), Outlined(saved.baseFlags, Style("outline")))
		local _
		_, saved.oursSize, saved.oursFlags = name:GetFont()
	end
	local x, y, alpha = 0, 0, 0
	if Style("shadow") then
		x, y, alpha = Style("shadowX"), Style("shadowY"), Style("shadowAlpha")
	end
	local nowX, nowY = name:GetShadowOffset()
	local nowAlpha = select(4, name:GetShadowColor())
	if nowX ~= x or nowY ~= y or nowAlpha ~= alpha then
		name:SetShadowOffset(x, y)
		name:SetShadowColor(0, 0, 0, alpha)
	end
end

local painter = CreateFrame("Frame")
painter:Hide()
painter:SetScript("OnUpdate", ns.Profiled("Plate name colours", function(self)
	for name, saved in pairs(tinted) do
		PaintName(name, saved.unit)
	end
	for name, saved in pairs(styled) do
		KeepStyle(name, saved)
	end
	if not (next(tinted) or next(styled)) then
		self:Hide()
	end
end))

-- The game sets the name's colour again as the mouse goes over a unit or the
-- target changes, after this frame's OnUpdate: shown white for a frame
-- before the painter caught it. Painted again on those events too.
local repainter = CreateFrame("Frame")
for _, event in ipairs({ "UPDATE_MOUSEOVER_UNIT", "CURSOR_CHANGED", "PLAYER_TARGET_CHANGED",
	"PLAYER_FOCUS_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED",
	"PLAYER_SOFT_INTERACT_CHANGED", "UNIT_NAME_UPDATE" }) do
	pcall(repainter.RegisterEvent, repainter, event) -- (not every client has them all)
end
repainter:SetScript("OnEvent", function()
	for name, saved in pairs(tinted) do
		PaintName(name, saved.unit)
	end
end)

-- It also sets it again on its own while units move, at any time in the
-- frame: shown white for a frame, again and again (a flicker). So ours goes
-- back on the moment the game sets its colour. [name text] = true once hooked.
local hookedNames = {}

local function Repaint(name)
	local saved = tinted[name]
	if saved and not painting then
		pcall(PaintName, name, saved.unit)
	end
end

local function HookName(name)
	if hookedNames[name] then
		return
	end
	hookedNames[name] = true
	for _, method in ipairs({ "SetTextColor", "SetVertexColor", "SetFontObject" }) do
		if name[method] then
			hooksecurefunc(name, method, Repaint)
		end
	end
end

local function StyleName(unitFrame, on)
	local name = unitFrame.name
	if not (Usable(name) and name.GetFont and name.SetFont and name.SetShadowOffset) then
		return
	end
	if on then
		if not styled[name] then
			local file, size, flags = name:GetFont()
			local saved = { object = name.GetFontObject and name:GetFontObject(), file = file, size = size,
				flags = flags, shadow = { name:GetShadowColor() }, offset = { name:GetShadowOffset() } }
			styled[name] = saved
		end
		KeepStyle(name, styled[name])
		painter:Show()
	elseif styled[name] then
		local saved = styled[name]
		styled[name] = nil
		if saved.object then
			name:SetFontObject(saved.object)
			-- (Set again, so it takes the object's alphabet for its letters.)
			pcall(function() name:SetText(name:GetText()) end)
		elseif saved.file then
			pcall(name.SetFont, name, saved.file, saved.size, saved.flags)
		end
		pcall(name.SetShadowColor, name, unpack(saved.shadow))
		pcall(name.SetShadowOffset, name, unpack(saved.offset))
	end
end

local function TintName(unitFrame, on)
	local name = unitFrame.name
	if not (Usable(name) and name.SetTextColor and name.GetTextColor) then
		return
	end
	local unit = unitFrame.unit
	if on and unit and Style("colour") and TintUnit(unit) then
		local saved = tinted[name]
		if not saved then
			saved = { text = { name:GetTextColor() } }
			if name.GetVertexColor then
				saved.vertex = { name:GetVertexColor() }
			end
			tinted[name] = saved
		end
		saved.unit = unit
		HookName(name)
		PaintName(name, unit)
		painter:Show()
	elseif tinted[name] then
		local saved = tinted[name]
		tinted[name] = nil
		local r, g, b = unpack(saved.text)
		pcall(name.SetTextColor, name, r, g, b, select(4, name:GetTextColor()))
		if saved.vertex then
			r, g, b = unpack(saved.vertex)
			pcall(name.SetVertexColor, name, r, g, b, select(4, name:GetVertexColor()))
		end
	end
end

local function ApplyPlate(plate, personal)
	local unitFrame = plate and plate.UnitFrame
	if not Usable(unitFrame) or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	local body = bodyShare[plate] or 1
	CentreName(unitFrame, nameShare[plate] ~= nil and body < 1)
	TintName(unitFrame, nameShare[plate] ~= nil and body < 1)
	StyleName(unitFrame, nameShare[plate] ~= nil and body < 1)
	for _, part in ipairs(ns.PLATE_PARTS) do
		local level = plate ~= personal and levels[part] or 1
		if part == "Name" then
			level = math.max(level * body, nameShare[plate] or 0)
		else
			level = level * body
		end
		EachPartFrame(unitFrame, part, Fade, level)
	end
	if next(held) then
		keeper:Show()
	end
end

local function ApplyAll()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	local personal = PersonalPlate()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		ApplyPlate(plate, personal)
	end
end
ApplyAll = ns.Profiled("Plate parts", ApplyAll)

-- After a name style change (the dev Name Style page): every name-only
-- plate's name drawn again from the game's.
function ns.RefreshPlateNameStyle()
	for _, saved in pairs(styled) do
		saved.dirty = true
	end
	ApplyAll()
end

-- Whether any part is faded (or still held from being faded).
local function AnyFaded()
	for _, part in ipairs(ns.PLATE_PARTS) do
		if (levels[part] or 1) < 1 then
			return true
		end
	end
	return next(held) ~= nil or next(bodyShare) ~= nil
end

-- The class icon rows (ns.PLATE_CLASS_PARTS): our own icon left of a player's
-- health bar, where Duel Vision's badge goes (and giving way to it), friendly
-- and enemy players apart. Hidden unless ticked: in CineMode as its row says,
-- outside it only with Always ticked.
local CLASS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"
local plateClass = {} -- [plate] = { part = row, class = file name }, or false for no icon
local icons = {} -- [plate] = icon frame

-- What icon a plate's unit has, if any: players' only. (Players that can't be
-- attacked count as friendly.)
local function ReadClass(plate)
	local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
	if not unit or not Ask(UnitIsPlayer, unit) then
		return false
	end
	local ok, _, class = pcall(UnitClass, unit)
	if not (ok and Known(class) and type(class) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]) then
		return false
	end
	return { part = Ask(UnitCanAttack, "player", unit) and "ClassEnemy" or "ClassFriendly", class = class }
end

local function ClassIcon(plate)
	local icon = icons[plate]
	local unitFrame = plate.UnitFrame
	if icon or not Usable(unitFrame) then
		return icon
	end
	local bar = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame
	icon = CreateFrame("Frame", nil, unitFrame)
	icon:SetSize(22, 22)
	icon:SetPoint("RIGHT", bar, "LEFT", -3, 0)
	icon:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 5)
	icon.texture = icon:CreateTexture(nil, "OVERLAY")
	icon.texture:SetAllPoints()
	icon.texture:SetTexture(CLASS_TEXTURE)
	icons[plate] = icon
	return icon
end

-- Shows or hides a plate's class icon as its row and its unit say.
local function RefreshClass(plate)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	if plateClass[plate] == nil then
		plateClass[plate] = ReadClass(plate)
	end
	local info = plateClass[plate]
	local level = info and plate ~= PersonalPlate() and not ns.DuelBadgeShown(plate)
		and levels[info.part] * (bodyShare[plate] or 1) or 0
	local icon = icons[plate]
	if level <= 0 then
		if icon then
			icon:Hide()
		end
		return
	end
	icon = ClassIcon(plate)
	if icon then
		icon.texture:SetTexCoord(unpack(CLASS_ICON_TCOORDS[info.class]))
		icon:SetAlpha(level)
		icon:Show()
	end
end

-- The role icon rows (ns.PLATE_ROLE_PARTS): the game's role icon left of a
-- group member's health bar (the level box is on the right), further out
-- while the class icon or Duel Vision's badge is there. A row per role,
-- shown like the class icons. Only players with a role set have one.
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLES = {
	TANK = { part = "RoleTank", coords = { 0, 19 / 64, 22 / 64, 41 / 64 } },
	HEALER = { part = "RoleHealer", coords = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 } },
	DAMAGER = { part = "RoleDamager", coords = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } },
}
local plateRole = {} -- [plate] = an entry of ROLES, or false for no icon
local roleIcons = {} -- [plate] = icon frame

-- A plate's unit's role in your group, if it's a player with one.
local function ReadRole(plate)
	local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
	if not unit or not UnitGroupRolesAssigned or not Ask(UnitIsPlayer, unit) then
		return false
	end
	local ok, role = pcall(UnitGroupRolesAssigned, unit)
	return ok and Known(role) and ROLES[role] or false
end

local function RoleIcon(plate)
	local icon = roleIcons[plate]
	local unitFrame = plate.UnitFrame
	if icon or not Usable(unitFrame) then
		return icon
	end
	local bar = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame
	icon = CreateFrame("Frame", nil, unitFrame)
	icon:SetSize(18, 18)
	icon.bar = bar
	icon:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 5)
	icon.texture = icon:CreateTexture(nil, "OVERLAY")
	icon.texture:SetAllPoints()
	icon.texture:SetTexture(ROLE_TEXTURE)
	roleIcons[plate] = icon
	return icon
end

-- Shows or hides a plate's role icon as its row and its unit say.
local function RefreshRoleIcon(plate)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	if plateRole[plate] == nil then
		plateRole[plate] = ReadRole(plate)
	end
	local role = plateRole[plate]
	local level = role and plate ~= PersonalPlate() and levels[role.part] * (bodyShare[plate] or 1) or 0
	local icon = roleIcons[plate]
	if level <= 0 then
		if icon then
			icon:Hide()
		end
		return
	end
	icon = RoleIcon(plate)
	if icon then
		local classIcon = icons[plate]
		local beside = ns.DuelBadgeShown(plate) or (classIcon and classIcon:IsShown())
		icon:ClearAllPoints()
		icon:SetPoint("RIGHT", icon.bar, "LEFT", beside and -28 or -3, 0)
		icon.texture:SetTexCoord(unpack(role.coords))
		icon:SetAlpha(level)
		icon:Show()
	end
end

-- The Quest Icon row: a golden exclamation mark left of the health bar of a
-- unit for a quest objective you haven't finished (ns.IsQuestMob), where
-- players' class icons go (quest mobs aren't players). Shown like the class
-- icons, its one box (Always) ticked on the Vision page's Quest Vision, whose
-- Enable and page switch it follows.
local QUEST_TEXTURE = ns.QUEST_MOB_TEXTURE
local questIcons = {} -- [plate] = icon frame

local function QuestIcon(plate)
	local icon = questIcons[plate]
	local unitFrame = plate.UnitFrame
	if icon or not Usable(unitFrame) then
		return icon
	end
	local bar = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame
	icon = CreateFrame("Frame", nil, unitFrame)
	icon:SetSize(20, 20)
	icon:SetPoint("RIGHT", bar, "LEFT", -3, 0)
	icon:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 5)
	icon.texture = icon:CreateTexture(nil, "OVERLAY")
	icon.texture:SetAllPoints()
	icon.texture:SetTexture(QUEST_TEXTURE)
	questIcons[plate] = icon
	return icon
end

local function RefreshQuestIcon(plate)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	local level = (levels.QuestIcon or 0) * (bodyShare[plate] or 1)
	local icon = questIcons[plate]
	if level > 0 and plate ~= PersonalPlate() then
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if not (unit and ns.IsQuestMob(unit)) then
			level = 0
		end
	end
	if level <= 0 then
		if icon then
			icon:Hide()
		end
		return
	end
	icon = QuestIcon(plate)
	if icon then
		icon:SetAlpha(level)
		icon:Show()
	end
end

-- A plate's icons (the role icon goes by where the class icon is).
function ns.RefreshClassIcon(plate)
	RefreshClass(plate)
	RefreshRoleIcon(plate)
	RefreshQuestIcon(plate)
end

local function RefreshClassIcons()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			ns.RefreshClassIcon(plate)
		end
	end
end

local function AnyClassIcons()
	for _, part in ipairs(ns.PLATE_ICON_PARTS) do
		if (levels[part] or 0) > 0 then
			return true
		end
	end
	return false
end

-- A plate given a new unit takes the parts' alphas (or lets go of its last
-- unit's), and its class and role icons. One whose player changes sides (a
-- duel starting) swaps icon rows; roles are read again when the group changes.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
watcher:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
watcher:RegisterEvent("UNIT_FACTION")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
pcall(watcher.RegisterEvent, watcher, "PLAYER_ROLES_ASSIGNED") -- (not every client has it)
watcher:SetScript("OnEvent", function(_, event, unit)
	if not (ns.db and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return
	end
	if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
		wipe(plateRole)
		if AnyClassIcons() or next(roleIcons) then
			RefreshClassIcons()
		end
		return
	end
	if event == "UNIT_FACTION" and not (type(unit) == "string" and unit:find("^nameplate")) then
		return
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		return
	end
	if event == "NAME_PLATE_UNIT_REMOVED" then
		plateClass[plate], plateRole[plate] = nil, nil
		bodyShare[plate], nameShare[plate] = nil, nil
		if Usable(plate.UnitFrame) then
			CentreName(plate.UnitFrame, false)
			TintName(plate.UnitFrame, false)
			StyleName(plate.UnitFrame, false)
		end
		if icons[plate] then
			icons[plate]:Hide()
		end
		if roleIcons[plate] then
			roleIcons[plate]:Hide()
		end
		if questIcons[plate] then
			questIcons[plate]:Hide()
		end
		return
	end
	plateClass[plate], plateRole[plate] = nil, nil
	if AnyClassIcons() or icons[plate] or roleIcons[plate] or questIcons[plate] then
		ns.RefreshClassIcon(plate)
	end
	if event == "NAME_PLATE_UNIT_ADDED" and AnyFaded() then
		ApplyPlate(plate, PersonalPlate())
	end
end)

-- From Effects, with each plate's alpha: how much of it the plate's parts
-- other than the name get (body, 0 to 1) and the name at least (name), for a
-- plate held up for its name alone (Names rows: see Effects' nameLevel).
function ns.SetPlateBody(plate, body, name)
	if not plate then
		return
	end
	body = body < 1 and body or nil
	name = name > 0 and name or nil
	if bodyShare[plate] == body and nameShare[plate] == name then
		return
	end
	bodyShare[plate], nameShare[plate] = body, name
	ApplyPlate(plate, PersonalPlate())
	if AnyClassIcons() or icons[plate] or roleIcons[plate] or questIcons[plate] then
		ns.RefreshClassIcon(plate)
	end
end

local QUEST_ICONS_EVERY = 0.5
local questIconsAt = 0

-- Each tick, from ns.UpdatePlates: active while the Nameplates page steers
-- plates (CineMode, its master switch on).
function ns.UpdatePlateParts(active, elapsed)
	local changed = false
	for _, part in ipairs(ns.PLATE_PARTS) do
		local target = (not active or ns.PlateRowWanted("Part" .. part)) and 1 or 0
		local level = levels[part]
		if level == nil then
			levels[part] = target -- logging in: no fade
			changed = changed or target < 1
		elseif level ~= target then
			levels[part] = ns.Approach(level, target, elapsed, target > level and ns.FadeInTime() or ns.FadeOutTime())
			changed = true
		end
	end
	if changed then
		ApplyAll()
	end
	-- The class and role icons: shown nowhere with the page's master switch off.
	local iconsChanged = false
	for _, part in ipairs(ns.PLATE_ICON_PARTS) do
		local wanted
		if not ns.db.handlePlates or (part == "QuestIcon" and not ns.Setting("questVision")) then
			wanted = false
		elseif active then
			wanted = ns.PlateRowWanted("Part" .. part)
		else
			wanted = ns.db["plateAlwaysPart" .. part]
		end
		local target = wanted and 1 or 0
		local level = levels[part]
		if level == nil then
			levels[part] = target
			iconsChanged = iconsChanged or target > 0
		elseif level ~= target then
			levels[part] = ns.Approach(level, target, elapsed, target > level and ns.FadeInTime() or ns.FadeOutTime())
			iconsChanged = true
		end
	end
	if iconsChanged then
		RefreshClassIcons()
	elseif (levels.QuestIcon or 0) > 0 and GetTime() >= questIconsAt then
		-- (Quest progress comes and goes without the row changing: looked at again now and then.)
		questIconsAt = GetTime() + QUEST_ICONS_EVERY
		for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
			RefreshQuestIcon(plate)
		end
	end
end

-- For /cine debug plates: which of each part's frames the plate has, then
-- every frame and text on it, for finding parts a client names otherwise.
-- One frame or texture for the debug listing: its type, whether it's shown,
-- a text's words and a texture's colour. (Not everything can say:
-- animations, say. Anything that errors is listed bare.)
local function Entry(name, value)
	local okType, kind = pcall(function() return value:GetObjectType() end)
	local okShown, shown = pcall(function() return value:IsShown() end)
	local okText, text = pcall(function() return kind == "FontString" and value:GetText() or nil end)
	if okText and issecretvalue and issecretvalue(text) then
		text = "(secret)"
	end
	local okColor, color = pcall(function()
		if kind ~= "Texture" then
			return nil
		end
		local r, g, b = value:GetVertexColor()
		return ("%.2f/%.2f/%.2f"):format(r, g, b)
	end)
	return name .. ":" .. (okType and tostring(kind) or "?")
		.. ((okShown and not ns.Flag(shown)) and "(hidden)" or "")
		.. ((okText and text) and (' "' .. text .. '"') or "")
		.. ((okColor and color) and (" " .. color) or "")
end

-- Every frame and texture on a frame: by its field, then its textures and
-- texts that have none (numbered).
local function ListFields(frame)
	local children, named = {}, {}
	for field, value in pairs(frame) do
		-- (Some tables can't even be looked into: a locked one on a group member's plate.)
		if type(field) == "string" and type(value) == "table"
			and select(2, pcall(function() return value.GetObjectType ~= nil end)) == true then
			named[value] = true
			children[#children + 1] = Entry(field, value)
		end
	end
	table.sort(children)
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	for i, region in ipairs(ok and regions or {}) do
		if not named[region] then
			children[#children + 1] = Entry("#" .. i, region)
		end
	end
	return table.concat(children, ", ")
end

-- For /cine debug plates: the plate's name colour (text, then vertex), the
-- game's colour for its unit, and why ours is on it or not.
local function Rgb(r, g, b)
	if not (Known(r) and Known(g) and Known(b)) then
		return "secret"
	end
	return ("%.2f/%.2f/%.2f"):format(r or -1, g or -1, b or -1)
end

function ns.DescribePlateName(unitFrame)
	local name = unitFrame and unitFrame.name
	if not Usable(name) then
		return "no name text"
	end
	local plate = unitFrame:GetParent()
	local unit = unitFrame.unit
	local ok, text = pcall(function()
		return "text " .. Rgb(name:GetTextColor())
			.. (name.GetVertexColor and (" vertex " .. Rgb(name:GetVertexColor())) or "")
	end)
	local okGame, game = pcall(function()
		return UnitSelectionColor and Rgb(UnitSelectionColor(unit)) or "no UnitSelectionColor"
	end)
	return ("%s, game %s, ours=%s unit=%s tint unit=%s body=%s name=%s"):format(
		ok and text or ("error " .. tostring(text)), okGame and game or ("error " .. tostring(game)),
		tostring(tinted[name] ~= nil), tostring(unit), tostring(unit and TintUnit(unit)),
		tostring(bodyShare[plate]), tostring(nameShare[plate]))
end

function ns.DescribePlateParts(unitFrame)
	local found = {}
	for _, part in ipairs(ns.PLATE_PARTS) do
		local names = {}
		EachPartFrame(unitFrame, part, function(frame)
			-- (With its alpha now, and @ ours while held.)
			local ok, alpha = pcall(function() return ("%.2f"):format(frame:GetAlpha()) end)
			local wanted = held[frame]
			local okName, name = pcall(frame.GetDebugName, frame)
			names[#names + 1] = (okName and tostring(name):match("[^.]*%.?[^.]+$") or "?") .. " " .. (ok and alpha or "?")
				.. (wanted and ("@" .. ("%.2f"):format(wanted)) or "")
		end)
		found[#found + 1] = part .. "=" .. (#names > 0 and table.concat(names, "+") or "NONE")
	end
	-- The role the game gives the plate's unit, and whether our role icon shows.
	local unit = unitFrame.unit
	local okRole, role = pcall(function() return unit and UnitGroupRolesAssigned(unit) end)
	if okRole and issecretvalue and issecretvalue(role) then
		role = "(secret)"
	end
	local roleIcon = roleIcons[unitFrame:GetParent()]
	found[#found + 1] = "Role=" .. (okRole and tostring(role) or "?") .. " icon="
		.. (roleIcon and (roleIcon:IsShown() and "shown" or "hidden") or "none")
	if unit and ns.DescribeQuestMob then
		local questIcon = questIcons[unitFrame:GetParent()]
		found[#found + 1] = ns.DescribeQuestMob(unit) .. " icon="
			.. (questIcon and (questIcon:IsShown() and "shown" or "hidden") or "none")
	end
	-- The health bar's container, the bar, and any frame on the bar (its border).
	local healthFields = {}
	local container, bar = unitFrame.HealthBarsContainer, unitFrame.healthBar
	if type(container) == "table" and container.GetObjectType then
		healthFields[#healthFields + 1] = "container: " .. ListFields(container)
	end
	if type(bar) == "table" and bar.GetObjectType then
		healthFields[#healthFields + 1] = "healthBar: " .. ListFields(bar)
		for field, value in pairs(bar) do
			if type(field) == "string" and type(value) == "table"
				and select(2, pcall(function() return value.GetRegions ~= nil end)) == true then
				healthFields[#healthFields + 1] = "healthBar." .. field .. ": " .. ListFields(value)
			end
		end
	end
	-- And the auras' frame, whose lists are the Buffs and Debuffs parts.
	local auras = unitFrame.AurasFrame
	if type(auras) == "table" and auras.GetObjectType then
		healthFields[#healthFields + 1] = "AurasFrame: " .. ListFields(auras)
	end
	healthFields = #healthFields > 0 and table.concat(healthFields, " | ") or "NONE"
	return table.concat(found, ", "), ListFields(unitFrame), healthFields
end
