-- Cinematic: the healer frame (UI Manager > Healer frame). Your group's tank
-- always shown, and next to them everyone else who's lost health, the ones
-- taking the most damage right now first.
--
-- The game keeps group health secret from addons (WoW Forever, and retail in
-- Midnight): this file never knows anyone's health. The game draws it - a
-- status bar and "%" text take secret values - and fades each row by it: the
-- health percent run through a curve (shown below the page's percent, gone
-- above) goes straight into SetAlpha, and another into the row's height, so
-- the rows after a hidden one close up. What the addon can read is each hit
-- and heal as it lands (UNIT_COMBAT, plain even in combat), so the order is by
-- damage taken lately, less healing. Players at full health have none, so they
-- sink to the end, out of sight.
--
-- Clickable rows (the page's Click to target) are secure unit buttons, and in
-- combat the game lets no addon move, size, show or hide those: from the pull
-- the rows stay where they were (full size, so nobody's lost), still fading
-- and highlighting, and sort again once the fight's over. Plain rows (not
-- clickable) keep sorting and closing up all fight.
-- (/cine debug health, healthfade and damage are the tests behind all this.)
-- Work in progress: only in the dev copy (ns.isDev), whatever the settings say.
local _, ns = ...
local L = ns.L

local GAP = 2
local rowWidth, rowHeight = 150, 20 -- each bar, from the page (ns.ApplyHealerFrame)
local TANKS_MAX = 2
local RESORT_EVERY = 0.5  -- seconds between re-orders (any faster and rows jump about)
local UPDATE_EVERY = 0.1
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
-- Each role's corner of the game's role icons.
local ROLE_COORDS = {
	TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
	HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
	DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

local frame, mover
local plainRows, clickRows = {}, {} -- the two kinds of row, each made as needed
local roster = {}       -- { unit, guid, tank } in the group's order, rebuilt on changes
local order = {}        -- the roster's non-tanks in the order they show
local rosterDirty = true
local hurt = {}         -- guid -> damage taken lately, less healing (decaying)
local hurtAt = {}       -- guid -> when that was last worked out
local lastHit = {}      -- guid -> the last hit's time and amount (one hit comes once per unit token)
local fadeCurve, sizeCurve, curvesKey
local canCollapse = true -- whether the game takes a secret row size
local sinceUpdate, sinceSort = 0, 0
local clickShown = false -- clickable rows are up (so the frame is locked in combat)
local pending = false    -- a change waiting for the end of the fight

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

local function Plain(value)
	if Secret(value) then return nil end
	return value
end

-- Your heals over time and shields on a player: small icons next to their bar
-- (right of it, or under it side by side), each with its time running down.
-- The game picks them (your own, and the kind raid frames show) and may keep
-- the icon and times secret: they go straight to the game, never looked at.
-- Read again only when that player's auras change (UNIT_AURA).
local AURA_SIZE, AURA_MAX = 16, 4
local auraFilter = "HELPFUL|PLAYER|RAID"
local auraGeneration = 0 -- goes up when the rows' players may have changed
local aurasDirty = {}    -- unit -> its auras changed since last shown

-- The icons follow the bar's height (16 on the default 20-high bar).
local function AuraScale()
	return math.max(8, rowHeight - 4) / AURA_SIZE
end

local function AuraIcon(row, i)
	local icon = row.auras[i]
	if icon then return icon end
	icon = CreateFrame("Frame", nil, row.body)
	icon:SetSize(AURA_SIZE, AURA_SIZE)
	if i > 1 then
		icon:SetPoint("LEFT", row.auras[i - 1], "RIGHT", 1, 0)
	end
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints()
	icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	icon.cooldown:SetAllPoints()
	icon.cooldown:SetReverse(true)
	icon.cooldown:SetDrawEdge(false)
	if icon.cooldown.SetHideCountdownNumbers then icon.cooldown:SetHideCountdownNumbers(true) end
	icon.count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	icon.count:SetPoint("BOTTOMRIGHT", 2, -1)
	row.auras[i] = icon
	return icon
end

-- The aura's time running down: the game's own duration where it has one
-- (works while the times are secret), else from its plain times.
local function SetAuraTime(icon, unit, aura)
	local id = aura.auraInstanceID
	if C_UnitAuras.GetAuraDuration and icon.cooldown.SetCooldownFromDurationObject and id then
		local ok, duration = pcall(C_UnitAuras.GetAuraDuration, unit, id)
		if ok and duration and pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, duration) then
			return
		end
	end
	local length, ends = Plain(aura.duration), Plain(aura.expirationTime)
	if length and ends and length > 0 then
		icon.cooldown:SetCooldown(ends - length, length)
	else
		icon.cooldown:Clear()
	end
end

-- Stacks (Lifebloom and the like): the game's text where it has it.
local function SetAuraCount(icon, unit, aura)
	local id = aura.auraInstanceID
	if C_UnitAuras.GetAuraApplicationDisplayCount and id then
		local ok, text = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id)
		if ok and pcall(icon.count.SetText, icon.count, text) then return end
	end
	local stacks = Plain(aura.applications)
	icon.count:SetText(stacks and stacks > 1 and stacks or "")
