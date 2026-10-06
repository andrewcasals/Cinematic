-- Cinematic: effects that follow cinematic mode. Hidden names, music,
-- nameplates, world tooltips and the letterbox bars.
local _, ns = ...

local letterboxProgress = 0
ns.letterboxDirty = false
-- Game settings (CVars) that change while cinematic. The player's original
-- values are saved on the way in and put back on the way out. Originals are
-- also kept in the saved variables so a crash or disconnect can't leave names
-- switched off for good. CVars this client doesn't have are skipped.
local CVAR_SETS = {
	{
		option = "hideNames",
		values = {
			UnitNameOwn = "0", UnitNameNPC = "0", UnitNameHostleNPC = "0",
			UnitNameInteractiveNPC = "0", UnitNameFriendlySpecialNPCName = "0",
			UnitNameNonCombatCreatureName = "0",
			UnitNameFriendlyPlayerName = "0", UnitNameFriendlyMinionName = "0",
			UnitNameFriendlyPetName = "0", UnitNameFriendlyGuardianName = "0",
			UnitNameFriendlyTotemName = "0",
			UnitNameEnemyPlayerName = "0", UnitNameEnemyMinionName = "0",
			UnitNameEnemyPetName = "0", UnitNameEnemyGuardianName = "0",
			UnitNameEnemyTotemName = "0",
		},
	},
}

-- Switched off once plates have faded out (so invisible plates can't be
-- clicked). Can't be changed during combat lockdown.
local PLATE_CVARS = {
	secure = true,
	values = { nameplateShowEnemies = "0", nameplateShowFriends = "0", nameplateShowFriendlyNPCs = "0" },
}

-- Floating combat text (damage and healing numbers, like "+10" from a heal or
-- regen): off in cinematic mode while you're out of combat; back for fights.
-- CVars this client doesn't have are skipped.
local COMBAT_TEXT_CVARS = {
	values = {
		enableFloatingCombatText = "0",
		floatingCombatTextCombatHealing = "0",
		floatingCombatTextCombatDamage = "0",
		floatingCombatTextCombatHealingAbsorbSelf = "0",
		floatingCombatTextCombatHealingAbsorbTarget = "0",
		floatingCombatTextPetMeleeDamage = "0",
		floatingCombatTextPetSpellDamage = "0",
	},
}

function ns.UpdateCVars(cinematic)
	for _, set in ipairs(CVAR_SETS) do
		ns.ApplyCVarSet(set, cinematic and ns.db[set.option] or false)
	end
	local inCombat = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	ns.ApplyCVarSet(COMBAT_TEXT_CVARS, (cinematic and ns.db.hideCombatText and not inCombat) or false)
end

-- Music fades by ramping the music volume from 0 up to the player's own
-- volume and back. If music was already on, it's left completely alone.
ns.music = { managing = false, level = 0, volume = 1 }

function ns.StopMusicNow()
	if ns.music.managing then
		ns.RestoreCVar("Sound_EnableMusic")
		ns.RestoreCVar("Sound_MusicVolume")
		ns.music.managing = false
	end
end

-- Muting music in combat: a 0-1 level that fades down during fights and back
-- up afterwards. Music the addon plays applies it directly; the player's own
-- music gets its volume saved (crash-safe) and ducked, then restored.
local COMBAT_MUSIC_FADE = 1
-- musicOff: the player's own music switched off by the mute; managedOff: the
-- addon's cinematic music switched off by it. Kept apart so one never undoes
-- the other.
local combatMusic = { level = 1, ducking = false, original = 1, musicOff = false, managedOff = false,
	lastFightAt = -math.huge }

-- Once fully faded out, music is switched off rather than left playing at
-- zero volume; switching it back on when the mute ends makes the game start a
-- fresh track (instead of resuming one halfway through) as it fades back in.
local function SetMuteMusicOff(flag, off)
	if off ~= combatMusic[flag] then
		combatMusic[flag] = off
		SetCVar("Sound_EnableMusic", off and 0 or 1)
	end
end

