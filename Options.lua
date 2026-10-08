-- Cinematic settings: a panel under Options > AddOns, also opened with /cine config
local _, ns = ...

-- Each page is a canvas (registered with the Settings panel) holding a scroll
-- frame; the panel/cameraPanel/extrasPanel variables are the scrolling content
-- that the widgets are built on.
local panel, category, extrasPanel, cameraPanel, keepPanel, chatPanel
local mainCanvas
local controls = {}   -- widgets that mirror a db key, refreshed on show
local extraRows = {}
local MAX_EXTRA_ROWS = 18
local sliderCount = 0

local function Tooltip(widget, tip)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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
	return cb
end

-- A labelled slider. `scale` converts between stored and shown values
-- (letterbox size is stored as a fraction but shown as a percent).
local function Slider(parent, key, label, minV, maxV, step, fmt, scale, onChange)
	scale = scale or 1
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

local function RefreshExtras()
	local faded, ignored = ns.GetExtraFrames()
	local items = {}
	for _, name in ipairs(faded) do items[#items + 1] = { name = name, faded = true } end
	for _, name in ipairs(ignored) do items[#items + 1] = { name = name, faded = false } end

	for i, row in ipairs(extraRows) do
		local item = items[i]
		row:SetShown(item ~= nil)
		if item then
			row.item = item
			row.text:SetText(item.faded and item.name or ("|cff808080" .. item.name .. "|r"))
			row.button:SetText(item.faded and "Stop" or "Restore")
		end
	end

	local empty = extrasPanel.empty
	local shown = math.min(#items, MAX_EXTRA_ROWS)
	empty:ClearAllPoints()
	if shown == 0 then
		empty:SetPoint("TOPLEFT", extrasPanel.help, "BOTTOMLEFT", 0, -12)
	else
		empty:SetPoint("TOPLEFT", extraRows[shown], "BOTTOMLEFT", 0, -6)
	end

	local hidden = #items - MAX_EXTRA_ROWS
	if #items == 0 then
		empty:SetText("None yet.")
	elseif hidden > 0 then
		empty:SetText(("...and %d more (see /cine list)"):format(hidden))
	else
		empty:SetText("")
	end
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
	return dropdown
end

local function CreateExtraRow(parent, anchor, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(300, 22)
	row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10 - (index - 1) * 24)

	row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.button:SetSize(70, 20)
	row.button:SetPoint("LEFT")
	row.button:SetScript("OnClick", function()
		if not row.item then
			return
		end
		if row.item.faded then
			ns.StopFading(row.item.name)
		else
			ns.UnignoreFrame(row.item.name)
		end
		RefreshExtras()
	end)

	row.text = Label(row, "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row.button, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT")
	row.text:SetWordWrap(false)
	row:Hide()
	return row
end

local SCROLLBAR_WIDTH = 26

local function CreateScrollPage()
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
	mainCanvas, panel = CreateScrollPage()
	mainCanvas.name = "Cinematic"

	local title = Label(panel, "GameFontNormalLarge", "Cinematic")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(panel, "GameFontHighlightSmall",
		"Fades the UI and adds letterbox bars between fights. Combat, casting " ..
		"and opening windows like the spellbook bring it back. Typing just shows the chat. The " ..
		"pages under this one cover what shows when (Showing the UI, Frames, Combat, Nameplates, " ..
		"Chat), the look and sound, the camera modes (a page each) and keybinds.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Left column: general
	local general = Header(panel, "General", subtitle, -20)

	local enabled = Check(panel, "enabled", "Enable cinematic mode",
		"Also toggled with /cine or the keybind under Key Bindings > AddOns.", ns.SetEnabled)
	enabled:SetPoint("TOPLEFT", general, "BOTTOMLEFT", -2, -6)

	local startCinematic = Check(panel, "startCinematic", "Start in cinematic mode",
		"When you log in, /reload or turn cinematic mode on, the UI hides straight away and the " ..
		"letterbox slides in, instead of waiting for the fade delay.")
	startCinematic:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -2)

	local minimapButton = Check(panel, "minimapButton", "Show minimap button",
		"Left-click it for quick options (turn off for a while, combat, tint), right-click for " ..
		"these settings, drag to move it.", function(value)
			ns.GetDB().minimapButton = value
			if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
		end)
	minimapButton:SetPoint("TOPLEFT", startCinematic, "BOTTOMLEFT", 0, -2)

	-- Right column: places
	local placesHeader = Label(panel, "GameFontNormal", "Turn off in")
	placesHeader:SetPoint("TOPLEFT", general, "TOPLEFT", 320, 0)

	-- Stored the other way round (stayInCombat), as the Combat page's lists apply while staying.
	local combat = Check(panel, "stayInCombat", "Combat",
		"Being in combat brings the UI back. Targeting an enemy only shows the frames chosen " ..
		"for it on the Combat page. Untick to stay cinematic in combat too.", function(value)
			ns.GetDB().stayInCombat = not value
			Refresh()
		end)
	combat.Refresh = function(self) self:SetChecked(not ns.GetDB().stayInCombat) end
	combat:SetPoint("TOPLEFT", placesHeader, "BOTTOMLEFT", -2, -6)

	-- Places in the same order as every other place list (PlaceList).
	local cities = Check(panel, "offInCities", "Cities",
		"Capital cities, including Dalaran. Flights leaving a city still go cinematic.")
	cities:SetPoint("TOPLEFT", combat, "BOTTOMLEFT", 0, -2)

	local inns = Check(panel, "offInInns", "Inns",
		"Resting anywhere outside a capital city, such as a town inn.")
	inns:SetPoint("TOPLEFT", cities, "BOTTOMLEFT", 0, -2)

	local dungeons = Check(panel, "offInDungeons", "Dungeons",
		"Keep the normal UI in dungeons and scenarios.")
	dungeons:SetPoint("TOPLEFT", inns, "BOTTOMLEFT", 0, -2)

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

	local title = Label(content, "GameFontNormalLarge", "Showing the UI")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"How fast the UI fades, what brings it (or parts of it) back while cinematic mode " ..
		"is on, and combat text and tooltips in the world. Fights and targeting are on the Combat " ..
		"page, names and nameplates on the Nameplates page, chat on the Chat page.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	local OVERRIDE_COLUMN, OVERRIDE_ROW = 300, 28

	-- Fading (full width): how fast the UI goes and comes back
	local fadingHeader = Header(content, "Fading", subtitle, -20)

	local delay = Slider(content, "delay", "Fade delay", 0, 30, 0.5, "%.1f sec")
	delay:SetPoint("TOPLEFT", fadingHeader, "BOTTOMLEFT", 2, -26)
	Tooltip(delay, "How long things must stay calm before the UI fades out.")

	local fadeOut = Slider(content, "fadeOutTime", "Fade out time", 0.1, 5, 0.1, "%.1f sec")
	fadeOut:SetPoint("LEFT", delay, "LEFT", OVERRIDE_COLUMN, 0)
	Tooltip(fadeOut, "How long the UI takes to fade out. The mouseover times below include it: " ..
		"a time shorter than the fade just fades straight away.")

	local fadeIn = Slider(content, "fadeInTime", "Fade in time", 0, 10, 0.05, "%.2f sec")
	fadeIn:SetPoint("TOPLEFT", delay, "BOTTOMLEFT", 0, -34)

	-- Mouseover (full width): the shared hold time, and per-group overrides
	local mouseHeader = Header(content, "Mouseover", fadeIn, -24)
	mouseHeader:SetPoint("TOPLEFT", fadeIn, "BOTTOMLEFT", -2, -24)

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

	-- Left column: what brings the UI back, portrait and buffs
	local revealHeader = Header(content, "Bring the UI back", lastOverride, -18)
	revealHeader:SetPoint("TOPLEFT", lastOverride, "BOTTOMLEFT", 2, -18)

	local cast = Check(content, "revealOnCast", "While casting",
		"Includes mounting and hearthstone casts.")
	cast:SetPoint("TOPLEFT", revealHeader, "BOTTOMLEFT", -2, -6)

	local npcs = Check(content, "revealAtNPCs", "At vendors, banks, mail and trainers",
		"Bring the UI back while a vendor, bank, mailbox, class trainer, trade or auction " ..
		"house window is open. When off, the window still shows but the rest stays hidden.")
	npcs:SetPoint("TOPLEFT", cast, "BOTTOMLEFT", 0, -2)

	local windows = Check(content, "stayWithWindows", "Stay in cinematic mode when opening windows",
		"Opening the spellbook, character sheet, talents, macros, key bindings or these " ..
		"options doesn't bring the UI back. The window itself still shows.")
	windows:SetPoint("TOPLEFT", npcs, "BOTTOMLEFT", 0, -2)

	local drag = Check(content, "revealOnDrag", "While dragging something",
		"Picking up an item or spell (to drag it to your action bars, say) brings the UI back " ..
		"until you put it down. Off: picking things up never does; mouse over a faded bar to " ..
		"see it when dragging there.")
	drag:SetPoint("TOPLEFT", windows, "BOTTOMLEFT", 0, -2)

	local yoursHeader = Header(content, "Your portrait and buffs", drag, -18)
	yoursHeader:SetPoint("TOPLEFT", drag, "BOTTOMLEFT", 2, -18)

	local portrait = Check(content, "portraitWhenNotFull", "Show your portrait until health and power are full",
		"Keeps your player portrait up while you're recovering. Rage and runic power count " ..
		"as full when empty, so a warrior's portrait hides once their rage has drained.")
	portrait:SetPoint("TOPLEFT", yoursHeader, "BOTTOMLEFT", -2, -6)
	portrait:HookScript("OnClick", Refresh) -- grey out / enable the options below

	-- Children: only apply the rule shortly after combat
	local PORTRAIT_INDENT = 16
	local function IfPortrait(db) return db.portraitWhenNotFull end

	local afterCombat = Check(content, "portraitAfterCombat", "Only after combat",
		"Only keep the portrait up if you've been in combat recently, so things like " ..
		"fall damage or casting a buff in town don't bring it up.")
	afterCombat:SetPoint("TOPLEFT", portrait, "BOTTOMLEFT", PORTRAIT_INDENT, -2)
	GreyUnless(afterCombat, IfPortrait)

	local combatWindow = Slider(content, "portraitCombatWindow", "Within", 10, 300, 10, "%d sec of a fight")
	combatWindow:SetPoint("TOPLEFT", afterCombat, "BOTTOMLEFT", 4, -26)
	GreyUnless(combatWindow, IfPortrait)

	local buffPeek = Check(content, "buffPeek", "Show buffs when you gain or refresh one",
		"A new buff or debuff, or one being refreshed, briefly shows your buffs and " ..
		"debuffs. Buffs falling off don't count, and neither do flights.")
	buffPeek:SetPoint("TOPLEFT", combatWindow, "BOTTOMLEFT", -4 - PORTRAIT_INDENT, -18)
	buffPeek:HookScript("OnClick", Refresh) -- grey out / enable the options below

	local function IfBuffPeek(db) return db.buffPeek end

	local buffAfterCombat = Check(content, "buffPeekAfterCombat", "Only after combat",
		"Only show your buffs if you've been in combat recently, so buffing up or " ..
		"picking up a buff in town doesn't bring them up.")
	buffAfterCombat:SetPoint("TOPLEFT", buffPeek, "BOTTOMLEFT", PORTRAIT_INDENT, -2)
	GreyUnless(buffAfterCombat, IfBuffPeek)

	local buffCombatWindow = Slider(content, "buffPeekCombatWindow", "Within", 10, 300, 10, "%d sec of a fight")
	buffCombatWindow:SetPoint("TOPLEFT", buffAfterCombat, "BOTTOMLEFT", 4, -26)
	GreyUnless(buffCombatWindow, IfBuffPeek)

	local buffPeekTime = Slider(content, "buffPeekTime", "Show buffs for", 0.5, 30, 0.5, "%.1f sec")
	buffPeekTime:SetPoint("TOPLEFT", buffCombatWindow, "BOTTOMLEFT", -PORTRAIT_INDENT, -26)

	local ignoreLabel = Label(content, "GameFontHighlightSmall", "Except for these buffs and debuffs (spell IDs or names):")
	ignoreLabel:SetPoint("TOPLEFT", buffPeekTime, "BOTTOMLEFT", -2, -22)
	local ignoreBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	ignoreBox:SetSize(270, 20)
	ignoreBox:SetAutoFocus(false)
	ignoreBox:SetPoint("TOPLEFT", ignoreLabel, "BOTTOMLEFT", 6, -4)
	local function SaveIgnore(self) ns.GetDB().buffPeekIgnore = self:GetText() end
	ignoreBox:SetScript("OnEnterPressed", function(self) SaveIgnore(self) self:ClearFocus() end)
	ignoreBox:SetScript("OnEditFocusLost", SaveIgnore)
	ignoreBox:SetScript("OnEscapePressed", function(self)
		self:SetText(ns.GetDB().buffPeekIgnore or "")
		self:ClearFocus()
	end)
	ignoreBox.Refresh = function(self)
		local db = ns.GetDB()
		if not self:HasFocus() then self:SetText(db.buffPeekIgnore or "") end
		self:SetEnabled(db.buffPeek)
	end
	controls[#controls + 1] = ignoreBox
	Tooltip(ignoreBox, "Gaining or stacking these doesn't bring your buffs up. Separate with commas. " ..
		"Names must match your game language; spell IDs work in any language (2479 is " ..
		"Honorless Target, 8326 and 20584 are Ghost).")

	-- Right column: combat text and world tooltips. World tooltips hide
	-- throughout cinematic mode or only in the camera modes ticked here, and can
	-- come back after hovering.
	local worldHeader = Label(content, "GameFontNormal", "In the world")
	worldHeader:SetPoint("TOPLEFT", revealHeader, "TOPLEFT", 320, 0)

	local combatText = Check(content, "hideCombatText", "Hide combat text out of combat",
		"No floating damage and healing numbers (like \"+10\" from a heal or regen) in cinematic " ..
		"mode while you're out of combat. They come back the moment a fight starts, and your " ..
		"combat text settings are put back when the UI returns.")
	combatText:SetPoint("TOPLEFT", worldHeader, "BOTTOMLEFT", -2, -6)

	local tooltip = Check(content, "fadeTooltip", "Hide world tooltips",
		"Hides the tooltip for players, NPCs and objects you mouse over in the world, throughout " ..
		"cinematic mode. Tooltips for UI elements still show. To hide them only in some camera " ..
		"modes, untick this and tick the modes below.")
	tooltip:SetPoint("TOPLEFT", combatText, "BOTTOMLEFT", 0, -2)
	tooltip:HookScript("OnClick", Refresh) -- grey out / enable the camera modes below

	local tooltipLabel = Label(content, "GameFontHighlight", "Or only in these camera modes")
	tooltipLabel:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 2, -8)
	local tooltipModes = tooltipLabel
	for i, mode in ipairs({
		{ "tooltipOffFlight", "On flights" },
		{ "tooltipOffIdle", "AFK camera (standing still or AFK)" },
		{ "tooltipOffCozy", "Cozy (campfire, sitting, emotes)" },
		{ "tooltipOffVista", "Vista (/stare)" },
		{ "tooltipOffFish", "Fish (fishing)" },
		{ "tooltipOffWalk", "RP walking" },
		{ "tooltipOffRun", "Auto-running" },
	}) do
		local check = Check(content, mode[1], mode[2],
			"No tooltip for players, NPCs and objects you mouse over in the world while this camera " ..
			"is running. Tooltips for UI elements still show. (Not needed while \"Hide world " ..
			"tooltips\" above hides them throughout cinematic mode.)")
		check:SetPoint("TOPLEFT", tooltipModes, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -4 or -2)
		GreyUnless(check, function(db) return not db.fadeTooltip end)
		tooltipModes = check
	end

	local tooltipReveal = Check(content, "tooltipReveal", "Show world tooltips after hovering",
		"A hidden world tooltip appears once you've kept the mouse on the same player, NPC or " ..
		"object for the time below. Applies wherever world tooltips are hidden: throughout " ..
		"cinematic mode, or in the camera modes ticked above.")
	tooltipReveal:SetPoint("TOPLEFT", tooltipModes, "BOTTOMLEFT", 0, -10)
	tooltipReveal:HookScript("OnClick", Refresh) -- grey out / enable the sliders

	local tooltipRevealDelay = Slider(content, "tooltipRevealDelay", "After hovering for", 0, 10, 0.5, "%.1f sec")
	tooltipRevealDelay:SetPoint("TOPLEFT", tooltipReveal, "BOTTOMLEFT", 4, -26)
	GreyUnless(tooltipRevealDelay, function(db) return db.tooltipReveal end)

	local tooltipFade = Slider(content, "tooltipFadeTime", "Fade in and out over", 0, 2, 0.05, "%.2f sec")
	tooltipFade:SetPoint("TOPLEFT", tooltipRevealDelay, "BOTTOMLEFT", 0, -26)
	GreyUnless(tooltipFade, function(db) return db.tooltipReveal end)
	Tooltip(tooltipFade, "How long a tooltip takes to fade in once it's shown, and to fade out " ..
		"when you move off. 0 shows and hides it at once.")

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Showing the UI")
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

	local title = Label(cameraPanel, "GameFontNormalLarge", "Camera modes")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(cameraPanel, "GameFontHighlightSmall",
		"While cinematic mode is on, the camera comes alive in seven situations, each with its " ..
		"own page: Flight (on flight paths), AFK (once you've stood still a while, or go AFK), " ..
		"Cozy (campfires and emotes), Vista (/stare), Fish (fishing), RP Walk (moving in walk " ..
		"mode) and Auto-run. Death Cam turns round your body when you die, and Quest Cam swings " ..
		"behind you at quest givers. The Events page picks which camera each emote or event " ..
		"starts. Everything goes back to normal when the UI returns. The settings here apply to " ..
		"all of them.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", cameraPanel, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	local sharedHeader = Header(cameraPanel, "All camera modes", subtitle, -20)

	local npcPause = Check(cameraPanel, "cameraPauseAtNPCs", "Pause while talking to NPCs",
		"While an auction house, vendor, bank, mailbox, trainer, quest giver or flight map window " ..
		"is open, the AFK and cozy cameras don't start (and stop if they're running). " ..
		"The AFK camera timer starts again once you close it.")
	npcPause:SetPoint("TOPLEFT", sharedHeader, "BOTTOMLEFT", -2, -6)

	local castPause = Check(cameraPanel, "cameraPauseCasting", "Pause while casting",
		"While you cast or channel (crafting, say), the AFK camera doesn't start, or " ..
		"stops if it's running. Its timer starts again once you finish. The cozy camera keeps " ..
		"going, so cooking at a campfire still feels cozy.")
	castPause:SetPoint("TOPLEFT", npcPause, "BOTTOMLEFT", 0, -2)

	local menuPause = Check(cameraPanel, "cameraPauseInMenus", "Pause while menus are open",
		"While the game menu, options, spellbook, talents, character sheet, map or another " ..
		"game window is open, the AFK and cozy cameras don't start (and stop if they're " ..
		"running). The AFK camera timer starts again once you close it.")
	menuPause:SetPoint("TOPLEFT", castPause, "BOTTOMLEFT", 0, -2)

	local depthOfField = Check(cameraPanel, "depthOfField", "Depth of field",
		"A soft haze around the edges of the screen, as if the camera had focused on you. " ..
		"Each camera mode's page sets how strong it is there (0% leaves it off). Off here: " ..
		"no haze in any of them. /cine doftest shows it on demand.")
	depthOfField:SetPoint("TOPLEFT", menuPause, "BOTTOMLEFT", 0, -2)

	local holdNote = Label(cameraPanel, "GameFontHighlightSmall",
		"In the camera modes, the minimap and quest tracker hover holds and the buff and chat " ..
		"peeks use their short default times, so they clear the view quickly. Each mode's page " ..
		"sets its own pause after you move the camera.")
	holdNote:SetPoint("TOPLEFT", depthOfField, "BOTTOMLEFT", 4, -10)
	holdNote:SetWidth(520)
	holdNote:SetJustifyV("TOP")

	-- Indoors
	local indoorHeader = Header(cameraPanel, "Indoors", holdNote, -24)
	indoorHeader:SetPoint("TOPLEFT", holdNote, "BOTTOMLEFT", -2, -24)
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
	RegisterSubpage(cameraCanvas, "Camera modes")
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
	{ "Cities", "Cities" }, { "Inns", "Inns" }, { "Dungeons", "Dungeons" },
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

-- Each camera's "play a fresh song" switch: its key, its page's name and when
-- the song starts. Shown on the camera's own page and the Audio page.
local MUSIC_CAMS = {
	{ "musicCamFlight", "Flight Cam", "as the camera starts rotating on a flight (at takeoff if " ..
		"flight rotation is off). Once per flight. Not while music is muted on flights." },
	{ "musicCamIdle", "AFK Cam", "as the AFK camera starts rotating. Once each time you stand " ..
		"still (not again after you move the camera)." },
	{ "musicCamCozy", "Cozy Cam", "as the cozy camera starts (campfire, sitting, dancing...). " ..
		"Getting up for less than 20 seconds and settling back down counts as the same spell." },
	{ "musicCamVista", "Vista Cam", "as the vista camera starts (/stare). Moving off for less " ..
		"than 20 seconds and starting again counts as the same spell." },
	{ "musicCamFish", "Fish Cam", "as the fish camera starts (casting Fishing). Moving off for " ..
		"less than 20 seconds and casting again counts as the same spell." },
	{ "musicCamWalk", "RP Walk Cam", "as you set off walking (walk/run key). Pausing for less " ..
		"than 20 seconds and walking on counts as the same walk." },
	{ "musicCamRun", "Auto-run Cam", "as you start auto-running. Stopping for less than 20 " ..
		"seconds and running on counts as the same run." },
}

local function MusicCamTip(key)
	for _, item in ipairs(MUSIC_CAMS) do
		if item[1] == key then
			return "A fresh song starts " .. item[3] .. " It plays even if music played recently " ..
				"(see Fatigue on the Audio page). Not when you switch straight over from another " ..
				"camera mode: the song playing carries on. Off: this camera leaves the music as it " ..
				"is. Needs \"Play music in cinematic mode\" on the Audio page."
		end
	end
end

-- Every camera mode's page is laid out the same way:
--   Starting (full width): opts.top's own section first if any (the fish
--     camera's casting), then starting cinematic mode straight away, the
--     mode's own starting options (opts.start), the wait after combat and the
--     pause after you move the camera.
--   Left column: Rotation (and opts.rotationExtras), then the mode's own
--     sections (opts.extras: Height, Turning, Fly-bys, Landing).
--   Right column: Zoom (and opts.zoomExtras), Depth of field, Music.
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
		stack:Add(Check(content, opts.instantKey, "Start cinematic mode as soon as you " .. opts.instantWhen,
			"Skips the fade delay, so the UI fades and the camera starts moving straight away."), "check")
	end
	if opts.start then
		opts.start(content, stack)
	end
	local combatWait = stack:Add(Slider(content, opts.combatWaitKey, "Wait after combat", 0, 120, 5,
		function(value) return value == 0 and "Off" or ("%d sec"):format(value) end), "slider")
	Tooltip(combatWait, "After a fight, this camera holds off this long before starting (its " ..
		"rotation and zoom both). Off starts it as soon as the fight is over.")
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

	-- Right column: zoom, depth of field, music
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
		"Needs \"Depth of field\" on the Camera modes page.")
	GreyUnless(dof, function(db) return db.depthOfField end)

	right:Header(content, "Music")
	local music = right:Add(Check(content, opts.musicKey, "Play a fresh song as it starts",
		MusicCamTip(opts.musicKey)), "check")
	DependsOnMusic(music)
	right:Note(content, "Fatigue, muting and ambience are on the Audio page.")

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
			"new facing, easing in and out. Steering with the mouse hands the camera straight " ..
			"back to you."), "check")
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

-- A number of seconds in a small edit box (saved as you leave it). Empty or 0
-- saves nil.
local function SecondsBox(parent, key, tip)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(40, 20)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(3)
	-- Empty saves 0 rather than nil, so a delay with a default can still be cleared.
	local function Shown()
		local value = tonumber(ns.GetDB()[key])
		return (value and value > 0) and value or ""
	end
	local function Save(self)
		local value = tonumber(self:GetText())
		ns.GetDB()[key] = (value and value > 0) and value or 0
		self:SetText(Shown())
	end
	box:SetScript("OnEnterPressed", function(self) Save(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusLost", Save)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(Shown())
		self:ClearFocus()
	end)
	box.Refresh = function(self)
		if not self:HasFocus() then self:SetText(Shown()) end
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
local EVENT_TIPS = {
	Campfire = "Standing or sitting still with any of the buffs listed below (like Welcoming Campfire).",
	Sit = "Doing the emote (or pressing the sit key). Moving, jumping or another emote ends it.",
	Sleep = "Doing the emote. Moving, jumping or another emote ends it.",
	Dance = "Doing the emote. Moving, jumping or another emote ends it.",
	Kneel = "Doing the emote. Moving, jumping or another emote ends it.",
	Chair = "Right-clicking a seat to sit on it; standing up ends it. Seats are recognised by name, " ..
		"using the words below.",
	Weapon = "Unsheathing your weapon out of combat, for a \"hero shot\". Putting it away, running or " ..
		"combat ends it. With the cozy camera it carries on while you RP walk (the camera swings " ..
		"round in front as you walk, even with Stop on move).",
	Stare = "Doing the emote while standing still. Moving, jumping or another emote ends it.",
	Fishing = "Casting Fishing. It carries on after the cast ends (looting, casting again) until " ..
		"you move or jump. The cast doesn't bring the UI back or pause the camera.",
	AFK = "Being flagged AFK (/afk, or away long enough). With \"No camera\", the AFK camera still " ..
		"starts once you've stood still for its delay.",
	Flight = "Taking off on a flight path. The flight camera is set on the Flight Cam page. With a " ..
		"delay, the camera and the UI fade wait that long into the flight. With \"No camera\", the " ..
		"camera is left to you for the whole flight.",
	Quest = "Talking to a quest giver (a quest to pick up or hand in). The quest camera is set on " ..
		"the Quest Cam page. With a delay, it waits that long into the conversation. Works whether " ..
		"or not cinematic mode is on.",
}
local function CreateEventsPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Events")
	title:SetPoint("TOPLEFT", 16, -16)
	local subtitle = Label(content, "GameFontHighlightSmall",
		"What starts the AFK, cozy, vista and fish cameras. Pick a camera for each event; the latest " ..
		"emote wins, then a drawn weapon, a campfire and going AFK. Taking a flight has the flight " ..
		"camera, and talking to a quest giver the quest camera. How each camera moves is set on its " ..
		"own page. RP walk, auto-run and death start by themselves.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	local CAMERA_X, DELAY_X, STOP_X = 250, 415, 500
	local header = Header(content, "Event", subtitle, -20)
	local cameraHeader = Label(content, "GameFontNormal", "Camera")
	cameraHeader:SetPoint("LEFT", header, "LEFT", CAMERA_X, 0)
	local delayHeader = Label(content, "GameFontNormal", "Wait (sec)")
	delayHeader:SetPoint("LEFT", header, "LEFT", DELAY_X, 0)
	local delayTip = "How long the event has to last before its camera starts and the UI fades. " ..
		"Leave it empty to start right away. Moving, jumping or another emote starts the wait over."
	local stopHeader = Label(content, "GameFontNormal", "Stop on move")
	stopHeader:SetPoint("LEFT", header, "LEFT", STOP_X, 0)
	local stopTip = "Moving or jumping ends the camera until the event starts afresh (the weapon " ..
		"drawn again, the buff gained again, AFK again). Off: the camera waits while you move and " ..
		"carries on once you stand still. Emotes and seats always end when you move or jump."

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
			or EVENT_CAMERAS
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

		local delay = SecondsBox(content, key .. "Delay", delayTip)
		delay:SetPoint("LEFT", label, "LEFT", DELAY_X + 12, 0)
		GreyUnless(delay, function(db) return db[key .. "Camera"] ~= "none" end)
		if event.stopsOnMove then
			local stop = Check(content, key .. "StopOnMove", "", stopTip)
			stop:SetPoint("LEFT", label, "LEFT", STOP_X + 26, 0)
			GreyUnless(stop, function(db) return db[key .. "Camera"] ~= "none" end)
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
		"An event set to the AFK camera starts it without waiting out the AFK camera's own delay. " ..
		"A camera whose rotation and zoom are both off on its own page shows nothing.")
	note:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", dx, -28)
	note:SetWidth(520)
	note:SetJustifyV("TOP")

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Events")
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
		combatWaitKey = "taxiCombatWait", inputPauseKey = "taxiInputPause",
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
		zoomPrefix = "taxiZoom", dofKey = "dofFlight", musicKey = "musicCamFlight",
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
				"set to the AFK camera on the Events page, like going AFK, skips the wait). Also " ..
				"used by the other options that mention standing still (tint, tracking, music, " ..
				"tooltips).")
		end,
		combatWaitKey = "idleCombatWait", inputPauseKey = "idleInputPause",
		orbitPrefix = "idleOrbit", style = "sweep",
		rotateLabel = "Sweep round you",
		rotateTip = "The camera sweeps around your character, pausing between sweeps. Moving or " ..
			"dragging the camera stops it.",
		rotationExtras = function(content, stack)
			PlaceList(content, stack, "Turn rotation off in", "rotOffIn", "No AFK camera rotation here.")
		end,
		zoomPrefix = "idleZoom",
		zoomExtras = function(content, stack)
			PlaceList(content, stack, "Turn zoom off in", "zoomOffIn", "No AFK camera zoom here.")
		end,
		dofKey = "dofIdle", musicKey = "musicCamIdle",
	})
