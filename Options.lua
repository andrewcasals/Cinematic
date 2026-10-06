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
		title:SetText(label .. ": |cffffd100" .. fmt:format(value) .. "|r")
	end

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
		"Fades the UI and adds letterbox bars between fights. Combat, targeting an enemy, casting " ..
		"and opening windows like the spellbook bring it back. Typing just shows the chat. The " ..
		"pages under this one cover what shows when, the camera modes, sound, chat and the look.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Left column: general, fading
	local general = Header(panel, "General", subtitle, -20)

	local enabled = Check(panel, "enabled", "Enable cinematic mode",
		"Also toggled with /cine or the keybind under Key Bindings > AddOns.", ns.SetEnabled)
	enabled:SetPoint("TOPLEFT", general, "BOTTOMLEFT", -2, -6)

	local startCinematic = Check(panel, "startCinematic", "Start in cinematic mode on login",
		"When you log in, the UI starts hidden and the letterbox slides in, instead of " ..
		"waiting for the fade delay. Doesn't apply to /reload (see below).")
	startCinematic:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -2)

	local startOnReload = Check(panel, "startCinematicOnReload", "Start in cinematic mode after /reload",
		"After a /reload, the UI starts hidden and the letterbox slides in, instead of " ..
		"waiting for the fade delay.")
	startOnReload:SetPoint("TOPLEFT", startCinematic, "BOTTOMLEFT", 0, -2)

	local timeMessage = Check(panel, "timeOfDayMessage", "Show the time of day on login and /reload",
		"Under the zone name that appears when you log in or reload: Dawn, Morning, Midday, " ..
		"Afternoon, Evening, Dusk or Night. Uses the same clock as the time-of-day tint (set " ..
		"on the Look page).")
	timeMessage:SetPoint("TOPLEFT", startOnReload, "BOTTOMLEFT", 0, -2)
	timeMessage:HookScript("OnClick", Refresh) -- grey out / enable the option below

	local timeChange = Check(panel, "timeOfDayChange", "...and when it changes",
		"When the time of day moves on during play (Evening to Dusk, say), its name fades in " ..
		"where the zone title appears, then fades away. Not during combat.")
	timeChange:SetPoint("TOPLEFT", timeMessage, "BOTTOMLEFT", 16, -2)
	GreyUnless(timeChange, function(db) return db.timeOfDayMessage end)
	timeChange:HookScript("OnClick", Refresh) -- grey out / enable the sound option

	local timeSound = Check(panel, "timeOfDaySound", "...with a sound",
		"A fitting sound plays with it: a rooster at dawn, a horse in the morning, " ..
		"your faction's bell at midday, a gentle afternoon sound, frogs in the evening, an owl at dusk and a " ..
		"wolf at night. Uses your sound effects volume.")
	timeSound:SetPoint("TOPLEFT", timeChange, "BOTTOMLEFT", 16, -2)
	GreyUnless(timeSound, function(db) return db.timeOfDayMessage and db.timeOfDayChange end)

	local minimapButton = Check(panel, "minimapButton", "Show minimap button",
		"Left-click it for quick options (turn off for a while, combat, tint), right-click for " ..
		"these settings, drag to move it.", function(value)
			ns.GetDB().minimapButton = value
			if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
		end)
	minimapButton:SetPoint("TOPLEFT", timeSound, "BOTTOMLEFT", -32, -2)

	local fadingHeader = Header(panel, "Fading", minimapButton, -18)
	fadingHeader:SetPoint("TOPLEFT", minimapButton, "BOTTOMLEFT", 2, -18)

	local delay = Slider(panel, "delay", "Fade delay", 0, 30, 0.5, "%.1f sec")
	delay:SetPoint("TOPLEFT", fadingHeader, "BOTTOMLEFT", 2, -26)
	Tooltip(delay, "How long things must stay calm before the UI fades out.")

	local fadeOut = Slider(panel, "fadeOutTime", "Fade out time", 0.1, 5, 0.1, "%.1f sec")
	fadeOut:SetPoint("TOPLEFT", delay, "BOTTOMLEFT", 0, -34)

	local fadeIn = Slider(panel, "fadeInTime", "Fade in time", 0, 10, 0.05, "%.2f sec")
	fadeIn:SetPoint("TOPLEFT", fadeOut, "BOTTOMLEFT", 0, -34)

	-- Right column: places
	local placesHeader = Label(panel, "GameFontNormal", "Turn off in")
	placesHeader:SetPoint("TOPLEFT", general, "TOPLEFT", 320, 0)

	local dungeons = Check(panel, "offInDungeons", "Dungeons",
		"Keep the normal UI in dungeons and scenarios.")
	dungeons:SetPoint("TOPLEFT", placesHeader, "BOTTOMLEFT", -2, -6)

	local raids = Check(panel, "offInRaids", "Raids")
	raids:SetPoint("TOPLEFT", dungeons, "BOTTOMLEFT", 0, -2)

	local pvp = Check(panel, "offInPvP", "Battlegrounds and arenas")
	pvp:SetPoint("TOPLEFT", raids, "BOTTOMLEFT", 0, -2)

	local cities = Check(panel, "offInCities", "Cities",
		"Capital cities, including Dalaran. Flights leaving a city still go cinematic.")
	cities:SetPoint("TOPLEFT", pvp, "BOTTOMLEFT", 0, -2)

	local inns = Check(panel, "offInInns", "Inns",
		"Resting anywhere outside a capital city, such as a town inn.")
	inns:SetPoint("TOPLEFT", cities, "BOTTOMLEFT", 0, -2)

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
		"What brings the UI, or parts of it, back while cinematic mode is on. Fights and " ..
		"targeting are on the Combat page, chat on the Chat page.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Left column: mouseover, what brings the UI back, portrait and buffs
	local mouseHeader = Header(content, "Mouseover", subtitle, -20)

	local mouseover = Check(content, "mouseover", "Reveal on mouseover",
		"Pointing at a faded element shows it (and the elements grouped with it).")
	mouseover:SetPoint("TOPLEFT", mouseHeader, "BOTTOMLEFT", -2, -6)

	local minimapHold = Slider(content, "minimapHoverHold", "Minimap stays after mouseover", 0, 30, 1, "%d sec")
	minimapHold:SetPoint("TOPLEFT", mouseover, "BOTTOMLEFT", 4, -26)
	Tooltip(minimapHold, "How long the minimap stays up after your mouse leaves it. In the camera " ..
		"modes the short default is used.")

	local questsHold = Slider(content, "questsHoverHold", "Quest tracker stays after mouseover", 0, 30, 1, "%d sec")
	questsHold:SetPoint("TOPLEFT", minimapHold, "BOTTOMLEFT", 0, -34)
	Tooltip(questsHold, "How long the quest tracker stays up after your mouse leaves it. In the " ..
		"camera modes the short default is used.")

	local revealHeader = Header(content, "Bring the UI back", questsHold, -24)
	revealHeader:SetPoint("TOPLEFT", questsHold, "BOTTOMLEFT", -2, -24)

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

	local buffPeekTime = Slider(content, "buffPeekTime", "Show buffs for", 0.5, 30, 0.5, "%.1f sec")
	buffPeekTime:SetPoint("TOPLEFT", buffPeek, "BOTTOMLEFT", 4, -26)

	local ignoreLabel = Label(content, "GameFontHighlightSmall", "Except for these buffs (spell IDs or names):")
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
		"Honorless Target).")
	buffPeek:HookScript("OnClick", Refresh) -- grey out / enable the list

	-- Right column: minimap and tracking
	local trackingHeader = Label(content, "GameFontNormal", "Minimap and tracking")
	trackingHeader:SetPoint("TOPLEFT", mouseHeader, "TOPLEFT", 320, 0)

	-- Master switch; the kinds of tracking below only apply while it's on.
	local trackingMaster = Check(content, "minimapForTracking", "Keep minimap open while tracking",
		"While you're tracking one of the kinds ticked below, the minimap stays up during " ..
		"cinematic mode. Also on the minimap button's menu.", function(value)
			ns.GetDB().minimapForTracking = value
			Refresh()
		end)
	trackingMaster:SetPoint("TOPLEFT", trackingHeader, "BOTTOMLEFT", -2, -6)

	local TRACKING_INDENT = 16
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
			"still for the standing-still delay. It comes back when you move." },
	}) do
		local check = Check(content, kind[1], kind[2], kind[3] or TRACKING_TIP)
		check:SetPoint("TOPLEFT", previousTracking, "BOTTOMLEFT", i == 1 and TRACKING_INDENT or 0, -2)
		GreyUnless(check, function(db) return db.minimapForTracking end)
		previousTracking = check
	end

	local alwaysNote = Label(content, "GameFontHighlightSmall",
		"To keep the whole minimap up all the time, see \"Always show the minimap\" on the " ..
		"Frames page.")
	alwaysNote:SetPoint("TOPLEFT", previousTracking, "BOTTOMLEFT", 4 - TRACKING_INDENT, -10)
	alwaysNote:SetWidth(270)
	alwaysNote:SetJustifyV("TOP")

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

	local zoomPastMax = Check(parent, key("PastMax"), "Allow zooming past your maximum",
		"Raises the game's max camera distance (to 2.6) while pulled back, so the zoom " ..
		"isn't cut short. Your own maximum comes back once you've zoomed in again.")
	zoomPastMax:SetPoint("TOPLEFT", zoomPause, "BOTTOMLEFT", -4, -14)
	return zoomPastMax