local function UpdateCombatMusic(elapsed)
	-- Muted while fighting (if chosen) or in a place chosen under "Mute music in".
	-- Only when the addon handles music at all: with "Play music in cinematic
	-- mode" off, the player's volumes are left alone (any ducking eases back).
	local handlesMusic = ns.db.musicInCinematic
	local now = GetTime()
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		combatMusic.lastFightAt = now
	end
	-- Stays muted until musicCombatResume seconds after the last fight ended,
	-- so back-to-back fights don't bring the music in and out.
	local fighting = handlesMusic and ns.db.musicOffInCombat
		and now - combatMusic.lastFightAt < ns.db.musicCombatResume
	local flying = handlesMusic and ns.db.musicOffOnFlights and UnitOnTaxi("player")
	-- Music belongs to the camera modes (flying, RP walking, standing still):
	-- once you move on from one, it fades out, and a fresh track comes in when
	-- the next one starts.
	if not (handlesMusic and ns.db.musicPauseWhenMoving) or (ns.InCameraMode and ns.InCameraMode()) then
		combatMusic.movingPaused = false
	elseif ns.playerMoving then
		combatMusic.movingPaused = true
		combatMusic.pauseFade = true
	end
	local otherMute = fighting or flying or (handlesMusic and ns.IsMusicBlocked())
	local target = (otherMute or combatMusic.movingPaused) and 0 or 1
	-- The move-on pause fades at its own speed, out and back in again; the
	-- other mutes use the quick fade.
	if otherMute or combatMusic.level >= 1 then
		combatMusic.pauseFade = false
	end
	local fade = combatMusic.pauseFade and ns.db.musicPauseFadeTime or COMBAT_MUSIC_FADE
	if combatMusic.level ~= target then
		combatMusic.level = ns.Approach(combatMusic.level, target, elapsed, fade)
	end
	local silent = combatMusic.level <= 0

	if ns.music.managing then
		-- The addon's own music: UpdateMusic applies the level to the volume; here
		-- it's just switched off while silent (its on/off is already saved).
		SetMuteMusicOff("managedOff", silent)
		return
	end
	combatMusic.managedOff = false -- the addon's music has stopped; its on/off was restored

	-- The player's own music: save its volume and on/off, then duck it.
	if combatMusic.level < 1 and (GetCVar("Sound_EnableMusic") == "1" or combatMusic.musicOff) then
		if not combatMusic.ducking then
			ns.SaveCVar("Sound_MusicVolume")
			ns.SaveCVar("Sound_EnableMusic")
			combatMusic.original = tonumber(ns.db.savedCVars.Sound_MusicVolume) or 1
			combatMusic.ducking = true
		end
		SetCVar("Sound_MusicVolume", ("%.3f"):format(combatMusic.original * combatMusic.level))
		SetMuteMusicOff("musicOff", silent)
	elseif combatMusic.ducking and combatMusic.level >= 1 then
		ns.RestoreCVar("Sound_MusicVolume")
		ns.RestoreCVar("Sound_EnableMusic")
		combatMusic.ducking, combatMusic.musicOff = false, false
	end
end

function ns.StopCombatMusicNow()
	if combatMusic.ducking then
		ns.RestoreCVar("Sound_MusicVolume")
		ns.RestoreCVar("Sound_EnableMusic")
		combatMusic.ducking = false
	end
	combatMusic.musicOff, combatMusic.managedOff = false, false
	combatMusic.level = 1
end

-- Times music starts despite music fatigue: on a flight, once the
-- standing-still timer has run, or in a different zone from the last music.
local function FatigueOverridden()
	if ns.db.fatigueIgnoreOnFlights and UnitOnTaxi("player") then
		return true
	end
	local stillSince = ns.GetStillSince()
	if ns.db.fatigueIgnoreWhenWalking and ns.IsRPWalking and ns.IsRPWalking() then
		return true
	end
	if ns.db.fatigueIgnoreWhenAutoRun and ns.IsAutoRunning and ns.IsAutoRunning() then
		return true
	end
	if ns.db.fatigueIgnoreWhenCozy and ns.IsCozy and ns.IsCozy() then
		return true
	end
	if ns.db.fatigueIgnoreWhenIdle and stillSince and GetTime() - stillSince >= ns.db.idleOrbitDelay then
		return true
	end
	local zone = GetRealZoneText()
	if ns.db.fatigueIgnoreNewZone and zone and zone ~= "" and ns.db.lastMusicZone
		and zone ~= ns.db.lastMusicZone then
		return true
	end
	return false
