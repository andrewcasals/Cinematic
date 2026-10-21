-- Profile parts: each slot's templates (ProfileSlots.lua), that the built-in
-- profiles (Profiles.lua) are put together from. ns.PROFILE_PARTS[slot][name]
-- = { apply = function(set) }: set(key, value) changes the defaults, and a
-- list (a Standard Frames column...) is given just the rows it changes, so
-- two parts can each change their own rows of one. A part changes only its
-- own slot's settings (/cine debug slots checks), and in a list only its own
-- rows: a Standard Frames column's action bar rows are the Action bars
-- slot's, so Rows() splits a column between the two parts. "standard" is a
-- slot's part for a profile that names none. A part with client =
-- "forever" or "retail" is only for a profile on that client.

local _, ns = ...

-- Switches cameras off: an event's camera to none, or (for the ones no
-- event starts) its row of the Camera Modes page's "Turn off in" grid.
local EVENT_CAMS = { flight = true, idle = true, cozy = true, tele = true, vista = true, fish = true,
	quest = true }
local function CamsOff(set, cams)
	local off = {}
	for _, cam in ipairs(cams) do off[cam] = true end
	for _, event in ipairs(ns.EVENTS or {}) do
		local cam = event.camera == "afk" and "idle" or event.camera
		if off[cam] then
			set("event" .. event.key .. "Camera", "none")
		end
	end
	for _, cam in ipairs(cams) do
		if not EVENT_CAMS[cam] then
			for _, where in ipairs(ns.CAMERA_OFF_WHERE) do
				if not (ns.CAMERA_OFF_NEVER[cam] or {})[where] then
					set(cam .. "OffIn" .. where, true)
				end
			end
		end
	end
end

-- A Standard Frames column as a list: every row given true (in on) or false.
local STANDARD_ROWS = {
	"player", "prd", "prdpower", "target", "tot", "focus", "party", "raidplayers", "raidpets", "raidmanager", "minimap", "quests",
	"buffs", "swing", "cooldowns", "mainbar", "art",
	"bottomleft", "bottomright", "right1", "right2", "bar6", "bar7", "bar8", "pet", "stance", "totems",
	"micro", "bags", "xp",
}
local function Column(on)
	local list = {}
	for _, key in ipairs(STANDARD_ROWS) do list[key] = false end
	for _, key in ipairs(on) do list[key] = true end
	return list
end

-- The minimap's rows (its header, buttons, zone name and clock), all off.
local MINIMAP_ROWS = { "minimap", "minimapheader", "minimaptracking", "minimapcalendar", "minimapzone", "minimapclock" }
local function Except(rows)
	local list = {}
	for _, key in ipairs(rows) do list[key] = false end
	return list
end

-- Just a column's action bar rows (bars true), or just the rest.
local function Rows(list, bars)
	local result = {}
	for row, value in pairs(list) do
		if ns.IsBarRow(row) == bars then result[row] = value end
	end
	return result
end

-- Each event that can start music, starting it.
local MUSIC_EVENTS = { "AFK", "Still", "Chair", "Kneel", "Sleep", "Dance", "Weapon", "Campfire",
	"SitButton", "Fishing", "Hearth", "Teleport", "Logout", "Quest" }

-- The Immersive (CDM) profile's In combat and Tar Enemy columns.
local CDM_COMBAT = { "player", "prd", "prdpower", "target", "tot", "focus", "party", "raidplayers", "raidpets",
	"buffs", "swing", "cooldowns", "pet", "stance", "totems" }
local CDM_ENEMY = { "player", "prd", "prdpower", "target", "tot", "focus", "buffs", "cooldowns", "pet",
	"stance", "totems" }

-- The Pure Cinema profile's columns: fights bring up only your target and its
-- target (and the cast bar): no portrait, bars, buffs, minimap or swing timer.
-- (Rows not listed keep the defaults.)
local PURE_COMBAT = { tot = true, castbar = true, prd = false, prdpower = false, party = false, raidplayers = false,
	raidpets = false, minimap = false, buffs = false, swing = false, mainbar = false, art = false, bottomleft = false,
	bottomright = false, pet = false, stance = false, totems = false, micro = false, bags = false, xp = false,
	focus = false }