end

-- Sub-page: the camera modes, and the settings they share.
local function CreateCameraPanel()
	local cameraCanvas
	cameraCanvas, cameraPanel = CreateScrollPage()

	local title = Label(cameraPanel, "GameFontNormalLarge", "Camera modes")
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(cameraPanel, "GameFontHighlightSmall",
		"While cinematic mode is on, the camera comes alive in five situations, each with its " ..
		"own page: Flight camera (on flight paths), Standing still camera (once you've stood " ..
		"still a while), Cozy camera (campfires and emotes), RP walk (moving in walk mode) and " ..
		"Auto-run camera. Everything goes back " ..
		"to normal when " ..
		"the UI returns. The settings here apply to all of them.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", cameraPanel, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	local sharedHeader = Header(cameraPanel, "All camera modes", subtitle, -20)

	local inputPause = Slider(cameraPanel, "cameraInputPause", "Pause after you move the camera", 0, 60, 1, "%d sec")
	inputPause:SetPoint("TOPLEFT", sharedHeader, "BOTTOMLEFT", 2, -26)
	Tooltip(inputPause, "When you drag the camera or use camera keys, the rotation stops and waits " ..
		"this long after your last adjustment before carrying on from your new view. (RP walk " ..
		"has its own, shorter pause.)")

	local npcPause = Check(cameraPanel, "cameraPauseAtNPCs", "Pause while talking to NPCs",
		"While an auction house, vendor, bank, mailbox, trainer, quest giver or flight map window " ..
		"is open, the standing-still and cozy cameras don't start (and stop if they're running). " ..
		"The standing-still timer starts again once you close it.")
	npcPause:SetPoint("TOPLEFT", inputPause, "BOTTOMLEFT", -4, -14)

	local castPause = Check(cameraPanel, "cameraPauseCasting", "Pause while casting",
		"While you cast or channel (crafting, say), the standing-still camera doesn't start, or " ..
		"stops if it's running. Its timer starts again once you finish. The cozy camera keeps " ..
		"going, so cooking at a campfire still feels cozy.")
	castPause:SetPoint("TOPLEFT", npcPause, "BOTTOMLEFT", 0, -2)

	local TUCK_TIP = "Addons can't move the cursor, but they can switch on mouse-steering mode (like " ..
		"holding the right button), which hides it. Once the cursor has been still for the time " ..
		"below, with no window open, it's tucked away. Any click, turning with the mouse, typing, " ..
		"a window, combat or the end of cinematic mode brings it back. Moving the mouse sideways " ..
		"turns you a touch before it does; moving it up or down tilts the camera. While it's " ..
		"tucked away, your right mouse button is held down for you (that's how the cursor hides)."
	local tuckLabel = Label(cameraPanel, "GameFontHighlight", "Tuck the mouse cursor away (experimental)")
	tuckLabel:SetPoint("TOPLEFT", castPause, "BOTTOMLEFT", 2, -12)
	local tuck = tuckLabel
	for i, mode in ipairs({
		{ "cursorTuckFlight", "On flights" },
		{ "cursorTuckIdle", "Standing still" },
		{ "cursorTuckCozy", "Cozy (campfire, sitting, emotes)" },
		{ "cursorTuckWalk", "RP walking" },
		{ "cursorTuckRun", "Auto-running" },
		{ "cursorTuckOther", "Other times in cinematic mode" },
	}) do
		local check = Check(cameraPanel, mode[1], mode[2], TUCK_TIP)
		check:SetPoint("TOPLEFT", tuck, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -4 or -2)
		tuck = check
	end
	local tuckNote = Label(cameraPanel, "GameFontHighlightSmall",
		"|cffff9933Note:|r while the cursor is tucked away, your right mouse button is locked down " ..
		"(mouse-steering mode), as if you were holding it. Click any mouse button to get the " ..
		"cursor back.")
	tuckNote:SetPoint("TOPLEFT", tuck, "BOTTOMLEFT", 4, -6)
	tuckNote:SetWidth(500)
	tuckNote:SetJustifyV("TOP")
	local tuckDelay = Slider(cameraPanel, "cursorTuckDelay", "Tuck it away after", 1, 15, 1, "%d sec")
	tuckDelay:SetPoint("TOPLEFT", tuckNote, "BOTTOMLEFT", 0, -26)

	local tooltipLabel = Label(cameraPanel, "GameFontHighlight", "Hide world tooltips")
	tooltipLabel:SetPoint("TOPLEFT", tuckDelay, "BOTTOMLEFT", -2, -22)
	local tooltipModes = tooltipLabel
	for i, mode in ipairs({
		{ "tooltipOffFlight", "On flights" },
		{ "tooltipOffIdle", "Standing still" },
		{ "tooltipOffCozy", "Cozy (campfire, sitting, emotes)" },
		{ "tooltipOffWalk", "RP walking" },
		{ "tooltipOffRun", "Auto-running" },
	}) do
		local check = Check(cameraPanel, mode[1], mode[2],
			"No tooltip for players, NPCs and objects you mouse over in the world while this camera " ..
			"is running. Tooltips for UI elements still show. (\"Hide world tooltips\" on the Look " ..
			"page hides them throughout cinematic mode.)")
		check:SetPoint("TOPLEFT", tooltipModes, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -4 or -2)
		tooltipModes = check
	end

	local holdNote = Label(cameraPanel, "GameFontHighlightSmall",
		"In the camera modes, the minimap and quest tracker hover holds and the buff and chat " ..
		"peeks use their short default times, so they clear the view quickly.\n\n" ..
		"To fade the music out when you move on from a camera mode, see \"Pause music when you " ..
		"move on\" on the Audio page.")
	holdNote:SetPoint("TOPLEFT", tooltipModes, "BOTTOMLEFT", 4, -10)
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

	local indoorZoom = Slider(cameraPanel, "indoorZoomOut", "Zoom out indoors, at most", 0, 10, 0.5, "%.1f yards")
	indoorZoom:SetPoint("TOPLEFT", indoorLimits, "BOTTOMLEFT", 4, -26)
	Tooltip(indoorZoom, "How far past your own distance the slow zoom may pull back indoors. It " ..
		"also never raises the max zoom distance indoors. Walking in pulled back, the camera " ..
		"glides in to this.")
	GreyUnless(indoorZoom, IfIndoorLimits)

	local indoorSwing = Slider(cameraPanel, "indoorSwing", "Swing indoors, at most", 0, 90, 5, "%d°")
	indoorSwing:SetPoint("TOPLEFT", indoorZoom, "BOTTOMLEFT", 0, -34)
	Tooltip(indoorSwing, "How far either side of behind the flight, RP walk and auto-run cameras " ..
		"may swing indoors.")
	GreyUnless(indoorSwing, IfIndoorLimits)

	local indoorSweep = Check(cameraPanel, "indoorNoSweep", "Pause the standing-still rotation indoors",
		"The standing-still camera sweeps right round your character, which can bump into walls " ..
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
-- standing-still camera) or "back" (swings behind you: flights, RP walk).
local function BuildRotationControls(container, prefix, style)
	local function key(name) return prefix .. name end

	local last
	if style == "sweep" then
		local orbitRight = Check(container, key("Right"), "Rotate clockwise",
			"Sweeps turn the other way round.")
		orbitRight:SetPoint("TOPLEFT", container, "TOPLEFT", -2, 0)

		local orbitStep = Slider(container, key("Step"), "Turn per sweep", 10, 90, 5, "%d°")
		orbitStep:SetPoint("TOPLEFT", orbitRight, "BOTTOMLEFT", 4, -26)
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

		local pitchUp = Slider(container, key("PitchUp"), "Tilt up, max", 0, 45, 5, "%d°")
		pitchUp:SetPoint("TOPLEFT", backArc, "BOTTOMLEFT", 0, -34)
		Tooltip(pitchUp, "Each move also tilts the camera to a random angle between the down " ..
			"and up limits. 0 on both keeps it level.")

		local pitchDown = Slider(container, key("PitchDown"), "Tilt down, max", 0, 45, 5, "%d°")
		pitchDown:SetPoint("TOPLEFT", pitchUp, "BOTTOMLEFT", 0, -34)
		Tooltip(pitchDown, "How far below level a move may tilt.")

		local moveTime = Slider(container, key("MoveTime"), "Move time", 1, 20, 0.5, "%.1f sec")
		moveTime:SetPoint("TOPLEFT", pitchDown, "BOTTOMLEFT", 0, -34)
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


-- A "Turn ... off in" list of place checkboxes (keys prefix .. "Cities" etc.).
local function PlaceList(parent, anchor, title, prefix, tip)
	local header = Label(parent, "GameFontNormal", title)
	header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, -18)
	local previous, checks = header, {}
	for i, place in ipairs({
		{ "Cities", "Cities" }, { "Inns", "Inns" }, { "Dungeons", "Dungeons" },
		{ "Raids", "Raids" }, { "PvP", "Battlegrounds and arenas" },
	}) do
		local check = Check(parent, prefix .. place[1], place[2], tip)
		check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
		checks[#checks + 1] = check
		previous = check
	end
	return previous, checks
end

-- A camera mode's page, laid out the same for every mode: Starting (full
-- width), then Rotation (left) beside Zoom, the mode's extras and Music
-- (right). opts.start(content, header) and opts.extras(content, anchor, dx)
-- build their controls and return the last one plus the x offset from it back
-- to the column edge (2 below a checkbox, -2 below a slider).
local ZOOM_TIP = "The camera slowly pulls back, then (with random zoom) drifts in and out. Moving " ..
	"glides it back to your distance; zooming yourself keeps your new distance."

