-- Cinematic screen tint: colour grading and a vignette over the game world
-- while cinematic mode is active. Driven from Core.lua's update loop.
local _, ns = ...

local db -- set once saved settings have loaded (ns.CreateTint runs at login)

local function Approach(current, target, elapsed, duration)
	local step = duration > 0 and elapsed / duration or 1
	if current < target then
		return math.min(target, current + step)
	end
	return math.max(target, current - step)
end

-- Screen tint: a full-screen texture over the 3D world but under the UI
-- (BACKGROUND strata, like the letterbox). Multiply ("MOD") blending grades the
-- scene's colours, and can only darken; additive ("ADD") adds a glow. Strength
-- blends the tint toward no change. A vignette of four edge gradients can sit
-- on top. Both fade with cinematic mode.
local TINT_PRESETS = {
	{ key = "none", label = "None", tip = "No colour tint." },
	{ key = "warm", label = "Warm / golden hour", mode = "MOD", color = { 1, 0.82, 0.6 },
		tip = "Soft orange, like late-afternoon light." },
	{ key = "cool", label = "Cool", mode = "MOD", color = { 0.75, 0.88, 1 },
		tip = "Pale blue, crisp and wintry." },
	{ key = "night", label = "Night", mode = "MOD", color = { 0.45, 0.55, 0.85 },
		tip = "Deep blue and darker, like moonlight." },
	{ key = "dusk", label = "Dusk gradient", mode = "MOD",
		top = { 1, 0.7, 0.45 }, bottom = { 0.6, 0.45, 0.85 },
		tip = "Orange at the top fading to purple at the bottom, like a sunset." },
	{ key = "sepia", label = "Sepia-ish", mode = "MOD", color = { 0.95, 0.8, 0.55 },
		tip = "Warm brownish yellow, old-photo warmth. (The world can't be truly desaturated.)" },
	{ key = "dreamy", label = "Dreamy", mode = "ADD", color = { 0.3, 0.22, 0.12 },
		tip = "A faint warm glow added over the scene. Soft and hazy." },
	{ key = "custom", label = "Custom", mode = "MOD",
		tip = "Your own colour, chosen with the colour picker below." },
	{ key = "timeofday", label = "Time of day", mode = "MOD", dynamic = true,
		tip = "Changes through the day: blue at night, pink at dawn, clear in the day, " ..
			"golden in the evening and purple at dusk." },
	{ key = "zone", label = "Zone", mode = "MOD", dynamic = true,
		tip = "A mood for the zone you're in: pale blue in the snow, sandy in deserts, green " ..
			"in swamps and jungles, sickly in blighted lands, ember red near volcanoes. " ..
			"Other zones are left untinted." },
	{ key = "zonetime", label = "Zone + time of day", mode = "MOD", dynamic = true,
		tip = "The zone's mood and the time-of-day colour together: a desert at night is warm " ..
			"sand darkened by moonlight." },
}

