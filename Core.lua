-- Cinematic: fades the UI out between fights and slides in letterbox bars.
--
-- Only SetAlpha is used on Blizzard frames (never Show/Hide), so it is safe
-- to touch protected frames like action bars even during combat lockdown.

local ADDON_NAME, ns = ...

-- Retail (the main game) rather than a Classic client such as WoW Forever.
-- Most differences are handled by checking whether an API or frame exists;
-- this is for the few that differ by design (data files, retail-only options).
ns.isRetail = WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

BINDING_HEADER_CINEMATIC = "Cinematic"
BINDING_NAME_CINEMATIC_TOGGLE = "Cinematic: Toggle cinematic mode"
BINDING_NAME_CINEMATIC_PEEK = "Cinematic: Peek at UI (hold)"
BINDING_NAME_CINEMATIC_HIDEUI = "Cinematic: Hide the UI (keep the look)"
BINDING_NAME_CINEMATIC_FLYBY = "Cinematic: Fly-by (turn round to look back)"
BINDING_NAME_CINEMATIC_CAM_IDLE = "Cinematic: Start the AFK camera"
BINDING_NAME_CINEMATIC_CAM_COZY = "Cinematic: Start the cozy camera"
BINDING_NAME_CINEMATIC_CAM_VISTA = "Cinematic: Start the vista camera"
BINDING_NAME_CINEMATIC_CAM_FISH = "Cinematic: Start the fish camera"
BINDING_NAME_CINEMATIC_CAM_DEATH = "Cinematic: Test the death camera"