end

-- The game's own aura icons (an AuraContainer, WoW Forever and retail 12.1):
-- given a unit and a filter, the game finds the auras and draws each icon,
-- its time and stacks itself, in combat too, when addons can't read them
-- (UNIT_AURA data comes back empty then). Its buttons can only be set up as
-- the game makes them (initializeFrame); after that they refuse addon calls
-- while auras are secret.
local auraButtons, auraButtonError = 0, nil -- (for /cine debug healer)

local function SetUpAuraButton(button)
	-- (The group's layout only spaces the icons: each button is sized here, or it's 0 by 0.)
	button:SetSize(AURA_SIZE, AURA_SIZE)
	pcall(button.SetMouseClickEnabled, button, false) -- (clicks go to the row)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(button)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints(button)
	cooldown:SetReverse(true)
	cooldown:SetDrawEdge(false)
	if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
	if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
	local holder = CreateFrame("Frame", nil, button)
	holder:SetAllPoints(button)
	holder:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	local count = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetPoint("BOTTOMRIGHT", 2, -1)
	button:SetIcon(icon)
	button:SetDurationCooldown(cooldown)
	button:SetApplicationCount(count, {})
end

local function InitAuraButton(button)
	auraButtons = auraButtons + 1
	local ok, err = pcall(SetUpAuraButton, button)
	if not ok then auraButtonError = tostring(err) end
end

-- The page's "Only buffs shorter than", in seconds. (Up to 10 minutes: older
-- settings could go to 30.)
local function MaxAuraSeconds()
	return math.min(ns.db.healerHotMaxMinutes, 10) * 60
end

-- Which of your buffs a container shows: only ones shorter than the page's
-- time (maxDuration also leaves out buffs with no duration).
local function AuraCandidates()
	return { maxDuration = MaxAuraSeconds() }
end

-- A row's container, or nil where the client has none (the icons are then
-- read and drawn by UpdateAuras below, out of combat only).
local function AuraBox(row)
	if row.auraBox ~= nil then return row.auraBox or nil end
	row.auraBox = false
	if C_AddOns and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end
	local ok, box = pcall(CreateFrame, "AuraContainer", nil, row.body, "CustomAuraContainerTemplate")
	if not ok or not box or not box.AddAuraGroup then
		row.auraBoxError = ok and "made, but no AddAuraGroup" or tostring(box)
		return nil
	end
	box:SetSize(1, 1)
	local axes, flow = AnchorUtil and AnchorUtil.FlowLayoutAxis, AnchorUtil and AnchorUtil.FlowDirection
	if box.SetFlowLayoutAxis and axes then box:SetFlowLayoutAxis(axes.Horizontal) end
	local anchor = box.SetFlowLayoutAnchorPoint or box.SetAuraLayoutAnchorPoint
	if anchor then anchor(box, "TOPLEFT") end
	local grow = box.SetFlowLayoutGrowthDirection or box.SetAuraLayoutGrowthDirection
	if grow and flow then grow(box, flow.Right, flow.Down) end
	local added, err = pcall(box.AddAuraGroup, box, "hots", "HELPFUL|PLAYER", {
		maxFrameCount = AURA_MAX,
		candidateFilters = AuraCandidates(),
		initializeFrame = InitAuraButton,
		layout = { elementWidth = AURA_SIZE, elementHeight = AURA_SIZE, elementSpacing = 1, lineSpacing = 1 },
	})
	if not added then
		row.auraBoxError = "AddAuraGroup: " .. tostring(err)
		box:Hide()
		return nil
	end
	row.auraBox = box
	row.auraBoxMinutes = ns.db.healerHotMaxMinutes
	return box
