-- The dev build's Profile Builder page: every built-in profile (both
-- clients', and dev-only ones) against the profile slots, with the part each
-- uses. Clicking a cell tries another part (this client's; kept in
-- db.devRecipes until cleared, and only taking effect when the profile is
-- picked or reset); Lua gives the profile's parts line for Profiles.lua.
-- Capture writes the live settings of one slot as a part for
-- ProfileParts.lua, and Compare lists the settings two profiles differ on.
-- Output goes in the box at the bottom, to copy. Options.lua calls
-- ns.CreateProfileBuilder with the page helpers it shares (dev build only).

local _, ns = ...

local NAME_W, CELL_W, ROW_H = 150, 70, 22

-- A value as Lua source (keys sorted, so the same settings give the same text).
local function Lua(value)
	if type(value) == "string" then return ("%q"):format(value) end
	if type(value) ~= "table" then return tostring(value) end
	local keys = {}
	for k in pairs(value) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then return type(a) == "number" end
		return a < b
	end)
	local parts = {}
	for _, k in ipairs(keys) do
		local key
		if type(k) == "string" and k:match("^[%a_][%w_]*$") then
			key = k
		elseif type(k) == "string" then
			key = ("[%q]"):format(k)
		else
			key = "[" .. tostring(k) .. "]"
		end
		parts[#parts + 1] = key .. " = " .. Lua(value[k])
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function SlotName(slot)
	for _, each in ipairs(ns.PROFILE_SLOTS) do
		if each.key == slot then return each.name end
	end
	return slot
end

-- A menu of { text, fn } under a button (no menus on this client: each
-- click takes the next one).
local function Menu(owner, entries)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			for _, entry in ipairs(entries) do root:CreateButton(entry[1], entry[2]) end
		end)
	elseif #entries > 0 then
		owner.menuIndex = (owner.menuIndex or 0) % #entries + 1
		entries[owner.menuIndex][2]()
	end
end

local function Changes(name)
	local recipes = ns.db.devRecipes
	return recipes and recipes[name]
end

-- A cell's text: the part (by client where it differs), a changed one green
-- with a *, the standard part grey, none "-".
local function CellText(profile, slot)
	local changed = Changes(profile.name)
	if changed and changed[slot] then return "|cff40ff40" .. changed[slot] .. "*|r" end
	local spec = profile.parts[slot]
	if type(spec) == "table" then
		return ("F:%s R:%s"):format(spec.forever or "-", spec.retail or "-")
	elseif spec then
		return spec
	end
	return ns.PROFILE_PARTS[slot].standard and "|cff808080standard|r" or "|cff808080-|r"
end