end

local function CreateAutoRunPanel()
	CreateCameraModePanel({
		name = "Auto-run Cam",
		description = "While you're auto-running (the auto-run key). Pressing forward or back, or " ..
			"stopping, ends it; stop and stand, and the AFK camera takes over. Auto-" ..
			"walking counts as RP walk instead.",
		instantKey = "runInstant", instantWhen = "auto-run",
		combatWaitKey = "runCombatWait", inputPauseKey = "runInputPause",
		orbitPrefix = "runOrbit", style = "back",
		rotateLabel = "Sway behind you",
		rotateTip = "The camera swings gently from side to side behind your character, pausing " ..
			"between moves.",
		extras = TurningExtras("runSwingBehind", "runGlideDelay"),
		zoomPrefix = "runZoom",
		zoomTip = "The camera eases out a little, then drifts in and out around your own distance. " ..
			"When you stop it glides back.",
		dofKey = "dofRun", musicKey = "musicCamRun",
	})
end

local function CreateCozyPanel()
	CreateCameraModePanel({
		name = "Cozy Cam",
		description = "Resting at a campfire, sitting, sleeping, dancing and the like (whichever " ..
			"events pick it on the Events page): the camera swings slowly round to face you, then " ..
			"sways gently from side to side in front of you, and eases in close. Moving (or standing " ..
			"up) ends it.",
		combatWaitKey = "cozyCombatWait", inputPauseKey = "cozyInputPause",
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
		dofKey = "dofCozy", musicKey = "musicCamCozy",
	})