-- Zone moods: subtle colours, multiplied over the scene.
local ZONE_MOODS = {
	snow = { { 0.82, 0.9, 1 }, "Snow" },
	desert = { { 1, 0.86, 0.66 }, "Desert" },
	savanna = { { 1, 0.92, 0.78 }, "Savanna" },
	swamp = { { 0.8, 0.92, 0.74 }, "Swamp and jungle" },
	blight = { { 0.88, 0.92, 0.62 }, "Blighted" },
	volcanic = { { 1, 0.72, 0.58 }, "Volcanic" },
	forest = { { 0.92, 0.98, 0.85 }, "Forest" },
	dusky = { { 0.72, 0.75, 0.92 }, "Dusky" },
	forge = { { 0.8, 0.72, 0.62 }, "Forge" },   -- dim, warm and smoky
	hearth = { { 1, 0.95, 0.88 }, "Warm" },      -- just a touch of golden warmth
	dusty = { { 1, 0.86, 0.74 }, "Dusty red" },  -- sun-baked, a little orange
	sickly = { { 0.8, 0.88, 0.7 }, "Sickly" },   -- dim and faintly green
	airy = { { 1, 0.98, 0.93 }, "Airy" },        -- bright and clear, barely warm
	moonlit = { { 0.84, 0.88, 1 }, "Moonlit" },  -- cool, soft blue
	gloomy = { { 0.76, 0.83, 0.82 }, "Gloomy" }, -- foggy grey-green, damp and eerie
	twilight = { { 0.86, 0.8, 1 }, "Twilight" }, -- cool, soft purple-blue
	golden = { { 1, 0.9, 0.7 }, "Golden" },      -- warm harvest gold
}
-- Zones by area ID, so names match in any client language.
local ZONE_AREA_IDS = {
	[1] = "snow", [618] = "snow", [36] = "snow",                       -- Dun Morogh, Winterspring, Alterac Mountains
	[440] = "desert", [1377] = "desert", [3] = "desert",               -- Tanaris, Silithus, Badlands
	[405] = "desert", [400] = "desert",                                -- Desolace, Thousand Needles
	[17] = "savanna", [14] = "savanna", [215] = "savanna",             -- The Barrens, Durotar, Mulgore
	[8] = "swamp", [15] = "swamp", [33] = "swamp", [490] = "swamp",    -- Swamp of Sorrows, Dustwallow, Stranglethorn, Un'Goro
	[28] = "blight", [139] = "blight", [361] = "blight",               -- Western/Eastern Plaguelands, Felwood
	[85] = "blight", [41] = "blight",                                  -- Tirisfal Glades, Deadwind Pass
	[46] = "volcanic", [51] = "volcanic",                              -- Burning Steppes, Searing Gorge
	[12] = "forest", [331] = "forest", [17065] = "forest",             -- Elwynn Forest, Ashenvale, Gilneas
	[10] = "dusky",                                                    -- Duskwood
	[1537] = "forge",                                                  -- Ironforge
	[1519] = "hearth",                                                 -- Stormwind City
	[1637] = "dusty", [1497] = "sickly",                               -- Orgrimmar, Undercity
	[1638] = "airy", [1657] = "moonlit",                               -- Thunder Bluff, Darnassus
	[11] = "gloomy",                                                   -- Wetlands
	[141] = "twilight",                                                -- Teldrassil
	[40] = "golden",                                                   -- Westfall
}
-- Mood order for the options page.
local ZONE_MOOD_ORDER = { "snow", "desert", "savanna", "swamp", "blight", "volcanic", "forest", "dusky", "forge", "hearth", "dusty",
	"sickly", "airy", "moonlit", "gloomy", "twilight", "golden" }
local ZONE_BLEND_TIME = 5 -- seconds to blend between moods at a zone border

-- Time-of-day tint: colours at times of day (minutes after midnight),
-- blended in between.
local TIME_OF_DAY = {
	{ 0, { 0.5, 0.58, 0.88 }, "Night" },
	{ 300, { 0.5, 0.58, 0.88 }, "Night" },
	{ 390, { 1, 0.78, 0.78 }, "Dawn" },
	{ 480, { 1, 1, 1 }, "Day" },
	{ 1020, { 1, 1, 1 }, "Day" },
	{ 1110, { 1, 0.82, 0.6 }, "Golden hour" },
	{ 1200, { 0.78, 0.62, 0.88 }, "Dusk" },
	{ 1290, { 0.5, 0.58, 0.88 }, "Night" },
	{ 1440, { 0.5, 0.58, 0.88 }, "Night" },
}
local TIME_OF_DAY_REFRESH = 20 -- seconds between colour updates
-- Phases you can recolour, with the hour the quick preview shows for each.
local TIME_PHASES = {
	{ "Night", 2 }, { "Dawn", 6 }, { "Day", 12 }, { "Golden hour", 18 }, { "Dusk", 20 },
}
local DEFAULT_PHASE_COLOR = {}
for _, key in ipairs(TIME_OF_DAY) do DEFAULT_PHASE_COLOR[key[3]] = key[2] end
local MENU_PREVIEW_TIME = 8 -- seconds a preview from the minimap menu lasts

-- Tint state. Declared before the functions that use it: a Lua local only
-- exists from its declaration on, so anything above would see a nil global.
local VIGNETTE_SIZE = 0.25 -- fraction of the screen each edge gradient covers
local tintFrame, tintTexture, vignetteEdges
local tintLevel = 0
local tintDirty = false
local tintPreview = false
local menuPreviewHour, menuPreviewUntil = -1, 0
local zoneMoodByName -- zone name -> mood key, built on first use
local zoneColor = { 1, 1, 1 } -- the zone colour shown now, blending toward the zone's mood
local zoneStrength -- the Zone presets' strength shown now, blending toward the zone's own

