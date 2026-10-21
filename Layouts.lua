-- Edit Mode layouts: Cinematic's own (EDIT_MODE_LAYOUTS), and the profile
-- layout slot's switching (ns.ApplyProfileLayout). A built-in profile whose
-- layout part names one (db.editModeLayout) switches Edit Mode to it when
-- it's picked, making it first if it isn't there; a profile without one
-- puts back the layout the player was on before. The dev build's Dev page
-- has a button per layout to make it or bring it up to date.
--
-- Each is the game's own: an account layout listed in Edit Mode beside the
-- player's, which they can change there like any other. Making one never
-- touches their layouts. Edit Mode keeps its own copy of every layout until
-- a reload (and would save that copy over ours), so making one ends by
-- offering one.

local _, ns = ...
local L = ns.L

ns.LAYOUT_NAME = "CINE_FOREVER_RETAIL_LAYOUT"

local function AccountType()
	return Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account or 1
end

local function Presets()
	local manager = _G.EditModePresetLayoutManager
	return manager and manager:GetCopyOfPresetLayouts() or {}
end

-- The saved layouts (not the presets), and a layout's place among them (nil: none).
local function FindLayout(name)
	local info = C_EditMode.GetLayouts()
	for i, layout in ipairs(info.layouts) do
		if layout.layoutName == name then return info, i end
	end
	return info, nil
end

-- A layout's number for SetActiveLayout by name (a preset's too); nil if gone.
local function IndexOf(info, name)
	local presets = Presets()
	for i, preset in ipairs(presets) do
		if preset.layoutName == name then return i end
	end
	for i, layout in ipairs(info.layouts) do
		if layout.layoutName == name then return #presets + i end
	end
end

