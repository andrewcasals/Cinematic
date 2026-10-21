-- Cinematic: the camera wheel. Holding its key brings up a ring of icons
-- round the cursor, one for each camera its own key starts (the
-- standing-still ones and the death camera test): point the cursor at one
-- and let go to start it. Tapping the key instead leaves the wheel up to
-- click one; clicking the middle, Escape or the key again puts it away.
-- Picking the camera that's running stops it (like pressing its key again).
local ADDON_NAME, ns = ...
local L = ns.L

local CAMERAS = {
	{ key = "idle", manual = "afk", label = "AFK camera", icon = "Interface\\Icons\\Spell_Nature_Sleep" },
	{ key = "cozy", manual = "cozy", label = "Cozy camera", icon = "Interface\\Icons\\Spell_Fire_Fire" },
	{ key = "vista", manual = "vista", label = "Vista camera", icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
	{ key = "fish", manual = "fish", label = "Fish camera", icon = "Interface\\Icons\\Trade_Fishing" },
	{ key = "tele", manual = "tele", label = "Tele camera", icon = "Interface\\Icons\\INV_Misc_Rune_01" },
	{ key = "death", label = "Death camera", icon = "Interface\\Icons\\Ability_Rogue_FeignDeath" },
}
local MASK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\RoundIcon" -- soft rounded corners
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- (a round mask every client has)
local RADIUS = 110     -- from the middle to each icon's centre (UI units)
local ICON_SIZE = 52
local PICKED_SCALE = 1.25
local DEAD_ZONE = 64   -- the cursor this near the middle picks nothing (the middle circle)
local TAP = 0.25       -- let go sooner than this (with nothing picked): the wheel stays up to click
local FADE_TIME = 0.12
-- (The middle lights up while the cursor's in it: nothing picked, so letting
-- go there leaves the wheel up.)
local HUB_COLOR = { 0, 0, 0, 0.5 }
local HUB_LIT = { 0.45, 0.36, 0.12, 0.6 }

local wheel, face, centerText, stateText, hub
local slots = {}
local picked             -- the slot the cursor points at, or nil
local heldSince          -- when the key went down, while it's held
local clickMode = false  -- up after a tap: waiting for a click
local fading = 0         -- -1 going, 1 coming, 0 still

local function CursorFromMiddle()
	local x, y = GetCursorPosition()
	local scale = face:GetEffectiveScale()
	local cx, cy = face:GetCenter()
	return x / scale - cx, y / scale - cy
end

-- Whether a camera's running now, and whether it could start (dimmed if not:
-- picking it still says why).
local function IsRunning(camera)
	if camera.key == "death" then
		return GetTime() < (ns.deathTestUntil or 0)
	end
	return ns.manualCam == camera.manual
end

local function CanStart(camera)
	local db = ns.db
	if not db then
		return false
	end
	if camera.key == "death" then
		return db.deathOrbit and not ns.playerMoving
	end
	if not db.enabled or ns.playerMoving or ns.Flag(UnitOnTaxi("player")) then
		return false
	end
	return camera.key ~= "idle" or db.idleOrbit
end

-- (Grown by size, not SetScale: a scaled frame's offset from the middle
-- would scale too and move it.)
local function SizeSlot(slot, size)
	slot:SetSize(size, size)
	slot.glow:SetSize(size + 10, size + 10)
	slot.ring:SetSize(size + 6, size + 6)
end

local function Pick(index)
	if picked == index then
		return
	end
	if picked then
		SizeSlot(slots[picked], ICON_SIZE)
		slots[picked].glow:Hide()
	end
	picked = index
	hub:SetColorTexture(unpack(index and HUB_COLOR or HUB_LIT))
	if index then
		SizeSlot(slots[index], ICON_SIZE * PICKED_SCALE)
		slots[index].glow:Show()
	end
end

local function UpdateText()
	local camera = picked and CAMERAS[picked]
	centerText:SetText(camera and L[camera.label] or L["Camera wheel"])
	if camera and IsRunning(camera) then
		stateText:SetText(L["running: pick it to stop it"])
	elseif camera and not CanStart(camera) then
		stateText:SetText(L["can't start now"])
	else
		stateText:SetText("")
	end
