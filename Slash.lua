-- Cinematic: the /cine slash commands.
local _, ns = ...

-- What the commands print goes in the log too (/cine log), so troubleshooting
-- output can be sent in one paste. The help lists are left out.
local logPrints = true
local function print(...)
	if logPrints then
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		ns.Log("cmd", table.concat(parts, " "))
	end
	_G.print(...)
end

local function OnOff(value)
	return value and "|cff40ff40on|r" or "|cffff4040off|r"
end

local TOGGLES = {
	letterbox = { key = "letterbox", label = "Letterbox bars" },
	chat = { key = "fadeChat", label = "Fade chat" },
	cast = { key = "revealOnCast", label = "Reveal while casting" },
	music = { key = "musicInCinematic", label = "Play music in cinematic mode" },
	logoutmusic = { key = "musicOffOnLogout", label = "Turn music off on logout" },
	names = { key = "hideNames", label = "Hide names in cinematic mode" },
	plates = { key = "hidePlates", label = "Hide nameplates in cinematic mode" },
	tooltip = { key = "fadeTooltip", label = "Hide world tooltips" },
	orbit = { key = "taxiOrbit", label = "Flight camera sway" },
	flybys = { key = "taxiFlyBy", label = "Random fly-bys on flight paths" },
	flybylook = { key = "flyByLook", label = "/look as a fly-by starts" },
	idle = { key = "idleOrbit", label = "AFK camera sweep" },
	start = { key = "startCinematic", label = "Start in cinematic mode on login, /reload and turning it on" },
	combat = { key = "stayInCombat", label = "Stay in cinematic mode in combat" },
	npcs = { key = "revealAtNPCs", label = "Reveal at vendors, banks, mail and trainers" },
	minimap = { key = "alwaysShowMinimap", label = "Always show the minimap" },
	tracking = { key = "minimapForTracking", label = "Keep minimap open while tracking" },
	dungeons = { key = "offInDungeons", label = "Turn off in dungeons" },
	raids = { key = "offInRaids", label = "Turn off in raids" },
	pvp = { key = "offInPvP", label = "Turn off in battlegrounds and arenas" },
	cities = { key = "offInCities", label = "Turn off in cities" },
	inns = { key = "offInInns", label = "Turn off in inns" },
	party = { key = "offInParty", label = "Turn off in a party" },
	raidgroup = { key = "offInRaidGroup", label = "Turn off in a raid group" },
	center = { key = "taxiCenter", label = "Swing round behind you at takeoff" },
	settle = { key = "taxiSettle", label = "Lock the camera behind you before landing" },
	flight = { key = "taxiInstant", label = "Start cinematic mode as soon as you take off" },
	chatpeek = { key = "chatPeek", label = "Show chat when a message arrives" },
	citychat = { key = "chatInCities", label = "Keep chat visible in cities" },
	innchat = { key = "chatInInns", label = "Keep chat visible in inns" },
	dungeonchat = { key = "chatInDungeons", label = "Keep chat visible in dungeons" },
	raidchat = { key = "chatInRaids", label = "Keep chat visible in raids" },
	pvpchat = { key = "chatInPvP", label = "Keep chat visible in battlegrounds and arenas" },
	mouseover = { key = "mouseover", label = "Mouseover reveal" },
	timetitle = { key = "timeOfDayMessage", label = "Show the time of day" },
	windows = { key = "stayWithWindows", label = "Stay in cinematic mode when opening windows" },
	walkcam = { key = "walkOrbit", label = "RP walk camera" },
	autoruncam = { key = "runOrbit", label = "Auto-run camera" },
	cozy = { key = "cozyOrbit", label = "Cozy camera" },
	vista = { key = "vistaOrbit", label = "Vista camera" },
	fish = { key = "fishOrbit", label = "Fish camera" },
	death = { key = "deathOrbit", label = "Death camera" },
	deathsong = { key = "deathSong", label = "Death song" },
	musicpause = { key = "musicPauseWhenMoving", label = "Pause music when you move on" },
	landingpause = { key = "musicPauseOnLanding", label = "Pause music when a flight lands" },
	indoor = { key = "indoorLimits", label = "Limit the camera indoors" },
	combattext = { key = "hideCombatText", label = "Hide combat text out of combat" },
	drag = { key = "revealOnDrag", label = "Bring the UI back while dragging something" },
}

local function Heading(text)
	print("|cffffd100" .. text .. "|r")
end

