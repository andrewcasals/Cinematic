-- Cinematic: the marker wheels. Like the menu wheel, but their icons are the
-- raid markers (skull, cross, square...). Holding a wheel's key brings up its
-- ring round the cursor: point at a marker and let go to use it. Letting go
-- in the middle leaves the wheel up to click one; clicking elsewhere, Escape
-- or the key again puts it away.
--
-- The marker wheel puts a marker over a unit, in the order of the game's
-- Target Marker Icon menu, and None takes theirs off. Who it marks is
-- settled as the key goes down: your target, or with none (out of a fight),
-- whatever the cursor's on. In a fight, always your target: our code can't
-- change the buttons then, and the snippets can't tell who the mouseover is.
--
-- The ground marker wheel drops a world marker (the coloured light on the
-- floor) under the cursor, where you let go (on the icon you picked).
-- Picking one that's down moves it there; Clear all takes them all up.
--
-- Marking is protected (an addon setting a marker itself is blocked), so the
-- wheels mark through secure buttons (the game's own "raidtarget" and
-- "worldmarker" actions), and opening, picking and closing run as secure
-- snippets, as in the menu wheel.
local _, ns = ...
local L = ns.L

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local CLEAR_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- (a round mask every client has)
local RADIUS = 110     -- from the middle to each icon's centre (UI units)
local ICON_SIZE = 46
local PICKED_SCALE = 1.3
local DEAD_ZONE = 64   -- the cursor this near the middle picks nothing (the middle circle)
local OUTER = RADIUS + ICON_SIZE * 0.9 -- the disc's edge: a click past it picks nothing
local FADE_TIME = 0.12
local TURN_TIME = 0.3  -- a slot going from on to off (or back): its ring fading, its icon greying
local LINGER_FADE = 0.3 -- the last of a linger (below): the picked slot fading away
-- (The middle lights up while the cursor's in it: nothing picked, so letting
-- go there leaves the wheel up.)
local HUB_COLOR = { 0, 0, 0, 0.5 }
local HUB_LIT = { 0.45, 0.36, 0.12, 0.6 }

-- By the game's unit marker number (the icon's too): its English name and
-- the game menu's colour.
local ENGLISH = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local COLORS = {
	{ 1, 0.92, 0 },        -- star
	{ 0.98, 0.57, 0 },     -- circle
	{ 0.83, 0.22, 0.9 },   -- diamond
	{ 0.04, 0.95, 0 },     -- triangle
	{ 0.7, 0.82, 0.88 },   -- moon
	{ 0, 0.71, 1 },        -- square
	{ 1, 0.24, 0.17 },     -- cross
	{ 1, 1, 1 },           -- skull
}
-- The ring's order, skull first (the menu's), by unit marker number.
local RING = { 8, 7, 6, 5, 4, 3, 2, 1 }
-- A world marker's number by its icon's (the game numbers them otherwise:
-- blue square first, white skull last).
local WORLD = { [6] = 1, [4] = 2, [3] = 3, [7] = 4, [1] = 5, [2] = 6, [5] = 7, [8] = 8 }

local wheels = {} -- each wheel made, so each can put the others away

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function Exists(token)
	local ok, exists = pcall(UnitExists, token)
	return ok and ns.Flag(exists)
end

-- The marker's name as the game gives it, in the game's language (else
-- English, for L).
local function IconName(icon)
	local name = _G["RAID_TARGET_" .. icon]
	return type(name) == "string" and name or ENGLISH[icon]
end

-- In a raid only the leader and assistants mark, unless everyone's one.
local function MayMark()
	return not (IsInRaid and ns.Flag(IsInRaid())) or ns.Flag(UnitIsGroupLeader("player"))
		or ns.Flag(UnitIsGroupAssistant("player"))
		or (IsEveryoneAssistant and ns.Flag(IsEveryoneAssistant()))
end

-- Opens a secure wheel from another's snippet (the master wheel's): round
-- the cursor, waiting for a click, as if its key had been tapped. Run as its
-- _onattributechanged when a snippet sets its "cineopen".
local OPEN_SNIPPET = [[
	if name ~= "cineopen" or not value then
		return
	end
	self:SetAttribute("cineopen", nil)
	if (self:GetAttribute("count") or 0) == 0 then
		return
	end
	for i = 1, self:GetAttribute("others") or 0 do
		local other = self:GetFrameRef("other" .. i)
		if other then
			other:Hide()
		end
	end
	local area = self:GetFrameRef("area")
	self:ClearAllPoints()
	self:SetPoint("CENTER", "$cursor")
	area:EnableMouse(true)
	self:Show()
	self:SetBindingClick(true, "ESCAPE", area:GetName(), "Escape")
]]