end

local function CreateVistaPanel()
	CreateCameraModePanel({
		name = "Vista Cam",
		description = "Stop and /stare out at the view (or any event set to it on the Events page): " ..
			"the camera glides round behind you and sways very gently there, looking out the way " ..
			"you're facing. Like the RP walk camera, only slower and softer. Moving, jumping or " ..
			"another emote ends it.",
		combatWaitKey = "vistaCombatWait", inputPauseKey = "vistaInputPause",
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
		dofKey = "dofVista", musicKey = "musicCamVista",
	})
end

local function CreateFishPanel()
	CreateCameraModePanel({
		name = "Fish Cam",
		description = "Cast Fishing (or any event set to it on the Events page): the vista camera, " ..
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
		combatWaitKey = "fishCombatWait", inputPauseKey = "fishInputPause",
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
		dofKey = "dofFish", musicKey = "musicCamFish",
	})
end

local function CreateWalkPanel()
	CreateCameraModePanel({
		name = "RP Walk Cam",
		description = "While you're moving in walk mode (walk/run key). Stop and stand, and the " ..
			"AFK camera takes over after its delay. Walking is recognised from your " ..
			"speed; /cine walk shows what the addon thinks.",
		instantKey = "walkInstant", instantWhen = "walk",
		combatWaitKey = "walkCombatWait", inputPauseKey = "walkInputPause",
		inputPauseTip = "Keep it short, so it's back in time if you need to steer.",
		orbitPrefix = "walkOrbit", style = "back",
		rotateLabel = "Sway behind you",
		rotateTip = "The camera swings gently from side to side behind your character, pausing " ..
			"between moves.",
		extras = TurningExtras("walkSwingBehind", "walkGlideDelay"),
		zoomPrefix = "walkZoom",
		zoomTip = "The camera eases out a little, then drifts in and out around your own distance. " ..
			"When you stop walking it glides back.",
		dofKey = "dofWalk", musicKey = "musicCamWalk",
	})