-- The profile's parts line, changes and all, for Profiles.lua.
local function RecipeLua(profile)
	local parts = {}
	for slot, spec in pairs(profile.parts) do parts[slot] = spec end
	for slot, part in pairs(Changes(profile.name) or {}) do
		parts[slot] = part ~= "standard" and part or nil
	end
	local fields = {}
	for _, slot in ipairs(ns.PROFILE_SLOTS) do
		if parts[slot.key] ~= nil then fields[#fields + 1] = slot.key .. " = " .. Lua(parts[slot.key]) end
	end
	return ("-- %s\n\t\tparts = { %s },"):format(profile.name, table.concat(fields, ", "))
end

-- The live settings of one slot that differ from the defaults, as a part:
-- each setting, and each list's rows that are the slot's.
local function CaptureLua(slot)
	local db, lines = ns.db, {}
	local keys = {}
	for key in pairs(ns.DEFAULTS) do
		if ns.IsProfileKey(key) and ns.SettingSlot(key) == slot and db[key] ~= ns.DEFAULTS[key] then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do lines[#lines + 1] = ("\t\t\tset(%q, %s)"):format(key, Lua(db[key])) end
	local lists = {}
	for _, key in ipairs(ns.PROFILE_TABLES) do lists[#lists + 1] = key end
	table.sort(lists)
	for _, key in ipairs(lists) do
		if type(db[key]) == "table" then
			local rows = {}
			for row, value in pairs(db[key]) do
				if ns.SettingSlot(key, row) == slot then rows[row] = value end
			end
			if next(rows) then lines[#lines + 1] = ("\t\t\tset(%q, %s)"):format(key, Lua(rows)) end
		end
	end
	return ("-- %s part captured %s from %s (%d settings): paste into ProfileParts.lua's %s parts, and name it.\n"
		.. "\t\tNEWPART = { apply = function(set)\n%s\n\t\tend },"):format(SlotName(slot), date("%Y-%m-%d %H:%M"),
		ns.ProfileLabel(ns.ActiveProfile()), #lines, slot, table.concat(lines, "\n"))
end

-- The settings two profiles differ on, by slot (a list row by row; a row
-- one hasn't got: "default").
local function CompareText(a, b)
	local A, B = ns.ProfileSettings(a), ns.ProfileSettings(b)
	local bySlot = {}
	local function Add(slot, text)
		slot = slot or "?"
		bySlot[slot] = bySlot[slot] or {}
		table.insert(bySlot[slot], text)
	end
	local function Shown(value)
		if value == nil then return "default" end
		return type(value) == "table" and Lua(value) or tostring(value)
	end
	for key in pairs(ns.DEFAULTS) do
		if ns.IsProfileKey(key) and A[key] ~= B[key] then
			Add(ns.SettingSlot(key), ("%s: %s -> %s"):format(key, Shown(A[key]), Shown(B[key])))
		end
	end
	for _, key in ipairs(ns.PROFILE_TABLES) do
		local listA, listB = A[key] or {}, B[key] or {}
		local rows = {}
		for row in pairs(listA) do rows[row] = true end
		for row in pairs(listB) do rows[row] = true end
		for row in pairs(rows) do
			local va, vb = listA[row], listB[row]
			if type(va) == "table" or type(vb) == "table" then
				if Lua(va) ~= Lua(vb) then
					Add(ns.SettingSlot(key, row), ("%s.%s: %s -> %s"):format(key, tostring(row), Shown(va), Shown(vb)))
				end
			elseif va ~= vb then
				Add(ns.SettingSlot(key, row), ("%s.%s: %s -> %s"):format(key, tostring(row), Shown(va), Shown(vb)))
			end
		end
	end
	local out, total = { ("%s -> %s"):format(ns.ProfileLabel(a), ns.ProfileLabel(b)) }, 0
	for _, slot in ipairs(ns.PROFILE_SLOTS) do
		local list = bySlot[slot.key]
		if list then
			table.sort(list)
			total = total + #list
			out[#out + 1] = ("\n%s (%d):"):format(slot.name, #list)
			for _, line in ipairs(list) do out[#out + 1] = "  " .. line end
		end
	end
	if bySlot["?"] then
		out[#out + 1] = "\nno slot:"
		for _, line in ipairs(bySlot["?"]) do out[#out + 1] = "  " .. line end
	end
	if total == 0 and not bySlot["?"] then out[#out + 1] = "\nthe same settings" end
	return table.concat(out, "\n")
end

function ns.CreateProfileBuilder(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", "|cffff4040DEV ONLY|r Profile Builder")
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.Label(content, "GameFontHighlight", "Each built-in profile's part in each slot. " ..
		"Click a cell to try another part on this client (green*: changed; it takes effect when you pick or " ..
		"reset that profile, and your live settings stay as they are). Lua puts the profile's parts line in " ..
		"the box below, for Profiles.lua.")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	intro:SetWidth(600)
	intro:SetJustifyH("LEFT")

	local function Button(parent, text, width, tip, onClick)
		local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		button:SetSize(width, ROW_H)
		button:SetText(text)
		if tip then kit.Tooltip(button, tip) end
		button:SetScript("OnClick", onClick)
		return button
	end

	-- The slots across the top.
	local header = CreateFrame("Frame", nil, content)
	header:SetSize(NAME_W + #ns.PROFILE_SLOTS * CELL_W, ROW_H)
	header:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -14)
	for i, slot in ipairs(ns.PROFILE_SLOTS) do
		local label = kit.Label(header, "GameFontNormalSmall", slot.name)
		label:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", NAME_W + (i - 1) * CELL_W + 4, 4)
		label:SetWidth(CELL_W - 6)
		label:SetWordWrap(true)
	end

	local output -- (the box at the bottom)
	local Refresh
	local cells = {}
	local anchor = header
	for _, profile in ipairs(ns.ALL_BUILTIN_PROFILES) do
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(NAME_W + #ns.PROFILE_SLOTS * CELL_W + 44, ROW_H)
		row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
		anchor = row
		local tags = {}
		if profile.client then tags[#tags + 1] = profile.client == "forever" and "F" or "R" end
		if profile.dev then tags[#tags + 1] = "dev" end
		if profile.hidden then tags[#tags + 1] = "hidden" end
		local shown = (profile.label or profile.name) .. (#tags > 0 and " |cff808080(" .. table.concat(tags, ",")
			.. ")|r" or "")
		local name = kit.Label(row, "GameFontHighlightSmall", shown)
		name:SetPoint("LEFT", row, "LEFT", 0, 0)
		name:SetWidth(NAME_W - 6)
		name:SetWordWrap(false)
		for i, slot in ipairs(ns.PROFILE_SLOTS) do
			local cell = CreateFrame("Button", nil, row)
			cell:SetSize(CELL_W - 4, ROW_H - 2)
			cell:SetPoint("LEFT", row, "LEFT", NAME_W + (i - 1) * CELL_W, 0)
			local back = cell:CreateTexture(nil, "BACKGROUND")
			back:SetAllPoints()
			back:SetColorTexture(1, 1, 1, 0.06)
			cell:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			cell.text = kit.Label(cell, "GameFontHighlightSmall")
			cell.text:SetPoint("LEFT", 3, 0)
			cell.text:SetPoint("RIGHT", -3, 0)
			cell.text:SetWordWrap(false)
			cell.profile, cell.slot = profile, slot.key
			cell:SetScript("OnClick", function(self)
				local function Pick(part)
					ns.db.devRecipes = ns.db.devRecipes or {}
					local changed = ns.db.devRecipes[profile.name] or {}
					changed[slot.key] = part
					ns.db.devRecipes[profile.name] = next(changed) and changed or nil
					ns.ForgetProfileBases()
					ns.Print(("Profile Builder: %s %s: %s (when you pick or reset it)"):format(profile.name,
						slot.key, part or "as in the code"))
					Refresh()
				end
				local entries = {}
				local changed = Changes(profile.name)
				if changed and changed[slot.key] then entries[#entries + 1] = { "Undo (as in the code)", function() Pick(nil) end } end
				entries[#entries + 1] = { ns.PROFILE_PARTS[slot.key].standard and "standard" or "none",
					function() Pick("standard") end }
				local names = {}
				for partName in pairs(ns.PROFILE_PARTS[slot.key]) do
					if partName ~= "standard" then names[#names + 1] = partName end
				end
				table.sort(names)
				for _, partName in ipairs(names) do
					local part = ns.PROFILE_PARTS[slot.key][partName]
					local text = partName .. (part.client and " (" .. part.client .. " only)" or "")
					entries[#entries + 1] = { text, function() Pick(partName) end }
				end
				Menu(self, entries)
			end)
			cells[#cells + 1] = cell
		end
		local lua = Button(row, "Lua", 40, "This profile's parts line, with your changes, in the box below.", function()
			output:SetText(RecipeLua(profile))
			output:HighlightText()
			output:SetFocus()
		end)
		lua:SetPoint("LEFT", row, "LEFT", NAME_W + #ns.PROFILE_SLOTS * CELL_W + 2, 0)
	end

	-- Clear changes, Capture, Compare.
	local clear = Button(content, "Clear changes", 120, "Every profile's parts back to the code's.", function()
		ns.db.devRecipes = nil
		ns.ForgetProfileBases()
		Refresh()
	end)
	clear:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
	local capture = Button(content, "Capture slot...", 130, "The live settings of one slot that differ from " ..
		"the defaults, as a part to paste into ProfileParts.lua.", function(self)
		local entries = {}
		for _, slot in ipairs(ns.PROFILE_SLOTS) do
			entries[#entries + 1] = { slot.name, function()
				output:SetText(CaptureLua(slot.key))
				output:HighlightText()
				output:SetFocus()
			end }
		end
		Menu(self, entries)
	end)
	capture:SetPoint("LEFT", clear, "RIGHT", 8, 0)

	-- Compare: the two profiles picked (the active one and Immersive to start).
	local picked = {}
	local function PickButton(index)
		local button
		button = Button(content, "", 130, "Pick a profile to compare.", function(self)
			local entries = {}
			for _, name in ipairs(ns.ProfileNames()) do
				entries[#entries + 1] = { ns.ProfileLabel(name), function()
					picked[index] = name
					button:SetText(ns.ProfileLabel(name))
				end }
			end
			Menu(self, entries)
		end)
		return button
	end
	local first, second = PickButton(1), PickButton(2)
	first:SetPoint("TOPLEFT", clear, "BOTTOMLEFT", 0, -10)
	second:SetPoint("LEFT", first, "RIGHT", 8, 0)
	local compare = Button(content, "Compare", 100, "The settings these two profiles differ on, by slot " ..
		"(each as it would be live: its own values with your changes).", function()
		output:SetText(CompareText(picked[1], picked[2]))
		output:SetCursorPosition(0)
	end)
	compare:SetPoint("LEFT", second, "RIGHT", 8, 0)

	-- The box: text to copy (Ctrl+A, Ctrl+C).
	local box = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
	box:SetSize(600, 220)
	box:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -12)
	if box.SetBackdrop then
		box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		box:SetBackdropColor(0, 0, 0, 0.8)
	end
	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	output = CreateFrame("EditBox", nil, scroll)
	output:SetMultiLine(true)
	output:SetAutoFocus(false)
	output:SetFontObject(ChatFontNormal)
	output:SetWidth(560)
	output:SetScript("OnEscapePressed", output.ClearFocus)
	scroll:SetScrollChild(output)

	function Refresh()
		for _, cell in ipairs(cells) do cell.text:SetText(CellText(cell.profile, cell.slot)) end
		picked[1] = picked[1] or ns.ActiveProfile()
		picked[2] = picked[2] or ns.BUILTIN_PROFILES[1].name
		first:SetText(ns.ProfileLabel(picked[1]))
		second:SetText(ns.ProfileLabel(picked[2]))
	end

	canvas:SetScript("OnShow", kit.PageShown(Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Profile Builder", "Profile Builder")
end
