-- Cinematic settings: a panel under Options > AddOns, also opened with /cine config
local _, ns = ...

-- Each page is a canvas (registered with the Settings panel) holding a scroll
-- frame; the panel/cameraPanel/extrasPanel variables are the scrolling content
-- that the widgets are built on.
local panel, category, extrasPanel, cameraPanel, chatPanel
local mainCanvas
local controls = {}   -- widgets that mirror a db key, refreshed on show
-- The settings each page's controls show (page content frame -> key -> true),
-- for its "Reset page" button.
local pageKeys = {}
local function RecordKey(parent, key)
	if type(key) == "string" then
		pageKeys[parent] = pageKeys[parent] or {}
		pageKeys[parent][key] = true
	end
end
local extraRows = {}
local sliderCount = 0

local function Tooltip(widget, tip)
	widget:SetScript("OnEnter", function(self)
		-- A slider's label can run past its bar: the tip goes beyond whichever
		-- ends further right, so it never covers the value.
		local label = self.tooltipLabel
		if label and label:GetRight() and self:GetRight() and label:GetRight() > self:GetRight() then
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOMLEFT", label, "TOPRIGHT", 8, 0)
		else
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		end
		GameTooltip:SetText(tip, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Label(parent, font, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH("LEFT")
	fs:SetText(text or "")
	return fs
end

local function Header(parent, text, anchor, yOffset)
	local fs = Label(parent, "GameFontNormal", text)
	fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset or -18)
	return fs
end

-- Lays out a column of controls, each below the last, the same way on every
-- page: headers and notes at the column edge, checkboxes 2 left of it (so the
-- box lines up), sliders 2 right and edit boxes 6 right (their borders).
local STACK_X = { header = 0, label = 0, dropdown = 0, check = -2, slider = 2, box = 6 }
local STACK_GAP = { -- [kind being added][kind above it]
	header = { header = 6, label = 18, dropdown = 18, check = 18, slider = 24, box = 18 },
	label = { header = 6, label = 6, dropdown = 6, check = 8, slider = 14, box = 4 },
	dropdown = { header = 8, label = 6, dropdown = 8, check = 6, slider = 14, box = 8 },
	check = { header = 6, label = 8, dropdown = 8, check = 2, slider = 14, box = 8 },
	slider = { header = 26, label = 26, dropdown = 30, check = 26, slider = 34, box = 30 },
	box = { header = 6, label = 4, dropdown = 8, check = 4, slider = 14, box = 8 },
}

local function Stack(anchor, kind)
	local stack = { last = anchor, kind = kind or "header", indent = 0 }
	-- Puts control below the last one. indent: how far right of the usual
	-- place it sits (children of a checkbox); the next control is placed from it.
	function stack:Add(control, controlKind, indent)
		indent = indent or 0
		control:SetPoint("TOPLEFT", self.last, "BOTTOMLEFT",
			STACK_X[controlKind] + indent - STACK_X[self.kind] - self.indent,
			-STACK_GAP[controlKind][self.kind])
		self.last, self.kind, self.indent = control, controlKind, indent
		return control
	end
	function stack:Header(parent, text)
		return self:Add(Label(parent, "GameFontNormal", text), "header")
	end
	-- A note in small text, wrapped to width.
	function stack:Note(parent, text, width)
		local note = Label(parent, "GameFontHighlightSmall", text)
		note:SetWidth(width or 270)
		note:SetJustifyV("TOP")
		return self:Add(note, "label")
	end
	-- Carries on from a control placed some other way.
	function stack:Continue(control, controlKind)
		self.last, self.kind, self.indent = control, controlKind, 0
	end
	return stack
end

local function Check(parent, key, label, tip, onChange)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	local text = cb.Text or cb.text
	if not text then
		text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	end
	text:SetFontObject("GameFontHighlight")
	text:SetText(label)
	if tip then Tooltip(cb, tip) end

	cb:SetScript("OnClick", function(self)
		local value = self:GetChecked() and true or false
		if onChange then onChange(value) else ns.GetDB()[key] = value end
	end)
	cb.Refresh = function(self) self:SetChecked(ns.GetDB()[key]) end
	controls[#controls + 1] = cb
	RecordKey(parent, key)
	return cb
end

-- A labelled slider. `scale` converts between stored and shown values
-- (letterbox size is stored as a fraction but shown as a percent).
local function Slider(parent, key, label, minV, maxV, step, fmt, scale, onChange)
	scale = scale or 1
	RecordKey(parent, key)
	sliderCount = sliderCount + 1
	local name = "CinematicOptionsSlider" .. sliderCount
	local ok, slider = pcall(CreateFrame, "Slider", name, parent, "OptionsSliderTemplate")
	if not ok then
		-- Fallback for clients without the template.
		slider = CreateFrame("Slider", name, parent)
		slider:SetOrientation("HORIZONTAL")
		slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
		local bg = slider:CreateTexture(nil, "BACKGROUND")
		bg:SetColorTexture(0, 0, 0, 0.5)
		bg:SetPoint("LEFT", 0, 0)
		bg:SetPoint("RIGHT", 0, 0)
		bg:SetHeight(6)
	end
	slider:SetSize(200, 16)
	slider:SetMinMaxValues(minV, maxV)
	slider:SetValueStep(step)
	if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

	-- Hide the template's own min/max/title text; we draw a single label.
	for _, suffix in ipairs({ "Low", "High", "Text" }) do
		local fs = slider[suffix] or _G[name .. suffix]
		if fs then fs:Hide() end
	end

	local title = Label(slider, "GameFontHighlight")
	title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)
	slider.tooltipLabel = title

	local function UpdateTitle(value)
		local shown = "|cffffd100" .. (type(fmt) == "function" and fmt(value) or fmt:format(value)) .. "|r"
		title:SetText(label == "" and shown or label .. ": " .. shown)
	end
	slider.title = title

	slider:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value / step + 0.5) * step
		UpdateTitle(value)
		if self.refreshing then return end
		if type(key) == "table" then
			key.set(value / scale)
		else
			ns.GetDB()[key] = value / scale
		end
		if onChange then onChange(value) end
	end)
	slider.Refresh = function(self)
		local value = (type(key) == "table" and key.get() or ns.GetDB()[key]) * scale
		self.refreshing = true
		self:SetValue(value)
		self.refreshing = false
		UpdateTitle(value)
	end
	controls[#controls + 1] = slider
	return slider
end

-- Greys a control out unless test(db) holds (checkbox labels dim too).
local function GreyUnless(control, test)
	local refresh = control.Refresh
	control.Refresh = function(self)
		refresh(self)
		local enabled = test(ns.GetDB())
		if self.SetEnabled then self:SetEnabled(enabled) end
		local label = self.Text or self.text
		if label and self.GetObjectType and self:GetObjectType() == "CheckButton" then
			label:SetFontObject(enabled and "GameFontHighlight" or "GameFontDisable")
		end
	end
end

-- Music options only do anything while the addon handles music.
local function DependsOnMusic(control)
	GreyUnless(control, function(db) return db.musicInCinematic end)
end

local function Refresh()
	if not ns.GetDB() then return end
	for _, control in ipairs(controls) do
		control:Refresh()
	end
end

-- A checkbox that acts as one choice in a group sharing a db key.
local function Choice(parent, key, value, label, tip)
	local cb = Check(parent, key, label, tip, function()
		ns.GetDB()[key] = value
		Refresh()
	end)
	cb.Refresh = function(self) self:SetChecked(ns.GetDB()[key] == value) end
	return cb
end

-- A dropdown for a db key with a fixed set of choices ({ value, text }).
-- Returns nil on clients without the modern dropdown template.
local function Dropdown(parent, key, choices, width, onChange)
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if not ok or not dropdown or not dropdown.SetupMenu then
		return nil
	end
	dropdown:SetWidth(width or 200)
	dropdown:SetupMenu(function(_, rootDescription)
		for _, choice in ipairs(choices) do
			rootDescription:CreateRadio(choice.text,
				-- SetupMenu builds the menu right away, before saved settings load.
				function()
					local db = ns.GetDB()
					return db ~= nil and db[key] == choice.value
				end,
				function()
					ns.GetDB()[key] = choice.value
					if onChange then onChange(choice.value) end
					Refresh()
				end)
		end
	end)
	dropdown.Refresh = function(self) self:GenerateMenu() end
	controls[#controls + 1] = dropdown
	RecordKey(parent, key)
	return dropdown
end

local SCROLLBAR_WIDTH = 26

-- Puts a page's settings back to their defaults: each setting its controls
-- show (a list kept as a table, like the Standard Frames columns, is emptied,
-- which means its defaults).
local function ResetPage(content)
	local db = ns.GetDB()
	for key in pairs(pageKeys[content] or {}) do
		local default = ns.DEFAULTS[key]
		if type(db[key]) == "table" and default == nil then
			for k in pairs(db[key]) do db[key][k] = nil end
		else
			db[key] = default
		end
	end
	ns.letterboxDirty = true
	if ns.RefreshTint then ns.RefreshTint() end
	Refresh()
end

StaticPopupDialogs.CINEMATIC_RESET_PAGE = {
	text = "Put this page's settings back to their defaults?",
	button1 = YES, button2 = NO,
	OnAccept = function(_, content) ResetPage(content) end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

-- noReset: no "Reset page" button (the main page has its own reset for everything).
local function CreateScrollPage(noReset)
	local canvas = CreateFrame("Frame")
	local scroll = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_WIDTH, 4)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(600, 1)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(_, width)
		content:SetWidth(width)
	end)
	-- Every page gets a "Reset page" button, top right; it stays put as the
	-- page scrolls, and goes on a page with no settings of its own.
	local reset = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
	reset:SetSize(100, 22)
	reset:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -SCROLLBAR_WIDTH - 8, -12)
	reset:SetText("Reset page")
	Tooltip(reset, "Put this page's settings back to their defaults.")
	reset:SetScript("OnClick", function()
		StaticPopup_Show("CINEMATIC_RESET_PAGE", nil, nil, content)
	end)
	reset:SetScript("OnShow", function(self)
		if noReset or not pageKeys[content] then
			self:Hide()
		end
	end)
	return canvas, content
end

-- Size the scrolling content to reach just past its lowest widget, so the
-- scroll range always fits however many settings a page has.
local function FitContentHeight(content)
	local top = content:GetTop()
	if not top then
		return
	end
	local lowest = top
	local function consider(object)
		if object:IsShown() then
			local bottom = object:GetBottom()
			if bottom and bottom < lowest then
				lowest = bottom
			end
		end
	end
	for _, child in ipairs({ content:GetChildren() }) do
		consider(child)
		if child:IsShown() then
			for _, grandchild in ipairs({ child:GetChildren() }) do consider(grandchild) end
			for _, region in ipairs({ child:GetRegions() }) do consider(region) end
		end
	end
	for _, region in ipairs({ content:GetRegions() }) do consider(region) end
	content:SetHeight(top - lowest + 16)
end

-- OnShow for a page: refresh, then fit the scroll height (again next frame,
-- once text and anchors have settled).
local function PageShown(refresh, content)
	return function()
		refresh()
		FitContentHeight(content)
		C_Timer.After(0, function() FitContentHeight(content) end)
	end
end

local function CreatePanel()
	mainCanvas, panel = CreateScrollPage(true)
	mainCanvas.name = "Cinematic"

	local title = Label(panel, "GameFontNormalLarge", "Cinematic")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(panel, "GameFontHighlightSmall",
		"Fades the UI and adds letterbox bars between fights. Combat, casting " ..
		"and opening windows like the spellbook bring it back. Typing just shows the chat. The " ..
		"pages under this one cover what shows when (CineMode, Standard Frames, 3rd Party Frames, Minimap, Quest tracker, Nameplates, " ..
		"Chat), visual effects and sound, the camera modes and triggers, and keybinds.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Left column: general
	local general = Header(panel, "General", subtitle, -20)

	local enabled = Check(panel, "enabled", "Enable Cinematic",
		"Also toggled with /cine or the keybind under Key Bindings > AddOns.", ns.SetEnabled)
	enabled:SetPoint("TOPLEFT", general, "BOTTOMLEFT", -2, -6)

	local minimapButton = Check(panel, "minimapButton", "Show minimap button",
		"Left-click it for quick options (turn off for a while, combat, tint), right-click for " ..
		"these settings, drag to move it.", function(value)
			ns.GetDB().minimapButton = value
			if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
		end)
	minimapButton:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -2)

	-- The same setting as "Turn off in: Combat" on the right, the right way round.
	local stay = Check(panel, "stayInCombat", "Stay in CineMode in combat",
		"Fights don't bring the whole UI back: only the frames ticked under In combat on the " ..
		"Standard Frames page show. Off: being in combat brings the UI back. Same as unticking " ..
		"\"Turn off in: Combat\".", function(value)
			ns.GetDB().stayInCombat = value
			Refresh() -- grey out / enable the In combat column
		end)
	stay:SetPoint("TOPLEFT", minimapButton, "BOTTOMLEFT", 0, -2)

	-- Right column: places
	local placesHeader = Label(panel, "GameFontNormal", "Turn off in")
	placesHeader:SetPoint("TOPLEFT", general, "TOPLEFT", 320, 0)

	-- Stored the other way round (stayInCombat), as the Standard Frames page's lists apply while staying.
	local combat = Check(panel, "stayInCombat", "Combat",
		"Being in combat brings the UI back. Targeting an enemy only shows the frames chosen " ..
		"for it on the Standard Frames page. Untick to stay cinematic in combat too.", function(value)
			ns.GetDB().stayInCombat = not value
			Refresh()
		end)
	combat.Refresh = function(self) self:SetChecked(not ns.GetDB().stayInCombat) end
	combat:SetPoint("TOPLEFT", placesHeader, "BOTTOMLEFT", -2, -6)

	-- Places in the same order as every other place list (PlaceList).
	local world = Check(panel, "offInWorld", "Open world",
		"Anywhere outside cities, dungeons, raids, battlegrounds and arenas (inns too). " ..
		"Flights still go cinematic.")
	world:SetPoint("TOPLEFT", combat, "BOTTOMLEFT", 0, -2)

	local cities = Check(panel, "offInCities", "Cities",
		"Capital cities, including Dalaran. Flights leaving a city still go cinematic.")
	cities:SetPoint("TOPLEFT", world, "BOTTOMLEFT", 0, -2)

	local dungeons = Check(panel, "offInDungeons", "Dungeons",
		"Keep the normal UI in dungeons and scenarios.")
	dungeons:SetPoint("TOPLEFT", cities, "BOTTOMLEFT", 0, -2)

	local raids = Check(panel, "offInRaids", "Raids")
	raids:SetPoint("TOPLEFT", dungeons, "BOTTOMLEFT", 0, -2)

	local pvp = Check(panel, "offInPvP", "Battlegrounds and arenas")
	pvp:SetPoint("TOPLEFT", raids, "BOTTOMLEFT", 0, -2)

	local party = Check(panel, "offInParty", "A party",
		"Keep the normal UI while you're in a party (but not a raid group).")
	party:SetPoint("TOPLEFT", pvp, "BOTTOMLEFT", 0, -2)

	local raidGroup = Check(panel, "offInRaidGroup", "A raid group",
		"Keep the normal UI while you're in a raid group, wherever you are.")
	raidGroup:SetPoint("TOPLEFT", party, "BOTTOMLEFT", 0, -2)

	local defaults = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	defaults:SetSize(140, 22)
	defaults:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -12)
	defaults:SetText("Reset settings")
	Tooltip(defaults, "Restore the default settings. Frames you added or stopped fading are kept.")
	defaults:SetScript("OnClick", function()
		ns.ResetSettings()
		Refresh()
	end)

	mainCanvas:SetScript("OnShow", PageShown(Refresh, panel))
	mainCanvas:Hide() -- so OnShow fires on the first visit too

	if Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(mainCanvas, "Cinematic")
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(mainCanvas)
	end
end

local function RegisterSubpage(subpanel, name)
	subpanel.name = name
	subpanel.parent = "Cinematic"
	if category and Settings and Settings.RegisterCanvasLayoutSubcategory then
		local sub = Settings.RegisterCanvasLayoutSubcategory(category, subpanel, name)
		Settings.RegisterAddOnCategory(sub)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(subpanel)
	end
end

-- Sub-page: what brings faded things back, and what stays up.
local function CreateRevealPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "CineMode")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"How fast the UI fades, what brings it (or parts of it) back while CineMode " ..
		"is on, and combat text. Fights and targeting are on the Standard Frames page, names and " ..
		"nameplates on the Nameplates page, buffs on the " ..
		"Buffs/debuffs page, the minimap on the Minimap page, the quest tracker on the Quest tracker page, " ..
		"chat on the Chat page.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	local OVERRIDE_COLUMN, OVERRIDE_ROW = 300, 28

	-- Fading (full width): how fast the UI goes and comes back
	local fadingHeader = Header(content, "Fading", subtitle, -20)

	local fadeIn = Slider(content, "fadeInTime", "Fade in time", 0, 10, 0.1, "%.1f sec")
	fadeIn:SetPoint("TOPLEFT", fadingHeader, "BOTTOMLEFT", 2, -26)

	local fadeOut = Slider(content, "fadeOutTime", "Fade out time", 0, 10, 0.1, "%.1f sec")
	fadeOut:SetPoint("TOPLEFT", fadeIn, "BOTTOMLEFT", 0, -34)
	Tooltip(fadeOut, "How long the UI takes to fade out. The mouseover times below include it: " ..
		"a time shorter than the fade just fades straight away.")

	local calm = Slider(content, "calmTime", "Calm Timer", 0, 120, 5, "%d sec after a fight")
	calm:SetPoint("TOPLEFT", fadeOut, "BOTTOMLEFT", 0, -34)
	Tooltip(calm, "How long things take to settle back into CineMode after a fight. " ..
		"Nameplates and names ticked In combat stay up this long (so they don't drop away " ..
		"between pulls), and the letterbox and tint, if they step aside for fights, wait this " ..
		"long before fading back in. Your portrait and buffs, if they only show after combat, " ..
		"count a fight as recent for this long too, the RP walk, auto-run and cozy cameras " ..
		"wait this long before starting, and music muted for fights comes back after it. 0 " ..
		"settles at once.")

	-- Mouseover (full width): the shared hold time, and per-group overrides
	local mouseHeader = Header(content, "Mouseover", calm, -24)
	mouseHeader:SetPoint("TOPLEFT", calm, "BOTTOMLEFT", -2, -24)

	local mouseover = Check(content, "mouseover", "Reveal on mouseover",
		"Pointing at a faded element shows it (and the elements grouped with it).", function(value)
			ns.GetDB().mouseover = value
			Refresh() -- grey out / enable the hold times
		end)
	mouseover:SetPoint("TOPLEFT", mouseHeader, "BOTTOMLEFT", -2, -6)
	local function IfMouseover(db) return db.mouseover end

	local hold = Slider(content, "mouseoverHold", "Stays after mouseover", 0, 30, 1, "%d sec")
	hold:SetPoint("TOPLEFT", mouseover, "BOTTOMLEFT", 4, -26)
	Tooltip(hold, "How long until a group is gone after your mouse leaves it, fade included, " ..
		"unless it has its own time below. In the camera modes the shorter default is used.")
	GreyUnless(hold, IfMouseover)

	local overrideLabel = Label(content, "GameFontHighlightSmall",
		"Tick a group to give it its own time instead:")
	overrideLabel:SetPoint("TOPLEFT", hold, "BOTTOMLEFT", -2, -18)

	local OVERRIDE_ROWS = math.ceil(#ns.HOVER_GROUPS / 2)
	local lastOverride
	for i, group in ipairs(ns.HOVER_GROUPS) do
		local key, label = group[1], group[2]
		local column, row = math.floor((i - 1) / OVERRIDE_ROWS), (i - 1) % OVERRIDE_ROWS
		local override = Check(content, key .. "HoverOverride", label,
			"Give this group its own time instead of \"Stays after mouseover\".",
			function(value)
				ns.GetDB()[key .. "HoverOverride"] = value
				Refresh()
			end)
		override:SetPoint("TOPLEFT", overrideLabel, "BOTTOMLEFT",
			column * OVERRIDE_COLUMN, -4 - row * OVERRIDE_ROW)
		GreyUnless(override, IfMouseover)

		local groupHold = Slider(content, key .. "HoverHold", "", 0, 30, 1, "%d sec")
		groupHold:SetWidth(80)
		groupHold:SetPoint("LEFT", override, "LEFT", 150, 0)
		groupHold.title:ClearAllPoints()
		groupHold.title:SetPoint("LEFT", groupHold, "RIGHT", 6, 0)
		Tooltip(groupHold, "How long until this group is gone after your mouse leaves it, fade " ..
			"included. In the camera modes the shorter default is used.")
		GreyUnless(groupHold, function(db) return db.mouseover and db[key .. "HoverOverride"] end)
		if row == OVERRIDE_ROWS - 1 and column == 0 then
			lastOverride = override
		end
	end

	-- One column of sections, each below the last: what brings the UI back,
	-- combat text, your portrait.
	local revealHeader = Header(content, "Exit CineMode", lastOverride, -18)
	revealHeader:SetPoint("TOPLEFT", lastOverride, "BOTTOMLEFT", 2, -18)

	local cast = Check(content, "revealOnCast", "While casting",
		"Includes mounting and hearthstone casts.")
	cast:SetPoint("TOPLEFT", revealHeader, "BOTTOMLEFT", -2, -6)

	local npcs = Check(content, "revealAtNPCs", "At vendors, banks, mail and trainers",
		"Exit CineMode while a vendor, bank, mailbox, class trainer, trade or auction " ..
		"house window is open. When off, the window still shows but the rest stays hidden.")
	npcs:SetPoint("TOPLEFT", cast, "BOTTOMLEFT", 0, -2)

	-- Stored the other way round (stayWithWindows), like the rest of this
	-- section reading as what brings the UI back.
	local windows = Check(content, "stayWithWindows", "Opening windows",
		"Exit CineMode while the spellbook, character sheet, talents, macros, key " ..
		"bindings or these options are open. When off, the window still shows but the rest " ..
		"stays hidden.", function(value)
			ns.GetDB().stayWithWindows = not value
		end)
	windows.Refresh = function(self) self:SetChecked(not ns.GetDB().stayWithWindows) end
	windows:SetPoint("TOPLEFT", npcs, "BOTTOMLEFT", 0, -2)

	local drag = Check(content, "revealOnDrag", "While dragging something",
		"Picking up an item or spell (to drag it to your action bars, say) brings the UI back " ..
		"until you put it down. Off: picking things up never does; mouse over a faded bar to " ..
		"see it when dragging there.")
	drag:SetPoint("TOPLEFT", windows, "BOTTOMLEFT", 0, -2)

	local returnDelay = Slider(content, "returnDelay", "Back into CineMode after", 0, 60, 1, "%d sec")
	returnDelay:SetPoint("TOPLEFT", drag, "BOTTOMLEFT", 4, -26)
	Tooltip(returnDelay, "How long things must stay calm (no cast, window, dragging and the like) " ..
		"before CineMode comes back. After a fight it comes back at once instead. 0 returns at once.")

	local combatTextHeader = Header(content, "Combat text", returnDelay, -24)
	combatTextHeader:SetPoint("TOPLEFT", returnDelay, "BOTTOMLEFT", -2, -24)

	local combatText = Check(content, "hideCombatText", "Hide combat text out of combat",
		"No floating damage and healing numbers (like \"+10\" from a heal or regen) in cinematic " ..
		"mode while you're out of combat. They come back the moment a fight starts, and your " ..
		"combat text settings are put back when the UI returns.")
	combatText:SetPoint("TOPLEFT", combatTextHeader, "BOTTOMLEFT", -2, -6)

	local yoursHeader = Header(content, "Your portrait", combatText, -24)
	yoursHeader:SetPoint("TOPLEFT", combatText, "BOTTOMLEFT", 2, -24)

	local portrait = Check(content, "portraitWhenNotFull", "Show your portrait until health and power are full",
		"Keeps your player portrait up while you're recovering. Rage and runic power don't " ..
		"count, so a warrior's portrait hides once their health is full.")
	portrait:SetPoint("TOPLEFT", yoursHeader, "BOTTOMLEFT", -2, -6)
	portrait:HookScript("OnClick", Refresh) -- grey out / enable the options below

	-- Child: only apply the rule within the Calm Timer of a fight
	local PORTRAIT_INDENT = 16
	local function IfPortrait(db) return db.portraitWhenNotFull end

	local afterCombat = Check(content, "portraitAfterCombat", "Only after combat",
		"Only keep the portrait up if you've been in combat (or taken fall damage) within the " ..
		"Calm Timer above, so things like casting a buff in town don't bring it up.")
	afterCombat:SetPoint("TOPLEFT", portrait, "BOTTOMLEFT", PORTRAIT_INDENT, -2)
	GreyUnless(afterCombat, IfPortrait)

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "CineMode")
end