-- The mood key for the zone you're in, or nil.
local function CurrentZoneMood()
	if not zoneMoodByName then
		zoneMoodByName = {}
		for areaID, mood in pairs(ZONE_AREA_IDS) do
			local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
			if name then
				zoneMoodByName[name] = mood
			end
		end
	end
	return zoneMoodByName[GetRealZoneText() or ""]
end

-- The zone tint for a zone: your override if you set one, else the built-in
-- mood. Returns the colour, a label and whether it's your override.
local function ZoneTint(zoneName)
	local override = db.zoneTints and db.zoneTints[zoneName]
	if type(override) == "table" then
		return override, "Custom colour", true
	elseif override == "none" then
		return { 1, 1, 1 }, "No tint", true
	elseif override and ZONE_MOODS[override] then
		return ZONE_MOODS[override][1], ZONE_MOODS[override][2], true
	end
	CurrentZoneMood() -- builds the name lookup
	local mood = ZONE_MOODS[zoneMoodByName[zoneName]]
	if mood then
		return mood[1], mood[2], false
	end
	return { 1, 1, 1 }, "No tint", false
end

-- A zone's strength for the Zone presets: its own if set, else the main one.
local function ZoneStrength(zoneName)
	local own = db.zoneTintStrength and db.zoneTintStrength[zoneName]
	return own or db.tintStrength, own ~= nil
end

-- Areas within a zone (towns, ports, outposts): they take the zone's tint, but
-- some are softer built in (a clean harbour town in a swamp, say), and the
-- player can give any area its own colour or strength. Names are your game
-- language's.
local AREA_STRENGTH = {
	["Theramore Isle"] = 0.4, ["Booty Bay"] = 0.5, ["Ratchet"] = 0.5, ["Gadgetzan"] = 0.6,
	["Light's Hope Chapel"] = 0.5, ["Everlook"] = 0.6, ["Cenarion Hold"] = 0.6,
	["Menethil Harbor"] = 1.2, -- a little more haunted than the marsh around it
}

local function CurrentArea()
	local zone, area = GetRealZoneText() or "", GetSubZoneText() or ""
	if area ~= "" and area ~= zone then
		return area
	end
end

-- The tint where you're standing: the area's own choice if it has one, else
-- the zone's. Also returns whether it came from the area.
local function HereTint()
	local area = CurrentArea()
	if area and db.zoneTints and db.zoneTints[area] ~= nil then
		local color, label = ZoneTint(area)
		return color, label, true
	end
	local color, label = ZoneTint(GetRealZoneText() or "")
	return color, label, false
end

-- The strength where you're standing: the area's own, or the zone's (softened
-- for the built-in areas). Also returns the area's default and whether it
-- has its own.
local function HereStrength()
	local zoneStrength = (ZoneStrength(GetRealZoneText() or ""))
	local area = CurrentArea()
	if not area then
		return zoneStrength, zoneStrength, false
	end
	local default = zoneStrength * (AREA_STRENGTH[area] or 1)
	local own = db.zoneTintStrength and db.zoneTintStrength[area]
	return own or default, default, own ~= nil
end

local function ZoneTargetColor()
	return (HereTint())
end

-- Moves the shown zone colour and strength toward the zone's. True while
-- still blending.
local function BlendZoneColor(elapsed, instant)
	local target = ZoneTargetColor()
	local targetStrength = (HereStrength())
	local moving = false
	for c = 1, 3 do
		if instant then
			zoneColor[c] = target[c]
		else
			zoneColor[c] = Approach(zoneColor[c], target[c], elapsed, ZONE_BLEND_TIME)
		end
		moving = moving or zoneColor[c] ~= target[c]
	end
	if instant or not zoneStrength then
		zoneStrength = targetStrength
	else
		zoneStrength = Approach(zoneStrength, targetStrength, elapsed, ZONE_BLEND_TIME)
	end
	return moving or zoneStrength ~= targetStrength
end

local function GetClockTime()
	if db.tintClock == "local" then
		local now = date("*t")
		return now.hour, now.min
	end
	return GetGameTime()
end

-- Showing a preview: the Look page is open, or a quick preview from
-- the minimap menu is running.
local function Previewing()
	return tintPreview or GetTime() < menuPreviewUntil
end

-- A phase's colour: your own if you picked one, else the built-in.
local function PhaseColor(name)
	return db and db.timePhaseColors and db.timePhaseColors[name] or DEFAULT_PHASE_COLOR[name]
