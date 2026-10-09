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
	volcanic = { { 1, 0.8, 0.68 }, "Volcanic" },
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
	autumn = { { 1, 0.88, 0.76 }, "Autumn" },    -- rust and amber, red rock and turning leaves
	summer = { { 0.95, 0.97, 0.96 }, "Summer" }, -- clear and fresh, tames red ground, keeps blue skies
	fel = { { 0.84, 1, 0.76 }, "Fel" },          -- sickly bright green, demon-scorched land
	void = { { 0.84, 0.76, 0.96 }, "Void" },     -- deeper violet than twilight
}
-- Zones by area ID, so names match in any client language. IDs a client
-- doesn't have are skipped, so retail's zones sit here too. Matching is by
-- name, so zones that share one (the two Nagrands) share a mood.
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
	[44] = "summer", [38] = "summer", [267] = "summer",                -- Redridge Mountains, Loch Modan, Hillsbrad Foothills
	[130] = "gloomy",                                                  -- Silverpine Forest
	[45] = "savanna",                                                  -- Arathi Highlands
	[47] = "forest", [406] = "forest",                                 -- The Hinterlands, Stonetalon Mountains
	[4] = "dusty",                                                     -- Blasted Lands
	[148] = "moonlit", [493] = "twilight",                             -- Darkshore, Moonglade
	[357] = "swamp",                                                   -- Feralas
	[16] = "autumn",                                                   -- Azshara
	-- Retail: zones split or renamed since Classic
	[4709] = "savanna",                                                -- Southern Barrens
	[5339] = "swamp", [5287] = "swamp",                                -- Stranglethorn Vale, The Cape of Stranglethorn
	[4706] = "gloomy", [4714] = "forest",                              -- Ruins of Gilneas, Gilneas (worgen start)
	[616] = "forest",                                                  -- Mount Hyjal
	-- The Burning Crusade
	[3483] = "dusty", [3522] = "dusty",                                -- Hellfire Peninsula, Blade's Edge Mountains
	[3521] = "twilight", [3523] = "twilight",                          -- Zangarmarsh, Netherstorm
	[3519] = "autumn",                                                 -- Terokkar Forest
	[3518] = "summer",                                                 -- Nagrand (Outland; same name as Draenor's)
	[3520] = "moonlit",                                                -- Shadowmoon Valley (Outland; same name as Draenor's)
	[3703] = "hearth",                                                 -- Shattrath City
	[3433] = "gloomy",                                                 -- Ghostlands
	[4080] = "airy",                                                   -- Isle of Quel'Danas
	[3524] = "summer", [3525] = "dusty", [3557] = "twilight",          -- Azuremyst Isle, Bloodmyst Isle, The Exodar
	-- Wrath of the Lich King
	[3537] = "snow", [65] = "snow", [67] = "snow", [4197] = "snow",    -- Borean Tundra, Dragonblight, The Storm Peaks, Wintergrasp
	[210] = "moonlit",                                                 -- Icecrown
	[394] = "forest", [3711] = "swamp",                                -- Grizzly Hills, Sholazar Basin
	[66] = "gloomy",                                                   -- Zul'Drak
	[2817] = "twilight", [4395] = "twilight",                          -- Crystalsong Forest, Dalaran (Northrend)
	-- Cataclysm
	[5034] = "desert", [5733] = "volcanic",                            -- Uldum, Molten Front
	[5095] = "gloomy", [5389] = "gloomy",                              -- Tol Barad, Tol Barad Peninsula
	[4737] = "summer", [4720] = "swamp",                               -- Kezan, The Lost Isles
	-- Mists of Pandaria
	[5785] = "forest", [5805] = "golden",                              -- The Jade Forest, Valley of the Four Winds
	[6134] = "swamp", [6661] = "swamp",                                -- Krasarang Wilds, Isle of Giants
	[5841] = "snow", [5842] = "savanna",                               -- Kun-Lai Summit, Townlong Steppes
	[6138] = "sickly", [5840] = "hearth",                              -- Dread Wastes, Vale of Eternal Blossoms
	[6507] = "gloomy",                                                 -- Isle of Thunder
	[6757] = "summer", [5736] = "summer",                              -- Timeless Isle, The Wandering Isle
	-- Warlords of Draenor
	[6720] = "snow", [6721] = "dusty",                                 -- Frostfire Ridge, Gorgrond
	[6662] = "autumn", [6722] = "autumn",                              -- Talador, Spires of Arak
	[6719] = "moonlit", [6755] = "summer",                             -- Shadowmoon Valley (Draenor), Nagrand (Draenor)
	[6723] = "fel",                                                    -- Tanaan Jungle
	-- Legion
	[7334] = "autumn", [7558] = "forest",                              -- Azsuna, Val'sharah
	[7503] = "summer", [7541] = "gloomy",                              -- Highmountain, Stormheim
	[7637] = "twilight", [7502] = "twilight",                          -- Suramar, Dalaran (Broken Isles)
	[7543] = "fel",                                                    -- Broken Shore
	[8574] = "fel", [8899] = "fel", [8701] = "twilight",               -- Krokuun, Antoran Wastes, Eredath (Argus)
	-- Battle for Azeroth
	[8567] = "summer", [9042] = "summer", [8721] = "autumn",           -- Tiragarde Sound, Stormsong Valley, Drustvar
	[8499] = "swamp", [8500] = "swamp", [8501] = "desert",             -- Zuldazar, Nazmir, Vol'dun
	[10052] = "moonlit", [10290] = "dusty",                            -- Nazjatar, Mechagon
	-- Shadowlands
	[10534] = "airy", [11462] = "sickly",                              -- Bastion, Maldraxxus
	[11510] = "twilight", [10413] = "dusky",                           -- Ardenweald, Revendreth
	[11400] = "gloomy", [13570] = "gloomy",                            -- The Maw, Korthia
	[13536] = "airy",                                                  -- Zereth Mortis
	-- Dragonflight
	[13644] = "autumn", [13645] = "summer",                            -- The Waking Shores, Ohn'ahran Plains
	[13646] = "snow", [13647] = "airy",                                -- The Azure Span, Thaldraszus
	[14022] = "forge",                                                 -- Zaralek Cavern
	[14529] = "forest", [15105] = "forest",                            -- Emerald Dream, Amirdrassil
	-- The War Within
	[14717] = "summer", [14795] = "forge",                             -- Isle of Dorn, The Ringing Deeps
	[14838] = "golden", [14752] = "void",                              -- Hallowfall, Azj-Kahet
	[15347] = "forge", [16093] = "forge",                              -- Undermine (two IDs, one name)
	[10416] = "gloomy", [15336] = "void",                              -- Siren Isle, K'aresh
	-- Midnight
	[15968] = "golden", [15969] = "hearth",                            -- Eversong Woods, Silvermoon City
	[16215] = "airy",                                                  -- Isle of Quel'Danas (Midnight)
	[15947] = "forest",                                                -- Zul'Aman
	[15355] = "twilight",                                              -- Harandar
	[16648] = "void",                                                  -- Voidstorm
}
-- Mood order for the options page.
local ZONE_MOOD_ORDER = { "snow", "desert", "savanna", "swamp", "blight", "volcanic", "forest", "dusky", "forge", "hearth", "dusty",
	"sickly", "airy", "moonlit", "gloomy", "twilight", "golden", "autumn", "summer", "fel", "void" }
-- At a border the old mood fades out, there's a pause with no mood (the land
-- either side blends for a while, and snow under an ember tint looks red), then
-- the new mood fades in. The pause is longer in the air, where you see
-- further back over the old zone. Timings: db.zoneFadeTime, db.zoneGapTime and
-- db.zoneGapFlying (seconds).

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
-- Strength drift: two slow waves with unrelated periods, so it wanders rather
-- than pulses. Refreshed a few times a second; the steps are far too small to see.
local DRIFT_PERIOD_A, DRIFT_PERIOD_B = 170, 410 -- seconds
local DRIFT_REFRESH = 0.25 -- seconds between drift updates

