-- Cinematic: fades the UI out between fights and slides in letterbox bars.
--
-- Only SetAlpha is used on Blizzard frames (never Show/Hide), so it is safe
-- to touch protected frames like action bars even during combat lockdown.

local ADDON_NAME, ns = ...
local L = ns.L

-- Retail (the main game) rather than a Classic client such as WoW Forever.
-- Most differences are handled by checking whether an API or frame exists;
-- this is for the few that differ by design (data files, retail-only options).
ns.isRetail = WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

BINDING_HEADER_CINEMATIC = "Cinematic"
-- (Set again once the language is known: see Locales.lua.)
local function SetBindingNames()
	BINDING_NAME_CINEMATIC_TOGGLE = "Cinematic: " .. L["Toggle CineMode"]
	BINDING_NAME_CINEMATIC_HIDEUI = "Cinematic: " .. L["Hide the UI (keep the look)"]
	BINDING_NAME_CINEMATIC_CAMWHEEL = "Cinematic: " .. L["Camera wheel (hold)"]
	BINDING_NAME_CINEMATIC_CAM_IDLE = "Cinematic: " .. L["Start the AFK camera"]
	BINDING_NAME_CINEMATIC_CAM_COZY = "Cinematic: " .. L["Start the cozy camera"]
	BINDING_NAME_CINEMATIC_CAM_VISTA = "Cinematic: " .. L["Start the vista camera"]
	BINDING_NAME_CINEMATIC_CAM_FISH = "Cinematic: " .. L["Start the fish camera"]
	BINDING_NAME_CINEMATIC_CAM_TELE = "Cinematic: " .. L["Start the tele camera"]
	BINDING_NAME_CINEMATIC_CAM_DEATH = "Cinematic: " .. L["Test the death camera"]
	BINDING_NAME_CINEMATIC_SHOWTOOLTIPS = "Cinematic: " .. L["Show hidden tooltips (hold)"]
	BINDING_NAME_CINEMATIC_TOGGLETOOLTIPS = "Cinematic: " .. L["Toggle tooltip hiding"]
end
SetBindingNames()
ns.OnLanguage(SetBindingNames)

