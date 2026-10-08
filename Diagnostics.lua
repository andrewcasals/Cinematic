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

local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
local NumAddOns = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
local AddOnInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo

local function Plain(text)
	return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function ns.Log(category, text)
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
	title:SetText("Cinematic log: press Ctrl+C to copy, then paste it into your bug report")

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

function ns.ShowLog()
	if not window then
		CreateWindow()
	end
	local log = ns.db.log or {}
	window.text = ("%s\n\n--- log (%d lines, newest last) ---\n%s"):format(Summary(), #log,
		table.concat(log, "\n"))
	window:Show()
	window.box:SetText(window.text)
	window.box:SetFocus()
	window.box:HighlightText()
end

function ns.ClearLog()
	ns.db.log = {}
	ns.Log("session", "log cleared")
end