-- Tint state. Declared before the functions that use it: a Lua local only
-- exists from its declaration on, so anything above would see a nil global.
local VIGNETTE_SIZE = 0.25 -- fraction of the screen each edge gradient covers
local tintFrame, tintTexture, vignetteEdges
local tintLevel = 0
local tintDirty = false
local tintPreview = false
local menuPreviewHour, menuPreviewUntil = -1, 0
local zoneMoodByName -- zone name -> mood key, built on first use
local zoneColor = { 1, 1, 1 } -- the zone colour shown now: zoneGoal, faded by zoneMix
local zoneGoal = { 1, 1, 1 } -- the mood being shown, or faded out or in
local zoneMix = 1 -- how much of zoneGoal shows (0: none)
local zonePhase -- nil when settled; "out", "gap" or "in" across a border
local zoneGapUntil = 0
local zoneStrength -- the Zone presets' strength shown now, blending toward the zone's own
local shownPreset -- the preset on screen; trails HerePreset() across a border
local presetFade = 1 -- dips to 0 and back to swap presets at a border
local PRESET_SWITCH_TIME = 1.5 -- seconds to fade out the old preset (and again to fade in the new)

-- Inn glow: indoors in an inn the outdoor mood (a gloomy marsh, a moonlit night)
-- partly lifts, and a soft hearth glow is added. Multiply can only darken, so
-- the glow is its own additive layer, brighter low down like firelight. The
-- glow takes on the zone's colour: cooler in the snow, greener in a swamp.
-- The glow's colour, scaled so its brightest part (red, at the bottom) adds
-- exactly the Glow amount setting.
local INN_GLOW_BOTTOM = { 1, 0.62, 0.23 }
local INN_GLOW_TOP = { 0.46, 0.27, 0.09 }
local INN_ZONE_WEIGHT = 2 -- how strongly the zone colours the glow (a power on its colour)
local INN_SOFTEN = 0.6    -- how much of the main tint lifts indoors in an inn
local INN_BLEND_TIME = 3  -- seconds to blend in or out at the door
local INN_CHECK = 0.5     -- seconds between indoor checks (there's no reliable event)
local innGlowTexture
local innLevel, innWanted, innCheckedAt = 0, false, 0

-- Weather: rain, snow and sandstorms grade the scene through their own
-- multiply layer, so they work with any preset (None included). Scaled by the
-- weather's intensity, off under a roof, and blended in and out as a storm
-- builds or you go indoors. Only on clients with C_Weather.
local WEATHER_TYPE = Enum and Enum.WeatherType or {}
local WEATHER_COLORS = {
	[WEATHER_TYPE.Rain or 1] = { 0.74, 0.79, 0.88 },      -- grey and cool, overcast
	[WEATHER_TYPE.Snow or 2] = { 0.86, 0.91, 1 },         -- pale blue, bright and cold
	[WEATHER_TYPE.Sandstorm or 3] = { 1, 0.82, 0.6 },     -- dusty orange haze
	[WEATHER_TYPE.Miscellaneous or 4] = { 0.86, 0.86, 0.9 }, -- a neutral grey haze
}
local WEATHER_BLEND_TIME = 8 -- seconds to blend as weather changes or at a door
local WEATHER_CHECK = 1      -- seconds between weather checks
local weatherTexture
local weatherColor = { 1, 1, 1 } -- the weather colour shown now, blending toward the current weather's
local weatherCheckedAt = 0
local weatherTarget = { 1, 1, 1 }

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

-- Per-zone presets: a zone or area can swap in a whole preset of its own
-- (Night in Duskwood, None in a city). The area's wins over the zone's; with
-- neither, your main preset. Also returns where it came from: "area", "zone" or nil.
local function HerePreset()
	local presets = db.zonePresets
	if presets then
		local area = CurrentArea()
		if area and presets[area] then
			return presets[area], "area"
		end
		local zone = presets[GetRealZoneText() or ""]
		if zone then
			return zone, "zone"
		end
	end
	return db.tintPreset
end

local function SameColor(a, b)
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function InTheAir()
	return UnitOnTaxi("player") or (IsFlying and IsFlying()) or false
end

-- Moves the shown zone colour and strength toward the zone's: a new mood
-- fades the old one out, pauses, then fades in. True while anything changed.
local function BlendZoneColor(elapsed, instant)
	local target = ZoneTargetColor()
	local targetStrength = (HereStrength())
	local before = { zoneColor[1], zoneColor[2], zoneColor[3], zoneStrength }
	if instant or not zoneStrength then
		zoneGoal = { target[1], target[2], target[3] }
		zoneMix, zonePhase, zoneStrength = 1, nil, targetStrength
	else
		if not SameColor(target, zoneGoal) then
			if zonePhase == nil or zonePhase == "in" then
				zonePhase = "out"
			end
		elseif zonePhase == "out" then
			zonePhase = "in" -- turned back before the old mood had gone
		end
		if zonePhase == "out" then
			if SameColor(zoneGoal, { 1, 1, 1 }) then
				zoneMix = 0 -- an untinted zone: nothing to fade out
			end
			zoneMix = Approach(zoneMix, 0, elapsed, db.zoneFadeTime)
			if zoneMix == 0 then
				zonePhase = "gap"
				zoneGapUntil = GetTime() + (InTheAir() and db.zoneGapFlying or db.zoneGapTime)
			end
		end
		if zonePhase == "gap" then
			-- Nothing shows, so take on the new mood (and any later one) as is.
			zoneGoal = { target[1], target[2], target[3] }
			zoneStrength = targetStrength
			if GetTime() >= zoneGapUntil then
				zonePhase = "in"
			end
		end
		if zonePhase == "in" then
			zoneMix = Approach(zoneMix, 1, elapsed, db.zoneFadeTime)
			if zoneMix == 1 then
				zonePhase = nil
			end
		end
		if zonePhase ~= "out" and zonePhase ~= "gap" then
			zoneStrength = Approach(zoneStrength, targetStrength, elapsed, db.zoneFadeTime)
		end
	end
	for c = 1, 3 do
		zoneColor[c] = 1 - (1 - zoneGoal[c]) * zoneMix
	end
	return zoneColor[1] ~= before[1] or zoneColor[2] ~= before[2] or zoneColor[3] ~= before[3]
		or zoneStrength ~= before[4]
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
-- The drift multiplier on tint strength: 1 +/- the drift amount, wandering
-- slowly. Off while previewing, so the Look page shows the strength you set.
local function DriftFactor()
	if not db.tintDrift or Previewing() then
		return 1
	end
	local now = GetTime()
	local wave = 0.6 * math.sin(now * 2 * math.pi / DRIFT_PERIOD_A)
		+ 0.4 * math.sin(now * 2 * math.pi / DRIFT_PERIOD_B + 1.3)
	return 1 + wave * (db.tintDriftAmount or 0)
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
	ns.AddOverlay(tintFrame)

	tintTexture = tintFrame:CreateTexture(nil, "BACKGROUND")
	tintTexture:SetAllPoints()
	tintTexture:SetColorTexture(1, 1, 1, 1)

	innGlowTexture = tintFrame:CreateTexture(nil, "BORDER")
	innGlowTexture:SetAllPoints()
	innGlowTexture:SetColorTexture(1, 1, 1, 1)
	innGlowTexture:SetBlendMode("ADD")
	innGlowTexture:Hide()

	weatherTexture = tintFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
	weatherTexture:SetAllPoints()
	weatherTexture:SetColorTexture(1, 1, 1, 1)
	weatherTexture:SetBlendMode("MOD")
	weatherTexture:Hide()

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
	local preset = TINT_BY_KEY[shownPreset] or TINT_BY_KEY.none
	local isZone = preset.key == "zone" or preset.key == "zonetime"
	local strength = math.min(1, (isZone and zoneStrength or db.tintStrength) * DriftFactor())
		* level * presetFade * (1 - innLevel * INN_SOFTEN)

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

	local glow = innLevel * level * (db.innGlowAmount or 0)
	if glow > 0 then
		-- The zone's colour with its brightest channel at 1, so it shifts the
		-- glow's hue without dimming it.
		local zone = HereTint()
		local peak = math.max(zone[1], zone[2], zone[3], 0.01)
		local bottom, top = { 0, 0, 0, 1 }, { 0, 0, 0, 1 }
		for c = 1, 3 do
			local shade = (zone[c] / peak) ^ INN_ZONE_WEIGHT * glow
			bottom[c], top[c] = INN_GLOW_BOTTOM[c] * shade, INN_GLOW_TOP[c] * shade
		end
		SetGradient(innGlowTexture, "VERTICAL", bottom, top)
		innGlowTexture:Show()
	else
		innGlowTexture:Hide()
	end

	local weather = { 1, 1, 1, 1 }
	for c = 1, 3 do
		weather[c] = 1 - (1 - weatherColor[c]) * level
	end
	if weather[1] < 1 or weather[2] < 1 or weather[3] < 1 then
		SetGradient(weatherTexture, "VERTICAL", weather, weather)
		weatherTexture:Show()
	else
		weatherTexture:Hide()
	end

	local vignetteAlpha = db.vignette and db.vignetteStrength * level or 0
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	for _, edge in pairs(vignetteEdges) do
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

-- cinematic: already false outside the situations ticked for the tint (see Core).
local function TintWanted(cinematic)
	return cinematic or Previewing()
end

-- Death screen: while the death camera runs, the world goes dim and cold and a
-- heavy vignette closes in. Its own overlay, beside the tint and under the UI
-- (so the release button stays clear). Fades in slowly, clears quickly.
local DEATH_COLOR = { 0.6, 0.63, 0.75 } -- multiply: dimmer, drained toward grey-blue
local DEATH_VIGNETTE = 0.75             -- edge darkness at full strength
local DEATH_VIGNETTE_SIZE = 0.35        -- fraction of the screen each edge covers, at full
local DEATH_VIGNETTE_START = 0.1        -- ...and as it starts creeping in
local DEATH_FADE_IN, DEATH_FADE_OUT = 3, 1 -- seconds (the wash)
local DEATH_CREEP_TIME = 10             -- seconds for the vignette to creep in
local deathFrame, deathWash, deathEdges
local deathLevel, deathCreep = 0, 0

local function CreateDeathScreen()
	deathFrame = CreateFrame("Frame", nil, UIParent)
	deathFrame:SetAllPoints(UIParent)
	deathFrame:SetFrameStrata("BACKGROUND")
	deathFrame:SetFrameLevel(tintFrame:GetFrameLevel()) -- (under the letterbox, like the tint)
	deathFrame:EnableMouse(false)
	ns.AddOverlay(deathFrame)
	deathWash = deathFrame:CreateTexture(nil, "BACKGROUND")
	deathWash:SetAllPoints()
	deathWash:SetColorTexture(1, 1, 1, 1)
	deathWash:SetBlendMode("MOD")
	deathEdges = {}
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do
		local edge = deathFrame:CreateTexture(nil, "ARTWORK")
		edge:SetColorTexture(1, 1, 1, 1)
		edge:SetBlendMode("BLEND")
		deathEdges[side] = edge
	end
	deathEdges.top:SetPoint("TOPLEFT")
	deathEdges.top:SetPoint("TOPRIGHT")
	deathEdges.bottom:SetPoint("BOTTOMLEFT")
	deathEdges.bottom:SetPoint("BOTTOMRIGHT")
	deathEdges.left:SetPoint("TOPLEFT")
	deathEdges.left:SetPoint("BOTTOMLEFT")
	deathEdges.right:SetPoint("TOPRIGHT")
	deathEdges.right:SetPoint("BOTTOMRIGHT")
	deathFrame:Hide()
end

-- level: the wash; creep: the vignette, which darkens and closes in slowly
-- (eased, so it starts gently and settles).
local function ApplyDeathScreen(level, creep)
	local s = level * db.deathScreenStrength
	local c = creep * creep * (3 - 2 * creep)
	local v = c * db.deathScreenStrength
	local size = DEATH_VIGNETTE_START + (DEATH_VIGNETTE_SIZE - DEATH_VIGNETTE_START) * c
	local wash = { 1 - (1 - DEATH_COLOR[1]) * s, 1 - (1 - DEATH_COLOR[2]) * s, 1 - (1 - DEATH_COLOR[3]) * s, 1 }
	SetGradient(deathWash, "VERTICAL", wash, wash)
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local dark, clear = { 0, 0, 0, DEATH_VIGNETTE * v }, { 0, 0, 0, 0 }
	deathEdges.top:SetHeight(height * size)
	deathEdges.bottom:SetHeight(height * size)
	deathEdges.left:SetWidth(width * size)
	deathEdges.right:SetWidth(width * size)
	SetGradient(deathEdges.top, "VERTICAL", clear, dark)
	SetGradient(deathEdges.bottom, "VERTICAL", dark, clear)
	SetGradient(deathEdges.left, "HORIZONTAL", dark, clear)
	SetGradient(deathEdges.right, "HORIZONTAL", clear, dark)
	deathFrame:SetShown(level > 0 or creep > 0)
end

local function UpdateDeathScreen(elapsed)
	if not deathFrame then
		return
	end
	local want = db.enabled and db.deathScreen and ns.IsDeathCinematic and ns.IsDeathCinematic()
	local target = want and 1 or 0
	if deathLevel ~= target or deathCreep ~= target then
		deathLevel = Approach(deathLevel, target, elapsed, target > deathLevel and DEATH_FADE_IN or DEATH_FADE_OUT)
		deathCreep = Approach(deathCreep, target, elapsed, target > deathCreep and DEATH_CREEP_TIME or DEATH_FADE_OUT)
		ApplyDeathScreen(deathLevel, deathCreep)
	end
end

-- Indoors in an inn: resting outside a capital, under a roof. (The rested area
-- often spills out the door; the roof check keeps the street outside dark.)
local function InInn()
	if not db.innGlow or ns.GetPlaceType() ~= "inn" then
		return false
	end
	local ok, indoors = pcall(IsIndoors)
	return ok and indoors == true
end

-- Moves the inn glow toward in or out. True while it changed.
local function UpdateInnGlow(elapsed)
	local now = GetTime()
	if now - innCheckedAt >= INN_CHECK then
		innCheckedAt = now
		innWanted = InInn()
	end
	local target = innWanted and 1 or 0
	if innLevel == target then
		return false
	end
	-- While the tint is hidden, just jump.
	innLevel = tintLevel == 0 and target or Approach(innLevel, target, elapsed, INN_BLEND_TIME)
	return true
end

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

-- The current weather's type and intensity (0-1), or nil if the client
-- doesn't say. (In clear weather the client gives { type = 0, intensity = 0 }.)
local function CurrentWeather()
	if not (C_Weather and C_Weather.GetCurrentWeather) then
		return nil
	end
	local ok, weather = pcall(C_Weather.GetCurrentWeather)
	if not ok or type(weather) ~= "table" or IsSecret(weather) then
		return nil
	end
	local kind, intensity = weather.type, weather.intensity
	if IsSecret(kind) or IsSecret(intensity) or type(kind) ~= "number" or type(intensity) ~= "number" then
		return nil
	end
	return kind, math.max(0, math.min(1, intensity))
end

-- The weather colour to show here: no change with the option off, indoors,
-- or in clear or unknown weather.
local function WeatherTargetColor()
	local kind, intensity
	if db.weatherTint then
		local ok, indoors = pcall(IsIndoors)
		if not (ok and indoors) then
			kind, intensity = CurrentWeather()
		end
	end
	local color = kind and WEATHER_COLORS[kind]
	local amount = color and intensity * (db.weatherTintStrength or 0) or 0
	local target = { 1, 1, 1 }
	for c = 1, 3 do
		target[c] = color and 1 - (1 - color[c]) * amount or 1
	end
	return target
end

-- Moves the shown weather colour toward the weather's. True while it changed.
local function UpdateWeather(elapsed)
	local now = GetTime()
	if now - weatherCheckedAt >= WEATHER_CHECK then
		weatherCheckedAt = now
		weatherTarget = WeatherTargetColor()
	end
	local changed = false
	for c = 1, 3 do
		if weatherColor[c] ~= weatherTarget[c] then
			-- While the tint is hidden, just jump.
			weatherColor[c] = tintLevel == 0 and weatherTarget[c]
				or Approach(weatherColor[c], weatherTarget[c], elapsed, WEATHER_BLEND_TIME)
			changed = true
		end
	end
	return changed
end

local timeOfDayRefreshedAt = 0
local driftRefreshedAt = 0

-- When a zone's own preset takes over at a border, the old preset fades out
-- and the new one fades in. While the tint is hidden or previewed it just
-- swaps. True while anything changed.
local function UpdatePresetSwap(elapsed)
	local want = HerePreset()
	if want ~= shownPreset then
		if tintLevel == 0 or Previewing() or not shownPreset then
			shownPreset, presetFade = want, 1
		else
			if shownPreset == "none" then
				presetFade = 0 -- nothing to fade out
			end
			presetFade = Approach(presetFade, 0, elapsed, PRESET_SWITCH_TIME)
			if presetFade > 0 then
				return true
			end
			shownPreset = want
		end
		BlendZoneColor(0, true) -- a Zone preset starts at this zone's colour
		return true
	elseif presetFade < 1 then
		presetFade = Approach(presetFade, 1, elapsed, PRESET_SWITCH_TIME)
		return true
	end
	return false
end

local function UpdateTint(cinematic, elapsed)
	UpdateDeathScreen(elapsed)
	local target = TintWanted(cinematic) and 1 or 0
	if UpdatePresetSwap(elapsed) then
		tintDirty = true
	end
	if UpdateInnGlow(elapsed) then
		tintDirty = true
	end
	if UpdateWeather(elapsed) then
		tintDirty = true
	end
	-- The time-of-day colour drifts with the clock, so refresh it now and then.
	local now = GetTime()
	local preset = shownPreset
	local usesTime = preset == "timeofday" or preset == "zonetime"
	if usesTime and tintLevel > 0 and now - timeOfDayRefreshedAt >= TIME_OF_DAY_REFRESH then
		timeOfDayRefreshedAt = now
		tintDirty = true
	end
	if db.tintDrift and tintLevel > 0 and now - driftRefreshedAt >= DRIFT_REFRESH then
		driftRefreshedAt = now
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
	CreateDeathScreen()
end

ns.UpdateTint = UpdateTint
ns.RefreshTint = function()
	tintDirty = true
	innCheckedAt = 0 -- pick up an inn glow setting change right away
	weatherCheckedAt = 0 -- ...and a weather one
end
-- For /cine debug weather: what the client reports (unclamped), whether you're
-- indoors, and the colour aimed for and shown.
ns.GetWeatherDebug = function()
	db = db or ns.GetDB()
	local info = { api = C_Weather ~= nil and C_Weather.GetCurrentWeather ~= nil }
	if info.api then
		local ok, weather = pcall(C_Weather.GetCurrentWeather)
		if not ok then
			info.error = true
		elseif type(weather) == "table" and not IsSecret(weather) then
			info.kind, info.intensity = weather.type, weather.intensity
			info.secret = IsSecret(info.kind) or IsSecret(info.intensity)
		end
	end
	for name, value in pairs(WEATHER_TYPE) do
		if value == info.kind then
			info.kindName = name
		end
	end
	local ok, indoors = pcall(IsIndoors)
	info.indoors = ok and indoors
	info.target, info.shown = weatherTarget, weatherColor
	return info
end
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
	if not area or not db then -- (no saved settings yet while the options page builds)
		return nil
	end
	local color, label, own = HereTint()
	local strength, default, ownStrength = HereStrength()
	return area, own and label or "same as the zone", own, color, strength, default, ownStrength
end
-- The preset where you're standing (a zone's or area's own, else the main
-- one), and where it came from: "area", "zone" or nil.
ns.GetTintPresetHere = function()
	db = db or ns.GetDB()
	if not db then
		return nil -- (the options page builds before saved settings exist)
	end
	return HerePreset()
end
-- A zone's or area's own preset (a preset key), or nil to use the main one.
ns.SetZonePreset = function(name, preset)
	db = db or ns.GetDB()
	db.zonePresets[name] = preset
	tintDirty = true
end
ns.GetZonePreset = function(name)
	db = db or ns.GetDB()
	return db and db.zonePresets and db.zonePresets[name]
end
ns.GetTintPresetLabel = function(key)
	return TINT_BY_KEY[key] and TINT_BY_KEY[key].label or key
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
		ns.AddOverlay(changeTitle)
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
	if db and db.timeOfDayMessage then
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
	if lastTitle and title ~= lastTitle and db.timeOfDayMessage
		and not InCombatLockdown() and not (ZoneTextFrame and ZoneTextFrame:IsShown()) then
		ShowChangeTitle(title)
	end
	lastTitle = title
end)
