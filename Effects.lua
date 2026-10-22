-- Cinematic: effects that follow cinematic mode. Hidden names, music,
-- nameplates, world tooltips and the letterbox bars.
local ADDON_NAME, ns = ...
local L = ns.L

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
-- Rows marked plate are for units with nameplates: in CineMode away from
-- dungeons and raids (ns.PlatesForcedHere) a kept name shows on the unit's
-- plate, the rest of the plate hidden, as a unit with a plate switched on
-- gets no name over its head (even with the plate faded out). Beyond plate
-- range, where no unit has one, the game's own names still show as the rows
-- say. Your own name and critters' have no plate.
ns.NAME_GROUPS = {
	{ key = "Self", label = L["My Name"], cvars = { "UnitNameOwn" } },
	-- The game's NPC Names choice (None, quest NPCs... all NPCs) is these
	-- together; switched on, it only changes from None (to all).
	{ key = "NPCs", label = L["NPC Names"], anyOn = true, plate = true,
		cvars = { "UnitNameNPC", "UnitNameHostleNPC", "UnitNameInteractiveNPC", "UnitNameFriendlySpecialNPCName" } },
	{ key = "Critters", label = L["Critters and Companions"], cvars = { "UnitNameNonCombatCreatureName" } },
	{ key = "Friends", label = L["Friendly Players"], plate = true, cvars = { "UnitNameFriendlyPlayerName" } },
	{ key = "FriendlyMinions", label = L["Minions"], indent = true, plate = true,
		cvars = {
			"UnitNameFriendlyMinionName", "UnitNameFriendlyPetName", "UnitNameFriendlyGuardianName",
			"UnitNameFriendlyTotemName",
		} },
	{ key = "Enemies", label = L["Enemy Players"], plate = true, cvars = { "UnitNameEnemyPlayerName" } },
	{ key = "EnemyMinions", label = L["Minions"], indent = true, plate = true,
		cvars = {
			"UnitNameEnemyMinionName", "UnitNameEnemyPetName", "UnitNameEnemyGuardianName",
			"UnitNameEnemyTotemName",
		} },
	-- Not in the game's menu: whatever you've targeted shows its name
	-- even with its kind's names off, unless this is off too. (On a plate:
	-- your target's, whatever its kind's row says.)
	{ key = "Target", label = L["Target"], plate = true, cvars = { "UnitNameFocused" } },
}
ns.OnLanguage(function() ns.TranslateFields(ns.NAME_GROUPS, "label") end)

