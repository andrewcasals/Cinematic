-- Cinematic: Roll Vision, a window of the group's loot rolls (rollWindow, the
-- Vision hub's General page), so you needn't read them in chat. Each item
-- rolled on gets a card: its icon and name, a bar for the time left, and a
-- row for each player with what they picked (need, greed, transmog) and, once
-- the rolls are revealed, their number. The winner goes to the top, lit;
-- passes share one line. In a raid a card lists only the top few: clicking
-- it lists everyone (and every pass), clicking again goes back. The window opens as a roll starts and goes again a
-- while after the last one's done. /cine rolls shows the latest ones.
--
-- The rolls come from the game's loot history (C_LootHistory, what /loot
-- shows): the server tells the whole group everyone's choice and number.
-- Clients without it get nothing here (the options hide).
local _, ns = ...
local L = ns.L

local History = C_LootHistory
if not (History and History.GetSortedInfoForDrop and History.GetSortedDropsForEncounter) then
	return
end
ns.hasRollWindow = true

local WIDTH = 280
local ICON = 34
local ROW = 16
local MAX_CARDS = 8    -- newest first; older ones drop off the end (rollMaxPanels, up to this)
local PER_COLUMN = 4   -- ...this many down, the rest in a second column to the right
local MAX_PASSED = 4   -- names on the "Passed:" line; more (a raid), and it's only the count
local LINGER = 3       -- seconds a roll's panel stays once it's won (or all passed), the mouse off them

local State = Enum and Enum.EncounterLootDropRollState or {}
local NEED, NEED_OFF, TRANSMOG, GREED, NO_ROLL, PASS =
	State.NeedMainSpec or 0, State.NeedOffSpec or 1, State.Transmog or 2, State.Greed or 3,
	State.NoRoll or 4, State.Pass or 5
local ORDER = { [NEED] = 1, [NEED_OFF] = 2, [TRANSMOG] = 3, [GREED] = 4, [NO_ROLL] = 5, [PASS] = 6 }

local DICE = "Interface\\Buttons\\UI-GroupLoot-Dice-Up"
local COIN = "Interface\\Buttons\\UI-GroupLoot-Coin-Up"
local TRANSMOG_ATLAS = "lootroll-toast-icon-transmog-up"

local function Enabled()
	return ns.Setting("rollWindow")
end

-- Player rows per card: everyone in a party; in a raid, the top few
-- (rollRaidRows), the rest as "and N more".
local function MaxRows()
	if IsInRaid and IsInRaid() then
		return ns.Setting("rollRaidRows") or 3
	end
	return 5
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

-- "Name-Realm" -> "Name".
local function ShortName(name)
	if type(name) ~= "string" or Secret(name) then
		return name
	end
	return name:match("^[^%-]+") or name
end

local function ClassText(name, class)
	local color = type(class) == "string" and not Secret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	name = ShortName(name) or "?"
	if color and color.colorStr and not Secret(name) then
		return "|c" .. color.colorStr .. name .. "|r"
	end
	return name
end

local function ItemIcon(link)
	local id = type(link) == "string" and not Secret(link) and tonumber(link:match("item:(%d+)"))
	if not id then
		return 134400 -- the question mark
	end
	local GetIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon
	return GetIcon and GetIcon(id) or 134400
end

-- [Name] in its quality colour, without the brackets.
local function ItemText(link)
	if type(link) ~= "string" or Secret(link) then
		return link
	end
	return (link:gsub("|h%[(.-)%]|h", "|h%1|h"))
end

local function Done(info)
	return info.winner ~= nil or info.allPassed
end

-- The loot history's clock isn't documented: its "now" may count in seconds
-- or milliseconds. The first unfinished roll seen picks the one that puts it
-- inside its time; then that one's kept.
local CLOCKS = {
	function() return History.GetLootHistoryTime() end,
	function() return History.GetLootHistoryTime() * 1000 end,
	function() return History.GetLootHistoryTime() / 1000 end,
	function() return GetTime() end,
	function() return GetTime() * 1000 end,
	function() return time() end,
}
local clock -- the CLOCKS entry that fits, once found

local function Gone(now, info)
	return (now - info.startTime) / info.duration
end

-- The share of the roll's time gone, 0 to 1, or nil if it can't be told.
local function TimeGone(info)
	local start, duration = info.startTime, info.duration
	if type(start) ~= "number" or type(duration) ~= "number" or duration <= 0 or Secret(start) then
		return nil
	end
	if info.testClock then
		return math.min(math.max(Gone(GetTime(), info), 0), 1)
	end
	if not clock then
		for _, candidate in ipairs(CLOCKS) do
			local ok, now = pcall(candidate)
			if ok and type(now) == "number" then
				local gone = Gone(now, info)
				if gone >= -0.05 and gone <= 1.05 then
					clock = candidate
					break
				end
			end
		end
		if not clock then
			return nil
		end
	end
	local ok, now = pcall(clock)
	if not ok or type(now) ~= "number" then
		return nil
	end
	return math.min(math.max(Gone(now, info), 0), 1)
end

-- The item's quality (0 poor to 5 legendary...), from its link or the item
-- cache, or nil if it can't be told yet.
local function ItemQuality(link)
	if type(link) ~= "string" or Secret(link) then
		return nil
	end
	local quality = tonumber(link:match("|cnIQ(%d+):"))
	if quality then
		return quality
	end
	if C_Item and C_Item.GetItemQualityByID then
		local ok, value = pcall(C_Item.GetItemQualityByID, link)
		if ok and type(value) == "number" then
			return value
		end
	end
	local color = link:match("|c(%x%x%x%x%x%x%x%x)")
	for q, info in pairs(ITEM_QUALITY_COLORS or {}) do
		if color and info.hex and info.hex:lower():find(color:lower(), 1, true) then
			return q
		end
	end
end

local function Panels()
	return math.max(1, math.min(MAX_CARDS, ns.Setting("rollMaxPanels") or MAX_CARDS))
end

-- Its tooltip has a line in red (the armour or weapon type you can't wear,
-- another class's, a level you're not): you can't use it. Nil while the
-- game can't say (not loaded yet, or no tooltip data on this client).
local function Red(color)
	local r, g, b = color and color.r, color and color.g, color and color.b
	return type(r) == "number" and type(g) == "number" and type(b) == "number"
		and not (Secret(r) or Secret(g) or Secret(b)) and r > 0.99 and g < 0.2 and b < 0.2