end

-- New song: music is switched off and back on a moment later, which makes the
-- game start a fresh track. Happens as the flight rotation starts (or at
-- takeoff with flight rotation off) and as the standing-still camera starts,
-- once per flight / per spell of standing still. Skipped if music isn't
-- playing, or on flights while muted there (a fresh track comes on landing).
local NEW_SONG_GAP = 0.2
local wasOnTaxiForMusic = false
local restartToken = 0
local songFlight = false -- this flight already got its new song
local songStillSince     -- the standing-still spell that already got one
-- RP walking: a new song when you set off, but not for every pause. Stopping
-- for less than this long and walking on counts as the same walk.
local WALK_SONG_GAP = 20
local lastWalkingAt = -math.huge
local lastStillCameraAt = -math.huge -- last moment the standing-still camera's timer had run
local lastAutoRunAt = -math.huge
local lastCozyAt = -math.huge

local function RestartMusic()
	if not ns.db.musicInCinematic or GetCVar("Sound_EnableMusic") ~= "1" then
		return
	end
	restartToken = restartToken + 1
	local token = restartToken
	SetCVar("Sound_EnableMusic", 0)
	C_Timer.After(NEW_SONG_GAP, function()
		-- Only switch back on if nothing else touched music in between.
		if token == restartToken and GetCVar("Sound_EnableMusic") == "0" then
			SetCVar("Sound_EnableMusic", 1)
		end
	end)
end

local function NewSongForFlight()
	if songFlight or not ns.db.musicNewSongOnFlights or ns.db.musicOffOnFlights then
		return
	end
	songFlight = true
	RestartMusic()
end

-- Called by the camera when a rotation starts ("taxiOrbit" or "idleOrbit").
-- It also restarts after you move the camera; only the first start counts.
function ns.OnRotationStart(prefix)
	if prefix == "taxiOrbit" then
		NewSongForFlight()
	elseif ns.db.musicNewSongWhenIdle and ns.stillSince and songStillSince ~= ns.stillSince then
		songStillSince = ns.stillSince
		RestartMusic()
	end
end