end

-- A phase's own strength (default full), and the colour as applied: blended
-- toward no change by that strength.
local DEFAULT_PHASE_STRENGTH = { Night = 0.65 } -- others: full
local function PhaseStrength(name)
	return db and db.timePhaseStrength and db.timePhaseStrength[name] or DEFAULT_PHASE_STRENGTH[name] or 1
end

local function AppliedPhaseColor(name)
	local color, strength = PhaseColor(name), PhaseStrength(name)
	return {
		1 - (1 - color[1]) * strength,
		1 - (1 - color[2]) * strength,
		1 - (1 - color[3]) * strength,
	}
end

-- The tint colour for the current time, the phase's name, and the time.
-- A previewed hour (menu preview, or the Look page), else the clock.
-- Time-of-day strength blends the colour toward no change.
local function TimeOfDayColor()
	local hour, minute
	if GetTime() < menuPreviewUntil then
		hour, minute = menuPreviewHour, 0
	elseif tintPreview and (db.tintPreviewHour or -1) >= 0 then
		hour, minute = db.tintPreviewHour, 0
	else
		hour, minute = GetClockTime()
	end
	local now = hour * 60 + minute
	local color, phase = { 1, 1, 1 }, TIME_OF_DAY[1][3]
	for i = 1, #TIME_OF_DAY - 1 do
		local from, to = TIME_OF_DAY[i], TIME_OF_DAY[i + 1]
		if now >= from[1] and now < to[1] then
			local t = (now - from[1]) / (to[1] - from[1])
			local fromColor, toColor = AppliedPhaseColor(from[3]), AppliedPhaseColor(to[3])
			for c = 1, 3 do
				color[c] = fromColor[c] + (toColor[c] - fromColor[c]) * t
			end
			phase = (t < 0.5 and from or to)[3]
			break
		end
	end
	local strength = db.timeTintStrength or 1
	for c = 1, 3 do
		color[c] = 1 - (1 - color[c]) * strength
	end
	return color, phase, hour, minute
end
local TINT_BY_KEY = {}
for _, preset in ipairs(TINT_PRESETS) do TINT_BY_KEY[preset.key] = preset end

-- Gradient across a texture, coping with both the colour-object API of newer
-- clients and the older number-based one. Colours are { r, g, b, a }; for
-- VERTICAL "from" is the bottom, for HORIZONTAL the left.
local function SetGradient(texture, orientation, from, to)
	if CreateColor and pcall(texture.SetGradient, texture, orientation,
		CreateColor(unpack(from)), CreateColor(unpack(to))) then
		return
	end
	if texture.SetGradientAlpha then
		texture:SetGradientAlpha(orientation, from[1], from[2], from[3], from[4], to[1], to[2], to[3], to[4])
	else
		texture:SetGradient(orientation, from[1], from[2], from[3], to[1], to[2], to[3])
	end
end

local function CreateTint()
	tintFrame = CreateFrame("Frame", "CinematicTint", UIParent)
	tintFrame:SetAllPoints(UIParent)
	tintFrame:SetFrameStrata("BACKGROUND")
	tintFrame:SetFrameLevel(0)
	tintFrame:EnableMouse(false)

	tintTexture = tintFrame:CreateTexture(nil, "BACKGROUND")
	tintTexture:SetAllPoints()
	tintTexture:SetColorTexture(1, 1, 1, 1)

	vignetteEdges = {}
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do
		local edge = tintFrame:CreateTexture(nil, "ARTWORK")
		edge:SetColorTexture(1, 1, 1, 1)
		edge:SetBlendMode("BLEND")
		vignetteEdges[side] = edge
	end
	vignetteEdges.top:SetPoint("TOPLEFT")
	vignetteEdges.top:SetPoint("TOPRIGHT")
	vignetteEdges.bottom:SetPoint("BOTTOMLEFT")
	vignetteEdges.bottom:SetPoint("BOTTOMRIGHT")
	vignetteEdges.left:SetPoint("TOPLEFT")
	vignetteEdges.left:SetPoint("BOTTOMLEFT")
	vignetteEdges.right:SetPoint("TOPRIGHT")
	vignetteEdges.right:SetPoint("BOTTOMRIGHT")
	tintFrame:Hide()
	-- Keep the letterbox bars above the tint so a glow doesn't tint them.
	local letterbox = ns.GetLetterbox()
	if letterbox then
		letterbox:SetFrameLevel(tintFrame:GetFrameLevel() + 1)
	end
