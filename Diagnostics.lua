-- Cinematic: a log for bug reports, and the safety net for Lua errors.
--
-- The log is a short history (the last LOG_MAX lines) kept in the saved
-- settings (CinematicDB.log), so it survives a /reload or logout. Addons can't
-- write files of their own: /cine log shows it, with a summary of the setup,
-- ready to copy and paste into a bug report.
--
-- Errors from this addon are logged with their stack. One that keeps coming
-- back (an error every frame) stops the addon for the session and puts the
-- game back as it was (see ns.Suspend in Core.lua). This file loads first so
-- its error handler also sees errors while the other files load.
local ADDON_NAME, ns = ...

local LOG_MAX = 500
local STACK_MAX = 1500       -- characters of stack kept per error
local REPEAT_LIMIT = 5       -- the same error this many times...
local REPEAT_WINDOW = 3      -- ...within this many seconds means it's stuck in a loop

-- Addons that also fade frames, move the camera or handle nameplates, so they
-- may overlap with this one. Only noted in the log's summary.
local OVERLAPPING = {
	"DynamicCam", "ElvUI", "Immersion", "ConsolePort", "SexyMap", "Bartender4", "Dominos",
	"Plater", "Kui_Nameplates", "TidyPlates_ThreatPlates", "Platynator",
}

local pending = {} -- lines logged before the saved settings load
local captured -- while a /cine debug command runs: what it prints, for the copy window

local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
local NumAddOns = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
local AddOnInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo

