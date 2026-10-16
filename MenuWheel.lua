-- Cinematic: the menu wheel. Like the camera wheel, but its icons are the
-- game's micro menu buttons (character, spellbook, quest log...), so its
-- windows are in reach with the UI hidden. Holding its key brings up the ring
-- round the cursor: point at one and let go to open that window. Letting go
-- in the middle leaves the wheel up to click one; clicking elsewhere, Escape
-- or the key again puts it away.
--
-- It mirrors the bar: only the buttons the game shows on this client, in the
-- bar's order. A pick clicks the real button through a secure button (as if
-- you'd clicked it yourself), so the windows it opens aren't tainted. It
-- works in a fight too: opening, picking and closing run as secure snippets
-- (the only code that may show or click secure frames then), and the ring is
-- laid out before the fight. Our own code only draws: names, glow, fade.
local ADDON_NAME, ns = ...
local L = ns.L

-- Each button the game might have (in the bar's order, for a client whose
-- buttons have no layoutIndex). The wheel shows the button's own art; our
-- icon is for one that has none.
local BUTTONS = {
	-- (On Classic this one acts on mouse down/up, not a click: where it has no
	-- OnClick, the slot opens the window itself.)
	{ name = "CharacterMicroButton", portrait = true, open = function() ToggleCharacter("PaperDollFrame") end },
	{ name = "ProfessionMicroButton", icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ name = "PlayerSpellsMicroButton", icon = "Interface\\Icons\\INV_Misc_Book_09" },
	{ name = "SpellbookMicroButton", icon = "Interface\\Icons\\INV_Misc_Book_09" },
	{ name = "TalentMicroButton", icon = "Interface\\Icons\\Ability_Marksmanship" },
	{ name = "AchievementMicroButton", icon = "Interface\\Icons\\Achievement_General" },
	{ name = "LegacyMicroButton", icon = "Interface\\Icons\\INV_Shield_06" },
	{ name = "QuestLogMicroButton", icon = "Interface\\Icons\\INV_Scroll_03" },
	{ name = "HousingMicroButton", icon = "Interface\\Icons\\INV_Misc_Key_03" },
	{ name = "SocialsMicroButton", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" },
	{ name = "GuildMicroButton", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
	{ name = "LFDMicroButton", icon = "Interface\\Icons\\INV_Misc_GroupLooking" },
	{ name = "LFGMicroButton", icon = "Interface\\Icons\\INV_Misc_GroupLooking" },
	{ name = "PVPMicroButton", icon = "Interface\\Icons\\INV_BannerPVP_02" },
	{ name = "CollectionsMicroButton", icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
	{ name = "EJMicroButton", icon = "Interface\\Icons\\INV_Misc_Map_01" },
	{ name = "WorldMapMicroButton", icon = "Interface\\Icons\\INV_Misc_Map02" },
	{ name = "HelpMicroButton", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
	{ name = "StoreMicroButton", icon = "Interface\\Icons\\INV_Misc_Coin_01" },
	-- (Clicking this one does nothing: the game's only acts with the mouse
	-- over it, or on Classic on mouse down/up. The slot opens the menu itself.)
	{ name = "MainMenuMicroButton", icon = "Interface\\Icons\\INV_Misc_Gear_01", gameMenu = true },
}
local KEY_BUTTON = "CinematicMenuWheelButton" -- its key binding clicks this
local AREA = "CinematicMenuWheelArea" -- the click-catcher (Escape clicks it too)
local MASK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\RoundIcon" -- soft rounded corners
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- (a round mask every client has)
local MIN_RADIUS = 110 -- from the middle to each icon's centre (UI units); more for many icons
local ICON_SIZE = 52
local ICON_GAP = 14    -- at least this between icons round the ring
local PICKED_SCALE = 1.25
local DEAD_ZONE = 34   -- the cursor this near the middle picks nothing
local FADE_TIME = 0.12

local wheel, disc, centerText, stateText, keyButton, area, gameMenuButton
local slots = {}         -- secure buttons, one per button the bar could have
local shown = {}         -- the bar's buttons as last laid out, by slot
local openButtons = {}   -- by slot: what it clicks for a button with no OnClick
local radius = MIN_RADIUS
local picked             -- the slot the cursor points at, or nil

local function CursorFromMiddle()
	local x, y = GetCursorPosition()
	local scale = wheel:GetEffectiveScale()
	local cx, cy = wheel:GetCenter()
	if not cx then
		return 0, 0
	end
	return x / scale - cx, y / scale - cy
end

-- The game's buttons now on the bar, in its order. Where the bar numbers
-- its buttons (layoutIndex), only those: the game makes some it leaves off
-- the bar (Forever's Adventure Guide), and clicking those errors.
local function BarButtons()
	local list = {}
	local numbered = false
	for i, entry in ipairs(BUTTONS) do
		local button = _G[entry.name]
		if type(button) == "table" and button.IsShown and ns.Flag(button:IsShown()) then
			local index = button.layoutIndex
			numbered = numbered or type(index) == "number"
			list[#list + 1] = { entry = entry, button = button, order = type(index) == "number" and index or nil, i = i }
		end
	end
	for i = #list, 1, -1 do
		local item = list[i]
		if numbered and not item.order then
			table.remove(list, i)
		else
			item.order = item.order or item.i
		end
	end
	table.sort(list, function(a, b) return a.order < b.order end)
	return list
end

-- The button's name as its tooltip gives it, in the game's language (less
-- the key in brackets).
local function ButtonLabel(button, entry)
	local text = button.tooltipText
	if type(text) == "string" then
		text = text:gsub("|c%x%x%x%x%x%x%x%x.-|r", ""):gsub("|n.*", ""):match("^%s*(.-)%s*$")
		if text ~= "" then
			return text
		end
	end
	return (entry.name:gsub("MicroButton$", ""))
end

local function CanOpen(button)
	return ns.Flag(button:IsEnabled())
end

-- Its window is open (the game shows its button pushed in then).
local function IsOpen(button)
	local state = button.GetButtonState and button:GetButtonState()
	return type(state) == "string" and state == "PUSHED"
end

-- (The art grows, not the secure button: that can't change in a fight.)
local function SizeSlot(slot, size)
	slot.art:SetSize(size, size)
	slot.glow:SetSize(size + 10, size + 10)
	slot.ring:SetSize(size + 6, size + 6)
end

local function Pick(index)
	if picked == index then
		return
	end
	if picked and slots[picked] then
		SizeSlot(slots[picked], ICON_SIZE)
		slots[picked].glow:Hide()
	end
	picked = index
	if index and slots[index] then
		SizeSlot(slots[index], ICON_SIZE * PICKED_SCALE)
		slots[index].glow:Show()
	end
end

local function UpdateText()
	local item = picked and shown[picked]
	centerText:SetText(item and item.label or L["Menu wheel"])
	if item and IsOpen(item.button) then
		stateText:SetText(L["open: pick it to close it"])
	elseif item and not CanOpen(item.button) then
		stateText:SetText(L["can't open now"])
	else
		stateText:SetText("")
	end
end

local function Refresh()
	for i, item in ipairs(shown) do
		local slot = slots[i]
		local open, usable = IsOpen(item.button), CanOpen(item.button)
		slot.ring:SetShown(open)
		for _, texture in ipairs({ slot.under, slot.icon }) do
			texture:SetDesaturated(not open and not usable)
			texture:SetAlpha((open or usable) and 1 or 0.5)
		end
	end
	UpdateText()
end

-- The character slot: your portrait, over your class icon (shown if the
-- portrait doesn't draw, as on Forever until it's set again once visible).
local function SetPortrait(slot)
	local _, class = UnitClass("player")
	local coords = CLASS_ICON_TCOORDS and type(class) == "string" and CLASS_ICON_TCOORDS[class]
	if coords then
		slot.under:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
		slot.under:SetTexCoord(unpack(coords))
		slot.under:Show()
	end
	if SetPortraitTexture then
		SetPortraitTexture(slot.icon, "player")
		slot.icon:SetTexCoord(0, 1, 0, 1)
	end
end

local function SetIcon(slot, entry, button)
	local icon = slot.icon
	slot.under:Hide()
	if entry.portrait then
		SetPortrait(slot)
		return
	end
	-- The button's own art first, so the wheel looks like the bar.
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	local atlas = normal and normal.GetAtlas and normal:GetAtlas()
	local file = normal and normal:GetTexture()
	if type(atlas) == "string" and atlas ~= "" then
		icon:SetAtlas(atlas)
	elseif type(file) == "number" or (type(file) == "string" and file ~= "") then
		icon:SetTexture(file)
		icon:SetTexCoord(normal:GetTexCoord())
	-- (SetTexture says false for a file this client doesn't have.)
	elseif entry.icon and icon:SetTexture(entry.icon) ~= false then
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- (trims the icon's own edge)
	else
		icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
end

-- Lays the ring out for the buttons on the bar now (they change with level,
-- guild, game rules...). Out of a fight only: in one, the last layout stays.
local function Build()
	if InCombatLockdown() then
		return
	end
	local list = BarButtons()
	wipe(shown)
	local count = math.min(#list, #slots)
	-- (Wider for many icons, so they don't touch.)
	radius = math.max(MIN_RADIUS, count * (ICON_SIZE + ICON_GAP) / (2 * math.pi))
	local size = (radius + ICON_SIZE) * 2
	-- (Not in UIParent, so it shows with the UI hidden: scaled like it.)
	wheel:SetScale(UIParent:GetEffectiveScale())
	wheel:SetSize(size, size)
	disc:SetSize((radius + ICON_SIZE * 0.85) * 2, (radius + ICON_SIZE * 0.85) * 2)
	wheel:SetAttribute("count", count)
	for i, slot in ipairs(slots) do
		local item = i <= count and list[i]
		if item then
			item.label = ButtonLabel(item.button, item.entry)
			shown[i] = item
			SetIcon(slot, item.entry, item.button)
			local angle = math.rad(90 - (i - 1) * 360 / count)
			slot:ClearAllPoints()
			slot:SetPoint("CENTER", wheel, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
			local target = item.button
			if item.entry.gameMenu then
				target = gameMenuButton
			elseif item.entry.open and not item.button:GetScript("OnClick") then
				openButtons[i] = openButtons[i] or CreateFrame("Button") -- (no size: never seen)
				openButtons[i]:SetScript("OnClick", item.entry.open)
				target = openButtons[i]
			end
			slot:SetAttribute("clickbutton", target)
			keyButton:SetAttribute("clickbutton-slot" .. i, target)
			slot:Show()
		else
			slot:SetAttribute("clickbutton", nil)
			keyButton:SetAttribute("clickbutton-slot" .. i, nil)
			slot:Hide()
		end
	end
end

-- Which slot the cursor points at: the nearest by angle, once it's out of
-- the dead zone in the middle. (The secure snippet below works it out the
-- same way.)
local function SlotAtCursor()
	local count = #shown
	if count == 0 then
		return nil
	end
	local x, y = CursorFromMiddle()
	if x * x + y * y < DEAD_ZONE * DEAD_ZONE then
		return nil
	end
	local step = 360 / count
	-- (Slot 1 straight up, the rest round clockwise.)
	local angle = (90 - math.deg(math.atan2(y, x))) % 360
	return math.floor((angle + step / 2) / step) % count + 1
end

-- With the UI hidden, a window wouldn't show: it's brought back first.
local function ShowUIFor(index)
	local item = index and shown[index]
	if item and CanOpen(item.button) and not UIParent:IsShown() then
		ns.ToggleUI()
	end
end

-- What the game menu's slot clicks: does what the game's button does.
gameMenuButton = CreateFrame("Button") -- (no size: never seen)
gameMenuButton:SetScript("OnClick", function()
	if GameMenuFrame:IsShown() then
		PlaySound(SOUNDKIT.IG_MAINMENU_QUIT)
		HideUIPanel(GameMenuFrame)
		return
	end
	if AreAllPanelsDisallowed and AreAllPanelsDisallowed() then
		return
	end
	if SettingsPanel and SettingsPanel:IsShown() then
		SettingsPanel:Close()
	end
	CloseMenus()
	CloseAllWindows()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
	ShowUIPanel(GameMenuFrame)
end)

-- The wheel (secure, so the snippets can show, place and hide it in a fight;
-- outside UIParent, so it shows with the UI hidden): icons round a dark
-- disc, names in the middle.
wheel = CreateFrame("Frame", "CinematicMenuWheel", nil, "SecureHandlerShowHideTemplate")
wheel:SetFrameStrata("FULLSCREEN_DIALOG")
wheel:SetClampedToScreen(true) -- (it opens round the cursor, kept on screen)
wheel:SetSize((MIN_RADIUS + ICON_SIZE) * 2, (MIN_RADIUS + ICON_SIZE) * 2)
wheel:SetPoint("CENTER", UIParent)
wheel:SetAttribute("count", 0)
wheel:SetAttribute("deadzone", DEAD_ZONE)
wheel:Hide()

disc = wheel:CreateTexture(nil, "BACKGROUND")
disc:SetPoint("CENTER")
disc:SetColorTexture(0, 0, 0, 0.55)
local hub = wheel:CreateTexture(nil, "BORDER")
hub:SetPoint("CENTER")
hub:SetSize(DEAD_ZONE * 2 + 60, DEAD_ZONE * 2 + 60)
hub:SetColorTexture(0, 0, 0, 0.5)
if wheel.CreateMaskTexture then
	for _, texture in ipairs({ disc, hub }) do
		local mask = wheel:CreateMaskTexture()
		mask:SetAllPoints(texture)
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
		texture:AddMaskTexture(mask)
	end
end

centerText = wheel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
centerText:SetPoint("CENTER", 0, 6)
centerText:SetWidth(DEAD_ZONE * 2 + 50)
stateText = wheel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
stateText:SetPoint("TOP", centerText, "BOTTOM", 0, -3)
stateText:SetWidth(DEAD_ZONE * 2 + 50)

-- The click-catcher: the whole screen, behind the icons. It only takes the
-- mouse once the key's let go in the middle; then a click anywhere but an
-- icon puts the wheel away. The snippets also measure the cursor with it.
area = CreateFrame("Button", AREA, wheel, "SecureActionButtonTemplate")
area:SetAllPoints(WorldFrame)
area:SetFrameLevel(wheel:GetFrameLevel())
area:RegisterForClicks("AnyUp")
area:EnableMouse(false)
wheel:SetFrameRef("area", area)

-- The icons: secure buttons that click the game's button, made now (they
-- can't be in a fight), as many as the bar could have.
for i = 1, #BUTTONS do
	local slot = CreateFrame("Button", nil, wheel, "SecureActionButtonTemplate")
	slot:SetSize(ICON_SIZE, ICON_SIZE)
	slot:SetFrameLevel(wheel:GetFrameLevel() + 5)
	slot:RegisterForClicks("AnyUp")
	slot:SetAttribute("type", "click")
	slot:SetScript("PreClick", function()
		ShowUIFor(i)
	end)
	local art = CreateFrame("Frame", nil, slot)
	art:SetPoint("CENTER")
	art:SetSize(ICON_SIZE, ICON_SIZE)
	local glow = art:CreateTexture(nil, "BACKGROUND")
	glow:SetPoint("CENTER")
	glow:SetSize(ICON_SIZE + 10, ICON_SIZE + 10)
	glow:SetColorTexture(1, 0.82, 0.3, 0.9)
	glow:Hide()
	local ring = art:CreateTexture(nil, "BORDER") -- its window is open
	ring:SetPoint("CENTER")
	ring:SetSize(ICON_SIZE + 6, ICON_SIZE + 6)
	ring:SetColorTexture(0.3, 0.9, 0.4, 0.9)
	ring:Hide()
	local under = art:CreateTexture(nil, "ARTWORK", nil, -1) -- (the character slot's class icon)
	under:SetAllPoints()
	under:Hide()
	local icon = art:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	if art.CreateMaskTexture then
		for _, texture in ipairs({ glow, ring, under, icon }) do
			local mask = art:CreateMaskTexture()
			mask:SetAllPoints(texture)
			mask:SetTexture(MASK, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
			texture:AddMaskTexture(mask)
		end
	end
	slot.art, slot.glow, slot.ring, slot.under, slot.icon = art, glow, ring, under, icon
	slot:Hide()
	slots[i] = slot
	-- (A click on it puts the wheel away; the click itself goes on.)
	wheel:WrapScript(slot, "OnClick", [[ owner:Hide() ]])
end

-- The key's button: its binding clicks it on the way down and up. Its action
-- only ever runs on the way up, and only when the snippet picks a slot (as
-- the "button" slotN, whose clickbutton is that slot's game button).
keyButton = CreateFrame("Button", KEY_BUTTON, nil, "SecureActionButtonTemplate")
keyButton:RegisterForClicks("AnyDown", "AnyUp")
keyButton:SetAttribute("useOnKeyDown", false)
for i = 1, #BUTTONS do
	keyButton:SetAttribute("type-slot" .. i, "click")
end
keyButton:SetScript("PreClick", function(_, _, down)
	if down then
		if not wheel:IsShown() then
			Build() -- (out of a fight: freshly laid out)
		end
	elseif wheel:IsShown() then
		ShowUIFor(SlotAtCursor())
	end
end)
_G["BINDING_NAME_CLICK " .. KEY_BUTTON .. ":LeftButton"] = "Cinematic: " .. L["Menu wheel (hold)"]
ns.OnLanguage(function()
	_G["BINDING_NAME_CLICK " .. KEY_BUTTON .. ":LeftButton"] = "Cinematic: " .. L["Menu wheel (hold)"]
end)

-- Down: up round the cursor (or, already up, away). Up: opens the slot the
-- cursor points at; let go in the middle, it stays up to click one.
wheel:WrapScript(keyButton, "OnClick", [[
	local area = owner:GetFrameRef("area")
	if down then
		if owner:IsShown() then
			owner:Hide()
			return false
		end
		if (owner:GetAttribute("count") or 0) == 0 then
			return false
		end
		owner:ClearAllPoints()
		owner:SetPoint("CENTER", "$cursor")
		area:EnableMouse(false)
		owner:Show()
		owner:SetBindingClick(true, "ESCAPE", "]] .. AREA .. [[")
		held = true
		return false
	end
	if not held or not owner:IsShown() then
		return false
	end
	held = false
	local fx, fy = area:GetMousePosition()
	local al, ab, aw, ah = area:GetRect()
	local wl, wb, ww, wh = owner:GetRect()
	if not (fx and al and wl) then
		owner:Hide()
		return false
	end
	local dx = al + fx * aw - (wl + ww / 2)
	local dy = ab + fy * ah - (wb + wh / 2)
	local dead = owner:GetAttribute("deadzone")
	if dx * dx + dy * dy < dead * dead then
		area:EnableMouse(true)
		return false
	end
	local count = owner:GetAttribute("count")
	local step = 360 / count
	local angle = (90 - math.deg(math.atan2(dy, dx))) % 360
	local index = math.floor((angle + step / 2) / step) % count + 1
	owner:Hide()
	return "slot" .. index
]])
-- A click on the catcher (or Escape) puts it away.
wheel:WrapScript(area, "OnClick", [[
	owner:Hide()
	return false
]])
wheel:SetAttribute("_onhide", [[
	self:ClearBindings()
	held = false
]])

-- Our side: fades in, and shows what the cursor points at.
local sinceRefresh = 0
local function OnUpdate(_, elapsed)
	local alpha = wheel:GetAlpha()
	if alpha < 1 then
		wheel:SetAlpha(math.min(1, alpha + elapsed / FADE_TIME))
	end
	Pick(SlotAtCursor())
	sinceRefresh = sinceRefresh + elapsed
	if sinceRefresh >= 0.2 then
		sinceRefresh = 0
		Refresh() -- (a window closing, a button enabled...)
	else
		UpdateText()
	end
end
wheel:HookScript("OnShow", function()
	wheel:SetAlpha(0)
	Pick(nil)
	for i, item in ipairs(shown) do
		if item.entry.portrait then
			SetPortrait(slots[i]) -- (again, now it's on screen)
		end
	end
	Refresh()
end)
wheel:HookScript("OnHide", function()
	Pick(nil)
end)
wheel:SetScript("OnUpdate", ns.Profiled("Menu wheel", OnUpdate))

-- Laid out at login and again as a fight starts (just before the lockdown),
-- so the ring in a fight matches the bar.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("UI_SCALE_CHANGED")
watcher:SetScript("OnEvent", Build)