end

local function Refresh()
	for i, camera in ipairs(CAMERAS) do
		local slot = slots[i]
		local running = IsRunning(camera)
		slot.ring:SetShown(running)
		slot.icon:SetDesaturated(not running and not CanStart(camera))
		slot.icon:SetAlpha((running or CanStart(camera)) and 1 or 0.5)
	end
	UpdateText()
end

local function Close()
	if fading ~= -1 and wheel:IsShown() then
		fading = -1
	end
	heldSince, clickMode = nil, false
	wheel:EnableMouse(false)
end

local function Choose(index)
	Close()
	local camera = index and CAMERAS[index]
	if camera then
		Cinematic_StartCam(camera.key, true) -- (quietly: no chat messages)
	end
end

local function Open()
	-- (One wheel at a time. It only opens out of a fight, so ours may hide
	-- the secure ones.)
	for _, other in ipairs({ CinematicMenuWheel, CinematicMarkerWheel, CinematicMasterWheel, CinematicWorldMarkerWheel }) do
		if other:IsShown() and not InCombatLockdown() then
			other:Hide()
		end
	end
	-- (Shown again before it finished going: picks up from where it was.)
	Pick(nil)
	clickMode = false
	-- (Centred on the cursor, so it starts in the middle with nothing picked.)
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	local width, height = UIParent:GetSize()
	local half = RADIUS + ICON_SIZE
	x = math.max(half, math.min(width - half, x / scale))
	y = math.max(half, math.min(height - half, y / scale))
	face:ClearAllPoints()
	face:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	if not wheel:IsShown() then
		wheel:SetAlpha(0)
		wheel:Show()
	end
	fading = 1
	Refresh()
end

-- Which slot the cursor points at: the nearest by angle, once it's out of
-- the dead zone in the middle.
local function SlotAtCursor(reach)
	local x, y = CursorFromMiddle()
	local distance = x * x + y * y
	if distance < DEAD_ZONE * DEAD_ZONE or (reach and distance > reach * reach) then
		return nil
	end
	local step = 360 / #CAMERAS
	-- (Slot 1 straight up, the rest round clockwise.)
	local angle = (90 - math.deg(math.atan2(y, x))) % 360
	return math.floor((angle + step / 2) / step) % #CAMERAS + 1
end

