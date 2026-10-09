-- Cinematic: effects that follow cinematic mode. Hidden names, music,
-- nameplates, world tooltips and the letterbox bars.
local _, ns = ...

local letterboxProgress = 0
ns.letterboxDirty = false
-- Game settings (CVars) that change while cinematic. The player's original
-- values are saved on the way in and put back on the way out. Originals are
-- also kept in the saved variables so a crash or disconnect can't leave names
-- switched off for good. CVars this client doesn't have are skipped.
-- Names, in the rows the Nameplates page lists: the game's own name
-- options, in its order. In cinematic mode each row hides unless kept up:
-- nameCombat<key> in fights, otherwise nameKeep<key> in the open world and
-- nameIn<place><key> elsewhere, like the plates. Minions rows (indent) sit
-- under their players' rows and cover pets, guardians and totems too.
ns.NAME_GROUPS = {
	{ key = "Self", label = "My Name", cvars = { "UnitNameOwn" } },
	-- The game's NPC Names choice (None, quest NPCs... all NPCs) is these
	-- together; switched on, it only changes from None (to all).
	{ key = "NPCs", label = "NPC Names", anyOn = true,
		cvars = { "UnitNameNPC", "UnitNameHostleNPC", "UnitNameInteractiveNPC", "UnitNameFriendlySpecialNPCName" } },
	{ key = "Critters", label = "Critters and Companions", cvars = { "UnitNameNonCombatCreatureName" } },
	{ key = "Friends", label = "Friendly Players", cvars = { "UnitNameFriendlyPlayerName" } },
	{ key = "FriendlyMinions", label = "Minions", indent = true,
		cvars = {
			"UnitNameFriendlyMinionName", "UnitNameFriendlyPetName", "UnitNameFriendlyGuardianName",
			"UnitNameFriendlyTotemName",
		} },
	{ key = "Enemies", label = "Enemy Players", cvars = { "UnitNameEnemyPlayerName" } },
	{ key = "EnemyMinions", label = "Minions", indent = true,
		cvars = {
			"UnitNameEnemyMinionName", "UnitNameEnemyPetName", "UnitNameEnemyGuardianName",
			"UnitNameEnemyTotemName",
		} },
}