end

-- Points a row's container at its player, beside the bar; true if it has one.
local function UpdateAuraBox(row, unit)
	local box = AuraBox(row)
	if not box then return false end
	local on = ns.db.healerHots and true or false
	local sideways = ns.db.healerSideways and true or false
	-- (Its buttons can't be resized once made, so the whole box is scaled; its
	-- offsets are in its own scale.)
	local scale = AuraScale()
	if row.auraBoxOn ~= on or row.auraBoxSideways ~= sideways or row.auraBoxScale ~= scale then
		row.auraBoxOn, row.auraBoxSideways, row.auraBoxScale = on, sideways, scale
		box:SetScale(scale)
		box:ClearAllPoints()
		if sideways then
			box:SetPoint("TOPLEFT", row.body, "BOTTOMLEFT", 0, -1 / scale)
		else
			box:SetPoint("TOPLEFT", row.body, "TOPRIGHT", 2 / scale, -2 / scale)
		end
		if box.SetEnabled then pcall(box.SetEnabled, box, on) end
		box:SetShown(on)
	end
	if row.auraBoxMinutes ~= ns.db.healerHotMaxMinutes and box.SetAuraGroupCandidateFilters then
		row.auraBoxMinutes = ns.db.healerHotMaxMinutes
		pcall(box.SetAuraGroupCandidateFilters, box, "hots", AuraCandidates())
	end
	if on and row.auraBoxUnit ~= unit then
		row.auraBoxUnit = unit
		pcall(box.SetUnit, box, unit)
		if box.UpdateAllAuras then pcall(box.UpdateAllAuras, box) end
	end
	return true
end