local CVAR_SETS = {}
for _, group in ipairs(ns.NAME_GROUPS) do
	local values = {}
	for _, cvar in ipairs(group.cvars) do values[cvar] = "0" end
	-- Secure: the game blocks changing name settings in combat. A fight's
	-- names are set just before it starts (ns.UpdateCVarsForFight).
	CVAR_SETS[#CVAR_SETS + 1] = { key = group.key, values = values, secure = true, playerWins = true }
end

-- Whether CineMode keeps every nameplate switched on (see FORCED_PLATE_CVARS),
-- leaving what shows to the plates' fades: everywhere but dungeons and raids,
-- where the game locks friendly plates away from addons.
function ns.PlatesForcedHere(cinematic)
	return cinematic and ns.db.handlePlates and ns.PlateSuffix() ~= "Instances" or false
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

-- Sets a game setting for good: straight away, or, while cinematic mode has
-- it put away, in the value it comes back to.
local function SetOwnValue(cvar, value)
	if GetCVar(cvar) == nil then
		return
	end
	if ns.IsCVarHeld(cvar) then
		ns.db.savedCVars[cvar] = value
		return
	end
	-- (A value left over from a fight or a crash isn't holding it off.)
	ns.db.savedCVars[cvar] = nil
	if GetCVar(cvar) ~= value then
		SetCVar(cvar, value)
	end
end

-- Whether any box in a names row is ticked.
local NAME_ROW_PREFIXES = { "nameAlways", "nameGroup", "nameCombat", "nameCombatPvP", "nameKeep",
	"nameInInstances", "nameInPvP", "nameInBGs" }
local function NameRowTicked(group)
	for _, prefix in ipairs(NAME_ROW_PREFIXES) do
		if ns.db[prefix .. group.key] then
			return true
		end
	end
	return false
end

-- A names row and the game's own option for it go together: anything ticked
-- in the row switches the game's names on (only names the game shows can stay
-- up), nothing ticked switches them off.
function ns.SyncNameRow(group)
	local on = NameRowTicked(group)
	if on and group.anyOn then
		for _, cvar in ipairs(group.cvars) do
			local value = OwnValue(cvar)
			if value ~= nil and value ~= "0" then
				return
			end
		end
	end
	for _, cvar in ipairs(group.cvars) do
		SetOwnValue(cvar, on and "1" or "0")
	end
end

-- Switched off once plates have faded out (so invisible plates can't be
-- clicked). Can't be changed during combat lockdown.
local PLATE_CVARS = {
	secure = true,
	playerWins = true,
	values = {
		nameplateShowEnemies = "0", nameplateShowFriends = "0", nameplateShowFriendlyPlayers = "0",
		nameplateShowFriendlyNPCs = "0",
	},
}

-- Floating combat text (damage and healing numbers, like "+10" from a heal or
-- regen): off in cinematic mode while you're out of combat; back for fights.
-- CVars this client doesn't have are skipped.
local COMBAT_TEXT_CVARS = {
	playerWins = true,
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

-- The selection circle the game draws on the ground under your target (a box
-- on WoW Forever): off in cinematic mode out of combat, so a target kept
-- lazily doesn't show; back for fights.
local TARGET_CIRCLE_CVARS = {
	playerWins = true,
	values = { ObjectSelectionCircle = "0" },
}

-- Whether you were PvP flagged as the fight now under way started: names
-- can't change mid-fight, so In PvP combat names go by that.
local pvpNamesFight = false

-- Names ticked In combat (or In PvP combat, in such fights) stay up through
-- the fight and for the Calm Timer (calmTime) after it, like the plates.
-- (Always on the Nameplates page keeps a row up everywhere, and Grouped in a
-- party or raid, whatever its other boxes say.)
local function NameKeptHere(key, inCombat)
	if ns.db["nameAlways" .. key] or (ns.db["nameGroup" .. key] and ns.InGroup()) then
		return true
	end
	local fightKept = ns.db["nameCombat" .. key] or (pvpNamesFight and ns.db["nameCombatPvP" .. key])
	if inCombat or (ns.FightLingering() and fightKept) then
		return fightKept
	end
	local place = ns.PlateSuffix()
	return ns.db[place and ("nameIn" .. place .. key) or ("nameKeep" .. key)]
end

local lastCinematic = false

-- fightStarting: called as a fight starts, just before combat lockdown.
function ns.UpdateCVars(cinematic, fightStarting)
	lastCinematic = cinematic
	local inCombat = fightStarting or InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	for _, set in ipairs(CVAR_SETS) do
		-- (Nameplates page's master switch off: names are left to the game.)
		local want = cinematic and ns.db.handlePlates and not NameKeptHere(set.key, inCombat)
		ns.ApplyCVarSet(set, want or false)
	end
	-- (Kept through the Calm Timer after a fight, like the plates.)
	local fighting = inCombat or (ns.FightLingering and ns.FightLingering())
	ns.ApplyCVarSet(COMBAT_TEXT_CVARS, (cinematic and ns.db.hideCombatText and not fighting) or false)
	ns.ApplyCVarSet(TARGET_CIRCLE_CVARS, (cinematic and ns.db.hideTargetCircle and not fighting) or false)
	-- The red error text ("Target not in line of sight"): its own In combat
	-- and Out of combat boxes, CineMode or not (the addon off: always shown).
	if UIErrorsFrame then
		local hide = ns.db.enabled and ns.db[fighting and "hideErrorsInCombat" or "hideErrorsOutOfCombat"]
		UIErrorsFrame:SetAlpha(hide and 0 or 1)
	end
end

-- The last chance to switch names to the "In combat" choices before lockdown.
function ns.UpdateCVarsForFight()
	pvpNamesFight = ns.InPvPFight()
	ns.UpdateCVars(lastCinematic, true)
end

-- Music fades by ramping the music volume from 0 up to the player's own
-- volume and back. If music was already on, it's left completely alone.
ns.music = { managing = false, level = 0, volume = 1 }

-- The music volume the addon last wrote (nil while it isn't touching it). If
-- the CVar no longer matches, the player changed it in the sound settings, and
-- their change wins over any fade or mute.
local MUSIC_VOLUME_EPSILON = 0.005
local musicWritten
-- When a camera last started the addon's music this session (for music
-- fatigue). Not saved: nil after a login or /reload, so the first camera plays.
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

-- Music for standing still (not flagged AFK): Stand still's switch, or with
-- that event set to no camera (its switch greyed out) Go AFK's.
local function StillMusicOn()
	if ns.db.eventStillCamera == "none" then
		return ns.db.eventAFKMusic
	end
	return ns.db.eventStillMusic
end

-- Standing still or AFK, as far as music goes: the AFK camera, the wait for it
-- (standing still with the UI faded) or being flagged AFK. With that one's
-- music off (Camera Triggers page: Go AFK's while flagged AFK, otherwise
-- StillMusicOn's), none of these brings music back from the move-on pause;
-- music already playing carries on.
local function QuietForAFK()
	if ns.Flag(UnitIsAFK("player")) then
		return not ns.db.eventAFKMusic
	end
	local mode = ns.CameraMode and ns.CameraMode()
	return (mode == "idle" or (mode == nil and ns.stillSince ~= nil)) and not StillMusicOn()
end

-- Muting music in combat: a 0-1 level that fades down during fights and back
-- up afterwards. Music the addon plays applies it directly; the player's own
-- music gets its volume saved (crash-safe) and ducked, then restored.
local COMBAT_MUSIC_FADE = 1
-- Leaving the camera modes: none running for this long while you move. A
-- shorter gap is one camera handing over to another (vista to cozy...).
local CAM_HANDOVER = 2
-- musicOff: the player's own music switched off by the mute; managedOff: the
-- addon's cinematic music switched off by it. Kept apart so one never undoes
-- the other.
local combatMusic = { level = 1, ducking = false, original = 1, musicOff = false, managedOff = false,
	lastFightAt = -math.huge }

-- The volume share left after the combat/place mutes.
local function MusicDuck()
	return combatMusic.level
end

-- Music started within the fatigue time (Audio page) of the last start: a
-- camera starting music, or music coming back as a fresh track after a mute.
local function MusicFatigued()
	return ns.db.musicFatigue > 0 and musicStartedAt ~= nil
		and GetTime() - musicStartedAt < ns.db.musicFatigue * 60
end

-- Once fully faded out, music is switched off rather than left playing at
-- zero volume; switching it back on when the mute ends makes the game start a
-- fresh track (instead of resuming one halfway through) as it fades back in.
-- That's a start like any other, for music fatigue.
local function SetMuteMusicOff(flag, off)
	if off ~= combatMusic[flag] then
		combatMusic[flag] = off
		SetCVar("Sound_EnableMusic", off and 0 or 1)
		if not off then
			musicStartedAt = GetTime()
		end
	end
end

-- playerOverride: the player changed the music volume (or switched music back
-- on) during a mute. That lifts the mute until it clears by itself or a new
-- reason to mute comes up (a fight starting while you walk on, say).
local function UpdateCombatMusic(elapsed, playerOverride)
	-- Muted while fighting (if chosen) or in a place chosen under "Stop Music".
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
	-- Music belongs to the camera modes (flying, RP walking, standing still,
	-- vista, cozy, fishing, the quest cam...): once you leave them all and move
	-- on, it fades out, and the next one starts it again (music fatigue
	-- allowing; back before it's faded right out, it fades back in). Going from one
	-- camera straight to another (vista to cozy) isn't leaving, nor is standing
	-- still (the wait for the AFK camera). It fades at the music fade time.
	-- (Any camera mode lifts the pause: vista, cozy and fish start straight away
	-- from their emote, before standing still would count. Not the AFK camera
	-- with Go AFK's music off: the music stays paused while you're away.)
	local inCam = (ns.CameraMode and ns.CameraMode() and not QuietForAFK())
		or (ns.QuestCamActive and ns.QuestCamActive())
	if inCam then
		combatMusic.camSeenAt = now
	end
	local leftCams = now - (combatMusic.camSeenAt or -math.huge) >= CAM_HANDOVER
	if not (handlesMusic and ns.db.musicPauseWhenMoving) or inCam then
		combatMusic.movingPaused = false
	elseif ns.playerMoving and leftCams then
		combatMusic.movingPaused = true
		combatMusic.pauseFade = true
	end
	local blocked = handlesMusic and ns.IsMusicBlocked()
	local moving = combatMusic.movingPaused
	-- Music the move-on pause faded right out rests until the fatigue time
	-- (Audio page) since it last started is up: a camera starting meanwhile
	-- doesn't bring it back. Then it comes back as a fresh track.
	if combatMusic.rested and not moving then
		if MusicFatigued() then
			moving = true
		else
			combatMusic.rested = false
		end
	end
	if playerOverride then
		combatMusic.override = { fighting = fighting, blocked = blocked, moving = moving }
		combatMusic.level = 1
	end
	local o = combatMusic.override
	if o and (not (fighting or blocked or moving) or (fighting and not o.fighting)
		or (blocked and not o.blocked) or (moving and not o.moving)) then
		combatMusic.override = nil
	end
	if combatMusic.override then
		fighting, blocked, moving = false, false, false
	end
	local otherMute = fighting or blocked
	local target = (otherMute or moving) and 0 or 1
	-- The move-on pause fades at its own speed, out and back in again; the
	-- other mutes use the quick fade.
	if otherMute or combatMusic.level >= 1 then
		combatMusic.pauseFade = false
	end
	local fade = combatMusic.pauseFade and ns.db.musicFadeTime or COMBAT_MUSIC_FADE
	if combatMusic.level ~= target then
		combatMusic.level = ns.Approach(combatMusic.level, target, elapsed, fade)
	end
	local silent = combatMusic.level <= 0
	local duck = MusicDuck()
	if silent and moving then
		combatMusic.rested = true
	end

	if ns.music.managing then
		if silent and moving and not otherMute then
			-- Moved on and faded right out: that's the end of it. Coming back
			-- would be a fresh track, so the next camera starts it anew, if
			-- music fatigue allows (a pause that hasn't faded out just fades
			-- back in). Your music settings go back meanwhile.
			MusicTrace("END managed music: moved on")
			ns.StopMusicNow()
			combatMusic.managedOff = false
			return
		end
		-- The addon's own music: UpdateMusic applies the level to the volume; here
		-- it's just switched off while silent (its on/off is already saved).
		SetMuteMusicOff("managedOff", silent)
		return
	end
	combatMusic.managedOff = false -- the addon's music has stopped; its on/off was restored

	-- The player's own music: save its volume and on/off, then duck it.
	if duck < 1 and (GetCVar("Sound_EnableMusic") == "1" or combatMusic.musicOff) then
		-- (Saved again if the addon's own music put the volume back meanwhile:
		-- ducking on without a saved copy would leave it turned down for good.)
		if not combatMusic.ducking or ns.db.savedCVars.Sound_MusicVolume == nil then
			ns.SaveCVar("Sound_MusicVolume")
			ns.SaveCVar("Sound_EnableMusic")
			combatMusic.original = tonumber(ns.db.savedCVars.Sound_MusicVolume) or 1
			combatMusic.ducking = true
			-- (Your music was already playing: it counts as started, so the
			-- fatigue time covers it too.)
			musicStartedAt = musicStartedAt or GetTime()
		end
		-- Fully faded out, music is switched off and the slider goes back to
		-- your own volume (it only reads lower while actually fading).
		SetMuteMusicOff("musicOff", silent)
		SetMusicVolume(combatMusic.musicOff and combatMusic.original or combatMusic.original * duck)
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
	combatMusic.rested = false
	combatMusic.level = 1
end

-- The death song picked for this death (a music file ID), or nil; see SetDeathSong.
local deathSong = { file = nil, playing = false }

-- Music starts with a camera: as one starts with its music switch on, and
-- music fatigue allows. The flight, RP walk and auto-run cameras each have a
-- switch; the cozy, vista and fish cameras follow the event that started them
-- (the Camera Triggers page's Music column, event<key>Music). The AFK camera's
-- is Go AFK's (eventAFKMusic) while flagged AFK, Stand still's (eventStillMusic)
-- when standing still started it; the quest camera's its own event's
-- (eventQuestMusic). Music already playing just carries on: no camera swaps
-- in a new song.
local MUSIC_CAM = { flight = "musicCamFlight", walk = "musicCamWalk", run = "musicCamRun",
	quest = "eventQuestMusic" }
local EVENT_MUSIC_CAMS = { cozy = true, vista = true, fish = true }

local function CameraMusicOn(mode)
	local key = ns.ActiveEvent and ns.ActiveEvent()
	-- (A camera started from its key binding is a trigger you pulled: it
	-- starts music, as it brings CineMode on.)
	if key == "Manual" and mode ~= "flight" and mode ~= "walk" and mode ~= "run" then
		return true
	end
	if mode == "idle" then
		if ns.Flag(UnitIsAFK("player")) then
			return ns.db.eventAFKMusic or false
		end
		return StillMusicOn() or false
	end
	if EVENT_MUSIC_CAMS[mode] then
		return key ~= nil and ns.db["event" .. key .. "Music"] or false
	end
	return MUSIC_CAM[mode] ~= nil and ns.db[MUSIC_CAM[mode]] or false
end

-- The camera running ("flight", "walk"... or "quest"), and whether its start
-- is still waiting to start music (held until CineMode is in, then used up).
local musicCam, musicCamPending = nil, false

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
	-- With CineMode music off (musicInCinematic), music is never switched on:
	-- the song plays only if your game music is on already.
	local musicOn = GetCVar("Sound_EnableMusic") == "1"
	deathSong.file = on and ns.db.deathSong and (musicOn or ns.db.musicInCinematic) and ns.PickDeathSong() or nil
	if on and ns.DeathTestLog then
		ns.DeathTestLog(("death song: %s (song option %s, game music %s)"):format(
			tostring(deathSong.file), tostring(ns.db.deathSong),
			musicOn and "on" or ns.db.musicInCinematic and "off - switching it on"
				or "off, and CineMode music off: no song"))
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

-- Logging out (or /reload) mid-song: your music settings go back first, so
-- they're saved as you had them.
function ns.StopDeathSongNow()
	deathSong.file = nil
	if deathSong.playing then
		UpdateDeathSong()
	end
end

-- Switching music on or off yourself (the Sound settings' box, the Toggle
-- Music key) while the addon has it switched for now: that's your setting, so
-- it's what comes back afterwards and at logout. (Music the addon switched on
-- for a camera used to go back off at logout even after you ticked it.)
local function MusicSwitchedByPlayer(name)
	if name ~= "Sound_EnableMusic" then
		return
	end
	local stack = debugstack(3) or ""
	if stack:find("AddOns/" .. ADDON_NAME .. "/", 1, true) then
		return -- the addon's own switch
	end
	local value = GetCVar("Sound_EnableMusic")
	MusicTrace(("PLAYER switched music %s"):format(tostring(value)))
	if ns.db and ns.db.savedCVars.Sound_EnableMusic ~= nil then
		ns.db.savedCVars.Sound_EnableMusic = value
	end
	if deathSong.playing then
		deathSong.enable = value
	end
end

if C_CVar and C_CVar.SetCVar then
	hooksecurefunc(C_CVar, "SetCVar", MusicSwitchedByPlayer)
else
	hooksecurefunc("SetCVar", MusicSwitchedByPlayer)
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
	local report = ("music: cine %s mode %s | managing %s level %s vol %.2f | mute %s%s%s | cam %s | duck %s | saved %s | game: music %s volume %s"):format(
		tostring(cinematic), tostring(ns.CameraMode and ns.CameraMode()),
		tostring(ns.music.managing), Bucket(ns.music.level), ns.music.volume,
		Bucket(combatMusic.level), combatMusic.movingPaused and " (moved)" or "",
		combatMusic.override and " (overridden)" or "",
		tostring(musicCam), tostring(combatMusic.ducking),
		tostring(ns.db.savedCVars.Sound_MusicVolume), GetCVar("Sound_EnableMusic"),
		volume <= 0 and "0" or volume >= (ns.music.managing and ns.music.volume or combatMusic.original) - 0.01
			and ("%.2f"):format(volume) or "fading")
	if report ~= lastMusicReport then
		lastMusicReport = report
		ns.Print(report)
	end
end

function ns.UpdateMusic(cinematic, elapsed)
	ReportMusic(cinematic)
	-- A camera starting (or the quest cam) may start music; switching from one
	-- camera to another counts as a start too.
	local cam = (ns.CameraMode and ns.CameraMode()) or (ns.QuestCamActive and ns.QuestCamActive() and "quest") or nil
	if cam ~= musicCam then
		musicCam = cam
		musicCamPending = cam ~= nil and CameraMusicOn(cam)
	end
	UpdateDeathSong()
	if deathSong.file then
		return -- the death song has the music for now
	end
	local want = cinematic and ns.db.musicInCinematic
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
	-- Only a camera starts music, and not again within the fatigue time of the
	-- last time one did. Your own music already on is left alone.
	local start = want and musicCamPending and not ns.music.managing
	if want and musicCamPending then
		musicCamPending = false
	end
	if start and GetCVar("Sound_EnableMusic") == "0" and not MusicFatigued() then
		musicStartedAt = GetTime()
		ns.SaveCVar("Sound_EnableMusic")
		ns.SaveCVar("Sound_MusicVolume")
		ns.music.managing = true
		ns.music.level = 0
		ns.music.volume = tonumber(ns.db.savedCVars.Sound_MusicVolume) or 1
		MusicTrace(("START managed music, your volume %s"):format(tostring(ns.music.volume)))
		-- It fades in to your own volume, so with that at 0 nothing is heard.
		if ns.music.volume <= 0 and not ns.music.warnedSilent then
			ns.music.warnedSilent = true
			ns.Print(L["your game music volume is 0, so cinematic music can't be heard. " ..
				"Turn Music up in the game's Sound settings."])
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
		-- Keep writing until the mute level is back to full.
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

-- The game resets a plate's alpha itself (for one, when its unit enters
-- combat), so while a plate is faded or hidden, its alpha is put back to ours
-- every frame. At full alpha the game is left to do as it likes. (Not by
-- hooking the plate's SetAlpha: that breaks the game's own calls to it.)
local fadedPlates = {} -- [plate unit frame] = true while it has a cinematicAlpha
local plateKeeper = CreateFrame("Frame")
plateKeeper:Hide()
plateKeeper:SetScript("OnUpdate", ns.Profiled("Plate keeper", function(self)
	for frame in pairs(fadedPlates) do
		local wanted = frame.cinematicAlpha
		if wanted then
			-- (A secret alpha can't be compared: set ours again.)
			local alpha = frame:GetAlpha()
			if (issecretvalue and issecretvalue(alpha)) or alpha ~= wanted then
				if ns.plateWatch then
					ns.plateWatch.PutBack(frame, alpha, wanted)
				end
				frame:SetAlpha(wanted)
			end
		else
			fadedPlates[frame] = nil
		end
	end
	if not next(fadedPlates) then
		self:Hide()
	end
end))

-- /cine debug platewatch: logs, as it changes, how each faded plate is drawn
-- (its unit frame and name: alpha, shown, parent, ignoring the parent's
-- alpha), and each time the keeper above finds its alpha changed, to track
-- down a faded plate flashing up. Read at the start of each frame and again
-- once the frame's updates are done (OnUpdate here, and a C_Timer after).
do
	local LIMIT = 400
	local watch
	local function Num(value)
		if issecretvalue and issecretvalue(value) then
			return "secret"
		end
		return type(value) == "number" and ("%.2f"):format(value) or tostring(value)
	end
	local function State(plate, frame)
		local name = frame.name
		local nameState = "-"
		if type(name) == "table" and name.GetAlpha then
			local parent = name:GetParent()
			nameState = ("name a=%s shown=%s visible=%s ignoreParent=%s parent=%s"):format(Num(name:GetAlpha()),
				tostring(name:IsShown()), tostring(name:IsVisible()),
				tostring(name.IsIgnoringParentAlpha and name:IsIgnoringParentAlpha()),
				parent == frame and "unitframe" or (parent and (parent:GetName() or tostring(parent)) or "nil"))
		end
		local parent = frame:GetParent()
		return ("plate a=%s shown=%s | unitframe a=%s effective=%s shown=%s parent=%s | %s"):format(
			Num(plate:GetAlpha()), tostring(plate:IsShown()), Num(frame:GetAlpha()),
			Num(frame.GetEffectiveAlpha and frame:GetEffectiveAlpha()), tostring(frame:IsShown()),
			parent == plate and "plate" or (parent and (parent:GetName() or tostring(parent)) or "nil"), nameState)
	end
	local function Line(text)
		if watch.lines >= LIMIT then
			return
		end
		watch.lines = watch.lines + 1
		ns.Log("platewatch", text)
		if watch.lines == LIMIT then
			ns.Log("platewatch", "line limit reached: /reload and run it again for more")
		end
	end
	local function Scan(when)
		if not (C_NamePlate and C_NamePlate.GetNamePlates) then
			return
		end
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			local frame = plate.UnitFrame
			if frame and frame.cinematicAlpha and not (plate.IsForbidden and plate:IsForbidden()) then
				local state = State(plate, frame)
				if watch.last[frame] ~= state then
					watch.last[frame] = state
					local unit = frame.unit
					local name = unit and UnitName(unit)
					Line(("%s %s (%s, ours %.2f): %s"):format(when,
						(name and not (issecretvalue and issecretvalue(name))) and name or "?", tostring(unit),
						frame.cinematicAlpha, state))
				end
			end
		end
	end
	function ns.TogglePlateWatch()
		if ns.plateWatch then
			ns.plateWatch.frame:SetScript("OnUpdate", nil)
			ns.plateWatch = nil
			return false
		end
		watch = { lines = 0, last = setmetatable({}, { __mode = "k" }), frame = CreateFrame("Frame") }
		function watch.PutBack(frame, alpha, wanted)
			local unit = frame.unit
			local name = unit and UnitName(unit)
			Line(("keeper: %s (%s) was at %s, put back to %.2f"):format(
				(name and not (issecretvalue and issecretvalue(name))) and name or "?", tostring(unit), Num(alpha), wanted))
		end
		watch.frame:SetScript("OnUpdate", function()
			Scan("start")
			C_Timer.After(0, function()
				if ns.plateWatch == watch then
					Scan("after")
				end
			end)
		end)
		ns.plateWatch = watch
		return true
	end
end

-- The interact prompt on a plate (gamepad mode's button, over a bobber or
-- someone you can talk to: the plate's SoftTargetFrame) stays up while the
-- plate fades, with showInteractPrompt (Gamepad page).
local function KeepInteractPrompt(frame)
	local prompt = frame.SoftTargetFrame
	if not (prompt and prompt.SetIgnoreParentAlpha) or (prompt.IsForbidden and prompt:IsForbidden()) then
		return
	end
	local keep = ns.db and ns.db.showInteractPrompt and true or false
	if prompt.cinematicKept ~= keep then
		prompt:SetIgnoreParentAlpha(keep)
		prompt.cinematicKept = keep
	end
end

-- The raid marker on a plate (skull, moon...) likewise, as the Nameplates
-- page's Raid Markers grid says for the unit's side: the rest of the plate
-- fades, and a marker of our own
-- fades in over the middle of the plate, above the unit's head. (The game's
-- sits left of the health bar, which looks off with no bar there.) WoW
-- Forever won't say which marker a unit has (GetRaidTargetIndex is secret),
-- so ours copies the game's icon: its texture and its part of the sheet.
-- Retail hides the marker on some plates itself (a friendly NPC's in an
-- instance): ours stands in for it there, with the plate up too. Which marker
-- is secret, but whether there's one isn't (nil without), and the hidden icon
-- still holds it. Returns the icon, its frame, and true for a stand-in.
local function GameMarkerIcon(frame)
	local marker = frame.RaidTargetFrame
	if not (type(marker) == "table" and marker.GetRegions) or (marker.IsForbidden and marker:IsForbidden()) then
		return nil
	end
	local icon = marker.RaidTargetIcon or marker.icon or marker.Icon or marker:GetRegions()
	if not (type(icon) == "table" and icon.GetTexCoord) then
		return nil
	end
	if ns.Flag(marker:IsShown()) and ns.Flag(icon:IsShown()) then
		return icon, marker, false
	end
	if ns.isRetail then
		local ok, index = pcall(GetRaidTargetIndex, frame.unit)
		if ok and index ~= nil then
			return icon, marker, true
		end
	end
	return nil
end

-- Where ours sits from the middle of the health bar, and its size: lined up
-- with the marker the game draws over units beyond nameplate range, so going
-- in and out of range doesn't move it. (/cine debug marker tries others.)
local markerSpot = { x = 0, y = -15, size = 28 } -- (tested on WoW Forever)

local function PlaceKeptMarker(ours)
	ours:ClearAllPoints()
	ours:SetPoint("CENTER", ours.bar, "CENTER", markerSpot.x, markerSpot.y)
	ours:SetSize(markerSpot.size, markerSpot.size)
end

local function KeptMarker(frame)
	local ours = frame.cinematicMarker
	if not ours then
		ours = CreateFrame("Frame", nil, frame)
		ours.bar = frame.HealthBarsContainer or frame.healthBar or frame
		PlaceKeptMarker(ours)
		ours:SetIgnoreParentAlpha(true)
		ours.texture = ours:CreateTexture(nil, "OVERLAY")
		ours.texture:SetAllPoints()
		frame.cinematicMarker = ours
	end
	return ours
end

local function KeepRaidMarker(frame, alpha)
	-- (A plate up for its name alone: its marker goes by the rest of it.)
	local bodyAlpha = frame.cinematicBodyAlpha
	alpha = bodyAlpha or alpha
	local icon, standIn, kept
	if ns.db and ns.db.handlePlates then
		local _
		icon, _, standIn = GameMarkerIcon(frame)
		if icon then
			kept = ns.PlateRowWanted("PartMarker")
			-- (The game's own shows on a plate that's up. A stand-in only while
			-- its row is ticked: unticked, it's as the game has it, none.)
			if not kept or (not standIn and alpha >= 1) then
				icon = nil
			end
		end
	end
	local ours = frame.cinematicMarker
	if not icon then
		if ours then
			ours:Hide()
		end
		return
	end
	ours = KeptMarker(frame)
	-- (Secret values can be handed on as they are.)
	local ok = pcall(function()
		ours.texture:SetTexture(icon:GetTexture())
		ours.texture:SetTexCoord(icon:GetTexCoord())
	end)
	if not ok then
		ours:Hide()
		return
	end
	-- (A stand-in shows with its plate up as well, the game's own being hidden.)
	local level = standIn and 1 or (1 - alpha)
	ours:SetAlpha(level)
	ours:Show()
end

-- Markers put on or taken off while plates are faded (a moment later: the
-- game's markers change on the same event).
local function RefreshKeptMarkers()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local frame = plate.UnitFrame
		if frame and not (plate.IsForbidden and plate:IsForbidden()) then
			KeepRaidMarker(frame, frame.cinematicAlpha or 1)
		end
	end
end
-- For /cine debug marker: moves (and sizes) the kept markers, to line them up.
function ns.KeptMarkerSpot(x, y, size)
	if x then
		markerSpot.x, markerSpot.y, markerSpot.size = x, y or markerSpot.y, size or markerSpot.size
		if C_NamePlate and C_NamePlate.GetNamePlates then
			for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
				local ours = plate.UnitFrame and plate.UnitFrame.cinematicMarker
				if ours then
					PlaceKeptMarker(ours)
				end
			end
		end
	end
	return markerSpot.x, markerSpot.y, markerSpot.size
end
local markerWatcher = CreateFrame("Frame")
markerWatcher:RegisterEvent("RAID_TARGET_UPDATE")
-- (And plates given a unit: a stand-in shows on plates that are up, which
-- otherwise aren't looked at.)
markerWatcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
markerWatcher:SetScript("OnEvent", function(_, event)
	C_Timer.After(0, RefreshKeptMarkers)
	-- (Markers of your own, out of a group: see MarkersHiddenOverFriends.)
	if event == "RAID_TARGET_UPDATE" and not ns.InGroup() then
		markerWatcher.solo = true
	end
end)

-- A nameplate addon drawing plates of its own sets this (see Support/Plater.lua):
-- fn(plate, alpha), alpha nil to let go of the plate.
ns.addonPlateAlpha = nil

-- bodyAlpha: for a plate up for its name alone, how far the rest of it shows.
function ns.SetPlateAlpha(plate, alpha, bodyAlpha)
	if ns.addonPlateAlpha and plate and not (plate.IsForbidden and plate:IsForbidden()) then
		ns.addonPlateAlpha(plate, alpha)
	end
	if plate and plate.UnitFrame and not (plate.IsForbidden and plate:IsForbidden()) then
		local frame = plate.UnitFrame
		KeepInteractPrompt(frame)
		frame.cinematicAlpha = alpha < 1 and alpha or nil
		frame.cinematicBodyAlpha = bodyAlpha ~= nil and bodyAlpha < alpha and bodyAlpha or nil
		if frame.cinematicAlpha then
			fadedPlates[frame] = true
			plateKeeper:Show()
		end
		frame:SetAlpha(alpha)
		KeepRaidMarker(frame, alpha)
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

-- The Nameplates page's rows: enemy players (their minions apart), hostile
-- and neutral NPCs (minor units apart), friendly players (their minions apart) and
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
	-- Neutral (yellow) NPCs apart; hostile when the game won't say.
	local okReaction, reaction = pcall(UnitReaction, unit, "player")
	local neutral = okReaction and Known(reaction) and reaction == 4
	local okClass, class = pcall(UnitClassification, unit)
	if okClass and Known(class) and class == "minus" then
		return neutral and "NeutralMinor" or "EnemyMinor"
	end
	return neutral and "NeutralNPCs" or "EnemyNPCs"
end

-- The Nameplates page only steers plates in cinematic mode: outside it the
-- game's own options decide. Set each frame.
local platesActive = false

-- Where you are, for the Nameplates page's place columns: "PvP", "BGs" or
-- "Instances", or nil for the open world. Set each frame.
local placeSuffix

-- For the In PvP combat columns: fights while you're PvP flagged (as you
-- always are in battlegrounds and arenas).
local function InPvPFight()
	return ns.IsPvPFlagged() and true or false
end
ns.InPvPFight = InPvPFight

-- Whether a kind shows in fights in cinematic mode (plateCombat<kind>,
-- plateCombatPvP<kind> while flagged for PvP, or Always or Grouped on the
-- Nameplates page, which keep a row up everywhere / in a party or raid
-- whatever its other boxes say).
-- A row with a rule (Rules section, key plate:<row>) goes by it instead,
-- in fights and out: nil without one. (Keys made once each, not each frame.)
-- Hidden by its roles button while you're that role: no, whatever the rest says.
local PLATE_RULE_KEY = setmetatable({}, { __index = function(keys, kind)
	keys[kind] = "plate:" .. kind
	return keys[kind]
end })
local function RuleSays(kind)
	if ns.RoleHides(ns.RuleFactsNow())[PLATE_RULE_KEY[kind]] then
		return false
	end
	local test = ns.RuleTest(PLATE_RULE_KEY[kind])
	if test then
		return test(ns.RuleFactsNow()) and true or false
	end
end
local function ShownInFights(kind)
	local rule = RuleSays(kind)
	if rule ~= nil then
		return rule
	end
	return (ns.db["plateCombat" .. kind] or ns.db["plateAlways" .. kind]
		or (ns.db["plateGroup" .. kind] and ns.InGroup()) or (ns.db["plateCombatPvP" .. kind] and InPvPFight())) and true or false
end

-- Whether a kind stays up in cinematic mode out of combat where you are:
-- plateCinematic<kind> in the open world, plateIn<place><kind> elsewhere.
local function KeptHere(kind)
	local rule = RuleSays(kind)
	if rule ~= nil then
		return rule
	end
	local key = placeSuffix and ("plateIn" .. placeSuffix .. kind) or ("plateCinematic" .. kind)
	return (ns.db[key] or ns.db["plateAlways" .. kind] or (ns.db["plateGroup" .. kind] and ns.InGroup()))
		and true or false
end

-- How far each kind is held up by KeptHere, faded so moving between places
-- (or changing the ticks) doesn't pop plates on or off. kind -> 0 to 1.
local keptLevel = {}

-- Plates kept switched on (ns.PlatesForcedHere): set each frame. Their
-- settings (below).
local platesForced = false
local FORCED_PLATE_CVARS

-- Names kept on plates (Names rows marked plate), faded like keptLevel:
-- group key -> 0 to 1. A plate shows its name as far as its kind's group (or,
-- your target's, the Target row) says, the rest of it only as far as its
-- own alpha says.
local nameLevel = {}
local KIND_NAME_GROUP = {
	Friends = "Friends", FriendlyMinions = "FriendlyMinions", Enemies = "Enemies", EnemyMinions = "EnemyMinions",
	EnemyNPCs = "NPCs", NeutralNPCs = "NPCs", EnemyMinor = "NPCs", NeutralMinor = "NPCs", FriendlyNPCs = "NPCs",
}

local function NamesOnPlates()
	for _, level in pairs(nameLevel) do
		if level > 0 then
			return true
		end
	end
	return false
end

local function Ask(fn, ...)
	local ok, value = pcall(fn, ...)
	return ok and Known(value) and value and true or false
end

-- The Nameplates grid's rows for particular units (ns.PLATE_UNIT_ROWS): your
-- target, your pet, your party or raid's players and their pets. They only
-- add: a plate shows as far as its kind's row or any of these lets it. In
-- fights a row's In Combat boxes count; out of them, where you are (and just
-- after a fight, both).
local function UnitRowWanted(row)
	if InCombatLockdown() then
		return ShownInFights(row)
	end
	return KeptHere(row) or (ns.FightLingering() and ShownInFights(row))
end
ns.PlateRowWanted = UnitRowWanted -- (the Plate Parts rows go by the same columns: see PlateParts)

-- Whether a unit row has anyone to show now (your target's has its own fade, below).
-- Quest mobs (plateQuestMobs, the Vision page's Quest Vision): units that count
-- for a quest objective you haven't finished, everywhere in CineMode, fights included.
local function UnitRowActive(row)
	if row == "QuestMobs" then
		return ns.QuestVisionSetting("plateQuestMobs") and true or false
	end
	if not UnitRowWanted(row) then
		return false
	end
	if row == "MyPet" then
		return Ask(UnitExists, "pet")
	end
	return ns.InGroup()
end

-- Whether a plate's unit is the one (or one of those) a unit row covers.
local function InUnitRow(row, unit, kind)
	if row == "MyPet" then
		return kind == "FriendlyMinions" and Ask(UnitIsUnit, unit, "pet")
	end
	if row == "QuestMobs" then
		return kind ~= "Friends" and kind ~= "Enemies" and ns.IsQuestMob(unit)
	end
	local wanted = row == "GroupMembers" and "Friends" or "FriendlyMinions"
	if kind ~= wanted or (row == "GroupMinions" and Ask(UnitIsUnit, unit, "pet")) then
		return false -- (your pet has its own row)
	end
	return Ask(UnitPlayerOrPetInParty, unit) or Ask(UnitPlayerOrPetInRaid, unit)
end

-- How far each unit row holds its plates up, faded like keptLevel. row -> 0 to 1.
local unitRowLevel = { MyPet = 0, GroupMembers = 0, GroupMinions = 0, QuestMobs = 0 }

local function UnitRowAlpha(unit, kind)
	local alpha = 0
	for row, level in pairs(unitRowLevel) do
		if level > alpha and InUnitRow(row, unit, kind) then
			alpha = level
		end
	end
	return alpha
end

-- Duels nearby (duelPlates, Nameplates page). In CineMode, in the open world
-- and out of fights, friendly players' plates are switched on but kept
-- invisible (and click-through), and the two players in a duel near you get
-- theirs back, so you can watch their health. A duel is two of your faction's
-- players, both in combat, who can attack each other. Not in cities,
-- instances, free-for-all areas (anyone can attack anyone there) or on
-- flights, nor while you're fighting or dueling yourself. Each duel has a
-- colour, a border round both players' health bars, with a class icon
-- badge beside each, so it's clear who's fighting whom. The game's "has defeated ... in a
-- duel" line ends it: the winner's badge turns to a crown, the loser's to a
-- cross, for a few seconds before their plates fade out.
local duels = {
	on = false, -- friendly plates switched on (and click-through) for watching
	watching = false,
	-- How far each duelist's plate is held up, 0 to 1, by name (by plate when
	-- the game won't say), so a plate taken away and given back (the player
	-- behind the camera a moment) comes back where it was, not faded in again.
	levels = {}, -- [name or plate] = 0 to 1
	keyOf = {}, -- [plate] = its key in levels
	shown = {}, -- [plate] = { pair = duel, name = player's name }: at the last scan
	infoByName = {}, -- [name] = the same, for a plate given to a duelist between scans
	pairs = {}, -- [key] = { color, names, seen, and once over: endedAt, winner, loser, fled }
	ended = {}, -- [name] = when their duel ended (not picked again while they cool down)
	scanAt = 0,
	selfUntil = 0, -- dueling yourself (asked or asking) until then, or until it ends
	-- (Name-only friendly players have no health bar to watch: off meanwhile.)
	cvars = { secure = true, playerWins = true,
		values = { nameplateShowFriends = "1", nameplateShowFriendlyPlayers = "1",
			nameplateShowOnlyNameForFriendlyPlayerUnits = "0" } },
}
do
	local SCAN_EVERY = 0.5
	local ENDED_COOLDOWN = 10
	local RESULT_TIME = 6 -- seconds the winner and loser show after a duel
	-- A duel with no sign of going on for this long is let go (out of plate
	-- range, or walked off). Signs: the two can attack each other, or one has
	-- the other targeted.
	local LOST_TIME = 10
	local NO_DUEL_ZONES = { arena = true, combat = true, sanctuary = true }
	local NO_DUEL_PLACES = { city = true, dungeon = true, raid = true, pvp = true }
	local ZonePvPInfo = (C_PvP and C_PvP.GetZonePVPInfo) or GetZonePVPInfo
	-- Each duel's colour, the first free one (not red or green: those read as
	-- enemy and friend).
	local COLORS = {
		{ 1, 0.82, 0 }, { 0.2, 0.85, 0.95 }, { 0.75, 0.45, 1 }, { 1, 0.55, 0.15 }, { 1, 0.45, 0.75 },
		{ 1, 1, 1 },
	}

	-- A global string such as DUEL_WINNER ("%1$s has defeated %2$s in a duel")
	-- as a pattern catching both names, and which argument each catch is.
	local function DuelPattern(text)
		if type(text) ~= "string" then
			return nil
		end
		local order, n = {}, 0
		local marked = text:gsub("%%(%d?)%$?s", function(index)
			n = n + 1
			order[n] = tonumber(index) or n
			return "\001"
		end)
		local pattern = marked:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("\001", "(.+)")
		return { pattern = "^" .. pattern .. "$", order = order }
	end
	-- DUEL_WINNER: winner, then loser. DUEL_FLED: who fled, then who won.
	-- (WoW Forever has neither: its lines are in English.)
	local WINNER = DuelPattern(DUEL_WINNER or "%1$s has defeated %2$s in a duel")
	local FLED = DuelPattern(DUEL_FLED or "%1$s has fled from %2$s in a duel")

	-- A name from the duel line as UnitName gives it: no realm, and on WoW
	-- Forever no surname ("Unholy Might" is Unholy). Names have no spaces.
	local function ShortName(name)
		return name and name:match("^[^%-%s]+")
	end

	-- The names a line catches, by argument: { [1] = ..., [2] = ... }.
	local function Catch(text, format)
		if not format then
			return nil
		end
		local caught = { text:match(format.pattern) }
		if #caught < 2 then
			return nil
		end
		local names = {}
		for i, value in ipairs(caught) do
			names[format.order[i] or i] = ShortName(value)
		end
		return names
	end

	local function PairKey(a, b)
		return a < b and (a .. "\n" .. b) or (b .. "\n" .. a)
	end

	local function FreeColor()
		local used = {}
		for _, pair in pairs(duels.pairs) do
			used[pair.color] = true
		end
		for i = 1, #COLORS do
			if not used[i] then
				return i
			end
		end
		return 1
	end

	local function PairFor(key, a, b)
		local pair = duels.pairs[key]
		if not pair then
			pair = { color = FreeColor(), names = { a, b } }
			duels.pairs[key] = pair
		end
		return pair
	end

	-- A duel's end: who won and who lost (or fled), shown for a while.
	local function DuelEnded(winner, loser, fled)
		if not (winner and loser) then
			return
		end
		local now = GetTime()
		local pair = PairFor(PairKey(winner, loser), winner, loser)
		if pair.endedAt and now - pair.endedAt < RESULT_TIME then
			return -- (the same line again)
		end
		pair.winner, pair.loser, pair.fled, pair.endedAt = winner, loser, fled, now
		duels.ended[winner], duels.ended[loser] = now, now
		duels.scanAt = 0
	end

	-- A line that may be a duel's end (source, for /cine debug duels). True
	-- if it was one.
	local function DuelLine(text, source)
		local names = Catch(text, WINNER)
		local fled = false
		if not names then
			names, fled = Catch(text, FLED), true
		end
		if not names then
			return false
		end
		duels.lastResult = { text = text, source = source, at = GetTime() }
		if fled then
			DuelEnded(names[2], names[1], true)
		else
			DuelEnded(names[1], names[2], false)
		end
		return true
	end

	local watcher = CreateFrame("Frame")
	for _, event in ipairs({ "CHAT_MSG_SYSTEM", "DUEL_REQUESTED", "DUEL_FINISHED" }) do
		pcall(watcher.RegisterEvent, watcher, event)
	end
	watcher:SetScript("OnEvent", function(_, event, text)
		if event == "DUEL_REQUESTED" then
			duels.selfUntil = GetTime() + 60
		elseif event == "DUEL_FINISHED" then
			duels.selfUntil = 0
		elseif Known(text) and type(text) == "string" then
			duels.lastSystem = text
			DuelLine(text, "event")
		else
			duels.lastSystem = "(unreadable: " .. type(text) .. ")"
		end
	end)

	-- Asking someone to a duel yourself.
	if StartDuel then
		hooksecurefunc("StartDuel", function()
			duels.selfUntil = GetTime() + 60
		end)
	end

	-- Why duels aren't watched now (nil: they are).
	local function NotWatchingWhy()
		if not ns.Setting("duelPlates") then
			return "option off"
		elseif not platesActive then
			return "not in CineMode"
		elseif InCombatLockdown() or Ask(UnitAffectingCombat, "player") then
			return "in combat"
		elseif GetTime() < duels.selfUntil then
			return "dueling yourself"
		elseif Ask(UnitOnTaxi, "player") then
			return "on a flight"
		elseif NO_DUEL_PLACES[ns.GetPlaceType() or ""] then
			return "no duels here (" .. ns.GetPlaceType() .. ")"
		elseif (UnitIsPVPFreeForAll and Ask(UnitIsPVPFreeForAll, "player"))
			or (ZonePvPInfo and NO_DUEL_ZONES[ZonePvPInfo() or ""]) then
			return "free-for-all or no-duel zone"
		end
		return nil
	end
	duels.NotWatchingWhy = NotWatchingWhy

	local function SetClickThrough(on)
		local set = C_NamePlate and C_NamePlate.SetNamePlateFriendlyClickThrough
		local get = C_NamePlate and C_NamePlate.GetNamePlateFriendlyClickThrough
		if not (set and get) then
			return
		end
		if on then
			if ns.db.duelClickThrough == nil then
				ns.db.duelClickThrough = get() and true or false
			end
			pcall(set, true)
		elseif ns.db.duelClickThrough ~= nil then
			pcall(set, ns.db.duelClickThrough)
			ns.db.duelClickThrough = nil
		end
	end

	-- Friendly plates on or off for watching (from ns.UpdatePlates, before the
	-- other plate settings). Plate settings can't change in a fight: then it
	-- waits. Any plate switch-off goes first, so the two don't save each
	-- other's values.
	function duels.Sync(want)
		if InCombatLockdown() then
			return
		end
		if want and not duels.on then
			ns.ShowPlatesNow()
		end
		-- (With every plate kept switched on, the watch needs none of its own.)
		ns.ApplyCVarSet(duels.cvars, (want and not platesForced) or false)
		duels.on = duels.cvars.active or (want and platesForced) or false
		SetClickThrough(duels.on) -- (also puts back one left over from a reload)
	end

	-- Whether a unit has the named player targeted, and can attack them.
	local function Targets(unit, name)
		if not name then
			return false
		end
		local target = unit .. "target"
		local targetName = Ask(UnitExists, target) and UnitName(target)
		return Known(targetName) and targetName == name and Ask(UnitCanAttack, unit, target)
	end

	-- The duels near you: [plate] = { pair, name } for each player in one
	-- (or whose one just ended), and the friendly players in combat looked at.
	function duels.Scan()
		local now = GetTime()
		local fighters, byName = {}, {}
		for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
			local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
			if unit and Ask(UnitIsPlayer, unit) and Ask(UnitIsFriend, "player", unit)
				and not Ask(UnitIsUnit, unit, "player") then
				local name = UnitName(unit)
				name = Known(name) and name or nil
				if name then
					byName[name] = { plate = plate, unit = unit }
				end
				local ended = name and duels.ended[name]
				if Ask(UnitAffectingCombat, unit) and not Ask(UnitIsCharmed, unit)
					and not (ended and now - ended < ENDED_COOLDOWN) then
					fighters[#fighters + 1] = { plate = plate, unit = unit, name = name }
				end
			end
		end
		local shown = {}
		for i = 1, #fighters do
			for j = i + 1, #fighters do
				local a, b = fighters[i], fighters[j]
				if Ask(UnitCanAttack, a.unit, b.unit) then
					-- (Names the game won't give: the pair goes by its plates.)
					local key = (a.name and b.name) and PairKey(a.name, b.name)
						or PairKey(tostring(a.plate), tostring(b.plate))
					local pair = PairFor(key, a.name, b.name)
					pair.seen = now
					shown[a.plate] = { pair = pair, name = a.name }
					shown[b.plate] = { pair = pair, name = b.name }
				end
			end
		end
		-- A duel already found stays up until LOST_TIME passes with no sign of
		-- it going on, fighting or not (a few quiet seconds drop them out of
		-- combat), and one of them can stay up with the other's plate gone;
		-- once it's over, while its result shows.
		for _, pair in pairs(duels.pairs) do
			local a, b = byName[pair.names[1] or ""], byName[pair.names[2] or ""]
			if not pair.endedAt and ((a and b and Ask(UnitCanAttack, a.unit, b.unit))
				or (a and Targets(a.unit, pair.names[2])) or (b and Targets(b.unit, pair.names[1]))) then
				pair.seen = now
			end
			for i, found in ipairs({ a or false, b or false }) do
				if found then
					shown[found.plate] = { pair = pair, name = pair.names[i] }
				end
			end
		end
		return shown, fighters
	end

	-- Each duelist's plate: a border in the duel's colour round the health
	-- bar, and a badge beside it (their class icon; a crown or a cross once it's
	-- over, with Won or Lost below). On the plate's unit frame, so it fades
	-- with the plate. [plate] = frame.
	local overlays = {}

	local function Overlay(plate)
		local unitFrame = plate.UnitFrame
		if not unitFrame or (plate.IsForbidden and plate:IsForbidden())
			or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
			return nil
		end
		local overlay = overlays[plate]
		if overlay then
			return overlay
		end
		local bar = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame
		overlay = CreateFrame("Frame", nil, unitFrame)
		overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
		overlay:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
		overlay:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 5)
		-- The border is on the bar itself, so it hides and fades with it: a
		-- name-only plate (a friendly player's) or a faded Health part would
		-- otherwise leave an empty box that looks like a bar at 0%.
		local border = CreateFrame("Frame", nil, bar)
		border:SetAllPoints(overlay)
		border:SetFrameLevel(overlay:GetFrameLevel())
		overlay.border = border
		overlay.edges = {}
		for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			local edge = border:CreateTexture(nil, "OVERLAY")
			edge:SetColorTexture(1, 1, 1)
			if side == "TOP" or side == "BOTTOM" then
				edge:SetPoint(side .. "LEFT")
				edge:SetPoint(side .. "RIGHT")
				edge:SetHeight(2)
			else
				edge:SetPoint("TOP" .. side)
				edge:SetPoint("BOTTOM" .. side)
				edge:SetWidth(2)
			end
			overlay.edges[#overlay.edges + 1] = edge
		end
		overlay.badge = overlay:CreateTexture(nil, "OVERLAY")
		overlay.badge:SetPoint("RIGHT", overlay, "LEFT", -1, 0)
		overlay.result = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		overlay.result:SetPoint("TOP", overlay, "BOTTOM", 0, -1)
		overlays[plate] = overlay
		return overlay
	end

	local function ShowOverlay(plate, info)
		local overlay = Overlay(plate)
		if not overlay then
			return
		end
		local pair = info.pair
		local r, g, b = unpack(COLORS[pair.color] or COLORS[1])
		for _, edge in ipairs(overlay.edges) do
			edge:SetVertexColor(r, g, b)
		end
		local badge, text = overlay.badge, overlay.result
		if pair.endedAt and info.name and info.name == pair.winner then
			badge:SetSize(24, 24)
			badge:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
			badge:SetTexCoord(0, 1, 0, 1)
			badge:SetDesaturated(false)
			badge:SetVertexColor(1, 1, 1)
			text:SetText(L["Won"])
			text:SetTextColor(1, 0.82, 0)
		elseif pair.endedAt and info.name and info.name == pair.loser then
			badge:SetSize(24, 24)
			badge:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
			badge:SetTexCoord(0, 1, 0, 1)
			badge:SetDesaturated(false)
			badge:SetVertexColor(1, 1, 1)
			text:SetText(pair.fled and L["Fled"] or L["Lost"])
			text:SetTextColor(0.6, 0.6, 0.6)
		else
			-- The player's class icon (kept once read, for a plate that's lost
			-- its unit); the crossed swords from the player frame's combat icon,
			-- in the duel's colour, if the class can't be read.
			if not info.class then
				local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
				local class
				if unit then
					class = select(2, UnitClass(unit))
				end
				info.class = Known(class) and type(class) == "string" and class or nil
			end
			local coords = CLASS_ICON_TCOORDS and info.class and CLASS_ICON_TCOORDS[info.class]
			if coords then
				badge:SetSize(22, 22)
				badge:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
				badge:SetTexCoord(unpack(coords))
				badge:SetDesaturated(false)
				badge:SetVertexColor(1, 1, 1)
			else
				-- (The swords fill little of their square: drawn larger to match.)
				badge:SetSize(40, 40)
				badge:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
				badge:SetTexCoord(0.55, 0.95, 0.04, 0.445)
				badge:SetDesaturated(true)
				badge:SetVertexColor(r, g, b)
			end
			text:SetText("")
		end
		overlay.info = info
		overlay:Show()
		overlay.border:Show()
		ns.RefreshClassIcon(plate) -- (the Plate Parts class icon gives way to the badge)
	end

	-- Whether a plate has a duel's border and badge on it.
	function ns.DuelBadgeShown(plate)
		local overlay = overlays[plate]
		return overlay ~= nil and overlay.info ~= nil
	end

	-- A plate given a new unit (or let go of): its duel and its border go.
	function duels.Forget(plate)
		duels.keyOf[plate], duels.shown[plate] = nil, nil
		local overlay = overlays[plate]
		if overlay then
			overlay.info = nil
			overlay:Hide()
			overlay.border:Hide()
			ns.RefreshClassIcon(plate)
		end
	end

	-- A plate just given to a duelist (as the player comes back into view):
	-- their border, at once, and their plate where it was.
	function duels.Attach(plate, unit)
		local name = unit and UnitName(unit)
		local info = Known(name) and name and duels.watching and duels.infoByName[name]
		if info then
			duels.shown[plate], duels.keyOf[plate] = info, name
			ShowOverlay(plate, info)
		end
	end

	function duels.Level(plate)
		local key = plate and duels.keyOf[plate]
		return key and duels.levels[key] or 0
	end

	function duels.Clear()
		for plate in pairs(overlays) do
			duels.Forget(plate)
		end
		wipe(duels.levels)
		wipe(duels.keyOf)
		wipe(duels.shown)
		wipe(duels.infoByName)
		wipe(duels.pairs)
	end

	-- Moves the duelists' plates' fades on; true while any of them is moving.
	function duels.Update(elapsed)
		local now = GetTime()
		duels.watching = duels.on and NotWatchingWhy() == nil
		for key, pair in pairs(duels.pairs) do
			if (pair.endedAt and now - pair.endedAt >= RESULT_TIME)
				or (not pair.endedAt and now - (pair.seen or 0) >= LOST_TIME) then
				duels.pairs[key] = nil
			end
		end
		for name, at in pairs(duels.ended) do
			if now - at >= ENDED_COOLDOWN then
				duels.ended[name] = nil
			end
		end
		if not duels.watching then
			wipe(duels.shown)
			wipe(duels.infoByName)
		elseif now >= duels.scanAt then
			duels.scanAt = now + SCAN_EVERY
			duels.shown = duels.Scan()
			wipe(duels.infoByName)
			for plate, info in pairs(duels.shown) do
				duels.keyOf[plate] = info.name or plate
				if info.name then
					duels.infoByName[info.name] = info
				end
				ShowOverlay(plate, info)
			end
		end
		local moving = false
		local wanted = {}
		for plate in pairs(duels.shown) do
			local key = duels.keyOf[plate]
			wanted[key] = true
			duels.levels[key] = duels.levels[key] or 0
		end
		-- Both players of a duel still going stay held up with their plates
		-- gone (off screen, behind the camera), so a plate given back shows at
		-- once rather than fading in again.
		if duels.watching then
			for _, pair in pairs(duels.pairs) do
				for _, name in ipairs(pair.names) do
					if duels.levels[name] then
						wanted[name] = true
						duels.infoByName[name] = duels.infoByName[name] or { pair = pair, name = name }
					end
				end
			end
		end
		for key, level in pairs(duels.levels) do
			local target = wanted[key] and 1 or 0
			if level ~= target then
				duels.levels[key] = ns.Approach(level, target, elapsed,
					target > level and ns.FadeInTime() or ns.FadeOutTime())
				moving = true
			elseif target == 0 then
				duels.levels[key] = nil
			end
		end
		-- (Borders stay as they last were while a plate fades out.)
		for plate, overlay in pairs(overlays) do
			if overlay.info and not duels.shown[plate] and duels.Level(plate) <= 0 then
				duels.Forget(plate)
			end
		end
		return moving
	end
end

-- Any kind kept up in cinematic mode keeps the plates switched on.
local function AnyPlatesKeptCinematic()
	if duels.on or next(duels.levels) then
		return true
	end
	for row, level in pairs(unitRowLevel) do
		if level > 0 or UnitRowActive(row) then
			return true
		end
	end
	for _, kind in ipairs(ns.PLATE_KINDS) do
		if KeptHere(kind) or (keptLevel[kind] or 0) > 0 then
			return true
		end
	end
	return false
end

-- Which of the Target Nameplate rows your target goes by, players and NPCs
-- apart: Enemy (those you can attack), Neutral (NPCs the game calls neutral,
-- and the other faction's players you can't attack) or Friendly (the rest,
-- and the dead). nil when the game won't say.
local function TargetRow(unit)
	local who = Ask(UnitIsPlayer, unit) and "Player" or "NPC"
	if Ask(UnitIsDeadOrGhost, unit) then
		return "MyFriendly" .. who .. "Target"
	end
	local enemy = ns.IsEnemyUnit(unit)
	if enemy == nil then
		return nil
	end
	if not enemy then
		return "MyFriendly" .. who .. "Target"
	end
	local neutral
	if who == "Player" then
		neutral = not Ask(UnitCanAttack, "player", unit)
	else
		local ok, reaction = pcall(UnitReaction, unit, "player")
		neutral = ok and Known(reaction) and reaction == 4
	end
	return (neutral and "MyNeutral" or "MyEnemy") .. who .. "Target"
end

-- Whether your target's plate shows now (its target row), whatever its
-- kind's row says.
local function AlwaysShownTarget(unit)
	local row = TargetRow(unit)
	return row ~= nil and UnitRowWanted(row)
end

local function TargetKeptUp()
	return ns.HasTarget() and AlwaysShownTarget("target") -- (not one dropped at takeoff)
end

-- Kept raid markers (see KeepRaidMarker) need their plates switched on: in a
-- group, where markers are used, or while your target has one.
local function MarkersKeptUp()
	if not UnitRowWanted("PartMarker") then
		return false
	end
	if ns.InGroup() then
		return true
	end
	local ok, index = pcall(GetRaidTargetIndex, "target")
	if ok and Known(index) then
		return index ~= nil
	end
	-- (Secret on WoW Forever: the target's plate's marker says.)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
	return plate ~= nil and plate.UnitFrame ~= nil and GameMarkerIcon(plate.UnitFrame) ~= nil
end

-- Friendly units' markers that fade with the plates (the Names grid's Raid
-- Marker row unticked) need
-- friendly players' plates switched on, kept invisible like the duel watch's: a friendly player with no plate has the
-- game draw its marker over their head itself, and nothing hides that one
-- (tested on WoW Forever; nor the one over your own head). Only where
-- markers are seen: in a group, or once you've marked something yourself.
-- Not in dungeons and raids: there the Friendly Plates in Dungeons and Raids
-- choices switch the same settings, and the two put back each other's
-- saved values (tested: a delve companion's plate stayed up).
local function MarkersHiddenOverFriends()
	if not platesActive or placeSuffix == "Instances" then
		return false
	end
	if UnitRowWanted("PartMarker") then
		return false
	end
	return ns.InGroup() or markerWatcher.solo or false
end

-- The always-shown target's plate fades in (at the UI's fade-in time) rather
-- than popping up, and
-- once it's no longer your target fades back down to where the other plates
-- are. Tracked by plate frame: `targetFade` is the current target's,
-- `leavingTargets` maps old targets' plates to their fade on the way out.
local targetFade = { plate = nil, level = 0, enemy = false }
local leavingTargets = {}
-- The other way round: in CineMode, your target's plate goes while its
-- target row doesn't keep it up here, whatever its kind's row says (the
-- Target Nameplate grid overrides the Nameplates grid both ways). It fades
-- down, and back up if the row lets it again; a plate that stops being your
-- target is its kind's again at once. level: 1 untouched, 0 hidden.
local targetHidden = { plate = nil, level = 1 }

local function TargetHeldDown()
	if not (platesActive and ns.HasTarget()) then
		return false
	end
	local row = TargetRow("target")
	return row ~= nil and not UnitRowWanted(row)
end

local function TargetFadeTime(fadeIn)
	return fadeIn and ns.FadeInTime() or ns.FadeOutTime()
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
		targetFade.enemy = ns.IsEnemyUnit("target") or false
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
	local targetPlate = ns.HasTarget() and C_NamePlate and C_NamePlate.GetNamePlateForUnit
		and C_NamePlate.GetNamePlateForUnit("target") or nil
	local heldPlate = targetPlate and TargetHeldDown() and targetPlate or nil
	if targetHidden.plate and targetHidden.plate ~= targetPlate then
		-- (No longer your target: its kind's again at once.)
		targetHidden.plate, targetHidden.level = nil, 1
		moving = true
	end
	if heldPlate and not targetHidden.plate then
		targetHidden.plate, targetHidden.level = heldPlate, 1
	end
	if targetHidden.plate then
		local goal = heldPlate == targetHidden.plate and 0 or 1
		if targetHidden.level ~= goal then
			targetHidden.level = ns.Approach(targetHidden.level, goal, elapsed, TargetFadeTime(goal == 1))
			moving = true
		elseif goal == 1 then
			targetHidden.plate = nil
		end
	end
	return moving
end

-- A plate just given to a new unit: whatever fade it had was its last unit's.
local function ForgetTargetFade(plate)
	leavingTargets[plate] = nil
	if targetFade.plate == plate then
		targetFade.plate, targetFade.level = nil, 0
	end
	if targetHidden.plate == plate then
		targetHidden.plate, targetHidden.level = nil, 1
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
ns.OnCalmEnd(function(cut)
	fightEndedAt = math.min(fightEndedAt, cut)
	combatMusic.lastFightAt = math.min(combatMusic.lastFightAt, cut)
end)

local function FightLingering()
	return not InCombatLockdown() and GetTime() - fightEndedAt < (ns.db.calmTime or 0)
end
ns.FightLingering = FightLingering -- (names linger too)

local function AnyFightKinds()
	for _, kind in ipairs(ns.PLATE_KINDS) do
		if ShownInFights(kind) then
			return true
		end
	end
	return false
end

-- Whether some plates need an alpha other than the shared fade level.
local function PlatesFiltered()
	if next(combatCap) or targetHidden.plate then
		return true
	end
	if platesActive and InCombatLockdown() then
		for _, kind in ipairs(ns.PLATE_KINDS) do
			if not ShownInFights(kind) then
				return true
			end
		end
	end
	return ns.plates.level < 1
		and (AnyPlatesKeptCinematic() or TargetKeptUp() or next(leavingTargets) ~= nil or NamesOnPlates())
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
		local member = UnitRowAlpha(unit, kind)
		-- Plates can't be switched off in fights, only made invisible.
		if platesActive and InCombatLockdown() and not ShownInFights(kind) then
			return member
		end
		return math.max(math.min(math.max(ns.plates.level, keptLevel[kind] or 0), combatCap[kind] or 1), member)
	end
	return ns.plates.level
end

-- WoW Forever's personal resource bars are your own nameplate: it follows
-- the Standard Frames page's row (its stand-in's fade, from Frames), not the
-- Nameplates page's rows. (Retail's are a frame of their own.)
local personalAlpha = 1
local personalHeld = false -- (faded last time: put back to full once)

local function PersonalPlate()
	return C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("player")
end

function ns.SetPersonalPlateAlpha(alpha)
	personalAlpha = alpha
	local plate = PersonalPlate()
	if plate and (alpha < 1 or personalHeld) then
		ns.SetPlateAlpha(plate, alpha)
	end
	personalHeld = alpha < 1
end

local function PlateAlpha(unit, plate)
	if plate and plate == PersonalPlate() then
		return personalAlpha
	end
	if ns.SoftTargetCorpse(unit) then
		return 0 -- (a plate only Quest Vision's soft targeting gave it: see QuestGlow)
	end
	local alpha = KindAlpha(unit)
	if plate == targetFade.plate and not (unit and IsTarget(unit) and AlwaysShownTarget(unit)) then
		return alpha -- a frame before the target fade catches up with a new target
	end
	alpha = math.max(alpha, TargetPlateLevel(plate), duels.Level(plate))
	if plate and plate == targetHidden.plate then
		alpha = math.min(alpha, targetHidden.level)
	end
	return alpha
end

-- The plate's alpha with its name kept (see nameLevel), and how much of that
-- the rest of the plate gets (body) and the name (name), for PlateParts.
local function PlateAlphas(unit, plate)
	local body = PlateAlpha(unit, plate)
	local name = 0
	if platesForced and unit and plate ~= PersonalPlate() then
		local kind = PlateKind(unit)
		name = kind and nameLevel[KIND_NAME_GROUP[kind]] or 0
		if (nameLevel.Target or 0) > name and IsTarget(unit) then
			name = nameLevel.Target
		end
	end
	local alpha = math.max(body, name)
	if alpha <= 0 then
		return 0, 1, 0
	end
	return alpha, body / alpha, name / alpha
end

local function SetPlateAlphas(plate, alpha, body, name)
	ns.SetPlateBody(plate, body, name)
	ns.SetPlateAlpha(plate, alpha, alpha * body)
end

-- Leaves a plate's alpha to the game (or its nameplate addon) again.
local function LetGoOfPlate(plate)
	if plate.UnitFrame then
		plate.UnitFrame.cinematicAlpha = nil
		if plate.UnitFrame.cinematicMarker then
			plate.UnitFrame.cinematicMarker:Hide() -- (its last unit's)
		end
	end
	if ns.addonPlateAlpha and not (plate.IsForbidden and plate:IsForbidden()) then
		ns.addonPlateAlpha(plate, nil)
	end
end

function ns.RefreshPlate(plate, unit)
	if not plate then
		return
	end
	if not ns.db.handlePlates then
		LetGoOfPlate(plate) -- (left to the game: Nameplates page's switch off)
		return
	end
	unit = unit or plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
	ForgetTargetFade(plate) -- only called for a plate given a new unit
	duels.Forget(plate)
	duels.Attach(plate, unit)
	local alpha, body, name = PlateAlphas(unit, plate)
	if alpha < 1 or body < 1 or PlatesFiltered() then
		SetPlateAlphas(plate, alpha, body, name)
	else
		ns.SetPlateBody(plate, 1, 0)
		LetGoOfPlate(plate) -- a reused plate: let go of its last unit's alpha
	end
end

local function RefreshAllPlates()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		SetPlateAlphas(plate, PlateAlphas(unit, plate))
	end
end
RefreshAllPlates = ns.Profiled("RefreshAllPlates", RefreshAllPlates)

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
	-- Name-only friendly players have no health bar, target or not.
	if GetCVar("nameplateShowOnlyNameForFriendlyPlayerUnits") == "1" then
		ns.Print("friendly players' plates are names only (the game's setting, not ours): no health bar, even on your target"
			.. (ns.AddOnLoaded("EllesmereUINameplates")
				and " - EllesmereUI sets it: untick its Make Friendly Nameplates Name Only (Nameplates, General)" or ""))
	end
	ns.Print(("fade level=%.2f, switched off=%s, filtered=%s, kept in cinematic=%s, cinematic=%s, combat=%s"):format(
		ns.plates.level, tostring(ns.plates.off), tostring(PlatesFiltered()),
		tostring(AnyPlatesKeptCinematic()), tostring(ns.lastCinematic), tostring(InCombatLockdown())))
	-- Plates kept switched on, names shown on plates, and sides made unclickable.
	local onPlates, unclickable = {}, {}
	for key, level in pairs(nameLevel) do
		if level > 0 then
			onPlates[#onPlates + 1] = ("%s %.2f"):format(key, level)
		end
	end
	for side in pairs(ns.db.savedPlateClicks or {}) do
		unclickable[#unclickable + 1] = side
	end
	ns.Print(("plates kept on=%s (settings %s), names on plates: %s, unclickable: %s"):format(tostring(platesForced),
		FORCED_PLATE_CVARS.active and "held" or "not held", #onPlates > 0 and table.concat(onPlates, ", ") or "none",
		#unclickable > 0 and table.concat(unclickable, ", ") or "none"))
	local keptHere = {}
	for _, kind in ipairs(ns.PLATE_KINDS) do
		if KeptHere(kind) then
			keptHere[#keptHere + 1] = kind
		end
	end
	ns.Print(("pvp fights=%s"):format(tostring(InPvPFight())))
	ns.Print(("place=%s, kept up here=%s"):format(placeSuffix or "open world",
		#keptHere > 0 and table.concat(keptHere, ", ") or "none"))
	local function describe(unit)
		local name = UnitName(unit)
		local isPlayer, faction = UnitIsPlayer(unit), UnitFactionGroup(unit)
		local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
		-- (A raid marker: its index, and our kept one over the faded plate.)
		-- (And the game's: shown or not, and its textures, for a client that names it otherwise.)
		local okMark, mark = pcall(GetRaidTargetIndex, unit)
		mark = not okMark and "error" or (Known(mark) and tostring(mark) or "secret")
		local ours = plate and plate.UnitFrame and plate.UnitFrame.cinematicMarker
		local game = plate and plate.UnitFrame and plate.UnitFrame.RaidTargetFrame
		local gameText = "none"
		if type(game) == "table" and game.GetRegions then
			local ok, text = pcall(function()
				local list = {}
				for _, region in ipairs({ game:GetRegions() }) do
					-- (And its part of the sheet: whether a hidden one still holds the marker.)
					local coords = {}
					if region.GetTexCoord then
						for _, value in ipairs({ region:GetTexCoord() }) do
							coords[#coords + 1] = (issecretvalue and issecretvalue(value)) and "secret"
								or ("%.3f"):format(value)
						end
					end
					list[#list + 1] = tostring(region:GetTexture()) .. (ns.Flag(region:IsShown()) and "" or "(hidden)")
						.. (#coords > 0 and ("[" .. table.concat(coords, ",") .. "]") or "")
				end
				return (ns.Flag(game:IsShown()) and "shown" or "hidden") .. ("@%.2f "):format(game:GetAlpha())
					.. table.concat(list, "+")
			end)
			gameText = ok and text or "?"
		end
		local body = plate and plate.UnitFrame and plate.UnitFrame.cinematicBodyAlpha
		local marker = (" marker=%s game=%s kept=%s%s"):format(mark, gameText,
			ours and (ours:IsShown() and ("%.2f"):format(ours:GetAlpha()) or "hidden") or "none",
			body and (", name only (rest at %.2f)"):format(body) or "")
		return ("%s: kind=%s, alpha=%.2f, can attack=%s, player=%s, faction=%s%s"):format(
			Known(name) and tostring(name) or "?", tostring(PlateKind(unit)), PlateAlpha(unit, plate),
			tostring(UnitCanAttack("player", unit)),
			Known(isPlayer) and tostring(isPlayer) or "secret", Known(faction) and tostring(faction) or "secret", marker)
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
	-- (Marked ones and ones up for their name alone first: the list is cut short.)
	local function Notable(plate)
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		local ok, mark = pcall(GetRaidTargetIndex, unit)
		return (ok and mark ~= nil) or (plate.UnitFrame and plate.UnitFrame.cinematicBodyAlpha ~= nil) or false
	end
	local sorted = {}
	for _, plate in ipairs(plates) do
		if Notable(plate) then
			table.insert(sorted, 1, plate)
		else
			sorted[#sorted + 1] = plate
		end
	end
	plates = sorted
	for i, plate in ipairs(plates) do
		if i > 8 then break end
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		local shown = plate.UnitFrame and ("%.2f"):format(plate.UnitFrame:GetAlpha()) or "-"
		ns.Print(("  %s (unit %s, frame alpha %s)"):format(unit and describe(unit) or "?", tostring(unit), shown))
	end
	if UnitExists("target") then
		local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
		ns.Print("target " .. describe("target") .. (plate and ", has a plate" or ", NO plate"))
		local okFriend, friend = pcall(UnitIsFriend, "player", "target")
		local okReaction, reaction = pcall(UnitReaction, "player", "target")
		ns.Print(("  enemy=%s, friend=%s, reaction=%s, kept up=%s"):format(
			tostring(ns.IsEnemyUnit("target")), okFriend and tostring(friend) or "?",
			okReaction and tostring(reaction) or "?", tostring(TargetKeptUp())))
		local frame = plate and plate.UnitFrame
		if frame then
			ns.Print(("  plate shown=%s alpha=%.2f, frame shown=%s alpha=%.2f, health bar shown=%s"):format(
				tostring(plate:IsShown()), plate:GetAlpha(), tostring(frame:IsShown()), frame:GetAlpha(),
				tostring(frame.healthBar and frame.healthBar:IsShown())))
			-- The health bar's value and fill, for a bar that looks empty.
			local bar = frame.healthBar
			if type(bar) == "table" and bar.GetValue then
				local function Show(fn)
					local ok, a, b = pcall(fn)
					if not ok then
						return "?"
					end
					local shown = {}
					for _, value in ipairs({ a, b }) do
						if issecretvalue and issecretvalue(value) then
							shown[#shown + 1] = "secret"
						else
							shown[#shown + 1] = type(value) == "number" and ("%.2f"):format(value) or tostring(value)
						end
					end
					return table.concat(shown, "/")
				end
				local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
				local container = frame.HealthBarsContainer
				ns.Print(("  health value=%s range=%s bar alpha=%s visible=%s size=%s | fill=%s shown=%s alpha=%s"
					.. " size=%s color=%s | container shown=%s alpha=%s | UnitHealth=%s"):format(
					Show(function() return bar:GetValue() end), Show(function() return bar:GetMinMaxValues() end),
					Show(function() return bar:GetAlpha() end), Show(function() return bar:IsVisible() end),
					Show(function() return bar:GetSize() end), Show(function() return fill:GetTexture() end),
					Show(function() return fill:IsShown() end), Show(function() return fill:GetAlpha() end),
					Show(function() return fill:GetSize() end),
					Show(function() local r, g = fill:GetVertexColor() return r, g end),
					Show(function() return container:IsShown() end), Show(function() return container:GetAlpha() end),
					Show(function() return UnitHealth("target"), UnitHealthMax("target") end)))
			end
			local parts, fields, healthFields = ns.DescribePlateParts(frame)
			ns.Print("  parts: " .. parts)
			ns.Print("  fields: " .. fields)
			ns.Print("  health bar fields: " .. healthFields)
		end
	end
	-- Your personal resource bars' power half (Frames), and on Forever your
	-- own plate's fields, for finding power bars a client names otherwise.
	if ns.DescribePersonalPower then
		ns.Print("personal resource bars: " .. ns.DescribePersonalPower())
		local own = PersonalPlate()
		if own and own.UnitFrame and not (own.IsForbidden and own:IsForbidden()) then
			local _, fields = ns.DescribePlateParts(own.UnitFrame)
			ns.Print("  your plate's fields: " .. fields)
		end
		local display = _G.PersonalResourceDisplayFrame
		if display and not (display.IsForbidden and display:IsForbidden()) then
			local _, fields = ns.DescribePlateParts(display)
			ns.Print("  the frame's fields: " .. fields)
		end
	end
	-- Every nameplate setting this client has, for comparing.
	local names = {}
	for _, name in ipairs({ "nameplateShowFriends", "nameplateShowFriendlyPlayers", "nameplateShowEnemies",
		"nameplateShowEnemyPlayers", "nameplateShowOnlyNames", "nameplateShowAll" }) do
		if GetCVar(name) ~= nil then
			names[#names + 1] = cvar(name)
		end
	end
	ns.Print(table.concat(names, ", "))
end

-- For /cine debug duels: whether duels are watched (or why not), and each
-- friendly player in combat with a plate, against the others.
function ns.PrintDuelsDebug()
	local why = duels.NotWatchingWhy()
	ns.Print(("duel plates: on=%s, watching=%s%s, for markers=%s, friendly plates=%s/%s, click-through=%s"):format(
		tostring(duels.on), tostring(duels.watching), why and (" (" .. why .. ")") or "",
		tostring(MarkersHiddenOverFriends()),
		tostring(GetCVar("nameplateShowFriends")), tostring(GetCVar("nameplateShowFriendlyPlayers")),
		tostring(C_NamePlate and C_NamePlate.GetNamePlateFriendlyClickThrough
			and C_NamePlate.GetNamePlateFriendlyClickThrough())))
	local found, fighters = duels.Scan()
	ns.Print(("%d friendly players in combat with a plate"):format(#fighters))
	for i, a in ipairs(fighters) do
		if i > 10 then break end
		local canAttack = {}
		for _, b in ipairs(fighters) do
			if b ~= a then
				local ok, value = pcall(UnitCanAttack, a.unit, b.unit)
				canAttack[#canAttack + 1] = ("%s=%s"):format(Known(b.name) and tostring(b.name) or "?",
					ok and (Known(value) and tostring(value) or "secret") or "error")
			end
		end
		local info = found[a.plate]
		ns.Print(("  %s (%s)%s, can attack: %s, shown %.2f"):format(Known(a.name) and tostring(a.name) or "?",
			a.unit, info and (" DUELING (colour " .. info.pair.color .. ")") or "",
			#canAttack > 0 and table.concat(canAttack, ", ") or "-", duels.Level(a.plate)))
	end
	ns.Print(("duel lines: %s / %s (the game's own; nil: English used)"):format(tostring(DUEL_WINNER),
		tostring(DUEL_FLED)))
	ns.Print("last system line: " .. tostring(duels.lastSystem))
	local result = duels.lastResult
	ns.Print(result and ("last result caught %.0fs ago from %s: %s"):format(GetTime() - result.at, result.source,
		result.text) or "no duel result caught yet")
	for _, pair in pairs(duels.pairs) do
		if pair.endedAt then
			ns.Print(("  %s %s %s %.0fs ago"):format(tostring(pair.winner), pair.fled and "saw off" or "beat",
				tostring(pair.loser), GetTime() - pair.endedAt))
		end
	end
end

function ns.ShowPlatesNow()
	if ns.plates.off and not InCombatLockdown() then
		ns.ApplyCVarSet(PLATE_CVARS, false)
		ns.plates.off = false
		ns.plates.level = 0
		-- (Settings it shared with the locked friendly plates' switches went
		-- back with it: those go on again afresh.)
		for _, set in pairs(ns.LOCKED_PLATE_SETS or {}) do
			if set.active then
				ns.ApplyCVarSet(set, false)
				ns.ApplyCVarSet(set, true)
			end
		end
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
	NeutralNPCs = { "nameplateShowEnemies" },
	EnemyMinions = {
		"nameplateShowEnemyMinions", "nameplateShowEnemyPets", "nameplateShowEnemyGuardians",
		"nameplateShowEnemyTotems",
	},
	EnemyMinor = { "nameplateShowEnemyMinus" },
	NeutralMinor = { "nameplateShowEnemyMinus" },
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
local PLATE_ROW_PARENT = { EnemyMinions = "Enemies", EnemyMinor = "EnemyNPCs", NeutralMinor = "NeutralNPCs",
	FriendlyMinions = "Friends" }
-- The unit rows go by their units' kinds (your target's could be any: none).
local UNIT_ROW_KIND = { MyPet = "FriendlyMinions", GroupMembers = "Friends", GroupMinions = "FriendlyMinions" }
local pendingPlateRows = {}

-- Whether this client has any of a row's nameplate settings.
function ns.HasPlateSettings(kind)
	if kind:find("Target$") then
		return true
	end
	for _, cvar in ipairs(PLATE_KIND_CVARS[UNIT_ROW_KIND[kind] or kind]) do
		if GetCVar(cvar) ~= nil then
			return true
		end
	end
	return false
end

function ns.EnablePlateRow(kind)
	kind = UNIT_ROW_KIND[kind] or kind
	if not PLATE_KIND_CVARS[kind] then
		return
	end
	if InCombatLockdown() then
		pendingPlateRows[kind] = true
		return
	end
	pendingPlateRows[kind] = nil
	for _, row in ipairs({ kind, PLATE_ROW_PARENT[kind] }) do
		for _, cvar in ipairs(PLATE_KIND_CVARS[row]) do
			SetOwnValue(cvar, "1")
		end
	end
end

-- At login, every row with anything ticked has its game settings switched on
-- (in case they were turned off in the game's options since). Rows with
-- nothing ticked are left alone.
function ns.EnsurePlateRows()
	if not ns.db.handlePlates then
		return -- (the game's own options decide: Nameplates page's switch off)
	end
	local rows = {}
	for _, kind in ipairs(ns.PLATE_KINDS) do rows[#rows + 1] = kind end
	for _, row in ipairs(ns.PLATE_UNIT_ROWS) do rows[#rows + 1] = row end
	for _, kind in ipairs(rows) do
		if ns.RuleTest(PLATE_RULE_KEY[kind]) then
			ns.EnablePlateRow(kind) -- (a rule may show it)
		end
		for _, prefix in ipairs({ "plateAlways", "plateGroup", "plateCombat", "plateCombatPvP",
			"plateCinematic", "plateInInstances", "plateInPvP", "plateInBGs" }) do
			if ns.db[prefix .. kind] then
				ns.EnablePlateRow(kind)
				break
			end
		end
	end
	-- (And friendly kinds shown in dungeons and raids, by their own setting.)
	for _, kind in ipairs(ns.PLATE_INSTANCE_KINDS) do
		if ns.db["plateInstance" .. kind] ~= "hide" then
			ns.EnablePlateRow(kind)
		end
	end
end

-- In dungeons and raids the game locks friendly plates away from addons, so
-- they can't be faded. There, in cinematic mode, each friendly kind is on or
-- off as the Nameplates page's "Friendly plates in dungeons and raids" says
-- (plateInstance<kind>: "hide", "show", or "target": on while you have one of
-- that kind targeted). Off means its game settings switched off (put back on
-- the way out). Friendly players' setting covers their minions too, so it
-- only goes off with the minions off as well. Not in fights: the game won't
-- change plate settings then, so they stay as the fight found them.
local LOCKED_PLATE_KINDS = ns.PLATE_INSTANCE_KINDS
local LOCKED_PLATE_SETS = {}
for _, kind in ipairs(LOCKED_PLATE_KINDS) do
	local values = {}
	for _, cvar in ipairs(PLATE_KIND_CVARS[kind]) do
		values[cvar] = "0"
	end
	LOCKED_PLATE_SETS[kind] = { secure = true, playerWins = true, values = values }
end
ns.LOCKED_PLATE_SETS = LOCKED_PLATE_SETS -- (ns.ShowPlatesNow, above)

-- Which kind your target is, for the "target" choice.
local TARGET_ROW_KIND = { MyFriendlyPlayerTarget = "Friends", MyFriendlyNPCTarget = "FriendlyNPCs" }
local lockedHidden = {} -- (kept: made each tick, it was garbage)

local function UpdateLockedPlates()
	local locked = platesActive and placeSuffix == "Instances"
	local targetKind = locked and Ask(UnitExists, "target") and TARGET_ROW_KIND[TargetRow("target") or ""]
	local hidden = lockedHidden
	for _, kind in ipairs(LOCKED_PLATE_KINDS) do
		local mode = ns.db["plateInstance" .. kind]
		hidden[kind] = locked and (mode == "hide" or (mode == "target" and targetKind ~= kind)) or false
	end
	hidden.Friends = hidden.Friends and hidden.FriendlyMinions
	local changed = false
	for _, kind in ipairs(LOCKED_PLATE_KINDS) do
		local set = LOCKED_PLATE_SETS[kind]
		local was = set.active
		ns.ApplyCVarSet(set, hidden[kind] or false)
		changed = changed or (set.active ~= was)
	end
	-- These share settings with the switch that turns every plate off, and
	-- the first to let go puts a shared setting back from under the other:
	-- with plates switched off, that switch goes on again afresh.
	if changed and PLATE_CVARS.active and not InCombatLockdown() then
		ns.ApplyCVarSet(PLATE_CVARS, false)
		ns.ApplyCVarSet(PLATE_CVARS, true)
	end
end

-- In CineMode away from dungeons and raids (ns.PlatesForcedHere) every
-- nameplate is kept switched on, plates and their names only made visible or
-- not by their fades: fades can change in fights, plate settings can't, and a
-- unit whose plate is switched off shows the game's own name over its head
-- (or none). Plate names on: retail's plates otherwise follow the game's name
-- settings, off for rows whose names are hidden. The player's own settings come back after.
FORCED_PLATE_CVARS = { secure = true, playerWins = true, values = {
	nameplateShowAll = "1", nameplateForceShowUnitName = "1", nameplateShowOnlyNameForFriendlyPlayerUnits = "0",
} }
for _, cvars in pairs(PLATE_KIND_CVARS) do
	for _, cvar in ipairs(cvars) do
		FORCED_PLATE_CVARS.values[cvar] = "1"
	end
end

-- Invisible plates still take clicks, so while every plate of a side
-- (friendly or enemy) is faded out, that side's plates are made unclickable
-- (their click area shrunk to nothing): clicks reach the world behind them.
-- Not in fights (the game won't allow it): every plate takes clicks again as
-- one starts. The game's own areas are kept in the saved variables and put
-- back. Clients without the setting are left alone.
local PlateManager = C_NamePlateManager
local PLATE_SIDES = {
	Friendly = { kinds = { Friends = true, FriendlyMinions = true, FriendlyNPCs = true } },
	Enemy = { kinds = {} },
}
for _, kind in ipairs(ns.PLATE_KINDS) do
	if not PLATE_SIDES.Friendly.kinds[kind] then
		PLATE_SIDES.Enemy.kinds[kind] = true
	end
end

local function SetPlateClicks(side, on)
	local plateType = Enum and Enum.NamePlateType and Enum.NamePlateType[side]
	if not (plateType and PlateManager and PlateManager.SetNamePlateHitTestInsets
		and PlateManager.GetNamePlateHitTestInsets) or InCombatLockdown() then
		return
	end
	ns.db.savedPlateClicks = ns.db.savedPlateClicks or {}
	local saved = ns.db.savedPlateClicks[side]
	if on then
		if saved then
			pcall(PlateManager.SetNamePlateHitTestInsets, plateType, unpack(saved))
			ns.db.savedPlateClicks[side] = nil
		end
	elseif not saved then
		local ok, left, right, top, bottom = pcall(PlateManager.GetNamePlateHitTestInsets, plateType)
		if ok and type(left) == "number" then
			ns.db.savedPlateClicks[side] = { left, right, top, bottom }
			pcall(PlateManager.SetNamePlateHitTestInsets, plateType, 1000, 1000, 1000, 1000)
		end
	end
end

-- Whether any plate of a side may be showing.
local function SideShown(side)
	if ns.plates.level > 0 or TargetKeptUp() or next(leavingTargets) ~= nil or (nameLevel.Target or 0) > 0 then
		return true
	end
	for kind in pairs(side.kinds) do
		if (keptLevel[kind] or 0) > 0 or (combatCap[kind] or 0) > 0 or (nameLevel[KIND_NAME_GROUP[kind]] or 0) > 0 then
			return true
		end
	end
	if unitRowLevel.QuestMobs > 0 then
		return true -- (quest mobs are on either side)
	end
	if side == PLATE_SIDES.Friendly then
		for _, level in pairs(unitRowLevel) do
			if level > 0 then
				return true
			end
		end
	end
	return false
end

local function UpdatePlateClicks()
	for name, side in pairs(PLATE_SIDES) do
		SetPlateClicks(name, not platesForced or SideShown(side))
	end
end

-- As a fight starts (just before lockdown): every plate takes clicks.
local clickWatcher = CreateFrame("Frame")
clickWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
clickWatcher:SetScript("OnEvent", function()
	if ns.db then
		for name in pairs(PLATE_SIDES) do
			SetPlateClicks(name, true)
		end
	end
end)

local platesWereFiltered = false

-- While plates are filtered (each at its own alpha) and none of the fades is
-- moving, they're refreshed only when what decides their alphas changes: a
-- fight, a group, the place or PvP flag (filteredKey), a unit changing sides
-- or joining your group (the events below), and every FILTERED_REFRESH
-- seconds for anything else (a setting changed, say). Every tick was a lot
-- of work with a city's worth of plates.
local FILTERED_REFRESH = 0.5
local filteredKey, filteredPlace, filteredRefreshAt = nil, nil, 0
local platesDirty = false
local plateChangeWatcher = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_FACTION", "UNIT_FLAGS", "UNIT_PET", "GROUP_ROSTER_UPDATE" }) do
	pcall(plateChangeWatcher.RegisterEvent, plateChangeWatcher, event)
end
plateChangeWatcher:SetScript("OnEvent", function()
	platesDirty = true
end)

local function FilteredInputsChanged(now)
	local key = (platesActive and 1 or 0) + (InCombatLockdown() and 2 or 0) + (ns.InGroup() and 4 or 0)
		+ (InPvPFight() and 8 or 0)
	if platesDirty or key ~= filteredKey or placeSuffix ~= filteredPlace or now >= filteredRefreshAt then
		platesDirty, filteredKey, filteredPlace = false, key, placeSuffix
		filteredRefreshAt = now + FILTERED_REFRESH
		return true
	end
	return false
end

-- The Nameplates page's master switch off (handlePlates): every plate back to
-- full, the game's plate settings put back, then nothing more until it's on
-- again. Tried each tick until done (settings can't change in a fight).
local platesReleased = false
local function ReleasePlates()
	platesActive = false
	platesForced = false
	ns.ApplyCVarSet(FORCED_PLATE_CVARS, false)
	UpdatePlateClicks()
	duels.Sync(false)
	duels.Clear()
	UpdateLockedPlates()
	ns.ShowPlatesNow()
	ns.plates.level = 1
	for kind in pairs(combatCap) do
		combatCap[kind] = nil
	end
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			SetPlateAlphas(plate, 1, 1, 0)
		end
	end
	platesWereFiltered = false
	local locked = false
	for _, set in pairs(LOCKED_PLATE_SETS) do
		locked = locked or set.active or false
	end
	platesReleased = not ns.plates.off and not locked and not duels.on and not FORCED_PLATE_CVARS.active
		and not (ns.db.savedPlateClicks and next(ns.db.savedPlateClicks))
end

function ns.UpdatePlates(cinematic, elapsed)
	if not ns.db.handlePlates then
		if not platesReleased then
			ReleasePlates()
		end
		ns.UpdatePlateParts(false, elapsed)
		return
	end
	platesReleased = false
	platesActive = cinematic and true or false
	placeSuffix = ns.PlateSuffix()
	platesForced = ns.PlatesForcedHere(cinematic)
	-- (Let go before the other plate switches take hold, and taken up after
	-- they let go: they share settings, and each puts back what it saved.)
	if not platesForced then
		ns.ApplyCVarSet(FORCED_PLATE_CVARS, false)
	end
	duels.Sync(duels.NotWatchingWhy() == nil or MarkersHiddenOverFriends())
	UpdateLockedPlates()
	if platesForced then
		ns.ShowPlatesNow()
		ns.ApplyCVarSet(FORCED_PLATE_CVARS, true)
	end
	-- Plates show for every fight (bar kinds cinematic mode hides in fights)
	-- and hide again afterwards. Just after a fight, kinds ticked for fights
	-- stay up through their linger; the rest go as cinematic mode comes back.
	local inCombat = InCombatLockdown()
	local lingering = FightLingering()
	local holding = platesActive and lingering and AnyFightKinds()
	local hide = platesActive and not inCombat and not holding
	local keep = platesForced or AnyPlatesKeptCinematic() or TargetKeptUp() or next(leavingTargets) ~= nil
		or MarkersKeptUp()
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
	changed = duels.Update(elapsed) or changed
	changed = ns.plates.level ~= target or changed
	if changed then
		local duration = target > ns.plates.level and ns.FadeInTime() or ns.FadeOutTime()
		ns.plates.level = ns.Approach(ns.plates.level, target, elapsed, duration)
	end
	-- The unit rows' plates (your pet's, group members') fade up and down likewise.
	for row, level in pairs(unitRowLevel) do
		local rowTarget = UnitRowActive(row) and 1 or 0
		if level ~= rowTarget then
			unitRowLevel[row] = ns.Approach(level, rowTarget, elapsed,
				rowTarget > level and ns.FadeInTime() or ns.FadeOutTime())
			changed = true
		end
	end
	-- Kinds hidden in cinematic fights: held at 0 in combat, then let back up
	-- at the fade-in speed, but only while plates are on their way in. Heading
	-- out (cinematic again), they stay hidden until the fade has caught up.
	-- Held up after a fight, the kinds not ticked for fights (bar those kept
	-- up where you are) fade down the same way.
	for _, kind in ipairs(ns.PLATE_KINDS) do
		local combat = ShownInFights(kind)
		local cinematicKept = KeptHere(kind)
		local keptTarget = cinematicKept and 1 or 0
		if keptLevel[kind] == nil then
			keptLevel[kind] = keptTarget -- logging in: no fade
		elseif keptLevel[kind] ~= keptTarget then
			keptLevel[kind] = ns.Approach(keptLevel[kind], keptTarget, elapsed,
				keptTarget > keptLevel[kind] and ns.FadeInTime() or ns.FadeOutTime())
			changed = true
		end
		if inCombat and platesActive and not combat then
			combatCap[kind] = 0
		elseif holding and not combat and not cinematicKept then
			local from = combatCap[kind] or 1
			if from > 0 then
				changed = true
			end
			combatCap[kind] = ns.Approach(from, 0, elapsed, ns.FadeOutTime())
		elseif combatCap[kind] then
			if hide and not cinematicKept then
				if ns.plates.level <= combatCap[kind] then
					combatCap[kind] = nil -- the fade is below the limit now: it takes over
				end
			else
				combatCap[kind] = ns.Approach(combatCap[kind], 1, elapsed, ns.FadeInTime())
				if combatCap[kind] >= 1 then
					combatCap[kind] = nil
				end
			end
			changed = true
		end
	end
	-- Names kept on plates fade up and down likewise.
	for _, group in ipairs(ns.NAME_GROUPS) do
		if group.plate then
			local nameTarget = platesForced and NameKeptHere(group.key, inCombat) and 1 or 0
			local level = nameLevel[group.key]
			if level == nil then
				nameLevel[group.key] = nameTarget
			elseif level ~= nameTarget then
				nameLevel[group.key] = ns.Approach(level, nameTarget, elapsed,
					nameTarget > level and ns.FadeInTime() or ns.FadeOutTime())
				changed = true
			end
		end
	end
	-- One more pass after filtering stops, to put every plate back. (Filtered
	-- with nothing moving: see FilteredInputsChanged.)
	local filtered = PlatesFiltered()
	if changed or filtered ~= platesWereFiltered or (filtered and FilteredInputsChanged(GetTime())) then
		RefreshAllPlates()
	end
	platesWereFiltered = filtered
	ns.UpdatePlateParts(platesActive, elapsed)
	UpdatePlateClicks()

	if hide and not keep and ns.plates.level == 0 and not ns.plates.off and not InCombatLockdown() then
		ns.ApplyCVarSet(PLATE_CVARS, true)
		ns.plates.off = true
	end
end

-- World tooltips (units and objects under the cursor) use the default anchor,
-- owned by UIParent. They and unit frames' hide in CineMode as the Tooltips
-- page says; other UI elements' only in combat (Hide in combat: Everything
-- else), so hovering a faded button still explains it. Hidden outright:
-- fading them fought Blizzard's own tooltip alpha and flickered.
ns.lastCinematic = false

-- Minimap blips (tracked herbs, party members) use a world-style tooltip; with
-- the cursor on the minimap it's always left showing.
local function OverMinimap()
	return Minimap ~= nil and ns.Flag(Minimap:IsVisible()) and ns.Flag(Minimap:IsMouseOver())
end

local function WorldOwned()
	local owner = GameTooltip:GetOwner()
	return owner == nil or owner == UIParent or owner == WorldFrame
end

-- Tooltips hide in the camera modes ticked (tooltipHideIn*).
local TOOLTIP_HIDE_IN = {
	flight = "tooltipHideInFlight", idle = "tooltipHideInIdle", cozy = "tooltipHideInCozy",
	tele = "tooltipHideInTele", walk = "tooltipHideInWalk", run = "tooltipHideInRun",
	vista = "tooltipHideInVista", fish = "tooltipHideInFish", death = "tooltipHideInDeath",
	quest = "tooltipHideInQuest",
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
-- The Tooltips page's master switch (handleTooltips, off to start with): off,
-- every tooltip shows as the game has it.
local function Handling()
	return ns.db.enabled and ns.db.handleTooltips and true or false
end

-- Holding the Show hidden tooltips keybind shows tooltips the page would
-- hide, in combat and in CineMode alike.
local bindHeld = false

-- The keybind (Bindings.xml, runOnUp): held from its press to its release.
function Cinematic_ShowTooltips(keystate)
	bindHeld = keystate == "down"
end

-- The Toggle tooltip hiding keybind: the page's master switch.
function Cinematic_ToggleTooltips()
	if not ns.db then
		return
	end
	ns.db.handleTooltips = not ns.db.handleTooltips
	ns.Print(ns.db.handleTooltips and L["tooltip hiding on"] or L["tooltip hiding off"])
	if ns.RefreshOptions then
		ns.RefreshOptions()
	end
end

local function ShowKeyDown()
	return bindHeld
end

local function InCombat()
	return InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
end

-- The owner SetUnit was last called for: a unit frame's tooltip appears
-- (OnShow) before the mouseover and GetUnit catch up, so it's told apart by
-- that until it hides or another owner takes it over.
local unitTooltipOwner

local function TooltipHasUnit(tooltip)
	if unitTooltipOwner ~= nil and unitTooltipOwner == tooltip:GetOwner() then
		return true
	end
	if ns.Flag(UnitExists("mouseover")) then
		return true
	end
	local ok, unit = pcall(function()
		local _, unit = tooltip:GetUnit()
		return unit
	end)
	return ok and (type(unit) == "string" or (issecretvalue and issecretvalue(unit))) or false
end

local function TooltipName()
	local ok, text = pcall(function() return GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText() end)
	return ok and text or nil
end

-- A name that can't be compared (secret) counts as the same thing.
local function SameName(a, b)
	local ok, same = pcall(function() return a == b end)
	return not ok or same
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

-- Hide out of combat: db key -> test. One that's more than one kind (a quest
-- mob is an enemy too) hides only if every kind it is is ticked.
local HIDE_KINDS = {
	{ key = "tooltipHideQuest", test = ShowsQuestObjective, why = "quest objective" },
	{ key = "tooltipHideGather", test = ShowsGatheringNode, why = "gatherable" },
	{ key = "tooltipHideEnemy", test = ShowsEnemy, why = "enemy" },
	{ key = "tooltipHideFriendly", test = ShowsFriend, why = "friendly" },
}

-- Optional trace for /cine debug tooltip: what the tooltip did and why.
local function Trace(what, ...)
	local log = ns.tooltipTrace
	if log and #log < 60 then
		log[#log + 1] = ("%.2f %s"):format(GetTime() - log.started, what:format(...))
	end
end

-- Whether the tooltip should be hidden now, and why. Only in CineMode, with
-- the key not held, and never a minimap blip's. In a camera mode ticked
-- (tooltipHideIn*), every world and unit frame tooltip; in combat, enemies
-- (tooltipHideCombatEnemy), friendlies (tooltipHideCombatFriendly) or
-- everything else, the UI's too (tooltipHideCombatElse); otherwise the world
-- and unit frame kinds ticked.
local function Hides(tooltip)
	if not Handling() or not ns.lastCinematic or ShowKeyDown() then
		return false
	end
	local world = WorldOwned()
	if world and OverMinimap() then
		return false
	end
	local unitOrWorld = world or TooltipHasUnit(tooltip)
	local mode = TooltipCameraMode()
	if unitOrWorld and mode and ns.db[TOOLTIP_HIDE_IN[mode]] then
		return true, mode
	end
	if InCombat() then
		local enemy = TooltipUnitIsEnemy(tooltip)
		if enemy == true then
			return ns.db.tooltipHideCombatEnemy and true or false, "combat enemy"
		elseif enemy == false then
			return ns.db.tooltipHideCombatFriendly and true or false, "combat friendly"
		end
		return ns.db.tooltipHideCombatElse and true or false, "combat else"
	end
	if not unitOrWorld then
		return false
	end
	local why
	for _, kind in ipairs(HIDE_KINDS) do
		if kind.test(tooltip) then
			if not ns.db[kind.key] then
				return false
			end
			why = kind.why
		end
	end
	return why ~= nil, why
end

-- The decision for the tooltip up now, kept until it hides, shows something
-- else (the game reuses a world tooltip for the next unit without showing it
-- again) or things change (combat, the camera mode, CineMode, the key), so
-- the tick doesn't read the quest log and the lines each time.
local checked

local function CheckState()
	return ("%s:%s:%s:%s"):format(tostring(ns.lastCinematic), tostring(InCombat()),
		tostring(TooltipCameraMode()), tostring(ShowKeyDown()))
end

local function StillChecked(tooltip)
	return checked ~= nil and checked.owner == tooltip:GetOwner() and SameName(TooltipName(), checked.name)
		and checked.state == CheckState()
end

local function CheckTooltip(tooltip)
	local hide, why = Hides(tooltip)
	checked = { owner = tooltip:GetOwner(), name = TooltipName(), state = CheckState() }
	return hide, why
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

local function MouseFocus()
	if GetMouseFoci then
		return GetMouseFoci()[1]
	elseif GetMouseFocus then
		return GetMouseFocus()
	end
end

local function MouseOverWorld()
	local focus = MouseFocus()
	return focus == nil or focus == WorldFrame
end
ns.MouseOverWorld = MouseOverWorld -- (DragEquip.lua too)

-- Where the player is and faces. An object is only found by what's under the
-- cursor, and a parked cursor stays still while flying or turning moves the
-- world under it, so the view moving counts as leaving the object too.
local VIEW_SLACK_YARDS = 0.5
local VIEW_SLACK_FACING = math.rad(2)
local CURSOR_REACH = 32 -- UI pixels the cursor may wander over an object

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

-- What was hidden, to show again if the Show hidden tooltips key goes down
-- while you're still on it: a unit's (in the world or on a unit frame) from
-- the mouseover, a world object's from its noted lines. Any other UI
-- element's needs hovering again with the key held (putting it back would
-- mean running the game's own code). A unit counts as left once it's no
-- longer the mouseover; an object once the cursor strays from there or goes
-- over the UI, or the view moves (walking, flying, turning, the camera
-- orbiting).
local hid
local showingAgain -- (our own Show: not a new tooltip)

local function HideTooltip(tooltip, why)
	local world, hasUnit = WorldOwned(), TooltipHasUnit(tooltip)
	hid = nil
	if world or hasUnit then
		local x, y = GetCursorPosition()
		local px, py, facing = PlayerView()
		hid = {
			name = TooltipName(), owner = tooltip:GetOwner(), world = world, unit = hasUnit,
			x = x, y = y, px = px, py = py, facing = facing,
			lines = not hasUnit and NoteLines(tooltip) or nil,
		}
	end
	Trace("hiding %s (%s)", tostring(TooltipName()), tostring(why))
	tooltip:Hide()
end

local function StillOver(note)
	if not note.world and MouseFocus() ~= note.owner then
		return false
	end
	if note.unit then
		return ns.Flag(UnitExists("mouseover"))
	end
	local x, y = GetCursorPosition()
	local reach = CURSOR_REACH * UIParent:GetEffectiveScale()
	return math.abs(x - note.x) <= reach and math.abs(y - note.y) <= reach and MouseOverWorld()
		and not ViewMoved(note)
end

local function ShowAgain(note)
	hid = nil
	local tooltip = GameTooltip
	showingAgain = true
	local ok, err = pcall(GameTooltip_SetDefaultAnchor, tooltip, note.world and UIParent or note.owner)
	if note.unit then
		ok, err = pcall(tooltip.SetUnit, tooltip, "mouseover")
	elseif note.lines and #note.lines > 0 then
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
		ok, err = pcall(tooltip.Show, tooltip)
	end
	showingAgain = false
	checked = nil
	Trace("key down, showing %s ok=%s %s", tostring(note.name), tostring(ok), ok and "" or tostring(err))
end

-- Catches each new tooltip the moment it appears (a hidden tooltip shows
-- again for the next thing you mouse over, so this runs every time).
function ns.OnTooltipShow(self)
	if showingAgain then
		return
	end
	local hide, why = CheckTooltip(self)
	if ns.tooltipTrace then
		local owner = self:GetOwner()
		Trace("show %s owner=%s hide=%s (%s)", tostring(TooltipName()),
			tostring(owner and (owner:GetName() or "unnamed")), tostring(hide), tostring(why))
	end
	if hide then
		HideTooltip(self, why)
	else
		hid = nil
	end
end

-- After GameTooltip:SetUnit (a unit frame's OnEnter): OnShow ran inside it,
-- before the unit was known, and took it for "everything else". Checked again
-- here, still before it's drawn, rather than flashing until the next tick.
function ns.OnTooltipSetUnit(self)
	if showingAgain then
		return
	end
	unitTooltipOwner = self:GetOwner()
	if ns.Flag(self:IsShown()) and not WorldOwned() then
		local hide, why = CheckTooltip(self)
		if hide then
			HideTooltip(self, why)
		end
	end
end

function ns.OnTooltipHide()
	unitTooltipOwner = nil
	checked = nil
end

-- Runs on the tick: hides a tooltip that was already up as hiding starts (or
-- as the key's let go, or the game reused it for something else), and shows
-- a hidden one again while the key's down.
function ns.UpdateTooltip()
	if not Handling() then
		hid = nil
		return
	end
	if ns.Flag(GameTooltip:IsShown()) then
		if not StillChecked(GameTooltip) then
			local hide, why = CheckTooltip(GameTooltip)
			if hide then
				HideTooltip(GameTooltip, why)
			end
		end
		return
	end
	if hid then
		if not ns.lastCinematic or not StillOver(hid) then
			hid = nil
		elseif ShowKeyDown() then
			ShowAgain(hid)
		end
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

-- The game's frame rate counter (Ctrl+R) sits at the bottom of the screen in
-- WorldFrame, which draws under UIParent (the letterbox) whatever its strata:
-- it moves up above the bottom bar while the bars show. Where the game puts
-- it is kept, and taken again if the game moves it.
local framerate = { height = 0 }

local function LiftFramerate(height)
	local counter = _G.FramerateFrame
	if type(counter) ~= "table" or type(counter.GetNumPoints) ~= "function" then
		return
	end
	framerate.height = height
	if not framerate.hooked then
		framerate.hooked = true
		hooksecurefunc(counter, "SetPoint", function()
			if framerate.moving then
				return
			end
			-- The game placed it: keep that, lifted again a frame later (once
			-- it has set all its points).
			framerate.points = nil
			if framerate.height > 0 and not framerate.pending then
				framerate.pending = true
				C_Timer.After(0, function()
					framerate.pending = false
					LiftFramerate(framerate.height)
				end)
			end
		end)
	end
	if not framerate.points then
		if height == 0 or counter:GetNumPoints() == 0 then
			return -- (where the game put it, untouched)
		end
		framerate.points = {}
		for i = 1, counter:GetNumPoints() do
			framerate.points[i] = { counter:GetPoint(i) }
		end
	end
	local lift = height * UIParent:GetEffectiveScale() / counter:GetEffectiveScale()
	framerate.moving = true
	counter:ClearAllPoints()
	for _, point in ipairs(framerate.points) do
		counter:SetPoint(point[1], point[2], point[3], point[4], point[5] + lift)
	end
	framerate.moving = false
end

function ns.UpdateLetterbox(cinematic, elapsed)
	local target = (cinematic and ns.db.letterbox) and 1 or 0
	if letterboxProgress == target and not ns.letterboxDirty then
		return
	end
	ns.letterboxDirty = false
	local duration = target > letterboxProgress and ns.FadeOutTime() or ns.FadeInTime()
	letterboxProgress = ns.Approach(letterboxProgress, target, elapsed, duration)

	-- Smoothstep so the bars ease in and out.
	local t = letterboxProgress * letterboxProgress * (3 - 2 * letterboxProgress)
	local height = math.max(t * UIParent:GetHeight() * ns.db.letterboxSize, 0.01)
	ns.letterbox.top:SetHeight(height)
	ns.letterbox.bottom:SetHeight(height)
	ns.letterbox:SetAlpha(ns.db.letterboxAlpha)
	ns.letterbox:SetShown(letterboxProgress > 0)
	LiftFramerate(letterboxProgress > 0 and height or 0)
end