-- Makes a wheel. spec: name (its frame's; its key's button and click-catcher
-- are named from it), title, binding (its key's name), slots (each: icon,
-- color, label, and attributes for its secure action, or opens: a secure
-- wheel it opens; optional: trim, for an icon with an edge of its own, and
-- Cant(), why that slot can't be used now), and these, all optional:
-- Cant() (why it can't be used now, or nil), Active(slot) (true: shows its
-- ring), Title() (the middle's text with nothing picked), activeText (under a
-- picked slot that's active), inactiveText (under one that isn't),
-- dimInactive (true: slots that aren't active are greyed), onColor and
-- offColor (r, g, b, a: the ring always shows, in these, not just while
-- active), linger (seconds
-- the wheel stays up after a slot that calls wheel.Linger(index) is picked,
-- showing it turn on or off), lingerPicks (true: every pick lingers, for
-- slots whose secure actions can't call it), OnOpen() (as the key goes down, before the
-- snippet: out of a fight our code may still change the buttons). Text is
-- English, translated as it's shown (the language is only known later).
local function MakeWheel(spec)
	local keyName, areaName = spec.name .. "Button", spec.name .. "Area"
	local list = spec.slots
	local slots = {}
	local picked -- the slot the cursor points at, or nil
	local lingering -- seconds left showing a pick after the wheel's put away, or nil
	local wheel, face, hub, centerText, stateText

	-- (The art grows, not the secure button: that can't change in a fight.)
	local function SizeSlot(slot, size)
		slot.art:SetSize(size, size)
		slot.glow:SetSize(size + 16, size + 16)
		slot.ring:SetSize(size + 10, size + 10)
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
		local entry = picked and list[picked]
		local cant = spec.Cant and spec.Cant()
		cant = cant or (entry and entry.Cant and entry.Cant())
		if entry then
			centerText:SetText(L[entry.label])
			centerText:SetTextColor(entry.color[1], entry.color[2], entry.color[3])
		else
			-- (A secret title on WoW Forever is still shown, just not joined to anything.)
			local ok = not cant and spec.Title and pcall(centerText.SetText, centerText, spec.Title())
			if not ok then
				centerText:SetText(L[spec.title])
			end
			centerText:SetTextColor(1, 0.82, 0)
		end
		stateText:SetTextColor(1, 1, 1)
		if cant then
			stateText:SetText(cant)
		elseif entry and spec.activeText and spec.Active and spec.Active(entry) then
			stateText:SetText(L[spec.activeText])
		elseif entry and spec.inactiveText and spec.Active and spec.Active(entry) == false then
			stateText:SetText(L[spec.inactiveText])
			stateText:SetTextColor(1, 0.4, 0.35)
		else
			stateText:SetText("")
		end
	end

	local function Refresh()
		local usable = not (spec.Cant and spec.Cant())
		for i, entry in ipairs(list) do
			local slot = slots[i]
			local can = usable and not (entry.Cant and entry.Cant())
			local active = spec.Active and spec.Active(entry)
			slot.ringTo = (can and active == true) and 1 or 0
			-- (Greyed: can't be used now, or with dimInactive, isn't active.)
			slot.colorTo = (not can or (spec.dimInactive and active == false)) and 0 or 1
		end
		UpdateText()
	end

	-- Each slot's ring and colour towards what Refresh set (all the way at
	-- once with no elapsed: as the wheel opens).
	local function Turn(elapsed)
		for _, slot in ipairs(slots) do
			slot.ringLit = elapsed and ns.Approach(slot.ringLit, slot.ringTo, elapsed, TURN_TIME) or slot.ringTo
			slot.colorLit = elapsed and ns.Approach(slot.colorLit, slot.colorTo, elapsed, TURN_TIME) or slot.colorTo
			local on, off, lit = spec.onColor, spec.offColor, slot.ringLit
			if on and off then
				slot.ring:SetVertexColor(off[1] + (on[1] - off[1]) * lit, off[2] + (on[2] - off[2]) * lit,
					off[3] + (on[3] - off[3]) * lit)
				slot.ring:SetAlpha(off[4] + (on[4] - off[4]) * lit)
			else
				slot.ring:SetAlpha(lit)
			end
			if slot.icon.SetDesaturation then
				slot.icon:SetDesaturation(1 - slot.colorLit)
			else
				slot.icon:SetDesaturated(slot.colorLit < 0.5)
			end
			slot.icon:SetAlpha(0.5 + 0.5 * slot.colorLit)
		end
	end

	-- Which slot the cursor points at: the nearest by angle, once it's out of
	-- the dead zone in the middle (and, for a click, still on the disc). (The
	-- secure snippets below work it out the same way.)
	local function SlotAtCursor(clicking)
		local x, y = GetCursorPosition()
		local scale = wheel:GetEffectiveScale()
		local cx, cy = wheel:GetCenter()
		if not cx then
			return nil
		end
		x, y = x / scale - cx, y / scale - cy
		if x * x + y * y < DEAD_ZONE * DEAD_ZONE or (clicking and x * x + y * y > OUTER * OUTER) then
			return nil
		end
		local step = 360 / #list
		-- (Slot 1 straight up, the rest round clockwise.)
		local angle = (90 - math.deg(math.atan2(y, x))) % 360
		return math.floor((angle + step / 2) / step) % #list + 1
	end

	-- The wheel (secure, so the snippets can show, place and hide it in a
	-- fight; outside UIParent, so it shows with the UI hidden): icons round a
	-- dark disc, names in the middle.
	wheel = CreateFrame("Frame", spec.name, nil, "SecureHandlerShowHideTemplate, SecureHandlerAttributeTemplate")
	wheel:SetFrameStrata("FULLSCREEN_DIALOG")
	wheel:SetClampedToScreen(true) -- (it opens round the cursor, kept on screen)
	wheel:SetSize((RADIUS + ICON_SIZE) * 2, (RADIUS + ICON_SIZE) * 2)
	wheel:SetPoint("CENTER", UIParent)
	wheel:SetAttribute("count", #list)
	wheel:SetAttribute("deadzone", DEAD_ZONE)
	wheel:SetAttribute("outer", OUTER)
	wheel:Hide()

	-- What's drawn: a plain frame of ours over the wheel, so it can stay up a
	-- moment after the wheel's put away (linger), which our code can't keep
	-- the secure wheel from in a fight. Scaled like it (see the watcher).
	face = CreateFrame("Frame")
	face:SetFrameStrata("FULLSCREEN_DIALOG")
	face:SetAllPoints(wheel)
	face:SetFrameLevel(wheel:GetFrameLevel() + 5)
	face:Hide()

	local disc = face:CreateTexture(nil, "BACKGROUND")
	disc:SetPoint("CENTER")
	disc:SetSize(OUTER * 2, OUTER * 2)
	disc:SetColorTexture(0, 0, 0, 0.55)
	hub = face:CreateTexture(nil, "BORDER")
	hub:SetPoint("CENTER")
	hub:SetSize(DEAD_ZONE * 2, DEAD_ZONE * 2)
	hub:SetColorTexture(unpack(HUB_LIT)) -- (nothing picked yet)

	-- (Round, all of them: the markers have no square of their own to show.)
	local function Round(frame, texture)
		if frame.CreateMaskTexture then
			local mask = frame:CreateMaskTexture()
			mask:SetAllPoints(texture)
			mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
			texture:AddMaskTexture(mask)
		end
	end
	Round(face, disc)
	Round(face, hub)

	centerText = face:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	centerText:SetPoint("CENTER", 0, 6)
	centerText:SetWidth(DEAD_ZONE * 2 - 10)
	stateText = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	stateText:SetPoint("TOP", centerText, "BOTTOM", 0, -3)
	stateText:SetWidth(DEAD_ZONE * 2 - 10)

	-- The click-catcher: the whole screen, under the icons. It only takes the
	-- mouse once the key's let go in the middle; then a click does the slot the
	-- cursor points at (the lit one: all its slice of the disc, not just its
	-- icon, which is drawn bigger than any button could be), and a click in
	-- the middle or off the disc puts the wheel away. The snippets also
	-- measure the cursor with it.
	local area = CreateFrame("Button", areaName, wheel, "SecureActionButtonTemplate")
	area:SetAllPoints(WorldFrame)
	area:SetFrameLevel(wheel:GetFrameLevel())
	area:RegisterForClicks("AnyUp")
	area:SetAttribute("useOnKeyDown", false)
	area:EnableMouse(false)
	wheel:SetFrameRef("area", area)

	-- The key's button: its binding clicks it on the way down and up. Its
	-- action only ever runs on the way up, and only when the snippet picks a
	-- slot (as the "button" slotN, set up as that slot's).
	local keyButton = CreateFrame("Button", keyName, nil, "SecureActionButtonTemplate")
	keyButton:RegisterForClicks("AnyDown", "AnyUp")
	keyButton:SetAttribute("useOnKeyDown", false)

	-- The icons: just art. Their actions are the key's button's and the
	-- catcher's, as the "button" slotN.
	for i, entry in ipairs(list) do
		local slot = CreateFrame("Frame", nil, face)
		slot:SetSize(ICON_SIZE, ICON_SIZE)
		slot:SetFrameLevel(face:GetFrameLevel() + 5)
		local angle = math.rad(90 - (i - 1) * 360 / #list)
		slot:SetPoint("CENTER", face, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle))
		for key, value in pairs(entry.attributes or {}) do
			keyButton:SetAttribute(key .. "-slot" .. i, value)
			area:SetAttribute(key .. "-slot" .. i, value)
		end
		if entry.opens then
			wheel:SetFrameRef("open" .. i, entry.opens)
		end
		local art = CreateFrame("Frame", nil, slot)
		art:SetPoint("CENTER")
		local glow = art:CreateTexture(nil, "BACKGROUND") -- the cursor's on it
		glow:SetPoint("CENTER")
		glow:SetColorTexture(entry.color[1], entry.color[2], entry.color[3], 0.45)
		glow:Hide()
		local ring = art:CreateTexture(nil, "BORDER") -- active (theirs now, or down)
		ring:SetPoint("CENTER")
		if spec.onColor then
			ring:SetColorTexture(1, 1, 1) -- (coloured as it turns)
		else
			ring:SetColorTexture(1, 1, 1, 0.3)
		end
		ring:SetAlpha(0)
		local icon = art:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetTexture(entry.icon)
		if entry.trim then
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		end
		Round(art, glow)
		Round(art, ring)
		if entry.trim then
			Round(art, icon) -- (a spell's square icon, cut to a circle like its ring)
		end
		slot.art, slot.glow, slot.ring, slot.icon = art, glow, ring, icon
		slot.ringLit, slot.ringTo, slot.colorLit, slot.colorTo = 0, 0, 1, 1
		slots[i] = slot
		SizeSlot(slot, ICON_SIZE)
	end

	keyButton:SetScript("PreClick", function(_, _, down)
		if down and not wheel:IsShown() then
			if spec.OnOpen then
				spec.OnOpen()
			end
			ns.CloseCameraWheel()
		end
	end)
	_G["BINDING_NAME_CLICK " .. keyName .. ":LeftButton"] = "Cinematic: " .. L[spec.binding]
	ns.OnLanguage(function()
		_G["BINDING_NAME_CLICK " .. keyName .. ":LeftButton"] = "Cinematic: " .. L[spec.binding]
	end)

	-- Down: up round the cursor (or, already up, away). Up: does the slot the
	-- cursor points at; let go in the middle, it stays up to click one.
	wheel:WrapScript(keyButton, "OnClick", [[
		local area = owner:GetFrameRef("area")
		if down then
			if owner:IsShown() then
				owner:Hide()
				return false
			end
			-- (One wheel at a time: the other secure ones are put away.)
			for i = 1, owner:GetAttribute("others") or 0 do
				local other = owner:GetFrameRef("other" .. i)
				if other then
					other:Hide()
				end
			end
			owner:ClearAllPoints()
			owner:SetPoint("CENTER", "$cursor")
			area:EnableMouse(false)
			owner:Show()
			owner:SetBindingClick(true, "ESCAPE", "]] .. areaName .. [[", "Escape")
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
		local sub = owner:GetFrameRef("open" .. index)
		if sub then
			sub:SetAttribute("cineopen", true)
			return false
		end
		return "slot" .. index
	]])
	-- A click on the catcher: the slot the cursor points at, or (in the
	-- middle, off the disc, or Escape) just away.
	wheel:WrapScript(area, "OnClick", [[
		local fx, fy = self:GetMousePosition()
		local al, ab, aw, ah = self:GetRect()
		local wl, wb, ww, wh = owner:GetRect()
		owner:Hide()
		if button == "Escape" or not (fx and al and wl) then
			return false
		end
		local dx = al + fx * aw - (wl + ww / 2)
		local dy = ab + fy * ah - (wb + wh / 2)
		local dead, outer = owner:GetAttribute("deadzone"), owner:GetAttribute("outer")
		local far = dx * dx + dy * dy
		if far < dead * dead or far > outer * outer then
			return false
		end
		local count = owner:GetAttribute("count")
		local step = 360 / count
		local angle = (90 - math.deg(math.atan2(dy, dx))) % 360
		local index = math.floor((angle + step / 2) / step) % count + 1
		local sub = owner:GetFrameRef("open" .. index)
		if sub then
			sub:SetAttribute("cineopen", true)
			return false
		end
		return "slot" .. index
	]])
	wheel:SetAttribute("_onhide", [[
		self:ClearBindings()
		held = false
	]])
	wheel:SetAttribute("_onattributechanged", OPEN_SNIPPET)

	-- Our side: fades in, and shows what the cursor points at. Once the
	-- wheel's put away, the face goes too, unless a pick lingers it: then the
	-- rest goes at once, and the picked slot stays, turning on or off, then fades.
	local sinceRefresh = 0
	local restAlpha = 1 -- all but the picked slot's, while lingering
	local restParts = { disc, hub, centerText, stateText }
	local function SetRest(alpha)
		restAlpha = alpha
		for _, part in ipairs(restParts) do
			part:SetAlpha(alpha)
		end
		for i, slot in ipairs(slots) do
			slot:SetAlpha(i == picked and 1 or alpha)
		end
	end
	local function Away()
		lingering = nil
		face:Hide()
		Pick(nil)
	end
	local function OnUpdate(_, elapsed)
		if not wheel:IsShown() then
			lingering = lingering and lingering - elapsed
			if not lingering or lingering <= 0 then
				Away()
				return
			end
			-- (The rest goes at once; the picked slot stays, and fades last.)
			if restAlpha > 0 then
				SetRest(math.max(0, restAlpha - elapsed / FADE_TIME))
			end
			if picked then
				slots[picked]:SetAlpha(math.min(1, lingering / LINGER_FADE))
			end
			Turn(elapsed)
			-- (A mark shows a moment after the pick: the ring catches up.)
			sinceRefresh = sinceRefresh + elapsed
			if sinceRefresh >= 0.2 then
				sinceRefresh = 0
				Refresh()
			end
			return
		end
		local alpha = face:GetAlpha()
		if alpha < 1 then
			face:SetAlpha(math.min(1, alpha + elapsed / FADE_TIME))
		end
		Turn(elapsed)
		Pick(SlotAtCursor(area:IsMouseEnabled()))
		sinceRefresh = sinceRefresh + elapsed
		if sinceRefresh >= 0.2 then
			sinceRefresh = 0
			Refresh() -- (someone else marking, them going away...)
		else
			UpdateText()
		end
	end
	wheel:HookScript("OnShow", function()
		lingering = nil
		face:SetAlpha(0)
		face:Show()
		Pick(nil)
		SetRest(1)
		Refresh()
		Turn()
	end)
	-- (The face goes on its next update: a pick's action, just after this,
	-- may linger it first.)
	face:SetScript("OnUpdate", ns.Profiled(spec.title, OnUpdate))

	-- Called by a slot's action as it's picked: that slot stays up showing it.
	function wheel.Linger(index)
		if wheel:IsShown() or not face:IsShown() then
			return
		end
		lingering = spec.linger or 1
		Pick(index)
		Refresh()
	end
	-- (After the secure click: the slot picked is the one our side lit.)
	if spec.lingerPicks then
		keyButton:HookScript("PostClick", function(_, _, down)
			if not down and picked then
				wheel.Linger(picked)
			end
		end)
		area:HookScript("PostClick", function(_, button)
			if button ~= "Escape" and picked then
				wheel.Linger(picked)
			end
		end)
	end

	wheel.keyButton, wheel.area, wheel.face = keyButton, area, face
	wheels[#wheels + 1] = wheel
	return wheel
end

-- The marker wheel ----------------------------------------------------------

local unit = "target" -- who its buttons mark

-- The mouseover only lasts while the cursor's on them, so it's swapped for a
-- token that stays: one of these that's the same unit.
local STEADY = { "target", "focus", "player", "pet" }
for i = 1, 4 do
	STEADY[#STEADY + 1] = "party" .. i
	STEADY[#STEADY + 1] = "partypet" .. i
end
for i = 1, 40 do
	STEADY[#STEADY + 1] = "raid" .. i
end
for i = 1, 40 do
	STEADY[#STEADY + 1] = "nameplate" .. i
end

-- Who the wheel marks: the target; with none, the mouseover, if a steady
-- token names them (one with no plate or frame can't be).
local function MarkUnit()
	if not Exists("target") and Exists("mouseover") then
		for _, token in ipairs(STEADY) do
			if Exists(token) then
				local ok, same = pcall(UnitIsUnit, "mouseover", token)
				if ok and ns.Flag(same) then
					return token
				end
			end
		end
	end
	return "target"
end

local unitSlots = {}
for _, icon in ipairs(RING) do
	unitSlots[#unitSlots + 1] = { icon = ICON .. icon, color = COLORS[icon], label = IconName(icon), index = icon,
		attributes = { type = "raidtarget", action = "set", marker = icon } }
end
unitSlots[#unitSlots + 1] = { icon = CLEAR_ICON, color = { 1, 1, 1 }, index = 0,
	label = type(NONE) == "string" and NONE or "None",
	attributes = { type = "raidtarget", action = "clear" } }

local markerWheel

-- Points the buttons at who to mark (one "unit" for all their slots: a
-- slot's own unit-slotN would win over it). Out of a fight only.
local function SetUnit(token)
	if InCombatLockdown() then
		return
	end
	unit = token
	markerWheel.keyButton:SetAttribute("unit", token)
	markerWheel.area:SetAttribute("unit", token)
end

markerWheel = MakeWheel({
	name = "CinematicMarkerWheel",
	title = "Marker wheel",
	binding = "Marker wheel (hold)",
	slots = unitSlots,
	linger = 0.6, -- (up a moment after a pick, showing the marker go on)
	lingerPicks = true,
	OnOpen = function() SetUnit(MarkUnit()) end,
	Title = function() return UnitName(unit) end,
	-- Why they can't be marked now, or nil if they can.
	Cant = function()
		if not Exists(unit) then
			return L["no target"]
		end
		if CanBeRaidTarget then
			local ok, can = pcall(CanBeRaidTarget, unit)
			if ok and Known(can) and not can then
				return L["can't be marked"]
			end
		end
		if not MayMark() then
			return L["only the leader and assistants can mark"]
		end
		return nil
	end,
	-- The marker they have now (None with none). Not known on WoW Forever,
	-- where it's secret.
	Active = function(entry)
		local ok, index = pcall(GetRaidTargetIndex, unit)
		if not ok or not Known(index) then
			return nil
		end
		return (index or 0) == entry.index
	end,
})
SetUnit(unit)

-- The ground marker wheel (where the client has world markers) --------------

local count = type(NUM_WORLD_RAID_MARKERS) == "number" and NUM_WORLD_RAID_MARKERS or 8
if PlaceRaidMarker then
	local worldSlots = {}
	for _, icon in ipairs(RING) do
		local index = WORLD[icon]
		if index <= count then
			worldSlots[#worldSlots + 1] = { icon = ICON .. icon, color = COLORS[icon], label = IconName(icon),
				index = index, attributes = { type = "macro", macrotext = "/wm [@cursor] " .. index } }
		end
	end
	worldSlots[#worldSlots + 1] = { icon = CLEAR_ICON, color = { 1, 1, 1 }, label = "Clear all",
		attributes = { type = "worldmarker", action = "clear" } }

	MakeWheel({
		name = "CinematicWorldMarkerWheel",
		title = "Ground marker wheel",
		binding = "Ground marker wheel (hold)",
		slots = worldSlots,
		linger = 0.6, -- (up a moment after a pick, showing the marker go down)
		lingerPicks = true,
		activeText = "down: pick it to move it",
		Cant = function()
			if not (IsInGroup and ns.Flag(IsInGroup())) then
				return L["only in a group"]
			end
			if not MayMark() then
				return L["only the leader and assistants can mark"]
			end
			return nil
		end,
		-- It's down now. Not known where the game won't say.
		Active = function(entry)
			if not (entry.index and IsRaidMarkerActive) then
				return nil
			end
			local ok, active = pcall(IsRaidMarkerActive, entry.index)
			if not ok or not Known(active) then
				return nil
			end
			return active and true or false
		end,
	})
end
-- For the keybinds page: whether this client has the ground marker wheel.
ns.hasWorldMarkerWheel = CinematicWorldMarkerWheel ~= nil

-- The visions: each one's switch, turned on and off by its keybind and the
-- vision wheel. Duel and Roll Vision's ticks are on the Vision page, under
-- its Enable page switch (page): turning one on turns that on too. Apply()
-- puts the change into effect, as the options pages do.
local VISIONS = {
	{ key = "heal", setting = "handleHealVision", label = "Heal Vision",
		icon = "Interface\\Icons\\Spell_Holy_FlashHeal", trim = true, color = { 0.35, 1, 0.45 },
		Apply = function()
			if ns.ApplyHealVisionFrames then ns.ApplyHealVisionFrames() end
		end },
	{ key = "quest", setting = "questVision", label = "Quest Vision",
		icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", trim = true, color = { 1, 0.82, 0 },
		Apply = function()
			if ns.RefreshTargetQuestIcon then ns.RefreshTargetQuestIcon() end
			if ns.UpdateQuestGlow then ns.UpdateQuestGlow() end
		end },
	{ key = "duel", setting = "duelPlates", page = "handleVision", label = "Duel Vision",
		icon = "Interface\\Icons\\Ability_DualWield", trim = true, color = { 1, 0.35, 0.3 } },
}
-- (Only where the game has a loot history.)
if ns.hasRollWindow then
	VISIONS[#VISIONS + 1] = { key = "roll", setting = "rollWindow", page = "handleVision", label = "Roll Vision",
		icon = "Interface\\Icons\\INV_Misc_Dice_01", trim = true, color = { 0.45, 0.7, 1 },
		Apply = function()
			if ns.RefreshRollWindow then ns.RefreshRollWindow() end
		end }
end
local visionByKey = {}
for _, vision in ipairs(VISIONS) do
	visionByKey[vision.key] = vision
end

local function VisionOn(vision)
	return ns.Setting(vision.setting) and true or false
end

-- Turns a vision on or off. quiet: no message in chat (the wheel shows it).
local function ToggleVision(vision, quiet)
	local db = ns.db
	if not db then
		return
	end
	if VisionOn(vision) then
		db[vision.setting] = false
	else
		db[vision.setting] = true
		if vision.page then
			db[vision.page] = true
		end
	end
	if vision.Apply then
		vision.Apply()
	end
	if not quiet then
		ns.Print((VisionOn(vision) and L["%s on"] or L["%s off"]):format(L[vision.label]))
	end
	if ns.RefreshOptions then
		ns.RefreshOptions()
	end
end

-- The Toggle Heal Vision (Quest, Duel, Roll) keybinds (Bindings.xml).
function Cinematic_ToggleVision(key)
	local vision = visionByKey[key]
	if not vision then
		ns.Print(L["this game has no Roll Vision"])
		return
	end
	ToggleVision(vision)
end

local function SetVisionBindingNames()
	BINDING_NAME_CINEMATIC_VISION_HEAL = "Cinematic: " .. L["Toggle Heal Vision"]
	BINDING_NAME_CINEMATIC_VISION_QUEST = "Cinematic: " .. L["Toggle Quest Vision"]
	BINDING_NAME_CINEMATIC_VISION_DUEL = "Cinematic: " .. L["Toggle Duel Vision"]
	BINDING_NAME_CINEMATIC_VISION_ROLL = "Cinematic: " .. L["Toggle Roll Vision"]
end
SetVisionBindingNames()
ns.OnLanguage(SetVisionBindingNames)

-- The vision wheel: an icon for each vision, ringed green while it's on and
-- grey while it's off; picking
-- one turns it on or off. Each slot clicks a plain button of ours (no size:
-- never seen) that does it, in a fight too.
local visionSlots = {}
local visionWheel
for i, vision in ipairs(VISIONS) do
	local toggler = CreateFrame("Button")
	toggler:SetScript("OnClick", function()
		ToggleVision(vision, true)
		visionWheel.Linger(i)
	end)
	visionSlots[#visionSlots + 1] = { icon = vision.icon, trim = vision.trim, color = vision.color,
		label = vision.label, vision = vision, attributes = { type = "click", clickbutton = toggler } }
end
visionWheel = MakeWheel({
	name = "CinematicVisionWheel",
	title = "Vision wheel",
	binding = "Vision wheel (hold)",
	slots = visionSlots,
	activeText = "on: pick it to turn it off",
	inactiveText = "off: pick it to turn it on",
	dimInactive = true, -- (the ones off greyed, so they stand out from the ones on)
	onColor = { 0.2, 0.8, 0.3, 0.9 }, offColor = { 0.45, 0.45, 0.45, 0.6 },
	linger = 1, -- (up a second after a pick, showing it turn on or off)
	Active = function(entry) return VisionOn(entry.vision) end,
})

-- The master wheel: one icon for each of the other wheels. Picking one opens
-- it round the cursor, waiting for a click. The camera wheel isn't secure:
-- its slot clicks a plain button of ours (no size: never seen) that opens
-- it, out of a fight only (like its own key).
local cameraOpener = CreateFrame("Button")
cameraOpener:SetScript("OnClick", function() ns.OpenCameraWheel() end)
local masterSlots = {
	{ icon = "Interface\\Icons\\INV_Misc_Spyglass_03", trim = true, color = { 1, 0.82, 0.3 }, label = "Camera wheel",
		attributes = { type = "click", clickbutton = cameraOpener },
		Cant = function() return ns.CameraWheelCant() end },
	{ icon = "Interface\\Icons\\INV_Misc_Gear_01", trim = true, color = { 1, 0.82, 0.3 }, label = "Menu wheel",
		opens = CinematicMenuWheel },
	{ icon = ICON .. 8, color = COLORS[8], label = "Marker wheel", opens = markerWheel },
	{ icon = "Interface\\Icons\\Ability_EyeOfTheOwl", trim = true, color = { 0.35, 1, 0.45 }, label = "Vision wheel",
		opens = visionWheel },
}
if CinematicWorldMarkerWheel then
	masterSlots[#masterSlots + 1] = { icon = ICON .. 6, color = COLORS[6], label = "Ground marker wheel",
		opens = CinematicWorldMarkerWheel }
end
MakeWheel({
	name = "CinematicMasterWheel",
	title = "Master wheel",
	binding = "Master wheel (hold)",
	slots = masterSlots,
	-- (Out of a fight: the menu wheel laid out fresh, and who the marker
	-- wheel marks settled from where the cursor is now.)
	OnOpen = function()
		ns.BuildMenuWheel()
		SetUnit(MarkUnit())
	end,
})
-- (The menu wheel opens from the master wheel's snippet too.)
CinematicMenuWheel:SetAttribute("_onattributechanged", OPEN_SNIPPET)

-- (Each secure wheel can put the others away, in a fight too: the menu
-- wheel's snippet reads the same refs.)
local secure = { CinematicMenuWheel }
for _, wheel in ipairs(wheels) do
	secure[#secure + 1] = wheel
end
for _, wheel in ipairs(secure) do
	local others = 0
	for _, other in ipairs(secure) do
		if other ~= wheel then
			others = others + 1
			wheel:SetFrameRef("other" .. others, other)
		end
	end
	wheel:SetAttribute("others", others)
end

-- Scaled like the UI (they aren't in UIParent) out of a fight; and the
-- marker wheel back to the target as a fight starts (just before the
-- lockdown), as a mouseover's token could name someone else by the time the
-- key's next pressed.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("UI_SCALE_CHANGED")
watcher:SetScript("OnEvent", function()
	if InCombatLockdown() then
		return
	end
	for _, wheel in ipairs(wheels) do
		wheel:SetScale(UIParent:GetEffectiveScale())
		wheel.face:SetScale(UIParent:GetEffectiveScale())
	end
	SetUnit("target")
end)