function ns.UpdateMusic(cinematic, elapsed)
	local now = GetTime()
	local still = ns.GetStillSince()
	if still and now - still >= ns.db.idleOrbitDelay then
		lastStillCameraAt = now
	end
	-- RP walking and auto-running: a new song when you set off, but not when
	-- carrying straight on from another camera mode (they hand over seamlessly),
	-- and not for a short pause in the same walk or run.
	local walking = ns.IsRPWalking and ns.IsRPWalking()
	local autoRunning = ns.IsAutoRunning and ns.IsAutoRunning()
	local fromStill = now - lastStillCameraAt < 1
	if walking then
		local fromRun = now - lastAutoRunAt < 1
		if now - lastWalkingAt > WALK_SONG_GAP and ns.db.musicNewSongWhenWalking
			and not fromStill and not fromRun then
			RestartMusic()
		end
		lastWalkingAt = now
	elseif autoRunning then
		local fromWalk = now - lastWalkingAt < 1
		if now - lastAutoRunAt > WALK_SONG_GAP and ns.db.musicNewSongWhenAutoRun
			and not fromStill and not fromWalk then
			RestartMusic()
		end
		lastAutoRunAt = now
	end
	-- Cozy camera: a new song as it starts; standing up briefly and settling
	-- back down counts as the same spell.
	if ns.IsCozy and ns.IsCozy() then
		if now - lastCozyAt > WALK_SONG_GAP and ns.db.musicNewSongWhenCozy then
			RestartMusic()
		end
		lastCozyAt = now
	end
	local onTaxi = UnitOnTaxi("player")
	if onTaxi ~= wasOnTaxiForMusic then
		wasOnTaxiForMusic = onTaxi
		songFlight = false
		if onTaxi and not ns.db.taxiOrbit then
			NewSongForFlight() -- no rotation to wait for: new song at takeoff
		end
	end
	UpdateCombatMusic(elapsed)
	local want = cinematic and ns.db.musicInCinematic
	if want and not ns.music.managing then
		if GetCVar("Sound_EnableMusic") == "1" then
			return
		end
		-- Music fatigue: started music recently? Stay quiet this time. (Saved as
		-- real time, so a /reload doesn't reset it.)
		local last = ns.db.lastMusicStartedAt
		if ns.db.musicFatigue > 0 and last and time() - last < ns.db.musicFatigue * 60
			and not FatigueOverridden() then
			return
		end
		ns.db.lastMusicStartedAt = time()
		ns.db.lastMusicZone = GetRealZoneText()
		ns.SaveCVar("Sound_EnableMusic")
		ns.SaveCVar("Sound_MusicVolume")
		ns.music.managing = true
		ns.music.level = 0
		ns.music.volume = tonumber(ns.db.savedCVars.Sound_MusicVolume) or 1
		SetCVar("Sound_MusicVolume", 0)
		SetCVar("Sound_EnableMusic", 1)
	end
	if not ns.music.managing then
		return
	end

	local target = want and 1 or 0
	if ns.music.level ~= target or combatMusic.level < 1 or ns.music.combatApplied then
		ns.music.level = ns.Approach(ns.music.level, target, elapsed, ns.db.musicFadeTime)
		SetCVar("Sound_MusicVolume", ("%.3f"):format(ns.music.volume * ns.music.level * combatMusic.level))
		-- Keep writing until the combat level is back to full.
		ns.music.combatApplied = combatMusic.level < 1
	end
	if ns.music.level == 0 and not want then
		ns.StopMusicNow()
	end
end

-- Nameplates fade by setting the alpha of each plate's unit frame, then get
-- switched off once invisible. On the way back they're switched on straight
-- away and faded in.
ns.plates = { level = 1, off = false }

-- Ambience follows music: while cinematic, the ambient sound volume becomes a
-- share (ambienceScale) of the music volume as it currently plays, so it
-- tracks the music fade too. Eases in and out over musicFadeTime, starting
-- from and returning to the player's own ambience volume (saved crash-safe).
local AMBIENCE_EPSILON = 0.005 -- skip CVar writes for imperceptible changes
local ambience = { level = 0, active = false, original = 1, written = nil, current = nil, holdUntil = 0 }

-- The music's full volume (what it plays at once faded in) and how much of
-- it is playing right now (0 = none: off, muted, or skipped for fatigue).
local function MusicFullVolume()
	if ns.music.managing then
		return ns.music.volume
	end
	if combatMusic.ducking then
		return combatMusic.original
	end
	return tonumber(GetCVar("Sound_MusicVolume")) or 0
end

local function MusicPresence()
	if combatMusic.musicOff or combatMusic.managedOff then
		return 0
	end
	if ns.music.managing then
		return ns.music.level * combatMusic.level
	end
	if GetCVar("Sound_EnableMusic") ~= "1" then
		return 0
	end
	return combatMusic.level
end

function ns.StopAmbienceNow()
	if ambience.active then
		ns.RestoreCVar("Sound_AmbienceVolume")
		ambience.active, ambience.level, ambience.written, ambience.current = false, 0, nil, nil
	end
end

-- After a /reload (or login) the player's original ambience volume is still in
-- the saved settings, and the lowered volume is still applied: carry on from
-- there instead of jumping back. Cinematic mode only resumes after the fade
-- delay, so hold the current level until then.
local function AdoptSavedAmbience()
	local saved = ns.db.savedCVars.Sound_AmbienceVolume
	if saved == nil or ambience.active then
		return
	end
	ambience.active = true
	ambience.original = tonumber(saved) or 1
	ambience.level = 1
	ambience.current = tonumber(GetCVar("Sound_AmbienceVolume")) or ambience.original
	ambience.written = ambience.current
	ambience.holdUntil = GetTime() + ns.db.delay + 2
end

function ns.UpdateAmbience(cinematic, elapsed)
	AdoptSavedAmbience()
	-- Like the music mutes, only when the addon handles music at all.
	local want = cinematic and ns.db.ambienceFollowsMusic and ns.db.musicInCinematic
	if want and not ambience.active then
		ns.SaveCVar("Sound_AmbienceVolume")
		ambience.active = true
		ambience.original = tonumber(ns.db.savedCVars.Sound_AmbienceVolume) or 1
		ambience.current = ambience.original
	end
	if not ambience.active then
		return
	end
	-- You changed the ambience volume yourself (in the sound settings) while
	-- it was lowered: that's your new level, to come back to afterwards.
	local actual = tonumber(GetCVar("Sound_AmbienceVolume"))
	if actual and ambience.written and math.abs(actual - ambience.written) > AMBIENCE_EPSILON then
		ambience.original = actual
		ns.db.savedCVars.Sound_AmbienceVolume = tostring(actual)
		ambience.current, ambience.written = actual, actual
	end
	if not want and GetTime() < ambience.holdUntil then
		return -- just reloaded: wait for cinematic mode to come back
	end
	ambience.level = ns.Approach(ambience.level, want and 1 or 0, elapsed, ns.db.musicFadeTime)
	-- Ambience steps down to its share of the music only as far as music is
	-- actually playing; with no music it stays at the player's own level.
	local desired = math.min(1, MusicFullVolume() * ns.db.ambienceScale)
	local share = ambience.level * MusicPresence()
	local target = ambience.original + (desired - ambience.original) * share
	-- However the target moves (music restarting, the scale changing), the
	-- volume itself only ever glides there, at the music fade speed.
	ambience.current = ns.Approach(ambience.current or target, target, elapsed, ns.db.musicFadeTime)
	if ambience.level <= 0 and not want and math.abs(ambience.current - ambience.original) < AMBIENCE_EPSILON then
		ns.StopAmbienceNow()
		return
	end
	if not ambience.written or math.abs(ambience.current - ambience.written) > AMBIENCE_EPSILON then
		ambience.written = ambience.current
		SetCVar("Sound_AmbienceVolume", ("%.3f"):format(ambience.current))
	end
end

-- For /cine debug ambience.
function ns.GetAmbienceDebug()
	return {
		active = ambience.active, level = ambience.level, original = ambience.original,
		current = ambience.current, written = ambience.written,
		saved = ns.db.savedCVars.Sound_AmbienceVolume, cvar = GetCVar("Sound_AmbienceVolume"),
		musicVolume = MusicFullVolume(), presence = MusicPresence(),
		hold = math.max(0, ambience.holdUntil - GetTime()),
	}
end

-- Campfire crackle: while the cozy camera runs at a campfire (one of its buffs),
-- a fire loop plays; it fades out when the cozy camera ends or you leave the
-- fire. If the sound stops by itself, it's started again.
local CRACKLE_SOUND = 3347      -- CampFireSmallLoop (3240 is Elwynn Campfire Loop)
local CRACKLE_FADE_MS = 1500
local crackleHandle

local function StopCrackle()
	if crackleHandle then
		StopSound(crackleHandle, CRACKLE_FADE_MS)
		crackleHandle = nil
	end
end

local function StartCrackle()
	local ok, willPlay, handle = pcall(PlaySound, CRACKLE_SOUND, "SFX", false, true)
	if ok and willPlay then
		crackleHandle = handle
	end
end

local crackleWatcher = CreateFrame("Frame")
crackleWatcher:RegisterEvent("SOUNDKIT_FINISHED")
crackleWatcher:SetScript("OnEvent", function(_, _, handle)
	if handle == crackleHandle then
		crackleHandle = nil -- ended by itself; UpdateCrackle starts it again if still wanted
	end
end)

function ns.UpdateCrackle(cinematic)
	local want = cinematic and ns.db.cozyCrackle and ns.IsCozy and ns.IsCozy()
		and ns.IsAtCampfire and ns.IsAtCampfire()
	if want and not crackleHandle then
		StartCrackle()
	elseif not want then
		StopCrackle()
	end
end

function ns.SetPlateAlpha(plate, alpha)
	if plate and plate.UnitFrame and not (plate.IsForbidden and plate:IsForbidden()) then
		plate.UnitFrame:SetAlpha(alpha)
	end
end

local function SetAllPlatesAlpha(alpha)
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		ns.SetPlateAlpha(plate, alpha)
	end
end

function ns.ShowPlatesNow()
	if ns.plates.off and not InCombatLockdown() then
		ns.ApplyCVarSet(PLATE_CVARS, false)
		ns.plates.off = false
		ns.plates.level = 0
	end
end

function ns.UpdatePlates(cinematic, elapsed)
	-- Nameplate settings can't change in combat, so plates show for every
	-- fight (even when staying cinematic) and hide again afterwards.
	local hide = cinematic and ns.db.hidePlates and not InCombatLockdown()
	if not hide then
		ns.ShowPlatesNow()
	end

	local target = hide and 0 or 1
	if ns.plates.level ~= target then
		local duration = target > ns.plates.level and ns.db.fadeInTime or ns.db.fadeOutTime
		ns.plates.level = ns.Approach(ns.plates.level, target, elapsed, duration)
		SetAllPlatesAlpha(ns.plates.level)
	end

	if hide and ns.plates.level == 0 and not ns.plates.off and not InCombatLockdown() then
		ns.ApplyCVarSet(PLATE_CVARS, true)
		ns.plates.off = true
	end
end

-- World tooltips (units and objects under the cursor) use the default anchor,
-- owned by UIParent. Tooltips owned by UI elements are left alone so hovering a
-- faded button still explains it. World tooltips are hidden outright while
-- cinematic: fading them fought Blizzard's own tooltip alpha and flickered.
ns.lastCinematic = false

local function IsWorldTooltip()
	local owner = GameTooltip:GetOwner()
	return owner == nil or owner == UIParent or owner == WorldFrame
end

-- World tooltips hide in cinematic mode (fadeTooltip), or only in the camera
-- modes, each chosen on its own (tooltipOff*).
local TOOLTIP_OFF_IN = {
	flight = "tooltipOffFlight", idle = "tooltipOffIdle", cozy = "tooltipOffCozy",
	walk = "tooltipOffWalk", run = "tooltipOffRun",
}
local function ShouldHideTooltip()
	if not (ns.lastCinematic and GameTooltip:IsShown() and IsWorldTooltip()) then
		return false
	end
	if ns.db.fadeTooltip then
		return true
	end
	local mode = ns.CameraMode and ns.CameraMode()
	return mode ~= nil and ns.db[TOOLTIP_OFF_IN[mode]] or false
end

-- Catches each new world tooltip the moment it appears (a hidden tooltip shows
-- again for the next thing you mouse over, so this runs every time).
function ns.OnTooltipShow(self)
	if ShouldHideTooltip() then
		self:Hide()
	end
end

-- Covers a tooltip that was already up when cinematic mode started.
function ns.UpdateTooltip()
	if ShouldHideTooltip() then
		GameTooltip:Hide()
	end
end

function ns.CreateLetterbox()
	ns.letterbox = CreateFrame("Frame", "CinematicLetterbox", UIParent)
	ns.letterbox:SetAllPoints(UIParent)
	ns.letterbox:SetFrameStrata("BACKGROUND")
	ns.letterbox:SetFrameLevel(0)
	ns.letterbox:EnableMouse(false)

	ns.letterbox.top = ns.letterbox:CreateTexture(nil, "BACKGROUND")
	ns.letterbox.top:SetColorTexture(0, 0, 0, 1)
	ns.letterbox.top:SetPoint("TOPLEFT")
	ns.letterbox.top:SetPoint("TOPRIGHT")

	ns.letterbox.bottom = ns.letterbox:CreateTexture(nil, "BACKGROUND")
	ns.letterbox.bottom:SetColorTexture(0, 0, 0, 1)
	ns.letterbox.bottom:SetPoint("BOTTOMLEFT")
	ns.letterbox.bottom:SetPoint("BOTTOMRIGHT")

	ns.letterbox:Hide()
end

function ns.UpdateLetterbox(cinematic, elapsed)
	local target = (cinematic and ns.db.letterbox) and 1 or 0
	if letterboxProgress == target and not ns.letterboxDirty then
		return
	end
	ns.letterboxDirty = false
	local duration = target > letterboxProgress and ns.db.fadeOutTime or ns.db.fadeInTime
	letterboxProgress = ns.Approach(letterboxProgress, target, elapsed, duration)

	-- Smoothstep so the bars ease in and out.
	local t = letterboxProgress * letterboxProgress * (3 - 2 * letterboxProgress)
	local height = math.max(t * UIParent:GetHeight() * ns.db.letterboxSize, 0.01)
	ns.letterbox.top:SetHeight(height)
	ns.letterbox.bottom:SetHeight(height)
	ns.letterbox:SetAlpha(ns.db.letterboxAlpha)
	ns.letterbox:SetShown(letterboxProgress > 0)
end
