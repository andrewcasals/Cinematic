-- Cinematic: the /cine slash commands.
local _, ns = ...
local L = ns.L

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

local function Heading(text)
	print("|cffffd100" .. text .. "|r")
end

-- A command and what it does (the command itself is the same in every language).
local function Command(command, text)
	print("  " .. command .. " - " .. text)
end

local function PrintHelp()
	logPrints = false
	ns.Print(L["commands"])
	Heading(L["General"])
	Command("/cine", L["toggle CineMode (also /cine on, /cine off)"])
	Command("/cine config", L["open the settings"])
	Command("/cine hideui", L["hide the UI but keep the look (again to bring it back)"])
	Command("/cine size <percent>", L["letterbox bar height (now %s%%)"]:format(ns.db.letterboxSize * 100))
	Command("/cine button", L["show or hide the minimap button"])
	Command("/cine reset", L["put the active profile back to how it started"])
	Command("/cine profile", L["list the profiles (/cine profile <name> switches to one)"])
	Command("/cine export", L["share the active profile as text to copy"])
	Command("/cine import", L["add a profile someone shared with you"])
	Command("/cine welcome", L["the welcome window, to pick a profile"])
	if ns.ToggleTalentCalc then
		Command("/cine talents", L["the talent calculator, to plan a build"])
	end
	if ns.ToggleRollWindow then
		Command("/cine rolls", L["the latest loot rolls (/cine rolls test shows made-up ones)"])
	end
	Heading(L["Frames (hover over one first)"])
	Command("/cine add", L["fade it too (or /cine add <FrameName>)"])
	Command("/cine add mode", L["pick up every frame you hover over, then again to fade them all"])
	Command("/cine keep", L["always show it"])
	Command("/cine list", L["show the extra faded frames"])
	Heading(L["Camera"])
	Command("/cine behind", L["swing the camera back behind your character"])
	Command("/cine flyby", L["turn the camera slowly round to look back, then back behind you (again to stop)"])
	Command("/cine walk", L["does the addon think you're walking or auto-running?"])
	Command("/cine walk flip", L["fix it if it has walk and run backwards"])
	Heading(L["More"])
	Command("/cine debug help", L["troubleshooting commands"])
	Command("/cine log", L["copy the log and your setup for a bug report (/cine log clear empties it)"])
	Command("/cine panic", L["stop for this session and put your UI and settings back (/cine resume to restart)"])
	print("  " .. L["Keybinds (toggle CineMode, hide the UI, start a camera) are on the Keybinds settings page."])
	logPrints = true
end