-- The row's icons for its player, or none (switched off, or no aura API).
local function UpdateAuras(row, unit)
	if UpdateAuraBox(row, unit) then return end
	if row.auraUnit == unit and row.auraGeneration == auraGeneration and not aurasDirty[unit] then return end
	row.auraUnit, row.auraGeneration, aurasDirty[unit] = unit, auraGeneration, nil
	local shown = 0
	if ns.db.healerHots and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local first = row.auras[1] or AuraIcon(row, 1)
		first:ClearAllPoints()
		if ns.db.healerSideways then
			first:SetPoint("TOPLEFT", row.body, "BOTTOMLEFT", 0, -1)
		else
			first:SetPoint("LEFT", row.body, "RIGHT", 2, 0)
		end
		for i = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, auraFilter)
			if not ok and auraFilter ~= "HELPFUL|PLAYER" then
				-- (A client without the RAID filter: all your buffs on them.)
				auraFilter = "HELPFUL|PLAYER"
				ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, auraFilter)
			end
			if not (ok and aura) then break end
			-- (Shorter than the page's minutes; a secret duration shows.)
			local length = Plain(aura.duration)
			local wanted = not length or (length > 0 and length <= MaxAuraSeconds())
			if wanted then
				shown = shown + 1
				local icon = AuraIcon(row, shown)
				icon:SetSize(AURA_SIZE * AuraScale(), AURA_SIZE * AuraScale())
				if not pcall(icon.texture.SetTexture, icon.texture, aura.icon) then
					icon.texture:SetColorTexture(0.2, 0.8, 0.2)
				end
				SetAuraTime(icon, unit, aura)
				SetAuraCount(icon, unit, aura)
				icon:Show()
				if shown >= AURA_MAX then break end
			end
		end
	end
	for i = shown + 1, #row.auras do row.auras[i]:Hide() end
end

-- The rows in use: clickable or plain, as the page says.
local function Rows()
	return ns.db.healerClickable and clickRows or plainRows
end

-- Nothing may move, size, show or hide: clickable rows are up and it's a fight.
local function Locked()
	return clickShown and InCombatLockdown()
end

local function Tank(unit)
	if Plain(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) == "TANK" then return true end
	return IsInRaid() and GetPartyAssignment and Plain(GetPartyAssignment("MAINTANK", unit)) == true
end

local function RebuildRoster()
	rosterDirty = false
	wipe(roster)
	auraGeneration = auraGeneration + 1
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
	else
		if ns.db.healerSelf then units[1] = "player" end
		for i = 1, math.max(0, GetNumGroupMembers() - 1) do units[#units + 1] = "party" .. i end
	end
	local tanks = 0
	for _, unit in ipairs(units) do
		local isYou = Plain(UnitIsUnit(unit, "player")) == true
		if UnitExists(unit) and (ns.db.healerSelf or not isYou) then
			local tank = tanks < TANKS_MAX and Tank(unit)
			if tank then tanks = tanks + 1 end
			local role = tank and "TANK" or Plain(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit))
			roster[#roster + 1] = { unit = unit, guid = Plain(UnitGUID(unit)) or unit, tank = tank,
				role = ROLE_COORDS[role] and role or nil }
		end
	end
end

-- Damage taken lately, less healing: it halves every few seconds (the page's
-- slider), so what counts is what's happening now.
local function Hurt(guid, now)
	local value = hurt[guid]
	if not value then return 0 end
	value = value * 0.5 ^ ((now - hurtAt[guid]) / ns.db.healerWindow)
	hurt[guid], hurtAt[guid] = value, now
	return value
end

local function OnHit(unit, action, amount)
	if Secret(unit) or Secret(action) or type(amount) ~= "number" or Secret(amount) then return end
	if action ~= "WOUND" and action ~= "HEAL" then return end
	if unit ~= "player" and not unit:find("^party%d$") and not unit:find("^raid%d+$") then return end
	local guid = Plain(UnitGUID(unit)) or unit
	-- (In a raid the same hit can come as player, party1 and raid7.)
	local now = GetTime()
	local key = action .. amount
	local last = lastHit[guid]
	if last and last.at == now and last.key == key then return end
	if last then last.at, last.key = now, key else lastHit[guid] = { at = now, key = key } end
	local value = Hurt(guid, now) + (action == "WOUND" and amount or -amount)
	hurt[guid], hurtAt[guid] = math.max(0, value), now
end

-- The game's own answers from health, by the page's percent (100: any lost
-- health; full health is 1): a fade and a size (a row's height, or width side
-- by side, below; 0 above, so the rows after it close up). The fade runs down
-- over the page's last few percent before it (1 below them, 0 at the percent),
-- so a player healed up bit by bit fades out rather than going at once: the
-- addon never knows when they're full, so it can't fade by time. Both are
-- secret; they go straight to SetAlpha and SetHeight.
local function Curves()
	local db = ns.db
	local percent, size = db.healerThreshold, db.healerSideways and rowWidth + GAP or rowHeight + GAP
	local band = db.healerFadeBand
	-- How visible players stay at full health (0: gone, and their slot closes up).
	local floor = db.healerMinAlpha / 100
	local key = percent .. ":" .. size .. ":" .. band .. ":" .. floor
	if curvesKey == key then return fadeCurve, sizeCurve end
	curvesKey, fadeCurve, sizeCurve = key, nil, nil
	if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum.LuaCurveType) then return nil end
	local at = math.min(percent / 100, 0.9995)
	local function Make(below, above, from)
		local ok, curve = pcall(C_CurveUtil.CreateCurve)
		if not ok or not curve then return nil end
		if from and from < at and Enum.LuaCurveType.Linear then
			curve:SetType(Enum.LuaCurveType.Linear)
			curve:AddPoint(0, below)
			curve:AddPoint(from, below)
			curve:AddPoint(at, above)
			curve:AddPoint(1, above)
		else
			curve:SetType(Enum.LuaCurveType.Step)
			curve:AddPoint(0, below)
			curve:AddPoint(at, above)
		end
		return curve
	end
	fadeCurve = Make(1, floor, math.max(0, at - band / 100))
	-- (Still a little visible: the slot stays.)
	sizeCurve = floor <= 0 and Make(size, 0) or nil
	return fadeCurve, sizeCurve
end