end
local function Unusable(link)
	if type(link) ~= "string" or Secret(link) or link:find("|Hitem:0|h", 1, true)
		or not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then
		return nil
	end
	local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
	local lines = ok and type(data) == "table" and data.lines
	if type(lines) ~= "table" or #lines < 2 then
		return nil
	end
	for i = 2, #lines do -- (not the name)
		local line = lines[i]
		if type(line) == "table" and (Red(line.leftColor) or Red(line.rightColor)) then
			return true
		end
	end
	return false
end

-- Good enough for a panel (rollMinQuality; rollUsableOnly, ones you can
-- use); an item not known yet is.
local function Wanted(info)
	local quality = ItemQuality(info.itemHyperlink)
	if quality and quality < (ns.Setting("rollMinQuality") or 0) then
		return false
	end
	return not (ns.Setting("rollUsableOnly") and Unusable(info.itemHyperlink))
end

-- The item's quality colour, from its link (either way links colour it), else white.
local function QualityColor(link)
	if type(link) ~= "string" or Secret(link) then
		return 1, 1, 1
	end
	local quality = tonumber(link:match("|cnIQ(%d+):"))
	if quality then
		local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		if color then
			return color.r, color.g, color.b
		end
	end
	local r, g, b = link:match("|c%x%x(%x%x)(%x%x)(%x%x)")
	if r then
		return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
	end
	return 1, 1, 1
end

-- A left-to-right fade of one colour.
local function Gradient(texture, r, g, b, fromAlpha, toAlpha)
	texture:SetColorTexture(1, 1, 1, 1)
	if texture.SetGradient and CreateColor then
		texture:SetGradient("HORIZONTAL", CreateColor(r, g, b, fromAlpha), CreateColor(r, g, b, toAlpha))
	elseif texture.SetGradientAlpha then
		texture:SetGradientAlpha("HORIZONTAL", r, g, b, fromAlpha, r, g, b, toAlpha)
	else
		texture:SetColorTexture(r, g, b, (fromAlpha + toAlpha) / 2)
	end
end

local function FadeIn(frame, seconds)
	local fade = frame:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(seconds)
	alpha:SetSmoothing("OUT")
	return fade
end

---------------------------------------------------------------------------
-- The window: dark and flat, a thin gold rule under the title; each item a
-- card washed in its quality colour, a stripe of it down the left.

local CARD_W = WIDTH
local GAP = 6                        -- between the roll panels
local INSET = 8                      -- inside a card
local HEAD = ICON + 2 * INSET        -- a card's icon row
local GOLD = { 1, 0.82, 0 }
local CROWN = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
-- The game hands over every number at once (when all have picked, or time's
-- up): they're revealed one by one, lowest first, the winner last.
local REVEAL_GAP = 0.35

local window
local DismissCard, DragStack, RemoveDrop, FindDrop, Layout -- (below: they need the window's insides)
local cards = {}    -- the card frames, reused
local shown = {}    -- the drops on show, newest first: { key, encounterID, lootListID, info }
local pinned = false -- opened with /cine rolls: stays until closed
local testing        -- the test's fake drops, while it runs
local dismissed = {} -- drops whose window was closed by hand mid-roll: not brought back for them

local function SetStateIcon(texture, state)
	texture:SetDesaturated(false)
	texture:SetVertexColor(1, 1, 1)
	if state == TRANSMOG and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(TRANSMOG_ATLAS) then
		texture:SetAtlas(TRANSMOG_ATLAS)
	elseif state == NEED or state == NEED_OFF then
		texture:SetTexture(DICE)
		if state == NEED_OFF then
			texture:SetVertexColor(0.65, 0.75, 1) -- (off spec: a cooler dice)
		end
	elseif state == GREED or state == TRANSMOG then
		texture:SetTexture(COIN)
	else
		texture:SetTexture(nil)
	end
end

local function StateName(state)
	if state == NEED then return L["Need"]
	elseif state == NEED_OFF then return L["Need (off spec)"]
	elseif state == TRANSMOG then return L["Transmog"]
	elseif state == GREED then return L["Greed"]
	elseif state == PASS then return L["Pass"]
	end
	return L["Choosing..."]
end

local function SortRolls(a, b)
	if (a.isWinner and true or false) ~= (b.isWinner and true or false) then
		return a.isWinner and true or false
	end
	local ra, rb = type(a.roll) == "number" and a.roll or -1, type(b.roll) == "number" and b.roll or -1
	if ra ~= rb then
		return ra > rb
	end
	local oa, ob = ORDER[a.state] or 9, ORDER[b.state] or 9
	if oa ~= ob then
		return oa < ob
	end
	return tostring(ShortName(a.playerName)) < tostring(ShortName(b.playerName))
end

-- A one-pixel line.
local function Line(parent, layer, r, g, b, a)
	local line = parent:CreateTexture(nil, layer)
	line:SetColorTexture(r, g, b, a)
	return line
end

-- How far in from a panel's edge its rounded border reaches.
local RIM = 4
local EDGE = 22

-- Near-black behind a frame, in the game's rounded roll-frame border (tinted
-- by quality, as its roll frames are, with a dark line round the outside);
-- returns the border, for its colour.
local function Panel(frame)
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -3)
	bg:SetPoint("TOPLEFT", RIM, -RIM)
	bg:SetPoint("BOTTOMRIGHT", -RIM, RIM)
	bg:SetColorTexture(0.03, 0.03, 0.04, 0.88)
	local function Edge(outset)
		local edge = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
		edge:SetPoint("TOPLEFT", -outset, outset)
		edge:SetPoint("BOTTOMRIGHT", outset, -outset)
		edge:SetFrameLevel(frame:GetFrameLevel())
		edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = EDGE })
		return edge
	end
	Edge(2):SetBackdropBorderColor(0, 0, 0, 0.9)
	local border = Edge(0)
	border:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
	return border
end