local function CreateCameraModePanel(opts)
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", opts.name)
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = Label(content, "GameFontHighlightSmall", opts.description)
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	local startHeader = Header(content, "Starting", subtitle, -20)
	local lastStart, startDx = opts.start(content, startHeader)

	-- Left column: rotation
	local rotationHeader = Label(content, "GameFontNormal", "Rotation")
	rotationHeader:SetPoint("TOPLEFT", lastStart, "BOTTOMLEFT", startDx, -24)
	local rotate = Check(content, opts.orbitPrefix, opts.rotateLabel, opts.rotateTip)
	rotate:SetPoint("TOPLEFT", rotationHeader, "BOTTOMLEFT", -2, -6)
	local container = CreateFrame("Frame", nil, content)
	container:SetPoint("TOPLEFT", rotate, "BOTTOMLEFT", 2, -14)
	container:SetSize(300, 1)
	BuildRotationControls(container, opts.orbitPrefix, opts.style)

	-- Right column: zoom, the mode's extras, music
	local zoomHeader = Label(content, "GameFontNormal", "Zoom")
	zoomHeader:SetPoint("TOPLEFT", rotationHeader, "TOPLEFT", 320, 0)
	local zoom = Check(content, opts.zoomPrefix, opts.zoomLabel, opts.zoomTip or ZOOM_TIP)
	zoom:SetPoint("TOPLEFT", zoomHeader, "BOTTOMLEFT", -2, -6)
	local last, dx = BuildZoomControls(content, opts.zoomPrefix, zoom), 2
	if opts.extras then
		last, dx = opts.extras(content, last, dx)
	end

	if opts.music then
		local musicHeader = Label(content, "GameFontNormal", "Music")
		musicHeader:SetPoint("TOPLEFT", last, "BOTTOMLEFT", dx, -18)
		local previous = musicHeader
		for i, item in ipairs(opts.music) do
			local check = Check(content, item[1], item[2], item[3])
			check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
			DependsOnMusic(check)
			previous = check
		end
		local musicNote = Label(content, "GameFontHighlightSmall",
			"The same settings as on the Audio page. They need \"Play music in cinematic mode\" there.")
		musicNote:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 4, -4)
		musicNote:SetWidth(270)
		musicNote:SetJustifyV("TOP")
	end

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, opts.name)
end