end

-- Not a CreateCameraModePanel page (no sway, zoom profile or music switch of
-- its own), but laid out the same way.
local function CreateDeathPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Death Cam")
	title:SetPoint("TOPLEFT", 16, -16)
	local subtitle = Label(content, "GameFontHighlightSmall", "When you die, the camera turns " ..
		"slowly round your body until you release or are resurrected. Cinematic mode stays on " ..
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
	for _, check in ipairs(PlaceList(content, stack, "Turn off in", "deathOffIn",
		"No death camera here: dying brings the UI back as usual.")) do
		GreyUnless(check, IfOn)
	end

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
		"whether or not cinematic mode is on. The \"Talk to a quest giver\" event on the Events " ..
		"page can also turn it off or make it wait a moment.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")
	local function IfOn(db) return db.eventQuestCamera ~= "none" end

	local stack = Stack(subtitle, "label")
	stack:Header(content, "Starting")
	local on = stack:Add(Check(content, "eventQuestCamera", "Use the quest camera",
		"Same as setting the \"Talk to a quest giver\" event to the quest camera (on) or no " ..
		"camera (off) on the Events page.",
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
		"what's around you, so it can't pick the open side.)"
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
	local zoomOutTime = right:Add(Slider(content, "questCamZoomOutTime", "Zoom back out takes", 1.5, 6, 0.5, "%.1f sec"), "slider")
	Tooltip(zoomOutTime, "Leaving the quest giver, the camera zooms back out to your own distance " ..
		"this quickly (turning back behind you and tilting back up as it goes).")
	GreyUnless(zoomOutTime, IfOn)

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Quest Cam")
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

-- Sub-page for the screen tint and vignette.
local function CreateTintPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Look")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"How the game world looks while cinematic mode is active: letterbox bars, colour " ..
		"grading, vignette, inn glow and weather. The UI isn't tinted. While this page is open " ..
		"the tint is previewed behind the options window. Names and nameplates are on the " ..
		"Nameplates page, world tooltips on the Showing the UI page.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Letterbox
	local letterboxHeader = Header(content, "Letterbox", subtitle, -20)

	local letterbox = Check(content, "letterbox", "Show letterbox bars",
		"Black bars slide in at the top and bottom of the screen.", function(value)
			ns.GetDB().letterbox = value
			ns.RefreshLetterbox()
		end)
	letterbox:SetPoint("TOPLEFT", letterboxHeader, "BOTTOMLEFT", -2, -6)

	local size = Slider(content, "letterboxSize", "Bar height", 0, 25, 1, "%d%%", 100, ns.RefreshLetterbox)
	size:SetPoint("TOPLEFT", letterbox, "BOTTOMLEFT", 4, -26)

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
	local WHEN = {
		{ value = "always", text = "Whenever cinematic mode is on" },
		{ value = "flight", text = "Only on flights" },
		{ value = "idle", text = "Only when standing still" },
	}
	local whenControl = Dropdown(content, "tintWhen", WHEN, 260, ns.RefreshTint)
	if whenControl then
		whenControl:SetPoint("TOPLEFT", whenLabel, "BOTTOMLEFT", 0, -6)
	else
		local previous = whenLabel
		for i, choice in ipairs(WHEN) do
			local check = Choice(content, "tintWhen", choice.value, choice.text)
			check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
			previous = check
		end
		whenControl = previous
	end
	local whenNote = Label(content, "GameFontHighlightSmall",
		"\"Only when standing still\" starts after the delay on the AFK camera page.")
	whenNote:SetPoint("TOPLEFT", whenControl, "BOTTOMLEFT", 2, -8)
	whenNote:SetWidth(320)
	whenNote:SetJustifyV("TOP")

	-- Time of day: which clock, strength, your own phases
	local timeHeader = Header(content, "Time of day", whenNote, -24)
	timeHeader:SetPoint("TOPLEFT", whenNote, "BOTTOMLEFT", -2, -24)
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

	canvas:SetScript("OnShow", PageShown(function()
		Refresh()
		ns.SetTintPreview(true)
	end, content))
	canvas:SetScript("OnHide", function() ns.SetTintPreview(false) end)
	canvas:Hide()
	RegisterSubpage(canvas, "Look")
end

-- Sub-page for audio: music and ambience during cinematic mode.
local function CreateAudioPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Audio")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"Sound during cinematic mode. Your own sound settings are saved first and put " ..
		"back afterwards, even after a crash. Pick which cameras play music as they start.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Left column: music, fresh songs, fatigue
	local musicHeader = Header(content, "Music", subtitle, -20)

	local music = Check(content, "musicInCinematic", "Play music in cinematic mode",
		"Fades game music in when the UI fades out and back out when it returns, " ..
		"using your music volume. If music was already on, it's left alone.")
	music:SetPoint("TOPLEFT", musicHeader, "BOTTOMLEFT", -2, -6)
	music:HookScript("OnClick", Refresh) -- grey out / enable the options that depend on it

	local logoutMusic = Check(content, "musicOffOnLogout", "Turn music off on logout",
		"Switches game music off when you log out or exit, so it starts off next time.")
	logoutMusic:SetPoint("TOPLEFT", music, "BOTTOMLEFT", 0, -2)

	local musicFade = Slider(content, "musicFadeTime", "Music fade time", 0.5, 10, 0.5, "%.1f sec")
	musicFade:SetPoint("TOPLEFT", logoutMusic, "BOTTOMLEFT", 4, -26)
	Tooltip(musicFade, "How long music (and ambience) takes to fade in or out with cinematic mode.")

	local playHeader = Header(content, "Play music", musicFade, -24)
	playHeader:SetPoint("TOPLEFT", musicFade, "BOTTOMLEFT", -2, -24)
	local previous = playHeader
	for i, item in ipairs(MUSIC_CAMS) do
		local check = Check(content, item[1], item[2], MusicCamTip(item[1]) ..
			" Also on the camera's own page.")
		check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
		DependsOnMusic(check)
		previous = check
	end

	local fatigueHeader = Header(content, "Fatigue", previous, -18)
	fatigueHeader:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 2, -18)

	local fatigue = Slider(content, "musicFatigue", "Music fatigue", 0, 30, 1, "%d min")
	fatigue:SetPoint("TOPLEFT", fatigueHeader, "BOTTOMLEFT", 2, -26)
	Tooltip(fatigue, "Once the addon has started music, it won't start it again for this " ..
		"long, so short spells of cinematic mode don't keep restarting it. The cameras ticked " ..
		"under Play music start it anyway. Music coming back after a mute doesn't count. 0 turns this off.")
	DependsOnMusic(fatigue)

	local newZone = Check(content, "fatigueIgnoreNewZone", "Start music anyway in a new zone",
		"Music starts in a zone other than the one it last played in, even if it played recently.")
	newZone:SetPoint("TOPLEFT", fatigue, "BOTTOMLEFT", -4, -18)
	DependsOnMusic(newZone)

	-- Right column: muting, ambience
	local muteHeader = Label(content, "GameFontNormal", "Muting")
	muteHeader:SetPoint("TOPLEFT", musicHeader, "TOPLEFT", 320, 0)

	local combatMusic = Check(content, "musicOffInCombat", "Mute music in combat",
		"Music fades out over about a second when a fight starts and back in when it " ..
		"ends. Works on your own game music too; your volume is put back afterwards.")
	combatMusic:SetPoint("TOPLEFT", muteHeader, "BOTTOMLEFT", -2, -6)
	DependsOnMusic(combatMusic)
	combatMusic:HookScript("OnClick", Refresh) -- grey out / enable the delay below

	local combatResume = Slider(content, "musicCombatResume", "Resume music after", 0, 120, 5, "%d sec")
	combatResume:SetPoint("TOPLEFT", combatMusic, "BOTTOMLEFT", 24, -26)
	Tooltip(combatResume, "After a fight, music stays off until this long has passed with no new " ..
		"fight, then a fresh track fades in.")
	GreyUnless(combatResume, function(db) return db.musicInCinematic and db.musicOffInCombat end)

	local flightMusic = Check(content, "musicOffOnFlights", "Mute music on flights",
		"Music fades out and switches off when you take off, and a fresh track fades in " ..
		"when you land.")
	flightMusic:SetPoint("TOPLEFT", combatResume, "BOTTOMLEFT", -24, -14)
	DependsOnMusic(flightMusic)

	local movingMusic = Check(content, "musicPauseWhenMoving", "Pause music when you move on",
		"Music fades out once you start moving after a flight, RP walking or standing still " ..
		"(running, riding). A fresh track fades in when you next fly, walk, or stand still for " ..
		"the AFK camera delay.")
	movingMusic:SetPoint("TOPLEFT", flightMusic, "BOTTOMLEFT", 0, -2)
	DependsOnMusic(movingMusic)
	movingMusic:HookScript("OnClick", Refresh) -- grey out / enable the fade below

	local landingMusic = Check(content, "musicPauseOnLanding", "Pause music when a flight lands",
		"Music fades out as soon as you touch down, without waiting for you to move. A fresh " ..
		"track fades in when you next fly, walk, or stand still for the AFK camera delay.")
	landingMusic:SetPoint("TOPLEFT", movingMusic, "BOTTOMLEFT", 0, -2)
	DependsOnMusic(landingMusic)
	landingMusic:HookScript("OnClick", Refresh)

	local pauseFade = Slider(content, "musicPauseFadeTime", "Pause fade time", 0.5, 10, 0.5, "%.1f sec")
	pauseFade:SetPoint("TOPLEFT", landingMusic, "BOTTOMLEFT", 24, -26)
	Tooltip(pauseFade, "How long the music takes to fade out when you move on or land, and to " ..
		"fade back in when the next flight, walk or AFK camera starts.")
	GreyUnless(pauseFade, function(db)
		return db.musicInCinematic and (db.musicPauseWhenMoving or db.musicPauseOnLanding)
	end)

	-- Back out to the checkboxes' edge for the next heading.
	local pauseFadeEdge = CreateFrame("Frame", nil, content)
	pauseFadeEdge:SetSize(1, 1)
	pauseFadeEdge:SetPoint("TOPLEFT", pauseFade, "BOTTOMLEFT", -24, -4)

	local placeChecks = PlaceList(content, Stack(pauseFadeEdge, "check"), "Mute music in", "musicOffIn",
		"Music fades out here (your own game music too) and back in when you leave.")
	local lastPlace = placeChecks[#placeChecks]
	for _, check in ipairs(placeChecks) do
		DependsOnMusic(check)
	end

	local ambienceHeader = Label(content, "GameFontNormal", "Ambience")
	ambienceHeader:SetPoint("TOPLEFT", lastPlace, "BOTTOMLEFT", 2, -18)

	local ambience = Check(content, "ambienceFollowsMusic", "Ambience follows music",
		"While cinematic, ambient sound (wind, water, crowds) is set to a share of the " ..
		"music volume, following the music as it fades. Your own ambience volume comes " ..
		"back afterwards.")
	ambience:SetPoint("TOPLEFT", ambienceHeader, "BOTTOMLEFT", -2, -6)
	DependsOnMusic(ambience)

	local ambienceScale = Slider(content, "ambienceScale", "Ambience level", 0, 200, 5, "%d%% of music", 100)
	ambienceScale:SetPoint("TOPLEFT", ambience, "BOTTOMLEFT", 4, -26)
	Tooltip(ambienceScale, "Ambient sound volume as a share of the music volume. 50% keeps it " ..
		"under the music; 100% matches it.")
	DependsOnMusic(ambienceScale)

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Audio")
end

-- Sub-page for combat: staying cinematic in fights, and what to show then.
local function CreateCombatPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Combat")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"Which frames show when you fight or target something while cinematic mode is on, " ..
		"and how fast they fade in and out.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- The same setting as "Turn off in: Combat" on the main page, the right way round.
	local stayHeader = Header(content, "Fights", subtitle, -20)
	local stay = Check(content, "stayInCombat", "Stay in cinematic mode in combat",
		"Fights don't bring the whole UI back: only the frames ticked under In combat below " ..
		"show. Off: being in combat brings the UI back. Same as unticking \"Turn off in: " ..
		"Combat\" on the main page.", function(value)
			ns.GetDB().stayInCombat = value
			Refresh() -- grey out / enable the In combat column
		end)
	stay:SetPoint("TOPLEFT", stayHeader, "BOTTOMLEFT", -2, -6)

	-- One table: a row per frame, a column per situation.
	local showHeader = Header(content, "What to show", stay, -18)
	showHeader:SetPoint("TOPLEFT", stay, "BOTTOMLEFT", 2, -18)

	local showHelp = Label(content, "GameFontHighlightSmall",
		"In combat: only while you stay in cinematic mode in fights (above). Enemy: an alive enemy you can attack, before a fight " ..
		"starts. Anything else: friends, NPCs, other players and dead enemies. Targeting never " ..
		"brings the whole UI back, only what's ticked here.")
	showHelp:SetPoint("TOPLEFT", showHeader, "BOTTOMLEFT", 0, -6)
	showHelp:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	showHelp:SetJustifyV("TOP")

	local LABEL_WIDTH, COLUMN_WIDTH, ROW_HEIGHT = 220, 100, 24
	local COLUMNS = {
		{ "In combat", ns.IsCombatShowOn, "combatShow", true },
		{ "Enemy", ns.IsEnemyShowOn, "enemyShow", false },
		{ "Anything else", ns.IsFriendlyShowOn, "friendlyShow", false },
	}
	local columnTop = CreateFrame("Frame", nil, content)
	columnTop:SetSize(1, 1)
	columnTop:SetPoint("TOPLEFT", showHelp, "BOTTOMLEFT", 0, -14)
	for c, column in ipairs(COLUMNS) do
		local heading = Label(content, "GameFontNormalSmall", column[1])
		heading:SetWidth(COLUMN_WIDTH)
		heading:SetJustifyH("CENTER")
		heading:SetPoint("TOPLEFT", columnTop, "TOPLEFT", LABEL_WIDTH + (c - 1) * COLUMN_WIDTH, 0)
	end

	local lastLabel
	for r, item in ipairs(ns.COMBAT_SHOW) do
		local y = -16 - (r - 1) * ROW_HEIGHT
		local rowLabel = Label(content, "GameFontHighlight", item.label)
		rowLabel:SetPoint("TOPLEFT", columnTop, "TOPLEFT", 0, y - 5)
		lastLabel = rowLabel
		for c, column in ipairs(COLUMNS) do
			local isOn, tableKey, needsStay = column[2], column[3], column[4]
			local check = Check(content, tableKey, "", nil, function(value)
				ns.GetDB()[tableKey][item.key] = value
			end)
			check:SetPoint("TOPLEFT", columnTop, "TOPLEFT",
				LABEL_WIDTH + (c - 1) * COLUMN_WIDTH + (COLUMN_WIDTH - 26) / 2, y)
			check.Refresh = function(self)
				self:SetChecked(isOn(item.key))
				self:SetEnabled(not needsStay or ns.GetDB().stayInCombat)
			end
		end
	end

	-- All the fade times together: a row per situation, fade in and fade out.
	local fadeHeader = Header(content, "Fade times", lastLabel, -24)

	local FADES = {
		{ "In combat", "combatFadeInTime", "combatFadeOutTime", 3,
			"How fast the frames appear when you enter combat. 0 is instant.",
			"How fast they fade away again once the fight is over." },
		{ "Enemy", "enemyFadeInTime", "enemyFadeOutTime", 5,
			"How fast the frames appear when you target an alive enemy.",
			"How fast they fade away again once the enemy is no longer targeted." },
		{ "Anything else", "friendlyFadeInTime", "friendlyFadeOutTime", 5,
			"How fast the frames appear when you target anything else.",
			"How fast they fade away again once it's no longer targeted." },
	}
	local previous = fadeHeader
	for i, fade in ipairs(FADES) do
		local fadeIn = Slider(content, fade[2], fade[1] .. ": fade in", 0, fade[4], 0.05, "%.2f sec")
		fadeIn:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and 2 or 0, i == 1 and -26 or -34)
		Tooltip(fadeIn, fade[5])
		local fadeOut = Slider(content, fade[3], fade[1] .. ": fade out", 0, 30, 0.5, "%.1f sec")
		fadeOut:SetPoint("LEFT", fadeIn, "LEFT", 300, 0)
		Tooltip(fadeOut, fade[6])
		previous = fadeIn
	end

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Combat")
end

-- Sub-page: which nameplates show (mobs, your faction, the other faction),
-- which stay up in cinematic mode, and how far away they show.
local function CreatePlatesPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", "Nameplates")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"Which nameplates show, which stay up while cinematic mode hides the rest, and how far " ..
		"away they appear. Your faction and the other faction work out from the character " ..
		"you're playing, so the same settings suit Horde and Alliance characters.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	local hide = Check(content, "hidePlates", "Hide nameplates in cinematic mode",
		"Fades out nameplates along with the UI. They fade back in the moment combat starts. " ..
		"Kinds ticked under \"In cinematic mode\" below stay up.")
	hide:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -14)
	hide:HookScript("OnClick", Refresh)

	-- Nameplates and names each get a table: a row per kind of unit, a column
	-- per situation.
	local LABEL_WIDTH, COLUMN_WIDTH, ROW_HEIGHT = 220, 120, 24
	local function TableTop(anchor, headings)
		local top = CreateFrame("Frame", nil, content)
		top:SetSize(1, 1)
		top:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
		for c, heading in ipairs(headings) do
			local text = Label(content, "GameFontNormalSmall", heading)
			text:SetWidth(COLUMN_WIDTH)
			text:SetJustifyH("CENTER")
			text:SetPoint("TOPLEFT", top, "TOPLEFT", LABEL_WIDTH + (c - 1) * COLUMN_WIDTH, 0)
		end
		return top
	end
	local function PlaceRow(top, r, label, ...)
		local y = -16 - (r - 1) * ROW_HEIGHT
		local rowLabel = Label(content, "GameFontHighlight", label)
		rowLabel:SetPoint("TOPLEFT", top, "TOPLEFT", 0, y - 5)
		for c, check in ipairs({ ... }) do
			check:SetPoint("TOPLEFT", top, "TOPLEFT", LABEL_WIDTH + (c - 1) * COLUMN_WIDTH + (COLUMN_WIDTH - 26) / 2, y)
		end
		return rowLabel
	end

	local showHeader = Header(content, "Show nameplates for", hide, -18)
	showHeader:SetPoint("TOPLEFT", hide, "BOTTOMLEFT", 2, -18)
	local columnTop = TableTop(showHeader, { "Show", "In cinematic mode", "In combat" })

	local KINDS = {
		{ "Mobs", "Hostile and neutral mobs" },
		{ "NPCs", "Friendly NPCs" },
		{ "Own", "Players of your faction" },
		{ "Other", "Players of the other faction" },
		{ "Pets", "Pets, minions and guardians" },
		{ "Totems", "Totems" },
	}
	local lastLabel
	for r, kind in ipairs(KINDS) do
		local showKey, cinematicKey = "plateShow" .. kind[1], "plateCinematic" .. kind[1]
		local show = Check(content, showKey, "",
			"Show these nameplates. Unticked, they stay hidden everywhere, in fights too. " ..
			"The game's own nameplate options (enemy nameplates, friendly NPC nameplates...) " ..
			"are set to match these ticks at login and whenever you change them here, so " ..
			"changes made with the V keys or the game's options last until you log in again.",
			function(value)
				ns.GetDB()[showKey] = value
				ns.SyncPlateCVars()
				Refresh()
			end)
		local cinematic = Check(content, cinematicKey, "",
			"Keep these nameplates up in cinematic mode while the others fade out.")
		GreyUnless(cinematic, function(db) return db.hidePlates and db[showKey] end)
		local combat = Check(content, "plateCombat" .. kind[1], "",
			"Show these nameplates during fights. Unticked, they're hidden while you're in " ..
			"combat, in or out of cinematic mode. The game won't let nameplates be switched " ..
			"off mid-fight, so hidden ones can still be clicked.")
		GreyUnless(combat, function(db) return db[showKey] end)
		lastLabel = PlaceRow(columnTop, r, kind[2], show, cinematic, combat)
	end

	local alwaysTarget = Check(content, "plateAlwaysTarget", "Always show your target's nameplate",
		"Your target's nameplate shows whatever the rows above say, in cinematic mode too. " ..
		"The game still needs its nameplates for that kind of unit switched on, so a row " ..
		"whose game option is off (for example Friendly NPCs unticked) has no plate to show.")
	alwaysTarget:SetPoint("TOPLEFT", lastLabel, "BOTTOMLEFT", -2, -12)
	lastLabel = alwaysTarget

	-- Names, laid out the same way. "Show" is the game's own name setting
	-- (what you see outside cinematic mode).
	local namesHeader = Header(content, "Names", lastLabel, -24)
	local hideNames = Check(content, "hideNames", "Hide names in cinematic mode",
		"Hides unit names while the UI is faded. Your name settings are restored when the UI " ..
		"comes back. Kinds ticked under \"In cinematic mode\" below keep their names.")
	hideNames:SetPoint("TOPLEFT", namesHeader, "BOTTOMLEFT", -2, -6)
	hideNames:HookScript("OnClick", Refresh)

	local namesShowHeader = Header(content, "Show names for", hideNames, -18)
	namesShowHeader:SetPoint("TOPLEFT", hideNames, "BOTTOMLEFT", 2, -18)
	local namesTop = TableTop(namesShowHeader, { "Show", "In cinematic mode" })
	local previousName
	for r, group in ipairs(ns.NAME_GROUPS) do
		local iconKey = ns.NAME_ICON_KINDS[group.key] and ("nameIcon" .. group.key)
		local showKey = "nameShow" .. group.key
		local show = Check(content, showKey, "",
			"Show these names. The game's own name options are set to match these ticks at " ..
			"login and whenever you change them here, so changes made in the game's options " ..
			"last until you log in again.", function(value)
				ns.GetDB()[showKey] = value
				ns.SetNamesShown(group, value)
				Refresh()
			end)
		show.Refresh = function(self)
			self:SetChecked(ns.GetDB()[showKey] == true)
			self:SetEnabled(ns.GetNamesShown(group) ~= nil) -- greyed out where this client has no such setting
		end
		local keepKey = "nameKeep" .. group.key
		-- Keeping the name and using an icon in its place are one or the other.
		local cinematic = Check(content, keepKey, "",
			"Keep these names up in cinematic mode while the others are hidden.", function(value)
				local db = ns.GetDB()
				db[keepKey] = value
				if value and iconKey then
					db[iconKey] = false
				end
				ns.UpdateCVars(ns.lastCinematic)
				Refresh()
			end)
		GreyUnless(cinematic, function(db) return db.hideNames and db[showKey] == true end)
		previousName = PlaceRow(namesTop, r, group.label, show, cinematic)
	end

	-- Custom icons: in cinematic mode, an icon in place of a kind's name, on
	-- every unit of that kind or only on those flagged for PvP.
	local iconsHeader = Header(content, "Custom icons", previousName, -18)
	iconsHeader:SetPoint("TOPLEFT", previousName, "BOTTOMLEFT", 2, -18)
	local iconsHelp = Label(content, "GameFontHighlightSmall",
		"In cinematic mode, a small icon where these units' nameplates would be, in place of " ..
		"their names (a faction icon for players). Needs \"Hide names in cinematic mode\" and " ..
		"their nameplates ticked under \"Show nameplates for\"; their faded plates stay switched " ..
		"on (and clickable) for it.")
	iconsHelp:SetPoint("TOPLEFT", iconsHeader, "BOTTOMLEFT", 0, -6)
	iconsHelp:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	iconsHelp:SetJustifyH("LEFT")
	local iconsTop = TableTop(iconsHelp, { "Use custom icon", "Only if PvP flagged" })
	for r, kind in ipairs(KINDS) do
		local iconKey, keepKey = "nameIcon" .. kind[1], "nameKeep" .. kind[1]
		local icon = Check(content, iconKey, "",
			"Show an icon in place of these names in cinematic mode. Keeping their names (under " ..
			"\"Show names for\") is turned off: it's one or the other.",
			function(value)
				local db = ns.GetDB()
				db[iconKey] = value
				if value then
					db[keepKey] = false -- the icon replaces the name
					ns.UpdateCVars(ns.lastCinematic)
				end
				Refresh()
			end)
		GreyUnless(icon, function(db) return db.hideNames and db["plateShow" .. kind[1]] end)
		local pvp = Check(content, "nameIconPvP" .. kind[1], "",
			"Only units flagged for PvP get the icon; the rest show nothing.")
		GreyUnless(pvp, function(db) return db.hideNames and db["plateShow" .. kind[1]] and db[iconKey] end)
		previousName = PlaceRow(iconsTop, r, kind[2], icon, pvp)
	end

	-- The game's own setting, not a saved one: shown as it is now.
	local distanceHeader = Header(content, "Distance", previousName, -18)
	distanceHeader:SetPoint("TOPLEFT", previousName, "BOTTOMLEFT", 2, -18)
	local distance = Slider(content, {
		get = function() return tonumber(GetCVar("nameplateMaxDistance")) or 20 end,
		set = function(value)
			if not InCombatLockdown() then SetCVar("nameplateMaxDistance", value) end
		end,
	}, "Show nameplates up to", 10, 100, 1, "%d yards")
	distance:SetPoint("TOPLEFT", distanceHeader, "BOTTOMLEFT", 2, -26)
	Tooltip(distance, "The game's own nameplate distance, for every kind of nameplate. " ..
		"Can't change during a fight. Far plates also need the unit to be loaded: the server " ..
		"only sends units within about 100 yards, often less.")
	if GetCVar("nameplateMaxDistance") == nil then
		distance:Hide()
		distanceHeader:Hide()
	end

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
		"How the chat window behaves while cinematic mode is active. Typing always shows it.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", chatPanel, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Left column: the chat window, message types, places
	local windowHeader = Header(chatPanel, "Chat window", subtitle, -20)

	local fadeChat = Check(chatPanel, "fadeChat", "Fade chat",
		"Fade the chat window and input bar along with the rest of the UI.")
	fadeChat:SetPoint("TOPLEFT", windowHeader, "BOTTOMLEFT", -2, -6)

	local chatPeek = Check(chatPanel, "chatPeek", "Show chat when a message arrives",
		"While the UI is faded, a new message briefly shows just the chat window it " ..
		"arrived in. Choose which messages below. Needs \"Fade chat\" to be on.")
	chatPeek:SetPoint("TOPLEFT", fadeChat, "BOTTOMLEFT", 0, -2)

	local peekTime = Slider(chatPanel, "chatPeekTime", "Show chat for", 2, 30, 1, "%d sec")
	peekTime:SetPoint("TOPLEFT", chatPeek, "BOTTOMLEFT", 4, -26)
	Tooltip(peekTime, "How long chat stays up after a message arrives or after you finish typing.")

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
		check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previousIsHeader and -2 or 0,
			previousIsHeader and -6 or -2)
		previous, previousIsHeader = check, false
	end

	local keepHeader = Label(chatPanel, "GameFontNormal", "Keep chat visible in")
	keepHeader:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 2, -18)
	local CHAT_TIP = "The chat window stays up here while the rest of the UI fades. " ..
		"Only matters where cinematic mode isn't turned off."
	previous = keepHeader
	for i, place in ipairs({
		{ "chatInCities", "Cities", "Capital cities. " },
		{ "chatInInns", "Inns", "Resting anywhere outside a capital city. " },
		{ "chatInDungeons", "Dungeons", "" },
		{ "chatInRaids", "Raids", "" },
		{ "chatInPvP", "Battlegrounds and arenas", "" },
	}) do
		local check = Check(chatPanel, place[1], place[2], place[3] .. CHAT_TIP)
		check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
		previous = check
	end

	-- Right column: channels the player has joined
	local channelHeader = Label(chatPanel, "GameFontNormal", "Show chat for these channels")
	channelHeader:SetPoint("TOPLEFT", windowHeader, "TOPLEFT", 320, 0)

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
local keepRows, keepHeaders = {}, {}

