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

-- Names on plates showing just the name are drawn by a text of our own (with
-- the Nameplates page's tick), the game's name faded to nothing behind it:
-- the game keeps setting its own name's colour, font and place (and on WoW
-- Forever won't even say where it is), ours it leaves alone. Ours sits on the
-- game's name, moved up or down as the Name Style page says, coloured as the
-- game colours names over heads: red hostile, yellow neutral, green friendly,
-- friendly players blue, white or in the class colours their plates give
-- them (plateNameFriends). WoW Forever's colours and names can be secret: they
-- go straight from the game to our text. [unit frame] = our text.
local texts = {}
-- [unit frame] = a copy of our text in its last band's look, fading out
-- while the text fades in at the new one (see swaps).
local ghosts = {}

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function Ask(fn, ...)
	local ok, value = pcall(fn, ...)
	return ok and Known(value) and value and true or false
end

-- A name style setting (the Name Style page's, see Core's DEFAULTS).
local function Style(key)
	local value = ns.db and ns.db[key]
	if value == nil then
		return ns.DEFAULTS[key]
	end
	return value
end

-- Whether a unit's name takes a colour of ours: true for the game's colour
-- for it over heads, a friendly player's colour of our own ("blue",
-- "white"), or false for the plate's own (class colours).
local function TintUnit(unit)
	local okGuid, guid = pcall(UnitGUID, unit)
	if okGuid and Known(guid) and type(guid) == "string" and guid:find("^Player%-")
		and not Ask(UnitCanAttack, "player", unit) then
		local friends = Style("plateNameFriends")
		return friends ~= "class" and friends
	end
	return true
end

