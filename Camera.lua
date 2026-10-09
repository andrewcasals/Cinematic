-- Cinematic: camera rotation. The orbit (flights and standing still), camera
-- input detection, the takeoff swing, flight timing and settling before landing.
local _, ns = ...

-- Flight path orbit: while on a taxi the camera moves in sweeps, holding still
-- for taxiOrbitPause seconds between them. Each sweep eases in and out (see
-- EaseShape); the distance moved is the integral of that speed curve. Modes decide where each sweep goes:
--   sweep:  turn taxiOrbitStep degrees, always the same way, staying level
--   random: a random new angle around the character, at least
--           taxiOrbitMinChange degrees from the current one, the short way round
--   back:   like random, but only angles within taxiOrbitBackArc degrees
--           (0-90) of directly behind, so the camera always faces the forward
--           half; never crosses the front
-- random and back also pick a random tilt between -taxiOrbitPitchDown and
-- +taxiOrbitPitchUp degrees.
-- Turn and tilt share the sweep's duration so they arrive together. Steady
-- sweeps derive the duration from taxiOrbitSpeed; the random modes use a fixed
-- taxiOrbitMoveTime so a big move doesn't crawl for most of a minute.
--
-- orbit.angle (positive = turned left) and orbit.pitch (positive = tilted up)
-- are offsets from where the camera was at takeoff. There's no API to read the
-- camera angle, so they're the sum of our own moves since the flight started
-- (camera follow is off during flights, so nothing else moves it).
local ORBIT_STOP_TIME = 1.5      -- ease-out if cinematic ends mid-sweep
local ORBIT_QUICK_STOP_TIME = 0.4 -- ease-out when the player moves or grabs the camera
local ORBIT_MIN_SWEEP_TIME = 0.5 -- avoid near-instant sweeps for tiny moves
local ORBIT_SPEED_EPSILON = 0.02 -- skip restarts for speed changes under 2%
local DRIFT_RAMP = 1.5           -- seconds for the drift to ease in, or turn round
local DRIFT_SMOOTH = 0.6         -- seconds of smoothing on top, so it never starts or stops sharply
local ORBIT_RESTART_INTERVAL = 0.05 -- at most 20 speed changes per second per axis
local ORBIT_BIG_CHANGE = 0.3 -- speed changes over 30% skip that limit

-- One camera axis driven by a pair of MoveView start/stop functions. Speeds
-- passed to MoveView*Start are multipliers of the axis's speed CVar (deg/sec).
local function NewAxis(positiveStart, positiveStop, negativeStart, negativeStop, speedCVar, defaultSpeed)
	return {
		positiveStart = positiveStart, positiveStop = positiveStop,
		negativeStart = negativeStart, negativeStop = negativeStop,
		speedCVar = speedCVar, defaultSpeed = defaultSpeed,
		moving = false, positive = true, speed = 0, lastStart = 0,
	}
end

ns.yawAxis = NewAxis("MoveViewLeftStart", "MoveViewLeftStop",
	"MoveViewRightStart", "MoveViewRightStop", "cameraYawMoveSpeed", 180)
ns.pitchAxis = NewAxis("MoveViewUpStart", "MoveViewUpStop",
	"MoveViewDownStart", "MoveViewDownStop", "cameraPitchMoveSpeed", 90)

-- Player camera input (mouse drags, camera keybinds, saved views) pauses the
-- orbit. Our own MoveView calls go through the same functions, so they're
-- made with drivingCamera set and the hooks ignore them.
local drivingCamera = false
local lastCameraInput = -math.huge

local function CallCameraFunction(name, ...)
	drivingCamera = true
	_G[name](...)
	drivingCamera = false
