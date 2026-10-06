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

local idleZoom = { active = false, saved = nil }
local turnKeys = { left = false, right = false }
-- Cozy camera emotes: emote token -> the setting that switches it on.
local COZY_EMOTES = {
	SIT = "cozySit", SLEEP = "cozySleep", LAYDOWN = "cozySleep", LIE = "cozySleep",
	DANCE = "cozyDance", KNEEL = "cozyKneel",
}
local cozyEmote -- the setting key for the emote you're doing, or nil

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

local function OnPlayerCameraInput()
	if not drivingCamera then
		lastCameraInput = GetTime()
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
		if CancelIdleZoom then CancelIdleZoom() end
		lastCameraInput = GetTime()
	end
end

function ns.HookCameraInput()
	-- Any click brings a tucked cursor back.
	local clickWatcher = CreateFrame("Frame")
	clickWatcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
	clickWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	clickWatcher:SetScript("OnEvent", function() if ns.UntuckCursor then ns.UntuckCursor() end end)
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
		cozyEmote = "cozyChair"
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
		cozyEmote = COZY_EMOTES[token:upper()]
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
				cozyEmote = (cozyEmote == nil) and "cozySit" or nil -- the sit key toggles
			end
		end)
	end
	if JumpOrAscendStart then
		hooksecurefunc("JumpOrAscendStart", function() cozyEmote = nil end) -- jumping stands you up
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
			hooksecurefunc(name, OnPlayerCameraInput)
		end
	end
	for _, name in ipairs({ "CameraOrSelectOrMoveStart", "TurnOrActionStart" }) do
		if _G[name] then
			hooksecurefunc(name, function() mouseCameraHeld = true end)
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

-- (The addon's own cursor tuck uses mouse-steering mode too; that isn't you.)
local cursorTucked = false
local function IsMouseOnCamera()
	return mouseCameraHeld or (IsMouselooking and IsMouselooking() and not cursorTucked) or false
end

-- Cursor tuck: there's no way to move the cursor, but mouse-steering mode
-- (like holding the right button) hides it. Once the cursor has been still for
-- a while in cinematic mode, with nothing open that needs it, steering mode is
-- switched on; any click, the mouse turning you, typing, a window, combat or
-- the end of cinematic mode switches it off and the cursor comes back.
local cursorX, cursorY, cursorStillSince = nil, nil, 0
local CURSOR_TUCK_IN = {
	flight = "cursorTuckFlight", idle = "cursorTuckIdle", cozy = "cursorTuckCozy",
	walk = "cursorTuckWalk", run = "cursorTuckRun",
}
local tuckFacing

local function Untuck()
	if cursorTucked then
		cursorTucked = false
		if IsMouselooking and IsMouselooking() then
			pcall(MouselookStop)
		end
	end
end

ns.UntuckCursor = Untuck

function ns.UpdateCursorTuck(cinematic)
	local now = GetTime()
	local x, y = GetCursorPosition()
	if x ~= cursorX or y ~= cursorY then
		cursorX, cursorY, cursorStillSince = x, y, now
	end
	local ok, facing = pcall(GetPlayerFacing)
	facing = (ok and type(facing) == "number" and not (issecretvalue and issecretvalue(facing))) and facing or nil

	-- Wanted in this camera mode (or, outside them, at other times)?
	local mode = ns.CameraMode and ns.CameraMode()
	local wanted = ns.db[mode and CURSOR_TUCK_IN[mode] or "cursorTuckOther"]
	local blocked = not cinematic or not wanted or InCombatLockdown()
		or GetCursorInfo() ~= nil or (ns.IsChatActive and ns.IsChatActive())
		or (ns.MouseWindowOpen and ns.MouseWindowOpen())
		or IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")

	if cursorTucked then
		local turned = facing and tuckFacing and math.abs(facing - tuckFacing) > 0.01
		if blocked or turned or not IsMouselooking() then
			Untuck()
			cursorStillSince = now -- don't tuck straight back
		end
		return
	end
	if not blocked and now - cursorStillSince >= ns.db.cursorTuckDelay
		and not (IsMouselooking and IsMouselooking()) then
		if pcall(MouselookStart) and IsMouselooking() then
			cursorTucked, tuckFacing = true, facing
		end
	end
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
	local speed = degreesPerSecond / (tonumber(GetCVar(axis.speedCVar)) or axis.defaultSpeed)
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
-- (COZY_EMOTES and cozyEmote are declared near the top, for the input hooks.)
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
-- until it's put away and drawn again.
local weaponWasDrawn, weaponDrawnCalmly = false, false
local function WeaponCozy()
	local drawn = WeaponDrawn()
	local inCombat = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	if drawn and not weaponWasDrawn then
		weaponDrawnCalmly = not inCombat
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