end

local function ApplyTint(level)
	local preset = TINT_BY_KEY[db.tintPreset] or TINT_BY_KEY.none
	local isZone = preset.key == "zone" or preset.key == "zonetime"
	local strength = (isZone and zoneStrength or db.tintStrength) * level

	if preset.mode and strength > 0 then
		local function grade(color)
			if preset.mode == "ADD" then
				return { color[1] * strength, color[2] * strength, color[3] * strength, 1 }
			end
			-- Multiply: blend from white (no change) toward the tint colour.
			return {
				1 - (1 - color[1]) * strength,
				1 - (1 - color[2]) * strength,
				1 - (1 - color[3]) * strength, 1,
			}
		end
		local top, bottom
		if preset.key == "custom" then
			top = { db.tintCustomR, db.tintCustomG, db.tintCustomB }
			bottom = top
		elseif preset.key == "timeofday" then
			top = TimeOfDayColor()
			bottom = top
		elseif preset.key == "zone" then
			top = zoneColor
			bottom = top
		elseif preset.key == "zonetime" then
			local time = TimeOfDayColor()
			top = { zoneColor[1] * time[1], zoneColor[2] * time[2], zoneColor[3] * time[3] }
			bottom = top
		else
			top = preset.top or preset.color
			bottom = preset.bottom or preset.color
		end
		tintTexture:SetBlendMode(preset.mode)
		SetGradient(tintTexture, "VERTICAL", grade(bottom), grade(top))
		tintTexture:Show()
	else
		tintTexture:Hide()
	end

	local vignetteAlpha = db.vignette and db.vignetteStrength * level or 0
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	for side, edge in pairs(vignetteEdges) do
		edge:SetShown(vignetteAlpha > 0)
	end
	if vignetteAlpha > 0 then
		local dark, clear = { 0, 0, 0, vignetteAlpha }, { 0, 0, 0, 0 }
		vignetteEdges.top:SetHeight(height * VIGNETTE_SIZE)
		vignetteEdges.bottom:SetHeight(height * VIGNETTE_SIZE)
		vignetteEdges.left:SetWidth(width * VIGNETTE_SIZE)
		vignetteEdges.right:SetWidth(width * VIGNETTE_SIZE)
		SetGradient(vignetteEdges.top, "VERTICAL", clear, dark)
		SetGradient(vignetteEdges.bottom, "VERTICAL", dark, clear)
		SetGradient(vignetteEdges.left, "HORIZONTAL", dark, clear)
		SetGradient(vignetteEdges.right, "HORIZONTAL", clear, dark)
	end

	tintFrame:SetShown(level > 0)
end

local function TintWanted(cinematic)
	local stillSince = ns.GetStillSince()
	if Previewing() then
		return true
	end
	if not cinematic then
		return false
	end
	if db.tintWhen == "flight" then
		return UnitOnTaxi("player")
	elseif db.tintWhen == "idle" then
		return not UnitOnTaxi("player") and stillSince ~= nil
			and GetTime() - stillSince >= db.idleOrbitDelay
	end
	return true
end

local timeOfDayRefreshedAt = 0

local function UpdateTint(cinematic, elapsed)
	local target = TintWanted(cinematic) and 1 or 0
	-- The time-of-day colour drifts with the clock, so refresh it now and then.
	local now = GetTime()
	local preset = db.tintPreset
	local usesTime = preset == "timeofday" or preset == "zonetime"
	if usesTime and tintLevel > 0 and now - timeOfDayRefreshedAt >= TIME_OF_DAY_REFRESH then
		timeOfDayRefreshedAt = now
		tintDirty = true
	end
	-- Zone moods blend across borders; while hidden the colour just jumps.
	if preset == "zone" or preset == "zonetime" then
		if BlendZoneColor(elapsed, tintLevel == 0) then
			tintDirty = true
		end
	end
	if tintLevel == target and not tintDirty then
		return
	end
	tintDirty = false
	local duration = target > tintLevel and db.fadeOutTime or db.fadeInTime
	tintLevel = Previewing() and target or Approach(tintLevel, target, elapsed, duration)
	ApplyTint(tintLevel)
end

-- Entry points for Core.lua and the options page
function ns.CreateTint()
	db = ns.GetDB()
	CreateTint()
end