end
ns.CallCameraFunction = CallCameraFunction -- (for the quest cam's tilt)

local idleZoom = { active = false, saved = nil }
local turnKeys = { left = false, right = false }
-- Events that start a standing-still camera, in the order the Events page
-- lists them. Each has its own settings: event<key>Camera (which camera:
-- "cozy", "vista", "fish", "afk", "tele" or "none") and event<key>Delay (seconds the event
-- has to last first; nil starts it right away). Once it counts, the camera
-- starts and the UI fades at once. The emotes and seats always end as you move
-- or jump; those marked stopsOnMove (a state that carries on as you move) have
-- event<key>StopOnMove: moving or jumping ends it until it starts afresh.
ns.EVENTS = {
	{ key = "Campfire", label = "Resting with a listed buff (campfire)", camera = "cozy", stopsOnMove = true },
	{ key = "Sit", label = "/sit (or press the sit key)", camera = "cozy" },
	{ key = "Sleep", label = "/sleep or /lie down", camera = "cozy" },
	{ key = "Dance", label = "/dance", camera = "cozy" },
	{ key = "Kneel", label = "/kneel", camera = "cozy" },
	{ key = "Chair", label = "Sitting in a chair or on a bench", camera = "cozy" },
	{ key = "Weapon", label = "Unsheathe your weapon (Z)", camera = "cozy", stopsOnMove = true },
	{ key = "Hearth", label = "Cast your Hearthstone", camera = "tele" },
	{ key = "Teleport", label = "Cast a teleport", camera = "tele" },
	{ key = "Logout", label = "Log out (the 20-second countdown)", camera = "cozy" },
	{ key = "Stare", label = "/stare", camera = "vista" },
	{ key = "Fishing", label = "Cast Fishing", camera = "fish" },
	{ key = "AFK", label = "Go AFK", camera = "afk", stopsOnMove = true },
	-- Not a standing-still camera: its choices are the flight camera or none.
	{ key = "Flight", label = "Take a flight", camera = "flight" },
	-- Nor this: the quest cam (QuestCam.lua) or none.
	{ key = "Quest", label = "Talk to a quest giver", camera = "quest" },
}
for _, event in ipairs(ns.EVENTS) do
	ns.DEFAULTS["event" .. event.key .. "Camera"] = event.camera
	if event.stopsOnMove then
		ns.DEFAULTS["event" .. event.key .. "StopOnMove"] = true
	end
end
ns.DEFAULTS.eventWeaponDelay = 0

-- Seconds an event has to last before its camera starts (0: right away).
local function EventDelay(key)
	return tonumber(ns.db["event" .. key .. "Delay"]) or 0
end

-- Taking a flight: it counts once the flight has lasted its delay. The flight
-- camera runs then, unless the event is set to no camera.
local flightSince -- when this flight took off, or nil on the ground
local flightCamStarted = false -- this flight's camera has started (takeoff swing done)
function ns.FlightStarted()
	return ns.db ~= nil and UnitOnTaxi("player") and flightSince ~= nil
		and GetTime() - flightSince >= EventDelay("Flight")
end
function ns.FlightCameraOn()
	return ns.FlightStarted() and ns.db.eventFlightCamera ~= "none" and not ns.IsCameraOffHere("flight")
end
-- Emote token -> its event. Over once you move, jump or do another emote.
local EMOTE_EVENTS = {
	SIT = "Sit", SLEEP = "Sleep", LAYDOWN = "Sleep", LIE = "Sleep",
	DANCE = "Dance", KNEEL = "Kneel", STARE = "Stare",
}
local emoteEvent -- the event for the emote (or seat) you're doing, or nil

-- Hearthstone and teleports: casting one counts like an emote until the cast
-- ends (you're whisked away, or it's interrupted), for the tele camera: the
-- cozy camera's swing round to face you, quicker so it's round before you go
-- (DepartTimeLeft), then a spin that speeds up, zooming in over the cast.
-- Cancelled, it turns back and zooms back out; gone, the camera swings round
-- behind you where you arrive.
-- Hearthstone itself and Astral Recall by ID, and any spell whose name holds
-- "Hearthstone" in your game language (Dalaran, Garrison, the toys). Teleports:
-- the mage city ones by ID, and any spell named like "Teleport: Stormwind" in
-- your game language (the part up to the colon), Moonglade and newer cities too.
do
	local HEARTH_IDS = { [8690] = true, [556] = true }
	local TELEPORT_IDS = { [3561] = true, [3562] = true, [3563] = true, [3565] = true, [3566] = true, [3567] = true }
	local MIN_SWING = 1.5  -- seconds, at least, for the swing round
	local BEHIND_TIME = 1.5 -- seconds the swing behind you takes where you arrive
	local castEndsAt -- when the cast ends (GetTime), while casting one
	local castCamera = false -- that cast's event has the tele camera
	-- "Hearth", "Teleport" or nil for a spell.
	local function DepartEvent(spellID)
		local ok, event = pcall(function()
			if HEARTH_IDS[spellID] then
				return "Hearth"
			elseif TELEPORT_IDS[spellID] then
				return "Teleport"
			end
			local GetName = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
			local name = spellID and GetName(spellID)
			if not name then
				return nil
			end
			local hearthName = GetName(8690)
			if hearthName and name:find(hearthName, 1, true) then
				return "Hearth"
			end
			-- "Teleport: Stormwind" -> "Teleport:" (a full-width colon in some languages)
			local example = GetName(3561)
			local colon = example and (example:find(":", 1, true) or example:find(string.char(239, 188, 154), 1, true))
			if colon then
				local prefix = example:sub(1, colon)
				if name:sub(1, #prefix) == prefix then
					return "Teleport"
				end
			end
		end)
		return ok and event or nil
	end
	local departWatcher = CreateFrame("Frame")
	departWatcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
	departWatcher:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
	departWatcher:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
	departWatcher:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
	departWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

	-- Gone: once you're there (after the loading screen, if there is one),
	-- swing the camera round behind you.
	local behindPending, loading = false, false
	local function SwingBehind()
		if behindPending then
			behindPending = false
			ns.CenterCamera(BEHIND_TIME, 360, 120)
		end
	end
	local arrivalWatcher = CreateFrame("Frame")
	for _, event in ipairs({ "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "PLAYER_ENTERING_WORLD" }) do
		pcall(arrivalWatcher.RegisterEvent, arrivalWatcher, event)
	end
	arrivalWatcher:SetScript("OnEvent", function(_, event)
		if event == "LOADING_SCREEN_ENABLED" then
			loading = true
		elseif behindPending then
			loading = false
			C_Timer.After(0.2, SwingBehind) -- (a moment for the world to settle)
		end
	end)

	departWatcher:SetScript("OnEvent", function(_, event, _, _, spellID)
		local depart = DepartEvent(spellID)
		if not depart then
			return
		elseif event ~= "UNIT_SPELLCAST_START" and event ~= "UNIT_SPELLCAST_SUCCEEDED"
			and ns.Flag(UnitCastingInfo("player")) then
			return -- still casting (pressing it again fails, but the cast goes on)
		end
		-- (Remembered from the start: moving ends the event before the cast's end comes in.)
		local camera = castCamera
		if event == "UNIT_SPELLCAST_SUCCEEDED" and castEndsAt then
			-- You're off: the spin and zoom stop where they are (the zoom jumps
			-- back to your distance), and the camera goes behind you on arrival.
			castEndsAt = nil
			if emoteEvent == depart then
				emoteEvent = nil
			end
			if camera then
				ns.StopOrbitNow()
				ns.orbit.spin, ns.orbit.returnPending, ns.orbit.back = false, false, nil
				ns.StopIdleZoomNow()
				if ns.stillSince then
					ns.stillSince = GetTime() -- (no AFK camera in the moment before you go)
				end
				if ns.db.teleBehind and ns.db.enabled then
					behindPending, loading = true, false
					C_Timer.After(1, function()
						if not loading then SwingBehind() end -- (no loading screen)
					end)
				end
			end
			return
		elseif event ~= "UNIT_SPELLCAST_START" and castEndsAt and camera then
			-- Cancelled (moved, jumped, Esc): the spin turns back to where the
			-- camera was (the zoom goes back quickly: EndIdleZoom), and the AFK
			-- camera's wait starts over rather than taking over straight away.
			if ns.orbit.spin and ns.db.teleReturn then
				ns.orbit.returnPending = true
			end
			if ns.stillSince then
				ns.stillSince = GetTime()
			end
		end
		if event == "UNIT_SPELLCAST_START" then
			emoteEvent = depart
			if ns.EndLogoutEvent then ns.EndLogoutEvent() end -- (casting calls a logout off)
			castCamera, behindPending = ns.IsDepartEvent(), false
			ns.lastEmote = { token = depart:upper(), via = "cast", at = GetTime() }
			local ok, endMS = pcall(function() return select(5, UnitCastingInfo("player")) end)
			if ok and type(endMS) == "number" and not (issecretvalue and issecretvalue(endMS)) then
				castEndsAt = endMS / 1000
			else
				castEndsAt = GetTime() + 10 -- (the usual cast)
			end
		else
			castEndsAt = nil
			if emoteEvent == depart then
				emoteEvent = nil
			end
		end
	end)
	-- Casting your Hearthstone or a teleport: the seconds the cozy camera has to
	-- swing round (and zoom in) so it's in front of you before the cast ends;
	-- nil otherwise.
	function ns.DepartTimeLeft()
		if (emoteEvent ~= "Hearth" and emoteEvent ~= "Teleport") or not castEndsAt then
			return nil
		end
		return math.max(MIN_SWING, castEndsAt - GetTime() - ns.db.teleArriveEarly)
	end
	-- ...and the seconds left on the cast itself (the zoom in takes them all).
	function ns.DepartCastLeft()
		return ns.DepartTimeLeft() and math.max(MIN_SWING, castEndsAt - GetTime())
	end
end

-- Fishing: casting it counts like an emote, so it carries on after the cast
-- ends (looting, recasting) until you move or jump. All ranks share the name.
do
	local FISHING_IDS = { [7620] = true, [7731] = true, [7732] = true, [18248] = true }
	local function SpellName(id)
		if C_Spell and C_Spell.GetSpellName then
			return C_Spell.GetSpellName(id)
		elseif GetSpellInfo then
			return (GetSpellInfo(id))
		end
	end
	local function IsFishingSpell(spellID)
		local ok, fishing = pcall(function()
			return FISHING_IDS[spellID] or (spellID and SpellName(spellID) == SpellName(7620))
		end)
		return ok and fishing and true or false
	end
	local fishingWatcher = CreateFrame("Frame")
	fishingWatcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
	fishingWatcher:SetScript("OnEvent", function(_, _, _, _, spellID)
		if IsFishingSpell(spellID) then
			emoteEvent = "Fishing"
			ns.lastEmote = { token = "FISHING", via = "cast", at = GetTime() }
		end
	end)

	-- The player cast bar while it shows Fishing: kept invisible (hideFishingCastBar).
	-- The bar sets itself back to full alpha as each cast starts, so its own
	-- events are followed and the alpha set again after them.
	local function UpdateCastBar(bar)
		if not ns.db or not ns.db.hideFishingCastBar then
			if bar.cinematicFishingHidden then
				bar.cinematicFishingHidden = nil
				if bar:IsShown() then bar:SetAlpha(1) end
			end
			return
		end
		local ok, fishing = pcall(function()
			local name, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
			return name ~= nil and IsFishingSpell(spellID or 0) or (name ~= nil and name == SpellName(7620))
		end)
		if ok and fishing then
			bar.cinematicFishingHidden = true
			bar:SetAlpha(0)
		elseif bar.cinematicFishingHidden and (UnitCastingInfo("player") or UnitChannelInfo("player")) then
			bar.cinematicFishingHidden = nil -- another cast: the bar shows it as usual
			bar:SetAlpha(1)
		end
	end
	local castBarWatcher = CreateFrame("Frame")
	castBarWatcher:RegisterEvent("PLAYER_LOGIN")
	castBarWatcher:SetScript("OnEvent", function()
		for _, name in ipairs({ "PlayerCastingBarFrame", "CastingBarFrame" }) do
			local bar = _G[name]
			if bar and bar.HookScript then
				bar:HookScript("OnEvent", UpdateCastBar)
				bar:HookScript("OnShow", UpdateCastBar)
			end
		end
	end)

	-- Right-click to recast (fishRightClickCast): while the fish camera is on
	-- and no bobber is out, a right-click in the world clicks a secure button
	-- that casts Fishing. Every cast still comes from your own click (addons
	-- can't cast by themselves). While the bobber is out, the loot window is
	-- open or you're in combat, right-click is left alone (to click the bobber).
	local castButton -- the secure button, made at login
	local AFTER_COMBAT = 5 -- seconds after a fight before right-click casts again (time to loot)
	local combatSeenAt = -math.huge
	local BOTH_BUTTONS_WINDOW = 0.25 -- seconds: a left-click this close before the right one counts as both
	local leftDownAt = -math.huge
	local leftWatcher = CreateFrame("Frame")
	leftWatcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
	leftWatcher:SetScript("OnEvent", function(_, _, button)
		if button == "LeftButton" then
			leftDownAt = GetTime()
		end
	end)
	local bound = false
	local channelEndedAt = -math.huge
	local function SetRecast(on)
		if on == bound or InCombatLockdown() then
			return -- (bindings can't change in combat)
		end
		bound = on
		if on then
			SetOverrideBindingClick(castButton, true, "BUTTON2", castButton:GetName())
		else
			ClearOverrideBindings(castButton)
		end
	end
	local recastWatcher = CreateFrame("Frame")
	recastWatcher:RegisterEvent("PLAYER_LOGIN")
	recastWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	recastWatcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
	recastWatcher:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" then
			castButton = CreateFrame("Button", "CinematicFishingCastButton", UIParent, "SecureActionButtonTemplate")
			castButton:SetAttribute("type", "spell")
			castButton:SetAttribute("spell", SpellName(7620))
			-- Click on key down or up, as the game's action buttons do (not both:
			-- that would cast twice).
			castButton:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
			-- Both mouse buttons together runs you forward: no cast then. (Out
			-- of combat, so the spell can be taken off just for this click.)
			castButton:SetScript("PreClick", function(self)
				local both = IsMouseButtonDown("LeftButton") or GetTime() - leftDownAt < BOTH_BUTTONS_WINDOW
				if not InCombatLockdown() then
					self:SetAttribute("type", not both and "spell" or nil)
				end
			end)
		elseif event == "PLAYER_REGEN_DISABLED" then
			combatSeenAt = GetTime()
			SetRecast(false) -- a fight: right-click attacks as usual (cleared just before lockdown)
		else
			channelEndedAt = GetTime()
		end
	end)
	-- A fishing pole in your main hand (fishPoleRightClickCast): right-click casts
	-- the first time too, standing still out of the fish camera. Not while
	-- the mouse is on a unit or an object you just moused over (an NPC,
	-- a mailbox, a corpse to loot): right-click is theirs.
	local poleEquipped = false
	local function CheckPole()
		local itemID = GetInventoryItemID("player", 16)
		local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
		local classID, subclassID
		if itemID and info then
			classID, subclassID = select(6, info(itemID))
		end
		poleEquipped = classID == 2 and subclassID == 20 -- weapon: fishing pole
	end
	local poleWatcher = CreateFrame("Frame")
	poleWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	poleWatcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	poleWatcher:SetScript("OnEvent", function() pcall(CheckPole) end)
	-- World objects under the mouse: their tooltip appearing (it may be hidden
	-- straight away by the tooltip options), and the mouse staying near there.
	local objectAt, objectX, objectY = -math.huge, 0, 0
	GameTooltip:HookScript("OnShow", function(self)
		local owner = self:GetOwner()
		if owner == nil or owner == UIParent or owner == WorldFrame then
			objectAt = GetTime()
			objectX, objectY = GetCursorPosition()
		end
	end)
	-- "Your cast didn't land in fishable water": likely a pole left equipped
	-- away from water, so right-click casting stands aside for fishMissPause sec.
	-- Moving and then standing still for MISS_SETTLE seconds ends it early: a
	-- new spot to fish from.
	local MISS_SETTLE = 1
	local missedAt = -math.huge
	local movedSinceMiss = false
	local stoppedAt -- standing still again since this time, after moving
	local missWatcher = CreateFrame("Frame")
	missWatcher:RegisterEvent("UI_ERROR_MESSAGE")
	-- "Skill not high enough": fishing water (or clicking something) beyond your
	-- skill. Moving won't fix that, so right-click casting stands aside for
	-- SKILL_PAUSE seconds whatever you do. (The game's own name for the message
	-- isn't certain, so a few likely ones are tried, and the English text.)
	local SKILL_PAUSE = 30
	local skillBlockedUntil = -math.huge
	local function IsSkillError(message)
		for _, name in ipairs({ "ERR_SKILL_NOT_HIGH_ENOUGH",
			"SPELL_FAILED_MIN_SKILL", "SPELL_FAILED_FISHING_TOO_LOW" }) do
			local text = _G[name]
			if type(text) == "string" then
				-- (One with a number or name filled in: the part before that.)
				local fixed = text:match("^(.-)%%") or text
				if message == text or (#fixed >= 8 and message:sub(1, #fixed) == fixed) then
					return true
				end
			end
		end
		return message == "Skill not high enough"
	end
	-- (Curly or straight apostrophes, either way.)
	local function Plain(text)
		return (text:gsub("\226\128\153", "'"))
	end
	local function IsMissError(message)
		return (type(SPELL_FAILED_NOT_FISHABLE) == "string" and Plain(message) == Plain(SPELL_FAILED_NOT_FISHABLE))
			or Plain(message) == "Your cast didn't land in fishable water"
	end
	ns.fishErrorDebug = {} -- for /dump: the last red error seen, and what it was taken for
	local function OnErrorText(message, via)
		if type(message) ~= "string" or (issecretvalue and issecretvalue(message)) then
			return
		end
		local taken
		if IsMissError(message) then
			missedAt, movedSinceMiss, stoppedAt = GetTime(), false, nil
			taken = "miss"
		elseif (poleEquipped or (ns.IsFish and ns.IsFish())) and IsSkillError(message) then
			skillBlockedUntil = GetTime() + SKILL_PAUSE
			taken = "skill"
		end
		ns.fishErrorDebug = { message = message, via = via, taken = taken, at = GetTime() }
	end
	missWatcher:SetScript("OnEvent", function(_, _, a, b)
		OnErrorText(type(b) == "string" and b or a, "event") -- (message second on newer clients)
	end)
	-- The same red text as it reaches the screen, in case a client sends it
	-- some other way than the event.
	if UIErrorsFrame and UIErrorsFrame.AddMessage then
		hooksecurefunc(UIErrorsFrame, "AddMessage", function(_, message) OnErrorText(message, "screen") end)
	end
	local OBJECT_REACH = 40 -- pixels (UI scale aside) the mouse can wander and still be on it
	local function MouseOnSomething()
		if UnitExists("mouseover") then
			return true
		end
		if GetTime() - objectAt > 30 then
			return false
		end
		local x, y = GetCursorPosition()
		return (x - objectX) ^ 2 + (y - objectY) ^ 2 < OBJECT_REACH ^ 2
	end

	recastWatcher:SetScript("OnUpdate", function()
		if not castButton then
			return
		end
		-- Right button held: the binding stays as it was pressed. Swapping it
		-- mid-press sends the release to the other binding, so a right-drag
		-- begun as the game's (turning) never got its stop and stayed stuck.
		local rightHeld = IsMouseButtonDown("RightButton")
		if missedAt > -math.huge then
			if ns.playerMoving then
				movedSinceMiss, stoppedAt = true, nil
			elseif movedSinceMiss then
				stoppedAt = stoppedAt or GetTime()
				if GetTime() - stoppedAt >= MISS_SETTLE then
					missedAt, movedSinceMiss, stoppedAt = -math.huge, false, nil -- settled somewhere new
				end
			end
		end
		local inCombat = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
		if inCombat then
			combatSeenAt = GetTime()
		end
		local fishCam = ns.IsFish and ns.IsFish()
		local pole = ns.db and ns.db.fishPoleRightClickCast and poleEquipped and not fishCam
			and not ns.playerMoving and not IsMounted() and not UnitOnTaxi("player")
			and not ns.Flag(UnitIsDeadOrGhost("player")) and not MouseOnSomething()
		-- (In the fish camera only units count: the spot you just looted the
		-- bobber at would otherwise keep right-click from casting again there.)
		-- (Left button held: right-click is the game's, so both together run you forward.)
		local want = ns.db and ns.db.fishRightClickCast and not IsMouseButtonDown("LeftButton")
			and ((fishCam and not UnitExists("mouseover")) or pole)
			and not UnitChannelInfo("player") and not UnitCastingInfo("player")
			and GetTime() - channelEndedAt >= (tonumber(ns.db.fishRecastDelay) or 0.5)
			and GetTime() - missedAt >= (tonumber(ns.db.fishMissPause) or 30)
			and GetTime() >= skillBlockedUntil
			and not (LootFrame and LootFrame:IsShown())
			and not inCombat and GetTime() - combatSeenAt >= AFTER_COMBAT
		if not rightHeld then
			SetRecast(want and true or false)
		end
	end)
end

-- Sitting on a chair or bench: there's no event for it, so it's pieced
-- together. The world tooltip's name is noted as it appears (before the
-- tooltip options hide it); a right-click while it names a seat, followed by
-- the brief snap onto the seat (a quick move that stops), counts as sitting.
local lastWorldName, lastWorldNameAt = nil, 0
local seatClickAt = -math.huge
local SEAT_CLICK_WINDOW = 4   -- seconds between the seat's name appearing and the click
local SEAT_SNAP_WINDOW = 3    -- seconds after the click for the snap onto the seat
local SEAT_SNAP_MOVE = 0.15   -- yards: being moved at least this far onto it counts

local function IsSeatName(name)
	if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) or not ns.db then
		return false
	end
	local lower = name:lower()
	for word in (ns.db.cozyChairWords or ""):gmatch("[^,]+") do
		word = word:match("^%s*(.-)%s*$"):lower()
		if word ~= "" and lower:find(word, 1, true) then
			return true
		end
	end
	return false
end
local CancelIdleZoom -- defined with the idle zoom below

local function OnPlayerCameraInput(what)
	if not drivingCamera then
		lastCameraInput = GetTime()
		ns.lastCameraInputWhat = what -- (for the log: what took a flight over)
	end
end

-- Mouse buttons held on the game world. Left-drag moves only the camera and
-- doesn't count as mouselook, so it's caught through the functions the mouse
-- bindings call. (A plain click to select something counts too.)
local mouseCameraHeld = false

-- The player's own zooming: they've chosen a new distance, so the idle zoom
-- stops managing it (no snapping back later). Also counts as camera input.
local function OnPlayerZoom()
	if not drivingCamera then
		-- Zoomed yourself on a flight: your distance stays at landing (see
		-- taxiLandZoom), rather than going back to the one you took off with.
		if UnitOnTaxi("player") and ns.db then
			ns.db.takeoffZoom = nil
		end
		if CancelIdleZoom then CancelIdleZoom() end
		if ns.CancelDeathZoom then ns.CancelDeathZoom() end
		lastCameraInput = GetTime()
		ns.lastCameraInputWhat = "zoom"
	end
end

function ns.HookCameraInput()
	-- Seats: note world tooltip names, watch right-clicks and the snap.
	GameTooltip:HookScript("OnShow", function(self)
		local owner = self:GetOwner()
		if owner == nil or owner == UIParent or owner == WorldFrame then
			local ok, text = pcall(function() return GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText() end)
			if ok and type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
				lastWorldName, lastWorldNameAt = text, GetTime()
			end
		end
	end)
	local function Position()
		local ok, y, x = pcall(UnitPosition, "player")
		if ok and type(y) == "number" and not (issecretvalue and (issecretvalue(y) or issecretvalue(x))) then
			return x, y
		end
	end
	local seatX, seatY
	local function Seated(how)
		seatClickAt = -math.huge
		emoteEvent = "Chair" -- the latest choice wins
		ns.lastEmote = { token = "CHAIR", via = how .. " on " .. tostring(lastWorldName), at = GetTime() }
	end
	local seatWatcher = CreateFrame("Frame")
	seatWatcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
	seatWatcher:RegisterEvent("PLAYER_STOPPED_MOVING")
	seatWatcher:SetScript("OnEvent", function(_, event, button)
		local now = GetTime()
		if event == "GLOBAL_MOUSE_DOWN" then
			if button == "RightButton" then
				ns.seatDebug = { name = lastWorldName, nameAge = now - lastWorldNameAt,
					seat = IsSeatName(lastWorldName), at = now }
				if now - lastWorldNameAt <= SEAT_CLICK_WINDOW and IsSeatName(lastWorldName) then
					seatClickAt = now
					seatX, seatY = Position()
				end
			end
		elseif now - seatClickAt <= SEAT_SNAP_WINDOW then
			Seated("snap (movement stopped)")
		end
	end)
	-- The snap may not send a movement event: watch your position instead.
	seatWatcher:SetScript("OnUpdate", function()
		if GetTime() - seatClickAt > SEAT_SNAP_WINDOW or not seatX then
			return
		end
		local x, y = Position()
		if x and ((x - seatX) ^ 2 + (y - seatY) ^ 2) > SEAT_SNAP_MOVE ^ 2 and not ns.playerMoving then
			Seated("snap (moved onto it)")
		end
	end)
	-- Emotes: whichever emote function this client uses, plus typed commands
	-- (see below), all end up here with the emote's token ("DANCE", "SIT", ...).
	local function OnEmote(token, via)
		if type(token) ~= "string" then
			return
		end
		ns.lastEmote = { token = token, via = via, at = GetTime() }
		local event = EMOTE_EVENTS[token:upper()]
		if event or emoteEvent ~= "Fishing" then -- (a /wave doesn't end fishing)
			emoteEvent = event
		end
	end
	if DoEmote then
		hooksecurefunc("DoEmote", function(token) OnEmote(token, "DoEmote") end)
	end
	if C_ChatInfo and C_ChatInfo.PerformEmote then
		hooksecurefunc(C_ChatInfo, "PerformEmote", function(token) OnEmote(token, "PerformEmote") end)
	end

	-- Typed emotes: note the last slash command typed in chat; when the game
	-- then reports you doing an emote, match the command to its token using the
	-- game's own emote command lists (so any language and any alias works).
	local commandToken -- "/dance" -> "DANCE", built on first use
	local function TokenForCommand(command)
		if not commandToken then
			commandToken = {}
			for i = 1, 1000 do
				local token = _G["EMOTE" .. i .. "_TOKEN"]
				if token then
					for j = 1, 10 do
						local cmd = _G["EMOTE" .. i .. "_CMD" .. j]
						if cmd then commandToken[cmd:lower()] = token end
					end
				end
			end
		end
		return commandToken[command]
	end
	local typedCommand, typedAt
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local editBox = _G["ChatFrame" .. i .. "EditBox"]
		if editBox then
			editBox:HookScript("OnTextChanged", function(self)
				local command = (self:GetText() or ""):match("^(/%S+)")
				if command then
					typedCommand, typedAt = command:lower(), GetTime()
				end
			end)
		end
	end
	local emoteWatcher = CreateFrame("Frame")
	emoteWatcher:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
	emoteWatcher:SetScript("OnEvent", function(_, _, _, _, _, _, _, _, _, _, _, _, _, guid)
		if not typedCommand or GetTime() - typedAt > 3 then
			return
		end
		-- Yours? (If the game hides who it was, the command you just typed is
		-- good enough.)
		local ok, mine = pcall(function() return guid == UnitGUID("player") end)
		if mine or not ok or guid == nil then
			local command = typedCommand
			typedCommand = nil
			local token = TokenForCommand(command)
			if token then
				OnEmote(token, "typed " .. command)
			end
		end
	end)
	if SitStandOrDescendStart then
		hooksecurefunc("SitStandOrDescendStart", function()
			if not IsFlying or not IsFlying() then
				-- The sit key toggles (from a /stare, it sits you down).
				emoteEvent = (emoteEvent == nil or emoteEvent == "Stare" or emoteEvent == "Fishing") and "Sit" or nil
			end
		end)
	end
	if JumpOrAscendStart then
		hooksecurefunc("JumpOrAscendStart", function() -- jumping stands you up
			emoteEvent = nil
			ns.manualCam = nil
			ns.StopEventsOnMove()
		end)
	end
	for _, name in ipairs({ "CameraZoomIn", "CameraZoomOut" }) do
		if _G[name] then
			hooksecurefunc(name, OnPlayerZoom)
		end
	end
	for _, name in ipairs({
		"MoveViewLeftStart", "MoveViewRightStart", "MoveViewUpStart", "MoveViewDownStart",
		"SetView", "ResetView",
	}) do
		if _G[name] then
			hooksecurefunc(name, function() OnPlayerCameraInput(name) end)
		end
	end
	for _, name in ipairs({ "CameraOrSelectOrMoveStart", "TurnOrActionStart" }) do
		if _G[name] then
			hooksecurefunc(name, function() mouseCameraHeld = GetTime() end) -- (when it was pressed)
		end
	end
	for _, name in ipairs({ "CameraOrSelectOrMoveStop", "TurnOrActionStop" }) do
		if _G[name] then
			hooksecurefunc(name, function() mouseCameraHeld = false end)
		end
	end
	-- Turn keys (for spotting turns where the facing direction is hidden).
	for name, value in pairs({ TurnLeftStart = true, TurnLeftStop = false }) do
		if _G[name] then
			hooksecurefunc(name, function() turnKeys.left = value end)
		end
	end
	for name, value in pairs({ TurnRightStart = true, TurnRightStop = false }) do
		if _G[name] then
			hooksecurefunc(name, function() turnKeys.right = value end)
		end
	end
end

local function IsMouseOnCamera()
	-- Fishing: a quick click (right-clicking the bobber) isn't moving the camera;
	-- only holding the button down a moment is.
	if mouseCameraHeld and ns.IsFishingEvent and ns.IsFishingEvent() then
		return GetTime() - mouseCameraHeld >= 0.4
	end
	return mouseCameraHeld and true or (IsMouselooking and IsMouselooking()) or false
end

-- Turning left or right, by keys or mouse: the facing direction changing
-- faster than TURN_RATE, or a turn key held (where facing is hidden).
local TURN_RATE = math.rad(20) -- radians per second
local lastFacing

-- Returns whether you're turning, and how many degrees you turned this frame
-- (positive = left; 0 when the facing direction is hidden).
local function IsTurning(elapsed)
	local ok, facing = pcall(GetPlayerFacing)
	if not ok or type(facing) ~= "number" or (issecretvalue and issecretvalue(facing)) then
		lastFacing = nil
		return turnKeys.left or turnKeys.right, 0
	end
	local previous = lastFacing
	lastFacing = facing
	if not previous or elapsed <= 0 then
		return turnKeys.left or turnKeys.right, 0
	end
	local delta = facing - previous
	if delta > math.pi then
		delta = delta - 2 * math.pi -- crossed north
	elseif delta < -math.pi then
		delta = delta + 2 * math.pi
	end
	local turning = turnKeys.left or turnKeys.right or math.abs(delta) / elapsed > TURN_RATE
	return turning, math.deg(delta)
end

local function StopAxis(axis)
	if axis.moving then
		CallCameraFunction(axis.positive and axis.positiveStop or axis.negativeStop)
		axis.moving = false
		axis.speed = 0
	end
end

local function MoveAxis(axis, degreesPerSecond, positive)
	if degreesPerSecond <= 0 then
		StopAxis(axis)
		return
	end
	if axis.moving and axis.positive ~= positive then
		StopAxis(axis)
	end
	-- (While a fly-by holds the turn speed setting, or is about to put yours
	-- back, the speed is worked out from yours: worked out from the fly-by's,
	-- it would jump as yours came back.)
	local held = axis == ns.yawAxis and ns.flyByHoldsYawSpeed and tonumber(ns.db.savedCVars[axis.speedCVar])
	local speed = degreesPerSecond / (held or tonumber(GetCVar(axis.speedCVar)) or axis.defaultSpeed)
	-- Every MoveView*Start call restarts the camera move, which hitches if done
	-- every frame. Skip imperceptible changes, and while already moving the same
	-- way, change speed at most every ORBIT_RESTART_INTERVAL. (Early in a move
	-- the speed climbs from ~0, so the relative check alone passes every frame.)
	local now = GetTime()
	if axis.moving then
		local change = math.abs(speed - axis.speed)
		if change <= axis.speed * ORBIT_SPEED_EPSILON then
			return
		end
		-- Big changes (a turn key released, say) go through at once; holding them
		-- back even a twentieth of a second shows as a snap.
		if now - axis.lastStart < ORBIT_RESTART_INTERVAL and change <= axis.speed * ORBIT_BIG_CHANGE then
			return
		end
	end
	axis.positive, axis.moving, axis.speed, axis.lastStart = positive, true, speed, now
	CallCameraFunction(positive and axis.positiveStart or axis.negativeStart, speed)
end

-- Speed profile for one move of duration T: ease up over the first R = ease*T
-- seconds, cruise, then ease down over the last R. The ramps are half cosine
-- waves, so acceleration starts and ends at zero (no jolt). Each ramp covers
-- half its length at cruise speed, so distance = cruise * (T - R).
-- With ease = 0.5 there's no cruise: one smooth swell (a sin^2 curve).
local function EaseShape(t, T, ease)
	local R = ease * T
	if R <= 0 then
		return 1
	elseif t < R then
		return (1 - math.cos(math.pi * t / R)) / 2
	elseif t > T - R then
		return (1 - math.cos(math.pi * (T - t) / R)) / 2
	end
	return 1
end

-- The active profile's value for a rotation setting ("Mode", "Pause", ...).
local orbitPrefix = "taxiOrbit"
local CONTINUOUS_RAMP = 3 -- seconds a continuous turn takes to reach full speed
local CONTINUOUS_FADE = 1.5 -- seconds it takes to ease out when handing over to moves
local HANDOFF_PAUSE = 1 -- seconds: stopped walking, the first sweep starts this soon
local walkHandoff = false

-- Cozy camera triggers. Buffs: any from the player's list (names or spell
-- IDs, cozyBuffs), checked whenever your buffs change. Emotes: followed from
-- the emote calls, and over once you move, jump or do another emote.
-- (EMOTE_EVENTS and emoteEvent are declared near the top, for the input hooks.)
local atCampfire = false
local function HasBuffNamed(name)
	local id = tonumber(name)
	if id then
		if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
			local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
			return ok and type(aura) == "table"
		end
		return false
	end
	if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
		local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
		if ok then
			return type(aura) == "table"
		end
	end
	if AuraUtil and AuraUtil.FindAuraByName then
		local ok, found = pcall(AuraUtil.FindAuraByName, name, "player", "HELPFUL")
		return ok and found ~= nil
	end
	return false
end
local campfireWatcher = CreateFrame("Frame")
campfireWatcher:RegisterUnitEvent("UNIT_AURA", "player")
campfireWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
local function CheckIdleBuffs()
	local found = false
	if ns.db and ns.db.cozyBuffs then
		for name in ns.db.cozyBuffs:gmatch("[^,]+") do
			name = name:match("^%s*(.-)%s*$")
			if name ~= "" and HasBuffNamed(name) then
				found = true
				break
			end
		end
	end
	atCampfire = found
end
campfireWatcher:SetScript("OnEvent", CheckIdleBuffs)
ns.CheckIdleBuffs = CheckIdleBuffs -- after the list changes
function ns.IsAtCampfire() return atCampfire end

-- Weapon drawn (melee or ranged), or false if the game won't say.
local function WeaponDrawn()
	if not GetSheathState then
		return false
	end
	local ok, state = pcall(GetSheathState)
	return ok and type(state) == "number" and not (issecretvalue and issecretvalue(state)) and state >= 2
end

-- The weapon trigger: only a weapon you drew yourself out of combat, and never
-- in combat. One drawn for a fight (and still out after it) doesn't count
-- until it's put away and drawn again. Nor does one already out as you log in
-- or reload (weaponWasDrawn is nil until the first look after loading in).
local weaponWasDrawn, weaponDrawnCalmly = nil, false
campfireWatcher:HookScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		weaponWasDrawn, weaponDrawnCalmly = nil, false
	end
end)
local function WeaponCozy()
	local drawn = WeaponDrawn()
	local inCombat = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	if weaponWasDrawn == nil then
		weaponWasDrawn = drawn -- loading in: whatever's out already doesn't count
	end
	if drawn and not weaponWasDrawn then
		-- (Casting Fishing brings the pole out: that draw doesn't count.)
		weaponDrawnCalmly = not inCombat and emoteEvent ~= "Fishing"
		if weaponDrawnCalmly then
			emoteEvent = nil -- drawn after an emote: the latest choice wins
		end
	end
	if not drawn or inCombat then
		weaponDrawnCalmly = false
	end
	weaponWasDrawn = drawn
	return weaponDrawnCalmly
end

-- For /cine debug weapon.
function ns.GetWeaponDebug()
	local ok, state = false, nil
	if GetSheathState then
		ok, state = pcall(GetSheathState)
	end
	return {
		exists = GetSheathState ~= nil, ok = ok, state = tostring(state),
		drawn = WeaponDrawn(), calm = weaponDrawnCalmly, cozy = ns.IsCozy(),
	}
end

-- The camera an event is set to on the Events page, or nil for none.
local function EventCamera(key)
	local camera = key and ns.db["event" .. key .. "Camera"]
	if camera and camera ~= "none" then
		if key == "Hearth" or key == "Teleport" then
			return "tele" -- (its only camera; early test versions saved "cozy")
		end
		return camera
	end
end

-- Fishing with a camera set for it: the cast doesn't count as busy casting.
function ns.IsFishingEvent()
	return emoteEvent == "Fishing" and ns.db ~= nil and EventCamera("Fishing") ~= nil
end

-- The same for your Hearthstone or a teleport.
function ns.IsDepartEvent()
	return (emoteEvent == "Hearth" or emoteEvent == "Teleport") and ns.db ~= nil
		and EventCamera(emoteEvent) ~= nil
end

-- The event happening now and its camera, before any wait (see ActiveEvent).
-- Its helpers sit in a do block: this file is at Lua's 200-local limit.
local CurrentEvent
do
	-- Events set to stop on moving that you've moved or jumped during: passed
	-- over until they end (weapon put away, buff gone, back from AFK) and start afresh.
	local stoppedByMove = {}
	local function EventOn(key)
		if key == "Weapon" then
			return weaponDrawnCalmly
		elseif key == "Campfire" then
			return atCampfire
		elseif key == "AFK" then
			return ns.Flag(UnitIsAFK("player"))
		end
	end
	-- Moving or jumping now: stop the events that are on and set to stop.
	function ns.StopEventsOnMove(except)
		if not ns.db then
			return
		end
		for _, event in ipairs(ns.EVENTS) do
			if event.stopsOnMove and event.key ~= except and ns.db["event" .. event.key .. "StopOnMove"]
				and EventOn(event.key) then
				stoppedByMove[event.key] = true
			end
		end
	end
	-- Whether an event's state counts now (on, and not stopped by moving).
	local function EventLive(key, on)
		if not on then
			stoppedByMove[key] = nil -- ended: the next one starts afresh
			return false
		end
		return not stoppedByMove[key]
	end

	-- Logging out (or quitting) with the 20-second countdown. Where logging out
	-- is instant (an inn, a city) there's no countdown, and no event. Moving,
	-- jumping, casting or Cancel ends it. The game's cancel event isn't relied
	-- on alone (a logout left "on" would hold every other camera off): the
	-- countdown box closing, moving, or still being here once the countdown's
	-- run out all end it too.
	local LOGOUT_COUNTDOWN = 20 -- seconds
	local LOGOUT_POPUP_GRACE = 1 -- seconds for the countdown box to show
	local logoutAt -- when the countdown started, while it's on
	local logoutWatcher = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_CAMPING", "PLAYER_QUITING", "LOGOUT_CANCEL", "PLAYER_ENTERING_WORLD" }) do
		pcall(logoutWatcher.RegisterEvent, logoutWatcher, event)
	end
	logoutWatcher:SetScript("OnEvent", function(_, event)
		logoutAt = (event == "PLAYER_CAMPING" or event == "PLAYER_QUITING") and GetTime() or nil
	end)
	local function LoggingOut()
		if not logoutAt then
			return false
		end
		local since = GetTime() - logoutAt
		local boxGone = false
		if since > LOGOUT_POPUP_GRACE and StaticPopup_FindVisible then
			local ok, shown = pcall(function()
				return StaticPopup_FindVisible("CAMP") or StaticPopup_FindVisible("QUIT")
			end)
			boxGone = ok and not shown
		end
		if boxGone or since > LOGOUT_COUNTDOWN + 2 then
			logoutAt = nil
			return false
		end
		return true
	end
	-- (For casting your Hearthstone or a teleport: that calls a logout off too.)
	function ns.EndLogoutEvent()
		logoutAt = nil
	end

	function CurrentEvent()
		if not ns.db or UnitOnTaxi("player") then
			return nil
		end
		local weapon = EventLive("Weapon", WeaponCozy())
		local campfire = EventLive("Campfire", atCampfire)
		local afk = EventLive("AFK", ns.Flag(UnitIsAFK("player")))
		if ns.playerMoving then
			logoutAt = nil -- (moving calls a logout off)
			if ns.MovingManually and ns.MovingManually() then
				-- Moving by hand: every event ends, even those set to carry on
				-- through moving (they start afresh: the weapon drawn again...).
				-- Only auto-run and auto-walk carry the cameras on.
				for _, event in ipairs(ns.EVENTS) do
					if EventOn(event.key) then
						stoppedByMove[event.key] = true
					end
				end
				return nil
			end
			-- Moving ends them all, except a weapon drawn while RP walking for the
			-- cozy camera: it swings round in front of you as you walk (a "hero walk").
			local heroWalk = weapon and EventCamera("Weapon") == "cozy" and ns.IsRPWalking and ns.IsRPWalking()
			ns.StopEventsOnMove(heroWalk and "Weapon")
			if heroWalk then
				return "Weapon", "cozy"
			end
			return nil
		end
		if ns.db.cameraPauseAtNPCs and ns.NPCWindowOpen and ns.NPCWindowOpen() then
			return nil -- talking to an NPC: waits until the window closes
		end
		if ns.db.cameraPauseInMenus and ns.MenuWindowOpen and ns.MenuWindowOpen() then
			return nil -- in a menu or game window: waits until it closes
		end
		if ns.manualCam then
			return "Manual", ns.manualCam -- started from a key binding (Cinematic_StartCam)
		end
		-- A Hearthstone or teleport cast first (it calls a logout off anyway),
		-- then logging out, then going AFK (it comes after whatever you were
		-- doing: AFK while sitting is the AFK camera), then the rest.
		local departing = (emoteEvent == "Hearth" or emoteEvent == "Teleport") and emoteEvent
		for _, key in ipairs({ departing, LoggingOut() and "Logout", afk and "AFK", emoteEvent or false,
			weapon and "Weapon", campfire and "Campfire" }) do
			local camera = key and EventCamera(key)
			if camera then
				return key, camera
			end
		end
		return nil
	end
end

-- The event that picks the standing-still camera now, and its camera ("cozy",
-- "vista", "fish", "afk" or "tele"), or nil. A Hearthstone or teleport cast
-- comes first, then logging out, going AFK, the latest emote (or seat), a
-- drawn weapon and a campfire buff; one set to no camera is passed over.
-- An event with a delay counts only once it has lasted that many seconds, and
-- one whose camera is turned off here (Camera modes page) doesn't count.
local EVENT_CAM = { cozy = "cozy", vista = "vista", fish = "fish", afk = "idle", tele = "tele" }
local lastEvent, eventSince = nil, 0
function ns.ActiveEvent()
	local key, camera = CurrentEvent()
	local now = GetTime()
	if key ~= lastEvent then
		lastEvent, eventSince = key, now
	end
	if key and now - eventSince < EventDelay(key) then
		return nil
	end
	if camera and EVENT_CAM[camera] and ns.IsCameraOffHere(EVENT_CAM[camera]) then
		return nil
	end
	return key, camera
end

-- For /cine debug emote: the event happening now, and how long until it counts.
function ns.GetEventDebug()
	local key, camera = CurrentEvent()
	local wait = 0
	if key and key == lastEvent then
		wait = math.max(0, EventDelay(key) - (GetTime() - eventSince))
	end
	return key, camera, wait
end

-- Vista: the camera lines up behind you and sways gently there, looking out
-- the way you're facing.
function ns.IsVista()
	return select(2, ns.ActiveEvent()) == "vista"
end

-- Fish: the vista camera with a narrower sway, for fishing.
function ns.IsFish()
	return select(2, ns.ActiveEvent()) == "fish"
end

-- Cozy: the camera swings round to face you and sways in front. The tele
-- camera is the cozy camera too, with its own spin and zoom (ns.IsTele).
function ns.IsCozy()
	local camera = select(2, ns.ActiveEvent())
	return camera == "cozy" or camera == "tele"
end

-- Tele: casting your Hearthstone or a teleport.
function ns.IsTele()
	return select(2, ns.ActiveEvent()) == "tele"
end

-- An event set to the AFK camera: it starts without waiting out its delay.
function ns.IsEventAFK()
	return select(2, ns.ActiveEvent()) == "afk"
end
local RECENTER_TIME = 5 -- seconds a swing back behind you lasts
local recenterUntil = 0
-- Travel modes (RP walk, auto-run) line up behind you before swaying: a
-- slower version of the takeoff swing that carries on while you move.
local TRAVEL_CENTER_TIME = 5
local TRAVEL_CENTER_RAMP = 2 -- seconds for that glide to build up speed (no lurch)
-- Auto-running with no fight for a while: a quicker line-up.
local CALM_AFTER_COMBAT = 60
local CALM_CENTER_TIME = 2.5
local CALM_CENTER_RAMP = 0.8
local CALM_CENTER_YAW = 70
local CALM_CENTER_PITCH = 40
local lastCombatAt = -math.huge
-- Each camera mode can hold off for a while after a fight (its <mode>CombatWait
-- setting, in seconds; 0: no wait). Looked up by mode ("run") or orbit prefix
-- ("runOrbit"). The death camera has none: it runs in combat by design.
local COMBAT_WAIT_KEY = {}
for _, mode in ipairs({ "taxi", "idle", "walk", "run", "cozy", "vista", "fish", "tele" }) do
	COMBAT_WAIT_KEY[mode] = mode .. "CombatWait"
	COMBAT_WAIT_KEY[mode .. "Orbit"] = mode .. "CombatWait"
end
-- (On ns, not a local: UpdateOrbit is close to Lua's upvalue limit.)
function ns.CombatWaitOver(mode, now)
	local key = COMBAT_WAIT_KEY[mode]
	return not key or now - lastCombatAt >= (ns.db[key] or 0)
end
local lastAnyTurnAt = -math.huge
local followArmed = false -- turn hold-and-glide ready (not armed mid-turn)
-- Steering a lot: this many turns started within the window means the glide
-- after a turn starts sooner and moves quicker.
local TURN_BURST_COUNT = 3
local TURN_BURST_WINDOW = 4    -- seconds
local STEER_GLIDE_DELAY = 0.3  -- seconds before gliding, at most, while steering
local STEER_GLIDE_BOOST = 1.5  -- glide speed-up while steering
-- Auto-run: bigger turns glide back quicker. Up to TURN_SIZE_SMALL degrees off
-- is the normal glide; each TURN_SIZE_PER degrees beyond adds 1x, up to +1.5x.
local TURN_SIZE_SMALL = 15
local TURN_SIZE_PER = 50
local TURN_SIZE_BOOST_MAX = 1.5
local TURN_SIZE_GENTLE = 0.5 -- small turns glide at down to half the normal speed
local turnStarts, wasTurningAny = {}, false
local TRAVEL_START_AFTER_TURN = 0.6 -- seconds of not turning before a travel camera starts
local TRAVEL_CENTER_YAW = 40
local TRAVEL_CENTER_PITCH = 25
local travelRecenter = false
-- RP walk turn follow: when you turn, the camera keeps its direction instead
-- of snapping round with you, then glides round behind your new facing.
-- turnOffset is how far (degrees, left positive) the camera is from behind you.
local TURN_FOLLOW_TIME = 1.6  -- seconds: how lazily it follows (bigger is gentler)
local TURN_FOLLOW_MAX = 40    -- degrees per second, at most
local TURN_FOLLOW_ACCEL = 30  -- degrees per second per second: eases the glide in and out
local TURN_FOLLOW_DONE = 0.5  -- degrees: close enough to behind
local GLIDE_BRAKE_MARGIN = 0.8 -- share of the full stopping speed allowed (some slack)
-- While gliding, the game's own camera follow is off so the two don't fight.
local TURN_FOLLOW_CVARS = { values = { cameraSmoothStyle = "0" } }
local turnOffset, turnGlide = 0, 0
local turnRate = 0          -- your turn speed (degrees per second, left positive), smoothed
local TURN_SMOOTH = 0.08    -- seconds of smoothing on its jitter
local TURN_JUMP = 15        -- degrees per second: bigger changes are followed at once
local yawExtra = 0 -- degrees per second added to the camera's yaw this frame
local lastTurnAt = -math.huge

-- The camera's yaw: the orbit's own speed (signed, left positive) plus any
-- turn-follow speed.
local function DriveYaw(speed)
	local total = speed + yawExtra
	MoveAxis(ns.yawAxis, math.abs(total), total > 0)
end
-- Each camera has a fixed style (no mode choice): steady sweeps standing
-- still, swings behind you on flights and while RP walking.
local FIXED_MODE = { idleOrbit = "sweep", taxiOrbit = "back", walkOrbit = "back", runOrbit = "back",
	cozyOrbit = "back", vistaOrbit = "back", fishOrbit = "back", deathOrbit = "sweep" }
-- The swing's centre: behind you (0), or in front for the cozy camera.
local ARC_CENTER = { cozyOrbit = 180 }
local function ArcCenter(prefix)
	return ARC_CENTER[prefix] or 0
end
-- Tilt centre for the cozy camera: down toward the ground. (On the pitch axis,
-- positive is the "view up" command, which in this client raises the camera to
-- look down more steeply; so lowering it is negative.)
-- Steering a lot while auto-running (set by the turn handling): the camera
-- comes in closer and lower, for control.
local steeringNow = false
local STEER_LOWER = 12 -- degrees lower while steering
local steerLowered = false

local function PitchCenter()
	if orbitPrefix == "cozyOrbit" then
		return ns.IsTele() and -ns.db.teleLevel or -ns.db.cozyLevel
	elseif orbitPrefix == "vistaOrbit" then
		return -ns.db.vistaLevel
	elseif orbitPrefix == "fishOrbit" then
		return -ns.db.fishLevel
	elseif (orbitPrefix == "runOrbit" or orbitPrefix == "walkOrbit") and steeringNow then
		return -STEER_LOWER
	end
	return 0
end
local COZY_TURN_SPEED = 15 -- degrees per second, at most, swinging round to face you
local cozySessionStarted = false -- this cozy spell has already swung round to face you
local COZY_START_EASE = 0.2 -- that swing spends this share speeding up (and slowing down)
local COZY_ARRIVE_EDGE = 1 -- it arrives at the near edge of the sway (share of it)
local COZY_ZOOM_START = 9   -- seconds for the first zoom in to the close-up (with the swing round)
local COZY_ZOOM_EASE = 0.35 -- ...easing in and out alongside it

-- On-foot travel modes (moving camera modes): RP walking and auto-running.
-- Each has the same kinds of settings under its own keys.
local TRAVEL = {
	-- glide: how the view follows you round after a turn (seconds of laziness,
	-- top speed, easing); auto-run catches up quicker than a stroll.
	walk = { orbit = "walkOrbit", zoom = "walkZoom", pause = "walkInputPause",
		swing = "walkSwingBehind", delay = "walkGlideDelay", glide = { 1.6, 40, 30 } },
	run = { orbit = "runOrbit", zoom = "runZoom", pause = "runInputPause",
		swing = "runSwingBehind", delay = "runGlideDelay", glide = { 1.0, 70, 60 }, sizeBoost = true },
}
-- Standing still and the travel modes hand over seamlessly between each other.
local FOOT_ORBIT = { idleOrbit = true, walkOrbit = true, runOrbit = true, cozyOrbit = true }
-- (The vista and fish cameras always start afresh, so they can line up behind you first.)
local FOOT_ZOOM = { idle = true, walk = true, run = true, cozy = true, vista = true, fish = true }
-- Modes that line up behind you before they start (cozy then swings round).
local LINEUP_ORBIT = { walkOrbit = true, runOrbit = true, vistaOrbit = true, fishOrbit = true }
-- Modes whose sway favours angles near directly behind (the way you face).
local TRAVEL_ORBIT = { walkOrbit = true, runOrbit = true, vistaOrbit = true, fishOrbit = true }
-- Indoors (with the indoor limits on): smaller swings and zoom, so the
-- camera doesn't keep pushing into walls and ceilings. Never on a flight: the
-- game calls you indoors around some flight points and buildings on the way,
-- and the flag flicking on and off changed the zoom mid-flight (snapping a
-- fly-by's turn).
local function Indoors()
	if not ns.db.indoorLimits or UnitOnTaxi("player") then
		return false
	end
	local ok, indoors = pcall(IsIndoors)
	return ok and indoors == true
end

local function OrbitSetting(key)
	if key == "Mode" then
		return FIXED_MODE[orbitPrefix]
	end
	if key == "Right" and ns.db[orbitPrefix .. "RandomDir"] then
		return ns.orbit.randomRight -- picked as the AFK or death camera starts
	end
	local value = ns.db[orbitPrefix .. key]
	if (key == "BackArc" or key == "MinChange") and Indoors() then
		local limit = ns.db.indoorSwing
		if key == "MinChange" then
			limit = limit / 2 -- keep it below the swing so moves still vary
		end
		return math.min(value, limit)
	end
	return value
end

ns.orbit = {
	level = 0, phase = "move", t = 0,
	yawDelta = 0, pitchDelta = 0, sweepTime = ORBIT_MIN_SWEEP_TIME,
	angle = 0, pitch = 0,
}

local function WrapAngle(angle)
	if angle > 180 then
		return angle - 360
	elseif angle < -180 then
		return angle + 360
	end
	return angle
end

-- The Hearthstone and teleport spin (the cozy camera while you cast one): the
-- swing round eases in, then keeps speeding up until you go. Cancel the cast
-- and it brakes, then turns back to where the camera was before it started.
-- (In a do block: this file is at Lua's 200-local limit.)
do
	local SPIN_BRAKE = 1.5  -- seconds to brake to a stop once the cast is cancelled
	local RETURN_SPEED = 45 -- degrees per second (about) for the turn back
	local RETURN_MIN = 1.5  -- seconds, at least, for the turn back

	-- The spin's yaw speed now (degrees per second, unsigned), and whether it's
	-- still going (false once it has braked to a stop after a cancel).
	function ns.SpinSpeed(elapsed)
		local o = ns.orbit
		local T, ease, t = o.sweepTime, o.ease, o.t
		if ns.DepartTimeLeft() then
			-- (At least as fast as a half-turn swing: from in front of you already,
			-- say straight after the cozy camera, the swing is short, but the spin
			-- carries on past the front anyway, so it shouldn't set off at a crawl.)
			local base = math.max(math.abs(o.yawDelta), 180) / (T * (1 - ease))
			local speed = t < ease * T and base * EaseShape(t, T, ease) or base + ns.db.teleSpinAccel * (t - ease * T)
			o.spinSpeed = math.min(speed, math.max(base, ns.db.teleSpinMax))
			return o.spinSpeed, true
		end
		o.brakeT = (o.brakeT or 0) + elapsed
		local f = math.min(1, o.brakeT / SPIN_BRAKE)
		return (o.spinSpeed or 0) * (1 + math.cos(math.pi * f)) / 2, f < 1
	end

	-- After a cancelled spin has stopped: turn back to the starting view (angle
	-- and tilt 0, where the cozy camera began). Returns true while it's turning.
	-- Moving the camera yourself drops it.
	function ns.StepSpinReturn(elapsed, adjusting)
		local o = ns.orbit
		if o.returnPending then
			o.returnPending = false
			if not adjusting then
				local yaw, pitch = WrapAngle(-o.angle), -o.pitch
				o.back = { yaw = yaw, pitch = pitch, t = 0,
					T = math.max(RETURN_MIN, math.abs(yaw) / RETURN_SPEED, math.abs(pitch) / RETURN_SPEED) }
			end
		end
		local back = o.back
		if not back then
			return false
		end
		back.t = back.t + elapsed
		if adjusting or back.t >= back.T then
			StopAxis(ns.yawAxis)
			StopAxis(ns.pitchAxis)
			o.back = nil
			return false
		end
		-- One smooth swell (no cruise), from a standstill to a standstill.
		local shape = EaseShape(back.t, back.T, 0.5) / (back.T * 0.5)
		local yawSpeed, pitchSpeed = back.yaw * shape, back.pitch * shape
		MoveAxis(ns.yawAxis, math.abs(yawSpeed), yawSpeed > 0)
		MoveAxis(ns.pitchAxis, math.abs(pitchSpeed), pitchSpeed > 0)
		o.angle = WrapAngle(o.angle + yawSpeed * elapsed)
		o.pitch = o.pitch + pitchSpeed * elapsed
		return true
	end
end

-- Back mode: random target in [-limit, limit] at least minChange from the
-- current angle, chosen uniformly over the allowed stretches.
local function PickBackTarget(limit, current)
	local a, min = current or ns.orbit.angle, OrbitSetting("MinChange")
	-- Clamped so a camera already outside the arc (e.g. after switching mode
	-- mid-flight) still gets a target inside it.
	local lowEnd = math.min(a - min, limit)     -- [-limit, lowEnd]
	local highStart = math.max(a + min, -limit) -- [highStart, limit]
	local lowLength = math.max(0, lowEnd + limit)
	local highLength = math.max(0, limit - highStart)
	if lowLength + highLength <= 0 then
		-- Minimum change too big to fit: swing to the far edge instead.
		return a >= 0 and -limit or limit
	end
	local r = math.random() * (lowLength + highLength)
	if r < lowLength then
		return -limit + r
	end
	return highStart + (r - lowLength)
end

local function RandomPitchTarget()
	local down, up = OrbitSetting("PitchDown"), OrbitSetting("PitchUp")
	return -down + math.random() * (up + down)
end

local function PlanNextSweep()
	local mode = OrbitSetting("Mode")
	ns.orbit.spin = false
	-- The tele camera's spin, not yet started this cast: it starts with this
	-- move, even from in front (say, sitting by a fire as you cast).
	local teleSwing = ARC_CENTER[orbitPrefix] and ns.IsTele() and ns.DepartTimeLeft() ~= nil and not ns.orbit.teleSpun
	if mode == "back" then
		-- Angles are worked relative to the swing's centre (in front for cozy).
		local arc = OrbitSetting("BackArc")
		local center = ArcCenter(orbitPrefix)
		local relative = WrapAngle(ns.orbit.angle - center)
		local target
		if ARC_CENTER[orbitPrefix] and (math.abs(relative) > 2 * arc or teleSwing) then
			-- Cozy, swinging round from far off: stop short at the near edge of the
			-- sway, so it can flow on the same way across the centre.
			-- (From straight behind, either way round is as short: pick one.)
			if math.abs(math.abs(relative) - 180) < 1 then
				ns.orbit.cozyDir = math.random() < 0.5 and 1 or -1
			else
				ns.orbit.cozyDir = relative < 0 and 1 or -1
			end
			ns.orbit.cozyFollow = true
			target = -ns.orbit.cozyDir * arc * COZY_ARRIVE_EDGE -- one side of your front
		elseif ARC_CENTER[orbitPrefix] and ns.orbit.cozyFollow then
			-- ...and the first sway move carries on that way, across your front to
			-- the other side.
			ns.orbit.cozyFollow = false
			target = ns.orbit.cozyDir * arc * (0.6 + 0.4 * math.random())
		else
			target = PickBackTarget(arc, relative)
		end
		if TRAVEL_ORBIT[orbitPrefix] and arc > 0 then
			-- Travelling: favour angles near directly behind, so the camera mostly
			-- looks the way you're going.
			target = target * (0.4 + 0.6 * math.abs(target) / arc)
		end
		ns.orbit.yawDelta = WrapAngle(center + target - ns.orbit.angle)
		if teleSwing and math.abs(ns.orbit.yawDelta) < 1 then
			ns.orbit.yawDelta = ns.orbit.cozyDir -- (already there: the spin still needs a way to go)
		end
		local pitchTarget = PitchCenter() + RandomPitchTarget()
		if orbitPrefix == "runOrbit" then
			-- Auto-run: never below the lowest tilt (steering lowering included).
			pitchTarget = math.max(pitchTarget, -OrbitSetting("PitchFloor"))
		end
		ns.orbit.pitchDelta = pitchTarget - ns.orbit.pitch
	elseif mode == "random" then
		-- Uniform over the allowed arc (everything outside +-min of the current
		-- angle), then take the shorter way round.
		local min = OrbitSetting("MinChange")
		local delta = min + math.random() * (360 - 2 * min)
		if delta > 180 then
			delta = delta - 360
		end
		ns.orbit.yawDelta = delta
		ns.orbit.pitchDelta = RandomPitchTarget() - ns.orbit.pitch
	else
		ns.orbit.yawDelta = OrbitSetting("Right") and -OrbitSetting("Step") or OrbitSetting("Step")
		ns.orbit.pitchDelta = -ns.orbit.pitch -- level out if a random mode left it tilted
	end
	ns.orbit.ease = OrbitSetting("Ease")
	if mode == "back" or mode == "random" then
		ns.orbit.sweepTime = math.max(ORBIT_MIN_SWEEP_TIME, OrbitSetting("MoveTime"))
		if ARC_CENTER[orbitPrefix] and (math.abs(ns.orbit.yawDelta) > 2 * OrbitSetting("BackArc") or teleSwing) then
			-- The cozy camera's first swing round to face you is a long one: take
			-- it slowly, but get going quickly (a short ease-in).
			ns.orbit.sweepTime = math.max(ns.orbit.sweepTime, math.abs(ns.orbit.yawDelta) / COZY_TURN_SPEED)
			ns.orbit.ease = math.min(ns.orbit.ease, COZY_START_EASE)
			-- The tele camera: quicker, to be in front of you before you go, and it
			-- never eases out: it keeps spinning round you, faster and faster,
			-- until you're gone (ns.SpinSpeed).
			if teleSwing then
				ns.orbit.sweepTime = math.max(ORBIT_MIN_SWEEP_TIME, math.min(ns.orbit.sweepTime, ns.DepartTimeLeft()))
				ns.orbit.spin, ns.orbit.spinSpeed, ns.orbit.brakeT, ns.orbit.teleSpun = true, 0, 0, true
			end
		end
	else
		-- The larger move cruises at the configured speed; the other is scaled to
		-- finish at the same time. Distance = cruise * T * (1 - ease), solved for T.
		local largest = math.max(math.abs(ns.orbit.yawDelta), math.abs(ns.orbit.pitchDelta))
		ns.orbit.sweepTime = math.max(ORBIT_MIN_SWEEP_TIME,
			largest / (OrbitSetting("Speed") * (1 - OrbitSetting("Ease"))))
	end
end

-- Enter the pause phase. startT is where the pause clock starts: 0 for a full
-- pause, closer to taxiOrbitPause for a shorter one. Drift, if on, creeps on in
-- the direction of the last move; in the behind modes it eases to a stop before
-- the edge of the swing (see UpdateOrbit) rather than turning back there.
-- noDrift holds still (used while the takeoff swing is moving the camera).
local function BeginPause(startT, noDrift, forceDrift)
	ns.orbit.phase, ns.orbit.t, ns.orbit.pauseStart = "pause", startT, startT
	ns.orbit.pauseLen = nil -- (the setting's pause; a fly-by's hold sets its own)
	ns.orbit.spin = false
	ns.orbit.noDrift = noDrift or false
	ns.orbit.forceDrift = forceDrift or false
	if OrbitSetting("Mode") == "back" then
		-- Carry on gently the way the last move went. (Turning back at the
		-- swing limit would brake and reverse within a second: a visible jolt.
		-- Near the limit it eases to a stop instead; the next move heads back.)
		local lastPositive = ns.orbit.yawDelta >= 0
		if ns.orbit.yawDelta == 0 then
			lastPositive = math.random() < 0.5
		end
		ns.orbit.driftPositive = lastPositive
	else
		ns.orbit.driftPositive = ns.orbit.yawDelta >= 0
	end
end

local StopOrbitTilt -- defined with the death tilt below

local function StopOrbitMove()
	StopAxis(ns.yawAxis)
	StopOrbitTilt()
end

function ns.StopOrbitNow()
	StopOrbitMove()
	ns.orbit.level = 0
	-- (A fly-by or arrival under way is dropped with it: see ns.OrbitSpecial.)
	ns.orbit.special, ns.orbit.flyByWanted, ns.orbit.settleWanted = nil, false, false
	ns.orbit.flyBySide = nil
	ns.orbit.continuous, ns.orbit.contFade = false, nil
	ns.orbit.driftVel, ns.orbit.driftSmooth = 0, 0
end

local CenterCamera -- defined with the flight-start code below
-- (On ns too, for the quest cam in QuestCam.lua.)
function ns.CenterCamera(...) return CenterCamera(...) end

-- Standing still: no movement and not dragging the camera. Turning on the spot
-- with the mouse counts as active, so the orbit never fights the player.
-- Movement comes from the PLAYER_STARTED/STOPPED_MOVING events: this client
-- can return GetUnitSpeed as a "secret" value that addons may not compare.
ns.playerMoving = false

-- shortPause: walking, so pick up again quickly in case they need to move.
local function IsAdjustingCamera(now, shortPause)
	if IsMouseOnCamera() then
		lastCameraInput = now
		ns.lastCameraInputWhat = "mouse on the camera"
	end
	local pause = shortPause or ns.db.idleInputPause
	return now - lastCameraInput < pause
end

-- Feet moving or the camera being dragged right now. (The longer pause after
-- camera input is handled separately in UpdateOrbit.)
local function IsPlayerActive()
	return ns.playerMoving or IsMouseOnCamera()
end

-- Idle zoom: after standing still for the standing-still delay, the camera
-- slowly pulls back, then (optionally) keeps drifting in and out to random
-- distances. The game's own zoom is too quick even at its slowest, so the
-- addon moves it in tiny steps every frame, along the same ease-in/out curve
-- as the camera rotation. Moving zooms straight back to the player's distance.
-- Optionally the max zoom distance is raised meanwhile; on the way back it's
-- only restored once the camera is inside the old limit again, or the game
-- would clamp the zoom with a visible snap.
local ZOOM_MAX_CVARS = { values = { cameraDistanceMaxZoomFactor = "2.6" } }
local ZOOM_MIN_CHANGE = 1           -- yards: smallest random zoom worth making
local ZOOM_CLOSEST = 1              -- yards: never zoom in past this

-- The active zoom profile's value: idleZoom* standing still, taxiZoom* flying,
-- walkZoom* while RP walking.
local ZOOM_PREFIX = { taxi = "taxiZoom", walk = "walkZoom", run = "runZoom", idle = "idleZoom",
	cozy = "cozyZoom", vista = "vistaZoom", fish = "fishZoom", tele = "teleZoom" }
local function ZoomSetting(key)
	local value = ns.db[ZOOM_PREFIX[idleZoom.context] .. key]
	if Indoors() then
		if key == "Distance" then
			return math.min(value, ns.db.indoorZoomOut)
		elseif key == "PastMax" then
			return false
		end
	end
	return value
end
-- The pause before the next random zoom: Pause, give or take up to PauseVary.
-- The roll is kept as a fraction so a profile switch mid-pause rescales it.
local function RollZoomPause()
	idleZoom.pauseRoll = math.random() * 2 - 1
end
local function ZoomPause()
	return math.max(0, ZoomSetting("Pause") + (idleZoom.pauseRoll or 0) * (ZoomSetting("PauseVary") or 0))
end
local zoomWasIndoors = false
local INDOOR_ZOOM_IN_TIME = 3 -- seconds to glide in when you walk indoors pulled back

-- The game doesn't move the camera exactly the distance asked of
-- CameraZoomIn/Out (it can go several times further), so the zoom isn't sent
-- as open-loop steps. Each move is a planned path (from, delta, eased over its
-- duration); every frame the real distance is read with GetCameraZoom() and a
-- small correction sent toward where the path says the camera should be. Any
-- over- or under-shoot is corrected on the next frame, so it follows the plan
-- whatever the game's step size.
local ZOOM_GAIN = 0.15        -- share of the remaining error corrected per frame
local ZOOM_DEADBAND = 0.05    -- yards: close enough, send nothing
local ZOOM_RESTORE_TIME = 1.5 -- seconds to glide back when the player moves
local ZOOM_RESTORE_DONE = 0.2 -- yards: back where the player had it
local ZOOM_RESTORE_GIVE_UP = 3 -- extra seconds before calling a restore finished anyway

-- Share (0-1) of a move's distance covered at time t, for the ease-in/out
-- speed curve in EaseShape: half-cosine ramps of length ease*T either end.
local function EaseProgress(t, T, ease)
	if t <= 0 then return 0 end
	if t >= T then return 1 end
	local R = ease * T
	if R <= 0 then return t / T end
	local total = T - R
	local function ramp(u) return u / 2 - R / (2 * math.pi) * math.sin(math.pi * u / R) end
	local covered
	if t < R then
		covered = ramp(t)
	elseif t <= T - R then
		covered = R / 2 + (t - R)
	else
		covered = total - ramp(T - t)
	end
	return covered / total
end

local function PlanPath(target, duration, ease, phase)
	idleZoom.from = GetCameraZoom()
	idleZoom.delta = math.max(ZOOM_CLOSEST, target) - idleZoom.from
	idleZoom.duration, idleZoom.ease = math.max(0.5, duration), ease
	idleZoom.phase, idleZoom.t = phase, 0
end

-- Landing (taxiLandZoom): glide back to the distance you had at takeoff,
-- undoing the flight's slow zoom. Zooming yourself on the way counts as your
-- choice: the distance then stays where you put it (see OnPlayerZoom).
-- (Kept on ns: this file is at Lua's limit of 200 locals.)

-- Your own zoom distance: the slow zoom's starting point while it's running
-- (or gliding back), the camera's otherwise.
function ns.PlayerZoom()
	if (idleZoom.active or idleZoom.restoring) and idleZoom.saved then
		return idleZoom.saved
	end
	return GetCameraZoom and GetCameraZoom()
end

-- Glides back to distance over 2 seconds.
function ns.ZoomBackTo(distance, seconds)
	if not GetCameraZoom or math.abs(GetCameraZoom() - distance) < ZOOM_RESTORE_DONE then
		return
	end
	idleZoom.active = false
	idleZoom.saved, idleZoom.restoring = distance, true
	PlanPath(distance, seconds or 2, 0.5, "restore")
end

local function PlanZoom(target)
	PlanPath(target, ZoomSetting("Time"), ZoomSetting("Ease"), "move")
end

-- The distance the zoom works around: your own, or for the cozy camera its
-- close-up distance (if you're further out than that).
local function ZoomBase()
	if idleZoom.context == "cozy" then
		return math.min(idleZoom.saved, ns.db.cozyZoomClose)
	end
	return idleZoom.saved
end

-- Steering a lot while auto-running (steeringNow, set by the turn handling):
-- zoom closer.
local STEER_ZOOM_CLOSER = 1.5 -- yards closer than your own distance
local STEER_ZOOM_TIME = 3     -- seconds to glide in
local CALM_TURN_ZOOM = 5      -- seconds without turning before the travel zoom opens up

local function PlanRandomZoom()
	local current = GetCameraZoom()
	local base = ZoomBase()
	local low = base - ZoomSetting("In")
	local high = base + ZoomSetting("Distance")
	if (idleZoom.context == "run" or idleZoom.context == "walk") and steeringNow then
		high = math.min(high, base) -- steering a lot: stay close for control
	end
	local target = current
	for _ = 1, 8 do -- a few tries for a change big enough to notice
		target = low + math.random() * (high - low)
		if math.abs(target - current) >= ZOOM_MIN_CHANGE then
			break
		end
	end
	PlanZoom(target)
end

-- Nudge the real camera distance toward `desired`.
local function CorrectZoomToward(desired)
	local err = desired - GetCameraZoom()
	if math.abs(err) > ZOOM_DEADBAND then
		CallCameraFunction(err > 0 and "CameraZoomOut" or "CameraZoomIn", math.abs(err) * ZOOM_GAIN)
	end
	return err
end

-- Death camera tilt and zoom: raises the camera to look down on your body (by
-- deathLevel degrees, from wherever it was) and pulls back deathZoom yards, then
-- lowers it by as much again and returns to your distance once you release or
-- come back. tilt.amount is how far it's raised so far. Each change of target
-- is one eased move, tilt and zoom together. There's no reading the camera's
-- angle, so the tilt is counted; the zoom follows the real distance (see
-- CorrectZoomToward) and stops if you zoom yourself.
-- The game won't turn and tilt the camera at once (a tilt holds the turn), so
-- the orbit waits for the rise: ns.orbit.deathRisen says it's done.
-- The tilt doesn't use MoveAxis: small, changing speed multipliers on the
-- "view up" command come out far too fast. Instead the tilt speed setting
-- itself is set and "view up" (or down) sent at the normal rate. To ease in
-- and out (a sudden start shows as a snap) the setting is stepped along the
-- usual ease curve: the move is sent once and the setting changed as it goes
-- (re-sending it showed as a snap). It stops once it has covered the distance;
-- your setting then comes back.
local DEATH_TILT_TIME = 3 -- seconds for the full tilt, up or down
local TILT_SPEED_CVAR = "cameraPitchMoveSpeed"
local TILT_EASE = 0.35     -- share of the tilt spent speeding up (and again slowing down)
local TILT_STEP = 0.1      -- seconds between speed changes, at most
local TILT_MIN_SPEED = 1   -- degrees per second: the slowest step sent

local TILT_RESTORE_DELAY = 0.3 -- seconds after stopping before your tilt speed comes back

-- /cine deathtest, and real deaths after /cine debug death, print what the
-- death camera does and when (seconds since you died).
function ns.DeathTestLog(text)
	if GetTime() < (ns.deathTestUntil or 0) or ns.deathDebug then
		ns.Print(("%.2fs %s"):format(GetTime() - (ns.orbit.deadSince or GetTime()), text))
	end
end

local function StopDeathTilt()
	if ns.orbit.tilting then
		ns.DeathTestLog("tilt stopped")
	end
	StopAxis(ns.pitchAxis)
	ns.orbit.tilting = false
	-- (Put back a moment later, so the end of the tilt can't run at full speed.)
	C_Timer.After(TILT_RESTORE_DELAY, function()
		if not ns.orbit.tilting then
			ns.RestoreCVar(TILT_SPEED_CVAR)
		end
	end)
end

local function StartDeathTilt(delta, T)
	StopDeathTilt()
	ns.SaveCVar(TILT_SPEED_CVAR)
	ns.orbit.tilting = true
	ns.DeathTestLog(("tilt %s %.0f° over %.1fs (zoom %.1f, combat %s, your tilt speed %s)"):format(
		delta > 0 and "up" or "down", math.abs(delta), T, GetCameraZoom and GetCameraZoom() or -1,
		tostring(InCombatLockdown()), tostring(ns.db.savedCVars[TILT_SPEED_CVAR])))
end

-- Send the tilt at this speed (degrees per second), if it's changed enough.
-- live: the move goes out once, and after that only the speed setting changes
-- (every frame it changes by more than TILT_LIVE_CHANGE), so there are no
-- restarts to hitch on. (The death tilt; its start snapped with restarts.)
local TILT_LIVE_CHANGE = 0.02
local function SendTiltSpeed(tilt, speed, positive, live)
	local now = GetTime()
	if live and tilt.sent then
		if math.abs(speed - tilt.sent) > tilt.sent * TILT_LIVE_CHANGE then
			SetCVar(TILT_SPEED_CVAR, ("%.2f"):format(speed))
			tilt.sent = speed
		end
		return
	end
	if tilt.sent and (now - tilt.sentAt < TILT_STEP or math.abs(speed - tilt.sent) <= tilt.sent * 0.1) then
		return
	end
	SetCVar(TILT_SPEED_CVAR, ("%.2f"):format(speed))
	if not tilt.sent and math.abs((tonumber(GetCVar(TILT_SPEED_CVAR)) or 0) - speed) > 0.1 then
		ns.DeathTestLog(("tilt speed didn't take: asked %.2f, got %s"):format(speed,
			tostring(GetCVar(TILT_SPEED_CVAR))))
	end
	local axis = ns.pitchAxis
	axis.positive, axis.moving, axis.speed, axis.lastStart = positive, true, 1, now
	CallCameraFunction(positive and axis.positiveStart or axis.negativeStart, 1)
	tilt.sent, tilt.sentAt = speed, now
end

-- The sway's tilt stops (unless the death camera's tilt has the pitch: see
-- UpdateDeathTilt). The sway tilts with MoveAxis; driving it through the tilt
-- speed setting, like the death tilt, made the swaying cameras snap.
function StopOrbitTilt()
	if not ns.orbit.tilting then
		StopAxis(ns.pitchAxis)
	end
end

local DEATH_ZOOM_GIVE_UP = 2 -- extra seconds before a zoom that can't get there stops
local deathTilt = { amount = 0, from = 0, target = 0, t = 0, T = 0, on = false }
-- You moved the camera yourself (while dead, or as it goes back after): the
-- death camera hands it over where it is, and makes no more moves (none back
-- either) until your next death.
function ns.AbandonDeathCamera()
	local tilt = deathTilt
	if tilt.abandoned then
		return
	end
	tilt.abandoned = true
	if ns.orbit.tilting then
		StopDeathTilt()
	end
	tilt.amount, tilt.from, tilt.target = 0, 0, 0 -- nothing to put back
	tilt.zoomTo, tilt.zoomSaved = nil, nil
	ns.DeathTestLog("you moved the camera: it's yours now")
end

-- Still doing something with the camera: dead, or on the way back after.
function ns.DeathCameraBusy()
	local tilt = deathTilt
	return not tilt.abandoned and (tilt.on or tilt.amount ~= tilt.target or tilt.zoomTo ~= nil)
end

function ns.UpdateDeathTilt(on, elapsed)
	local tilt = deathTilt
	if tilt.abandoned then
		ns.orbit.deathRisen = false
		if not on then
			tilt.abandoned, tilt.on = false, false -- released or back: ready for next time
		end
		return
	end
	ns.orbit.deathRisen = on and tilt.on and tilt.amount == tilt.target
	if on ~= tilt.on then
		tilt.on, tilt.t = on, 0
		tilt.from, tilt.target = tilt.amount, on and ns.db.deathLevel or 0
		local share = math.abs(tilt.target - tilt.amount) / math.max(1, ns.db.deathLevel, tilt.amount)
		tilt.T = DEATH_TILT_TIME * math.max(0.3, share)
		tilt.sent = nil
		if tilt.target ~= tilt.amount then
			StartDeathTilt(tilt.target - tilt.amount, tilt.T)
		elseif ns.orbit.tilting then
			StopDeathTilt()
		end
		local zoom = GetCameraZoom and GetCameraZoom()
		if on and zoom and ns.db.deathZoom > 0 then
			tilt.zoomSaved = tilt.zoomSaved or zoom -- (still on its way back: keep the first)
			tilt.zoomFrom, tilt.zoomTo = zoom, tilt.zoomSaved + ns.db.deathZoom
		elseif not on and zoom and tilt.zoomSaved then
			tilt.zoomFrom, tilt.zoomTo = zoom, tilt.zoomSaved
		end
	end
	if tilt.on or tilt.amount ~= tilt.target or tilt.zoomTo then
		tilt.t = tilt.t + elapsed
	end
	if tilt.zoomTo then
		local desired = tilt.zoomFrom + (tilt.zoomTo - tilt.zoomFrom) * EaseProgress(tilt.t, tilt.T, 0.5)
		local err = CorrectZoomToward(desired)
		if tilt.t >= tilt.T and (math.abs(err) < ZOOM_RESTORE_DONE or tilt.t >= tilt.T + DEATH_ZOOM_GIVE_UP) then
			tilt.zoomTo = nil
			if not tilt.on then
				tilt.zoomSaved = nil
			end
		end
	end
	if tilt.amount == tilt.target then
		return
	end
	local delta = tilt.target - tilt.from
	if math.abs(tilt.amount - tilt.from) >= math.abs(delta) or tilt.t >= tilt.T + 1 then
		tilt.amount = tilt.target
		StopDeathTilt()
		-- Stopping the tilt can stop the turn with it, and the orbit won't
		-- re-send a turn whose speed hasn't changed: make it send it again.
		if ns.yawAxis.moving then
			ns.yawAxis.speed = 0
		end
		return
	end
	-- Eased: cruise = distance / (T * (1 - ease)), shaped by the ease curve.
	local cruise = math.abs(delta) / (tilt.T * (1 - TILT_EASE))
	SendTiltSpeed(tilt, math.max(TILT_MIN_SPEED, cruise * EaseShape(tilt.t, tilt.T, TILT_EASE)), delta > 0, true)
	-- How far it's come, at the speed actually sent (for the stop, and any move back).
	tilt.amount = tilt.amount + (delta > 0 and tilt.sent or -tilt.sent) * elapsed
end

-- Dead (not yet released, or /cine deathtest) with the death camera on.
function ns.IsDead()
	return (ns.Flag(UnitIsDead("player")) and not ns.Flag(UnitIsGhost("player")))
		or GetTime() < (ns.deathTestUntil or 0)
end

-- Dead with the death camera to watch: cinematic mode stays on (popups like
-- the release button aren't faded, so it's still there).
function ns.IsDeathCinematic()
	return ns.db.deathOrbit and ns.IsDead() and not ns.IsCameraOffHere("death")
end

-- Your own zooming: you've picked a distance, so the death camera leaves it.
function ns.CancelDeathZoom()
	deathTilt.zoomTo, deathTilt.zoomSaved = nil, nil
end

local function FinishRestore()
	idleZoom.restoring = false
	idleZoom.saved = nil
	-- The camera's back inside the old limit. Putting the limit back can still
	-- jolt the camera (a hair outside it gets pulled in at once), so on a
	-- flight it waits until you land, where the dismount moves the camera
	-- anyway (see UpdateTaxi).
	if not UnitOnTaxi("player") then
		ns.ApplyCVarSet(ZOOM_MAX_CVARS, false)
	end
end

local function StartIdleZoom()
	if idleZoom.restoring then
		idleZoom.restoring = false -- still heading back: keep the original distance
	else
		idleZoom.saved = GetCameraZoom and GetCameraZoom()
	end
	if not idleZoom.saved then
		return
	end
	if ZoomSetting("PastMax") then
		ns.ApplyCVarSet(ZOOM_MAX_CVARS, true)
	end
	idleZoom.active = true
	if idleZoom.context == "cozy" then
		-- Cozy: the first move comes in to the close-up, getting going quickly.
		PlanPath(ZoomBase(), COZY_ZOOM_START, COZY_ZOOM_EASE, "move")
	elseif idleZoom.context == "tele" then
		-- Tele: in to its close-up over the whole cast, getting going at once
		-- (a short ease in; it's still coming in as you go).
		PlanPath(math.min(idleZoom.saved, ns.db.teleZoomClose), ns.DepartCastLeft() or 10, 0.15, "move")
	else
		PlanZoom(idleZoom.saved + ZoomSetting("Distance")) -- the first move always pulls back
	end
	if idleZoom.context == "taxi" then
		ns.Log("zoom", ("flight zoom: %.1f -> %.1f yards%s, max factor %s"):format(idleZoom.saved,
			idleZoom.from + idleZoom.delta, Indoors() and " (indoors)" or "",
			tostring(GetCVar("cameraDistanceMaxZoomFactor"))))
	end
end

local function StepIdleZoom(elapsed)
	idleZoom.t = idleZoom.t + elapsed
	local T = idleZoom.duration
	local desired
	if idleZoom.phase == "brake" then
		-- Slowing from brakeV yards a second to a stop over T (see ns.BrakeIdleZoom).
		local t = math.min(idleZoom.t, T)
		desired = idleZoom.from + idleZoom.brakeV * (t / 2 + T / (2 * math.pi) * math.sin(math.pi * t / T))
	else
		desired = idleZoom.from + idleZoom.delta * EaseProgress(idleZoom.t, T, idleZoom.ease)
	end
	local err = CorrectZoomToward(desired)

	if idleZoom.phase == "restore" then
		if (idleZoom.t >= T and math.abs(err) < ZOOM_RESTORE_DONE) or idleZoom.t >= T + ZOOM_RESTORE_GIVE_UP then
			FinishRestore()
		end
	elseif idleZoom.phase == "move" or idleZoom.phase == "brake" then
		if idleZoom.t >= T then
			idleZoom.phase, idleZoom.t = ZoomSetting("Random") and "pause" or "hold", 0
			idleZoom.from, idleZoom.delta, idleZoom.duration = desired, 0, 1
			RollZoomPause()
		end
	elseif idleZoom.phase == "pause" and idleZoom.t >= ZoomPause() and not ns.FlyByTurning() then
		-- (No new zoom move while a fly-by is turning the camera: starting one
		-- mid-turn showed as snaps. A move already under way as it began was
		-- slowed to a stop, ns.BrakeIdleZoom: freezing it dead snapped too.)
		PlanRandomZoom()
	end
end

-- A fly-by or the arrival shot taking over: a zoom move under way slows to a
-- stop over `seconds` (from the speed it's going, so there's no jolt), then
-- pauses; the next move waits until the fly-by's over (see StepIdleZoom).
function ns.BrakeIdleZoom(seconds)
	if not (idleZoom.active and idleZoom.phase == "move") or idleZoom.t >= idleZoom.duration then
		return
	end
	local T, t, ease, h = idleZoom.duration, idleZoom.t, idleZoom.ease, 0.05
	local speed = idleZoom.delta * (EaseProgress(t + h, T, ease) - EaseProgress(math.max(0, t - h), T, ease))
		/ (t + h - math.max(0, t - h))
	idleZoom.from = idleZoom.from + idleZoom.delta * EaseProgress(t, T, ease)
	idleZoom.brakeV, idleZoom.duration, idleZoom.t, idleZoom.phase = speed, seconds, 0, "brake"
end

-- restore: glide back to the saved distance (moving, cinematic ending).
-- Otherwise (the player zoomed themselves) just let go. Either way the max zoom
-- distance goes back once the camera is inside the old limit.
local function EndIdleZoom(restore)
	if not idleZoom.active then
		return
	end
	idleZoom.active = false
	if restore and idleZoom.saved and GetCameraZoom then
		idleZoom.restoring = true
		-- (The tele zoom only ends early on a cancelled cast: back quickly then.)
		PlanPath(idleZoom.saved, idleZoom.context == "tele" and ns.db.teleZoomBackTime or ZOOM_RESTORE_TIME,
			0.5, "restore")
	else
		FinishRestore()
	end
end

-- For /cine debug turn.
function ns.GetTurnDebug()
	return {
		offset = turnOffset, glide = turnGlide, extra = yawExtra,
		followOff = TURN_FOLLOW_CVARS.active, smoothStyle = GetCVar("cameraSmoothStyle"),
		yawSpeed = GetCVar("cameraYawMoveSpeed"), keys = (turnKeys.left and "left " or "") ..
			(turnKeys.right and "right" or ""),
		axis = ns.yawAxis.moving and ((ns.yawAxis.positive and "left " or "right ") ..
			("%.2f"):format(ns.yawAxis.speed)) or "stopped",
	}
end

-- For /cine debug zoom.
function ns.GetZoomDebug()
	return idleZoom
end
function ns.GetLastCameraInput()
	return lastCameraInput
end

function CancelIdleZoom()
	EndIdleZoom(false)
	if idleZoom.restoring then
		FinishRestore() -- the player took over mid-restore
	end
end
-- The quest cam takes the zoom over: the slow zoom lets go where it is, but
-- a raised max distance stays until ns.RestoreZoomLimit. (Put back while the
-- camera's still past it, the game quietly moves its own zoom target in to the
-- limit, so a zoom counted from where the camera is goes too far.)
function ns.TakeOverZoom()
	idleZoom.active, idleZoom.restoring, idleZoom.saved = false, false, nil
end
function ns.RestoreZoomLimit()
	if not idleZoom.active and not idleZoom.restoring then
		ns.ApplyCVarSet(ZOOM_MAX_CVARS, false)
	end
end

-- Logout: no time to glide, so jump straight back and put everything back.
function ns.StopIdleZoomNow()
	local saved = idleZoom.saved
	idleZoom.active, idleZoom.restoring = false, false
	if saved and GetCameraZoom then
		local diff = GetCameraZoom() - saved
		if math.abs(diff) > 0.1 then
			CallCameraFunction(diff > 0 and "CameraZoomIn" or "CameraZoomOut", math.abs(diff))
		end
	end
	idleZoom.saved = nil
	ns.ApplyCVarSet(ZOOM_MAX_CVARS, false)
end

-- Runs when standing still (past the standing-still delay) or on a flight
-- (until the camera settles before landing). Once per standing-still spell or
-- flight; switching between the two starts afresh.
local function UpdateIdleZoom(cinematic, onTaxi, travel, now, elapsed)
	local still = not onTaxi and ns.stillSince ~= nil and now - ns.stillSince >= ns.db.idleOrbitDelay
	local context = onTaxi and "taxi" or travel or "idle"
	local allowed
	if onTaxi then
		allowed = ns.db.taxiZoom and ns.FlightCameraOn() and not ns.orbit.settling and not ns.orbit.zoomSettled
		if ns.FlightTakenOver() then
			-- You've moved the camera: the slow zoom lets go where it is (no
			-- glide back) and stays off for the rest of the flight.
			allowed = false
			if not ns.flight.takeoverLogged then
				ns.flight.takeoverLogged = true
				ns.Log("zoom", ("flight taken over by %s: the flight camera stands down"):format(
					tostring(ns.lastCameraInputWhat)))
			end
			if idleZoom.active and idleZoom.context == "taxi" then
				CancelIdleZoom()
			end
		end
	elseif travel == "cozy" then
		allowed = ns.db.cozyZoom -- (cozy already means still, or walking weapon-drawn)
	elseif travel == "tele" then
		allowed = ns.db.teleZoom
	elseif travel == "vista" then
		allowed = ns.db.vistaZoom -- (vista already means still)
	elseif travel == "fish" then
		allowed = ns.db.fishZoom
	elseif travel then
		allowed = ns.db[TRAVEL[travel].zoom]
		-- Zoomed yourself mid-walk: carry on from your new distance shortly after.
		if idleZoom.done and not idleZoom.active and now - lastCameraInput >= ns.db[TRAVEL[travel].pause] then
			idleZoom.done = false
		end
	else
		allowed = ns.db.idleZoom and still and not ns.IsCameraOffHere("idle")
	end
	local want = cinematic and allowed and not InCombatLockdown() and ns.CombatWaitOver(context, now)
	-- Walked indoors with the camera pulled back: glide in to the indoor limit.
	local indoors = Indoors()
	if indoors and not zoomWasIndoors and idleZoom.active and idleZoom.saved then
		local cap = idleZoom.saved + ZoomSetting("Distance")
		local heading = idleZoom.phase == "move" and (idleZoom.from + idleZoom.delta) or GetCameraZoom()
		if GetCameraZoom() > cap or heading > cap then
			PlanPath(math.min(cap, math.max(GetCameraZoom(), idleZoom.saved)), INDOOR_ZOOM_IN_TIME, 0.5, "move")
		end
	end
	zoomWasIndoors = indoors
	-- Started indoors (no going past the max there) and now out: raise the max
	-- now, or the zoom stops dead at your own limit. (Only ever raised mid-zoom:
	-- dropping it while pulled back would snap the camera in.)
	if idleZoom.active and idleZoom.context == context and not indoors and ZoomSetting("PastMax") then
		ns.ApplyCVarSet(ZOOM_MAX_CVARS, true)
	end
	if idleZoom.active and idleZoom.context ~= context then
		local footHandoff = FOOT_ZOOM[idleZoom.context] and FOOT_ZOOM[context]
		if want and footHandoff then
			-- Standing still <-> RP walk: keep zooming from where it is, with the new
			-- settings from here on (same base distance, no glide back).
			idleZoom.context, idleZoom.doneContext = context, context
			if ZoomSetting("PastMax") then
				ns.ApplyCVarSet(ZOOM_MAX_CVARS, true)
			end
			if context == "cozy" then
				-- Into the cozy camera: zoom in to its close-up as it swings round.
				PlanPath(ZoomBase(), COZY_ZOOM_START, COZY_ZOOM_EASE, "move")
			elseif context == "vista" or context == "fish" then
				-- Into the vista camera (say, /stare after /sit): ease back out from
				-- wherever it was (a cozy close-up) to the vista's pull-back.
				PlanZoom(idleZoom.saved + ZoomSetting("Distance"))
			end
			if idleZoom.phase == "hold" and ZoomSetting("Random") then
				idleZoom.phase, idleZoom.t = "pause", 0
				RollZoomPause()
			elseif idleZoom.phase == "pause" and not ZoomSetting("Random") then
				idleZoom.phase = "hold"
			end
		else
			EndIdleZoom(true) -- took off or landed mid-zoom
		end
	end
	if idleZoom.doneContext and idleZoom.doneContext ~= context then
		idleZoom.done = false
	end
	if want and not idleZoom.active and not idleZoom.done then
		idleZoom.context = context -- picks the settings profile before starting
		StartIdleZoom()
		idleZoom.done, idleZoom.doneContext = true, context
	elseif not want then
		EndIdleZoom(true)
		-- Ready for the next standing-still spell / flight.
		if (context == "idle" and not still) then
			idleZoom.done = false
		end
	end
	-- Auto-running or RP walking and steering a lot: you want control, so pull in a little
	-- (and the random zoom stays inside your distance until you settle down).
	if (context == "run" or context == "walk") and idleZoom.active and idleZoom.saved then
		if steeringNow and not idleZoom.steerClose then
			idleZoom.steerClose = true
			PlanPath(math.max(ZOOM_CLOSEST, idleZoom.saved - STEER_ZOOM_CLOSER), STEER_ZOOM_TIME, 0.5, "move")
		elseif not steeringNow then
			idleZoom.steerClose = false
		end
		-- Going straight for a while: open up, gliding out to the full distance
		-- (re-armed by the next turn).
		if now - lastAnyTurnAt < CALM_TURN_ZOOM then
			idleZoom.calmOut = false
		elseif not idleZoom.calmOut and not steeringNow then
			idleZoom.calmOut = true
			PlanPath(idleZoom.saved + ZoomSetting("Distance"), ZoomSetting("Time"), ZoomSetting("Ease"), "move")
		end
	end
	if idleZoom.active or idleZoom.restoring then
		StepIdleZoom(elapsed)
	end
end

-- RP walk / auto-run turn handling, called every frame from UpdateOrbit.
-- Sets yawExtra (the speed added to the camera's yaw) for the orbit to use.
local function UpdateTurnFollow(now, elapsed, travel, T, cinematic, turning, turned)
	-- Steering a lot (several turns started in quick succession): note each
	-- turn's start, keeping only the recent ones.
	if turning and not wasTurningAny then
		turnStarts[#turnStarts + 1] = now
	end
	wasTurningAny = turning
	while turnStarts[1] and now - turnStarts[1] > TURN_BURST_WINDOW do
		table.remove(turnStarts, 1)
	end
	local steering = #turnStarts >= TURN_BURST_COUNT
	steeringNow = steering -- (the auto-run zoom pulls in while you steer a lot)

	-- RP walk turn follow: while you turn, the camera is turned back by the
	-- same amount on top of whatever the sway is doing, so it carries on
	-- unaffected. Once you stop turning, the whole view glides gently round to
	-- your new facing (the sway still going). turnOffset is how far the view is
	-- from your facing (degrees, left positive); yawExtra is the speed added.
	yawExtra = 0
	local testing = now < (ns.turnTestUntil or 0) -- /cine turnhold
	local follow = ((travel and cinematic and ns.db[T.swing]) or testing) and not IsMouseOnCamera()
		and not InCombatLockdown()
	-- Only arm once you've stopped turning for a moment: catching a turn that's
	-- already under way (auto-run started mid-turn, say) would stop the camera
	-- dead mid-swing. That turn just carries on as normal.
	if not follow then
		followArmed = false
	elseif not followArmed and (testing or now - lastAnyTurnAt >= TRAVEL_START_AFTER_TURN) then
		followArmed = true
	end
	follow = follow and followArmed
	if travelRecenter and now < recenterUntil then
		follow = false -- lining up behind you: camera follow already handles turns
	end
	local glideDelay = T and ns.db[T.delay] or ns.db.walkGlideDelay
	if steering then
		-- Actively steering: get back behind you sooner than usual.
		glideDelay = math.min(glideDelay, STEER_GLIDE_DELAY)
	end
	if follow then
		-- Your turn speed, smoothed: the raw per-frame figure jitters with frame
		-- times, and every change restarts the camera turn (a small hitch).
		-- Real changes (starting, stopping, reversing a turn) are followed at
		-- once, so the view never lags into turning with you; only the small
		-- frame-to-frame jitter is smoothed.
		local measured = elapsed > 0 and turned / elapsed or 0
		local diff = measured - turnRate
		if math.abs(diff) > math.max(TURN_JUMP, math.abs(turnRate) * 0.15) then
			turnRate = measured
		else
			turnRate = turnRate + diff * math.min(1, elapsed / TURN_SMOOTH)
		end
		if measured == 0 and math.abs(turnRate) < 1 then
			turnRate = 0
		end
		if turning then
			turnGlide = 0 -- hold the view until the turn ends
			lastTurnAt = now
		elseif turnGlide == 0 and now - lastTurnAt < glideDelay then
			-- Just stopped turning: hold a moment longer in case of more adjustments.
		elseif math.abs(turnOffset) > TURN_FOLLOW_DONE or turnGlide ~= 0 then
			-- Glide: lazily (proportional to how far off it is), capped, and with
			-- the speed itself eased so it never jerks.
			local glide = T and T.glide
			local lazy, top, accel = glide and glide[1] or TURN_FOLLOW_TIME,
				glide and glide[2] or TURN_FOLLOW_MAX, glide and glide[3] or TURN_FOLLOW_ACCEL
			if steering then -- ...and catch up quicker
				lazy, top, accel = lazy / STEER_GLIDE_BOOST, top * STEER_GLIDE_BOOST, accel * STEER_GLIDE_BOOST
			end
			if T and T.sizeBoost then
				-- Auto-run: the bigger the turn, the quicker it swings round with you
				-- (a corner, not a nudge).
				local size = math.abs(turnOffset)
				local boost
				if size < TURN_SIZE_SMALL then
					-- Small turns (and the last few degrees of any glide): gentler.
					boost = TURN_SIZE_GENTLE + (1 - TURN_SIZE_GENTLE) * size / TURN_SIZE_SMALL
				else
					boost = 1 + math.min(TURN_SIZE_BOOST_MAX, (size - TURN_SIZE_SMALL) / TURN_SIZE_PER)
				end
				lazy, top, accel = lazy / boost, top * boost, accel * boost
			end
			local target = -turnOffset / lazy
			target = math.max(-top, math.min(top, target))
			-- Always leave room to stop: no faster than it can brake from in the
			-- distance left (a big, fast turn would otherwise slide past behind
			-- you and swing back).
			local brakeLimit = math.sqrt(2 * accel * math.abs(turnOffset)) * GLIDE_BRAKE_MARGIN
			target = math.max(-brakeLimit, math.min(brakeLimit, target))
			local step = accel * elapsed
			turnGlide = turnGlide + math.max(-step, math.min(step, target - turnGlide))
		end
		-- The view's offset from your facing is exactly what's been sent to the
		-- camera: the counter-turn (holding it against your turn) plus the glide.
		local rate = -turnRate + turnGlide
		turnOffset = turnOffset + rate * elapsed
		-- Work from where you actually ended up facing: a full spin leaves the
		-- view where it started, so the offset wraps to the short way round
		-- (-180..180) instead of piling up whole turns.
		turnOffset = (turnOffset + 180) % 360 - 180
		if turnRate == 0 and math.abs(turnOffset) <= TURN_FOLLOW_DONE and math.abs(turnGlide) < 2 then
			turnOffset, turnGlide = 0, 0
		elseif turnOffset ~= 0 or rate ~= 0 then
			-- (Flipped: on the camera's yaw axis, "left" turns the view the same way
			-- as turning your character right, so the offset maps on negated.)
			yawExtra = -rate
		end
	elseif turnOffset ~= 0 or turnRate ~= 0 then
		-- Interrupted (stopped walking, steering with the mouse, combat): leave
		-- the view where it is and hand back.
		turnOffset, turnGlide, turnRate = 0, 0, 0
		StopAxis(ns.yawAxis)
	end
	-- The game's own camera follow is off while the view is away from your
	-- facing, so the two don't fight.
	if turnOffset == 0 and TURN_FOLLOW_CVARS.active and ns.RECENTER_CVARS.active then
		-- A line-up glide has taken over camera follow (and will put yours back).
		TURN_FOLLOW_CVARS.active = false
	else
		ns.ApplyCVarSet(TURN_FOLLOW_CVARS, turnOffset ~= 0)
	end
end

-- The "Print the camera mode to chat" option: one line each time the mode
-- changes (nil: none of them).
local reportedMode = false -- (false: nothing printed yet)
function ns.ReportCameraMode(mode)
	if mode == reportedMode then
		return
	end
	reportedMode = mode
	local text = "camera mode: " .. (mode and (mode .. " camera") or "none")
	if ns.db.debugCameraMode then
		ns.Print(text) -- (which logs it too)
	else
		ns.Log("state", text)
	end
end

-- Turning the option on prints the current mode straight away.
function ns.ResetCameraModeReport()
	reportedMode = false
end

function ns.UpdateOrbit(cinematic, elapsed)
	local onTaxi = UnitOnTaxi("player")
	local active = IsPlayerActive()
	local now = GetTime()
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		lastCombatAt = now
	end
	WeaponCozy() -- follow the weapon every frame, moving or not
	-- An NPC window open (auction house, vendor, quest giver...): you're busy,
	-- not idling, so the standing-still timer waits too.
	local atNPC = ns.db.cameraPauseAtNPCs and ns.NPCWindowOpen and ns.NPCWindowOpen()
	-- Same for a menu or game window (options, spellbook...).
	local inMenu = ns.db.cameraPauseInMenus and ns.MenuWindowOpen and ns.MenuWindowOpen()
	-- Casting (crafting, say) is busy too. (The cozy camera keeps going: cooking
	-- at a campfire is still cozy.)
	local casting = ns.db.cameraPauseCasting
		and (ns.Flag(UnitCastingInfo("player")) or ns.Flag(UnitChannelInfo("player")))
		and not ns.IsFishingEvent() and not ns.IsDepartEvent()
	if onTaxi or active or atNPC or inMenu or (casting and not ns.IsCozy()) then
		ns.stillSince = nil
	elseif not ns.stillSince then
		-- Stopping from the RP walk or auto-run camera goes straight into the
		-- standing-still camera: its timer counts as already run (for the tint,
		-- tooltips and music too), so there's no gap between the two. Those
		-- only run on auto-walk and auto-run; moving by hand last means the
		-- timer starts afresh (walkHandoff is cleared as you do).
		ns.stillSince = walkHandoff and (now - ns.db.idleOrbitDelay) or now
		walkHandoff = false
	end
	-- Moving ends an emote.
	if ns.playerMoving or onTaxi then
		emoteEvent = nil
		ns.manualCam = nil -- (and a camera started from a key binding)
	end
	-- An event (Events page) for the cozy, vista or AFK camera: no waiting; the
	-- AFK camera's timer counts as run, for the tint, tooltips and music too.
	local vista = ns.IsVista()
	local fish = ns.IsFish()
	local cozy = ns.IsCozy()
	local tele = cozy and ns.IsTele()
	if not cozy then
		cozySessionStarted = false -- the next cozy spell swings round afresh
	end
	if not tele then
		ns.orbit.teleSpun = false -- the next cast spins afresh
	end
	local afk = ns.IsEventAFK()
	if ns.stillSince and (cozy or vista or fish or afk) and now - ns.stillSince < ns.db.idleOrbitDelay then
		ns.stillSince = now - ns.db.idleOrbitDelay
	end
	local idle = ns.db.idleOrbit and ns.stillSince ~= nil and now - ns.stillSince >= ns.db.idleOrbitDelay
		and not ns.IsCameraOffHere("idle")
	-- Death camera: dead (not yet released), the camera turns slowly round your
	-- body. Cinematic mode is off while you're dead (the UI comes back for the
	-- release button), so this runs without it, and in combat too.
	local dead = ns.IsDead()
	ns.orbit.deadSince = dead and (ns.orbit.deadSince or now) or nil
	local deathCam = dead and ns.db.enabled and now - ns.orbit.deadSince >= ns.db.deathOrbitDelay
		and ns.IsDeathCinematic()
	-- The game's camera follow is off meanwhile, so it can't pull the view back.
	-- It goes off as you die, not as the tilt starts: switched off then, while
	-- it was still easing the view after your fall, it jolted the tilt's start.
	local followOff = (dead and ns.db.enabled and ns.IsDeathCinematic()) or false
	if followOff ~= (ns.DEATH_CVARS.active or false) then
		ns.DeathTestLog(followOff and "camera follow off" or "camera follow back on")
		-- The death song starts as you die too (starting music can hitch a frame:
		-- better then than as the tilt starts).
		if ns.SetDeathSong then ns.SetDeathSong(followOff) end
	end
	ns.ApplyCVarSet(ns.DEATH_CVARS, followOff)
	ns.UpdateDeathTilt(deathCam, elapsed)
	-- RP walk camera: only while auto-walking (auto-run in walk mode; walking by
	-- hand cancels the cameras). Stop and stand, and it's the standing-still
	-- camera again.
	-- Auto-running (not walking) gets the auto-run camera, set up the same way.
	local walking = not onTaxi and ns.IsRPWalking and ns.IsRPWalking()
	local autoRunning = not onTaxi and not walking and ns.IsAutoRunning and ns.IsAutoRunning()
	local travel = (walking and not ns.IsCameraOffHere("walk") and "walk")
		or (autoRunning and not ns.IsCameraOffHere("run") and "run") or nil
	if travel == "walk" and ns.IsCozy() then
		travel = nil -- weapon drawn while walking: the cozy camera in front instead
	end
	local T = travel and TRAVEL[travel]
	do -- (logged always; printed with /cine debug modes)
		ns.ReportCameraMode((deathCam and "death") or (cinematic and ((onTaxi and ns.FlightCameraOn() and "flight")
			or (travel == "walk" and "RP walk") or (travel == "run" and "auto-run")
			or (vista and "vista") or (fish and "fish") or (tele and "tele") or (cozy and "cozy")
			or (ns.stillSince and now - ns.stillSince >= ns.db.idleOrbitDelay
				and not ns.IsCameraOffHere("idle") and "AFK"))) or nil)
	end
	if travel and cinematic then
		walkHandoff = true
	elseif onTaxi or (active and not travel and ns.playerMoving) then
		walkHandoff = false -- running or flying: the next stop starts the timer afresh
	end
	-- (Dead: the death camera has the zoom.)
	UpdateIdleZoom(cinematic and not dead, onTaxi, travel or (vista and "vista") or (fish and "fish") or (tele and "tele") or (cozy and "cozy") or nil, now, elapsed)

	local turning, turned = IsTurning(elapsed) -- every frame, to keep the last facing current
	if turning then
		lastAnyTurnAt = now
	end
	-- Turns while walking or auto-running: held, then glided round (see
	-- UpdateTurnFollow, kept separate to stay within Lua's upvalue limit).
	-- The cozy camera while walking (weapon drawn, walking or auto-walking)
	-- follows turns the way auto-run does.
	local followTravel, followT = travel, T
	if not travel and cozy and ns.playerMoving then
		followTravel, followT = "run", TRAVEL.run
	end
	UpdateTurnFollow(now, elapsed, followTravel, followT, cinematic, turning, turned)
	-- Started steering a lot while auto-running: lower the camera promptly
	-- (don't wait out a pause between sway moves).
	if steeringNow and not steerLowered and (orbitPrefix == "runOrbit" or orbitPrefix == "walkOrbit")
		and ns.orbit.phase == "pause" then
		ns.orbit.t = math.max(ns.orbit.t, OrbitSetting("Pause"))
	end
	steerLowered = steeringNow

	-- The player moving the camera pauses the orbit until that camera's input
	-- pause has passed since their last camera input, in flight and on foot.
	local adjusting = IsAdjustingCamera(now, (T and ns.db[T.pause]) or (onTaxi and ns.db.taxiInputPause)
		or (vista and ns.db.vistaInputPause) or (fish and ns.db.fishInputPause) or (cozy and ns.db.cozyInputPause) or nil)
	-- The death camera doesn't pause: camera input since you died (or while it
	-- goes back after) hands the camera to you for good (AbandonDeathCamera).
	if dead then
		ns.orbit.deathWatchFrom = ns.orbit.deathWatchFrom or now
	elseif not ns.DeathCameraBusy() then
		ns.orbit.deathWatchFrom = nil
	end
	if ns.orbit.deathWatchFrom and ns.GetLastCameraInput() > ns.orbit.deathWatchFrom then
		ns.AbandonDeathCamera()
	end
	if adjusting then
		ns.orbit.newReference = true
	end
	-- A fly-by (/cine flyby, its key, or a random one on a flight) has the
	-- camera to itself while it lasts.
	ns.UpdateAutoFlyBy(now, onTaxi, cinematic, adjusting)
	if ns.UpdateFlyBy(now, elapsed) then
		return
	end

	-- A travel camera (auto-run, RP walk) doesn't start mid-turn: its line-up
	-- would swing the camera round with you. It waits until you've stopped
	-- turning for a moment. (Once running, turns are held and glided instead.)
	local turnBlocksStart = travel and ns.orbit.level == 0 and now - lastAnyTurnAt < TRAVEL_START_AFTER_TURN
	local want = (deathCam and ns.orbit.deathRisen and not adjusting)
		or (cinematic and not adjusting and not InCombatLockdown() and not turnBlocksStart
		and ((onTaxi and ns.db.taxiOrbit and ns.FlightCameraOn() and not ns.orbit.settling) or (travel and ns.db[T.orbit])
			or (vista and ns.db.vistaOrbit)
			or (fish and ns.db.fishOrbit)
			or (cozy and (ns.db.cozyOrbit or tele))
			or (idle and not (ns.db.indoorNoSweep and Indoors()))))
	local prefix = deathCam and "deathOrbit" or onTaxi and "taxiOrbit" or ((travel and ns.db[T.orbit]) and T.orbit)
		or ((vista and ns.db.vistaOrbit) and "vistaOrbit")
		or ((fish and ns.db.fishOrbit) and "fishOrbit")
		or ((cozy and (ns.db.cozyOrbit or tele)) and "cozyOrbit") or "idleOrbit"
	-- Fresh out of a fight: this mode may wait a while before starting.
	-- (The tele camera turns with the cozy camera's rotation, but has its own wait.)
	want = want and ns.CombatWaitOver((tele and prefix == "cozyOrbit") and "tele" or prefix, now)
	local footHandoff = ns.orbit.level > 0 and orbitPrefix ~= prefix
		and FOOT_ORBIT[orbitPrefix] and FOOT_ORBIT[prefix]
	-- Into the vista camera with another one still moving (the standing-still
	-- sweep, cozy): ease that out first rather than stopping it dead.
	local easeOutFirst = want and (prefix == "vistaOrbit" or prefix == "fishOrbit") and ns.orbit.level > 0 and orbitPrefix ~= prefix
	if want and footHandoff then
		-- Standing still <-> RP walk: no stop and restart. The current move or
		-- pause plays out, and the next move follows on from where the camera
		-- is (for walking, that eases it back behind you).
		if prefix == "cozyOrbit" and tele and orbitPrefix ~= "cozyOrbit" then
			-- Into the tele camera from another (the AFK turn, a walk): their
			-- angles don't say where you're facing, so it starts afresh, as if
			-- from behind you.
			ns.orbit.angle, ns.orbit.pitch = 0, 0
		end
		orbitPrefix = prefix
		ns.orbit.level = 1
		ns.orbit.returnPending, ns.orbit.back = false, nil -- (another camera: no turn back)
		if prefix == "idleOrbit" then
			ns.orbit.randomRight = math.random() < 0.5 -- a fresh direction each time
		end
		if prefix == "cozyOrbit" then
			cozySessionStarted = true -- its next move swings round to face you
		end
		if prefix == "idleOrbit" or prefix == "cozyOrbit" then
			-- Stopped walking (or sat down): start moving almost straight away
			-- rather than after a full pause.
			if ns.orbit.phase == "pause" then
				local soon = OrbitSetting("Pause") - (prefix == "cozyOrbit" and 0 or HANDOFF_PAUSE)
				if ns.orbit.t < soon then
					ns.orbit.t = soon
					ns.orbit.pauseStart = math.min(ns.orbit.pauseStart or soon, soon)
				end
			else
				ns.orbit.shortPauseNext = true -- after the current move ends
			end
		else
			ns.orbit.shortPauseNext = false -- walking again before that move finished
		end
	elseif want and not easeOutFirst then
		if ns.orbit.level == 0 or orbitPrefix ~= prefix then
			-- Starting, or switching between flight and standing-still settings
			-- (taking off mid-rotation): begin afresh with the right profile.
			StopOrbitMove()
			orbitPrefix = prefix
			ns.orbit.returnPending, ns.orbit.back = false, nil -- (another camera: no turn back)
			if prefix == "idleOrbit" then
				ns.orbit.randomRight = math.random() < 0.5 -- a fresh direction each time
			end
			if prefix == "deathOrbit" then
				ns.orbit.randomRight = math.random() < 0.5 -- (used with deathOrbitRandomDir)
				ns.orbit.continuous = false -- its own slow turn, eased in from a standstill
				ns.DeathTestLog("turn started")
			elseif ns.OnRotationStart then
				ns.OnRotationStart(prefix)
			end
			-- Start moving straight away, except while the takeoff swing is
			-- still bringing the camera round behind the character.
			local wait = onTaxi and math.max(0, (ns.orbit.centerUntil or 0) - now) or 0
			if onTaxi and ns.orbit.newReference then
				-- Picking up mid-flight after you moved the camera: swing back
				-- behind you first, and sway from there.
				wait = math.max(wait, ns.RecenterFlight())
			end
			if LINEUP_ORBIT[prefix] then
				-- RP walk / auto-run / vista starting (or picking up after you moved
				-- the camera): glide round behind you first, then sway from there.
				-- Auto-running well clear of any fight: a quicker line-up, so the
				-- travel camera gets going sooner.
				if prefix == "runOrbit" and now - lastCombatAt > CALM_AFTER_COMBAT then
					CenterCamera(CALM_CENTER_TIME, CALM_CENTER_YAW, CALM_CENTER_PITCH, CALM_CENTER_RAMP)
					wait = CALM_CENTER_TIME
				elseif prefix == "vistaOrbit" or prefix == "fishOrbit" then
					-- Vista: an unhurried glide (8 sec at up to 30 deg/sec yaw and 20
					-- tilt, building up over 3 sec), long enough to come round from in
					-- front without being cut off mid-swing.
					CenterCamera(8, 30, 20, 3)
					wait = 8
				else
					CenterCamera(TRAVEL_CENTER_TIME, TRAVEL_CENTER_YAW, TRAVEL_CENTER_PITCH, TRAVEL_CENTER_RAMP)
					wait = TRAVEL_CENTER_TIME
				end
				travelRecenter = true
			end
			local mode = OrbitSetting("Mode")
			local opening = ns.db.idleOpeningDrift
			if wait == 0 and not onTaxi and opening > 0 and (mode == "random" or mode == "back") then
				-- Standing still in the random modes: open with a slow drift so the
				-- first (possibly big) move doesn't start from a dead stop.
				BeginPause(OrbitSetting("Pause") - opening, false, true)
			else
				BeginPause(OrbitSetting("Pause") - wait, wait > 0)
			end
			if not onTaxi or ns.orbit.newReference then -- (travel: "behind" once lined up)
				-- Wherever the camera was left counts as the starting point
				-- ("behind" for behind-only mode).
				ns.orbit.angle, ns.orbit.pitch = 0, 0
			end
			ns.orbit.newReference = false
			if ARC_CENTER[prefix] then
				if cozySessionStarted then
					-- Picking up again in the same cozy session (after you moved the
					-- camera): your view is the cozy view now, so sway around it
					-- rather than swinging round (and tilting) all over again.
					ns.orbit.angle, ns.orbit.pitch = ArcCenter(prefix), PitchCenter()
				else
					-- Cozy starting: the slow swing round to face you, straight away,
					-- to one side or the other.
					cozySessionStarted = true
					ns.orbit.phase, ns.orbit.t = "move", 0
					PlanNextSweep()
				end
			end
		end
		ns.orbit.level = 1 -- the sweep curve already eases in
	elseif ns.orbit.level > 0 then
		-- Quick stop when the player takes over, and when a flight lands (the
		-- standing-still timer then counts from touchdown, so nothing restarts
		-- until it runs out).
		local landed = orbitPrefix == "taxiOrbit" and (not onTaxi or ns.orbit.settling)
		-- (Released or brought back: the death camera stops promptly too.)
		local stopTime = (adjusting or landed or (active and not onTaxi) or orbitPrefix == "deathOrbit")
			and ORBIT_QUICK_STOP_TIME or ORBIT_STOP_TIME
		ns.orbit.level = ns.Approach(ns.orbit.level, 0, elapsed, stopTime)
	end
	-- The tele camera taking over from the cozy one (sat by a fire, then cast),
	-- or picking up after you moved the camera: no swing round, but its spin
	-- starts now.
	if tele and want and orbitPrefix == "cozyOrbit" and ns.orbit.level > 0 and not ns.orbit.teleSpun then
		-- Taking over from the AFK camera's continuous turn: no easing that out
		-- first (it would end in a pause, cancelling the spin).
		ns.orbit.continuous, ns.orbit.contFade = false, nil
		ns.orbit.phase, ns.orbit.t = "move", 0
		PlanNextSweep()
	end
	if ns.orbit.level <= 0 then
		-- A cancelled Hearthstone or teleport spin: turn back to where it started.
		if ns.StepSpinReturn(elapsed, adjusting) then
			return
		end
		if yawExtra ~= 0 then
			-- No sway, but a turn to hold or glide: drive the yaw for that alone.
			StopOrbitTilt()
			ns.orbit.level, ns.orbit.continuous, ns.orbit.driftVel, ns.orbit.driftSmooth = 0, false, 0, 0
			DriveYaw(0)
		else
			ns.StopOrbitNow()
		end
		return
	end

	ns.orbit.t = ns.orbit.t + elapsed

	-- Steady sweeps with no pause: one continuous turn at the turn speed, easing
	-- in once at the start (and out through the level when it stops), instead
	-- of separate sweeps that each slow to a halt. A move already under way
	-- (say, from the walk camera) finishes first.
	local continuous = OrbitSetting("Mode") == "sweep" and OrbitSetting("Pause") <= 0
	if not continuous and ns.orbit.continuous then
		-- Leaving a continuous turn (say, for the walk camera): ease it out
		-- first, then the new style's moves follow on.
		ns.orbit.contFade = (ns.orbit.contFade or CONTINUOUS_FADE) - elapsed
		if ns.orbit.contFade > 0 then
			local f = ns.orbit.contFade / CONTINUOUS_FADE
			local speed = ns.orbit.level * f * f * (3 - 2 * f) * ns.orbit.contSpeed
			DriveYaw(ns.orbit.contPositive and speed or -speed)
			ns.orbit.angle = WrapAngle(ns.orbit.angle + (ns.orbit.contPositive and speed or -speed) * elapsed)
			return
		end
		ns.orbit.continuous, ns.orbit.contFade = false, nil
		StopOrbitMove()
		BeginPause(0, false, OrbitSetting("Mode") == "back")
		return
	elseif continuous and (ns.orbit.continuous or ns.orbit.phase == "pause") then
		if not ns.orbit.continuous then
			ns.orbit.continuous, ns.orbit.contT, ns.orbit.contFade = true, 0, nil
		end
		ns.orbit.contT = ns.orbit.contT + elapsed
		-- (The death camera gets going almost at once, after its rise.)
		local ramp = math.min(1, ns.orbit.contT / (orbitPrefix == "deathOrbit" and 0.5 or CONTINUOUS_RAMP))
		ramp = ramp * ramp * (3 - 2 * ramp)
		local positive = not OrbitSetting("Right")
		ns.orbit.contSpeed, ns.orbit.contPositive = ramp * OrbitSetting("Speed"), positive
		local speed = ns.orbit.level * ns.orbit.contSpeed
		DriveYaw(positive and speed or -speed)
		ns.orbit.angle = WrapAngle(ns.orbit.angle + (positive and speed or -speed) * elapsed)
		ns.orbit.yawDelta = positive and 1 or -1 -- the direction, for the drift that follows
		return
	end

	-- Drift: a steady creep that never stops. It runs under the moves too, so a
	-- move starts and ends at drift speed instead of at a standstill, and it
	-- changes speed or direction gradually (over about DRIFT_RAMP seconds).
	-- (Not under the Hearthstone or teleport spin: it would wobble its speed past your front.)
	local spinning = ns.orbit.spin and ns.orbit.phase == "move"
	local driftOn = (OrbitSetting("Drift") or ns.orbit.forceDrift) and not ns.orbit.noDrift and not spinning
	local driftTarget = 0
	if driftOn then
		local positive
		if ns.orbit.phase == "move" then
			positive = ns.orbit.yawDelta > 0 -- carry on the way the move goes
		else
			positive = ns.orbit.driftPositive
		end
		driftTarget = OrbitSetting("DriftSpeed") * (positive and 1 or -1)
		-- (A fly-by goes out past the edge of the swing on purpose: the drift
		-- runs on under it.)
		if OrbitSetting("Mode") == "back" and ns.orbit.special ~= "flyOut" then
			-- Ease off over the last stretch before the edge of the swing (and
			-- stay put past it), so the drift never runs into the limit and turns.
			-- The easing is an S-curve, so the braking starts gently too.
			local arc = OrbitSetting("BackArc")
			local relative = WrapAngle(ns.orbit.angle - ArcCenter(orbitPrefix))
			local room = arc - (positive and relative or -relative)
			local zone = math.max(1, math.min(10, arc * 0.4)) -- degrees of easing
			local f = math.max(0, math.min(1, room / zone))
			driftTarget = driftTarget * f * f * (3 - 2 * f)
		end
	end
	local driftStep = elapsed * math.max(1, OrbitSetting("DriftSpeed")) / DRIFT_RAMP
	local driftVel = ns.orbit.driftVel or 0
	if driftVel < driftTarget then
		driftVel = math.min(driftTarget, driftVel + driftStep)
	else
		driftVel = math.max(driftTarget, driftVel - driftStep)
	end
	ns.orbit.driftVel = driftVel
	-- Smoothed, so the drift's speed changes (turning round as a move sets off
	-- the other way, braking at the edge) ease in rather than start at once.
	local driftSmooth = ns.orbit.driftSmooth or driftVel
	driftSmooth = driftSmooth + (driftVel - driftSmooth) * math.min(1, elapsed / DRIFT_SMOOTH)
	ns.orbit.driftSmooth = driftSmooth

	local yawVel = driftSmooth -- signed degrees per second, before the level
	if ns.orbit.phase == "move" then
		local T = ns.orbit.sweepTime
		if spinning then
			-- The Hearthstone or teleport spin: the swing round eases in, then keeps
			-- speeding up (no easing out); the tilt still settles at its target.
			-- Cancelled, it brakes to a stop (and turns back once stopped:
			-- ns.StepSpinReturn).
			local ease = ns.orbit.ease or OrbitSetting("Ease")
			local cruise = T * (1 - ease)
			local t = ns.orbit.t
			local speed, going = ns.SpinSpeed(elapsed)
			yawVel = ns.orbit.yawDelta > 0 and speed or -speed
			if not going then
				StopOrbitTilt()
				BeginPause(0, true) -- (no drift: the turn back follows once the level is down)
				if want then
					-- Still a cozy camera (at a campfire, say): it sways on from here.
					ns.orbit.returnPending = false
				end
			elseif t < T then
				local pitchSpeed = ns.orbit.level * math.abs(ns.orbit.pitchDelta) * EaseShape(t, T, ease) / cruise
				MoveAxis(ns.pitchAxis, pitchSpeed, ns.orbit.pitchDelta > 0)
				ns.orbit.pitch = ns.orbit.pitch + (ns.orbit.pitchDelta > 0 and pitchSpeed or -pitchSpeed) * elapsed
			else
				StopOrbitTilt()
			end
		elseif ns.orbit.t >= T then
			StopOrbitTilt() -- the yaw carries on drifting
			-- Behind only always drifts a little after a move, drift setting or not.
			local startT = 0
			if ns.orbit.shortPauseNext then
				ns.orbit.shortPauseNext = false
				startT = math.max(0, OrbitSetting("Pause") - (orbitPrefix == "cozyOrbit" and 0 or HANDOFF_PAUSE))
			end
			BeginPause(startT, false, OrbitSetting("Mode") == "back")
			if ns.orbit.special then
				ns.OrbitSpecialMoveDone() -- (a fly-by's or the arrival's move)
			end
		else
			-- Each axis: cruise = distance / (T * (1 - ease)), shaped by the ease curve.
			local ease = ns.orbit.ease or OrbitSetting("Ease")
			local shape = EaseShape(ns.orbit.t, T, ease) / (T * (1 - ease))
			yawVel = yawVel + ns.orbit.yawDelta * shape
			local pitchSpeed = ns.orbit.level * math.abs(ns.orbit.pitchDelta) * shape
			MoveAxis(ns.pitchAxis, pitchSpeed, ns.orbit.pitchDelta > 0)
			ns.orbit.pitch = ns.orbit.pitch + (ns.orbit.pitchDelta > 0 and pitchSpeed or -pitchSpeed) * elapsed
		end
	elseif orbitPrefix == "taxiOrbit" and want and ns.OrbitSpecial() then
		-- (On a flight: a fly-by or the arrival instead of the next sway.)
	elseif ns.orbit.t >= (ns.orbit.pauseLen or OrbitSetting("Pause")) then
		ns.orbit.phase, ns.orbit.t = "move", 0
		PlanNextSweep()
	end
	local yawSpeed = ns.orbit.level * yawVel
	DriveYaw(yawSpeed)
	ns.orbit.angle = WrapAngle(ns.orbit.angle + yawSpeed * elapsed)
end

-- Fly-by: line the camera up behind you, turn it flyByAngle degrees round to
-- look back past you, hold, then turn it back behind you. Each step is one
-- move that starts and ends at rest, eased in and out (EaseShape), and sent
-- the way the flight camera sends its sways. Turning only: tilting as well
-- kept snapping the turn. Started with /cine flyby or its key, or at random
-- in the middle of flights (taxiFlyBy). Settings: flyByAngle (degrees),
-- flyByTurnTime, flyByHold, flyByBackTime (seconds).
--
-- flyby.view tracks the camera the way the flight camera does (degrees left
-- of straight behind you), and is handed back to it at the end.
local FLYBY = {
	LINE_UP_SPEED = 30, -- degrees per second, about: how long lining up behind you takes...
	LINE_UP_MIN = 1.5,  -- ...but at least this many seconds
	SETTLE_TURN = 12,   -- seconds before it must be done that the arrival's turn behind you starts (UpdateTaxi)
	SETTLE_ZOOM = 3,    -- seconds the zoom glides back first, just before that
	SPEED_CVAR = "cameraYawMoveSpeed",
	MIN_SETTING = 1,    -- the lowest turn speed setting sent (lower, the game uses its full speed)
	SETTING_CHANGE = 0.02, -- speed setting changes smaller than this share aren't sent
	PRIME_TIME = 0.2,   -- seconds the starting speed is set before the turn starts
	RESTORE_DELAY = 0.3, -- seconds after a turn stops before your speed setting comes back
	HANDOVER = 0.6,     -- seconds to ease out the flight camera's drift before the first turn
	HANDOVER_MAX = 1.5, -- ...longer from a faster sway (BRAKE_RATE degrees/sec per second), up to this...
	BRAKE_RATE = 15,
	QUIET = 1,          -- ...then held still this long before the turn sets off (see TakeOver)
	BEFORE_FRAMES = 90, -- frames of the flight camera logged ahead of each fly-by (debug)
	MAX_ACCEL = 9,      -- degrees/sec per second: fly-by and arrival turns speed up no harder (the sways' most)
	AGAINST_DRIFT = 0.3, -- degrees/sec: a fly-by or arrival turn against a drift faster than this waits for it to fade
	FIRST = { 30, 60 }, -- seconds after takeoff for a random one on a route not timed yet
	CVARS = { values = { cameraSmoothStyle = "0" } }, -- camera follow off (already off on flights)
}
local flyby = { active = false }

-- A fly-by message in chat: always for ones you start, and for the random
-- ones while /cine debug flybys is on. debugOnly: only with that on.
local function FlyBySay(text, debugOnly)
	if ns.db.debugFlyBy or not (debugOnly or flyby.quiet) then
		ns.Print("fly-by" .. (flyby.quiet and " (random)" or "") .. ": " .. text)
	end
end

-- /look as the fly-by starts (flyByLook): your character looks around, as if
-- they'd spotted something. Untargeted ("none"), so it doesn't come out as
-- looking at whatever you have targeted.
local function FlyByLook()
	if not ns.db.flyByLook then
		return
	end
	local ok
	if DoEmote then
		ok = pcall(DoEmote, "LOOK", "none")
	elseif C_ChatInfo and C_ChatInfo.PerformEmote then
		ok = pcall(C_ChatInfo.PerformEmote, "LOOK", "none")
	end
	FlyBySay(ok and "/look" or "/look failed", true)
end

-- How fast an axis is turning now (degrees per second, positive its
-- positive way).
local function AxisRate(axis)
	if not axis.moving then
		return 0
	end
	local rate = axis.speed * (tonumber(GetCVar(axis.speedCVar)) or axis.defaultSpeed)
	return axis.positive and rate or -rate
end

-- Each step's turn goes out as one held command, like the quest cam's: re-
-- sending it at each new speed restarted it, and every start gives a small
-- jolt (bigger the faster it's going), which showed as a jump as each turn
-- began. Instead the turn is sent once, at the share of your turn speed
-- setting that makes your setting its top speed, and the setting itself is
-- stepped along the ease curve, from MIN_SETTING (a fraction of a degree per
-- second) up toward yours and back. Your setting comes back once it stops.

-- Stops the step's turn; your speed setting comes back a moment later, so the
-- end of the turn can't run at full speed.
local function StopTurn()
	StopAxis(ns.yawAxis)
	if flyby.turning then
		flyby.turning, flyby.sent = false, nil
		C_Timer.After(FLYBY.RESTORE_DELAY, function()
			if not flyby.turning then
				ns.RestoreCVar(FLYBY.SPEED_CVAR)
				ns.flyByHoldsYawSpeed = false
			end
		end)
	end
end

-- The next step: turn by turn degrees (left positive) over T seconds (0: hold
-- still). The speed setting goes to its lowest a moment before the turn starts.
local function BeginStep(phase, turn, T)
	flyby.phase, flyby.turn, flyby.t, flyby.T = phase, turn, 0, math.max(0.1, T)
	T = flyby.T
	if flyby.handover then
		return -- (set off once the flight camera has eased out: see StepFlyBy)
	end
	StopTurn()
	if math.abs(turn) < 0.5 then
		return
	end
	ns.SaveCVar(FLYBY.SPEED_CVAR)
	ns.flyByHoldsYawSpeed = true
	local yours = tonumber(ns.db.savedCVars[FLYBY.SPEED_CVAR]) or ns.yawAxis.defaultSpeed
	flyby.cruise = math.abs(turn) / (T * 0.5) -- top speed of one smooth swell (EaseShape, ease 0.5)
	flyby.share = flyby.cruise / yours
	SetCVar(FLYBY.SPEED_CVAR, ("%.2f"):format(FLYBY.MIN_SETTING))
	flyby.primedUntil = GetTime() + FLYBY.PRIME_TIME
	flyby.turning, flyby.sent = true, nil
end


-- Lines up behind you, from wherever the camera is: quicker the nearer it is.
local function LineUpTime(maxTime)
	return math.min(maxTime or math.huge, math.max(FLYBY.LINE_UP_MIN, math.abs(flyby.view) / FLYBY.LINE_UP_SPEED))
end

-- why: printed when it ends early (nil when it's run its course or was stopped).
local function EndFlyBy(why)
	if flyby.handover and not flyby.handover.stopped then
		StopOrbitTilt() -- (cut short while easing the flight camera out)
	end
	flyby.active, flyby.handover = false, nil
	if why then
		FlyBySay("stopped: " .. why)
	end
	StopTurn()
	ns.ApplyCVarSet(FLYBY.CVARS, false)
	-- Hand the camera back to the flight camera (its angle is positive turned
	-- right): a full pause holding still before its next sway.
	ns.orbit.angle = WrapAngle(-flyby.view)
	if ns.orbit.settling then
		ns.StopOrbitNow() -- (locked behind you for landing: it stays off)
	elseif ns.orbit.level > 0 then
		ns.orbit.continuous, ns.orbit.contFade = false, nil
		ns.orbit.driftVel, ns.orbit.driftSmooth = 0, 0
		BeginPause(0, true)
	end
	-- Nor does the slow zoom start a move straight away (it was held back
	-- meanwhile, so it was due): a full pause first.
	if idleZoom.active and idleZoom.phase == "pause" then
		idleZoom.t = 0
	end
end

-- Takes the camera over from the flight camera, stopping its sway and tilt:
-- where it's pointing is the flight camera's tracking on flights (or with a
-- camera running), straight behind you otherwise.
local function TakeOver()
	local tracked = ns.orbit.level > 0 or UnitOnTaxi("player")
	flyby.view = tracked and -ns.orbit.angle or 0
	-- Whatever the flight camera was doing (its drift, or a sway the arrival
	-- shot cut into, tilt and all) eases out first: stopped dead, it showed
	-- as a jerk as the fly-by or arrival shot began. Then the camera holds
	-- still for QUIET seconds before the first turn: a turn sent within a
	-- moment of the last one stopping snapped as it set off (the quest cam
	-- found the same, see its STEP_GAP), while one after a still spell (the
	-- turn back, after the hold) set off cleanly.
	local rate = AxisRate(ns.yawAxis)
	local tilt = not ns.orbit.tilting and AxisRate(ns.pitchAxis) or 0
	-- (Longer from a faster sway, so it never brakes hard.)
	local T = math.min(FLYBY.HANDOVER_MAX, math.max(FLYBY.HANDOVER, math.abs(rate) / FLYBY.BRAKE_RATE,
		math.abs(tilt) / FLYBY.BRAKE_RATE))
	flyby.handover = { rate = rate, tilt = tilt, view = flyby.view, T = T, t = 0 }
	-- The slow zoom, if it's gliding, comes to a stop meanwhile too, done
	-- halfway through the still moment: a zoom moving under a turn snaps it.
	ns.BrakeIdleZoom(T + FLYBY.QUIET * 0.5)
	if rate == 0 then
		StopAxis(ns.yawAxis)
	end
	if tilt == 0 then
		StopOrbitTilt()
	end
	flyby.active, flyby.started = true, GetTime()
	flyby.onTaxi = UnitOnTaxi("player")
end

-- Starts a fly-by, or stops the one running. Returns false and why if it
-- can't. quiet: a random one (no messages unless /cine debug flybys is on).
function ns.ToggleFlyBy(quiet)
	if flyby.active then
		EndFlyBy()
		return true, "stopped"
	end
	if not ns.db.enabled then
		return false, "Cinematic is off (/cine turns it on)"
	end
	if InCombatLockdown() then
		return false, "not in combat"
	end
	-- Steering with the mouse turns your character to face the camera, so the
	-- camera can't turn away from your facing meanwhile.
	if IsMouseOnCamera() then
		return false, "let go of the mouse first"
	end
	-- On a flight the flight camera makes it, between its sways (see
	-- ns.OrbitSpecial): just ask.
	if UnitOnTaxi("player") and ns.orbit.level > 0 and orbitPrefix == "taxiOrbit" then
		if ns.orbit.special or ns.orbit.flyByWanted then
			return false, "one's already under way"
		elseif ns.orbit.noNewSways or ns.orbit.settleWanted then
			return false, "too close to landing"
		end
		ns.orbit.flyByWanted, ns.orbit.flyByQuiet = true, quiet or false
		return true
	end
	TakeOver()
	flyby.quiet = quiet or false
	-- Which way round: the side the camera's on, if it's off to one side
	-- (it turns on out from there); either, from behind you.
	flyby.side = flyby.view > 5 and 1 or flyby.view < -5 and -1 or (math.random() < 0.5 and 1 or -1)
	if math.abs(flyby.view) > 5 then
		-- Off to one side already (the flight sway left it there): turn on out
		-- from where it is, at the usual turn's pace. Lining up behind you first
		-- whipped it back the other way and then reversed, which showed as a snap.
		local turn = flyby.side * ns.db.flyByAngle - flyby.view
		BeginStep("out", turn, math.max(FLYBY.LINE_UP_MIN,
			ns.db.flyByTurnTime * math.abs(turn) / math.max(1, ns.db.flyByAngle)))
	else
		BeginStep("lineup", -flyby.view, LineUpTime())
	end
	if ns.db.debugFlyBy then
		ns.db.flyByLog = {}
		flyby.log = ns.db.flyByLog
		ns.FlyByLogBefore()
	end
	-- A swing back behind you still going (the takeoff swing, say) would fight
	-- it: end it now. On flights, follow then goes back off with the flight's
	-- own setting; elsewhere the fly-by turns it off itself.
	recenterUntil = 0
	ns.ApplyCVarSet(ns.RECENTER_CVARS, false)
	if flyby.onTaxi then
		ns.ApplyCVarSet(ns.FLIGHT_CVARS, true)
	else
		ns.ApplyCVarSet(FLYBY.CVARS, GetCVar("cameraSmoothStyle") ~= "0")
	end
	FlyBySay(("turning round to look back (%s)"):format(flyby.side > 0 and "left" or "right"))
	FlyByLook()
	return true
end

-- One fly-by frame: returns true while it's turning the camera.
local function StepFlyBy(now, elapsed)
	if not flyby.active then
		return false
	end
	-- Only camera input since it started counts: the flight camera's pause
	-- after input reaches back several seconds.
	-- (Turning the addon off, with its key or /cine, stops it where it is.)
	local why = (not ns.db.enabled and "turned off")
		or (lastCameraInput > flyby.started and "you moved the camera")
		or (InCombatLockdown() and "combat") or (flyby.onTaxi and not UnitOnTaxi("player") and "landed")
	if why then
		EndFlyBy(why)
		return false
	end
	if ns.orbit.settling and flyby.phase ~= "back" and flyby.phase ~= "settle" then
		-- About to land: straight back behind you, in time for landing. (A
		-- step under way is cut short: rare, as random ones end before this.)
		BeginStep("back", -flyby.view, LineUpTime(FLYBY.SETTLE_TURN))
	end
	-- Where the camera actually went this frame: at the speed it was turning.
	flyby.view = WrapAngle(flyby.view - AxisRate(ns.yawAxis) * elapsed)
	local hand = flyby.handover
	if hand then
		-- Easing out the flight camera's turn and tilt (half a cosine down to a
		-- stop), holding still a moment, then the first step sets off.
		hand.t = hand.t + elapsed
		if hand.t < hand.T then
			local f = (1 + math.cos(math.pi * hand.t / hand.T)) / 2
			local rate, tilt = hand.rate * f, hand.tilt * f
			if hand.rate ~= 0 then
				MoveAxis(ns.yawAxis, math.abs(rate), rate > 0)
			end
			if hand.tilt ~= 0 then
				ns.orbit.pitch = ns.orbit.pitch + AxisRate(ns.pitchAxis) * elapsed -- (the flight camera's count)
				MoveAxis(ns.pitchAxis, math.abs(tilt), tilt > 0)
			end
			return true
		end
		if not hand.stopped then
			hand.stopped = true
			StopAxis(ns.yawAxis)
			if hand.tilt ~= 0 then
				StopOrbitTilt()
			end
		end
		if hand.t < hand.T + FLYBY.QUIET then
			return true -- (held still: nothing sent, the speed setting untouched)
		end
		flyby.handover = nil
		-- (Still aiming where it was: less the little way the drift carried it.)
		BeginStep(flyby.phase, flyby.turn - WrapAngle(flyby.view - hand.view), flyby.T)
	end
	if flyby.turning and now < flyby.primedUntil then
		return true -- (the lowest speed setting going in before the turn starts)
	end
	-- This step's speed now: one smooth swell from rest to rest, sent as the
	-- speed setting under the one held turn (see BeginStep).
	flyby.t = flyby.t + elapsed
	if flyby.turning then
		local setting = math.max(FLYBY.MIN_SETTING,
			flyby.cruise * EaseShape(math.min(flyby.t, flyby.T), flyby.T, 0.5) / flyby.share)
		if not flyby.sent then
			local axis = ns.yawAxis
			axis.positive, axis.moving, axis.speed, axis.lastStart = flyby.turn < 0, true, flyby.share, now
			CallCameraFunction(axis.positive and axis.positiveStart or axis.negativeStart, flyby.share)
			flyby.sent = FLYBY.MIN_SETTING
		elseif math.abs(setting - flyby.sent) > flyby.sent * FLYBY.SETTING_CHANGE then
			SetCVar(FLYBY.SPEED_CVAR, ("%.2f"):format(setting))
			flyby.sent = setting
		end
	end
	if flyby.t >= flyby.T then
		if flyby.phase == "lineup" then
			BeginStep("out", flyby.side * ns.db.flyByAngle - flyby.view, ns.db.flyByTurnTime)
		elseif flyby.phase == "out" then
			BeginStep("hold", 0, ns.db.flyByHold)
		elseif flyby.phase == "hold" then
			BeginStep("back", -flyby.view, ns.db.flyByBackTime)
			FlyBySay("turning back behind you", true)
		else
			EndFlyBy() -- (handing over where it actually got to)
			FlyBySay("done", true)
		end
	end
	return true
end

-- Before landing (taxiSettle): line up behind you and stay there; the flight
-- camera stops meanwhile (ns.orbit.settling), so the camera stays locked
-- behind you until you land. (A fly-by under way turns back on its own: see
-- StepFlyBy.)
function ns.SettleBehind()
	if flyby.active then
		return
	end
	TakeOver()
	flyby.quiet = true
	-- The whole time there is (the settle starts SETTLE_TURN before it must be
	-- done), less the ease-out and the still moment: a quick line-up (67 degrees
	-- in 2 seconds) lurched as it got going.
	BeginStep("settle", -flyby.view,
		math.max(FLYBY.LINE_UP_MIN, FLYBY.SETTLE_TURN - flyby.handover.T - FLYBY.QUIET))
	if ns.db.debugFlyBy then
		ns.db.flyBySettleLog = {} -- (its own, so the last fly-by's stays)
		flyby.log = ns.db.flyBySettleLog
		ns.FlyByLogBefore()
	end
	FlyBySay("settling behind you for landing", true)
end

ns.SETTLE_TURN, ns.SETTLE_ZOOM = FLYBY.SETTLE_TURN, FLYBY.SETTLE_ZOOM

-- Random fly-bys on flight paths (taxiFlyBy): spread over the middle of the
-- flight, taxiFlyByFrom to taxiFlyByTo % of its known time, one per
-- taxiFlyByEvery seconds of that stretch, each at a random moment in its own
-- share (leaving room for it to play out). A route flown for the first time
-- has no known time yet: one fly-by, FLYBY.FIRST seconds after takeoff.
-- Flights picked up after a /reload or login get none. A fly-by that can't
-- start on time (you're moving the camera, say) waits, until its share is over.
local autoFlyBys = { times = {} }

-- WoW Forever's Frequent Flier legacy talent (spell 1225490): flight path
-- mounts fly 20% faster, so every flight takes 1/1.2 of the time. Checked
-- directly, so the first flight after learning (or unlearning) it is already
-- timed right. (Constants inside the functions: this file is at Lua's
-- 200-local limit.)
local function TalentFlightScale()
	return (IsPlayerSpell and IsPlayerSpell(1225490)) and 1 / 1.2 or 1
end

-- How long a route takes (seconds): your own timed flight of it, or nil
-- until you've flown it once. (See ns.UpdateTaxi.) Saved times are at a
-- common speed (without the talent); the talent and flightSpeedScale turn
-- them into today's. flightSpeedScale catches anything else that changes
-- every flight's speed, learned from one flight instead of one per route.
local function KnownFlightTime(route)
	local base = route and ns.db.flightTimes[route]
	return base and base * (ns.db.flightSpeedScale or 1) * TalentFlightScale()
end

-- On landing: save the route's time. A route already known that took a
-- clearly different time (more than FLIGHT_SCALE_SLACK off) means every flight
-- has sped up or slowed down, so the scale follows it. One odd flight that
-- sets it wrong is put right by the next one.
local function RecordFlightTime(route, seconds)
	local FLIGHT_SCALE_SLACK = 0.08
	seconds = seconds / TalentFlightScale() -- (saved as if without the talent)
	local scale = ns.db.flightSpeedScale or 1
	local base = ns.db.flightTimes[route]
	if base and base > 0 then
		local ratio = seconds / base
		if math.abs(ratio - scale) > scale * FLIGHT_SCALE_SLACK and ratio > 0.5 and ratio < 2 then
			scale = math.abs(ratio - 1) > 0.01 and ratio or 1
			ns.db.flightSpeedScale = scale ~= 1 and scale or nil
			if ns.db.debugFlyBy then
				ns.Print(("flight: flights now take %d%% of the time they used to"):format(scale * 100 + 0.5))
			end
		end
	end
	ns.db.flightTimes[route] = seconds / scale
end

local function PlanAutoFlyBys()
	local plan = { times = {}, key = flightSince }
	if flightSince == -math.huge then
		return plan -- (resumed mid-flight: they're only planned as you take off)
	end
	local start = ns.flight.start or flightSince
	local duration = ns.flight.start and KnownFlightTime(ns.flight.route)
	local length = ns.SpecialMoveTime(ns.db.flyByAngle, ns.db.flyByTurnTime) + ns.db.flyByHold
		+ ns.SpecialMoveTime(ns.db.flyByAngle, ns.db.flyByBackTime)
	if duration then
		local a = math.min(ns.db.taxiFlyByFrom, ns.db.taxiFlyByTo) / 100
		local b = math.max(ns.db.taxiFlyByFrom, ns.db.taxiFlyByTo) / 100
		local from, to = start + duration * a, start + duration * b
		-- Each must be over before the arrival (the zoom back, the turn behind
		-- you and the lock before landing) begins: one still turning when the
		-- landing zoom started showed as snaps.
		local arrival = start + duration
		if ns.db.taxiSettle then
			arrival = arrival - (ns.db.taxiSettleLead + ns.SETTLE_TURN + ns.SETTLE_ZOOM) - 2
		end
		local count = math.max(1, math.floor((to - from) / ns.db.taxiFlyByEvery))
		local share = (to - from) / count
		for i = 1, count do
			local shareStart = from + (i - 1) * share
			-- The latest it may start: by the end of its share, and in time to
			-- finish before the arrival. (No room: skipped.)
			local latest = math.min(shareStart + share, arrival - length)
			if latest >= shareStart then
				plan.times[#plan.times + 1] = {
					at = shareStart + math.random() * math.max(0, math.min(share - length, latest - shareStart)),
					latest = latest }
			end
		end
	elseif start then
		local first = FLYBY.FIRST
		local at = start + first[1] + math.random() * (first[2] - first[1])
		plan.times[1] = { at = at, latest = at + ns.db.taxiFlyByEvery }
	end
	return plan
end

-- Called from UpdateOrbit each frame, before UpdateFlyBy.
function ns.UpdateAutoFlyBy(now, onTaxi, cinematic, adjusting)
	if not onTaxi then
		autoFlyBys = { times = {} }
		return
	end
	if not (ns.db.taxiFlyBy and cinematic and ns.FlightCameraOn()) or ns.FlightTakenOver() then
		return
	end
	if autoFlyBys.key ~= flightSince then
		autoFlyBys = PlanAutoFlyBys() -- (a new flight)
		if ns.db.debugFlyBy then
			local times = {}
			for _, slot in ipairs(autoFlyBys.times) do
				times[#times + 1] = ("in %d sec"):format(math.max(0, slot.at - now))
			end
			local duration = KnownFlightTime(ns.flight.route)
			ns.Print(("fly-by: random ones planned for this flight (%s): %s"):format(
				flightSince == -math.huge and "resumed after a reload, so none"
					or duration and ("%d sec long"):format(duration) or "route not timed yet",
				#times > 0 and table.concat(times, ", ") or "none"))
		end
	end
	local nextOne = autoFlyBys.times[1]
	if not nextOne or now < nextOne.at then
		return
	end
	-- Not while you're moving the camera (or just did), in combat, swinging
	-- round behind you after takeoff or settling for landing.
	-- (Once asked, the flight camera starts it as its current sway ends.)
	local blocked = flyby.active or adjusting or IsMouseOnCamera() or InCombatLockdown() or ns.orbit.settling
		or ns.orbit.level <= 0 or now < (ns.orbit.centerUntil or 0)
		or ns.orbit.special or ns.orbit.flyByWanted or ns.orbit.noNewSways or ns.orbit.settleWanted
	if blocked then
		if now > nextOne.latest then
			table.remove(autoFlyBys.times, 1)
			if ns.db.debugFlyBy then
				ns.Print("fly-by (random): skipped: you were moving the camera, in combat, or it was too near landing")
			end
		end
		return
	end
	table.remove(autoFlyBys.times, 1)
	ns.ToggleFlyBy(true)
end

-- With /cine debug flybys on, every frame of each fly-by (and the 3 seconds
-- after it, as the flight camera takes over) is recorded in the saved
-- settings (flyByLog, the latest one only, and flyBySettleLog for the settle
-- before landing; written out on /reload or logout).
-- One line per frame: time, frame time, phase ("after" once it's over), the
-- turn and tilt actually sent (degrees per second; turn left positive, tilt
-- up positive), whether each was restarted (1/0), the tracked view and
-- tilt, the zoom distance, the slow zoom's phase, the flight camera's level
-- and phase, and your facing (degrees; -1 if hidden), to spot the flight
-- path itself jerking the camera round (it turns with you).
local LOG_MAX, LOG_AFTER = 6000, 3
local logLast = { yaw = 0, pitch = 0 }

-- phase: logging the flight camera (its angle as the view): "before", ahead of
-- a fly-by (into flyby.before, the last FLYBY.BEFORE_FRAMES frames, put at the
-- top of the next fly-by's log), or its own fly-by or arrival (ns.orbit.special).
local function LogFlyBy(now, elapsed, phase)
	local before = phase == "before"
	local log = before and flyby.before or flyby.log
	if type(log) ~= "table" or #log >= LOG_MAX then
		return
	end
	local yaw, pitch = ns.yawAxis, ns.pitchAxis
	local yawRestart = yaw.lastStart ~= logLast.yaw and 1 or 0
	local pitchRestart = pitch.lastStart ~= logLast.pitch and 1 or 0
	logLast.yaw, logLast.pitch = yaw.lastStart, pitch.lastStart
	local okFacing, facing = pcall(GetPlayerFacing)
	facing = okFacing and type(facing) == "number" and not (issecretvalue and issecretvalue(facing))
		and math.deg(facing) or -1
	log[#log + 1] = ("%.3f %.4f %s %.2f %.2f %d %d %.2f %.2f %.2f %s %.2f %s %.2f"):format(now, elapsed,
		phase or (flyby.active and flyby.phase) or "after", -AxisRate(yaw), AxisRate(pitch),
		yawRestart, pitchRestart, (phase and -(ns.orbit.angle or 0)) or flyby.view or 0, ns.orbit.pitch or 0, GetCameraZoom and GetCameraZoom() or 0,
		idleZoom.active and tostring(idleZoom.phase) or (idleZoom.restoring and "restoring" or "off"),
		ns.orbit.level or 0, tostring(ns.orbit.phase), facing)
end

-- Called from UpdateOrbit each frame: returns true while the fly-by is
-- turning the camera (the flight camera waits meanwhile).
-- A fly-by's log starting: the frames just before it go at the top.
function ns.FlyByLogBefore()
	for _, line in ipairs(flyby.before or {}) do
		flyby.log[#flyby.log + 1] = line
	end
	flyby.before = {}
end

function ns.UpdateFlyBy(now, elapsed)
	local driving = StepFlyBy(now, elapsed)
	if ns.db.debugFlyBy then
		local special = ns.orbit.special
		if driving or special then
			flyby.logUntil = now + LOG_AFTER
		end
		if now < (flyby.logUntil or 0) then
			LogFlyBy(now, elapsed, not driving and (special or "after") or nil)
		elseif UnitOnTaxi("player") then
			flyby.before = flyby.before or {}
			LogFlyBy(now, elapsed, "before")
			if #flyby.before > FLYBY.BEFORE_FRAMES then
				table.remove(flyby.before, 1)
			end
		end
	end
	return driving
end

-- Whether a fly-by (or the settle) is turning the camera right now.
function ns.FlyByTurning()
	local special = ns.orbit.special
	return flyby.active or special == "flyOut" or special == "flyHold" or special == "flyBack"
end

-- For /cine debug flyby.
function ns.GetFlyByDebug()
	return {
		active = flyby.active, phase = flyby.phase, t = flyby.t, T = flyby.T,
		view = flyby.view, planned = autoFlyBys.times,
	}
end

-- Swing the camera back behind the character (flight start, and the
-- standing-still orbit in behind-only mode). There's no API to set the camera
-- angle, and SetView's blend is too quick and abrupt, so this borrows camera
-- following instead: for RECENTER_TIME seconds, follow is set to "Always" with
-- slowed swing speeds, so the camera eases round behind the character on its
-- own, then the player's follow settings are put back. Zoom is untouched.
ns.DEATH_CVARS = { values = { cameraSmoothStyle = "0" } }
ns.RECENTER_CVARS = {
	values = { cameraSmoothStyle = "2", cameraYawSmoothSpeed = "45", cameraPitchSmoothSpeed = "30" },
}
ns.wasOnTaxi = false

-- duration and swing speeds (degrees per second) default to the flight-start
-- swing; the RP walk glide after a turn passes slower ones.
-- ramp: seconds over which the swing speeds build up from a crawl, so a camera
-- that's been turned well away doesn't lurch into motion.
local recenterRamp = { start = 0, length = 0, yaw = 45, pitch = 30, applied = nil }
local RAMP_MIN = 0.08 -- the share of full speed it starts at

local function RampedSpeeds(now)
	local r = recenterRamp
	local f = 1
	if r.length > 0 then
		f = math.min(1, (now - r.start) / r.length)
		f = RAMP_MIN + (1 - RAMP_MIN) * f * f * (3 - 2 * f)
	end
	return ("%.0f"):format(r.yaw * f), ("%.0f"):format(r.pitch * f)
end

function CenterCamera(duration, yawSpeed, pitchSpeed, ramp)
	local now = GetTime()
	recenterUntil = now + (duration or RECENTER_TIME)
	recenterRamp.start, recenterRamp.length = now, ramp or 0
	recenterRamp.yaw, recenterRamp.pitch = yawSpeed or 45, pitchSpeed or 30
	local values = ns.RECENTER_CVARS.values
	local yaw, pitch = RampedSpeeds(now)
	if ns.RECENTER_CVARS.active then
		-- Already swinging (your own settings are saved): just change the speeds.
		if values.cameraYawSmoothSpeed ~= yaw then SetCVar("cameraYawSmoothSpeed", yaw) end
		if values.cameraPitchSmoothSpeed ~= pitch then SetCVar("cameraPitchSmoothSpeed", pitch) end
	end
	values.cameraYawSmoothSpeed, values.cameraPitchSmoothSpeed = yaw, pitch
	ns.ApplyCVarSet(ns.RECENTER_CVARS, true)
end

-- Camera following ("Smart"/"Always") keeps pulling the camera back behind a
-- moving character, which fights the orbit and makes it jitter. Turn it off
-- for the whole flight; orbit offsets then stay put relative to the character
-- (so the camera still banks with the flight) and add up sweep by sweep.
ns.FLIGHT_CVARS = { values = { cameraSmoothStyle = "0" } }

-- Runs on the throttled tick: flight start, the end of a recenter, and camera
-- follow for flights. Both CVar sets touch cameraSmoothStyle, so a recenter is
-- always ended (restoring the player's value) before the flight set applies.
-- Flight times: there's no API for how long a flight takes, so each route
-- (start > destination, read from the flight map when TakeTaxiNode is called)
-- is timed from takeoff to landing and saved. Later flights on the same route
-- know when they'll land, so the camera can settle behind the character first.
local TAXI_PICK_WINDOW = 30 -- seconds between picking a destination and takeoff
local pendingRoute, pendingRouteAt
ns.flight = {}           -- route and start (time) of the flight in progress

function ns.HookTaxiRoutes()
	if not TakeTaxiNode then
		return
	end
	hooksecurefunc("TakeTaxiNode", function(index)
		local from
		for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
			if TaxiNodeGetType(i) == "CURRENT" then
				from = TaxiNodeName(i)
			end
		end
		local to = TaxiNodeName(index)
		if from and to then
			pendingRoute, pendingRouteAt = from .. " > " .. to, GetTime()
		end
	end)
end

local function FlightTimeLeft()
	local duration = KnownFlightTime(ns.flight.route)
	if not duration then
		return nil
	end
	return duration - (GetTime() - ns.flight.start)
end

-- On flights the fly-by and the arrival are moves of the flight camera itself
-- (ns.orbit.special), made the way its sways are: speed changes on top of the
-- drift that always runs underneath, so the camera never stops and restarts,
-- and no game setting changes. (Taking the camera over for them, stopping
-- it, easing the game's turn speed setting and starting it again, jolted as
-- the turns set off and finished, however the steps were timed.) They speed
-- up and slow down no harder than the sways (FLYBY.MAX_ACCEL), and start as
-- the sway under way ends:
--   flyOut   round toward your front on the side the camera's on, to flyByAngle
--   flyHold  held there flyByHold seconds, the drift fading to rest
--   flyBack  back round behind you; the sways carry on after a full pause
--   settle   the arrival: back behind you and level, the drift fading out...
--   settled  ...and still there until you land
-- None sets off against the drift: the camera would have to turn round
-- partway into the move's speeding up (the game's turn stopping and starting
-- the other way in one frame), which showed as a snap at the turn back after
-- the hold. The drift fades out first; any turning round then happens as the
-- move begins, everything at a crawl.
-- Asked for with ns.orbit.flyByWanted (random fly-bys, /cine flyby) and
-- settleWanted (UpdateTaxi, which also sets noNewSways so no sway is still
-- going when the arrival's due).

-- Seconds for a move of `degrees`: at least `seconds`, and long enough that
-- it speeds up no harder than MAX_ACCEL. (An eased move of T seconds, ease
-- 0.5, speeds up by at most 2 * pi * degrees / T^2 degrees/sec per second.)
function ns.SpecialMoveTime(degrees, seconds)
	return math.max(seconds or 0, ORBIT_MIN_SWEEP_TIME,
		math.sqrt(2 * math.pi * math.abs(degrees) / FLYBY.MAX_ACCEL))
end

-- Starts one: round to `target` (the flight camera's angle; 0 is behind you)
-- over at least `seconds`; level: tilt back to the height you took off at too.
function ns.StartSpecialMove(kind, target, seconds, level)
	local o = ns.orbit
	local desired = WrapAngle(target - o.angle)
	local T = ns.SpecialMoveTime(desired, seconds)
	-- The drift runs on under the move (the arrival's fades it out instead),
	-- adding its own bit: aim that much short.
	local drift = (kind ~= "settle" and OrbitSetting("Drift")) and OrbitSetting("DriftSpeed") or 0
	local delta = desired
	if math.abs(desired) > drift * T then
		delta = desired - (desired > 0 and drift or -drift) * T
	end
	o.special, o.phase, o.t = kind, "move", 0
	o.yawDelta, o.pitchDelta = delta, level and -o.pitch or 0
	o.ease, o.sweepTime = 0.5, T
	o.noDrift = kind == "settle"
end

-- In a pause on a flight (each frame): starts a fly-by or the arrival if one's
-- asked for, or holds the pause. Returns true when it has (no sway next).
function ns.OrbitSpecial()
	local o = ns.orbit
	if o.special == "settled" then
		return true -- still, behind you, until you land
	end
	-- Would a move toward `desired` degrees set off against the drift? If so
	-- the drift fades out first (and the move waits).
	local function AgainstDrift(desired)
		local drift = o.driftSmooth or 0
		if math.abs(drift) > FLYBY.AGAINST_DRIFT and (drift > 0) ~= (desired > 0) then
			o.noDrift = true
			return true
		end
		return false
	end
	if o.settleWanted then
		if AgainstDrift(WrapAngle(-o.angle)) then
			return true
		end
		-- The arrival (from a fly-by's hold too): over all the time there is,
		-- so it's done just as the lead before landing begins.
		flyby.quiet = true
		ns.StartSpecialMove("settle", 0, nil, true)
		local left = FlightTimeLeft()
		if left then
			o.sweepTime = math.max(ORBIT_MIN_SWEEP_TIME, left - ns.db.taxiSettleLead)
		end
		if ns.db.debugFlyBy then
			ns.db.flyBySettleLog = {}
			flyby.log = ns.db.flyBySettleLog
			ns.FlyByLogBefore()
		end
		FlyBySay(("settling behind you for landing (%.0f sec)"):format(o.sweepTime), true)
		return true
	end
	if o.special == "flyHold" then
		if o.t >= (o.pauseLen or 0) and not AgainstDrift(WrapAngle(-o.angle)) then
			local desired = math.abs(WrapAngle(-o.angle))
			ns.StartSpecialMove("flyBack", 0, ns.db.flyByBackTime * desired / math.max(1, ns.db.flyByAngle))
			FlyBySay("turning back behind you", true)
		end
		return true
	end
	if o.flyByWanted then
		-- Round on the side the camera's on (either, from behind you).
		o.flyBySide = o.flyBySide or (o.angle > 5 and 1 or o.angle < -5 and -1 or (math.random() < 0.5 and 1 or -1))
		local side = o.flyBySide
		local target = side * ns.db.flyByAngle
		if AgainstDrift(WrapAngle(target - o.angle)) then
			return true
		end
		o.flyByWanted, o.flyBySide = false, nil
		flyby.quiet = o.flyByQuiet
		local desired = math.abs(WrapAngle(target - o.angle))
		ns.StartSpecialMove("flyOut", target, ns.db.flyByTurnTime * desired / math.max(1, ns.db.flyByAngle))
		ns.BrakeIdleZoom(1.5) -- (the slow zoom eases to a stop, and waits until it's over)
		if ns.db.debugFlyBy then
			ns.db.flyByLog = {}
			flyby.log = ns.db.flyByLog
			ns.FlyByLogBefore()
		end
		-- (The flight camera's angle is positive to your right.)
		FlyBySay(("turning round to look back (%s, %.0f sec)"):format(side > 0 and "right" or "left", o.sweepTime))
		FlyByLook()
		return true
	end
	return o.noNewSways -- (close to landing: no new sway, the arrival's next)
end

-- A fly-by's or the arrival's move has ended (the pause after it has begun).
function ns.OrbitSpecialMoveDone()
	local o = ns.orbit
	if o.special == "flyOut" then
		o.special, o.pauseLen, o.noDrift = "flyHold", ns.db.flyByHold, true
	elseif o.special == "flyBack" then
		o.special = nil -- (a full pause, then the sways carry on)
		FlyBySay("done", true)
	elseif o.special == "settle" then
		o.special, o.noDrift = "settled", true
		FlyBySay("behind you for landing", true)
	end
end

-- For /cine debug flight: the route noted at the flight master (if still
-- waiting for takeoff), the flight in progress, its known time and time left.
function ns.GetFlightDebug()
	local now = GetTime()
	return {
		onTaxi = UnitOnTaxi("player"),
		pending = pendingRoute, pendingAge = pendingRoute and now - pendingRouteAt,
		route = ns.flight.route, elapsed = ns.flight.start and ns.flight.route and now - ns.flight.start,
		known = KnownFlightTime(ns.flight.route),
		left = FlightTimeLeft(), settling = ns.orbit.settling,
		hooked = TakeTaxiNode ~= nil, scale = ns.db.flightSpeedScale or 1,
		talent = TalentFlightScale() ~= 1,
	}
end

-- Mid-flight, once the pause after you moved the camera is up: swing back
-- behind you, like the takeoff swing. Camera follow is off during flights, so
-- put it back first (as for the settle) or the swing's settings would be undone.
-- Returns how long the swing takes (0 when it's off).
-- You've moved the camera yourself on this flight (dragged it, zoomed, a
-- camera key, a click in the world): for the rest of the flight only the
-- basic sway runs. Random fly-bys, the swing back behind you, the slow zoom,
-- the settle before landing and the zoom back at landing all stand down,
-- leaving the camera how you set it. (/cine flyby still works when you ask.)
function ns.FlightTakenOver()
	return flightSince ~= nil and lastCameraInput > flightSince
end

function ns.RecenterFlight()
	if not (ns.db.enabled and ns.db.taxiCenter) or ns.FlightTakenOver() then
		return 0
	end
	ns.ApplyCVarSet(ns.FLIGHT_CVARS, false)
	CenterCamera(nil, nil, 0, 1.5) -- (turn only: the height you left it at stays; easing in)
	ns.orbit.centerUntil = GetTime() + RECENTER_TIME
	return RECENTER_TIME
end

function ns.UpdateTaxi()
	local onTaxi = UnitOnTaxi("player")
	local now = GetTime()
	if onTaxi and not ns.wasOnTaxi then
		ns.orbit.angle, ns.orbit.pitch = 0, 0 -- assume the camera starts behind the character
		ns.orbit.settling, ns.orbit.zoomSettled = false, false
		ns.orbit.special, ns.orbit.flyByWanted, ns.orbit.settleWanted, ns.orbit.noNewSways = nil, false, false, false
		ns.orbit.flyBySide = nil
		if pendingRoute and now - pendingRouteAt < TAXI_PICK_WINDOW then
			ns.flight.route, ns.flight.start = pendingRoute, now
		end
		pendingRoute = nil
		ns.db.currentFlight = ns.flight.route
			and { route = ns.flight.route, start = ns.flight.start } or nil
		-- (Saved, so a /reload on the way still knows it.)
		ns.db.takeoffZoom = ns.PlayerZoom()
		ns.db.takeoffInCity = ns.IsInCity() and true or nil -- (for the Flight Cam's "Turn off in: Cities")
		flightSince, flightCamStarted = ns.flight.start or now, false
	elseif ns.wasOnTaxi and not onTaxi then
		ns.flight.takeoverLogged = nil
		if ns.flight.route then
			RecordFlightTime(ns.flight.route, now - ns.flight.start)
		end
		ns.flight.route = nil
		ns.db.currentFlight = nil
		ns.orbit.settling, ns.orbit.zoomSettled = false, false
		ns.orbit.special, ns.orbit.flyByWanted, ns.orbit.settleWanted, ns.orbit.noNewSways = nil, false, false, false
		ns.orbit.flyBySide = nil
		local takenOver = ns.FlightTakenOver() -- (before the flight's forgotten)
		flightSince = nil
		if ns.OnLandedForBuffs then ns.OnLandedForBuffs() end
		if ns.db.enabled and ns.db.taxiLandZoom and ns.db.takeoffZoom and not takenOver then
			ns.ZoomBackTo(ns.db.takeoffZoom)
		end
		ns.db.takeoffZoom, ns.db.takeoffInCity = nil, nil
		if not idleZoom.active and not idleZoom.restoring then
			ns.ApplyCVarSet(ZOOM_MAX_CVARS, false) -- (held back on the flight: see FinishRestore)
		end
	end
	ns.wasOnTaxi = onTaxi
	if onTaxi and not flightSince then
		-- Already in the air after a /reload: the camera carries on, no takeoff swing.
		-- (Login sets wasOnTaxi, so the takeoff branch above doesn't run.)
		flightSince, flightCamStarted = -math.huge, true
		-- Carry on with the saved flight so it still knows when it'll land.
		-- (GetTime carries on across reloads, so its start still lines up.)
		local saved = ns.db.currentFlight
		if not ns.flight.route and saved and saved.route and saved.start and now >= saved.start
			and now - saved.start < (KnownFlightTime(saved.route) or 600) + 60 then
			ns.flight.route, ns.flight.start = saved.route, saved.start
		else
			ns.db.currentFlight = nil
		end
	end
	-- The flight camera starting (at takeoff, or once the flight event's delay
	-- has passed): swing round behind the character. Only the behind modes need
	-- the camera to start behind the character.
	if onTaxi and not flightCamStarted and ns.FlightCameraOn() then
		flightCamStarted = true
		ns.orbit.angle, ns.orbit.pitch = 0, 0
		if ns.db.enabled and ns.db.taxiCenter then
			-- Round behind you, turning only: the height stays as you had it at
			-- takeoff, which the flight camera then tracks from (so the settle
			-- before landing puts it back there). Camera follow would otherwise
			-- shift the height too, out of sight of that tracking.
			CenterCamera(nil, nil, 0, 1.5) -- (easing in over 1.5 sec rather than starting at full speed)
			ns.orbit.centerUntil = now + RECENTER_TIME
		end
	end

	-- Settle: before a known landing, turn the camera back behind you so it's
	-- there taxiSettleLead seconds before touchdown, and lock it there (the
	-- rotation stops). Steered back directly, like a fly-by's turn back: the
	-- swing borrowed from camera follow couldn't bring it round from far off.
	-- The zoom goes first: the flight's slow zoom stops and glides back to
	-- your distance just before the turn, so only one thing moves at a time.
	if onTaxi and flightCamStarted and not ns.orbit.settling and ns.db.enabled and ns.db.taxiSettle
		and not ns.FlightTakenOver() then
		local left = FlightTimeLeft()
		-- (Not while a fly-by's turning: a zoom moving under the turn snaps it.
		-- If none ends in time, the zoom goes back at touchdown instead.)
		if left and not ns.orbit.zoomSettled and left <= ns.db.taxiSettleLead + ns.SETTLE_TURN + ns.SETTLE_ZOOM
			and not ns.FlyByTurning() then
			ns.orbit.zoomSettled = true
			-- Your takeoff distance (unless you zoomed yourself on the way), or
			-- else back from the slow zoom to where it started.
			local distance = (ns.db.taxiLandZoom and ns.db.takeoffZoom)
				or (idleZoom.active and idleZoom.saved)
			if distance then
				ns.ZoomBackTo(distance, ns.SETTLE_ZOOM)
			end
		end
		-- With the flight camera running, the arrival is its last move (see
		-- ns.OrbitSpecial): no new sway starts once one couldn't finish before
		-- the arrival's due, then it turns you behind. Otherwise the steered
		-- settle takes the camera over.
		local orbitRunning = ns.orbit.level > 0 and orbitPrefix == "taxiOrbit"
		if left and orbitRunning
			and left <= ns.db.taxiSettleLead + ns.SETTLE_TURN + (ns.db.taxiOrbitMoveTime or 10) then
			ns.orbit.noNewSways = true
		end
		if left and left <= ns.db.taxiSettleLead + ns.SETTLE_TURN then -- (the turn's time)
			if orbitRunning then
				ns.orbit.settleWanted = true
			else
				ns.orbit.settling = true
				ns.SettleBehind()
			end
		end
	end

	-- Moving on foot cancels a standing-still recenter; let the player steer.
	-- The travel line-up carries on while you walk or auto-run, but stops if
	-- you steer with the mouse or the travel mode ends.
	local traveling = (ns.IsRPWalking and ns.IsRPWalking()) or (ns.IsAutoRunning and ns.IsAutoRunning())
		or (ns.IsCozy and ns.IsCozy()) -- (the cozy camera lines up the same way)
		or (ns.IsVista and ns.IsVista()) -- (and so does the vista camera)
		or (ns.IsFish and ns.IsFish()) -- (and the fish camera)
	if travelRecenter then
		if not traveling or IsMouseOnCamera() then
			recenterUntil = 0
		end
	elseif not onTaxi and IsPlayerActive() then
		recenterUntil = 0
	end
	-- The arrival swing holds until touchdown: camera follow stays on behind
	-- you rather than going off again once the swing's time is up.
	if onTaxi and ns.orbit.settling and ns.RECENTER_CVARS.active then
		recenterUntil = math.max(recenterUntil, now + 1)
	end
	local recentering = GetTime() < recenterUntil
	if not recentering then
		ns.ApplyCVarSet(ns.RECENTER_CVARS, false)
		travelRecenter = false
	elseif ns.RECENTER_CVARS.active and recenterRamp.length > 0 then
		-- Easing the swing speeds up from a crawl.
		local yaw, pitch = RampedSpeeds(GetTime())
		local values = ns.RECENTER_CVARS.values
		if values.cameraYawSmoothSpeed ~= yaw then
			values.cameraYawSmoothSpeed = yaw
			SetCVar("cameraYawSmoothSpeed", yaw)
		end
		if values.cameraPitchSmoothSpeed ~= pitch then
			values.cameraPitchSmoothSpeed = pitch
			SetCVar("cameraPitchSmoothSpeed", pitch)
		end
	end
	ns.ApplyCVarSet(ns.FLIGHT_CVARS, (onTaxi and ns.db.enabled and ns.db.taxiOrbit and ns.FlightCameraOn()
		and not recentering) or false)
end
