-- Profiles: named sets of settings to switch between.
--
-- The settings themselves stay where they always were (ns.db, flat), so the
-- rest of the addon never knows about profiles. Each profile is stored as the
-- settings that differ from its base: the built-in profile's own values (the
-- defaults with its changes on top), or the defaults for the player's own.
-- Switching saves the one you're leaving and loads the next; so does logging
-- out. Every character uses the account's profile (db.profile) unless it's
-- been given one of its own (CinematicCharDB.profile); db.liveProfile is the
-- one whose settings are live, so logging in on a character with a different
-- one swaps them over. Built-in profiles keep your changes too, until you reset them, and
-- settings you never changed follow the built-in's values as they're updated.
--
-- Not part of a profile: the minimap button and its position, the on/off
-- switch, debug options, frames you added or stopped fading, zone and time
-- tint colours you picked, and things the addon keeps for itself (flight
-- times, the log, game settings it's holding).

local _, ns = ...
local L = ns.L

local GLOBAL_KEYS = {
	enabled = true, minimapButton = true, minimapAngle = true, logDetail = true, language = true,
}
-- Lists kept as tables that belong to a profile (their defaults are in code;
-- see EnsureTables in Core.lua). Missing from a profile: emptied, which means defaults.
local PROFILE_TABLES = {
	"chatPeekTypes", "chatPeekChannelList", "combatShow", "cineShow", "targetShow", "enemyShow",
	"friendlyShow", "bgShow", "worldShow", "groupShow", "instanceShow", "addonFrames", "gamepadPressButtons",
	"hoverGroups", "cooldownReadyOnly", "cooldownReadyEarly", "cooldownEarlyOn",
}

local DEFAULT_PROFILE = "Immersive"

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
	"player", "prd", "target", "tot", "focus", "party", "raidplayers", "raidpets", "raidmanager", "minimap", "quests",
	"buffs", "swing", "cooldowns", "mainbar", "art",
	"bottomleft", "bottomright", "right1", "right2", "bar6", "bar7", "bar8", "pet", "stance", "totems",
	"micro", "xp",
}
local function Column(on)
	local list = {}
	for _, key in ipairs(STANDARD_ROWS) do list[key] = false end
	for _, key in ipairs(on) do list[key] = true end
	return list
end