local function GetKeepRow(i)
	if not keepRows[i] then
		local row = CreateFrame("CheckButton", nil, keepPanel, "UICheckButtonTemplate")
		row:SetSize(24, 24)
		row.label = row.Text or row.text
		if not row.label then
			row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.label:SetPoint("LEFT", row, "RIGHT", 2, 0)
		end
		row.label:SetFontObject("GameFontHighlightSmall")
		row:SetScript("OnClick", function(self)
			ns.SetFrameKept(self.frameName, self:GetChecked() and true or false)
		end)
		keepRows[i] = row
	end
	return keepRows[i]
end

local function GetKeepHeader(i)
	if not keepHeaders[i] then
		keepHeaders[i] = Label(keepPanel, "GameFontNormal")
	end
	return keepHeaders[i]
end

local function RefreshKeep()
	local rowIndex, headerIndex = 0, 0
	local previous, lastGroup, previousIsHeader = keepPanel.keepTop, nil, false
	for _, item in ipairs(ns.GetBuiltInFrames()) do
		if item.groupLabel ~= lastGroup then
			lastGroup = item.groupLabel
			headerIndex = headerIndex + 1
			local header = GetKeepHeader(headerIndex)
			header:SetText(item.groupLabel)
			header:ClearAllPoints()
			header:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 2, -14)
			header:Show()
			previous, previousIsHeader = header, true
		end
		rowIndex = rowIndex + 1
		local row = GetKeepRow(rowIndex)
		row.frameName = item.name
		row.label:SetText(item.name)
		row:SetChecked(item.kept)
		row:ClearAllPoints()
		-- Checkboxes sit a little left of their header so the boxes line up with it.
		row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previousIsHeader and -2 or 0, -2)
		row:Show()
		previous, previousIsHeader = row, false
	end
	for i = rowIndex + 1, #keepRows do keepRows[i]:Hide() end
	for i = headerIndex + 1, #keepHeaders do keepHeaders[i]:Hide() end