local function PrintHelp()
	logPrints = false
	ns.Print("commands")
	Heading("General")
	print("  /cine - toggle cinematic mode (also /cine on, /cine off)")
	print("  /cine config - open the settings")
	print("  /cine delay <seconds> - calm time before fading (now " .. ns.db.delay .. ")")
	print("  /cine size <percent> - letterbox bar height (now " .. ns.db.letterboxSize * 100 .. "%)")
	print("  /cine button - show or hide the minimap button")
	print("  /cine reset - restore the default settings")
	Heading("Frames (hover over one first)")
	print("  /cine add - fade it too")
	print("  /cine keep - always show it")
	print("  /cine list - show the extra faded frames")
	Heading("Camera")
	print("  /cine behind - swing the camera back behind your character")
	print("  /cine flyby - turn the camera slowly round to look back, then back behind you (again to stop)")
	print("  /cine walk - does the addon think you're walking or auto-running?")
	print("  /cine walk flip - fix it if it has walk and run backwards")
	Heading("Switches: /cine <name> turns one on or off")
	local names = {}
	for cmd in pairs(TOGGLES) do names[#names + 1] = cmd end
	table.sort(names)
	for _, cmd in ipairs(names) do
		local toggle = TOGGLES[cmd]
		print("  " .. cmd .. " - " .. toggle.label .. " (" .. OnOff(ns.db[toggle.key]) .. ")")
	end
	Heading("More")
	print("  /cine debug help - troubleshooting commands")
	print("  /cine log - copy the log and your setup for a bug report (/cine log clear empties it)")
	print("  /cine panic - stop for this session and put your UI and settings back (/cine resume to restart)")
	print("  Keybinds (toggle, hold-to-peek, hide the UI, fly-by) are on the Keybinds settings page.")
	logPrints = true
end

local function PrintDebugHelp()
	ns.Print("troubleshooting commands")
	logPrints = false
	print("  /cine log - copy the log for a bug report: what's printed below goes in it too")
	print("  /cine debug record - also log game setting changes and music in detail (again to stop)")
	print("  /cine debug mode - which camera mode it thinks you're in")
	print("  /cine debug modes - print each camera mode change to chat (again to stop)")
	print("  /cine debug emote - the last emote the game passed, and whether cozy or vista took it")
	print("  /cine debug fishing - the last red error message, and whether it paused right-click casting")
	print("  /cine debug weapon - what the game says about your weapon, and the cozy weapon trigger")
	print("  /cine debug quest - the quest cam: on or off, its zoom and the over-the-shoulder offset")
	print("  /cine debug questlog - save every frame of the next quest cams (for tracking down snaps)")
	print("  /cine debug zoom - the slow zoom's state")
	print("  /cine debug turn - turn handling while walking (8 seconds)")
	print("  /cine debug ambience - ambience volume and what it follows")
	print("  /cine debug plates - nameplate settings, and how the plates (and your target) are sorted")
	print("  /cine debug weather - the weather the game reports and the weather tint")
	print("  /cine debug flight - the flight route, its known time and when the camera settles")
	print("  /cine debug orbit - the camera rotation's state")
	print("  /cine debug flyby - the fly-by's state and the random ones planned")
	print("  /cine debug flybys - print each fly-by's start and end, random ones too (again to stop)")
	print("  /cine debug death - print what the death camera does on real deaths (again to stop)")
	print("  /cine debug place - city, inn, dungeon detection")
	print("  /cine debug portrait - the portrait-until-full rule")
	print("  /cine debug tracking - which tracking is active")
	print("  /cine debug tooltip - trace the world tooltip hold-back (10 seconds)")
	print("  /cine debug <group> - faded frames in a group (hover first; default minimap)")
	print("  /cine speed - your speed, two ways")
	print("  /cine facing - whether turning can be detected (10 seconds)")
	print("  /cine turntest <degrees> <speed> - turn the camera a set amount")
	print("  /cine starttest gentle|tilt|setting|share|steady|nomove - one slow move, to find what snaps as it starts")
	print("  /cine restarttest [speed] - turn for 4 seconds, re-sending the turn every 0.1 sec")
	print("  /cine turnhold - hold the view while you turn on the spot (10 seconds)")
	print("  /cine deathtest [seconds] - act as if you'd died, for the death camera (30; again to stop)")
	print("  /cine zoomtest, drifttest, pitchtest - camera movement tests")
	print("  /cine doftest [seconds|strength <0-100>] - show the depth-of-field edge haze (30; again to stop)")
	print("  /cine timetest [name] - show the time-of-day change title now (all: each in turn)")
	print("  /cine soundtest <id> - play a game sound by its ID (stops after 10 seconds)")
	print("  /cine songtest [file ID] - play a random death song, or any music file (again to stop)")
	logPrints = true
end

function ns.HandleSlash(msg)
	local cmd, arg = msg:lower():match("^%s*(%S*)%s*(.-)%s*$")
	local num = tonumber(arg)
	if cmd ~= "log" then
		ns.Log("cmd", "/cine " .. msg)
	end

	if cmd == "log" then
		if arg == "clear" then
			ns.ClearLog()
			ns.Print("log cleared")
		else
			ns.ShowLog()
		end
	elseif cmd == "panic" then
		if ns.IsSuspended() then
			ns.Print("already stopped: /cine resume starts it again")
		else
			ns.Suspend("/cine panic")
		end
	elseif cmd == "resume" then
		ns.Print(ns.Resume() and "started again" or "isn't stopped")
	elseif cmd == "debug" and arg == "record" then
		ns.db.logDetail = not ns.db.logDetail
		ns.Print("detailed logging (game settings, music): " .. OnOff(ns.db.logDetail) ..
			(ns.db.logDetail and ". Reproduce the problem, then /cine log." or ""))
	elseif cmd == "" or cmd == "toggle" then
		Cinematic_Toggle()
	elseif cmd == "config" or cmd == "options" then
		ns.OpenOptions()
	elseif cmd == "on" or cmd == "off" then
		ns.SetEnabled(cmd == "on")
		ns.Print(ns.db.enabled and "enabled" or "disabled")
		if ns.IsSuspended() then
			ns.Print("(still stopped after an error: /cine resume starts it again)")
		end
	elseif cmd == "delay" and num and num >= 0 then
		ns.db.delay = num
		ns.Print("fade delay set to " .. num .. "s")
	elseif cmd == "size" and num and num >= 0 and num <= 40 then
		ns.db.letterboxSize = num / 100
		ns.letterboxDirty = true
		ns.Print("letterbox size set to " .. num .. "%")
	elseif TOGGLES[cmd] then
		local toggle = TOGGLES[cmd]
		ns.db[toggle.key] = not ns.db[toggle.key]
		ns.Print(toggle.label .. ": " .. OnOff(ns.db[toggle.key]))
	elseif cmd == "add" then
		ns.AddUnderMouse()
	elseif cmd == "remove" or cmd == "keep" then
		ns.RemoveUnderMouse()
	elseif cmd == "button" then
		ns.ToggleMinimapButton()
	elseif cmd == "behind" then
		-- Glide to Blizzard's default view (behind, level) in saved view slot 5,
		-- then put the zoom back once the glide settles.
		local zoom = GetCameraZoom and GetCameraZoom()
		ResetView(5)
		SetView(5)
		if zoom then
			C_Timer.After(1.5, function()
				local diff = zoom - GetCameraZoom()
				if diff > 0.1 then
					CameraZoomOut(diff)
				elseif diff < -0.1 then
					CameraZoomIn(-diff)
				end
			end)
		end
	elseif cmd == "starttest" then
		local ok, why = ns.QuestCamStartTest(arg)
		if ok then
			ns.Print(("start test (%s): stand still and watch the camera; it starts moving in a second"):format(arg))
		else
			ns.Print("start test: " .. why)
		end
	elseif cmd == "turntest" then
		-- Turns the camera a set number of degrees at a steady speed (default 30
		-- deg/sec) using the same speed conversion as the orbit, to check that it's
		-- accurate. /cine turntest 180 135 turns half round at turn-key speed.
		local degrees, speed = arg:match("^(%S+)%s*(%S*)$")
		degrees, speed = tonumber(degrees) or 90, tonumber(speed) or 30
		local yawSpeed = tonumber(GetCVar("cameraYawMoveSpeed")) or 180
		ns.Print(("turning %d degrees left at %d°/sec (cameraYawMoveSpeed = %s)"):format(degrees,
			speed, tostring(GetCVar("cameraYawMoveSpeed"))))
		MoveViewLeftStart(speed / yawSpeed)
		C_Timer.After(degrees / speed, function() MoveViewLeftStop() end)
	elseif cmd == "flyby" then
		Cinematic_FlyBy()
	elseif cmd == "debug" and arg == "flybys" then
		ns.db.debugFlyBy = not ns.db.debugFlyBy
		ns.Print("fly-by messages " .. (ns.db.debugFlyBy and
			"on: each fly-by's plan, start and end, random ones too (again to stop)" or "off"))
	elseif cmd == "debug" and arg == "flyby" then
		local d = ns.GetFlyByDebug()
		if d.active then
			ns.Print(("fly-by on: %s, %.1f of %.1f sec, view %.0f° from behind you"):format(
				d.phase, d.t, d.T, d.view))
		else
			ns.Print("fly-by off")
		end
		local planned = {}
		for _, slot in ipairs(d.planned) do
			planned[#planned + 1] = ("in %d sec"):format(math.max(0, slot.at - GetTime()))
		end
		ns.Print("random fly-bys (" .. (ns.db.taxiFlyBy and "on" or "off") .. "): " ..
			(#planned > 0 and table.concat(planned, ", ") or "none planned"))
	elseif cmd == "restarttest" then
		-- Like turntest, but the turn is re-sent at the same speed every 0.1 sec
		-- (as a fly-by does to change speed), to see whether restarting the
		-- camera's turn shows as a jump. /cine restarttest [degrees/sec], 4 sec.
		local speed = num or 40
		local yawSpeed = tonumber(GetCVar("cameraYawMoveSpeed")) or 180
		ns.Print(("turning left at %d°/sec for 4 sec, restarting the turn every 0.1 sec"):format(speed))
		local sends = 0
		local function Send()
			sends = sends + 1
			if sends > 40 then
				MoveViewLeftStop()
				ns.Print("restart test over")
				return
			end
			MoveViewLeftStart(speed / yawSpeed)
			C_Timer.After(0.1, Send)
		end
		Send()
	elseif cmd == "turnhold" then
		-- For 10 seconds, the turn follow runs even standing still: hold a turn key
		-- and the camera should stay pointing the same way while you spin.
		ns.turnTestUntil = GetTime() + 10
		ns.Print("turn hold test for 10 seconds: stand still and hold a turn key. The camera " ..
			"should keep looking the same way while your character turns.")
	elseif cmd == "debug" and arg == "modes" then
		ns.db.debugCameraMode = not ns.db.debugCameraMode
		ns.ResetCameraModeReport() -- print the current mode straight away
		ns.Print("print camera mode changes to chat: " .. OnOff(ns.db.debugCameraMode))
	elseif cmd == "debug" and arg == "death" then
		ns.deathDebug = not ns.deathDebug
		ns.Print("death camera log on real deaths: " .. OnOff(ns.deathDebug) .. " (until you /reload)")
	elseif cmd == "debug" and arg == "music" then
		ns.musicDebug = not ns.musicDebug
		ns.Print("music log: " .. OnOff(ns.musicDebug) .. " (until you /reload)")
	elseif cmd == "songtest" then
		-- Plays a music file in place of the zone music: the death song, or any
		-- music file ID. Run it again (with no ID) to stop.
		if ns.songTestPlaying and not num then
			StopMusic()
			ns.songTestPlaying = false
			ns.Print("song stopped")
		else
			local file = num or ns.PickDeathSong()
			ns.songTestPlaying = pcall(PlayMusic, file)
			ns.Print(("playing music file %s%s. /cine songtest again stops it."):format(tostring(file),
				GetCVar("Sound_EnableMusic") == "1" and "" or " (game music is off, so you won't hear it)"))
		end
	elseif cmd == "deathtest" then
		-- Pretends you're dead (default 30 seconds) so the death camera runs, delay
		-- and all. Running it again while it's going stops it.
		if GetTime() < (ns.deathTestUntil or 0) then
			ns.deathTestUntil = 0
			ns.Print("death camera test stopped")
		elseif not ns.db.deathOrbit then
			ns.Print("the death camera is off: turn it on with /cine death first")
		else
			local seconds = num or 30
			ns.deathTestUntil = GetTime() + seconds
			ns.Print(("death camera test for %d seconds: stand still and it starts after %.1f sec. " ..
				"/cine deathtest again stops it."):format(seconds, ns.db.deathOrbitDelay))
		end
	elseif cmd == "debug" and arg == "fishing" then
		local e = ns.fishErrorDebug
		if not e or not e.message then
			ns.Print("No error message seen since loading in.")
		else
			ns.Print(("Last error (%d sec ago, from the %s): \"%s\" - %s"):format(GetTime() - e.at, e.via,
				e.message, e.taken == "miss" and "missed the water: right-click casting paused"
				or e.taken == "skill" and "skill too low: right-click casting off for 30 sec"
				or "not a fishing error"))
		end
	elseif cmd == "debug" and arg == "emote" then
		-- What the last emote passed to the game, and whether the cozy camera took it.
		local e = ns.lastEmote
		if not e then
			ns.Print("no emote seen since login (the emote hook may not be firing)")
		else
			ns.Print(("last emote: %s (caught by %s), %.0f sec ago"):format(e.token, e.via, GetTime() - e.at))
		end
		local event, camera, wait = ns.GetEventDebug()
		ns.Print(event and ("event now: %s -> %s camera%s"):format(event, camera,
			wait > 0 and (", starts in %d sec"):format(math.ceil(wait)) or "")
			or "event now: none (or set to no camera)")
		local d = ns.seatDebug
		if d then
			ns.Print(("last right-click %.0f sec ago: world tooltip was \"%s\" (%.1f sec before), seat word match: %s"):format(
				GetTime() - d.at, tostring(d.name), d.nameAge, tostring(d.seat)))
		else
			ns.Print("no right-click seen since login")
		end
	elseif cmd == "eventtest" then
		-- Records which game events fire over the next 8 seconds (sit in a chair
		-- meanwhile), leaving out the constant background ones, then lists them.
		local NOISY = {
			COMBAT_LOG_EVENT_UNFILTERED = true, UNIT_AURA = true, UNIT_POWER_UPDATE = true,
			UNIT_POWER_FREQUENT = true, UNIT_HEALTH = true, CURSOR_CHANGED = true,
			UPDATE_MOUSEOVER_UNIT = true, NAME_PLATE_UNIT_ADDED = true, NAME_PLATE_UNIT_REMOVED = true,
			CHAT_MSG_CHANNEL = true, UNIT_THREAT_LIST_UPDATE = true, ACTIONBAR_UPDATE_COOLDOWN = true,
			SPELL_UPDATE_COOLDOWN = true, BAG_UPDATE_COOLDOWN = true, UNIT_COMBAT = true,
			CVAR_UPDATE = true, WORLD_CURSOR_TOOLTIP_UPDATE = true, MODIFIER_STATE_CHANGED = true,
		}
		local seen, order = {}, {}
		local probe = ns.eventProbe or CreateFrame("Frame")
		ns.eventProbe = probe
		local started = GetTime()
		probe:SetScript("OnEvent", function(_, event, arg1)
			if NOISY[event] then return end
			if not seen[event] then
				seen[event] = { count = 0, first = GetTime() - started, arg = tostring(arg1) }
				order[#order + 1] = event
			end
			seen[event].count = seen[event].count + 1
		end)
		probe:RegisterAllEvents()
		ns.Print("event test for 8 seconds: sit in a chair now.")
		C_Timer.After(8, function()
			probe:UnregisterAllEvents()
			ns.Print(("event test done: %d kinds of event"):format(#order))
			for _, event in ipairs(order) do
				local e = seen[event]
				print(("  %.1fs %s x%d (first arg: %s)"):format(e.first, event, e.count, e.arg))
			end
		end)
	elseif cmd == "slopetest" then
		-- Compares your movement speed with how fast you actually cross the
		-- map, every half second for 12 seconds: run on the flat, then up or down
		-- a steep hill. If slopes slow your progress across the map, the % drops.
		local function Pos()
			local ok, y, x = pcall(UnitPosition, "player")
			if ok and type(y) == "number" and not (issecretvalue and issecretvalue(y)) then
				return x, y
			end
		end
		local lastX, lastY = Pos()
		if not lastX then
			ns.Print("slope test: position not available here")
			return
		end
		ns.Print("slope test for 12 seconds: run on the flat, then up and down a steep hill.")
		local ticks = 0
		local ticker
		ticker = C_Timer.NewTicker(0.5, function()
			ticks = ticks + 1
			local x, y = Pos()
			local speed = ns.GetPlayerSpeed()
			if x and speed and speed > 0 then
				local across = math.sqrt((x - lastX) ^ 2 + (y - lastY) ^ 2) / 0.5
				print(("  speed %.1f, across the map %.1f yards/sec (%d%%)"):format(speed, across,
					across / speed * 100 + 0.5))
			end
			lastX, lastY = x or lastX, y or lastY
			if ticks >= 24 then
				ticker:Cancel()
				ns.Print("slope test done.")
			end
		end)
	elseif cmd == "elevation" then
		-- Can the addon read your height? Prints your position now and again
		-- after 5 seconds (jump, climb or fly meanwhile to see if it changes).
		local function Report(label)
			local ok, y, x, z, instance = pcall(UnitPosition, "player")
			if not ok then
				ns.Print(label .. ": UnitPosition gave an error")
			elseif y == nil then
				ns.Print(label .. ": position hidden here (instances hide it)")
			elseif issecretvalue and (issecretvalue(y) or issecretvalue(z)) then
				ns.Print(label .. ": position is secret")
			else
				ns.Print(("%s: x %.1f, y %.1f, height %s (instance %s)"):format(label, x, y,
					z == nil and "none" or ("%.2f"):format(z), tostring(instance)))
			end
		end
		Report("now")
		ns.Print("jump, climb a hill or fly for 5 seconds...")
		C_Timer.After(5, function() Report("5 sec later") end)
	elseif cmd == "soundtest" then
		-- Plays a game sound by its ID (Wowhead's sound=ID), stopping it after 10
		-- seconds in case it loops. /cine soundtest stops one that's playing.
		if ns.testSound then
			StopSound(ns.testSound)
			ns.testSound = nil
		end
		if num then
			local ok, willPlay, handle = pcall(PlaySound, num, "SFX")
			if ok and willPlay then
				ns.testSound = handle
				ns.Print("playing sound " .. num)
				C_Timer.After(10, function()
					if ns.testSound == handle then
						StopSound(handle)
						ns.testSound = nil
					end
				end)
			else
				ns.Print("sound " .. num .. " didn't play (not a sound ID on this client?)")
			end
		end
	elseif cmd == "doftest" then
		-- Faked depth of field: /cine doftest shows it now (a number sets how
		-- long; again stops it). /cine doftest strength 20 shows it at 20%, to
		-- compare values (the camera pages set the real ones).
		local strength = arg:match("^strength%s+(%d+)$")
		if strength then
			ns.FocusDemo(nil, tonumber(strength) / 100)
			ns.Print(("showing depth of field at %d%% for 30 seconds"):format(
				math.floor(ns.FocusDemoStrength() * 100 + 0.5)))
		elseif arg ~= "" and not num then
			ns.Print("/cine doftest [seconds|strength <0-100>]")
		elseif ns.FocusDemo(num) then
			ns.Print(("showing depth of field at %d%% for %d seconds. /cine doftest again stops it."):format(
				math.floor(ns.FocusDemoStrength() * 100 + 0.5), num or 30))
		else
			ns.Print("depth of field demo stopped")
		end
	elseif cmd == "timetest" then
		-- Shows the time-of-day change title now; /cine timetest dusk shows "Dusk".
		if arg == "all" then
			-- Each time of day in turn, one after the other finishes.
			local phases = { "Dawn", "Morning", "Midday", "Afternoon", "Evening", "Dusk", "Night" }
			ns.Print("showing every time of day, 8 seconds each")
			for i, phase in ipairs(phases) do
				C_Timer.After((i - 1) * 8, function() ns.TestTimeChangeTitle(phase) end)
			end
			return
		end
		local text = arg ~= "" and (arg:gsub("^%l", string.upper)) or nil
		ns.TestTimeChangeTitle(text)
	elseif cmd == "debug" and arg == "tooltip" then
		-- Traces the world tooltip hold-back for 10 seconds (hover a herb meanwhile).
		ns.tooltipTrace = { started = GetTime() }
		ns.Print(("tooltip trace for 10 seconds: hover the thing now (reveal %s, after %.1f sec)."):format(
			OnOff(ns.db.tooltipReveal), ns.db.tooltipRevealDelay or 0))
		C_Timer.After(10, function()
			local log = ns.tooltipTrace
			ns.tooltipTrace = nil
			ns.Print(("tooltip trace done: %d entries"):format(#log))
			for _, line in ipairs(log) do
				print("  " .. line)
			end
		end)
	elseif cmd == "debug" and arg == "weapon" then
		local w = ns.GetWeaponDebug()
		ns.Print(("weapon: GetSheathState %s, returned %s (1 sheathed, 2 melee, 3 ranged); drawn %s, drawn calmly %s; cozy now %s, weapon event camera %s"):format(
			w.exists and "exists" or "MISSING", w.state, tostring(w.drawn), tostring(w.calm),
			tostring(w.cozy), tostring(ns.db.eventWeaponCamera)))
	elseif cmd == "debug" and arg == "questlog" then
		ns.db.debugQuestCam = not ns.db.debugQuestCam
		ns.Print("quest cam log " .. (ns.db.debugQuestCam and
			"on: each quest cam's frames are saved; /reload after one so they can be read (again to stop)"
			or "off"))
	elseif cmd == "debug" and arg == "quest" then
		local q = ns.GetQuestCamDebug()
		ns.Print(("quest cam: %s, event camera %s; turned %.1f°, lowered %.1f°%s; your distance %s, zoomed to %s; shoulder %s (ours %s), Keep Character Centered %s"):format(
			q.active and "on" or (q.talking and "waiting") or "off", tostring(ns.db.eventQuestCamera), q.turned, q.lowered, q.handedOver and " (handed over to you)" or "", tostring(q.zoom), tostring(q.zoomedTo),
			tostring(q.shoulder), tostring(q.shoulderOn), tostring(q.centered)))
	elseif cmd == "debug" and arg == "help" then
		PrintDebugHelp()
	elseif cmd == "debug" and arg == "zoom" then
		local zoom = ns.GetZoomDebug()
		ns.Print(("camera distance now: %.2f, zoom speed: %s, max factor: %s"):format(
			GetCameraZoom(), tostring(GetCVar("cameraZoomSpeed")),
			tostring(GetCVar("cameraDistanceMaxZoomFactor"))))
		ns.Print(("zoom (%s) active: %s, started from: %s, phase: %s, planned change: %s"):format(
			tostring(zoom.context), tostring(zoom.active), zoom.saved and ("%.2f"):format(zoom.saved) or "-",
			tostring(zoom.phase), zoom.delta and ("%.2f"):format(zoom.delta) or "-"))
		ns.Print(("done: %s (%s), step %.1f of %.1f sec, cinematic: %s, RP walking: %s, walk zoom option: %s, last camera input %.1f sec ago"):format(
			tostring(zoom.done), tostring(zoom.doneContext), zoom.t or 0, zoom.duration or 0,
			tostring(ns.lastCinematic), tostring(ns.IsRPWalking and ns.IsRPWalking()),
			tostring(ns.db.walkZoom), GetTime() - (ns.GetLastCameraInput and ns.GetLastCameraInput() or 0)))
	elseif cmd == "debug" and arg == "turn" then
		-- Prints the RP walk turn handling four times a second for 8 seconds:
		-- walk, then turn with the keys while walking.
		ns.Print("turn debug for 8 seconds: walk, then turn with the keys.")
		local ticks = 0
		local ticker
		ticker = C_Timer.NewTicker(0.25, function()
			ticks = ticks + 1
			local d = ns.GetTurnDebug()
			local ok, facing = pcall(GetPlayerFacing)
			local line = (("walking %s, keys %s, facing %s | offset %.0f°, extra %.0f°/s, glide %.0f | camera turning %s | follow off %s (style %s), yaw speed cvar %s"):format(
				tostring(ns.IsRPWalking and ns.IsRPWalking()), d.keys ~= "" and d.keys or "-",
				(ok and type(facing) == "number") and ("%.0f°"):format(math.deg(facing)) or "?",
				d.offset, d.extra, d.glide, d.axis, tostring(d.followOff), tostring(d.smoothStyle),
				tostring(d.yawSpeed)))
			ns.Print(line)
			if ticks >= 32 then
				ticker:Cancel()
				ns.Print("turn debug done.")
			end
		end)
	elseif cmd == "debug" and arg == "flight" then
		local f = ns.GetFlightDebug()
		local function s(v) return v and ("%.0fs"):format(v) or "-" end
		if not f.hooked then
			ns.Print("flight: this client has no TakeTaxiNode, so routes can't be noted")
		end
		if f.talent then
			ns.Print("flight: Frequent Flier is learned, so flights are timed 20% faster")
		end
		if f.scale ~= 1 then
			ns.Print(("flight: flights take %d%% of their first timed length (sped up or slowed since)"):format(
				f.scale * 100 + 0.5))
		end
		if f.pending then
			ns.Print(("flight: noted %s %s ago, waiting for takeoff"):format(f.pending, s(f.pendingAge)))
		end
		if f.onTaxi then
			ns.Print(("flight: route %s, %s in, known time %s, left %s, settle at %s left (%s)"):format(
				f.route or "unknown (not noted at the flight master)", s(f.elapsed),
				s(f.known), s(f.left),
				s(ns.db.taxiSettleLead), f.settling and "settling now"
					or not ns.db.taxiSettle and "settle is off"
					or not f.route and "can't settle: no route"
					or not f.known and "can't settle: first time on this route, timing it"
					or "waiting"))
		elseif not f.pending then
			ns.Print("flight: not flying. Talk to a flight master and pick a destination, then try again.")
		end
	elseif cmd == "debug" and arg == "weather" then
		local w = ns.GetWeatherDebug()
		local function rgb(c) return ("%.2f %.2f %.2f"):format(c[1], c[2], c[3]) end
		if not w.api then
			ns.Print("weather: this client has no C_Weather")
		elseif w.error then
			ns.Print("weather: C_Weather.GetCurrentWeather gave an error")
		elseif w.secret then
			ns.Print("weather: the values are secret here")
		else
			ns.Print(("weather: type %s (%s), intensity %s, indoors %s"):format(tostring(w.kind),
				w.kindName or "unknown", tostring(w.intensity), tostring(w.indoors)))
		end
		ns.Print(("weather tint: %s, aiming for %s, showing %s"):format(
			ns.GetDB().weatherTint and "on" or "off", rgb(w.target), rgb(w.shown)))
	elseif cmd == "debug" and arg == "plates" then
		ns.PrintPlatesDebug()
	elseif cmd == "debug" and arg == "ambience" then
		local a = ns.GetAmbienceDebug()
		local function n(v) return v and ("%.2f"):format(tonumber(v) or 0) or "-" end
		ns.Print(("ambience: active=%s level=%s, your level=%s (saved %s), volume now=%s (written %s, target glide %s)"):format(
			tostring(a.active), n(a.level), n(a.original), n(a.saved), n(a.cvar), n(a.written), n(a.current)))
		ns.Print(("music: full volume=%s, playing share=%s, reload hold=%.0fs"):format(
			n(a.musicVolume), n(a.presence), a.hold))
	elseif cmd == "facing" then
		-- Test: can the addon tell when you turn? For 10 seconds, reports the
		-- turning events, the turn keys, and your facing direction.
		local function Facing()
			local ok, facing = pcall(GetPlayerFacing)
			if not ok then return "error" end
			if facing == nil then return "hidden" end
			if issecretvalue and issecretvalue(facing) then return "secret" end
			return ("%.0f°"):format(math.deg(facing))
		end
		ns.Print("facing test for 10 seconds: turn with the keys, then with the mouse. Facing now: " .. Facing())
		local watcher = ns.facingWatcher
		if not watcher then
			watcher = CreateFrame("Frame")
			ns.facingWatcher = watcher
			for _, event in ipairs({ "PLAYER_STARTED_TURNING", "PLAYER_STOPPED_TURNING" }) do
				pcall(watcher.RegisterEvent, watcher, event)
			end
			watcher:SetScript("OnEvent", function(_, event)
				if watcher.active then
					ns.Print(("%s (facing %s)"):format(event == "PLAYER_STARTED_TURNING" and "started turning"
						or "stopped turning", Facing()))
				end
			end)
			for _, name in ipairs({ "TurnLeftStart", "TurnRightStart" }) do
				if _G[name] then
					hooksecurefunc(name, function()
						if watcher.active then ns.Print(name .. " (turn key pressed)") end
					end)
				end
			end
		end
		watcher.active = true
		C_Timer.After(10, function()
			watcher.active = false
			ns.Print("facing test over. Facing now: " .. Facing())
		end)
	elseif cmd == "speed" then
		-- Test: can the addon read your speed? The direct API, then speed worked
		-- out from your position half a second apart.
		local ok, speed = pcall(GetUnitSpeed, "player")
		if not ok then
			ns.Print("GetUnitSpeed: error")
		elseif issecretvalue and issecretvalue(speed) then
			ns.Print("GetUnitSpeed: secret (can't be read)")
		else
			ns.Print(("GetUnitSpeed: %.2f yards/sec"):format(speed or 0))
		end
		local function Position()
			local okPos, y, x = pcall(UnitPosition, "player")
			if not okPos or y == nil or (issecretvalue and (issecretvalue(y) or issecretvalue(x))) then
				return nil
			end
			return x, y
		end
		local x1, y1 = Position()
		if not x1 then
			ns.Print("UnitPosition: not available here (instances hide it, or it's secret)")
			return
		end
		C_Timer.After(0.5, function()
			local x2, y2 = Position()
			if not x2 then
				ns.Print("UnitPosition: stopped answering")
				return
			end
			local distance = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
			ns.Print(("measured from position: %.2f yards/sec (walking is about 2.5, running 7)"):format(
				distance / 0.5))
		end)
	elseif cmd == "walk" then
		-- /cine walk: what the addon thinks. /cine walk flip: fix it when it's
		-- out of step with the game (say, after a reload while walking).
		if arg == "flip" then
			ns.walking = not ns.walking
		end
		if ns.IsRPWalking then ns.IsRPWalking() end -- refresh from your speed if moving
		local state
		if not ns.walking then
			state = "running (walk mode off)"
		elseif ns.playerMoving and ns.MovingManually and ns.MovingManually() then
			state = "walking by hand - no RP walk camera (auto-walk for it)"
		elseif ns.playerMoving then
			state = "auto-walking - RP walk camera " .. (ns.db.walkOrbit and "on" or "switched off in settings")
		else
			state = "walk mode on, standing still"
		end
		local speed = ns.GetPlayerSpeed()
		local source = (ns.playerMoving and ns.walkingFromSpeed)
			and (" (from your speed: %.1f yards/sec)"):format(speed or 0)
			or " (from the walk/run key)"
		ns.Print("the addon thinks you're " .. state .. source ..
			(arg == "flip" and "." or ". Wrong? Type /cine walk flip."))
		ns.Print("auto-run: " .. (ns.autoRunning and "on" or "off") ..
			((ns.IsAutoRunning and ns.IsAutoRunning()) and " (auto-run camera)" or
				(ns.autoRunning and ns.walking and " (walking, so RP walk camera)" or "")))
	elseif cmd == "debug" and arg == "mode" then
		-- Which camera situation the addon thinks you're in.
		local still = ns.GetStillSince()
		local mode
		if UnitOnTaxi("player") then
			mode = "flight"
		elseif ns.walking and ns.playerMoving then
			mode = "walking (RP walk camera)"
		elseif ns.IsAutoRunning and ns.IsAutoRunning() then
			mode = "auto-running (auto-run camera)"
		elseif ns.IsVista and ns.IsVista() then
			mode = "vista (/stare)"
		elseif ns.IsFish and ns.IsFish() then
			mode = "fish (fishing)"
		elseif ns.IsCozy and ns.IsCozy() then
			mode = "cozy (campfire or emote)"
		elseif ns.playerMoving then
			mode = "running"
		elseif still then
			local left = ns.db.idleOrbitDelay - (GetTime() - still)
			mode = left > 0 and ("standing still, AFK camera in %d sec"):format(math.ceil(left))
				or "standing still (AFK camera)"
		else
			mode = "moving the camera"
		end
		ns.Print(("camera mode: %s; walk mode %s"):format(mode, ns.walking and "on" or "off"))
	elseif cmd == "zoomtest" then
		-- Zooms out by N yards (default 6) over 10 seconds with the same tiny
		-- per-frame steps the slow zoom uses, then reports how far it really went.
		local yards = num or 6
		local start = GetCameraZoom()
		local elapsedTotal, sent = 0, 0
		ns.Print(("zoom test: out %d yards over 10 sec, starting at %.2f"):format(yards, start))
		local tester = CreateFrame("Frame")
		tester:SetScript("OnUpdate", function(self, elapsed)
			elapsedTotal = elapsedTotal + elapsed
			local step = math.min(yards - sent, yards / 10 * elapsed)
			if step > 0 then
				CameraZoomOut(step)
				sent = sent + step
			end
			if elapsedTotal >= 11 then
				self:SetScript("OnUpdate", nil)
				ns.Print(("zoom test done: asked for %.2f yards, camera moved %.2f (now %.2f)"):format(
					sent, GetCameraZoom() - start, GetCameraZoom()))
			end
		end)
	elseif cmd == "drifttest" then
		-- Turns the camera at a slow drift speed (default: the flight drift speed)
		-- for 10 seconds, to check the game doesn't ignore very slow camera turns.
		local speed = num or ns.db.taxiOrbitDriftSpeed
		local yawSpeed = tonumber(GetCVar("cameraYawMoveSpeed")) or 180
		ns.Print(("drifting left at %.1f deg/sec for 10 sec (should turn about %d degrees)"):format(
			speed, math.floor(speed * 10 + 0.5)))
		MoveViewLeftStart(speed / yawSpeed)
		C_Timer.After(10, function() MoveViewLeftStop() end)
	elseif cmd == "pitchtest" then
		-- Tilts the camera up a set number of degrees at 30 deg/sec, to check the
		-- pitch speed conversion the same way turntest checks turning.
		-- Negative tilts the other way (the "view down" command).
		local degrees = num or 30
		local pitchSpeed = tonumber(GetCVar("cameraPitchMoveSpeed")) or 90
		local up = degrees >= 0
		ns.Print(("tilting %d degrees %s with the \"view %s\" command (cameraPitchMoveSpeed = %s)"):format(
			math.abs(degrees), up and "up" or "down", up and "up" or "down",
			tostring(GetCVar("cameraPitchMoveSpeed"))))
		local start, stop = up and MoveViewUpStart or MoveViewDownStart, up and MoveViewUpStop or MoveViewDownStop
		start(30 / pitchSpeed)
		C_Timer.After(math.abs(degrees) / 30, function() stop() end)
	elseif cmd == "debug" and arg == "portrait" then
		-- What the "show portrait until full" check can see.
		local function show(value)
			if issecretvalue and issecretvalue(value) then
				return "SECRET"
			end
			return tostring(value)
		end
		local powerType, powerToken = UnitPowerType("player")
		ns.Print(("health %s / %s"):format(show(UnitHealth("player")), show(UnitHealthMax("player"))))
		ns.Print(("power %s / %s, type %s (%s)"):format(show(UnitPower("player")),
			show(UnitPowerMax("player")), show(powerToken), show(powerType)))
		ns.Print(("last health/power change: %.1f sec ago"):format(ns.GetSecondsSinceVitalsChange()))
		ns.Print(("option on: %s, recovering: %s, in combat: %s"):format(
			tostring(ns.db.portraitWhenNotFull), tostring(ns.IsPlayerRecovering()),
			tostring(InCombatLockdown())))
		for _, entry in ipairs(ns.managed) do
			if entry.name == "PlayerFrame" then
				ns.Print(("PlayerFrame alpha %.2f, group %s, nested %s"):format(
					entry.alpha, entry.group, tostring(entry.nested or false)))
			end
		end
		if ns.db.ignoredFrames.PlayerFrame then
			ns.Print("PlayerFrame is on the Always shown list")
		end
	elseif cmd == "debug" and arg == "tracking" then
		-- Shows what tracking the addon can see, to check the spell IDs.
		local ids = {}
		for spellID in pairs(ns.GetActiveTrackingSpells()) do ids[#ids + 1] = tostring(spellID) end
		table.sort(ids)
		ns.Print("active buff/tracking spell IDs: " .. (#ids > 0 and table.concat(ids, ", ") or "none"))
		ns.Print("tracking icon: " .. tostring(ns.GetActiveTrackingIcon()))
		ns.Print("keeping minimap for tracking: " .. tostring(ns.IsTrackingSomethingWanted()))
	elseif cmd == "debug" and arg == "place" then
		-- Shows how the addon classifies where you are (cities vs inns etc.).
		local inInstance, instanceType = IsInInstance()
		ns.Print(("zone=%s place=%s resting=%s instance=%s/%s"):format(
			tostring(GetRealZoneText()), tostring(ns.GetPlaceType()), tostring(IsResting()),
			tostring(inInstance), tostring(instanceType)))
		ns.IsInCity() -- make sure the city list is built
		local names = {}
		for name in pairs(ns.cityNames) do names[#names + 1] = name end
		table.sort(names)
		ns.Print("cities: " .. (#names > 0 and table.concat(names, ", ") or "none found"))
	elseif cmd == "debug" and arg == "orbit" then
		-- Run mid-flight to see what the camera rotation thinks it's doing.
		ns.Print(("onTaxi=%s cinematic=%s enabled=%s orbitOption=%s mode=%s"):format(
			tostring(UnitOnTaxi("player")), tostring(ns.lastCinematic), tostring(ns.db.enabled),
			tostring(ns.db.taxiOrbit), tostring(ns.db.taxiOrbitMode)))
		ns.Print(("level=%.2f phase=%s t=%.1f sweepTime=%.1f yawDelta=%.1f pitchDelta=%.1f"):format(
			ns.orbit.level, ns.orbit.phase, ns.orbit.t, ns.orbit.sweepTime, ns.orbit.yawDelta, ns.orbit.pitchDelta))
		ns.Print(("angle=%.1f pitch=%.1f yawMoving=%s pitchMoving=%s smoothStyle=%s"):format(
			ns.orbit.angle, ns.orbit.pitch, tostring(ns.yawAxis.moving), tostring(ns.pitchAxis.moving),
			tostring(GetCVar("cameraSmoothStyle"))))
		ns.Print(("orbitFrame running=%s, MoveViewUpStart=%s"):format(
			tostring(ns.orbitFrame:GetScript("OnUpdate") ~= nil), tostring(MoveViewUpStart ~= nil)))
	elseif cmd == "debug" then
		-- Hover over something and run this to see how the addon sees it.
		for _, entry in ipairs(ns.managed) do
			if entry.group == arg or (arg == "" and entry.group == "minimap") then
				ns.Print(("%s [%s] shown=%s alpha=%.2f hovered=%s"):format(
					entry.name or entry.frame:GetDebugName(), entry.group,
					tostring(entry.frame:IsShown()), entry.alpha, tostring(ns.IsEntryHovered(entry))))
			end
		end
	elseif cmd == "list" then
		ns.ListExtras()
	elseif cmd == "reset" then
		ns.ResetSettings()
		ns.Print("settings reset")
	else
		PrintHelp()
	end
end
