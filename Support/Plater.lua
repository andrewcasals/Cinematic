-- Cinematic: Plater, which draws nameplates of its own and treats the game's
-- nameplate settings as its own too. Neither fits the usual support (fading
-- its frames with a row), so:
--
-- Settings. It keeps a copy of the game's nameplate settings in each of its
-- profiles and writes them back at every login (and on a profile change, on
-- its first run on a character, and by zone or combat with its auto
-- toggles). Those passes aren't the player's doing: settings cinematic mode
-- holds stay held and are written back after them, and the Nameplates page's
-- rows are switched on again if a pass turned them off. Its copy is kept to
-- the player's own values rather than the ones cinematic mode holds for now,
-- or it would write those back at the next login.
--
-- Fade. Its plates are its own frames (plate.unitFrame), standing in for the
-- game's (hidden), and it sets their alpha all the time for its range and
-- target fading. They're its own frames, so they're hooked: while a plate is
-- faded its alpha is ours times its own, and at full it's left to it again.
local _, ns = ...
local L = ns.L

-- 3rd Party Frames page (no columns: its plates follow the Nameplates page).
table.insert(ns.ADDON_NOTES, {
	addon = "Plater", label = "Plater",
	works = L["Follows the Nameplates page"],
	about = L["Plater's nameplates fade in CineMode and follow the Nameplates page's rows. Plater can " ..
		"change the game's nameplate settings itself (at login, and with its auto toggles); " ..
		"Cinematic puts its own back afterwards."],
})

-- The game's settings that pick which plates show: one of these changed by a
-- pass gets the Nameplates page's rows switched on again.
local ROW_CVARS = {
	"nameplateShowEnemies", "nameplateShowEnemyMinions", "nameplateShowEnemyPets",
	"nameplateShowEnemyGuardians", "nameplateShowEnemyTotems", "nameplateShowEnemyMinus",
	"nameplateShowFriends", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNPCs",
	"nameplateShowFriendlyMinions", "nameplateShowFriendlyPets", "nameplateShowFriendlyGuardians",
	"nameplateShowFriendlyTotems", "nameplateShowFriendlyPlayerMinions", "nameplateShowFriendlyPlayerPets",
	"nameplateShowFriendlyPlayerGuardians", "nameplateShowFriendlyPlayerTotems",
}

-- Its own passes over the game's settings.
local PASSES = { "RestoreProfileCVars", "SetCVarsOnFirstRun", "RefreshAutoToggle" }

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function RowValues()
	local values = {}
	for _, cvar in ipairs(ROW_CVARS) do
		values[cvar] = GetCVar(cvar)
	end
	return values
end

-- Its profile's copy of the game's settings.
local function SavedCopy()
	local plater = _G.Plater
	local profile = plater and plater.db and plater.db.profile
	return profile and type(profile.saved_cvars) == "table" and profile.saved_cvars or nil
end

-- Logged once: its auto toggles switch the same settings as the Nameplates
-- page's rows, which win after each.
local autoToggleNoted = false
local function NoteAutoToggles()
	local plater = _G.Plater
	local profile = plater and plater.db and plater.db.profile
	if autoToggleNoted or not profile then
		return
	end
	autoToggleNoted = true
	local on = {}
	for _, key in ipairs({ "auto_toggle_friendly_enabled", "auto_toggle_enemy_enabled", "auto_toggle_combat_enabled" }) do
		if profile[key] then
			on[#on + 1] = key
		end
	end
	if #on > 0 then
		ns.Log("support", "Plater auto toggles on (" .. table.concat(on, ", ") ..
			"): the Nameplates page's rows are switched back on after them")
	end
end

-- Settings ------------------------------------------------------------------

local function FollowPasses(plater)
	for _, name in ipairs(PASSES) do
		local pass = plater[name]
		if type(pass) == "function" then
			plater[name] = function(...)
				local before = RowValues()
				local results = { ns.RunOthersCVarPass(pass, ...) }
				NoteAutoToggles()
				if ns.db and ns.db.handlePlates then
					local after = RowValues()
					for _, cvar in ipairs(ROW_CVARS) do
						if before[cvar] ~= after[cvar] then
							ns.Log("cvar", ("Plater (%s) set %s to %s: Nameplates page's rows switched on again")
								:format(name, cvar, tostring(after[cvar])))
							ns.EnsurePlateRows()
							break
						end
					end
				end
				return unpack(results)
			end
		end
	end

	-- It copies every setting written into its profile (ours too): a setting
	-- held for now goes in as the value it comes back to.
	table.insert(ns.cvarWrittenHooks, function(cvar)
		local back = ns.db and ns.db.savedCVars[cvar]
		local saved = back ~= nil and SavedCopy()
		if not saved then
			return
		end
		local lower = cvar:lower()
		for key in pairs(saved) do
			if type(key) == "string" and key:lower() == lower then
				saved[key] = plater.ParseCVarValue and plater.ParseCVarValue(back) or tostring(back)
				return
			end
		end
	end)
end

-- Fade -----------------------------------------------------------------------

-- On its unit frames: cinematicPlateAlpha, our alpha while faded (nil at
-- full); cinematicOwnAlpha, the alpha it last set itself (nil when it can't
-- be known: set from a secret value).
local applying = false

local function Apply(frame)
	applying = true
	frame:SetAlpha((frame.cinematicOwnAlpha or 1) * (frame.cinematicPlateAlpha or 1))
	applying = false
end

local function HookFrame(frame)
	if frame.cinematicHooked then
		return
	end
	frame.cinematicHooked = true
	local alpha = frame:GetAlpha()
	frame.cinematicOwnAlpha = Known(alpha) and alpha or nil
	hooksecurefunc(frame, "SetAlpha", ns.Profiled("Plater SetAlpha hook", function(self, own)
		if applying then
			return
		end
		self.cinematicOwnAlpha = type(own) == "number" and Known(own) and own or nil
		if self.cinematicPlateAlpha then
			Apply(self)
		end
	end))
	if frame.SetAlphaFromBoolean then
		hooksecurefunc(frame, "SetAlphaFromBoolean", function(self)
			self.cinematicOwnAlpha = nil
			if self.cinematicPlateAlpha then
				Apply(self)
			end
		end)
	end
end

local function SetPlaterPlateAlpha(plate, alpha)
	local frame = plate.unitFrame
	if type(frame) ~= "table" or not frame.Plater or not frame.SetAlpha then
		return
	end
	if alpha and alpha < 1 then
		HookFrame(frame)
		if frame.cinematicPlateAlpha ~= alpha then
			frame.cinematicPlateAlpha = alpha
			Apply(frame)
		end
	elseif frame.cinematicPlateAlpha then
		frame.cinematicPlateAlpha = nil
		Apply(frame) -- (back to its own alpha; one it can't tell is put right at its next update)
	end
end

ns.WhenAddonLoads("Plater", function()
	local plater = _G.Plater
	if type(plater) ~= "table" then
		return
	end
	FollowPasses(plater)
	ns.addonPlateAlpha = SetPlaterPlateAlpha
end)