-- Sub-page: your buffs and debuffs, shown when you gain one and on hover.
local function CreateBuffsPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Buffs/debuffs")
	title:SetPoint("TOPLEFT", 16, -16)

	local note = Label(content, "GameFontHighlightSmall",
		"Your buff and debuff icons. They fade with the UI in CineMode; these bring them back.")
	note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	note:SetPoint("RIGHT", content, "RIGHT", -16, 0)

	local buffPeek = Check(content, "buffPeek", "Show buffs when you gain or refresh one",
		"A new buff or debuff, or one being refreshed, briefly shows your buffs and " ..
		"debuffs. Buffs falling off don't count, and neither do flights.")
	buffPeek:SetPoint("TOPLEFT", note, "BOTTOMLEFT", -2, -14)
	buffPeek:HookScript("OnClick", Refresh) -- grey out / enable the options below

	local BUFF_INDENT = 16
	local function IfBuffPeek(db) return db.buffPeek end

	local buffAfterCombat = Check(content, "buffPeekAfterCombat", "Only after combat",
		"Only show your buffs within the Calm Timer (above) of a fight, so buffing up or " ..
		"picking up a buff in town doesn't bring them up.")
	buffAfterCombat:SetPoint("TOPLEFT", buffPeek, "BOTTOMLEFT", BUFF_INDENT, -2)
	GreyUnless(buffAfterCombat, IfBuffPeek)

	local buffPeekTime = Slider(content, "buffPeekTime", "Show buffs for", 0.5, 30, 0.5, "%.1f sec")
	buffPeekTime:SetPoint("TOPLEFT", buffAfterCombat, "BOTTOMLEFT", 4 - BUFF_INDENT, -30)

	-- Buffs and debuffs that never bring the buffs up: a row each (icon, name,
	-- Remove), then a box to add one. Still saved as one comma-separated list
	-- (buffPeekIgnore), which is what Frames.lua reads.
	local ignoreLabel = Label(content, "GameFontHighlightSmall", "Except for these buffs and debuffs:")
	ignoreLabel:SetPoint("TOPLEFT", buffPeekTime, "BOTTOMLEFT", -2, -22)

	local function IgnoreEntries()
		local entries = {}
		for entry in (ns.GetDB().buffPeekIgnore or ""):gmatch("[^,]+") do
			entry = entry:match("^%s*(.-)%s*$")
			if entry ~= "" then
				entries[#entries + 1] = entry
			end
		end
		return entries
	end
	local function SaveEntries(entries)
		ns.GetDB().buffPeekIgnore = table.concat(entries, ", ")
		Refresh()
		FitContentHeight(content)
	end
	-- A spell ID shows as its name (and icon) in your game language.
	local function Describe(entry)
		local id = tonumber(entry)
		if not id then
			return entry, nil
		end
		local name, icon
		if C_Spell and C_Spell.GetSpellInfo then
			local info = C_Spell.GetSpellInfo(id)
			name, icon = info and info.name, info and info.iconID
		elseif GetSpellInfo then
			local _
			name, _, icon = GetSpellInfo(id)
		end
		return name and ("%s |cff808080(%d)|r"):format(name, id) or entry, icon
	end

	local ignoreRows = {}
	local function IgnoreRow(i)
		local row = ignoreRows[i]
		if not row then
			row = CreateFrame("Frame", nil, content)
			row:SetSize(300, 22)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(18, 18)
			row.icon:SetPoint("LEFT", 0, 0)
			row.text = Label(row, "GameFontHighlight")
			row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
			row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.remove:SetSize(70, 20)
			row.remove:SetPoint("RIGHT", 0, 0)
			row.remove:SetText("Remove")
			row.remove:SetScript("OnClick", function(self)
				local entries = IgnoreEntries()
				table.remove(entries, self:GetParent().index)
				SaveEntries(entries)
			end)
			ignoreRows[i] = row
		end
		return row
	end

	local addBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	addBox:SetSize(200, 20)
	addBox:SetAutoFocus(false)
	local addButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	addButton:SetSize(70, 20)
	addButton:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
	addButton:SetText("Add")
	local function AddEntry()
		local entry = addBox:GetText():gsub(",", ""):match("^%s*(.-)%s*$")
		addBox:SetText("")
		addBox:ClearFocus()
		if entry ~= "" then
			local entries = IgnoreEntries()
			for _, existing in ipairs(entries) do
				if existing:lower() == entry:lower() then
					return
				end
			end
			entries[#entries + 1] = entry
			SaveEntries(entries)
		end
	end
	addBox:SetScript("OnEnterPressed", AddEntry)
	addBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	addButton:SetScript("OnClick", AddEntry)
	local ADD_TIP = "Gaining or stacking this doesn't bring your buffs up. Type a spell ID or a " ..
		"name. Names must match your game language; spell IDs work in any language (2479 is " ..
		"Honorless Target, 8326 and 20584 are Ghost)."
	Tooltip(addBox, ADD_TIP)
	Tooltip(addButton, ADD_TIP)

	-- Rebuilt as the page shows and after each change.
	local ignoreList = { Refresh = function()
		local enabled = ns.GetDB().buffPeek and true or false
		local previous = ignoreLabel
		local entries = IgnoreEntries()
		for i, entry in ipairs(entries) do
			local row = IgnoreRow(i)
			local text, icon = Describe(entry)
			row.index = i
			row.text:SetText(text)
			row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.remove:SetEnabled(enabled)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and 6 or 0, i == 1 and -6 or -2)
			row:Show()
			previous = row
		end
		for i = #entries + 1, #ignoreRows do ignoreRows[i]:Hide() end
		addBox:ClearAllPoints()
		addBox:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", #entries == 0 and 12 or 6, -8)
		addBox:SetEnabled(enabled)
		addButton:SetEnabled(enabled)
	end }
	controls[#controls + 1] = ignoreList
	RecordKey(content, "buffPeekIgnore") -- (for Reset page)

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Buffs/debuffs")
end

-- Slow zoom controls for one profile (idleZoom* or taxiZoom*), stacked under
-- `anchor` (a checkbox). Returns the last control, for anchoring below it.
local function BuildZoomControls(parent, prefix, anchor)
	local function key(name) return prefix .. name end

	local zoomRandom = Check(parent, key("Random"), "Random zoom in and out",
		"After the first pull-back, keep drifting to new random distances (within the " ..
		"limits below), pausing between each. Off: a single pull-back that then holds.")
	zoomRandom:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)

	local zoomDistance = Slider(parent, key("Distance"), "Zoom out up to", 1, 40, 1, "%d yards")
	zoomDistance:SetPoint("TOPLEFT", zoomRandom, "BOTTOMLEFT", 4, -26)
	Tooltip(zoomDistance, "How far past your own zoom the camera pulls back (the first move always " ..
		"goes this far).")

	local zoomIn = Slider(parent, key("In"), "Zoom in up to", 0, 10, 1, "%d yards")
	zoomIn:SetPoint("TOPLEFT", zoomDistance, "BOTTOMLEFT", 0, -34)
	Tooltip(zoomIn, "Random zoom only. How much closer than your own zoom it may come.")

	local zoomTime = Slider(parent, key("Time"), "Each zoom takes", 5, 60, 1, "%d sec")
	zoomTime:SetPoint("TOPLEFT", zoomIn, "BOTTOMLEFT", 0, -34)

	local zoomEase = Slider(parent, key("Ease"), "Zoom ease in/out", 10, 50, 5, "%d%%", 100)
	zoomEase:SetPoint("TOPLEFT", zoomTime, "BOTTOMLEFT", 0, -34)
	Tooltip(zoomEase, "How much of each zoom is spent speeding up, and again slowing down. " ..
		"50% is one smooth swell; lower gets moving sooner and glides in the middle.")

	local zoomPause = Slider(parent, key("Pause"), "Pause between zooms", 0, 60, 1, "%d sec")
	zoomPause:SetPoint("TOPLEFT", zoomEase, "BOTTOMLEFT", 0, -34)
	Tooltip(zoomPause, "Random zoom only.")

	local zoomPauseVary = Slider(parent, key("PauseVary"), "Pause varies by up to", 0, 30, 0.5, "%.1f sec")
	zoomPauseVary:SetPoint("TOPLEFT", zoomPause, "BOTTOMLEFT", 0, -34)
	Tooltip(zoomPauseVary, "Random zoom only. Each pause is picked at random this much shorter or " ..
		"longer than the pause above: 3 sec with a 10 sec pause waits anywhere from 7 to 13 sec. " ..
		"0 keeps every pause the same.")

	local zoomPastMax = Check(parent, key("PastMax"), "Allow zooming past your maximum",
		"Raises the game's max camera distance (to 2.6) while pulled back, so the zoom " ..
		"isn't cut short. Your own maximum comes back once you've zoomed in again.")
	zoomPastMax:SetPoint("TOPLEFT", zoomPauseVary, "BOTTOMLEFT", -4, -14)
	return zoomPastMax
end

-- Sub-page: the camera modes, and the settings they share.
local function CreateCameraPanel()
	local cameraCanvas
	cameraCanvas, cameraPanel = CreateScrollPage()

	local title = Label(cameraPanel, "GameFontNormalLarge", "Camera Modes")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(cameraPanel, "GameFontHighlightSmall",
		"While CineMode is on, the camera comes alive in eight situations: Flight (on " ..
		"flight paths), AFK (once you've stood still a while, or go AFK), Cozy (campfires and " ..
		"emotes), Tele (casting your Hearthstone or a teleport), Vista (/stare), Fish (fishing), " ..
		"RP Walk (auto-walking) and Auto-run. Moving by hand cancels them all. Death Cam turns " ..
		"round your body when you die, and Quest Cam swings behind you at quest givers. The Camera Triggers page picks which camera each emote or " ..
		"event starts. Everything goes back to normal when the UI returns. The settings here apply " ..
		"to all of them.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", cameraPanel, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	local holdNote = Label(cameraPanel, "GameFontHighlightSmall",
		"In the camera modes, the minimap and quest tracker hover holds and the buff and chat " ..
		"peeks use their short default times, so they clear the view quickly.")
	holdNote:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
	holdNote:SetWidth(520)
	holdNote:SetJustifyV("TOP")

	-- Turn off in: a grid of each camera (rows) by place or group (columns).
	local offHeader = Header(cameraPanel, "Turn off in", holdNote, -24)
	offHeader:SetPoint("TOPLEFT", holdNote, "BOTTOMLEFT", -2, -24)
	local offNote = Label(cameraPanel, "GameFontHighlightSmall",
		"Ticked, that camera doesn't start there (and stops if it's running): the UI stays " ..
		"faded, with the camera left to you. With the Death Cam off, dying brings the UI back " ..
		"as usual. To keep the normal UI somewhere instead, use Turn off in on the main page. " ..
		"Always turns that camera off everywhere. For flights, Cities means taking off from one.")
	offNote:SetPoint("TOPLEFT", offHeader, "BOTTOMLEFT", 0, -6)
	offNote:SetWidth(520)
	offNote:SetJustifyV("TOP")
	-- Always first, set a little apart from the places and groups after it.
	local GRID_NAME_WIDTH, GRID_COLUMN, GRID_GAP = 90, 62, 10
	local GRID_PLACES = GRID_NAME_WIDTH + GRID_COLUMN + GRID_GAP
	local WHERE = {
		Cities = { "Cities", "in capital cities" },
		Dungeons = { "Dungeons", "in dungeons and scenarios" }, Raids = { "Raids", "in raids" },
		PvP = { "BGs", "in battlegrounds and arenas" },
		Party = { "Party", "while you're in a party (not a raid group)" },
		RaidGroup = { "Raid group", "while you're in a raid group" },
	}
	local gridTop = CreateFrame("Frame", nil, cameraPanel)
	gridTop:SetSize(GRID_PLACES + GRID_COLUMN * #ns.CAMERA_OFF_WHERE, 16)
	gridTop:SetPoint("TOPLEFT", offNote, "BOTTOMLEFT", 0, -10)
	local function ColumnHeader(x, label, tip)
		local cell = CreateFrame("Frame", nil, gridTop)
		cell:SetSize(GRID_COLUMN, 16)
		cell:SetPoint("LEFT", gridTop, "LEFT", x, 0)
		local text = Label(cell, "GameFontNormalSmall", label)
		text:SetPoint("CENTER")
		text:SetJustifyH("CENTER")
		Tooltip(cell, tip)
	end
	ColumnHeader(GRID_NAME_WIDTH, "Always", "Tick a camera here to turn it off everywhere.")
	for i, where in ipairs(ns.CAMERA_OFF_WHERE) do
		ColumnHeader(GRID_PLACES + GRID_COLUMN * (i - 1), WHERE[where][1],
			"Tick a camera here to turn it off " .. WHERE[where][2] .. ".")
	end
	local lastRow = gridTop
	for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do
		local row = CreateFrame("Frame", nil, cameraPanel)
		row:SetSize(gridTop:GetWidth(), 24)
		row:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, -2)
		local name = Label(row, "GameFontHighlight", cam[2])
		name:SetPoint("LEFT", row, "LEFT", 0, 0)
		local alwaysKey = cam[1] .. "OffAlways"
		local always = Check(row, alwaysKey, "", "No " .. cam[2] .. " Cam anywhere.")
		always:SetPoint("CENTER", row, "LEFT", GRID_NAME_WIDTH + GRID_COLUMN * 0.5, 0)
		always:HookScript("OnClick", Refresh) -- grey out / enable the rest of the row
		local function IfNotAlways(db) return not db[alwaysKey] end
		for i, where in ipairs(ns.CAMERA_OFF_WHERE) do
			local x = GRID_PLACES + GRID_COLUMN * (i - 0.5)
			if (ns.CAMERA_OFF_NEVER[cam[1]] or {})[where] then
				-- No flights from here: a greyed-out cross in place of the box.
				local cell = CreateFrame("Frame", nil, row)
				cell:SetSize(26, 26)
				cell:SetPoint("CENTER", row, "LEFT", x, 0)
				local cross = Label(cell, "GameFontDisable", "x")
				cross:SetPoint("CENTER")
				Tooltip(cell, "Flights don't start " .. WHERE[where][2] .. ".")
			else
				local tip = (cam[1] == "flight" and where == "Cities")
					and "No Flight Cam on flights taking off from a capital city."
					or ("No " .. cam[2] .. " Cam " .. WHERE[where][2] .. ".")
				local cb = Check(row, cam[1] .. "OffIn" .. where, "", tip)
				cb:SetPoint("CENTER", row, "LEFT", x, 0)
				GreyUnless(cb, IfNotAlways)
			end
		end
		lastRow = row
	end

	-- Indoors
	local indoorHeader = Header(cameraPanel, "Indoors", lastRow, -24)
	local indoorLimits = Check(cameraPanel, "indoorLimits", "Limit the camera indoors",
		"Inside buildings and caves, the camera modes zoom out less and swing less, so the " ..
		"camera doesn't keep pushing into walls and ceilings. Uses the game's own indoor check.")
	indoorLimits:SetPoint("TOPLEFT", indoorHeader, "BOTTOMLEFT", -2, -6)
	indoorLimits:HookScript("OnClick", Refresh) -- grey out / enable the options below
	local function IfIndoorLimits(db) return db.indoorLimits end

	local indoorZoom = Slider(cameraPanel, "indoorZoomOut", "Zoom out indoors up to", 0, 10, 0.5, "%.1f yards")
	indoorZoom:SetPoint("TOPLEFT", indoorLimits, "BOTTOMLEFT", 4, -26)
	Tooltip(indoorZoom, "How far past your own distance the slow zoom may pull back indoors. It " ..
		"also never raises the max zoom distance indoors. Walking in pulled back, the camera " ..
		"glides in to this.")
	GreyUnless(indoorZoom, IfIndoorLimits)

	local indoorSwing = Slider(cameraPanel, "indoorSwing", "Swing indoors up to", 0, 90, 5, "%d°")
	indoorSwing:SetPoint("TOPLEFT", indoorZoom, "BOTTOMLEFT", 0, -34)
	Tooltip(indoorSwing, "How far either side of behind the flight, RP walk and auto-run cameras " ..
		"may swing indoors.")
	GreyUnless(indoorSwing, IfIndoorLimits)

	local indoorSweep = Check(cameraPanel, "indoorNoSweep", "No AFK camera sweep indoors",
		"The AFK camera sweeps right round your character, which can bump into walls " ..
		"in tight rooms. Its zoom still runs (within the limit above).")
	indoorSweep:SetPoint("TOPLEFT", indoorSwing, "BOTTOMLEFT", -4, -14)
	GreyUnless(indoorSweep, IfIndoorLimits)

	cameraCanvas:SetScript("OnShow", PageShown(Refresh, cameraPanel))
	cameraCanvas:Hide()
	RegisterSubpage(cameraCanvas, "Camera Modes")
end

-- A checkbox for one entry of a table setting (db[tableKey][subKey]), where a
-- missing entry means defaultValue.
local function TableCheck(parent, tableKey, subKey, label, defaultValue, tip)
	local cb = Check(parent, tableKey, label, tip, function(value)
		ns.GetDB()[tableKey][subKey] = value
	end)
	cb.Refresh = function(self)
		local value = ns.GetDB()[tableKey][subKey]
		if value == nil then value = defaultValue end
		self:SetChecked(value)
	end
	return cb
end

-- Camera rotation settings, built once per profile (taxiOrbit* for flights,
-- idleOrbit* for standing still), each on its own sub-page.
-- Rotation controls for a camera's fixed style: "sweep" (steady sweeps: the
-- AFK camera) or "back" (swings behind you: flights, RP walk).
local function BuildRotationControls(container, prefix, style)
	local function key(name) return prefix .. name end

	local last
	if style == "sweep" then
		local orbitRight = Check(container, key("Right"), "Turn clockwise",
			"Sweeps turn the other way round.")
		orbitRight:SetPoint("TOPLEFT", container, "TOPLEFT", -2, 0)
		local lastCheck = orbitRight

		if prefix == "idleOrbit" then
			local randomDir = Check(container, key("RandomDir"), "Random direction",
				"Each time the camera starts, it picks clockwise or anticlockwise at random " ..
				"(and keeps to it until it stops).", function(value)
					ns.GetDB()[key("RandomDir")] = value
					Refresh()
				end)
			randomDir:SetPoint("TOPLEFT", orbitRight, "BOTTOMLEFT", 0, 2)
			GreyUnless(orbitRight, function(db) return not db[key("RandomDir")] end)
			lastCheck = randomDir
		end

		local orbitStep = Slider(container, key("Step"), "Turn per sweep", 10, 90, 5, "%d°")
		orbitStep:SetPoint("TOPLEFT", lastCheck, "BOTTOMLEFT", 4, -26)
		Tooltip(orbitStep, "How far each sweep turns, always the same way, staying level.")

		local orbitSpeed = Slider(container, key("Speed"), "Turn speed", 1, 45, 1, "%d°/sec")
		orbitSpeed:SetPoint("TOPLEFT", orbitStep, "BOTTOMLEFT", 0, -34)
		Tooltip(orbitSpeed, "Top speed in the middle of a sweep. At 6°/sec with 50% ease, a 30° " ..
			"sweep takes 10 seconds.")
		last = orbitSpeed
	else
		local minChange = Slider(container, key("MinChange"), "Minimum change", 10, 120, 5, "%d°")
		minChange:SetPoint("TOPLEFT", container, "TOPLEFT", 2, -20)
		Tooltip(minChange, "The new angle is never within this many degrees of the current " ..
			"one, either way. Keep it below the swing for varied moves.")

		local backArc = Slider(container, key("BackArc"),
			prefix == "cozyOrbit" and "Swing either side of the front" or "Swing either side of behind",
			0, 90, 5, "%d°")
		backArc:SetPoint("TOPLEFT", minChange, "BOTTOMLEFT", 0, -34)
		Tooltip(backArc, "How far the camera may swing to either side of directly behind your " ..
			"character. 90° reaches side-on; smaller keeps it closer behind.")

		local pitchUp = Slider(container, key("PitchUp"), "Tilt up as far as", 0, 45, 5, "%d°")
		pitchUp:SetPoint("TOPLEFT", backArc, "BOTTOMLEFT", 0, -34)
		Tooltip(pitchUp, "Each move also tilts the camera to a random angle between the down " ..
			"and up limits. 0 on both keeps it level.")

		local pitchDown = Slider(container, key("PitchDown"), "Tilt down as far as", 0, 45, 5, "%d°")
		pitchDown:SetPoint("TOPLEFT", pitchUp, "BOTTOMLEFT", 0, -34)
		Tooltip(pitchDown, "How far below level a move may tilt.")
		local lastPitch = pitchDown

		if prefix == "runOrbit" then
			local pitchFloor = Slider(container, key("PitchFloor"), "Lowest tilt", 0, 45, 1, "%d°")
			pitchFloor:SetPoint("TOPLEFT", pitchDown, "BOTTOMLEFT", 0, -34)
			Tooltip(pitchFloor, "The camera never tilts more than this far below where it was " ..
				"when auto-run started, even when it lowers while you steer.")
			lastPitch = pitchFloor
		end

		local moveTime = Slider(container, key("MoveTime"), "Each move takes", 1, 20, 0.5, "%.1f sec")
		moveTime:SetPoint("TOPLEFT", lastPitch, "BOTTOMLEFT", 0, -34)
		Tooltip(moveTime, "How long each move takes, however far it goes.")
		last = moveTime
	end

	local ease = Slider(container, key("Ease"), "Ease in/out", 10, 50, 5, "%d%%", 100)
	ease:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -34)
	Tooltip(ease, "How much of each move is spent speeding up, and again slowing down. " ..
		"50% is one smooth swell, gentlest at the ends. Lower values get up to speed " ..
		"quicker and cruise in the middle.")

	local orbitPause = Slider(container, key("Pause"), "Pause between moves", 0, 60, 0.5, "%.1f sec")
	orbitPause:SetPoint("TOPLEFT", ease, "BOTTOMLEFT", 0, -34)
	if style == "sweep" then
		Tooltip(orbitPause, "How long the camera rests between sweeps. 0 keeps it turning " ..
			"continuously at the turn speed, without slowing between sweeps.")
	else
		Tooltip(orbitPause, "How long the camera rests between moves.")
	end

	local drift = Check(container, key("Drift"), "Keep drifting during pauses",
		style == "sweep"
			and "Instead of stopping between sweeps, the camera keeps creeping slowly the same way."
			or "Instead of stopping between moves, the camera keeps creeping slowly back toward " ..
				"the middle.")
	drift:SetPoint("TOPLEFT", orbitPause, "BOTTOMLEFT", -4, -14)

	local driftSpeed = Slider(container, key("DriftSpeed"), "Drift speed", 0.5, 5, 0.5, "%.1f°/sec")
	driftSpeed:SetPoint("TOPLEFT", drift, "BOTTOMLEFT", 4, -26)
	return driftSpeed
