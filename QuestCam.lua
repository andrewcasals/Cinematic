-- Quest cam: talking to a quest giver, the camera eases in close, swings
-- round behind you, comes round to one side and down toward eye level,
-- looking past you at them at an angle (a dialogue shot). Optionally it also
-- moves over your right shoulder. It all goes back as the window closes.
--
-- Interacting turns you to face the NPC, so "behind you" is looking at them.
-- The swing borrows camera follow (ns.CenterCamera), which is reliable for
-- the small offsets left by that turn. The shoulder is the game's
-- test_cameraOverShoulder offset, which it eases over to on its own; the
-- game ignores it while Keep Character Centered (Accessibility) is on, so
-- it's only used with that off (or questCamUncenter turning it off meanwhile).
-- It's one of Blizzard's experimental camera settings (setting it brings up
-- their warning), so it's off unless you turn it on (questCamOverShoulder).
--
-- Once the swing's over, the turn to the side (questCamAngle) runs alongside
-- the rest of the zoom, then the tilt down (questCamLower) follows, after a
-- short pause (the game won't turn and tilt at once). Going back, the zoom
-- out and the turn back go together, then the tilt up. In between, once all
-- that's settled, the turn drifts slowly to and fro (questCamDrift). There's no reading
-- the camera's angle, so both are counted, and undone by as much.
-- Both ease in and out, like the death camera's tilt: one move command is
-- held while its speed setting is stepped along the curve (re-sending the
-- move at each new speed restarts it, which snapped, worse with the zoom's
-- per-frame steps alongside); your setting then comes back. Camera follow is
-- off meanwhile, so it can't pull the view back.
-- Every move gives a small jolt as it starts, bigger the faster it starts
-- (/cine starttest: a steady 10 degrees/sec start jolted plainly, 1 degree/sec
-- just a hair). The speed setting can't go much below 1 (lower, the game
-- uses its full speed), so the move is sent at a share of it instead: the
-- share that makes your own setting the move's top speed. The setting then
-- runs from 1 (a start of a fraction of a degree per second) up toward
-- yours and back, never past it.
-- The zoom works the same way: one CameraZoomIn (or Out) for the whole
-- distance, with the game's zoom speed setting stepped along the curve. (The
-- addon's other zooms nudge the camera every frame; alongside a turn those
-- nudges showed as small snaps.)
-- Moving off (walking away from the quest giver) ends it: everything goes
-- back, and it doesn't start again until the next conversation.
-- Moving the camera yourself while talking hands it over: nothing is undone.
local _, ns = ...

local CLOSE_GRACE = 0.4 -- seconds: going from gossip to a quest closes one window before opening the next
-- The swing behind you: the takeoff swing's gentle speeds (a quicker one
-- showed as a snap), then a moment for it to settle before camera follow is
-- handed back (switched off while still easing the view, it jolts).
local SWING_YAW = 45    -- degrees per second, at most (no pitch: the tilt has that)
local SWING_RAMP = 1.5  -- seconds for it to build up speed from a crawl
local SWING_SETTLE = 1  -- seconds held on past questCamTime
local ZOOM_MARGIN = 0.5 -- yards: already about this close, so no zoom
local ZOOM_YOURS = 1.5  -- yards from where it zoomed to: you've zoomed yourself, so it stays
local BACK_SHARE = 0.5  -- the turn back takes this share of the turn's time...
local BACK_MIN = 1.5    -- ...but at least this many seconds
local MOVE_MIN_TIME = 1.5 -- seconds: the shortest turn or tilt
local MOVE_EASE = 0.35   -- share of a move spent speeding up (and again slowing down)
local MOVE_MIN_SPEED = 1 -- degrees per second: the slowest step sent (lower, the game uses its full speed)
local MOVE_MIN_SETTING = 1 -- the lowest speed setting sent (the start's speed is this times the move's share)
local MOVE_CHANGE = 0.02 -- speed changes smaller than this share aren't sent
local MOVE_PRIME_TIME = 0.2 -- seconds the starting speed is set before the move starts
local SPEED_RESTORE_DELAY = 0.3 -- seconds after stopping before your speed setting comes back
local ZOOM_CVAR = "cameraZoomSpeed"
local ZOOM_MIN_SPEED = 0.3 -- yards per second: the slowest step sent
local ZOOM_DONE = 0.05     -- yards: arrived
local ZOOM_GIVE_UP = 4     -- extra seconds to settle before a zoom that can't get there stops
local FOLLOW_GAP = 0.5 -- seconds between the swing handing camera follow back and the turn starting
local STEP_GAP = 0.6   -- seconds between one move stopping and the next starting (on neighbouring frames, it
                       -- snapped; and clear of the speed setting coming back, SPEED_RESTORE_DELAY after)