-- Friendly players' colours of our own. Blue as the game's names over their
-- heads (read off a screenshot: the game's colour for them on plates is a
-- far darker pure blue); green, its own, while they're PvP flagged, as
-- there too.
local FRIEND_COLOURS = { blue = { 0.4, 0.4, 1 }, white = { 1, 1, 1 } }
ns.PLATE_FRIEND_COLOURS = FRIEND_COLOURS -- (the Name Style page's preview)

local function PaintName(text, unit, own)
	local colour = FRIEND_COLOURS[own or ""]
	if colour and not (own == "blue" and Ask(UnitIsPVP, unit)) then
		text:SetTextColor(colour[1], colour[2], colour[3])
	elseif UnitSelectionColor then
		pcall(function() text:SetTextColor(UnitSelectionColor(unit)) end)
	else
		local reaction = Ask(UnitReaction, unit, "player") and UnitReaction(unit, "player")
		local color = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
		if color then
			text:SetTextColor(color.r, color.g, color.b)
		end
	end
end

local OUTLINES = { [0] = "", "OUTLINE", "THICKOUTLINE" }

local function Outlined(flags, outline)
	flags = (flags or ""):gsub("THICKOUTLINE", ""):gsub("OUTLINE", "")
	if OUTLINES[outline] ~= "" then
		flags = flags .. "," .. OUTLINES[outline]
	end
	return (flags:gsub("^,+", ""):gsub(",+$", ""):gsub(",,+", ","))
end
ns.OutlinedFlags = Outlined -- (the Name Style page's preview)

-- A font file holds one alphabet: a name set in the plate's file shows
-- Cyrillic (or Korean, Chinese) letters as boxes. So names get a font family
-- of our own, like the game's plate font: its font for each alphabet, at our
-- size and outline. (From the game's font object where it can say which font
-- each alphabet has; else the game's usual ones.) Kept by size and flags.
-- nil on clients without font families.
local ALPHABETS = { "roman", "russian", "korean", "simplifiedchinese", "traditionalchinese" }
local ALPHABET_FILES = { russian = "Fonts\\FRIZQT___CYR.TTF", korean = "Fonts\\2002.TTF",
	simplifiedchinese = "Fonts\\ARKai_T.ttf", traditionalchinese = "Fonts\\blei00d.TTF" }
local families, familyCount = {}, 0

-- object: the game's font object for the name (its other alphabets' fonts);
-- file, size: its roman font as it is; scale: times that size.
local function NameFamily(object, file, size, scale, flags)
	if not CreateFontFamily or not (file and size) then
		return nil
	end
	local key = tostring(object) .. "|" .. file .. "|" .. ("%.1f"):format(size * scale) .. "|" .. (flags or "")
	local family = families[key]
	if family == nil then
		local members = {}
		for _, alphabet in ipairs(ALPHABETS) do
			local memberFile, memberSize = file, size
			if alphabet ~= "roman" then
				memberFile = ALPHABET_FILES[alphabet]
				local ok, member = pcall(function() return object:GetFontObjectForAlphabet(alphabet) end)
				local memberFont, height = nil, nil
				if ok and member then
					memberFont, height = member:GetFont()
				end
				if memberFont then
					memberFile, memberSize = memberFont, height or size
				end
			end
			members[#members + 1] = { alphabet = alphabet, file = memberFile, height = memberSize * scale,
				flags = flags or "" }
		end
		familyCount = familyCount + 1
		local ok, made = pcall(CreateFontFamily, "CinematicPlateName" .. familyCount, members)
		family = ok and made or false
		families[key] = family
	end
	return family or nil
end
ns.PlateNameFamily = NameFamily

-- Sets a text's font, every alphabet's letters drawn (a family where the
-- client has them), its words set again so they take it.
local function SetNameFont(text, object, file, size, scale, flags)
	local family = NameFamily(object, file, size, scale, flags)
	if family then
		text:SetFontObject(family)
	else
		pcall(text.SetFont, text, file, size * scale, flags)
	end
	pcall(function() text:SetText(text:GetText()) end)
end
ns.SetPlateNameFont = SetNameFont

-- Further off, smaller and lower: the game's names over heads are drawn in
-- the world, so they shrink with their distance from the camera (and take
-- over from the plate's at the edge of nameplate range). WoW Forever's
-- plates don't scale, so ours are sized and placed by that distance, as
-- near as it can be told: the camera's from you (exact), plus the unit's
-- from you in bands, the game only saying whether it's within about 11
-- yards (trade range) and 28 (follow range). Size and height follow
-- perspective (one over the distance) through the Name Style page's two
-- points, close and far, and on past them. A unit has to stay in a new band
-- a moment first, and its name then swaps: a copy in the old look fading out
-- as the new fades in, both sliding to the new height (a size can't change
-- smoothly, a place can: see ghosts and SwapShares);
-- zooming changes them in small steps. Bands aren't
-- looked at in fights (the game may not allow it). Not on retail, whose
-- plates scale with distance themselves. [plate] = band, 1 to 3 (nil: 2).
local FAR_USED = not ns.isRetail
local FAR_CHECK, FAR_HOLD, FAR_SWAP = 0.25, 0.5, 0.6 -- seconds
local BAND_YARDS = { 4, 16, 35 } -- a unit's rough distance from you, by band
local CLOSE_YARDS, FAR_YARDS = 10, 50 -- from the camera: the page's two points
local SIZE_STEP = 0.05 -- size changes in steps (text sized smoothly wobbles)
local bandOf, farChecked = {}, {}
local farSince = {} -- [plate] = when it was first seen in another band
local swaps = {} -- [plate] = { started = time, to = band }
local zoom = 0 -- the camera's distance from you, this frame

-- Out of sight, gone: the game's names over heads hide behind walls, a
-- plate shows through them. The game dims a plate whose unit is out of
-- sight (nameplateOccludedAlphaMult, the plate's own alpha: WoW Forever
-- does this much), so a name shown alone fades out while its plate is
-- dimmed, and back as its unit comes into sight. Full plates are left
-- dimmed as the game has them. [plate] = how far it shows (nil: all).
local sight = {}
local SIGHT_FADE = 0.4 -- seconds

-- A unit's band: 1 within about 11 yards, 2 within 28, 3 beyond; nil when
-- the game won't say.
local function Band(unit)
	if not unit or InCombatLockdown() then
		return nil
	end
	local ok, near = pcall(CheckInteractDistance, unit, 4)
	if not ok or not Known(near) or near == nil then
		return nil
	end
	if not near then
		return 3
	end
	local okClose, close = pcall(CheckInteractDistance, unit, 2)
	return (okClose and Known(close) and close) and 1 or 2
end

-- A name's size (times the plate's) and height for its band, at the
-- camera's distance now (see bandOf); retail's, as the page says.
local function Look(band)
	if not FAR_USED then
		return Style("plateNameSize"), Style("plateNameY")
	end
	local yards = math.max(1, zoom + BAND_YARDS[band or 2])
	local t = (1 / yards - 1 / FAR_YARDS) / (1 / CLOSE_YARDS - 1 / FAR_YARDS)
	local size = Style("plateNameFarSize") + t * (Style("plateNameCloseSize") - Style("plateNameFarSize"))
	local y = Style("plateNameFarY") + t * (Style("plateNameCloseY") - Style("plateNameFarY"))
	size = math.min(3, math.max(0.2, size))
	return math.floor(size / SIZE_STEP + 0.5) * SIZE_STEP, math.floor(math.min(80, math.max(-80, y)) + 0.5)
end

-- How far a plate's name is through swapping to its new look: 0 to 1 (1:
-- none under way).
local function SwapFade(plate)
	local swap = swaps[plate]
	if not swap then
		return 1
	end
	return math.min(1, (GetTime() - swap.started) / FAR_SWAP)
end

-- How much shows of the new look (in) and the old (out) that far through:
-- the old fading out over the first half, the new in over the second, with
-- only a sliver of overlap (two sizes over each other read as a double image).
local SWAP_OVERLAP = 0.1
local function SwapShares(t)
	local half = (1 + SWAP_OVERLAP) / 2
	local out = math.max(0, 1 - t / half)
	local into = math.min(1, math.max(0, (t - (1 - half)) / half))
	return into, out
end

local function UnitOf(plate)
	return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

-- Draws our text over the game's name: its look when that changed (dirty),
-- then its words and colour, which the game may change at any time.
local function DrawName(text, name, unit)
	if text.dirty then
		text.dirty = nil
		local object = name.GetFontObject and name:GetFontObject()
		local file, size, flags = name:GetFont()
		if not file then
			object = _G.SystemFont_NamePlate or _G.GameFontNormal
			file, size, flags = object:GetFont()
		end
		SetNameFont(text, object, file, size, text.size, Outlined(flags, Style("plateNameOutline")))
		if Style("plateNameShadow") then
			text:SetShadowOffset(Style("plateNameShadowX"), Style("plateNameShadowY"))
			text:SetShadowColor(0, 0, 0, Style("plateNameShadowAlpha"))
		else
			text:SetShadowOffset(0, 0)
		end
		-- (Further off, lower: a plate's name sits a fixed height over the unit's
		-- head, and the game's names over heads come down closer to it with distance.)
		text:ClearAllPoints()
		text:SetPoint("BOTTOM", name, "BOTTOM", 0, text.y)
	end
	-- (The game's own words: a secret name shows all the same.)
	local ok, words = pcall(name.GetText, name)
	if not ok then
		ok, words = pcall(UnitName, unit)
	end
	if ok then
		pcall(text.SetText, text, words)
	end
	-- (Colour only: on WoW Forever a FontString's colour carries its alpha, and
	-- the game's name is faded out under ours, so its alpha is 0, tested.)
	local alpha = text:GetAlpha()
	local tint = Style("plateNameColour") and TintUnit(unit)
	if tint then
		PaintName(text, unit, tint ~= true and tint or nil)
	else
		-- (A player's class colour from their class, not the game's name, which
		-- it can turn white.)
		local okClass, _, class = pcall(UnitClass, unit)
		local colour = okClass and Known(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if colour then
			text:SetTextColor(colour.r, colour.g, colour.b)
		else
			pcall(function()
				local r, g, b = name:GetTextColor()
				text:SetTextColor(r, g, b)
			end)
		end
	end
	text:SetAlpha(alpha)
	-- Retail's plates grow as their units come nearer: undone, for one size.
	if ns.isRetail and text.SetScale then
		local scale = 1
		local parent = text:GetParent()
		if Style("plateNameFixedSize") and parent and parent.GetEffectiveScale then
			local plateScale, uiScale = parent:GetEffectiveScale(), UIParent:GetEffectiveScale()
			if Known(plateScale) and Known(uiScale) and plateScale > 0 then
				scale = uiScale / plateScale
			end
		end
		text:SetScale(scale)
	end
end

-- A text's size and height as its band and the camera have them now
-- (dirty when they changed).
local function UpdateLook(text, band)
	local size, y = Look(band)
	if text.size ~= size or text.y ~= y then
		text.size, text.y, text.dirty = size, y, true
	end
end

-- Shows or hides our text for a plate, at alpha (nil: hidden), and while
-- its band swaps, its copy in the old look fading out under it.
local function OwnName(plate, alpha)
	local unitFrame = plate.UnitFrame
	local text, ghost = texts[unitFrame], ghosts[unitFrame]
	local name = unitFrame.name
	local unit = UnitOf(plate)
	if not (alpha and alpha > 0 and unit and Usable(name)) then
		if text then
			text:Hide()
		end
		if ghost then
			ghost:Hide()
		end
		return
	end
	if not text then
		text = unitFrame:CreateFontString(nil, "OVERLAY")
		text.dirty = true
		texts[unitFrame] = text
	end
	local share = SwapFade(plate)
	local into, out = SwapShares(share)
	text.band = bandOf[plate] or 2
	UpdateLook(text, text.band)
	DrawName(text, name, unit)
	text:SetAlpha(alpha * into)
	text:Show()
	local swap = swaps[plate]
	if swap and share < 1 then
		if not ghost then
			ghost = unitFrame:CreateFontString(nil, "OVERLAY")
			ghost.dirty = true
			ghosts[unitFrame] = ghost
		end
		ghost.band = swap.from
		UpdateLook(ghost, ghost.band)
		DrawName(ghost, name, unit)
		ghost:SetAlpha(alpha * out)
		ghost:Show()
		-- (Both slide from the old height to the new together, so they sit on
		-- one line and only the size blends: a place moves smoothly, a size
		-- doesn't.)
		local y = ghost.y + (text.y - ghost.y) * share
		for _, each in ipairs({ text, ghost }) do
			each:ClearAllPoints()
			each:SetPoint("BOTTOM", name, "BOTTOM", 0, y)
		end
		text.slid = true
	else
		if ghost then
			ghost:Hide()
		end
		if text.slid then
			text.slid = nil
			text:ClearAllPoints()
			text:SetPoint("BOTTOM", name, "BOTTOM", 0, text.y)
		end
	end
end

-- Our text for a plate while it shows (the guild line goes under it).
function ns.PlateNameText(plate)
	local text = plate and plate.UnitFrame and texts[plate.UnitFrame]
	return text and text:IsShown() and text or nil
end

local function ApplyPlate(plate, personal)
	local unitFrame = plate and plate.UnitFrame
	if not Usable(unitFrame) or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	local body = bodyShare[plate] or 1
	local kept = nameShare[plate]
	-- A plate filling in round a name kept up (your target clicked) or
	-- emptying back to it: the name crossfades, so its look never jumps.
	-- Its name-only look fades out over the first half of the rest coming in,
	-- the plate's own look fades in over the second half (and back).
	local crossfading = kept ~= nil and body < 1
	local nameOnly = crossfading and body < 0.5
	local nameFade = crossfading and (nameOnly and 1 - 2 * body or 2 * body - 1) or 1
	local nameAlpha = nameOnly and kept * nameFade * (sight[plate] or 1) or 0
	-- (Our own text in its place, with the Nameplates page's tick: see texts.)
	local ours = nameOnly and plate ~= personal and Style("plateNameStyle")
	CentreName(unitFrame, nameOnly and not ours)
	OwnName(plate, ours and nameAlpha * Style("plateNameAlpha") or nil)
	for _, part in ipairs(ns.PLATE_PARTS) do
		local level = plate ~= personal and levels[part] or 1
		if part == "Name" then
			if ours then
				level = 0
			elseif nameOnly then
				level = nameAlpha
			elseif crossfading then
				level = math.max(level, kept) * nameFade
			else
				level = math.max(level * body, kept or 0)
			end
		else
			level = level * body
		end
		EachPartFrame(unitFrame, part, Fade, level)
	end
	-- (And the guild line under a name shown alone: PlateGuild.lua. It sits
	-- under our text, so it fades in with its new look.)
	ns.SetPlateGuild(plate, plate ~= personal and nameAlpha * (ours and (SwapShares(SwapFade(plate))) or 1) or 0)
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

-- After a name style change (the Name Style page): our texts drawn anew.
function ns.RefreshPlateNameStyle()
	for _, text in pairs(texts) do
		text.dirty = true
	end
	for _, ghost in pairs(ghosts) do
		ghost.dirty = true
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
		and (levels[info.part] or 0) * (bodyShare[plate] or 1) or 0
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
	local level = role and plate ~= PersonalPlate() and (levels[role.part] or 0) * (bodyShare[plate] or 1) or 0
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
	ns.SetQuestMark(icon.texture)
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
		bandOf[plate], farChecked[plate], farSince[plate], swaps[plate] = nil, nil, nil, nil
		sight[plate] = nil
		if Usable(plate.UnitFrame) then
			CentreName(plate.UnitFrame, false)
			OwnName(plate, nil)
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
	-- (A name first kept up: its band straight away, no swap.)
	if FAR_USED and name and not farChecked[plate] then
		farChecked[plate] = true
		bandOf[plate] = Band(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
	end
	if name then
		ns.WatchFarNames()
	end
	ApplyPlate(plate, PersonalPlate())
	if AnyClassIcons() or icons[plate] or roleIcons[plate] or questIcons[plate] then
		ns.RefreshClassIcon(plate)
	end
end

-- Each frame while names show alone: names out of sight faded, swaps
-- under way faded, names sized anew as the camera zooms (Forever), and every
-- FAR_CHECK our texts' words and colours looked at again (a unit changing
-- sides, a name read late) and, on Forever, each name-only plate's band.
-- Only plates showing nothing but the name (a target's filling in has its
-- own crossfade).
local farWatch = CreateFrame("Frame")
farWatch:Hide()
local farCheckAt = 0
farWatch:SetScript("OnUpdate", ns.Profiled("Plate names", function(self, elapsed)
	local now = GetTime()
	local personal
	-- (The camera moved in or out: see Look.)
	local nowZoom = FAR_USED and GetCameraZoom and GetCameraZoom() or 0
	if type(nowZoom) == "number" and Known(nowZoom) and nowZoom ~= zoom then
		zoom = nowZoom
		for unitFrame, text in pairs(texts) do
			if text:IsShown() and Usable(unitFrame.name) and unitFrame.unit then
				UpdateLook(text, text.band)
				if text.dirty then
					DrawName(text, unitFrame.name, unitFrame.unit)
				end
			end
		end
	end
	-- (In sight or not: see sight. Plates showing just a name.)
	for plate in pairs(nameShare) do
		local level = sight[plate] or 1
		local okAlpha, alpha = pcall(plate.GetAlpha, plate)
		local target = ((bodyShare[plate] or 1) < 0.5 and okAlpha and Known(alpha) and alpha < 0.99) and 0 or 1
		if level ~= target then
			level = ns.Approach(level, target, elapsed, SIGHT_FADE)
			sight[plate] = level < 1 and level or nil
			personal = personal or PersonalPlate()
			ApplyPlate(plate, personal)
		end
	end
	for plate, swap in pairs(swaps) do
		personal = personal or PersonalPlate()
		if now - swap.started >= FAR_SWAP then
			swaps[plate] = nil
		end
		ApplyPlate(plate, personal)
	end
	if now >= farCheckAt then
		farCheckAt = now + FAR_CHECK
		for unitFrame, text in pairs(texts) do
			if text:IsShown() and Usable(unitFrame.name) and unitFrame.unit then
				DrawName(text, unitFrame.name, unitFrame.unit)
			end
		end
		for plate in pairs(FAR_USED and nameShare or {}) do
			if (bodyShare[plate] or 1) <= 0 and not swaps[plate] then
				local band = Band(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
				if band == nil or band == (bandOf[plate] or 2) then
					farSince[plate] = nil
				elseif not farSince[plate] then
					farSince[plate] = now
				elseif now - farSince[plate] >= FAR_HOLD then
					farSince[plate] = nil
					-- (The text takes the new look at once, fading in over a copy in the old.)
					swaps[plate] = { started = now, from = bandOf[plate] or 2, to = band }
					bandOf[plate] = band
				end
			end
		end
	end
	if not (next(nameShare) or next(swaps)) then
		self:Hide()
	end
end))

function ns.WatchFarNames()
	farWatch:Show()
end

-- /cine debug names: every 0.1 s, each player's plate's name state, logged
-- when it changes, to see why a name blinks on and off.
local namesTicker
local namesLast = {}
function ns.ToggleNamesDebug()
	if namesTicker then
		namesTicker:Cancel()
		namesTicker = nil
		wipe(namesLast)
		return false
	end
	namesTicker = C_Timer.NewTicker(0.1, function()
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			local unit = UnitOf(plate)
			local okGuid, guid = pcall(UnitGUID, unit)
			if unit and okGuid and Known(guid) and type(guid) == "string" and guid:find("^Player%-") then
				local okName, who = pcall(UnitName, unit)
				local okAlpha, alpha = pcall(plate.GetAlpha, plate)
				local text = texts[plate.UnitFrame]
				local line = ("%s: %s | name=%s body=%s plateAlpha=%s sight=%s band=%s swap=%s text=%s"):format(
					okName and Known(who) and tostring(who) or unit, ns.DescribePlateNameKept(unit, plate),
					tostring(nameShare[plate]), tostring(bodyShare[plate]),
					okAlpha and Known(alpha) and ("%.2f"):format(alpha) or "?", tostring(sight[plate]),
					tostring(bandOf[plate]), tostring(swaps[plate] and swaps[plate].to),
					text and (text:IsShown() and ("%.2f"):format(text:GetAlpha()) or "hidden") or "none")
				if namesLast[unit] ~= line then
					namesLast[unit] = line
					ns.Log("names", line)
				end
			end
		end
	end)
	return true
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
	local text = texts[unitFrame]
	local ok, colours = pcall(function()
		return "game's text " .. Rgb(name:GetTextColor())
			.. (text and (", ours " .. Rgb(text:GetTextColor())) or "")
	end)
	local okGame, game = pcall(function()
		return UnitSelectionColor and Rgb(UnitSelectionColor(unit)) or "no UnitSelectionColor"
	end)
	return ("%s, game %s, ours=%s band=%s size=%s height=%s unit=%s tint unit=%s body=%s name=%s"):format(
		ok and colours or ("error " .. tostring(colours)), okGame and game or ("error " .. tostring(game)),
		tostring(text ~= nil and text:IsShown()), tostring(bandOf[plate] or 2), tostring(text and text.size),
		tostring(text and text.y), tostring(unit),
		tostring(unit and TintUnit(unit)), tostring(bodyShare[plate]), tostring(nameShare[plate]))
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

-- /cine debug range: what the game says about how far a unit is, for sizing
-- names on name-only plates like the game's names over heads (which shrink
-- with distance). Your target, the unit under the mouse, then the plates
-- showing just a name: each check's answer (true, false, nil, secret, error).
local function Answer(ok, value)
	if not ok then
		return "error"
	elseif issecretvalue and issecretvalue(value) then
		return "secret"
	end
	return tostring(value)
end

function ns.PrintRangeDebug()
	local function Describe(unit)
		local parts = {}
		for i = 1, 4 do
			parts[#parts + 1] = "interact" .. i .. "=" .. Answer(pcall(CheckInteractDistance, unit, i))
		end
		parts[#parts + 1] = "distance=" .. Answer(pcall(function()
			local squared, checked = UnitDistanceSquared(unit)
			return checked and squared and ("%.0f"):format(math.sqrt(squared)) or nil
		end))
		local isItem = C_Item and C_Item.IsItemInRange or IsItemInRange
		parts[#parts + 1] = "bandage=" .. Answer(pcall(isItem, 1251, unit))
		local isSpell = C_Spell and C_Spell.IsSpellInRange or IsSpellInRange
		parts[#parts + 1] = "autoattack=" .. Answer(pcall(isSpell, 6603, unit))
		return table.concat(parts, " ")
	end
	for _, unit in ipairs({ "target", "mouseover" }) do
		if UnitExists(unit) then
			ns.Print(unit .. " " .. tostring(UnitName(unit)) .. ": " .. Describe(unit))
		end
	end
	for plate in pairs(nameShare) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit and (bodyShare[plate] or 1) < 1 then
			local okName, name = pcall(UnitName, unit)
			ns.Print(unit .. " " .. Answer(okName, name) .. ": " .. Describe(unit))
		end
	end
end