local function Plain(text)
	return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function ns.Log(category, text)
	-- (What's printed to chat is caught at print, below; this adds what only goes in the log.)
	if captured and category ~= "chat" and category ~= "cmd" then
		captured[#captured + 1] = Plain(text)
	end
	local line = ("%s %s: %s"):format(date("%H:%M:%S"), category, Plain(text))
	local log = ns.db and ns.db.log
	if not log then
		pending[#pending + 1] = line
		return
	end
	log[#log + 1] = line
	-- Trim in batches rather than shifting the whole list every line.
	if #log > LOG_MAX + 50 then
		local kept = {}
		for i = #log - LOG_MAX + 1, #log do
			kept[#kept + 1] = log[i]
		end
		ns.db.log = kept
	end
end

-- Detail only wanted while tracking something down (/cine debug record).
function ns.LogDetail(category, text)
	if ns.db and ns.db.logDetail then
		ns.Log(category, text)
	end
end

local function Version()
	return GetMetadata and GetMetadata(ADDON_NAME, "Version") or "?"
end
ns.Version = Version -- (the main settings page shows it too)

-- Called from Core.lua once the saved settings are loaded.
function ns.InitLog()
	ns.db.log = ns.db.log or {}
	local _, build, _, interface = GetBuildInfo()
	ns.Log("session", ("---- %s %s, game %s (%s), %s ----"):format(ADDON_NAME, Version(),
		tostring(interface), tostring(build), GetLocale()))
	for _, line in ipairs(pending) do
		ns.db.log[#ns.db.log + 1] = line
	end
	pending = nil
	-- (Left on from last session: /cine debug combatlog again turns it off.)
	if ns.db.debugCombatLog and ns.CombatLogDebug then ns.CombatLogDebug(true) end
end

-- Errors ---------------------------------------------------------------------

-- Matches this addon's files in an error or a stack, with or without the
-- Interface/AddOns/ part (BugGrabber strips it).
local OUR_FILE = "%f[%w]" .. ADDON_NAME .. "[/\\][^:]+%.lua"

local function IsOurs(text)
	return type(text) == "string" and text:find(OUR_FILE) ~= nil
end

local errors = {}      -- message -> { count, windowStart, inWindow }
local errorOrder = {}  -- messages, first seen first
local told = false     -- told the player about /cine log this session
local forwarding = false

local function Shorten(stack)
	stack = (stack or ""):gsub("Interface[/\\]AddOns[/\\]", "")
	if #stack > STACK_MAX then
		stack = stack:sub(1, STACK_MAX) .. "..."
	end
	return stack
end

-- Records an error from this addon. `caught` errors were stopped by the
-- addon's own loop (so the game's error handler hasn't seen them yet).
function ns.ReportError(message, stack, caught)
	message = tostring(message)
	local now = GetTime()
	local entry = errors[message]
	if not entry then
		entry = { count = 0, windowStart = now, inWindow = 0 }
		errors[message] = entry
		errorOrder[#errorOrder + 1] = message
		ns.Log("ERROR", message .. "\n" .. Shorten(stack))
		if caught then
			-- Pass it on (once) so BugSack or the game's error window still shows it.
			forwarding = true
			pcall(geterrorhandler(), message)
			forwarding = false
		end
		if not told and ns.Print then
			told = true
			ns.Print("hit a Lua error. Type /cine log to copy the details for a bug report.")
		end
	end
	entry.count = entry.count + 1
	if now - entry.windowStart > REPEAT_WINDOW then
		entry.windowStart, entry.inWindow = now, 0
	end
	entry.inWindow = entry.inWindow + 1
	if entry.inWindow >= REPEAT_LIMIT and ns.Suspend and not ns.IsSuspended() then
		ns.Log("safety", ("that error came %d times in %d sec"):format(entry.inWindow, REPEAT_WINDOW))
		ns.Suspend("an error kept repeating")
	end
end

-- After /cine resume: give the repeat counts a fresh start.
function ns.ResetErrorWindows()
	for _, entry in pairs(errors) do
		entry.inWindow = 0
	end
end

-- How many times each error happened, for the log and the summary.
local function ErrorCounts()
	local lines = {}
	for _, message in ipairs(errorOrder) do
		local count = errors[message].count
		if count > 1 then
			lines[#lines + 1] = ("%dx %s"):format(count, message:match("^[^\n]*"))
		end
	end
	return lines
end

-- The game's error handler, wrapped to notice this addon's errors. With
-- BugGrabber installed it usually owns the handler, so its callback is used.
local usingBugGrabber = false
local original = geterrorhandler()
seterrorhandler(function(message, ...)
	-- (WoW Forever, as and once DragEquip.lua has opened or closed the
	-- character window: it works, but Blizzard's player and pet bars, updated
	-- in our call and so counted as ours, can't compare their secret values.
	-- Only those are dropped: any during the call, and the bars' own later
	-- updates (text, health, heal prediction) after it.)
	if type(message) == "string" and message:find("secret", 1, true)
		and message:find("tainted by '" .. ADDON_NAME .. "'", 1, true)
		and (ns.togglingCharacter or message:find("TextStatusBar", 1, true)
			or message:find("HealthBar", 1, true) or message:find("UnitFrame", 1, true)) then
		return
	end
	if not forwarding and not usingBugGrabber then
		local stack = debugstack(2)
		if IsOurs(message) or IsOurs(stack) then
			pcall(ns.ReportError, message, stack)
		end
	end
	return original(message, ...)
end)

local function UseBugGrabber()
	local grabber = _G.BugGrabber
	if usingBugGrabber or not (grabber and grabber.RegisterCallback) then
		return
	end
	usingBugGrabber = true
	grabber.RegisterCallback(ns, "BugGrabber_BugGrabbed", function(_, err)
		if not forwarding and err and (IsOurs(err.message) or IsOurs(err.stack)) then
			pcall(ns.ReportError, err.message, err.stack)
		end
	end)
end

-- Blocked actions (taint) aren't Lua errors; the game names the addon.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_LOGOUT")
watcher:SetScript("OnEvent", function(_, event, addon, action)
	if event == "PLAYER_LOGIN" then
		UseBugGrabber()
		-- The released and dev copies share their saved settings.
		local other = ADDON_NAME == "CinematicDev" and "Cinematic" or "CinematicDev"
		if IsLoaded and IsLoaded(other) then
			ns.Print(("|cffff4040%s is loaded too.|r Turn one of them off: they share their settings and " ..
				"fight over the screen."):format(other))
			ns.Log("warning", other .. " is loaded too")
		end
	elseif event == "PLAYER_LOGOUT" then
		for _, line in ipairs(ErrorCounts()) do
			ns.Log("errors", line)
		end
	elseif addon == ADDON_NAME then
		ns.Log("BLOCKED", ("%s: %s"):format(event, tostring(action)))
	end
end)

-- The report ----------------------------------------------------------------

-- The other addons loaded now, sorted.
local function OtherAddons()
	local addons = {}
	if NumAddOns and AddOnInfo and IsLoaded then
		for i = 1, NumAddOns() do
			local name = AddOnInfo(i)
			if name and name ~= ADDON_NAME and IsLoaded(i) then
				addons[#addons + 1] = name
			end
		end
	end
	table.sort(addons)
	return addons
end

local function Summary()
	local lines = {}
	local function add(text) lines[#lines + 1] = text end
	local _, build, _, interface = GetBuildInfo()
	add(("%s %s | game %s (%s) | %s"):format(ADDON_NAME, Version(), tostring(interface), tostring(build),
		GetLocale()))
	local ok, mode = pcall(ns.CameraMode)
	add(("state: %s%s, camera mode %s"):format(ns.db.enabled and "on" or "off",
		ns.IsSuspended() and " (STOPPED after an error)" or "", ok and tostring(mode or "none") or "?"))
	local left = {}
	for cvar, value in pairs(ns.db.savedCVars or {}) do
		left[#left + 1] = cvar .. "=" .. tostring(value)
	end
	if #left > 0 then
		table.sort(left)
		add("game settings held: " .. table.concat(left, ", "))
	end

	add("profile: " .. (ns.ActiveProfile and ns.ActiveProfile() or "?"))
	-- Settings changed from the defaults (tables, like frame lists, left out).
	local changed = {}
	for key, default in pairs(ns.DEFAULTS) do
		local value = ns.db[key]
		if value ~= default and type(value) ~= "table" and not key:find("^debug") then
			changed[#changed + 1] = key .. "=" .. tostring(value)
		end
	end
	table.sort(changed)
	add(("changed settings (%d): %s"):format(#changed, #changed > 0 and table.concat(changed, ", ") or "none"))

	local addons, overlapping = OtherAddons(), {}
	for _, name in ipairs(OVERLAPPING) do
		if IsLoaded and IsLoaded(name) then
			overlapping[#overlapping + 1] = name
		end
	end
	if #overlapping > 0 then
		add("may overlap: " .. table.concat(overlapping, ", "))
	end
	add(("other addons (%d): %s"):format(#addons, table.concat(addons, ", ")))

	local counts = ErrorCounts()
	if #counts > 0 then
		add("errors this session: " .. table.concat(counts, " | "))
	end
	return table.concat(lines, "\n")
end

local window

local function CreateWindow()
	window = CreateFrame("Frame", "CinematicLogWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	window:SetSize(720, 460)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	tinsert(UISpecialFrames, "CinematicLogWindow") -- Escape closes it

	local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -12)
	window.title = title

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	-- The template's click goes through HideUIPanel, which does nothing in combat.
	close:SetScript("OnClick", function() window:Hide() end)

	local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -34)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)

	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetMaxLetters(0)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(scroll:GetWidth() > 0 and scroll:GetWidth() or 670)
	box:SetScript("OnEscapePressed", function() window:Hide() end)
	-- Read-only: any typing puts the text back.
	box:SetScript("OnTextChanged", function(self, user)
		if user then
			self:SetText(window.text)
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(box)
	scroll:SetScript("OnSizeChanged", function(_, width) box:SetWidth(width) end)
	window.box = box
end

-- The window with any text, selected and ready to copy.
local shownCount = 0 -- (so a debug command that opens it itself isn't covered over)
local function ShowText(title, text)
	if not window then
		CreateWindow()
	end
	shownCount = shownCount + 1
	window.title:SetText(title)
	window.text = text
	window:Show()
	window.box:SetText(text)
	window.box:SetFocus()
	window.box:HighlightText()
end

ns.ShowText = ShowText

function ns.ShowLog()
	local log = ns.db.log or {}
	ShowText("Cinematic log: press Ctrl+C to copy, then paste it into your bug report",
		("%s\n\n--- log (%d lines, newest last) ---\n%s"):format(Summary(), #log, table.concat(log, "\n")))
end

-- /cine debug commands (and /cine list): what one prints or logs at once also
-- opens in the window, for copying (not the toggles' line or two, nor what
-- timed ones print later). Every print counts, not just ns.Print's.
function ns.CaptureDebug(command, run)
	captured = {}
	local print = _G.print
	_G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		captured[#captured + 1] = (Plain(table.concat(parts, " ")):gsub("^Cinematic: ", ""))
		return print(...)
	end
	local before = shownCount
	local ok, err = pcall(run)
	_G.print = print
	local lines = captured
	captured = nil
	if #lines >= 3 and shownCount == before then
		-- (With the version, game and other addons, for when a player sends it.)
		local _, build, _, interface = GetBuildInfo()
		local addons = OtherAddons()
		ShowText(("%s: press Ctrl+C to copy"):format(command),
			("%s (%s %s, game %s (%s), %s)\nother addons (%d): %s\n%s"):format(command, ADDON_NAME, Version(),
				tostring(interface), tostring(build), GetLocale(), #addons, table.concat(addons, ", "),
				table.concat(lines, "\n")))
	end
	if not ok then error(err, 0) end
end

function ns.ClearLog()
	ns.db.log = {}
	ns.Log("session", "log cleared")
end

-- Graphics CVars (/cine debug cvars) ------------------------------------------
-- Which graphics settings the game's own menu reaches, for a possible "beyond
-- Ultra" page. The first run logs the candidates (there or not, now, default)
-- and notes every CVar's value; move the Graphics sliders, run it again, and
-- the log lists each CVar the menu changed. Ones that never change are console only.
do
	local CANDIDATES = {
		"farclip", "horizonStart", "entityLodDist", "terrainLodDist", "wmoLodDist",
		"lodObjectCullSize", "lodObjectMinSize", "lodObjectFadeScale",
		"groundEffectDensity", "groundEffectDist", "renderScale", "ResampleSharpness",
		"MSAAQuality", "ffxAntiAliasingMode", "textureFilteringMode", "shadowMode",
		"shadowTextureSize", "shadowSoft", "shadowRt", "ssao", "sunShafts", "depthEffects",
		"refraction", "projectedTextures", "particleDensity", "weatherDensity",
		"waterDetail", "reflectionMode", "rippleDetail",
	}
	local snapshot -- name -> value, from the first run

	local function Value(get, name)
		local ok, value = pcall(get, name)
		if ok and type(value) == "string" then return value end
	end

	-- Every CVar name the client lists (older clients: just the candidates).
	local function AllNames()
		local names = {}
		local list = C_Console and C_Console.GetAllCommands and select(2, pcall(C_Console.GetAllCommands))
			or (ConsoleGetAllCommands and select(2, pcall(ConsoleGetAllCommands)))
		local cvarType = Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar
		if type(list) == "table" then
			for _, info in ipairs(list) do
				if type(info) == "table" and type(info.command) == "string"
					and (cvarType == nil or info.commandType == cvarType) then
					names[#names + 1] = info.command
				end
			end
		end
		if #names == 0 then
			for _, name in ipairs(CANDIDATES) do names[#names + 1] = name end
		end
		return names
	end

	function ns.CVarsDebug()
		local get = (C_CVar and C_CVar.GetCVar) or GetCVar
		local getDefault = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
		if not snapshot then
			local missing = 0
			for _, name in ipairs(CANDIDATES) do
				local value = Value(get, name)
				if value then
					ns.Log("cvars", ("%s = %s (default %s)"):format(name, value,
						tostring(getDefault and Value(getDefault, name))))
				else
					missing = missing + 1
					ns.Log("cvars", name .. ": not on this client")
				end
			end
			snapshot = {}
			local count = 0
			for _, name in ipairs(AllNames()) do
				local value = Value(get, name)
				if value then
					snapshot[name] = value
					count = count + 1
				end
			end
			ns.Print(("cvars: %d of %d candidates on this client (in /cine log). Noted %d CVars: now open"
				.. " the game's Graphics settings, move each slider to its highest, apply, then"
				.. " /cine debug cvars again"):format(#CANDIDATES - missing, #CANDIDATES, count))
			return
		end
		local changed = 0
		for name, before in pairs(snapshot) do
			local now = Value(get, name)
			if now and now ~= before then
				changed = changed + 1
				ns.Log("cvars", ("menu changed %s: %s -> %s"):format(name, before, now))
			end
		end
		snapshot = nil
		ns.Print(("cvars: %d changed since the first run (in /cine log). Run it again to start over")
			:format(changed))
	end

	-- /cine debug cvars <words>: every CVar whose name has any of the words in
	-- it (any case), for finding a setting by what it's likely called.
	function ns.CVarsFind(words)
		local get = (C_CVar and C_CVar.GetCVar) or GetCVar
		local getDefault = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
		local found = {}
		for _, name in ipairs(AllNames()) do
			local lower = name:lower()
			for word in words:gmatch("%S+") do
				if lower:find(word, 1, true) then
					found[#found + 1] = name
					break
				end
			end
		end
		table.sort(found)
		for _, name in ipairs(found) do
			ns.Log("cvars", ("%s = %s (default %s)"):format(name, tostring((Value(get, name))),
				tostring(getDefault and Value(getDefault, name))))
		end
		ns.Print(("cvars: %d named like \"%s\" (in /cine log)"):format(#found, words))
	end
end

-- /cine debug settings <words>: every option in the game's Settings panel whose
-- shown name has any of the words in it, with the variable behind it and its
-- value, for settings that aren't plain CVars (like Forever's Character Models).
function ns.SettingsFind(words)
	local panel = _G.SettingsPanel
	local ok, categories = pcall(function() return panel:GetAllCategories() end)
	if not (ok and type(categories) == "table") then
		ns.Print("settings: no Settings panel here")
		return
	end
	local count = 0
	for _, category in ipairs(categories) do
		local _, layout = pcall(panel.GetLayout, panel, category)
		local _, initializers = pcall(function() return layout:GetInitializers() end)
		for _, initializer in ipairs(type(initializers) == "table" and initializers or {}) do
			local _, setting = pcall(function() return initializer:GetSetting() end)
			local _, name = pcall(function() return setting:GetName() end)
			if type(name) == "string" then
				local lower = name:lower()
				for word in words:lower():gmatch("%S+") do
					if lower:find(word, 1, true) then
						local _, variable = pcall(setting.GetVariable, setting)
						local _, value = pcall(setting.GetValue, setting)
						local line = ("settings: %s: variable %s = %s"):format(name, tostring(variable), tostring(value))
						ns.Print(line)
						ns.Log("settings", line)
						count = count + 1
						break
					end
				end
			end
		end
	end
	ns.Print(("settings: %d named like \"%s\""):format(count, words))
end

-- Group health (/cine debug health) -------------------------------------------
-- For a possible healer list (the tank plus whoever's most hurt): whether this
-- client hands addons the group's health as plain numbers it can compare and
-- sort, or as secret values (only drawable on a bar). Run it in and out of
-- combat; each run also goes in the log.
do
	local function Secret(value)
		return issecretvalue ~= nil and issecretvalue(value) == true
	end

	local function Read(func, ...)
		if not func then return "no API" end
		local ok, value = pcall(func, ...)
		if not ok then return "error" end
		return value
	end

	local function Show(value)
		if Secret(value) then return "secret" end
		return tostring(value)
	end

	-- Can the addon do the sums and comparisons sorting needs?
	local function Usable(health, max)
		if type(health) ~= "number" or type(max) ~= "number" or Secret(health) or Secret(max) then
			return false
		end
		return (pcall(function() return max - health > 0 and health / max < 1 end))
	end

	-- The group, then (withOthers) the target, focus and mouseover.
	local function Units(withOthers)
		local units = { "player" }
		local count = GetNumGroupMembers and GetNumGroupMembers() or 0
		if IsInRaid and IsInRaid() then
			units = {}
			for i = 1, count do units[#units + 1] = "raid" .. i end
		else
			for i = 1, math.max(0, count - 1) do units[#units + 1] = "party" .. i end
		end
		for _, unit in ipairs(withOthers and { "target", "focus", "mouseover" } or {}) do
			if UnitExists(unit) then units[#units + 1] = unit end
		end
		return units
	end

	function ns.HealthDebug()
		local combat = InCombatLockdown and InCombatLockdown()
		local units = Units(true)
		local usable, secret = 0, 0
		ns.Log("health", ("%s, %d units, issecretvalue %s"):format(combat and "in combat" or "out of combat",
			#units, issecretvalue and "exists" or "missing"))
		for i, unit in ipairs(units) do
			local health = Read(UnitHealth, unit)
			local max = Read(UnitHealthMax, unit)
			local missing = Read(UnitHealthMissing, unit)
			local percent = Read(UnitHealthPercent, unit)
			local role = Read(UnitGroupRolesAssigned, unit)
			local tank = Read(GetPartyAssignment, "MAINTANK", unit)
			local ok = Usable(health, max)
			if ok then usable = usable + 1 end
			if Secret(health) or Secret(max) then secret = secret + 1 end
			local line = ("%s (%s): health %s / %s, missing %s, percent %s, role %s, main tank %s,"
				.. " dead %s, online %s, in range %s, in sight %s, distance squared %s, position y %s, yards %s -> %s"):format(
				unit, Show(Read(UnitName, unit)), Show(health), Show(max), Show(missing), Show(percent),
				Show(role), Show(tank), Show(Read(UnitIsDeadOrGhost, unit)), Show(Read(UnitIsConnected, unit)),
				Show(Read(UnitInRange, unit)), Show(Read(UnitIsVisible, unit)), Show(Read(UnitDistanceSquared, unit)),
				Show(Read(UnitPosition, unit)),
				Show(ns.HealVisionDistance and ns.HealVisionDistance(unit)), ok and "sortable" or "NOT sortable")
			-- (Printed lines go in the log already.)
			if ns.HealVisionDebug then
				local ok, verdict = pcall(ns.HealVisionDebug, unit)
				line = line .. "; heal vision: " .. (ok and verdict or ("error " .. tostring(verdict)))
			end
			if i <= 10 then print("  " .. line) else ns.Log("health", line) end
		end
		if #units > 10 then print(("  ...and %d more in /cine log"):format(#units - 10)) end
		ns.Print(("health (%s): %d of %d sortable, %d secret. Run it %s too"):format(
			combat and "in combat" or "out of combat", usable, #units, secret,
			combat and "out of combat" or "in combat (hit a training dummy, in a group)"))
	end

	-- /cine debug healthfade [percent]: can a frame show only while someone's
	-- hurt, with the addon never knowing their health? A window with a row per
	-- group member: a plain bar and %, then two ways of fading a block by the
	-- game's own (secret) health percent - frame alpha from a number curve
	-- (blue), and texture colour from a colour curve (red). Both should be gone
	-- at full health and show below the percent (100: any damage).
	local window, alphaCurve, colorCurve
	local rows, failed = {}, {}
	local ROWS_MAX = 10

	local function Try(what, func, ...)
		local ok, err = pcall(func, ...)
		if not ok and not failed[what] then
			failed[what] = true
			ns.Print(("healthfade: %s failed: %s"):format(what, tostring(err)))
		end
		return ok
	end

	local function MakeCurves(percent)
		local at = math.min(percent / 100, 0.9995) -- (full is 1, so 100 means any damage)
		alphaCurve, colorCurve = nil, nil
		if not (C_CurveUtil and C_CurveUtil.CreateCurve) then
			ns.Print("healthfade: no C_CurveUtil on this client")
			return
		end
		Try("number curve", function()
			local curve = C_CurveUtil.CreateCurve()
			curve:SetType(Enum.LuaCurveType.Step)
			curve:AddPoint(0, 1)
			curve:AddPoint(at, 0)
			alphaCurve = curve
		end)
		Try("colour curve", function()
			local curve = C_CurveUtil.CreateColorCurve()
			curve:AddPoint(0, CreateColor(1, 0.2, 0.2, 1))
			curve:AddPoint(at - 0.0001, CreateColor(1, 0.2, 0.2, 1))
			curve:AddPoint(at, CreateColor(1, 0.2, 0.2, 0))
			curve:AddPoint(1, CreateColor(1, 0.2, 0.2, 0))
			colorCurve = curve
		end)
	end

	local function Row(i)
		if rows[i] then return rows[i] end
		local row = CreateFrame("Frame", nil, window)
		row:SetSize(300, 18)
		row:SetPoint("TOPLEFT", 8, -40 - (i - 1) * 20)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT")
		row.name:SetWidth(80)
		row.name:SetJustifyH("LEFT")
		row.bar = CreateFrame("StatusBar", nil, row)
		row.bar:SetSize(120, 14)
		row.bar:SetPoint("LEFT", 84, 0)
		row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		row.bar:SetStatusBarColor(0.1, 0.8, 0.1)
		local back = row.bar:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0.2, 0.2, 0.2, 0.8)
		row.text = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("CENTER")
		row.alpha = CreateFrame("Frame", nil, row)
		row.alpha:SetSize(40, 14)
		row.alpha:SetPoint("LEFT", 208, 0)
		local blue = row.alpha:CreateTexture(nil, "ARTWORK")
		blue:SetAllPoints()
		blue:SetColorTexture(0.2, 0.6, 1, 1)
		row.color = row:CreateTexture(nil, "ARTWORK")
		row.color:SetSize(40, 14)
		row.color:SetPoint("LEFT", 252, 0)
		row.color:SetColorTexture(1, 1, 1, 1)
		rows[i] = row
		return row
	end

	local function UpdateRow(row, unit)
		Try("name", row.name.SetText, row.name, (UnitName(unit)))
		Try("bar", function()
			row.bar:SetMinMaxValues(0, UnitHealthMax(unit))
			row.bar:SetValue(UnitHealth(unit))
		end)
		Try("percent text", function()
			row.text:SetFormattedText("%d%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
		end)
		if alphaCurve then
			Try("frame alpha", function() row.alpha:SetAlpha(UnitHealthPercent(unit, true, alphaCurve)) end)
		end
		if colorCurve then
			Try("texture colour", function()
				row.color:SetVertexColor(UnitHealthPercent(unit, true, colorCurve):GetRGBA())
			end)
		end
	end

	local function UpdateFade()
		local units = Units()
		for i = 1, ROWS_MAX do
			local unit = units[i]
			if unit then
				local row = Row(i)
				row:Show()
				UpdateRow(row, unit)
			elseif rows[i] then
				rows[i]:Hide()
			end
		end
		window:SetHeight(48 + math.min(#units, ROWS_MAX) * 20)
	end

	local function MakeWindow()
		window = CreateFrame("Frame", nil, UIParent)
		window:SetSize(316, 60)
		window:SetPoint("CENTER", 0, 200)
		window:SetFrameStrata("HIGH")
		window:SetMovable(true)
		window:EnableMouse(true)
		window:RegisterForDrag("LeftButton")
		window:SetScript("OnDragStart", window.StartMoving)
		window:SetScript("OnDragStop", window.StopMovingOrSizing)
		local back = window:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0, 0, 0, 0.75)
		window.title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		window.title:SetPoint("TOPLEFT", 8, -6)
		local function Head(text, x)
			local head = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			head:SetPoint("TOPLEFT", 8 + x, -24)
			head:SetText(text)
		end
		Head("name", 0)
		Head("health", 84)
		Head("alpha", 208)
		Head("colour", 252)
		local elapsed = 0
		window:SetScript("OnUpdate", function(_, delta)
			elapsed = elapsed + delta
			if elapsed < 0.2 then return end
			elapsed = 0
			UpdateFade()
		end)
	end

	function ns.HealthFadeDebug(arg)
		local percent = tonumber(arg)
		if window and window:IsShown() and not percent then
			window:Hide()
			ns.Print("healthfade: closed")
			return
		end
		percent = percent or 100
		wipe(failed)
		MakeCurves(percent)
		if not window then MakeWindow() end
		window.title:SetText(("Health fade test: shown below %d%%"):format(percent))
		window:Show()
		UpdateFade()
		ns.Print(("healthfade: the blue (frame alpha) and red (colour) blocks should be gone at full"
			.. " health and show below %d%%. Take some damage and watch. Drag to move, run again to close")
			:format(percent))
	end

	-- /cine debug damage [seconds]: does damage taken reach the addon? Listens
	-- to the portrait hit event for a while (15 seconds), then reads Blizzard's
	-- own damage meter, and says what's plain or secret. (Not the combat log:
	-- registering for it is blocked on WoW Forever, with the game's "blocked
	-- from an action" popup.)
	local probe

	-- (Printed after the command ends, so not caught for the log by itself.)
	local function Line(text)
		print(text)
		ns.Log("damage", text)
	end

	local function ReportMeter(combat)
		if not (C_DamageMeter and Enum.DamageMeterSessionType and Enum.DamageMeterType) then
			Line("  damage meter: no C_DamageMeter on this client")
			return
		end
		local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
			Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageTaken)
		local sources = ok and type(session) == "table" and session.combatSources
		if not ok then
			Line("  damage meter: error " .. tostring(session))
		elseif type(sources) ~= "table" or (issecrettable and issecrettable(sources)) then
			Line("  damage meter: damage taken list " .. (sources and "secret" or "missing"))
		else
			local count = 0
			pcall(function() count = #sources end)
			Line(("  damage meter (%s): %d in the damage taken list"):format(combat, count))
			for i = 1, math.min(count, 5) do
				local source = sources[i]
				Line(("    %d. %s: %s taken, class %s, spec icon %s"):format(i, Show(source.name),
					Show(source.totalAmount), Show(source.classFilename), Show(source.specIconID)))
			end
		end
	end

	function ns.DamageDebug(arg)
		local seconds = tonumber(arg) or 15
		probe = probe or CreateFrame("Frame")
		probe:UnregisterAllEvents()
		-- One sample per kind of unit (player, party, nameplate...) and action
		-- (WOUND, HEAL...): a healer needs the player's and party's to be plain.
		local count, samples, order = 0, {}, {}
		local ok, err = pcall(probe.RegisterEvent, probe, "UNIT_COMBAT")
		probe:SetScript("OnEvent", function(_, _, unit, action, _, amount)
			count = count + 1
			local kind = (Secret(unit) and "secret" or tostring(unit):gsub("%d+$", "")) .. " "
				.. (Secret(action) and "secret" or tostring(action))
			if samples[kind] or #order >= 12 then return end
			samples[kind] = ("%s (%s): amount %s"):format(Show(unit), Show(Read(UnitName, unit)), Show(amount))
			order[#order + 1] = kind
		end)
		ns.Print(("damage: listening %d seconds (%s): get hit, heal yourself, and in a group let others get hit"):format(seconds,
			InCombatLockdown() and "in combat" or "out of combat"))
		C_Timer.After(seconds, function()
			probe:UnregisterAllEvents()
			probe:SetScript("OnEvent", nil)
			local combat = InCombatLockdown() and "in combat" or "out of combat"
			Line(("  hit event: %s, %d events"):format(ok and "registered" or ("refused: " .. tostring(err)), count))
			for _, kind in ipairs(order) do
				Line(("    %s: %s"):format(kind, samples[kind]))
			end
			Line("  combat log: not tried (blocked on WoW Forever)")
			ReportMeter(combat)
			ns.Print("damage: done (" .. combat .. ")")
		end)
	end
end

-- Unit frames -----------------------------------------------------------------

-- /cine debug unitframes: every part of the player, pet, target and focus frames, as a
-- tree in the log (field name, type, shown, size, texture or atlas, text), to
-- find which pieces are the portrait, level, name and borders on clients
-- whose frames are laid out their own way (WoW Forever's).
do
	local function Safe(fn, ...)
		local ok, a, b = pcall(fn, ...)
		if not ok or (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then
			return nil
		end
		return a, b
	end

	-- The key its parent keeps it under (frame.healthbar and the like).
	local function FieldName(parent, object)
		for key, value in pairs(parent) do
			if value == object and type(key) == "string" then
				return key
			end
		end
	end

	local managedGroup = {} -- frame -> its faded group, while a walk logs

	local function Describe(object, parent)
		local name = Safe(object.GetName, object)
		local field = parent and FieldName(parent, object)
		local kind = Safe(object.GetObjectType, object) or "?"
		local w, h = Safe(object.GetSize, object)
		local parts = { ("%s%s %s"):format(name or "-", field and (" ." .. field) or "", kind) }
		parts[#parts + 1] = Safe(object.IsShown, object) and "shown" or "hidden"
		if w then
			parts[#parts + 1] = ("%.0fx%.0f"):format(w, h)
		end
		local alpha = Safe(object.GetAlpha, object)
		if alpha and alpha < 1 then
			parts[#parts + 1] = ("alpha %.2f"):format(alpha)
		end
		if object.GetAtlas then
			local atlas = Safe(object.GetAtlas, object)
			if atlas then
				parts[#parts + 1] = "atlas " .. atlas
			end
		end
		if object.GetTexture then
			local texture = Safe(object.GetTexture, object)
			if texture then
				parts[#parts + 1] = "texture " .. tostring(texture)
			end
		end
		if object.GetText then
			local text = Safe(object.GetText, object)
			if type(text) == "string" and text ~= "" then
				parts[#parts + 1] = ("text %q"):format(text)
			end
		end
		if managedGroup[object] then
			parts[#parts + 1] = "FADED AS " .. managedGroup[object]
		end
		if ns.unitPartsHidden and ns.unitPartsHidden[object] then
			parts[#parts + 1] = "HELD HIDDEN"
		end
		-- (A playing alpha animation outdoes the alpha we set.)
		if object.GetAnimationGroups then
			for _, group in ipairs(Safe(function() return { object:GetAnimationGroups() } end) or {}) do
				if Safe(group.IsPlaying, group) then
					parts[#parts + 1] = "anim playing"
					break
				end
			end
		end
		return table.concat(parts, ", ")
	end

	local function Walk(object, parent, depth, count, category, limit)
		category, limit = category or "unitframes", limit or 400
		if count[1] > limit then
			return
		end
		count[1] = count[1] + 1
		ns.Log(category, ("%s%s"):format(("  "):rep(depth), Describe(object, parent)))
		if depth >= 6 then
			return
		end
		if object.GetRegions then
			for _, region in ipairs(Safe(function() return { object:GetRegions() } end) or {}) do
				count[1] = count[1] + 1
				ns.Log(category, ("%s%s"):format(("  "):rep(depth + 1), Describe(region, object)))
			end
		end
		if object.GetChildren then
			for _, child in ipairs(Safe(function() return { object:GetChildren() } end) or {}) do
				Walk(child, object, depth + 1, count, category, limit)
			end
		end
	end

	-- /cine debug raidparts: every part of the party and raid frames, each
	-- marked with the group it's faded as (none: Cinematic doesn't fade it on
	-- its own), to find icons a row should hide but doesn't. Shown buttons
	-- on a member's frame that aren't faded are printed too.
	function ns.LogRaidFrames()
		wipe(managedGroup)
		for _, entry in ipairs(ns.managed) do
			managedGroup[entry.frame] = entry.group
		end
		local total, loose = 0, 0
		for _, name in ipairs({ "CompactPartyFrame", "CompactRaidFrameContainer" }) do
			local holder = _G[name]
			if holder and not Safe(holder.IsForbidden, holder) then
				local count = { 0 }
				Walk(holder, nil, 0, count, "raidparts", 1500)
				total = total + count[1]
				for _, member in ipairs({ holder:GetChildren() }) do
					-- Its aura icons, wherever they're parented (on WoW Forever
					-- they aren't its children): each field named like one.
					local memberName = Safe(member.GetName, member) or "?"
					for key, value in pairs(member) do
						local lower = type(key) == "string" and key:lower()
						if lower and (lower:find("aura") or lower:find("buff")) then
							if type(value) == "table" and value.GetObjectType then
								ns.Log("raidparts", ("%s.%s: %s, parent %s"):format(memberName, key,
									Describe(value), Safe(function() return value:GetParent():GetDebugName() end) or "?"))
							elseif type(value) == "table" then
								local n = 0
								for index, item in pairs(value) do
									n = n + 1
									local text = type(item) == "table" and item.GetObjectType and ("%s, parent %s"):format(
										Describe(item), Safe(function() return item:GetParent():GetDebugName() end) or "?")
										or type(item)
									ns.Log("raidparts", ("%s.%s[%s]: %s"):format(memberName, key, tostring(index), text))
								end
								ns.Log("raidparts", ("%s.%s: table, %d entries"):format(memberName, key, n))
								if Safe(member.IsShown, member) then
									ns.Print(("%s.%s: %d entries"):format(memberName, key, n))
								end
							else
								ns.Log("raidparts", ("%s.%s = %s"):format(memberName, key, tostring(value)))
							end
						end
					end
					for _, child in ipairs(Safe(function() return { member:GetChildren() } end) or {}) do
						if not managedGroup[child] and Safe(child.IsShown, child)
							and Safe(child.GetObjectType, child) == "Button" then
							loose = loose + 1
							if loose <= 8 then
								ns.Print("not faded: " .. Describe(child, member))
							end
						end
					end
				end
			else
				ns.Log("raidparts", name .. ": not on this client (or forbidden)")
			end
		end
		-- Every frame anchored to a member's frame, whatever its parent: newer
		-- clients' aura icons sit outside the member (no buffFrames list).
		local members = {}
		for _, name in ipairs({ "CompactPartyFrame", "CompactRaidFrameContainer" }) do
			local holder = _G[name]
			if holder and not Safe(holder.IsForbidden, holder) then
				for _, member in ipairs({ holder:GetChildren() }) do
					members[member] = Safe(member.GetName, member) or "?"
				end
			end
		end
		local anchored = 0
		local frame = EnumerateFrames()
		while frame do
			for i = 1, (Safe(frame.GetNumPoints, frame) or 0) do
				local relativeTo = select(2, Safe(function() return nil, select(2, frame:GetPoint(i)) end))
				if relativeTo and members[relativeTo] then
					anchored = anchored + 1
					ns.Log("raidparts", ("anchored to %s: %s, parent %s, strata %s"):format(members[relativeTo],
						Describe(frame), Safe(function() return frame:GetParent():GetDebugName() end) or "?",
						Safe(frame.GetFrameStrata, frame) or "?"))
					break
				end
			end
			frame = EnumerateFrames(frame)
		end
		for _, fn in ipairs({ "CompactUnitFrame_UtilSetBuff", "CompactUnitFrame_UtilSetDebuff",
			"CompactUnitFrame_UpdateAuras", "CompactUnitFrame_UpdateBuffs" }) do
			ns.Log("raidparts", ("%s: %s"):format(fn, type(_G[fn])))
		end
		local focus = GetMouseFoci and GetMouseFoci()[1]
		if focus then
			ns.Log("raidparts", ("under the mouse: %s, debug name %s, parent %s"):format(Describe(focus),
				Safe(focus.GetDebugName, focus) or "?",
				Safe(function() return focus:GetParent():GetDebugName() end) or "?"))
		end
		wipe(managedGroup)
		ns.Print(("raidparts: %d frames anchored to members (hover an icon while running it to log it too)"):format(anchored))
		ns.Print(("raidparts: logged %d parts, %d shown buttons not faded. /reload to write the log"):format(total, loose))
	end

	function ns.LogUnitFrames()
		local total = 0
		for _, name in ipairs({ "PlayerFrame", "PetFrame", "TargetFrame", "FocusFrame" }) do
			local frame = _G[name]
			if frame then
				local count = { 0 }
				Walk(frame, nil, 0, count)
				total = total + count[1]
			else
				ns.Log("unitframes", name .. ": not on this client")
			end
		end
		for _, line in ipairs(ns.UnitPartDebug and ns.UnitPartDebug("CastBar") or {}) do
			ns.Print(line)
			ns.Log("unitframes", line)
		end
		ns.Print(("unitframes: logged %d parts of the player, pet, target and focus frames (have a target). /reload to write the log"):format(total))
	end
end

-- Minimap nodes (/cine debug nodes) -------------------------------------------
-- Test for showing the minimap when a herb or vein is on it: sweep a pretend
-- mouse over the minimap (Minimap:UpdateMouseoverAtPoint) and print the names
-- its tooltip would show there (C_TooltipInfo.GetMinimapMouseover). Mainly to
-- find out whether the tracking dots still answer while CineMode has the
-- minimap faded (shrunk and moved off the screen). With seconds, it sweeps once
-- a second for that long and prints only when what it finds changes.
do
	local STEP = 10 -- minimap units between two points of the grid
	local watcher, untilTime, lastFound
	local growing = false -- /cine debug nodes grow: each sweep grows the faded minimap first
	local showRaw = false -- /cine debug nodes raw: each name's line as the game wrote it

	-- /cine debug nodes park: while watching, the faded minimap stays full size
	-- (off the screen, where it's moved while faded) instead of shrinking, and
	-- is swept there. Does the game keep adding tracking dots to it then?
	local function Park(on)
		ns.parkMinimapFullSize = on or nil
		for _, entry in ipairs(ns.managed or {}) do
			if entry.frame == Minimap and entry.shrunk then
				Minimap:SetScale(on and (entry.savedScale or 1) or ns.SHRUNK_SCALE)
			end
		end
	end

	-- /cine debug nodes stay: while watching, the faded minimap isn't shrunk
	-- or moved at all: full size in its place at alpha 0 (its player arrow
	-- shows). Does the game keep adding tracking dots to it then? (Off, it's
	-- shrunk again on the next tick.)
	-- (Its icons are hidden meanwhile, as for the option: NodeSweep.lua.)
	local function Stay(on)
		ns.minimapStayFullSize = on or nil
		if not on then return end
		for _, entry in ipairs(ns.managed or {}) do
			if entry.frame == Minimap and entry.shrunk then
				Minimap:SetScale(entry.savedScale or 1)
				ns.UnparkShrunk(entry)
				entry.shrunk = false
			end
		end
	end
	local watched -- while watching: every line printed, for the copy window at the end

	-- Names of the tracking that's on (Find Herbs, Find Minerals...).
	local function Tracking()
		local list = {}
		if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then
			return "no tracking API"
		end
		local ok, count = pcall(C_Minimap.GetNumTrackingTypes)
		for i = 1, ok and type(count) == "number" and count or 0 do
			local okInfo, info, _, active = pcall(C_Minimap.GetTrackingInfo, i)
			if okInfo and type(info) == "table" then
				if info.active == true and type(info.name) == "string" then list[#list + 1] = info.name end
			elseif okInfo and active == true and type(info) == "string" then
				list[#list + 1] = info
			end
		end
		return #list > 0 and table.concat(list, ", ") or "none"
	end

	-- The sweep is NodeSweep.lua's, every name kept (not just herbs and veins).
	local refreshing = false -- /cine debug nodes update: Minimap:UpdateBlips before each sweep
	local function Sweep(grow)
		return ns.SweepMinimap(STEP, grow, nil, refreshing)
	end

	local function State()
		local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
		local x, y = Minimap:GetCenter()
		local onScreen = x and y and x > 0 and y > 0 and x < screenW and y < screenH
		return ("minimap visible %s, alpha %.2f, scale %.3f, %s; %s; tracking: %s"):format(
			tostring(ns.Flag(Minimap:IsVisible())), Minimap:GetEffectiveAlpha(), Minimap:GetEffectiveScale(),
			onScreen and "on screen" or "off screen", IsIndoors and IsIndoors() and "indoors" or "outdoors", Tracking())
	end

	local function Describe(found)
		local names = {}
		for name, entry in pairs(found) do
			local kind = ns.NodeKind(name)
			-- (raw: the game's line with its codes showing, and its colour.)
			local rawText = showRaw and entry.raw and (", raw \"" .. entry.raw:gsub("|", "||"):gsub("\n", "\\n")
				.. "\" colour " .. tostring(entry.color)) or ""
			names[#names + 1] = ("%s (%d%s%s%s)"):format(name, entry.points, entry.gray and ", gray" or "",
				kind and (", " .. kind) or "", rawText)
		end
		table.sort(names)
		return #names > 0 and table.concat(names, "; ") or "nothing"
	end

	local function Report(onlyChanges)
		local found, probes, grown = Sweep(growing and not ns.parkMinimapFullSize)
		local text = (grown and "(grown for the sweep) " or "")
			.. (found and Describe(found) or ("can't sweep: " .. probes))
		-- (the minimap fading or coming back counts as a change too)
		local key = text .. (Minimap:GetEffectiveAlpha() < 0.5 and " faded" or " shown")
		if onlyChanges and key == lastFound then return end
		lastFound = key
		local first = ("nodes: %s"):format(text)
		local second = "  " .. State() .. (found and (", %d points tried"):format(probes) or "")
		ns.Print(first)
		print(second)
		ns.Log("nodes", second) -- (only ns.Print's lines reach the log by themselves)
		if watched then
			watched[#watched + 1] = date("%H:%M:%S ") .. first
			watched[#watched + 1] = second
		end
	end

	-- The watch is over: everything it printed opens in the copy window.
	local function Done(why)
		watcher:Hide()
		if ns.parkMinimapFullSize or ns.minimapStayFullSize then
			Park(false)
			Stay(false)
			ns.Print("nodes: the faded minimap shrinks again")
		end
		ns.Print("nodes: " .. why)
		local lines = watched
		watched = nil
		if lines and #lines > 0 then
			ShowText("/cine debug nodes: press Ctrl+C to copy",
				("/cine debug nodes (Cinematic %s)\n%s"):format(Version(), table.concat(lines, "\n")))
		end
	end

	function ns.NodesDebug(args)
		args = args or ""
		local seconds = tonumber(args:match("%d+"))
		growing = args:find("grow") ~= nil
		showRaw = args:find("raw") ~= nil
		refreshing = args:find("update") ~= nil
		if (args:find("park") or args:find("stay")) and not seconds then seconds = 60 end
		lastFound = nil
		if not seconds and watcher and watcher:IsShown() then
			Done("stopped watching")
			return
		end
		watched = seconds and {} or nil
		if args:find("park") then
			Park(true)
			ns.Print("nodes: the faded minimap stays full size off the screen while this watches")
		elseif args:find("stay") then
			Stay(true)
			ns.Print("nodes: the faded minimap stays full size in its place (alpha 0, icons hidden) while this watches")
		end
		Report(false)
		if not seconds then return end
		watcher = watcher or CreateFrame("Frame")
		untilTime = GetTime() + math.min(seconds, 600)
		local wait = 1
		watcher:SetScript("OnUpdate", function(_, elapsed)
			wait = wait - elapsed
			if wait > 0 then return end
			wait = 1
			if GetTime() >= untilTime then
				Done("done watching")
				return
			end
			Report(true)
		end)
		watcher:Show()
		ns.Print(("nodes: sweeping once a second for %d seconds, printing when it changes"):format(math.min(seconds, 600)))
	end
end

-- Group debuffs (/cine debug auras) -------------------------------------------
-- For Heal Vision's debuff options: where and when this client lets addons
-- see the group's debuffs, which ways of asking work (by index, by slot, by
-- aura instance from UNIT_AURA, with which filters), what comes back secret,
-- and whether the raid frames' own debuff icons can be looked at. The first
-- run starts watching UNIT_AURA (for the aura instances it hands out); run it
-- in and out of combat, in the open world, dungeons, raids and battlegrounds.
do
	local FILTERS = { "HARMFUL", "HARMFUL|RAID", "HARMFUL|RAID_PLAYER_DISPELLABLE", "HARMFUL|PLAYER" }
	local DETAIL_UNITS = 6 -- members logged in full; the rest get a line each
	local seen = {}        -- unit -> { aura instance ID -> true } from UNIT_AURA
	local events = {}      -- unit -> { events, secret answers, plain instance IDs }
	local latest = {}      -- unit -> the last 3 auras UNIT_AURA added, described
	local watcher

	local function Secret(value)
		return issecretvalue ~= nil and issecretvalue(value) == true
	end

	local function Show(value)
		if Secret(value) then return "secret" end
		if type(value) == "number" then return ("%.1f"):format(value) end
		return tostring(value)
	end

	-- A call's answer: true and the value, or false and "no API" / "error <why>".
	local function Try(func, ...)
		if not func then return false, "no API" end
		local ok, value = pcall(func, ...)
		if not ok then return false, "error " .. tostring(value):gsub("^.-:%d+: ", ""):sub(1, 70) end
		return true, value
	end

	-- An aura's fields that matter (any of them may be secret).
	local function Describe(data)
		if Secret(data) then return "secret table" end
		if type(data) ~= "table" then return Show(data) end
		local parts = {}
		for _, key in ipairs({ "name", "spellId", "duration", "expirationTime", "dispelName", "isHarmful",
			"isRaid", "auraInstanceID", "sourceUnit" }) do
			local ok, value = pcall(function() return data[key] end)
			parts[#parts + 1] = key .. " " .. (ok and Show(value) or "?")
		end
		return table.concat(parts, ", ")
	end

	local function Watch()
		if watcher then return end
		watcher = CreateFrame("Frame")
		if not pcall(watcher.RegisterEvent, watcher, "UNIT_AURA") then return end
		watcher:SetScript("OnEvent", function(_, _, unit, info)
			if Secret(unit) or type(unit) ~= "string" then return end
			local counts = events[unit] or { 0, 0, 0 }
			events[unit] = counts
			counts[1] = counts[1] + 1
			if Secret(info) then
				counts[2] = counts[2] + 1
				return
			end
			if type(info) ~= "table" then return end
			local ids = seen[unit] or {}
			seen[unit] = ids
			pcall(function()
				for _, aura in ipairs(info.addedAuras or {}) do
					local id = aura.auraInstanceID
					if Secret(id) then
						counts[2] = counts[2] + 1
					elseif id then
						ids[id] = true
						counts[3] = counts[3] + 1
					end
					-- What the event itself hands over (the aura may be gone by the
					-- next run), and whether the filters answer about it right then.
					local filtered = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
					local _, outAny = Try(filtered, unit, id, "HARMFUL")
					local _, outRaid = Try(filtered, unit, id, "HARMFUL|RAID")
					local _, outDispel = Try(filtered, unit, id, "HARMFUL|RAID_PLAYER_DISPELLABLE")
					local list = latest[unit] or {}
					latest[unit] = list
					table.insert(list, 1, ("%s %s: %s; filtered out: HARMFUL %s, RAID %s, DISPELLABLE %s"):format(
						date("%H:%M:%S"), InCombatLockdown() and "in combat" or "out of combat", Describe(aura),
						Show(outAny), Show(outRaid), Show(outDispel)))
					list[4] = nil
				end
				for _, id in ipairs(info.removedAuraInstanceIDs or {}) do
					if not Secret(id) then ids[id] = nil end
				end
			end)
		end)
	end

	local function Units()
		local units = { "player" }
		local count = GetNumGroupMembers and GetNumGroupMembers() or 0
		if IsInRaid and IsInRaid() then
			units = {}
			for i = 1, count do units[#units + 1] = "raid" .. i end
		else
			for i = 1, math.max(0, count - 1) do units[#units + 1] = "party" .. i end
		end
		if UnitExists("target") and not UnitCanAttack("player", "target") then units[#units + 1] = "target" end
		return units
	end

	-- Every function in a table whose name has one of the words (for spotting new APIs).
	local function Names(where, words)
		local found = {}
		for key, value in pairs(where or {}) do
			if type(key) == "string" and type(value) == "function" then
				local lower = key:lower()
				for _, word in ipairs(words) do
					if lower:find(word, 1, true) then
						found[#found + 1] = key
						break
					end
				end
			end
		end
		table.sort(found)
		return #found > 0 and table.concat(found, " ") or "none"
	end

	-- The raid frames showing this unit: are their debuff icons and dispel
	-- highlight forbidden, and can "shown" be read?
	local function FrameLines(unit)
		local lines = {}
		local function Part(parts, label, part)
			if not part then return end
			local okF, isForbidden = pcall(part.IsForbidden, part)
			if not okF then
				parts[#parts + 1] = label .. " ?"
			elseif isForbidden then
				parts[#parts + 1] = label .. " forbidden"
			else
				local okS, shown = pcall(part.IsShown, part)
				local okA, alpha = pcall(part.GetAlpha, part)
				parts[#parts + 1] = ("%s shown %s alpha %s"):format(label, okS and Show(shown) or "error",
					okA and Show(alpha) or "error")
			end
		end
		local function Look(frame)
			if not frame then return end
			local okForbidden, forbidden = pcall(frame.IsForbidden, frame)
			if not okForbidden or forbidden then return end
			local okUnit, frameUnit = pcall(function() return frame.unit end)
			if not okUnit or Secret(frameUnit) or frameUnit ~= unit then return end
			local parts = {}
			for i, icon in ipairs(frame.debuffFrames or {}) do Part(parts, "debuff" .. i, icon) end
			for i, icon in ipairs(frame.dispelDebuffFrames or {}) do Part(parts, "dispel" .. i, icon) end
			Part(parts, "DispelOverlay", frame.DispelOverlay)
			Part(parts, "dispelHighlight", frame.dispelHighlight)
			lines[#lines + 1] = ("%s: %s"):format(tostring(frame:GetName()),
				#parts > 0 and table.concat(parts, "; ") or "no debuff parts")
		end
		for i = 1, 5 do Look(_G["CompactPartyFrameMember" .. i]) end
		for i = 1, 40 do Look(_G["CompactRaidFrame" .. i]) end
		for g = 1, 8 do
			for i = 1, 5 do Look(_G["CompactRaidGroup" .. g .. "Member" .. i]) end
		end
		return lines
	end

	local function Log(text)
		ns.Log("auras", text)
	end

	-- One member in full: other ways of asking, aura instances, their frames.
	local function Detail(unit)
		local _, slots = Try(C_UnitAuras and C_UnitAuras.GetAuraSlots, unit, "HARMFUL")
		local _, list = Try(C_UnitAuras and C_UnitAuras.GetUnitAuras, unit, "HARMFUL")
		local _, ids = Try(C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs, unit, "HARMFUL")
		Log(("%s GetAuraSlots %s, GetUnitAuras %s, GetUnitAuraInstanceIDs %s"):format(unit, Show(slots),
			type(list) == "table" and not Secret(list) and ("x" .. #list) or Show(list),
			type(ids) == "table" and not Secret(ids) and ("x" .. #ids) or Show(ids)))
		-- Aura instances (from UNIT_AURA, or the list just read): can they be
		-- asked about one by one?
		local known = {}
		for id in pairs(seen[unit] or {}) do known[id] = true end
		if type(ids) == "table" and not Secret(ids) then
			for _, id in ipairs(ids) do
				if not Secret(id) then known[id] = true end
			end
		end
		local asked = 0
		for id in pairs(known) do
			if asked >= 4 then break end
			asked = asked + 1
			local _, data = Try(C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
			local filtered = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
			local _, outAny = Try(filtered, unit, id, "HARMFUL")
			local _, outDispel = Try(filtered, unit, id, "HARMFUL|RAID_PLAYER_DISPELLABLE")
			local _, outRaid = Try(filtered, unit, id, "HARMFUL|RAID")
			local _, duration = Try(C_UnitAuras and C_UnitAuras.GetAuraDuration, unit, id)
			local secrets = _G.C_Secrets
			local _, secret = Try(secrets and secrets.ShouldUnitAuraInstanceBeSecret, unit, id)
			Log(("%s instance %s (secret: %s): %s; filtered out: HARMFUL %s, RAID %s, DISPELLABLE %s; GetAuraDuration %s"):format(
				unit, Show(id), Show(secret), Describe(data), Show(outAny), Show(outRaid), Show(outDispel), Show(duration)))
		end
		local counts = events[unit] or { 0, 0, 0 }
		Log(("%s UNIT_AURA since first run: %d events, %d secret, %d plain instance IDs"):format(
			unit, counts[1], counts[2], counts[3]))
		for _, line in ipairs(latest[unit] or {}) do Log(unit .. " UNIT_AURA added at " .. line) end
		for _, line in ipairs(FrameLines(unit)) do Log(unit .. " frame " .. line) end
		if ns.HealVisionDebug then
			local ok, verdict = pcall(ns.HealVisionDebug, unit)
			Log(unit .. " heal vision: " .. (ok and verdict or ("error " .. tostring(verdict))))
		end
		if ns.HealVisionDebuffs then
			local ok, verdict = pcall(ns.HealVisionDebuffs, unit)
			Log(unit .. " heal vision debuff check (short ones only): " .. (ok and verdict or ("error " .. tostring(verdict))))
		end
	end

	function ns.AurasDebug()
		local firstRun = not watcher
		Watch()
		local combat = InCombatLockdown and InCombatLockdown()
		local _, inside, kind = pcall(IsInInstance)
		local units = Units()
		Log(("--- %s, %s (%s), zone %s, %d units"):format(combat and "IN COMBAT" or "out of combat",
			inside and "instance" or "open world", Show(kind), Show(GetRealZoneText and GetRealZoneText()), #units))
		if firstRun then
			Log("C_UnitAuras: " .. Names(C_UnitAuras, { "" }))
			Log("C_Secrets: " .. Names(_G.C_Secrets, { "" }))
			Log("globals: " .. Names(_G, { "dispel", "debuff", "unitaura" }))
		end
		-- Does the game say up front whether auras are secret?
		local someone = units[2] or "player"
		for key, func in pairs(_G.C_Secrets or {}) do
			if type(key) == "string" and type(func) == "function" and key:lower():find("aura") then
				local _, plain = Try(func)
				local _, forUnit = Try(func, someone)
				Log(("C_Secrets.%s() %s, (%s) %s"):format(key, Show(plain), someone, Show(forUnit)))
			end
		end
		local answered, failed = 0, 0
		for n, unit in ipairs(units) do
			local summary = {}
			for _, filter in ipairs(FILTERS) do
				local ok, data = Try(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex, unit, 1, filter)
				-- (How many by index, up to 40: stops at the first nil or secret.)
				local count = 0
				if ok and type(data) == "table" and not Secret(data) then
					for i = 1, 40 do
						local okI, more = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
						if not okI or more == nil or Secret(more) then break end
						count = i
					end
				end
				local short = filter:gsub("^HARMFUL|?", "")
				summary[#summary + 1] = ("%s %s"):format(short == "" and "any" or short,
					not ok and "ERR" or data == nil and "none" or Secret(data) and "secret" or ("x" .. count))
				if n <= DETAIL_UNITS then
					-- (Shown with + for |: the log window takes |R for a colour code.)
					local secrets = _G.C_Secrets
					local _, secret = Try(secrets and secrets.ShouldUnitAuraIndexBeSecret, unit, 1, filter)
					Log(("%s %s [%s] #1 (secret: %s): %s"):format(unit, Show(UnitName(unit)), (filter:gsub("|", "+")),
						Show(secret), ok and Describe(data) or data))
				end
				if ok then answered = answered + 1 else failed = failed + 1 end
			end
			if n <= DETAIL_UNITS then Detail(unit) end
			print(("  %s %s: %s"):format(unit, Show(UnitName(unit)), table.concat(summary, ", ")))
		end
		ns.Print(("auras (%s, %s): %d asks answered, %d errored. Details in /cine log"):format(
			combat and "in combat" or "out of combat", inside and Show(kind) or "open world", answered, failed))
	end
end

-- Combat log tab (/cine debug combatlog) --------------------------------------
-- The combat log event is blocked on WoW Forever, but Blizzard still writes its
-- lines into the Combat Log chat tab. Can we read who got a debuff there in
-- combat? Logs the lines it sees (the first LINES_MAX), plus how many were
-- secret or plain, until switched off or /reload (then read the log).
do
	local LINES_MAX = 300 -- aura lines logged per session, so the log keeps the rest
	local on, hooked
	local counts = { secret = 0, plain = 0, aura = 0, secretCombat = 0, plainCombat = 0, token = 0 }

	local function Summary()
		return ("combat log lines kept by the tab: %d plain (%d in combat), %d secret (%d in combat), %d handed over as |K tokens, %d logged"):format(
			counts.plain, counts.plainCombat, counts.secret, counts.secretCombat, counts.token, counts.aura)
	end

	-- Forever hands most lines over as a bare |Ky123|k token (and some don't
	-- go through AddMessage at all), but the tab keeps the filled-in text: the
	-- tab's own list is read a few times a second instead (Poll, below).
	local function OnLine(_, text)
		if on and type(text) == "string" and not (issecretvalue and issecretvalue(text))
			and text:find("^|K[^|]*|k$") then
			counts.token = counts.token + 1
		end
	end

	local function OnStored(stored)
		local combat = InCombatLockdown()
		if issecretvalue and issecretvalue(stored) then
			counts.secret = counts.secret + 1
			if combat then counts.secretCombat = counts.secretCombat + 1 end
			if counts.secret == 1 then
				ns.Log("combatlog", ("first secret line (%s)"):format(combat and "in combat" or "out of combat"))
			end
			return
		end
		if type(stored) ~= "string" then return end
		counts.plain = counts.plain + 1
		if combat then counts.plainCombat = counts.plainCombat + 1 end
		if counts.aura < LINES_MAX then
			counts.aura = counts.aura + 1
			ns.Log("combatlog", (combat and "IN COMBAT " or "") .. stored)
		end
		-- Every so often, so a /reload mid-dungeon still leaves the totals.
		if (counts.plain + counts.secret) % 200 == 0 then ns.Log("combatlog", Summary()) end
	end

	-- The lines added since the last look: the tab's list stops growing once
	-- full, so it goes back from the newest to the last line already seen.
	local lastSeen, lastCount = nil, 0
	local function Poll(frame)
		if not on then return end
		local okN, count = pcall(frame.GetNumMessages, frame)
		if not okN or type(count) ~= "number" or count == 0 then return end
		local new = {}
		for i = count, math.max(1, count - 60), -1 do
			local ok, text = pcall(function() return (frame:GetMessageInfo(i)) end)
			if not ok then break end
			local plain = not (issecretvalue and issecretvalue(text))
			if plain and lastSeen ~= nil and text == lastSeen then break end
			if lastSeen == nil and i <= lastCount then break end
			new[#new + 1] = text
		end
		local okL, newest = pcall(function() return (frame:GetMessageInfo(count)) end)
		lastSeen = okL and not (issecretvalue and issecretvalue(newest)) and newest or nil
		lastCount = count
		for i = #new, 1, -1 do OnStored(new[i]) end
	end

	-- resume: turning back on at load because it was left on (stays on until
	-- the command is run again).
	function ns.CombatLogDebug(resume)
		local frame = _G.COMBATLOG or _G.ChatFrame2
		if not frame then
			ns.Print("combatlog: no Combat Log chat frame on this client")
			return
		end
		on = resume or not on
		ns.db.debugCombatLog = on or nil
		if on and not hooked then
			hooksecurefunc(frame, "AddMessage", OnLine)
			-- (Skip what's already in the tab from before.)
			local okN, count = pcall(frame.GetNumMessages, frame)
			lastCount = okN and type(count) == "number" and count or 0
			local okL, newest = pcall(function() return (frame:GetMessageInfo(lastCount)) end)
			lastSeen = okL and not (issecretvalue and issecretvalue(newest)) and newest or nil
			C_Timer.NewTicker(0.25, function() Poll(frame) end)
			-- The totals, when a /reload or logout saves the log.
			local saver = CreateFrame("Frame")
			saver:RegisterEvent("PLAYER_LOGOUT")
			saver:SetScript("OnEvent", function()
				if on then ns.Log("combatlog", "at reload: " .. Summary()) end
			end)
			hooked = true
		end
		ns.Log("combatlog", (on and "watching " or "stopped, ") .. tostring(frame:GetName()) .. ". " .. Summary())
		ns.Print(on and "combatlog: watching the Combat Log tab, after reloads too, until you run it again"
			or ("combatlog: stopped. " .. Summary()))
	end
end