ns.UpdateTint = UpdateTint
ns.RefreshTint = function() tintDirty = true end
-- While the Look page is open, show the tint at full strength.
ns.SetTintPreview = function(on)
	tintPreview = on
	tintDirty = true
	if not on then
		-- Leaving the page: go back to the real clock. (The page is also hidden
		-- once while the options load, before saved settings exist.)
		db = db or ns.GetDB()
		if db then
			db.tintPreviewHour = -1
		end
	end
end
-- Time-of-day phases for the options page and menu: { name, color, own, hour }.
-- (The options page builds before saved settings exist; built-in colours then.)
ns.GetTimePhases = function()
	db = db or ns.GetDB()
	local list = {}
	for _, phase in ipairs(TIME_PHASES) do
		list[#list + 1] = {
			name = phase[1], color = PhaseColor(phase[1]), hour = phase[2],
			own = db ~= nil and db.timePhaseColors ~= nil and db.timePhaseColors[phase[1]] ~= nil,
			strength = PhaseStrength(phase[1]),
			ownStrength = db ~= nil and db.timePhaseStrength ~= nil and db.timePhaseStrength[phase[1]] ~= nil,
		}
	end
	return list
end
-- Your own colour for a phase ({ r, g, b }), or nil for the built-in one.
ns.SetTimePhaseColor = function(name, color)
	db = db or ns.GetDB()
	db.timePhaseColors[name] = color
	tintDirty = true
end
-- Your own strength for a phase (0-1), or nil for its default.
ns.SetTimePhaseStrength = function(name, strength)
	db = db or ns.GetDB()
	if strength and math.abs(strength - (DEFAULT_PHASE_STRENGTH[name] or 1)) < 0.001 then
		strength = nil -- same as the default: nothing of your own to keep
	end
	db.timePhaseStrength[name] = strength
	tintDirty = true
end
-- Quick preview from the minimap menu: the tint at this hour for a few
-- seconds, shown even outside cinematic mode.
ns.PreviewTintHour = function(hour)
	menuPreviewHour, menuPreviewUntil = hour, GetTime() + MENU_PREVIEW_TIME
	tintDirty = true
	C_Timer.After(MENU_PREVIEW_TIME + 0.1, function() tintDirty = true end)
end
-- Phase name at a given hour, for labelling the preview choices.
ns.GetTimeOfDayPhaseAt = function(hour)
	local minutes = hour * 60
	for i = 1, #TIME_OF_DAY - 1 do
		local from, to = TIME_OF_DAY[i], TIME_OF_DAY[i + 1]
		if minutes >= from[1] and minutes < to[1] then
			local t = (minutes - from[1]) / (to[1] - from[1])
			return (t < 0.5 and from or to)[3]
		end
	end
	return TIME_OF_DAY[1][3]
end
ns.TINT_PRESETS = TINT_PRESETS

-- Time-of-day title: a line such as "Dusk" under the game's own zone name
-- when you log in or reload. It's a child of the zone text frame, so it fades
-- in and out with it, and is cleared once the zone text hides.
local TIME_TITLES = {
	{ 5, "Dawn" }, { 8, "Morning" }, { 12, "Midday" }, { 14, "Afternoon" },
	{ 17, "Evening" }, { 19, "Dusk" }, { 21, "Night" },
}
local timeTitle

local function TimeTitleAt(hour)
	local title = "Night" -- before dawn
	for _, entry in ipairs(TIME_TITLES) do
		if hour >= entry[1] then
			title = entry[2]
		end
	end
	return title
end

-- The zone title's lines, top to bottom: zone name, PvP status ("Alliance
-- Territory"), arena/sanctuary note, subzone. They don't all appear at once.
local ZONE_LINES = { "ZoneTextString", "PVPInfoTextString", "PVPArenaTextString", "SubZoneTextString" }