local DEFAULTS = {
	enabled = true,
	minimapButton = true,     -- show the minimap button
	minimapAngle = 225,       -- its position around the minimap, in degrees
	startCinematic = true,   -- be in cinematic mode straight away on login, /reload and turning it on
	-- Hide world tooltips in each camera mode:
	tooltipOffFlight = true,
	tooltipOffIdle = true,    -- standing still
	tooltipOffCozy = true,
	tooltipOffVista = true,   -- /stare
	tooltipOffFish = true,    -- fishing
	tooltipOffWalk = true,    -- RP walking
	tooltipOffRun = true,      -- auto-running
	hideCombatText = true,    -- no floating combat text (heals, regen) in cinematic mode out of combat
	timeOfDayMessage = true,  -- "Dusk" under the zone name on login and /reload, and when it
	                          -- changes, with a fitting sound (rooster, bells, frogs, owl, wolf)
	offInDungeons = true,     -- no cinematic mode in dungeons (and scenarios)
	offInRaids = true,
	offInPvP = true,          -- battlegrounds and arenas
	offInCities = false,      -- capital cities
	offInInns = false,        -- inns (resting outside a capital)
	offInParty = false,       -- while in a party (not a raid group)
	offInRaidGroup = false,   -- while in a raid group
	delay = 15,            -- seconds of calm before fading out
	fadeOutTime = 1.5,
	fadeInTime = 0.5,
	letterbox = true,
	letterboxSize = 0.03,  -- fraction of screen height per bar
	letterboxAlpha = 1,    -- bar opacity
	tintPreset = "zonetime",   -- screen tint over the game world (see TINT_PRESETS)
	tintStrength = 1,
	tintCustomR = 1, tintCustomG = 0.8, tintCustomB = 0.6,
	tintDrift = true,      -- tint strength slowly wanders up and down over a few minutes
	tintDriftAmount = 0.08, -- how far it wanders, as a fraction of the strength (0.08 = +/-8%)
	vignette = true,      -- darkened screen edges
	vignetteStrength = 0.1,
	innGlow = true,        -- indoors in an inn: lift the outdoor tint and add a warm glow
	innGlowAmount = 0.02,  -- light the inn glow adds at its brightest (0.1 = 10%)
	weatherTint = true,    -- rain, snow and sandstorms grey or colour the scene (clients with C_Weather)
	weatherTintStrength = 0.6,
	tintWhen = "always",   -- "always", "flight" or "idle" (standing still past the standing-still delay)
	tintClock = "game",    -- time-of-day tint follows "game" (realm) time or "local" (computer) time
	timeTintStrength = 0.5,-- how strongly the time-of-day colour applies (both time presets)
	tintPreviewHour = -1,  -- options-page preview of the time-of-day tint at this hour (-1 = now)
	fadeChat = true,
	alwaysShowMinimap = false, -- keep the whole minimap group visible in cinematic mode
	alwaysShowWaypoint = false, -- keep retail's quest waypoint visible in cinematic mode
	minimapForTracking = true, -- master switch for the minimapFor* tracking options below
	minimapForHerbs = true,    -- keep the minimap visible while this tracking is active
	minimapForMinerals = true,
	minimapForTreasure = true,
	minimapForFish = true,
	minimapForCreatures = false,
	trackingHideWhenIdle = true, -- ...except once the standing-still timer has run, or on flights
	stayInCombat = true,  -- stay cinematic in combat and when targeting enemies
	combatFadeInTime = 1,    -- how fast the "while fighting, show" frames appear
	combatFadeOutTime = 5, -- and how fast they go once the fight is over
	enemyFadeInTime = 1,     -- targeting an enemy out of combat: fade times for its frame list
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
	buffPeekAfterCombat = true,  -- ...but only within buffPeekCombatWindow seconds of combat
	buffPeekCombatWindow = 60,
	buffPeekTime = 2.5,         -- seconds they stay up
	buffPeekIgnore = "2479, Plainsrunning, 8326, 20584", -- buffs or debuffs that never bring them up
	                                                    -- (spell IDs or names; 8326/20584: Ghost)
	mouseover = true,      -- hovering a faded element reveals it
	mouseoverHold = 3,     -- seconds a group stays after the mouse leaves it (per-group overrides below)
	musicInCinematic = true,  -- turn game music on while cinematic, off after
	musicOffOnLogout = true,  -- turn game music off when logging out
	hideNames = true,         -- hide unit names while cinematic
	hidePlates = true,        -- hide nameplates while cinematic
	plateShowMobs = true,     -- nameplates for hostile and neutral mobs (off hides them everywhere)
	plateShowNPCs = true,     -- ...for friendly NPCs (when the game's friendly NPC plates are on)
	plateShowOwn = true,      -- ...for players of your own faction
	plateShowOther = true,    -- ...for players of the other faction
	plateShowPets = true,     -- ...for pets, minions and guardians
	plateShowTotems = true,   -- ...for totems
	plateAlwaysTarget = false, -- your target's nameplate always shows, whatever the rows below say
	plateCombatMobs = false,  -- show these during fights (off: hidden while you're in combat)
	plateCombatNPCs = false,
	plateCombatOwn = false,
	plateCombatOther = false,
	plateCombatPets = false,
	plateCombatTotems = false,
	plateCinematicMobs = false, -- keep these showing in cinematic mode despite hidePlates
	plateCinematicNPCs = false,
	plateCinematicOwn = false,
	plateCinematicOther = false,
	plateCinematicPets = false,
	plateCinematicTotems = false,
	nameKeepMobs = false,     -- keep these names up in cinematic mode despite hideNames
	nameKeepNPCs = false,
	nameKeepOwn = false,
	nameKeepOther = false,
	nameKeepPets = false,
	nameKeepMinions = false,  -- minions and guardians
	nameKeepTotems = false,
	nameKeepSelf = false,     -- your own name
	nameIconMobs = false,     -- in cinematic mode, an icon in place of these names
	nameIconNPCs = false,
	nameIconOwn = false,
	nameIconOther = true,
	nameIconPets = true,      -- pets, minions and guardians (they share a nameplate kind)
	nameIconTotems = false,
	nameIconPvPMobs = false,  -- ...only on units flagged for PvP
	nameIconPvPNPCs = false,
	nameIconPvPOwn = true,
	nameIconPvPOther = true,
	nameIconPvPPets = false,
	nameIconPvPTotems = false,
	fadeTooltip = true,       -- hide tooltips for units/objects in the world
	tooltipReveal = true,     -- a hidden world tooltip comes back after hovering the same thing...
	tooltipRevealDelay = 1,   -- ...for this many seconds
	tooltipFadeTime = 0.5,    -- seconds it takes to fade in, and out again
	musicFadeTime = 5,        -- seconds for music to fade in or out
	musicFatigue = 5,         -- minutes: don't start music again within this long of the last start
	-- Play music with each camera: a fresh song as it starts, even within the fatigue time.
	musicCamFlight = true,
	musicCamIdle = true,      -- AFK camera
	musicCamCozy = true,
	musicCamVista = true,
	musicCamFish = true,
	musicCamWalk = true,      -- RP walk
	musicCamRun = true,       -- auto-run
	musicPauseWhenMoving = true,  -- music fades out once you move on from flying, RP walking or standing still
	musicPauseOnLanding = true,   -- ...and as soon as a flight lands, without waiting for you to move
	musicPauseFadeTime = 3,      -- seconds that pause takes to fade out (and the music to come back)
	fatigueIgnoreNewZone = true,   -- start music anyway in a different zone from the last music
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
	taxiFlyBy = true,         -- random fly-bys in the middle of flights
	taxiFlyByEvery = 60,      -- ...about one per this many seconds of...
	taxiFlyByFrom = 25,       -- ...the stretch between these % of the way
	taxiFlyByTo = 75,
	taxiLandZoom = true,      -- put the zoom back to your takeoff distance on landing
	flyByLook = false,        -- /look as each fly-by starts (off for now: under suspicion for a snap)
	flyByAngle = 160,         -- fly-by: degrees round from behind you
	flyByTurnTime = 8,        -- ...seconds to turn round
	flyByHold = 5,            -- ...seconds looking back
	flyByBackTime = 6,        -- ...seconds to turn back
	taxiOrbit = true,         -- slowly rotate the camera while on a flight path
	taxiSettle = true,        -- swing the camera behind the character before landing
	taxiSettleLead = 5,       -- seconds before the expected landing the camera is locked behind you
	zoneFadeTime = 3,         -- seconds a zone tint fades out (and the next fades in) at a border
	zoneGapTime = 1.5,        -- seconds untinted between zone tints on the ground
	zoneGapFlying = 6,        -- ...and in the air
	idleOrbit = true,         -- also rotate it after standing still for a while
	idleOrbitDelay = 30,      -- seconds of standing still before it starts
	-- Cozy camera: swings round to face you and sways in front, when an event
	-- picks it (Events page: ns.EVENTS in Camera.lua has their defaults).
	cozyOrbit = true,         -- sway in front of you
	cozyZoom = true,          -- with a close, gentle zoom
	cozyBuffs = "Welcoming Campfire", -- the campfire event's buffs: names or spell IDs, comma-separated
	cozyChairWords = "chair, bench, stool, seat, throne, pew", -- the chair event: words in a seat's name
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
	taxiInputPause = 15,      -- seconds the flight camera waits after the player moves the camera
	idleInputPause = 15,      -- ...and the AFK camera
	cameraPauseAtNPCs = true, -- no standing-still camera while an NPC window (auction house...) is open
	cameraPauseCasting = true, -- ...or while you're casting (crafting, say)
	cameraPauseInMenus = true, -- ...or while a menu or game window (spellbook, options...) is open
	-- Quest cam (eventQuestCamera on the Events page): talking to a quest giver, zoom in and swing behind you
	questCamDistance = 4,     -- ...yards it zooms in to (if you're further out)
	questCamTime = 3,         -- ...seconds the swing behind you takes
	questCamZoomTime = 7,     -- ...seconds the zoom in takes (the side turn and tilt finish with it)
	questCamZoomOutTime = 1.5, -- ...seconds the zoom back out takes, leaving
	questCamAngle = 30,       -- ...degrees the camera comes round to one side of behind you (0: straight behind)
	questCamSide = "random",  -- ...to a side picked at random each time, or "left" or "right"
	questCamTurnTime = 4,     -- ...seconds that turn takes (once the zoom's done)
	questCamLower = 0,        -- ...degrees the camera comes down, toward eye level (0: keep your angle)
	questCamOverShoulder = false, -- ...and move over your shoulder (a Blizzard experimental camera setting: off by default)
	questCamShoulder = 1,     -- ...yards the camera moves right, over your shoulder
	questCamUncenter = false, -- ...turn the game's Keep Character Centered off meanwhile (it blocks the shoulder)
	questCamAllGossip = false, -- ...for every NPC you talk to, not just quest givers
	indoorLimits = true,      -- indoors, keep the camera modes from pushing into walls:
	indoorZoomOut = 1,        -- ...zoom out at most this many yards past your own distance
	indoorSwing = 10,         -- ...swing at most this far either side of behind
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

-- The groups of faded frames, in the order the options list them. Each can
-- override the mouseover hold time: <group>HoverOverride and <group>HoverHold.
ns.HOVER_GROUPS = {
	{ "bars", "Action bars" }, { "sidebars", "Side action bars" }, { "player", "Player" },
	{ "target", "Target and focus" }, { "buffs", "Buffs" }, { "minimap", "Minimap" },
	{ "quests", "Quest tracker" }, { "chat", "Chat" }, { "totems", "Totems" },
	{ "swing", "Swing timer" }, { "meters", "Damage meter" }, { "misc", "Other" },
}
-- The minimap and quest tracker linger by default; the rest follow mouseoverHold.
local HOVER_HOLD_DEFAULTS = { minimap = 5, quests = 5 }
for _, group in ipairs(ns.HOVER_GROUPS) do
	local key = group[1]
	DEFAULTS[key .. "HoverOverride"] = HOVER_HOLD_DEFAULTS[key] ~= nil
	DEFAULTS[key .. "HoverHold"] = HOVER_HOLD_DEFAULTS[key] or 5
end
DEFAULTS.idleOrbitBackArc = 45
DEFAULTS.idleOrbitDrift = true
DEFAULTS.idleOrbitDriftSpeed = 1
DEFAULTS.idleOrbitMoveTime = 10
DEFAULTS.idleOrbitPause = 20
DEFAULTS.idleOrbitPitchDown = 10
DEFAULTS.idleOrbitPitchUp = 10
DEFAULTS.idleOrbitStep = 40
DEFAULTS.idleOrbitRandomDir = true -- pick clockwise or not afresh each time it starts
DEFAULTS.debugCameraMode = false   -- print each camera mode change to chat
DEFAULTS.debugFlyBy = false        -- print each fly-by's plan, start and end (/cine debug flybys)
DEFAULTS.logDetail = false         -- also log game setting saves and restores, and music (/cine debug record)
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
-- Vista camera (/stare, by default). Lines up behind you and sways there like
-- the RP walk camera, only gentler: slower moves, longer pauses and a softer drift.
DEFAULTS.vistaOrbit = true         -- sway the camera behind you
DEFAULTS.vistaZoom = true          -- and drift the zoom gently in and out
DEFAULTS.vistaInputPause = 2       -- seconds after you move the camera before it carries on
DEFAULTS.vistaLevel = 5            -- degrees it brings the camera down toward the ground
for key, value in pairs({
	Mode = "back", Right = false, Step = 30, Speed = 4, MinChange = 10,
	PitchUp = 5, PitchDown = 3, BackArc = 30, MoveTime = 14, Ease = 0.5,
	Pause = 8, Drift = true, DriftSpeed = 0.5,
}) do
	DEFAULTS["vistaOrbit" .. key] = value
end
for key, value in pairs({
	Distance = 4, In = 2, Time = 16, Pause = 8, Random = true, Ease = 0.5, PastMax = true,
}) do
	DEFAULTS["vistaZoom" .. key] = value
end
-- Fish camera (casting Fishing, by default): the vista camera's settings, with
-- a narrower, calmer sway either side of behind you (so the bobber stays in view).
DEFAULTS.fishOrbit = true
DEFAULTS.fishZoom = true
DEFAULTS.fishInputPause = DEFAULTS.vistaInputPause
DEFAULTS.fishLevel = DEFAULTS.vistaLevel
DEFAULTS.fishRightClickCast = true  -- right-click casts Fishing again while the fish camera is on
DEFAULTS.fishRecastDelay = 0.3     --...seconds after a cast ends before it does
DEFAULTS.fishPoleRightClickCast = true -- ...and for the first cast, with a fishing pole equipped
DEFAULTS.fishMissPause = 30        -- ...seconds it stands aside after a cast misses the water
DEFAULTS.hideFishingCastBar = true -- no cast bar while it shows Fishing (other spells still show it)
for _, key in ipairs({ "Mode", "Right", "Step", "Speed", "MinChange", "PitchUp", "PitchDown", "BackArc",
	"MoveTime", "Ease", "Pause", "Drift", "DriftSpeed" }) do
	DEFAULTS["fishOrbit" .. key] = DEFAULTS["vistaOrbit" .. key]
end
DEFAULTS.fishOrbitBackArc = 12     -- (vista: 30)
DEFAULTS.fishOrbitMinChange = 4    -- (vista: 10)
DEFAULTS.fishOrbitDriftSpeed = 0.3 -- (vista: 0.5)
for _, key in ipairs({ "Distance", "In", "Time", "Pause", "Random", "Ease", "PastMax" }) do
	DEFAULTS["fishZoom" .. key] = DEFAULTS["vistaZoom" .. key]
end
-- Death camera: a slow, steady turn round your body while you're dead.
DEFAULTS.deathOrbit = true         -- turn the camera slowly while dead (until you release)
DEFAULTS.deathOrbitDelay = 0       -- seconds after dying before it starts (0: the rise
                                   -- goes with your fall, which hides the snap the game
                                   -- gives a tilt starting on a dead character)
DEFAULTS.deathOrbitSpeed = 5       -- degrees per second
DEFAULTS.deathOrbitRight = false   -- turn clockwise instead
DEFAULTS.deathOrbitRandomDir = false -- pick clockwise or not afresh each death
DEFAULTS.deathLevel = 30           -- degrees it raises the camera to look down on you
DEFAULTS.deathSong = true          -- play a song of its own meanwhile
-- Music file IDs, comma-separated; one is picked at random each death:
-- GhostMusic03 (the ghost world's music), Gloomy02, Haunted02, Haunted01,
-- Mystery01, Undercity01, KelThuzad1A.
DEFAULTS.deathSongFiles = "53519, 53232, 53235, 53234, 53240, 53216, 53602"
DEFAULTS.deathOffInCities = false  -- no death camera in these places
DEFAULTS.deathOffInInns = false
DEFAULTS.deathOffInDungeons = false
DEFAULTS.deathOffInRaids = false
DEFAULTS.deathOffInPvP = true
DEFAULTS.deathScreen = true        -- dim, cold screen with a heavy vignette meanwhile
DEFAULTS.deathScreenStrength = 1
DEFAULTS.deathZoom = 4             -- yards it pulls back meanwhile
DEFAULTS.deathOrbitPause = 0       -- (always one continuous turn)
-- Auto-run camera: like RP walk, while auto-running (runOrbit*, runZoom*).
DEFAULTS.runOrbit = true
DEFAULTS.runZoom = true
DEFAULTS.runInstant = true
DEFAULTS.runInputPause = 2
DEFAULTS.runSwingBehind = true
DEFAULTS.runGlideDelay = 0.5
for key, value in pairs({
	Mode = "back", Right = false, Step = 30, Speed = 4, MinChange = 6,
	PitchUp = 3, PitchDown = 10, PitchFloor = 10, BackArc = 15, MoveTime = 6, Ease = 0.5,
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
-- Seconds after a fight before each camera mode may start (0: no wait).
DEFAULTS.taxiCombatWait = 0
DEFAULTS.idleCombatWait = 0
DEFAULTS.walkCombatWait = 15
DEFAULTS.runCombatWait = 30
DEFAULTS.cozyCombatWait = 30
DEFAULTS.vistaCombatWait = 0
DEFAULTS.fishCombatWait = 0
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
DEFAULTS.taxiZoomPause = 7
-- Seconds the pause between random zooms may run over or under <prefix>Pause.
for _, prefix in ipairs({ "idleZoom", "taxiZoom", "walkZoom", "runZoom", "cozyZoom", "vistaZoom", "fishZoom" }) do
	DEFAULTS[prefix .. "PauseVary"] = 0
end
DEFAULTS.taxiZoomPauseVary = 3
-- Depth of field (faked): a soft haze round the screen edges in the camera
-- modes. One switch for all, then a strength per mode (0 is off there).
DEFAULTS.depthOfField = true
DEFAULTS.dofIdle = 0.025
DEFAULTS.dofCozy = 0.025
DEFAULTS.dofVista = 0.025
DEFAULTS.dofFish = 0.025
DEFAULTS.dofFlight = 0.025
DEFAULTS.dofWalk = 0
DEFAULTS.dofRun = 0

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
	ns.Log("chat", msg)
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

-- Menus and game windows (the Escape menu, options, spellbook, character
-- sheet, map...). The camera modes wait while one is open (cameraPauseInMenus).
local MENU_WINDOWS = {
	"GameMenuFrame", "WorldMapFrame", "QuestLogFrame", "FriendsFrame", "PVEFrame",
	"CollectionsJournal", "EncounterJournal", "AchievementFrame", "CommunitiesFrame",
	"ProfessionsFrame", "TradeSkillFrame", "CraftFrame", "AddonList", "ChatConfigFrame",
	"VideoOptionsFrame",
}
for _, name in ipairs(REVEAL_WHILE_SHOWN) do MENU_WINDOWS[#MENU_WINDOWS + 1] = name end
function ns.MenuWindowOpen()
	return AnyShown(MENU_WINDOWS)
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
	-- Targeting never brings the whole UI back; it shows the Combat page's
	-- target lists instead (see GetCombatShownFrames).
	-- Dead: the UI comes back, unless the death camera is watching (then the
	-- release button, a popup, shows anyway). A ghost keeps cinematic mode as
	-- usual: the corpse run is just travel (Return to Graveyard isn't faded).
	local corpse = Flag(UnitIsDead("player")) and not Flag(UnitIsGhost("player"))
	return (corpse and not (ns.IsDeathCinematic and ns.IsDeathCinematic()))
		or (ns.db.revealOnCast and (Flag(UnitCastingInfo("player")) or Flag(UnitChannelInfo("player")))
			and not (ns.IsFishingEvent and ns.IsFishingEvent()))
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
	-- Retail
	15969,       -- Silvermoon City
	3557,        -- The Exodar
	3703,        -- Shattrath City
	4395, 7502,  -- Dalaran (Northrend, Broken Isles)
	8568, 8670,  -- Boralus, Dazar'alor
	10565,       -- Oribos
	13862,       -- Valdrakken
	14771,       -- Dornogal
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

function ns.IsDeathCameraBlocked()
	local place = ns.GetPlaceType()
	return place ~= nil and ns.db["deathOffIn" .. PLACE_SUFFIX[place]] or false
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

-- "Turn off in" a party or raid group: who you're with, not where you are.
local function IsInDisabledGroup()
	if IsInRaid() then
		return ns.db.offInRaidGroup
	end
	return IsInGroup() and ns.db.offInParty
end

-- "Turn off for a while" from the minimap menu. Session only: a reload or
-- logout clears it.
local snoozeUntil = 0

local function ShouldBeCinematic(now)
	if not ns.db.enabled or peeking or GetTime() < snoozeUntil or IsInDisabledZone()
		or IsInDisabledGroup() then
		lastBusy = now -- the full fade delay applies after leaving
		return false
	end
	if IsBusy() then
		lastBusy = now
		return false
	end
	-- Flights: right away with the option on, or as the flight event's delay ends.
	local instant = (ns.FlightStarted and ns.FlightStarted() and (ns.db.taxiInstant or ns.db.eventFlightDelay))
		or (ns.db.walkInstant and ns.IsRPWalking())
		or (ns.db.runInstant and ns.IsAutoRunning())
		or (ns.ActiveEvent and ns.ActiveEvent())
		or (ns.IsDeathCinematic and ns.IsDeathCinematic())
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
				ns.LogDetail("cvar", ("%s %s -> %s"):format(cvar, tostring(original), tostring(value)))
				SetCVar(cvar, value)
			end
		elseif ns.db.savedCVars[cvar] ~= nil then
			ns.LogDetail("cvar", ("%s back to %s"):format(cvar, tostring(ns.db.savedCVars[cvar])))
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
			-- Skip values that are already right: writing a test_ CVar at all
			-- brings up Blizzard's experimental-camera warning.
			local now = GetCVar(cvar)
			local same = now == value or (tonumber(now) ~= nil and tonumber(now) == tonumber(value))
			if not same then
				ns.Log("cvar", ("%s put back to %s (left over)"):format(cvar, tostring(value)))
				SetCVar(cvar, value)
			end
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
		ns.LogDetail("cvar", ("%s saved (%s)"):format(cvar, tostring(ns.db.savedCVars[cvar])))
	end
end

function ns.RestoreCVar(cvar)
	local value = ns.db.savedCVars[cvar]
	if value ~= nil then
		ns.LogDetail("cvar", ("%s back to %s"):format(cvar, tostring(value)))
		SetCVar(cvar, value)
		ns.db.savedCVars[cvar] = nil
	end
end

local ticker = CreateFrame("Frame")
local accumulated = 0
local sinceScan = 0
local TICK = 0.03

-- Each step of the update runs protected: an error in one (the music, say)
-- is logged and the rest carry on, and one that keeps repeating stops the
-- addon for the session (see ns.ReportError in Diagnostics.lua).
local stepFn, stepA, stepB, stepStack
local function RunStep()
	return stepFn(stepA, stepB)
end
local function StepHandler(err)
	stepStack = debugstack(2)
	return err
end
local function Step(fn, a, b)
	if ns.IsSuspended() then
		return nil -- stopped by an earlier step this tick: leave the rest
	end
	stepFn, stepA, stepB = fn, a, b
	local ok, result = xpcall(RunStep, StepHandler)
	stepFn, stepA, stepB = nil, nil, nil
	if not ok then
		ns.ReportError(result, stepStack, true)
		return nil
	end
	return result
end

-- The orbit changes camera speed continuously, so it runs every frame; on the
-- throttled tick its speed would change in visible steps.
ns.orbitFrame = CreateFrame("Frame")
local function OnOrbitUpdate(_, elapsed)
	Step(ns.UpdateOrbit, ns.lastCinematic, elapsed)
end

-- Set at login (and on turning it on) when "start in cinematic mode" is on: the first cinematic tick
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

	-- A stop that came mid-glide (see PLAYER_STOPPED_MOVING): once the glide
	-- ends, stop for real if you're not moving any more.
	if ns.stopWhileGliding and not ns.GlidingSpeed() then
		ns.stopWhileGliding = nil
		if IsPlayerMoving and not IsPlayerMoving() then
			ns.playerMoving = false
			ns.autoRunning = false
		end
	end

	-- Some frames (like the damage meter) are created on demand, so keep looking.
	sinceScan = sinceScan + elapsed
	if sinceScan >= ns.SCAN_INTERVAL then
		sinceScan = 0
		Step(ns.BuildManagedList)
		if ns.UpdateMinimapButton then Step(ns.UpdateMinimapButton) end
	end

	Step(UpdateDroppedTarget)
	local cinematic = Step(ShouldBeCinematic, GetTime()) or false -- (an error: the normal UI)
	if cinematic and GetTime() < startSnapUntil then
		-- Start in cinematic mode: hide the UI at once instead of fading. The
		-- letterbox bars still slide in at their usual pace.
		startSnapUntil = 0
		for _, entry in ipairs(ns.managed) do
			Step(ns.SetEntryAlpha, entry, 0)
		end
	end
	if cinematic ~= ns.lastCinematic then
		ns.Log("state", cinematic and "cinematic" or "normal UI")
	end
	Step(ns.UpdateFrames, cinematic, elapsed)
	Step(ns.UpdateLetterbox, cinematic, elapsed)
	Step(ns.UpdateTint, cinematic, elapsed)
	Step(ns.UpdateCVars, cinematic)
	Step(ns.UpdateMusic, cinematic, elapsed)
	Step(ns.UpdateAmbience, cinematic, elapsed)
	Step(ns.UpdatePlates, cinematic, elapsed)
	Step(ns.UpdateTooltip)
	Step(ns.UpdateTaxi)
	if not ns.IsSuspended() then
		ns.lastCinematic = cinematic
	end
end

-- The safety net: put everything the addon changes back as it was, each part
-- on its own so one that fails doesn't stop the rest. Used when an error keeps
-- repeating and by /cine panic.
local function Try(fn, ...)
	if fn then
		local ok, err = pcall(fn, ...)
		if not ok then
			ns.Log("safety", "a restore step failed: " .. tostring(err))
		end
	end
end

local function RestoreEverything()
	-- The camera: stop any turn or zoom in progress.
	Try(ns.StopOrbitNow)
	Try(ns.StopIdleZoomNow)
	Try(ns.CancelDeathZoom)
	for _, name in ipairs({ "MoveViewLeftStop", "MoveViewRightStop", "MoveViewUpStop", "MoveViewDownStop",
		"MoveViewInStop", "MoveViewOutStop" }) do
		Try(_G[name])
	end
	-- Sound, names and nameplates.
	Try(ns.UpdateCVars, false)
	Try(ns.StopMusicNow)
	Try(ns.StopCombatMusicNow)
	Try(ns.StopAmbienceNow)
	Try(ns.ShowPlatesNow)
	Try(ns.ApplyCVarSet, ns.FLIGHT_CVARS, false)
	Try(ns.ApplyCVarSet, ns.RECENTER_CVARS, false)
	-- The UI: every faded frame back, the bars and tint off (hidden outright
	-- if their own update is what's failing).
	for _, entry in ipairs(ns.managed or {}) do
		Try(ns.SetEntryAlpha, entry, 1)
	end
	if not pcall(ns.UpdateLetterbox, false, 1e6) and ns.letterbox then
		ns.letterbox:Hide()
	end
	if not pcall(ns.UpdateTint, false, 1e6) and _G.CinematicTint then
		_G.CinematicTint:Hide()
	end
	if _G.CinematicFocus then
		_G.CinematicFocus:Hide()
	end
	Try(GameTooltip.SetAlpha, GameTooltip, 1)
	if not UIParent:IsShown() then
		Try(ns.ToggleUI) -- hidden with the Hide the UI key
	end
	-- Anything still held (a game setting the parts above didn't cover).
	Try(RestoreSavedCVars)
	ns.lastCinematic = false
end

-- Stopped for the session (ns.Suspend), until /cine resume.
local started, suspended = false, false
local combatRetry = CreateFrame("Frame")
combatRetry:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if suspended then
		RestoreEverything() -- nameplate settings can only change out of combat
	end
end)

function ns.IsSuspended()
	return suspended
end

function ns.Suspend(reason)
	if suspended then
		return
	end
	suspended = true
	ticker:SetScript("OnUpdate", nil)
	ns.orbitFrame:SetScript("OnUpdate", nil)
	RestoreEverything()
	if InCombatLockdown() then
		combatRetry:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
	ns.Log("safety", "stopped: " .. reason)
	ns.Print(("|cffff4040stopped for this session|r (%s) and put your UI and settings back. " ..
		"/cine log has the details for a bug report; /cine resume starts it again."):format(reason))
end

function ns.Resume()
	if not suspended then
		return false
	end
	suspended = false
	ns.ResetErrorWindows()
	lastBusy = GetTime()
	ns.letterboxDirty = true
	if ns.RefreshTint then ns.RefreshTint() end
	if _G.CinematicFocus then _G.CinematicFocus:Show() end
	if started then
		ticker:SetScript("OnUpdate", OnUpdate)
		ns.orbitFrame:SetScript("OnUpdate", OnOrbitUpdate)
	end
	ns.Log("safety", "resumed")
	return true
end

-- Global entry points for Bindings.xml
function ns.SetEnabled(enabled)
	ns.db.enabled = enabled
	lastBusy = GetTime()
	if enabled and ns.db.startCinematic then
		-- "Start in cinematic mode" covers turning it on too: straight in, as at login.
		lastBusy = GetTime() - ns.db.delay
		startSnapUntil = GetTime() + START_SNAP_WINDOW
	end
end

function Cinematic_Toggle()
	ns.SetEnabled(not ns.db.enabled)
	ns.Print(ns.db.enabled and "enabled" or "disabled")
	if ns.IsSuspended() then
		ns.Print("(still stopped after an error: /cine resume starts it again)")
	end
end

function Cinematic_FlyBy()
	local _, message = ns.ToggleFlyBy()
	if message then
		ns.Print("fly-by: " .. message)
	end
end

-- Key bindings for the standing-still cameras: each starts its camera now, as
-- if its event had happened, and pressing it again stops it. Moving or jumping
-- ends it, like an emote. "death" runs the death camera test (/cine deathtest).
local CAM_NAMES = { idle = "AFK", cozy = "cozy", vista = "vista", fish = "fish" }
function Cinematic_StartCam(camera)
	if not ns.db then
		return
	end
	local now = GetTime()
	if camera == "death" then
		if now < (ns.deathTestUntil or 0) then
			ns.deathTestUntil = 0
			ns.Print("death camera test stopped")
		elseif not ns.db.deathOrbit then
			ns.Print("the death camera is off: turn it on with /cine death first")
		else
			ns.deathTestUntil = now + 30
			ns.Print(("death camera test for 30 seconds: stand still and it starts after %.1f sec. " ..
				"Press the key again to stop it."):format(ns.db.deathOrbitDelay))
		end
		return
	end
	if not ns.db.enabled then
		ns.Print("Cinematic is off: turn it on first")
		return
	end
	if ns.playerMoving or UnitOnTaxi("player") then
		ns.Print("stand still to start the " .. CAM_NAMES[camera] .. " camera")
		return
	end
	local idleOn = camera == "idle" and ns.stillSince ~= nil and now - ns.stillSince >= ns.db.idleOrbitDelay
		and not ns.manualCam
	if ns.manualCam == camera or idleOn then
		ns.manualCam = nil
		ns.stillSince = now -- the standing-still timer starts afresh
		ns.Print(CAM_NAMES[camera] .. " camera stopped")
		return
	end
	if camera == "idle" and not ns.db.idleOrbit then
		ns.Print("the AFK camera's rotation is off on its options page")
		return
	end
	ns.manualCam = camera ~= "idle" and camera or nil
	ns.stillSince = now - ns.db.idleOrbitDelay -- counts as stood still long enough
	lastBusy = 0 -- fade the UI now
	ns.Print(CAM_NAMES[camera] .. " camera on: move, jump or press the key again to stop it")
end

function Cinematic_ToggleUI()
	ns.ToggleUI()
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
	ns.db.chatPeekChannelList = ns.db.chatPeekChannelList or { General = true, LocalDefense = true }
	ns.db.flightTimes = ns.db.flightTimes or {}
	ns.db.zoneTints = ns.db.zoneTints or {} -- zone name -> "none", a mood key or { r, g, b }
	ns.db.zoneTintStrength = ns.db.zoneTintStrength or {} -- zone name -> strength (0-1) for the Zone presets
	ns.db.zonePresets = ns.db.zonePresets or {} -- zone or area name -> tint preset key used there instead of tintPreset
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
	ns.SyncPlateCVars() -- the game's nameplate options follow the restored ticks
	lastBusy = GetTime()
	ns.letterboxDirty = true
end

-- Shared with Options.lua
ns.DEFAULTS = DEFAULTS

-- Your speed in yards per second, or nil when the game won't say (secret).
-- Walking is 2.5, running backwards 4.5, running 7.
local WALK_SPEED_MAX = 3.5
local AUTORUN_INFER_AFTER = 1 -- seconds of moving with no movement key held = auto-run
-- Skyriding (retail): your speed through the air while gliding, else nil.
-- The usual speed reading and the moving/stopped events don't follow a glide
-- well, so the gliding info is asked instead.
function ns.GlidingSpeed()
	if not (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then
		return nil
	end
	local ok, gliding, _, speed = pcall(C_PlayerInfo.GetGlidingInfo)
	if not ok or (issecretvalue and (issecretvalue(gliding) or issecretvalue(speed))) or not gliding then
		return nil
	end
	return type(speed) == "number" and speed or 0
end

function ns.GetPlayerSpeed()
	local gliding = ns.GlidingSpeed()
	if gliding and gliding > 0 then
		return gliding
	end
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
local FLIGHT_USES_DEFAULT = { mouseoverHold = true, buffPeekTime = true, chatPeekTime = true }
for _, group in ipairs(ns.HOVER_GROUPS) do FLIGHT_USES_DEFAULT[group[1] .. "HoverHold"] = true end
-- ...except the general hold, which goes at once there (normal play holds it a while).
local FLIGHT_HOLD = { mouseoverHold = 0 }

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

-- Which camera mode you're in: "flight", "walk", "run", "vista", "fish", "cozy", "idle", or nil.
function ns.CameraMode()
	if UnitOnTaxi("player") then
		return "flight"
	elseif ns.IsRPWalking and ns.IsRPWalking() then
		return "walk"
	elseif ns.IsAutoRunning and ns.IsAutoRunning() then
		return "run"
	elseif ns.IsVista and ns.IsVista() then
		return "vista"
	elseif ns.IsFish and ns.IsFish() then
		return "fish"
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
		return math.min(FLIGHT_HOLD[key] or DEFAULTS[key], ns.db[key])
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
pcall(ticker.RegisterEvent, ticker, "LOADING_SCREEN_DISABLED") -- (not on every client)
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
		-- An early build had one "keep the other faction's names" option.
		if ns.db.plateEnemyNamesCinematic then
			ns.db.nameKeepOther = true
		end
		ns.db.plateEnemyNamesCinematic = nil
		-- The other faction's icon used to be its own option (markOther).
		if ns.db.markOther == false then
			ns.db.nameIconOther = false
		end
		ns.db.markOther = nil
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
		-- The settle used to start this long before landing (default 8); now
		-- it's when the camera is locked behind you (default 5). Once, unless changed.
		if not ns.db.taxiSettleV2 then
			if ns.db.taxiSettleLead == 8 then ns.db.taxiSettleLead = nil end
			ns.db.taxiSettleV2 = true
		end
		-- Fly-bys turned to 150 degrees at first, now 160. Once, unless changed.
		if not ns.db.flyByAngleV2 then
			if ns.db.flyByAngle == 150 then ns.db.flyByAngle = nil end
			ns.db.flyByAngleV2 = true
		end
		-- The fly-by /look was on by default at first; now off by default (it may
		-- be what snaps the camera as a fly-by starts). Saved "on" goes once.
		if not ns.db.flyByLookOffV1 then
			if ns.db.flyByLook == true then ns.db.flyByLook = nil end
			ns.db.flyByLookOffV1 = true
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
		if ns.db.deathSongFile then -- one song became a list to pick from
			if ns.db.deathSongFile ~= 53519 then ns.db.deathSongFiles = tostring(ns.db.deathSongFile) end
			ns.db.deathSongFile = nil
		end
		if not ns.db.buffPeekIgnoreV2 then -- Ghost joins the list, unless it was changed
			if ns.db.buffPeekIgnore == "2479, Plainsrunning" then ns.db.buffPeekIgnore = nil end
			ns.db.buffPeekIgnoreV2 = true
		end
		if not ns.db.deathSettingsV4 then -- starts as you fall
			if ns.db.deathOrbitDelay == 2 then ns.db.deathOrbitDelay = nil end
			ns.db.deathSettingsV4 = true
		end
		if not ns.db.deathSettingsV3 then -- a gentler rise
			if ns.db.deathLevel == 70 or ns.db.deathLevel == 60 then ns.db.deathLevel = nil end
			ns.db.deathSettingsV3 = true
		end
		if not ns.db.questCamSettingsV4 then -- comes down less (lower, it met the scenery)
			if ns.db.questCamLower == 20 then ns.db.questCamLower = nil end
			ns.db.questCamSettingsV4 = true
		end
		if not ns.db.questCamSettingsV3 then -- a gentler swing
			if ns.db.questCamTime == 1.5 then ns.db.questCamTime = nil end
			ns.db.questCamSettingsV3 = true
		end
		if not ns.db.questCamSettingsV2 then -- a slower zoom
			if ns.db.questCamZoomTime == 4 then ns.db.questCamZoomTime = nil end
			ns.db.questCamSettingsV2 = true
		end
		if not ns.db.vistaSettingsV2 then -- doesn't drop down as much
			if ns.db.vistaLevel == 10 then ns.db.vistaLevel = nil end
			if ns.db.vistaOrbitPitchDown == 5 then ns.db.vistaOrbitPitchDown = nil end
			ns.db.vistaSettingsV2 = true
		end
		-- "Start a fresh song when" and "Start music anyway" became one "Play
		-- music" choice per camera: one switched off in both stays off.
		for new, old in pairs({ Flight = { "musicNewSongOnFlights", "fatigueIgnoreOnFlights" },
			Idle = { "musicNewSongWhenIdle", "fatigueIgnoreWhenIdle" },
			Cozy = { "musicNewSongWhenCozy", "fatigueIgnoreWhenCozy" },
			Walk = { "musicNewSongWhenWalking", "fatigueIgnoreWhenWalking" },
			Run = { "musicNewSongWhenAutoRun", "fatigueIgnoreWhenAutoRun" } }) do
			if ns.db[old[1]] == false and ns.db[old[2]] == false and ns.db["musicCam" .. new] == nil then
				ns.db["musicCam" .. new] = false
			end
			ns.db[old[1]], ns.db[old[2]] = nil, nil
		end
		if not ns.db.fishMissPauseV2 then -- 5 sec became 30 (moving to a new spot still ends it)
			if ns.db.fishMissPause == 5 then ns.db.fishMissPause = nil end
			ns.db.fishMissPauseV2 = true
		end
		-- The fishing event used the vista camera by default before the fish
		-- camera existed: that saved default moves over to it.
		if not ns.db.fishCamV1 then
			if ns.db.eventFishingCamera == "vista" then ns.db.eventFishingCamera = nil end
			ns.db.fishCamV1 = true
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
		-- World tooltips used to be one switch for every camera mode.
		if ns.db.tooltipOffInCameraModes ~= nil then
			for _, key in ipairs({ "tooltipOffFlight", "tooltipOffIdle", "tooltipOffCozy",
				"tooltipOffWalk", "tooltipOffRun" }) do
				ns.db[key] = ns.db.tooltipOffInCameraModes
			end
			ns.db.tooltipOffInCameraModes = nil
		end
		-- The cozy and vista triggers used to be switches on those cameras' pages;
		-- they're events now, each picking its camera. A switched-off trigger
		-- becomes "no camera".
		local oldTriggers = { Campfire = "cozyBuffsOn", Sit = "cozySit", Sleep = "cozySleep",
			Dance = "cozyDance", Kneel = "cozyKneel", Chair = "cozyChair", Weapon = "cozyWeapon",
			Stare = "vistaStare" }
		for event, old in pairs(oldTriggers) do
			if ns.db[old] == false and ns.db["event" .. event .. "Camera"] == nil then
				ns.db["event" .. event .. "Camera"] = "none"
			end
		end
		-- "Start right away" and the shared eventDelay became a delay per event
		-- (empty: right away). Only a changed eventDelay carries over, to the
		-- events that weren't set to start right away.
		local oldDelay = ns.db.eventDelay
		for _, event in ipairs(ns.EVENTS) do
			local key = "event" .. event.key
			if oldDelay and oldDelay ~= 10 and not ns.db[key .. "Instant"] and ns.db[key .. "Delay"] == nil
				and event.key ~= "Flight" and event.key ~= "Quest" and event.key ~= "Fishing" then -- (added after; never had the shared delay)
				ns.db[key .. "Delay"] = oldDelay
			end
			ns.db[key .. "Instant"] = nil
		end
		-- One camera input pause used to cover the flight and AFK cameras; each
		-- has its own now. Only a changed one carries over.
		if ns.db.cameraInputPause and ns.db.cameraInputPause ~= 15 then
			ns.db.taxiInputPause = ns.db.taxiInputPause or ns.db.cameraInputPause
			ns.db.idleInputPause = ns.db.idleInputPause or ns.db.cameraInputPause
		end
		-- The quest cam's side used to be two switches (random, else left).
		if ns.db.questCamRandomSide == false and ns.db.questCamSide == nil then
			ns.db.questCamSide = ns.db.questCamLeft and "left" or "right"
		end
		-- Settings from removed or renamed features, now that the migrations
		-- above have read what they need.
		for _, key in ipairs({
			"cozyInstant", "cozyBuffsOn", "cozySit", "cozySleep", "cozyDance", "cozyKneel", "cozyChair",
			"cozyWeapon", "vistaInstant", "vistaStare", "eventsV2", "eventDelay",
			"taxiShotHold", "taxiShotBlendTime",
			"taxiShots", "taxiShotInterval", "taxiShotLength", "taxiShotBlend", "taxiShotCuts",
			"questCam", -- (now the quest giver event's camera)
			"thirdsFraming", "thirdsStrength", "thirdsInterval", "thirdsHold",
			"taxiThirdsInterval", "taxiThirdsStrength", "taxiThirds", "walkThirds", "runThirds",
			"idleThirds", "cozyThirds", "vistaThirds", "deathThirds",
			"startCinematicOnReload", "timeOfDayChange", "timeOfDaySound",
			"revealOnTarget", "ignoreDeadTarget",
			"plateHurtMobs", "plateHurtNPCs", "plateHurtOwn", "plateHurtOther", "plateHurtPets",
			"plateHurtTotems",
			"camOffInCities", "camOffInInns", "camOffInDungeons", "camOffInRaids", "camOffInPvP",
			"hideCursor", "hideCursorDelay", "innZoom", "innZoomDistance",
			"viewShift", "viewShiftAmount", "viewShiftRight", "zoneTitle", "zoneTitleSubzones",
			"taxiOrbitPitch", "idleOrbitPitch", "turnLog", "cozyPray", "cozyAngle", "deathInputPause",
			"cozyCrackle", "cursorTuck", "cursorTuckFlight", "cursorTuckIdle", "cursorTuckCozy",
			"cursorTuckVista", "cursorTuckWalk", "cursorTuckRun", "cursorTuckOther", "cursorTuckDelay",
			"flyByDistance", "flyByMinDistance", "flyByMaxDistance", "flyByTrace", "flyByLower",
			"cameraInputPause", "questCamRandomSide", "questCamLeft", "lastMusicStartedAt",
		}) do
			ns.db[key] = nil
		end
		for k, v in pairs(DEFAULTS) do
			if ns.db[k] == nil then ns.db[k] = v end
		end
		EnsureTables()
		ns.InitLog()
		SLASH_CINEMATIC1 = "/cine"
		SLASH_CINEMATIC2 = "/cinematic"
		SlashCmdList.CINEMATIC = ns.HandleSlash
	elseif event == "PLAYER_LOGIN" then
		ns.MusicTrace(("LOGIN volume %s music %s"):format(GetCVar("Sound_MusicVolume"), GetCVar("Sound_EnableMusic")))
		RestoreSavedCVars()
		ns.RestoreMusicVolume()
		ns.SyncPlateCVars()
		ns.SyncNameCVars()
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
		GameTooltip:HookScript("OnHide", ns.OnTooltipHide)
		-- The minimap button first, so the fade list picks it up straight away
		-- (otherwise it stays visible until the next scan).
		if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
		ns.BuildManagedList()
		ns.CreateLetterbox()
		ns.CreateTint()
		lastBusy = GetTime()
		started = true
		if not suspended then
			self:SetScript("OnUpdate", OnUpdate)
			ns.orbitFrame:SetScript("OnUpdate", OnOrbitUpdate)
		end
	elseif event == "LOADING_SCREEN_DISABLED" then
		ns.stillSince = nil -- the AFK timer starts once you can see the world
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- After a login, /reload or any loading screen, the AFK timer starts
		-- afresh (the orbit has been running since login, counting the loading
		-- screen as standing still).
		ns.stillSince = nil
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
		if (arg1 or arg2) and ns.db.startCinematic then
			lastBusy = GetTime() - ns.db.delay -- skip the fade delay
			startSnapUntil = GetTime() + START_SNAP_WINDOW
		end
	elseif event == "PLAYER_LOGOUT" then
		ns.MusicTrace(("LOGOUT volume %s music %s"):format(GetCVar("Sound_MusicVolume"), GetCVar("Sound_EnableMusic")))
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
		ns.MusicTrace(("LOGOUT done volume %s music %s"):format(GetCVar("Sound_MusicVolume"), GetCVar("Sound_EnableMusic")))
	elseif event == "PLAYER_LEVEL_UP" then
		ns.levelUpUntil = GetTime() + ns.LEVEL_UP_WINDOW
	elseif event == "PLAYER_STARTED_MOVING" then
		ns.playerMoving = true
		ns.movingSince = GetTime()
	elseif event == "PLAYER_STOPPED_MOVING" then
		if ns.GlidingSpeed() then
			-- Skyriding: this can come mid-glide. You're still flying (on
			-- auto-run, say), so carry on; the tick checks again once you land.
			ns.stopWhileGliding = true
		else
			ns.playerMoving = false
			ns.autoRunning = false -- auto-run ends when you stop
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		-- New plates start fully visible; match them to the current fade and
		-- the Nameplates page's choices.
		if C_NamePlate then
			ns.RefreshPlate(C_NamePlate.GetNamePlateForUnit(arg1), arg1)
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
