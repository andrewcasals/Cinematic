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
	"frameRules", -- (none in any built-in profile: each starts with no Custom Visibility Rules)
	"tankHide", "healerHide", "damageHide",
}
ns.PROFILE_TABLES = PROFILE_TABLES

local DEFAULT_PROFILE = "Immersive"

-- The built-in profiles, in the order they're listed. parts: the part each
-- slot uses (ProfileParts.lua; a slot not named: its "standard" part).
ns.BUILTIN_PROFILES = {
	{
		name = DEFAULT_PROFILE,
		icon = "Interface\\Icons\\Spell_Holy_MindVision",
		tip = L["Everything on: the UI fades, the letterbox and tint, and every camera mode. The defaults, " ..
			"and how the developer plays every day."],
		parts = { frames = "immersive", camera = "immersive", misc = "immersive" },
	},
	{
		name = "Immersive (CDM)",
		icon = "Interface\\Icons\\Spell_Shadow_AntiShadow", -- (Preparation)
		tip = L["Immersive, with the Cooldown Manager in place of action bars 1 to 3, the micro menu and the " ..
			"XP bar in fights and with an enemy targeted. After a fight it stays up until its cooldowns are ready."],
		parts = { frames = "cdm", bars = "cdm", camera = "immersive", misc = "immersive" },
	},
	{
		name = "Lite",
		icon = "Interface\\Icons\\Spell_Holy_HolyBolt",
		tip = L["The UI fades and the look stays, with just a few cameras: flights (and fly-bys), AFK, " ..
			"and your Hearthstone and teleports. No cozy, vista, fish, RP walk, auto-run, death or quest cameras."],
		parts = { camera = "lite", misc = "lite" },
	},
	{
		name = "VFX Only",
		icon = "Interface\\Icons\\Spell_Nature_Lightning",
		tip = L["Just the visual effects (tint, vignette, weather) over your normal UI: nothing fades, no " ..
			"letterbox, and the camera's left to you."],
		parts = { frames = "nofade", vfx = "noletterbox", misc = "nomusic" },
	},
	{
		name = "Camera Only",
		icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
		tip = L["The normal UI until a camera starts (standing still, going AFK, a flight, an emote...), " ..
			"then CineMode until it ends. The letterbox, tint, vignette and weather show only while a " ..
			"camera mode runs; no soft edges. Standing still starts the AFK camera, and every camera can start music."],
		parts = { frames = "nofade", camera = "cinemode", vfx = "cameras", misc = "quietnpcs" },
	},
	{
		name = "Solo Explorer",
		icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
		tip = L["Everything on while you're out in the world on your own; the normal UI in a group, " ..
			"in dungeons, raids and PvP."],
		parts = { frames = "solo" },
	},
	{
		name = "Pure Cinema",
		icon = "Interface\\Icons\\Ability_Stealth",
		tip = L["As little UI as possible: chat, buffs and the quest tracker " ..
			"don't pop up on their own (hovering still shows them), group members' " ..
			"nameplates aren't kept up, and fights don't bring the letterbox down. Fights bring up only " ..
			"your target and your cast bar (hidden otherwise), and every camera can start music."],
		parts = { frames = "pure", bars = "pure", camera = "pure", vfx = "pure", misc = "pure" },
	},
}
ns.OnLanguage(function() ns.TranslateFields(ns.BUILTIN_PROFILES, "tip") end)
local builtinByName = {}
for _, profile in ipairs(ns.BUILTIN_PROFILES) do builtinByName[profile.name] = profile end

function ns.IsBuiltinProfile(name)
	return builtinByName[name] ~= nil
end

local function IsProfileKey(key)
	-- (Graphics+ is the machine's: a shared or switched profile leaves it as it is.)
	return not GLOBAL_KEYS[key] and not key:find("^debug") and not key:find("^graphicsPlus")
end
ns.IsProfileKey = IsProfileKey

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
	if builtin then ns.ApplyParts(builtin.parts, base) end
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
	if ns.ApplyUnitFrameParts then ns.ApplyUnitFrameParts() end
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

-- A profile's icon: a built-in's own, or the one picked for yours
-- (db.profileIcons, one of HOVER_GROUP_ICONS).
function ns.ProfileIcon(name)
	local builtin = builtinByName[name]
	return builtin and builtin.icon or ns.db.profileIcons[name] or ns.HOVER_GROUP_ICONS[1]
end

function ns.SetProfileIcon(name, file)
	if builtinByName[name] then return end
	ns.db.profileIcons[name] = file
end

-- A random icon no profile has yet (for a new one), else any.
function ns.UnusedProfileIcon()
	local used, free = {}, {}
	for _, name in ipairs(ns.ProfileNames()) do used[ns.ProfileIcon(name)] = true end
	for i = 2, #ns.HOVER_GROUP_ICONS do
		if not used[ns.HOVER_GROUP_ICONS[i]] then free[#free + 1] = ns.HOVER_GROUP_ICONS[i] end
	end
	if #free == 0 then free = ns.HOVER_GROUP_ICONS end
	return free[math.random(#free)]
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
	ns.db.profileIcons[name] = ns.UnusedProfileIcon()
	Choose(name)
	ns.db.profileChosen = true
	return true
end

function ns.RenameProfile(old, new)
	if builtinByName[old] or ns.ProfileExists(new) then return false end
	if old == ns.ActiveProfile() then ns.SaveProfile() end
	ns.db.profiles[new], ns.db.profiles[old] = ns.db.profiles[old], nil
	ns.db.profileNotes[new], ns.db.profileNotes[old] = ns.db.profileNotes[old], nil
	ns.db.profileIcons[new], ns.db.profileIcons[old] = ns.db.profileIcons[old], nil
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
	ns.db.profileIcons[name] = nil
	return true
end

-- Back to the profile's base: a built-in's own values, or the defaults.
function ns.ResetProfile()
	ns.db.profiles[ns.ActiveProfile()] = nil
	Load(ns.ActiveProfile())
	SettingsChanged()
end

-- Everything back to a fresh install: every profile and setting goes, and the
-- UI reloads so it starts over (the welcome window too). Other characters'
-- own profile picks fall back to the account's next login.
function ns.ResetAddon()
	CinematicDB, CinematicCharDB = nil, nil
	ns.db.profiles = {} -- (so logout's ns.SaveProfile writes into nothing kept)
	ReloadUI()
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
function ns.AddSharedProfile(name, settings, note, icon)
	if ns.ProfileExists(name) then return false end
	ns.db.profileIcons[name] = icon or ns.UnusedProfileIcon()
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
	db.profileIcons = db.profileIcons or {}
	-- The default profile was first called Cinematic Strong (test builds).
	local old = "Cinematic Strong"
	if db.profiles[old] and not db.profiles[DEFAULT_PROFILE] then
		db.profiles[DEFAULT_PROFILE], db.profiles[old] = db.profiles[old], nil
	end
	for _, holder in ipairs({ db, chardb }) do
		if holder.profile == old then holder.profile = DEFAULT_PROFILE end
	end
	if db.liveProfile == old then db.liveProfile = DEFAULT_PROFILE end
	-- Your own profiles made before they had icons get one each.
	for _, name in ipairs(ns.ProfileNames()) do
		if not builtinByName[name] and not db.profileIcons[name] then
			db.profileIcons[name] = ns.UnusedProfileIcon()
		end
	end
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
