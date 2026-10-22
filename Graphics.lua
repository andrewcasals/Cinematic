-- Cinematic: Graphics+, the game's graphics settings one by one, past its
-- Graphics menu either way: higher for a better look (denser grass, more
-- distant detail, sharper shadows), lower for a faster game.
--
-- Each is one of the game's own settings (CVars), which it keeps between
-- sessions. A slider changes nothing until it's moved (its value is nil till
-- then, shown as the game's own). Moved and ticked (graphicsPlus<name>On),
-- its value is written, the game's own value noted first (graphicsPlusSaved)
-- and written back when it's unticked, the page's switch goes off or the page
-- is reset, so ticking and unticking compares the two. The Graphics menu
-- rewrites these when it's changed, so after any graphics setting changes
-- they're looked at again, the menu's new value noted and ours put back. The
-- settings are the machine's, not a profile's (see Profiles.lua).
local _, ns = ...

-- min and menu: the least and the most the game's Graphics menu sets (tested
-- on WoW Forever with /cine debug cvars); max: as far as the slider goes (from
-- players' testing: past it there's nothing more to see, or a crash). values:
-- the only ones it takes, in place of a range. also: settings written the
-- same value alongside it, but only ever raised. noMenu: not in the Graphics
-- menu at all. secure: can't change in a fight (it waits). resetToDefault:
-- Reset page puts the game's default back, not just its own. decimals: shown
-- with this many. group: the page's header it goes under (in this order).
ns.GRAPHICS_PLUS = {
	-- (How far away nameplates show, in yards. The game caps it at its own limit.)
	{ key = "graphicsPlusPlateDistance", cvar = "nameplateMaxDistance", min = 10, menu = 60, max = 100, step = 5,
		group = "Camera and nameplates", noMenu = true, secure = true, resetToDefault = true },
	-- (How far out the camera zooms, times the game's base distance. The game caps it at its own limit.)
	{ key = "graphicsPlusZoomMax", cvar = "cameraDistanceMaxZoomFactor", min = 1, menu = 2.6, max = 4, step = 0.1,
		group = "Camera and nameplates", noMenu = true, decimals = 1 },
	{ key = "graphicsPlusClutter", cvar = "groundEffectDensity", min = 16, menu = 48, max = 256, step = 8,
		group = "Ground clutter" },
	{ key = "graphicsPlusClutterDistance", cvar = "groundEffectDist", min = 40, menu = 320, max = 500, step = 20,
		group = "Ground clutter" },
	-- (Not set by the menu, always 70: where the grass starts thinning out, towards groundEffectDist.)
	{ key = "graphicsPlusClutterFade", cvar = "groundEffectFade", min = 0, menu = 70, max = 500, step = 10,
		group = "Ground clutter" },
	-- (Where the land turns to the flat horizon, and how far anything's drawn: together.)
	{ key = "graphicsPlusView", cvar = "horizonStart", also = { "farclip" }, min = 400, menu = 4000,
		max = 24000, step = 400, group = "Land and buildings" },
	{ key = "graphicsPlusTerrain", cvar = "terrainLodDist", min = 200, menu = 650, max = 2000, step = 50,
		group = "Land and buildings" },
	{ key = "graphicsPlusBuildings", cvar = "wmoLodDist", min = 250, menu = 400, max = 2000, step = 50,
		group = "Land and buildings" },
	{ key = "graphicsPlusObjects", cvar = "doodadLodScale", min = 50, menu = 150, max = 300, step = 10,
		group = "Objects and creatures" },
	{ key = "graphicsPlusObjectFade", cvar = "lodObjectFadeScale", min = 50, menu = 150, max = 600, step = 25,
		group = "Objects and creatures" },
	{ key = "graphicsPlusCreatures", cvar = "entityLodDist", min = 5, menu = 10, max = 1000, step = 5,
		group = "Objects and creatures" },
	{ key = "graphicsPlusShadows", cvar = "shadowTextureSize", min = 512, menu = 2048, max = 4096,
		values = { 512, 1024, 2048, 4096 }, group = "Shadows" },
}

local writing = false
local borrowed = false -- a setting left alone while another feature has it

local function Exists(cvar)
	return GetCVar(cvar) ~= nil
end
ns.GraphicsPlusExists = Exists

local function Write(cvar, value)
	writing = true
	SetCVar(cvar, value)
	writing = false
end

local function Same(a, b)
	return tonumber(a) ~= nil and tonumber(a) == tonumber(b)
end

-- Writes a setting as the page says (wanted: nil for the game's own, put
-- back). raiseOnly: only written when above the game's own.
-- graphicsPlusSaved: [cvar] = the game's own value; graphicsPlusWritten:
-- [cvar] = what we wrote, to tell the Graphics menu's changes from ours.
local function ApplyOne(cvar, wanted, raiseOnly, saved, written)
	if ns.db.savedCVars and ns.db.savedCVars[cvar] ~= nil then
		-- Borrowed for now (idle zoom raising the max zoom): looked at again
		-- once it's put back.
		borrowed = true
		return
	end
	local now = GetCVar(cvar)
	if saved[cvar] ~= nil and not Same(now, written[cvar]) then
		-- Changed since we wrote it (the Graphics menu): that's the game's own now.
		ns.Log("graphics", ("%s changed to %s outside Graphics+"):format(cvar, tostring(now)))
		saved[cvar] = now
	end
	if wanted and raiseOnly and wanted <= (tonumber(saved[cvar] or now) or 0) then
		wanted = nil
	end
	if wanted then
		saved[cvar] = saved[cvar] or now
		local text = tostring(wanted)
		if not Same(now, text) then
			ns.Log("graphics", ("%s %s -> %s"):format(cvar, tostring(now), text))
			Write(cvar, text)
		end
		-- (What the game kept: one it caps isn't then taken for a menu change.)
		written[cvar] = GetCVar(cvar)
	elseif saved[cvar] ~= nil then
		if not Same(now, saved[cvar]) then
			ns.Log("graphics", ("%s back to %s"):format(cvar, tostring(saved[cvar])))
			Write(cvar, saved[cvar])
		end
		saved[cvar], written[cvar] = nil, nil
	end
end

function ns.ApplyGraphicsPlus()
	local db = ns.db
	if not db then return end
	db.graphicsPlusSaved = db.graphicsPlusSaved or {}
	db.graphicsPlusWritten = db.graphicsPlusWritten or {}
	local saved, written = db.graphicsPlusSaved, db.graphicsPlusWritten
	borrowed = false
	for _, setting in ipairs(ns.GRAPHICS_PLUS) do
		if Exists(setting.cvar) and not (setting.secure and InCombatLockdown()) then
			local wanted = db.graphicsPlus and db[setting.key .. "On"] and db[setting.key] or nil
			ApplyOne(setting.cvar, wanted, false, saved, written)
			for _, cvar in ipairs(setting.also or {}) do
				if Exists(cvar) then
					ApplyOne(cvar, wanted, true, saved, written)
				end
			end
		end
	end
end

-- Reset page: settings marked resetToDefault go back to the game's default
-- (after a fight, for those that can't change in one).
local toDefault = false
local function GameDefault(cvar)
	local GetDefault = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
	return GetDefault and GetDefault(cvar)
end
ns.GraphicsPlusDefault = GameDefault

local function WriteDefaults()
	toDefault = false
	for _, setting in ipairs(ns.GRAPHICS_PLUS) do
		if setting.resetToDefault and Exists(setting.cvar) then
			if setting.secure and InCombatLockdown() then
				toDefault = true
			else
				local default = GameDefault(setting.cvar)
				if default and not Same(GetCVar(setting.cvar), default) then
					ns.Log("graphics", ("%s reset to the game's default %s"):format(setting.cvar, tostring(default)))
					Write(setting.cvar, default)
				end
			end
		end
	end
end
ns.GraphicsPlusResetDefaults = WriteDefaults

-- The game's own value of a setting: as noted while ours is written, else as it stands.
function ns.GraphicsPlusOwn(setting)
	local saved = ns.db and ns.db.graphicsPlusSaved
	return saved and saved[setting.cvar] or GetCVar(setting.cvar)
end

-- After a graphics setting changes (the Graphics menu writes several at
-- once), look again once they've settled. Only while something's written.
local WATCHED = {} -- [lowercased cvar] = true
for _, setting in ipairs(ns.GRAPHICS_PLUS) do
	WATCHED[setting.cvar:lower()] = true
	for _, cvar in ipairs(setting.also or {}) do
		WATCHED[cvar:lower()] = true
	end
end
local pending = false
local function Settled()
	pending = false
	ns.ApplyGraphicsPlus()
end
local function Recheck(name)
	if writing or pending or type(name) ~= "string"
		or not (borrowed or (ns.db and ns.db.graphicsPlusSaved and next(ns.db.graphicsPlusSaved))) then
		return
	end
	name = name:lower()
	if WATCHED[name] or name:find("^graphics") then
		pending = true
		C_Timer.After(0.5, Settled)
	end
end

if C_CVar and C_CVar.SetCVar then
	hooksecurefunc(C_CVar, "SetCVar", Recheck)
end
hooksecurefunc("SetCVar", Recheck)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED") -- (settings that wait for a fight to end)
watcher:RegisterEvent("CVAR_UPDATE")
watcher:SetScript("OnEvent", ns.Profiled("Graphics+ event", function(_, event, name)
	if event == "PLAYER_REGEN_ENABLED" then
		if toDefault then
			WriteDefaults()
		end
		ns.ApplyGraphicsPlus()
	elseif event == "PLAYER_LOGIN" then
		ns.ApplyGraphicsPlus()
	else
		Recheck(name)
	end
end))
