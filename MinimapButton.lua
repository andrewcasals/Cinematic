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

local STRENGTHS = { 0.25, 0.5, 0.75, 1 }
local VIGNETTE_STRENGTHS = { 0.1, 0.15, 0.25, 0.5, 0.75, 1 }

-- Strength choices: the usual steps plus the current value if it's between
-- them. Compared as whole percents (slider values aren't exact).
local function Percent(value)
	return value and math.floor(value * 100 + 0.5)
end

local function AddStrengthChoices(menu, get, set, defaultLabel, choices)
	if defaultLabel then
		menu:CreateRadio(defaultLabel, function() return get() == nil end, function() set(nil) end)
	end
	local current, steps, seen = Percent(get()), {}, {}
	for _, value in ipairs(choices or STRENGTHS) do
		steps[#steps + 1] = value
		seen[Percent(value)] = true
	end
	if current and not seen[current] then
		steps[#steps + 1] = current / 100
		table.sort(steps)
	end
	for _, value in ipairs(steps) do
		menu:CreateRadio(("%d%%"):format(Percent(value)),
			function() return Percent(get()) == Percent(value) end, function() set(value) end)
	end
end

-- Screen tint section, right in the main menu so nothing nests more than one
-- level deep (deeper menus flip sides near the screen edge and overlap).
-- With a Zone preset on, the colour and strength choices change only the
-- zone you're standing in.
local function AddTintMenu(root, db)
	local tint = root
	tint:CreateDivider()
	tint:CreateTitle("Screen tint")

	local presetMenu = tint:CreateButton("Preset")
	for _, preset in ipairs(ns.TINT_PRESETS) do
		presetMenu:CreateRadio(preset.label, function() return db.tintPreset == preset.key end,
			function()
				db.tintPreset = preset.key
				ns.RefreshTint()
			end)
	end

	local zone = GetRealZoneText() or ""
	if (db.tintPreset == "zone" or db.tintPreset == "zonetime") and zone ~= "" then
		local current = function() return db.zoneTints[zone] end
		local mood = tint:CreateButton(zone .. " colour")
		mood:CreateRadio("Built-in mood", function() return current() == nil end,
			function() ns.SetZoneTint(zone, nil) end)
		mood:CreateRadio("No tint", function() return current() == "none" end,
			function() ns.SetZoneTint(zone, "none") end)
		for _, entry in ipairs(ns.GetZoneMoods()) do
			local hex = ("|cff%02x%02x%02x"):format(entry.color[1] * 255, entry.color[2] * 255, entry.color[3] * 255)
			mood:CreateRadio(hex .. entry.label .. "|r", function() return current() == entry.key end,
				function() ns.SetZoneTint(zone, entry.key) end)
		end
		if ns.OpenColorPicker then
			mood:CreateButton("Pick a colour...", function()
				local _, _, _, color = ns.GetZoneTintInfo(zone)
				ns.OpenColorPicker(color[1], color[2], color[3], function(r, g, b)
					ns.SetZoneTint(zone, { r, g, b })
				end)
			end)
		end
		local strength = tint:CreateButton(zone .. " strength")
		AddStrengthChoices(strength,
			function() return db.zoneTintStrength[zone] end,
			function(value) ns.SetZoneTintStrength(zone, value) end,
			("Main strength (%d%%)"):format(db.tintStrength * 100 + 0.5))

		-- The area you're in (a town, a port): its own colour and strength.
		local area, _, _, _, _, areaDefault = ns.GetAreaTintInfo()
		if area then
			local areaCurrent = function() return db.zoneTints[area] end
			local areaMood = tint:CreateButton(area .. " colour")
			areaMood:CreateRadio("Same as the zone", function() return areaCurrent() == nil end,
				function() ns.SetZoneTint(area, nil) end)
			areaMood:CreateRadio("No tint", function() return areaCurrent() == "none" end,
				function() ns.SetZoneTint(area, "none") end)
			for _, entry in ipairs(ns.GetZoneMoods()) do
				local hex = ("|cff%02x%02x%02x"):format(entry.color[1] * 255, entry.color[2] * 255, entry.color[3] * 255)
				areaMood:CreateRadio(hex .. entry.label .. "|r", function() return areaCurrent() == entry.key end,
					function() ns.SetZoneTint(area, entry.key) end)
			end
			if ns.OpenColorPicker then
				areaMood:CreateButton("Pick a colour...", function()
					local _, _, _, color = ns.GetAreaTintInfo()
					ns.OpenColorPicker(color[1], color[2], color[3], function(r, g, b)
						ns.SetZoneTint(area, { r, g, b })
					end)
				end)
			end
			local areaStrength = tint:CreateButton(area .. " strength")
			AddStrengthChoices(areaStrength,
				function() return db.zoneTintStrength[area] end,
				function(value) ns.SetZoneTintStrength(area, value) end,
				("Area default (%d%%)"):format(areaDefault * 100 + 0.5))
		end
	elseif db.tintPreset ~= "none" then
		local strength = tint:CreateButton("Strength")
		AddStrengthChoices(strength, function() return db.tintStrength end, function(value)
			db.tintStrength = value
			ns.RefreshTint()
		end)
		if db.tintPreset == "custom" and ns.OpenColorPicker then
			tint:CreateButton("Pick custom colour...", function()
				ns.OpenColorPicker(db.tintCustomR, db.tintCustomG, db.tintCustomB, function(r, g, b)
					db.tintCustomR, db.tintCustomG, db.tintCustomB = r, g, b
					ns.RefreshTint()
				end)
			end)
		end
	end

	if db.tintPreset == "timeofday" or db.tintPreset == "zonetime" then
		local timeStrength = tint:CreateButton("Time of day strength")
		AddStrengthChoices(timeStrength, function() return db.timeTintStrength end, function(value)
			db.timeTintStrength = value
			ns.RefreshTint()
		end)
		-- Clicking a phase previews it and opens the colour picker.
		local colours = tint:CreateButton("Phase colours")
		local anyOwn = false
		for _, phase in ipairs(ns.GetTimePhases()) do
			anyOwn = anyOwn or phase.own
			local hex = ("|cff%02x%02x%02x"):format(phase.color[1] * 255, phase.color[2] * 255, phase.color[3] * 255)
			colours:CreateButton(hex .. phase.name .. "|r" .. (phase.own and " (yours)" or ""), function()
				ns.PreviewTintHour(phase.hour)
				if ns.OpenColorPicker then
					ns.OpenColorPicker(phase.color[1], phase.color[2], phase.color[3], function(r, g, b)
						ns.SetTimePhaseColor(phase.name, { r, g, b })
						ns.PreviewTintHour(phase.hour) -- keep showing it while you pick
					end)
				end
			end)
		end
		if anyOwn then
			colours:CreateDivider()
			colours:CreateButton("Reset all to built-in", function()
				for _, phase in ipairs(ns.GetTimePhases()) do ns.SetTimePhaseColor(phase.name, nil) end
			end)
		end
		-- One level only: each phase's choices under its own heading.
		local phaseStrength = tint:CreateButton("Phase strength")
		for i, phase in ipairs(ns.GetTimePhases()) do
			if i > 1 then phaseStrength:CreateDivider() end
			phaseStrength:CreateTitle(phase.name)
			AddStrengthChoices(phaseStrength,
				function()
					return phase.strength
				end,
				function(value)
					ns.SetTimePhaseStrength(phase.name, value)
					ns.PreviewTintHour(phase.hour)
				end)
		end
		local preview = tint:CreateButton("Preview time of day")
		for _, phase in ipairs(ns.GetTimePhases()) do
			preview:CreateButton(("%s (%02d:00)"):format(phase.name, phase.hour),
				function() ns.PreviewTintHour(phase.hour) end)
		end
		local clock = tint:CreateButton("Time of day clock")
		clock:CreateRadio("Game time", function() return db.tintClock ~= "local" end, function()
			db.tintClock = "game"
			ns.RefreshTint()
		end)
		clock:CreateRadio("Your computer's clock", function() return db.tintClock == "local" end, function()
			db.tintClock = "local"
			ns.RefreshTint()
		end)
	end

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

-- Camera section: quick on/off for each camera mode (one level deep).
local CAMERA_MODES = {
	{ "Flight camera", "taxiOrbit", "taxiZoom" },
	{ "Standing still camera", "idleOrbit", "idleZoom" },
	{ "Cozy camera", "cozyOrbit", "cozyZoom" },
	{ "RP walk camera", "walkOrbit", "walkZoom" },
	{ "Auto-run camera", "runOrbit", "runZoom" },
}

local function AddCameraMenu(root, db)
	root:CreateDivider()
	root:CreateTitle("Camera")
	for _, mode in ipairs(CAMERA_MODES) do
		root:CreateCheckbox(mode[1], function() return db[mode[2]] end,
			function() db[mode[2]] = not db[mode[2]] end)
	end
	local zoom = root:CreateButton("Zoom")
	for _, mode in ipairs(CAMERA_MODES) do
		zoom:CreateCheckbox(mode[1], function() return db[mode[3]] end,
			function() db[mode[3]] = not db[mode[3]] end)
	end
	root:CreateCheckbox("Pause music when you move on", function() return db.musicPauseWhenMoving end,
		function() db.musicPauseWhenMoving = not db.musicPauseWhenMoving end)
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
