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

	local addons, overlapping = {}, {}
	if NumAddOns and AddOnInfo and IsLoaded then
		for i = 1, NumAddOns() do
			local name = AddOnInfo(i)
			if name and name ~= ADDON_NAME and IsLoaded(i) then
				addons[#addons + 1] = name
			end
		end
	end
	for _, name in ipairs(OVERLAPPING) do
		if IsLoaded and IsLoaded(name) then
			overlapping[#overlapping + 1] = name
		end
	end
	if #overlapping > 0 then
		add("may overlap: " .. table.concat(overlapping, ", "))
	end
	table.sort(addons)
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
		ShowText(("%s: press Ctrl+C to copy"):format(command),
			("%s (Cinematic %s)\n%s"):format(command, Version(), table.concat(lines, "\n")))
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

	local function Units()
		local units = { "player" }
		local count = GetNumGroupMembers and GetNumGroupMembers() or 0
		if IsInRaid and IsInRaid() then
			units = {}
			for i = 1, count do units[#units + 1] = "raid" .. i end
		else
			for i = 1, math.max(0, count - 1) do units[#units + 1] = "party" .. i end
		end
		for _, unit in ipairs({ "target", "focus", "mouseover" }) do
			if UnitExists(unit) then units[#units + 1] = unit end
		end
		return units
	end

	function ns.HealthDebug()
		local combat = InCombatLockdown and InCombatLockdown()
		local units = Units()
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
			local line = ("%s (%s): health %s / %s, missing %s, percent %s, role %s, main tank %s -> %s"):format(
				unit, Show(Read(UnitName, unit)), Show(health), Show(max), Show(missing), Show(percent),
				Show(role), Show(tank), ok and "sortable" or "NOT sortable")
			-- (Printed lines go in the log already.)
			if i <= 10 then print("  " .. line) else ns.Log("health", line) end
		end
		if #units > 10 then print(("  ...and %d more in /cine log"):format(#units - 10)) end
		ns.Print(("health (%s): %d of %d sortable, %d secret. Run it %s too"):format(
			combat and "in combat" or "out of combat", usable, #units, secret,
			combat and "out of combat" or "in combat (hit a training dummy, in a group)"))
	end
end

-- Unit frames -----------------------------------------------------------------

-- /cine debug unitframes: every part of the player and target frames, as a
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
		return table.concat(parts, ", ")
	end

	local function Walk(object, parent, depth, count)
		if count[1] > 400 then
			return
		end
		count[1] = count[1] + 1
		ns.Log("unitframes", ("%s%s"):format(("  "):rep(depth), Describe(object, parent)))
		if depth >= 6 then
			return
		end
		if object.GetRegions then
			for _, region in ipairs(Safe(function() return { object:GetRegions() } end) or {}) do
				count[1] = count[1] + 1
				ns.Log("unitframes", ("%s%s"):format(("  "):rep(depth + 1), Describe(region, object)))
			end
		end
		if object.GetChildren then
			for _, child in ipairs(Safe(function() return { object:GetChildren() } end) or {}) do
				Walk(child, object, depth + 1, count)
			end
		end
	end

	function ns.LogUnitFrames()
		local total = 0
		for _, name in ipairs({ "PlayerFrame", "TargetFrame" }) do
			local frame = _G[name]
			if frame then
				local count = { 0 }
				Walk(frame, nil, 0, count)
				total = total + count[1]
			else
				ns.Log("unitframes", name .. ": not on this client")
			end
		end
		ns.Print(("unitframes: logged %d parts of the player and target frames (have a target). /reload to write the log"):format(total))
	end
end