-- Cozy: one of the triggers while you're standing (or sitting) still.
function ns.IsCozy()
	if not ns.db or UnitOnTaxi("player") then
		return false
	end
	if ns.playerMoving then
		-- Moving ends cozy, except a weapon drawn while RP walking: the camera
		-- swings round in front of you as you walk (a "hero walk").
		return ns.db.cozyWeapon and ns.IsRPWalking and ns.IsRPWalking() and WeaponCozy() or false
	end
	if ns.db.cameraPauseAtNPCs and ns.NPCWindowOpen and ns.NPCWindowOpen() then
		return false -- talking to an NPC: waits until the window closes
	end
	return (ns.db.cozyBuffsOn and atCampfire) or (cozyEmote ~= nil and ns.db[cozyEmote])
		or (ns.db.cozyWeapon and WeaponCozy()) or false
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
	cozyOrbit = "back" }
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
		return -ns.db.cozyLevel
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
local FOOT_ZOOM = { idle = true, walk = true, run = true, cozy = true }
-- Modes that line up behind you before they start (cozy then swings round).
local LINEUP_ORBIT = { walkOrbit = true, runOrbit = true }
local TRAVEL_ORBIT = { walkOrbit = true, runOrbit = true }
-- Indoors (with the indoor limits on): smaller swings and zoom, so the
-- camera doesn't keep pushing into walls and ceilings.
local function Indoors()
	if not ns.db.indoorLimits then
		return false
	end
	local ok, indoors = pcall(IsIndoors)
	return ok and indoors == true
end

local function OrbitSetting(key)
	if key == "Mode" then
		return FIXED_MODE[orbitPrefix]
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
	if mode == "back" then
		-- Angles are worked relative to the swing's centre (in front for cozy).
		local arc = OrbitSetting("BackArc")
		local center = ArcCenter(orbitPrefix)
		local relative = WrapAngle(ns.orbit.angle - center)
		local target
		if ARC_CENTER[orbitPrefix] and math.abs(relative) > 2 * arc then
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
		ns.orbit.pitchDelta = PitchCenter() + RandomPitchTarget() - ns.orbit.pitch
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
		if ARC_CENTER[orbitPrefix] and math.abs(ns.orbit.yawDelta) > 2 * OrbitSetting("BackArc") then
			-- The cozy camera's first swing round to face you is a long one: take
			-- it slowly, but get going quickly (a short ease-in).
			ns.orbit.sweepTime = math.max(ns.orbit.sweepTime, math.abs(ns.orbit.yawDelta) / COZY_TURN_SPEED)
			ns.orbit.ease = math.min(ns.orbit.ease, COZY_START_EASE)
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
-- the direction of the last move, or back toward the start in the behind modes
-- so it never pushes past their arc. noDrift holds still (used while the
-- takeoff swing is moving the camera).
local function BeginPause(startT, noDrift, forceDrift)
	ns.orbit.phase, ns.orbit.t, ns.orbit.pauseStart = "pause", startT, startT
	ns.orbit.noDrift = noDrift or false
	ns.orbit.forceDrift = forceDrift or false
	if OrbitSetting("Mode") == "back" then
		-- Carry on gently the way the last move went, unless the drift would
		-- run past the swing limit before the pause ends; then head back in.
		local lastPositive = ns.orbit.yawDelta >= 0
		if ns.orbit.yawDelta == 0 then
			lastPositive = math.random() < 0.5
		end
		local pauseLength = OrbitSetting("Pause") - startT
		local distance = OrbitSetting("DriftSpeed") * math.max(0, pauseLength - DRIFT_RAMP)
		local relative = WrapAngle(ns.orbit.angle - ArcCenter(orbitPrefix))
		local landing = relative + (lastPositive and distance or -distance)
		if math.abs(landing) <= OrbitSetting("BackArc") then
			ns.orbit.driftPositive = lastPositive
		else
			ns.orbit.driftPositive = relative < 0
		end
	else
		ns.orbit.driftPositive = ns.orbit.yawDelta >= 0
	end