local PURE_ENEMY = { target = true, tot = true, player = false, prd = false, prdpower = false, party = false,
	raidplayers = false, raidpets = false, focus = false, buffs = false, mainbar = false, art = false,
	bottomleft = false, bottomright = false, pet = false, stance = false, totems = false, micro = false,
	bags = false, xp = false }
-- Nor in dungeons, scenarios and raids (the Instances column starts with the
-- party and raid frames ticked): every row off there too.
local function PureInstances()
	local list = {}
	for _, row in ipairs(ns.COMBAT_SHOW) do list[row.key] = false end
	return list
end

-- Every UI manager part: In combat rows stay for the Calm Timer, and the
-- player frame and personal resource display stay up until full (both
-- already on by default).
local function FramesBase(set)
	set("combatShowCalm", true)
	set("portraitWhenNotFull", true)
	set("prdWhenNotFull", true)
end

-- Nameplates: group members' pets, and the Grouped column for friendly
-- players and minions, don't stay up.
local function FewerGroupPlates(set)
	set("plateAlwaysGroupMinions", false)
	set("plateGroupFriends", false)
	set("plateGroupFriendlyMinions", false)
end

-- Chat doesn't peek for NPC speech (guards, vendors, ambient chatter).
local function NoNpcChat(set)
	set("chatPeekTypes", { npc = false })
end