local TILT_TIME = 4    -- seconds the tilt down takes (squeezed into what was left of the zoom, it was rushed)
local TILT_EASE = 0.5  -- ...one long, smooth swell: speeding up over its first half
local TILT_BACK_TIME = 2 -- ...and back up
local DRIFT_TIME = 7   -- seconds each leg of the drift takes, once settled (questCamDrift)
local DRIFT_EASE = 0.3 -- ...ramps at either end (all easing, it crawled so long it seemed to stop at each
                       -- side; much shorter, it turned round with a jump)
local DRIFT_GAP = 0.35 -- ...seconds between legs (STEP_GAP's pause showed)
local INPUT_GRACE = 1 -- seconds: camera input this soon is the click that opened the window
local LOG_MAX = 4000  -- frames kept by /cine debug questlog

local SHOULDER_CVARS = { values = { test_cameraOverShoulder = "1" } }
local CENTERED_CVARS = { values = { CameraKeepCharacterCentered = "0" } }
local FOLLOW_CVARS = { values = { cameraSmoothStyle = "0" } }

local cam = { active = false, steps = {} }

-- The two moves. amount: degrees from where the swing left the camera
-- (yaw: round to your right, or left; pitch: down).
-- grow/shrink: the commands that move amount up and down.
-- (Kept apart from ns.yawAxis and ns.pitchAxis: the orbit stops those every
-- frame while it's idle, which cut the turn off over and over, a lurching spin.)
local movers = {
	yaw = { amount = 0, cvar = "cameraYawMoveSpeed", default = 180,
		grow = "MoveViewLeft", shrink = "MoveViewRight" },
	pitch = { amount = 0, cvar = "cameraPitchMoveSpeed", default = 90,
		grow = "MoveViewDown", shrink = "MoveViewUp" },
}

-- Quests on offer or to hand in at this gossip NPC.
local function GossipHasQuests()
	local info = C_GossipInfo
	if info and info.GetNumAvailableQuests and info.GetNumActiveQuests then
		return (info.GetNumAvailableQuests() or 0) + (info.GetNumActiveQuests() or 0) > 0
	end
	if GetNumGossipAvailableQuests and GetNumGossipActiveQuests then
		return (GetNumGossipAvailableQuests() or 0) + (GetNumGossipActiveQuests() or 0) > 0
	end
	return false
end

local function ShoulderAllowed()
	return ns.db.questCamUncenter or GetCVar("CameraKeepCharacterCentered") ~= "1"
end

-- Speed (0-1) at t along a move of T seconds: half-cosine ramps of ease*T at
-- either end (as Camera.lua's EaseShape).
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

-- Our camera commands: marked, so the log can tell others' apart.
-- /cine debug questlog: our own commands and speed setting changes, noted by
-- name for the next log line.
local function Note(text)
	if cam.log then
		cam.notes = cam.notes or {}
		if #cam.notes < 8 then
			cam.notes[#cam.notes + 1] = text
		end
	end
end

local function Send(name, amount)
	cam.sending = true
	ns.CallCameraFunction(name, amount)
	cam.sending = false
	if not name:find("Zoom") then
		Note(amount and ("%s(%.3f)"):format(name, amount) or name)
	end
end

-- A speed setting put back (noted for the log).
local function RestoreSpeed(cvar)
	if ns.db.savedCVars[cvar] ~= nil then
		Note(cvar .. " back")
		ns.RestoreCVar(cvar)
	end
end

-- The command a mover sends: its grow or shrink one, the yaw's flipped for
-- your left.
local function Command(m)
	local grow = m.growing
	if m == movers.yaw and m.left then
		grow = not grow
	end
	return grow and m.grow or m.shrink
end

-- Settled and drifting to and fro (or about to).
local function Drifting()
	return cam.active and not cam.handedOver and (ns.db.questCamDrift or 0) >= 1
end

local function StopMove(m)
	if not m.moving then
		return
	end
	if m.sent then
		Send(Command(m) .. "Stop")
	end
	m.moving, m.sent, m.stoppedAt = false, nil, GetTime()
	-- (Put back a moment later, so the end of the move can't run at full speed.
	-- Not between the drift's legs: your setting coming back just as the
	-- camera came to rest jumped it.)
	C_Timer.After(SPEED_RESTORE_DELAY, function()
		if not m.moving and not (m == movers.yaw and Drifting()) then
			RestoreSpeed(m.cvar)
		end
	end)
end

-- Moves to `target` degrees, over T seconds.
-- ease: the share spent speeding up (and slowing down), MOVE_EASE if nil.
-- tail: { extra, speed, R }: instead of slowing to a stop at target, it slows
-- only to `speed` (degrees per second) and carries on `extra` degrees further
-- the same way, easing to a stop over R seconds at the end (the side turn
-- flowing into the drift's first leg).
local function MoveTo(m, target, T, ease, tail)
	StopMove(m)
	local final = target
	if tail then
		final = target + (target >= m.amount and tail.extra or -tail.extra)
	end
	m.from, m.target, m.t, m.T = m.amount, final, 0, math.max(MOVE_MIN_TIME, T)
	m.tail = tail and { speed = tail.speed, R = tail.R } or nil
	if math.abs(final - m.amount) < 0.5 then
		m.amount = final
		return
	end
	ns.SaveCVar(m.cvar)
	-- The share of the speed setting the move is sent at: your setting is
	-- then its top speed.
	local yours = tonumber(ns.db.savedCVars[m.cvar]) or m.default
	m.ease = ease or MOVE_EASE
	m.cruise = math.abs(target - m.amount) / (m.T * (1 - m.ease))
	m.limit = m.T + 1 + (tail and (math.abs(final - target) / tail.speed + tail.R) or 0)
	m.share = math.max(m.cruise, m.tail and m.tail.speed or 0) / yours
	-- The setting goes to its lowest a moment before the move starts.
	SetCVar(m.cvar, ("%.2f"):format(MOVE_MIN_SETTING))
	m.primedUntil = GetTime() + MOVE_PRIME_TIME
	m.growing = final > m.amount
	m.lastGrowing = m.growing
	m.moving = true
end

-- A move with a tail: its speed at this point. Up to its cruise, down only
-- to the tail's speed by T, on at that, and once the distance left is what
-- easing to a stop over the tail's R covers, eased to a stop.
local function TailSpeed(m)
	local t, T, R, tail = m.t, m.T, m.ease * m.T, m.tail
	if tail.stopAt then
		local u = (t - tail.stopAt) / tail.R
		return u >= 1 and 0 or tail.from * (1 + math.cos(math.pi * u)) / 2
	end
	local speed
	if t < T - R then
		speed = m.cruise * EaseShape(t, T, m.ease)
	elseif t < T then
		speed = tail.speed + (m.cruise - tail.speed) * EaseShape(t, T, m.ease)
	else
		speed = tail.speed
	end
	if t >= R and math.abs(m.target - m.amount) <= speed * tail.R / 2 then
		tail.stopAt, tail.from = t, speed
	end
	return speed
end

local function StepMove(m, elapsed)
	if not m.moving or GetTime() < m.primedUntil then
		return
	end
	m.t = m.t + elapsed
	-- Done when its curve has eased right down, not when it's counted as far
	-- as asked: the speed sent lags a little behind the curve as it slows (see
	-- MOVE_CHANGE), so it got there early and stopped still moving, a small jump.
	local speed = m.tail and TailSpeed(m) or m.cruise * EaseShape(m.t, m.T, m.ease)
	if m.t >= m.limit or (m.tail and m.tail.stopAt and speed == 0) or (not m.tail and m.t >= m.T) then
		m.amount = m.target
		StopMove(m)
		return
	end
	-- The speed setting for this point on the curve (the move's speed is the
	-- setting times its share).
	local setting = math.max(MOVE_MIN_SETTING, speed / m.share)
	if not m.sent then
		-- The move goes out once, at the primed setting; after that only the
		-- setting changes.
		Note(("%s %s share %.4f"):format(m.cvar, tostring(GetCVar(m.cvar)), m.share))
		Send(Command(m) .. "Start", m.share)
		m.sent = MOVE_MIN_SETTING
	elseif math.abs(setting - m.sent) > m.sent * MOVE_CHANGE then
		SetCVar(m.cvar, ("%.2f"):format(setting))
		m.sent = setting
	end
	-- How far it's come, at the speed actually sent.
	speed = m.sent * m.share
	m.amount = m.amount + (m.growing and speed or -speed) * elapsed
end

-- The zoom. The game doesn't move the camera exactly the distance asked of
-- CameraZoomIn/Out (it can go several times further), and there's no reading
-- where it's heading, only where the camera is: one command for the whole
-- distance went far past the goal. So it's steered along the eased path: at
-- most every ZOOM_SEND_EVERY seconds, a command toward where the path will be
-- ZOOM_LEAD seconds on, from where the camera really is. The game's zoom
-- speed setting is held just above the path's speed meanwhile, so the camera
-- glides between commands instead of hopping to each one (at your own speed,
-- the addon's other zooms' small per-frame steps showed as snaps). Your
-- setting comes back once the camera has held still at the goal.
local ZOOM_SEND_EVERY = 0.1  -- seconds between commands, at least
local ZOOM_LEAD = 0.25       -- seconds ahead on the path each command aims for
local ZOOM_GAIN = 0.6        -- share of the way to that point each command asks for
local ZOOM_HEADROOM = 1.3    -- the speed setting, as a share of the path's speed...
local ZOOM_SPEED_EXTRA = 0.3 -- ...plus this many yards per second
local ZOOM_SETTLE_SPEED = 0.5 -- yards per second once the path's done
local ZOOM_SETTLED = 0.4     -- seconds held still at the goal before it counts as done
local ZOOM_STILL = 0.002     -- yards per frame: less is holding still
local zoomer = { moving = false }

local function Zooming()
	return zoomer.moving
end

-- Done: the speed setting rises back to yours over ZOOM_RELEASE_TIME (all at
-- once, any last bit of the game's own zoom left to go happened in a frame:
-- a hop). restoreNow: at once (you're zooming yourself).
local ZOOM_RELEASE_TIME = 1.5
local function StopZoom(restoreNow)
	if restoreNow then
		zoomer.moving, zoomer.sent, zoomer.release = false, nil, nil
		RestoreSpeed(ZOOM_CVAR)
		return
	end
	if not zoomer.moving then
		return
	end
	zoomer.moving = false
	local yours = tonumber(ns.db.savedCVars[ZOOM_CVAR])
	if yours and zoomer.sent and yours > zoomer.sent then
		zoomer.release = { from = zoomer.sent, to = yours, t = 0 }
		Note("zoom speed easing back")
	else
		zoomer.sent = nil
		RestoreSpeed(ZOOM_CVAR)
	end
end

local function StepZoomRelease(elapsed)
	local release = zoomer.release
	if not release then
		return
	end
	-- Held at the crawl while a turn or tilt is under way or still to come:
	-- one starting as the setting eased back snapped, and waiting for it to
	-- finish first left a long gap between the turn and the tilt.
	if cam.active and (#cam.steps > 0 or movers.yaw.moving or movers.pitch.moving or Drifting()) then
		return
	end
	release.t = release.t + elapsed
	local f = release.t / ZOOM_RELEASE_TIME
	if f >= 1 then
		zoomer.release, zoomer.sent = nil, nil
		RestoreSpeed(ZOOM_CVAR)
		return
	end
	-- (Geometric, so it creeps up from the crawl rather than leaping.)
	SetCVar(ZOOM_CVAR, ("%.2f"):format(release.from * (release.to / release.from) ^ (f * f)))
end

local function SetZoomSpeed(speed)
	if not zoomer.sent or math.abs(speed - zoomer.sent) > zoomer.sent * MOVE_CHANGE then
		SetCVar(ZOOM_CVAR, ("%.2f"):format(speed))
		zoomer.sent = speed
	end
end

-- Share (0-1) of a move covered at t along T seconds, for EaseShape's speed
-- curve (as Camera.lua's EaseProgress).
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

-- Where the path has the camera at t.
local function ZoomPath(t)
	return zoomer.from + (zoomer.goal - zoomer.from) * EaseProgress(t, zoomer.T, MOVE_EASE)
end

-- Zooms to `distance` yards over T seconds.
local function ZoomTo(distance, T)
	local now = GetCameraZoom()
	zoomer.moving = false
	if math.abs(distance - now) < ZOOM_DONE then
		return
	end
	zoomer.release = nil
	ns.SaveCVar(ZOOM_CVAR)
	Note(("zoom to %.2f"):format(distance))
	zoomer.from, zoomer.goal, zoomer.t, zoomer.T = now, distance, 0, math.max(MOVE_MIN_TIME, T)
	zoomer.cruise = math.abs(distance - now) / (zoomer.T * (1 - MOVE_EASE))
	zoomer.last, zoomer.sentAt, zoomer.stillSince, zoomer.sent = now, 0, nil, nil
	zoomer.moving = true
end

local function StepZoom(elapsed)
	if not zoomer.moving then
		return
	end
	local now, zoom = GetTime(), GetCameraZoom()
	zoomer.t = zoomer.t + elapsed
	local t, T = zoomer.t, zoomer.T
	local still = math.abs(zoom - zoomer.last) < ZOOM_STILL
	zoomer.last = zoom
	-- Done once the path's over and it's held still at the goal (or given up on).
	if t >= T and math.abs(zoomer.goal - zoom) < ZOOM_DONE and still then
		zoomer.stillSince = zoomer.stillSince or now
		if now - zoomer.stillSince >= ZOOM_SETTLED then
			StopZoom()
			ns.RestoreZoomLimit() -- (inside it now)
			return
		end
	else
		zoomer.stillSince = nil
	end
	if t >= T + ZOOM_GIVE_UP then
		StopZoom()
		ns.RestoreZoomLimit()
		return
	end
	-- The speed setting: just above the path's speed, then a crawl.
	local speed = ZOOM_SETTLE_SPEED
	if t < T then
		local pathSpeed = zoomer.cruise * EaseShape(t, T, MOVE_EASE)
		speed = math.max(ZOOM_MIN_SPEED, pathSpeed * ZOOM_HEADROOM + ZOOM_SPEED_EXTRA)
	end
	SetZoomSpeed(speed)
	-- Steer toward where the path will be shortly.
	if now - zoomer.sentAt >= ZOOM_SEND_EVERY then
		local miss = ZoomPath(math.min(T, t + ZOOM_LEAD)) - zoom -- (positive: further out)
		if math.abs(miss) > ZOOM_DONE then
			zoomer.sentAt = now
			Send(miss < 0 and "CameraZoomIn" or "CameraZoomOut", math.abs(miss) * ZOOM_GAIN)
		end
	end
end

-- Runs the queued steps in order (cam.steps: { kind, target, T, waitZoom, ease, tail }),
-- once the swing behind you has handed camera follow back. "yaw" and "pitch"
-- moves run one at a time; a "zoom" starts and the next step follows at once
-- (the tilt and the zoom go together). waitZoom: not while the zoom's moving.
local function StepSequence(now)
	while true do
		local drift = cam.active and not cam.handedOver and #cam.steps == 0 and (ns.db.questCamDrift or 0) >= 1
		if movers.yaw.moving or movers.pitch.moving
			or now - math.max(movers.yaw.stoppedAt or 0, movers.pitch.stoppedAt or 0) < (drift and DRIFT_GAP or STEP_GAP) then
			return
		end
		local step = cam.steps[1]
		if drift then
			-- Settled: a slow drift to and fro about the turn's angle, so the
			-- shot isn't stock-still. (Each leg's own gentle start and stop
			-- turn it round at either end.) Each leg's time goes by its
			-- distance, so a first one from the middle doesn't crawl. (The
			-- side turn usually runs on into that first leg itself.)
			-- The first leg carries on the way the camera last turned.
			local half = ns.db.questCamDrift / 2
			if cam.driftOut == nil then
				cam.driftOut = movers.yaw.lastGrowing ~= false
			else
				cam.driftOut = not cam.driftOut
			end
			local target = math.max(0, ns.db.questCamAngle) + (cam.driftOut and half or -half)
			local T = DRIFT_TIME * math.abs(target - movers.yaw.amount) / ns.db.questCamDrift
			step = { "yaw", target, T, false, DRIFT_EASE }
			cam.steps[1] = step
		end
		if not step then
			if not cam.active and movers.yaw.amount == 0 and movers.pitch.amount == 0 then
				ns.ApplyCVarSet(FOLLOW_CVARS, false) -- all back: your camera follow returns
			end
			return
		end
		if ns.RECENTER_CVARS.active then
			cam.followBackAt = nil
			return
		end
		cam.followBackAt = cam.followBackAt or now
		if now < (cam.stepsAt or 0) or now - cam.followBackAt < FOLLOW_GAP or (step[4] and Zooming()) then
			return
		end
		table.remove(cam.steps, 1)
		if step[1] == "zoom" then
			ZoomTo(step[2], step[3])
		else
			ns.ApplyCVarSet(FOLLOW_CVARS, true)
			if step[6] then
				-- (The turn carries on into the drift's first leg: the next
				-- leg heads back.)
				cam.driftOut = step[2] >= movers.yaw.amount
			end
			MoveTo(movers[step[1]], step[2], step[3], step[5], step[6])
		end
	end
end

-- You moved the camera yourself: it's yours, nothing to put back.
local function HandOver()
	for _, m in pairs(movers) do
		StopMove(m)
		m.amount = 0
	end
	StopZoom(true) -- (your own zooming goes at your speed)
	ns.RestoreZoomLimit()
	cam.steps, cam.handedOver = {}, true
	ns.ApplyCVarSet(FOLLOW_CVARS, false)
end

-- /cine debug questlog: every frame of each quest cam, saved (ns.db.questCamLog)
-- for reading after a /reload.
local function Log(now)
	local log = cam.log
	if not log or #log >= LOG_MAX then
		return
	end
	local yaw, pitch = movers.yaw, movers.pitch
	log[#log + 1] = ("%.3f yaw %.1f%s sent %s pitch %.1f%s zoom %.2f%s %s follow %s recenter %s steps %d%s"):format(
		now - cam.startedAt, yaw.amount, yaw.moving and "*" or "", yaw.sent and ("%.1f"):format(yaw.sent) or "-",
		pitch.amount, pitch.moving and "*" or "", GetCameraZoom and GetCameraZoom() or -1,
		Zooming() and "*" or "", zoomer.moving and ("speed %.2f path %.2f"):format(zoomer.sent or 0, ZoomPath(math.min(zoomer.t, zoomer.T))) or "-",
		tostring(GetCVar("cameraSmoothStyle")),
		tostring(ns.RECENTER_CVARS.active or false), #cam.steps,
		cam.others and (" OTHERS: " .. table.concat(cam.others, " ")) or "")
		.. (cam.notes and (" | " .. table.concat(cam.notes, " ")) or "")
	cam.others, cam.notes = nil, nil
end

local function Start()
	local db = ns.db
	cam.active, cam.closingAt, cam.handedOver = true, nil, false
	cam.startedAt = GetTime()
	cam.log = nil
	if db.debugQuestCam then
		db.questCamLog = {}
		cam.log = db.questCamLog
	end
	-- Your own distance (the AFK camera's slow zoom, if it was going, lets go
	-- where it is: this zoom takes over).
	cam.zoom, cam.zoomedTo = ns.PlayerZoom and ns.PlayerZoom(), nil
	ns.TakeOverZoom()
	if cam.zoom and GetCameraZoom and GetCameraZoom() > db.questCamDistance + ZOOM_MARGIN then
		cam.zoomedTo = db.questCamDistance
		ZoomTo(db.questCamDistance, db.questCamZoomTime)
	else
		ns.RestoreZoomLimit() -- (close already: inside it)
	end
	-- (Held on a little past its time so it settles fully behind you.)
	ns.CenterCamera(db.questCamTime + SWING_SETTLE, SWING_YAW, 0, SWING_RAMP)
	-- Then round to the side as the zoom carries on, and down after that.
	-- (A move still undoing a past conversation's carries on from where it is.)
	-- Which side: there's no knowing where the quest giver stands (only your
	-- own and your group's positions are given), nor what's around you, so
	-- with questCamSide "random" it's picked afresh each time.
	-- (Unless still turning back from the last one: it carries on that way.)
	if movers.yaw.amount == 0 then
		if db.questCamSide == "random" then
			movers.yaw.left = math.random() < 0.5
		else
			movers.yaw.left = db.questCamSide == "left"
		end
		Note("side " .. (movers.yaw.left and "left" or "right"))
	end
	cam.steps, cam.stepsAt = {}, cam.startedAt + db.questCamTime + SWING_SETTLE
	cam.driftOut, movers.yaw.lastGrowing = nil, nil
	local turnTime = db.questCamAngle > 0 and db.questCamTurnTime or 0
	if db.questCamAngle > 0 then
		-- With nothing after it but the drift, the turn flows straight into it
		-- (stopping and starting again showed as a pause).
		local tail
		if (db.questCamDrift or 0) >= 1 and db.questCamLower <= 0 then
			tail = { extra = db.questCamDrift / 2, R = DRIFT_EASE * DRIFT_TIME,
				speed = db.questCamDrift / (DRIFT_TIME * (1 - DRIFT_EASE)) }
		end
		table.insert(cam.steps, { "yaw", db.questCamAngle, turnTime, nil, nil, tail })
	end
	if db.questCamLower > 0 then
		table.insert(cam.steps, { "pitch", db.questCamLower, TILT_TIME, false, TILT_EASE })
	end
	if db.questCamOverShoulder and db.questCamShoulder > 0 and ShoulderAllowed() then
		SHOULDER_CVARS.values.test_cameraOverShoulder = ("%.2f"):format(db.questCamShoulder)
		if db.questCamUncenter then
			ns.ApplyCVarSet(CENTERED_CVARS, true)
		end
		ns.ApplyCVarSet(SHOULDER_CVARS, true)
	end
end

local function Stop()
	cam.active, cam.closingAt = false, nil
	ns.ApplyCVarSet(SHOULDER_CVARS, false)
	ns.ApplyCVarSet(CENTERED_CVARS, false)
	-- The zoom out and the turn back behind you together, then the tilt up.
	cam.steps, cam.stepsAt = {}, 0
	if not cam.handedOver then
		for _, m in pairs(movers) do
			StopMove(m) -- (cut short if still on the way in: undone from where it got to)
		end
	end
	-- Back out to your distance, unless you zoomed yourself while talking.
	-- (Still on its way in counts as ours.)
	if cam.zoomedTo and cam.zoom and GetCameraZoom
		and (zoomer.moving or math.abs(GetCameraZoom() - cam.zoomedTo) < ZOOM_YOURS) then
		table.insert(cam.steps, { "zoom", cam.zoom, ns.db.questCamZoomOutTime })
	end
	if not cam.handedOver then
		local turnBack = math.max(BACK_MIN, ns.db.questCamTurnTime * BACK_SHARE)
		if movers.yaw.amount ~= 0 then
			table.insert(cam.steps, { "yaw", 0, turnBack })
		end
		if movers.pitch.amount ~= 0 then
			table.insert(cam.steps, { "pitch", 0, TILT_BACK_TIME })
		end
	end
	cam.zoom, cam.zoomedTo = nil, nil
end

-- The quest giver event (Events page): its camera isn't "none".
local function Wanted()
	local db = ns.db
	return db and db.enabled and db.eventQuestCamera ~= "none" and not InCombatLockdown()
		and not UnitOnTaxi("player") and not ns.IsCameraOffHere("quest")
end

local OPENS = {
	QUEST_GREETING = true, QUEST_DETAIL = true, QUEST_PROGRESS = true, QUEST_COMPLETE = true,
	GOSSIP_SHOW = true,
}

-- Talking to a quest giver: cam.since is when it started (nil: not talking),
-- cam.closingAt when its window closed (it ends after CLOSE_GRACE, unless
-- another opens meanwhile, going from gossip to the quest text).
local function OnEvent(_, event)
	if OPENS[event] then
		if event == "GOSSIP_SHOW" and not cam.since and not (ns.db and ns.db.questCamAllGossip)
			and not GossipHasQuests() then
			return -- an innkeeper or the like: not a quest giver
		end
		if not cam.since then
			cam.since, cam.cancelled = GetTime(), nil -- a new conversation
		end
		cam.closingAt = nil
	elseif event == "PLAYER_LOGOUT" then
		-- No time to glide: everything goes straight back (the zoom isn't saved).
		for _, m in pairs(movers) do
			StopMove(m)
			ns.RestoreCVar(m.cvar)
		end
		StopZoom(true)
		ns.ApplyCVarSet(FOLLOW_CVARS, false)
		ns.ApplyCVarSet(SHOULDER_CVARS, false)
		ns.ApplyCVarSet(CENTERED_CVARS, false)
	elseif event == "PLAYER_REGEN_DISABLED" then
		if cam.since then
			cam.closingAt = 0 -- a fight: ends now
		end
	elseif cam.since then
		cam.closingAt = cam.closingAt or GetTime()
	end
end

local function OnUpdate(_, elapsed)
	if ns.IsSuspended() then
		return -- stopped after an error (Diagnostics.lua)
	end
	local now = GetTime()
	-- (The moves carry on after the window closes, going back.)
	StepMove(movers.yaw, elapsed)
	StepMove(movers.pitch, elapsed)
	StepZoom(elapsed)
	StepZoomRelease(elapsed)
	local busy = cam.active or #cam.steps > 0 or movers.yaw.moving or movers.pitch.moving or zoomer.moving
	if not cam.handedOver and cam.startedAt and busy
		and ns.GetLastCameraInput() > cam.startedAt + INPUT_GRACE then
		HandOver()
	end
	StepSequence(now)
	if busy or Zooming() or zoomer.release then
		Log(now)
	end
	if not cam.since then
		return
	end
	if cam.closingAt and now - cam.closingAt >= CLOSE_GRACE then
		cam.since, cam.closingAt = nil, nil
		if cam.active then
			Stop()
		end
	elseif cam.active and not Wanted() then
		Stop() -- turned off (or set to no camera) mid-conversation
		cam.since = nil
	elseif cam.active and ns.playerMoving then
		Stop() -- walked off: back to normal, and no more until the next conversation
		cam.cancelled = true
	elseif not cam.active and not cam.closingAt and not cam.cancelled and not ns.playerMoving and Wanted()
		and now - cam.since >= (tonumber(ns.db.eventQuestDelay) or 0) then
		Start()
	end
end

local frame = CreateFrame("Frame")
for event in pairs(OPENS) do
	frame:RegisterEvent(event)
end
for _, event in ipairs({ "GOSSIP_CLOSED", "QUEST_FINISHED", "PLAYER_REGEN_DISABLED", "PLAYER_LOGOUT" }) do
	frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", OnEvent)

-- For the log: camera commands that aren't ours (the addon's other cameras,
-- the zoom, your own input), noted by name until the next log line.
for _, name in ipairs({ "MoveViewLeftStart", "MoveViewLeftStop", "MoveViewRightStart", "MoveViewRightStop",
	"MoveViewUpStart", "MoveViewUpStop", "MoveViewDownStart", "MoveViewDownStop", "CameraZoomIn", "CameraZoomOut",
	"SetView", "ResetView" }) do
	if _G[name] then
		hooksecurefunc(name, function()
			if cam.log and not cam.sending then
				cam.others = cam.others or {}
				if #cam.others < 8 then
					cam.others[#cam.others + 1] = name
				end
			end
		end)
	end
end
frame:SetScript("OnUpdate", OnUpdate)

-- For /cine debug: whether the quest cam is on now, its moves and the shoulder state.
function ns.GetQuestCamDebug()
	return {
		active = cam.active, talking = cam.since ~= nil, zoom = cam.zoom, zoomedTo = cam.zoomedTo,
		turned = movers.yaw.amount, lowered = movers.pitch.amount, handedOver = cam.handedOver,
		shoulder = GetCVar("test_cameraOverShoulder"), centered = GetCVar("CameraKeepCharacterCentered"),
		shoulderOn = SHOULDER_CVARS.active or false,
	}
end

-- /cine starttest <kind>: one slow turn (about 30 degrees left) on its own,
-- to find what snaps as the quest cam's moves start. Stand still; nothing
-- else moves the camera meanwhile. Your turn speed setting comes back after.
--   setting: the quest cam's way (the low speed set first, then the move,
--            then the setting eased up and down)
--   share:   your setting left alone; the move sent at a share of it and
--            re-sent as the speed changes (each send restarts the turn)
--   steady:  your setting left alone; one move at a steady 10 degrees/sec
--   nomove:  only the setting changed to the low speed, no move at all
--   gentle:  the quest cam's way now: sent at a share of the setting, the
--            setting eased from 1 up toward yours and back (a far gentler start)
--   tilt:    the same, tilting down (about 20 degrees) instead
do
	local YAW = "cameraYawMoveSpeed"
	local TEST_TIME, TEST_PEAK, TEST_WAIT = 4, 12, 1 -- seconds, degrees per second at most, seconds first
	local KINDS = { setting = true, share = true, steady = true, nomove = true, gentle = true, tilt = true }
	local PITCH = "cameraPitchMoveSpeed"
	local test
	local runner = CreateFrame("Frame")

	local function Finish()
		if test.kind == "tilt" then
			ns.CallCameraFunction("MoveViewDownStop")
		elseif test.kind ~= "nomove" then
			ns.CallCameraFunction("MoveViewLeftStop")
		end
		runner:SetScript("OnUpdate", nil)
		C_Timer.After(SPEED_RESTORE_DELAY, function()
			ns.RestoreCVar(YAW)
			ns.RestoreCVar(PITCH)
		end)
		ns.Print("start test (" .. test.kind .. "): done")
		test = nil
	end

	local function OnTestUpdate(_, elapsed)
		test.t = test.t + elapsed
		local t = test.t - TEST_WAIT
		if t < 0 then
			return
		end
		local yours = tonumber(ns.db.savedCVars[YAW] or GetCVar(YAW)) or 180
		local speed = math.max(MOVE_MIN_SPEED, TEST_PEAK * EaseShape(t, TEST_TIME, MOVE_EASE))
		local now = GetTime()
		if test.kind == "setting" then
			if not test.primedAt then
				SetCVar(YAW, ("%.2f"):format(MOVE_MIN_SPEED))
				test.primedAt = now
			elseif not test.sent then
				if now - test.primedAt >= MOVE_PRIME_TIME then
					ns.CallCameraFunction("MoveViewLeftStart", 1)
					test.sent = MOVE_MIN_SPEED
				end
			elseif math.abs(speed - test.sent) > test.sent * MOVE_CHANGE then
				SetCVar(YAW, ("%.2f"):format(speed))
				test.sent = speed
			end
		elseif test.kind == "share" then
			if not test.sent or (math.abs(speed - test.sent) > test.sent * 0.03 and now - test.sentAt >= 0.1) then
				ns.CallCameraFunction("MoveViewLeftStart", speed / yours)
				test.sent, test.sentAt = speed, now
			end
		elseif test.kind == "steady" then
			if not test.sent then
				ns.CallCameraFunction("MoveViewLeftStart", 10 / yours)
				test.sent = 10
			end
		elseif test.kind == "gentle" or test.kind == "tilt" then
			local cvar = test.kind == "tilt" and PITCH or YAW
			local peak = test.kind == "tilt" and TEST_PEAK * 2 / 3 or TEST_PEAK
			local share = peak / (tonumber(ns.db.savedCVars[cvar]) or (cvar == PITCH and 90 or 180))
			local setting = math.max(MOVE_MIN_SETTING, peak * EaseShape(t, TEST_TIME, MOVE_EASE) / share)
			if not test.primedAt then
				SetCVar(cvar, ("%.2f"):format(MOVE_MIN_SETTING))
				test.primedAt = now
			elseif not test.sent then
				if now - test.primedAt >= MOVE_PRIME_TIME then
					ns.CallCameraFunction(test.kind == "tilt" and "MoveViewDownStart" or "MoveViewLeftStart", share)
					test.sent = MOVE_MIN_SETTING
				end
			elseif math.abs(setting - test.sent) > test.sent * MOVE_CHANGE then
				SetCVar(cvar, ("%.2f"):format(setting))
				test.sent = setting
			end
		elseif not test.sent then -- nomove
			SetCVar(YAW, ("%.2f"):format(MOVE_MIN_SPEED))
			test.sent = MOVE_MIN_SPEED
		end
		if t >= TEST_TIME then
			Finish()
		end
	end

	-- Returns false and why if it can't start.
	function ns.QuestCamStartTest(kind)
		if not KINDS[kind] then
			return false, "pick one: gentle, tilt, setting, share, steady or nomove"
		end
		if test then
			return false, "one's already running"
		end
		if cam.active or movers.yaw.moving or movers.pitch.moving then
			return false, "not while the quest cam is moving"
		end
		if kind == "setting" or kind == "nomove" or kind == "gentle" then
			ns.SaveCVar(YAW)
		elseif kind == "tilt" then
			ns.SaveCVar(PITCH)
		end
		test = { kind = kind, t = 0 }
		runner:SetScript("OnUpdate", OnTestUpdate)
		return true
	end
end
