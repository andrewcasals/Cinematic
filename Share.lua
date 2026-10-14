-- Sharing profiles: Export turns a profile into a line of text to paste
-- anywhere (Discord, a forum, a whisper), and Import turns that text back
-- into a new profile of your own.
--
-- The text is "CINE1:" and then the profile written out by Write below, with
-- a checksum on the end, in base64 (letters, digits, + and /), so chat and
-- Discord can't mangle it and a bit missing from a copy is caught. It's read
-- back by Read, never run as code, and only settings this version has, of
-- the right kind, are kept (Profiles.lua's ns.KnownProfileSetting): one from
-- a newer version loads all but its new settings. The 1 is the format;
-- a later format number asks for an update instead.
--
-- What's in it: the profile's name, its description, who shared it, the
-- version, and its settings that differ from the defaults (ns.ProfileForSharing).
-- Like a profile, not the frames you added or the zone and time tints.

local _, ns = ...
local L = ns.L

local FORMAT = 1
local PREFIX = "CINE" .. FORMAT .. ":"
local MAX_NAME = 32 -- (as the New profile box)
local MAX_NOTE = 200

local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local floor = math.floor

-- Base64 (sums rather than bit operations: the same in every client).
local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CHAR_VALUE = {}
for i = 1, #CHARS do CHAR_VALUE[CHARS:sub(i, i)] = i - 1 end

local function Char(n)
	return CHARS:sub(n + 1, n + 1)
end

local function Encode(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = data:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		out[#out + 1] = Char(floor(n / 262144)) .. Char(floor(n / 4096) % 64)
			.. (b and Char(floor(n / 64) % 64) or "=") .. (c and Char(n % 64) or "=")
	end
	return table.concat(out)
end

-- Anything that isn't base64 (spaces, line breaks from a paste) is ignored.
local function Decode(text)
	text = text:gsub("[^%w%+/]", "")
	local out = {}
	for i = 1, #text, 4 do
		local group = text:sub(i, i + 3)
		local n, count = 0, #group
		for j = 1, 4 do
			n = n * 64 + (CHAR_VALUE[group:sub(j, j)] or 0)
		end
		local a, b, c = floor(n / 65536), floor(n / 256) % 256, n % 256
		if count == 4 then
			out[#out + 1] = string.char(a, b, c)
		elseif count == 3 then
			out[#out + 1] = string.char(a, b)
		elseif count == 2 then
			out[#out + 1] = string.char(a)
		end
	end
	return table.concat(out)
end

-- Adler-32, as 8 hex digits: catches a copy that's lost or changed a bit.
local function Checksum(data)
	local a, b = 1, 0
	for i = 1, #data do
		a = (a + data:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return ("%04x%04x"):format(b, a) -- (in halves: %x can't take 32 bits everywhere)
end

-- Writing a value out: T / F, n<number>; , s<length>:<text>, or { key value ... }.
local function Writable(value)
	local kind = type(value)
	if kind == "number" then
		return value == value and value ~= math.huge and value ~= -math.huge
	end
	return kind == "boolean" or kind == "string" or kind == "table"
end

local function Write(value, out)
	local kind = type(value)
	if kind == "boolean" then
		out[#out + 1] = value and "T" or "F"
	elseif kind == "number" then
		local text = ("%.14g"):format(value)
		if tonumber(text) ~= value then text = ("%.17g"):format(value) end
		out[#out + 1] = "n" .. text .. ";"
	elseif kind == "string" then
		out[#out + 1] = "s" .. #value .. ":" .. value
	else
		-- (Keys in order, so the same profile always gives the same text.)
		local keys = {}
		for k, v in pairs(value) do
			local keyKind = type(k)
			if (keyKind == "string" or keyKind == "number") and Writable(k) and Writable(v) then
				keys[#keys + 1] = k
			end
		end
		table.sort(keys, function(x, y)
			if type(x) ~= type(y) then return type(x) == "number" end
			return x < y
		end)
		out[#out + 1] = "{"
		for _, k in ipairs(keys) do
			Write(k, out)
			Write(value[k], out)
		end
		out[#out + 1] = "}"
	end
end

-- Reading one back from pos: the value and where the next one starts.
-- Errors on anything else (Read catches it).
local MAX_DEPTH = 8
local function ReadValue(text, pos, depth)
	local tag = text:sub(pos, pos)
	if tag == "T" then
		return true, pos + 1
	elseif tag == "F" then
		return false, pos + 1
	elseif tag == "n" then
		local digits, after = text:match("^([%d%.eE%+%-]+);()", pos + 1)
		local number = tonumber(digits)
		if not number then error("number") end
		return number, after
	elseif tag == "s" then
		local length, start = text:match("^(%d+):()", pos + 1)
		length = tonumber(length)
		if not length or start + length - 1 > #text then error("string") end
		return text:sub(start, start + length - 1), start + length
	elseif tag == "{" and depth < MAX_DEPTH then
		local result = {}
		pos = pos + 1
		while text:sub(pos, pos) ~= "}" do
			local key, value
			key, pos = ReadValue(text, pos, depth + 1)
			if type(key) ~= "string" and type(key) ~= "number" then error("key") end
			value, pos = ReadValue(text, pos, depth + 1)
			result[key] = value
		end
		return result, pos + 1
	end
	error("value")
end

local function Read(text)
	local ok, value, after = pcall(ReadValue, text, 1, 0)
	if ok and after == #text + 1 then return value end
end

local function Version()
	return GetMetadata and GetMetadata("Cinematic", "Version") or "?"
end

-- No | in names or descriptions from a string: it would turn into colours or icons.
local function Clean(text, max)
	if type(text) ~= "string" then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", ""):gsub("%c", " "):match("^%s*(.-)%s*$")
	if #text > max then
		-- (Cut at a whole letter: a UTF-8 one is several bytes.)
		text = text:sub(1, max):gsub("[\192-\255][\128-\191]*$", "")
	end
	return text ~= "" and text or nil
end

function ns.ExportProfile(name)
	local data = {
		format = FORMAT,
		version = Version(),
		name = name,
		note = not ns.IsBuiltinProfile(name) and ns.ProfileNote(name) or nil,
		from = UnitName("player"),
		settings = ns.ProfileForSharing(name),
	}
	local out = {}
	Write(data, out)
	local body = table.concat(out)
	return PREFIX .. Encode(body .. Checksum(body))
end

-- What a pasted string holds: { name, note, from, version, settings, count,
-- skipped }, or nil and why not ("empty", "newer" or "broken").
function ns.ReadSharedProfile(text)
	text = (text or ""):gsub("%s", "")
	if text == "" then return nil, "empty" end
	local format, encoded = text:match("CINE(%d+):(.*)")
	format = tonumber(format)
	if not format then return nil, "broken" end
	if format > FORMAT then return nil, "newer" end
	local payload = Decode(encoded)
	local body, sum = payload:sub(1, -9), payload:sub(-8)
	if #payload < 9 or Checksum(body) ~= sum then return nil, "broken" end
	local data = Read(body)
	if type(data) ~= "table" or type(data.settings) ~= "table" then return nil, "broken" end
	local settings, count, skipped = {}, 0, 0
	for key, value in pairs(data.settings) do
		if ns.KnownProfileSetting(key, value) then
			settings[key] = value
			count = count + 1
		else
			skipped = skipped + 1
		end
	end
	return {
		name = Clean(data.name, MAX_NAME) or L["Shared profile"],
		note = Clean(data.note, MAX_NOTE),
		from = Clean(data.from, 48),
		version = Clean(data.version, 32),
		settings = settings, count = count, skipped = skipped,
	}
end

-- A name not taken yet: the shared one, or it with 2, 3... after.
local function FreeName(name)
	if not ns.FindProfile(name) then return name end
	for i = 2, 99 do
		local suffix = " " .. i
		local try = name:sub(1, MAX_NAME - #suffix):gsub("[\192-\255][\128-\191]*$", "") .. suffix
		if not ns.FindProfile(try) then return try end
	end
	return name
end

-- The window: Export shows the text to copy; Import takes it, says what's in
-- it and asks for a name.
local window

local function Trimmed(box)
	return (box:GetText() or ""):match("^%s*(.-)%s*$")
end

-- Import mode: what the pasted text holds, and whether Import can go ahead.
local function UpdateImport()
	local info, why = ns.ReadSharedProfile(window.box:GetText())
	window.info = info
	local name = Trimmed(window.nameBox)
	if not info then
		window.nameRow:Hide()
		window.status:SetText(why == "newer"
			and "|cffff8000" .. L["This profile needs a newer version of Cinematic. Update it, then try again."] .. "|r"
			or why == "broken"
			and "|cffff4040" .. L["That isn't a whole Cinematic profile. Copy all of it and paste it again."] .. "|r"
			or L["Paste a profile someone shared with you (Ctrl+V)."])
		window.accept:Disable()
		return
	end
	if not window.nameRow:IsShown() or window.lastName ~= info.name then
		-- (A new paste: its own name, or one that's free.)
		window.lastName = info.name
		window.nameBox:SetText(FreeName(info.name))
		name = Trimmed(window.nameBox)
		window.nameRow:Show()
	end
	local lines = {}
	lines[1] = (info.from and L["%s, shared by %s: %d settings changed from the defaults."]:format(
		"|cffffd100" .. info.name .. "|r", info.from, info.count)
		or L["%s: %d settings changed from the defaults."]:format("|cffffd100" .. info.name .. "|r", info.count))
	if info.note then lines[#lines + 1] = "|cffbbbbbb" .. info.note .. "|r" end
	if info.skipped > 0 then
		lines[#lines + 1] = "|cffff8000" .. L["%d settings from a newer Cinematic (%s) will be skipped. " ..
			"Update Cinematic to get them all."]:format(info.skipped, info.version or "?") .. "|r"
	end
	local taken = name ~= "" and ns.FindProfile(name)
	if name == "" then
		lines[#lines + 1] = "|cffff4040" .. L["A profile needs a name."] .. "|r"
	elseif taken then
		lines[#lines + 1] = "|cffff4040" .. L["There's already a profile called %s."]:format(taken) .. "|r"
	end
	window.status:SetText(table.concat(lines, "\n"))
	window.accept:SetEnabled(name ~= "" and not taken)
end

local function Accept()
	local info, name = window.info, Trimmed(window.nameBox)
	if not info or name == "" or ns.FindProfile(name) then return end
	local note = info.note or (info.from and L["Shared by %s."]:format(info.from))
	if ns.AddSharedProfile(name, info.settings, note) then
		ns.Print(L["profile imported: %s"]:format(name))
		window:Hide()
	end
end

local function CreateWindow()
	window = CreateFrame("Frame", "CinematicShareWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	window:SetSize(560, 330)
	window:SetPoint("CENTER", 0, 40)
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
	tinsert(UISpecialFrames, "CinematicShareWindow") -- Escape closes it

	local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -14)
	window.title = title

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	hint:SetPoint("RIGHT", window, "RIGHT", -16, 0)
	hint:SetJustifyH("LEFT")
	window.hint = hint

	-- The text: a box with a scroll bar, for a long line.
	local holder = CreateFrame("Frame", nil, window, BackdropTemplateMixin and "BackdropTemplate")
	holder:SetPoint("TOPLEFT", 14, -70)
	holder:SetPoint("RIGHT", window, "RIGHT", -14, 0)
	holder:SetHeight(120)
	holder:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	holder:SetBackdropColor(0, 0, 0, 0.6)
	local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetMaxLetters(0)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(490)
	box:SetScript("OnEscapePressed", function() window:Hide() end)
	box:SetScript("OnTextChanged", function(self, user)
		if window.mode == "export" then
			-- Read-only: any typing puts the text back.
			if user then
				self:SetText(window.text)
				self:HighlightText()
			end
		else
			UpdateImport()
		end
	end)
	-- Export: a click in it selects the lot again, so Ctrl+C never copies part of it.
	box:SetScript("OnMouseUp", function(self)
		if window.mode == "export" then self:HighlightText() end
	end)
	scroll:SetScrollChild(box)
	scroll:SetScript("OnSizeChanged", function(_, width) box:SetWidth(width) end)
	-- (Clicking anywhere in the box puts the cursor in it, not just on the text.)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	window.box = box

	local status = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	status:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 2, -10)
	status:SetPoint("RIGHT", window, "RIGHT", -16, 0)
	status:SetJustifyH("LEFT")
	status:SetJustifyV("TOP")
	window.status = status

	-- Import's name for the new profile, and its button.
	local nameRow = CreateFrame("Frame", nil, window)
	nameRow:SetPoint("BOTTOMLEFT", 16, 14)
	nameRow:SetSize(400, 24)
	local nameLabel = nameRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	nameLabel:SetPoint("LEFT", 0, 0)
	nameLabel:SetText(L["Save as:"])
	local nameBox = CreateFrame("EditBox", nil, nameRow, "InputBoxTemplate")
	nameBox:SetSize(220, 20)
	nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
	nameBox:SetAutoFocus(false)
	nameBox:SetMaxLetters(MAX_NAME)
	nameBox:SetScript("OnTextChanged", function(_, user)
		if user then UpdateImport() end
	end)
	nameBox:SetScript("OnEnterPressed", Accept)
	nameBox:SetScript("OnEscapePressed", function() window:Hide() end)
	window.nameRow, window.nameBox = nameRow, nameBox

	local accept = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	accept:SetSize(110, 22)
	accept:SetPoint("BOTTOMRIGHT", -16, 14)
	accept:SetText(L["Import"])
	accept:SetScript("OnClick", Accept)
	window.accept = accept

	-- Export's: addons can't put text on the clipboard (the game keeps that
	-- for its own UI), so this selects it all, ready for Ctrl+C.
	local selectAll = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	selectAll:SetSize(110, 22)
	selectAll:SetPoint("BOTTOMRIGHT", -16, 14)
	selectAll:SetText(L["Select all"])
	selectAll:SetScript("OnClick", function()
		box:SetFocus()
		box:HighlightText()
	end)
	window.selectAll = selectAll
end

-- Export: the profile as text, selected and ready to copy.
function ns.ShowExport(name)
	name = name or ns.ActiveProfile()
	-- (Everyone has the built-in ones: a copy made with New profile can go.)
	if ns.IsBuiltinProfile(name) then
		ns.Print(L["%s is a built-in profile, which everyone has already. To share your changes to it, " ..
			"make a New profile from it on the Profiles page and export that."]:format(name))
		return
	end
	if not window then CreateWindow() end
	window.mode = "export"
	window.text = ns.ExportProfile(name)
	window.title:SetText(L["Export profile: %s"]:format(name))
	window.hint:SetText(L["Press Ctrl+C to copy this, then paste it wherever your friends will see it. " ..
		"They add it with Import on their Cinematic Profiles page (or /cine import)."])
	window.status:SetText(L["Only Cinematic settings are in it: nothing about you or your character " ..
		"but its name. Not in it, as with any profile: frames you added and your zone and time tint colours."])
	window.nameRow:Hide()
	window.accept:Hide()
	window.selectAll:Show()
	window:Show()
	window.box:SetText(window.text)
	window.box:SetFocus()
	window.box:HighlightText()
end

-- Import: an empty box to paste into.
function ns.ShowImport()
	if not window then CreateWindow() end
	window.mode = "import"
	window.info, window.lastName = nil, nil
	window.title:SetText(L["Import a profile"])
	window.hint:SetText(L["Paste in a profile someone shared, give it a name, and Import. " ..
		"It's added as a new profile and switched to; your own profiles stay as they are."])
	window.nameRow:Hide()
	window.accept:Show()
	window.selectAll:Hide()
	window:Show()
	window.box:SetText("")
	window.box:SetFocus()
	UpdateImport()
end
