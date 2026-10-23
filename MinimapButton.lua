-- Cinematic minimap button: left-click for a quick menu, right-click for the
-- settings, drag to move it around the minimap's edge.
--
-- The minimap shrinks to almost nothing while fully faded, so the button isn't
-- attached to it. It lives on UIParent and is moved to the minimap's edge
-- whenever the minimap is at full size. It's in the minimap fade group, so it
-- fades with the minimap and hovering it reveals the minimap.
local _, ns = ...
local L = ns.L

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local EDGE_OFFSET = 10 -- how far outside the minimap's rim the button sits
local button
-- With EllesmereUI's minimap, the button is the minimap's child instead, so its
-- button drawer collects it (it only takes the minimap's own children). It's
-- then anchored to the minimap and left alone, as EllesmereUI lays it out.
local onMinimap

local function Print(msg)
	ns.Print(msg)
end

-- The visions: while one is in use (doing something now, not just switched
-- on), the button glows in its colour, and the menu and tooltip list it with
-- a link to its page, with its icon (as the vision wheel has them). Not
-- with the Vision page's Vision Helper (minimapVisions) unticked.
-- active: its file's ns function saying so. trim: an icon's edge cut off.
local VISIONS = {
	{ label = "Heal Vision", page = "Heal Vision", active = "HealVisionActive", color = { 0.35, 1, 0.45 },
		icon = "Interface\\Icons\\Spell_Holy_FlashHeal", trim = true },
	{ label = "Quest Vision", page = "Quest Vision", active = "QuestVisionActive", color = { 1, 0.82, 0 },
		icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", trim = true },
	{ label = "Duel Vision", page = "Vision", active = "DuelVisionActive", color = { 1, 0.35, 0.3 },
		icon = "Interface\\Icons\\Ability_DualWield", trim = true },
	{ label = "Roll Vision", page = "Roll Vision", active = "RollVisionActive", color = { 0.45, 0.7, 1 },
		icon = "Interface\\Icons\\INV_Misc_Dice_01", trim = true },
}
local GLOW_EVERY = 0.5 -- seconds between looks at which are in use
local inUse = {} -- the visions in use at the last look

-- A vision's line in the menu and tooltip (text: its label, or a line with
-- it): its icon, then the text in its colour.
local function VisionText(vision, text)
	local icon = vision.trim and "|T%s:16:16:0:0:64:64:5:59:5:59|t " or "|T%s:16:16|t "
	local function Byte(value) return math.floor(value * 255 + 0.5) end
	local color = vision.color
	return icon:format(vision.icon) .. ("|cff%02x%02x%02x%s|r"):format(Byte(color[1]), Byte(color[2]),
		Byte(color[3]), text)
end

local function UpdateInUse()
	wipe(inUse)
	for _, vision in ipairs(ns.Setting("minimapVisions") and VISIONS or {}) do
		local Active = ns[vision.active]
		if Active then
			local ok, active = pcall(Active)
			if ok and active then
				inUse[#inUse + 1] = vision
			end
		end
	end
	local glow = button.glow
	local first = inUse[1]
	if first then
		if glow.vision ~= first then
			glow.vision = first
			glow.texture:SetVertexColor(first.color[1], first.color[2], first.color[3])
		end
		if not glow:IsShown() then
			glow:Show()
			glow.pulse:Play()
		end
	elseif glow:IsShown() then
		glow.pulse:Stop()
		glow:Hide()
	end
end

local function UpdatePosition()
	local db = ns.GetDB()
	if not button or not db then
		return
	end
	if onMinimap then
		local radius = Minimap:GetWidth() / 2 + EDGE_OFFSET
		local angle = math.rad(db.minimapAngle)
		button:ClearAllPoints()
		button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
		return
	end
	if Minimap:GetScale() < 0.5 then
		return -- minimap is shrunk while faded; keep the last good position
	end
	local mx, my = Minimap:GetCenter()
	if not mx then
		return
	end
	local minimapScale, buttonScale = Minimap:GetEffectiveScale(), button:GetEffectiveScale()
	-- Faded but kept full size (a Reveal tick, Minimap page), the minimap is
	-- moved off the screen: following it there left the button gone after it
	-- came back, until the next scan. Keep the last good position.
	local uiScale = UIParent:GetEffectiveScale()
	if mx * minimapScale / uiScale > UIParent:GetWidth() then
		return
	end
	local radius = (Minimap:GetWidth() / 2) * minimapScale / buttonScale + EDGE_OFFSET
	local cx, cy = mx * minimapScale / buttonScale, my * minimapScale / buttonScale
	local angle = math.rad(db.minimapAngle)
	button:ClearAllPoints()
	button:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
		cx + math.cos(angle) * radius, cy + math.sin(angle) * radius)
end

local function UpdateIcon()
	local db = ns.GetDB()
	local active = db.enabled and not ns.GetSnoozeLeft()
	button.icon:SetDesaturated(not active)
	-- (Not in gamepad mode with hideMinimapButtonGamepad: clicking it there
	-- tends to freeze WoW Forever.)
	local shown = db.minimapButton and not (db.hideMinimapButtonGamepad and ns.IsGamePadOn())
	if not onMinimap then
		button:SetShown(shown)
	elseif shown ~= button.wanted then
		-- Only on a change, and with Show/Hide, which EllesmereUI follows: it
		-- hides drawer buttons itself.
		button.wanted = shown
		if shown then button:Show() else button:Hide() end
	end
end

local function FormatTime(seconds)
	if seconds == math.huge then
		return L["until logout"]
	end
	return (L["%d:%02d left"]):format(math.floor(seconds / 60), math.floor(seconds % 60))
end

local STRENGTHS = { 0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1 }

-- Strength choices: fixed steps (finer values are set with the sliders in
-- settings). Compared as whole percents (slider values aren't exact).
local function Percent(value)
	return value and math.floor(value * 100 + 0.5)
end

local function AddStrengthChoices(menu, get, set)
	for _, value in ipairs(STRENGTHS) do
		menu:CreateRadio(("%d%%"):format(Percent(value)),
			function() return Percent(get()) == Percent(value) end, function() set(value) end)
	end
end

-- VFX section: tint strength, 0% being off. Presets, colours, the
-- vignette and the rest are in settings. A strength above 0% also brings back
-- a tint preset that was switched off in settings.
local function AddTintMenu(root, db)
	root:CreateDivider()
	root:CreateTitle("VFX")

	local strength = root:CreateButton(L["Tint"])
	AddStrengthChoices(strength, function()
		return db.tintPreset == "none" and 0 or db.tintStrength
	end, function(value)
		db.tintStrength = value
		if value > 0 and db.tintPreset == "none" then
			db.tintPreset = db.tintPresetBeforeOff or ns.DEFAULTS.tintPreset
			db.tintPresetBeforeOff = nil
		end
		ns.RefreshTint()
	end)
end

-- Audio section: the Audio page's master music switch.
local function AddAudioMenu(root, db)
	root:CreateDivider()
	root:CreateTitle(L["Audio"])
	root:CreateCheckbox(L["Enable page"], function() return db.musicInCinematic end,
		function() db.musicInCinematic = not db.musicInCinematic end)
end

local MENU_MARGIN = 12 -- pixels between the menu and the screen edges

local function KeepOffEdges(menu)
	if not menu:IsShown() then
		return
	end
	local left, bottom, width, height = menu:GetRect()
	if not left then
		return
	end
	local scale = menu:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local screenW, screenH = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
	local dx, dy = 0, 0
	if left + width > screenW - MENU_MARGIN then dx = screenW - MENU_MARGIN - (left + width) end
	if left + dx < MENU_MARGIN then dx = MENU_MARGIN - left end
	if bottom < MENU_MARGIN then dy = MENU_MARGIN - bottom end
	if bottom + height + dy > screenH - MENU_MARGIN then dy = screenH - MENU_MARGIN - (bottom + height) end
	if dx ~= 0 or dy ~= 0 then
		menu:ClearAllPoints()
		-- (Offsets are in the menu's own scale, like its rect.)
		menu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + dx, bottom + dy)
	end
end

local function ShowMenu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		-- No menu system on this client: just toggle.
		ns.SetEnabled(not ns.GetDB().enabled)
		UpdateIcon()
		return
	end
	local menu = MenuUtil.CreateContextMenu(owner, function(_, root)
		local db = ns.GetDB()
		-- (The visions in use first, each a link to its page.)
		UpdateInUse()
		if inUse[1] then
			root:CreateTitle(L["Visions in use"])
			for _, vision in ipairs(inUse) do
				local page = vision.page
				root:CreateButton(VisionText(vision, L[vision.label]), function() ns.OpenOptions(page) end)
			end
			-- (Ticked whenever it shows: unticking turns this all off.)
			root:CreateCheckbox(L["Vision Helper"], function() return ns.Setting("minimapVisions") end, function()
				ns.GetDB().minimapVisions = false
				UpdateInUse()
				if ns.RefreshOptions then ns.RefreshOptions() end
				Print(L["Vision Helper off. Turn it back on on the Vision page."])
			end)
			root:CreateDivider()
		end
		root:CreateTitle("Cinematic")
		root:CreateCheckbox(L["Enable Cinematic"], function() return db.enabled end, function()
			ns.SetEnabled(not db.enabled)
			UpdateIcon()
		end)
		-- (Ticked whenever the menu is open: unticking hides the button.)
		root:CreateCheckbox(L["Show minimap button"], function() return db.minimapButton end, function()
			db.minimapButton = false
			UpdateIcon()
			Print(L["minimap button hidden. Bring it back with /cine button or the " ..
				"\"Show minimap button\" option."])
		end)
		-- (The CineMode page's "Turn off in: Combat": stored the other way round.)
		root:CreateCheckbox(L["Turn off in combat"],
			function() return not db.stayInCombat end,
			function() db.stayInCombat = not db.stayInCombat end)
		AddAudioMenu(root, db)
		AddTintMenu(root, db)
		root:CreateDivider()
		root:CreateButton(L["Open settings"], ns.OpenOptions)
	end)
	-- The menu opens at the cursor and is only kept on screen; keep it a little
	-- way off the edges too. (Once it has its size, a frame later.)
	if menu and menu.GetRect then
		C_Timer.After(0, function() KeepOffEdges(menu) end)
	end
end

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Cinematic")
	local db = ns.GetDB()
	local left = ns.GetSnoozeLeft()
	-- (No profile picked yet: Cinematic does nothing, and a click opens the welcome window.)
	if not ns.ProfileChosen() then
		GameTooltip:AddLine(L["No profile yet"], 1, 0.5, 0)
		GameTooltip:AddLine(L["Click: pick a profile"], 1, 1, 1)
		if not onMinimap then
			GameTooltip:AddLine(L["Drag: move"], 1, 1, 1)
		end
		GameTooltip:Show()
		return
	end
	if not db.enabled then
		GameTooltip:AddLine(L["Off"], 1, 0.3, 0.3)
	elseif left then
		GameTooltip:AddLine(L["Paused, %s"]:format(FormatTime(left)), 1, 0.8, 0.2)
	else
		GameTooltip:AddLine(L["On"], 0.3, 1, 0.3)
	end
	for _, vision in ipairs(inUse) do
		GameTooltip:AddLine(VisionText(vision, L["%s in use"]:format(L[vision.label])))
	end
	GameTooltip:AddLine(L["Left-click: options"], 1, 1, 1)
	GameTooltip:AddLine(L["Right-click: settings"], 1, 1, 1)
	if not onMinimap then
		GameTooltip:AddLine(L["Drag: move"], 1, 1, 1)
	end
	GameTooltip:Show()
end

-- Dragging moves the button around the minimap's rim.
local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	if not mx then
		return
	end
	local scale = Minimap:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = x / scale, y / scale
	ns.GetDB().minimapAngle = math.deg(math.atan2(y - my, x - mx))
	UpdatePosition()
end

local function Create()
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	onMinimap = isLoaded("EllesmereUIMinimap") and true or false
	button = CreateFrame("Button", "CinematicMinimapButton", onMinimap and Minimap or UIParent)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	if not onMinimap then -- (EllesmereUI places it: dragging would pull it out of the drawer)
		button:RegisterForDrag("LeftButton")
	end
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetTexture(ICON)
	button.icon:SetSize(17, 17)
	button.icon:SetPoint("TOPLEFT", 7, -6)
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	-- The glow while a vision is in use: a pulsing light over the icon and
	-- rim, in the vision's colour. (The pulse is on a frame of its own: a
	-- texture's vertex colour alpha is its alpha.)
	local glow = CreateFrame("Frame", nil, button)
	glow:SetAllPoints()
	glow:Hide()
	glow.texture = glow:CreateTexture(nil, "OVERLAY")
	glow.texture:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	glow.texture:SetBlendMode("ADD")
	glow.texture:SetSize(38, 38)
	glow.texture:SetPoint("CENTER", button.icon, "CENTER")
	glow.pulse = glow:CreateAnimationGroup()
	glow.pulse:SetLooping("BOUNCE")
	local fade = glow.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.9)
	fade:SetSmoothing("IN_OUT")
	button.glow = glow

	button:SetScript("OnClick", function(self, mouseButton)
		GameTooltip:Hide()
		if not ns.ProfileChosen() then
			ns.ShowWelcome()
		elseif mouseButton == "RightButton" then
			ns.OpenOptions()
		else
			ShowMenu(self)
		end
	end)
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	-- (A timer of its own: the drag has the button's OnUpdate.)
	C_Timer.NewTicker(GLOW_EVERY, function()
		if button:IsVisible() or glow:IsShown() then
			UpdateInUse()
		end
	end)

	UpdatePosition()
	UpdateIcon()
end

-- Called by Core: at login, and on its regular scan so the button follows the
-- minimap if it moves (and the icon catches a pause running out).
function ns.UpdateMinimapButton()
	if not button then
		Create()
	elseif not onMinimap then
		UpdatePosition()
	end
	UpdateIcon()
end

function ns.ToggleMinimapButton()
	local db = ns.GetDB()
	db.minimapButton = not db.minimapButton
	ns.UpdateMinimapButton()
	Print(db.minimapButton and L["minimap button shown"] or L["minimap button hidden"])
end