-- The "Turning" section of a travel mode's page (RP walk, auto-run).
local function TurningExtras(swingKey, delayKey)
	return function(content, anchor, dx)
		local header = Label(content, "GameFontNormal", "Turning")
		header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx, -18)
		local swing = Check(content, swingKey, "Glide round gently when you turn",
			"When you turn left or right, the camera doesn't snap round with you: it carries on " ..
			"as it was (sway and all) until you stop turning, then glides gently round to your " ..
			"new facing, easing in and out. Steering with the mouse hands the camera straight " ..
			"back to you.")
		swing:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -2, -6)
		swing:HookScript("OnClick", Refresh) -- grey out / enable the wait below
		local glideDelay = Slider(content, delayKey, "Wait before gliding", 0, 5, 0.5, "%.1f sec")
		glideDelay:SetPoint("TOPLEFT", swing, "BOTTOMLEFT", 4, -26)
		Tooltip(glideDelay, "After you stop turning, the view holds this long before gliding round " ..
			"to your new facing, in case you turn again. Turning again starts the wait over.")
		GreyUnless(glideDelay, function(db) return db[swingKey] end)
		return glideDelay, -2
	end
end

local function CreateFlightPanel()
	CreateCameraModePanel({
		name = "Flight camera",
		description = "On flight paths. The camera swings round behind you as you take off, sways " ..
			"behind you on the way and settles behind you before landing.",
		start = function(content, header)
			local instant = Check(content, "taxiInstant", "Start cinematic mode right away on flights",
				"Skips the fade delay when you take off on a flight path.")
			instant:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -2, -6)
			local dropTarget = Check(content, "dropTargetOnFlights", "Drop your target when a flight starts",
				"Your target's frames fade as if nothing were targeted, until you pick a new target " ..
				"or land. (Addons can't clear the target itself; the game doesn't allow it.)")
			dropTarget:SetPoint("TOPLEFT", instant, "BOTTOMLEFT", 0, -2)
			local center = Check(content, "taxiCenter", "Center camera when a flight starts",
				"Slowly swings the camera round behind your character as you take off, ready for " ..
				"the swings behind you.")
			center:SetPoint("TOPLEFT", dropTarget, "BOTTOMLEFT", 0, -2)
			return center, 2
		end,
		orbitPrefix = "taxiOrbit", style = "back",
		rotateLabel = "Sway the camera behind you",
		rotateTip = "The camera swings from side to side behind your character, pausing between " ..
			"moves. Dragging the camera pauses it.",
		zoomPrefix = "taxiZoom", zoomLabel = "Slowly zoom",
		extras = function(content, anchor, dx)
			local header = Label(content, "GameFontNormal", "Landing")
			header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx, -18)
			local settle = Check(content, "taxiSettle", "Settle camera behind you before landing",
				"Shortly before you land, the rotation stops and the camera swings round behind " ..
				"you. Needs one flight on a route to learn how long it takes.")
			settle:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -2, -6)
			local settleLead = Slider(content, "taxiSettleLead", "Start settling before landing", 5, 20, 1, "%d sec")
			settleLead:SetPoint("TOPLEFT", settle, "BOTTOMLEFT", 4, -26)
			Tooltip(settleLead, "The swing takes about 5 seconds, so leave a little extra.")
			return settleLead, -2
		end,
		music = {
			{ "musicNewSongOnFlights", "Fresh song when the rotation starts",
				"Music is switched off and straight back on as the camera starts rotating on a flight " ..
				"(at takeoff if the rotation is off), so the game starts a fresh track. Once per flight." },
			{ "musicOffOnFlights", "Mute music on flights",
				"Music fades out and switches off when you take off, and a fresh track fades in " ..
				"when you land." },
			{ "fatigueIgnoreOnFlights", "Start music even if it played recently",
				"Music fatigue doesn't hold music back when you take off." },
		},
	})
end

local function CreateStandingPanel()
	CreateCameraModePanel({
		name = "Standing still camera",
		description = "Once you've stood still for a while with the UI faded, the camera slowly " ..
			"sweeps around your character. Moving stops it.",
		start = function(content, header)
			local idleDelay = Slider(content, "idleOrbitDelay", "Start after standing still for", 5, 120, 5, "%d sec")
			idleDelay:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 2, -26)
			Tooltip(idleDelay, "How long you stand still before the rotation and zoom begin. Also " ..
				"used by the other options that mention standing still (tint, tracking, music, " ..
				"tooltips).")
			return idleDelay, -2
		end,
		orbitPrefix = "idleOrbit", style = "sweep",
		rotateLabel = "Rotate camera",
		rotateTip = "The camera sweeps around your character, pausing between sweeps. Moving or " ..
			"dragging the camera stops it.",
		zoomPrefix = "idleZoom", zoomLabel = "Slowly zoom",
		extras = function(content, anchor)
			local lastRot = PlaceList(content, anchor, "Turn rotation off in", "rotOffIn",
				"No standing-still rotation here.")
			local lastZoom = PlaceList(content, lastRot, "Turn zoom off in", "zoomOffIn",
				"No standing-still zoom here.")
			return lastZoom, 2
		end,
		music = {
			{ "musicNewSongWhenIdle", "Fresh song when the camera starts",
				"Music is switched off and straight back on as the rotation begins, so the game " ..
				"starts a fresh track. Once each time you stand still (not again after you move " ..
				"the camera)." },
			{ "fatigueIgnoreWhenIdle", "Start music even if it played recently",
				"Music fatigue doesn't hold music back once you've stood still for the delay." },
		},
	})
end