end

local function StopOrbitMove()
	StopAxis(ns.yawAxis)
	StopAxis(ns.pitchAxis)
end

function ns.StopOrbitNow()
	StopOrbitMove()
	ns.orbit.level = 0
	ns.orbit.continuous, ns.orbit.contFade = false, nil
	ns.orbit.driftVel = 0
end

local CenterCamera -- defined with the flight-start code below

-- Standing still: no movement and not dragging the camera. Turning on the spot
-- with the mouse counts as active, so the orbit never fights the player.
-- Movement comes from the PLAYER_STARTED/STOPPED_MOVING events: this client
-- can return GetUnitSpeed as a "secret" value that addons may not compare.
ns.playerMoving = false

-- shortPause: walking, so pick up again quickly in case they need to move.
local function IsAdjustingCamera(now, shortPause)
	if IsMouseOnCamera() then
		lastCameraInput = now
	end
	local pause = shortPause or ns.db.cameraInputPause
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
	cozy = "cozyZoom" }
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

local function FinishRestore()
	idleZoom.restoring = false
	idleZoom.saved = nil
	ns.ApplyCVarSet(ZOOM_MAX_CVARS, false) -- the camera's back inside the old limit
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
	else
		PlanZoom(idleZoom.saved + ZoomSetting("Distance")) -- the first move always pulls back
	end
end