local sinceRefresh = 0
local function OnUpdate(_, elapsed)
	if fading ~= 0 then
		local alpha = wheel:GetAlpha() + fading * elapsed / FADE_TIME
		if alpha >= 1 then
			alpha, fading = 1, 0
		elseif alpha <= 0 then
			fading = 0
			Pick(nil)
			wheel:Hide()
			return
		end
		wheel:SetAlpha(alpha)
	end
	if fading == -1 then
		return
	end
	-- (A fight starting puts it away: the cameras don't run in one.)
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		Close()
		return
	end
	Pick(SlotAtCursor())
	sinceRefresh = sinceRefresh + elapsed
	if sinceRefresh >= 0.2 then
		sinceRefresh = 0
		Refresh() -- (moving, a camera ending...)
	else
		UpdateText()
	end
end

-- The key binding (CINEMATIC_CAMWHEEL, runs on both down and up).
function Cinematic_CameraWheel(keystate)
	if not wheel or not ns.db then
		return
	end
	if keystate == "down" then
		if clickMode then
			Close() -- (the key again, while it waits for a click)
			return
		end
		if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
			return
		end
		Open()
		heldSince = GetTime()
	elseif heldSince then
		local held = GetTime() - heldSince
		heldSince = nil
		if picked then
			Choose(picked)
		elseif held < TAP then
			clickMode = true
			wheel:EnableMouse(true)
		else
			Close()
		end
	end
end

-- The wheel: icons round a dark disc, names in the middle.
wheel = CreateFrame("Frame", "CinematicCameraWheel", UIParent)
wheel:SetAllPoints(UIParent)
wheel:SetFrameStrata("DIALOG")
wheel:Hide()
-- (Its face goes where the cursor is, kept on screen: the wheel fills the
-- screen only to take the clicks.)
face = CreateFrame("Frame", nil, wheel)
face:SetSize((RADIUS + ICON_SIZE) * 2, (RADIUS + ICON_SIZE) * 2)
face:SetPoint("CENTER")

local disc = face:CreateTexture(nil, "BACKGROUND")
disc:SetPoint("CENTER")
disc:SetSize((RADIUS + ICON_SIZE * 0.85) * 2, (RADIUS + ICON_SIZE * 0.85) * 2)
disc:SetColorTexture(0, 0, 0, 0.55)
hub = face:CreateTexture(nil, "BORDER")
hub:SetPoint("CENTER")
hub:SetSize(DEAD_ZONE * 2, DEAD_ZONE * 2)
hub:SetColorTexture(unpack(HUB_LIT)) -- (nothing picked yet)
if face.CreateMaskTexture then
	for _, texture in ipairs({ disc, hub }) do
		local mask = face:CreateMaskTexture()
		mask:SetAllPoints(texture)
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
		texture:AddMaskTexture(mask)
	end
end

centerText = face:CreateFontString(nil, "OVERLAY", "GameFontNormal")
centerText:SetPoint("CENTER", 0, 6)
centerText:SetWidth(DEAD_ZONE * 2 - 10)
stateText = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
stateText:SetPoint("TOP", centerText, "BOTTOM", 0, -3)
stateText:SetWidth(DEAD_ZONE * 2 - 10)

for i, camera in ipairs(CAMERAS) do
	local slot = CreateFrame("Frame", nil, face)
	slot:SetSize(ICON_SIZE, ICON_SIZE)
	local angle = math.rad(90 - (i - 1) * 360 / #CAMERAS)
	slot:SetPoint("CENTER", face, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle))
	local glow = slot:CreateTexture(nil, "BACKGROUND")
	glow:SetPoint("CENTER")
	glow:SetSize(ICON_SIZE + 10, ICON_SIZE + 10)
	glow:SetColorTexture(1, 0.82, 0.3, 0.9)
	glow:Hide()
	local ring = slot:CreateTexture(nil, "BORDER") -- running now
	ring:SetPoint("CENTER")
	ring:SetSize(ICON_SIZE + 6, ICON_SIZE + 6)
	ring:SetColorTexture(0.3, 0.9, 0.4, 0.9)
	ring:Hide()
	local icon = slot:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(camera.icon)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- (trims the icon's own edge)
	if slot.CreateMaskTexture then
		for _, texture in ipairs({ glow, ring, icon }) do
			local mask = slot:CreateMaskTexture()
			mask:SetAllPoints(texture)
			mask:SetTexture(MASK, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
			texture:AddMaskTexture(mask)
		end
	end
	slot.glow, slot.ring, slot.icon = glow, ring, icon
	slots[i] = slot
end

-- (Only takes the mouse while it waits for a click, over the whole screen:
-- a click on an icon starts it, anywhere else puts the wheel away.)
wheel:SetScript("OnMouseUp", function()
	Choose(SlotAtCursor(RADIUS + ICON_SIZE))
end)
wheel:SetScript("OnHide", function()
	-- (Escape hides it at once: tidied up.)
	fading, heldSince, clickMode = 0, nil, false
	wheel:EnableMouse(false)
	Pick(nil)
end)
wheel:SetScript("OnUpdate", ns.Profiled("Camera wheel", OnUpdate))
-- (The other wheels put it away as they open.)
function ns.CloseCameraWheel()
	if wheel:IsShown() then
		wheel:Hide()
	end
end

-- For the master wheel: why it can't open now (a fight), or nil.
function ns.CameraWheelCant()
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		return L["not in a fight"]
	end
	return nil
end

-- The master wheel opens it round the cursor, waiting for a click (as if its
-- key had been tapped).
function ns.OpenCameraWheel()
	if not ns.db or ns.CameraWheelCant() then
		return
	end
	Open()
	clickMode = true
	wheel:EnableMouse(true)
end
tinsert(UISpecialFrames, "CinematicCameraWheel") -- Escape closes it
ns.AddOverlay(wheel) -- (stays with the UI hidden, like the bars)
