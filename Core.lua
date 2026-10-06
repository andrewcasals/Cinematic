-- Cinematic: fades the UI out between fights and slides in letterbox bars.
--
-- Only SetAlpha is used on Blizzard frames (never Show/Hide), so it is safe
-- to touch protected frames like action bars even during combat lockdown.

local ADDON_NAME, ns = ...

BINDING_HEADER_CINEMATIC = "Cinematic"
BINDING_NAME_CINEMATIC_TOGGLE = "Toggle cinematic mode"
BINDING_NAME_CINEMATIC_PEEK = "Peek at UI (hold)"

local DEFAULTS = {
	enabled = true,
	minimapButton = true,     -- show the minimap button
	minimapAngle = 225,       -- its position around the minimap, in degrees
	startCinematic = true,   -- be in cinematic mode straight away on login
	startCinematicOnReload = true, -- ...and after a /reload
	-- Hide world tooltips in each camera mode:
	tooltipOffFlight = true,
	tooltipOffIdle = true,    -- standing still
	tooltipOffCozy = true,
	tooltipOffWalk = true,    -- RP walking
	tooltipOffRun = false,     -- auto-running
	hideCombatText = true,    -- no floating combat text (heals, regen) in cinematic mode out of combat
	timeOfDayMessage = true,  -- "Dusk" under the zone name on login and /reload
	timeOfDayChange = true,   -- ...and on its own when the time of day changes
	timeOfDaySound = true,    -- ...with a fitting sound (rooster, bells, frogs, owl, wolf)
	offInDungeons = true,     -- no cinematic mode in dungeons (and scenarios)
	offInRaids = true,
	offInPvP = true,          -- battlegrounds and arenas
	offInCities = false,      -- capital cities
	offInInns = false,        -- inns (resting outside a capital)
	delay = 15,            -- seconds of calm before fading out
	fadeOutTime = 2.5,
	fadeInTime = 0.5,
	letterbox = true,
	letterboxSize = 0.03,  -- fraction of screen height per bar
	letterboxAlpha = 1,    -- bar opacity
	tintPreset = "zonetime",   -- screen tint over the game world (see TINT_PRESETS)
	tintStrength = 1,
	tintCustomR = 1, tintCustomG = 0.8, tintCustomB = 0.6,
	vignette = true,      -- darkened screen edges
	vignetteStrength = 0.1,
	tintWhen = "always",   -- "always", "flight" or "idle" (standing still past the standing-still delay)
	tintClock = "game",    -- time-of-day tint follows "game" (realm) time or "local" (computer) time
	timeTintStrength = 1,  -- how strongly the time-of-day colour applies (both time presets)
	tintPreviewHour = -1,  -- options-page preview of the time-of-day tint at this hour (-1 = now)
	fadeChat = true,
	alwaysShowMinimap = false, -- keep the whole minimap group visible in cinematic mode
	minimapForTracking = true, -- master switch for the minimapFor* tracking options below
	minimapForHerbs = true,    -- keep the minimap visible while this tracking is active
	minimapForMinerals = true,
	minimapForTreasure = true,
	minimapForFish = true,
	minimapForCreatures = false,
	trackingHideWhenIdle = true, -- ...except once the standing-still timer has run, or on flights
	revealOnTarget = true, -- attackable target brings the UI back
	stayInCombat = true,  -- stay cinematic in combat and when targeting enemies
	combatFadeInTime = 0.2,  -- how fast the "while fighting, show" frames appear
	ignoreDeadTarget = true, -- a dead enemy targeted doesn't count as fighting
	combatFadeOutTime = 5, -- and how fast they go once the fight is over
	enemyFadeInTime = 0.5,   -- targeting an enemy out of combat: fade times for its frame list
	enemyFadeOutTime = 1.5,
	friendlyFadeInTime = 1,  -- targeting a friend (anything you can't attack)
	friendlyFadeOutTime = 1.5,
	revealOnCast = false,   -- casting or channeling brings the UI back
	revealAtNPCs = false,
	revealOnDrag = true,      -- bring the UI back while something's held on the cursor (dragging)  -- vendor/bank/mail/trainer/trade/auction windows bring the UI back
	stayWithWindows = true, -- stay cinematic when opening the spellbook, options and similar
	portraitWhenNotFull = true, -- keep the player portrait up while health or power isn't full
	portraitAfterCombat = true,  -- ...but only within portraitCombatWindow seconds of combat
	portraitCombatWindow = 60,
	buffPeek = true,          -- briefly show buffs/debuffs when one is gained or refreshed
	buffPeekTime = 2.5,         -- seconds they stay up
	buffPeekIgnore = "2479, Plainsrunning", -- buffs that never bring them up (spell IDs or names)
	mouseover = true,      -- hovering a faded element reveals it
	minimapHoverHold = 8,  -- seconds the minimap stays after the mouse leaves it
	questsHoverHold = 10,   -- seconds the quest tracker stays after the mouse leaves it
	musicInCinematic = true,  -- turn game music on while cinematic, off after
	musicOffOnLogout = true,  -- turn game music off when logging out
	hideNames = true,         -- hide unit names while cinematic
	hidePlates = true,        -- hide nameplates while cinematic
	fadeTooltip = false,      -- hide tooltips for units/objects in the world
	musicFadeTime = 5,        -- seconds for music to fade in or out
	musicFatigue = 5,         -- minutes: don't start music again within this long of the last start
	musicNewSongOnFlights = true, -- switch music off and on as flight rotation starts so a new song starts
	musicNewSongWhenIdle = true,  -- ...and as the standing-still camera starts
	musicNewSongWhenWalking = true, -- ...and when you set off RP walking
	musicNewSongWhenAutoRun = true, -- ...and when you start auto-running
	musicNewSongWhenCozy = true,    -- ...and when the cozy camera starts
	musicPauseWhenMoving = true,  -- music fades out once you move on from flying, RP walking or standing still
	musicPauseFadeTime = 3,       -- seconds that pause takes to fade out (and the music to come back)
	fatigueIgnoreOnFlights = true, -- ...but start it anyway on a flight,
	fatigueIgnoreWhenIdle = true,  -- once the standing-still timer has run,
	fatigueIgnoreWhenWalking = true, -- while RP walking,
	fatigueIgnoreWhenAutoRun = true, -- while auto-running,
	fatigueIgnoreWhenCozy = true,    -- while cozy (campfire, emotes),
	fatigueIgnoreNewZone = true,   -- or in a different zone from the last music
	ambienceFollowsMusic = false, -- set ambient sound to a share of the music volume while cinematic
	musicOffInCombat = false, -- fade game music out while in combat
	musicCombatResume = 30,   -- ...and keep it off until this many seconds after the fight
	musicOffOnFlights = false, -- ...and while on a flight path
	musicOffInCities = false, -- ...and in these places
	musicOffInInns = false,
	musicOffInDungeons = false,
	musicOffInRaids = false,
	musicOffInPvP = false,
	ambienceScale = 0.5,      -- ...this share (0-2)
	chatPeek = true,          -- briefly show a chat window when a message arrives
	chatPeekChannels = false, -- old "include public channels"; now the default for channels not yet set
	chatPeekTime = 8,         -- seconds the chat window stays up
	chatInCities = false,     -- keep chat visible in capital cities
	chatInInns = false,       -- ...in inns
	chatInDungeons = false,   -- ...in dungeons and scenarios
	chatInRaids = false,
	chatInPvP = false,        -- ...in battlegrounds and arenas
	dropTargetOnFlights = true, -- ignore your target from takeoff (its frames fade) until you pick another
	taxiInstant = true,       -- go cinematic as soon as a flight starts (no fade delay)
	taxiCenter = true,        -- swing the camera behind the character when a flight starts
	taxiOrbit = true,         -- slowly rotate the camera while on a flight path
	taxiSettle = true,        -- swing the camera behind the character before landing
	taxiSettleLead = 8,       -- seconds before the expected landing to start settling
	idleOrbit = true,         -- also rotate it after standing still for a while
	idleOrbitDelay = 30,      -- seconds of standing still before it starts
	-- Cozy camera: swings round to face you and sways in front, when resting
	-- at a campfire (listed buffs) or doing one of these emotes.
	cozyOrbit = true,         -- sway in front of you
	cozyZoom = true,          -- with a close, gentle zoom
	cozyInstant = true,       -- go cinematic straight away
	cozyBuffsOn = true,       -- with one of the buffs below, while still
	cozyBuffs = "Welcoming Campfire", -- buff names or spell IDs, comma-separated
	cozySit = true,           -- /sit (and the sit key)
	cozySleep = true,         -- /sleep, /lie
	cozyDance = true,         -- /dance
	cozyKneel = true,         -- /kneel
	cozyChair = true,         -- sitting on a chair, bench and so on
	cozyWeapon = true,        -- standing with your weapon drawn (a "hero shot")
	cozyCrackle = true,       -- a crackling fire sound while cozy at a campfire
	cozyChairWords = "chair, bench, stool, seat, throne, pew", -- words in a seat's name
	cozyInputPause = 2,       -- seconds after you move the camera before it carries on
	cozyZoomClose = 10,       -- yards: the distance it zooms in to (if you're further out); far side of a fire
	cozyLevel = 15,           -- degrees it brings the camera down toward the ground as it swings round
	idleZoom = true,          -- slowly zoom out after standing still for idleOrbitDelay
	taxiZoom = true,          -- the same slow zoom during flights
	idleZoomDistance = 6,     -- yards: first pull-back, and furthest out a random zoom goes
	idleZoomIn = 2,           -- yards: furthest in (closer than the player's zoom) a random zoom goes
	idleZoomTime = 20,        -- seconds each zoom takes
	idleZoomPause = 10,       -- seconds between random zooms
	idleZoomRandom = true,    -- keep zooming in and out at random after the first pull-back
	idleZoomEase = 0.5,       -- fraction of each zoom spent speeding up (and again slowing down)
	idleZoomPastMax = true,   -- raise the max zoom distance (to 2.6) during the pull-back
	idleOpeningDrift = 5,     -- random/behind modes: seconds of slow drift before the first move
	rotOffInCities = false,   -- no standing-still rotation in these places
	rotOffInInns = false,
	rotOffInDungeons = false,
	rotOffInRaids = false,
	rotOffInPvP = false,
	zoomOffInCities = false,  -- no standing-still zoom in these places
	zoomOffInInns = false,
	zoomOffInDungeons = false,
	zoomOffInRaids = false,
	zoomOffInPvP = false,
	cameraInputPause = 15,    -- seconds the rotation waits after the player moves the camera
	cameraPauseAtNPCs = true, -- no standing-still camera while an NPC window (auction house...) is open
	cameraPauseCasting = true, -- ...or while you're casting (crafting, say)
	-- Tuck the mouse cursor away (mouse-steering mode) once it's still, in each
	-- camera mode, and at other times in cinematic mode:
	cursorTuckFlight = true,
	cursorTuckIdle = false,
	cursorTuckCozy = false,
	cursorTuckWalk = false,
	cursorTuckRun = false,
	cursorTuckOther = false,
	cursorTuckDelay = 3,      -- seconds of a still cursor first
	indoorLimits = true,      -- indoors, keep the camera modes from pushing into walls:
	indoorZoomOut = 1,        -- ...zoom out at most this many yards past your own distance
	indoorSwing = 20,         -- ...swing at most this far either side of behind
	indoorNoSweep = false,    -- ...and optionally no standing-still rotation at all
	taxiOrbitSpeed = 6,       -- peak degrees per second during a sweep
	taxiOrbitMode = "back",  -- "sweep", "random" or "back" (random angles behind the character)
	taxiOrbitStep = 60,       -- degrees per sweep (sweep mode)
	taxiOrbitMinChange = 45,  -- random mode: new angle is at least this far from the current one
	taxiOrbitPitchUp = 10,    -- random modes: tilt up to this many degrees up...
	taxiOrbitPitchDown = 20,  -- ...and down
	taxiOrbitBackArc = 70,    -- behind mode: swing up to this many degrees either side of behind
	taxiOrbitMoveTime = 10,    -- random modes: seconds per move, however far it goes
	taxiOrbitEase = 0.5,      -- fraction of each move spent speeding up (and again slowing down)
	taxiOrbitDrift = true,   -- keep the camera creeping during pauses instead of stopping
	taxiOrbitDriftSpeed = 3, -- degrees per second while drifting
	taxiOrbitPause = 15,       -- seconds to hold between sweeps
	taxiOrbitRight = false,   -- rotate clockwise instead
}

-- Camera rotation settings come in two profiles: taxiOrbit* for flights and
-- idleOrbit* for standing still. The idle defaults copy the flight ones.
local ORBIT_PROFILE_KEYS = {
	"Mode", "Right", "Step", "Speed", "MinChange", "PitchUp", "PitchDown", "BackArc", "MoveTime",
	"Ease", "Pause", "Drift", "DriftSpeed",
}
for _, key in ipairs(ORBIT_PROFILE_KEYS) do
	DEFAULTS["idleOrbit" .. key] = DEFAULTS["taxiOrbit" .. key]
end
-- The standing-still camera's own defaults where they differ from the flight ones.
DEFAULTS.idleOrbitMode = "sweep"
DEFAULTS.idleOrbitBackArc = 45
DEFAULTS.idleOrbitDrift = true
DEFAULTS.idleOrbitDriftSpeed = 1
DEFAULTS.idleOrbitMoveTime = 10
DEFAULTS.idleOrbitPause = 20
DEFAULTS.idleOrbitPitchDown = 10
DEFAULTS.idleOrbitPitchUp = 10
DEFAULTS.idleOrbitStep = 40
-- RP walking (moving in walk mode): its own page. The rotation is always
-- "behind only" (walkOrbit* minus the mode), plus its own gentle zoom.
DEFAULTS.walkOrbit = true          -- sway the camera behind you while walking
DEFAULTS.walkZoom = true           -- and drift the zoom gently in and out
DEFAULTS.walkInstant = true        -- go cinematic as soon as you walk
DEFAULTS.walkInputPause = 2        -- seconds: picks up again quickly after you move the camera
DEFAULTS.walkSwingBehind = true    -- after a turn, the camera glides back behind you
DEFAULTS.walkGlideDelay = 1.5      -- seconds after a turn before that glide starts
-- Cozy camera swing (around the front) and zoom (stays close).
for key, value in pairs({
	Mode = "back", Right = false, Step = 30, Speed = 4, MinChange = 5,
	PitchUp = 4, PitchDown = 3, BackArc = 45, MoveTime = 20, Ease = 0.5,
	Pause = 5, Drift = true, DriftSpeed = 0.5,
}) do
	DEFAULTS["cozyOrbit" .. key] = value
end
-- (Around the close-up distance: a little in, a little out.)
for key, value in pairs({
	Distance = 0.5, In = 1.5, Time = 12, Pause = 6, Random = true, Ease = 0.5, PastMax = false,
}) do
	DEFAULTS["cozyZoom" .. key] = value
end
-- Auto-run camera: like RP walk, while auto-running (runOrbit*, runZoom*).
DEFAULTS.runOrbit = true
DEFAULTS.runZoom = true
DEFAULTS.runInstant = true
DEFAULTS.runInputPause = 2
DEFAULTS.runSwingBehind = true
DEFAULTS.runGlideDelay = 0.5
for key, value in pairs({
	Mode = "back", Right = false, Step = 30, Speed = 4, MinChange = 6,
	PitchUp = 3, PitchDown = 10, BackArc = 15, MoveTime = 6, Ease = 0.5,
	Pause = 2, Drift = true, DriftSpeed = 1,
}) do
	DEFAULTS["runOrbit" .. key] = value
end
for key, value in pairs({
	Mode = "back", Right = false, Step = 30, Speed = 4, MinChange = 15,
	PitchUp = 8, PitchDown = 8, BackArc = 35, MoveTime = 8, Ease = 0.5,
	Pause = 4, Drift = true, DriftSpeed = 1,
}) do
	DEFAULTS["walkOrbit" .. key] = value
end
-- Slow zoom settings likewise: idleZoom* for standing still, taxiZoom* for
-- flights, with the flight defaults copying the standing-still ones.
local ZOOM_PROFILE_KEYS = { "Distance", "In", "Time", "Pause", "Random", "Ease", "PastMax" }
for key, value in pairs({
	Distance = 4, In = 3, Time = 10, Pause = 4, Random = true, Ease = 0.5, PastMax = true,
}) do
	DEFAULTS["walkZoom" .. key] = value
	DEFAULTS["runZoom" .. key] = value
end
-- Auto-run zooms in and out more often, over a little more range.
DEFAULTS.runZoomPause = 1.5
DEFAULTS.runZoomTime = 7
DEFAULTS.runZoomDistance = 8
DEFAULTS.runZoomIn = 4
for _, key in ipairs(ZOOM_PROFILE_KEYS) do
	DEFAULTS["taxiZoom" .. key] = DEFAULTS["idleZoom" .. key]
end

-- While any of these windows is open, keep the UI visible.
local REVEAL_WHILE_SHOWN = {
	"SpellBookFrame", "PlayerSpellsFrame", "MacroFrame", "CharacterFrame",
	"TalentFrame", "PlayerTalentFrame", "SettingsPanel",
	"KeyBindingFrame", "InterfaceOptionsFrame", "EditModeManagerFrame",
}
-- Windows opened by talking to an NPC; these only reveal the UI if the player
-- chooses (revealAtNPCs). The windows themselves aren't faded either way.
local REVEAL_AT_NPCS = {
	"MerchantFrame", "TradeFrame", "AuctionFrame", "AuctionHouseFrame", "BankFrame",
	"MailFrame", "ClassTrainerFrame",
}

local lastBusy = 0
local peeking = false

function ns.Print(msg)
	print("|cffe0b050Cinematic:|r " .. msg)
end

local function AnyShown(names)
	for _, name in ipairs(names) do
		local frame = _G[name]
		if frame and frame:IsShown() then
			return true
		end
	end
	return false
end

-- Talking to an NPC: their windows, plus quest givers, gossip and the flight
-- map. The camera modes wait while one is open (cameraPauseAtNPCs).
local NPC_WINDOWS = {
	"GossipFrame", "QuestFrame", "TaxiFrame", "ItemTextFrame",
}
for _, name in ipairs(REVEAL_AT_NPCS) do NPC_WINDOWS[#NPC_WINDOWS + 1] = name end
function ns.NPCWindowOpen()
	return AnyShown(NPC_WINDOWS)
end

-- Anything open that you'd want the mouse for: windows, the game menu, popups,
-- open dropdown menus.
local MOUSE_WINDOWS = { "GameMenuFrame", "StaticPopup1", "StaticPopup2", "StaticPopup3", "LootFrame",
	"ContainerFrame1", "ContainerFrameCombinedBags", "WorldMapFrame", "QuestLogFrame", "FriendsFrame" }
function ns.MouseWindowOpen()
	if AnyShown(REVEAL_WHILE_SHOWN) or AnyShown(NPC_WINDOWS) or AnyShown(MOUSE_WINDOWS) then
		return true
	end
	local manager = Menu and Menu.GetManager and Menu.GetManager()
	return manager and manager.GetOpenMenu and manager:GetOpenMenu() ~= nil or false
end

local function AnyRevealFrameShown()
	return (not ns.db.stayWithWindows and AnyShown(REVEAL_WHILE_SHOWN))
		or (ns.db.revealAtNPCs and AnyShown(REVEAL_AT_NPCS))
end

-- Unit queries can return "secret" values during combat, which can't even be
-- tested for truth. Treat those as false.
local function Flag(value)
	if issecretvalue and issecretvalue(value) then
		return false
	end
	return value and true or false
end

-- Flights "drop" the target: addons can't clear it (ClearTarget is protected),
-- so the target you had at takeoff is ignored until you pick a new one or land.
local targetDropped = false
local wasOnTaxiForTarget = false
local targetWatcher = CreateFrame("Frame")
targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
targetWatcher:SetScript("OnEvent", function() targetDropped = false end)

local function UpdateDroppedTarget()
	local onTaxi = UnitOnTaxi("player")
	if onTaxi ~= wasOnTaxiForTarget then
		wasOnTaxiForTarget = onTaxi
		targetDropped = onTaxi and ns.db.dropTargetOnFlights
	end
end

-- A target counts (exists and wasn't dropped at takeoff).
function ns.HasTarget()
	return not targetDropped and Flag(UnitExists("target"))
end

-- An enemy you could fight is targeted (a dead one doesn't count when
-- ignoreDeadTarget is on, e.g. targeting a corpse to loot it).
function ns.HasHostileTarget()
	if not (ns.HasTarget() and Flag(UnitCanAttack("player", "target"))) then
		return false
	end
	return not (ns.db.ignoreDeadTarget and Flag(UnitIsDeadOrGhost("target")))
end

-- Confirming that an item will bind (Bind on Equip and the like) holds the item
-- on the cursor until you answer; that isn't dragging something about.
local BIND_POPUPS = {
	"EQUIP_BIND", "AUTOEQUIP_BIND", "EQUIP_BIND_TRADEABLE", "EQUIP_BIND_REFUNDABLE",
	"USE_BIND", "CONFIRM_BINDER",
}
local function BindPopupShown()
	if not StaticPopup_FindVisible then
		return false
	end
	for _, which in ipairs(BIND_POPUPS) do
		local ok, shown = pcall(StaticPopup_FindVisible, which)
		if ok and shown then
			return true
		end
	end
	return false
end

-- Something on the cursor (dragging an item or spell to your bars, say).
local function CursorBusy()
	return ns.db.revealOnDrag and GetCursorInfo() ~= nil and not BindPopupShown()
end

local function IsBusy()
	local inCombat = InCombatLockdown() or Flag(UnitAffectingCombat("player"))
	if inCombat and not ns.db.stayInCombat then
		return true
	end
	local revealOnTarget = ns.db.revealOnTarget and not ns.db.stayInCombat
	return Flag(UnitIsDeadOrGhost("player"))
		or (revealOnTarget and ns.HasHostileTarget())
		or (ns.db.revealOnCast and (Flag(UnitCastingInfo("player")) or Flag(UnitChannelInfo("player"))))
		or CursorBusy()
		or AnyRevealFrameShown()
end

-- Places the player chose to keep the normal UI. Cities have no API of their
-- own, so they're detected as rest areas, which also covers inns. Flights
-- that leave from a city still go cinematic.
-- Capital cities, by zone (area) ID from Wowhead's Forever zone list. Names
-- are looked up from the IDs at login, so matching works in any language. IDs
-- this client doesn't have are skipped.
local CITY_AREA_IDS = {
	1519, 16509, -- Stormwind City
	1537,        -- Ironforge
	1657,        -- Darnassus
	1637,        -- Orgrimmar
	1638,        -- Thunder Bluff
	1497,        -- Undercity
	16544, 16560, -- City of Dalaran
}

function ns.IsInCity()
	if not ns.cityNames then
		ns.cityNames = {}
		for _, areaID in ipairs(CITY_AREA_IDS) do
			local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
			if name then
				ns.cityNames[name] = true
			end
		end
	end
	return ns.cityNames[GetRealZoneText() or ""] or false
end

-- What kind of place the player is in, for the per-place options: "city",
-- "dungeon", "raid", "pvp", "inn" (resting outside a capital) or nil. Cities
-- are checked first because Dalaran is an instance. A flight leaving a city or
-- inn doesn't count as being there.
function ns.GetPlaceType()
	local onTaxi = UnitOnTaxi("player")
	if ns.IsInCity() then
		return not onTaxi and "city" or nil
	end
	local inInstance, instanceType = IsInInstance()
	if inInstance then
		if instanceType == "party" or instanceType == "scenario" then
			return "dungeon"
		elseif instanceType == "raid" then
			return "raid"
		elseif instanceType == "pvp" or instanceType == "arena" then
			return "pvp"
		end
	end
	if IsResting() and not onTaxi then
		return "inn"
	end
end

local OFF_IN = {
	city = "offInCities", inn = "offInInns",
	dungeon = "offInDungeons", raid = "offInRaids", pvp = "offInPvP",
}
ns.CHAT_IN = {
	city = "chatInCities", inn = "chatInInns",
	dungeon = "chatInDungeons", raid = "chatInRaids", pvp = "chatInPvP",
}

local PLACE_SUFFIX = { city = "Cities", inn = "Inns", dungeon = "Dungeons", raid = "Raids", pvp = "PvP" }

-- Places where the standing-still rotation (rotOffIn*) or zoom (zoomOffIn*)
-- stays off. Flights never count as being in a place, so they're unaffected.
function ns.IsRotationBlocked()
	local place = ns.GetPlaceType()
	return place ~= nil and ns.db["rotOffIn" .. PLACE_SUFFIX[place]] or false
end

function ns.IsMusicBlocked()
	local place = ns.GetPlaceType()
	return place ~= nil and ns.db["musicOffIn" .. PLACE_SUFFIX[place]] or false
end

function ns.IsZoomBlocked()
	local place = ns.GetPlaceType()
	return place ~= nil and ns.db["zoomOffIn" .. PLACE_SUFFIX[place]] or false
end

local function IsInDisabledZone()
	local place = ns.GetPlaceType()
	return place ~= nil and ns.db[OFF_IN[place]] or false
end

-- "Turn off for a while" from the minimap menu. Session only: a reload or
-- logout clears it.
local snoozeUntil = 0

local function ShouldBeCinematic(now)
	if not ns.db.enabled or peeking or GetTime() < snoozeUntil or IsInDisabledZone() then
		lastBusy = now -- the full fade delay applies after leaving
		return false
	end
	if IsBusy() then
		lastBusy = now
		return false
	end
	local instant = (ns.db.taxiInstant and UnitOnTaxi("player")) or (ns.db.walkInstant and ns.IsRPWalking())
		or (ns.db.runInstant and ns.IsAutoRunning()) or (ns.db.cozyInstant and ns.IsCozy and ns.IsCozy())
	local delay = instant and 0 or ns.db.delay
	return now - lastBusy >= delay
end

function ns.ApplyCVarSet(set, want)
	if (set.active or false) == want then
		return
	end
	if set.secure and InCombatLockdown() then
		return -- try again once combat ends
	end
	set.active = want
	for cvar, value in pairs(set.values) do
		if want then
			local original = GetCVar(cvar)
			if original ~= nil then
				if ns.db.savedCVars[cvar] == nil then
					ns.db.savedCVars[cvar] = original
				end
				SetCVar(cvar, value)
			end
		elseif ns.db.savedCVars[cvar] ~= nil then
			SetCVar(cvar, ns.db.savedCVars[cvar])
			ns.db.savedCVars[cvar] = nil
		end
	end
end

-- Puts back anything left over from a session that ended without restoring.
-- (Ambience is left for Effects.lua to fade back smoothly instead.)
local function RestoreSavedCVars()
	for cvar, value in pairs(ns.db.savedCVars) do
		if cvar ~= "Sound_AmbienceVolume" and not (cvar:find("^nameplate") and InCombatLockdown()) then
			SetCVar(cvar, value)
			ns.db.savedCVars[cvar] = nil
		end
	end
end

function ns.Approach(current, target, elapsed, duration)
	local step = duration > 0 and elapsed / duration or 1
	if current < target then
		return math.min(target, current + step)
	end
	return math.max(target, current - step)
end

function ns.SaveCVar(cvar)
	if ns.db.savedCVars[cvar] == nil then
		ns.db.savedCVars[cvar] = GetCVar(cvar)
	end
end

function ns.RestoreCVar(cvar)
	local value = ns.db.savedCVars[cvar]
	if value ~= nil then
		SetCVar(cvar, value)
		ns.db.savedCVars[cvar] = nil
	end
end

local ticker = CreateFrame("Frame")
local accumulated = 0
local sinceScan = 0
local TICK = 0.03

-- The orbit changes camera speed continuously, so it runs every frame; on the
-- throttled tick its speed would change in visible steps.
ns.orbitFrame = CreateFrame("Frame")
local function OnOrbitUpdate(_, elapsed)
	ns.UpdateOrbit(ns.lastCinematic, elapsed)
end

-- Set at login when "start in cinematic mode" is on: the first cinematic tick
-- within this window snaps straight to cinematic. Expires so a busy login
-- (say, an enemy targeted) falls back to the normal fade later.
local START_SNAP_WINDOW = 5
local startSnapUntil = 0

local function OnUpdate(_, elapsed)
	accumulated = accumulated + elapsed
	if accumulated < TICK then
		return
	end
	elapsed, accumulated = accumulated, 0

	-- Some frames (like the damage meter) are created on demand, so keep looking.
	sinceScan = sinceScan + elapsed
	if sinceScan >= ns.SCAN_INTERVAL then
		sinceScan = 0
		ns.BuildManagedList()
		if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
	end

	UpdateDroppedTarget()
	local cinematic = ShouldBeCinematic(GetTime())
	if cinematic and GetTime() < startSnapUntil then
		-- Start in cinematic mode: hide the UI at once instead of fading. The
		-- letterbox bars still slide in at their usual pace.
		startSnapUntil = 0
		for _, entry in ipairs(ns.managed) do
			ns.SetEntryAlpha(entry, 0)
		end
	end
	ns.UpdateFrames(cinematic, elapsed)
	ns.UpdateLetterbox(cinematic, elapsed)
	ns.UpdateTint(cinematic, elapsed)
	ns.UpdateCVars(cinematic)
	ns.UpdateMusic(cinematic, elapsed)
	ns.UpdateAmbience(cinematic, elapsed)
	ns.UpdatePlates(cinematic, elapsed)
	ns.UpdateTooltip()
	if ns.UpdateCrackle then ns.UpdateCrackle(cinematic) end
	if ns.UpdateCursorTuck then ns.UpdateCursorTuck(cinematic) end
	ns.UpdateTaxi()
	ns.lastCinematic = cinematic
end

-- Global entry points for Bindings.xml
function ns.SetEnabled(enabled)
	ns.db.enabled = enabled
	lastBusy = GetTime()
end

function Cinematic_Toggle()
	ns.SetEnabled(not ns.db.enabled)
	ns.Print(ns.db.enabled and "enabled" or "disabled")
end

function Cinematic_Peek(down)
	peeking = down
	if not down then
		lastBusy = GetTime()
	end
end

local function EnsureTables()
	ns.db.extraFrames = ns.db.extraFrames or {}
	ns.db.ignoredFrames = ns.db.ignoredFrames or {}
	ns.db.savedCVars = ns.db.savedCVars or {}
	ns.db.chatPeekTypes = ns.db.chatPeekTypes or {}
	ns.db.chatPeekChannelList = ns.db.chatPeekChannelList or {}
	ns.db.flightTimes = ns.db.flightTimes or {}
	ns.db.zoneTints = ns.db.zoneTints or {} -- zone name -> "none", a mood key or { r, g, b }
	ns.db.zoneTintStrength = ns.db.zoneTintStrength or {} -- zone name -> strength (0-1) for the Zone presets
	ns.db.timePhaseColors = ns.db.timePhaseColors or {} -- "Night", "Dawn"... -> { r, g, b } of your own
	ns.db.timePhaseStrength = ns.db.timePhaseStrength or {} -- "Night", "Dawn"... -> strength (0-1) of your own
	ns.db.combatShow = ns.db.combatShow or {}
	ns.db.targetShow = ns.db.targetShow or {}
	-- The target list used to cover friend and foe alike; both new lists start from it.
	local function copy(source)
		local result = {}
		for k, v in pairs(source) do result[k] = v end
		return result
	end
	ns.db.enemyShow = ns.db.enemyShow or copy(ns.db.targetShow)
	ns.db.friendlyShow = ns.db.friendlyShow or copy(ns.db.targetShow)
end

-- Restores the tunable settings but keeps the player's added/ignored frames.
function ns.ResetSettings()
	for k, v in pairs(DEFAULTS) do ns.db[k] = v end
	lastBusy = GetTime()
	ns.letterboxDirty = true
end

-- Shared with Options.lua
ns.DEFAULTS = DEFAULTS

-- Your speed in yards per second, or nil when the game won't say (secret).
-- Walking is 2.5, running backwards 4.5, running 7.
local WALK_SPEED_MAX = 3.5
local AUTORUN_INFER_AFTER = 1 -- seconds of moving with no movement key held = auto-run
function ns.GetPlayerSpeed()
	local ok, speed = pcall(GetUnitSpeed, "player")
	if not ok or speed == nil or (issecretvalue and issecretvalue(speed)) then
		return nil
	end
	return speed
end

-- How long things stay up after a mouseover or a peek. In the camera modes
-- (flying, RP walking, standing still past the standing-still delay) these use
-- their default values instead of the player's, so a long hold set for normal
-- play doesn't keep the quest tracker (or chat, or buffs) up over the view.
local FLIGHT_USES_DEFAULT = {
	minimapHoverHold = true, questsHoverHold = true, buffPeekTime = true, chatPeekTime = true,
}

-- Flying, RP walking, or standing still past the standing-still delay.
local function InCameraMode()
	if UnitOnTaxi("player") then
		return true
	end
	if (ns.IsRPWalking and ns.IsRPWalking()) or (ns.IsAutoRunning and ns.IsAutoRunning()) then
		return true
	end
	local still = ns.GetStillSince()
	return still ~= nil and GetTime() - still >= ns.db.idleOrbitDelay
end

ns.InCameraMode = function() return InCameraMode() end

-- Which camera mode you're in: "flight", "walk", "run", "cozy", "idle", or nil.
function ns.CameraMode()
	if UnitOnTaxi("player") then
		return "flight"
	elseif ns.IsRPWalking and ns.IsRPWalking() then
		return "walk"
	elseif ns.IsAutoRunning and ns.IsAutoRunning() then
		return "run"
	elseif ns.IsCozy and ns.IsCozy() then
		return "cozy"
	end
	local still = ns.GetStillSince()
	if still ~= nil and GetTime() - still >= ns.db.idleOrbitDelay then
		return "idle"
	end
	return nil
end

function ns.HoldTime(key)
	if FLIGHT_USES_DEFAULT[key] and InCameraMode() then
		return math.min(DEFAULTS[key], ns.db[key])
	end
	return ns.db[key]
end
ns.GetDB = function() return ns.db end
ns.Snooze = function(seconds)
	snoozeUntil = GetTime() + seconds
end
ns.Unsnooze = function()
	snoozeUntil = 0
	lastBusy = GetTime()
end
-- Seconds left on a snooze (math.huge until logout), or nil if not snoozed.
ns.GetSnoozeLeft = function()
	local left = snoozeUntil - GetTime()
	return left > 0 and left or nil
end
ns.RefreshLetterbox = function() ns.letterboxDirty = true end
ns.GetStillSince = function() return ns.stillSince end
ns.Flag = Flag
ns.GetLetterbox = function() return ns.letterbox end
-- Keep a built-in frame visible, or let it fade again (re-added immediately).
ns.SetFrameKept = function(name, keep)
	if keep then
		ns.StopFading(name)
	else
		ns.UnignoreFrame(name)
		ns.BuildManagedList()
	end
end

ticker:RegisterEvent("ADDON_LOADED")
ticker:RegisterEvent("PLAYER_LOGIN")
ticker:RegisterEvent("PLAYER_REGEN_DISABLED")
ticker:RegisterEvent("PLAYER_LOGOUT")
ticker:RegisterEvent("PLAYER_ENTERING_WORLD")
ticker:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ticker:RegisterEvent("PLAYER_STARTED_MOVING")
ticker:RegisterEvent("PLAYER_LEVEL_UP")
ticker:RegisterEvent("PLAYER_STOPPED_MOVING")
ticker:SetScript("OnEvent", function(self, event, arg1, arg2)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		CinematicDB = CinematicDB or {}
		ns.db = CinematicDB
		-- Older settings: one vertical range for up and down, and a separate
		-- narrow behind mode (now behind mode with a 45 degree swing).
		local function MigrateProfile(prefix)
			local pitch = ns.db[prefix .. "Pitch"]
			if pitch ~= nil and ns.db[prefix .. "PitchUp"] == nil then
				ns.db[prefix .. "PitchUp"], ns.db[prefix .. "PitchDown"] = pitch, pitch
			end
			if ns.db[prefix .. "Mode"] == "backnarrow" then
				ns.db[prefix .. "Mode"], ns.db[prefix .. "BackArc"] = "back", 45
			end
		end
		MigrateProfile("taxiOrbit")
		-- Rotation settings used to be shared; start the standing-still profile
		-- from the player's existing (flight) values.
		for _, key in ipairs(ORBIT_PROFILE_KEYS) do
			if ns.db["idleOrbit" .. key] == nil then
				ns.db["idleOrbit" .. key] = ns.db["taxiOrbit" .. key]
			end
		end
		MigrateProfile("idleOrbit")
		-- Zoom settings used to be shared; start the flight ones from the player's values.
		for _, key in ipairs(ZOOM_PROFILE_KEYS) do
			if ns.db["taxiZoom" .. key] == nil then
				ns.db["taxiZoom" .. key] = ns.db["idleZoom" .. key]
			end
		end
		-- "Turn camera effects off in" used to cover rotation and zoom together.
		for _, suffix in ipairs({ "Cities", "Inns", "Dungeons", "Raids", "PvP" }) do
			local old = ns.db["camOffIn" .. suffix]
			if old ~= nil then
				if ns.db["rotOffIn" .. suffix] == nil then ns.db["rotOffIn" .. suffix] = old end
				if ns.db["zoomOffIn" .. suffix] == nil then ns.db["zoomOffIn" .. suffix] = old end
			end
		end
		-- An early walk camera saved other values for these; start from the
		-- current defaults once.
		if not ns.db.walkSettingsV2 then
			for k in pairs(DEFAULTS) do
				if k:find("^walkOrbit.") or k:find("^walkZoom.") or k == "walkInstant" then
					ns.db[k] = nil
				end
			end
			ns.db.walkSettingsV2 = true
		end
		-- The auto-run camera first swung wider; narrow it once, unless changed.
		if not ns.db.runSettingsV2 then
			if ns.db.runOrbitBackArc == 35 then ns.db.runOrbitBackArc = nil end
			if ns.db.runOrbitMinChange == 15 then ns.db.runOrbitMinChange = nil end
			if ns.db.runOrbitPitchUp == 8 then ns.db.runOrbitPitchUp = nil end
			if ns.db.runOrbitPitchDown == 8 then ns.db.runOrbitPitchDown = nil end
			ns.db.runSettingsV2 = true
		end
		-- "Cities and inns" used to be one setting; carry it over to inns.
		if ns.db.offInInns == nil then ns.db.offInInns = ns.db.offInCities end
		if ns.db.chatInInns == nil then ns.db.chatInInns = ns.db.chatInCities end
		-- The cozy zoom first pulled back further and came in less; update it
		-- once, unless changed.
		if not ns.db.cozySettingsV2 then
			if ns.db.cozyZoomDistance == 1 then ns.db.cozyZoomDistance = nil end
			if ns.db.cozyZoomIn == 2 then ns.db.cozyZoomIn = nil end
			ns.db.cozySettingsV2 = true
		end
		-- ...and its sway was wider and quicker, and its zoom worked from your
		-- own distance rather than a close-up.
		if ns.db.cozyLevel == 20 then ns.db.cozyLevel = nil end -- was tilting the wrong way
		-- The close-up was too tight (and a little too low); once, unless changed.
		if not ns.db.cozySettingsV4 then
			if ns.db.cozyZoomClose == 6 then ns.db.cozyZoomClose = nil end
			if ns.db.cozyLevel == 50 then ns.db.cozyLevel = nil end
			ns.db.cozySettingsV4 = true
		end
		-- Still too low (the ground pulled the camera in); once, unless changed.
		if not ns.db.cozySettingsV5 then
			if ns.db.cozyLevel == 40 then ns.db.cozyLevel = nil end
			ns.db.cozySettingsV5 = true
		end
		-- The cozy sway now reaches either side of your front (arriving at one
		-- side); its old narrow swing is updated once, unless changed.
		if not ns.db.cozySettingsV7 then
			if ns.db.cozyOrbitBackArc == 15 then ns.db.cozyOrbitBackArc = nil end
			ns.db.cozySettingsV7 = true
		end
		if not ns.db.runSettingsV6 then -- auto-run rises less (looks ahead more)
			if ns.db.runOrbitPitchUp == 10 then ns.db.runOrbitPitchUp = nil end
			ns.db.runSettingsV6 = true
		end
		if not ns.db.runSettingsV5 then -- auto-run zooms out further
			if ns.db.runZoomDistance == 5 or ns.db.runZoomDistance == 4 then ns.db.runZoomDistance = nil end
			ns.db.runSettingsV5 = true
		end
		if not ns.db.runSettingsV4 then -- livelier auto-run zoom and height changes
			for key, old in pairs({ runZoomPause = 4, runZoomTime = 10, runZoomDistance = 4, runZoomIn = 3,
				runOrbitPitchUp = 6, runOrbitPitchDown = 6, runOrbitMoveTime = 8, runOrbitPause = 4 }) do
				if ns.db[key] == old then ns.db[key] = nil end
			end
			ns.db.runSettingsV4 = true
		end
		if not ns.db.runSettingsV3 then -- auto-run's glide after a turn starts sooner
			if ns.db.runGlideDelay == 1.5 then ns.db.runGlideDelay = nil end
			ns.db.runSettingsV3 = true
		end
		if not ns.db.cozySettingsV8 then -- a slower sway
			if ns.db.cozyOrbitMoveTime == 12 then ns.db.cozyOrbitMoveTime = nil end
			ns.db.cozySettingsV8 = true
		end
		if not ns.db.cozySettingsV6 then -- a little higher again
			if ns.db.cozyLevel == 20 then ns.db.cozyLevel = nil end
			ns.db.cozySettingsV6 = true
		end
		if not ns.db.cozySettingsV3 then
			for key, old in pairs({ BackArc = 30, MinChange = 10, PitchUp = 8, PitchDown = 4,
				MoveTime = 9, DriftSpeed = 1 }) do
				if ns.db["cozyOrbit" .. key] == old then ns.db["cozyOrbit" .. key] = nil end
			end
			if ns.db.cozyZoomIn == 2 or ns.db.cozyZoomIn == 4 then ns.db.cozyZoomIn = nil end
			ns.db.cozySettingsV3 = true
		end
		-- The buff list used to start the standing-still camera; it's the cozy
		-- camera's now.
		if ns.db.idleBuffs ~= nil then
			ns.db.cozyBuffs = ns.db.idleBuffs
			if ns.db.idleAtCampfire ~= nil then ns.db.cozyBuffsOn = ns.db.idleAtCampfire end
			ns.db.idleBuffs, ns.db.idleAtCampfire = nil, nil
		end
		-- The cursor tuck used to be one switch.
		if ns.db.cursorTuck ~= nil then
			for _, suffix in ipairs({ "Flight", "Idle", "Cozy", "Walk", "Run", "Other" }) do
				ns.db["cursorTuck" .. suffix] = ns.db.cursorTuck
			end
			ns.db.cursorTuck = nil
		end
		-- World tooltips used to be one switch for every camera mode.
		if ns.db.tooltipOffInCameraModes ~= nil then
			for _, key in ipairs({ "tooltipOffFlight", "tooltipOffIdle", "tooltipOffCozy",
				"tooltipOffWalk", "tooltipOffRun" }) do
				ns.db[key] = ns.db.tooltipOffInCameraModes
			end
			ns.db.tooltipOffInCameraModes = nil
		end
		-- Settings from removed or renamed features, now that the migrations
		-- above have read what they need.
		for _, key in ipairs({
			"camOffInCities", "camOffInInns", "camOffInDungeons", "camOffInRaids", "camOffInPvP",
			"hideCursor", "hideCursorDelay", "innZoom", "innZoomDistance",
			"viewShift", "viewShiftAmount", "viewShiftRight", "zoneTitle", "zoneTitleSubzones",
			"taxiOrbitPitch", "idleOrbitPitch", "turnLog", "cozyPray", "cozyAngle",
		}) do
			ns.db[key] = nil
		end
		for k, v in pairs(DEFAULTS) do
			if ns.db[k] == nil then ns.db[k] = v end
		end
		EnsureTables()
		SLASH_CINEMATIC1 = "/cine"
		SLASH_CINEMATIC2 = "/cinematic"
		SlashCmdList.CINEMATIC = ns.HandleSlash
	elseif event == "PLAYER_LOGIN" then
		RestoreSavedCVars()
		ns.PruneBuiltInExtras()
		ns.wasOnTaxi = UnitOnTaxi("player") -- don't re-center after a /reload mid-flight
		ns.RegisterChatPeek()
		ns.HookCameraInput()
		-- Walk mode: there's no "am I walking" API, so the walk/run toggle is
		-- followed (you log in running), and corrected from your actual speed
		-- whenever you move and the speed can be read (it's secret at times).
		ns.walking = false
		ns.IsRPWalking = function()
			if not ns.playerMoving then
				return false
			end
			local speed = ns.GetPlayerSpeed()
			if speed and speed > 0 then
				ns.walking = speed < WALK_SPEED_MAX
				ns.walkingFromSpeed = true
			else
				ns.walkingFromSpeed = false
			end
			return ns.walking
		end
		if ToggleRun then
			hooksecurefunc("ToggleRun", function() ns.walking = not ns.walking end)
		end
		-- Auto-run: no "am I auto-running" API either, so follow the auto-run key
		-- and the things that end it (forward/back, stopping, a flight).
		ns.autoRunning = false
		-- Also worked out from what you're doing, for when the key was missed
		-- (say, a /reload mid-auto-run): moving for a moment with no movement key
		-- held and not steering with both mouse buttons can only be auto-run.
		local movementKeys = {}
		local function AnyMovementKey()
			for _, held in pairs(movementKeys) do
				if held then return true end
			end
			return IsMouseButtonDown("LeftButton") and IsMouseButtonDown("RightButton")
		end
		ns.IsAutoRunning = function()
			if not ns.playerMoving or UnitOnTaxi("player") then
				return false
			end
			if not ns.autoRunning and GetTime() - (ns.movingSince or GetTime()) > AUTORUN_INFER_AFTER
				and not AnyMovementKey() then
				ns.autoRunning = true
			end
			return ns.autoRunning and not ns.IsRPWalking()
		end
		local function Hook(name, fn)
			if _G[name] then hooksecurefunc(name, fn) end
		end
		for _, key in ipairs({ "MoveForward", "MoveBackward", "StrafeLeft", "StrafeRight", "MoveAndSteer" }) do
			Hook(key .. "Start", function() movementKeys[key] = true end)
			Hook(key .. "Stop", function() movementKeys[key] = false end)
		end
		-- The toggle: if it's on and you're moving, you're stopping it; any other
		-- press starts it. (A plain flip could get out of step for good if an
		-- auto-run ever ended unseen.)
		Hook("ToggleAutoRun", function()
			ns.autoRunning = not (ns.autoRunning and ns.playerMoving)
		end)
		Hook("StartAutoRun", function() ns.autoRunning = true end)
		Hook("StopAutoRun", function() ns.autoRunning = false end)
		Hook("MoveForwardStart", function() ns.autoRunning = false end)
		Hook("MoveBackwardStart", function() ns.autoRunning = false end)
		ns.HookTaxiRoutes()
		GameTooltip:HookScript("OnShow", ns.OnTooltipShow)
		-- The minimap button first, so the fade list picks it up straight away
		-- (otherwise it stays visible until the next scan).
		if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
		ns.BuildManagedList()
		ns.CreateLetterbox()
		ns.CreateTint()
		lastBusy = GetTime()
		self:SetScript("OnUpdate", OnUpdate)
		ns.orbitFrame:SetScript("OnUpdate", OnOrbitUpdate)
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Movement is only reported as it starts and stops, so after a login or
		-- /reload already on the move, check your speed instead.
		local function CheckMoving()
			local speed = ns.GetPlayerSpeed()
			if speed and speed > 0 and not UnitOnTaxi("player") and not ns.playerMoving then
				ns.playerMoving = true
				ns.movingSince = GetTime() - 5 -- (long enough to count as auto-run if no key's held)
			end
		end
		CheckMoving()
		C_Timer.After(1, CheckMoving) -- (the speed can read 0 for a moment while loading)
		-- arg1 is isInitialLogin (a real login), arg2 isReloadingUi (a /reload).
		-- Other loading screens never start straight in cinematic mode.
		if (arg1 or arg2) and ns.db.timeOfDayMessage then
			ns.ShowTimeOfDayTitle()
		end
		if (arg1 and ns.db.startCinematic) or (arg2 and ns.db.startCinematicOnReload) then
			lastBusy = GetTime() - ns.db.delay -- skip the fade delay
			startSnapUntil = GetTime() + START_SNAP_WINDOW
		end
	elseif event == "PLAYER_LOGOUT" then
		-- Put the player's music/name/nameplate settings back before they're saved.
		ns.UpdateCVars(false)
		ns.StopIdleZoomNow()
		ns.StopMusicNow()
		ns.StopCombatMusicNow()
		-- Ambience is deliberately left as is: it can't fade during a reload, so the
		-- reloaded addon picks it up and carries on smoothly (see Effects.lua).
		ns.ShowPlatesNow()
		ns.StopOrbitNow()
		ns.ApplyCVarSet(ns.FLIGHT_CVARS, false)
		ns.ApplyCVarSet(ns.RECENTER_CVARS, false)
		if ns.db.musicOffOnLogout then
			SetCVar("Sound_EnableMusic", 0)
		end
	elseif event == "PLAYER_LEVEL_UP" then
		ns.levelUpUntil = GetTime() + ns.LEVEL_UP_WINDOW
	elseif event == "PLAYER_STARTED_MOVING" then
		ns.playerMoving = true
		ns.movingSince = GetTime()
	elseif event == "PLAYER_STOPPED_MOVING" then
		ns.playerMoving = false
		ns.autoRunning = false -- auto-run ends when you stop
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		-- New plates start fully visible; match them to the current fade.
		if ns.plates.level < 1 and C_NamePlate then
			ns.SetPlateAlpha(C_NamePlate.GetNamePlateForUnit(arg1), ns.plates.level)
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Snap back instantly when a fight starts rather than waiting for a tick.
		-- This fires just before combat lockdown starts, which is the last chance
		-- to restore nameplate settings until the fight ends.
		ns.ShowPlatesNow()
		ns.StopOrbitNow()
		if not ns.db.stayInCombat then
			lastBusy = GetTime()
			ns.UpdateCVars(false)
			for _, entry in ipairs(ns.managed) do
				ns.SetEntryAlpha(entry, 1)
			end
		end
	end
end)