local function StepIdleZoom(elapsed)
	idleZoom.t = idleZoom.t + elapsed
	local T = idleZoom.duration
	local desired = idleZoom.from + idleZoom.delta * EaseProgress(idleZoom.t, T, idleZoom.ease)
	local err = CorrectZoomToward(desired)

	if idleZoom.phase == "restore" then
		if (idleZoom.t >= T and math.abs(err) < ZOOM_RESTORE_DONE) or idleZoom.t >= T + ZOOM_RESTORE_GIVE_UP then
			FinishRestore()
		end
	elseif idleZoom.phase == "move" then
		if idleZoom.t >= T then
			idleZoom.phase, idleZoom.t = ZoomSetting("Random") and "pause" or "hold", 0
			idleZoom.from, idleZoom.delta, idleZoom.duration = desired, 0, 1
		end
	elseif idleZoom.phase == "pause" and idleZoom.t >= ZoomSetting("Pause") then
		PlanRandomZoom()
	end
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
		PlanPath(idleZoom.saved, ZOOM_RESTORE_TIME, 0.5, "restore")
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
		allowed = ns.db.taxiZoom and not ns.orbit.settling
	elseif travel == "cozy" then
		allowed = ns.db.cozyZoom -- (cozy already means still, or walking weapon-drawn)
	elseif travel then
		allowed = ns.db[TRAVEL[travel].zoom]
		-- Zoomed yourself mid-walk: carry on from your new distance shortly after.
		if idleZoom.done and not idleZoom.active and now - lastCameraInput >= ns.db[TRAVEL[travel].pause] then
			idleZoom.done = false
		end
	else
		allowed = ns.db.idleZoom and still and not ns.IsZoomBlocked()
	end
	local want = cinematic and allowed and not InCombatLockdown()
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
			end
			if idleZoom.phase == "hold" and ZoomSetting("Random") then
				idleZoom.phase, idleZoom.t = "pause", 0
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
	-- Casting (crafting, say) is busy too. (The cozy camera keeps going: cooking
	-- at a campfire is still cozy.)
	local casting = ns.db.cameraPauseCasting
		and (ns.Flag(UnitCastingInfo("player")) or ns.Flag(UnitChannelInfo("player")))
	if onTaxi or active or atNPC or (casting and not ns.IsCozy()) then
		ns.stillSince = nil
	elseif not ns.stillSince then
		-- Stopping from the RP walk camera goes straight into the standing-still
		-- camera: its timer counts as already run (for the tint, tooltips and
		-- music too), so there's no gap between the two.
		ns.stillSince = walkHandoff and (now - ns.db.idleOrbitDelay) or now
		walkHandoff = false
	end
	-- Moving ends an emote.
	if ns.playerMoving or onTaxi then
		cozyEmote = nil
	end
	-- Cozy (campfire, emotes): no waiting; the standing-still timer counts as
	-- run, for the tint, tooltips and music too.
	local cozy = ns.IsCozy()
	if not cozy then
		cozySessionStarted = false -- the next cozy spell swings round afresh
	end
	if ns.stillSince and cozy and now - ns.stillSince < ns.db.idleOrbitDelay then
		ns.stillSince = now - ns.db.idleOrbitDelay
	end
	local idle = ns.db.idleOrbit and ns.stillSince ~= nil and now - ns.stillSince >= ns.db.idleOrbitDelay
	-- RP walk camera: only while actually moving in walk mode. Stop and stand,
	-- and it's the standing-still camera again (after its usual delay).
	-- Auto-running (not walking) gets the auto-run camera, set up the same way.
	local walking = not onTaxi and ns.IsRPWalking and ns.IsRPWalking()
	local autoRunning = not onTaxi and not walking and ns.IsAutoRunning and ns.IsAutoRunning()
	local travel = (walking and "walk") or (autoRunning and "run") or nil
	if travel == "walk" and ns.IsCozy() then
		travel = nil -- weapon drawn while walking: the cozy camera in front instead
	end
	local T = travel and TRAVEL[travel]
	if travel and cinematic then
		walkHandoff = true
	elseif onTaxi or (active and not travel and ns.playerMoving) then
		walkHandoff = false -- running or flying: the next stop starts the timer afresh
	end
	UpdateIdleZoom(cinematic, onTaxi, travel or (cozy and "cozy") or nil, now, elapsed)

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

	-- The player moving the camera pauses the orbit until cameraInputPause
	-- seconds after their last camera input, in flight and on foot.
	local adjusting = IsAdjustingCamera(now, (T and ns.db[T.pause]) or (cozy and ns.db.cozyInputPause) or nil)
	if adjusting then
		ns.orbit.newReference = true
	end

	-- A travel camera (auto-run, RP walk) doesn't start mid-turn: its line-up
	-- would swing the camera round with you. It waits until you've stopped
	-- turning for a moment. (Once running, turns are held and glided instead.)
	local turnBlocksStart = travel and ns.orbit.level == 0 and now - lastAnyTurnAt < TRAVEL_START_AFTER_TURN
	local want = cinematic and not adjusting and not InCombatLockdown() and not turnBlocksStart
		and ((onTaxi and ns.db.taxiOrbit and not ns.orbit.settling) or (travel and ns.db[T.orbit])
			or (cozy and ns.db.cozyOrbit and not ns.IsRotationBlocked())
			or (idle and not ns.IsRotationBlocked() and not (ns.db.indoorNoSweep and Indoors())))
	local prefix = onTaxi and "taxiOrbit" or ((travel and ns.db[T.orbit]) and T.orbit)
		or ((cozy and ns.db.cozyOrbit) and "cozyOrbit") or "idleOrbit"
	local footHandoff = ns.orbit.level > 0 and orbitPrefix ~= prefix
		and FOOT_ORBIT[orbitPrefix] and FOOT_ORBIT[prefix]
	if want and footHandoff then
		-- Standing still <-> RP walk: no stop and restart. The current move or
		-- pause plays out, and the next move follows on from where the camera
		-- is (for walking, that eases it back behind you).
		orbitPrefix = prefix
		ns.orbit.level = 1
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
	elseif want then
		if ns.orbit.level == 0 or orbitPrefix ~= prefix then
			-- Starting, or switching between flight and standing-still settings
			-- (taking off mid-rotation): begin afresh with the right profile.
			StopOrbitMove()
			orbitPrefix = prefix
			if ns.OnRotationStart then ns.OnRotationStart(prefix) end
			-- Start moving straight away, except while the takeoff swing is
			-- still bringing the camera round behind the character.
			local wait = onTaxi and math.max(0, (ns.orbit.centerUntil or 0) - now) or 0
			if LINEUP_ORBIT[prefix] then
				-- RP walk / auto-run starting (or picking up after you moved the
				-- camera): glide round behind you first, then sway from there.
				-- Auto-running well clear of any fight: a quicker line-up, so the
				-- travel camera gets going sooner.
				if prefix == "runOrbit" and now - lastCombatAt > CALM_AFTER_COMBAT then
					CenterCamera(CALM_CENTER_TIME, CALM_CENTER_YAW, CALM_CENTER_PITCH, CALM_CENTER_RAMP)
					wait = CALM_CENTER_TIME
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
		local stopTime = (adjusting or landed or (active and not onTaxi))
			and ORBIT_QUICK_STOP_TIME or ORBIT_STOP_TIME
		ns.orbit.level = ns.Approach(ns.orbit.level, 0, elapsed, stopTime)
	end
	if ns.orbit.level <= 0 then
		if yawExtra ~= 0 then
			-- No sway, but a turn to hold or glide: drive the yaw for that alone.
			StopAxis(ns.pitchAxis)
			ns.orbit.level, ns.orbit.continuous, ns.orbit.driftVel = 0, false, 0
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
		local ramp = math.min(1, ns.orbit.contT / CONTINUOUS_RAMP)
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
	local driftOn = (OrbitSetting("Drift") or ns.orbit.forceDrift) and not ns.orbit.noDrift
	local driftTarget = 0
	if driftOn then
		local positive
		if ns.orbit.phase == "move" then
			positive = ns.orbit.yawDelta > 0 -- carry on the way the move goes
		else
			positive = ns.orbit.driftPositive
		end
		driftTarget = OrbitSetting("DriftSpeed") * (positive and 1 or -1)
	end
	local driftStep = elapsed * math.max(1, OrbitSetting("DriftSpeed")) / DRIFT_RAMP
	local driftVel = ns.orbit.driftVel or 0
	if driftVel < driftTarget then
		driftVel = math.min(driftTarget, driftVel + driftStep)
	else
		driftVel = math.max(driftTarget, driftVel - driftStep)
	end
	ns.orbit.driftVel = driftVel

	local yawVel = driftVel -- signed degrees per second, before the level
	if ns.orbit.phase == "move" then
		local T = ns.orbit.sweepTime
		if ns.orbit.t >= T then
			StopAxis(ns.pitchAxis) -- the yaw carries on drifting
			-- Behind only always drifts a little after a move, drift setting or not.
			local startT = 0
			if ns.orbit.shortPauseNext then
				ns.orbit.shortPauseNext = false
				startT = math.max(0, OrbitSetting("Pause") - (orbitPrefix == "cozyOrbit" and 0 or HANDOFF_PAUSE))
			end
			BeginPause(startT, false, OrbitSetting("Mode") == "back")
		else
			-- Each axis: cruise = distance / (T * (1 - ease)), shaped by the ease curve.
			local ease = ns.orbit.ease or OrbitSetting("Ease")
			local shape = EaseShape(ns.orbit.t, T, ease) / (T * (1 - ease))
			yawVel = yawVel + ns.orbit.yawDelta * shape
			local pitchSpeed = ns.orbit.level * math.abs(ns.orbit.pitchDelta) * shape
			MoveAxis(ns.pitchAxis, pitchSpeed, ns.orbit.pitchDelta > 0)
			ns.orbit.pitch = ns.orbit.pitch + (ns.orbit.pitchDelta > 0 and pitchSpeed or -pitchSpeed) * elapsed
		end
	elseif ns.orbit.t >= OrbitSetting("Pause") then
		ns.orbit.phase, ns.orbit.t = "move", 0
		PlanNextSweep()
	end
	local yawSpeed = ns.orbit.level * yawVel
	DriveYaw(yawSpeed)
	ns.orbit.angle = WrapAngle(ns.orbit.angle + yawSpeed * elapsed)