-- Below the lowest zone line on screen, centred, in the zone name's colour.
-- Run every frame while the zone title shows, as its lines arrive and recolour.
local function PlaceTimeTitle()
	local lowest, lowestScale
	for _, name in ipairs(ZONE_LINES) do
		local line = _G[name]
		if line and line:IsVisible() and (line:GetText() or "") ~= "" then
			local bottom = line:GetBottom()
			if bottom and (not lowest or bottom * line:GetEffectiveScale() < lowest * lowestScale) then
				lowest, lowestScale = bottom, line:GetEffectiveScale()
			end
		end
	end
	if not lowest then
		return
	end
	if not timeTitle.sized then
		local font, size, flags = (SubZoneTextString or ZoneTextString):GetFont()
		if font then
			timeTitle.text:SetFont(font, math.floor(size * 0.75 + 0.5), flags)
			timeTitle.sized = true
		end
	end
	timeTitle.text:SetTextColor(ZoneTextString:GetTextColor())
	-- Centred on the screen, a little below the lowest line (converted to this
	-- text's own scale).
	local y = lowest * lowestScale / timeTitle.text:GetEffectiveScale() - 12
	if timeTitle.y ~= y then
		timeTitle.y = y
		timeTitle.text:ClearAllPoints()
		timeTitle.text:SetPoint("TOP", UIParent, "BOTTOM", 0, y)
	end
end

function ns.ShowTimeOfDayTitle()
	if not (ZoneTextFrame and ZoneTextString) then
		return
	end
	if not timeTitle then
		timeTitle = CreateFrame("Frame", nil, ZoneTextFrame)
		timeTitle:SetAllPoints(UIParent)
		timeTitle.text = timeTitle:CreateFontString(nil, "OVERLAY")
		-- A font before any text (SetText errors without one); PlaceTimeTitle
		-- then sizes it to match the zone text.
		timeTitle.text:SetFontObject(_G.SubZoneTextFont or GameFontNormalLarge)
		timeTitle.text:SetShadowOffset(1, -1)
		ZoneTextFrame:HookScript("OnHide", function() timeTitle.text:SetText("") end)
		-- Only runs while the zone title shows (this frame is its child).
		timeTitle:SetScript("OnUpdate", function()
			if (timeTitle.text:GetText() or "") ~= "" then
				PlaceTimeTitle()
			end
		end)
	end
	db = db or ns.GetDB()
	local _, _, hour = TimeOfDayColor()
	PlaceTimeTitle()
	timeTitle.text:SetText(TimeTitleAt(hour))
	-- If the zone name never showed, don't leave the title waiting for the
	-- next zone change.
	C_Timer.After(10, function()
		if not ZoneTextFrame:IsShown() then
			timeTitle.text:SetText("")
		end
	end)
end
-- For the options page: the zone (default: the one you're in), its tint's
-- label, whether that's your override, and the colour.
ns.GetZoneTintInfo = function(zoneName)
	db = db or ns.GetDB()
	zoneName = zoneName or GetRealZoneText() or ""
	local color, label, isOverride = ZoneTint(zoneName)
	return zoneName, label, isOverride, color
end
-- Built-in moods for the override menu: { key, label, color } in order.
ns.GetZoneMoods = function()
	local list = {}
	for _, key in ipairs(ZONE_MOOD_ORDER) do
		list[#list + 1] = { key = key, label = ZONE_MOODS[key][2], color = ZONE_MOODS[key][1] }
	end
	return list
end
-- Sets a zone's override: "none", a mood key, { r, g, b }, or nil to go back
-- to the built-in mood.
ns.SetZoneTint = function(zoneName, value)
	db = db or ns.GetDB()
	db.zoneTints[zoneName] = value
	tintDirty = true
end
-- A zone's strength for the Zone presets (0-1), or nil to use the main
-- Strength. GetZoneTintStrength also returns whether the zone has its own.
ns.SetZoneTintStrength = function(zoneName, value)
	db = db or ns.GetDB()
	db.zoneTintStrength[zoneName] = value
	tintDirty = true
end
ns.GetZoneTintStrength = function(zoneName)
	db = db or ns.GetDB()
	return ZoneStrength(zoneName)
end
-- The area you're in (or nil), its tint's label, whether that's the area's own,
-- the colour, its strength, its default strength, and whether it has its own.
ns.GetAreaTintInfo = function()
	db = db or ns.GetDB()
	local area = CurrentArea()
	if not area then
		return nil
	end
	local color, label, own = HereTint()
	local strength, default, ownStrength = HereStrength()
	return area, own and label or "same as the zone", own, color, strength, default, ownStrength
end
-- For the options page: the current time-of-day phase name and clock time.
ns.GetTimeOfDayInfo = function()
	db = db or ns.GetDB()
	local _, phase, hour, minute = TimeOfDayColor()
	return phase, hour, minute
end

-- When the time of day changes during play (Evening to Dusk, say), its name
-- fades in on its own where the zone title appears, then fades out.
local CHANGE_FADE_IN, CHANGE_HOLD, CHANGE_FADE_OUT = 1.5, 4, 2
local CHANGE_CHECK = 15 -- seconds between checks
-- A sound for each time of day (Wowhead sound IDs), played with its title.
-- Bells are your faction's city bell.
local TIME_SOUNDS = {
	Dawn = 8352,          -- Chicken
	Morning = 730,        -- HorseStand3
	Midday = "bell",
	Afternoon = 4420,
	Evening = 8353,       -- Frog
	Dusk = 3605,          -- OwlAggro
	Night = 1018,         -- WolfFidget2
}
local BELLS = { Alliance = 6594, Horde = 6595 } -- BellTollAlliance, BellTollHorde
local TIME_SOUND_LENGTH = 3      -- seconds before a time-of-day sound is faded out
local TIME_SOUND_FADE_MS = 1000  -- ...over this long (4 seconds in all)
local timeSoundHandle

local function PlayTimeSound(title)
	local sound = TIME_SOUNDS[title]
	if sound == "bell" then
		sound = BELLS[UnitFactionGroup("player") or ""] or BELLS.Alliance
	end
	if sound then
		-- Some sounds loop (they'd play forever): every one is faded out as the
		-- title finishes, which short sounds have long since done anyway.
		if timeSoundHandle then
			StopSound(timeSoundHandle)
		end
		local ok, willPlay, handle = pcall(PlaySound, sound, "SFX")
		if ok and willPlay and handle then
			timeSoundHandle = handle
			C_Timer.After(TIME_SOUND_LENGTH, function()
				if timeSoundHandle == handle then
					StopSound(handle, TIME_SOUND_FADE_MS)
					timeSoundHandle = nil
				end
			end)
		end
	end
end
local changeTitle, lastTitle

local function ShowChangeTitle(text)
	if not changeTitle then
		changeTitle = CreateFrame("Frame", nil, UIParent)
		changeTitle:SetSize(1, 1)
		changeTitle:SetFrameStrata("MEDIUM")
		changeTitle.text = changeTitle:CreateFontString(nil, "OVERLAY")
		changeTitle.text:SetFontObject(_G.ZoneTextFont or GameFontNormalHuge or GameFontNormalLarge)
		changeTitle.text:SetShadowOffset(1, -1)
		changeTitle.text:SetTextColor(1, 0.86, 0.6)
		changeTitle.text:SetPoint("CENTER")
		changeTitle:SetScript("OnUpdate", function(self, elapsed)
			self.t = self.t + elapsed
			local t, alpha = self.t, 0
			if t < CHANGE_FADE_IN then
				alpha = t / CHANGE_FADE_IN
			elseif t < CHANGE_FADE_IN + CHANGE_HOLD then
				alpha = 1
			elseif t < CHANGE_FADE_IN + CHANGE_HOLD + CHANGE_FADE_OUT then
				alpha = 1 - (t - CHANGE_FADE_IN - CHANGE_HOLD) / CHANGE_FADE_OUT
			else
				self:Hide()
			end
			self:SetAlpha(alpha)
		end)
	end
	-- Where the zone title sits (it keeps its place even while hidden).
	changeTitle:ClearAllPoints()
	if ZoneTextString and ZoneTextString:GetCenter() then
		changeTitle:SetPoint("CENTER", ZoneTextString, "CENTER")
	else
		changeTitle:SetPoint("CENTER", UIParent, "TOP", 0, -200)
	end
	changeTitle.text:SetText(text)
	changeTitle.t = 0
	changeTitle:SetAlpha(0)
	changeTitle:Show()
	if db and db.timeOfDaySound then
		PlayTimeSound(text)
	end
end

-- /cine timetest: show it now (the current time of day, or a given name).
function ns.TestTimeChangeTitle(text)
	db = db or ns.GetDB()
	ShowChangeTitle(text or TimeTitleAt((GetClockTime())))
end

C_Timer.NewTicker(CHANGE_CHECK, function()
	db = db or ns.GetDB()
	if not db then
		return
	end
	local hour = GetClockTime()
	local title = TimeTitleAt(hour)
	if lastTitle and title ~= lastTitle and db.timeOfDayChange and db.timeOfDayMessage
		and not InCombatLockdown() and not (ZoneTextFrame and ZoneTextFrame:IsShown()) then
		ShowChangeTitle(title)
	end
	lastTitle = title
end)