local function PrintDebugHelp()
	ns.Print("troubleshooting commands")
	logPrints = false
	print("  /cine log - copy the log for a bug report: what's printed below goes in it too")
	print("  /cine debug record - also log game setting changes and music in detail (again to stop)")
	print("  /cine debug cpu [seconds|stop] - time what the addon spends its time on (30 seconds), report in the log")
	print("  /cine debug frame <name> - how faded frames with <name> in their name or group stand")
	print("  /cine debug minimap - the minimap's settings, where it's anchored, and whether it's shrunk and moved off the screen")
	print("  /cine debug minimapicons - the minimap's methods for its player arrow and icons on this client")
	print("  /cine debug nodes [raw] [grow [update]|park|stay] [seconds] - sweep a pretend mouse over the minimap and list the names its tooltip gives (herbs, veins), faded or not; grow gives the faded minimap its size back for each sweep only; park keeps it full size off the screen while it watches (60 seconds), stay full size in its place; update has the game place its dots first; raw shows each name's line as the game wrote it; with seconds, once a second, then all of it in the copy window (again to stop early)")
	print("  /cine debug pad - print each gamepad button press and whether it shows the bars (again to stop)")
	print("  /cine debug frames - log the shown frames that aren't faded, and gamepad frames")
	print("  /cine debug alpha -print frames setting their own alpha (again to stop)")
	print("  /cine debug hover [group] - print what the mouse is on and whether the group (quests) counts as hovered (again to stop)")
	print("  /cine debug swing - what the swing timer bars read, and print each one showing or fading (again to stop)")
	print("  /cine debug mode - which camera mode it thinks you're in")
	print("  /cine debug cooldowns - what the Cooldown Manager's \"stay up while recharging\" check sees")
	print("  /cine debug newplayer - back to no profile picked, as on a fresh install (the welcome window)")
	print("  /cine debug whatsnew - the chat line shown at login after an update, with its What's new link")
	print("  /cine debug modes - print each camera mode change to chat (again to stop)")
	print("  /cine debug emote - the last emote the game passed, and whether cozy or vista took it")
	print("  /cine debug tent [seen|cozy [left|right]|clear] - whether a Camp Tent's been moused over near here (seen fakes one on that side of the screen, cozy also starts the cozy camera)")
	print("  /cine debug fishing - the last red error message, and whether it paused right-click casting")
	print("  /cine debug weapon - what the game says about your weapon, and the cozy weapon trigger")
	print("  /cine debug quest - the quest cam: on or off, its zoom and the over-the-shoulder offset")
	print("  /cine debug questlog - save every frame of the next quest cams (for tracking down snaps)")
	print("  /cine debug zoom - the slow zoom's state")
	print("  /cine debug turn - turn handling while walking (8 seconds)")
	print("  /cine debug unitframes - log every part of the player, pet, target and focus frames (names, textures, sizes, held hidden) to the saved log")
	print("  /cine debug plates - nameplate settings, and how the plates (and your target) are sorted")
	print("  /cine debug range - what the game says about how far your target and units with name-only plates are")
	print("  /cine debug names - log players' plate names as they show and hide (again to stop, /reload to save)")
	print("  /cine debug readycheck - the raid frames' ready check icons and whether they fade (Ready check row)")
	print("  /cine debug marker [across up size] - where the kept raid markers sit over faded plates")
	print("  /cine debug platewatch - log how faded nameplates are drawn each time it changes, to find one flashing up")
	print("  /cine debug duels - duel nameplates: watching or why not, and which nearby players can attack each other")
	print("  /cine debug questglow - quest object glow: what soft targeting picked and why it glows or not")
	print("  /cine debug iconwatch - log nameplate interact icons every frame for 30 seconds")
	print("  /cine debug sounds - print each sound the game plays, by number and name, e.g. the talents window's (again to stop)")
	print("  /cine debug talentart - log every part of the open talents window (sizes, textures, atlases) and its trees")
	print("  /cine debug talentcalc - the talent calculator: your trees as read, their grids, the row rule, its button")
	print("  /cine debug talents - the character window's Talents button and the talents window's Character button: made, shown, where")
	print("  /cine debug panels - the game's open windows: where they're anchored and whether they can be dragged")
	print("  /cine debug raidparts - log every part of the party and raid frames and how each is faded, print shown icons that aren't")
	print("  /cine debug auras - whether your group's debuffs can be seen, and how (run in and out of combat, in different places)")
	print("  /cine debug combatlog - log the Combat Log tab's lines, readable or not; stays on across reloads (again to stop)")
	print("  /cine debug healwatch [seconds] - log each raid frame's alpha as it changes and who set it (5 seconds; /reload after)")
	print("  /cine debug health - whether your group's health can be read and sorted (run in and out of combat)")
	print("  /cine debug healthfade [percent] - test window: blocks that show only while someone's below the percent (again to close)")
	print("  /cine debug damage [seconds] - whether damage taken reaches addons: hit event, damage meter (15 seconds)")
	print("  /cine debug slots [all] - profile slots and parts: anything with no slot or in the wrong one (in the log; all: also how each shared list is split)")
	print("  /cine debug cvars - graphics CVars: which exist here; run, move the Graphics sliders, run again to log what the menu changed")
	print("  /cine debug cvars <words> - log every CVar whose name has any of the words in it, with its value and default")
	print("  /cine debug settings <words> - list every option in the game's Settings panel named like the words, with the variable behind it and its value")
	print("  /cine debug weather - the weather the game reports and the weather tint")
	print("  /cine debug corpse - how far your body is (as a ghost) and the corpse run's vignette")
	print("  /cine debug flight - the flight route, its known time and when the camera settles")
	print("  /cine debug orbit - the camera rotation's state")
	print("  /cine debug flyby - the fly-by's state and the random ones planned")
	print("  /cine debug flybys - print each fly-by's start and end, random ones too (again to stop)")
	print("  /cine debug questtimer - say whether a quest timer is running and how its box fades")
	print("  /cine debug death - print what the death camera does on real deaths (again to stop)")
	print("  /cine debug place - city, inn, dungeon detection")
	print("  /cine debug group [party|raid|off] - act as if in a party or raid, for the group options")
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
	print("  /cine attacktest [text] - show a LocalDefense attack warning now")
	print("  /cine tinttest [seconds] - each time of day's tint with its title, AFK camera on (8 each; again to stop)")
	print("  /cine soundtest <id> - play a game sound by its ID (stops after 10 seconds)")
	print("  /cine songtest [file ID] - play a random death song, or any music file (again to stop)")
	logPrints = true
