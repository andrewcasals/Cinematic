-- Cinematic minimap button: left-click for a quick menu, right-click for the
-- settings, drag to move it around the minimap's edge.
--
-- The minimap shrinks to almost nothing while fully faded, so the button isn't
-- attached to it. It lives on UIParent and is moved to the minimap's edge
-- whenever the minimap is at full size. It's in the minimap fade group, so it
-- fades with the minimap and hovering it reveals the minimap.
local _, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local EDGE_OFFSET = 10 -- how far outside the minimap's rim the button sits
local button

local function Print(msg)
	ns.Print(msg)
end

local function UpdatePosition()
	local db = ns.GetDB()
	if not button or not db or Minimap:GetScale() < 0.5 then
		return -- minimap is shrunk while faded; keep the last good position
	end
	local mx, my = Minimap:GetCenter()
	if not mx then
		return
	end
	local minimapScale, buttonScale = Minimap:GetEffectiveScale(), button:GetEffectiveScale()
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
	button:SetShown(db.minimapButton)
end

local function FormatTime(seconds)
	if seconds == math.huge then
		return "until logout"
	end
	return ("%d:%02d left"):format(math.floor(seconds / 60), math.floor(seconds % 60))
end

local STRENGTHS = { 0, 0.25, 0.5, 0.75, 1 }
local VIGNETTE_STRENGTHS = { 0, 0.1, 0.15, 0.25, 0.5, 0.75, 1 }

-- Strength choices: the same fixed steps everywhere (finer values are set with
-- the sliders in settings). Compared as whole percents (slider values aren't exact).
local function Percent(value)
	return value and math.floor(value * 100 + 0.5)
end

local function AddStrengthChoices(menu, get, set, defaultLabel, choices)
	if defaultLabel then
		menu:CreateRadio(defaultLabel, function() return get() == nil end, function() set(nil) end)
	end
	for _, value in ipairs(choices or STRENGTHS) do
		menu:CreateRadio(("%d%%"):format(Percent(value)),
			function() return Percent(get()) == Percent(value) end, function() set(value) end)
	end
end

-- Screen tint section: tint and vignette on/off and their strengths. Presets,
-- colours and the rest are in settings. Switching the tint off sets the main
-- preset to None and remembers the old one for switching it back on.
local function AddTintMenu(root, db)
	local tint = root
	tint:CreateDivider()
	tint:CreateTitle("Screen tint")

	tint:CreateCheckbox("Tint", function() return db.tintPreset ~= "none" end, function()
		if db.tintPreset == "none" then
			db.tintPreset = db.tintPresetBeforeOff or ns.DEFAULTS.tintPreset
			db.tintPresetBeforeOff = nil
		else
			db.tintPresetBeforeOff = db.tintPreset
			db.tintPreset = "none"
		end
		ns.RefreshTint()
	end)
	local strength = tint:CreateButton("Tint strength")
	AddStrengthChoices(strength, function() return db.tintStrength end, function(value)
		db.tintStrength = value
		ns.RefreshTint()
	end)

	tint:CreateCheckbox("Vignette", function() return db.vignette end, function()
		db.vignette = not db.vignette
		ns.RefreshTint()
	end)
	local vignetteStrength = tint:CreateButton("Vignette strength")
	AddStrengthChoices(vignetteStrength, function() return db.vignetteStrength end, function(value)
		db.vignetteStrength = value
		db.vignette = true -- picking a strength means you want it on
		ns.RefreshTint()
	end, nil, VIGNETTE_STRENGTHS)
end

-- Camera section: a submenu to switch each camera mode's zoom on or off.
local CAMERA_ZOOMS = {
	{ "Flight camera", "taxiZoom" },
	{ "AFK camera", "idleZoom" },
	{ "Cozy camera", "cozyZoom" },
	{ "Tele camera", "teleZoom" },
	{ "Vista camera", "vistaZoom" },
	{ "Fish camera", "fishZoom" },
	{ "RP walk camera", "walkZoom" },
	{ "Auto-run camera", "runZoom" },
}

local function AddCameraMenu(root, db)
	root:CreateDivider()
	root:CreateTitle("Camera")
	local zoom = root:CreateButton("Zoom")
	for _, mode in ipairs(CAMERA_ZOOMS) do
		zoom:CreateCheckbox(mode[1], function() return db[mode[2]] end,
			function() db[mode[2]] = not db[mode[2]] end)
	end
	root:CreateCheckbox("Pause music when you move on", function() return db.musicPauseWhenMoving end,
		function() db.musicPauseWhenMoving = not db.musicPauseWhenMoving end)
	root:CreateCheckbox("Pause music when a flight lands", function() return db.musicPauseOnLanding end,
		function() db.musicPauseOnLanding = not db.musicPauseOnLanding end)
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
		root:CreateTitle("Cinematic")
		root:CreateCheckbox("Enabled", function() return db.enabled end, function()
			ns.SetEnabled(not db.enabled)
			UpdateIcon()
		end)

		local left = ns.GetSnoozeLeft()
		if left then
			root:CreateButton("Turn back on now (" .. FormatTime(left) .. ")", function()
				ns.Unsnooze()
				UpdateIcon()
			end)
		else
			root:CreateButton("Turn off for 10 minutes", function()
				ns.Snooze(600)
				UpdateIcon()
			end)
			root:CreateButton("Turn off until logout", function()
				ns.Snooze(math.huge)
				UpdateIcon()
			end)
		end

		root:CreateDivider()
		root:CreateCheckbox("Stay in cinematic mode in combat",
			function() return db.stayInCombat end,
			function() db.stayInCombat = not db.stayInCombat end)
		root:CreateCheckbox("Always show the minimap",
			function() return db.alwaysShowMinimap end,
			function() db.alwaysShowMinimap = not db.alwaysShowMinimap end)
		root:CreateCheckbox("Keep minimap open while tracking",
			function() return db.minimapForTracking end,
			function() db.minimapForTracking = not db.minimapForTracking end)
		AddCameraMenu(root, db)
		AddTintMenu(root, db)
		root:CreateDivider()
		root:CreateButton("Open settings", ns.OpenOptions)
		root:CreateButton("Hide this button", function()
			db.minimapButton = false
			UpdateIcon()
			Print("minimap button hidden. Bring it back with /cine button or the " ..
				"\"Show minimap button\" option.")
		end)
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
	if not db.enabled then
		GameTooltip:AddLine("Off", 1, 0.3, 0.3)
	elseif left then
		GameTooltip:AddLine("Paused, " .. FormatTime(left), 1, 0.8, 0.2)
	else
		GameTooltip:AddLine("On", 0.3, 1, 0.3)
	end
	GameTooltip:AddLine("Left-click: options", 1, 1, 1)
	GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
	GameTooltip:AddLine("Drag: move", 1, 1, 1)
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
	button = CreateFrame("Button", "CinematicMinimapButton", UIParent)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
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

	button:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
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

	UpdatePosition()
	UpdateIcon()
end

-- Called by Core: at login, and on its regular scan so the button follows the
-- minimap if it moves (and the icon catches a pause running out).
function ns.UpdateMinimapButton()
	if not button then
		Create()
	end
	UpdatePosition()
	UpdateIcon()
end

function ns.ToggleMinimapButton()
	local db = ns.GetDB()
	db.minimapButton = not db.minimapButton
	ns.UpdateMinimapButton()
	Print("minimap button " .. (db.minimapButton and "shown" or "hidden"))
end