end

-- Sub-page: which frames fade. Built-in frames to keep shown (left), and
-- extra frames beyond the built-in list (right).
local function CreateFramesPanel()
	local canvas, content = CreateScrollPage()
	keepPanel, extrasPanel = content, content

	local title = Label(content, "GameFontNormalLarge", "Frames")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall",
		"Which frames fade in cinematic mode: keep built-in ones visible (left), or fade extra " ..
		"ones the addon doesn't know about (right).")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Left column: always shown
	local keepHeader = Header(content, "Always shown", subtitle, -20)
	local keepHelp = Label(content, "GameFontHighlightSmall",
		"Tick a frame to keep it visible during cinematic mode. You can also hover over " ..
		"something on screen and type |cffffd100/cine keep|r. A frame inside another frame " ..
		"that fades (like the minimap inside its cluster) fades with it, so keep the outer one.")
	keepHelp:SetPoint("TOPLEFT", keepHeader, "BOTTOMLEFT", 0, -6)
	keepHelp:SetWidth(290)
	keepHelp:SetJustifyV("TOP")

	-- The minimap is several nested frames (and shrinks when faded), so ticking
	-- one of them below isn't enough; this keeps the whole group up.
	content.alwaysMinimap = Check(content, "alwaysShowMinimap", "Always show the minimap",
		"Keeps the whole minimap visible in cinematic mode: the map, its ring, zone text " ..
		"and the Cinematic button.")
	content.alwaysMinimap:SetPoint("TOPLEFT", keepHelp, "BOTTOMLEFT", -2, -10)

	-- Or only while tracking; the kinds of tracking below only apply while it's on.
	local trackingMaster = Check(content, "minimapForTracking", "Keep minimap open while tracking",
		"While you're tracking one of the kinds ticked below, the minimap stays up during " ..
		"cinematic mode. Also on the minimap button's menu.", function(value)
			ns.GetDB().minimapForTracking = value
			Refresh()
		end)
	trackingMaster:SetPoint("TOPLEFT", content.alwaysMinimap, "BOTTOMLEFT", 0, -2)
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
	-- The list of frames starts below the tracking (back out to the column edge).
	content.keepTop = CreateFrame("Frame", nil, content)
	content.keepTop:SetSize(1, 1)
	content.keepTop:SetPoint("TOPLEFT", previousTracking, "BOTTOMLEFT", -16, 0)

	-- Right column: extra frames
	local extrasHeader = Label(content, "GameFontNormal", "Extra frames")
	extrasHeader:SetPoint("TOPLEFT", keepHeader, "TOPLEFT", 320, 0)
	content.help = Label(content, "GameFontHighlightSmall",
		"To fade something else, hover over it and type |cffffd100/cine add|r. " ..
		"Stop fading one with |cffffd100Stop|r; greyed-out frames are ones you stopped, " ..
		"which |cffffd100Restore|r undoes.")
	content.help:SetPoint("TOPLEFT", extrasHeader, "BOTTOMLEFT", 0, -6)
	content.help:SetWidth(290)
	content.help:SetJustifyV("TOP")

	for i = 1, MAX_EXTRA_ROWS do
		extraRows[i] = CreateExtraRow(content, content.help, i)
	end
	content.empty = Label(content, "GameFontDisableSmall")

	canvas:SetScript("OnShow", PageShown(function()
		if ns.GetDB() then
			Refresh()
			RefreshKeep()
			RefreshExtras()
		end
	end, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Frames")
end

-- Sub-page: keybinds. The same bindings as Key Bindings > AddOns, with two
-- key slots each like Blizzard's page.
local KEYBINDS = {
	{ action = "CINEMATIC_HIDEUI", label = "Hide the UI",
		tip = "Like Blizzard's Alt+Z: hides the whole UI, but keeps the tint, letterbox " ..
			"and time-of-day title. Press again (or Blizzard's key) to bring it back." },
	{ action = "CINEMATIC_TOGGLE", label = "Toggle cinematic mode",
		tip = "Turns cinematic mode on or off, like /cine." },
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

-- Puts key (or nothing) in the button's slot, replacing what was there.
local function Bind(button, key)
	StopListening()
	if InCombatLockdown() then
		ns.Print("keybinds can't be changed in combat")
		return
	end
	local current = select(button.slot, GetBindingKey(button.action))
	if current then
		SetBinding(current)
	end
	if key then
		local previous = GetBindingAction(key)
		if previous and previous ~= "" and previous ~= button.action then
			ns.Print(KeyText(key) .. " was bound to " .. (_G["BINDING_NAME_" .. previous] or previous) ..
				" and now isn't")
		end
		SetBinding(key, button.action)
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

function ns.OpenOptions()
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
-- and sound, then the camera modes (their shared page and events first).
CreateRevealPanel()
CreateFramesPanel()
CreateCombatPanel()
CreatePlatesPanel()
CreateChatPanel()
CreateTintPanel()
CreateAudioPanel()
CreateCameraPanel()
CreateEventsPanel()
CreateFlightPanel()
CreateStandingPanel()
CreateCozyPanel()
CreateVistaPanel()
CreateFishPanel()
CreateWalkPanel()
CreateAutoRunPanel()
CreateDeathPanel()
CreateQuestPanel()
CreateKeybindsPanel()