end

local function HandleSlash(msg)
	local cmd, arg = msg:lower():match("^%s*(%S*)%s*(.-)%s*$")
	local num = tonumber(arg)
	if cmd ~= "log" then
		ns.Log("cmd", "/cine " .. msg)
	end

	if cmd == "log" then
		if arg == "clear" then
			ns.ClearLog()
			ns.Print(L["log cleared"])
		else
			ns.ShowLog()
		end
	elseif cmd == "panic" then
		if ns.IsSuspended() then
			ns.Print(L["already stopped: /cine resume starts it again"])
		else
			ns.Suspend("/cine panic")
		end
	elseif cmd == "resume" then
		ns.Print(ns.Resume() and L["started again"] or L["isn't stopped"])
	elseif cmd == "debug" and arg:find("^cpu") then
		local seconds = tonumber(arg:match("^cpu%s+(%d+)"))
		if arg == "cpu stop" then
			if not ns.StopProfile() then
				ns.Print("no cpu profile running")
			end
		elseif ns.IsProfiling() then
			ns.Print("a cpu profile is already running: /cine debug cpu stop ends it early")
		else
			seconds = seconds or 30
			ns.StartProfile(seconds)
			ns.Print(("cpu profile for %d seconds (/cine debug cpu stop ends it early): play as usual"):format(seconds))
		end
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
		ns.Print(ns.db.enabled and L["enabled"] or L["disabled"])
		if ns.IsSuspended() then
			ns.Print(L["(still stopped after an error: /cine resume starts it again)"])
		end
	elseif cmd == "size" and num and num >= 0 and num <= 40 then
		ns.db.letterboxSize = num / 100
		ns.letterboxDirty = true
		ns.Print(L["letterbox size set to %s%%"]:format(num))
	elseif cmd == "add" then
		-- Frame names are case-sensitive, so take the name before lowercasing.
		local name = msg:match("^%s*%S+%s+(%S+)")
		if name == "mode" then
			ns.ToggleAddMode()
		elseif name == "cancel" then
			ns.CancelAddMode()
		else
			ns.AddUnderMouse(name)
		end
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
	elseif cmd == "hideui" then
		Cinematic_ToggleUI()
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
	elseif cmd == "debug" and arg == "whatsnew" then
		ns.ShowUpdateNotice(2)
	elseif cmd == "debug" and arg == "modes" then
		ns.db.debugCameraMode = not ns.db.debugCameraMode
		ns.ResetCameraModeReport() -- print the current mode straight away
		ns.Print("print camera mode changes to chat: " .. OnOff(ns.db.debugCameraMode))
	elseif cmd == "debug" and arg:find("^frame ") then
		ns.ReportFrames(arg:match("^frame%s+(.+)$"))
	elseif cmd == "debug" and arg == "names" then
		ns.Print("log players' plate names as they change: " .. OnOff(ns.ToggleNamesDebug())
			.. " (/reload afterwards to save the log)")
	elseif cmd == "debug" and arg == "alpha" then
		ns.alphaWatch = not ns.alphaWatch
		ns.Print("print frames setting their own alpha: " .. OnOff(ns.alphaWatch) .. " (until you /reload)")
	elseif cmd == "debug" and arg:find("^hover") then
		-- What the mouse is on and whether a group counts as hovered, printed as
		-- it changes (quest tracker by default), to see a fade it won't stop.
		if ns.hoverWatch then
			ns.hoverWatch:Cancel()
			ns.hoverWatch = nil
			ns.Print("hover watch: off")
			return
		end
		local group = arg:match("^hover%s+(%S+)") or "quests"
		local last
		ns.hoverWatch = C_Timer.NewTicker(0.1, function()
			local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
			local ok, focusName = pcall(function() return focus and focus:GetDebugName() or "nothing" end)
			local parts = { "on " .. (ok and tostring(focusName) or "?") }
			for _, entry in ipairs(ns.managed) do
				if entry.group == group then
					parts[#parts + 1] = ("%s alpha=%.1f over=%s hovered=%s"):format(
						entry.name or "?", entry.alpha, tostring(ns.Flag(entry.frame:IsMouseOver())),
						tostring(ns.IsEntryHovered(entry)))
				end
			end
			local line = table.concat(parts, " | ")
			if line ~= last then
				last = line
				ns.Print(line)
			end
		end)
		ns.Print("hover watch: on for " .. group .. " (again to stop)")
	elseif cmd == "debug" and arg == "swing" then
		ns.swingDebug = not ns.swingDebug
		if ns.ReportSwing then
			ns.ReportSwing()
		end
		ns.Print("print swing bars showing or fading: " .. OnOff(ns.swingDebug) .. " (until you /reload)")
	elseif cmd == "debug" and arg == "pad" then
		ns.padDebug = not ns.padDebug
		local hasState = C_GamePad and C_GamePad.GetDeviceMappedState and true or false
		ns.Print(("print gamepad presses: %s (until you /reload). button event: %s, button reading: %s, " ..
			"gamepad mode: %s"):format(OnOff(ns.padDebug), tostring(ns.padEventOK), tostring(hasState),
			tostring(ns.IsGamePadOn())))
	elseif cmd == "debug" and arg == "frames" then
		ns.ReportUnfadedFrames()
	elseif cmd == "debug" and (arg == "group" or arg:find("^group ")) then
		-- (No choice given: a party, or off again if already faking one.)
		local kind = arg:match("^group%s+(%S+)") or (ns.fakeGroup and "off" or "party")
		if kind == "party" or kind == "raid" then
			ns.fakeGroup = kind
			ns.Print(("acting as if in a %s (the game's own frames still go by your real group). " ..
				"/cine debug group off to stop"):format(kind))
		elseif kind == "off" then
			ns.fakeGroup = nil
			ns.Print("going by your real group again")
		else
			ns.Print("/cine debug group party, raid or off")
		end
	elseif cmd == "debug" and arg == "minimap" then
		ns.ReportMinimap()
	elseif cmd == "debug" and arg == "questtimer" then
		ns.ReportQuestTimer()
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
			ns.deathTestUntil, ns.deathTestLoud = GetTime() + seconds, true
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
		local event, camera = ns.GetEventDebug()
		ns.Print(event and ("event now: %s -> %s camera"):format(event, camera)
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
	elseif cmd == "tinttest" then
		-- Each time of day in turn: its tint and its title, with the AFK camera
		-- circling meanwhile. Again to stop.
		local seconds = tonumber(arg) or 8
		local startedCam = false
		local function StopCam()
			if startedCam and ns.manualCam == "afk" then
				Cinematic_StartCam("idle", true) -- (a second press stops it)
			end
		end
		if ns.DaySweep(math.max(4, seconds), StopCam) then
			if ns.manualCam ~= "afk" then
				Cinematic_StartCam("idle")
				startedCam = ns.manualCam == "afk"
			end
			ns.Print(("showing every time of day's tint, %d seconds each. /cine tinttest again stops it."):format(
				math.max(4, seconds)))
			if ns.db.visualEffects == false then
				ns.Print("Visual effects are off, so the tint won't show: turn them on first")
			end
		else
			ns.Print("time of day tint demo stopped")
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
	elseif cmd == "attacktest" then
		-- Shows an attack warning now, as LocalDefense would (here, or the text given,
		-- taken before lowercasing).
		local text = msg:match("^%s*%S+%s+(.-)%s*$") or ""
		local place = GetMinimapZoneText and GetMinimapZoneText() or ""
		ns.ShowAlertTitle(text ~= "" and text or L["%s is under attack!"]:format(place ~= "" and place
			or GetRealZoneText()))
	elseif cmd == "debug" and arg == "tooltip" then
		-- Traces tooltip hiding for 10 seconds (hover a herb meanwhile).
		ns.tooltipTrace = { started = GetTime() }
		ns.Print("tooltip trace for 10 seconds: hover the thing now.")
		C_Timer.After(10, function()
			local log = ns.tooltipTrace
			ns.tooltipTrace = nil
			ns.Print(("tooltip trace done: %d entries"):format(#log))
			for _, line in ipairs(log) do
				print("  " .. line)
			end
		end)
	elseif cmd == "debug" and (arg == "tent" or arg:find("^tent ")) then
		-- Whether a Camp Tent's been seen near here; "seen" fakes one, "clear" forgets it.
		-- (seen and cozy take the side of the screen it's on: right if not said.)
		local how, side = arg:match("^tent%s+(%S+)%s*(%S*)$")
		side = (side == "left" or side == "right") and side or nil
		if how == "seen" or how == "clear" then
			ns.TentTest(how == "clear", side)
		elseif how == "cozy" then
			-- A tent seen here, then the cozy camera (already on: it just picks the tent up).
			ns.TentTest(false, side)
			if ns.manualCam ~= "cozy" then
				Cinematic_StartCam("cozy")
			end
		elseif how then
			ns.Print("/cine debug tent [seen|cozy [left|right]|clear]")
			return
		end
		local t, c = ns.GetTentDebug()
		if t then
			-- (Your side of it: the camera's behind you outside the cozy camera, in front in it.)
			local yours = (t.side == "right") ~= (t.duringCozy and true or false) and "right" or "left"
			ns.Print(("Camp Tent: to your %s (%s of the screen, with the camera %s you); seen %.0f sec ago (%s), you're %s from there; forgotten %d yards away"):format(
				yours:upper(), t.side, t.duringCozy and "in front of" or "behind", t.ago, t.how,
				t.distance and ("%.1f yards"):format(t.distance) or "an unknown distance", t.forget))
		else
			ns.Print("Camp Tent: none seen near here (/cine debug tent seen fakes one)")
		end
		if c then
			ns.Print(("cozy camera: %s, %s"):format(
				c.on and ("on for %.0f sec"):format(c.length)
					or ("last one ran %.0f sec, ended %.0f sec ago"):format(c.length, c.endedAgo),
				c.tentAtStart and "tent already seen as it started"
					or c.tentAfter and ("tent first seen %.1f sec into it"):format(c.tentAfter)
					or "no tent seen during it"))
		else
			ns.Print("cozy camera: none since loading in")
		end
		local zoom = ns.GetZoomDebug()
		ns.Print(("camera distance now %.1f yards; cozy close-up %.1f, with a tent seen %.1f; cozy zoom %s%s"):format(
			GetCameraZoom(), ns.db.cozyZoomClose, ns.db.cozyTentClose, zoom.active and zoom.context == "cozy" and "on" or "off",
			zoom.active and zoom.context == "cozy" and zoom.phase == "move"
				and (", heading for %.1f"):format(zoom.from + zoom.delta) or ""))
		local tentAngle, cameraAngle, braking = ns.CozyTentDebug()
		if tentAngle then
			ns.Print(("cozy sway: tent guessed at %.0f°, camera at %.0f° (from in front of you), keeping 90° clear%s"):format(
				tentAngle, cameraAngle, braking and "; braking away from it now" or ""))
		else
			ns.Print(t and "cozy sway: not going yet (it steers clear of the tent once the cozy camera starts)"
				or "cozy sway: no tent to steer clear of")
		end
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
	elseif cmd == "debug" and arg == "unitframes" then
		ns.LogUnitFrames()
	elseif cmd == "debug" and arg == "plates" then
		ns.PrintPlatesDebug()
	elseif cmd == "debug" and arg == "range" then
		ns.PrintRangeDebug()
	elseif cmd == "debug" and arg == "readycheck" then
		ns.ReportRaidReadyCheck()
	elseif cmd == "debug" and arg:find("^marker") then
		local x, y, size = arg:match("^marker%s+(%S+)%s*(%S*)%s*(%S*)$")
		x, y, size = ns.KeptMarkerSpot(tonumber(x), tonumber(y), tonumber(size))
		ns.Print(("kept raid markers: %s across, %s up from the middle of the health bar, size %s"
			.. " (/cine debug marker <across> <up> <size> to move them)"):format(x, y, size))
	elseif cmd == "debug" and arg == "platewatch" then
		ns.Print("log how faded nameplates are drawn as it changes: " .. OnOff(ns.TogglePlateWatch())
			.. " (/reload to write the log)")
	elseif cmd == "debug" and arg == "duels" then
		ns.PrintDuelsDebug()
	elseif cmd == "debug" and arg == "questglow" then
		ns.PrintQuestGlowDebug()
	elseif cmd == "debug" and arg == "iconwatch" then
		ns.StartIconWatch()
	elseif cmd == "debug" and arg == "sounds" and ns.ToggleSoundWatch then
		ns.Print("print each sound the game plays: " .. OnOff(ns.ToggleSoundWatch()))
	elseif cmd == "debug" and arg == "talentart" and ns.LogTalentArt then
		ns.LogTalentArt()
	elseif cmd == "debug" and arg == "talentcalc" then
		if ns.PrintTalentCalcDebug then ns.PrintTalentCalcDebug() else ns.Print("talent calculator not loaded (retail, or TalentCalc.lua missing)") end
	elseif cmd == "debug" and arg:find("^talents?%p*$") then
		if ns.PrintTalentLinkDebug then ns.PrintTalentLinkDebug() else ns.Print("talents link not loaded (retail, or TalentLink.lua missing)") end
	elseif cmd == "debug" and arg == "panels" then
		ns.PrintPanelsDebug()
	elseif cmd == "debug" and (arg == "slots" or arg == "slots all") then
		ns.SlotsDebug(arg == "slots all")
	elseif cmd == "debug" and arg == "corpse" then
		local c = ns.GetCorpseDebug()
		local function yards(d) return d and ("%.1f yards"):format(d) or "unknown" end
		ns.Print(("corpse: %s (%s); from the map marker: %s (%s)"):format(
			yards(c.distance), tostring(c.source), yards(c.mapDistance), tostring(c.mapSource)))
		ns.Print(("ghost %s, wave %.0f sec, position saved at death %s, came back at %s, vignette %s"):format(
			tostring(c.ghost), c.wave, tostring(c.saved), yards(c.start),
			c.level and ("%d%%"):format(c.level * 100) or "off"))
		if c.walked then
			ns.Print(("body unknown: faking it, %s walked of 1000"):format(yards(c.walked)))
		end
		ns.Print(("edge creep %d%% (aiming for %s), edges reach %d%% of the screen, dim wash %d%%"):format(
			c.creep * 100, c.level and ("%d%%"):format(c.level * 100) or "none", c.edgeSize * 100, c.wash * 100))
	elseif cmd == "debug" and arg == "cvars" then
		ns.CVarsDebug()
	elseif cmd == "debug" and arg:find("^cvars%s") then
		ns.CVarsFind(arg:match("^cvars%s+(.+)"))
	elseif cmd == "debug" and arg:find("^settings%s") then
		ns.SettingsFind(arg:match("^settings%s+(.+)"))
	elseif cmd == "debug" and arg == "raidparts" then
		ns.LogRaidFrames()
	elseif cmd == "debug" and arg:find("^healwatch") then
		ns.HealWatchDebug(arg:match("^healwatch%s+(%S+)"))
	elseif cmd == "debug" and arg == "health" then
		ns.HealthDebug()
	elseif cmd == "debug" and arg == "auras" then
		ns.AurasDebug()
	elseif cmd == "debug" and arg == "combatlog" then
		ns.CombatLogDebug()
	elseif cmd == "debug" and arg:find("^healthfade") then
		ns.HealthFadeDebug(arg:match("^healthfade%s+(%S+)"))
	elseif cmd == "debug" and arg:find("^damage") then
		ns.DamageDebug(arg:match("^damage%s+(%S+)"))
	elseif cmd == "debug" and arg == "minimapicons" then
		-- Which of the minimap's own methods for its arrow and icons this client
		-- has (to hide them while it's faded but full size).
		local methods = {}
		local index = getmetatable(Minimap) and getmetatable(Minimap).__index
		for name in pairs(type(index) == "table" and index or {}) do
			if type(name) == "string" and (name:find("Texture") or name:find("Player") or name:find("Blip")
				or name:find("POI") or name:find("Arrow") or name:find("Icon") or name:find("Quest")) then
				methods[#methods + 1] = name
			end
		end
		table.sort(methods)
		ns.Print(("minimap icon methods (%d): %s"):format(#methods, #methods > 0 and table.concat(methods, ", ") or "none"))
	elseif cmd == "debug" and arg:find("^nodes") then
		ns.NodesDebug(arg:match("^nodes%s*(.*)$"))
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
			state = L["running (walk mode off)"]
		elseif ns.playerMoving and ns.MovingManually and ns.MovingManually() then
			state = L["walking by hand - no RP walk camera (auto-walk for it)"]
		elseif ns.playerMoving then
			state = ns.db.walkOrbit and L["auto-walking - RP walk camera on"]
				or L["auto-walking - RP walk camera switched off in settings"]
		else
			state = L["walk mode on, standing still"]
		end
		local speed = ns.GetPlayerSpeed()
		local source = (ns.playerMoving and ns.walkingFromSpeed)
			and L["from your speed: %.1f yards/sec"]:format(speed or 0)
			or L["from the walk/run key"]
		ns.Print((arg == "flip" and L["the addon thinks you're %s (%s)."]
			or L["the addon thinks you're %s (%s). Wrong? Type /cine walk flip."]):format(state, source))
		ns.Print(L["auto-run: %s"]:format(ns.autoRunning and L["on"] or L["off"]) ..
			((ns.IsAutoRunning and ns.IsAutoRunning()) and L[" (auto-run camera)"] or
				(ns.autoRunning and ns.walking and L[" (walking, so RP walk camera)"] or "")))
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
		-- (And why CineMode is off, if it is: with Start in CineMode off, the trigger's state.)
		ns.Print(("CineMode %s; place %s, auto-run flag %s, auto-run cam off here %s, trigger %s"):format(
			ns.lastCinematic and "on" or ("off: " .. tostring(ns.cineOffWhy)), tostring(ns.GetPlaceType()),
			tostring(ns.autoRunning), tostring(ns.IsCameraOffHere("run")), tostring(ns.TriggerStartsCine())))
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
		ns.Print(("option on: %s (PRD %s), recovering: %s, in combat: %s"):format(
			tostring(ns.db.portraitWhenNotFull), tostring(ns.db.prdWhenNotFull), tostring(ns.IsPlayerRecovering()),
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
		local gathering, creatures = ns.IsTrackingSomethingWanted()
		ns.Print(("keeping minimap open for gathering tracking: %s%s, for creatures or fish: %s"):format(
			tostring(gathering), gathering and ns.IsTrackingOffHere() and " (but not here: Except in, Minimap page)" or "",
			tostring(creatures)))
		ns.Print(ns.NodeSweepReport())
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
	elseif cmd == "debug" and arg == "cooldowns" then
		ns.ReportCooldowns()
	elseif cmd == "debug" and arg == "newplayer" then
		-- (Your profiles and their settings stay; picking one carries on from them.)
		ns.SaveProfile()
		ns.db.profileChosen = false
		ns.Print("no profile picked: Cinematic is off until you pick one")
		ns.ShowWelcome()
	elseif cmd == "debug" then
		-- Hover over something and run this to see how the addon sees it.
		local found = false
		for _, entry in ipairs(ns.managed) do
			if entry.group == arg or (arg == "" and entry.group == "minimap") then
				found = true
				ns.Print(("%s [%s] shown=%s alpha=%.2f hovered=%s"):format(
					entry.name or entry.frame:GetDebugName(), entry.group,
					tostring(entry.frame:IsShown()), entry.alpha, tostring(ns.IsEntryHovered(entry))))
			end
		end
		if not found then
			ns.Print("no faded frames in the group " .. (arg == "" and "minimap" or arg))
		end
	elseif cmd == "list" then
		ns.ListExtras()
	elseif cmd == "reset" then
		ns.ResetSettings()
		ns.Print(L["profile %s reset"]:format(ns.ProfileLabel(ns.ActiveProfile())))
	elseif cmd == "export" then
		ns.ShowExport()
	elseif cmd == "import" then
		ns.ShowImport()
	elseif cmd == "talents" and ns.ToggleTalentCalc then
		ns.ToggleTalentCalc()
	elseif (cmd == "rolls" or cmd == "roll") and ns.ToggleRollWindow then
		if arg == "test" then
			ns.TestRollWindow()
		elseif ns.Setting("rollWindow") then
			ns.ToggleRollWindow()
		else
			ns.Print(L["Turn on the loot roll window first."])
		end
	elseif cmd == "welcome" then
		ns.ShowWelcome()
	elseif cmd == "profile" or cmd == "profiles" then
		-- (The name's matched ignoring case: msg was lowered.)
		local name = arg ~= "" and ns.FindProfile(arg)
		if name then
			ns.SetProfile(name)
			ns.Print(L["profile: %s"]:format(ns.ProfileLabel(name)))
		else
			if arg ~= "" then ns.Print(L["no profile called %s"]:format(arg)) end
			ns.Print(L["profiles (the active one in yellow):"])
			for _, each in ipairs(ns.ProfileNames()) do
				local active = ns.ProfileChosen() and each == ns.ActiveProfile()
				local shown = ns.ProfileLabel(each)
				print("  " .. (active and "|cffffd100" .. shown .. "|r" or shown))
			end
		end
	else
		PrintHelp()
	end
end

function ns.HandleSlash(msg)
	local cmd, arg = msg:lower():match("^%s*(%S*)%s*(.-)%s*$")
	if (cmd == "debug" and arg ~= "help") or cmd == "list" then
		ns.CaptureDebug("/cine " .. msg:match("^%s*(.-)%s*$"), function() HandleSlash(msg) end)
	else
		HandleSlash(msg)
	end
end