local function CreateAutoRunPanel()
	CreateCameraModePanel({
		name = "Auto-run camera",
		description = "While you're auto-running (the auto-run key). Pressing forward or back, or " ..
			"stopping, ends it; stop and stand, and the standing-still camera takes over. Auto-" ..
			"walking counts as RP walk instead.",
		start = function(content, header)
			local instant = Check(content, "runInstant", "Start cinematic mode as soon as you auto-run",
				"Auto-running skips the fade delay, so the UI fades and the camera starts moving " ..
				"straight away.")
			instant:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -2, -6)
			local inputPause = Slider(content, "runInputPause", "Pause after you move the camera", 0, 15, 0.5, "%.1f sec")
			inputPause:SetPoint("TOPLEFT", instant, "BOTTOMLEFT", 4, -26)
			Tooltip(inputPause, "After you drag the camera, use camera keys or zoom, the rotation " ..
				"waits this long and then carries on from your new view.")
			return inputPause, -2
		end,
		orbitPrefix = "runOrbit", style = "back",
		rotateLabel = "Sway the camera behind you",
		rotateTip = "The camera swings gently from side to side behind your character, pausing " ..
			"between moves.",
		zoomPrefix = "runZoom", zoomLabel = "Gently zoom in and out",
		zoomTip = "The camera eases out a little, then drifts in and out around your own distance. " ..
			"When you stop it glides back.",
		extras = TurningExtras("runSwingBehind", "runGlideDelay"),
		music = {
			{ "musicNewSongWhenAutoRun", "Fresh song when you start auto-running",
				"Music is switched off and straight back on as you start auto-running, so the game " ..
				"starts a fresh track. Stopping for less than 20 seconds and running on doesn't " ..
				"count as a new run." },
			{ "fatigueIgnoreWhenAutoRun", "Start music even if it played recently",
				"Music fatigue doesn't hold music back while you auto-run." },
		},
	})
end

local function CreateCozyPanel()
	CreateCameraModePanel({
		name = "Cozy camera",
		description = "Resting at a campfire, sitting, sleeping, dancing and the like: the camera " ..
			"swings slowly round to face you straight away, then sways gently from side to side " ..
			"in front of you, and eases in close. Moving (or standing up) ends it.",
		start = function(content, header)
			local instant = Check(content, "cozyInstant", "Start cinematic mode straight away",
				"A trigger below skips the fade delay, so the UI fades and the camera starts at once.")
			instant:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -2, -6)

			local cozyPause = Slider(content, "cozyInputPause", "Pause after you move the camera", 0, 15, 0.5, "%.1f sec")
			cozyPause:SetPoint("TOPLEFT", instant, "BOTTOMLEFT", 4, -26)
			Tooltip(cozyPause, "After you drag the camera, use camera keys or zoom, the cozy camera " ..
				"waits this long and then carries on.")

			local buffs = Check(content, "cozyBuffsOn", "With these buffs, while you're still",
				"With any of the buffs listed below (like Welcoming Campfire), standing or sitting " ..
				"still starts the cozy camera.")
			buffs:SetPoint("TOPLEFT", cozyPause, "BOTTOMLEFT", -4, -14)
			buffs:HookScript("OnClick", Refresh) -- grey out / enable the list below

			local buffBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
			buffBox:SetSize(420, 20)
			buffBox:SetAutoFocus(false)
			buffBox:SetPoint("TOPLEFT", buffs, "BOTTOMLEFT", 30, -4)
			local function Save(self)
				ns.GetDB().cozyBuffs = self:GetText()
				if ns.CheckIdleBuffs then ns.CheckIdleBuffs() end
			end
			buffBox:SetScript("OnEnterPressed", function(self) Save(self) self:ClearFocus() end)
			buffBox:SetScript("OnEditFocusLost", Save)
			buffBox:SetScript("OnEscapePressed", function(self)
				self:SetText(ns.GetDB().cozyBuffs or "")
				self:ClearFocus()
			end)
			buffBox.Refresh = function(self)
				local db = ns.GetDB()
				if not self:HasFocus() then self:SetText(db.cozyBuffs or "") end
				self:SetEnabled(db.cozyBuffsOn)
			end
			controls[#controls + 1] = buffBox
			Tooltip(buffBox, "Buff names or spell IDs, separated by commas. Names must match your " ..
				"game language; spell IDs work in any language.")

			local emoteLabel = Label(content, "GameFontHighlight", "When you")
			emoteLabel:SetPoint("TOPLEFT", buffBox, "BOTTOMLEFT", -28, -12)
			local previous = emoteLabel
			for i, emote in ipairs({
				{ "cozySit", "/sit (or press the sit key)" },
				{ "cozySleep", "/sleep or /lie down" },
				{ "cozyDance", "/dance" },
				{ "cozyKneel", "/kneel" },
				{ "cozyWeapon", "Standing with your weapon drawn",
					"Drawing your weapon (Z) out of combat starts the cozy camera for a \"hero shot\": " ..
					"standing still, or while RP walking (the camera swings round in front as you " ..
					"walk). Putting it away, running or combat ends it." },
				{ "cozyChair", "Sitting in a chair or on a bench",
					"Right-clicking a seat to sit on it starts the cozy camera; standing up ends it. " ..
					"Seats are recognised by name, using the words below." },
			}) do
				local check = Check(content, emote[1], emote[2], emote[3] or
					"Doing this emote starts the cozy camera; moving, jumping or another emote ends it.")
				check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -4 or -2)
				previous = check
			end
			previous:HookScript("OnClick", Refresh) -- grey out / enable the seat words

			local seatBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
			seatBox:SetSize(420, 20)
			seatBox:SetAutoFocus(false)
			seatBox:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 30, -4)
			local function SaveSeats(self) ns.GetDB().cozyChairWords = self:GetText() end
			seatBox:SetScript("OnEnterPressed", function(self) SaveSeats(self) self:ClearFocus() end)
			seatBox:SetScript("OnEditFocusLost", SaveSeats)
			seatBox:SetScript("OnEscapePressed", function(self)
				self:SetText(ns.GetDB().cozyChairWords or "")
				self:ClearFocus()
			end)
			seatBox.Refresh = function(self)
				local db = ns.GetDB()
				if not self:HasFocus() then self:SetText(db.cozyChairWords or "") end
				self:SetEnabled(db.cozyChair)
			end
			controls[#controls + 1] = seatBox
			Tooltip(seatBox, "Words that mark a seat when they're in an object's name (\"Wooden " ..
				"Chair\"), separated by commas. Use words in your game language.")
			local seatNote = Label(content, "GameFontHighlightSmall", "Seat words, separated by commas.")
			seatNote:SetPoint("TOPLEFT", seatBox, "BOTTOMLEFT", -4, -4)
			return seatNote, -24 -- back out to the column edge
		end,
		orbitPrefix = "cozyOrbit", style = "back",
		rotateLabel = "Sway in front of you",
		rotateTip = "Once it has swung round to face you, the camera sways gently from side to side " ..
			"in front of your character, pausing between moves.",
		music = {
			{ "musicNewSongWhenCozy", "Fresh song when it starts",
				"Music is switched off and straight back on as the cozy camera starts, so the game " ..
				"starts a fresh track. Getting up for less than 20 seconds and settling back down " ..
				"doesn't count as a new spell." },
			{ "fatigueIgnoreWhenCozy", "Start music even if it played recently",
				"Music fatigue doesn't hold music back while you're cozy." },
		},
		zoomPrefix = "cozyZoom", zoomLabel = "Gently zoom in and out",
		zoomTip = "A close, gentle zoom: it starts by easing in to the close-up distance below, then " ..
			"drifts a little in and out around it.",
		extras = function(content, anchor, dx)
			local header = Label(content, "GameFontNormal", "Close-up")
			header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx, -18)
			local close = Slider(content, "cozyZoomClose", "Zoom in to about", 2, 20, 0.5, "%.1f yards")
			close:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 2, -26)
			Tooltip(close, "The distance the cozy camera zooms in to, if you're further out. The " ..
				"zoom settings above then work around it. Your own distance comes back afterwards.")
			local level = Slider(content, "cozyLevel", "Bring the camera down", -30, 80, 5, "%d°")
			level:SetPoint("TOPLEFT", close, "BOTTOMLEFT", 0, -34)
			Tooltip(level, "As it swings round, the camera also comes down this much toward the " ..
				"ground, so it feels low and close rather than looking down from above. It stops at " ..
				"the ground, so a big number just means \"as low as it goes\". 0 keeps your angle.")
			local crackle = Check(content, "cozyCrackle", "Campfire crackle",
				"While the cozy camera runs at a campfire (one of the buffs listed on the left), a " ..
				"crackling fire plays on your sound effects volume. It fades out when the cozy " ..
				"camera ends or you leave the fire.")
			crackle:SetPoint("TOPLEFT", level, "BOTTOMLEFT", -4, -14)
			return crackle, 2
		end,
	})