local CVAR_SETS = {}
for _, group in ipairs(ns.NAME_GROUPS) do
	local values = {}
	for _, cvar in ipairs(group.cvars) do values[cvar] = "0" end
	CVAR_SETS[#CVAR_SETS + 1] = { key = group.key, values = values }
end

-- Whether this client has any of a group's name settings.
function ns.HasNameSettings(group)
	for _, cvar in ipairs(group.cvars) do
		if GetCVar(cvar) ~= nil then
			return true
		end
	end
	return false
end

-- The player's own value for a game setting: what comes back after cinematic
-- mode if it's put away for now.
local function OwnValue(cvar)
	local saved = ns.db.savedCVars[cvar]
	if saved ~= nil then
		return saved
	end
	return GetCVar(cvar)
end

-- Switches a game setting on for good: straight away, or, while cinematic
-- mode has it put away, in the value it comes back to.
local function SwitchOn(cvar)
	if GetCVar(cvar) == nil then
		return
	end
	if ns.db.savedCVars[cvar] ~= nil then
		ns.db.savedCVars[cvar] = "1"
	elseif GetCVar(cvar) ~= "1" then
		SetCVar(cvar, "1")
	end
end

-- Ticking anything in a names row switches the game's own option for it on
-- (only names the game shows can stay up). Unticking leaves it alone.
function ns.EnableNameRow(group)
	if group.anyOn then
		for _, cvar in ipairs(group.cvars) do
			local value = OwnValue(cvar)
			if value ~= nil and value ~= "0" then
				return
			end
		end
	end
	for _, cvar in ipairs(group.cvars) do
		SwitchOn(cvar)
	end
end

-- Switched off once plates have faded out (so invisible plates can't be
-- clicked). Can't be changed during combat lockdown.
local PLATE_CVARS = {
	secure = true,
	values = {
		nameplateShowEnemies = "0", nameplateShowFriends = "0", nameplateShowFriendlyPlayers = "0",
		nameplateShowFriendlyNPCs = "0",
	},
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

-- Names ticked In combat stay up through the fight and for the Calm Timer (calmTime)
-- after it, like the plates.
local function NameKeptHere(key, inCombat)
	if inCombat or (ns.FightLingering() and ns.db["nameCombat" .. key]) then
		return ns.db["nameCombat" .. key]
	end
	local place = ns.PlaceSuffix()
	return ns.db[place and ("nameIn" .. place .. key) or ("nameKeep" .. key)]
end

function ns.UpdateCVars(cinematic)
	local inCombat = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	for _, set in ipairs(CVAR_SETS) do
		local want = cinematic and not NameKeptHere(set.key, inCombat)
		ns.ApplyCVarSet(set, want or false)
	end
	ns.ApplyCVarSet(COMBAT_TEXT_CVARS, (cinematic and ns.db.hideCombatText and not inCombat) or false)
end

-- Music fades by ramping the music volume from 0 up to the player's own
-- volume and back. If music was already on, it's left completely alone.
ns.music = { managing = false, level = 0, volume = 1 }

-- The music volume the addon last wrote (nil while it isn't touching it). If
-- the CVar no longer matches, the player changed it in the sound settings, and
-- their change wins over any fade or mute.
local MUSIC_VOLUME_EPSILON = 0.005
local musicWritten
-- When the addon last started music this session (for music fatigue).
local musicStartedAt

-- Music trace (for tracking down the music volume left at 0): every write to
-- the music volume or on/off, with who made it, in the log while detailed
-- logging is on (/cine debug record). The addon's own fade steps are only
-- logged when they reach or leave 0.
local fadeWriting, lastFadeZero = false, nil

local function MusicTrace(text)
	if not (ns.db and ns.db.logDetail) then
		return
	end
	ns.Log("music", ("%.1f %s | managing %s saved %s written %s"):format(GetTime(), text,
		tostring(ns.music.managing), tostring(ns.db.savedCVars and ns.db.savedCVars.Sound_MusicVolume),
		tostring(musicWritten)))
end
ns.MusicTrace = MusicTrace

local function TraceMusicWrite(name, value)
	if name ~= "Sound_MusicVolume" and name ~= "Sound_EnableMusic" then
		return
	end
	if fadeWriting then
		local zero = tonumber(value) == 0
		if zero == lastFadeZero then
			return
		end
		lastFadeZero = zero
		MusicTrace(("fade %s = %s"):format(name, tostring(value)))
		return
	end
	local stack = (debugstack(3, 4, 0) or ""):gsub("Interface/AddOns/", ""):gsub("\n", " < ")
	MusicTrace(("SET %s = %s by %s"):format(name, tostring(value), stack:sub(1, 300)))
end

if C_CVar and C_CVar.SetCVar then
	hooksecurefunc(C_CVar, "SetCVar", TraceMusicWrite)
else
	hooksecurefunc("SetCVar", TraceMusicWrite)
end

-- Changes made outside Lua (the game itself) only show up as this event.
local traceFrame = CreateFrame("Frame")
traceFrame:RegisterEvent("CVAR_UPDATE")
traceFrame:SetScript("OnEvent", function(_, _, name, value)
	if name == "Sound_MusicVolume" or name == "Sound_EnableMusic" or name == "MUSIC_VOLUME"
		or name == "ENABLE_MUSIC" then
		MusicTrace(("CVAR_UPDATE %s = %s (now %s)"):format(tostring(name), tostring(value),
			tostring(GetCVar("Sound_MusicVolume"))))
	end
end)

-- The game's Music slider moves in 5% steps. With the sound settings open, it
-- snaps each value the addon writes to the nearest step and writes that back
-- (0.524 becomes 0.5, and the first steps of a fade in become 0). That's the
-- slider, not the player: it mustn't be taken as a new volume.
local MUSIC_SLIDER_STEP = 0.05

local function IsSliderSnap(actual, written)
	local steps = actual / MUSIC_SLIDER_STEP
	return math.abs(steps - math.floor(steps + 0.5)) < 0.001
		and math.abs(actual - written) < MUSIC_SLIDER_STEP / 2 + 0.0001
end

local function SetMusicVolume(volume)
	local text = ("%.3f"):format(volume)
	musicWritten = tonumber(text)
	fadeWriting = true
	SetCVar("Sound_MusicVolume", text)
	fadeWriting = false
	-- Snapped by the slider during the write itself: that's the value now.
	local actual = tonumber(GetCVar("Sound_MusicVolume"))
	if actual and math.abs(actual - musicWritten) > MUSIC_VOLUME_EPSILON then
		MusicTrace(("snapped by the slider %.3f -> %.3f"):format(musicWritten, actual))
		musicWritten = actual
	end
end

-- Your music volume (musicVolume) is remembered: it's updated whenever you
-- change it (and, while the addon isn't touching it, follows the setting), and
-- put back at login and /reload, so a volume the addon left turned down, or one
-- something else wrote, can't stick.
function ns.RestoreMusicVolume()
	local volume = ns.db.musicVolume
	local now = tonumber(GetCVar("Sound_MusicVolume"))
	if volume and not (now and math.abs(now - volume) <= MUSIC_VOLUME_EPSILON) then
		MusicTrace(("RESTORE your volume %s -> %.3f"):format(tostring(now), volume))
		SetCVar("Sound_MusicVolume", ("%.3f"):format(volume))
	end
end

-- The player's new music volume, if they changed it since the addon last wrote it.
local function PlayerMusicVolume()
	if not musicWritten then
		return nil
	end
	local actual = tonumber(GetCVar("Sound_MusicVolume"))
	if actual and math.abs(actual - musicWritten) > MUSIC_VOLUME_EPSILON and IsSliderSnap(actual, musicWritten) then
		-- (A snap that came a moment after the write.)
		MusicTrace(("snapped by the slider later %.3f -> %.3f"):format(musicWritten, actual))
		musicWritten = actual
	elseif actual and math.abs(actual - musicWritten) > MUSIC_VOLUME_EPSILON then
		MusicTrace(("DETECTED player change %.3f -> %.3f"):format(musicWritten, actual))
		if ns.musicDebug then
			ns.Print(("music: you changed the volume %.2f -> %.2f"):format(musicWritten, actual))
		end
		musicWritten = actual
		return actual
	end
end

function ns.StopMusicNow()
	if ns.music.managing then
		ns.RestoreCVar("Sound_EnableMusic")
		ns.RestoreCVar("Sound_MusicVolume")
		ns.music.managing = false
		musicWritten = nil
	end
end

-- Standing still or AFK, as far as music goes: the AFK camera, the wait for it
-- (standing still with the UI faded) or being flagged AFK. With "No music
-- while AFK" on, none of these starts music, brings it back from the move-on
-- pause or swaps in a fresh song; music that's already playing carries on.
local function QuietForAFK()
	if not ns.db.noMusicWhenAFK then
		return false
	end
	local mode = ns.CameraMode and ns.CameraMode()
	return ns.Flag(UnitIsAFK("player")) or mode == "idle" or (mode == nil and ns.stillSince ~= nil)
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

-- New song swap: rather than cutting the current track dead, it fades out,
-- music is switched off for a moment (so the game picks a fresh track), then
-- the new one fades in. phase is nil, "out", "gap" or "in".
local SONG_SWAP_FADE_OUT = 1.5
local NEW_SONG_GAP = 0.2
local songSwap = { level = 1, phase = nil, gapUntil = 0 }

local function UpdateSongSwap(elapsed)
	if songSwap.phase == "out" then
		songSwap.level = ns.Approach(songSwap.level, 0, elapsed, SONG_SWAP_FADE_OUT)
		if songSwap.level <= 0 then
			SetCVar("Sound_EnableMusic", 0)
			songSwap.phase = "gap"
			songSwap.gapUntil = GetTime() + NEW_SONG_GAP
		end
	elseif songSwap.phase == "gap" then
		if GetTime() >= songSwap.gapUntil then
			-- Switch back on unless a mute has since taken over (it brings a fresh
			-- track itself when it ends), the addon's music stopped and put the
			-- player's setting back, or something else already did.
			if combatMusic.level > 0 and songSwap.managed == ns.music.managing
				and GetCVar("Sound_EnableMusic") == "0" then
				SetCVar("Sound_EnableMusic", 1)
			end
			songSwap.phase = "in"
		end
	elseif songSwap.phase == "in" then
		songSwap.level = ns.Approach(songSwap.level, 1, elapsed, ns.db.musicFadeTime)
		if songSwap.level >= 1 then
			songSwap.phase = nil
		end
	end
end

-- The volume share left after the combat/place mutes and any song swap.
local function MusicDuck()
	return combatMusic.level * songSwap.level
end

-- Once fully faded out, music is switched off rather than left playing at
-- zero volume; switching it back on when the mute ends makes the game start a
-- fresh track (instead of resuming one halfway through) as it fades back in.
local function SetMuteMusicOff(flag, off)
	if off ~= combatMusic[flag] then
		combatMusic[flag] = off
		SetCVar("Sound_EnableMusic", off and 0 or 1)
	end
end

-- playerOverride: the player changed the music volume (or switched music back
-- on) during a mute. That lifts the mute until it clears by itself or a new
-- reason to mute comes up (a fight starting while you walk on, say).
local function UpdateCombatMusic(elapsed, playerOverride)
	-- Muted while fighting (if chosen) or in a place chosen under "Mute music in".
	-- Only when the addon handles music at all: with "Play music in cinematic
	-- mode" off, the player's volumes are left alone (any ducking eases back).
	local handlesMusic = ns.db.musicInCinematic
	local now = GetTime()
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		combatMusic.lastFightAt = now
	end
	-- Stays muted until the Calm Timer (calmTime) has passed since the last
	-- fight ended, so back-to-back fights don't bring the music in and out.
	local fighting = handlesMusic and ns.db.musicOffInCombat
		and now - combatMusic.lastFightAt < ns.db.calmTime
	local flying = handlesMusic and ns.db.musicOffOnFlights and UnitOnTaxi("player")
	-- Music belongs to the camera modes (flying, RP walking, standing still,
	-- vista, cozy, fishing...): once you move on from one, it fades out, and a
	-- fresh track comes in when the next one starts. With pause on landing, a
	-- flight's music fades out as you touch down, without waiting for you to move.
	-- (Any camera mode lifts the pause: vista, cozy and fish start straight away
	-- from their emote, before standing still would count. Not the AFK camera
	-- with "No music while AFK" on: the music stays paused while you're away.)
	local onTaxi = UnitOnTaxi("player")
	local landed = combatMusic.wasOnTaxi and not onTaxi
	combatMusic.wasOnTaxi = onTaxi
	if not (handlesMusic and (ns.db.musicPauseWhenMoving or ns.db.musicPauseOnLanding))
		or (ns.CameraMode and ns.CameraMode() and not QuietForAFK()) then
		combatMusic.movingPaused = false
	elseif (ns.db.musicPauseWhenMoving and ns.playerMoving) or (ns.db.musicPauseOnLanding and landed) then
		combatMusic.movingPaused = true
		combatMusic.pauseFade = true
	end
	local blocked = handlesMusic and ns.IsMusicBlocked()
	local moving = combatMusic.movingPaused
	if playerOverride then
		combatMusic.override = { fighting = fighting, flying = flying, blocked = blocked, moving = moving }
		combatMusic.level = 1
	end
	local o = combatMusic.override
	if o and (not (fighting or flying or blocked or moving) or (fighting and not o.fighting)
		or (flying and not o.flying) or (blocked and not o.blocked) or (moving and not o.moving)) then
		combatMusic.override = nil
	end
	if combatMusic.override then
		fighting, flying, blocked, moving = false, false, false, false
	end
	local otherMute = fighting or flying or blocked
	local target = (otherMute or moving) and 0 or 1
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
	UpdateSongSwap(elapsed)
	local duck = MusicDuck()

	if ns.music.managing then
		-- The addon's own music: UpdateMusic applies the level to the volume; here
		-- it's just switched off while silent (its on/off is already saved).
		SetMuteMusicOff("managedOff", silent)
		return
	end
	combatMusic.managedOff = false -- the addon's music has stopped; its on/off was restored

	-- The player's own music: save its volume and on/off, then duck it.
	-- (A song swap ducks it the same way; during the swap's gap music is off, so
	-- the volume just holds until the new track comes in.)
	if duck < 1 and (GetCVar("Sound_EnableMusic") == "1" or combatMusic.musicOff) then
		-- (Saved again if the addon's own music put the volume back meanwhile:
		-- ducking on without a saved copy would leave it turned down for good.)
		if not combatMusic.ducking or ns.db.savedCVars.Sound_MusicVolume == nil then
			ns.SaveCVar("Sound_MusicVolume")
			ns.SaveCVar("Sound_EnableMusic")
			combatMusic.original = tonumber(ns.db.savedCVars.Sound_MusicVolume) or 1
			combatMusic.ducking = true
		end
		-- Fully faded out, music is switched off and the slider goes back to
		-- your own volume (it only reads lower while actually fading).
		SetMuteMusicOff("musicOff", silent)
		SetMusicVolume(silent and combatMusic.original or combatMusic.original * duck)
	elseif combatMusic.ducking and duck >= 1 then
		ns.RestoreCVar("Sound_MusicVolume")
		ns.RestoreCVar("Sound_EnableMusic")
		combatMusic.ducking, combatMusic.musicOff = false, false
		musicWritten = nil
	end
end

function ns.StopCombatMusicNow()
	if combatMusic.ducking then
		ns.RestoreCVar("Sound_MusicVolume")
		ns.RestoreCVar("Sound_EnableMusic")
		combatMusic.ducking = false
		musicWritten = nil
	end
	combatMusic.musicOff, combatMusic.managedOff, combatMusic.override = false, false, nil
	combatMusic.level = 1
	songSwap.level, songSwap.phase = 1, nil
end

-- The death song picked for this death (a music file ID), or nil; see SetDeathSong.
local deathSong = { file = nil, playing = false }

-- "Play music": as a camera starts, a fresh song, even if music played
-- recently (music fatigue). The flight, RP walk and auto-run cameras each have
-- a switch; the cozy, vista and fish cameras follow the event that started
-- them (the Camera Triggers page's Music column, event<key>Music). The AFK
-- camera's is "No music while AFK" (noMusicWhenAFK), the other way round.
local MUSIC_CAM = { flight = "musicCamFlight", walk = "musicCamWalk", run = "musicCamRun" }
local EVENT_MUSIC_CAMS = { cozy = true, vista = true, fish = true }

local function CameraMusicOn(mode)
	if EVENT_MUSIC_CAMS[mode] then
		local key = ns.ActiveEvent and ns.ActiveEvent()
		return key ~= nil and ns.db["event" .. key .. "Music"] or false
	end
	return MUSIC_CAM[mode] ~= nil and ns.db[MUSIC_CAM[mode]] or false
end

-- Times music starts despite music fatigue: in a camera mode set to play
-- music, or in a different zone from the last music.
local function FatigueOverridden()
	local mode = ns.CameraMode and ns.CameraMode()
	if (mode == "idle" and not ns.db.noMusicWhenAFK)
		or (mode and CameraMusicOn(mode)) then
		return true
	end
	local zone = GetRealZoneText()
	if ns.db.fatigueIgnoreNewZone and zone and zone ~= "" and ns.db.lastMusicZone
		and zone ~= ns.db.lastMusicZone then
		return true
	end
	return false
end

-- New song: the current track fades out, music is switched off and back on,
-- which makes the game start a fresh track, and that fades in (see songSwap).
-- Happens as the flight rotation starts (or at takeoff with flight rotation
-- off) and as the standing-still camera starts, once per flight / per spell of
-- standing still. Skipped if music isn't playing, or on flights while muted
-- there (a fresh track comes on landing).
local wasOnTaxiForMusic = false
local songFlight = false -- this flight already got its new song
local songStillSince     -- the standing-still spell that already got one
-- RP walking: a new song when you set off, but not for every pause. Stopping
-- for less than this long and walking on counts as the same walk.
local WALK_SONG_GAP = 20
local lastModeAt = {} -- camera mode -> when it was last running (walk, run, cozy, vista, fish)

-- Switching straight from one camera mode to another (vista to cozy, idle to
-- walking...) keeps the song that's playing: only a mode started from none
-- brings a new one. A gap of up to MODE_HANDOVER seconds between the two
-- still counts as switching.
local MODE_HANDOVER = 2
local modeNow, modeSeenAt, modeHandover = nil, -math.huge, false

local function NoteCameraMode()
	local mode = ns.CameraMode and ns.CameraMode()
	if not mode then
		return
	end
	local now = GetTime()
	if now - modeSeenAt >= MODE_HANDOVER then
		modeHandover = false -- started from no camera mode
	elseif mode ~= modeNow then
		modeHandover = true
	end
	modeNow = mode
	modeSeenAt = now
end

local function RestartMusic()
	if not ns.db.musicInCinematic or GetCVar("Sound_EnableMusic") ~= "1" then
		return
	end
	-- Carrying on from another camera mode: the song already playing stays.
	NoteCameraMode()
	if modeHandover then
		return
	end
	-- Already swapping, or the addon's music is still fading in (it's a fresh
	-- track already) or out: cutting it now would only make it skip.
	if songSwap.phase or (ns.music.managing and ns.music.level < 1) then
		return
	end
	-- Muted or mid-mute: the mute brings a fresh track in when it ends.
	if combatMusic.level < 1 then
		return
	end
	songSwap.phase = "out"
	songSwap.managed = ns.music.managing
end

local function NewSongForFlight()
	if songFlight or not ns.db.musicCamFlight or ns.db.musicOffOnFlights then
		return
	end
	songFlight = true
	RestartMusic()
end

-- Death song: while the death camera runs, a song of its own plays in place of
-- the zone music, picked at random from deathSongFiles (music file IDs,
-- comma-separated). It needs game music on.
function ns.PickDeathSong()
	local files = {}
	for id in (ns.db.deathSongFiles or ""):gmatch("%d+") do
		files[#files + 1] = tonumber(id)
	end
	return files[math.random(math.max(1, #files))]
end

-- It plays straight away at your music volume, switching game music on if it's
-- off; the music manager (UpdateMusic) stands aside meanwhile, and the music
-- settings it found are put back afterwards.
function ns.SetDeathSong(on)
	deathSong.file = on and ns.db.deathSong and ns.PickDeathSong() or nil
	if on and ns.DeathTestLog then
		ns.DeathTestLog(("death song: %s (song option %s, game music %s)"):format(
			tostring(deathSong.file), tostring(ns.db.deathSong),
			GetCVar("Sound_EnableMusic") == "1" and "on" or "off - switching it on"))
	end
end

-- Changing the music volume while it plays is your new volume: the song plays
-- on at it, it's saved as yours straight away, and it's what you're left with
-- afterwards (UpdateMusic then sees the change and lifts any fade or mute).
local function UpdateDeathSong()
	if deathSong.file and not deathSong.playing then
		deathSong.enable, deathSong.volume = GetCVar("Sound_EnableMusic"), GetCVar("Sound_MusicVolume")
		-- Your own volume: the addon may have it faded or ducked right now.
		deathSong.written = tonumber(ns.db.savedCVars.Sound_MusicVolume or deathSong.volume) or 1
		deathSong.changed = false
		SetCVar("Sound_EnableMusic", 1)
		SetCVar("Sound_MusicVolume", ns.db.savedCVars.Sound_MusicVolume or deathSong.volume)
		-- (Counts as playing even if PlayMusic fails, so the settings found
		-- above aren't taken again from the ones just written.)
		deathSong.playing = true
		pcall(PlayMusic, deathSong.file)
		if ns.DeathTestLog then ns.DeathTestLog("death song playing") end
	elseif deathSong.file then
		local actual = tonumber(GetCVar("Sound_MusicVolume"))
		if actual and math.abs(actual - deathSong.written) > MUSIC_VOLUME_EPSILON then
			if ns.musicDebug then
				ns.Print(("music: you changed the volume %.2f -> %.2f (death song)"):format(deathSong.written, actual))
			end
			deathSong.written, deathSong.changed = actual, true
			ns.db.musicVolume = actual
			if ns.db.savedCVars.Sound_MusicVolume ~= nil then
				ns.db.savedCVars.Sound_MusicVolume = tostring(actual)
				combatMusic.original = actual
				if ns.music.managing then
					ns.music.volume = actual
				end
			end
		end
	elseif deathSong.playing then
		deathSong.playing = false
		pcall(StopMusic)
		SetCVar("Sound_EnableMusic", deathSong.enable)
		SetCVar("Sound_MusicVolume", deathSong.changed and ("%.3f"):format(deathSong.written) or deathSong.volume)
	end
end

-- Called by the camera when a rotation starts ("taxiOrbit", "idleOrbit"...).
-- It also restarts after you move the camera; only the first start counts.
-- (The other cameras get their fresh song in UpdateMusic, as they start.)
function ns.OnRotationStart(prefix)
	if prefix == "taxiOrbit" then
		NewSongForFlight()
	elseif prefix == "idleOrbit" and not ns.db.noMusicWhenAFK and ns.stillSince
		and songStillSince ~= ns.stillSince then
		songStillSince = ns.stillSince
		RestartMusic()
	end
end

-- /cine debug music: a chat line whenever the music state changes. Levels are
-- shown as 0, "part" or 1 so a fade doesn't print every step.
local lastMusicReport
local function Bucket(level)
	return level <= 0 and "0" or level >= 1 and "1" or "part"
end

local function ReportMusic(cinematic)
	if not ns.musicDebug then
		return
	end
	local volume = tonumber(GetCVar("Sound_MusicVolume")) or -1
	local report = ("music: cine %s mode %s | managing %s level %s vol %.2f | mute %s%s%s | swap %s | duck %s | saved %s | game: music %s volume %s"):format(
		tostring(cinematic), tostring(ns.CameraMode and ns.CameraMode()),
		tostring(ns.music.managing), Bucket(ns.music.level), ns.music.volume,
		Bucket(combatMusic.level), combatMusic.movingPaused and " (moved)" or "",
		combatMusic.override and " (overridden)" or "",
		tostring(songSwap.phase), tostring(combatMusic.ducking),
		tostring(ns.db.savedCVars.Sound_MusicVolume), GetCVar("Sound_EnableMusic"),
		volume <= 0 and "0" or volume >= (ns.music.managing and ns.music.volume or combatMusic.original) - 0.01
			and ("%.2f"):format(volume) or "fading")
	if report ~= lastMusicReport then
		lastMusicReport = report
		ns.Print(report)
	end
end

-- Music kept off for being AFK (QuietForAFK) this cinematic spell: it stays
-- off as you come back and set off running, until another camera mode starts
-- (a flight, a walk, sitting down...) or the UI comes back. (Starting it then
-- would only bring a swell of music as the move-on pause fades it out.)
local afkKeptQuiet = false

function ns.UpdateMusic(cinematic, elapsed)
	ReportMusic(cinematic)
	local now = GetTime()
	NoteCameraMode()
	-- RP walk, auto-run, cozy, vista and fish: a new song as the camera starts,
	-- but not for a short break in the same walk, run or spell (nor when
	-- carrying straight on from another camera mode; see RestartMusic).
	local mode = ns.CameraMode and ns.CameraMode()
	if mode and mode ~= "flight" and (MUSIC_CAM[mode] or EVENT_MUSIC_CAMS[mode]) then
		if now - (lastModeAt[mode] or -math.huge) > WALK_SONG_GAP and CameraMusicOn(mode) then
			RestartMusic()
		end
		lastModeAt[mode] = now
	end
	local onTaxi = UnitOnTaxi("player")
	if onTaxi ~= wasOnTaxiForMusic then
		wasOnTaxiForMusic = onTaxi
		songFlight = false
		if onTaxi and not ns.db.taxiOrbit then
			NewSongForFlight() -- no rotation to wait for: new song at takeoff
		end
	end
	UpdateDeathSong()
	if deathSong.file then
		return -- the death song has the music for now
	end
	local want = cinematic and ns.db.musicInCinematic
	if not want or not ns.db.noMusicWhenAFK or (mode and not QuietForAFK()) then
		afkKeptQuiet = false
	end
	-- The player changed the music volume while the addon was fading or muting
	-- it: that's their new volume, to play at now and come back to afterwards.
	local playerVolume = PlayerMusicVolume()
	if playerVolume then
		ns.db.musicVolume = playerVolume
		ns.db.savedCVars.Sound_MusicVolume = tostring(playerVolume)
		combatMusic.original = playerVolume
		if ns.music.managing then
			ns.music.volume = playerVolume
			if want then
				ns.music.level = 1
			end
		end
	end
	if not playerVolume and ns.db.savedCVars.Sound_MusicVolume == nil then
		-- The addon isn't touching the volume: whatever it's set to is yours.
		ns.db.musicVolume = tonumber(GetCVar("Sound_MusicVolume")) or ns.db.musicVolume
	end
	local switchedOn = (combatMusic.musicOff or combatMusic.managedOff) and GetCVar("Sound_EnableMusic") == "1"
	UpdateCombatMusic(elapsed, playerVolume ~= nil or switchedOn)
	if want and not ns.music.managing then
		if GetCVar("Sound_EnableMusic") == "1" then
			return
		end
		-- Standing still or AFK, with "No music while AFK" on: no music
		-- until another camera mode starts it.
		if afkKeptQuiet or QuietForAFK() then
			afkKeptQuiet = true
			return
		end
		-- Music fatigue: started music recently? Stay quiet this time. (Not
		-- saved, so it starts over on each login and /reload.)
		if ns.db.musicFatigue > 0 and musicStartedAt and GetTime() - musicStartedAt < ns.db.musicFatigue * 60
			and not FatigueOverridden() then
			return
		end
		musicStartedAt = GetTime()
		ns.db.lastMusicZone = GetRealZoneText()
		ns.SaveCVar("Sound_EnableMusic")
		ns.SaveCVar("Sound_MusicVolume")
		ns.music.managing = true
		ns.music.level = 0
		ns.music.volume = tonumber(ns.db.savedCVars.Sound_MusicVolume) or 1
		MusicTrace(("START managed music, your volume %s"):format(tostring(ns.music.volume)))
		-- It fades in to your own volume, so with that at 0 nothing is heard.
		if ns.music.volume <= 0 and not ns.music.warnedSilent then
			ns.music.warnedSilent = true
			ns.Print("your game music volume is 0, so cinematic music can't be heard. " ..
				"Turn Music up in the game's Sound settings.")
		end
		SetMusicVolume(0)
		SetCVar("Sound_EnableMusic", 1)
	end
	if not ns.music.managing then
		return
	end

	local target = want and 1 or 0
	local duck = MusicDuck()
	if ns.music.level ~= target or duck < 1 or ns.music.combatApplied then
		ns.music.level = ns.Approach(ns.music.level, target, elapsed, ns.db.musicFadeTime)
		-- (Switched off while muted: the slider shows your own volume meanwhile.)
		SetMusicVolume(combatMusic.managedOff and ns.music.volume or ns.music.volume * ns.music.level * duck)
		-- Keep writing until the mute / song swap level is back to full.
		ns.music.combatApplied = duck < 1
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
	ambience.holdUntil = GetTime() + ns.db.returnDelay + 2
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

-- The game resets a plate's alpha itself (for one, when its unit enters
-- combat), so while a plate is faded or hidden, any alpha the game sets is
-- put straight back to ours. At full alpha the game is left to do as it likes.
local function KeepPlateAlpha(frame, alpha)
	local wanted = frame.cinematicAlpha
	if wanted and alpha ~= wanted and not frame.cinematicSetting then
		frame.cinematicSetting = true
		frame:SetAlpha(wanted)
		frame.cinematicSetting = false
	end
end

function ns.SetPlateAlpha(plate, alpha)
	if plate and plate.UnitFrame and not (plate.IsForbidden and plate:IsForbidden()) then
		local frame = plate.UnitFrame
		if not frame.cinematicHooked then
			frame.cinematicHooked = true
			hooksecurefunc(frame, "SetAlpha", KeepPlateAlpha)
		end
		frame.cinematicAlpha = alpha < 1 and alpha or nil
		frame.cinematicSetting = true
		frame:SetAlpha(alpha)
		frame.cinematicSetting = false
	end
end

-- The game's (localized) name for the Totem creature type.
local TOTEM_TYPE = "Totem"
if C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo then
	local ok, info = pcall(C_CreatureInfo.GetCreatureTypeInfo, 11)
	if ok and type(info) == "table" and info.name then
		TOTEM_TYPE = info.name
	end
end

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

-- The Nameplates page's rows: enemy players (their minions apart), enemy
-- NPCs (minor units apart), friendly players (their minions apart) and
-- friendly NPCs. Friendly or not is the game's own test, so the other
-- faction's players are enemies. Minions are anything a player controls
-- (pets, guardians, totems). nil when the game won't say (secret values in
-- combat): such plates just follow the fade.
local function PlateKind(unit)
	local okFriend, friend = pcall(UnitIsFriend, "player", unit)
	local ok, isPlayer = pcall(UnitIsPlayer, unit)
	if not (okFriend and ok and Known(friend) and Known(isPlayer)) then
		return nil
	end
	if isPlayer then
		return friend and "Friends" or "Enemies"
	end
	local okType, creatureType = pcall(UnitCreatureType, unit)
	local totem = okType and Known(creatureType) and creatureType == TOTEM_TYPE
	local okControl, controlled = pcall(UnitPlayerControlled, unit)
	if not okControl or not Known(controlled) then
		return nil
	end
	if controlled or totem then
		return friend and "FriendlyMinions" or "EnemyMinions"
	end
	if friend then
		return "FriendlyNPCs"
	end
	local okClass, class = pcall(UnitClassification, unit)
	if okClass and Known(class) and class == "minus" then
		return "EnemyMinor"
	end
	return "EnemyNPCs"
end

-- The Nameplates page only steers plates in cinematic mode: outside it the
-- game's own options decide. Set each frame.
local platesActive = false

-- Where you are, for the Nameplates page's place columns: "Cities", "Dungeons"...
-- or nil for the open world. Set each frame.
local placeSuffix

-- Whether a kind stays up in cinematic mode out of combat where you are:
-- plateCinematic<kind> in the open world, plateIn<place><kind> elsewhere.
local function KeptHere(kind)
	local key = placeSuffix and ("plateIn" .. placeSuffix .. kind) or ("plateCinematic" .. kind)
	return ns.db[key] and true or false
end

-- How far each kind is held up by KeptHere, faded so moving between places
-- (or changing the ticks) doesn't pop plates on or off. kind -> 0 to 1.
local keptLevel = {}

-- Any kind kept up in cinematic mode keeps the plates switched on.
local function AnyPlatesKeptCinematic()
	for _, kind in ipairs(ns.PLATE_KINDS) do
		if KeptHere(kind) or (keptLevel[kind] or 0) > 0 then
			return true
		end
	end
	return false
end

-- Whether your target's plate always shows here, from the Nameplates grid's
-- Enemy Target row (units you can attack, neutral mobs too) or Friendly
-- Target row (the rest): its In combat column in fights and for the Calm
-- Timer after, else the column for where you are.
local function TargetRowKept(row)
	local combat = ns.db["plateCombat" .. row]
	if InCombatLockdown() or (combat and ns.FightLingering and ns.FightLingering()) then
		return combat and true or false
	end
	return KeptHere(row)
end

local function AlwaysShownTarget(unit)
	local ok, attackable = pcall(UnitCanAttack, "player", unit)
	if not ok or not Known(attackable) then
		return false
	end
	return TargetRowKept(attackable and "EnemyTarget" or "FriendlyTarget")
end

local function TargetKeptUp()
	return UnitExists("target") and AlwaysShownTarget("target")
end

-- The always-shown target's plate fades in (at the UI's fade-in time) rather
-- than popping up, and
-- once it's no longer your target fades back down to where the other plates
-- are. Tracked by plate frame: `targetFade` is the current target's,
-- `leavingTargets` maps old targets' plates to their fade on the way out.
local targetFade = { plate = nil, level = 0, enemy = false }
local leavingTargets = {}

local function TargetFadeTime(fadeIn)
	return fadeIn and ns.db.fadeInTime or ns.db.fadeOutTime
end

-- Moves the target fades on by `elapsed`; true while any of them is moving.
local function UpdateTargetFade(elapsed)
	local plate
	if TargetKeptUp() and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
		plate = C_NamePlate.GetNamePlateForUnit("target")
	end
	if plate ~= targetFade.plate then
		if targetFade.plate and targetFade.level > 0 then
			leavingTargets[targetFade.plate] = { level = targetFade.level, enemy = targetFade.enemy }
		end
		-- Targeting a plate still on its way out carries on from there.
		local leaving = plate and leavingTargets[plate]
		targetFade.plate, targetFade.level = plate, leaving and leaving.level or 0
		if plate then
			leavingTargets[plate] = nil
		end
	end
	local moving = false
	if plate then
		local ok, attackable = pcall(UnitCanAttack, "player", "target")
		targetFade.enemy = ok and Known(attackable) and attackable or false
		if targetFade.level < 1 then
			targetFade.level = ns.Approach(targetFade.level, 1, elapsed, TargetFadeTime(true))
			moving = true
		end
	end
	for leavingPlate, fade in pairs(leavingTargets) do
		fade.level = ns.Approach(fade.level, 0, elapsed, TargetFadeTime(false))
		if fade.level <= 0 then
			leavingTargets[leavingPlate] = nil
		end
		moving = true
	end
	return moving
end

-- A plate just given to a new unit: whatever fade it had was its last unit's.
local function ForgetTargetFade(plate)
	leavingTargets[plate] = nil
	if targetFade.plate == plate then
		targetFade.plate, targetFade.level = nil, 0
	end
end

-- How far a plate is held up for being (or having just been) your target.
local function TargetPlateLevel(plate)
	if not plate then
		return 0
	end
	if plate == targetFade.plate then
		return targetFade.level
	end
	local leaving = leavingTargets[plate]
	return leaving and leaving.level or 0
end

-- Kinds hidden in cinematic fights (plateCombat<kind> off) come out of combat at 0 and
-- only rise again as far as the shared fade level lets them, rather than
-- jumping to it: it's still at 1 from the fight, so they'd flash up before
-- fading out again. kind -> highest alpha allowed (nil for no limit).
local combatCap = {}

-- Kinds shown in fights (plateCombat<kind> on) stay up for the Calm Timer (calmTime)
-- seconds after one in cinematic mode, then fade out at the fade-out speed
-- (unless kept up where you are).
local fightEndedAt = -math.huge
local fightWatcher = CreateFrame("Frame")
fightWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
fightWatcher:SetScript("OnEvent", function()
	fightEndedAt = GetTime()
end)

local function FightLingering()
	return not InCombatLockdown() and GetTime() - fightEndedAt < (ns.db.calmTime or 0)
end
ns.FightLingering = FightLingering -- (names linger too)

local function AnyFightKinds()
	for _, kind in ipairs(ns.PLATE_KINDS) do
		if ns.db["plateCombat" .. kind] then
			return true
		end
	end
	return false
end

-- Whether some plates need an alpha other than the shared fade level.
local function PlatesFiltered()
	if next(combatCap) then
		return true
	end
	if platesActive and InCombatLockdown() then
		for _, kind in ipairs(ns.PLATE_KINDS) do
			if not ns.db["plateCombat" .. kind] then
				return true
			end
		end
	end
	return ns.plates.level < 1
		and (AnyPlatesKeptCinematic() or TargetKeptUp() or next(leavingTargets) ~= nil)
end

local function IsTarget(unit)
	local ok, same = pcall(UnitIsUnit, unit, "target")
	return ok and Known(same) and same
end

-- The plate's alpha from the Nameplates page's rows and the fade, before any
-- target fade lifts it.
local function KindAlpha(unit)
	local kind = unit and PlateKind(unit)
	if kind then
		-- Plates can't be switched off in fights, only made invisible.
		if platesActive and InCombatLockdown() and not ns.db["plateCombat" .. kind] then
			return 0
		end
		return math.min(math.max(ns.plates.level, keptLevel[kind] or 0), combatCap[kind] or 1)
	end
	return ns.plates.level
end

local function PlateAlpha(unit, plate)
	local alpha = KindAlpha(unit)
	if plate == targetFade.plate and not (unit and IsTarget(unit) and AlwaysShownTarget(unit)) then
		return alpha -- a frame before the target fade catches up with a new target
	end
	return math.max(alpha, TargetPlateLevel(plate))
end

function ns.RefreshPlate(plate, unit)
	if not plate then
		return
	end
	unit = unit or plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
	ForgetTargetFade(plate) -- only called for a plate given a new unit
	local alpha = PlateAlpha(unit, plate)
	if alpha < 1 or PlatesFiltered() then
		ns.SetPlateAlpha(plate, alpha)
	elseif plate.UnitFrame then
		plate.UnitFrame.cinematicAlpha = nil -- a reused plate: let go of its last unit's alpha
	end
end

local function RefreshAllPlates()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		ns.SetPlateAlpha(plate, PlateAlpha(unit, plate))
	end
end

-- For /cine debug plates: the game's plate settings, the fade, and how each
-- visible plate (and the target) is sorted.
function ns.PrintPlatesDebug()
	local function cvar(name)
		local value = GetCVar(name)
		local saved = ns.db.savedCVars[name]
		return ("%s=%s%s"):format(name, tostring(value), saved and (" (saved " .. saved .. ")") or "")
	end
	ns.Print(cvar("nameplateShowEnemies") .. ", " .. cvar("nameplateShowFriends") .. ", " ..
		cvar("nameplateShowFriendlyNPCs") .. ", " .. cvar("nameplateMaxDistance"))
	-- Settings only some clients have, listed where they exist.
	local extra = {}
	for _, name in ipairs({ "nameplateShowEnemyPlayers", "nameplateShowFriendlyPlayers", "nameplateShowAll",
		"nameplateShowOnlyNames", "nameplateShowOnlyNameForFriendlyPlayerUnits" }) do
		if GetCVar(name) ~= nil then
			extra[#extra + 1] = cvar(name)
		end
	end
	if #extra > 0 then
		ns.Print(table.concat(extra, ", "))
	end
	ns.Print(("fade level=%.2f, switched off=%s, filtered=%s, kept in cinematic=%s, cinematic=%s, combat=%s"):format(
		ns.plates.level, tostring(ns.plates.off), tostring(PlatesFiltered()),
		tostring(AnyPlatesKeptCinematic()), tostring(ns.lastCinematic), tostring(InCombatLockdown())))
	local keptHere = {}
	for _, kind in ipairs(ns.PLATE_KINDS) do
		if KeptHere(kind) then
			keptHere[#keptHere + 1] = kind
		end
	end
	ns.Print(("place=%s, kept up here=%s"):format(placeSuffix or "open world",
		#keptHere > 0 and table.concat(keptHere, ", ") or "none"))
	local function describe(unit)
		local name = UnitName(unit)
		local isPlayer, faction = UnitIsPlayer(unit), UnitFactionGroup(unit)
		return ("%s: kind=%s, alpha=%.2f, can attack=%s, player=%s, faction=%s"):format(
			Known(name) and tostring(name) or "?", tostring(PlateKind(unit)),
			PlateAlpha(unit, C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)),
			tostring(UnitCanAttack("player", unit)),
			Known(isPlayer) and tostring(isPlayer) or "secret", Known(faction) and tostring(faction) or "secret")
	end
	local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
	-- Plates the game has locked away from addons aren't in the usual list.
	local all = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates(true) or {}
	local units = 0
	for i = 1, 40 do
		if UnitExists("nameplate" .. i) then
			units = units + 1
		end
	end
	ns.Print(("%d plates up (%d counting locked ones, %d nameplate units)"):format(#plates, #all, units))
	for i, plate in ipairs(plates) do
		if i > 8 then break end
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		local shown = plate.UnitFrame and ("%.2f"):format(plate.UnitFrame:GetAlpha()) or "-"
		ns.Print(("  %s (unit %s, frame alpha %s)"):format(unit and describe(unit) or "?", tostring(unit), shown))
	end
	if UnitExists("target") then
		local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
		ns.Print("target " .. describe("target") .. (plate and ", has a plate" or ", NO plate"))
	end
end

function ns.ShowPlatesNow()
	if ns.plates.off and not InCombatLockdown() then
		ns.ApplyCVarSet(PLATE_CVARS, false)
		ns.plates.off = false
		ns.plates.level = 0
	end
end

-- Each row's game settings (older and newer clients' names, and the pets,
-- guardians and totems a Minions row covers). Anything ticked in a row
-- switches them on for good, and its parent's too (Minions and Minor need
-- their units' plates on); unticking leaves them alone. The game has one
-- switch for all enemy plates, so both enemy rows turn it on. Nameplate
-- settings can't change in a fight: then it happens once the fight ends.
local PLATE_KIND_CVARS = {
	Enemies = { "nameplateShowEnemies", "nameplateShowEnemyPlayers" },
	EnemyNPCs = { "nameplateShowEnemies" },
	EnemyMinions = {
		"nameplateShowEnemyMinions", "nameplateShowEnemyPets", "nameplateShowEnemyGuardians",
		"nameplateShowEnemyTotems",
	},
	EnemyMinor = { "nameplateShowEnemyMinus" },
	Friends = { "nameplateShowFriends", "nameplateShowFriendlyPlayers" },
	FriendlyMinions = {
		"nameplateShowFriendlyMinions", "nameplateShowFriendlyPets", "nameplateShowFriendlyGuardians",
		"nameplateShowFriendlyTotems",
		-- (newer clients' names)
		"nameplateShowFriendlyPlayerMinions", "nameplateShowFriendlyPlayerPets",
		"nameplateShowFriendlyPlayerGuardians", "nameplateShowFriendlyPlayerTotems",
	},
	FriendlyNPCs = { "nameplateShowFriendlyNPCs" },
}
local PLATE_ROW_PARENT = { EnemyMinions = "Enemies", EnemyMinor = "EnemyNPCs", FriendlyMinions = "Friends" }
local pendingPlateRows = {}

-- Whether this client has any of a row's nameplate settings.
function ns.HasPlateSettings(kind)
	for _, cvar in ipairs(PLATE_KIND_CVARS[kind]) do
		if GetCVar(cvar) ~= nil then
			return true
		end
	end
	return false
end

function ns.EnablePlateRow(kind)
	if InCombatLockdown() then
		pendingPlateRows[kind] = true
		return
	end
	pendingPlateRows[kind] = nil
	for _, row in ipairs({ kind, PLATE_ROW_PARENT[kind] }) do
		for _, cvar in ipairs(PLATE_KIND_CVARS[row]) do
			SwitchOn(cvar)
		end
	end
end

-- At login, every row with anything ticked has its game settings switched on
-- (in case they were turned off in the game's options since). Rows with
-- nothing ticked are left alone.
function ns.EnsurePlateRows()
	for _, kind in ipairs(ns.PLATE_KINDS) do
		for _, prefix in ipairs({ "plateCombat", "plateCinematic", "plateInCities",
			"plateInDungeons", "plateInRaids", "plateInPvP" }) do
			if ns.db[prefix .. kind] then
				ns.EnablePlateRow(kind)
				break
			end
		end
	end
end

local platesWereFiltered = false

function ns.UpdatePlates(cinematic, elapsed)
	platesActive = cinematic and true or false
	placeSuffix = ns.PlaceSuffix()
	-- Plates show for every fight (bar kinds cinematic mode hides in fights)
	-- and hide again afterwards. Just after a fight, kinds ticked for fights
	-- stay up through their linger; the rest go as cinematic mode comes back.
	local inCombat = InCombatLockdown()
	local lingering = FightLingering()
	local holding = platesActive and lingering and AnyFightKinds()
	local hide = platesActive and not inCombat and not holding
	local keep = AnyPlatesKeptCinematic() or TargetKeptUp() or next(leavingTargets) ~= nil
	if not hide or keep then
		ns.ShowPlatesNow()
	end
	if next(pendingPlateRows) and not inCombat then
		for kind in pairs(pendingPlateRows) do
			ns.EnablePlateRow(kind)
		end
	end

	local target = hide and 0 or 1
	local changed = UpdateTargetFade(elapsed)
	changed = ns.plates.level ~= target or changed
	if changed then
		local duration = target > ns.plates.level and ns.db.fadeInTime or ns.db.fadeOutTime
		ns.plates.level = ns.Approach(ns.plates.level, target, elapsed, duration)
	end
	-- Kinds hidden in cinematic fights: held at 0 in combat, then let back up
	-- at the fade-in speed, but only while plates are on their way in. Heading
	-- out (cinematic again), they stay hidden until the fade has caught up.
	-- Held up after a fight, the kinds not ticked for fights (bar those kept
	-- up where you are) fade down the same way.
	for _, kind in ipairs(ns.PLATE_KINDS) do
		local combat = ns.db["plateCombat" .. kind]
		local cinematicKept = KeptHere(kind)
		local keptTarget = cinematicKept and 1 or 0
		if keptLevel[kind] == nil then
			keptLevel[kind] = keptTarget -- logging in: no fade
		elseif keptLevel[kind] ~= keptTarget then
			keptLevel[kind] = ns.Approach(keptLevel[kind], keptTarget, elapsed,
				keptTarget > keptLevel[kind] and ns.db.fadeInTime or ns.db.fadeOutTime)
			changed = true
		end
		if inCombat and platesActive and not combat then
			combatCap[kind] = 0
		elseif holding and not combat and not cinematicKept then
			local from = combatCap[kind] or 1
			if from > 0 then
				changed = true
			end
			combatCap[kind] = ns.Approach(from, 0, elapsed, ns.db.fadeOutTime)
		elseif combatCap[kind] then
			if hide and not cinematicKept then
				if ns.plates.level <= combatCap[kind] then
					combatCap[kind] = nil -- the fade is below the limit now: it takes over
				end
			else
				combatCap[kind] = ns.Approach(combatCap[kind], 1, elapsed, ns.db.fadeInTime)
				if combatCap[kind] >= 1 then
					combatCap[kind] = nil
				end
			end
			changed = true
		end
	end
	-- One more pass after filtering stops, to put every plate back.
	local filtered = PlatesFiltered()
	if changed or filtered or platesWereFiltered then
		RefreshAllPlates()
	end
	platesWereFiltered = filtered

	if hide and not keep and ns.plates.level == 0 and not ns.plates.off and not InCombatLockdown() then
		ns.ApplyCVarSet(PLATE_CVARS, true)
		ns.plates.off = true
	end
end

-- World tooltips (units and objects under the cursor) use the default anchor,
-- owned by UIParent. Tooltips owned by UI elements are left alone so hovering a
-- faded button still explains it. World tooltips are hidden outright while
-- cinematic: fading them fought Blizzard's own tooltip alpha and flickered.
ns.lastCinematic = false

-- Minimap blips (tracked herbs, party members) use a world-style tooltip; with
-- the cursor on the minimap it's always left showing.
local function OverMinimap()
	return Minimap ~= nil and Minimap:IsVisible() and Minimap:IsMouseOver()
end

local function WorldOwned()
	local owner = GameTooltip:GetOwner()
	return owner == nil or owner == UIParent or owner == WorldFrame
end

local function IsWorldTooltip()
	return WorldOwned() and not OverMinimap()
end

-- World tooltips hide in cinematic mode (fadeTooltip), or only in the camera
-- modes, each chosen on its own (tooltipOff*).
local TOOLTIP_OFF_IN = {
	flight = "tooltipOffFlight", idle = "tooltipOffIdle", cozy = "tooltipOffCozy",
	tele = "tooltipOffTele", walk = "tooltipOffWalk", run = "tooltipOffRun",
	vista = "tooltipOffVista", fish = "tooltipOffFish", death = "tooltipOffDeath",
	quest = "tooltipOffQuest",
}

-- The camera mode running now, for the tooltip settings: the death, quest and
-- tele cameras as well as the ones ns.CameraMode knows (it counts tele as cozy).
local function TooltipCameraMode()
	if ns.IsDeathCinematic and ns.IsDeathCinematic() then
		return "death"
	elseif ns.QuestCamActive and ns.QuestCamActive() then
		return "quest"
	elseif ns.IsTele and ns.IsTele() then
		return "tele"
	end
	return ns.CameraMode and ns.CameraMode()
end
-- Whether world tooltips are hidden right now (not whether one is up).
-- Hiding world tooltips is switched off for now, its page hidden with it:
-- they always show. True brings the feature (and its saved settings) back.
ns.WORLD_TOOLTIP_HIDING = false

local function HidingWorldTooltips()
	if not (ns.WORLD_TOOLTIP_HIDING and ns.lastCinematic) then
		return false
	end
	if ns.db.fadeTooltip then
		return true
	end
	local mode = TooltipCameraMode()
	return mode ~= nil and ns.db[TOOLTIP_OFF_IN[mode]] or false
end

-- Whether hidden world tooltips come back (after hovering, the exceptions,
-- warm): tooltipReveal.
local function Revealing()
	return ns.db.tooltipReveal and true or false
end

local function ShouldHideTooltip()
	return GameTooltip:IsShown() and IsWorldTooltip() and HidingWorldTooltips()
end

-- Reveal after hovering (tooltipReveal): the tooltip is hidden outright as
-- usual (anything gentler flashed it as it appeared), and its contents noted.
-- If you're still on the same thing after tooltipRevealDelay seconds it's put
-- back: a unit's from the mouseover, an object's from the noted lines (the game
-- has no way to ask about an object again). The cursor is usually still on
-- its way as an object's tooltip appears (at once, on a big one like a shop
-- sign), so the object's place is taken as wherever the cursor comes to rest;
-- one that doesn't rest within CURSOR_SETTLE seconds was only passing over.
-- Each move starts the wait over. After that, an object counts as left once
-- the cursor strays from there or goes over the UI, or the view moves
-- (walking, flying, turning, the camera orbiting); a unit once it's no longer
-- the mouseover.
-- A put-back tooltip is the add-on's own, so it's also taken down that way.
-- Once one's been put back, tooltips are warm: the game's own show at once,
-- left to it, until none has been up for tooltipWarmTime seconds.
local held, shown, revealedName, revealing
local warmUntil = 0
local CURSOR_REACH = 32 -- UI pixels the cursor may wander over an object
local CURSOR_REST = 3   -- UI pixels a tick that still count as resting
local CURSOR_SETTLE = 0.5 -- seconds the cursor has to come to rest over an object

local function TooltipName()
	local ok, text = pcall(function() return GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText() end)
	return ok and text or nil
end

-- A name that can't be compared (secret) counts as the same thing.
local function SameName(a, b)
	local ok, same = pcall(function() return a == b end)
	return not ok or same
end

-- The game reuses a world tooltip for the next unit without showing it again
-- (OnShow never fires), so a unit with a different name in a tooltip that's
-- already up is a new one. Only a unit: an object's tooltip (a shop sign) is
-- the add-on's own once put back, and the game can redo it in place.
local function ReusedForUnit(name)
	local ok, isUnit = pcall(function()
		local _, unit = GameTooltip:GetUnit()
		return unit ~= nil
	end)
	return ok and isUnit and not SameName(TooltipName(), name)
end

local function Warm()
	return Revealing() and GetTime() < warmUntil
end

local function KeepWarm()
	warmUntil = GetTime() + (ns.db.tooltipWarmTime or 0)
end

-- The titles of the quests in your log.
local function QuestTitles()
	local titles = {}
	if C_QuestLog and C_QuestLog.GetInfo then
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.title then
				titles[info.title] = true
			end
		end
	elseif GetQuestLogTitle then
		for i = 1, GetNumQuestLogEntries() do
			local title, _, _, isHeader = GetQuestLogTitle(i)
			if title and not isHeader then
				titles[title] = true
			end
		end
	end
	return titles
end

-- Whether the tooltip lists a quest objective: from the lines' own kinds where
-- the client gives them, or else (or as well) a line naming a quest in your log with an
-- objective (" - 5/7 Thistle Boar slain") under it. Unreadable (secret) lines
-- count as no.
local function ShowsQuestObjective(tooltip)
	local objective = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
	if objective and tooltip.GetTooltipData then
		local ok, found = pcall(function()
			local data = tooltip:GetTooltipData()
			for _, line in ipairs(data and data.lines or {}) do
				if line.type == objective then
					return true
				end
			end
			return false
		end)
		if ok and found then
			return true
		end
	end
	local ok, found = pcall(function()
		local titles = QuestTitles()
		for i = 1, tooltip:NumLines() - 1 do
			local line, under = _G["GameTooltipTextLeft" .. i], _G["GameTooltipTextLeft" .. (i + 1)]
			local text, below = line and line:GetText(), under and under:GetText()
			if text and titles[text] and below and below:find("^%s*%-") then
				return true
			end
		end
		return false
	end)
	return ok and found
end

-- Words that mark something gatherable, in the game's language: Herbalism and
-- Mining (from its "Requires Herbalism" and "Requires Mining" lines) and
-- "Skinnable" (English if those can't be read).
local gatherSkills
local function GatherSkills()
	if not gatherSkills then
		gatherSkills = {}
		local pattern
		if type(ITEM_REQ_SKILL) == "string" then
			pattern = "^" .. ITEM_REQ_SKILL:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
		end
		for _, entry in ipairs({ { UNIT_SKINNABLE_HERB, "Herbalism" }, { UNIT_SKINNABLE_ROCK, "Mining" } }) do
			local requires = entry[1]
			local name = pattern and type(requires) == "string" and requires:match(pattern)
			gatherSkills[#gatherSkills + 1] = name or entry[2]
		end
		gatherSkills[#gatherSkills + 1] = type(UNIT_SKINNABLE_LEATHER) == "string" and UNIT_SKINNABLE_LEATHER
			or "Skinnable"
	end
	return gatherSkills
end

-- Whether the tooltip is something gatherable: an herb or ore node, or a
-- creature to skin (a line under its name says Herbalism, Mining or
-- Skinnable). Unreadable lines count as no.
local function ShowsGatheringNode(tooltip)
	local ok, found = pcall(function()
		local skills = GatherSkills()
		for i = 2, tooltip:NumLines() do
			local line = _G["GameTooltipTextLeft" .. i]
			local text = line and line:GetText()
			if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
				for _, skill in ipairs(skills) do
					if text:find(skill, 1, true) then
						return true
					end
				end
			end
		end
		return false
	end)
	return ok and found
end

-- Whether the tooltip is a unit's you can attack (true) or can't (false):
-- players, NPCs and their minions and totems alike; nil for an object, or
-- when the game won't say (secret values in combat).
local function TooltipUnitIsEnemy(tooltip)
	local ok, enemy = pcall(function()
		local _, unit = tooltip:GetUnit()
		if not unit then
			return nil
		end
		local attackable = UnitCanAttack("player", unit)
		if issecretvalue and issecretvalue(attackable) then
			return nil
		end
		return attackable and true or false
	end)
	if ok then
		return enemy
	end
end

local function ShowsEnemy(tooltip)
	return TooltipUnitIsEnemy(tooltip) == true
end

local function ShowsFriend(tooltip)
	return TooltipUnitIsEnemy(tooltip) == false
end

-- Tooltips that skip the wait ("Except when" under Show world tooltips after
-- hovering): db key -> test.
local SHOW_AT_ONCE = {
	{ key = "tooltipQuestAtOnce", test = ShowsQuestObjective, why = "quest objective" },
	{ key = "tooltipGatherAtOnce", test = ShowsGatheringNode, why = "gatherable" },
	{ key = "tooltipEnemyAtOnce", test = ShowsEnemy, why = "enemy" },
	{ key = "tooltipFriendlyAtOnce", test = ShowsFriend, why = "friendly" },
}

local function ShowAtOnce(tooltip)
	for _, rule in ipairs(SHOW_AT_ONCE) do
		if ns.db[rule.key] and rule.test(tooltip) then
			return rule.why
		end
	end
end

-- Fades every frame (the tick is too coarse for a short fade). Fading out ends
-- by hiding the tooltip; anything else hiding or showing it stops the fade.
local fader = CreateFrame("Frame")
fader:Hide()
local fadeFrom, fadeTo, fadeStart, fadingName

local function StopFade()
	if fader:IsShown() then
		fader:Hide()
		GameTooltip:SetAlpha(1)
	end
end

local function StartFade(to)
	fadeFrom, fadeTo, fadeStart = GameTooltip:GetAlpha(), to, GetTime()
	fadingName = TooltipName()
	fader:Show()
end

fader:SetScript("OnUpdate", function(self)
	-- Reused for the next unit while fading out: finishing the fade would hide
	-- the new one, and nothing would bring it back until the mouseover changed.
	-- Treat it as newly shown instead.
	if fadeTo == 0 and ReusedForUnit(fadingName) then
		ns.OnTooltipShow(GameTooltip)
		return
	end
	local fadeTime = ns.db.tooltipFadeTime or 0
	local t = fadeTime > 0 and (GetTime() - fadeStart) / fadeTime or 1
	if t < 1 then
		GameTooltip:SetAlpha(fadeFrom + (fadeTo - fadeFrom) * t)
		return
	end
	self:Hide()
	if fadeTo == 0 then
		GameTooltip:Hide()
	end
	GameTooltip:SetAlpha(1)
end)

-- Optional trace for /cine debug tooltip: what the tooltip did and why.
local function Trace(what, ...)
	local log = ns.tooltipTrace
	if log and #log < 60 then
		log[#log + 1] = ("%.2f %s"):format(GetTime() - log.started, what:format(...))
	end
end

-- Each line on its own, so one odd line (no text, an icon, a secret value)
-- doesn't lose the rest. Blank lines are kept as spacers.
local function NoteLines(tooltip)
	local lines = {}
	local ok, count = pcall(tooltip.NumLines, tooltip)
	for i = 1, ok and count or 0 do
		pcall(function()
			local left, right = _G["GameTooltipTextLeft" .. i], _G["GameTooltipTextRight" .. i]
			local line = { left = left:GetText() or " ", lr = { left:GetTextColor() } }
			if right and right:IsShown() and right:GetText() then
				line.right, line.rr = right:GetText(), { right:GetTextColor() }
			end
			lines[#lines + 1] = line
		end)
	end
	return lines
end

local function MouseOverWorld()
	local focus
	if GetMouseFoci then
		focus = GetMouseFoci()[1]
	elseif GetMouseFocus then
		focus = GetMouseFocus()
	end
	return focus == nil or focus == WorldFrame
end

-- Where the player is and faces. An object is only found by what's under the
-- cursor, and a parked cursor stays still while flying or turning moves the
-- world under it, so the view moving counts as leaving the object too.
local VIEW_SLACK_YARDS = 0.5
local VIEW_SLACK_FACING = math.rad(2)

-- Secret values (the game hiding them from addons) can't be compared, so
-- they count as unknown.
local function Readable(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

local function PlayerView()
	local okPos, y, x = pcall(UnitPosition, "player")
	local okFacing, facing = pcall(GetPlayerFacing)
	if not (okPos and Readable(x) and Readable(y)) then
		x, y = nil, nil
	end
	if not (okFacing and Readable(facing)) then
		facing = nil
	end
	return x, y, facing
end

local function ViewMoved(note)
	local ok, speed = pcall(GetUnitSpeed, "player")
	if (ok and Readable(speed) and speed > 0) or UnitOnTaxi("player") or IsMouselooking()
		or (ns.yawAxis and ns.yawAxis.moving) or (ns.pitchAxis and ns.pitchAxis.moving) then
		return true
	end
	local x, y, facing = PlayerView()
	local moved = false
	pcall(function()
		if x and note.px and (math.abs(x - note.px) > VIEW_SLACK_YARDS or math.abs(y - note.py) > VIEW_SLACK_YARDS) then
			moved = true
		end
		if facing and note.facing then
			local turn = math.abs(facing - note.facing) % (2 * math.pi)
			if math.min(turn, 2 * math.pi - turn) > VIEW_SLACK_FACING then
				moved = true
			end
		end
	end)
	return moved
end

local function HoldBack(tooltip)
	-- One that skips the wait is left up, the game's own, and warms the rest.
	local atOnce = Revealing() and ShowAtOnce(tooltip)
	if atOnce then
		Trace("at once (%s): %s", atOnce, tostring(TooltipName()))
		held = nil
		KeepWarm()
		return
	end
	if Revealing() then
		local name = TooltipName()
		if held and SameName(name, held.name) then
			-- The game showing the same thing again (a unit refreshing): keep counting.
			Trace("same again: %s", tostring(name))
		else
			local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
			local x, y = GetCursorPosition()
			local px, py, facing = PlayerView()
			held = {
				name = name, unit = ok and unit or nil, x = x, y = y, lastX = x, lastY = y,
				px = px, py = py, facing = facing, settleBy = GetTime() + CURSOR_SETTLE,
				lines = not (ok and unit) and NoteLines(tooltip) or nil,
				at = GetTime() + (ns.db.tooltipRevealDelay or 0),
			}
			Trace("hold %s (%s, %d lines)", tostring(name), held.unit and "unit" or "object",
				held.lines and #held.lines or 0)
		end
	end
	revealedName = nil
	StopFade()
	tooltip:Hide()
end

local function StillOver(note)
	if note.unit then
		return UnitExists("mouseover")
	end
	if not note.settled then
		return GetTime() <= note.settleBy and MouseOverWorld() and not ViewMoved(note)
	end
	local x, y = GetCursorPosition()
	local reach = CURSOR_REACH * UIParent:GetEffectiveScale()
	return math.abs(x - note.x) <= reach and math.abs(y - note.y) <= reach and MouseOverWorld()
		and not ViewMoved(note)
end

-- An object's wait starts over while the cursor is still moving; until it
-- first rests, the object's place follows it.
local function WaitForRest(note)
	if note.unit then
		return
	end
	local x, y = GetCursorPosition()
	local rest = CURSOR_REST * UIParent:GetEffectiveScale()
	if math.abs(x - note.lastX) > rest or math.abs(y - note.lastY) > rest then
		note.at = GetTime() + (ns.db.tooltipRevealDelay or 0)
		if not note.settled then
			note.x, note.y = x, y
		end
	elseif not note.settled then
		note.settled = true
		Trace("rests on %s", tostring(note.name))
	end
	note.lastX, note.lastY = x, y
end

local function Reveal()
	local tooltip, note = GameTooltip, held
	held = nil
	note.settled = true -- (with no wait set, it may not have rested yet)
	revealing = true
	StopFade()
	local ok, err = pcall(GameTooltip_SetDefaultAnchor, tooltip, UIParent)
	if note.unit then
		ok, err = pcall(tooltip.SetUnit, tooltip, "mouseover")
	else
		-- A line that won't go back is skipped rather than losing the tooltip.
		for _, line in ipairs(note.lines) do
			pcall(function()
				if line.right then
					tooltip:AddDoubleLine(line.left, line.right, line.lr[1], line.lr[2], line.lr[3],
						line.rr[1], line.rr[2], line.rr[3])
				else
					tooltip:AddLine(line.left, line.lr[1], line.lr[2], line.lr[3])
				end
			end)
		end
		if #note.lines > 0 then
			ok, err = pcall(tooltip.Show, tooltip)
		end
	end
	Trace("reveal %s (%d lines) ok=%s %s", tostring(note.name), note.lines and #note.lines or -1,
		tostring(ok), ok and "" or tostring(err))
	revealing = false
	revealedName, shown = TooltipName(), note
	KeepWarm()
	if tooltip:IsShown() then
		tooltip:SetAlpha(0)
		StartFade(1)
	end
end

-- Catches each new world tooltip the moment it appears (a hidden tooltip shows
-- again for the next thing you mouse over, so this runs every time).
function ns.OnTooltipShow(self)
	if revealing then
		return
	end
	if ns.tooltipTrace then
		local owner = self:GetOwner()
		Trace("show %s owner=%s world=%s hiding=%s", tostring(TooltipName()),
			tostring(owner and (owner:GetName() or "unnamed")), tostring(IsWorldTooltip()),
			tostring(HidingWorldTooltips()))
	end
	StopFade() -- something new: never leave it part-faded
	shown = nil -- the game's own now (a minimap blip, a UI element, the next thing)
	if not ShouldHideTooltip() then
		return
	end
	if revealedName and SameName(TooltipName(), revealedName) then
		return -- the revealed one refreshing
	end
	if Warm() then
		Trace("warm, showing %s", tostring(TooltipName()))
		held, revealedName = nil, nil
		KeepWarm()
		return
	end
	HoldBack(self)
end

function ns.OnTooltipHide()
	StopFade()
end

-- Runs on the tick: counts down a held tooltip, and covers a tooltip that was
-- already up when cinematic mode started.
function ns.UpdateTooltip()
	-- Any world tooltip up keeps them warm.
	if Warm() and GameTooltip:IsShown() and IsWorldTooltip() then
		KeepWarm()
	end
	-- Gone, or taken over by a UI element's tooltip (left alone). (Not the
	-- minimap exception: a put-back tooltip is the add-on's to take down, and
	-- nothing else would if the cursor went over the minimap.)
	if shown and not (GameTooltip:IsShown() and WorldOwned()) then
		shown, revealedName = nil, nil
	end
	-- Straight from the revealed one onto the next unit: caught here as new.
	if shown and revealedName and ReusedForUnit(revealedName) then
		Trace("replaced %s", tostring(revealedName))
		ns.OnTooltipShow(GameTooltip)
		return
	end
	if shown and not StillOver(shown) then
		Trace("left %s, fading out", tostring(shown.name))
		shown, revealedName = nil, nil
		StartFade(0)
		return
	end
	if held then
		if not (Revealing() and HidingWorldTooltips() and StillOver(held)) then
			if ns.tooltipTrace then
				local x, y = GetCursorPosition()
				Trace("drop %s: reveal=%s hiding=%s moved=%.0f,%.0f overWorld=%s overMinimap=%s mouseover=%s view=%s",
					tostring(held.name), tostring(Revealing()), tostring(HidingWorldTooltips()),
					x - held.x, y - held.y, tostring(MouseOverWorld()), tostring(OverMinimap()),
					tostring(UnitExists("mouseover")), tostring(not held.unit and ViewMoved(held)))
			end
			held = nil
		else
			WaitForRest(held)
			if GetTime() >= held.at then
				Reveal()
			end
		end
	elseif not (fader:IsShown() and fadeTo == 0) -- let a fade-out finish
		and not Warm() and ShouldHideTooltip() and not (revealedName and SameName(TooltipName(), revealedName)) then
		HoldBack(GameTooltip)
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
	ns.AddOverlay(ns.letterbox)
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