-- The built-in profiles, in the order they're listed. apply(set) makes its
-- changes to the defaults; a list (PROFILE_TABLES) is set whole.
ns.BUILTIN_PROFILES = {
	{
		name = DEFAULT_PROFILE,
		tip = L["Everything on: the UI fades, the letterbox and tint, and every camera mode. The defaults, " ..
			"and how the developer plays every day."],
		apply = function(set)
			-- Auto-walking and auto-running can start music.
			set("musicCamWalk", true)
			set("musicCamRun", true)
			-- Nameplates: group members' pets, and the Grouped column for
			-- friendly players and minions, don't stay up.
			set("plateAlwaysGroupMinions", false)
			set("plateGroupFriends", false)
			set("plateGroupFriendlyMinions", false)
			-- Chat doesn't peek for NPC speech (guards, vendors, ambient chatter).
			set("chatPeekTypes", { npc = false })
		end,
	},
	{
		name = "Immersive (CDM)",
		tip = L["Immersive, with the Cooldown Manager in place of the action bars in fights: your " ..
			"portrait, target, buffs, swing timer, pet, stance and totem bars and the Cooldown Manager " ..
			"come up, the action bars don't. After a fight it stays up until its cooldowns are ready."],
		apply = function(set)
			-- The Standard Frames page's columns.
			set("cineShow", Column({}))
			set("combatShow", Column({ "player", "prd", "target", "tot", "focus", "party", "raidplayers", "raidpets",
				"minimap", "buffs", "swing", "cooldowns", "pet", "stance", "totems" }))
			set("enemyShow", Column({ "player", "prd", "target", "tot", "focus", "buffs", "pet", "stance",
				"totems" }))
			set("friendlyShow", Column({ "target", "tot" }))
			-- ...and after a fight, until its cooldowns are ready (within the Calm Timer).
			set("cooldownWhileRecharging", true)
			-- Auto-walking and auto-running can start music, as in Immersive.
			set("musicCamWalk", true)
			set("musicCamRun", true)
			-- Nameplates: group members' pets, and the Grouped column for
			-- friendly players and minions, don't stay up, as in Immersive.
			set("plateAlwaysGroupMinions", false)
			set("plateGroupFriends", false)
			set("plateGroupFriendlyMinions", false)
			-- Chat doesn't peek for NPC speech (guards, vendors, ambient chatter).
			set("chatPeekTypes", { npc = false })
		end,
	},
	{
		name = "Lite",
		tip = L["The UI fades and the look stays, with just a few cameras: flights (and fly-bys), AFK, " ..
			"and your Hearthstone and teleports. No cozy, vista, fish, RP walk, auto-run, death or quest cameras."],
		apply = function(set)
			CamsOff(set, { "cozy", "vista", "fish", "walk", "run", "death", "quest" })
			-- Chat shows for General, Trade and LocalDefense (others joined later stay off).
			set("chatPeekChannelList", { General = true, Trade = true, LocalDefense = true,
				Services = false, TradeLocal = false })
			-- ...and not for NPC speech (guards, vendors, ambient chatter).
			set("chatPeekTypes", { npc = false })
		end,
	},
	{
		name = "VFX Only",
		tip = L["Just the visual effects (tint, vignette, weather) over your normal UI: nothing fades, no " ..
			"letterbox, and the camera's left to you."],
		apply = function(set)
			set("fadeUI", false) -- (the effects then show over the normal UI)
			set("letterbox", false)
			set("musicInCinematic", false)
		end,
	},
	{
		name = "Camera Only",
		tip = L["The normal UI until a camera starts (standing still, going AFK, a flight, an emote...), " ..
			"then CineMode until it ends. The letterbox, tint, vignette and weather show only while a " ..
			"camera mode runs; no soft edges. Standing still starts the AFK camera, and every camera can start music."],
		apply = function(set)
			-- The visual effects just for the camera modes (Visual Effects
			-- page's "Outside camera modes" column).
			for _, effect in ipairs(ns.EFFECT_GRID) do
				set(effect .. "OnlyInCameras", true)
			end
			set("depthOfField", false)
			set("deathScreen", false)
			-- The normal UI until a camera starts: every camera brings CineMode
			-- on (Camera Triggers page's CineMode column).
			set("fadeUI", false)
			for _, event in ipairs(ns.EVENTS or {}) do
				if ns.DEFAULTS["event" .. event.key .. "Cine"] ~= nil then
					set("event" .. event.key .. "Cine", true)
				end
			end
			set("walkCine", true)
			set("runCine", true)
			set("deathCine", true)
			-- Every camera starting can bring music back, however recently it played.
			set("musicFatigue", 0)
			-- Standing still starts the AFK camera, and every camera can start music.
			set("eventStillCamera", "afk")
			for _, event in ipairs({ "AFK", "Still", "Chair", "Kneel", "Sleep", "Dance", "Weapon", "Campfire",
				"SitButton", "Fishing", "Hearth", "Teleport", "Logout", "Quest" }) do
				set("event" .. event .. "Music", true)
			end
			set("musicCamWalk", true)
			set("musicCamRun", true)
			-- NPCs talking nearby don't bring chat up over a camera shot.
			set("chatPeekTypes", { npc = false })
		end,
	},
	{
		name = "Solo Explorer",
		tip = L["Everything on while you're out in the world on your own; the normal UI in a group, " ..
			"in dungeons, raids and PvP."],
		apply = function(set)
			set("offInDungeons", true)
			set("offInRaids", true)
			set("offInPvP", true)
			set("offInParty", true)
			set("offInRaidGroup", true)
		end,
	},
	{
		name = "Pure Cinema",
		tip = L["As little UI as possible: chat, buffs, the quest tracker, the minimap and your portrait " ..
			"don't pop up on their own (hovering still shows them), group members' " ..
			"nameplates aren't kept up, and fights don't bring the letterbox down. Fights bring up only " ..
			"your target and your cast bar (hidden otherwise), and every camera can start music."],
		apply = function(set)
			set("chatPeek", false)
			set("buffPeek", false)
			set("debuffPeek", false)
			set("questRevealOnAccept", false)
			set("questRevealOnProgress", false)
			set("minimapRevealOnPing", false)
			set("portraitWhenNotFull", false)
			set("letterboxOffInCombat", false)
			set("timeOfDayMessage", false)
			set("plateAlwaysGroupMembers", false)
			set("plateAlwaysGroupMinions", false)
			-- No cast bar out of fights (it's up in them, with the default).
			set("cineShow", { castbar = false })
			-- Fights bring up only your target and its target (and the cast
			-- bar): no portrait, bars, buffs, minimap or swing timer. (Rows not
			-- listed keep the defaults.)
			set("combatShow", { tot = true, prd = false, party = false, raidplayers = false, raidpets = false, minimap = false, buffs = false, swing = false, mainbar = false,
				art = false, bottomleft = false, bottomright = false, pet = false, stance = false, totems = false,
				micro = false, xp = false, focus = false })
			set("enemyShow", { target = true, tot = true, player = false, prd = false, party = false, raidplayers = false,
				raidpets = false, focus = false, buffs = false,
				mainbar = false, art = false, bottomleft = false, bottomright = false, pet = false, stance = false,
				totems = false, micro = false, xp = false })
			set("friendlyShow", { target = true, tot = true })
			-- Standing still starts the AFK camera, and every event's camera can
			-- start music.
			set("eventStillCamera", "afk")
			for _, event in ipairs({ "AFK", "Still", "Chair", "Kneel", "Sleep", "Dance", "Weapon", "Campfire",
				"SitButton", "Fishing", "Hearth", "Teleport", "Logout", "Quest" }) do
				set("event" .. event .. "Music", true)
			end
			-- The cameras don't wait for things to calm down after a fight, and
			-- auto-run carries on in cities and instances (as RP walk always does).
			for _, cam in ipairs({ "walk", "run", "tele", "quest" }) do
				set(cam .. "CalmWait", false)
			end
			set("runOffInCities", false)
			set("runOffInInstances", false)
			-- No minimap for tracking, nor hiding it on flights or while AFK; no
			-- quest timer box.
			set("minimapForTracking", false)
			set("flightHideMinimap", false)
			set("idleHideMinimap", false)
			set("questTimerShow", false)
			-- Chat doesn't peek for General or LocalDefense.
			set("chatPeekChannelList", { General = false, LocalDefense = false })
			-- Nor for NPC speech, should chat peeking be switched back on.
			set("chatPeekTypes", { npc = false })
		end,
	},
}
ns.OnLanguage(function() ns.TranslateFields(ns.BUILTIN_PROFILES, "tip") end)
local builtinByName = {}
for _, profile in ipairs(ns.BUILTIN_PROFILES) do builtinByName[profile.name] = profile end

function ns.IsBuiltinProfile(name)
	return builtinByName[name] ~= nil
end

local function IsProfileKey(key)
	return not GLOBAL_KEYS[key] and not key:find("^debug")
end

local function CopyTable(source)
	if type(source) ~= "table" then return source end
	local result = {}
	for k, v in pairs(source) do result[k] = CopyTable(v) end
	return result
end

-- The values a profile starts from: the defaults, with a built-in's changes.
local baseCache = {}
function ns.ProfileBase(name)
	name = name or ns.ActiveProfile()
	if baseCache[name] then return baseCache[name] end
	local base = {}
	for k, v in pairs(ns.DEFAULTS) do base[k] = v end
	local builtin = builtinByName[name]
	if builtin then
		builtin.apply(function(key, value) base[key] = value end)
	end
	baseCache[name] = base
	return base
end

-- A new player has none until they pick one (Welcome.lua): Cinematic does
-- nothing meanwhile. (The default profile's settings are the live ones.)
function ns.ProfileChosen()
	return not ns.db or ns.db.profileChosen ~= false
end

function ns.ActiveProfile()
	return ns.db and ns.db.liveProfile or DEFAULT_PROFILE
end

-- This character has a profile of its own (not the account's).
function ns.IsCharacterProfile()
	return ns.chardb ~= nil and ns.chardb.profile ~= nil
end

-- Makes name the active one: this character's, or the account's.
local function Choose(name)
	if ns.IsCharacterProfile() then
		ns.chardb.profile = name
	else
		ns.db.profile = name
	end
	ns.db.liveProfile = name
end

-- The live settings as a profile: what differs from the base, and the lists.
local function Snapshot(name)
	local db, base = ns.db, ns.ProfileBase(name)
	local saved = {}
	for k in pairs(ns.DEFAULTS) do
		if IsProfileKey(k) and db[k] ~= base[k] then
			saved[k] = db[k]
		end
	end
	for _, k in ipairs(PROFILE_TABLES) do
		if type(db[k]) == "table" and next(db[k]) ~= nil then saved[k] = CopyTable(db[k]) end
	end
	return saved
end

-- Puts a profile's settings into the live ones.
local function Load(name)
	local db, base = ns.db, ns.ProfileBase(name)
	local saved = db.profiles[name] or {}
	for k in pairs(ns.DEFAULTS) do
		if IsProfileKey(k) then
			if saved[k] ~= nil then
				db[k] = saved[k]
			else
				db[k] = base[k]
			end
		end
	end
	for _, k in ipairs(PROFILE_TABLES) do
		-- (A built-in's own list when it has one; a copy, so the base isn't changed.)
		db[k] = CopyTable(saved[k] or base[k])
	end
	ns.EnsureTables()
end

-- Everything that reads settings once picks up the new ones.
local function SettingsChanged()
	ns.letterboxDirty = true
	if ns.RestartTimers then ns.RestartTimers() end
	if ns.RefreshTint then ns.RefreshTint() end
	if ns.BuildManagedList then ns.BuildManagedList() end
	if ns.ApplyBubbles then ns.ApplyBubbles() end
	if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Keeps the live settings in the active profile (on switching and logout).
function ns.SaveProfile()
	if ns.db and ns.db.profiles then
		ns.db.profiles[ns.ActiveProfile()] = Snapshot(ns.ActiveProfile())
	end
end

function ns.ProfileExists(name)
	return builtinByName[name] ~= nil or (ns.db.profiles[name] ~= nil)
end

-- Every profile's name: the built-in ones in order, then the player's A to Z.
function ns.ProfileNames()
	local names, own = {}, {}
	for _, profile in ipairs(ns.BUILTIN_PROFILES) do names[#names + 1] = profile.name end
	for name in pairs(ns.db.profiles) do
		if not builtinByName[name] then own[#own + 1] = name end
	end
	table.sort(own, function(a, b) return a:lower() < b:lower() end)
	for _, name in ipairs(own) do names[#names + 1] = name end
	return names
end

-- Finds a profile ignoring case (for /cine profile).
function ns.FindProfile(text)
	text = text:lower()
	for _, name in ipairs(ns.ProfileNames()) do
		if name:lower() == text then return name end
	end
end

function ns.SetProfile(name)
	if not ns.ProfileExists(name) then return end
	local first = not ns.ProfileChosen()
	ns.db.profileChosen = true
	if name == ns.ActiveProfile() then
		if first then SettingsChanged() end -- (the first pick: Cinematic starts)
		return
	end
	ns.SaveProfile()
	Choose(name)
	Load(name)
	SettingsChanged()
	ns.Log("state", "profile: " .. name)
end

-- A profile of your own's description (db.profileNotes: kept apart from its
-- settings, which are written over each time it's saved).
function ns.ProfileNote(name)
	return ns.db.profileNotes[name]
end

function ns.SetProfileNote(name, text)
	if builtinByName[name] then return end
	ns.db.profileNotes[name] = text ~= "" and text or nil
end

-- A new profile of your own from the current settings.
function ns.NewProfile(name)
	if ns.ProfileExists(name) then return false end
	local saved = Snapshot(ns.ActiveProfile())
	-- Stored against the defaults (a player's profile has no built-in under it).
	local base, own = ns.ProfileBase(ns.ActiveProfile()), ns.ProfileBase(name)
	for k in pairs(ns.DEFAULTS) do
		if IsProfileKey(k) then
			local value = saved[k]
			if value == nil then value = base[k] end
			if value == own[k] then value = nil end
			saved[k] = value
		end
	end
	ns.SaveProfile()
	ns.db.profiles[name] = saved
	ns.db.profileNotes[name] = L["Started from %s."]:format(ns.ActiveProfile())
	Choose(name)
	ns.db.profileChosen = true
	return true
end

function ns.RenameProfile(old, new)
	if builtinByName[old] or ns.ProfileExists(new) then return false end
	if old == ns.ActiveProfile() then ns.SaveProfile() end
	ns.db.profiles[new], ns.db.profiles[old] = ns.db.profiles[old], nil
	ns.db.profileNotes[new], ns.db.profileNotes[old] = ns.db.profileNotes[old], nil
	-- (Other characters with it as their own go back to the account's next login.)
	for _, holder in ipairs({ ns.db, ns.chardb }) do
		if holder.profile == old then holder.profile = new end
	end
	if ns.db.liveProfile == old then ns.db.liveProfile = new end
	return true
end

-- Deleting the active one switches to the default profile first.
function ns.DeleteProfile(name)
	if builtinByName[name] then return false end
	if name == ns.ActiveProfile() then ns.SetProfile(DEFAULT_PROFILE) end
	if ns.db.profile == name then ns.db.profile = DEFAULT_PROFILE end
	ns.db.profiles[name] = nil
	ns.db.profileNotes[name] = nil
	return true
end

-- Back to the profile's base: a built-in's own values, or the defaults.
function ns.ResetProfile()
	ns.db.profiles[ns.ActiveProfile()] = nil
	Load(ns.ActiveProfile())
	SettingsChanged()
end

-- Settings changed from the active profile's base, for the Profiles page's
-- "(changed)". (Not the lists: those are tables whatever's in them.)
function ns.ProfileChanged()
	local base = ns.ProfileBase()
	for k in pairs(ns.DEFAULTS) do
		if IsProfileKey(k) and ns.db[k] ~= base[k] then return true end
	end
	return false
end

-- A profile's settings for sharing (Share.lua): what differs from the
-- defaults, and its lists. (Against the defaults, not a built-in's values,
-- so it comes out the same on a version whose built-ins have changed.)
function ns.ProfileForSharing(name)
	if name == ns.ActiveProfile() then ns.SaveProfile() end
	local saved, base = ns.db.profiles[name] or {}, ns.ProfileBase(name)
	local shared = {}
	for k, default in pairs(ns.DEFAULTS) do
		if IsProfileKey(k) then
			local value = saved[k]
			if value == nil then value = base[k] end
			if value ~= default then shared[k] = CopyTable(value) end
		end
	end
	for _, k in ipairs(PROFILE_TABLES) do
		local list = saved[k] or base[k]
		if type(list) == "table" and next(list) ~= nil then shared[k] = CopyTable(list) end
	end
	return shared
end

-- Whether a shared setting is one this version has: a list, or a setting
-- of the same kind as its default. (The rest are skipped on import.)
function ns.KnownProfileSetting(key, value)
	if type(key) ~= "string" then return false end
	for _, k in ipairs(PROFILE_TABLES) do
		if k == key then return type(value) == "table" end
	end
	local default = ns.DEFAULTS[key]
	return default ~= nil and IsProfileKey(key) and type(value) == type(default)
end

-- A new profile of your own from shared settings (stored against the
-- defaults, as your own are), switched to.
function ns.AddSharedProfile(name, settings, note)
	if ns.ProfileExists(name) then return false end
	ns.db.profiles[name] = settings
	ns.db.profileNotes[name] = note
	ns.SetProfile(name)
	ns.Log("state", "profile imported: " .. name)
	return true
end

-- Ticked: this character keeps the profile it's on as its own, and
-- switching changes only its. Unticked: back to the account's profile.
function ns.SetCharacterProfile(own)
	if own then
		ns.chardb.profile = ns.ActiveProfile()
	elseif ns.IsCharacterProfile() then
		ns.chardb.profile = nil
		if ns.db.profile ~= ns.ActiveProfile() then
			ns.SaveProfile()
			ns.db.liveProfile = ns.db.profile
			Load(ns.db.profile)
			SettingsChanged()
		end
	end
end

-- After the settings load (Core.lua). Settings from before profiles become
-- the default profile's, changes and all.
function ns.InitProfiles()
	CinematicCharDB = CinematicCharDB or {}
	ns.chardb = CinematicCharDB
	local db, chardb = ns.db, ns.chardb
	db.profiles = db.profiles or {}
	db.profileNotes = db.profileNotes or {}
	-- The default profile was first called Cinematic Strong (test builds).
	local old = "Cinematic Strong"
	if db.profiles[old] and not db.profiles[DEFAULT_PROFILE] then
		db.profiles[DEFAULT_PROFILE], db.profiles[old] = db.profiles[old], nil
	end
	for _, holder in ipairs({ db, chardb }) do
		if holder.profile == old then holder.profile = DEFAULT_PROFILE end
	end
	if db.liveProfile == old then db.liveProfile = DEFAULT_PROFILE end
	-- Only a new player is asked to pick one (Welcome.lua); everyone else has
	-- their settings already.
	if db.profileChosen == nil then
		db.profileChosen = not ns.newInstall
	end
	if not db.profile or not ns.ProfileExists(db.profile) then
		db.profile = DEFAULT_PROFILE
	end
	-- (One deleted or renamed on another character: the account's again.)
	if chardb.profile and not ns.ProfileExists(chardb.profile) then
		chardb.profile = nil
	end
	db.liveProfile = db.liveProfile or db.profile
	local wanted = chardb.profile or db.profile
	if wanted ~= db.liveProfile then
		if ns.ProfileExists(db.liveProfile) then ns.SaveProfile() end
		db.liveProfile = wanted
		Load(wanted)
	end
end