-- The active layout's name (a preset's too).
local function ActiveName(info)
	local presets = Presets()
	local index = info.activeLayout
	if not index then return nil end
	if index <= #presets then return presets[index].layoutName end
	local layout = info.layouts[index - #presets]
	return layout and layout.layoutName
end

-- Without an export string: the Modern preset with the dev's changes to it
-- (the layout as it was at 17:30 on 2026-10-20, read from the game's own
-- Edit Mode save). Each: Enum.EditModeSystem, its index (nil: none), where
-- it's anchored, and the settings that differ from Modern (setting = value).
local DESIGN = {
	-- (Bar 3's two rows beside bars 1 and 2: its bottom row on bar 1's, and bar 2
	-- level with its top row, so the gap between 1 and 2 is its own rows' gap.)
	-- (Bar 1 left of centre by half of bar 3 and the gap, so bars 1-3 together are centred.)
	{ 0, 1, "BOTTOM", "UIParent", "BOTTOM", -142, 42, { [6] = 1 } },        -- action bar 1 (no bar art)
	{ 0, 2, "TOPRIGHT", "MultiBarBottomRight", "TOPLEFT", -4, 0 },          -- 2
	{ 0, 3, "BOTTOMLEFT", "MainActionBar", "BOTTOMRIGHT", 4, 0, { [1] = 2 } }, -- 3 (2 rows)
	-- (Stance and pet bars in the same spot above bar 2: a class has one or the other.)
	{ 0, 11, "BOTTOMLEFT", "MultiBarBottomLeft", "TOPLEFT", 0, 4 },         -- stance bar
	{ 0, 12, "BOTTOMLEFT", "MultiBarBottomLeft", "TOPLEFT", 0, 4 },         -- pet bar
	{ 0, 13, "BOTTOMLEFT", "MultiBarBottomLeft", "TOPLEFT", 0, 4 },         -- possess bar
	{ 1, nil, "BOTTOM", "UIParent", "BOTTOM", 0, 358 },                     -- cast bar
	-- (Its bottom on the same line as the pet bar's, at bar 2's right end.)
	{ 4, nil, "BOTTOMRIGHT", "MultiBarBottomLeft", "TOPRIGHT", 0, 4 },      -- encounter bar (right of the pet bar)
	{ 9, nil, "BOTTOMLEFT", "MultiBarBottomLeft", "TOPLEFT", 0, 4 },        -- vehicle leave button
	{ 13, nil, "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -2, 2 },           -- micro menu
	{ 14, nil, "BOTTOMRIGHT", "MicroMenuContainer", "TOPRIGHT", 0, 4 },     -- bags
	-- (status bars' setting 3: width, 0 = 50%, 10 = 100%)
	{ 15, 1, "BOTTOM", "UIParent", "BOTTOM", 0, 2, { [3] = 0 } },           -- status bar 1
	{ 15, 2, "BOTTOM", "MainStatusTrackingBarContainer", "TOP", 0, 0, { [3] = 0 } }, -- status bar 2
	{ 20, 1, "BOTTOM", "UtilityCooldownViewer", "TOP", -1, 4 },             -- cooldown viewers
	{ 20, 2, "CENTER", "UIParent", "CENTER", 0, -149 },
	{ 20, 3, "CENTER", "UIParent", "CENTER", 0, -187 },
	{ 25, nil, "BOTTOMLEFT", "MultiBarBottomLeft", "TOPLEFT", 0, 4 },
	{ 26, 1, "RIGHT", "MultiBarBottomLeft", "LEFT", 30, 13, { [0] = 1 } },  -- action bar end caps
	{ 26, 2, "LEFT", "MultiBarBottomRight", "RIGHT", -30, 38.2, { [0] = 1 } },
	{ 29, 1, "BOTTOMRIGHT", "SwingTimerOffHandFrame", "TOPRIGHT", 0, 4 },   -- swing timers
	{ 29, 2, "BOTTOM", "UIParent", "BOTTOM", 0, 272 },
	{ 29, 3, "TOPLEFT", "SwingTimerOffHandFrame", "BOTTOMLEFT", 0, -4 },
}

-- Cinematic's own layouts, by the name Edit Mode lists them under. export:
-- an Edit Mode export string (Share > Copy to Clipboard); without one, design:
-- changes to the Modern preset (as DESIGN).
ns.EDIT_MODE_LAYOUTS = {
	[ns.LAYOUT_NAME] = { export = nil, design = DESIGN },
}

local function ApplyDesign(layout, design)
	for _, system in ipairs(layout.systems or {}) do
		for _, saved in ipairs(design) do
			if system.system == saved[1] and system.systemIndex == saved[2] then
				system.isInDefaultPosition = false
				system.anchorInfo = { point = saved[3], relativeTo = saved[4], relativePoint = saved[5],
					offsetX = saved[6], offsetY = saved[7] }
				for _, setting in ipairs(system.settings or {}) do
					local value = saved[8] and saved[8][setting.setting]
					if value then setting.value = value end
				end
			end
		end
	end
end

local function BuildLayout(name)
	local def = ns.EDIT_MODE_LAYOUTS[name]
	if not def then return nil end
	local layout
	if def.export then
		layout = C_EditMode.ConvertStringToLayoutInfo(def.export)
	else
		layout = Presets()[1] -- (Modern)
		if layout then ApplyDesign(layout, def.design or {}) end
	end
	if not layout then return nil end
	layout.layoutName, layout.layoutType = name, AccountType()
	return layout
end

-- Why layouts can't be changed now (nil: they can).
local function Blocked()
	if not (C_EditMode and C_EditMode.GetLayouts) then return L["this game has no Edit Mode"] end
	if InCombatLockdown() then return L["not in combat"] end
	local manager = _G.EditModeManagerFrame
	if manager and manager:IsShown() then return L["close Edit Mode first"] end
end

-- One of ours made, or brought up to date, and switched to. true: done (a
-- reload applies it everywhere); false, reason: not.
function ns.MakeLayout(name)
	local blocked = Blocked()
	if blocked then return false, blocked end
	local info, index = FindLayout(name)
	local layout = BuildLayout(name)
	if not layout then return false, L["couldn't read the layout"] end
	if index then
		info.layouts[index] = layout
	else
		local count = 0
		for _, other in ipairs(info.layouts) do
			if other.layoutType == AccountType() then count = count + 1 end
		end
		local max = Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType or 5
		if count >= max then
			return false, L["you already have %d account layouts in Edit Mode; delete one there first"]:format(max)
		end
		info.layouts[#info.layouts + 1] = layout
	end
	C_EditMode.SaveLayouts(info)
	local active = IndexOf(C_EditMode.GetLayouts(), name)
	-- (whether the game took it: it can refuse a layout without saying)
	ns.Log("state", ("edit mode layout %s %s: %s"):format(name, index and "updated" or "made",
		active and "there" or "NOT there"))
	if not active then return false, L["the game didn't keep the layout"] end
	C_EditMode.SetActiveLayout(active)
	-- (the reload it asks for puts Edit Mode back on the layout it had: switched again after it)
	ns.chardb.layoutPending = name
	return true
end

-- Whether one of ours is there: nil: no; "active" or "made" (another in use).
function ns.LayoutState(name)
	if not (C_EditMode and C_EditMode.GetLayouts) then return nil end
	local info, index = FindLayout(name)
	if not index then return nil end
	return ActiveName(info) == name and "active" or "made"
end

-- After a reload, the layout just made, switched to again (once).
local pending = CreateFrame("Frame")
pending:RegisterEvent("PLAYER_ENTERING_WORLD")
pending:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	local name = ns.chardb and ns.chardb.layoutPending
	if not name or not (C_EditMode and C_EditMode.GetLayouts) then return end
	ns.chardb.layoutPending = nil
	C_Timer.After(1, function()
		if InCombatLockdown() then return end
		local info = C_EditMode.GetLayouts()
		local index = IndexOf(info, name)
		if index and info.activeLayout ~= index then
			C_EditMode.SetActiveLayout(index)
		end
	end)
end)

-- The profile's Edit Mode layout (db.editModeLayout, from its layout part):
-- on switching profile (Profiles.lua), Edit Mode goes to it, after the fight
-- if in one; one of ours is made if it isn't there. "": the player's own,
-- the one they were on before a profile switched it (chardb.layoutOwn), back.
-- Logging in never changes the layout.
local afterCombat = CreateFrame("Frame")
afterCombat:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	ns.ApplyProfileLayout()
end)
local missingSaid = {}

function ns.ApplyProfileLayout()
	if not (C_EditMode and C_EditMode.GetLayouts) or not ns.db or not ns.chardb then return end
	if InCombatLockdown() then
		afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	local manager = _G.EditModeManagerFrame
	if manager and manager:IsShown() then return end -- (the player's choosing there)
	local name = ns.db.editModeLayout or ""
	local info = C_EditMode.GetLayouts()
	if name == "" then
		local own = ns.chardb.layoutOwn
		if not own then return end
		ns.chardb.layoutOwn = nil -- (back on it: or, gone, nothing to go back to)
		local index = IndexOf(info, own)
		if index and info.activeLayout ~= index then
			C_EditMode.SetActiveLayout(index)
			ns.Log("state", "edit mode layout back to: " .. own)
		end
		return
	end
	-- (the one to go back to: what's on now, unless a profile's switched it already)
	local current = ActiveName(info)
	if not ns.chardb.layoutOwn and current ~= name then ns.chardb.layoutOwn = current end
	local index = IndexOf(info, name)
	if not index then
		if ns.EDIT_MODE_LAYOUTS[name] then
			local ok, reason = ns.MakeLayout(name)
			if ok then
				StaticPopup_Show("CINEMATIC_LAYOUT_RELOAD")
			else
				ns.Print(L["couldn't add this profile's Edit Mode layout: %s"]:format(reason))
			end
		elseif not missingSaid[name] then
			missingSaid[name] = true
			ns.Print(L["this profile's Edit Mode layout, %s, isn't there; your layout stays as it is"]:format(name))
		end
		return
	end
	if info.activeLayout ~= index then
		C_EditMode.SetActiveLayout(index)
		ns.Log("state", "edit mode layout: " .. name)
	end
end

ns.OnLanguage(function()
	StaticPopupDialogs.CINEMATIC_LAYOUT_RELOAD = {
		text = L["Edit Mode keeps its old list of layouts until you reload, and saving there before then " ..
			"would undo this. Reload now?"],
		button1 = RELOADUI or L["Reload"], button2 = L["Later"],
		OnAccept = ReloadUI,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
end)

-- The Dev page (dev build): each of our layouts, whether it's there, and a
-- button to make it or bring it up to date from the code.
function ns.CreateLayoutPanel(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", "|cffff4040DEV ONLY|r Edit Mode layouts")
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.Label(content, "GameFontHighlight", "Makes each layout in Edit Mode, or brings it up " ..
		"to date from the code if it's there, and switches to it. Delete them in Edit Mode. A profile whose " ..
		"layout part names one makes it when picked, too.")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	intro:SetWidth(560)
	intro:SetJustifyH("LEFT")

	local names = {}
	for name in pairs(ns.EDIT_MODE_LAYOUTS) do names[#names + 1] = name end
	table.sort(names)
	local rows, anchor = {}, intro
	for _, name in ipairs(names) do
		local status = kit.Label(content, "GameFontHighlight")
		status:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
		local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		button:SetSize(200, 24)
		button:SetPoint("TOPLEFT", status, "BOTTOMLEFT", -2, -8)
		rows[#rows + 1] = { name = name, status = status, button = button }
		anchor = button
	end

	local function Refresh()
		for _, row in ipairs(rows) do
			local state = ns.LayoutState(row.name)
			row.status:SetText(row.name .. ": " .. (state == "active" and "|cff40ff40there, in use|r"
				or state and "|cffffd100there, not in use|r" or "|cff808080not made yet|r"))
			row.button:SetText(state and "Update the layout" or "Create the layout")
		end
	end
	for _, row in ipairs(rows) do
		row.button:SetScript("OnClick", function()
			local ok, reason = ns.MakeLayout(row.name)
			if ok then
				StaticPopup_Show("CINEMATIC_LAYOUT_RELOAD")
			else
				ns.Print(reason)
			end
			Refresh()
		end)
	end

	-- (made or deleted in Edit Mode itself, too)
	canvas:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	canvas:SetScript("OnEvent", function(self) if self:IsVisible() then Refresh() end end)
	canvas:SetScript("OnShow", kit.PageShown(Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Dev", "Dev")
end