end


-- The places a "Turn ... off in" list covers, in the same order everywhere.
local PLACES = {
	{ "Cities", "Cities" }, { "Dungeons", "Dungeons" },
	{ "Raids", "Raids" }, { "PvP", "Battlegrounds and arenas" },
}

-- A "Turn ... off in" list of place checkboxes (keys prefix .. "Cities" etc.),
-- added to a Stack. Returns the checkboxes.
local function PlaceList(parent, stack, title, prefix, tip)
	stack:Header(parent, title)
	local checks = {}
	for _, place in ipairs(PLACES) do
		checks[#checks + 1] = stack:Add(Check(parent, prefix .. place[1], place[2], tip), "check")
	end
	return checks
end

-- Every camera mode's page is laid out the same way:
--   Starting (full width): opts.top's own section first if any (the fish
--     camera's casting), then starting cinematic mode straight away, the
--     mode's own starting options (opts.start), the wait after combat and the
--     pause after you move the camera.
--   Left column: Rotation (and opts.rotationExtras), then the mode's own
--     sections (opts.extras: Height, Turning, Fly-bys, Landing).
--   Right column: Zoom (and opts.zoomExtras), Depth of field.
-- The opts functions take (content, stack) and add their controls to it.
-- The Death Cam and Quest Cam pages follow the same layout by hand.
local ZOOM_TIP = "The camera slowly pulls back, then (with random zoom) drifts in and out. Moving " ..
	"glides it back to your distance; zooming yourself keeps your new distance."
local INPUT_PAUSE_TIP = "After you drag the camera, use camera keys or zoom, this camera waits " ..
	"this long, then carries on from your new view."

local function CreateCameraModePanel(opts)
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", opts.name)
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall", opts.description)
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	local stack = Stack(subtitle, "label")
	if opts.top then
		opts.top(content, stack)
	end

	stack:Header(content, "Starting")
	if opts.instantKey then
		stack:Add(Check(content, opts.instantKey, "Start CineMode as soon as you " .. opts.instantWhen,
			"Skips the wait before fading, so the UI fades and the camera starts moving straight away."), "check")
	end
	if opts.start then
		opts.start(content, stack)
	end
	local inputPause = stack:Add(Slider(content, opts.inputPauseKey, "Pause after you move the camera",
		0, 60, 0.5, "%.1f sec"), "slider")
	Tooltip(inputPause, INPUT_PAUSE_TIP .. (opts.inputPauseTip and (" " .. opts.inputPauseTip) or ""))

	-- Left column: rotation, then the mode's own sections
	local rotationHeader = stack:Header(content, "Rotation")
	local rotate = stack:Add(Check(content, opts.orbitPrefix, opts.rotateLabel, opts.rotateTip), "check")
	local container = CreateFrame("Frame", nil, content)
	container:SetPoint("TOPLEFT", rotate, "BOTTOMLEFT", 2, -14)
	container:SetSize(300, 1)
	stack:Continue(BuildRotationControls(container, opts.orbitPrefix, opts.style), "slider")
	if opts.rotationExtras then
		opts.rotationExtras(content, stack)
	end
	if opts.extras then
		opts.extras(content, stack)
	end

	-- Right column: zoom, depth of field
	local zoomHeader = Label(content, "GameFontNormal", "Zoom")
	zoomHeader:SetPoint("TOPLEFT", rotationHeader, "TOPLEFT", 320, 0)
	local right = Stack(zoomHeader)
	local zoom = right:Add(Check(content, opts.zoomPrefix, "Slowly zoom", opts.zoomTip or ZOOM_TIP), "check")
	right:Continue(BuildZoomControls(content, opts.zoomPrefix, zoom), "check")
	if opts.zoomExtras then
		opts.zoomExtras(content, right)
	end

	right:Header(content, "Depth of field")
	local dof = right:Add(Slider(content, opts.dofKey, "Edge haze", 0, 100, 2.5, "%.1f%%", 100, function(value)
		if ns.FocusPreview then ns.FocusPreview(value / 100) end
	end), "slider")
	Tooltip(dof, "A soft haze around the edges of the screen in this camera mode, as if the " ..
		"camera had focused on you. 0% leaves it off. Moving the slider shows it for a moment. " ..
		"Needs \"Depth of field\" on the Visual Effects page.")
	GreyUnless(dof, function(db) return db.visualEffects and db.depthOfField end)

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, opts.name)
end

-- The "Height" section of a camera mode's page: how far it lowers the camera.
local function HeightExtras(key, minV, maxV, tip)
	return function(content, stack)
		stack:Header(content, "Height")
		local level = stack:Add(Slider(content, key, "Lower the camera", minV, maxV, 5, "%d°"), "slider")
		Tooltip(level, tip)
	end
end

-- The "Turning" section of a travel mode's page (RP walk, auto-run).
local function TurningExtras(swingKey, delayKey)
	return function(content, stack)
		stack:Header(content, "Turning")
		local swing = stack:Add(Check(content, swingKey, "Glide round gently when you turn",
			"When you turn left or right, the camera doesn't snap round with you: it carries on " ..
			"as it was (sway and all) until you stop turning, then glides gently round to your " ..
			"new facing, easing in and out. Steering with the right mouse button keeps the camera " ..
			"going behind you; dragging with the left button hands it straight back to you."), "check")
		swing:HookScript("OnClick", Refresh) -- grey out / enable the wait below
		local glideDelay = stack:Add(Slider(content, delayKey, "Wait before gliding", 0, 5, 0.5, "%.1f sec"),
			"slider")
		Tooltip(glideDelay, "After you stop turning, the view holds this long before gliding round " ..
			"to your new facing, in case you turn again. Turning again starts the wait over.")
		GreyUnless(glideDelay, function(db) return db[swingKey] end)
	end
end

