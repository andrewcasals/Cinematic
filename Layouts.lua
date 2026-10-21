-- The dev build's Edit Mode layout page (for now: profiles may get a layout
-- part of their own later). One button makes CINE_FOREVER_RETAIL_LAYOUT, an
-- account layout listed in Edit Mode beside the player's, or brings it up to
-- date if it's there, and switches to it. Deleting it is left to Edit Mode.
-- Edit Mode keeps its own copy of every layout until a reload (and would save
-- that copy over ours), so it ends by offering one.
--
-- LAYOUT is an Edit Mode export string (Share > Copy to Clipboard); nil uses
-- a copy of the Modern preset with DESIGN's changes. Options.lua calls
-- ns.CreateLayoutPanel with the page helpers it shares (dev build only).

local _, ns = ...

ns.LAYOUT_NAME = "CINE_FOREVER_RETAIL_LAYOUT"

local LAYOUT = nil

local function AccountType()
	return Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account or 1
end

-- The saved layouts (not the presets), and our layout's place among them (nil: none).
local function FindLayout()
	local info = C_EditMode.GetLayouts()
	for i, layout in ipairs(info.layouts) do
		if layout.layoutName == ns.LAYOUT_NAME then return info, i end
	end
	return info, nil
end

-- A layout's number for SetActiveLayout by name (a preset's too); nil if gone.
local function IndexOf(info, name)
	local manager = _G.EditModePresetLayoutManager
	local presets = manager and manager:GetCopyOfPresetLayouts() or {}
	for i, preset in ipairs(presets) do
		if preset.layoutName == name then return i end
	end
	for i, layout in ipairs(info.layouts) do
		if layout.layoutName == name then return #presets + i end
	end
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

local function ApplyDesign(layout)
	for _, system in ipairs(layout.systems or {}) do
		for _, saved in ipairs(DESIGN) do
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

local function BuildLayout()
	local layout
	if LAYOUT then
		layout = C_EditMode.ConvertStringToLayoutInfo(LAYOUT)
	else
		local manager = _G.EditModePresetLayoutManager
		layout = manager and manager:GetCopyOfPresetLayouts()[1] -- (Modern)
		if layout then ApplyDesign(layout) end
	end
	if not layout then return nil end
	layout.layoutName, layout.layoutType = ns.LAYOUT_NAME, AccountType()
	return layout
end

-- Why it can't be changed now (nil: it can).
local function Blocked()
	if not (C_EditMode and C_EditMode.GetLayouts) then return "this game has no Edit Mode" end
	if InCombatLockdown() then return "not in combat" end
	local manager = _G.EditModeManagerFrame
	if manager and manager:IsShown() then return "close Edit Mode first" end
end

-- Made, or brought up to date, and switched to. true: done (a reload applies
-- it everywhere); false, reason: not.
local function MakeLayout()
	local blocked = Blocked()
	if blocked then return false, blocked end
	local info, index = FindLayout()
	local layout = BuildLayout()
	if not layout then return false, "couldn't read the layout" end
	if index then
		info.layouts[index] = layout
	else
		local count = 0
		for _, other in ipairs(info.layouts) do
			if other.layoutType == AccountType() then count = count + 1 end
		end
		local max = Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType or 5
		if count >= max then
			return false, ("you already have %d account layouts; delete one in Edit Mode first"):format(max)
		end
		info.layouts[#info.layouts + 1] = layout
	end
	C_EditMode.SaveLayouts(info)
	local active = IndexOf(C_EditMode.GetLayouts(), ns.LAYOUT_NAME)
	-- (whether the game took it: it can refuse a layout without saying)
	ns.Log("state", ("edit mode layout %s: %s"):format(index and "updated" or "made", active and "there" or "NOT there"))
	if not active then return false, "the game didn't keep it" end
	C_EditMode.SetActiveLayout(active)
	-- (the reload it asks for puts Edit Mode back on the layout it had: switched again after it)
	ns.chardb.layoutPending = ns.LAYOUT_NAME
	return true
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

-- The page: whether it's there, and the one button.
function ns.CreateLayoutPanel(kit)
	StaticPopupDialogs.CINEMATIC_LAYOUT_RELOAD = {
		text = "Edit Mode keeps its old list of layouts until you reload, and saving there before then " ..
			"would undo this. Reload now?",
		button1 = RELOADUI or "Reload", button2 = "Later",
		OnAccept = ReloadUI,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}

	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", "|cffff4040DEV ONLY|r Edit Mode layout")
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.Label(content, "GameFontHighlight", "Makes " .. ns.LAYOUT_NAME .. " in Edit Mode, or " ..
		"brings it up to date from the code if it's there, and switches to it. Delete it in Edit Mode.")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	intro:SetWidth(560)
	intro:SetJustifyH("LEFT")

	local status = kit.Label(content, "GameFontHighlight")
	status:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -14)
	local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	button:SetSize(200, 24)
	button:SetPoint("TOPLEFT", status, "BOTTOMLEFT", -2, -12)

	local function Refresh()
		local there = C_EditMode and C_EditMode.GetLayouts and select(2, FindLayout())
		status:SetText(ns.LAYOUT_NAME .. ": " .. (there and "|cff40ff40there|r" or "|cff808080not made yet|r"))
		button:SetText(there and "Update the layout" or "Create the layout")
	end
	button:SetScript("OnClick", function()
		local ok, reason = MakeLayout()
		if ok then
			StaticPopup_Show("CINEMATIC_LAYOUT_RELOAD")
		else
			ns.Print(reason)
		end
		Refresh()
	end)

	-- (made or deleted in Edit Mode itself, too)
	canvas:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	canvas:SetScript("OnEvent", function(self) if self:IsVisible() then Refresh() end end)
	canvas:SetScript("OnShow", kit.PageShown(Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Dev", "Dev")
end