-- A bright edge round a row (your target).
local function Edges(parent, r, g, b)
	local edges = CreateFrame("Frame", nil, parent)
	edges:SetPoint("TOPLEFT", -1, 1)
	edges:SetPoint("BOTTOMRIGHT", 1, -1)
	edges:SetFrameLevel(parent:GetFrameLevel() + 5)
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
		{ "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local line = edges:CreateTexture(nil, "OVERLAY")
		line:SetColorTexture(r, g, b, 1)
		line:SetPoint(side[1])
		line:SetPoint(side[2])
		if side[1]:sub(1, 3) == side[2]:sub(1, 3) then line:SetHeight(2) else line:SetWidth(2) end
	end
	return edges
end

local function Row(i)
	local pool = Rows()
	if pool[i] then return pool[i] end
	local row
	if pool == clickRows then
		-- Left click targets, right click the unit's menu; click-casting
		-- addons (Clique and the like) pick it up through ClickCastFrames.
		row = CreateFrame("Button", nil, frame, "SecureUnitButtonTemplate")
		row:RegisterForClicks("AnyUp")
		row:SetAttribute("type1", "target")
		row:SetAttribute("type2", "togglemenu")
		ClickCastFrames = ClickCastFrames or {}
		ClickCastFrames[row] = true
	else
		row = CreateFrame("Frame", nil, frame)
	end
	-- The row's own alpha is the health fade; body's is the range dimming (they
	-- multiply). The row is a slot (with the gap after it) that can shrink to
	-- nothing; body stays its full size inside it.
	row.body = CreateFrame("Frame", nil, row)
	row.body:SetPoint("TOPLEFT")
	row.body:SetSize(rowWidth, rowHeight)
	local back = row.body:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.6)
	row.bar = CreateFrame("StatusBar", nil, row.body)
	row.bar:SetPoint("TOPLEFT", 1, -1)
	row.bar:SetPoint("BOTTOMRIGHT", -1, 1)
	row.bar:SetStatusBarTexture(BAR_TEXTURE)
	-- Incoming heals: a lighter bar from the end of the health, as long as the
	-- healing on its way (all healers'; secret, so straight to the bar), cut
	-- off at the end of the bar.
	local clip = CreateFrame("Frame", nil, row.bar)
	clip:SetAllPoints()
	clip:SetClipsChildren(true)
	row.incoming = CreateFrame("StatusBar", nil, clip)
	row.incoming:SetPoint("TOPLEFT", row.bar:GetStatusBarTexture(), "TOPRIGHT")
	row.incoming:SetPoint("BOTTOMLEFT", row.bar:GetStatusBarTexture(), "BOTTOMRIGHT")
	row.incoming:SetWidth(rowWidth - 2)
	row.incoming:SetStatusBarTexture(BAR_TEXTURE)
	row.incoming:SetStatusBarColor(0.3, 1, 0.5, 0.55)
	-- (The name, % and role icon above the incoming heals.)
	local texts = CreateFrame("Frame", nil, row.bar)
	texts:SetAllPoints()
	texts:SetFrameLevel(row.incoming:GetFrameLevel() + 1)
	row.name = texts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetPoint("RIGHT", -36, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.text = texts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("RIGHT", -4, 0)
	-- The role icon, at the start of the bar (the name moves over for it).
	row.role = texts:CreateTexture(nil, "OVERLAY")
	row.role:SetSize(14, 14)
	row.role:SetPoint("LEFT", 2, 0)
	row.role:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
	row.role:Hide()
	row.target = Edges(row.body, 1, 0.82, 0)
	row.target:SetAlpha(0)
	row.auras = {}
	pool[i] = row
	return row
end

-- Each row after the one before, so a row that shrinks to nothing closes the gap.
local function Place(row, previous)
	row:ClearAllPoints()
	if not previous then
		row:SetPoint("TOPLEFT", frame, "TOPLEFT")
	elseif ns.db.healerSideways then
		row:SetPoint("TOPLEFT", previous, "TOPRIGHT")
	else
		row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT")
	end
end

-- A row's slot: full, nothing (empty), or by health (a secret value from the
-- size curve: never compared, only handed to the game). Once the game refuses
-- a secret size (canCollapse false), every row keeps its slot and there are
-- gaps. Left as it is while Locked().
local function Size(row, empty, byHealth)
	if Locked() then return end
	local sideways = ns.db.healerSideways
	local full = sideways and rowWidth + GAP or rowHeight + GAP
	if sideways then row:SetHeight(rowHeight) else row:SetWidth(rowWidth) end
	if type(byHealth) ~= "nil" and canCollapse then
		if pcall(sideways and row.SetWidth or row.SetHeight, row, byHealth) then return end
		canCollapse = false
	end
	local size = empty and 0 or full
	if sideways then row:SetWidth(size) else row:SetHeight(size) end
end

local function UpdateRow(row, entry)
	local unit = entry.unit
	local db = ns.db
	-- (Not `and ... or`: the name can be secret, and a secret can't be tested.)
	if db.healerNames then
		row.name:SetText((UnitName(unit)))
	else
		row.name:SetText("")
	end
	local _, class = UnitClass(unit)
	local color = db.healerClassColors and Plain(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color then
		row.bar:SetStatusBarColor(color.r, color.g, color.b)
	else
		row.bar:SetStatusBarColor(0.1, 0.8, 0.1)
	end
	local dead = Plain(UnitIsDeadOrGhost(unit)) == true
	local offline = Plain(UnitIsConnected(unit)) == false
	pcall(row.bar.SetMinMaxValues, row.bar, 0, UnitHealthMax(unit))
	pcall(row.bar.SetValue, row.bar, (dead or offline) and 0 or UnitHealth(unit))
	-- (type(), not `or 0`: a secret amount can't be tested.)
	local incoming = 0
	if db.healerIncoming and not (dead or offline) and UnitGetIncomingHeals then
		local amount = UnitGetIncomingHeals(unit)
		if type(amount) ~= "nil" then incoming = amount end
	end
	pcall(row.incoming.SetMinMaxValues, row.incoming, 0, UnitHealthMax(unit))
	if not pcall(row.incoming.SetValue, row.incoming, incoming) then row.incoming:SetValue(0) end
	if dead or offline then
		row.text:SetText(dead and L["Dead"] or L["Offline"])
	elseif db.healerPercent and UnitHealthPercent and CurveConstants then
		pcall(row.text.SetFormattedText, row.text, "%d%%", UnitHealthPercent(unit, false, CurveConstants.ScaleTo100))
	else
		row.text:SetText("")
	end
	local role = db.healerRoles and entry.role
	if row.shownRole ~= role then
		row.shownRole = role
		row.role:SetShown(role and true or false)
		if role then row.role:SetTexCoord(unpack(ROLE_COORDS[role])) end
		row.name:SetPoint("LEFT", role and 18 or 4, 0)
	end
	-- The fade and size: tanks always show; the rest only while hurt (the game decides).
	local fade, size = Curves()
	if entry.tank or frame.unlocked then
		row:SetAlpha(1)
		Size(row)
	elseif dead or offline then
		row:SetAlpha(0)
		Size(row, true)
	elseif fade and UnitHealthPercent then
		-- (Health as it is, not with heals being cast: those would fade it before they land.)
		if not pcall(row.SetAlpha, row, UnitHealthPercent(unit, false, fade)) then row:SetAlpha(1) end
		if size then Size(row, false, UnitHealthPercent(unit, false, size)) else Size(row) end
	else
		row:SetAlpha(1)
		Size(row)
	end
	-- Out of range: dimmed (also secret; UnitInRange is always false for yourself).
	if db.healerRange and UnitInRange and row.body.SetAlphaFromBoolean and unit ~= "player"
		and Plain(UnitIsUnit(unit, "player")) ~= true then
		if not pcall(row.body.SetAlphaFromBoolean, row.body, UnitInRange(unit), 1, 0.4) then row.body:SetAlpha(1) end
	else
		row.body:SetAlpha(1)
	end
	-- Your target: the edge shows (the answer may be secret; the game decides).
	if not db.healerTargetHighlight then
		row.target:SetAlpha(0)
	else
		local isTarget = UnitIsUnit(unit, "target")
		if type(isTarget) ~= "boolean" or not pcall(row.target.SetAlphaFromBoolean, row.target, isTarget, 1, 0) then
			row.target:SetAlpha(Plain(isTarget) == true and 1 or 0)
		end
	end
	UpdateAuras(row, unit)
end

local function ByHurt(a, b)
	if a.hurt ~= b.hurt then return a.hurt > b.hurt end
	return a.index < b.index
end

local function Sort(now)
	wipe(order)
	for _, entry in ipairs(roster) do
		if not entry.tank then
			entry.hurt = ns.db.healerSort and Hurt(entry.guid, now) or 0
			order[#order + 1] = entry
		end
	end
	if ns.db.healerSort then
		for i, entry in ipairs(order) do entry.index = i end
		table.sort(order, ByHurt)
	end
end

-- Hides every row of a kind (out of combat).
local function HideRows(pool)
	for _, row in ipairs(pool) do
		row:Hide()
		row.entry = nil
	end
end

-- The rows in their order, after the tanks; the frame covers them all (for
-- the drag handle). Not while Locked(): the rows stay as they are.
local function Layout()
	if Locked() then return end
	local pool = Rows()
	HideRows(pool == clickRows and plainRows or clickRows)
	local slot, previous = 0, nil
	local function Add(entry)
		slot = slot + 1
		local row = Row(slot)
		row.entry = entry
		if pool == clickRows and row:GetAttribute("unit") ~= entry.unit then row:SetAttribute("unit", entry.unit) end
		Place(row, previous)
		row:Show()
		previous = row
	end
	for _, entry in ipairs(roster) do
		if entry.tank then Add(entry) end
	end
	for i = 1, math.min(#order, ns.db.healerRows) do Add(order[i]) end
	for i = slot + 1, #pool do
		pool[i]:Hide()
		pool[i].entry = nil
	end
	clickShown = pool == clickRows and slot > 0
	local slots = math.max(1, slot)
	if ns.db.healerSideways then
		frame:SetSize(slots * (rowWidth + GAP) - GAP, rowHeight)
	else
		frame:SetSize(rowWidth, slots * (rowHeight + GAP) - GAP)
	end
end

-- Whether the frame shows: switched on, in a group (or solo, ticked), and
-- you're the healer (unless that's unticked). Always while unlocked to move.
local function Wanted()
	local db = ns.db
	if not (db and db.healerFrame and ns.isDev) or ns.IsSuspended() then return false end
	if db.healerUnlocked then return true end
	if not IsInGroup() and not db.healerSolo then return false end
	if db.healerOnlyHealer and IsInGroup() then
		return Plain(UnitGroupRolesAssigned("player")) == "HEALER"
	end
	return true
end

local function OnUpdate(_, elapsed)
	sinceUpdate, sinceSort = sinceUpdate + elapsed, sinceSort + elapsed
	if sinceUpdate < UPDATE_EVERY then return end
	sinceUpdate = 0
	-- (Stopped with the rest of the addon after an error kept repeating.)
	if ns.IsSuspended() then
		if Locked() then frame:SetAlpha(0) else frame:Hide() end
		return
	end
	if not Locked() then
		local changed = rosterDirty
		if changed then RebuildRoster() end
		if changed or sinceSort >= RESORT_EVERY then
			sinceSort = 0
			Sort(GetTime())
			Layout()
		end
	end
	for _, row in ipairs(Rows()) do
		if row:IsShown() and row.entry then UpdateRow(row, row.entry) end
	end
end

local function SavePosition()
	local point, _, relative, x, y = frame:GetPoint(1)
	ns.db.healerPosition = { point = point, relative = relative, x = x, y = y }
end

local function MakeFrame()
	frame = CreateFrame("Frame", "CinematicHealerFrame", UIParent)
	frame:SetSize(rowWidth, rowHeight)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetScript("OnUpdate", OnUpdate)
	frame:Hide()
	-- The drag handle while unlocked: over the frame and its title, above
	-- everything (the settings window too), so nothing takes the click.
	mover = CreateFrame("Frame", nil, frame)
	mover:SetPoint("TOPLEFT", -4, 18)
	mover:SetPoint("BOTTOMRIGHT", 4, -4)
	mover:SetFrameStrata("FULLSCREEN_DIALOG")
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:SetScript("OnDragStart", function()
		if not Locked() then frame:StartMoving() end
	end)
	mover:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		SavePosition()
	end)
	local back = mover:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.1, 0.4, 0.1, 0.5)
	local title = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", 4, -3)
	title:SetText(L["Healer frame: drag to move"])
	mover:Hide()
end

-- Shown or not (after the group changes, and from ns.ApplyHealerFrame); in a
-- fight with clickable rows, once it's over.
local function UpdateShown()
	if not frame then return end
	rosterDirty = true
	if Locked() then
		pending = true
		return
	end
	if Wanted() then
		frame:SetAlpha(1)
		frame:Show()
		RebuildRoster()
		Sort(GetTime())
		Layout()
		sinceUpdate = UPDATE_EVERY
	else
		frame:Hide()
		HideRows(clickRows)
		clickShown = false
	end
end

-- After a setting changes: shown or not, where, how big, unlocked to move
-- (in a fight with clickable rows, once it's over).
function ns.ApplyHealerFrame()
	local db = ns.db
	if not db then return end
	if not frame then
		if not (db.healerFrame and ns.isDev) then return end
		MakeFrame()
	end
	if Locked() then
		pending = true
		return
	end
	frame.unlocked = db.healerFrame and db.healerUnlocked
	mover:SetShown(frame.unlocked and true or false)
	frame:SetScale(db.healerScale)
	-- Each bar's size (the slots follow it as they're laid out and sized).
	rowWidth, rowHeight = db.healerBarWidth, db.healerBarHeight
	for _, pool in ipairs({ plainRows, clickRows }) do
		for _, row in ipairs(pool) do
			row.body:SetSize(rowWidth, rowHeight)
			row.incoming:SetWidth(rowWidth - 2)
		end
	end
	local position = db.healerPosition
	frame:ClearAllPoints()
	if position then
		frame:SetPoint(position.point, UIParent, position.relative, position.x, position.y)
	else
		frame:SetPoint("LEFT", UIParent, "CENTER", -350, 100)
	end
	curvesKey = nil
	auraGeneration = auraGeneration + 1
	UpdateShown()
end

-- The pull, just before the lock: one last order, and every clickable row at
-- full size, as none can grow once it's on.
local function BeforeFight()
	if not (frame and frame:IsShown() and ns.db.healerClickable) then return end
	if rosterDirty then RebuildRoster() end
	Sort(GetTime())
	Layout()
	for _, row in ipairs(clickRows) do
		if row:IsShown() then Size(row) end
	end
end

-- /cine debug healer: each row's player and its aura icons' container.
function ns.HealerDebug()
	local function Show(value)
		if Secret(value) then return "secret" end
		return tostring(value)
	end
	if not frame then
		ns.Print("healer frame: not made (switched off since login)")
		return
	end
	ns.Print(("healer frame: shown %s, clickable %s, locked %s, HoTs %s, Blizzard_AuraContainer loaded %s,"
		.. " aura buttons made %d%s"):format(tostring(frame:IsShown()), tostring(ns.db.healerClickable),
		tostring(Locked()), tostring(ns.db.healerHots),
		tostring(C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")),
		auraButtons, auraButtonError and (", button error: " .. auraButtonError) or ""))
	for i, row in ipairs(Rows()) do
		if row:IsShown() and row.entry then
			local box = row.auraBox
			local state
			if box then
				local okUnit, unit = pcall(box.GetUnit, box)
				local width, height = box:GetSize()
				-- Its icon buttons: how many, and what the last few (the ones the game
				-- hands out first) say of themselves (maybe secret).
				local children = { box:GetChildren() }
				local buttons, shown = #children, {}
				for j = buttons, math.max(1, buttons - 3), -1 do
					local child = children[j]
					local okShown, isShown = pcall(child.IsShown, child)
					local okVisible, isVisible = pcall(child.IsVisible, child)
					local okWidth, childWidth = pcall(child.GetWidth, child)
					shown[#shown + 1] = ("[%s/%s %s]"):format(okShown and Show(isShown) or "denied",
						okVisible and Show(isVisible) or "denied", okWidth and Show(childWidth) or "denied")
				end
				state = ("container shown %s, visible %s, unit %s, size %s x %s, alpha %s, %d buttons, last: %s"):format(
					Show(box:IsShown()), Show(box:IsVisible()), okUnit and Show(unit) or "?",
					Show(width), Show(height), Show(box:GetAlpha()), buttons, table.concat(shown, " "))
			elseif box == false then
				state = "no container: " .. tostring(row.auraBoxError)
			else
				state = "container not made yet"
			end
			print(("  %d. %s (%s): %s"):format(i, row.entry.unit, Show(UnitName(row.entry.unit)), state))
		end
	end
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "UNIT_COMBAT", "UNIT_AURA",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
	pcall(watcher.RegisterEvent, watcher, event) -- (not every client has every event)
end
watcher:SetScript("OnEvent", function(_, event, ...)
	if event == "UNIT_AURA" then
		local unit = ...
		if not Secret(unit) and unit then aurasDirty[unit] = true end
	elseif event == "UNIT_COMBAT" then
		if frame and frame:IsShown() and ns.db.healerSort then OnHit(...) end
	elseif event == "PLAYER_REGEN_DISABLED" then
		BeforeFight()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then
			pending = false
			ns.ApplyHealerFrame()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		ns.ApplyHealerFrame()
	else
		-- (Not the position: in a group these come often, and would stop a drag.)
		if event == "GROUP_ROSTER_UPDATE" then wipe(lastHit) end
		UpdateShown()
	end
end)