-- A comma-separated list setting in an edit box (saved as you leave it).
local function ListBox(parent, key, width, tip, onSave)
	RecordKey(parent, key)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	local function Save(self)
		ns.GetDB()[key] = self:GetText()
		if onSave then onSave() end
	end
	box:SetScript("OnEnterPressed", function(self) Save(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusLost", Save)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(ns.GetDB()[key] or "")
		self:ClearFocus()
	end)
	box.Refresh = function(self)
		if not self:HasFocus() then self:SetText(ns.GetDB()[key] or "") end
	end
	controls[#controls + 1] = box
	Tooltip(box, tip)
	return box
end

-- Sub-page: events (emotes, a campfire, going AFK...) and the camera each starts.
local EVENT_CAMERAS = {
	{ value = "cozy", text = "Cozy camera" },
	{ value = "vista", text = "Vista camera" },
	{ value = "fish", text = "Fish camera" },
	{ value = "afk", text = "AFK camera" },
	{ value = "none", text = "No camera" },
}
local FLIGHT_CAMERAS = {
	{ value = "flight", text = "Flight camera" },
	{ value = "none", text = "No camera" },
}
local QUEST_CAMERAS = {
	{ value = "quest", text = "Quest camera" },
	{ value = "none", text = "No camera" },
}
local TELE_CAMERAS = {
	{ value = "tele", text = "Tele camera" },
	{ value = "none", text = "No camera" },
}
local EVENT_TIPS = {
	Campfire = "Standing or sitting still with any of the buffs listed below (like Welcoming Campfire).",
	Sit = "Doing the emote (or pressing the sit key). Moving, jumping or another emote ends it.",
	Sleep = "Doing the emote. Moving, jumping or another emote ends it.",
	Dance = "Doing the emote. Moving, jumping or another emote ends it.",
	Kneel = "Doing the emote. Moving, jumping or another emote ends it.",
	Chair = "Right-clicking a seat to sit on it; standing up ends it. Seats are recognised by name, " ..
		"using the words below.",
	Weapon = "Unsheathing your weapon out of combat, for a \"hero shot\". Putting it away, running or " ..
		"combat ends it. With the cozy camera it carries on while you auto-walk (the camera " ..
		"swings round in front as you walk, even with Stop on move).",
	Hearth = "Casting your Hearthstone (or Astral Recall, or any spell with \"Hearthstone\" in its " ..
		"name). The tele camera swings round in front of you and spins faster and faster as it " ..
		"zooms in, until you go. The cast doesn't bring the UI back " ..
		"or pause the camera.",
	Teleport = "Casting a teleport (a mage's \"Teleport: Stormwind\" and the like, or a druid's " ..
		"Teleport: Moonglade). The tele camera, as for the Hearthstone.",
	Logout = "Logging out or quitting where the game counts down 20 seconds first (out in the " ..
		"world). In an inn or a city, logging out is instant, so there's nothing to see. Moving, " ..
		"jumping, casting or Cancel ends it. It comes before any other event (a Hearthstone or " ..
		"teleport cast calls it off).",
	Stare = "Doing the emote while standing still. Moving, jumping or another emote ends it.",
	Fishing = "Casting Fishing. It carries on after the cast ends (looting, casting again) until " ..
		"you move or jump. The cast doesn't bring the UI back or pause the camera.",
	AFK = "Being flagged AFK (/afk, or away long enough). With \"No camera\", the AFK camera still " ..
		"starts once you've stood still for its delay.",
	Flight = "Taking off on a flight path. With \"No camera\", the camera is left to you for " ..
		"the whole flight.",
	Quest = "Talking to a quest giver (a quest to pick up or hand in). Works whether or not " ..
		"CineMode is on.",
}
local function CreateEventsPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Camera Triggers")
	title:SetPoint("TOPLEFT", 16, -16)
	local subtitle = Label(content, "GameFontHighlightSmall",
		"What starts the AFK, cozy, vista and fish cameras. Pick a camera for each event; a " ..
		"Hearthstone or teleport cast comes first, then logging out, going AFK, the latest emote, a " ..
		"drawn weapon and a campfire. Taking a flight has the flight " ..
		"camera, and talking to a quest giver the quest camera. RP walk, auto-run and death start " ..
		"by themselves.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	local CAMERA_X, MUSIC_X = 250, 425
	local header = Header(content, "Event", subtitle, -20)
	local cameraHeader = Label(content, "GameFontNormal", "Camera")
	cameraHeader:SetPoint("LEFT", header, "LEFT", CAMERA_X, 0)
	local musicHeader = Label(content, "GameFontNormal", "Music")
	musicHeader:SetPoint("LEFT", header, "LEFT", MUSIC_X, 0)
	local MUSIC_TIP = "A fresh song starts as this event's camera starts, even if music played " ..
		"recently (see Fatigue on the Audio page). Not when you switch straight over from another " ..
		"camera mode: the song playing carries on, as it does after a break of under 20 seconds. " ..
		"Off: the music is left as it is. Needs \"Play music in CineMode\" on the Audio page."
	local MUSIC_EXTRA_TIPS = {
		Flight = " Once per flight, as the camera starts rotating (at takeoff if flight rotation is " ..
			"off); not while music is muted on flights.",
		AFK = " This covers the AFK camera however it starts, standing still included. Off goes " ..
			"further: standing still with the UI faded and being AFK don't start any music, nor " ..
			"bring it back after a pause, so it doesn't come on while you're away.",
		Quest = " Once for a run of quest givers, not for each one.",
	}

	local previous, dx = header, 0
	for _, event in ipairs(ns.EVENTS) do
		local key = "event" .. event.key
		local label = Label(content, "GameFontHighlight", event.label)
		label:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", dx, -20)
		label:SetWidth(CAMERA_X - 10)
		label:SetWordWrap(false)
		local hover = CreateFrame("Frame", nil, content)
		hover:SetAllPoints(label)
		hover:EnableMouse(true)
		Tooltip(hover, EVENT_TIPS[event.key])

		local choices = (event.key == "Flight" and FLIGHT_CAMERAS) or (event.key == "Quest" and QUEST_CAMERAS)
			or ((event.key == "Hearth" or event.key == "Teleport") and TELE_CAMERAS) or EVENT_CAMERAS
		local camera = Dropdown(content, key .. "Camera", choices, 150)
		if not camera then
			-- No modern dropdown on this client: a button that steps through them.
			camera = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
			camera:SetSize(150, 22)
			camera:SetScript("OnClick", function(self)
				local db = ns.GetDB()
				for i, choice in ipairs(choices) do
					if db[key .. "Camera"] == choice.value then
						db[key .. "Camera"] = choices[i % #choices + 1].value
						break
					end
				end
				Refresh()
			end)
			camera.Refresh = function(self)
				for _, choice in ipairs(choices) do
					if ns.GetDB()[key .. "Camera"] == choice.value then self:SetText(choice.text) end
				end
			end
			controls[#controls + 1] = camera
		end
		camera:SetPoint("LEFT", label, "LEFT", CAMERA_X, 0)

		-- Music: the event's own switch; a flight's is the flight camera's (once
		-- per flight, as it starts rotating). Going AFK's covers the AFK camera
		-- however it starts, so it isn't greyed with the event set to none.
		local musicKey = (event.key == "Flight" and "musicCamFlight")
			or (ns.DEFAULTS["event" .. event.key .. "Music"] ~= nil and ("event" .. event.key .. "Music"))
		if musicKey then
			local music = Check(content, musicKey, "", MUSIC_TIP .. (MUSIC_EXTRA_TIPS[event.key] or ""))
			music:SetPoint("LEFT", label, "LEFT", MUSIC_X + 8, 0)
			GreyUnless(music, function(db)
				return db.musicInCinematic and (event.key == "AFK" or db[key .. "Camera"] ~= "none")
			end)
		end
		previous, dx = label, 0

		if event.key == "Campfire" then
			local buffBox = ListBox(content, "cozyBuffs", 420, "Buff names or spell IDs, separated " ..
				"by commas. Names must match your game language; spell IDs work in any language.",
				function() if ns.CheckIdleBuffs then ns.CheckIdleBuffs() end end)
			buffBox:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 26, -8)
			local note = Label(content, "GameFontHighlightSmall", "Buffs, separated by commas.")
			note:SetPoint("TOPLEFT", buffBox, "BOTTOMLEFT", -4, -4)
			previous, dx = note, -22
		elseif event.key == "Chair" then
			local seatBox = ListBox(content, "cozyChairWords", 420, "Words that mark a seat when " ..
				"they're in an object's name (\"Wooden Chair\"), separated by commas. Use words in " ..
				"your game language.")
			seatBox:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 26, -8)
			local note = Label(content, "GameFontHighlightSmall", "Seat words, separated by commas.")
			note:SetPoint("TOPLEFT", seatBox, "BOTTOMLEFT", -4, -4)
			previous, dx = note, -22
		end
	end

	local note = Label(content, "GameFontHighlightSmall",
		"An event set to the AFK camera starts it without waiting out the AFK camera's own delay.")
	note:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", dx, -28)
	note:SetWidth(520)
	note:SetJustifyV("TOP")

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Camera Triggers")
end

local function CreateFlightPanel()
	CreateCameraModePanel({
		name = "Flight Cam",
		description = "On flight paths. The camera swings round behind you as you take off, sways " ..
			"behind you on the way and settles behind you before landing.",
		instantKey = "taxiInstant", instantWhen = "take off",
		start = function(content, stack)
			stack:Add(Check(content, "dropTargetOnFlights", "Drop your target at takeoff",
				"Your target's frames fade as if nothing were targeted, until you pick a new target " ..
				"or land. (Addons can't clear the target itself; the game doesn't allow it.)"), "check")
			stack:Add(Check(content, "taxiCenter", "Swing round behind you at takeoff",
				"Slowly swings the camera round behind your character as you take off, ready for " ..
				"the sway behind you. Also once the pause after you move the camera mid-flight is up."),
				"check")
		end,
		inputPauseKey = "taxiInputPause",
		orbitPrefix = "taxiOrbit", style = "back",
		rotateLabel = "Sway behind you",
		rotateTip = "The camera swings from side to side behind your character, pausing between " ..
			"moves. Dragging the camera pauses it.",
		extras = function(content, stack)
			stack:Header(content, "Fly-bys")
			stack:Add(Check(content, "taxiFlyBy", "Random fly-bys",
				"Now and then in the middle of a flight, the camera slowly turns round to look back " ..
				"past you, holds there, then turns back behind you. On a route's first flight (its " ..
				"length not known yet), just one, early on. Dragging the camera stops it. /cine flyby " ..
				"or its key starts one whenever you like. Once you move the camera yourself on a flight, " ..
				"there are no more for that flight."), "check")
			stack:Add(Check(content, "flyByLook", "Do /look as a fly-by starts",
				"Your character looks around as the camera starts turning, as if they'd spotted " ..
				"something. Players nearby see the emote in chat. Fly-bys you start count too."), "check")
			local every = stack:Add(Slider(content, "taxiFlyByEvery", "About one every", 30, 300, 10, "%d sec"), "slider")
			Tooltip(every, "Random fly-bys are spread over the part of the flight below: one per this " ..
				"many seconds of it (at least one), each at a random moment in its share.")
			local from = stack:Add(Slider(content, "taxiFlyByFrom", "Not before", 0, 100, 5, "%d%% of the way"), "slider")
			Tooltip(from, "Keeps random fly-bys away from takeoff.")
			local to = stack:Add(Slider(content, "taxiFlyByTo", "Not after", 0, 100, 5, "%d%% of the way"), "slider")
			Tooltip(to, "Keeps random fly-bys away from landing (and the settle before it).")
			local angle = stack:Add(Slider(content, "flyByAngle", "Turn round to", 90, 180, 5, "%d° from behind you"), "slider")
			Tooltip(angle, "The camera lines up behind you, then turns this far round: 180 looks " ..
				"straight back at you.")
			local turnTime = stack:Add(Slider(content, "flyByTurnTime", "Turn round takes", 3, 20, 1, "%d sec"), "slider")
			Tooltip(turnTime, "How long the turn round takes, easing in and out.")
			stack:Add(Slider(content, "flyByHold", "Look back for", 0, 20, 1, "%d sec"), "slider")
			stack:Add(Slider(content, "flyByBackTime", "Turn back takes", 3, 20, 1, "%d sec"), "slider")

			stack:Header(content, "Landing")
			stack:Add(Check(content, "taxiSettle", "Lock the camera behind you before landing",
				"Shortly before you land, the rotation stops and the camera turns back behind you " ..
				"and stays there until you touch down. Needs one flight on a " ..
				"route to learn how long it takes. Skipped if you've moved the camera yourself on that " ..
				"flight: it stays how you set it."), "check")
			stack:Add(Check(content, "taxiLandZoom", "Put the zoom back when you land",
				"As you land, the camera glides back to the zoom distance you had when you took " ..
				"off. If you zoomed yourself on the way, it stays where you put it."), "check")
			local settleLead = stack:Add(Slider(content, "taxiSettleLead", "Behind you by", 2, 20, 1,
				"%d sec before landing"), "slider")
			Tooltip(settleLead, "The camera turns back over the 6 seconds before this, so it's settled " ..
				"behind you this long before you land.")
		end,
		zoomPrefix = "taxiZoom", dofKey = "dofFlight",
	})
end

local function CreateStandingPanel()
	CreateCameraModePanel({
		name = "AFK Cam",
		description = "Once you've stood still for a while with the UI faded, or as soon as you " ..
			"go AFK, the camera slowly sweeps around your character. Moving stops it.",
		start = function(content, stack)
			local idleDelay = stack:Add(Slider(content, "idleOrbitDelay", "Start after standing still for",
				5, 120, 5, "%d sec"), "slider")
			Tooltip(idleDelay, "How long you stand still before the rotation and zoom begin (an event " ..
				"set to the AFK camera on the Camera Triggers page, like going AFK, skips the wait). Also " ..
				"used by the other options that mention standing still (tint, tracking, music, " ..
				"tooltips).")
		end,
		inputPauseKey = "idleInputPause",
		orbitPrefix = "idleOrbit", style = "sweep",
		rotateLabel = "Sweep round you",
		rotateTip = "The camera sweeps around your character, pausing between sweeps. Moving or " ..
			"dragging the camera stops it.",
		zoomPrefix = "idleZoom",
		dofKey = "dofIdle",
	})
end

local function CreateAutoRunPanel()
	CreateCameraModePanel({
		name = "Auto-run Cam",
		description = "While you're auto-running (the auto-run key). Pressing forward or back, or " ..
			"stopping, ends it; stop and stand, and the AFK camera takes over. Auto-" ..
			"walking counts as RP walk instead.",
		instantKey = "runInstant", instantWhen = "auto-run",
		inputPauseKey = "runInputPause",
		orbitPrefix = "runOrbit", style = "back",
		rotateLabel = "Sway behind you",
		rotateTip = "The camera swings gently from side to side behind your character, pausing " ..
			"between moves.",
		extras = TurningExtras("runSwingBehind", "runGlideDelay"),
		zoomPrefix = "runZoom",
		zoomTip = "The camera eases out a little, then drifts in and out around your own distance. " ..
			"When you stop it glides back.",
		dofKey = "dofRun",
	})
end

local function CreateCozyPanel()
	CreateCameraModePanel({
		name = "Cozy Cam",
		description = "Resting at a campfire, sitting, sleeping, dancing and the like (whichever " ..
			"events pick it on the Camera Triggers page): the camera swings slowly round to face you, then " ..
			"sways gently from side to side in front of you, and eases in close. Moving (or standing " ..
			"up) ends it.",
		inputPauseKey = "cozyInputPause",
		orbitPrefix = "cozyOrbit", style = "back",
		rotateLabel = "Sway in front of you",
		rotateTip = "Once it has swung round to face you, the camera sways gently from side to side " ..
			"in front of your character, pausing between moves.",
		extras = HeightExtras("cozyLevel", -30, 80, "As it swings round, the camera also comes down " ..
			"this much toward the ground, so it feels low and close rather than looking down from " ..
			"above. It stops at the ground, so a big number just means \"as low as it goes\". 0 " ..
			"keeps your angle."),
		zoomPrefix = "cozyZoom",
		zoomTip = "A close, gentle zoom: it starts by easing in to the close-up distance below, then " ..
			"drifts a little in and out around it.",
		zoomExtras = function(content, stack)
			local close = stack:Add(Slider(content, "cozyZoomClose", "Zoom in to about", 2, 20, 0.5,
				"%.1f yards"), "slider")
			Tooltip(close, "The close-up distance the cozy camera zooms in to, if you're further out. " ..
				"The zoom settings above then work around it. Your own distance comes back afterwards.")
		end,
		dofKey = "dofCozy",
	})
end

local function CreateVistaPanel()
	CreateCameraModePanel({
		name = "Vista Cam",
		description = "Stop and /stare out at the view (or any event set to it on the Camera Triggers page): " ..
			"the camera glides round behind you and sways very gently there, looking out the way " ..
			"you're facing. Like the RP walk camera, only slower and softer. Moving, jumping or " ..
			"another emote ends it.",
		inputPauseKey = "vistaInputPause",
		inputPauseTip = "It glides back behind you first.",
		orbitPrefix = "vistaOrbit", style = "back",
		rotateLabel = "Sway behind you",
		rotateTip = "The camera swings very gently from side to side behind your character, " ..
			"pausing between moves.",
		extras = HeightExtras("vistaLevel", -30, 45, "The camera sways this much lower than where " ..
			"it lines up behind you, so it looks out across the view rather than down at it. 0 " ..
			"keeps your angle."),
		zoomPrefix = "vistaZoom",
		zoomTip = "The camera eases out a little, then drifts slowly in and out around your own " ..
			"distance. Your own distance comes back afterwards.",
		dofKey = "dofVista",
	})
end

local function CreateFishPanel()
	CreateCameraModePanel({
		name = "Fish Cam",
		description = "Cast Fishing (or any event set to it on the Camera Triggers page): the vista camera, " ..
			"made for fishing. The camera glides round behind you and sways only a little either " ..
			"side, so your bobber stays in view. It carries on after the cast until you move or jump.",
		top = function(content, stack)
			stack:Header(content, "Casting")
			stack:Add(Check(content, "hideFishingCastBar", "Hide the Fishing cast bar",
				"Your cast bar stays hidden while it shows Fishing. Every other spell shows it as usual."),
				"check")
			local recast = stack:Add(Check(content, "fishRightClickCast", "Right-click to cast again",
				"While the fish camera is on and no bobber is out, right-clicking in the world casts " ..
				"Fishing again. Each cast still comes from your own click. While the bobber is out, " ..
				"right-click clicks it as usual; in combat, with the loot window open or with your " ..
				"mouse on a player or NPC, right-click is left alone. (Meanwhile right-drag doesn't " ..
				"turn the camera: left-drag still does.)"), "check")
			recast:HookScript("OnClick", Refresh) -- grey out / enable the options below
			local function IfRecast(db) return db.fishRightClickCast end
			local pole = stack:Add(Check(content, "fishPoleRightClickCast", "Also the first cast, with a pole equipped",
				"With a fishing pole in your main hand, standing still, right-clicking in the world " ..
				"casts Fishing, so you don't have to start the first cast yourself. Not while your " ..
				"mouse is on a player, NPC or object (mailbox, corpse...): right-click works on them " ..
				"as usual. Swap the pole out to have right-click back everywhere."), "check", 24)
			GreyUnless(pole, IfRecast)
			local delay = stack:Add(Slider(content, "fishRecastDelay", "Wait after a cast ends", 0, 3, 0.1,
				"%.1f sec"), "slider")
			Tooltip(delay, "How long after a cast ends (a catch looted, or the bobber gone) before " ..
				"right-click casts again, so the click that loots the fish doesn't cast straight away.")
			GreyUnless(delay, IfRecast)
			local missPause = stack:Add(Slider(content, "fishMissPause", "Pause after a missed cast", 0, 30, 1,
				function(value) return value == 0 and "Off" or ("%d sec"):format(value) end), "slider")
			Tooltip(missPause, "When a cast doesn't land in fishable water (say, a pole left equipped " ..
				"away from water), right-click goes back to normal for this long before it casts again. " ..
				"Moving and then standing still for 1 sec ends it early: you're likely at a new spot to fish from. " ..
				"Off doesn't pause. (\"Skill not high enough\" always pauses it for 30 sec, moving or not.)")
			GreyUnless(missPause, IfRecast)
		end,
		inputPauseKey = "fishInputPause",
		inputPauseTip = "It glides back behind you first.",
		orbitPrefix = "fishOrbit", style = "back",
		rotateLabel = "Sway behind you",
		rotateTip = "The camera swings a little from side to side behind your character, " ..
			"pausing between moves. Narrower than the vista camera's sway.",
		extras = HeightExtras("fishLevel", -30, 45, "The camera sways this much lower than where " ..
			"it lines up behind you, so it looks out across the water rather than down at it. 0 " ..
			"keeps your angle."),
		zoomPrefix = "fishZoom",
		zoomTip = "The camera eases out a little, then drifts slowly in and out around your own " ..
			"distance. Your own distance comes back afterwards.",
		dofKey = "dofFish",
	})
end

local function CreateWalkPanel()
	CreateCameraModePanel({
		name = "RP Walk Cam",
		description = "While you're auto-walking (auto-run in walk mode). Walking by hand cancels " ..
			"the camera, as all moving by hand does. Stop and stand, and the AFK camera takes over. " ..
			"Walking is recognised from your speed; /cine walk shows what the addon thinks.",
		instantKey = "walkInstant", instantWhen = "walk",
		inputPauseKey = "walkInputPause",
		inputPauseTip = "Keep it short, so it's back in time if you need to steer.",
		orbitPrefix = "walkOrbit", style = "back",
		rotateLabel = "Sway behind you",
		rotateTip = "The camera swings gently from side to side behind your character, pausing " ..
			"between moves.",
		extras = TurningExtras("walkSwingBehind", "walkGlideDelay"),
		zoomPrefix = "walkZoom",
		zoomTip = "The camera eases out a little, then drifts in and out around your own distance. " ..
			"When you stop walking it glides back.",
		dofKey = "dofWalk",
	})
end

-- Not a CreateCameraModePanel page (no sway, zoom profile or music switch of
-- its own), but laid out the same way.
local function CreateDeathPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Death Cam")
	title:SetPoint("TOPLEFT", 16, -16)
	local subtitle = Label(content, "GameFontHighlightSmall", "When you die, the camera turns " ..
		"slowly round your body until you release or are resurrected. CineMode stays on " ..
		"(straight away), with the release button (and any soulstone or Reincarnation " ..
		"button) still showing.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")
	local function IfOn(db) return db.deathOrbit end

	local stack = Stack(subtitle, "label")
	stack:Header(content, "Starting")
	local on = stack:Add(Check(content, "deathOrbit", "Use the death camera",
		"The camera turns steadily round your character while you're dead. Moving the camera " ..
		"yourself (dragging, camera keys, zooming) hands it back to you: it stops where it is " ..
		"and doesn't move again until your next death."), "check")
	on:HookScript("OnClick", Refresh) -- grey out / enable everything below
	local delay = stack:Add(Slider(content, "deathOrbitDelay", "Start after", 0, 10, 0.5, "%.1f sec"), "slider")
	Tooltip(delay, "How long after you die before the camera starts turning.")
	GreyUnless(delay, IfOn)

	-- Left column: rotation, height
	local rotationHeader = stack:Header(content, "Rotation")
	local right = stack:Add(Check(content, "deathOrbitRight", "Turn clockwise"), "check")
	GreyUnless(right, function(db) return IfOn(db) and not db.deathOrbitRandomDir end)
	local randomDir = stack:Add(Check(content, "deathOrbitRandomDir", "Random direction",
		"Each death, the camera picks clockwise or anticlockwise at random."), "check")
	randomDir:HookScript("OnClick", Refresh)
	GreyUnless(randomDir, IfOn)
	local speed = stack:Add(Slider(content, "deathOrbitSpeed", "Turn speed", 1, 20, 1, "%d°/sec"), "slider")
	GreyUnless(speed, IfOn)
	stack:Header(content, "Height")
	local level = stack:Add(Slider(content, "deathLevel", "Raise the camera", 0, 90, 5, "%d°"), "slider")
	Tooltip(level, "As it starts, the camera rises this much to look down on your body; it comes " ..
		"back down afterwards. The game stops it just short of straight down, so a big number " ..
		"means \"as high as it goes\". 0 keeps your angle.")
	GreyUnless(level, IfOn)

	-- Right column: zoom, screen, music
	local zoomHeader = Label(content, "GameFontNormal", "Zoom")
	zoomHeader:SetPoint("TOPLEFT", rotationHeader, "TOPLEFT", 320, 0)
	local rightStack = Stack(zoomHeader)
	local zoom = rightStack:Add(Slider(content, "deathZoom", "Zoom out by", 0, 15, 0.5, "%.1f yards"), "slider")
	Tooltip(zoom, "Meanwhile the camera pulls back this far, and returns to your own distance " ..
		"afterwards. Zooming yourself leaves it where you put it.")
	GreyUnless(zoom, IfOn)

	rightStack:Header(content, "Screen")
	local screen = rightStack:Add(Check(content, "deathScreen", "Darken the screen",
		"The world dims and goes cold and grey-blue, with a heavy vignette closing in from the " ..
		"edges. It clears when you release or come back."), "check")
	screen:HookScript("OnClick", Refresh) -- grey out / enable the strength below
	GreyUnless(screen, IfOn)
	local screenStrength = rightStack:Add(Slider(content, "deathScreenStrength", "Strength", 10, 100, 5,
		"%d%%", 100), "slider")
	GreyUnless(screenStrength, function(db) return IfOn(db) and db.deathScreen end)

	rightStack:Header(content, "Music")
	local song = rightStack:Add(Check(content, "deathSong", "Play a death song",
		"While the death camera runs, a song picked at random from the list below plays in place " ..
		"of the zone music. Needs game music on. It stops when you release or come back."), "check")
	song:HookScript("OnClick", Refresh) -- grey out / enable the file box below
	GreyUnless(song, IfOn)
	local songBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	songBox:SetSize(260, 20)
	songBox:SetAutoFocus(false)
	rightStack:Add(songBox, "box")
	local function SaveSong(self) ns.GetDB().deathSongFiles = self:GetText() end
	songBox:SetScript("OnEnterPressed", function(self) SaveSong(self) self:ClearFocus() end)
	songBox:SetScript("OnEditFocusLost", SaveSong)
	songBox:SetScript("OnEscapePressed", function(self)
		self:SetText(ns.GetDB().deathSongFiles or "")
		self:ClearFocus()
	end)
	songBox.Refresh = function(self)
		local db = ns.GetDB()
		if not self:HasFocus() then self:SetText(db.deathSongFiles or "") end
		self:SetEnabled(db.deathOrbit and db.deathSong)
	end
	controls[#controls + 1] = songBox
	Tooltip(songBox, "Music file IDs, separated by commas; one is picked at random each time " ..
		"you die (Wowhead lists the IDs on each sound's page). Try one with /cine songtest <ID>.")
	rightStack:Note(content, "Music file IDs, separated by commas. One is picked at random.")

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Death Cam")
end

-- Not a CreateCameraModePanel page either (QuestCam.lua, started by the quest
-- giver event), but laid out the same way.
local QUEST_SIDES = {
	{ value = "click", text = "Where you clicked them" },
	{ value = "random", text = "Either side, at random" },
	{ value = "right", text = "Your right" },
	{ value = "left", text = "Your left" },
}
local function CreateQuestPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Quest Cam")
	title:SetPoint("TOPLEFT", 16, -16)
	local subtitle = Label(content, "GameFontHighlightSmall", "Talking to a quest giver, the " ..
		"camera zooms in and swings round behind you, looking past you at them. It goes back " ..
		"once you close the window or move off (your zoom stays if you zoomed yourself meanwhile). Works " ..
		"whether or not CineMode is on. The \"Talk to a quest giver\" event on the Events " ..
		"page can also turn it off or make it wait a moment.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")
	local function IfOn(db) return db.eventQuestCamera ~= "none" end

	local stack = Stack(subtitle, "label")
	stack:Header(content, "Starting")
	local on = stack:Add(Check(content, "eventQuestCamera", "Use the quest camera",
		"Same as setting the \"Talk to a quest giver\" event to the quest camera (on) or no " ..
		"camera (off) on the Camera Triggers page.",
		function(value)
			ns.GetDB().eventQuestCamera = value and "quest" or "none"
			Refresh()
		end), "check")
	on.Refresh = function(self) self:SetChecked(ns.GetDB().eventQuestCamera ~= "none") end
	local gossip = stack:Add(Check(content, "questCamAllGossip", "Every NPC you talk to",
		"Also for NPCs with nothing to say about quests (innkeepers, guards...). Off: only when " ..
		"they have a quest to offer or take in."), "check")
	GreyUnless(gossip, IfOn)

	-- Left column: rotation, height, over the shoulder
	local rotationHeader = stack:Header(content, "Rotation")
	local duration = stack:Add(Slider(content, "questCamTime", "Swing behind you takes", 1, 6, 0.25, "%.2f sec"), "slider")
	Tooltip(duration, "The turn to the side starts once the swing is done.")
	GreyUnless(duration, IfOn)
	local angle = stack:Add(Slider(content, "questCamAngle", "Come round to the side", 0, 90, 5, "%d°"), "slider")
	Tooltip(angle, "After swinging behind you, the camera comes round this far to one side, so " ..
		"you see the quest giver past you at an angle rather than straight over your head. " ..
		"0 stays straight behind you. It turns back behind you as the window closes.")
	GreyUnless(angle, IfOn)
	local turnTime = stack:Add(Slider(content, "questCamTurnTime", "Turn to the side takes", 1, 8, 0.5, "%.1f sec"), "slider")
	Tooltip(turnTime, "It starts once the swing behind you is done, while the zoom carries on. " ..
		"The tilt down follows.")
	GreyUnless(turnTime, IfOn)
	local SIDE_TIP = "Which side the camera comes round to. On your right, the quest giver is on " ..
		"the right of the screen. (The game doesn't tell addons where the quest giver stands, or " ..
		"what's around you, so it can't pick the open side.) \"Where you clicked them\": the side " ..
		"of the screen you clicked the quest giver on, and the camera turns toward it; talking " ..
		"to them with a key instead, the side is picked at random."
	stack:Add(Label(content, "GameFontHighlight", "Side"), "label")
	local side = Dropdown(content, "questCamSide", QUEST_SIDES, 200)
	if side then
		stack:Add(side, "dropdown")
		Tooltip(side, SIDE_TIP)
		GreyUnless(side, IfOn)
	else
		for _, choice in ipairs(QUEST_SIDES) do
			local check = stack:Add(Choice(content, "questCamSide", choice.value, choice.text, SIDE_TIP), "check")
			GreyUnless(check, IfOn)
		end
	end
	local drift = stack:Add(Slider(content, "questCamDrift", "Drift", 0, 10, 1, "%d°"), "slider")
	Tooltip(drift, "Once the camera has settled, it drifts slowly to and fro, side to side, " ..
		"across this many degrees, so the shot isn't stock-still. 0 holds still.")
	GreyUnless(drift, IfOn)
	stack:Header(content, "Height")
	local lower = stack:Add(Slider(content, "questCamLower", "Lower the camera", 0, 45, 5, "%d°"), "slider")
	Tooltip(lower, "How far the camera comes down toward eye level, from wherever you had it. " ..
		"Much more and, close up, it can meet the ground or scenery behind you (a small jump). " ..
		"It goes back up as the window closes (unless you moved the camera yourself meanwhile). " ..
		"0 keeps your angle.")
	GreyUnless(lower, IfOn)

	stack:Header(content, "Over the shoulder (experimental)")
	local overShoulder = stack:Add(Check(content, "questCamOverShoulder", "Move over your shoulder",
		"The camera also moves to your right, putting you on the left of the screen and the " ..
		"quest giver on the right. This uses one of Blizzard's experimental camera settings: the " ..
		"game shows its experimental camera warning when it's used (Accept keeps it working). " ..
		"Your own setting comes back as the window closes."), "check")
	overShoulder:HookScript("OnClick", Refresh)
	GreyUnless(overShoulder, IfOn)
	local function IfShoulder(db) return IfOn(db) and db.questCamOverShoulder end
	local shoulder = stack:Add(Slider(content, "questCamShoulder", "Shoulder offset", 0.25, 2, 0.25, "%.2f yards"), "slider")
	Tooltip(shoulder, "How far the camera moves to your right. The game ignores this while " ..
		"its Keep Character Centered option (Accessibility) is on: see below.")
	GreyUnless(shoulder, IfShoulder)
	local uncenter = stack:Add(Check(content, "questCamUncenter", "Turn off Keep Character Centered meanwhile",
		"The game's Keep Character Centered option (Accessibility, on by default) stops the " ..
		"camera moving over your shoulder. On: it's turned off while you talk to a quest giver, " ..
		"and your setting comes back as the window closes. Off: with that option on, the " ..
		"camera stays straight behind you."), "check")
	GreyUnless(uncenter, IfShoulder)

	-- Right column: zoom
	local zoomHeader = Label(content, "GameFontNormal", "Zoom")
	zoomHeader:SetPoint("TOPLEFT", rotationHeader, "TOPLEFT", 320, 0)
	local right = Stack(zoomHeader)
	local distance = right:Add(Slider(content, "questCamDistance", "Zoom in to about", 1.5, 10, 0.5, "%.1f yards"), "slider")
	Tooltip(distance, "If you're further out than this. Closer already, it stays where it is.")
	GreyUnless(distance, IfOn)
	local zoomTime = right:Add(Slider(content, "questCamZoomTime", "Zoom in takes", 1, 10, 0.5, "%.1f sec"), "slider")
	Tooltip(zoomTime, "The turn to the side happens along the way, then the tilt down.")
	GreyUnless(zoomTime, IfOn)
	local zoomOutTime = right:Add(Slider(content, "questCamZoomOutTime", "Zoom back out takes", 1.5, 10, 0.5, "%.1f sec"), "slider")
	Tooltip(zoomOutTime, "Leaving the quest giver, the camera zooms back out to your own distance " ..
		"this slowly while you stand still (turning back behind you and tilting back up as it goes). " ..
		"Walk off and it speeds up, back out in a moment.")
	GreyUnless(zoomOutTime, IfOn)

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Quest Cam")
end

local function CreateTelePanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Tele Cam")
	title:SetPoint("TOPLEFT", 16, -16)
	local subtitle = Label(content, "GameFontHighlightSmall", "Casting your Hearthstone or a " ..
		"teleport, the camera swings round in front of you, quickly enough to be there before you " ..
		"go, then spins round you faster and faster as it zooms in. Cancel the cast and it goes " ..
		"back to where it was; once you're there, it swings round behind you. Its music, haze and " ..
		"tooltips follow the Cozy Cam's settings. The events on the Camera Triggers page can also make it " ..
		"wait a moment.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")
	local function IfOn(db) return db.eventHearthCamera ~= "none" or db.eventTeleportCamera ~= "none" end

	local stack = Stack(subtitle, "label")
	stack:Header(content, "Starting")
	for _, event in ipairs({
		{ key = "eventHearthCamera", label = "When you cast your Hearthstone",
			tip = "Same as the \"Cast your Hearthstone\" event on the Camera Triggers page. Also Astral Recall, " ..
				"and any spell with \"Hearthstone\" in its name (Dalaran, Garrison, the toys)." },
		{ key = "eventTeleportCamera", label = "When you cast a teleport",
			tip = "Same as the \"Cast a teleport\" event on the Camera Triggers page: a mage's \"Teleport: " ..
				"Stormwind\" and the like, or a druid's Teleport: Moonglade." },
	}) do
		local check = stack:Add(Check(content, event.key, event.label, event.tip,
			function(value)
				ns.GetDB()[event.key] = value and "tele" or "none"
				Refresh()
			end), "check")
		check.Refresh = function(self) self:SetChecked(ns.GetDB()[event.key] ~= "none") end
	end

	-- Left column: rotation, and after the cast
	local rotationHeader = stack:Header(content, "Rotation")
	local early = stack:Add(Slider(content, "teleArriveEarly", "Round in front of you", 0, 6, 0.5,
		"%.1f sec before you go"), "slider")
	Tooltip(early, "The swing round to face you is timed to get there this long before the cast " ..
		"ends. More is a quicker swing.")
	GreyUnless(early, IfOn)
	local accel = stack:Add(Slider(content, "teleSpinAccel", "Then speeds up by", 0, 30, 1,
		"%d° per sec, each sec"), "slider")
	Tooltip(accel, "Once round in front, the spin keeps going and picks up speed until you go. " ..
		"0 keeps a steady speed.")
	GreyUnless(accel, IfOn)
	local top = stack:Add(Slider(content, "teleSpinMax", "Top speed", 30, 360, 10, "%d° per sec"), "slider")
	Tooltip(top, "The spin never goes faster than this.")
	GreyUnless(top, IfOn)
	local level = stack:Add(Slider(content, "teleLevel", "Bring the camera down", -30, 80, 5, "%d°"), "slider")
	Tooltip(level, "As it swings round, the camera also comes down toward the ground (negative: up).")
	GreyUnless(level, IfOn)


	stack:Header(content, "Cancelling and arriving")
	local back = stack:Add(Check(content, "teleReturn", "Turn back if you cancel",
		"Moving, jumping or Esc cancels the cast: the spin slows to a stop and turns back to where " ..
		"the camera was before you started. Off: it stops where it is."), "check")
	GreyUnless(back, IfOn)
	local behind = stack:Add(Check(content, "teleBehind", "Swing behind you where you arrive",
		"Once you're there (after the loading screen, if there is one), the camera swings round " ..
		"behind you."), "check")
	GreyUnless(behind, IfOn)

	-- Right column: zoom
	local zoomHeader = Label(content, "GameFontNormal", "Zoom")
	zoomHeader:SetPoint("TOPLEFT", rotationHeader, "TOPLEFT", 320, 0)
	local right = Stack(zoomHeader)
	local zoom = right:Add(Check(content, "teleZoom", "Zoom in over the cast",
		"The camera starts zooming in as the cast starts, and is still coming in as you go."), "check")
	zoom:HookScript("OnClick", Refresh)
	GreyUnless(zoom, IfOn)
	local function IfZoom(db) return IfOn(db) and db.teleZoom end
	local close = right:Add(Slider(content, "teleZoomClose", "Zoom in to about", 1.5, 20, 0.5, "%.1f yards"), "slider")
	Tooltip(close, "Where the zoom ends as the cast does, if you're further out. Closer already, it " ..
		"stays where it is. Arriving, the camera is back at your own distance.")
	GreyUnless(close, IfZoom)
	local zoomBack = right:Add(Slider(content, "teleZoomBackTime", "If you cancel, zoom back out in",
		0.5, 3, 0.25, "%.2f sec"), "slider")
	Tooltip(zoomBack, "Cancelling the cast, the camera zooms back out to your own distance this quickly.")
	GreyUnless(zoomBack, IfZoom)

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Tele Cam")
end

-- Blizzard's colour picker; the setup API changed in newer clients.
-- Also used by the minimap button's menu (ns.OpenColorPicker).
local function OpenColorPicker(r, g, b, onChange)
	local function apply()
		onChange(ColorPickerFrame:GetColorRGB())
	end
	local function cancel(previous)
		onChange(previous.r or previous[1], previous.g or previous[2], previous.b or previous[3])
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, hasOpacity = false, swatchFunc = apply, cancelFunc = cancel,
		})
	else
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.previousValues = { r, g, b }
		ColorPickerFrame.func = apply
		ColorPickerFrame.cancelFunc = cancel
		ColorPickerFrame:SetColorRGB(r, g, b)
		ColorPickerFrame:Show()
	end
end
ns.OpenColorPicker = OpenColorPicker

-- When the letterbox or tint shows: a checkbox per situation (db.<prefix>Moving,
-- Still, Flight and InCombat), the first at x, y from anchor, then the wait
-- after a fight. text: what's shown (it), and how it leaves (away) and comes
-- back (back). enabled: false greys them all. Returns the slider at the end.
local function SituationChecks(content, prefix, anchor, x, y, text, onChange, enabled)
	enabled = enabled or function() return true end
	local function Situation(key, label, tip)
		local check = Check(content, prefix .. key, label, tip, function(value)
			ns.GetDB()[prefix .. key] = value
			onChange()
			Refresh()
		end)
		check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
		anchor, x, y = check, 0, -2
		return check
	end
	local moving = Situation("Moving", "Moving around",
		("Show %s while you're out and about, or stopped for less than the standing-still delay."):format(text.it))
	local still = Situation("Still", "Standing still",
		("Show %s once you've stood still a while."):format(text.it))
	local flight = Situation("Flight", "On flights", ("Show %s on flight paths."):format(text.it))
	local combat = Situation("InCombat", "In combat",
		("Keep %s during fights. Untick to %s, and back once the Calm Timer (on the CineMode " ..
		"page) runs out after. Only while staying cinematic in combat (Combat unticked under " ..
		"Turn off in, on the main page)."):format(text.it, text.away))
	for _, check in ipairs({ moving, still, flight }) do
		GreyUnless(check, enabled)
	end
	GreyUnless(combat, function(db) return enabled(db) and db.stayInCombat end)
	return combat
end

-- Sub-page for the screen tint and vignette.
local function CreateTintPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Visual Effects")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"How the game world looks in CineMode (or always, if you choose): letterbox bars, colour " ..
		"grading, vignette, inn glow and weather. The UI isn't tinted. While this page is open " ..
		"the tint is previewed behind the options window. Names and nameplates are on the " ..
		"Nameplates page.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- The master switch: off, none of this page's effects show (each keeps its
	-- own setting), and its other controls grey out (see the end of the page).
	local firstControl = #controls + 1
	local master = Check(content, "visualEffects", "Enable visual effects",
		"Turns everything on this page on or off at once: the letterbox, tint, time of day, " ..
		"zone tints, vignette, inn glow, weather and depth of field. Each keeps its own settings for when you " ..
		"turn this back on.", function(value)
			ns.GetDB().visualEffects = value
			ns.letterboxDirty = true
			if ns.RefreshTint then ns.RefreshTint() end
			Refresh()
		end)
	master:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -14)

	local always = Check(content, "visualEffectsAlways", "Enabled outside of CineMode",
		"Shows this page's effects with the normal UI up too, not just in CineMode: say, the tint " ..
		"and vignette while you play with every frame visible. Each still shows only in the " ..
		"situations ticked for it. Not while Cinematic is turned off or snoozed.", function(value)
			ns.GetDB().visualEffectsAlways = value
			ns.letterboxDirty = true
			if ns.RefreshTint then ns.RefreshTint() end
		end)
	always:SetPoint("TOPLEFT", master, "BOTTOMLEFT", 16, -2)

	-- Letterbox
	local letterboxHeader = Header(content, "Letterbox", always, -20)
	letterboxHeader:SetPoint("TOPLEFT", always, "BOTTOMLEFT", -14, -18)

	local letterbox = Check(content, "letterbox", "Show letterbox bars",
		"Black bars slide in at the top and bottom of the screen.", function(value)
			ns.GetDB().letterbox = value
			ns.RefreshLetterbox()
			Refresh() -- grey out / enable when they show
		end)
	letterbox:SetPoint("TOPLEFT", letterboxHeader, "BOTTOMLEFT", -2, -6)

	local letterboxBack = SituationChecks(content, "letterbox", letterbox, 16, -2,
		{ it = "the letterbox", away = "slide it away" },
		ns.RefreshLetterbox, function(db) return db.letterbox end)

	local size = Slider(content, "letterboxSize", "Bar height", 0, 25, 1, "%d%%", 100, ns.RefreshLetterbox)
	size:SetPoint("TOPLEFT", letterboxBack, "BOTTOMLEFT", -12, -30)

	local opacity = Slider(content, "letterboxAlpha", "Bar opacity", 10, 100, 5, "%d%%", 100, ns.RefreshLetterbox)
	opacity:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, -34)

	local lookHeader = Header(content, "Tint", opacity, -24)
	lookHeader:SetPoint("TOPLEFT", opacity, "BOTTOMLEFT", -2, -24)

	local choices = {}
	for _, preset in ipairs(ns.TINT_PRESETS) do
		choices[#choices + 1] = { value = preset.key, text = preset.label, tip = preset.tip }
	end
	local presetControl = Dropdown(content, "tintPreset", choices, 220, ns.RefreshTint)
	if presetControl then
		presetControl:SetPoint("TOPLEFT", lookHeader, "BOTTOMLEFT", 0, -8)

		-- Time of day only: preview the tint at any hour (until you leave the page).
		local hours = { { value = -1, text = "Current time" } }
		for hour = 0, 23 do
			hours[#hours + 1] = {
				value = hour,
				text = ("%02d:00 - %s"):format(hour, ns.GetTimeOfDayPhaseAt(hour)),
			}
		end
		local previewTime = Dropdown(content, "tintPreviewHour", hours, 200, ns.RefreshTint)
		if previewTime then
			previewTime:SetPoint("LEFT", presetControl, "RIGHT", 16, 0)
			local previewLabel = Label(content, "GameFontHighlightSmall", "Preview time")
			previewLabel:SetPoint("BOTTOMLEFT", previewTime, "TOPLEFT", 2, 2)
			local refreshMenu = previewTime.Refresh
			previewTime.Refresh = function(self)
				refreshMenu(self)
				local preset, here = ns.GetDB().tintPreset, ns.GetTintPresetHere()
				local shown = preset == "timeofday" or preset == "zonetime"
					or here == "timeofday" or here == "zonetime"
				self:SetShown(shown)
				previewLabel:SetShown(shown)
			end
			Tooltip(previewTime, "See how the tint looks at another time of day. Only a preview: " ..
				"it goes back to the real clock when you leave this page.")
		end
	else
		local previous = lookHeader
		for i, choice in ipairs(choices) do
			local check = Choice(content, "tintPreset", choice.value, choice.text, choice.tip)
			check:HookScript("OnClick", ns.RefreshTint)
			check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
			previous = check
		end
		presetControl = previous
	end

	local presetText = Label(content, "GameFontHighlightSmall")
	presetText:SetPoint("TOPLEFT", presetControl, "BOTTOMLEFT", 2, -8)
	presetText:SetWidth(320)
	presetText:SetJustifyV("TOP")
	presetText.Refresh = function(self)
		local db = ns.GetDB()
		local here, from = ns.GetTintPresetHere()
		for _, choice in ipairs(choices) do
			if choice.value == db.tintPreset then
				local text = choice.tip
				-- A zone or area with its own preset: say so, and describe that one.
				if from then
					text = text .. ("\n|cffffd100Here: %s (%s's own preset)|r"):format(
						ns.GetTintPresetLabel(here),
						from == "area" and ns.GetAreaTintInfo() or GetRealZoneText() or "?")
				end
				if here == "zone" or here == "zonetime" then
					local zone, label, isOverride = ns.GetZoneTintInfo()
					text = text .. ("\n|cffffd100Here: %s (%s%s)|r"):format(
						label, zone, isOverride and ", your choice" or "")
				end
				if here == "timeofday" or here == "zonetime" then
					local phase, hour, minute = ns.GetTimeOfDayInfo()
					if (db.tintPreviewHour or -1) >= 0 then
						text = text .. ("\n|cffffd100Previewing: %s (%02d:00)|r"):format(phase, hour)
					else
						text = text .. ("\n|cffffd100Now: %s (%02d:%02d %s time)|r"):format(
							phase, hour, minute, db.tintClock == "local" and "your" or "game")
					end
				end
				self:SetText(text)
			end
		end
	end
	controls[#controls + 1] = presetText

	local strength = Slider(content, "tintStrength", "Strength", 5, 100, 5, "%d%%", 100, ns.RefreshTint)
	strength:SetPoint("TOPLEFT", presetText, "BOTTOMLEFT", 2, -30)

	-- Custom colour swatch
	local swatch = CreateFrame("Button", nil, content)
	swatch:SetSize(22, 22)
	swatch:SetPoint("TOPLEFT", strength, "BOTTOMLEFT", 0, -24)
	local swatchBorder = swatch:CreateTexture(nil, "BACKGROUND")
	swatchBorder:SetAllPoints()
	swatchBorder:SetColorTexture(0.6, 0.6, 0.6, 1)
	local swatchColor = swatch:CreateTexture(nil, "ARTWORK")
	swatchColor:SetPoint("TOPLEFT", 2, -2)
	swatchColor:SetPoint("BOTTOMRIGHT", -2, 2)
	local swatchLabel = Label(content, "GameFontHighlight", "Custom colour")
	swatchLabel:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
	Tooltip(swatch, "Click to choose the colour used by the Custom preset.")
	swatch.Refresh = function()
		local db = ns.GetDB()
		swatchColor:SetColorTexture(db.tintCustomR, db.tintCustomG, db.tintCustomB, 1)
	end
	controls[#controls + 1] = swatch
	swatch:SetScript("OnClick", function()
		local db = ns.GetDB()
		OpenColorPicker(db.tintCustomR, db.tintCustomG, db.tintCustomB, function(r, g, b)
			db.tintCustomR, db.tintCustomG, db.tintCustomB = r, g, b
			swatch.Refresh()
			ns.RefreshTint()
		end)
	end)

	-- Strength drift
	local drift = Check(content, "tintDrift", "Subtle drift",
		"The tint's strength slowly wanders up and down over a few minutes, so a still scene " ..
		"feels a little more alive. Paused while this page is open.")
	drift:SetPoint("TOPLEFT", swatch, "BOTTOMLEFT", -2, -12)
	drift:HookScript("OnClick", function()
		Refresh() -- grey out / enable the amount slider
		ns.RefreshTint()
	end)

	local driftAmount = Slider(content, "tintDriftAmount", "Drift amount", 2, 15, 1, "+/-%d%%", 100,
		ns.RefreshTint)
	driftAmount:SetPoint("TOPLEFT", drift, "BOTTOMLEFT", 4, -26)
	Tooltip(driftAmount, "How far the strength wanders either way, as a share of the strength.")
	GreyUnless(driftAmount, function(db) return db.tintDrift end)

	-- When the tint shows
	local whenLabel = Label(content, "GameFontHighlight", "Show the tint")
	whenLabel:SetPoint("TOPLEFT", driftAmount, "BOTTOMLEFT", -4, -24)
	local tintBack = SituationChecks(content, "tint", whenLabel, -2, -6,
		{ it = "the tint", away = "fade it away" }, ns.RefreshTint)

	-- Time of day: which clock, strength, your own phases
	local timeHeader = Header(content, "Time of day", tintBack, -24)
	timeHeader:SetPoint("TOPLEFT", tintBack, "BOTTOMLEFT", 2, -20)
	local timeHelp = Label(content, "GameFontHighlightSmall",
		"For the Time of day and Zone + time of day presets, and the time of day message.")
	timeHelp:SetPoint("TOPLEFT", timeHeader, "BOTTOMLEFT", 0, -6)

	local timeMessage = Check(content, "timeOfDayMessage", "Show the time of day",
		"Dawn, Morning, Midday, Afternoon, Evening, Dusk or Night, under the zone name when " ..
		"you log in or reload, and on its own when it changes during play (not in combat), " ..
		"with a fitting sound: a rooster at dawn, a horse in the morning, your faction's bell " ..
		"at midday, frogs in the evening, an owl at dusk and a wolf at night. Follows the clock " ..
		"below.")
	timeMessage:SetPoint("TOPLEFT", timeHelp, "BOTTOMLEFT", -2, -8)

	local clockLabel = Label(content, "GameFontHighlight", "Follows")
	clockLabel:SetPoint("TOPLEFT", timeMessage, "BOTTOMLEFT", 2, -10)
	local CLOCKS = {
		{ value = "game", text = "Game time (matches the game's day and night)" },
		{ value = "local", text = "Your computer's clock" },
	}
	local clockControl = Dropdown(content, "tintClock", CLOCKS, 300, function()
		ns.RefreshTint()
	end)
	if clockControl then
		clockControl:SetPoint("TOPLEFT", clockLabel, "BOTTOMLEFT", 0, -6)
	else
		local previous = clockLabel
		for i, clock in ipairs(CLOCKS) do
			local check = Choice(content, "tintClock", clock.value, clock.text)
			check:HookScript("OnClick", ns.RefreshTint)
			check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
			previous = check
		end
		clockControl = previous
	end

	-- Time of day: strength and your own phase colours
	local timeStrength = Slider(content, "timeTintStrength", "Time of day strength", 0, 100, 5, "%d%%", 100,
		ns.RefreshTint)
	timeStrength:SetPoint("TOPLEFT", clockControl, "BOTTOMLEFT", 4, -30)
	Tooltip(timeStrength, "How strongly the time-of-day colour applies, in Time of day and " ..
		"Zone + time of day. Lower it for softer nights; 0 leaves just the zone mood.")

	local phaseLabel = Label(content, "GameFontHighlight", "Phases (click a colour to change it)")
	phaseLabel:SetPoint("TOPLEFT", timeStrength, "BOTTOMLEFT", -4, -24)
	local previousPhase = phaseLabel
	for i, phase in ipairs(ns.GetTimePhases()) do
		local name = phase.name
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(460, 40) -- room for the strength slider's label above it
		row:SetPoint("TOPLEFT", previousPhase, "BOTTOMLEFT", 0, i == 1 and -2 or 0)
		local swatch = CreateFrame("Button", nil, row)
		swatch:SetSize(20, 20)
		swatch:SetPoint("BOTTOMLEFT", 0, 4)
		local border = swatch:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		border:SetColorTexture(0.6, 0.6, 0.6, 1)
		local fill = swatch:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("TOPLEFT", 2, -2)
		fill:SetPoint("BOTTOMRIGHT", -2, 2)
		local text = Label(row, "GameFontHighlightSmall", name)
		text:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
		text:SetWidth(110)
		text:SetJustifyH("LEFT")
		local strength = Slider(row, {
			get = function()
				for _, p in ipairs(ns.GetTimePhases()) do
					if p.name == name then return p.strength end
				end
				return 1
			end,
			set = function(value) ns.SetTimePhaseStrength(name, value) end,
		}, "Strength", 0, 100, 5, "%d%%", 100, function()
			ns.PreviewTintHour(phase.hour) -- show the phase you're adjusting
		end)
		strength:SetWidth(150)
		strength:SetPoint("LEFT", text, "RIGHT", 4, 0)
		local reset = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		reset:SetSize(60, 20)
		reset:SetPoint("LEFT", strength, "RIGHT", 16, 0)
		reset:SetText("Reset")
		Tooltip(reset, "Back to the built-in colour and strength.")
		Tooltip(swatch, "Choose your own colour for " .. name .. ".")
		swatch:SetScript("OnClick", function()
			local color
			for _, p in ipairs(ns.GetTimePhases()) do
				if p.name == name then color = p.color end
			end
			OpenColorPicker(color[1], color[2], color[3], function(r, g, b)
				ns.SetTimePhaseColor(name, { r, g, b })
				Refresh()
			end)
		end)
		reset:SetScript("OnClick", function()
			ns.SetTimePhaseColor(name, nil)
			ns.SetTimePhaseStrength(name, nil)
			Refresh()
		end)
		row.Refresh = function()
			for _, p in ipairs(ns.GetTimePhases()) do
				if p.name == name then
					fill:SetColorTexture(p.color[1], p.color[2], p.color[3], 1)
					reset:SetEnabled(p.own or p.ownStrength)
				end
			end
		end
		controls[#controls + 1] = row
		previousPhase = row
	end

	-- Per-zone overrides: a preset of its own, and colours for the Zone presets
	local zoneHeader = Header(content, "Zone tints", previousPhase, -24)
	local zoneHelp = Label(content, "GameFontHighlightSmall",
		"Give the zone you're standing in, or just the area within it (a town, a port), a " ..
		"preset of its own: it replaces your main preset there. With a Zone preset you can also " ..
		"choose its colour, which replaces the built-in mood. An area's choices win over its zone's.")
	zoneHelp:SetPoint("TOPLEFT", zoneHeader, "BOTTOMLEFT", 0, -6)
	zoneHelp:SetWidth(420)
	zoneHelp:SetJustifyV("TOP")

	local zoneText = Label(content, "GameFontHighlight")
	zoneText:SetPoint("TOPLEFT", zoneHelp, "BOTTOMLEFT", 0, -10)
	zoneText:SetWidth(420)
	zoneText:SetJustifyH("LEFT")
	zoneText.Refresh = function(self)
		local zone, label, isOverride = ns.GetZoneTintInfo()
		local strength, ownStrength = ns.GetZoneTintStrength(zone)
		local function PresetNote(name)
			local preset = ns.GetZonePreset(name)
			return preset and (", |cffffd100%s|r preset"):format(ns.GetTintPresetLabel(preset)) or ""
		end
		local text = ("This zone: |cffffd100%s|r - %s%s, %d%% strength%s%s"):format(
			zone ~= "" and zone or "?", label, isOverride and " (your choice)" or " (built in)",
			strength * 100 + 0.5, ownStrength and " (its own)" or "", PresetNote(zone))
		local area, areaLabel, areaOwn, _, areaStrength, _, areaOwnStrength = ns.GetAreaTintInfo()
		if area then
			text = text .. ("\nThis area: |cffffd100%s|r - %s%s, %d%% strength%s%s"):format(
				area, areaLabel, areaOwn and " (your choice)" or "", areaStrength * 100 + 0.5,
				areaOwnStrength and " (its own)" or "", PresetNote(area))
		end
		self:SetText(text)
	end
	controls[#controls + 1] = zoneText

	-- Which the choices below change: the zone, or just the area you're in.
	local tintTarget = "zone"
	local function TargetName()
		local area = ns.GetAreaTintInfo()
		if tintTarget == "area" and area then
			return area
		end
		return GetRealZoneText() or ""
	end
	local function TargetColor()
		local area, _, _, areaColor = ns.GetAreaTintInfo()
		if tintTarget == "area" and area then
			return areaColor
		end
		local _, _, _, color = ns.GetZoneTintInfo()
		return color
	end
	local targetLabel = Label(content, "GameFontHighlight", "Change:")
	targetLabel:SetPoint("TOPLEFT", zoneText, "BOTTOMLEFT", 0, -10)
	local targetButtons = {}
	local function TargetButton(value, x)
		local ok, button = pcall(CreateFrame, "CheckButton", nil, content, "UIRadioButtonTemplate")
		if not ok or not button then
			button = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
			button:SetSize(22, 22)
		end
		button:SetPoint("LEFT", targetLabel, "RIGHT", x, 0)
		button.text = Label(content, "GameFontHighlight")
		button.text:SetPoint("LEFT", button, "RIGHT", 2, 0)
		button:SetScript("OnClick", function()
			tintTarget = value
			Refresh()
		end)
		button.Refresh = function(self)
			local area = ns.GetAreaTintInfo()
			self:SetChecked(tintTarget == value or (value == "zone" and not area))
			if value == "zone" then
				self.text:SetText("the zone")
			else
				self.text:SetText(area and ("this area (" .. area .. ")") or "this area (none here)")
				self:SetEnabled(area ~= nil)
			end
		end
		controls[#controls + 1] = button
		targetButtons[#targetButtons + 1] = button
		return button
	end
	TargetButton("zone", 8)
	TargetButton("area", 110)

	local function SetHere(value)
		local name = TargetName()
		if name ~= "" then
			ns.SetZoneTint(name, value)
			Refresh()
			FitContentHeight(content)
		end
	end

	-- Menu of presets for this zone or area (left out on clients without the dropdown).
	local presetMenu
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, content, "WowStyle1DropdownTemplate")
	if ok and dropdown and dropdown.SetupMenu then
		presetMenu = dropdown
		presetMenu:SetWidth(200)
		presetMenu:SetupMenu(function(_, root)
			local function current() return ns.GetZonePreset(TargetName()) end
			local function set(value)
				local name = TargetName()
				if name ~= "" then
					ns.SetZonePreset(name, value)
					Refresh()
					FitContentHeight(content)
				end
			end
			local isArea = tintTarget == "area" and ns.GetAreaTintInfo()
			root:CreateRadio(isArea and "Same as the zone" or "Main preset",
				function() return current() == nil end, function() set(nil) end)
			for _, preset in ipairs(ns.TINT_PRESETS) do
				root:CreateRadio(preset.label, function() return current() == preset.key end,
					function() set(preset.key) end)
			end
		end)
		presetMenu.Refresh = function(self) self:GenerateMenu() end
		controls[#controls + 1] = presetMenu
		presetMenu:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -10)
		local presetMenuLabel = Label(content, "GameFontHighlight", "Preset here")
		presetMenuLabel:SetPoint("LEFT", presetMenu, "RIGHT", 12, 0)
		Tooltip(presetMenu, "A preset for the zone or area chosen above, used there instead of your " ..
			"main preset.")
	end

	-- Menu of tints for this zone (left out on clients without the dropdown).
	local zoneMenu
	ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, content, "WowStyle1DropdownTemplate")
	if ok and dropdown and dropdown.SetupMenu then
		zoneMenu = dropdown
		zoneMenu:SetWidth(200)
		zoneMenu:SetupMenu(function(_, root)
			local function current()
				local db = ns.GetDB()
				return db and db.zoneTints and db.zoneTints[TargetName()]
			end
			root:CreateRadio("Built-in mood", function() return current() == nil end,
				function() SetHere(nil) end)
			root:CreateRadio("No tint", function() return current() == "none" end,
				function() SetHere("none") end)
			for _, mood in ipairs(ns.GetZoneMoods()) do
				local hex = ("|cff%02x%02x%02x"):format(mood.color[1] * 255, mood.color[2] * 255, mood.color[3] * 255)
				root:CreateRadio(hex .. mood.label .. "|r", function() return current() == mood.key end,
					function() SetHere(mood.key) end)
			end
			root:CreateRadio("Custom colour", function() return type(current()) == "table" end,
				function()
					local color = TargetColor()
					SetHere({ color[1], color[2], color[3] })
				end)
		end)
		zoneMenu.Refresh = function(self) self:GenerateMenu() end
		controls[#controls + 1] = zoneMenu
		zoneMenu:SetPoint("TOPLEFT", presetMenu or targetLabel, "BOTTOMLEFT", 0, -10)
	end

	local pickColor = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	pickColor:SetSize(140, 22)
	pickColor:SetText("Pick a colour...")
	if zoneMenu then
		pickColor:SetPoint("LEFT", zoneMenu, "RIGHT", 12, 0)
	else
		pickColor:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -10)
	end
	Tooltip(pickColor, "Choose your own colour for the zone or area chosen above (for the Zone presets).")
	pickColor:SetScript("OnClick", function()
		local name = TargetName()
		if name == "" then
			return
		end
		local color = TargetColor()
		OpenColorPicker(color[1], color[2], color[3], function(r, g, b)
			ns.SetZoneTint(name, { r, g, b })
			Refresh()
			FitContentHeight(content)
		end)
	end)

	-- Your overrides, each with a reset button.
	local overridesLabel = Label(content, "GameFontNormalSmall", "Your zone tints")
	overridesLabel:SetPoint("TOPLEFT", zoneMenu or pickColor, "BOTTOMLEFT", 0, -16)
	local MAX_ZONE_ROWS = 15
	local zoneRows = {}
	for i = 1, MAX_ZONE_ROWS do
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(420, 22)
		row:SetPoint("TOPLEFT", overridesLabel, "BOTTOMLEFT", 0, -6 - (i - 1) * 24)
		row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.button:SetSize(70, 20)
		row.button:SetPoint("LEFT")
		row.button:SetText("Reset")
		row.button:SetScript("OnClick", function()
			if row.zone then
				ns.SetZoneTint(row.zone, nil)
				ns.SetZoneTintStrength(row.zone, nil)
				ns.SetZonePreset(row.zone, nil)
				Refresh()
				FitContentHeight(content)
			end
		end)
		row.swatch = row:CreateTexture(nil, "ARTWORK")
		row.swatch:SetSize(14, 14)
		row.swatch:SetPoint("LEFT", row.button, "RIGHT", 8, 0)
		row.text = Label(row, "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", row.swatch, "RIGHT", 8, 0)
		row.text:SetPoint("RIGHT")
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row:Hide()
		zoneRows[i] = row
	end
	local zoneMore = Label(content, "GameFontHighlightSmall")
	zoneMore.Refresh = function(self)
		local zones = {}
		local db, listed = ns.GetDB(), {}
		for _, source in ipairs({ db.zoneTints or {}, db.zoneTintStrength or {}, db.zonePresets or {} }) do
			for zone in pairs(source) do
				if not listed[zone] then
					listed[zone] = true
					zones[#zones + 1] = zone
				end
			end
		end
		table.sort(zones)
		for i, row in ipairs(zoneRows) do
			local zone = zones[i]
			row.zone = zone
			if zone then
				local _, label, _, color = ns.GetZoneTintInfo(zone)
				row.swatch:SetColorTexture(color[1], color[2], color[3], 1)
				local strength, ownStrength = ns.GetZoneTintStrength(zone)
				local preset = ns.GetZonePreset(zone)
				row.text:SetText(("%s: %s%s%s"):format(zone,
					preset and (ns.GetTintPresetLabel(preset) .. " preset, ") or "", label,
					ownStrength and (", %d%% strength"):format(strength * 100 + 0.5) or ""))
			end
			row:SetShown(zone ~= nil)
		end
		local shownRows = math.min(#zones, MAX_ZONE_ROWS)
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", overridesLabel, "BOTTOMLEFT", 0, -8 - shownRows * 24)
		if #zones == 0 then
			self:SetText("None yet.")
		elseif #zones > MAX_ZONE_ROWS then
			self:SetText(("...and %d more."):format(#zones - MAX_ZONE_ROWS))
		else
			self:SetText("")
		end
	end
	controls[#controls + 1] = zoneMore

	-- Keep "This zone" up to date if you cross a border with the page open.
	local zoneWatcher = CreateFrame("Frame", nil, canvas)
	zoneWatcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	zoneWatcher:RegisterEvent("ZONE_CHANGED") -- moving between areas within a zone
	zoneWatcher:SetScript("OnEvent", function()
		if canvas:IsVisible() then
			Refresh()
		end
	end)

	-- Crossing a zone border: how the old zone's tint gives way to the new one.
	local borderLabel = Label(content, "GameFontHighlight", "At zone borders")
	borderLabel:SetPoint("TOPLEFT", zoneMore, "BOTTOMLEFT", 0, -18)
	local zoneFade = Slider(content, "zoneFadeTime", "Fade time", 0.5, 10, 0.5, "%.1f sec")
	zoneFade:SetPoint("TOPLEFT", borderLabel, "BOTTOMLEFT", 2, -26)
	Tooltip(zoneFade, "With a Zone tint preset, crossing into a zone with a different mood " ..
		"fades the old mood out over this long, pauses, then fades the new one in over " ..
		"this long.")
	local gapFlying = Slider(content, "zoneGapFlying", "Pause between tints when flying", 0, 20, 1, "%d sec")
	gapFlying:SetPoint("TOPLEFT", zoneFade, "BOTTOMLEFT", 0, -34)
	Tooltip(gapFlying, "Untinted time between the two zones' moods while you're in the air, " ..
		"where you see the old zone's ground for longer (snow under an ember tint looks red).")
	local gapGround = Slider(content, "zoneGapTime", "Pause between tints on the ground", 0, 10, 0.5, "%.1f sec")
	gapGround:SetPoint("TOPLEFT", gapFlying, "BOTTOMLEFT", 0, -34)
	Tooltip(gapGround, "The same pause when you cross a border on foot or riding.")

	-- Vignette
	local vignetteHeader = Header(content, "Vignette", gapGround, -24)
	vignetteHeader:SetPoint("TOPLEFT", gapGround, "BOTTOMLEFT", -2, -24)

	local vignette = Check(content, "vignette", "Darken the screen edges",
		"Soft dark edges that draw the eye to the middle. Works with any tint.", function(value)
			ns.GetDB().vignette = value
			ns.RefreshTint()
		end)
	vignette:SetPoint("TOPLEFT", vignetteHeader, "BOTTOMLEFT", -2, -6)

	local vignetteStrength = Slider(content, "vignetteStrength", "Vignette strength", 10, 100, 5, "%d%%", 100,
		ns.RefreshTint)
	vignetteStrength:SetPoint("TOPLEFT", vignette, "BOTTOMLEFT", 4, -26)

	-- Inns
	local innHeader = Header(content, "Inns", vignetteStrength, -24)
	innHeader:SetPoint("TOPLEFT", vignetteStrength, "BOTTOMLEFT", -2, -24)

	local innGlow = Check(content, "innGlow", "Light up inns",
		"Indoors in an inn, the outdoor tint (a gloomy marsh, a moonlit night) partly lifts and a " ..
		"soft firelit glow fades in, coloured by the zone: cooler in the snow, greener in a swamp. " ..
		"Blends over a few seconds as you go through the door.",
		function(value)
			ns.GetDB().innGlow = value
			Refresh() -- grey out / enable the strength slider
			ns.RefreshTint()
		end)
	innGlow:SetPoint("TOPLEFT", innHeader, "BOTTOMLEFT", -2, -6)

	local innGlowStrength = Slider(content, "innGlowAmount", "Glow amount", 0, 25, 1, "%d%%", 100,
		ns.RefreshTint)
	Tooltip(innGlowStrength, "How much light the glow adds at its brightest, low on the screen.")
	innGlowStrength:SetPoint("TOPLEFT", innGlow, "BOTTOMLEFT", 4, -26)
	GreyUnless(innGlowStrength, function(db) return db.innGlow end)

	-- Weather
	local weatherHeader = Header(content, "Weather", innGlowStrength, -24)
	weatherHeader:SetPoint("TOPLEFT", innGlowStrength, "BOTTOMLEFT", -2, -24)

	local weatherTint = Check(content, "weatherTint", "Tint for the weather",
		"Rain greys and cools the scene, snow turns it pale blue and a sandstorm gives it a dusty " ..
		"orange haze, more strongly the heavier the weather. Works with any tint (None included), " ..
		"lifts under a roof and blends in as a storm builds. Needs a game version that reports " ..
		"the weather.",
		function(value)
			ns.GetDB().weatherTint = value
			Refresh() -- grey out / enable the strength slider
			ns.RefreshTint()
		end)
	weatherTint:SetPoint("TOPLEFT", weatherHeader, "BOTTOMLEFT", -2, -6)

	local weatherTintStrength = Slider(content, "weatherTintStrength", "Weather strength", 10, 100, 5, "%d%%", 100,
		ns.RefreshTint)
	weatherTintStrength:SetPoint("TOPLEFT", weatherTint, "BOTTOMLEFT", 4, -26)
	GreyUnless(weatherTintStrength, function(db) return db.weatherTint end)

	-- Depth of field
	local dofHeader = Header(content, "Depth of field", weatherTintStrength, -24)
	dofHeader:SetPoint("TOPLEFT", weatherTintStrength, "BOTTOMLEFT", -2, -24)

	local depthOfField = Check(content, "depthOfField", "Haze the screen edges in the camera modes",
		"A soft haze around the edges of the screen, as if the camera had focused on you. " ..
		"Each camera mode's page sets its own strength. /cine doftest shows it on demand.")
	depthOfField:SetPoint("TOPLEFT", dofHeader, "BOTTOMLEFT", -2, -6)

	canvas:SetScript("OnShow", PageShown(function()
		Refresh()
		ns.SetTintPreview(true)
	end, content))
	canvas:SetScript("OnHide", function() ns.SetTintPreview(false) end)
	-- Everything else on the page greys out while the master switch is off
	-- (on top of its own greying: this only ever turns a control off).
	for i = firstControl, #controls do
		local control = controls[i]
		if control ~= master then
			local refresh = control.Refresh
			control.Refresh = function(self)
				refresh(self)
				if not ns.GetDB().visualEffects then
					if self.SetEnabled then self:SetEnabled(false) end
					local label = self.Text or self.text
					if label and self.GetObjectType and self:GetObjectType() == "CheckButton" then
						label:SetFontObject("GameFontDisable")
					end
				end
			end
		end
	end
	canvas:Hide()
	RegisterSubpage(canvas, "Visual Effects")
end

-- Sub-page for audio: music during cinematic mode.
local function CreateAudioPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Audio")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"Sound during CineMode. Your own sound settings are saved first and put " ..
		"back afterwards, even after a crash. Pick which cameras play music as they start.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Left column: music, fresh songs, fatigue
	local musicHeader = Header(content, "Music", subtitle, -20)

	local music = Check(content, "musicInCinematic", "Play music in CineMode",
		"Fades game music in when the UI fades out and back out when it returns, " ..
		"using your music volume. If music was already on, it's left alone.")
	music:SetPoint("TOPLEFT", musicHeader, "BOTTOMLEFT", -2, -6)
	music:HookScript("OnClick", Refresh) -- grey out / enable the options that depend on it

	local logoutMusic = Check(content, "musicOffOnLogout", "Turn music off on logout",
		"Switches game music off when you log out or exit, so it starts off next time.")
	logoutMusic:SetPoint("TOPLEFT", music, "BOTTOMLEFT", 0, -2)

	local musicFade = Slider(content, "musicFadeTime", "Music fade time", 0.5, 10, 0.5, "%.1f sec")
	musicFade:SetPoint("TOPLEFT", logoutMusic, "BOTTOMLEFT", 4, -26)
	Tooltip(musicFade, "How long music takes to fade in or out with CineMode.")

	local fatigueHeader = Header(content, "Fatigue", musicFade, -24)
	fatigueHeader:SetPoint("TOPLEFT", musicFade, "BOTTOMLEFT", -2, -24)

	local fatigue = Slider(content, "musicFatigue", "Music fatigue", 0, 30, 1, "%d min")
	fatigue:SetPoint("TOPLEFT", fatigueHeader, "BOTTOMLEFT", 2, -26)
	Tooltip(fatigue, "Once the addon has started music, it won't start it again for this " ..
		"long, so short spells of CineMode don't keep restarting it. The events ticked under " ..
		"Music on the Camera Triggers page start it anyway. Music coming back after a mute doesn't count. 0 turns this off.")
	DependsOnMusic(fatigue)

	-- Right column: muting
	local muteHeader = Label(content, "GameFontNormal", "Muting")
	muteHeader:SetPoint("TOPLEFT", musicHeader, "TOPLEFT", 320, 0)

	local combatMusic = Check(content, "musicOffInCombat", "Mute music in combat",
		"Music fades out over about a second when a fight starts, and a fresh track fades back " ..
		"in once the Calm Timer (on the CineMode page) has passed with no new fight. Works on " ..
		"your own game music too; your volume is put back afterwards.")
	combatMusic:SetPoint("TOPLEFT", muteHeader, "BOTTOMLEFT", -2, -6)
	DependsOnMusic(combatMusic)

	local flightMusic = Check(content, "musicOffOnFlights", "Mute music on flights",
		"Music fades out and switches off when you take off, and a fresh track fades in " ..
		"when you land.")
	flightMusic:SetPoint("TOPLEFT", combatMusic, "BOTTOMLEFT", 0, -2)
	DependsOnMusic(flightMusic)

	local movingMusic = Check(content, "musicPauseWhenMoving", "Pause music when you move on",
		"Music fades out once you start moving after a flight, RP walking or standing still " ..
		"(running, riding). A fresh track fades in when you next fly, walk, or sit down (or stand " ..
		"still for the AFK camera delay, with Go AFK's music on, Camera Triggers page).")
	movingMusic:SetPoint("TOPLEFT", flightMusic, "BOTTOMLEFT", 0, -2)
	DependsOnMusic(movingMusic)
	movingMusic:HookScript("OnClick", Refresh) -- grey out / enable the fade below

	local landingMusic = Check(content, "musicPauseOnLanding", "Pause music when a flight lands",
		"Music fades out as soon as you touch down, without waiting for you to move. A fresh " ..
		"track fades in when you next fly, walk, or sit down (or stand still for the AFK camera " ..
		"delay, with Go AFK's music on, Camera Triggers page).")
	landingMusic:SetPoint("TOPLEFT", movingMusic, "BOTTOMLEFT", 0, -2)
	DependsOnMusic(landingMusic)
	landingMusic:HookScript("OnClick", Refresh)

	local pauseFade = Slider(content, "musicPauseFadeTime", "Pause fade time", 0.5, 10, 0.5, "%.1f sec")
	pauseFade:SetPoint("TOPLEFT", landingMusic, "BOTTOMLEFT", 24, -26)
	Tooltip(pauseFade, "How long the music takes to fade out when you move on or land, and to " ..
		"fade back in when the next flight, walk or other camera starts.")
	GreyUnless(pauseFade, function(db)
		return db.musicInCinematic and (db.musicPauseWhenMoving or db.musicPauseOnLanding)
	end)

	-- Back out to the checkboxes' edge for the next heading.
	local pauseFadeEdge = CreateFrame("Frame", nil, content)
	pauseFadeEdge:SetSize(1, 1)
	pauseFadeEdge:SetPoint("TOPLEFT", pauseFade, "BOTTOMLEFT", -24, -4)

	local placeChecks = PlaceList(content, Stack(pauseFadeEdge, "check"), "Mute music in", "musicOffIn",
		"Music fades out here (your own game music too) and back in when you leave.")
	for _, check in ipairs(placeChecks) do
		DependsOnMusic(check)
	end

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Audio")
end

-- Sub-page for combat: staying cinematic in fights, and what to show then.
local function CreateCombatPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Standard Frames")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"Everything here is hidden in CineMode unless ticked. Tick a column to show that frame: " ..
		"CineMode shows it the whole time, the others only while you fight or have something " ..
		"targeted. Frames fade in and out at the fade times on the CineMode page. Other addons' " ..
		"frames are on the 3rd Party Frames page.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- One table: a row per frame, a column per situation.
	local LABEL_WIDTH, COLUMN_WIDTH, ROW_HEIGHT = 220, 100, 24
	local COLUMNS = {
		{ "CineMode", ns.IsCineShowOn, "cineShow", false },
		{ "In combat", ns.IsCombatShowOn, "combatShow", true },
		{ "Tar Enemy", ns.IsEnemyShowOn, "enemyShow", false },
		{ "Tar Friendly", ns.IsFriendlyShowOn, "friendlyShow", false },
	}
	local columnTop = CreateFrame("Frame", nil, content)
	columnTop:SetSize(1, 1)
	columnTop:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -20)
	for c, column in ipairs(COLUMNS) do
		local heading = Label(content, "GameFontNormalSmall", column[1])
		heading:SetWidth(COLUMN_WIDTH)
		heading:SetJustifyH("CENTER")
		heading:SetPoint("TOPLEFT", columnTop, "TOPLEFT", LABEL_WIDTH + (c - 1) * COLUMN_WIDTH, 0)
	end

	-- The game's frames this client has. Other addons' frames have the same
	-- columns on the 3rd Party Frames page.
	local rows = {}
	for _, item in ipairs(ns.COMBAT_SHOW) do
		if ns.OptionAvailable(item) and not item.key:find("^addon:") then
			rows[#rows + 1] = item
		end
	end
	for r, item in ipairs(rows) do
		local y = -16 - (r - 1) * ROW_HEIGHT
		local rowLabel = Label(content, "GameFontHighlight", item.label)
		rowLabel:SetPoint("TOPLEFT", columnTop, "TOPLEFT", 0, y - 5)
		-- An asterisk, with a tip, on rows that have a page of their own.
		if item.morePage then
			rowLabel:SetText(item.label .. " |cffffd100*|r")
			local hover = CreateFrame("Frame", nil, content)
			hover:SetAllPoints(rowLabel)
			hover:EnableMouse(true)
			Tooltip(hover, ("More settings on the %s page. They can keep it up beyond what's " ..
				"ticked here (hovering, tracking, new auras and the like)."):format(item.morePage))
		end
		if ns.CINE_SHOW_SETTING[item.key] then
			RecordKey(content, ns.CINE_SHOW_SETTING[item.key]) -- (for the page's Reset)
		end
		for c, column in ipairs(COLUMNS) do
			local isOn, tableKey, needsStay = column[2], column[3], column[4]
			local check = Check(content, tableKey, "", c == 1 and
				"Show it all through CineMode, instead of hiding it. (The other columns then have nothing to add.)" or nil, function(value)
				local setting = c == 1 and ns.CINE_SHOW_SETTING[item.key]
				if setting then
					ns.GetDB()[setting] = value
				else
					ns.GetDB()[tableKey][item.key] = value
				end
				if c == 1 then Refresh() end -- (greys the other columns)
			end)
			check:SetPoint("TOPLEFT", columnTop, "TOPLEFT",
				LABEL_WIDTH + (c - 1) * COLUMN_WIDTH + (COLUMN_WIDTH - 26) / 2, y)
			check.Refresh = function(self)
				self:SetChecked(isOn(item.key))
				self:SetEnabled(c == 1 or (not ns.IsCineShowOn(item.key)
					and (not needsStay or ns.GetDB().stayInCombat)))
			end
		end
	end

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Standard Frames")
end

-- Sub-page: which nameplates show (mobs, your faction, the other faction),
-- which stay up in cinematic mode, and how far away they show.
local function CreatePlatesPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Nameplates")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"Which nameplates and names stay up in CineMode, in fights and in each kind of place.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Nameplates and names each get a table: a row per kind of unit, a column
	-- per situation. A narrower table can set its first column apart (gap).
	local LABEL_WIDTH, COLUMN_WIDTH, ROW_HEIGHT = 220, 120, 24
	local function TableTop(anchor, headings, labelWidth, columnWidth, gap)
		local top = CreateFrame("Frame", nil, content)
		top:SetSize(1, 1)
		top:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
		top.width, top.xs = columnWidth or COLUMN_WIDTH, {}
		for c, heading in ipairs(headings) do
			top.xs[c] = (labelWidth or LABEL_WIDTH) + (c - 1) * top.width + (c > 1 and gap or 0)
			local text = Label(content, "GameFontNormalSmall", heading)
			text:SetWidth(top.width)
			text:SetJustifyH("CENTER")
			text:SetPoint("TOPLEFT", top, "TOPLEFT", top.xs[c], 0)
		end
		return top
	end
	-- indent: a row that sits under the one before (Minions), as in the game's options.
	local function PlaceRow(top, r, label, indent, ...)
		local y = -16 - (r - 1) * ROW_HEIGHT
		local rowLabel = Label(content, indent and "GameFontHighlightSmall" or "GameFontHighlight", label)
		rowLabel:SetPoint("TOPLEFT", top, "TOPLEFT", indent and 18 or 0, y - 5)
		for c, check in ipairs({ ... }) do
			check:SetPoint("TOPLEFT", top, "TOPLEFT", top.xs[c] + (top.width - 26) / 2, y)
		end
		return rowLabel
	end

	local showHeader = Header(content, "Nameplates", subtitle, -18)
	-- The grid can't keep plates up out of fights while the game's own
	-- "Always Show Nameplates" is off: say so beside it (checked as the page shows).
	local showAllWarning = Label(content, "GameFontRedSmall",
		"Blizzard's Always Show Nameplates is off, so nameplates only show in combat.")
	showAllWarning:SetPoint("LEFT", showHeader, "RIGHT", 10, 0)
	showAllWarning.Refresh = function(self)
		self:SetShown(GetCVar("nameplateShowAll") == "0")
	end
	controls[#controls + 1] = showAllWarning
	local PLACE_COLUMNS = {
		{ "", "Open world", "anywhere else (inns too)" }, { "Cities", "Cities", "in capital cities" },
		{ "Dungeons", "Dungeons", "in dungeons and scenarios" }, { "Raids", "Raids", "in raids" },
		{ "PvP", "BGs", "in battlegrounds and arenas" },
	}
	local headings = { "In combat" }
	for _, place in ipairs(PLACE_COLUMNS) do
		headings[#headings + 1] = place[2]
	end
	local columnTop = TableTop(showHeader, headings, 200, 62, 10)

	-- The game's own nameplate options, with enemy players and NPCs apart.
	local KINDS = {
		{ "Enemies", "Enemy Players" },
		{ "EnemyMinions", "Minions", true },
		{ "EnemyNPCs", "Enemy NPCs" },
		{ "EnemyMinor", "Minor", true },
		{ "Friends", "Friendly Players" },
		{ "FriendlyMinions", "Minions", true },
		{ "FriendlyNPCs", "Friendly NPCs" },
		-- Your target, whatever its own row says (not a game option of its own).
		{ "EnemyTarget", "Enemy Target", false, "a target you can attack (neutral mobs too)" },
		{ "FriendlyTarget", "Friendly Target", false, "a target you can't attack" },
	}
	local rowTip = " Ticking it switches this kind of nameplate on in the game's own options."
	local lastLabel
	for r, kind in ipairs(KINDS) do
		local target = kind[4]
		local tip = target and (" The nameplate of " .. target .. " shows here whatever its own row " ..
			"says. It still needs that kind of nameplate switched on in the game's own options, or " ..
			"there's no plate to show.") or rowTip
		local function Ticked(key)
			return function(value)
				ns.GetDB()[key] = value
				if value and not target then
					ns.EnablePlateRow(kind[1])
				end
				Refresh()
			end
		end
		local combatKey = "plateCombat" .. kind[1]
		local checks = {
			Check(content, combatKey, "",
				"Show these nameplates during fights in CineMode, and for the Calm Timer (on the " ..
				"CineMode page) after. The game won't let nameplates be switched off mid-fight, so " ..
				"hidden ones can still be clicked." .. tip, Ticked(combatKey)),
		}
		for _, place in ipairs(PLACE_COLUMNS) do
			-- The open world keeps the original "keep up in CineMode" key.
			local key = place[1] == "" and ("plateCinematic" .. kind[1]) or ("plateIn" .. place[1] .. kind[1])
			checks[#checks + 1] = Check(content, key, "",
				("Keep these nameplates up in CineMode %s when you're not in a fight."):format(place[3])
				.. tip, Ticked(key))
		end
		if not target then
			for _, check in ipairs(checks) do
				-- Greyed out where this client has no such setting.
				GreyUnless(check, function() return ns.HasPlateSettings(kind[1]) end)
			end
		end
		lastLabel = PlaceRow(columnTop, r, kind[2], kind[3], unpack(checks))
	end
	local lastPlateRow = lastLabel

	-- Names, laid out the same way. Outside cinematic mode the game's own
	-- name options decide.
	local namesHeader = Header(content, "Names", lastLabel, -24)
	local namesTop = TableTop(namesHeader, headings, 200, 62, 10)
	local nameTip = " Ticking it switches these names on in the game's own options."
	for r, group in ipairs(ns.NAME_GROUPS) do
		local function Ticked(key)
			return function(value)
				ns.GetDB()[key] = value
				if value then
					ns.EnableNameRow(group)
				end
				Refresh()
			end
		end
		local combatKey = "nameCombat" .. group.key
		local checks = {
			Check(content, combatKey, "", "Keep these names up during fights in CineMode." .. nameTip,
				Ticked(combatKey)),
		}
		for _, place in ipairs(PLACE_COLUMNS) do
			-- The open world keeps the original Keep column's key.
			local key = place[1] == "" and ("nameKeep" .. group.key) or ("nameIn" .. place[1] .. group.key)
			checks[#checks + 1] = Check(content, key, "",
				("Keep these names up in CineMode %s when you're not in a fight."):format(place[3])
				.. nameTip, Ticked(key))
		end
		for _, check in ipairs(checks) do
			-- Greyed out where this client has no such setting.
			GreyUnless(check, function() return ns.HasNameSettings(group) end)
		end
		PlaceRow(namesTop, r, group.label, group.indent, unpack(checks))
	end

	-- Laid out top to bottom: the target and fight settings, then the two
	-- grids (nameplates, then names).
	showHeader:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)
	-- (Lined up with the nameplate grid, so both grids' columns match.)
	namesHeader:SetPoint("TOPLEFT", lastPlateRow, "BOTTOMLEFT", 0, -24)

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Nameplates")
end

-- Sub-page for everything chat: fading, new-message peeks (by message type and
-- by channel) and the places chat stays visible.
local channelRows = {}

local function RefreshChannels()
	local channels = ns.GetJoinedChannels()
	local previous = chatPanel.channelHelp
	for i, name in ipairs(channels) do
		local row = channelRows[i]
		if not row then
			row = CreateFrame("CheckButton", nil, chatPanel, "UICheckButtonTemplate")
			row:SetSize(26, 26)
			row.label = row.Text or row.text
			if not row.label then
				row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				row.label:SetPoint("LEFT", row, "RIGHT", 2, 0)
			end
			row.label:SetFontObject("GameFontHighlight")
			row:SetScript("OnClick", function(self)
				ns.GetDB().chatPeekChannelList[self.channel] = self:GetChecked() and true or false
			end)
			channelRows[i] = row
		end
		row.channel = name
		row.label:SetText(name)
		row:SetChecked(ns.IsChannelPeekOn(name))
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
		row:Show()
		previous = row
	end
	for i = #channels + 1, #channelRows do
		channelRows[i]:Hide()
	end
	chatPanel.noChannels:SetShown(#channels == 0)
end

local function CreateChatPanel()
	local chatCanvas
	chatCanvas, chatPanel = CreateScrollPage()

	local title = Label(chatPanel, "GameFontNormalLarge", "Chat")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(chatPanel, "GameFontHighlightSmall",
		"The chat window fades with the rest of the UI in CineMode. Mousing over it or typing " ..
		"always shows it.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", chatPanel, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Left column: the chat window, message types
	local windowHeader = Header(chatPanel, "Chat window", subtitle, -20)

	local chatPeek = Check(chatPanel, "chatPeek", "Show chat when a message arrives",
		"While the UI is faded, a new message briefly shows just the chat window it " ..
		"arrived in. Choose which messages below.", function(value)
			ns.GetDB().chatPeek = value
			Refresh() -- grey out / enable the time and the messages below
		end)
	chatPeek:SetPoint("TOPLEFT", windowHeader, "BOTTOMLEFT", -2, -6)
	local function IfPeek(db) return db.chatPeek end

	local peekTime = Slider(chatPanel, "chatPeekTime", "Show chat for", 2, 30, 1, "%d sec")
	peekTime:SetPoint("TOPLEFT", chatPeek, "BOTTOMLEFT", 4, -26)
	Tooltip(peekTime, "How long chat stays up after a message arrives or after you finish typing.")
	GreyUnless(peekTime, IfPeek)

	local typesHeader = Header(chatPanel, "Show chat for these messages", peekTime, -24)
	local previous, previousIsHeader, section = typesHeader, true, nil
	for _, peekType in ipairs(ns.CHAT_PEEK_TYPES) do
		if peekType.section == "game" and section ~= "game" then
			section = "game"
			local gameHeader = Label(chatPanel, "GameFontNormal", "Game messages")
			gameHeader:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 2, -14)
			previous, previousIsHeader = gameHeader, true
		end
		local check = TableCheck(chatPanel, "chatPeekTypes", peekType.key, peekType.label,
			peekType.default ~= false)
		GreyUnless(check, IfPeek)
		check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previousIsHeader and -2 or 0,
			previousIsHeader and -6 or -2)
		previous, previousIsHeader = check, false
	end

	-- Right column: the places chat stays up, then channels the player has joined
	local keepHeader = Label(chatPanel, "GameFontNormal", "Always show in")
	keepHeader:SetPoint("TOPLEFT", windowHeader, "TOPLEFT", 320, 0)
	local CHAT_TIP = "The chat window stays up here while the rest of the UI fades. " ..
		"Only matters where CineMode isn't turned off."
	previous = keepHeader
	for i, place in ipairs({
		{ "chatInCities", "Cities", "Capital cities. " },
		{ "chatInDungeons", "Dungeons", "" },
		{ "chatInRaids", "Raids", "" },
		{ "chatInPvP", "Battlegrounds and arenas", "" },
	}) do
		local check = Check(chatPanel, place[1], place[2], place[3] .. CHAT_TIP)
		check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
		previous = check
	end

	local channelHeader = Label(chatPanel, "GameFontNormal", "Show chat for these channels")
	channelHeader:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 2, -18)

	chatPanel.channelHelp = Label(chatPanel, "GameFontHighlightSmall",
		"Channels you've joined, like General or Trade. The list updates each time " ..
		"you open this page.")
	chatPanel.channelHelp:SetPoint("TOPLEFT", channelHeader, "BOTTOMLEFT", 0, -6)
	chatPanel.channelHelp:SetWidth(260)
	chatPanel.channelHelp:SetJustifyV("TOP")

	chatPanel.noChannels = Label(chatPanel, "GameFontDisableSmall", "No channels joined.")
	chatPanel.noChannels:SetPoint("TOPLEFT", chatPanel.channelHelp, "BOTTOMLEFT", 0, -10)

	chatCanvas:SetScript("OnShow", PageShown(function()
		Refresh()
		if ns.GetDB() then RefreshChannels() end
	end, chatPanel))
	chatCanvas:Hide()
	RegisterSubpage(chatCanvas, "Chat")
end

-- Sub-page listing the built-in frames, each with a checkbox to keep it shown.
local RefreshExtras

-- One row of the extras list, made as needed: Stop/Restore, Delete, the name.
local function GetExtraRow(index)
	local row = extraRows[index]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, extrasPanel)
	row:SetSize(560, 22)
	row:SetPoint("TOPLEFT", extrasPanel.help, "BOTTOMLEFT", 0, -10 - (index - 1) * 24)

	row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.button:SetSize(70, 20)
	row.button:SetPoint("LEFT")
	row.button:SetScript("OnClick", function()
		if row.item.faded then
			ns.StopFading(row.item.name)
		else
			ns.UnignoreFrame(row.item.name)
		end
		RefreshExtras()
	end)

	row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.delete:SetSize(70, 20)
	row.delete:SetPoint("LEFT", row.button, "RIGHT", 4, 0)
	row.delete:SetText("Delete")
	Tooltip(row.delete, "Removes this frame from the list. A frame you added stops fading; " ..
		"one you stopped fades again if it's one the addon fades by itself.")
	row.delete:SetScript("OnClick", function()
		ns.ForgetExtraFrame(row.item.name)
		RefreshExtras()
	end)

	row.text = Label(row, "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row.delete, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT")
	row.text:SetWordWrap(false)
	extraRows[index] = row
	return row
end

RefreshExtras = function()
	local faded, ignored = ns.GetExtraFrames()
	local items = {}
	for _, name in ipairs(faded) do items[#items + 1] = { name = name, faded = true } end
	for _, name in ipairs(ignored) do items[#items + 1] = { name = name, faded = false } end

	for i, item in ipairs(items) do
		local row = GetExtraRow(i)
		row.item = item
		row.text:SetText(item.faded and item.name or ("|cff808080" .. item.name .. "|r"))
		row.button:SetText(item.faded and "Stop" or "Restore")
		row:Show()
	end
	for i = #items + 1, #extraRows do extraRows[i]:Hide() end

	extrasPanel.empty:SetShown(#items == 0)
	FitContentHeight(extrasPanel)
end

-- Sub-page: other addons' frames. The addons faded out of the box (a switch
-- for each one installed; the rest listed), then frames beyond the built-in
-- list, faded with /cine add.
-- Sub-page: the minimap in cinematic mode, always or while tracking.
local function CreateMinimapPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Minimap")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"When the minimap (and on retail the quest waypoint) stays up in CineMode. " ..
		"Hovering the minimap always shows it. To keep it up all the time, or in fights, " ..
		"see the Standard Frames page.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Retail's quest waypoint (the marker in the world showing where to go).
	local aboveTracking
	if ns.OptionAvailable({ retail = true }) then
		local waypoint = Check(content, "alwaysShowWaypoint", "Always show the quest waypoint",
			"Keeps the marker showing where your tracked quest or map pin is, with its " ..
			"distance, visible in CineMode. Off, it fades with the rest of the UI.")
		waypoint:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -14)
		aboveTracking = waypoint
	end

	-- Or only while tracking; the kinds of tracking below only apply while it's on.
	local trackingMaster = Check(content, "minimapForTracking", "Keep minimap open while tracking",
		"While you're tracking one of the kinds ticked below, the minimap stays up during " ..
		"CineMode. Also on the minimap button's menu.", function(value)
			ns.GetDB().minimapForTracking = value
			Refresh()
		end)
	if aboveTracking then
		trackingMaster:SetPoint("TOPLEFT", aboveTracking, "BOTTOMLEFT", 0, -2)
	else
		trackingMaster:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -14)
	end
	local TRACKING_TIP = "While this tracking is active, the minimap stays up during cinematic " ..
		"mode so you can spot nodes or creatures."
	local previousTracking = trackingMaster
	for i, kind in ipairs({
		{ "minimapForHerbs", "Herbs (Find Herbs)" },
		{ "minimapForMinerals", "Minerals (Find Minerals)" },
		{ "minimapForTreasure", "Treasure (Find Treasure)" },
		{ "minimapForFish", "Fish (Find Fish)" },
		{ "minimapForCreatures", "Creatures (hunter, druid, warlock)" },
		{ "trackingHideWhenIdle", "Except when standing still or flying",
			"Tracking doesn't keep the minimap up on flight paths, or once you've stood " ..
			"still for the AFK camera delay. It comes back when you move." },
	}) do
		local check = Check(content, kind[1], kind[2], kind[3] or TRACKING_TIP)
		check:SetPoint("TOPLEFT", previousTracking, "BOTTOMLEFT", i == 1 and 16 or 0, -2)
		GreyUnless(check, function(db) return db.minimapForTracking end)
		previousTracking = check
	end
	-- Places where tracking doesn't keep the minimap up, in the usual place order.
	local exceptIn = Label(content, "GameFontHighlight", "Except in")
	exceptIn:SetPoint("TOPLEFT", previousTracking, "BOTTOMLEFT", 4, -4)
	local PLACE_TIPS = {
		Cities = "Capital cities. ",
		PvP = "Alterac Valley's mines do have ore, so untick this if you mine there. ",
	}
	for i, place in ipairs(PLACES) do
		local check = Check(content, "trackingOffIn" .. place[1], place[2], (PLACE_TIPS[place[1]] or "") ..
			"Tracking doesn't keep the minimap up here. Hovering it still shows it.")
		check:SetPoint("TOPLEFT", i == 1 and exceptIn or previousTracking, "BOTTOMLEFT",
			i == 1 and 12 or 0, i == 1 and -4 or -2)
		GreyUnless(check, function(db) return db.minimapForTracking end)
		previousTracking = check
	end
	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Minimap")
end

-- Sub-page: the quest tracker in CineMode: the quest timer, and a look at
-- the tracker when you accept a quest.
local function CreateQuestTrackerPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Quest tracker")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"When the quest tracker comes up in CineMode. Hovering it always shows it. To keep it " ..
		"up all the time, or in fights, see the Standard Frames page.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	local reveal = Check(content, "questRevealOnAccept", "Reveal on new quest",
		"Accepting a quest shows the quest tracker as if you'd hovered it: it goes after the " ..
		"quest tracker's mouseover time on the CineMode page (or \"Stays after mouseover\" " ..
		"if it doesn't have its own).")
	reveal:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -14)

	-- Classic's quest timer box (retail shows timers in the tracker itself).
	if ns.OptionAvailable({ retail = false }) then
		local timer = Check(content, "questTimerShow", "Show the quest timer while one is running",
			"Keeps the quest timer box up in CineMode, and in fights, while a timed quest " ..
			"counts down. Just the timer: the quest tracker stays faded.")
		timer:SetPoint("TOPLEFT", reveal, "BOTTOMLEFT", 0, -2)
	end

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Quest tracker")
end

-- Sub-page: world tooltips (units and objects under the cursor) in cinematic mode.
local function CreateTooltipPanel()
	local canvas, content = CreateScrollPage()

	-- When world tooltips are hidden (throughout cinematic mode or only in the
	-- camera modes ticked Hide, and the modes where they never come back),
	-- then how they come back after hovering.
	local title = Label(content, "GameFontNormalLarge", "Tooltips")
	title:SetPoint("TOPLEFT", 16, -16)

	local tooltipNote = Label(content, "GameFontHighlightSmall",
		"The tooltips for players, NPCs and objects you mouse over in the world. Tooltips for UI " ..
		"elements always show.")
	tooltipNote:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	tooltipNote:SetPoint("RIGHT", content, "RIGHT", -16, 0)

	local hideLabel = Label(content, "GameFontNormalSmall", "When they're hidden")
	hideLabel:SetPoint("TOPLEFT", tooltipNote, "BOTTOMLEFT", 0, -14)

	local tooltip = Check(content, "fadeTooltip", "Throughout CineMode",
		"Hides world tooltips whenever CineMode is on. To hide them only in some camera " ..
		"modes, untick this and tick those modes under Hide below.")
	tooltip:SetPoint("TOPLEFT", hideLabel, "BOTTOMLEFT", -2, -6)
	tooltip:HookScript("OnClick", Refresh) -- grey out / enable the camera modes below

	local backLabel = Label(content, "GameFontNormalSmall", "Showing them again")
	backLabel:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 2, -14)

	local tooltipReveal = Check(content, "tooltipReveal", "After hovering",
		"A hidden world tooltip appears once you've kept the mouse on the same player, NPC or " ..
		"object for the time below. Applies wherever world tooltips are hidden.")
	tooltipReveal:SetPoint("TOPLEFT", backLabel, "BOTTOMLEFT", -2, -6)
	tooltipReveal:HookScript("OnClick", Refresh) -- grey out / enable the sliders

	local tooltipRevealDelay = Slider(content, "tooltipRevealDelay", "After hovering for", 0, 10, 0.5, "%.1f sec")
	tooltipRevealDelay:SetPoint("TOPLEFT", tooltipReveal, "BOTTOMLEFT", 4, -26)
	GreyUnless(tooltipRevealDelay, function(db) return db.tooltipReveal end)

	-- Tooltips that skip the wait (more may join this list).
	local exceptWhen = Label(content, "GameFontHighlight", "Except when")
	exceptWhen:SetPoint("TOPLEFT", tooltipRevealDelay, "BOTTOMLEFT", -2, -14)
	local exceptions = exceptWhen
	for i, rule in ipairs({
		{ "tooltipQuestAtOnce", "It shows a quest objective",
			"Tooltips listing one of your quest objectives (like \"5/7 Thistle Boar slain\") " ..
			"show straight away, so you can check your progress on what you're hunting." },
		{ "tooltipGatherAtOnce", "It's gatherable",
			"Herbs, ore and creatures you can skin (tooltips that say Herbalism, Mining or " ..
			"Skinnable) show straight away, so you can see what it is and whether you can gather it." },
		{ "tooltipEnemyAtOnce", "It's an enemy",
			"Players and NPCs you can attack (neutral mobs too), with their pets, minions and " ..
			"totems, show their tooltips straight away." },
		{ "tooltipFriendlyAtOnce", "It's friendly",
			"Players and NPCs you can't attack, with their pets, minions and totems, show their " ..
			"tooltips straight away." },
	}) do
		local check = Check(content, rule[1], rule[2], rule[3])
		check:SetPoint("TOPLEFT", exceptions, "BOTTOMLEFT", i == 1 and 10 or 0, i == 1 and -4 or -2)
		GreyUnless(check, function(db) return db.tooltipReveal end)
		exceptions = check
	end

	local tooltipWarm = Slider(content, "tooltipWarmTime", "Then show at once until none for", 0, 15, 0.5, "%.1f sec")
	tooltipWarm:SetPoint("TOPLEFT", exceptions, "BOTTOMLEFT", -8, -26)
	GreyUnless(tooltipWarm, function(db) return db.tooltipReveal end)
	Tooltip(tooltipWarm, "Once a tooltip has shown, the next things you hover show theirs straight " ..
		"away, until no world tooltip has been up for this long. 0 makes every one wait.")

	local tooltipFade = Slider(content, "tooltipFadeTime", "Fade in and out over", 0, 2, 0.05, "%.2f sec")
	tooltipFade:SetPoint("TOPLEFT", tooltipWarm, "BOTTOMLEFT", 0, -26)
	GreyUnless(tooltipFade, function(db) return db.tooltipReveal end)
	Tooltip(tooltipFade, "How long a tooltip takes to fade in once it's shown, and to fade out " ..
		"when you move off. 0 shows and hides it at once.")

	-- A row per camera mode: hide there (when not hidden throughout).
	local tooltipLabel = Label(content, "GameFontNormalSmall", "Or in camera modes")
	tooltipLabel:SetPoint("TOPLEFT", tooltipFade, "BOTTOMLEFT", -2, -14)
	local tooltipModes = tooltipLabel
	for i, mode in ipairs({
		{ "Flight", "On flights" },
		{ "Idle", "AFK camera (standing still or AFK)" },
		{ "Cozy", "Cozy (campfire, sitting, emotes)" },
		{ "Tele", "Tele (Hearthstone, teleports)" },
		{ "Vista", "Vista (/stare)" },
		{ "Fish", "Fish (fishing)" },
		{ "Walk", "RP walking" },
		{ "Run", "Auto-running" },
		{ "Death", "Death camera" },
		{ "Quest", "Quest camera (talking to quest givers)" },
	}) do
		local hide = Check(content, "tooltipOff" .. mode[1], mode[2],
			"Hide world tooltips while this camera is running. (Not needed while \"Throughout " ..
			"CineMode\" above hides them everywhere.)")
		hide:SetPoint("TOPLEFT", tooltipModes, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
		GreyUnless(hide, function(db) return not db.fadeTooltip end)
		tooltipModes = hide
	end

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Tooltips")
end

local function CreateExtrasPanel()
	local canvas, content = CreateScrollPage()
	extrasPanel = content

	local title = Label(content, "GameFontNormalLarge", "3rd Party Frames")
	title:SetPoint("TOPLEFT", 16, -16)

	-- (As if the title were a note, so the first heading gets a full gap below it.)
	local stack = Stack(title, "label")
	stack:Header(content, "Supported addons")
	stack:Note(content, "These addons' frames are hidden in CineMode unless ticked, like the game's " ..
		"frames on the Standard Frames page. Tick CineMode to leave an addon's frames alone (shown the " ..
		"whole time); the other columns show them only while you fight or have something targeted.", 560)

	-- The addons, laid out afresh each time the page opens (most load after
	-- this one, so whether they're loaded isn't known when it's built): those
	-- loaded, those installed but not loaded, then the rest supported. A suite's
	-- parts (suite = its name) sit under a header that opens and closes (closed
	-- to start with).
	local box = CreateFrame("Frame", nil, content)
	box:SetSize(640, 1)
	stack:Add(box, "label")

	local LABEL_WIDTH, COLUMN_WIDTH, ROW_HEIGHT, INDENT = 220, 100, 24, 18
	local COLUMNS = {
		{ "CineMode" },
		{ "In combat", ns.IsCombatShowOn, "combatShow", true },
		{ "Tar Enemy", ns.IsEnemyShowOn, "enemyShow", false },
		{ "Tar Friendly", ns.IsFriendlyShowOn, "friendlyShow", false },
	}
	local headings = {}
	for c, column in ipairs(COLUMNS) do
		local heading = Label(box, "GameFontNormalSmall", column[1])
		heading:SetWidth(COLUMN_WIDTH)
		heading:SetJustifyH("CENTER")
		headings[c] = heading
	end

	-- A row per installed addon: CineMode (ticked: left alone, so shown), then
	-- the Standard Frames page's columns. Made once, placed by Layout. (The
	-- ticks belong to the page itself, for its Reset.)
	local rows = {}
	local function MakeRow(known)
		local row = { known = known, checks = {} }
		row.label = Label(box, "GameFontHighlight", known.short or known.label)
		row.label:SetWidth(LABEL_WIDTH - INDENT)
		row.label:SetJustifyH("LEFT")
		row.label:SetWordWrap(false)
		-- In its suite's list: its name without the suite's ("Data Bars").
		if known.suite and known.label:sub(1, #known.suite + 1) == known.suite .. " " then
			row.suiteLabel = known.label:sub(#known.suite + 2)
		end
		local item = "addon:" .. known.key
		for c, column in ipairs(COLUMNS) do
			local check
			if c == 1 then
				check = Check(content, nil, "", ("Show %s the whole time in CineMode (Cinematic leaves them " ..
					"alone). Unticked, they're hidden, except as the other columns say.%s"):format(known.about,
					known.note and " " .. known.note or ""), function(value)
					ns.SetAddonFramesOn(known.key, not value)
					Refresh() -- (greys the other columns)
				end)
				check.Refresh = function(self)
					self:SetChecked(not ns.IsAddonFramesOn(known.key))
				end
			else
				local isOn, tableKey, needsStay = column[2], column[3], column[4]
				check = Check(content, tableKey, "", nil, function(value)
					ns.GetDB()[tableKey][item] = value
				end)
				check.Refresh = function(self)
					self:SetChecked(isOn(item))
					self:SetEnabled(ns.IsAddonFramesOn(known.key) and (not needsStay or ns.GetDB().stayInCombat))
				end
			end
			row.checks[c] = check
		end
		return row
	end
	for _, known in ipairs(ns.ADDON_FRAMES) do
		if ns.AddOnInstalled(known.addon) then
			rows[#rows + 1] = MakeRow(known)
		end
	end

	local sectionTitles, suiteHeaders = {}, {}
	local missingNote = Label(box, "GameFontHighlightSmall", "")
	missingNote:SetWidth(560)
	missingNote:SetJustifyH("LEFT")
	missingNote:SetJustifyV("TOP")
	local Layout

	local function SectionTitle(text)
		if not sectionTitles[text] then
			sectionTitles[text] = Label(box, "GameFontNormal", text)
		end
		return sectionTitles[text]
	end

	-- A suite's header: + or - and its name, with how many parts it has.
	local function SuiteHeader(suite)
		local header = suiteHeaders[suite]
		if not header then
			header = CreateFrame("Button", nil, box)
			header:SetSize(LABEL_WIDTH, ROW_HEIGHT)
			header.icon = header:CreateTexture(nil, "ARTWORK")
			header.icon:SetSize(14, 14)
			header.icon:SetPoint("LEFT", 0, 0)
			header.text = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			header.text:SetPoint("LEFT", header.icon, "RIGHT", 4, 0)
			header:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
			header:GetHighlightTexture():SetAllPoints(header.icon)
			header:SetScript("OnClick", function()
				local open = ns.GetDB().addonSuitesOpen
				open[suite] = not open[suite] or nil
				Layout()
				FitContentHeight(content)
			end)
			Tooltip(header, "Click to show or hide its parts.")
			suiteHeaders[suite] = header
		end
		return header
	end

	Layout = function()
		local db = ns.GetDB()
		local y = 0
		local function Place(region, x, height)
			region:ClearAllPoints()
			region:SetPoint("TOPLEFT", box, "TOPLEFT", x, -y)
			region:Show()
			y = y + height
		end
		for _, region in pairs(sectionTitles) do region:Hide() end
		for _, header in pairs(suiteHeaders) do header:Hide() end
		for _, row in ipairs(rows) do
			row.label:Hide()
			for _, check in ipairs(row.checks) do check:Hide() end
		end

		local function PlaceRow(row, indent)
			row.label:SetText(indent > 0 and row.suiteLabel or row.known.short or row.known.label)
			row.label:ClearAllPoints()
			row.label:SetPoint("TOPLEFT", box, "TOPLEFT", indent, -y - 5)
			row.label:Show()
			for c, check in ipairs(row.checks) do
				check:ClearAllPoints()
				check:SetPoint("TOPLEFT", box, "TOPLEFT",
					LABEL_WIDTH + (c - 1) * COLUMN_WIDTH + (COLUMN_WIDTH - 26) / 2, -y)
				check:Show()
			end
			y = y + ROW_HEIGHT
		end

		-- One section: its addons in the page's order, a suite's together under its header.
		local function Section(title, wanted)
			local list = {}
			for _, row in ipairs(rows) do
				if wanted(row.known) then
					list[#list + 1] = row
				end
			end
			if #list == 0 then
				return
			end
			y = y + (y > 16 and 12 or 0)
			Place(SectionTitle(title), 0, 20)
			local done = {}
			for _, row in ipairs(list) do
				local suite = row.known.suite
				if not suite then
					PlaceRow(row, 0)
				elseif not done[suite] then
					done[suite] = true
					local parts = {}
					for _, other in ipairs(list) do
						if other.known.suite == suite then
							parts[#parts + 1] = other
						end
					end
					local header = SuiteHeader(suite)
					local closed = not db.addonSuitesOpen[suite]
					header.icon:SetTexture(closed and "Interface\\Buttons\\UI-PlusButton-Up"
						or "Interface\\Buttons\\UI-MinusButton-Up")
					header.text:SetText(("%s |cff808080(%d)|r"):format(suite, #parts))
					Place(header, 0, ROW_HEIGHT)
					if not closed then
						for _, part in ipairs(parts) do
							PlaceRow(part, part.suiteLabel and INDENT or 0)
						end
					end
				end
			end
		end

		if #rows > 0 then
			for c, heading in ipairs(headings) do
				Place(heading, LABEL_WIDTH + (c - 1) * COLUMN_WIDTH, 0)
			end
			y = 16
		else
			for _, heading in ipairs(headings) do heading:Hide() end
		end
		Section("Loaded", function(known) return ns.AddOnLoaded(known.addon) end)
		Section("Installed, not loaded", function(known) return not ns.AddOnLoaded(known.addon) end)

		-- The rest supported, by name (a suite once).
		local missing, listed = {}, {}
		for _, known in ipairs(ns.ADDON_FRAMES) do
			local name = known.suite or known.label
			if not ns.AddOnInstalled(known.addon) and not listed[name] then
				listed[name] = true
				missing[#missing + 1] = name
			end
		end
		if #missing > 0 then
			y = y + (y > 0 and 12 or 0)
			Place(SectionTitle("Not installed"), 0, 20)
			missingNote:SetText("|cff808080Also supported, when installed: " .. table.concat(missing, ", ") .. "|r")
			Place(missingNote, 0, missingNote:GetStringHeight() + 4)
		else
			missingNote:Hide()
		end
		box:SetHeight(math.max(1, y))
	end

	stack:Header(content, "Custom frames")
	content.help = stack:Note(content,
		"To fade something else, hover over it and type |cffffd100/cine add|r, " ..
			"or type |cffffd100/cine add|r and its frame name. " ..
		"Stop fading one with |cffffd100Stop|r; greyed-out frames are ones you stopped, " ..
		"which |cffffd100Restore|r undoes. |cffffd100Delete|r takes a frame off the list.", 560)

	content.empty = Label(content, "GameFontDisableSmall", "None yet.")
	content.empty:SetPoint("TOPLEFT", content.help, "BOTTOMLEFT", 0, -12)

	canvas:SetScript("OnShow", PageShown(function()
		if ns.GetDB() then
			Layout()
			Refresh()
			RefreshExtras()
		end
	end, content))
	canvas:Hide()
	RegisterSubpage(canvas, "3rd Party Frames")
end

-- Sub-page: keybinds. The same bindings as Key Bindings > AddOns, with two
-- key slots each like Blizzard's page.
local KEYBINDS = {
	{ action = "CINEMATIC_HIDEUI", label = "Hide the UI",
		tip = "Like Blizzard's Alt+Z: hides the whole UI, but keeps the tint, letterbox " ..
			"and time-of-day title. Press again (or Blizzard's key) to bring it back." },
	{ action = "CINEMATIC_TOGGLE", label = "Toggle CineMode",
		tip = "Turns CineMode on or off, like /cine." },
	{ action = "CINEMATIC_PEEK", label = "Peek at the UI (hold)",
		tip = "Brings the UI back while held, and fades it again when let go." },
	{ action = "CINEMATIC_FLYBY", label = "Fly-by",
		tip = "The camera slowly turns round to look back past you, holds there, then turns " ..
			"back behind you. Press again to stop; moving the camera stops it too. Like /cine flyby." },
	{ action = "CINEMATIC_CAM_IDLE", label = "AFK camera",
		tip = "Starts the AFK camera now, without waiting out its delay. " ..
			"Press again, move or jump to stop it." },
	{ action = "CINEMATIC_CAM_COZY", label = "Cozy camera",
		tip = "Starts the cozy camera now, as if you'd sat down. Press again, move or jump to stop it." },
	{ action = "CINEMATIC_CAM_VISTA", label = "Vista camera",
		tip = "Starts the vista camera now, as if you'd done a /stare. Press again, move or jump to stop it." },
	{ action = "CINEMATIC_CAM_FISH", label = "Fish camera",
		tip = "Starts the fish camera now, without casting. Press again, move or jump to stop it." },
	{ action = "CINEMATIC_CAM_DEATH", label = "Death camera test",
		tip = "Pretends you're dead for 30 seconds so the death camera runs. Press again to stop. " ..
			"Like /cine deathtest." },
}

local IGNORED_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true,
}
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local keybindButtons = {}
local listening -- the slot button waiting for a key, if any

local function KeyText(key)
	return GetBindingText and GetBindingText(key) or key
end

local function RefreshKeybinds()
	for _, button in ipairs(keybindButtons) do
		local key = select(button.slot, GetBindingKey(button.action))
		if button == listening then
			button:SetText("Press a key")
		else
			button:SetText(key and KeyText(key) or "|cff808080Not bound|r")
		end
	end
end

local function StopListening()
	if listening then
		listening:EnableKeyboard(false)
		listening:UnlockHighlight()
		listening = nil
	end
	RefreshKeybinds()
end

-- Puts key (or nothing) in the button's slot, replacing what was there. The
-- game lists an action's keys in the order they were bound, so all of them
-- are unbound and bound again in slot order: binding just the new key would
-- add it at the end, and a key set in slot 1 would show up in slot 2. (A
-- slot with nothing before it takes the first free one.)
local function Bind(button, key)
	StopListening()
	if InCombatLockdown() then
		ns.Print("keybinds can't be changed in combat")
		return
	end
	local action = button.action
	local keys = { GetBindingKey(action) }
	if key then
		local previous = GetBindingAction(key)
		if previous and previous ~= "" and previous ~= action then
			ns.Print(KeyText(key) .. " was bound to " .. (_G["BINDING_NAME_" .. previous] or previous) ..
				" and now isn't")
		end
	end
	for _, old in ipairs(keys) do
		SetBinding(old)
	end
	local wanted = {}
	for i = 1, math.max(#keys, button.slot) do
		if i == button.slot then
			wanted[#wanted + 1] = key -- (nil when clearing: adds nothing)
		elseif keys[i] and keys[i] ~= key then -- (the key moving here from the other slot)
			wanted[#wanted + 1] = keys[i]
		end
	end
	for _, k in ipairs(wanted) do
		SetBinding(k, action)
	end
	SaveBindings(GetCurrentBindingSet())
	RefreshKeybinds()
end

local function WithModifiers(key)
	if IsShiftKeyDown() then key = "SHIFT-" .. key end
	if IsControlKeyDown() then key = "CTRL-" .. key end
	if IsAltKeyDown() then key = "ALT-" .. key end
	return key
end

local function CreateKeybindButton(parent, action, slot)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(140, 22)
	button.action, button.slot = action, slot
	button:RegisterForClicks("AnyUp")
	button:SetScript("OnClick", function(self, mouseButton)
		if self == listening and MOUSE_KEYS[mouseButton] then
			Bind(self, WithModifiers(MOUSE_KEYS[mouseButton]))
		elseif mouseButton == "RightButton" then
			Bind(self, nil)
		elseif self == listening then
			StopListening()
		else
			StopListening()
			listening = self
			self:EnableKeyboard(true)
			self:LockHighlight()
			RefreshKeybinds()
		end
	end)
	button:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			StopListening()
		elseif not IGNORED_KEYS[key] then
			Bind(self, WithModifiers(key))
		end
	end)
	-- Setting OnKeyDown turns keyboard input on, which would have every slot
	-- grab the next key pressed on this page; only the clicked one listens.
	button:EnableKeyboard(false)
	Tooltip(button, "Click, then press a key (with Shift, Ctrl or Alt if you like). " ..
		"Right-click to clear. Escape cancels.")
	keybindButtons[#keybindButtons + 1] = button
	return button
end

local function CreateKeybindsPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Keybinds")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"Keys for Cinematic. These are the same bindings as under Key Bindings > AddOns, " ..
		"so setting them in either place works.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	local previous = Header(content, "Keys", subtitle, -20)
	for i, bind in ipairs(KEYBINDS) do
		local label = Label(content, "GameFontHighlight", bind.label)
		label:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -14 or -18)
		label:SetWidth(200)
		local first = CreateKeybindButton(content, bind.action, 1)
		first:SetPoint("LEFT", label, "RIGHT", 10, 0)
		local second = CreateKeybindButton(content, bind.action, 2)
		second:SetPoint("LEFT", first, "RIGHT", 8, 0)
		local note = Label(content, "GameFontDisableSmall", bind.tip)
		note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
		note:SetPoint("RIGHT", content, "RIGHT", -16, 0)
		note:SetJustifyV("TOP")
		previous = note
	end

	canvas:RegisterEvent("UPDATE_BINDINGS")
	canvas:SetScript("OnEvent", RefreshKeybinds)
	canvas:SetScript("OnShow", PageShown(RefreshKeybinds, content))
	canvas:SetScript("OnHide", StopListening)
	canvas:Hide()
	RegisterSubpage(canvas, "Keybinds")
end

-- The settings window can't open in combat (the game blocks it, "Interface
-- action failed because of an AddOn"): just say so.
function ns.OpenOptions()
	if InCombatLockdown() then
		ns.Print("settings can't be opened in combat")
		return
	end
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		-- Called twice: the first call can land on the wrong page in old clients.
		InterfaceOptionsFrame_OpenToCategory(mainCanvas)
		InterfaceOptionsFrame_OpenToCategory(mainCanvas)
	end
end

CreatePanel()
-- Sub-pages in the order they're listed: what fades and shows, then the look
-- and sound, then the camera modes (their shared page and events first),
-- keybinds. (Standard Frames and 3rd Party Frames come right after CineMode.)
CreateRevealPanel()
CreateCombatPanel()
CreateExtrasPanel()
CreateMinimapPanel()
CreateQuestTrackerPanel()
-- World tooltips always show for now (see ns.WORLD_TOOLTIP_HIDING): no page.
if ns.WORLD_TOOLTIP_HIDING then
	CreateTooltipPanel()
end
CreateBuffsPanel()
CreatePlatesPanel()
CreateChatPanel()
CreateTintPanel()
CreateAudioPanel()
CreateCameraPanel()
CreateEventsPanel()
-- Each camera mode's own page: hidden for now (too many pages for settings few
-- players change); their settings keep their defaults. True brings them back.
local SHOW_CAMERA_MODE_PAGES = false
if SHOW_CAMERA_MODE_PAGES then
	CreateFlightPanel()
	CreateStandingPanel()
	CreateCozyPanel()
	CreateTelePanel()
	CreateVistaPanel()
	CreateFishPanel()
	CreateWalkPanel()
	CreateAutoRunPanel()
	CreateDeathPanel()
	CreateQuestPanel()
end
CreateKeybindsPanel()