-- A small grey x in the top right corner, lighter on hover.
local function CloseButton(parent, onClick)
	local close = CreateFrame("Button", nil, parent)
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", -5, -5)
	for _, angle in ipairs({ 45, -45 }) do
		local bar = Line(close, "ARTWORK", 0.6, 0.6, 0.6, 1)
		bar:SetSize(18, 2)
		bar:SetPoint("CENTER")
		bar:SetRotation(math.rad(angle))
		close[#close + 1] = bar
	end
	close:SetScript("OnEnter", function(self)
		for _, bar in ipairs(self) do bar:SetColorTexture(1, 1, 1, 1) end
	end)
	close:SetScript("OnLeave", function(self)
		for _, bar in ipairs(self) do bar:SetColorTexture(0.6, 0.6, 0.6, 1) end
	end)
	close:SetScript("OnClick", onClick)
	return close
end

local function NewRow(card)
	local row = CreateFrame("Frame", nil, card)
	row:SetSize(CARD_W - 2 * INSET + 4, ROW)
	row.lit = row:CreateTexture(nil, "BACKGROUND", nil, 2)
	row.lit:SetAllPoints()
	Gradient(row.lit, GOLD[1], GOLD[2], GOLD[3], 0.3, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(14, 14)
	row.icon:SetPoint("LEFT", 4, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.roll = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.roll:SetPoint("RIGHT", -4, 0)
	row.roll:SetJustifyH("RIGHT")
	-- A number arriving pops in: from big and faint to its size.
	row.pop = row.roll:CreateAnimationGroup()
	local grow = row.pop:CreateAnimation("Scale")
	if grow.SetScaleFrom then
		grow:SetScaleFrom(1.8, 1.8)
		grow:SetScaleTo(1, 1)
	else
		grow:SetFromScale(1.8, 1.8)
		grow:SetToScale(1, 1)
	end
	grow:SetOrigin("RIGHT", 0, 0)
	grow:SetDuration(0.25)
	grow:SetSmoothing("OUT")
	local appear = row.pop:CreateAnimation("Alpha")
	appear:SetFromAlpha(0)
	appear:SetToAlpha(1)
	appear:SetDuration(0.2)
	row.crown = row:CreateTexture(nil, "ARTWORK")
	row.crown:SetTexture(CROWN)
	row.crown:SetSize(12, 12)
	row.crown:SetPoint("RIGHT", row.roll, "LEFT", -4, 1)
	row.name:SetPoint("RIGHT", row.crown, "LEFT", -4, -1)
	return row
end

local function NewCard(index)
	local card = CreateFrame("Button", nil, window)
	card:SetWidth(CARD_W)
	card.border = Panel(card) -- (coloured as its item's quality, as the game's roll frames are)
	card.wash = card:CreateTexture(nil, "BACKGROUND", nil, -1)
	card.wash:SetPoint("TOPLEFT", RIM, -RIM)
	card.wash:SetPoint("BOTTOMLEFT", RIM, RIM)
	card.wash:SetWidth(CARD_W * 0.75)
	-- The icon in a thin frame of its quality colour.
	card.frame = card:CreateTexture(nil, "BORDER")
	card.frame:SetSize(ICON + 2, ICON + 2)
	card.frame:SetPoint("TOPLEFT", INSET + 1, -INSET + 1)
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(ICON, ICON)
	card.icon:SetPoint("CENTER", card.frame)
	card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	card.item = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	card.item:SetPoint("TOPLEFT", card.frame, "TOPRIGHT", 9, -3)
	card.item:SetPoint("RIGHT", card, "RIGHT", -(INSET + 20), 0)
	card.item:SetJustifyH("LEFT")
	card.item:SetWordWrap(false)
	-- (compact, under the game's roll frame: just the name, small, to tell which one it is)
	card.itemSmall = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.itemSmall:SetPoint("TOPLEFT", INSET + 2, -INSET)
	card.itemSmall:SetPoint("RIGHT", card, "RIGHT", -(INSET + 20), 0)
	card.itemSmall:SetJustifyH("LEFT")
	card.itemSmall:SetWordWrap(false)
	card.status = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.status:SetPoint("TOPLEFT", card.item, "BOTTOMLEFT", 0, -5)
	card.status:SetPoint("RIGHT", card, "RIGHT", -INSET, 0)
	card.status:SetJustifyH("LEFT")
	card.status:SetWordWrap(false)
	card.status:SetTextColor(0.78, 0.78, 0.78)
	-- The time left: a bar across the card under the icon row, draining.
	card.track = card:CreateTexture(nil, "BORDER")
	card.track:SetColorTexture(0, 0, 0, 0.6)
	card.track:SetHeight(5)
	card.track:SetPoint("TOPLEFT", INSET, -(HEAD - 3))
	card.track:SetPoint("TOPRIGHT", -INSET, -(HEAD - 3))
	card.bar = card:CreateTexture(nil, "ARTWORK")
	card.bar:SetHeight(3)
	card.bar:SetPoint("LEFT", card.track, "LEFT", 1, 0)
	card.passed = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.passed:SetJustifyH("LEFT")
	card.passed:SetWidth(CARD_W - 2 * INSET)
	card.fade = FadeIn(card, 0.3)
	-- Fading away once its roll's over; then it's gone.
	card.fadeOut = card:CreateAnimationGroup()
	local out = card.fadeOut:CreateAnimation("Alpha")
	out:SetFromAlpha(1)
	out:SetToAlpha(0)
	out:SetDuration(0.8)
	out:SetSmoothing("IN")
	card.fadeOut:SetScript("OnFinished", function(self)
		local key = card.key
		self:GetParent():SetAlpha(0) -- (until Layout gives it the next one, faded in)
		RemoveDrop(key)
	end)
	-- Its own x: don't care about this one, away it goes. Dragging any moves them all.
	CloseButton(card, function() DismissCard(card) end)
	DragStack(card)
	card.rows = {}
	-- Hovering the icon shows the item; shift-click links it, as the game's item buttons do.
	card.hover = CreateFrame("Button", nil, card)
	card.hover:SetAllPoints(card.frame)
	card.hover:SetScript("OnEnter", function(self)
		if card.link and not card.link:find("|Hitem:0|h", 1, true) then -- (not the test's stand-ins)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetHyperlink(card.link)
			GameTooltip:Show()
		end
	end)
	card.hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
	card.hover:SetScript("OnClick", function() card:GetScript("OnClick")(card) end)
	DragStack(card.hover)
	-- A plain click lists everyone on it, or back to the top few.
	card:SetScript("OnClick", function(self)
		if IsShiftKeyDown() or IsControlKeyDown() then -- (linking it, trying it on)
			if self.link and HandleModifiedItemClick and not self.link:find("|Hitem:0|h", 1, true) then
				HandleModifiedItemClick(self.link)
			end
			return
		end
		local _, drop = FindDrop(self.key)
		if drop and (drop.expanded or self.cut) then
			drop.expanded = not drop.expanded
			Layout()
		end
	end)
	cards[index] = card
	return card
end

-- The status line under the item's name.
local function StatusText(info, chosen, total)
	if info.winner then
		local text = L["%s won"]:format(ClassText(info.winner.playerName, info.winner.playerClass))
		if info.winner.state then
			text = text .. "  |cff999999" .. StateName(info.winner.state) .. "|r"
		end
		return text
	elseif info.allPassed then
		return "|cff999999" .. L["Everyone passed"] .. "|r"
	elseif info.isTied then
		return "|cffffd100" .. L["Tied: rolling again"] .. "|r"
	elseif info.playerRollState == NO_ROLL then
		-- (anyone in on need already? in red, while you choose)
		local needs = 0
		for _, roll in ipairs(info.rollInfos or {}) do
			if not roll.isSelf and (roll.state == NEED or roll.state == NEED_OFF) then
				needs = needs + 1
			end
		end
		if needs > 0 then
			return "|cffff5a4a" .. (needs == 1 and L["1 need"] or L["%d needs"]:format(needs)) .. "|r"
		end
	end
	return L["%d of %d chosen"]:format(chosen, total)
end

-- "." to "..." and round again, for players still choosing.
local function Dots()
	return ("."):rep(math.floor(GetTime() * 2.5) % 3 + 1)
end

-- When each number shows: new ones queue up behind those already waiting,
-- lowest first and the winner last. True while some are still to come.
local function ScheduleReveals(drop, now)
	drop.reveal = drop.reveal or {}
	local fresh = {}
	for _, roll in ipairs(drop.info.rollInfos or {}) do
		if type(roll.roll) == "number" and not drop.reveal[roll.playerName or "?"] then
			fresh[#fresh + 1] = roll
		end
	end
	table.sort(fresh, function(a, b)
		if (a.isWinner and true or false) ~= (b.isWinner and true or false) then
			return b.isWinner and true or false
		end
		return a.roll < b.roll
	end)
	for _, roll in ipairs(fresh) do
		local at = drop.instant and 0 or math.max(now, drop.nextReveal or 0)
		drop.reveal[roll.playerName or "?"] = at
		drop.nextReveal = at + REVEAL_GAP
	end
	return not drop.instant and now < (drop.nextReveal or 0) - REVEAL_GAP
end

-- Its roll is done (or long overdue) and every number's out.
local function Settled(drop)
	return (Done(drop.info) or drop.expired)
		and not (not drop.instant and drop.nextReveal and GetTime() < drop.nextReveal)
end

-- The game doesn't always say a roll's over (no winner, no "all passed"):
-- once its time's up it's asked again each second, and a few seconds on it's
-- taken as over. (Its time can't be told? Three minutes from when it came up.)
local OVERDUE = 5
local function CheckOverdue(drop, now)
	if Done(drop.info) or not drop.encounterID then
		return
	end
	drop.seenAt = drop.seenAt or now
	local gone = TimeGone(drop.info)
	if not (gone and gone >= 1) and now - drop.seenAt < 180 then
		return
	end
	drop.overAt = drop.overAt or now
	if now - (drop.askedAt or 0) >= 1 then
		drop.askedAt = now
		local ok, info = pcall(History.GetSortedInfoForDrop, drop.encounterID, drop.lootListID)
		if ok and type(info) == "table" then
			drop.info = info
		end
	end
	drop.expired = now - drop.overAt > OVERDUE
end

-- You've still to pick on this one: the game's roll frame is up for it.
local function YourChoiceDue(info)
	for _, roll in ipairs(info.rollInfos or {}) do
		if roll.isSelf then
			return roll.state == NO_ROLL
		end
	end
	return false
end

-- Fills a card from a drop; returns its height.
local function FillCard(card, drop)
	local info = drop.info
	local now = GetTime()
	local revealing = ScheduleReveals(drop, now)
	local function Revealed(roll)
		local at = type(roll.roll) == "number" and drop.reveal[roll.playerName or "?"]
		return at and at <= now
	end
	-- (the winner's only shown once every number is out)
	local winner = info.winner and not revealing
	local done = info.allPassed or winner
	local r, g, b = QualityColor(info.itemHyperlink)
	card.link = info.itemHyperlink
	card.icon:SetTexture(info.testIcon or ItemIcon(info.itemHyperlink))
	-- (the game's roll frame, just above, has the icon and name while you
	-- choose: no need for two; the picks so far, and the need count, are what's left)
	local compact = YourChoiceDue(info)
	card.icon:SetShown(not compact)
	card.frame:SetShown(not compact)
	card.hover:SetShown(not compact)
	card.item:SetShown(not compact)
	card.itemSmall:SetShown(compact)
	card.status:ClearAllPoints()
	if compact then
		card.status:SetPoint("TOPLEFT", card.itemSmall, "BOTTOMLEFT", 0, -3)
	else
		card.status:SetPoint("TOPLEFT", card.item, "BOTTOMLEFT", 0, -5)
	end
	card.status:SetPoint("RIGHT", card, "RIGHT", -(INSET + 20), 0)
	card.item:SetText(ItemText(info.itemHyperlink) or "")
	card.itemSmall:SetText(ItemText(info.itemHyperlink) or "")
	card.frame:SetColorTexture(r, g, b, 0.9)
	card.border:SetBackdropBorderColor(r, g, b, done and 0.5 or 1)
	Gradient(card.wash, r, g, b, done and 0.1 or 0.2, 0)
	card.bar:SetColorTexture(r, g, b, 0.9)

	local rolls, passed = {}, {}
	local chosen, total = 0, 0
	for _, roll in ipairs(info.rollInfos or {}) do
		total = total + 1
		if roll.state ~= NO_ROLL then
			chosen = chosen + 1
		end
		if roll.state == PASS and not roll.isWinner then
			passed[#passed + 1] = ShortName(roll.playerName) or "?"
		else
			rolls[#rolls + 1] = roll
		end
	end
	-- (need before greed, as the game decides it; then by the numbers out so
	-- far: rows climb as they come in)
	table.sort(rolls, function(a, b)
		local wa, wb = winner and a.isWinner or false, winner and b.isWinner or false
		if wa ~= wb then
			return wa and true or false
		end
		local oa, ob = ORDER[a.state] or 9, ORDER[b.state] or 9
		if oa ~= ob then
			return oa < ob
		end
		local ra, rb = Revealed(a) and a.roll or -1, Revealed(b) and b.roll or -1
		if ra ~= rb then
			return ra > rb
		end
		return SortRolls(a, b)
	end)
	-- (rollTopPick: only the best pick anyone's made counts, need over greed:
	-- the lower ones can't win, so they're only counted; those still choosing stay)
	local lower = 0
	if ns.Setting("rollTopPick") and not drop.expanded then
		local best
		for _, roll in ipairs(rolls) do
			if roll.state ~= NO_ROLL then
				best = math.min(best or 9, ORDER[roll.state] or 9)
			end
		end
		for i = #rolls, 1, -1 do
			local roll = rolls[i]
			if best and roll.state ~= NO_ROLL and (ORDER[roll.state] or 9) > best and not roll.isWinner
				and not (roll.isSelf and ns.Setting("rollShowSelf")) then
				table.remove(rolls, i)
				lower = lower + 1
			end
		end
	end
	if info.winner and not winner then
		card.status:SetText("|cffffd100" .. L["Rolling..."] .. "|r")
	else
		card.status:SetText(StatusText(info, chosen, total))
	end

	-- (not while the game's roll frame is up for you: it has its own)
	local gone = not Done(info) and not YourChoiceDue(info) and TimeGone(info)
	card.track:SetShown(gone and true or false)
	card.bar:SetShown(gone and gone < 1 or false)
	if gone then
		card.bar:SetWidth(math.max(1, (CARD_W - 2 * INSET - 2) * (1 - gone)))
	end

	local y = compact and -(INSET + 32) or -(HEAD + 6)
	local maxRows = drop.expanded and #rolls or MaxRows()
	-- (rollShowSelf: yours always listed, one row more under the few if it's further down)
	if ns.Setting("rollShowSelf") and maxRows < #rolls then
		for i = maxRows + 1, #rolls do
			if rolls[i].isSelf then
				table.insert(rolls, maxRows + 1, table.remove(rolls, i))
				maxRows = maxRows + 1
				break
			end
		end
	end
	local more = #rolls - maxRows
	for i = 1, math.max(#rolls, #card.rows) do
		local row = card.rows[i]
		local roll = i <= maxRows and rolls[i]
		if roll then
			row = row or NewRow(card)
			card.rows[i] = row
			row:SetPoint("TOPLEFT", INSET - 4, y)
			SetStateIcon(row.icon, roll.state)
			row.name:SetText(ClassText(roll.playerName, roll.playerClass))
			local choosing = roll.state == NO_ROLL
			-- (still choosing: faint, dots ticking; once it's won, the rest step back)
			local won = winner and roll.isWinner
			row.name:SetAlpha(choosing and 0.45 or (done and not won) and 0.7 or 1)
			if Revealed(roll) then
				row.roll:SetText(roll.roll)
				row.roll:SetTextColor(won and GOLD[1] or 0.85, won and GOLD[2] or 0.85, won and GOLD[3] or 0.85)
				-- (just out: it pops in, once)
				drop.popped = drop.popped or {}
				local name = roll.playerName or "?"
				if not drop.popped[name] then
					drop.popped[name] = true
					if not drop.instant then
						row.pop:Stop()
						row.pop:Play()
					end
				end
			elseif type(roll.roll) == "number" then
				row.roll:SetText("") -- (its turn's coming)
			elseif choosing then
				row.roll:SetText(Dots())
				row.roll:SetTextColor(0.5, 0.5, 0.5)
			else
				row.roll:SetText("")
			end
			row.lit:SetShown(won and true or false)
			row.crown:SetShown(won and true or false)
			row:Show()
			y = y - ROW
		elseif row then
			row:Hide()
		end
	end
	local lines = {}
	if more > 0 then
		lines[#lines + 1] = L["and %d more"]:format(more)
	end
	if lower > 0 then
		lines[#lines + 1] = L["Lower picks: %d"]:format(lower)
	end
	if #passed > MAX_PASSED and not drop.expanded then
		lines[#lines + 1] = L["Passed: %s"]:format(#passed)
	elseif #passed > 0 then
		lines[#lines + 1] = L["Passed: %s"]:format(table.concat(passed, ", "))
	end
	-- (something left out: a click lists it all; listed, a click goes back)
	card.cut = more > 0 or lower > 0 or #passed > MAX_PASSED
	if card.cut or drop.expanded then
		lines[#lines + 1] = "|cff808080" .. (drop.expanded and L["Click to show fewer"]
			or L["Click to list everyone"]) .. "|r"
	end
	if #lines > 0 and ns.Setting("rollFooter") then -- (the lines can be turned off; a click still works)
		card.passed:SetText(table.concat(lines, "\n"))
		card.passed:ClearAllPoints()
		card.passed:SetPoint("TOPLEFT", INSET, y - 4)
		card.passed:Show()
		y = y - 4 - card.passed:GetStringHeight()
	else
		card.passed:Hide()
	end
	return -y + INSET
end

Layout = function()
	if not window then
		return
	end
	-- (the window is the first column's width, so it stays put under the
	-- game's roll frames; the second column hangs off its right)
	local y, lowest = 0, 0
	for i = 1, math.max(#shown, #cards) do
		local card = cards[i]
		local drop = shown[i]
		if i == PER_COLUMN + 1 then
			y = 0
		end
		if drop then
			card = card or NewCard(i)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", i > PER_COLUMN and CARD_W + GAP or 0, y)
			card:SetHeight(FillCard(card, drop))
			if card.key ~= drop.key then
				card.fadeOut:Stop() -- (a panel moving up to fill a gap isn't the one that faded)
				card.key = drop.key
			end
			-- (not while it's fading in or out: Layout runs ten times a second while
			-- a roll's on, and that would flash it full each time)
			if not (card.fade:IsPlaying() or card.fadeOut:IsPlaying()) then
				card:SetAlpha(1)
			end
			if not drop.appeared then -- (fades in once, not again when it moves up)
				drop.appeared = true
				card.fade:Play()
			end
			card:Show()
			y = y - card:GetHeight() - GAP
			lowest = math.min(lowest, y)
		elseif card then
			card.key = nil
			card:Hide()
		end
	end
	-- (nothing to show, from /cine rolls: a panel saying so)
	window.empty:SetShown(#shown == 0)
	if #shown == 0 then
		lowest = -window.empty:GetHeight()
	end
	window:SetHeight(math.max(1, -lowest))
end

-- Where our panels go, in UIParent's units (top centre): just under the
-- game's roll frames while they're up (choose there, seeing the picks so far
-- here), else in their place: where they are, else where they were dropped
-- (dragPanels), else where they last were. Nil before any of that.
local lastX, lastTop
local function Number(value)
	return type(value) == "number" and not Secret(value) and value or nil
end

-- The game's roll frames up now (still to pick on): the box round them, in
-- UIParent's units (left, right, top, bottom), or nil. (Their own edges: they
-- don't sit inside GroupLootContainer's.)
local function RollFramesBox()
	local uiScale = UIParent:GetEffectiveScale()
	local left, right, top, bottom
	for i = 1, 10 do
		local frame = _G["GroupLootFrame" .. i]
		if not frame then
			break
		end
		if ns.Flag(frame:IsVisible()) then
			local scale = frame:GetEffectiveScale() / (uiScale > 0 and uiScale or 1)
			local l, r, t, b = Number(frame:GetLeft()), Number(frame:GetRight()), Number(frame:GetTop()),
				Number(frame:GetBottom())
			if l and r and t and b then
				l, r, t, b = l * scale, r * scale, t * scale, b * scale
				left, right = math.min(left or l, l), math.max(right or r, r)
				top, bottom = math.max(top or t, t), math.min(bottom or b, b)
			end
		end
	end
	if left then
		return left, right, top, bottom
	end
end

-- GroupLootContainer's top centre, in UIParent's units: where it is, else
-- where it was dropped (dragPanels). Nil if neither.
local function ContainerTop()
	local box = GroupLootContainer
	if not (box and box.GetPoint) then
		return nil
	end
	local uiScale = UIParent:GetEffectiveScale()
	local scale = box:GetEffectiveScale() / (uiScale > 0 and uiScale or 1)
	local left, top, width = Number(box:GetLeft()), Number(box:GetTop()), Number(box:GetWidth())
	if left and top and width then
		return (left + width / 2) * scale, top * scale
	end
	local spot = ns.PanelSpot and ns.PanelSpot("GroupLootContainer")
	if spot and spot[1] == "TOPLEFT" and spot[2] == "BOTTOMLEFT" and width then
		return (spot[3] + width / 2) * scale, spot[4] * scale
	end
end

-- How far the game's roll frames sat from their container's top centre, last
-- seen (they don't sit inside it): their place once they've gone.
local offsetX, offsetY = 0, 0
local halfWidth -- half the game's roll frames' width, last seen

-- How far right of the game's roll frames' centre ours sit with rollBeside
-- on (their tops level, ours just past their right edge); else 0.
local function BesideShift()
	if not ns.Setting("rollBeside") then
		return 0
	end
	local half = halfWidth
	if not half then
		local width = GroupLootContainer and Number(GroupLootContainer:GetWidth())
		half = width and width > 0 and width / 2 or CARD_W / 2
	end
	return half + GAP + CARD_W / 2
end

local function RollsTop()
	local boxX, boxTop = ContainerTop()
	-- (the game's frames up: just under the lowest, or beside them, and their place remembered)
	local left, right, top, bottom = RollFramesBox()
	if left then
		lastX, lastTop = (left + right) / 2, top
		halfWidth = (right - left) / 2
		if boxX then
			offsetX, offsetY = lastX - boxX, lastTop - boxTop
		end
		if ns.Setting("rollBeside") then
			return lastX + BesideShift(), top
		end
		return lastX, bottom - GAP
	end
	if boxX then
		lastX, lastTop = boxX + offsetX, boxTop + offsetY
	end
	return lastX and lastX + BesideShift(), lastTop
end

local ownDrag = false -- dragging our panels on their own (the game's frames have no place yet)

-- With rollSeparate on, our panels have a place of their own, apart from the
-- game's roll frames: where last dropped (rollSpot, their top centre in
-- UIParent's units). Never dropped, they come up by the game's frames as usual.
local function OwnSpot()
	local spot = ns.Setting("rollSeparate") and ns.db and ns.db.rollSpot
	if type(spot) == "table" and type(spot[1]) == "number" and type(spot[2]) == "number" then
		return spot[1], spot[2]
	end
end

-- Where the game's roll frames are (their top, centred), so its frame and
-- then our panel come up in the same spot; else a spot of our own.
local function Place()
	if ownDrag then
		return
	end
	local x, top = OwnSpot()
	if not x then
		x, top = RollsTop()
	end
	if x and (x ~= window.placedX or top ~= window.placedTop) then
		window.placedX, window.placedTop = x, top
		window:ClearAllPoints()
		window:SetPoint("TOP", UIParent, "BOTTOMLEFT", x, top)
		return
	elseif x then
		return
	end
	window.placedX = nil
	window:ClearAllPoints()
	window:SetPoint("LEFT", UIParent, "CENTER", 240, 80)
end

local function Close()
	pinned = false
	testing = nil
	wipe(shown)
	if window then
		window.fadeOut:Stop()
		window:Hide()
		window:SetAlpha(1)
	end
end

-- One roll's panel goes (its x, or its time's up); the last one fades the lot.
local function Remove(key, byHand)
	for i, drop in ipairs(shown) do
		if drop.key == key then
			if byHand and not Done(drop.info) then
				dismissed[key] = true -- (not brought back by its next update)
			end
			if #shown == 1 then
				if byHand then
					Close()
				elseif not window.fadeOut:IsPlaying() then
					window.fadeOut:Play()
				end
				return
			end
			if byHand then
				table.remove(shown, i)
				Layout()
				return
			end
			-- (its panel fades first, then it goes)
			for _, card in ipairs(cards) do
				if card.key == key and card:IsShown() then
					if not card.fadeOut:IsPlaying() then
						card.fadeOut:Play()
					end
					return
				end
			end
			table.remove(shown, i)
			Layout()
			return
		end
	end
end
RemoveDrop = function(key)
	for i, drop in ipairs(shown) do
		if drop.key == key then
			table.remove(shown, i)
			break
		end
	end
	if #shown == 0 then
		Close()
	else
		Layout()
	end
end
DismissCard = function(card)
	if card.key then
		Remove(card.key, true)
	end
end

local elapsed = 0
local function OnUpdate(self, delta)
	Place() -- (keeping up with the game's roll frames, dragged or laid out again)
	elapsed = elapsed + delta
	if elapsed < 0.1 then
		return
	end
	elapsed = 0
	local now = GetTime()
	local busy, hovered = false, self:IsMouseOver()
	for _, card in ipairs(cards) do -- (the second column's outside the window)
		hovered = hovered or (card:IsShown() and card:IsMouseOver())
	end
	for _, drop in ipairs(shown) do
		CheckOverdue(drop, now)
		if Settled(drop) then
			-- (each goes a while after it's settled; not while you're pointing at them)
			drop.settledAt = hovered and now or drop.settledAt or now
			if not pinned and now - drop.settledAt > LINGER then
				Remove(drop.key)
				return
			end
		else
			drop.settledAt = nil
			busy = true
		end
	end
	if busy or hovered then
		if self.fadeOut:IsPlaying() then
			self.fadeOut:Stop()
			self:SetAlpha(1)
		end
		if hovered then -- (pointing at them brings fading panels back)
			for _, card in ipairs(cards) do
				if card.fadeOut:IsPlaying() then
					card.fadeOut:Stop()
					card:SetAlpha(1)
				end
			end
		end
	end
	if busy then
		Layout() -- (the time bars, the dots, the numbers coming in)
	end
end

-- Dropped after dragging on their own: the game's roll frames are given the
-- same spot (their top left, as dragging them saves it), so they stay together.
local function DragStop()
	window:StopMovingOrSizing()
	window:SetUserPlaced(false)
	ownDrag = false
	if ns.Setting("rollSeparate") then -- (apart: only ours moves, and keeps its spot)
		local left, top = Number(window:GetLeft()), Number(window:GetTop())
		if left and top and ns.db then
			ns.db.rollSpot = { left + window:GetWidth() / 2, top }
		end
		window.placedX = nil
		Place()
		return
	end
	local box = GroupLootContainer
	local left, top = window:GetLeft(), window:GetTop()
	if not (box and type(left) == "number" and type(top) == "number") then
		return
	end
	local uiScale = UIParent:GetEffectiveScale()
	local scale = box:GetEffectiveScale() / (uiScale > 0 and uiScale or 1)
	-- (the container sits off from its frames: by as much the other way; and
	-- beside them, ours are off to their right)
	local centre = left + window:GetWidth() / 2 - BesideShift()
	local x = (centre - offsetX) / scale - box:GetWidth() / 2
	if ns.SavePanelSpot then
		ns.SavePanelSpot("GroupLootContainer", { "TOPLEFT", "BOTTOMLEFT", x, (top - offsetY) / scale })
	end
	lastX, lastTop = centre, top
	window.placedX = nil
	Place()
end
DragStack = function(card)
	card:RegisterForDrag("LeftButton")
	-- (tied to the game's roll frames: dragging moves those, and this follows;
	-- while they have no place, this moves and they're put with it. With
	-- rollSeparate on, only this moves)
	local withRolls = false
	card:SetScript("OnDragStart", function()
		local box = GroupLootContainer
		withRolls = not ns.Setting("rollSeparate") and ns.DragRolls and box and type(box:GetLeft()) == "number" and not Secret(box:GetLeft()) or false
		if withRolls then
			ns.DragRolls(true)
		else
			ownDrag = true
			window:StartMoving()
		end
	end)
	card:SetScript("OnDragStop", function()
		if withRolls then
			ns.DragRolls(false)
		elseif ownDrag then
			DragStop()
		end
	end)
end
local function CreateWindow()
	-- (only a holder: each roll is a panel of its own, stacked down from it)
	window = CreateFrame("Frame", "CinematicRolls", UIParent)
	window:SetWidth(CARD_W)
	window:SetFrameStrata("MEDIUM")
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:SetScript("OnUpdate", OnUpdate)

	local empty = CreateFrame("Button", nil, window)
	empty:SetPoint("TOPLEFT")
	empty:SetPoint("TOPRIGHT")
	empty:SetHeight(36)
	Panel(empty)
	local text = empty:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	text:SetPoint("LEFT", INSET + 2, 0)
	text:SetText(L["No rolls yet."])
	CloseButton(empty, function() Close() end)
	DragStack(empty)
	window.empty = empty

	window.fadeIn = FadeIn(window, 0.25)
	window.fadeOut = window:CreateAnimationGroup()
	local out = window.fadeOut:CreateAnimation("Alpha")
	out:SetFromAlpha(1)
	out:SetToAlpha(0)
	out:SetDuration(0.8)
	out:SetSmoothing("IN")
	window.fadeOut:SetScript("OnFinished", function() Close() end)
	window:Hide()
end

local function Show()
	if not window then
		CreateWindow()
	end
	window.fadeOut:Stop()
	window:SetAlpha(1)
	if not window:IsShown() then
		Place()
		window:Show()
		window.fadeIn:Play()
	end
	Layout()
end

---------------------------------------------------------------------------
-- The loot history

local function Key(encounterID, lootListID)
	return tostring(encounterID) .. ":" .. tostring(lootListID)
end

local function ListID(info)
	return info.lootListID or info.lootListKey
end

local function Find(key)
	for i, drop in ipairs(shown) do
		if drop.key == key then
			return i, drop
		end
	end
end
FindDrop = Find

-- A drop the game told us about: refreshed if on show, else added if its roll
-- is still going (finished ones turn up after a reload, or someone else's
-- roll ended: not news). Straight away, so you see the others' picks (a need
-- already in?) while you choose in the game's roll frame, just above.
local function Seen(encounterID, lootListID, info)
	if testing or type(info) ~= "table" then
		return
	end
	local key = Key(encounterID, lootListID)
	local _, drop = Find(key)
	if drop then
		drop.info = info
	elseif not Done(info) and not dismissed[key] and Wanted(info) then
		table.insert(shown, 1, { key = key, encounterID = encounterID, lootListID = lootListID, info = info })
		for i = #shown, Panels() + 1, -1 do
			shown[i] = nil
		end
	else
		return
	end
	Show()
end

local function ScanEncounter(encounterID)
	local ok, drops = pcall(History.GetSortedDropsForEncounter, encounterID)
	if not ok or type(drops) ~= "table" then
		return
	end
	for _, info in ipairs(drops) do
		local listID = ListID(info)
		if listID then
			Seen(encounterID, listID, info)
		end
	end
end

local function AllEncounters()
	local ok, infos = pcall(History.GetAllEncounterInfos)
	return ok and type(infos) == "table" and infos or {}
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event, encounterID, lootListID)
	if not Enabled() then
		return
	end
	if event == "LOOT_HISTORY_UPDATE_DROP" and encounterID and lootListID then
		local ok, info = pcall(History.GetSortedInfoForDrop, encounterID, lootListID)
		if ok then
			Seen(encounterID, lootListID, info)
		end
	elseif event == "LOOT_HISTORY_UPDATE_ENCOUNTER" and encounterID then
		ScanEncounter(encounterID)
	elseif event == "LOOT_HISTORY_CLEAR_HISTORY" and not testing then
		wipe(dismissed)
		Close()
	end
end)
for _, event in ipairs({ "LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_CLEAR_HISTORY" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end

-- /cine rolls: the latest drops, finished or not, until closed (again closes it).
function ns.ToggleRollWindow()
	if window and window:IsShown() and pinned then
		Close()
		return
	end
	testing = nil
	wipe(shown)
	local encounters = AllEncounters()
	for i = #encounters, 1, -1 do -- (oldest first, so the newest ends up on top)
		local encounterID = encounters[i].encounterID
		local ok, drops = pcall(History.GetSortedDropsForEncounter, encounterID)
		if ok and type(drops) == "table" then
			for j = #drops, 1, -1 do
				local listID = ListID(drops[j])
				if listID and Wanted(drops[j]) then
					table.insert(shown, 1, { key = Key(encounterID, listID), encounterID = encounterID,
						lootListID = listID, info = drops[j], instant = Done(drops[j]) })
				end
			end
		end
	end
	for i = #shown, Panels() + 1, -1 do
		shown[i] = nil
	end
	pinned = true
	Show()
end

-- Whether the window is up now (the minimap button's glow).
function ns.RollVisionActive()
	return window and window:IsShown() and true or false
end

-- The setting turned off: away it goes.
function ns.RefreshRollWindow()
	if not Enabled() then
		Close()
	elseif window then
		window.placedX = nil -- (put again: under or beside the game's frames)
	end
end

---------------------------------------------------------------------------
-- The test (button on the options page, /cine rolls test): an uncommon, a
-- rare and an epic made-up drop (the qualities group loot rolls on), with your
-- group (or made-up players) picking and rolling over a few seconds.

local FAKE = { { "Thrall", "SHAMAN" }, { "Jaina", "MAGE" }, { "Varian", "WARRIOR" }, { "Tyrande", "PRIEST" } }
local TEST_QUALITIES = { 2, 3, 4 } -- uncommon, rare, epic
local TEST_ICONS = { [2] = 132662, [3] = 135274, [4] = 133434 } -- a ring, a sword, a necklace: stand-ins
local TEST_COLORS = { [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee" }

-- Something of this quality you're wearing or carrying (real, to hover), else a stand-in.
local function FakeItem(quality)
	for slot = 1, 19 do
		local link = GetInventoryItemLink("player", slot)
		if type(link) == "string" and not Secret(link) and GetInventoryItemQuality("player", slot) == quality then
			return link
		end
	end
	local Container = C_Container
	if Container and Container.GetContainerItemInfo then
		for bag = 0, NUM_BAG_SLOTS or 4 do
			for slot = 1, Container.GetContainerNumSlots(bag) or 0 do
				local info = Container.GetContainerItemInfo(bag, slot)
				if info and info.quality == quality and type(info.hyperlink) == "string"
						and not Secret(info.hyperlink) and info.hyperlink:find("|Hitem:") then
					return info.hyperlink
				end
			end
		end
	end
	local name = _G["ITEM_QUALITY" .. quality .. "_DESC"]
	local text = name and L["%s test item"]:format(name) or L["Test item"]
	return "|c" .. TEST_COLORS[quality] .. "|Hitem:0|h[" .. text .. "]|h|r", TEST_ICONS[quality]
end

-- Your group (made-up players to make five), and you last: the others' picks
-- come in while you're still to choose, as they often do.
local function FakePlayers()
	local players = {}
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) then
			players[#players + 1] = { name = UnitName(unit), class = select(2, UnitClass(unit)) }
		end
	end
	for _, fake in ipairs(FAKE) do
		if #players >= 4 then
			break
		end
		players[#players + 1] = { name = fake[1], class = fake[2] }
	end
	players[#players + 1] = { name = UnitName("player"), class = select(2, UnitClass("player")), isSelf = true }
	return players
end

function ns.TestRollWindow()
	if not Enabled() then
		ns.Print(L["Turn on the loot roll window first."])
		return
	end
	local run = {}
	testing = run
	pinned = false
	wipe(shown)
	local players = FakePlayers()
	local choices = { { GREED, PASS, GREED, PASS, GREED }, { GREED, NEED, PASS, NEED_OFF, GREED },
		{ NEED, TRANSMOG, NEED, GREED, PASS } }
	local now = GetTime()
	for d, quality in ipairs(TEST_QUALITIES) do
		-- (below the window's quality: not shown, as a real one wouldn't be)
		if quality >= (ns.Setting("rollMinQuality") or 0) then
			local link, icon = FakeItem(quality)
			local info = { itemHyperlink = link, testIcon = icon, playerRollState = NO_ROLL, rollInfos = {},
				startTime = now, duration = 12, testClock = true }
			for _, player in ipairs(players) do
				info.rollInfos[#info.rollInfos + 1] = { playerName = player.name, playerClass = player.class,
					isSelf = player.isSelf, state = NO_ROLL }
			end
			table.insert(shown, 1, { key = "test" .. d, info = info, choices = choices[d] })
		end
	end
	Show()
	-- One player picks every so often; then the numbers, then the winner.
	local step = 0
	local function Tick()
		if testing ~= run then
			return
		end
		step = step + 1
		local any = false
		for _, drop in ipairs(shown) do
			local roll = drop.info.rollInfos[step]
			if roll then
				roll.state = drop.choices[step] or PASS
				if roll.isSelf then
					drop.info.playerRollState = roll.state
				end
				any = true
			end
		end
		if not any then
			for _, drop in ipairs(shown) do
				local best
				for _, roll in ipairs(drop.info.rollInfos) do
					if roll.state ~= PASS then
						roll.roll = math.random(1, 100)
						-- (need beats greed whatever the numbers; then the higher number)
						if not best or ORDER[roll.state] < ORDER[best.state]
								or (ORDER[roll.state] == ORDER[best.state] and roll.roll > best.roll) then
							best = roll
						end
					end
				end
				if best then
					best.isWinner = true
					drop.info.winner = best
				else
					drop.info.allPassed = true
				end
			end
			testing = nil -- (it closes as real ones do)
			Layout()
			return
		end
		Layout()
		C_Timer.After(1.2, Tick)
	end
	C_Timer.After(1.2, Tick)
end