local DEFAULTS = {
	enabled = true,
	fadeUI = true,            -- CineMode fades the UI (off: just the visual effects, over the normal UI)
	minimapButton = true,     -- show the minimap button
	minimapAngle = 205,       -- its position around the minimap, in degrees (clear of the dungeon finder's eye)
	-- In CineMode, hide every tooltip in each camera mode ticked (the Tooltips page):
	tooltipHideInFlight = true,
	tooltipHideInIdle = true,   -- standing still
	tooltipHideInCozy = true,
	tooltipHideInVista = true,  -- /stare
	tooltipHideInFish = true,   -- fishing
	tooltipHideInWalk = false,  -- RP walking
	tooltipHideInRun = false,   -- auto-running
	tooltipHideInTele = true,   -- Hearthstone and teleports
	tooltipHideInDeath = true,  -- the death camera
	tooltipHideInQuest = false, -- the quest camera
	hideCombatText = true,    -- no floating combat text (heals, regen) in cinematic mode out of combat (after the Calm Timer)
	hideErrorsInCombat = false,    -- no red error text ("Target not in line of sight") in fights (and the Calm Timer after)
	hideErrorsOutOfCombat = false, -- nor out of them (CineMode or not, either)
	hideWorldText = false,    -- no floating world text at all (XP gained, damage and healing numbers): a blank font, from the next game start
	visualEffects = true,     -- the Visual Effects page's master switch (off: none of its effects)
	timeOfDayMessage = true,  -- "Dusk" under the zone name on login and /reload, and when it
	                          -- changes, with a fitting sound (rooster, bells, frogs, owl, wolf)
	offInDungeons = false,    -- no cinematic mode in dungeons (and scenarios)
	offInRaids = false,
	offInPvP = false,         -- PvP flagged, battlegrounds and arenas
	offInCities = false,      -- capital cities
	offInWorld = false,       -- the open world: anywhere outside instances, cities and inns
	offInParty = false,       -- while in a party (not a raid group)
	offInRaidGroup = false,   -- while in a raid group
	offWhileMoving = false,   -- while walking or riding about yourself (not auto-run, RP walking or flights)
	movingBackAfter = 15,     -- ...until you've stood still, or kept moving, this many seconds
	movingKeepVFX = true,     -- ...and the visual effects (letterbox, tint...) stay on meanwhile
	fadeOutTime = 1.5,
	combatFadeOutTime = 6,    -- ...for fades that start within the Calm Timer after a fight
	fadeInTime = 1.5,
	combatFadeInTime = 0.2,   -- ...for fades in during a fight (the UI coming back as it starts)
	letterbox = true,
	letterboxSize = 0.03,  -- fraction of screen height per bar
	letterboxAlpha = 1,    -- bar opacity
	-- The Visual Effects page's "Turn off in" grid for the letterbox, tint,
	-- vignette and weather:
	-- <effect>OffIn<where> (ns.EFFECT_OFF_WHERE), <effect>OffInCombat (gone in
	-- fights, back once the Calm Timer has run out after) and
	-- <effect>OnlyInCameras (only while a camera mode runs). Set below.
	calmTime = 60,            -- Calm Timer: seconds after a fight before things settle back (nameplates
	                          -- and names shown for fights go, the visual effects fade back in)
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
	weatherTintStrength = 1,
	tintClock = "game",    -- time-of-day tint follows "game" (realm) time or "local" (computer) time
	timeTintStrength = 0.5,-- how strongly the time-of-day colour applies (both time presets)
	tintPreviewHour = -2,  -- options-page preview of the time-of-day tint at this hour (-1 = now, -2 = not picked)
	alwaysShowMinimap = false, -- keep the whole minimap group visible in cinematic mode
	alwaysShowWaypoint = true, -- keep retail's quest waypoint visible in cinematic mode
	questTimerShow = true,     -- keep the quest timer visible in cinematic mode while one runs (not retail)
	durabilityShow = true,     -- keep the durability figure visible in cinematic mode while gear is damaged
	durabilityHideInCam = true, -- ...except while a camera mode is running
	petUnhappyShow = true,     -- keep the pet frame visible in cinematic mode while a hunter's pet isn't happy (not retail)
	petUnhappyHideInCam = true, -- ...except while a camera mode is running
	-- Swing timer page (not retail), in CineMode and out:
	swingSmartShow = true,     -- melee and ranged bars only while that weapon is in use
	swingHideAfter = 5,        -- ...seconds after its last swing or shot (and the bar running down) it fades
	swingHideOffHand = false,  -- never show the off-hand bar
	questRevealOnAccept = true, -- accepting a quest shows the quest tracker as a mouseover would
	questAcceptCalm = false,    -- ...and stays up for the Calm Timer (if longer than the mouseover time)
	questRevealOnProgress = true, -- quest objective progress shows the quest tracker the same way
	questProgressCalm = false,  -- ...and stays up for the Calm Timer (if longer than the mouseover time)
	questCombatCalm = false,  -- ticked In combat (Standard Frames), it stays up until the Calm Timer runs out
	minimapRevealOnPing = true, -- a group member pinging the minimap shows it as a mouseover would
	cooldownWhileRecharging = false, -- the Cooldown Manager stays up while a cooldown recharges (Mouseover groups
	                                 -- with Cooldown recharging ticked: the Cooldowns group by default)
	cooldownAfterCombat = true,     -- ...only within the Calm Timer after a fight
	minimapIndoors = false,    -- keep the minimap up indoors (hidden there, its map goes stale)
	-- Reveal (Minimap page): the faded minimap comes up while one of these is on
	-- it (NodeSweep.lua looks; with any ticked it's kept full size, icons hidden).
	minimapRevealNodes = true,   -- ore, herbs and treasure (the tracking has to be on)
	minimapNodePing = true,      -- ...with a minimap ping where one shows up (your group sees it too)
	minimapRevealTurnIns = true, -- quests of yours that are done
	minimapRevealIcons = true,   -- anything else (quest givers, flight masters, your quests' areas...)
	minimapHideOnTaxi = true,    -- none of these, pings or Keep open's tracking bring it up on a flight path
	-- Keep open (Minimap page): the minimap stays up the whole time this tracking is on.
	minimapKeepCreatures = false, -- creatures (hunter, druid, warlock) or fish
	minimapKeepGathering = false, -- herbs, minerals or treasure...
	trackingOffInCities = true,  -- ...except in these places (no nodes there; dungeons have some)
	trackingOffInDungeons = true,
	trackingOffInRaids = true,
	trackingOffInPvP = true,
	stayInCombat = true,  -- stay cinematic in combat and when targeting enemies
	combatShowCalm = false, -- Standard Frames' In combat rows stay up until the Calm Timer runs out after a fight
	revealOnCast = false,   -- casting or channeling brings the UI back
	revealAtNPCs = false,     -- vendor/bank/mail/trainer/trade/auction windows bring the UI back
	revealOnDrag = false,     -- bring the UI back while something's held on the cursor (dragging)
	returnDelay = 15,         -- seconds things must stay calm (no cast, window...) before CineMode returns
	stayWithWindows = true, -- stay cinematic when opening the spellbook, options and similar
	portraitWhenNotFull = true, -- keep the player portrait up while health or power isn't full, within
	                            -- the Calm Timer (calmTime) of combat or after coming back to life
	prdWhenNotFull = true,      -- ...and the personal resource display (its own tick)
	buffPeek = true,          -- briefly show buffs/debuffs when a buff is gained or refreshed
	buffPeekAfterCombat = false, -- ...or only within the Calm Timer of a fight
	buffPeekIgnoreSelf = true,   -- ...and not for buffs you cast on yourself (or your pet does)
	debuffPeek = true,        -- ...and when a debuff is
	debuffPeekAfterCombat = false, -- (any time: Hunter's Mark and the like matter out of fights too)
	debuffPeekUntilGone = false,   -- ...and keep them up until your debuffs are gone
	buffPeekTime = 3,           -- seconds they stay up for a buff
	debuffPeekTime = 3,         -- ...and for a debuff
	buffPeekIgnore = "2479, Plainsrunning, 8326, 20584", -- buffs or debuffs that never bring them up
	                                                    -- (spell IDs or names; 8326/20584: Ghost)
	buffHoverPadX = 40,         -- how far beside the buff icons hovering reveals them (UI units)
	buffHoverPadY = 40,         -- ...and above and below
	mouseover = true,      -- hovering a faded element reveals it
	mouseoverHold = 3,     -- seconds a group stays after the mouse leaves it (per-group overrides below)
	musicInCinematic = true,  -- turn game music on while cinematic, off after
	plateCombatEnemies = false, -- in cinematic mode, show these during fights (Enemies: enemy players)
	plateCombatEnemyMinions = false,
	plateCombatEnemyNPCs = true,
	plateCombatNeutralNPCs = true,
	plateCombatEnemyMinor = true,
	plateCombatNeutralMinor = true,
	plateCombatFriends = false,
	plateCombatFriendlyMinions = false,
	plateCombatFriendlyNPCs = false,
	plateCinematicEnemies = true, -- keep these up in cinematic mode in the open world (plateIn<place><kind> elsewhere)
	plateCinematicEnemyMinions = false,
	plateCinematicEnemyNPCs = false,
	plateCinematicNeutralNPCs = false,
	plateCinematicEnemyMinor = false,
	plateCinematicNeutralMinor = false,
	plateCinematicFriends = false,
	plateCinematicFriendlyMinions = false,
	plateCinematicFriendlyNPCs = false,
	nameKeepSelf = false,     -- keep these names up in cinematic mode in the open world (see nameIn<place><key>)
	nameKeepNPCs = false,
	nameKeepCritters = false,
	nameKeepFriends = false,
	nameKeepFriendlyMinions = false,
	nameKeepEnemies = false,
	nameKeepEnemyMinions = false,
	handleTooltips = false,   -- the Tooltips page's master switch (off: every tooltip shows as the game has it)
	-- In CineMode, out of combat, hide the tooltips of (world ones and unit frames')...
	tooltipHideEnemy = false,   -- ...units you can attack
	tooltipHideFriendly = true, -- ...units you can't
	tooltipHideGather = false,  -- ...something gatherable (herb, ore, skinnable)
	tooltipHideQuest = false,   -- ...one showing a quest objective
	-- In CineMode, in combat, hide...
	tooltipHideCombatEnemy = false, -- ...units you can attack
	tooltipHideCombatElse = true,   -- ...everything else: friends, objects, action bars, bags, menus
	musicFadeTime = 3,        -- seconds for music to fade in or out
	musicFatigue = 0,         -- minutes: don't start music again within this long of the last start
	-- Which cameras can start music as they start (when music fatigue allows).
	musicCamFlight = true,
	musicCamWalk = false,     -- RP walk
	musicCamRun = false,      -- auto-run
	musicPauseWhenMoving = false, -- music fades out once you leave the camera modes and move on
	musicOffInCombat = false, -- fade game music out while in combat
	musicOffInCities = false, -- ...and in these places
	musicOffInDungeons = false,
	musicOffInRaids = false,
	musicOffInPvP = false,
	chatPeek = true,          -- briefly show a chat window when a message arrives
	chatPeekChannels = false, -- old "include public channels"; now the default for channels not yet set
	chatPeekTime = 8,         -- seconds the chat window stays up
	chatUntilWhisperRead = true, -- keep chat up while a whisper tab is flashing (until it's clicked)
	chatHideOwn = true, -- your own messages (emotes, say, party...) don't show chat
	chatHideBubbled = true, -- say/yell you can see as a bubble on screen doesn't show chat
	chatAttackAlert = true, -- LocalDefense "... is under attack!" also shows as a title
	updateNotice = true, -- after an update, a line in chat at login with a What's new link (WhatsNew.lua)
	chatInCities = false,     -- keep chat visible in capital cities
	chatInDungeons = false,   -- ...in dungeons and scenarios
	chatInRaids = false,
	chatInPvP = false,        -- ...while PvP flagged (battlegrounds and arenas too)
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
	idleOrbitDelay = 60,      -- seconds of standing still before it starts
	-- Cozy camera: swings round to face you and sways in front, when an event
	-- picks it (Camera Triggers page: ns.EVENTS in Camera.lua has their defaults).
	cozyOrbit = true,         -- sway in front of you
	cozyZoom = true,          -- with a close, gentle zoom
	cozyBuffs = "Welcoming Campfire", -- the campfire event's buffs: names or spell IDs, comma-separated
	cozyChairWords = "chair, bench, stool, seat, throne, pew", -- the chair event: words in a seat's name
	campfireSitButton = true, -- the Campfire button on hovering a campfire near the middle of the screen (Campfire.lua)
	campfireSit = true,       -- ...its emotes: sit, kneel, lie down (one of those ticked, at random)
	campfireKneel = true,
	campfireLie = true,
	campfireStandUp = true,   -- ...and stand up again once Camp Benefits arrives
	hunterRightClickShot = true, -- hunters: right-click on an enemy starts Auto Shot, in combat too (Hunter.lua)
	hunterAmmoSort = true,    -- hunters: after Clean Up Bags, the smallest ammo stack goes first, to be shot first (HunterAmmo.lua)
	hunterQuiverFill = true,  -- hunters: a Fill button on arrows and bullets at vendors fills the quiver (HunterAmmo.lua)
	-- Dragging something you can wear out of the bags opens the character window (DragEquip.lua). Off by
	-- default where unit values are secret: opening it taints the player bars, and BugSack shows their errors.
	dragEquipCharacter = issecretvalue == nil,
	talentLink = true,         -- Forever: inspecting someone, a button to their talents, and one back on the talents window (TalentLink.lua)
	talentCalc = true,         -- Forever: a Talent calculator button on the talents window (TalentCalc.lua)
	talentCalcTalented = false, -- ...counting the Legacy Tree's Talented (points from level 5) for the level a build needs
	centerPanels = true,      -- windows the game opens on the left open in the middle of the screen (CenterPanels.lua)
	dragPanels = true,         -- ...and drag them to move them; they open where last dropped (panelSpots, CenterPanels.lua)
	cozyInputPause = 2,       -- seconds after you move the camera before it carries on
	cozyZoomClose = 10,       -- yards: the distance it zooms in to (if you're further out); far side of a fire
	cozyTentClose = 8,        -- ...closer with a Camp Tent seen nearby (Campfire.lua), and no drifting further out
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
	taxiInputPause = 15,      -- seconds the flight camera waits after the player moves the camera
	idleInputPause = 15,      -- ...and the AFK camera
	-- Quest cam (eventQuestCamera on the Camera Triggers page): talking to a quest giver, zoom in and swing behind you
	questCamDistance = 4,     -- ...yards it zooms in to (if you're further out)
	questCamTime = 3,         -- ...seconds the swing behind you takes
	questCamZoomSpeed = 0.5,  -- ...yards a second the zoom in goes
	questCamZoomOutSpeed = 0.5, -- ...yards a second the zoom back out goes, leaving (walking off: quicker; 0: stays in)
	questCamAngle = 30,       -- ...degrees the camera comes round to one side of behind you (0: straight behind)
	questCamSide = "click",   -- ...the side of the screen you clicked them on (else at random), or "random", "left" or "right"
	questCamTurnTime = 4,     -- ...seconds that turn takes (once the zoom's done)
	questCamDrift = 4,        -- ...degrees it then drifts slowly to and fro, side to side (0: holds still)
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
DEFAULTS.fishGamepadCast = true    -- in gamepad mode, a gamepad button casts as right-click does...
DEFAULTS.fishGamepadKey = "PAD3"   -- ...this one (the left face button: X on an Xbox pad, square on a PlayStation one)
DEFAULTS.gamepadPressReveal = true -- a gamepad button press shows its action bars for the mouseover time
DEFAULTS.gamepadPressHold = 3       -- ...for this long after the last press (counting the fade out)
DEFAULTS.gamepadBarsFadeIn = 0.2    -- gamepad mode's action bars fade quicker than the rest of the UI
DEFAULTS.gamepadBarsFadeOut = 0.5
DEFAULTS.showInteractPrompt = true -- the interact prompt on a plate (gamepad's X) stays as plates fade
DEFAULTS.forceReloadOnSettingsExit = true -- WoW Forever: closing Settings reloads (gets past its gamepad freeze)
DEFAULTS.hideMinimapButtonGamepad = true -- no minimap button in gamepad mode (clicking it there tends to freeze)
for _, key in ipairs({ "Mode", "Right", "Step", "Speed", "MinChange", "PitchUp", "PitchDown", "BackArc",
	"MoveTime", "Ease", "Pause", "Drift", "DriftSpeed" }) do
	DEFAULTS["fishOrbit" .. key] = DEFAULTS["vistaOrbit" .. key]
end
DEFAULTS.fishOrbitBackArc = 12     -- (vista: 30)
DEFAULTS.fishOrbitPitchUp = 3      -- (vista: 5)
DEFAULTS.fishOrbitPitchDown = 2    -- (vista: 3)
DEFAULTS.fishOrbitMinChange = 4    -- (vista: 10)
DEFAULTS.fishOrbitDriftSpeed = 0.3 -- (vista: 0.5)
for _, key in ipairs({ "Distance", "In", "Time", "Pause", "Random", "Ease", "PastMax" }) do
	DEFAULTS["fishZoom" .. key] = DEFAULTS["vistaZoom" .. key]
end
-- Tele camera (casting your Hearthstone or a teleport): the cozy camera's
-- swing round to face you, only quicker, then a spin round you that speeds up
-- until you go, zooming in over the cast. (Its sway settings are the cozy camera's.)
DEFAULTS.teleArriveEarly = 3       -- seconds before the cast ends that the swing gets round in front
DEFAULTS.teleSpinAccel = 8         -- degrees per second it speeds up by, each second, once round
DEFAULTS.teleSpinMax = 120         -- degrees per second, at most
DEFAULTS.teleLevel = 15            -- degrees it brings the camera down as it swings round
DEFAULTS.teleZoom = true           -- zoom in over the cast
DEFAULTS.teleZoomClose = 4         -- yards it zooms in to (if you're further out)
DEFAULTS.teleReturn = true         -- cancelled: turn back to where the camera was
DEFAULTS.teleZoomBackTime = 0.5    -- seconds to zoom back out to your distance on a cancel
DEFAULTS.teleBehind = true         -- arrived: swing the camera round behind you
-- (Its zoom is one move in over the cast, then a hold: no random zooms.)
for key, value in pairs({
	Distance = 0, In = 0, Time = 1, Pause = 1, PauseVary = 0, Random = false, Ease = 0.5, PastMax = false,
}) do
	DEFAULTS["teleZoom" .. key] = value
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
-- Each camera mode's "Turn off in" grid (Camera Modes page): <cam>OffIn<where>,
-- for the cameras in ns.CAMERA_OFF_CAMS and the places in ns.CAMERA_OFF_WHERE
-- (capital cities; instances: dungeons, scenarios and raids; battlegrounds and
-- arenas; the open world), but not those in ns.CAMERA_OFF_NEVER (no flight from there).
-- All off.
ns.CAMERA_OFF_CAMS = {
	{ "flight", L["Flight"] }, { "idle", L["AFK"] }, { "cozy", L["Cozy"] }, { "tele", L["Tele"] },
	{ "vista", L["Vista"] }, { "fish", L["Fish"] }, { "walk", L["RP Walk"] }, { "run", L["Auto-run"] },
	{ "death", L["Death"] }, { "quest", L["Quest"] },
}
ns.OnLanguage(function() ns.TranslateFields(ns.CAMERA_OFF_CAMS, 2) end)
ns.CAMERA_OFF_WHERE = { "Cities", "Instances", "BGs", "World" }
ns.CAMERA_OFF_NEVER = { flight = { Instances = true, BGs = true } }
-- The Visual Effects page's grid: the same places, by where you are now.
ns.EFFECT_OFF_WHERE = ns.CAMERA_OFF_WHERE
ns.EFFECT_GRID = { "letterbox", "tint", "vignette", "weather" }
for _, effect in ipairs(ns.EFFECT_GRID) do
	for _, where in ipairs(ns.EFFECT_OFF_WHERE) do
		DEFAULTS[effect .. "OffIn" .. where] = false
	end
	DEFAULTS[effect .. "OnlyInCameras"] = false
end
DEFAULTS.letterboxOffInCombat = true -- (the bars slide away for fights)
DEFAULTS.tintOffInCombat = false
DEFAULTS.vignetteOffInCombat = false
-- The grid's Always column: the letterbox, vignette and weather have their own
-- switches (letterbox, vignette, weatherTint); the tint has this one.
DEFAULTS.tintOffAlways = false
DEFAULTS.weatherOffInCombat = false
-- The same grid's Calm Timer column: <cam>CalmWait, that camera holds off
-- until the Calm Timer (calmTime) has run out after a fight. By default the
-- ones you'd walk or run off into after one (RP walking, auto-running), the
-- tele camera and the quest camera; the rest start straight away. Not the death camera: you die in a fight.
ns.CALM_WAIT_NEVER = { death = true }
local CALM_WAIT_DEFAULT = { walk = true, run = true, tele = true, quest = true }
for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do
	if not ns.CALM_WAIT_NEVER[cam[1]] then
		DEFAULTS[cam[1] .. "CalmWait"] = CALM_WAIT_DEFAULT[cam[1]] or false
	end
	for _, where in ipairs(ns.CAMERA_OFF_WHERE) do
		if not (ns.CAMERA_OFF_NEVER[cam[1]] or {})[where] then
			DEFAULTS[cam[1] .. "OffIn" .. where] = false
		end
	end
end
-- The Minimap page's "Hide in camera modes": <cam>HideMinimap fades the
-- minimap while that camera runs, whatever would keep it up (hovering still
-- shows it).
-- Every camera but auto-run and the quest camera hides it.
for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do
	DEFAULTS[cam[1] .. "HideMinimap"] = cam[1] ~= "run" and cam[1] ~= "quest"
end
-- No auto-run camera in capital cities or instances. RP walking is
-- deliberate, so its camera runs everywhere.
-- RP walk and auto-run start their cameras by themselves: "none" turns one
-- off everywhere (Camera Triggers page), as the events' "No camera" does.
DEFAULTS.walkCamera = "walk"
DEFAULTS.runCamera = "run"
-- Seconds of auto-walking or auto-running before its camera starts (and its
-- CineMode column with it); 0 is straight away.
DEFAULTS.walkCameraDelay = 0
DEFAULTS.runCameraDelay = 5
DEFAULTS.walkOffInCities, DEFAULTS.walkOffInInstances = false, false
DEFAULTS.runOffInCities, DEFAULTS.runOffInInstances = true, true
DEFAULTS.deathOffInInstances = true -- (no death camera in dungeons and raids: the group's waiting)
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
-- The Nameplates page's kinds of unit (see Effects), and its columns per
-- place: keep these up in cinematic mode out of combat there.
ns.PLATE_PLACES = { "PvP", "BGs", "Instances" } -- (BGs: and arenas; Instances: dungeons and raids)
ns.PLATE_KINDS = {
	"Enemies", "EnemyMinions", "EnemyNPCs", "EnemyMinor", "NeutralNPCs", "NeutralMinor", "Friends",
	"FriendlyMinions", "FriendlyNPCs",
}
for _, kind in ipairs(ns.PLATE_KINDS) do
	DEFAULTS["plateCombatPvP" .. kind] = false -- shown in fights while flagged for PvP
	for _, suffix in ipairs(ns.PLATE_PLACES) do -- (cities and inns go with the open world)
		DEFAULTS["plateIn" .. suffix .. kind] = false
	end
end
-- Kept up in dungeons and raids: friendly players and NPCs; while PvP
-- flagged: enemy players; in battlegrounds and arenas: players on both sides.
for _, key in ipairs({ "plateInInstancesFriends", "plateInInstancesFriendlyNPCs", "plateInPvPEnemies",
	"plateInBGsEnemies", "plateInBGsFriends" }) do
	DEFAULTS[key] = true
end
-- Shown in fights while flagged for PvP: players on both sides, and enemy minions.
for _, key in ipairs({ "plateCombatPvPEnemies", "plateCombatPvPFriends", "plateCombatPvPEnemyMinions" }) do
	DEFAULTS[key] = true
end
-- Friendly plates in dungeons and raids (Nameplates page): the game won't let
-- addons fade them there, so each kind is "hide", "show" or (players and
-- NPCs) "target": on while you have one of that kind targeted. See Effects.
-- To start with: friendly players and NPCs with one targeted, pets never.
ns.PLATE_INSTANCE_KINDS = { "Friends", "FriendlyMinions", "FriendlyNPCs" }
DEFAULTS.plateInstanceFriends = "target"
DEFAULTS.plateInstanceFriendlyMinions = "hide"
DEFAULTS.plateInstanceFriendlyNPCs = "target"
-- And your target's plate, shown everywhere whatever its own row says.
DEFAULTS.handlePlates = true -- the Nameplates page's master switch (off: the game's own options decide)
DEFAULTS.duelPlates = true -- in CineMode, the nameplates of two players dueling near you show (see Effects)
DEFAULTS.handleCooldowns = true -- the Cooldown Manager page's master switch (off: left alone)
-- The other pages' master switches likewise (see ns.HANDLE_SWITCHES): off,
-- CineMode leaves that part of the UI to the game.
DEFAULTS.handleFrames = true -- Standard Frames
DEFAULTS.handleAddonFrames = true -- Advanced Frames
DEFAULTS.handleGamepad = true
DEFAULTS.handleMinimap = true
DEFAULTS.handleQuests = true -- Quest tracker
DEFAULTS.handleBuffs = true -- Buffs/debuffs
DEFAULTS.handleChat = true
-- Chat bubbles page (off: the game's own settings, as you left them).
DEFAULTS.handleBubbles = false
-- Its grid: bubbles<Say|Party>OffAlways, and OffIn<where> (ns.EFFECT_OFF_WHERE),
-- ticked = no bubbles there. Say covers yell and NPC speech too.
for _, kind in ipairs({ "Say", "Party" }) do
	DEFAULTS["bubbles" .. kind .. "OffAlways"] = false
	for _, where in ipairs(ns.EFFECT_OFF_WHERE) do
		DEFAULTS["bubbles" .. kind .. "OffIn" .. where] = false
	end
end
DEFAULTS.bubblesTextOnly = true -- no background or border, just the text
DEFAULTS.bubblesTextOutline = true -- with text only: a black outline round the letters
DEFAULTS.bubblesTextOutlineSize = 2 -- 1 thin, 2 thick, 3 thick with a drop shadow
DEFAULTS.bubblesTextScale = 1
-- Graphics+ page (Graphics.lua): off, each setting ticked (so switching it on
-- uses them all). Each slider's value (graphicsPlus<name>) has no default: nil
-- until it's moved, it changes nothing. Not in profiles.
DEFAULTS.graphicsPlus = false
for _, setting in ipairs(ns.GRAPHICS_PLUS) do
	DEFAULTS[setting.key .. "On"] = true
end
DEFAULTS.handleSwing = true -- Swing timer
-- The development copy (the CinematicDev folder), for features not ready to
-- ship: they show only there.
ns.isDev = ADDON_NAME == "CinematicDev"
-- Heal Vision (CineMode page, HealVisionFrames.lua): the game's party and raid
-- frames show the tanks always, and everyone else only while hurt. Its row of
-- the Vision grid: healVision is Always, healVisionIn<where> (ns.VISION_WHERE:
-- the open world, capital cities included, dungeons and scenarios, raids, and
-- battlegrounds and arenas), healVisionInParty and healVisionInRaid (in one,
-- wherever you are; not healVisionInRaids, the place). All off to start with.
ns.VISION_WHERE = { "World", "Dungeons", "Raids", "BGs" }
local VISION_PLACE = { dungeon = "Dungeons", raid = "Raids", pvp = "BGs" }
DEFAULTS.healVision = false
DEFAULTS.healVisionMinAlpha = 0.05 -- how much of the members it hides still shows (0-0.9)
DEFAULTS.healVisionShowBelow = 0.95 -- members show below this much health (0-1; 1: any damage)
DEFAULTS.healVisionTarget = true -- your target always shows
DEFAULTS.healVisionTanks = true -- tanks always show
DEFAULTS.healVisionDispel = true -- so do members with a debuff you can dispel
DEFAULTS.healVisionAnyDebuff = false -- or with any debuff
do
	local HEAL_VISION_KEYS = { "healVision" }
	for _, column in ipairs({ "World", "Dungeons", "Raids", "BGs", "Party", "Raid" }) do
		DEFAULTS["healVisionIn" .. column] = false
		HEAL_VISION_KEYS[#HEAL_VISION_KEYS + 1] = "healVisionIn" .. column
	end

	-- Your role ("TANK", "HEALER" or "DAMAGER"): your specialization's, or
	-- without one the one you picked in the group finder. nil when there's no telling.
	function ns.PlayerRole()
		if GetSpecialization and GetSpecializationRole then
			local spec = GetSpecialization()
			local role = spec and GetSpecializationRole(spec)
			if type(role) == "string" then return role end
		end
		if UnitGroupRolesAssigned then
			local role = UnitGroupRolesAssigned("player")
			if type(role) == "string" and role ~= "NONE" then return role end
		end
	end

	-- A grid row's roles button (tankHide, healerHide, damageHide: row key ->
	-- true, hidden or off while you're that role; false, ticked back on). Rows
	-- not set go by these: Heal Vision is for healers to start with.
	ns.ROLE_HIDE_DEFAULTS = { tankHide = { healVision = true }, damageHide = { healVision = true } }
	function ns.RoleHidden(db, list, key)
		local value = db[list] and db[list][key]
		if value == nil then
			value = ns.ROLE_HIDE_DEFAULTS[list] and ns.ROLE_HIDE_DEFAULTS[list][key]
		end
		return value and true or false
	end

	-- Whether Heal Vision is on where you are now (in a party or raid or not,
	-- a healer or not).
	function ns.HealVisionHere(db)
		db = db or ns.db
		if not db then return false end
		-- (Off while you're a role its roles button has unticked: healers only to start with.)
		local role = ns.PlayerRole()
		local list = role == "TANK" and "tankHide" or role == "HEALER" and "healerHide"
			or role == "DAMAGER" and "damageHide"
		if list and ns.RoleHidden(db, list, "healVision") then return false end
		if db.healVision or db["healVisionIn" .. (VISION_PLACE[ns.GetPlaceType()] or "World")] then return true end
		if IsInRaid() then return db.healVisionInRaid end
		return IsInGroup() and db.healVisionInParty
	end

	-- Whether any of its boxes is ticked.
	function ns.HealVisionAny(db)
		db = db or ns.db
		if not db then return false end
		for _, key in ipairs(HEAL_VISION_KEYS) do
			if db[key] then return true end
		end
		return false
	end
end

-- Swing timer page: the ranged bar on top (it and the main hand's trade
-- places), per class so one profile suits them all. To start with, the
-- classes that shoot most: hunters, and the casters with wands.
for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE",
	"WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }) do
	DEFAULTS["swingRangedOnTop" .. class] = class == "HUNTER" or class == "MAGE" or class == "PRIEST"
		or class == "WARLOCK"
end
DEFAULTS.handleFishing = true -- right-click casting and the cast bar
-- The Nameplates grid's rows for particular units, over the kinds above (see
-- Effects): your target, your pet, and your party or raid's players and their
-- pets. Same columns as the kinds. Your target and group members (with their
-- pets) are kept up everywhere to start with.
-- (Your target's rows, the Target Nameplate grid: ns.PLATE_TARGET_ROWS.)
ns.PLATE_TARGET_ROWS = { "MyEnemyPlayerTarget", "MyEnemyNPCTarget", "MyNeutralPlayerTarget", "MyNeutralNPCTarget",
	"MyFriendlyPlayerTarget", "MyFriendlyNPCTarget" }
ns.PLATE_UNIT_ROWS = { "MyPet", "GroupMembers", "GroupMinions" }
for _, row in ipairs(ns.PLATE_TARGET_ROWS) do
	table.insert(ns.PLATE_UNIT_ROWS, row)
end
for _, row in ipairs(ns.PLATE_UNIT_ROWS) do
	for _, prefix in ipairs({ "plateAlways", "plateCombat", "plateCombatPvP", "plateCinematic", "plateGroup" }) do
		DEFAULTS[prefix .. row] = false
	end
	for _, suffix in ipairs(ns.PLATE_PLACES) do
		DEFAULTS["plateIn" .. suffix .. row] = false
	end
end
for _, row in ipairs(ns.PLATE_TARGET_ROWS) do
	DEFAULTS["plateAlways" .. row] = true
end
DEFAULTS.plateAlwaysGroupMembers = true
DEFAULTS.plateAlwaysGroupMinions = true
-- The Plate Parts grid's rows (see PlateParts): each part of the plates that
-- are up, with the same columns (keys plate<column>Part<part>). All shown
-- everywhere to start with, as the game has them.
ns.PLATE_PARTS = { "Health", "Name", "CastBar", "Buffs", "Debuffs", "RaidMarker", "Classification", "Level",
	"Threat", "Highlight", "Widgets" }
for _, part in ipairs(ns.PLATE_PARTS) do
	for _, prefix in ipairs({ "plateAlways", "plateCombat", "plateCombatPvP", "plateCinematic", "plateGroup" }) do
		DEFAULTS[prefix .. "Part" .. part] = prefix == "plateAlways"
	end
	for _, suffix in ipairs(ns.PLATE_PLACES) do
		DEFAULTS["plateIn" .. suffix .. "Part" .. part] = false
	end
end
-- The Unit Frames page's Unit frame parts grids (see Frames), a column per
-- part: your own frame and your pet's (keys unitPartPlayer<part>,
-- unitPartPet<part>), then the target, focus and target of target frames, a
-- row per kind of unit they show (keys unitPart<kind><part> for the target,
-- unitPartFocus<kind><part> and unitPartToT<kind><part>). The focus and
-- target of target go as the target's grid says until their "Same as target"
-- is unticked. All shown to start with, as the game has them. Some parts
-- only on some rows (UNIT_PART_ONLY): the hit text on your and your pet's
-- portraits, and threat on NPCs you can fight. (The cast bar: the target's
-- and focus's only, the frames that have one.)
ns.UNIT_PART_KINDS = { "Self", "EnemyPlayer", "EnemyNPC", "NeutralPlayer", "NeutralNPC", "FriendlyPlayer",
	"FriendlyNPC" }
ns.UNIT_PARTS = { "Portrait", "Name", "Level", "Art", "PvP", "Icons", "Auras", "CombatText", "Threat", "CastBar" }
ns.UNIT_PART_ONLY = {
	CombatText = { Player = true, Pet = true },
	Threat = { EnemyNPC = true, NeutralNPC = true },
}
for _, part in ipairs(ns.UNIT_PARTS) do
	local only = ns.UNIT_PART_ONLY[part]
	for _, row in ipairs({ "Player", "Pet" }) do
		if not only or only[row] then
			DEFAULTS["unitPart" .. row .. part] = true
		end
	end
	for _, kind in ipairs(ns.UNIT_PART_KINDS) do
		if not only or only[kind] then
			for _, prefix in ipairs({ "", "Focus", "ToT" }) do
				DEFAULTS["unitPart" .. prefix .. kind .. part] = true
			end
		end
	end
end
DEFAULTS.unitPartsFocusSame = true
DEFAULTS.unitPartsToTSame = true
-- And rows of our own: a class icon by friendly and by enemy players' health
-- bars (as Duel Vision shows), and a role icon by group members' (tank,
-- healer, damage). Off everywhere to start with, except enemy class icons and
-- tank and healer role icons: shown always.
ns.PLATE_CLASS_PARTS = { "ClassFriendly", "ClassEnemy" }
ns.PLATE_ROLE_PARTS = { "RoleTank", "RoleHealer", "RoleDamager" }
ns.PLATE_ICON_PARTS = { "ClassFriendly", "ClassEnemy", "RoleTank", "RoleHealer", "RoleDamager" }
ns.PLATE_ICONS_ALWAYS = { "ClassEnemy", "RoleTank", "RoleHealer" }
for _, part in ipairs(ns.PLATE_ICON_PARTS) do
	for _, prefix in ipairs({ "plateAlways", "plateCombat", "plateCombatPvP", "plateCinematic", "plateGroup" }) do
		DEFAULTS[prefix .. "Part" .. part] = false
	end
	for _, suffix in ipairs(ns.PLATE_PLACES) do
		DEFAULTS["plateIn" .. suffix .. "Part" .. part] = false
	end
end
for _, part in ipairs(ns.PLATE_ICONS_ALWAYS) do
	DEFAULTS["plateAlwaysPart" .. part] = true
end
-- Names likewise (the groups are in Effects): kept up in fights, and in each place.
for _, key in ipairs({ "Self", "NPCs", "Critters", "Friends", "FriendlyMinions", "Enemies", "EnemyMinions" }) do
	DEFAULTS["nameCombat" .. key], DEFAULTS["nameCombatPvP" .. key] = false, false
	for _, suffix in ipairs(ns.PLATE_PLACES) do
		DEFAULTS["nameIn" .. suffix .. key] = false
	end
end
DEFAULTS.nameInPvPEnemies = true
DEFAULTS.nameInPvPEnemyMinions = true
DEFAULTS.nameInBGsEnemies = true
DEFAULTS.nameInBGsEnemyMinions = true
-- Both grids' Grouped column: the row stays up in a party or raid, in fights
-- and out, whatever its other boxes say. Friendly players and their minions by
-- default. Their Always column likewise, everywhere (none by default).
for _, kind in ipairs(ns.PLATE_KINDS) do
	DEFAULTS["plateGroup" .. kind] = kind == "Friends" or kind == "FriendlyMinions"
	DEFAULTS["plateAlways" .. kind] = false
end
for _, key in ipairs({ "Self", "NPCs", "Critters", "Friends", "FriendlyMinions", "Enemies", "EnemyMinions" }) do
	DEFAULTS["nameGroup" .. key] = false
	DEFAULTS["nameAlways" .. key] = false
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
DEFAULTS.taxiZoomPause = 7
-- Seconds the pause between random zooms may run over or under <prefix>Pause.
for _, prefix in ipairs({ "idleZoom", "taxiZoom", "walkZoom", "runZoom", "cozyZoom", "vistaZoom", "fishZoom" }) do
	DEFAULTS[prefix .. "PauseVary"] = 0
end
DEFAULTS.taxiZoomPauseVary = 3
-- Depth of field (faked): a soft haze round the screen edges in the camera
-- modes. One switch for all (on the Visual Effects page), then a strength
-- per mode (0 is off there).
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
-- After a fight, login, /reload or turning it on, cinematic mode starts at
-- once instead of waiting the fade delay (until something else brings the UI back).
local quickStart = false

function ns.Print(msg)
	print("|cffe0b050Cinematic:|r " .. msg)
	ns.Log("chat", msg)
end

local function AnyShown(names)
	for _, name in ipairs(names) do
		local frame = _G[name]
		if frame and ns.Flag(frame:IsShown()) then
			return true
		end
	end
	return false
end

-- fn's answer kept for the rest of the frame: for lookups asked many times a
-- frame (the camera modes ask a dozen) whose answer only changes with events,
-- which come between frames.
local function OncePerFrame(fn)
	local at, value = -1, nil
	return function()
		local now = GetTime()
		if now ~= at then
			at, value = now, fn()
		end
		return value
	end
end

-- Talking to an NPC: their windows, plus quest givers, gossip and the flight
-- map. The camera modes wait while one is open.
local NPC_WINDOWS = {
	"GossipFrame", "QuestFrame", "TaxiFrame", "ItemTextFrame",
}
for _, name in ipairs(REVEAL_AT_NPCS) do NPC_WINDOWS[#NPC_WINDOWS + 1] = name end
-- Windows /cine add must never fade (see Frames.lua).
ns.WINDOWS = {}
for _, list in ipairs({ REVEAL_WHILE_SHOWN, NPC_WINDOWS }) do
	for _, name in ipairs(list) do ns.WINDOWS[name] = true end
end
function ns.NPCWindowOpen()
	return AnyShown(NPC_WINDOWS)
end
ns.NPCWindowOpen = ns.Profiled("NPCWindowOpen", OncePerFrame(ns.NPCWindowOpen))

-- Menus and game windows (the Escape menu, options, spellbook, character
-- sheet, map...). The camera modes wait while one is open. The barbershop's
-- chair counts too: it sets up its own camera.
local MENU_WINDOWS = {
	"GameMenuFrame", "WorldMapFrame", "QuestLogFrame", "FriendsFrame", "PVEFrame",
	"CollectionsJournal", "EncounterJournal", "AchievementFrame", "CommunitiesFrame",
	"ProfessionsFrame", "TradeSkillFrame", "CraftFrame", "AddonList", "ChatConfigFrame",
	"VideoOptionsFrame", "BarberShopFrame",
}
for _, name in ipairs(REVEAL_WHILE_SHOWN) do MENU_WINDOWS[#MENU_WINDOWS + 1] = name end
function ns.MenuWindowOpen()
	return AnyShown(MENU_WINDOWS)
end
ns.MenuWindowOpen = ns.Profiled("MenuWindowOpen", OncePerFrame(ns.MenuWindowOpen))

local function AnyRevealFrameShown()
	return (not ns.db.stayWithWindows and AnyShown(REVEAL_WHILE_SHOWN))
		or (ns.db.revealAtNPCs and AnyShown(REVEAL_AT_NPCS))
end

-- How long things take to fade out: the Combat fade out time for fades that
-- start within the Calm Timer (calmTime) after a fight, the Fade out time for
-- the rest. The window runs on past the Calm Timer long enough for either
-- fade to finish, so one doesn't change speed halfway.
local fightEndedAt = -math.huge
local fightEndWatcher = CreateFrame("Frame")
fightEndWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
fightEndWatcher:SetScript("OnEvent", function() fightEndedAt = GetTime() end)

function ns.FadeOutTime()
	local db = ns.db
	if InCombatLockdown() then
		return db.combatFadeOutTime -- (hidden in fights: the combat speed too)
	end
	local window = (db.calmTime or 0) + math.max(db.fadeOutTime, db.combatFadeOutTime)
	return GetTime() - fightEndedAt < window and db.combatFadeOutTime or db.fadeOutTime
end

-- How long things take to fade in: the Combat fade in time during a fight
-- (the UI coming back as one starts), the Fade in time otherwise.
function ns.FadeInTime()
	local db = ns.db
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		return db.combatFadeInTime
	end
	return db.fadeInTime
end

-- Unit queries can return "secret" values during combat, which can't even be
-- tested for truth. Treat those as false.
local function Flag(value)
	if issecretvalue and issecretvalue(value) then
		return false
	end
	return value and true or false
end

-- Whether a unit counts as an enemy for the enemy target choices: one you can
-- attack (neutral mobs too), or the other faction's player even while they
-- aren't flagged for PvP. nil when the game won't say (secret values).
function ns.IsEnemyUnit(unit)
	local ok, attackable = pcall(UnitCanAttack, "player", unit)
	if not ok or (issecretvalue and issecretvalue(attackable)) then
		return nil
	end
	if attackable then
		return true
	end
	local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
	local okFriend, friend = pcall(UnitIsFriend, "player", unit)
	if okPlayer and okFriend and Flag(isPlayer) and not (issecretvalue and issecretvalue(friend)) then
		return not friend
	end
	return false
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

-- "Turn off in" Moving: walking or riding about yourself. Auto-run, RP
-- walking and flights carry on in CineMode. It comes back once you've moved,
-- or stood still, for movingBackAfter seconds.
-- Timed from when you last took over yourself: starting to move, or ending
-- an auto-run or RP walk (say, pressing forward) without stopping.
local movingOffSince
local function MovingFor()
	if not ns.db.offWhileMoving or not ns.playerMoving or UnitOnTaxi("player")
		or (ns.IsAutoRunning and ns.IsAutoRunning()) or (ns.IsRPWalking and ns.IsRPWalking()) then
		movingOffSince = nil
		return nil
	end
	local started = ns.movingSince or GetTime()
	if movingOffSince == nil or movingOffSince < started then
		movingOffSince = movingOffSince and started or GetTime()
	end
	return GetTime() - movingOffSince
end

local function MovingWait()
	return math.max(1, ns.db.movingBackAfter or DEFAULTS.movingBackAfter)
end

local function MovingOff()
	local moving = MovingFor()
	return moving ~= nil and moving < MovingWait()
end

local function LongMove()
	local moving = MovingFor()
	return moving ~= nil and moving >= MovingWait()
end
local lastMovingOff = -math.huge -- when Moving last kept CineMode off
local offForMoving = false -- this tick, Moving (and nothing else) kept CineMode off

local function IsBusy()
	local inCombat = InCombatLockdown() or Flag(UnitAffectingCombat("player"))
	if inCombat and not ns.db.stayInCombat then
		return true
	end
	-- Targeting never brings the whole UI back; it shows the Standard Frames page's
	-- target lists instead (see GetCombatShownFrames).
	-- Dead: the UI comes back, unless the death camera is watching (then the
	-- release button, a popup, shows anyway). A ghost keeps cinematic mode as
	-- usual: the corpse run is just travel (Return to Graveyard isn't faded).
	local corpse = Flag(UnitIsDead("player")) and not Flag(UnitIsGhost("player"))
	return (corpse and not (ns.IsDeathCinematic and ns.IsDeathCinematic()))
		or (ns.db.revealOnCast and (Flag(UnitCastingInfo("player")) or Flag(UnitChannelInfo("player")))
			and not (ns.IsFishingEvent and ns.IsFishingEvent())
			and not (ns.IsDepartEvent and ns.IsDepartEvent()))
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
ns.GetPlaceType = ns.Profiled("GetPlaceType", OncePerFrame(ns.GetPlaceType))

-- Flagged for PvP (or free-for-all PvP).
local function IsPvPFlagged()
	return Flag(UnitIsPVP("player")) or (UnitIsPVPFreeForAll and Flag(UnitIsPVPFreeForAll("player")))
end
ns.IsPvPFlagged = IsPvPFlagged

-- The place for the per-place options: as ns.GetPlaceType, except that an
-- inn counts as the open world (nil), and being flagged for PvP counts as
-- PvP (battlegrounds and arenas too) anywhere but dungeons and raids, and
-- not on flights. (The inn glow still tells inns apart.)
function ns.GetOptionPlace()
	local place = ns.GetPlaceType()
	if place == "pvp" or place == "dungeon" or place == "raid" then
		return place
	end
	if IsPvPFlagged() and not UnitOnTaxi("player") then
		return "pvp"
	end
	return place ~= "inn" and place or nil
end

local OFF_IN = {
	city = "offInCities", dungeon = "offInDungeons", raid = "offInRaids", pvp = "offInPvP",
}
ns.CHAT_IN = {
	city = "chatInCities", dungeon = "chatInDungeons", raid = "chatInRaids", pvp = "chatInPvP",
}

local PLACE_SUFFIX = { city = "Cities", dungeon = "Dungeons", raid = "Raids", pvp = "PvP" }

-- The place you're in as the options' keys name it ("Cities", "Dungeons"...),
-- or nil for the open world (inns too).
function ns.PlaceSuffix()
	local place = ns.GetOptionPlace()
	return place and PLACE_SUFFIX[place]
end

-- The same for the Nameplates page, whose columns are its own: cities go with
-- the open world, dungeons and raids are one ("Instances"), and battlegrounds
-- and arenas ("BGs") are apart from being flagged elsewhere ("PvP").
function ns.PlateSuffix()
	if ns.GetPlaceType() == "pvp" then
		return "BGs"
	end
	local place = ns.GetOptionPlace()
	if place == "city" then
		return nil
	end
	if place == "dungeon" or place == "raid" then
		return "Instances"
	end
	return place and PLACE_SUFFIX[place]
end

-- A camera mode ("flight", "idle", "cozy"... see ns.CAMERA_OFF_CAMS) turned
-- off where you are. Where: a capital city, an
-- instance (dungeons, scenarios, raids, battlegrounds and arenas) or the open
-- world (inns too, PvP flagged or not). A flight doesn't count as being in a
-- city (see ns.GetPlaceType): for it, Cities means taking off from one
-- (db.takeoffInCity, noted at takeoff), and the open world anywhere else.
local CAMERA_OFF_PLACE = { city = "Cities", dungeon = "Instances", raid = "Instances", pvp = "BGs" }
-- Where you are, as those grids' columns name it.
function ns.EffectPlace()
	return CAMERA_OFF_PLACE[ns.GetPlaceType()] or "World"
end
local SWITCHED_CAMS = { walk = "walkCamera", run = "runCamera" }
-- When this auto-walk and auto-run started, for their cameras' delays: noted
-- every frame by the orbit (ns.NoteTravel), and on first asking.
ns.travelSince = {}
function ns.NoteTravel(walking, autoRunning)
	local now = GetTime()
	ns.travelSince.walk = walking and (ns.travelSince.walk or now) or nil
	ns.travelSince.run = autoRunning and (ns.travelSince.run or now) or nil
end
function ns.IsCameraOffHere(cam)
	local db = ns.db
	if not db then return false end
	if SWITCHED_CAMS[cam] and db[SWITCHED_CAMS[cam]] == "none" then
		return true
	end
	-- Not auto-walking or auto-running long enough yet (the delay sliders).
	if SWITCHED_CAMS[cam] and (db[cam .. "CameraDelay"] or 0) > 0 then
		local since = ns.travelSince[cam] or GetTime()
		ns.travelSince[cam] = since
		if GetTime() - since < db[cam .. "CameraDelay"] then
			return true
		end
	end
	local place
	if cam == "flight" and UnitOnTaxi("player") then
		place = db.takeoffInCity and "Cities" or "World"
	else
		place = CAMERA_OFF_PLACE[ns.GetPlaceType()] or "World"
	end
	return db[cam .. "OffIn" .. place] or false
end
ns.IsCameraOffHere = ns.Profiled("IsCameraOffHere", ns.IsCameraOffHere)

function ns.IsMusicBlocked()
	local place = ns.PlaceSuffix()
	return place ~= nil and ns.db["musicOffIn" .. place] or false
end

-- Tracking doesn't keep the minimap up here (Minimap page, "Except in").
-- Going by where you are, not your PvP flag: PvP here means battlegrounds and
-- arenas, since flagged out in the world (always, on a PvP realm) is still
-- gathering country.
function ns.IsTrackingOffHere()
	local place = PLACE_SUFFIX[ns.GetPlaceType() or ""]
	return place ~= nil and ns.db["trackingOffIn" .. place] or false
end

local function IsInDisabledZone()
	local place = ns.GetOptionPlace()
	if place == nil then
		-- The open world (inns too). Flights still go cinematic, as they do leaving a city.
		return ns.db.offInWorld and not UnitOnTaxi("player") and not IsInInstance() or false
	end
	return ns.db[OFF_IN[place]] or false
end

-- /cine debug group: Cinematic acts as if you're in a party or raid ("party"
-- or "raid"; nil: as you are), to try its group options on your own. Session
-- only. The game's own frames (raid frames and the like) still go by the real group.
ns.fakeGroup = nil
function ns.InGroup()
	return ns.fakeGroup ~= nil or IsInGroup()
end
function ns.InRaid()
	return ns.fakeGroup == "raid" or IsInRaid()
end

-- "Turn off in" a party or raid group: who you're with, not where you are.
local function IsInDisabledGroup()
	if ns.InRaid() then
		return ns.db.offInRaidGroup
	end
	return ns.InGroup() and ns.db.offInParty
end

-- "Turn off for a while" from the minimap menu. Session only: a reload or
-- logout clears it.
local snoozeUntil = 0

-- A change to the CineMode page's "Turn off in" boxes (Combat among them)
-- that lets CineMode back starts it at once, with no "Back into CineMode
-- after" wait. Until CineMode starts.
local switchedOn = false
local OFF_IN_KEYS = {
	"stayInCombat", "offInWorld", "offInCities", "offInDungeons", "offInRaids", "offInPvP", "offInParty",
	"offInRaidGroup", "offWhileMoving",
}
local offInWas = {}
local function OffInChanged()
	local changed = false
	for _, key in ipairs(OFF_IN_KEYS) do
		local on = ns.db[key] and true or false
		if offInWas[key] ~= nil and offInWas[key] ~= on then
			changed = true
		end
		offInWas[key] = on
	end
	return changed
end

local function ShouldBeCinematic(now)
	ns.cineOffWhy = "an error (see /cine log)" -- (until a return below says otherwise)
	local changed = OffInChanged()
	MovingFor() -- (each tick, so its timer sees every auto-run and stop)
	-- Switched off, or in a place or group where it's off: once that ends
	-- (switched on, or you leave), straight back, at the fade out time. With
	-- "Start in CineMode" off, only while a camera ticked in the Camera
	-- Triggers page's CineMode column runs.
	if not ns.db.enabled or not (ns.db.fadeUI or ns.TriggerStartsCine()) or not ns.ProfileChosen()
		or GetTime() < snoozeUntil
		or IsInDisabledZone() or IsInDisabledGroup() then
		quickStart = false
		-- (For the log: why CineMode is off. See OnUpdate.)
		ns.cineOffWhy = (not ns.db.enabled and "switched off")
			or (not ns.db.fadeUI and not ns.TriggerStartsCine() and ("no CineMode trigger (place %s, moving %s, " ..
				"auto-run flag %s, auto-running %s, run cam off here %s)"):format(tostring(ns.GetPlaceType()),
				tostring(ns.playerMoving), tostring(ns.autoRunning), tostring(ns.IsAutoRunning and ns.IsAutoRunning()),
				tostring(ns.IsCameraOffHere("run"))))
			or (GetTime() < snoozeUntil and "snoozed") or "turned off here"
		return false
	end
	if changed then
		switchedOn = true
	end
	if IsBusy() then
		lastBusy = now
		-- Only the fight itself counts: anything else (a cast, a window) still
		-- busy as it ends waits the full fade delay.
		quickStart = not ns.db.stayInCombat
			and (InCombatLockdown() or Flag(UnitAffectingCombat("player"))) and true or false
		ns.cineOffWhy = "busy (combat, cast, window or cursor)"
		return false
	end
	-- Flights: right away with the option on, or as the flight event's delay ends.
	local instant = (ns.FlightStarted and ns.FlightStarted() and ns.db.taxiInstant)
		or (ns.db.walkInstant and ns.IsRPWalking())
		or (ns.db.runInstant and ns.IsAutoRunning())
		or (ns.ActiveEvent and ns.ActiveEvent())
		or (ns.IsDeathCinematic and ns.IsDeathCinematic())
		or LongMove()
	-- Moving: back once you've moved on, or stood still, for its own time
	-- (not the "Back into CineMode after" one).
	if MovingOff() then
		lastMovingOff = now
		offForMoving = true
		ns.cineOffWhy = "moving (Off while moving)"
		return false
	end
	if instant or not ns.db.offWhileMoving then
		lastMovingOff = -math.huge
	elseif now - lastMovingOff < MovingWait() then
		offForMoving = true
		ns.cineOffWhy = "just moved (Off while moving)"
		return false
	end
	-- Otherwise things must stay calm (no cast, window or the like) for the
	-- "Back into CineMode after" time first. After fights and at login, at once.
	local delay = (instant or quickStart or switchedOn) and 0 or ns.db.returnDelay
	if now - lastBusy >= delay then
		switchedOn = false
		return true
	end
	ns.cineOffWhy = ("waiting out Back into CineMode after (%.0f of %d sec)"):format(now - lastBusy, delay)
	return false
end

-- Settings held by a set marked playerWins, and the value written: if the
-- player (or another addon) changes one meanwhile, theirs stands. It's let go
-- rather than put back later, which would undo their change.
local heldCVars = {} -- [lowercased cvar] = { name = cvar, value = written }
local writingCVar = false

local function SameValue(a, b)
	return a == b or (tonumber(a) ~= nil and tonumber(a) == tonumber(b))
end

-- Held settings another addon changed in a pass of its own (see
-- ns.RunOthersCVarPass), to be written back after it: [lowercased cvar] = true.
local othersPass = 0
local overridden = {}

local function CheckHeldCVar(name)
	if writingCVar or type(name) ~= "string" then
		return
	end
	local held = heldCVars[name:lower()]
	if not held then
		return
	end
	if othersPass > 0 then
		overridden[name:lower()] = true
		return
	end
	local now = GetCVar(held.name)
	if now ~= nil and not SameValue(now, held.value) then
		heldCVars[name:lower()] = nil
		ns.db.savedCVars[held.name] = nil
		ns.Log("cvar", ("%s changed to %s outside the addon: left as is"):format(held.name, tostring(now)))
	end
end

if C_CVar and C_CVar.SetCVar then
	hooksecurefunc(C_CVar, "SetCVar", ns.Profiled("SetCVar hook", CheckHeldCVar))
end
hooksecurefunc("SetCVar", ns.Profiled("SetCVar hook", CheckHeldCVar))
-- Changes made outside Lua (console commands) only show up as this event.
local heldWatcher = CreateFrame("Frame")
heldWatcher:RegisterEvent("CVAR_UPDATE") -- (its script is below)

-- Whether a set has this setting switched off for now (and will put it back).
function ns.IsCVarHeld(cvar)
	return heldCVars[cvar:lower()] ~= nil
end

-- Called after each setting the addon writes, with its name: for addons that
-- keep their own copy of settings (see Support/Plater.lua).
ns.cvarWrittenHooks = {}

local function WriteCVar(cvar, value)
	writingCVar = true
	SetCVar(cvar, value)
	writingCVar = false
	for _, hook in ipairs(ns.cvarWrittenHooks) do
		hook(cvar)
	end
end

-- Held settings changed in another addon's pass written back. Plate and name
-- settings wait for the end of a fight.
local function WriteBackOverridden()
	for key in pairs(overridden) do
		local held = heldCVars[key]
		if not held then
			overridden[key] = nil
		elseif not ((held.name:find("^nameplate") or held.name:find("^UnitName")) and InCombatLockdown()) then
			overridden[key] = nil
			if not SameValue(GetCVar(held.name), held.value) then
				ns.Log("cvar", ("%s changed by another addon: put back to %s"):format(held.name, tostring(held.value)))
				WriteCVar(held.name, held.value)
			end
		end
	end
end
heldWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
heldWatcher:SetScript("OnEvent", ns.Profiled("CVAR_UPDATE event", function(_, event, name)
	if event == "PLAYER_REGEN_ENABLED" then
		WriteBackOverridden()
	else
		CheckHeldCVar(name)
	end
end))

-- Runs fn(...), an addon setting the game's settings of its own accord (not
-- the player's doing): settings held meanwhile stay held and are written back
-- after it, rather than let go.
function ns.RunOthersCVarPass(fn, ...)
	othersPass = othersPass + 1
	local results = { pcall(fn, ...) }
	othersPass = othersPass - 1
	if othersPass == 0 then
		WriteBackOverridden()
	end
	if not results[1] then
		error(results[2], 0)
	end
	return unpack(results, 2)
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
				WriteCVar(cvar, value)
				if set.playerWins then
					heldCVars[cvar:lower()] = { name = cvar, value = value }
				end
			end
		else
			heldCVars[cvar:lower()] = nil
			if ns.db.savedCVars[cvar] ~= nil then
				ns.LogDetail("cvar", ("%s back to %s"):format(cvar, tostring(ns.db.savedCVars[cvar])))
				WriteCVar(cvar, ns.db.savedCVars[cvar])
				ns.db.savedCVars[cvar] = nil
			end
		end
	end
end

-- Puts back anything left over from a session that ended without restoring.
-- Plate and name settings can't change in combat: they wait for it to end.
local function RestoreSavedCVars()
	for cvar, value in pairs(ns.db.savedCVars) do
		local secure = cvar:find("^nameplate") or cvar:find("^UnitName")
		if not (secure and InCombatLockdown()) then
			-- Skip values that are already right: writing a test_ CVar at all
			-- brings up Blizzard's experimental-camera warning.
			local now = GetCVar(cvar)
			local same = now == value or (tonumber(now) ~= nil and tonumber(now) == tonumber(value))
			if not same then
				ns.Log("cvar", ("%s put back to %s (left over)"):format(cvar, tostring(value)))
				WriteCVar(cvar, value)
			end
			heldCVars[cvar:lower()] = nil
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
	local started, memory
	if ns.profiling then
		started, memory = ns.ProfileMark()
	end
	local ok, result = xpcall(RunStep, StepHandler)
	if started then
		ns.ProfileStep(fn, started, memory) -- (/cine debug cpu)
	end
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
OnOrbitUpdate = ns.Profiled("Orbit camera (every frame)", OnOrbitUpdate)

-- Set at login (and on turning it on) when cinematic mode starts at once: the first cinematic tick
-- within this window snaps straight to cinematic. Expires so a busy login
-- (say, an enemy targeted) falls back to the normal fade later.
-- Frames found during the window snap too (UI addons make some a moment after
-- login), so it's scanned for them more often meanwhile. snapRound marks the
-- frames already snapped, so one shown again (hovered, say) stays shown.
local START_SNAP_WINDOW = 5
local START_SCAN_INTERVAL = 0.5
local startSnapUntil = 0
local snapRound = 0

-- The effects in the Visual Effects page's grid: off where ticked, off in
-- fights (and until the Calm Timer, db.calmTime, has run out after one), or
-- only while a camera mode runs.
local GRID_EFFECTS = { "letterbox", "tint", "vignette", "weather" }
local effectWanted = {}
local lastFightAt = -math.huge

local function OnUpdate(_, elapsed)
	-- Every frame (with EllesmereUI, or watching with /cine debug alpha): frames
	-- setting their own alpha are faded again before they're drawn.
	if (ns.syncEveryFrame or ns.alphaWatch) and ns.SyncOwnAlphas then
		Step(ns.SyncOwnAlphas)
	end
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
	local starting = GetTime() < startSnapUntil
	sinceScan = sinceScan + elapsed
	if sinceScan >= (starting and START_SCAN_INTERVAL or ns.SCAN_INTERVAL) then
		sinceScan = 0
		Step(ns.BuildManagedList)
		if ns.UpdateMinimapButton then Step(ns.UpdateMinimapButton) end
	end

	Step(UpdateDroppedTarget)
	offForMoving = false
	local cinematic = Step(ShouldBeCinematic, GetTime()) or false -- (an error: the normal UI)
	if cinematic and starting then
		-- Start in cinematic mode: hide the UI at once instead of fading. The
		-- letterbox bars still slide in at their usual pace.
		for _, entry in ipairs(ns.managed) do
			if entry.snapRound ~= snapRound then
				entry.snapRound = snapRound
				Step(ns.SetEntryAlpha, entry, 0)
			end
		end
	end
	if cinematic ~= ns.lastCinematic then
		ns.Log("state", cinematic and "cinematic" or ("normal UI: " .. tostring(ns.cineOffWhy)))
	end
	Step(ns.UpdateFrames, cinematic, elapsed)
	-- The letterbox, tint, vignette and weather each show except where their grid row says. One
	-- kept out of fights waits out the Calm Timer after one before fading back in.
	local now = GetTime()
	local inCombat = InCombatLockdown() or Flag(UnitAffectingCombat("player"))
	if inCombat then
		lastFightAt = now
	end
	local fighting = inCombat or now - lastFightAt < ns.db.calmTime
	local place = ns.EffectPlace()
	-- In CineMode; with Start in CineMode (fadeUI) off, over the normal UI (the VFX Only profile);
	-- and while just moving about takes you out of it, with Keep VFX on.
	local effectsOn = cinematic or (not ns.db.fadeUI and ns.db.enabled and ns.ProfileChosen())
		or (offForMoving and ns.db.movingKeepVFX) or false
	for _, key in ipairs(GRID_EFFECTS) do
		effectWanted[key] = effectsOn and ns.db.visualEffects and not ns.db[key .. "OffIn" .. place]
			and not (ns.db[key .. "OffInCombat"] and fighting)
			and not (ns.db[key .. "OnlyInCameras"] and not ns.activeCam)
			and not ns.db[key .. "OffAlways"] or false
	end
	Step(ns.UpdateLetterbox, effectWanted.letterbox, elapsed)
	-- (The vignette and weather share the tint's overlay, each fading on its own.)
	Step(ns.UpdateTint, effectWanted.tint, elapsed, effectWanted.vignette, effectWanted.weather)
	Step(ns.UpdateCVars, cinematic)
	Step(ns.UpdateMusic, cinematic, elapsed)
	Step(ns.UpdatePlates, cinematic, elapsed)
	Step(ns.UpdateTooltip)
	Step(ns.UpdateTaxi)
	if not ns.IsSuspended() then
		ns.lastCinematic = cinematic
	end
end
OnUpdate = ns.Profiled("Update tick", OnUpdate)
ns.ProfileName(UpdateDroppedTarget, "UpdateDroppedTarget")
ns.ProfileName(ShouldBeCinematic, "ShouldBeCinematic")

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
	ns.Print(L["|cffff4040stopped for this session|r (%s) and put your UI and settings back. " ..
		"/cine log has the details for a bug report; /cine resume starts it again."]:format(reason))
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
	if ns.ApplyHealVisionFrames then ns.ApplyHealVisionFrames() end
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
	quickStart = enabled
	if enabled then
		-- Starting at once covers turning it on too: straight in, as at login.
		startSnapUntil = GetTime() + START_SNAP_WINDOW
		snapRound = snapRound + 1
	end
end

-- Switching profiles starts afresh: CineMode comes in now (fading as usual)
-- rather than after the fade delay, and a Calm Timer running from the last
-- fight is dropped (not mid-fight).
function ns.RestartTimers()
	lastBusy = GetTime()
	quickStart = true
	if not (InCombatLockdown() or Flag(UnitAffectingCombat("player"))) then
		fightEndedAt, lastFightAt = -math.huge, -math.huge
	end
end

function Cinematic_Toggle()
	-- No profile picked yet: nothing to turn on; ask for one.
	if not ns.ProfileChosen() then
		ns.ShowWelcome()
		return
	end
	ns.SetEnabled(not ns.db.enabled)
	ns.Print(ns.db.enabled and L["enabled"] or L["disabled"])
	if ns.IsSuspended() then
		ns.Print(L["(still stopped after an error: /cine resume starts it again)"])
	end
end

function Cinematic_FlyBy()
	local _, message = ns.ToggleFlyBy()
	if message then
		ns.Print(L["fly-by: %s"]:format(message))
	end
end

-- Key bindings for the standing-still cameras: each starts its camera now, as
-- if its event had happened, and pressing it again stops it. Moving or jumping
-- ends it, like an emote. "death" runs the death camera test (/cine deathtest).
-- quiet: no messages in chat (the camera wheel).
local CAM_NAMES = { idle = "AFK camera", cozy = "cozy camera", vista = "vista camera", fish = "fish camera",
	tele = "tele camera" }
function Cinematic_StartCam(camera, quiet)
	if not ns.db then
		return
	end
	local Print = quiet and function() end or ns.Print
	local now = GetTime()
	if camera == "death" then
		if now < (ns.deathTestUntil or 0) then
			ns.deathTestUntil = 0
			Print(L["death camera test stopped"])
		elseif not ns.db.deathOrbit then
			Print(L["the death camera is off: turn it on with /cine death first"])
		elseif ns.playerMoving then
			-- (Moving ends the test, like the other cameras.)
			Print(L["stand still to start the %s"]:format(L["death camera"]))
		else
			ns.deathTestUntil, ns.deathTestLoud = now + 30, false
			Print(L["death camera test for 30 seconds: stand still and it starts after %.1f sec. " ..
				"Press the key again to stop it."]:format(ns.db.deathOrbitDelay))
		end
		return
	end
	if not ns.db.enabled then
		Print(L["Cinematic is off: turn it on first"])
		return
	end
	if ns.playerMoving or UnitOnTaxi("player") then
		Print(L["stand still to start the %s"]:format(L[CAM_NAMES[camera]]))
		return
	end
	local idleOn = camera == "idle" and ns.stillSince ~= nil and now - ns.stillSince >= ns.db.idleOrbitDelay
		and not ns.manualCam
	-- (The AFK camera's key runs it as an event set to it, so it starts even
	-- with Stand still set to another camera or none.)
	local manual = camera == "idle" and "afk" or camera
	if ns.manualCam == manual or idleOn then
		ns.manualCam = nil
		ns.stillSince = now -- the standing-still timer starts afresh
		Print(L["%s stopped"]:format(L[CAM_NAMES[camera]]))
		return
	end
	if camera == "idle" and not ns.db.idleOrbit then
		Print(L["the AFK camera's rotation is off in Camera Settings"])
		return
	end
	ns.manualCam = manual
	if camera == "tele" then
		ns.PretendDepartCast(10) -- (the usual Hearthstone cast: the spin and zoom need one)
	end
	ns.stillSince = now - ns.db.idleOrbitDelay -- counts as stood still long enough
	lastBusy = 0 -- fade the UI now
	Print(L["%s on: move, jump or press the key again to stop it"]:format(L[CAM_NAMES[camera]]))
end

function Cinematic_ToggleUI()
	ns.ToggleUI()
end

function ns.EnsureTables()
	ns.db.extraFrames = ns.db.extraFrames or {}
	ns.db.ignoredFrames = ns.db.ignoredFrames or {}
	ns.db.addonFrames = ns.db.addonFrames or {} -- Advanced Frames page: key -> false when switched off
	-- Advanced Frames page: suite -> true when opened (they start collapsed).
	ns.db.addonSuitesOpen = ns.db.addonSuitesOpen or {}
	ns.db.addonSuitesClosed = nil -- (a test build's: they started open then)
	ns.db.savedCVars = ns.db.savedCVars or {}
	ns.db.chatPeekTypes = ns.db.chatPeekTypes or {}
	ns.db.chatPeekChannelList = ns.db.chatPeekChannelList or { General = false, LocalDefense = false }
	ns.db.flightTimes = ns.db.flightTimes or {}
	ns.db.zoneTints = ns.db.zoneTints or {} -- zone name -> "none", a mood key or { r, g, b }
	ns.db.zoneTintStrength = ns.db.zoneTintStrength or {} -- zone name -> strength (0-1) for the Zone presets
	ns.db.zonePresets = ns.db.zonePresets or {} -- zone or area name -> tint preset key used there instead of tintPreset
	ns.db.timePhaseColors = ns.db.timePhaseColors or {} -- "Night", "Dawn"... -> { r, g, b } of your own
	ns.db.timePhaseStrength = ns.db.timePhaseStrength or {} -- "Night", "Dawn"... -> strength (0-1) of your own
	ns.db.combatShow = ns.db.combatShow or {}
	ns.db.cooldownReadyOnly = ns.db.cooldownReadyOnly or {} -- Cooldown Manager page: spell ID -> true
	ns.db.cooldownReadyEarly = ns.db.cooldownReadyEarly or {} -- ...spell ID -> seconds early it comes back
	ns.db.cooldownEarlyOn = ns.db.cooldownEarlyOn or {} -- ...spell ID -> true: Show Early ticked
	ns.db.cooldownEarlyOff = nil -- (a test build's, when Show Early started ticked)
	ns.db.gamepadPressButtons = ns.db.gamepadPressButtons or {} -- Gamepad page: button -> reveals the bars
	ns.db.cineFade = nil -- (a test build's CineMode column, before it became cineShow)
	ns.db.tooltipCineMode = nil -- (a test build's: the Tooltips page's master switch decides now)
	ns.db.cineShow = ns.db.cineShow or {} -- Standard Frames row -> true: shown all through CineMode
	ns.db.frameRules = ns.db.frameRules or {} -- row key -> rule text (Custom Visibility Rules, Advanced Frames page)
	-- Row key -> true: kept hidden in CineMode while you're that role (a frames grid row's roles button).
	ns.db.tankHide = ns.db.tankHide or {}
	ns.db.healerHide = ns.db.healerHide or {}
	ns.db.damageHide = ns.db.damageHide or {}
	ns.db.playerRule = nil -- (a test build's one rule, the player frame's)
	-- The minimap button's old spot, 225 (never dragged: dragging never lands
	-- exactly on it), covered the dungeon finder's eye: the new default.
	if ns.db.minimapAngle == 225 then ns.db.minimapAngle = 205 end
	-- The frames pages' place columns (ns.PLACE_SHOW): row -> true, shown all through CineMode there.
	for _, place in ipairs(ns.PLACE_SHOW) do
		ns.db[place.list] = ns.db[place.list] or {}
	end
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

-- Puts the active profile back to how it started (Profiles.lua): its
-- settings only, so the player's added/ignored frames are kept.
-- (Straight back into CineMode after, as on switching: ResetProfile restarts the timers.)
function ns.ResetSettings()
	ns.ResetProfile()
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
local FLIGHT_USES_DEFAULT = { mouseoverHold = true, buffPeekTime = true, debuffPeekTime = true, chatPeekTime = true }
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
-- (Not one turned off where you are; see ns.IsCameraOffHere.)
function ns.CameraMode()
	if UnitOnTaxi("player") then
		return "flight"
	elseif ns.IsRPWalking and ns.IsRPWalking() then
		return not ns.IsCameraOffHere("walk") and "walk" or nil
	elseif ns.IsAutoRunning and ns.IsAutoRunning() then
		return not ns.IsCameraOffHere("run") and "run" or nil
	elseif ns.IsVista and ns.IsVista() then
		return "vista"
	elseif ns.IsFish and ns.IsFish() then
		return "fish"
	elseif ns.IsCozy and ns.IsCozy() then
		return "cozy"
	end
	local still = ns.GetStillSince()
	if still ~= nil and GetTime() - still >= ns.db.idleOrbitDelay and not ns.IsCameraOffHere("idle")
		and ns.StillRunsAFK() then
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
	quickStart = false
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
ticker:SetScript("OnEvent", ns.Profiled("Core events", function(self, event, arg1, arg2)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		ns.newInstall = CinematicDB == nil -- (for the welcome window: Welcome.lua)
		CinematicDB = CinematicDB or {}
		ns.db = CinematicDB
		-- Floating world text (the XP gained over you, and damage numbers with it:
		-- one font) drawn in a font whose letters are specks too small to see.
		-- The game keeps the font it first loaded, so changes need a game restart.
		if ns.db.hideWorldText then
			DAMAGE_TEXT_FONT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\Blank.ttf"
		end
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
		ns.db.markOther = nil
		-- The AFK camera's "Turn rotation off in" and "Turn zoom off in" (and
		-- before them "Turn camera effects off in") are now its row of the
		-- "Turn off in" grid: off there if either was.
		for _, suffix in ipairs({ "Cities", "Inns", "Dungeons", "Raids", "PvP" }) do
			if ns.db["idleOffIn" .. suffix] == nil then
				local old = ns.db["camOffIn" .. suffix] or ns.db["rotOffIn" .. suffix]
					or ns.db["zoomOffIn" .. suffix]
				if old ~= nil then ns.db["idleOffIn" .. suffix] = old and true or false end
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
		-- Dragging gear out of the bags opening the character window was on for
		-- everyone; where unit values are secret it's off by default now, so turn
		-- it off once there.
		if not ns.db.dragEquipV2 then
			if issecretvalue and ns.db.dragEquipCharacter then ns.db.dragEquipCharacter = nil end
			ns.db.dragEquipV2 = true
		end
		-- The auto-run camera first swung wider; narrow it once, unless changed.
		if not ns.db.runSettingsV2 then
			if ns.db.runOrbitBackArc == 35 then ns.db.runOrbitBackArc = nil end
			if ns.db.runOrbitMinChange == 15 then ns.db.runOrbitMinChange = nil end
			if ns.db.runOrbitPitchUp == 8 then ns.db.runOrbitPitchUp = nil end
			if ns.db.runOrbitPitchDown == 8 then ns.db.runOrbitPitchDown = nil end
			ns.db.runSettingsV2 = true
		end
		-- Standing still first waited 30 sec before the camera started; 60 now, unless changed.
		if not ns.db.stillDelayV2 then
			if ns.db.idleOrbitDelay == 30 then ns.db.idleOrbitDelay = nil end
			ns.db.stillDelayV2 = true
		end
		-- Enemy nameplates were first hidden in fights by default; show them once.
		if not ns.db.plateCombatV2 then
			ns.db.plateCombatMobs = true
			ns.db.plateCombatOther = true
			ns.db.plateCombatV2 = true
		end
		-- "Turn music off on logout" (since removed) was first on by default,
		-- leaving game music switched off outside cinematic mode (and after
		-- removing the addon). Switch game music back on once at login if it did.
		if not ns.db.musicLogoutV1 then
			if ns.db.musicOffOnLogout then
				ns.musicBackOn = true
			end
			ns.db.musicLogoutV1 = true
		end
		ns.db.musicOffOnLogout = nil
		-- "No music while AFK" (Audio page) is now Go AFK's Music column on the
		-- Camera Triggers page, the other way round.
		if ns.db.noMusicWhenAFK == false and ns.db.eventAFKMusic == nil then
			ns.db.eventAFKMusic = true
		end
		-- Stand still with the AFK camera first took Go AFK's music; it has its
		-- own now, so it starts out as Go AFK's was.
		if not ns.db.stillMusicV2 then
			if ns.db.eventStillCamera == "afk" and ns.db.eventAFKMusic == true and ns.db.eventStillMusic == nil then
				ns.db.eventStillMusic = true
			end
			ns.db.stillMusicV2 = true
		end
		-- Tracking's "Except when standing still or flying" (Minimap page) is now
		-- Hide in camera modes, the Flight and AFK boxes.
		if ns.db.trackingHideWhenIdle == false then
			for _, key in ipairs({ "flightHideMinimap", "idleHideMinimap" }) do
				if ns.db[key] == nil then
					ns.db[key] = false
				end
			end
		end
		-- (The migrations below up to the rows' renaming use the old rows.)
		local OLD_PLATE_KINDS = { "Mobs", "NPCs", "Own", "Other", "Pets", "Totems" }
		local OLD_NAME_KEYS = { "Mobs", "NPCs", "Own", "Other", "Pets", "Minions", "Totems", "Self" }
		-- An unticked Show (now "Out of combat") used to hide a kind in fights
		-- too; its In combat tick, greyed out then, would now show it in them.
		if not ns.db.plateOutOfCombatV1 then
			for _, kind in ipairs(OLD_PLATE_KINDS) do
				if ns.db["plateShow" .. kind] == false then
					ns.db["plateCombat" .. kind] = false
				end
			end
			ns.db.plateOutOfCombatV1 = true
		end
		-- The Nameplates page had an Out of combat column (plateShow<kind>) that
		-- also set the game's own nameplate options. It now only steers plates
		-- in cinematic mode, with a column per place: a kind kept up in
		-- cinematic mode stays kept everywhere, unless Out of combat was off.
		if ns.db.plateShowMobs ~= nil then
			for _, kind in ipairs(OLD_PLATE_KINDS) do
				local kept = (ns.db["plateCinematic" .. kind] and ns.db["plateShow" .. kind] ~= false) and true or false
				ns.db["plateCinematic" .. kind] = kept
				for _, suffix in ipairs({ "Cities", "Inns", "Dungeons", "Raids", "PvP" }) do
					ns.db["plateIn" .. suffix .. kind] = kept
				end
			end
		end
		-- "Hide nameplates in cinematic mode" was a switch of its own; with it
		-- off, every kind now stays up everywhere instead.
		if ns.db.hidePlates == false then
			for _, kind in ipairs(OLD_PLATE_KINDS) do
				ns.db["plateCombat" .. kind], ns.db["plateCinematic" .. kind] = true, true
				for _, suffix in ipairs({ "Cities", "Inns", "Dungeons", "Raids", "PvP" }) do
					ns.db["plateIn" .. suffix .. kind] = true
				end
			end
		end
		ns.db.hidePlates = nil
		-- "Hide names in cinematic mode" likewise: off, every name stays up.
		if ns.db.hideNames == false then
			for _, key in ipairs(OLD_NAME_KEYS) do
				ns.db["nameKeep" .. key] = true
			end
		end
		ns.db.hideNames = nil
		-- Names had one Keep column; a kept name stays kept in fights and everywhere.
		if not ns.db.nameGridV1 then
			for _, key in ipairs(OLD_NAME_KEYS) do
				if ns.db["nameKeep" .. key] then
					ns.db["nameCombat" .. key] = true
					for _, suffix in ipairs({ "Cities", "Inns", "Dungeons", "Raids", "PvP" }) do
						ns.db["nameIn" .. suffix .. key] = true
					end
				end
			end
			ns.db.nameGridV1 = true
		end
		-- The Nameplates page's rows now follow the game's own options. Each
		-- new row is ticked in a column wherever an old row it covers was.
		if not ns.db.plateRowsV1 then
			local function Regroup(prefixes, map, oldKeys)
				for _, prefix in ipairs(prefixes) do
					local new = {}
					for newKey, olds in pairs(map) do
						for _, old in ipairs(olds) do
							new[newKey] = new[newKey] or ns.db[prefix .. old] or nil
						end
					end
					for _, old in ipairs(oldKeys) do
						ns.db[prefix .. old] = nil
					end
					for newKey, value in pairs(new) do
						ns.db[prefix .. newKey] = value
					end
				end
			end
			local function Columns(head, open)
				local list = { head .. "Combat", open }
				for _, suffix in ipairs({ "Cities", "Inns", "Dungeons", "Raids", "PvP" }) do
					list[#list + 1] = head .. "In" .. suffix
				end
				return list
			end
			Regroup(Columns("plate", "plateCinematic"), {
				Enemies = { "Mobs", "Other" }, EnemyMinions = { "Pets", "Totems" }, EnemyMinor = { "Mobs" },
				Friends = { "Own" }, FriendlyMinions = { "Pets", "Totems" }, FriendlyNPCs = { "NPCs" },
			}, OLD_PLATE_KINDS)
			Regroup(Columns("name", "nameKeep"), {
				Self = { "Self" }, NPCs = { "Mobs", "NPCs" }, Critters = { "Mobs" }, Friends = { "Own" },
				FriendlyMinions = { "Pets", "Minions", "Totems" }, Enemies = { "Other" },
				EnemyMinions = { "Pets", "Minions", "Totems" },
			}, OLD_NAME_KEYS)
			ns.db.plateRowsV1 = true
		end
		-- Enemy Units split into Enemy Players (still "Enemies") and Enemy NPCs:
		-- the new row starts out ticked wherever the old one was.
		if not ns.db.plateEnemyNPCsV1 then
			for _, prefix in ipairs({ "plateCombat", "plateCinematic", "plateInCities", "plateInInns",
				"plateInDungeons", "plateInRaids", "plateInPvP" }) do
				if ns.db[prefix .. "Enemies"] ~= nil then
					ns.db[prefix .. "EnemyNPCs"] = ns.db[prefix .. "Enemies"]
				end
			end
			ns.db.plateEnemyNPCsV1 = true
		end
		-- The grids' Inns column joined Open world: ticked there wherever either was.
		for _, kind in ipairs(ns.PLATE_KINDS) do
			if ns.db["plateInInns" .. kind] then ns.db["plateCinematic" .. kind] = true end
			ns.db["plateInInns" .. kind] = nil
		end
		for _, group in ipairs(ns.NAME_GROUPS) do
			if ns.db["nameInInns" .. group.key] then ns.db["nameKeep" .. group.key] = true end
			ns.db["nameInInns" .. group.key] = nil
		end
		ns.db.namePlateLinkV1 = nil
		-- The cozy, vista and fish cameras' "Play music" switches became a Music
		-- column per event: each starts from the switch for the camera it's set to.
		if ns.db.musicCamCozy ~= nil or ns.db.musicCamVista ~= nil or ns.db.musicCamFish ~= nil then
			local old = { cozy = ns.db.musicCamCozy, tele = ns.db.musicCamCozy, vista = ns.db.musicCamVista,
				fish = ns.db.musicCamFish }
			for _, event in ipairs(ns.EVENTS) do
				local camera = ns.db["event" .. event.key .. "Camera"] or event.camera
				if ns.EVENT_MUSIC_DEFAULT[event.camera] ~= nil and old[camera] ~= nil
					and ns.db["event" .. event.key .. "Music"] == nil then
					ns.db["event" .. event.key .. "Music"] = old[camera]
				end
			end
			ns.db.musicCamCozy, ns.db.musicCamVista, ns.db.musicCamFish = nil, nil, nil
		end
		-- The Calm Timer replaced the nameplates' linger and the letterbox's and
		-- tint's own waits after a fight; it starts from the linger.
		if ns.db.calmTime == nil then
			ns.db.calmTime = ns.db.plateCombatLinger or ns.db.letterboxCombatWait
		end
		ns.db.plateCombatLinger, ns.db.letterboxCombatWait, ns.db.tintCombatWait = nil, nil, nil
		-- And the buffs' window after a fight and each camera's own wait.
		ns.db.buffPeekCombatWindow, ns.db.musicCombatResume = nil, nil
		ns.db.fadeChat = nil -- (chat always fades in CineMode now; mouseover shows it)
		for _, mode in ipairs({ "taxi", "idle", "walk", "run", "cozy", "vista", "fish", "tele" }) do
			ns.db[mode .. "CombatWait"] = nil
		end
		-- The tele camera's tooltips followed the cozy camera's until it had its own row.
		if ns.db.tooltipOffTele == nil and ns.db.tooltipOffCozy ~= nil then
			ns.db.tooltipOffTele = ns.db.tooltipOffCozy
		end
		-- The tooltips' Never column (no showing again after hovering in a camera mode) is gone.
		for _, mode in ipairs({ "Flight", "Idle", "Cozy", "Tele", "Vista", "Fish", "Walk", "Run", "Death", "Quest" }) do
			ns.db["tooltipNever" .. mode] = nil
		end
		-- Inns had their own place in every "Turn off in" and "Keep ... in" list;
		-- they count as the open world now.
		ns.db.offInInns, ns.db.chatInInns, ns.db.musicOffInInns, ns.db.trackingOffInInns = nil, nil, nil, nil
		for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do
			ns.db[cam[1] .. "OffInInns"] = nil
		end
		-- The "Turn off in" grid had Dungeons, Raids and PvP columns, and Party,
		-- Raid group and In group (gone): now In instance (battlegrounds and
		-- arenas too) and Open world. In instance is ticked if Dungeons or Raids
		-- was (not PvP: that would turn a camera off in dungeons and raids too).
		for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do
			local prefix = cam[1] .. "OffIn"
			local function Merge(new, olds)
				local any, seen = false, false
				for _, old in ipairs(olds) do
					if ns.db[prefix .. old] ~= nil then
						seen = true
						any = any or ns.db[prefix .. old] == true
					end
					ns.db[prefix .. old] = nil
				end
				if seen and ns.db[prefix .. new] == nil then
					ns.db[prefix .. new] = any
				end
			end
			Merge("Instances", { "Dungeons", "Raids" })
			ns.db[prefix .. "PvP"], ns.db[prefix .. "Party"], ns.db[prefix .. "RaidGroup"] = nil, nil, nil
			ns.db[prefix .. "Group"] = nil
			-- It had an Always column too (off everywhere): every place now.
			if ns.db[cam[1] .. "OffAlways"] then
				for _, where in ipairs({ "Cities", "Instances", "World" }) do
					if not (ns.CAMERA_OFF_NEVER[cam[1]] or {})[where] then
						ns.db[prefix .. where] = true
					end
				end
			end
			ns.db[cam[1] .. "OffAlways"] = nil
		end
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
		-- RP walking is deliberate: its camera now runs in cities and instances
		-- too. Once, unless changed.
		if not ns.db.walkSettingsV1 then
			if ns.db.walkOffInCities == true then ns.db.walkOffInCities = nil end
			if ns.db.walkOffInInstances == true then ns.db.walkOffInInstances = nil end
			ns.db.walkSettingsV1 = true
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
		-- "Show buffs when you gain or refresh one" covered debuffs too; now they
		-- have their own switch, on if it was.
		if ns.db.debuffPeek == nil and ns.db.buffPeek ~= nil then
			ns.db.debuffPeek = ns.db.buffPeek
		end
		-- "Show buffs for" covered debuffs too; now they have their own time.
		if ns.db.debuffPeekTime == nil and ns.db.buffPeekTime ~= nil then
			ns.db.debuffPeekTime = ns.db.buffPeekTime
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
		if not ns.db.questCamSettingsV7 then -- the zooms in and back out go by speed, not time
			ns.db.questCamZoomTime, ns.db.questCamZoomOutTime = nil, nil
			ns.db.questCamSettingsV7 = true
		end
		if not ns.db.questCamSettingsV6 then -- a slower zoom back out (walking off, it's still quick)
			if ns.db.questCamZoomOutTime == 1.5 then ns.db.questCamZoomOutTime = nil end
			ns.db.questCamSettingsV6 = true
		end
		if not ns.db.questCamSettingsV5 then -- the side you clicked them on
			if ns.db.questCamSide == "random" then ns.db.questCamSide = nil end
			ns.db.questCamSettingsV5 = true
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
		-- Auto-run's "Play music" was on by default; it's off now, unless changed.
		if not ns.db.runMusicV2 then
			if ns.db.musicCamRun == true then ns.db.musicCamRun = nil end
			ns.db.runMusicV2 = true
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
		-- Gone: "Start music anyway in a new zone" and "Ambience follows music".
		-- (A lowered ambience volume left over is put back with the other settings.)
		ns.db.fatigueIgnoreNewZone, ns.db.lastMusicZone = nil, nil
		ns.db.ambienceFollowsMusic, ns.db.ambienceScale = nil, nil
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
		-- The Hearthstone and teleport events used the cozy camera before the tele
		-- camera existed: that saved choice moves over to it.
		if not ns.db.teleCamV1 then
			for _, key in ipairs({ "eventHearthCamera", "eventTeleportCamera" }) do
				if ns.db[key] == "cozy" then ns.db[key] = nil end
			end
			ns.db.teleCamV1 = true
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
		-- They could also hide the whole time in CineMode (fadeTooltip); now
		-- it's only ever per camera mode.
		ns.db.fadeTooltip = nil
		-- Then tooltips were always hidden, with exceptions: each camera mode's
		-- Hide (tooltipOff*) became its Show anyway (tooltipShowIn*), and
		-- hiding in combat (tooltipCombat and its kinds) went.
		for _, mode in ipairs({ "Flight", "Idle", "Cozy", "Tele", "Vista", "Fish", "Walk", "Run", "Death", "Quest" }) do
			local old = ns.db["tooltipOff" .. mode]
			if old ~= nil and ns.db["tooltipShowIn" .. mode] == nil then
				ns.db["tooltipShowIn" .. mode] = not old
			end
			ns.db["tooltipOff" .. mode] = nil
		end
		ns.db.tooltipCombat, ns.db.tooltipCombatWorld = nil, nil
		ns.db.tooltipCombatUnits, ns.db.tooltipCombatUI = nil, nil
		-- Then Always hide tooltips, with each exception its own line: the
		-- kinds that showed at once after hovering show at once by themselves,
		-- and the camera modes went under one Except in these camera modes.
		ns.db.tooltipHideWorld, ns.db.tooltipHideUnits, ns.db.tooltipHideUI = nil, nil, nil
		for old, new in pairs({ tooltipQuestAtOnce = "tooltipShowQuest", tooltipGatherAtOnce = "tooltipShowGather",
			tooltipEnemyAtOnce = "tooltipShowEnemy", tooltipFriendlyAtOnce = "tooltipShowFriendly" }) do
			if ns.db[old] ~= nil and ns.db[new] == nil then
				ns.db[new] = ns.db[old]
			end
			ns.db[old] = nil
		end
		if ns.db.tooltipShowInModes == nil then
			for _, mode in ipairs({ "Flight", "Idle", "Cozy", "Tele", "Vista", "Fish", "Walk", "Run", "Death", "Quest" }) do
				if ns.db["tooltipShowIn" .. mode] then
					ns.db.tooltipShowInModes = true
				end
			end
		end
		-- Then the other way round: Hide tooltips in CineMode, in these camera
		-- modes or outside CineMode, but still show the kinds ticked. Always hide
		-- with Except outside CineMode is In CineMode; Except in these camera
		-- modes is In these camera modes with the others ticked (so plain
		-- CineMode, in no camera mode, no longer hides). Saved profiles too. Once,
		-- and only with the page's switch on: with it off, the page's never been
		-- used (or was left), so it starts over from the new defaults.
		local tooltipModes = { "Flight", "Idle", "Cozy", "Tele", "Vista", "Fish", "Walk", "Run", "Death", "Quest" }
		local function TooltipsTheOtherWay(t)
			if t.tooltipHide == nil and t.tooltipShowOutsideCine == nil and t.tooltipShowInModes == nil then
				return
			end
			local hide = t.tooltipHide ~= false
			local inModes = false
			if t.tooltipShowInModes then
				for _, mode in ipairs(tooltipModes) do
					if not t["tooltipShowIn" .. mode] then inModes = true end
				end
			end
			if t.tooltipHideInCine == nil then
				t.tooltipHideInCine = hide and not inModes
				t.tooltipHideInModes = hide and inModes
				t.tooltipHideOutsideCine = hide and t.tooltipShowOutsideCine == false
				for _, mode in ipairs(tooltipModes) do
					t["tooltipHideIn" .. mode] = inModes and not t["tooltipShowIn" .. mode]
				end
			end
			t.tooltipHide, t.tooltipShowOutsideCine, t.tooltipShowInModes = nil, nil, nil
			for _, mode in ipairs(tooltipModes) do
				t["tooltipShowIn" .. mode] = nil
			end
		end
		if not ns.db.tooltipsTheOtherWayV1 then
			if ns.db.handleTooltips then
				TooltipsTheOtherWay(ns.db)
			else
				for _, key in ipairs({ "tooltipHideInCine", "tooltipHideInModes", "tooltipHideOutsideCine",
					"tooltipShowEnemy", "tooltipShowFriendly", "tooltipShowGather", "tooltipShowQuest",
					"tooltipShowInCombat", "tooltipCombatShowEnemy", "tooltipCombatShowFriendly",
					"tooltipCombatShowElse", "tooltipReveal", "tooltipRevealDelay", "tooltipWarmTime",
					"tooltipFadeTime", "tooltipHide", "tooltipShowOutsideCine", "tooltipShowInModes" }) do
					ns.db[key] = nil
				end
				for _, mode in ipairs(tooltipModes) do
					ns.db["tooltipHideIn" .. mode], ns.db["tooltipShowIn" .. mode] = nil, nil
				end
			end
			for _, saved in pairs(type(ns.db.profiles) == "table" and ns.db.profiles or {}) do
				if type(saved) == "table" then TooltipsTheOtherWay(saved) end
			end
			ns.db.tooltipsTheOtherWayV1 = true
		end
		-- The Tooltips page was Hide tooltips (in CineMode, in the camera modes
		-- ticked, outside CineMode), then But still show (kinds, a combat list,
		-- After hovering). Now it only hides in CineMode: the kinds ticked under
		-- Hide out of combat / Hide in combat, and everything in the camera modes
		-- ticked. Hiding in all of CineMode is every mode ticked and the kinds
		-- that didn't show anyway; with just the modes, plain CineMode hid
		-- nothing. Saved profiles too (missing settings were the old defaults).
		local OLD_TOOLTIP_DEFAULTS = {
			tooltipHideInCine = false, tooltipHideInModes = true, tooltipHideOutsideCine = false,
			tooltipShowEnemy = true, tooltipShowFriendly = false, tooltipShowGather = true,
			tooltipShowQuest = true, tooltipShowInCombat = true, tooltipCombatShowEnemy = true,
			tooltipCombatShowFriendly = false, tooltipCombatShowElse = false, tooltipReveal = true,
			tooltipRevealDelay = 1, tooltipWarmTime = 5, tooltipFadeTime = 0.5,
		}
		local function TooltipKindsToHide(t)
			local any = false
			for key in pairs(OLD_TOOLTIP_DEFAULTS) do
				any = any or t[key] ~= nil
			end
			if not any then
				return
			end
			local function old(key)
				if t[key] == nil then return OLD_TOOLTIP_DEFAULTS[key] end
				return t[key]
			end
			-- (With the page's switch off, it starts over from the new defaults.)
			if t.handleTooltips then
				local all = old("tooltipHideInCine")
				if all or not old("tooltipHideInModes") then
					for _, mode in ipairs(tooltipModes) do
						t["tooltipHideIn" .. mode] = all
					end
				end
				local combatList = old("tooltipShowInCombat")
				t.tooltipHideEnemy = all and not old("tooltipShowEnemy")
				t.tooltipHideFriendly = all and not old("tooltipShowFriendly")
				t.tooltipHideGather = all and not old("tooltipShowGather")
				t.tooltipHideQuest = all and not old("tooltipShowQuest")
				t.tooltipHideCombatEnemy = all and not old(combatList and "tooltipCombatShowEnemy" or "tooltipShowEnemy")
				t.tooltipHideCombatElse = all and combatList and not old("tooltipCombatShowElse")
			else
				for _, mode in ipairs(tooltipModes) do
					t["tooltipHideIn" .. mode] = nil
				end
			end
			for key in pairs(OLD_TOOLTIP_DEFAULTS) do
				t[key] = nil
			end
		end
		TooltipKindsToHide(ns.db)
		for _, saved in pairs(type(ns.db.profiles) == "table" and ns.db.profiles or {}) do
			if type(saved) == "table" then TooltipKindsToHide(saved) end
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
		-- Events had "Start right away", then a delay ("Wait") and a "Stop on
		-- move" switch each; they now start right away and always stop on moving.
		for _, event in ipairs(ns.EVENTS) do
			local key = "event" .. event.key
			ns.db[key .. "Instant"], ns.db[key .. "Delay"], ns.db[key .. "StopOnMove"] = nil, nil, nil
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
		-- When the tint shows used to be one choice: always, only on flights or
		-- only standing still (the last two never in combat).
		if ns.db.tintWhen == "flight" or ns.db.tintWhen == "idle" then
			ns.db.tintMoving, ns.db.tintInCombat = false, false
			ns.db.tintFlight = ns.db.tintWhen == "flight"
			ns.db.tintStill = ns.db.tintWhen == "idle"
		end
		-- The letterbox and tint first showed by situation (moving around,
		-- standing still, on flights, in combat): now by place, with fights
		-- their own column. In combat off is Combat ticked; the rest go.
		-- Battlegrounds and arenas were part of Instances on the Camera Modes
		-- grid: their own column now, starting as Instances was. (The live
		-- settings and each saved profile alike.)
		local function CarryOver(settings)
			for _, effect in ipairs(ns.EFFECT_GRID) do
				local inCombat = settings[effect .. "InCombat"]
				if inCombat ~= nil and settings[effect .. "OffInCombat"] == nil then
					settings[effect .. "OffInCombat"] = not inCombat
				end
				for _, old in ipairs({ "Moving", "Still", "Flight", "InCombat" }) do
					settings[effect .. old] = nil
				end
			end
			settings.visualEffectsAlways = nil -- (Fade the UI off shows them over the normal UI now)
			for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do
				local instances = settings[cam[1] .. "OffInInstances"]
				if instances ~= nil and settings[cam[1] .. "OffInBGs"] == nil then
					settings[cam[1] .. "OffInBGs"] = instances
				end
			end
		end
		CarryOver(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then CarryOver(saved) end
		end
		-- The raid frames' threat highlight got a row: into saved Mouseover
		-- groups with the role icons, as the default groups have it. Once.
		if not ns.db.raidThreatHoverV1 then
			local function AddThreatRow(groups)
				for _, group in ipairs(groups or {}) do
					local has = {}
					for _, key in ipairs(group.members or {}) do has[key] = true end
					if has.raidroles and not has.raidthreat then
						table.insert(group.members, "raidthreat")
					end
				end
			end
			AddThreatRow(ns.db.hoverGroups)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then AddThreatRow(saved.hoverGroups) end
			end
			ns.db.raidThreatHoverV1 = true
		end
		-- The pet portrait got a row apart from yours: into saved Mouseover
		-- groups with your portrait, as the default groups have it. Once.
		if not ns.db.petFrameHoverV1 then
			local function AddPetRow(groups)
				for _, group in ipairs(groups or {}) do
					local has = {}
					for _, key in ipairs(group.members or {}) do has[key] = true end
					if has.player and not has.petframe then
						table.insert(group.members, "petframe")
					end
				end
			end
			AddPetRow(ns.db.hoverGroups)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then AddPetRow(saved.hoverGroups) end
			end
			ns.db.petFrameHoverV1 = true
		end
		-- Your own frame's parts got settings apart from the target grid's You
		-- row (unitPartSelf<part>, which covered both): each starts as that row
		-- had it. The live settings and each saved profile alike. Once.
		if not ns.db.unitPartPlayerV1 then
			local function CarryPlayerParts(settings)
				for _, part in ipairs(ns.UNIT_PARTS) do
					if settings["unitPartPlayer" .. part] == nil and settings["unitPartSelf" .. part] ~= nil then
						settings["unitPartPlayer" .. part] = settings["unitPartSelf" .. part]
					end
				end
			end
			CarryPlayerParts(ns.db)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then CarryPlayerParts(saved) end
			end
			ns.db.unitPartPlayerV1 = true
		end
		-- Friendly plates in dungeons and raids got a setting of their own
		-- (plateInstance<kind>): each starts as the grids left it there, grouped
		-- and out of fights (what kept that kind on before), else hidden. The
		-- live settings and each saved profile alike. Once.
		if not ns.db.plateInstanceModesV1 then
			local ROWS = {
				Friends = { "Friends", "GroupMembers" },
				FriendlyMinions = { "FriendlyMinions", "MyPet", "GroupMinions" },
				FriendlyNPCs = { "FriendlyNPCs" },
			}
			local function CarryInstanceModes(settings)
				local function On(key)
					local value = settings[key]
					if value == nil then value = DEFAULTS[key] end
					return value and true or false
				end
				for kind, rows in pairs(ROWS) do
					if settings["plateInstance" .. kind] == nil then
						local shown = false
						for _, row in ipairs(rows) do
							for _, prefix in ipairs({ "plateInInstances", "plateAlways", "plateGroup", "plateCombat" }) do
								shown = shown or On(prefix .. row)
							end
						end
						settings["plateInstance" .. kind] = shown and "show" or "hide"
					end
				end
			end
			if not ns.newInstall then
				CarryInstanceModes(ns.db)
			end
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then CarryInstanceModes(saved) end
			end
			ns.db.plateInstanceModesV1 = true
		end
		-- The personal resource bars' power half got a row apart from the
		-- health bar: into saved Mouseover groups with it. Once.
		if not ns.db.prdPowerHoverV1 then
			local function AddPowerRow(groups)
				for _, group in ipairs(groups or {}) do
					local has = {}
					for _, key in ipairs(group.members or {}) do has[key] = true end
					if has.prd and not has.prdpower then
						table.insert(group.members, "prdpower")
					end
				end
			end
			AddPowerRow(ns.db.hoverGroups)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then AddPowerRow(saved.hoverGroups) end
			end
			ns.db.prdPowerHoverV1 = true
		end
		-- The minimap header got a row apart from the minimap: into saved
		-- Mouseover groups with the minimap, as the default groups have it. Once.
		if not ns.db.minimapHeaderHoverV1 then
			local function AddHeaderRow(groups)
				for _, group in ipairs(groups or {}) do
					local has = {}
					for _, key in ipairs(group.members or {}) do has[key] = true end
					if has.minimap and not has.minimapheader then
						table.insert(group.members, "minimapheader")
					end
				end
			end
			AddHeaderRow(ns.db.hoverGroups)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then AddHeaderRow(saved.hoverGroups) end
			end
			ns.db.minimapHeaderHoverV1 = true
		end
		-- What's on the header (its name, buttons and clock) got rows apart from
		-- the minimap too.
		if not ns.db.minimapHeaderPartsHoverV1 then
			local function AddButtonRows(groups)
				for _, group in ipairs(groups or {}) do
					local has = {}
					for _, key in ipairs(group.members or {}) do has[key] = true end
					for _, key in ipairs({ "minimapzone", "minimaptracking", "minimapcalendar", "minimapclock" }) do
						if has.minimap and not has[key] then
							table.insert(group.members, key)
						end
					end
				end
			end
			AddButtonRows(ns.db.hoverGroups)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then AddButtonRows(saved.hoverGroups) end
			end
			ns.db.minimapHeaderPartsHoverV1 = true
		end
		-- The vignette and weather went with the tint's row of the Visual
		-- Effects grid: rows of their own now, starting as the tint's was. Once.
		if not ns.db.effectGridV2 then
			local function SplitTintRow(settings)
				for _, effect in ipairs({ "vignette", "weather" }) do
					for _, column in ipairs({ "OffInCities", "OffInInstances", "OffInBGs", "OffInWorld",
						"OffInCombat", "OnlyInCameras" }) do
						if settings["tint" .. column] ~= nil and settings[effect .. column] == nil then
							settings[effect .. column] = settings["tint" .. column]
						end
					end
				end
			end
			SplitTintRow(ns.db)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then SplitTintRow(saved) end
			end
			ns.db.effectGridV2 = true
		end
		-- The auto-run camera now waits 5 seconds by default: into every profile
		-- too, whatever it had. Once.
		if not ns.db.runCameraDelayV1 then
			ns.db.runCameraDelay = 5
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then saved.runCameraDelay = 5 end
			end
			ns.db.runCameraDelayV1 = true
		end
		-- The game's damage meter no longer comes up in fights by default: its
		-- In combat box unticked in every profile too, whatever it had. Once.
		if not ns.db.metersCombatV1 then
			local function MetersOff(t)
				if type(t.combatShow) ~= "table" then t.combatShow = {} end
				t.combatShow.meters = false
			end
			MetersOff(ns.db)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then MetersOff(saved) end
			end
			ns.db.metersCombatV1 = true
		end
		-- Heal Vision's "Only while you're a healer" is its roles button now
		-- (healers only by default): unticked, it's ticked back on for tanks
		-- and damage, in every profile too. Once.
		if not ns.db.healVisionRolesV1 then
			local function Roles(t)
				if t.healVisionHealerOnly == false then
					for _, list in ipairs({ "tankHide", "damageHide" }) do
						if type(t[list]) ~= "table" then t[list] = {} end
						t[list].healVision = false
					end
				end
				t.healVisionHealerOnly = nil
			end
			Roles(ns.db)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then Roles(saved) end
			end
			ns.db.healVisionRolesV1 = true
		end
		-- The party frames and raid frames' players show while you're grouped
		-- by default: their Grouped boxes ticked in every profile too. Once.
		if not ns.db.groupFramesV1 then
			local function GroupedOn(t)
				if type(t.groupShow) ~= "table" then t.groupShow = {} end
				t.groupShow.party = true
				t.groupShow.raidplayers = true
			end
			GroupedOn(ns.db)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then GroupedOn(saved) end
			end
			ns.db.groupFramesV1 = true
		end
		-- No death camera in instances by default (but in Pure Cinema): its
		-- Instances box ticked in every profile too, whatever it had. Once.
		-- (Saved profiles drop theirs, to follow their base.)
		if not ns.db.deathInstancesV1 then
			if (ns.db.liveProfile or ns.db.profile) ~= "Pure Cinema" then
				ns.db.deathOffInInstances = true
			end
			for name, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" and name ~= "Pure Cinema" then saved.deathOffInInstances = nil end
			end
			ns.db.deathInstancesV1 = true
		end
		-- The weather tint now shows at full strength by default: into every
		-- profile too, whatever it had. Once.
		if not ns.db.weatherStrengthV1 then
			ns.db.weatherTintStrength = 1
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then saved.weatherTintStrength = 1 end
			end
			ns.db.weatherStrengthV1 = true
		end
		-- Heal Vision (Vision page) as its defaults in every profile: its grid
		-- unticked, the options as the defaults say. Once. (Saved profiles drop
		-- theirs, to follow their base.)
		if not ns.db.healVisionDefaultsV1 then
			for key, value in pairs(DEFAULTS) do
				if key:find("^healVision") then
					ns.db[key] = value
					for _, saved in pairs(ns.db.profiles or {}) do
						if type(saved) == "table" then saved[key] = nil end
					end
				end
			end
			ns.db.healVisionDefaultsV1 = true
		end
		-- The Plate Parts' Buffs/debuffs row (Part Auras) was split into Buffs
		-- and Debuffs rows: each takes its boxes, in every profile.
		local function SplitAuras(t)
			local keys = {}
			for key in pairs(t) do
				if type(key) == "string" and key:match("^plate.+PartAuras$") then
					keys[#keys + 1] = key
				end
			end
			for _, key in ipairs(keys) do
				local base = key:sub(1, -6)
				for _, part in ipairs({ "Buffs", "Debuffs" }) do
					if t[base .. part] == nil then
						t[base .. part] = t[key]
					end
				end
				t[key] = nil
			end
		end
		SplitAuras(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then SplitAuras(saved) end
		end
		-- "Always show your target's nameplate" (plateTarget) was split into a
		-- switch each for enemy and friendly targets, then into Enemy Target and
		-- Friendly Target rows in the Nameplates grid: one switch again, on if
		-- any of those was.
		local targetSeen, targetOn = false, false
		local oldTargetKeys = { "plateAlwaysTarget", "plateAlwaysTargetEnemy", "plateAlwaysTargetFriendly" }
		for _, row in ipairs({ "EnemyTarget", "FriendlyTarget" }) do
			for _, prefix in ipairs({ "plateCombat", "plateCombatPvP", "plateCinematic", "plateGroup", "plateAlways",
				"plateInCities", "plateInDungeons", "plateInRaids", "plateInPvP", "plateInBGs", "plateInInstances" }) do
				oldTargetKeys[#oldTargetKeys + 1] = prefix .. row
			end
		end
		for _, key in ipairs(oldTargetKeys) do
			if ns.db[key] ~= nil then
				targetSeen = true
				targetOn = targetOn or ns.db[key] and true
				ns.db[key] = nil
			end
		end
		if targetSeen and ns.db.plateTarget == nil then
			ns.db.plateTarget = targetOn
		end
		-- ...and that switch, "Always show group members' nameplates" (with
		-- "Their minions") and "Always show your pet's nameplate" became rows of
		-- the grid again: their Always boxes, as the switches were. In every
		-- profile too.
		local function UnitRowsFromSwitches(t)
			if t.plateTarget ~= nil then t.plateAlwaysMyTarget = t.plateTarget end
			if t.plateOwnPet ~= nil then t.plateAlwaysMyPet = t.plateOwnPet end
			if t.plateGroupMembers ~= nil then t.plateAlwaysGroupMembers = t.plateGroupMembers end
			if t.plateGroupMembers == false then
				t.plateAlwaysGroupMinions = false
			elseif t.plateGroupMemberMinions ~= nil then
				t.plateAlwaysGroupMinions = t.plateGroupMemberMinions
			end
			t.plateTarget, t.plateOwnPet, t.plateGroupMembers, t.plateGroupMemberMinions = nil, nil, nil, nil
		end
		UnitRowsFromSwitches(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then UnitRowsFromSwitches(saved) end
		end
		-- The Nameplates page's Cities column joined Open world (ticked there
		-- wherever either was), and Dungeons and Raids became one column
		-- (ticked wherever either was). Its BGs column came back from PvP:
		-- ticked where PvP is, to start with. (Its Always column, gone for a
		-- while, is back as its own setting.)
		local plateRows = {}
		for _, kind in ipairs(ns.PLATE_KINDS) do
			plateRows[#plateRows + 1] = { "plate", "plateCinematic", kind }
		end
		for _, group in ipairs(ns.NAME_GROUPS) do
			plateRows[#plateRows + 1] = { "name", "nameKeep", group.key }
		end
		for _, row in ipairs(plateRows) do
			local prefix, open, key = row[1], row[2], row[3]
			local head = prefix .. "In"
			if ns.db[head .. "Cities" .. key] then ns.db[open .. key] = true end
			ns.db[head .. "Cities" .. key] = nil
			if ns.db[head .. "BGs" .. key] == nil and ns.db[head .. "PvP" .. key] ~= nil then
				ns.db[head .. "BGs" .. key] = ns.db[head .. "PvP" .. key]
			end
			local dungeons, raids = ns.db[head .. "Dungeons" .. key], ns.db[head .. "Raids" .. key]
			if dungeons ~= nil or raids ~= nil then
				ns.db[head .. "Instances" .. key] = (dungeons or raids) and true or false
			end
			ns.db[head .. "Dungeons" .. key], ns.db[head .. "Raids" .. key] = nil, nil
		end
		-- Enemy NPCs (with Minor) split into Hostile NPCs (still "EnemyNPCs"
		-- and "EnemyMinor") and Neutral NPCs (with a Minor of their own): the
		-- new rows start out ticked wherever the old ones were. In every
		-- profile too.
		local function NeutralFromHostile(t)
			t.plateNeutralNPCsV1 = nil
			if t.plateNeutralRowsV1 then
				return
			end
			for _, prefix in ipairs({ "plateAlways", "plateCombat", "plateCombatPvP", "plateCinematic", "plateGroup",
				"plateInPvP", "plateInBGs", "plateInInstances" }) do
				for old, new in pairs({ EnemyNPCs = "NeutralNPCs", EnemyMinor = "NeutralMinor" }) do
					if t[prefix .. old] ~= nil and t[prefix .. new] == nil then
						t[prefix .. new] = t[prefix .. old]
					end
				end
			end
			t.plateNeutralRowsV1 = true
		end
		-- ...and Your Target into the Target Nameplate grid's rows (enemy,
		-- neutral and friendly, players and NPCs apart): each starts out ticked
		-- wherever it was, and with Always ticked whatever it was.
		local OLD_TARGET_ROWS = {
			MyTarget = ns.PLATE_TARGET_ROWS,
			MyEnemyTarget = { "MyEnemyPlayerTarget", "MyEnemyNPCTarget" },
			MyNeutralTarget = { "MyNeutralPlayerTarget", "MyNeutralNPCTarget" },
			MyFriendlyTarget = { "MyFriendlyPlayerTarget", "MyFriendlyNPCTarget" },
		}
		local function TargetRowsFromMyTarget(t)
			for _, prefix in ipairs({ "plateAlways", "plateCombat", "plateCombatPvP", "plateCinematic", "plateGroup",
				"plateInPvP", "plateInBGs", "plateInInstances" }) do
				for old, rows in pairs(OLD_TARGET_ROWS) do
					if t[prefix .. old] ~= nil then
						for _, row in ipairs(rows) do
							if t[prefix .. row] == nil then t[prefix .. row] = t[prefix .. old] end
						end
						t[prefix .. old] = nil
					end
				end
			end
			if not t.plateTargetRowsV1 then
				for _, row in ipairs(ns.PLATE_TARGET_ROWS) do
					t["plateAlways" .. row] = true
				end
				t.plateTargetRowsV1 = true
			end
		end
		NeutralFromHostile(ns.db)
		TargetRowsFromMyTarget(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				NeutralFromHostile(saved)
				TargetRowsFromMyTarget(saved)
			end
		end
		-- LocalDefense attacks now show as a title on the screen (Show attacks
		-- on the screen), so the channel no longer brings up chat. Once, in
		-- every profile. (A profile without its own channel list uses the
		-- defaults, which have it off now.)
		if not ns.db.chatAttackAlertV1 then
			local function LocalDefenseOff(t)
				if type(t.chatPeekChannelList) == "table" then
					t.chatPeekChannelList.LocalDefense = false
				end
			end
			ns.db.chatAttackAlert = true
			LocalDefenseOff(ns.db)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then
					saved.chatAttackAlert = nil -- (on by default)
					LocalDefenseOff(saved)
				end
			end
			ns.db.chatAttackAlertV1 = true
		end
		-- Say no longer brings up chat (it's off by default now). Once, in
		-- every profile.
		if not ns.db.chatSayOffV1 then
			local function SayOff(t)
				if type(t.chatPeekTypes) == "table" then
					t.chatPeekTypes.say = nil -- (off by default)
				end
			end
			SayOff(ns.db)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then SayOff(saved) end
			end
			ns.db.chatSayOffV1 = true
		end
		-- ...and back on, now that says you can see as a bubble on screen don't
		-- bring up chat (Hide speech you can see as a bubble, on too). Once, in
		-- every profile.
		if not ns.db.chatSayOnV1 then
			local function SayOn(t)
				if type(t.chatPeekTypes) == "table" then
					t.chatPeekTypes.say = nil -- (on by default)
				end
				t.chatHideBubbled = nil -- (on by default)
			end
			SayOn(ns.db)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then SayOn(saved) end
			end
			ns.db.chatSayOnV1 = true
		end
		-- The cozy camera by a tent: 8 yards, not 7. Once, in every profile still
		-- at the old default (there's no slider for it).
		if not ns.db.cozyTentCloseV1 then
			local function TentEight(t)
				if t.cozyTentClose == 7 then t.cozyTentClose = nil end -- (8 by default)
			end
			TentEight(ns.db)
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then TentEight(saved) end
			end
			ns.db.cozyTentCloseV1 = true
		end
		-- Enemy class icons and tank and healer role icons on nameplates are now
		-- on (Always) by default: into every profile too. Once.
		if not ns.db.plateIconsAlwaysV1 then
			for _, part in ipairs(ns.PLATE_ICONS_ALWAYS) do
				ns.db["plateAlwaysPart" .. part] = true
				for _, saved in pairs(ns.db.profiles or {}) do
					if type(saved) == "table" then saved["plateAlwaysPart" .. part] = true end
				end
			end
			ns.db.plateIconsAlwaysV1 = true
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
			"delay", "startCinematic", "startCinematicOnReload", "startDelay", "timeOfDayChange", "timeOfDaySound",
			"revealOnTarget", "ignoreDeadTarget", "unitBarTexture",
			"plateHurtMobs", "plateHurtNPCs", "plateHurtOwn", "plateHurtOther", "plateHurtPets",
			"plateHurtTotems",
			"camOffInCities", "camOffInInns", "camOffInDungeons", "camOffInRaids", "camOffInPvP",
			"rotOffInCities", "rotOffInInns", "rotOffInDungeons", "rotOffInRaids", "rotOffInPvP",
			"zoomOffInCities", "zoomOffInInns", "zoomOffInDungeons", "zoomOffInRaids", "zoomOffInPvP",
			"hideCursor", "hideCursorDelay", "innZoom", "innZoomDistance",
			"viewShift", "viewShiftAmount", "viewShiftRight", "zoneTitle", "zoneTitleSubzones",
			"taxiOrbitPitch", "idleOrbitPitch", "turnLog", "cozyPray", "cozyAngle", "deathInputPause",
			"cozyCrackle", "cursorTuck", "cursorTuckFlight", "cursorTuckIdle", "cursorTuckCozy",
			"cursorTuckVista", "cursorTuckWalk", "cursorTuckRun", "cursorTuckOther", "cursorTuckDelay",
			"flyByDistance", "flyByMinDistance", "flyByMaxDistance", "flyByTrace", "flyByLower",
			"cameraInputPause", "questCamRandomSide", "questCamLeft", "lastMusicStartedAt",
			"musicCamIdle", "musicWhenAFK", "noMusicWhenAFK", -- (now eventAFKMusic)
			"musicPauseOnLanding", "musicPauseFadeTime", -- (leaving the flight camera; the music fade time)
			"musicOffOnFlights", -- (the flight camera's Music switch, Camera Triggers page)
			"trackingHideWhenIdle", -- (now flightHideMinimap, idleHideMinimap)
			"tintWhen", -- (now tintMoving, tintStill, tintFlight)
			"plateTargetEnemyFadeIn", "plateTargetEnemyFadeOut", "plateTargetFriendlyFadeIn",
			"plateTargetFriendlyFadeOut", -- (the target's plate fades at the UI's fade times now)
			"enemyFadeInTime", "enemyFadeOutTime",
			"friendlyFadeInTime", "friendlyFadeOutTime", -- (combat frames likewise)
			-- (combatFadeInTime and combatFadeOutTime were too: they're back, for fights.)
			"plateShowMobs", "plateShowNPCs", "plateShowOwn", "plateShowOther", "plateShowPets",
			"plateShowTotems", -- (nameplates outside cinematic mode are the game's own now)
			"nameIconMobs", "nameIconNPCs", "nameIconOwn", "nameIconOther", "nameIconPets", "nameIconTotems",
			"nameIconPvPMobs", "nameIconPvPNPCs", "nameIconPvPOwn", "nameIconPvPOther", "nameIconPvPPets",
			"nameIconPvPTotems", -- (custom icons in place of names, removed)
			"nameShowMobs", "nameShowNPCs", "nameShowOwn", "nameShowOther", "nameShowPets",
			"nameShowMinions", "nameShowTotems", "nameShowSelf", -- (names outside cinematic mode are the game's own)
			"cameraPauseAtNPCs", "cameraPauseCasting", "cameraPauseInMenus", -- (always on now)
			"cozyTentZoom", -- (now cozyTentClose)
		}) do
			ns.db[key] = nil
		end
		-- New settings start as the active profile has them (a built-in's
		-- changes to the defaults included). A fresh install (or Reset addon)
		-- starts with all of them so: the once-only updates above write theirs
		-- into an empty db too, which made the profile show "(changed)".
		local base = ns.ProfileBase and ns.ProfileBase() or DEFAULTS
		for k, v in pairs(DEFAULTS) do
			if ns.db[k] == nil or (ns.newInstall and type(ns.db[k]) ~= "table") then
				if base[k] ~= nil and type(base[k]) ~= "table" then ns.db[k] = base[k] else ns.db[k] = v end
			end
		end
		ns.EnsureTables()
		ns.InitProfiles()
		ns.InitLog()
		SLASH_CINEMATIC1 = "/cine"
		SLASH_CINEMATIC2 = "/cinematic"
		SlashCmdList.CINEMATIC = ns.HandleSlash
	elseif event == "PLAYER_LOGIN" then
		ns.MusicTrace(("LOGIN volume %s music %s"):format(GetCVar("Sound_MusicVolume"), GetCVar("Sound_EnableMusic")))
		RestoreSavedCVars()
		if ns.musicBackOn and GetCVar("Sound_EnableMusic") == "0" then
			SetCVar("Sound_EnableMusic", 1)
		end
		ns.musicBackOn = nil
		ns.EnsurePlateRows()
		ns.RestoreMusicVolume()
		ns.PruneBuiltInExtras()
		ns.wasOnTaxi = UnitOnTaxi("player") -- don't re-center after a /reload mid-flight
		ns.RegisterChatPeek()
		ns.HookCameraInput()
		-- Walk mode: there's no "am I walking" API, so the walk/run toggle is
		-- followed (you log in running), and corrected from your actual speed
		-- whenever you move and the speed can be read (it's secret at times).
		ns.walking = false
		-- RP walking: auto-walking (auto-run in walk mode). Walking by hand
		-- cancels the camera modes like any other movement (ns.MovingManually).
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
			return ns.walking and not ns.MovingManually()
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
		-- Strafing doesn't end an auto-run (you drift sideways and carry on),
		-- so once auto-run is on, the strafe keys don't count as moving by hand.
		local STRAFE = { StrafeLeft = true, StrafeRight = true }
		local function AnyMovementKey()
			for key, held in pairs(movementKeys) do
				if held and not (ns.autoRunning and STRAFE[key]) then return true end
			end
			if ns.PadMovementHeld and ns.PadMovementHeld() then -- (gamepad mode's left stick)
				return true
			end
			return IsMouseButtonDown("LeftButton") and IsMouseButtonDown("RightButton")
		end
		-- Moving by hand: a movement key held, or steering with both mouse
		-- buttons. The camera modes only carry on through auto-run and
		-- auto-walk: moving by hand cancels them all, and the standing-still
		-- timer starts over once you stop (a safety net, so a camera never
		-- carries on, or starts, while you're steering yourself).
		ns.MovingManually = function()
			return ns.playerMoving and AnyMovementKey()
		end
		ns.IsAutoRunning = function()
			if not ns.playerMoving or UnitOnTaxi("player") or AnyMovementKey() then
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
		-- auto-run ever ended unseen.) Also called for gamepad mode's left stick
		-- click (Frames.lua); one press seen both ways only counts once.
		local lastToggle = 0
		function ns.OnAutoRunToggle()
			if GetTime() - lastToggle < 0.2 then
				return
			end
			lastToggle = GetTime()
			ns.autoRunning = not (ns.autoRunning and ns.playerMoving)
		end
		Hook("ToggleAutoRun", ns.OnAutoRunToggle)
		Hook("StartAutoRun", function() ns.autoRunning = true end)
		Hook("StopAutoRun", function() ns.autoRunning = false end)
		Hook("MoveForwardStart", function() ns.autoRunning = false end)
		Hook("MoveBackwardStart", function() ns.autoRunning = false end)
		ns.HookTaxiRoutes()
		GameTooltip:HookScript("OnShow", ns.Profiled("Tooltip shown", ns.OnTooltipShow))
		GameTooltip:HookScript("OnHide", ns.OnTooltipHide)
		hooksecurefunc(GameTooltip, "SetUnit", ns.OnTooltipSetUnit)
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
		if (arg1 or arg2) and ns.db.timeOfDayMessage and ns.db.visualEffects and ns.ProfileChosen() then
			ns.ShowTimeOfDayTitle()
		end
		if arg1 or arg2 then
			lastBusy = GetTime()
			quickStart = true -- straight in rather than after the fade delay
			startSnapUntil = GetTime() + START_SNAP_WINDOW
			snapRound = snapRound + 1
		end
	elseif event == "PLAYER_LOGOUT" then
		ns.SaveProfile()
		ns.MusicTrace(("LOGOUT volume %s music %s"):format(GetCVar("Sound_MusicVolume"), GetCVar("Sound_EnableMusic")))
		-- Put the player's music/name/nameplate settings back before they're saved.
		ns.UpdateCVars(false)
		ns.StopIdleZoomNow()
		ns.StopDeathSongNow()
		ns.StopMusicNow()
		ns.StopCombatMusicNow()
		ns.ShowPlatesNow()
		ns.StopOrbitNow()
		ns.ApplyCVarSet(ns.FLIGHT_CVARS, false)
		ns.ApplyCVarSet(ns.RECENTER_CVARS, false)
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
		if ns.db.stayInCombat then
			ns.UpdateCVarsForFight()
		else
			lastBusy = GetTime()
			ns.UpdateCVars(false)
			for _, entry in ipairs(ns.managed) do
				ns.SetEntryAlpha(entry, 1)
			end
		end
	end
end))

-- The development copy (CinematicDev) wins over the released Cinematic: with
-- both enabled (a new character starts with every addon on) they'd run twice
-- on the same settings and their key bindings clash. The dev copy turns the
-- released one off for every character (turning it off for just one, by name,
-- didn't stick) and offers a reload. Released installs
-- never have a CinematicDev folder, so this does nothing there.
if ADDON_NAME == "CinematicDev" then
	local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	local DisableAddOn = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
	-- Changes to the enabled list are only kept once saved (the AddOn List's
	-- Okay button does the same before it reloads).
	local SaveAddOns = (C_AddOns and C_AddOns.SaveAddOns) or SaveAddOns
	local devWins = CreateFrame("Frame")
	devWins:RegisterEvent("PLAYER_LOGIN")
	devWins:SetScript("OnEvent", function()
		if not IsLoaded("Cinematic") then
			return
		end
		DisableAddOn("Cinematic")
		SaveAddOns()
		ns.Print("the released Cinematic is also enabled; turned it off for all characters so the dev copy runs alone. Reload to finish.")
		StaticPopupDialogs.CINEMATIC_DEV_WINS = {
			text = "Cinematic (Dev) turned off the released Cinematic for all characters. Reload now?",
			button1 = RELOADUI or "Reload UI",
			button2 = CANCEL,
			OnAccept = ReloadUI,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
		}
		StaticPopup_Show("CINEMATIC_DEV_WINS")
	end)
end