end

local function CreateWalkPanel()
	CreateCameraModePanel({
		name = "RP walk",
		description = "While you're moving in walk mode (walk/run key). Stop and stand, and the " ..
			"standing-still camera takes over after its delay. Walking is recognised from your " ..
			"speed; /cine walk shows what the addon thinks.",
		start = function(content, header)
			local instant = Check(content, "walkInstant", "Start cinematic mode as soon as you walk",
				"Walking skips the fade delay, so the UI fades and the camera starts moving straight away.")
			instant:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -2, -6)
			local inputPause = Slider(content, "walkInputPause", "Pause after you move the camera", 0, 15, 0.5, "%.1f sec")
			inputPause:SetPoint("TOPLEFT", instant, "BOTTOMLEFT", 4, -26)
			Tooltip(inputPause, "After you drag the camera, use camera keys or zoom, the " ..
				"rotation waits this long and then carries on from your new view. Short, " ..
				"so it's back in time if you need to steer.")
			return inputPause, -2
		end,
		orbitPrefix = "walkOrbit", style = "back",
		rotateLabel = "Sway the camera behind you",
		rotateTip = "The camera swings gently from side to side behind your character, pausing " ..
			"between moves.",
		zoomPrefix = "walkZoom", zoomLabel = "Gently zoom in and out",
		zoomTip = "The camera eases out a little, then drifts in and out around your own distance. " ..
			"When you stop walking it glides back.",
		extras = TurningExtras("walkSwingBehind", "walkGlideDelay"),
		music = {
			{ "musicNewSongWhenWalking", "Fresh song when you start walking",
				"Music is switched off and straight back on as you set off, so the game starts a fresh " ..
				"track. Pausing for less than 20 seconds and walking on doesn't count as a new walk." },
			{ "fatigueIgnoreWhenWalking", "Start music even if it played recently",
				"Music fatigue doesn't hold music back while you walk." },
		},
	})
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
		"grading, vignette, and names and tooltips in the world. The UI isn't tinted. While " ..
		"this page is open the tint is previewed behind the options window.")
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
				local preset = ns.GetDB().tintPreset
				local shown = preset == "timeofday" or preset == "zonetime"
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
		for _, choice in ipairs(choices) do
			if choice.value == db.tintPreset then
				local text = choice.tip
				if choice.value == "zone" or choice.value == "zonetime" then
					local zone, label, isOverride = ns.GetZoneTintInfo()
					text = text .. ("\n|cffffd100Here: %s (%s%s)|r"):format(
						label, zone, isOverride and ", your choice" or "")
				end
				if choice.value == "timeofday" or choice.value == "zonetime" then
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

	-- When the tint shows
	local whenLabel = Label(content, "GameFontHighlight", "Show the tint")
	whenLabel:SetPoint("TOPLEFT", swatch, "BOTTOMLEFT", 0, -18)
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
		"\"Only when standing still\" starts after the delay on the Standing still camera page.")
	whenNote:SetPoint("TOPLEFT", whenControl, "BOTTOMLEFT", 2, -8)
	whenNote:SetWidth(320)
	whenNote:SetJustifyV("TOP")

	-- Time of day: which clock, strength, your own phases
	local timeHeader = Header(content, "Time of day", whenNote, -24)
	timeHeader:SetPoint("TOPLEFT", whenNote, "BOTTOMLEFT", -2, -24)
	local timeHelp = Label(content, "GameFontHighlightSmall",
		"For the Time of day and Zone + time of day presets.")
	timeHelp:SetPoint("TOPLEFT", timeHeader, "BOTTOMLEFT", 0, -6)

	local clockLabel = Label(content, "GameFontHighlight", "Follows")
	clockLabel:SetPoint("TOPLEFT", timeHelp, "BOTTOMLEFT", 0, -12)
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

	-- Per-zone overrides for the Zone presets
	local zoneHeader = Header(content, "Zone tints", previousPhase, -24)
	local zoneHelp = Label(content, "GameFontHighlightSmall",
		"Used by the Zone and Zone + time of day presets. Choose a tint for the zone you're " ..
		"standing in, or just the area within it (a town, a port); it replaces the built-in " ..
		"mood there. An area's choice wins over its zone's.")
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
		local text = ("This zone: |cffffd100%s|r - %s%s, %d%% strength%s"):format(
			zone ~= "" and zone or "?", label, isOverride and " (your choice)" or " (built in)",
			strength * 100 + 0.5, ownStrength and " (its own)" or "")
		local area, areaLabel, areaOwn, _, areaStrength, _, areaOwnStrength = ns.GetAreaTintInfo()
		if area then
			text = text .. ("\nThis area: |cffffd100%s|r - %s%s, %d%% strength%s"):format(
				area, areaLabel, areaOwn and " (your choice)" or "", areaStrength * 100 + 0.5,
				areaOwnStrength and " (its own)" or "")
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

	-- Menu of tints for this zone (left out on clients without the dropdown).
	local zoneMenu
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, content, "WowStyle1DropdownTemplate")
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
		zoneMenu:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -10)
	end

	local pickColor = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	pickColor:SetSize(140, 22)
	pickColor:SetText("Pick a colour...")
	if zoneMenu then
		pickColor:SetPoint("LEFT", zoneMenu, "RIGHT", 12, 0)
	else
		pickColor:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -10)
	end
	Tooltip(pickColor, "Choose your own colour for the zone or area chosen above.")
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
		for _, source in ipairs({ db.zoneTints or {}, db.zoneTintStrength or {} }) do
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
				row.text:SetText(("%s: %s%s"):format(zone, label,
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

	-- Vignette
	local vignetteHeader = Header(content, "Vignette", zoneMore, -24)

	local vignette = Check(content, "vignette", "Darken the screen edges",
		"Soft dark edges that draw the eye to the middle. Works with any tint.", function(value)
			ns.GetDB().vignette = value
			ns.RefreshTint()
		end)
	vignette:SetPoint("TOPLEFT", vignetteHeader, "BOTTOMLEFT", -2, -6)

	local vignetteStrength = Slider(content, "vignetteStrength", "Vignette strength", 10, 100, 5, "%d%%", 100,
		ns.RefreshTint)
	vignetteStrength:SetPoint("TOPLEFT", vignette, "BOTTOMLEFT", 4, -26)

	-- World: names, nameplates, tooltips
	local worldHeader = Header(content, "World", vignetteStrength, -24)
	worldHeader:SetPoint("TOPLEFT", vignetteStrength, "BOTTOMLEFT", -2, -24)

	local names = Check(content, "hideNames", "Hide names in cinematic mode",
		"Hides player, NPC, pet and your own names while the UI is faded. " ..
		"Your name settings are restored when the UI comes back.")
	names:SetPoint("TOPLEFT", worldHeader, "BOTTOMLEFT", -2, -6)

	local plates = Check(content, "hidePlates", "Hide nameplates in cinematic mode",
		"Fades out enemy and friendly nameplates along with the UI. " ..
		"They fade back in the moment combat starts.")
	plates:SetPoint("TOPLEFT", names, "BOTTOMLEFT", 0, -2)

	local tooltip = Check(content, "fadeTooltip", "Hide world tooltips",
		"Hides the tooltip for players, NPCs and objects you mouse over in the world, throughout " ..
		"cinematic mode. Tooltips for UI elements still show. (To hide them only in the camera " ..
		"modes, see the Camera modes page.)")
	tooltip:SetPoint("TOPLEFT", plates, "BOTTOMLEFT", 0, -2)

	local combatText = Check(content, "hideCombatText", "Hide combat text out of combat",
		"No floating damage and healing numbers (like \"+10\" from a heal or regen) in cinematic " ..
		"mode while you're out of combat. They come back the moment a fight starts, and your " ..
		"combat text settings are put back when the UI returns.")
	combatText:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 0, -2)

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
		"back afterwards, even after a crash. The camera mode pages show their own music " ..
		"options too; they're the same settings.")
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

	local freshHeader = Header(content, "Start a fresh song when", musicFade, -24)
	freshHeader:SetPoint("TOPLEFT", musicFade, "BOTTOMLEFT", -2, -24)
	local previous = freshHeader
	for i, item in ipairs({
		{ "musicNewSongOnFlights", "The flight rotation starts",
			"Music is switched off and straight back on as the camera starts rotating on a flight " ..
			"(at takeoff if flight rotation is off), so the game starts a fresh track. Once per " ..
			"flight. Not used while music is muted on flights." },
		{ "musicNewSongWhenIdle", "The standing-still camera starts",
			"Music is switched off and straight back on as the standing-still rotation begins, so " ..
			"the game starts a fresh track. Once each time you stand still (not again after you " ..
			"move the camera)." },
		{ "musicNewSongWhenWalking", "You start RP walking",
			"Music is switched off and straight back on as you set off walking (walk/run key), so " ..
			"the game starts a fresh track. Pausing for less than 20 seconds and walking on " ..
			"doesn't count as a new walk." },
		{ "musicNewSongWhenCozy", "The cozy camera starts",
			"Music is switched off and straight back on as the cozy camera starts (campfire, " ..
			"sitting, dancing...), so the game starts a fresh track. Getting up for less than 20 " ..
			"seconds and settling back down doesn't count as a new spell." },
		{ "musicNewSongWhenAutoRun", "You start auto-running",
			"Music is switched off and straight back on as you start auto-running, so the game " ..
			"starts a fresh track. Stopping for less than 20 seconds and running on doesn't count " ..
			"as a new run." },
	}) do
		local check = Check(content, item[1], item[2], item[3])
		check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
		DependsOnMusic(check)
		previous = check
	end

	local fatigueHeader = Header(content, "Fatigue", previous, -18)
	fatigueHeader:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 2, -18)

	local fatigue = Slider(content, "musicFatigue", "Music fatigue", 0, 30, 1, "%d min")
	fatigue:SetPoint("TOPLEFT", fatigueHeader, "BOTTOMLEFT", 2, -26)
	Tooltip(fatigue, "Once the addon has started music, it won't start it again for this " ..
		"long, so short spells of cinematic mode don't keep restarting it. Music coming " ..
		"back after a mute doesn't count. 0 turns this off.")
	DependsOnMusic(fatigue)

	local fatigueLabel = Label(content, "GameFontHighlight", "Start music anyway")
	fatigueLabel:SetPoint("TOPLEFT", fatigue, "BOTTOMLEFT", -2, -22)
	previous = fatigueLabel
	for i, override in ipairs({
		{ "fatigueIgnoreOnFlights", "On flights", "Music starts when you take off, even if it played recently." },
		{ "fatigueIgnoreWhenIdle", "When standing still",
			"Music starts once you've stood still for the standing-still delay, even if it played recently." },
		{ "fatigueIgnoreWhenWalking", "When RP walking",
			"Music starts as you walk (walk/run key), even if it played recently." },
		{ "fatigueIgnoreWhenAutoRun", "When auto-running",
			"Music starts as you auto-run, even if it played recently." },
		{ "fatigueIgnoreWhenCozy", "When cozy",
			"Music starts with the cozy camera (campfire, emotes), even if it played recently." },
		{ "fatigueIgnoreNewZone", "When entering a new zone",
			"Music starts in a zone other than the one it last played in, even if it played recently." },
	}) do
		local check = Check(content, override[1], override[2], override[3])
		check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -4 or -2)
		DependsOnMusic(check)
		previous = check
	end

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
		"the standing-still delay.")
	movingMusic:SetPoint("TOPLEFT", flightMusic, "BOTTOMLEFT", 0, -2)
	DependsOnMusic(movingMusic)
	movingMusic:HookScript("OnClick", Refresh) -- grey out / enable the fade below

	local pauseFade = Slider(content, "musicPauseFadeTime", "Pause fade time", 0.5, 10, 0.5, "%.1f sec")
	pauseFade:SetPoint("TOPLEFT", movingMusic, "BOTTOMLEFT", 24, -26)
	Tooltip(pauseFade, "How long the music takes to fade out when you move on, and to fade " ..
		"back in when the next flight, walk or standing-still spell starts.")
	GreyUnless(pauseFade, function(db) return db.musicInCinematic and db.musicPauseWhenMoving end)

	-- Back out to the checkboxes' edge for the next heading.
	local pauseFadeEdge = CreateFrame("Frame", nil, content)
	pauseFadeEdge:SetSize(1, 1)
	pauseFadeEdge:SetPoint("TOPLEFT", pauseFade, "BOTTOMLEFT", -24, -4)

	local lastPlace, placeChecks = PlaceList(content, pauseFadeEdge, "Mute music in", "musicOffIn",
		"Music fades out here (your own game music too) and back in when you leave.")
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
		"What happens to cinematic mode when a fight starts. By default the UI comes " ..
		"straight back; you can stay cinematic instead and show just what you need.")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	subtitle:SetJustifyV("TOP")

	-- Left column
	local fightHeader = Header(content, "During fights", subtitle, -20)

	local stayInCombat = Check(content, "stayInCombat", "Stay in cinematic mode in combat",
		"Combat and targeting an enemy no longer bring the UI back. Mouseover still " ..
		"reveals things. Nameplates show during fights, and camera rotation pauses.")
	stayInCombat:SetPoint("TOPLEFT", fightHeader, "BOTTOMLEFT", -2, -6)
	stayInCombat:HookScript("OnClick", Refresh) -- grey out / enable the frames list

	local target = Check(content, "revealOnTarget", "Reveal when targeting an enemy",
		"Bring the UI back when you target something you can attack. Ignored while " ..
		"\"Stay in cinematic mode in combat\" is on.")
	target:SetPoint("TOPLEFT", stayInCombat, "BOTTOMLEFT", 0, -2)

	local ignoreDead = Check(content, "ignoreDeadTarget", "Ignore dead targets",
		"Targeting a dead enemy (say, to loot it) doesn't bring the UI back with " ..
		"\"Reveal when targeting an enemy\". (For the frame lists below, dead enemies " ..
		"count as \"anything else\".)")
	ignoreDead:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -2)

	-- A greyed-out-unless-staying list of frame checkboxes for one situation.
	local function FrameList(header, isOn, tableKey, needsStay)
		local previous = header
		for i, item in ipairs(ns.COMBAT_SHOW) do
			local check = Check(content, tableKey, item.label, nil, function(value)
				ns.GetDB()[tableKey][item.key] = value
			end)
			check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
			check.Refresh = function(self)
				local db = ns.GetDB()
				self:SetChecked(isOn(item.key))
				local enabled = not needsStay or db.stayInCombat
				self:SetEnabled(enabled)
				local label = self.Text or self.text
				if label then
					label:SetFontObject(enabled and "GameFontHighlight" or "GameFontDisable")
				end
			end
			previous = check
		end
		return previous
	end

	-- A frame list with a header, help text and its own fade sliders.
	local function Section(anchor, x, y, title, help, isOn, tableKey, needsStay, fadeInKey, fadeOutKey, fadeInMax, fadeInLabel, fadeOutLabel)
		local header = Label(content, "GameFontNormal", title)
		header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
		local helpText = Label(content, "GameFontHighlightSmall", help)
		helpText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
		helpText:SetWidth(270)
		helpText:SetJustifyV("TOP")
		local last = FrameList(helpText, isOn, tableKey, needsStay)
		local fadeIn = Slider(content, fadeInKey, fadeInLabel, 0, fadeInMax, 0.05, "%.2f sec")
		fadeIn:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 4, -30)
		local fadeOut = Slider(content, fadeOutKey, fadeOutLabel, 0, 30, 0.5, "%.1f sec")
		fadeOut:SetPoint("TOPLEFT", fadeIn, "BOTTOMLEFT", 0, -34)
		return header, fadeIn, fadeOut
	end

	-- Left column, below the fight settings: an enemy targeted, out of combat
	local _, enemyIn = Section(ignoreDead, 2, -18, "When you target an enemy, show",
		"A living enemy you can attack, while you're not in combat yet. Once a fight " ..
		"starts, the in-combat list applies.",
		ns.IsEnemyShowOn, "enemyShow", false, "enemyFadeInTime", "enemyFadeOutTime", 5,
		"Fade in", "Fade out")
	Tooltip(enemyIn, "How fast the frames ticked above appear when you target an enemy.")

	-- Right column: in combat, then a friend targeted
	local combatHeader, fadeIn, fadeOut = Section(fightHeader, 0, 0, "In combat, show",
		"While you're in combat and staying cinematic.",
		ns.IsCombatShowOn, "combatShow", true, "combatFadeInTime", "combatFadeOutTime", 3,
		"Fade in when a fight starts", "Fade out after a fight")
	combatHeader:ClearAllPoints()
	combatHeader:SetPoint("TOPLEFT", fightHeader, "TOPLEFT", 320, 0)
	Tooltip(fadeIn, "How fast the frames ticked above appear when you enter combat. 0 is instant.")
	Tooltip(fadeOut, "How fast those frames fade away again once the fight is over.")

	local _, friendIn = Section(fadeOut, -6, -24, "When you target anything else, show",
		"Friends, NPCs, other players and dead enemies (say, a corpse you're looting), " ..
		"while you're not in combat.",
		ns.IsFriendlyShowOn, "friendlyShow", false, "friendlyFadeInTime", "friendlyFadeOutTime", 5,
		"Fade in", "Fade out")
	Tooltip(friendIn, "How fast the frames ticked above appear when you target anything else.")

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Combat")
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
	local previous, lastGroup, previousIsHeader = keepPanel.alwaysMinimap, nil, false
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
			content.alwaysMinimap:Refresh()
			RefreshKeep()
			RefreshExtras()
		end
	end, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Frames")
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
CreateRevealPanel()
CreateCameraPanel()
CreateFlightPanel()
CreateStandingPanel()
CreateCozyPanel()
CreateWalkPanel()
CreateAutoRunPanel()
CreateCombatPanel()
CreateAudioPanel()
CreateChatPanel()
CreateTintPanel()
CreateFramesPanel()
