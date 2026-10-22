-- Edit Mode layouts: Cinematic's own (EDIT_MODE_LAYOUTS), and the profile
-- layout slot's switching (ns.ApplyProfileLayout). A built-in profile whose
-- layout part names one (db.editModeLayout) switches Edit Mode to it when
-- it's picked, making it first if it isn't there; a profile without one
-- puts back the layout the player was on before. The dev build's Dev page
-- has a button per layout to make it or bring it up to date.
--
-- Each is the game's own: an account layout listed in Edit Mode beside the
-- player's, which they can change there like any other. Making one never
-- touches their layouts. A new one works at once, no reload needed; one
-- brought up to date (the Dev page's Update) shows its old copy in Edit Mode
-- until a reload (and saving there would put that back), so that offers one.

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

-- A layout's name by its SetActiveLayout number (a preset's too).
local function NameAt(info, index)
	if not index then return nil end
	local presets = Presets()
	if index <= #presets then return presets[index].layoutName end
	local layout = info.layouts[index - #presets]
	return layout and layout.layoutName
end

-- The active layout's name.
local function ActiveName(info)
	return NameAt(info, info.activeLayout)
end

-- A profile's layout (db.editModeLayout) as the name to go to. A preset
-- (ns.LAYOUT_PRESET): the one the player is on now, or was on before a
-- profile switched it, else the first (Modern); nil: the game has none.
local function Target(info, name)
	if name ~= ns.LAYOUT_PRESET then return name end
	local presets = Presets()
	local active = info.activeLayout
	if active and presets[active] then return presets[active].layoutName end
	for _, preset in ipairs(presets) do
		if preset.layoutName == ns.chardb.layoutOwn then return preset.layoutName end
	end
	return presets[1] and presets[1].layoutName
end

-- The action bars one of ours lays out (def.bars: 2 = MultiBarBottomLeft, 3 =
-- MultiBarBottomRight...), switched on when it's switched to: they're the
-- game's Action Bars options, not part of a layout. The ones Cinematic
-- switched on (chardb.layoutBarsOn) go back off on any other layout.
local function SyncBars(name)
	if not (GetActionBarToggles and SetActionBarToggles) or not ns.chardb then return end
	local def = name and ns.EDIT_MODE_LAYOUTS[name]
	local toggles = { GetActionBarToggles() }
	local on = ns.chardb.layoutBarsOn or {}
	local changed = false
	if def and def.bars then
		for _, bar in ipairs(def.bars) do
			if toggles[bar - 1] == false then
				toggles[bar - 1], on[bar] = true, true
				changed = true
			end
		end
	else
		for bar in pairs(on) do
			if toggles[bar - 1] then
				toggles[bar - 1] = false
				changed = true
			end
		end
		on = {}
	end
	ns.chardb.layoutBarsOn = next(on) and on or nil
	if not changed then return end
	-- (Not MultiActionBar_Update: called from here it taints the bars' buttons,
	-- and their cooldowns then error on secret values. The game shows the
	-- bars as toggled on the next reload.)
	SetActionBarToggles(unpack(toggles))
	StaticPopup_Show("CINEMATIC_BARS_RELOAD")
	ns.Log("state", "edit mode layout action bars: " .. (def and "on" or "back off"))
end

-- Switches Edit Mode's layout, with the faded frames at full size for it
-- (Frames.lua: shrunk, they'd keep their old size and place).
local function SetActive(index)
	if ns.UnshrinkForLayout then ns.UnshrinkForLayout() end
	C_EditMode.SetActiveLayout(index)
	SyncBars(NameAt(C_EditMode.GetLayouts(), index))
end

-- Without an export string: the Modern preset with the dev's changes to it
-- (the layout as it was at 17:30 on 2026-10-20, read from the game's own
-- Edit Mode save). Each: Enum.EditModeSystem, its index (nil: none), where
-- it's anchored (none: where Modern has it), and the settings that differ
-- from Modern (setting = value).
local UNIT_FRAME = Enum.EditModeSystem and Enum.EditModeSystem.UnitFrame or 3
local PARTY = Enum.EditModeUnitFrameSystemIndices and Enum.EditModeUnitFrameSystemIndices.Party or 4
local RAID_STYLE_PARTY = Enum.EditModeUnitFrameSetting and Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames or 4
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
	{ 15, 1, "BOTTOM", "UIParent", "BOTTOM", 0, 0, { [3] = 0 } },           -- status bar 1
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
	-- (No anchor: where Modern has it.)
	{ UNIT_FRAME, PARTY, nil, nil, nil, nil, nil, { [RAID_STYLE_PARTY] = 1 } }, -- party frames: raid-style
}

-- Cinematic's own layouts, by the name Edit Mode lists them under. export:
-- an Edit Mode export string (Share > Copy to Clipboard); without one, design:
-- changes to the Modern preset (as DESIGN). bars: the action bars it lays
-- out, switched on with it (SyncBars).
-- label: its name on the Profiles page's layout menu (listed on client only,
-- unless it's in Edit Mode already).
ns.EDIT_MODE_LAYOUTS = {
	[ns.LAYOUT_NAME] = { export = nil, design = DESIGN, bars = { 2, 3 },
		label = "Cinematic's retail look", client = "forever" },
	-- Retail laid out like WoW Forever's default (the retail profile "Forever").
	-- Not designed yet: a copy of Modern until its export string's in.
	CINE_RETAIL_FOREVER_LAYOUT = { export = nil, design = {},
		label = "Cinematic's WoW Forever look", client = "retail" },
}

local function ApplyDesign(layout, design)
	for _, system in ipairs(layout.systems or {}) do
		for _, saved in ipairs(design) do
			if system.system == saved[1] and system.systemIndex == saved[2] then
				if saved[3] then
					system.isInDefaultPosition = false
					system.anchorInfo = { point = saved[3], relativeTo = saved[4], relativePoint = saved[5],
						offsetX = saved[6], offsetY = saved[7] }
				end
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
	SetActive(active)
	return true
end

-- One of ours made again from the code (the Profiles page's Regenerate, the
-- Dev page's buttons), undoing changes made to it in Edit Mode, and switched
-- to. One that was there already offers a reload (Edit Mode shows its old
-- copy until then), after which it's switched to again.
function ns.RegenerateLayout(name)
	local updating = ns.LayoutState(name) ~= nil
	local ok, reason = ns.MakeLayout(name)
	if not ok then
		ns.Print(reason)
	elseif updating then
		-- (the reload puts Edit Mode back on the layout it had: switched again after it)
		ns.chardb.layoutPending = name
		StaticPopup_Show("CINEMATIC_LAYOUT_RELOAD")
	end
	return ok
end

-- Whether one of ours is there: nil: no; "active" or "made" (another in use).
function ns.LayoutState(name)
	if not (C_EditMode and C_EditMode.GetLayouts) then return nil end
	local info, index = FindLayout(name)
	if not index then return nil end
	return ActiveName(info) == name and "active" or "made"
end

-- On logging in (or a reload), once Edit Mode has its layouts: the layout
-- just made (the Dev page's Update), switched to again; otherwise the
-- profile's, as on switching to it. Edit Mode keeps a layout per character,
-- so one logged into from a character on another profile can be on the
-- wrong one (Retail's on a character whose profile isn't Retail).
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_ENTERING_WORLD")
login:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	if not (C_EditMode and C_EditMode.GetLayouts) or not ns.chardb then return end
	local name = ns.chardb.layoutPending
	ns.chardb.layoutPending = nil
	C_Timer.After(1, function()
		if not name then
			if ns.ProfileChosen() then ns.ApplyProfileLayout() end
			return
		end
		if InCombatLockdown() then return end
		local info = C_EditMode.GetLayouts()
		local index = IndexOf(info, name)
		if index and info.activeLayout ~= index then
			SetActive(index)
		end
	end)
end)

-- The profile's Edit Mode layout (db.editModeLayout, from its layout part,
-- or picked on the Profiles page): on switching profile (Profiles.lua) and
-- logging in, Edit Mode goes to it, after the fight if in one; one of ours
-- is made if it isn't there. "": the player's own, the one they were on
-- before a profile switched it (chardb.layoutOwn), back; on one of ours with
-- none saved, the first preset (Modern).
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
		ns.chardb.layoutOwn = nil -- (back on it: or, gone, nothing to go back to)
		local index = own and IndexOf(info, own)
		if not index and ns.EDIT_MODE_LAYOUTS[ActiveName(info) or ""] then
			own = Presets()[1] and Presets()[1].layoutName
			index = own and IndexOf(info, own)
		end
		if index and info.activeLayout ~= index then
			SetActive(index)
			ns.Log("state", "edit mode layout back to: " .. own)
		end
		return
	end
	name = Target(info, name)
	if not name then return end
	-- (the one to go back to: what's on now, unless a profile's switched it already)
	local current = ActiveName(info)
	if not ns.chardb.layoutOwn and current ~= name then ns.chardb.layoutOwn = current end
	local index = IndexOf(info, name)
	if not index then
		if ns.EDIT_MODE_LAYOUTS[name] then
			local ok, reason = ns.MakeLayout(name)
			if not ok then
				ns.Print(L["couldn't add this profile's Edit Mode layout: %s"]:format(reason))
			end
		elseif not missingSaid[name] then
			missingSaid[name] = true
			ns.Print(L["this profile's Edit Mode layout, %s, isn't there; your layout stays as it is"]:format(name))
		end
		return
	end
	if info.activeLayout ~= index then
		SetActive(index)
		ns.Log("state", "edit mode layout: " .. name)
	else
		SyncBars(name) -- (on it already: its bars may still be off)
	end
end

-- Resetting Cinematic (ns.ResetAddon): back on the player's own layout (the
-- one before a profile switched it; on one of ours with none saved, the
-- first preset), and Cinematic's own layouts deleted from Edit Mode. Not in
-- combat: false then (and done nothing).
function ns.ResetLayouts()
	if not (C_EditMode and C_EditMode.GetLayouts) or not ns.chardb then return true end
	if InCombatLockdown() then return false end
	local info = C_EditMode.GetLayouts()
	local own = ns.chardb.layoutOwn
	local active = ActiveName(info)
	if own and IndexOf(info, own) then
		active = own
	elseif active and ns.EDIT_MODE_LAYOUTS[active] then
		active = Presets()[1] and Presets()[1].layoutName
	end
	ns.chardb.layoutOwn = nil
	local kept, removed = {}, 0
	for _, layout in ipairs(info.layouts) do
		if ns.EDIT_MODE_LAYOUTS[layout.layoutName] then
			removed = removed + 1
		else
			kept[#kept + 1] = layout
		end
	end
	if removed > 0 then
		info.layouts = kept
		info.activeLayout = (active and IndexOf(info, active)) or 1
		if ns.UnshrinkForLayout then ns.UnshrinkForLayout() end
		C_EditMode.SaveLayouts(info)
		ns.Log("state", ("reset: %d edit mode layout(s) deleted, on %s"):format(removed, tostring(active)))
	end
	local index = active and IndexOf(C_EditMode.GetLayouts(), active)
	if index and C_EditMode.GetLayouts().activeLayout ~= index then SetActive(index) end
	SyncBars(active)
	return true
end

-- Whether ns.ApplyProfileLayout would switch Edit Mode's layout now (one of
-- ours not made yet counts: it's made and switched to).
function ns.LayoutWouldChange()
	if not (C_EditMode and C_EditMode.GetLayouts) or not ns.db or not ns.chardb or InCombatLockdown() then
		return false
	end
	local manager = _G.EditModeManagerFrame
	if manager and manager:IsShown() then return false end
	local name = ns.db.editModeLayout or ""
	local info = C_EditMode.GetLayouts()
	if name == "" then
		name = ns.chardb.layoutOwn
		if not (name and IndexOf(info, name)) and ns.EDIT_MODE_LAYOUTS[ActiveName(info) or ""] then
			name = Presets()[1] and Presets()[1].layoutName
		end
	else
		name = Target(info, name)
	end
	if not name then return false end
	local index = IndexOf(info, name)
	if not index then return ns.EDIT_MODE_LAYOUTS[name] ~= nil end
	return info.activeLayout ~= index
end

-- On switching profile: a layout change waits for the UI to fade out first
-- (Core.lua: up to LAYOUT_FADE_MAX), so the frames aren't seen moving; then
-- the profile's preview, if it has one (ns.PreviewProfile). Mid-fight, or
-- no change: as it is.
local LAYOUT_FADE_MAX = 2.5
function ns.SwitchProfileLayout()
	if ns.LayoutWouldChange() then
		ns.layoutFadeUntil = GetTime() + LAYOUT_FADE_MAX
	else
		ns.ApplyProfileLayout()
	end
end

-- (Core.lua, each tick while fading for it: once everything's faded, out of
-- time, or a fight starts.)
function ns.FinishLayoutFade()
	ns.layoutFadeUntil = nil
	ns.ApplyProfileLayout()
	local pending = ns.pendingPreview
	ns.pendingPreview = nil
	if pending then ns.PreviewProfile(pending) end
end

-- The Profiles page's layout menu ({ value, text } for db.editModeLayout):
-- leave it, the game's own, then the layouts as Edit Mode lists them (the
-- saved ones by their names, then the presets; the Gamepad preset only in
-- gamepad mode), Cinematic's own for this client to add if it isn't made,
-- and the profile's if it's gone.
local PRESETS_SHOWN = 2 -- (Modern and Classic; WoW Forever's third is Gamepad)
function ns.LayoutChoices()
	local choices = {
		{ value = "", text = L["Your own (Cinematic leaves it alone)"] },
		{ value = ns.LAYOUT_PRESET, text = L["The game's own (Modern or Classic)"] },
	}
	local info = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
	if not (info and info.layouts) then return choices end
	local listed = { [""] = true, [ns.LAYOUT_PRESET] = true }
	local function Add(name, text)
		if not name or listed[name] then return end
		listed[name] = true
		choices[#choices + 1] = { value = name, text = text or name }
	end
	for _, layout in ipairs(info.layouts) do Add(layout.layoutName) end
	local gamepad = ns.IsGamePadOn and ns.IsGamePadOn()
	for i, preset in ipairs(Presets()) do
		if i <= PRESETS_SHOWN or gamepad or preset.layoutName == (ns.db and ns.db.editModeLayout) then
			Add(preset.layoutName, L["%s (Preset)"]:format(preset.layoutName))
		end
	end
	for name, def in pairs(ns.EDIT_MODE_LAYOUTS) do
		if def.client == ns.CLIENT then Add(name, L["Add %s to Edit Mode"]:format(L[def.label])) end
	end
	local current = ns.db and ns.db.editModeLayout
	if current then Add(current, L["%s (not in Edit Mode)"]:format(current)) end
	return choices
end

-- Leaving Edit Mode on another layout than the profile's: the profile takes
-- it (a profile that leaves the layout alone stays so; one on the game's
-- own stays so while it's a preset), so logging in, or switching back to the
-- profile, puts the player's own pick back.
local function AdoptLayout()
	if not ns.db or not ns.chardb or not ns.ProfileChosen() then return end
	local want = ns.db.editModeLayout or ""
	if want == "" then return end
	local info = C_EditMode.GetLayouts()
	local active = ActiveName(info)
	if not active or active == Target(info, want) then return end
	if want == ns.LAYOUT_PRESET and info.activeLayout <= #Presets() then return end
	ns.db.editModeLayout = active
	ns.chardb.layoutOwn = nil -- (the player's pick now: nothing to go back to)
	SyncBars(active)
	ns.Print(L["the %s profile now uses the Edit Mode layout %s"]:format(
		ns.ProfileLabel(ns.ActiveProfile()), active))
	ns.Log("state", "edit mode layout picked in edit mode: " .. active)
	if ns.RefreshOptions then ns.RefreshOptions() end
end
if _G.EditModeManagerFrame and C_EditMode and C_EditMode.GetLayouts then
	_G.EditModeManagerFrame:HookScript("OnHide", AdoptLayout)
end

ns.OnLanguage(function()
	StaticPopupDialogs.CINEMATIC_LAYOUT_RELOAD = {
		text = L["Edit Mode keeps its old list of layouts until you reload, and saving there before then " ..
			"would undo this. Reload now?"],
		button1 = RELOADUI or L["Reload"], button2 = L["Later"],
		OnAccept = ReloadUI,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	StaticPopupDialogs.CINEMATIC_BARS_RELOAD = {
		text = L["This Edit Mode layout's action bars come on or off after a reload. Reload now?"],
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
			ns.RegenerateLayout(row.name)
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