ns.PROFILE_PARTS = {
	layout = {},
	frames = {
		standard = { apply = FramesBase },
		-- No minimap in fights (its header, buttons, zone name and clock
		-- neither); the micro menu, bags and XP bar do come up.
		immersive = { apply = function(set)
			FramesBase(set)
			FewerGroupPlates(set)
			set("combatShow", Except(MINIMAP_ROWS))
		end },
		-- Immersive's, with fights and an enemy targeted bringing up your
		-- frames, buffs and swing timer, but no minimap or quests.
		cdm = { apply = function(set)
			FramesBase(set)
			FewerGroupPlates(set)
			set("combatShow", Rows(Column(CDM_COMBAT), false))
			set("enemyShow", Rows(Column(CDM_ENEMY), false))
		end },
		-- The normal UI: nothing fades.
		nofade = { apply = function(set)
			FramesBase(set)
			set("fadeUI", false)
		end },
		-- On only while you're out in the world on your own.
		solo = { apply = function(set)
			FramesBase(set)
			set("offInDungeons", true)
			set("offInRaids", true)
			set("offInPvP", true)
			set("offInParty", true)
			set("offInRaidGroup", true)
		end },
		-- As little as possible: buffs and the quest tracker don't pop up on
		-- their own, group members' nameplates aren't kept up, no cast bar out
		-- of fights, and fights bring up only your target and its target.
		pure = { apply = function(set)
			FramesBase(set)
			set("buffPeek", false)
			set("debuffPeek", false)
			set("questRevealOnAccept", false)
			set("questRevealOnProgress", false)
			set("plateAlwaysGroupMembers", false)
			set("plateAlwaysGroupMinions", false)
			set("cineShow", { castbar = false })
			set("combatShow", Rows(PURE_COMBAT, false))
			set("enemyShow", Rows(PURE_ENEMY, false))
			set("friendlyShow", { target = true, tot = true })
			set("instanceShow", Rows(PureInstances(), false))
			-- No quest timer box.
			set("questTimerShow", false)
		end },
	},
	bars = {
		-- The Cooldown Manager in place of action bars 1 to 3, the micro menu
		-- and bags and the XP bar in fights and with an enemy targeted; after
		-- a fight it stays up until its cooldowns are ready (within the Calm Timer).
		cdm = { apply = function(set)
			set("combatShow", Rows(Column(CDM_COMBAT), true))
			set("enemyShow", Rows(Column(CDM_ENEMY), true))
			set("cooldownWhileRecharging", true)
		end },
		-- No action bars, micro menu, bags or XP bar in fights, with an enemy
		-- targeted or in instances.
		pure = { apply = function(set)
			set("combatShow", Rows(PURE_COMBAT, true))
			set("enemyShow", Rows(PURE_ENEMY, true))
			set("instanceShow", Rows(PureInstances(), true))
		end },
	},
	camera = {
		-- Auto-walking and auto-running can start music.
		immersive = { apply = function(set)
			set("musicCamWalk", true)
			set("musicCamRun", true)
		end },
		-- Just flights (and fly-bys), AFK, and your Hearthstone and teleports.
		lite = { apply = function(set)
			CamsOff(set, { "cozy", "vista", "fish", "walk", "run", "death", "quest" })
		end },
		-- Every camera brings CineMode on (Camera Triggers page's CineMode
		-- column), standing still starts the AFK camera, every camera can
		-- start music, and no death screen.
		cinemode = { apply = function(set)
			for _, event in ipairs(ns.EVENTS or {}) do
				if ns.DEFAULTS["event" .. event.key .. "Cine"] ~= nil then
					set("event" .. event.key .. "Cine", true)
				end
			end
			set("walkCine", true)
			set("runCine", true)
			set("deathCine", true)
			set("deathScreen", false)
			set("eventStillCamera", "afk")
			for _, event in ipairs(MUSIC_EVENTS) do set("event" .. event .. "Music", true) end
			set("musicCamWalk", true)
			set("musicCamRun", true)
		end },
		-- Standing still starts the AFK camera and every event's camera can
		-- start music; the cameras don't wait for things to calm down after a
		-- fight, auto-run carries on in cities and instances (as RP walk always
		-- does), and the death camera runs in instances too.
		pure = { apply = function(set)
			set("eventStillCamera", "afk")
			for _, event in ipairs(MUSIC_EVENTS) do set("event" .. event .. "Music", true) end
			for _, cam in ipairs({ "walk", "run", "tele", "quest" }) do
				set(cam .. "CalmWait", false)
			end
			set("runOffInCities", false)
			set("runOffInInstances", false)
			set("deathOffInInstances", false)
		end },
	},
	vfx = {
		-- No letterbox (the other effects show over the normal UI).
		noletterbox = { apply = function(set)
			set("letterbox", false)
		end },
		-- The effects just for the camera modes (Visual Effects page's
		-- "Outside camera modes" column); no soft edges.
		cameras = { apply = function(set)
			for _, effect in ipairs(ns.EFFECT_GRID) do
				set(effect .. "OnlyInCameras", true)
			end
			set("depthOfField", false)
		end },
		-- Fights don't bring the letterbox down, and no time of day message.
		pure = { apply = function(set)
			set("letterboxOffInCombat", false)
			set("timeOfDayMessage", false)
		end },
	},
	misc = {
		quietnpcs = { apply = NoNpcChat },
		-- No camera starts music again within half a minute of the last start.
		immersive = { apply = function(set)
			set("musicFatigue", 0.5)
			NoNpcChat(set)
		end },
		-- Chat shows for General and Trade (others joined later stay off;
		-- LocalDefense attacks show on the screen instead).
		lite = { apply = function(set)
			set("chatPeekChannelList", { General = true, Trade = true, LocalDefense = false,
				Services = false, TradeLocal = false })
			NoNpcChat(set)
		end },
		-- No music in CineMode.
		nomusic = { apply = function(set)
			set("musicInCinematic", false)
		end },
		-- Chat doesn't pop up on its own, nor peek for General or LocalDefense.
		pure = { apply = function(set)
			set("chatPeek", false)
			set("chatPeekChannelList", { General = false, LocalDefense = false })
			NoNpcChat(set)
		end },
	},
}

-- The part a profile's slot uses on a client (nil: none), and its name.
function ns.ProfilePart(parts, slot, client)
	local name = parts[slot]
	if type(name) == "table" then name = name[client] end
	name = name or "standard"
	return ns.PROFILE_PARTS[slot][name], name
end

-- A built-in profile's settings on a client: its parts (profile.parts), in
-- slot order, on top of base. A list's rows from two parts go together.
function ns.ApplyParts(parts, base, client)
	local written = {}
	local function Set(key, value)
		if type(value) == "table" then
			if not written[key] then
				base[key] = {}
				written[key] = true
			end
			for row, rowValue in pairs(value) do base[key][row] = rowValue end
		else
			base[key] = value
		end
	end
	for _, slot in ipairs(ns.PROFILE_SLOTS) do
		local part = ns.ProfilePart(parts, slot.key, client)
		if part then part.apply(Set) end
	end
	return base
end