end

-- Swing the camera back behind the character (flight start, and the
-- standing-still orbit in behind-only mode). There's no API to set the camera
-- angle, and SetView's blend is too quick and abrupt, so this borrows camera
-- following instead: for RECENTER_TIME seconds, follow is set to "Always" with
-- slowed swing speeds, so the camera eases round behind the character on its
-- own, then the player's follow settings are put back. Zoom is untouched.
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
ns.flight = {}           -- route, start for the flight in progress

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
	local duration = ns.flight.route and ns.db.flightTimes[ns.flight.route]
	if not duration then
		return nil
	end
	return duration - (GetTime() - ns.flight.start)
end

function ns.UpdateTaxi()
	local onTaxi = UnitOnTaxi("player")
	local now = GetTime()
	if onTaxi and not ns.wasOnTaxi then
		ns.orbit.angle, ns.orbit.pitch = 0, 0 -- assume the camera starts behind the character
		ns.orbit.settling = false
		if pendingRoute and now - pendingRouteAt < TAXI_PICK_WINDOW then
			ns.flight.route, ns.flight.start = pendingRoute, now
		end
		pendingRoute = nil
		-- Only the behind modes need the camera to start behind the character.
		if ns.db.enabled and ns.db.taxiCenter then
			CenterCamera()
			ns.orbit.centerUntil = now + RECENTER_TIME
		end
	elseif ns.wasOnTaxi and not onTaxi then
		if ns.flight.route then
			ns.db.flightTimes[ns.flight.route] = now - ns.flight.start
		end
		ns.flight.route = nil
		ns.orbit.settling = false
		if ns.OnLandedForBuffs then ns.OnLandedForBuffs() end
	end
	ns.wasOnTaxi = onTaxi

	-- Settle: shortly before a known landing, stop the rotation and swing the
	-- camera round behind the character. Camera follow is off during flights,
	-- so put it back first or the swing's settings would be undone.
	if onTaxi and not ns.orbit.settling and ns.db.enabled and ns.db.taxiSettle then
		local left = FlightTimeLeft()
		if left and left <= ns.db.taxiSettleLead then
			ns.orbit.settling = true
			ns.ApplyCVarSet(ns.FLIGHT_CVARS, false)
			CenterCamera()
		end
	end

	-- Moving on foot cancels a standing-still recenter; let the player steer.
	-- The travel line-up carries on while you walk or auto-run, but stops if
	-- you steer with the mouse or the travel mode ends.
	local traveling = (ns.IsRPWalking and ns.IsRPWalking()) or (ns.IsAutoRunning and ns.IsAutoRunning())
		or (ns.IsCozy and ns.IsCozy()) -- (the cozy camera lines up the same way)
	if travelRecenter then
		if not traveling or IsMouseOnCamera() then
			recenterUntil = 0
		end
	elseif not onTaxi and IsPlayerActive() then
		recenterUntil = 0
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
	ns.ApplyCVarSet(ns.FLIGHT_CVARS, (onTaxi and ns.db.enabled and ns.db.taxiOrbit and not recentering) or false)
end
