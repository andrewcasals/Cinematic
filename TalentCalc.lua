-- Cinematic: a talent calculator (WoW Forever only). Your class's three trees
-- drawn as the talents window draws them, starting from the talents you
-- have: left click adds a point, right click takes one back, with the level
-- the build needs and the points left, Reset, Undo, and Copy Over Changes to
-- put the plan in the talents window for its own Apply Changes. A button on
-- the talents window opens it in that window's place (talentCalc, on the
-- Quality of life page), and so does /cine talents.
--
-- Forever's talents are one trait tree per class, its three classic trees
-- being groups in it. The talents and where they sit come from the game
-- (C_Traits), and the classic rules are applied here: a row needs 5 points
-- in its tree above it, and a talent with an arrow into it needs the one the
-- arrow comes from at full rank.
local ADDON_NAME, ns = ...

if ns.isRetail then
	return
end

-- The talents window's own layout, read with /cine debug talentart: its
-- talents tab is 1212 by 681 at the foot of a 1218 by 708 window. The
-- calculator draws the same, at the same places, scaled to its window (which
-- takes the talents window's size). Talents are 40 square, 60 apart, the
-- first row's middle 220 down and each tree 400 across.
local WIN_W, WIN_H = 1218, 708
local TAB_W, TAB_H = 1212, 681
local SIZE, STEP = 40, 60
local FIRST_X, FIRST_Y, TREE_W = 113, 220, 400
local DEFAULT_W, DEFAULT_H = WIN_W, WIN_H -- before the talents window has been seen
local PER_ROW = 5         -- points a row needs in its tree, per row above it
local ART = "Interface\\TalentFrame\\"

-- The old talent window's tree pictures by class, in tree order: only where
-- this client has no picture of its own for the class.
local BACKGROUNDS = {
	DRUID = { "DruidBalance", "DruidFeralCombat", "DruidRestoration" },
	HUNTER = { "HunterBeastMastery", "HunterMarksmanship", "HunterSurvival" },
	MAGE = { "MageArcane", "MageFire", "MageFrost" },
	PALADIN = { "PaladinHoly", "PaladinProtection", "PaladinCombat" },
	PRIEST = { "PriestDiscipline", "PriestHoly", "PriestShadow" },
	ROGUE = { "RogueAssassination", "RogueCombat", "RogueSubtlety" },
	SHAMAN = { "ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration" },
	WARLOCK = { "WarlockCurses", "WarlockSummoning", "WarlockDestruction" },
	WARRIOR = { "WarriorArms", "WarriorFury", "WarriorProtection" },
}

-- A talent's border by state, as the talents window's; our own shape, tinted,
-- where this client lacks them (Media/make_talent_ring.py).
local BORDER = { full = "talents-node-square-yellow", open = "talents-node-square-green", shut = "talents-node-square-locked" }
local RING = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\TalentRing"
local GOLD = { 1, 0.82, 0 }        -- a talent at full rank, and the lines from it
local OPEN = { 0.098, 1, 0.098 }   -- one that can take a point (the talents window's green)
local SHUT = { 0.33, 0.33, 0.33 }  -- one that can't yet
local LINE = { 0.1, 0.09, 0.08 }   -- a line from a talent not yet at full rank (near black, as the talents window's)

local function Num(value)
	if type(value) ~= "number" or (issecretvalue and issecretvalue(value)) then
		return nil
	end
	return value
end

local function Enabled()
	return ns.db and ns.db.talentCalc
end

-------------------------------------------------------------------------------
-- The talents
-------------------------------------------------------------------------------
local configID, treeID
local trees = {} -- in tree order: { name, background, talents = { talent... }, rows }
local talents = {} -- nodeID -> { nodeID, tree, col, row, maxRanks, spellID, icon, name, needs = { nodeID... } }
local ranks = {} -- nodeID -> points put in here
local offset = 9 -- a level minus the talent points it gives (the first at 10)
local maxPoints = 51
local MOST_POINTS = 51 -- never more, whatever the level (Talented's own tooltip says so)
local TALENTED_OFFSET = 4 -- with Talented (a Legacy Tree talent), the first point comes at 5
local lastError -- why the talents couldn't be read (/cine debug talentcalc)

-- Positions on one axis -> each one's line, from 0. The game puts talents on
-- a grid, but a few sit a little off their line, so positions closer than a
-- third of the usual gap are the same line; the step is the smallest gap
-- between lines. A position ten times too far out (an extra zero in the
-- game's data) is read at a tenth.
local function Lines(values)
	local sorted = {}
	for _, v in ipairs(values) do sorted[#sorted + 1] = v end
	table.sort(sorted)
	local gaps = {}
	for i = 2, #sorted do
		local gap = sorted[i] - sorted[i - 1]
		if gap > 0 then gaps[#gaps + 1] = gap end
	end
	local first = sorted[1] or 0
	if #gaps == 0 then
		return function() return 0 end, first
	end
	table.sort(gaps)
	local close = gaps[math.floor(#gaps / 2) + 1] / 3
	local step
	for _, gap in ipairs(gaps) do
		if gap > close then
			step = gap
			break
		end
	end
	step = step or gaps[#gaps]
	local function Line(v)
		local line = math.floor((v - first) / step + 0.5)
		if line > 12 then
			local tenth = math.floor((v / 10 - first) / step + 0.5)
			if tenth >= 0 and tenth <= 12 then
				line = tenth
			end
		end
		return math.max(line, 0)
	end
	return Line, first, step
end

local function SpellOf(info)
	local entryID = info.activeEntry and info.activeEntry.entryID or info.entryIDs[1]
	local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
	local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
	if not def then
		return nil
	end
	local spellID = def.spellID
	local icon = def.overrideIcon
	if not icon or icon == 0 then
		icon = spellID and (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
			or GetSpellTexture and GetSpellTexture(spellID))
	end
	local name = def.overrideName
	if not name or name == "" then
		name = spellID and (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
			or GetSpellInfo and GetSpellInfo(spellID))
	end
	return spellID, icon, name, entryID
end

-- The level a number of points needs: a point a level from 10, or from 5
-- with Talented if the tickbox says to count it (ticked when the window
-- opens if you have it yourself).
local function ReadLevels()
	offset = ns.db and ns.db.talentCalcTalented and TALENTED_OFFSET or 9
	local maxLevel = GetMaxLevelForPlayerExpansion and Num(GetMaxLevelForPlayerExpansion())
		or GetMaxPlayerLevel and Num(GetMaxPlayerLevel()) or 60
	maxPoints = math.max(math.min(maxLevel - offset, MOST_POINTS), 0)
end

local function ByOrder(a, b)
	return a.orderIndex < b.orderIndex
end

-- Reads your class's trees (once: they don't change while you play).
local function ReadTalents()
	if treeID and next(talents) then
		ReadLevels()
		return true
	end
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetGroupDisplayInfoByTreeID) then
		lastError = "no talent trees (C_Traits) on this client"
		return false
	end
	configID = C_ClassTalents.GetActiveConfigID()
	local config = configID and C_Traits.GetConfigInfo(configID)
	treeID = config and config.treeIDs and config.treeIDs[1]
	if not treeID then
		lastError = "no talent tree for you yet"
		return false
	end
	local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}
	table.sort(groups, ByOrder)
	local _, class = UnitClass("player")
	local byGroup = {}
	wipe(trees)
	for i, group in ipairs(groups) do
		trees[i] = { index = i, name = group.displayName, talents = {}, rows = 1, cols = 4,
			icon = Num(group.iconFileID) or Num(group.iconID) or group.icon,
			background = BACKGROUNDS[class] and BACKGROUNDS[class][i] }
		byGroup[group.groupID] = trees[i]
	end
	local infos = {}
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
		local info = C_Traits.GetNodeInfo(configID, nodeID)
		if info and info.isVisible and info.entryIDs and info.entryIDs[1] then
			for _, groupID in ipairs(info.groupIDs or {}) do
				local tree = byGroup[groupID]
				if tree then
					local spellID, icon, name, entryID = SpellOf(info)
					local talent = { nodeID = nodeID, tree = tree, maxRanks = info.maxRanks or 1,
						spellID = spellID, icon = icon, name = name, entryID = entryID, needs = {} }
					talents[nodeID] = talent
					tree.talents[#tree.talents + 1] = talent
					infos[nodeID] = info
					break
				end
			end
		end
	end
	if not next(talents) then
		lastError = "the tree has no talents in its groups"
		return false
	end
	-- Each tree's grid, from where its talents sit; and where each tree
	-- starts across, as the talents window places them: by how far its first
	-- column is from the first tree's, at a grid step a step (they aren't
	-- quite 400 apart).
	local firstX, stepX
	for _, tree in ipairs(trees) do
		local xs, ys = {}, {}
		for i, talent in ipairs(tree.talents) do
			xs[i], ys[i] = infos[talent.nodeID].posX, infos[talent.nodeID].posY
		end
		local Col, left, step = Lines(xs)
		local Row = Lines(ys)
		tree.left = left
		firstX = firstX or left
		stepX = stepX or step
		for _, talent in ipairs(tree.talents) do
			talent.col = Col(infos[talent.nodeID].posX)
			talent.row = Row(infos[talent.nodeID].posY)
			tree.rows = math.max(tree.rows, talent.row + 1)
			tree.cols = math.max(tree.cols, talent.col + 1)
		end
	end
	for i, tree in ipairs(trees) do
		local x = stepX and stepX > 0 and (tree.left - firstX) / stepX * STEP
		-- (Where the positions don't say, 400 apart.)
		if not x or x < 0 or x > TAB_W then
			x = (i - 1) * TREE_W
		end
		tree.x = x
	end
	-- The arrows: each talent's edges lead to the ones it unlocks.
	for nodeID, info in pairs(infos) do
		for _, edge in ipairs(info.visibleEdges or {}) do
			local target = talents[edge.targetNode]
			if target then
				target.needs[#target.needs + 1] = nodeID
			end
		end
	end
	lastError = nil
	ReadLevels()
	return true
end

-------------------------------------------------------------------------------
-- The rules
-------------------------------------------------------------------------------
-- Points put in `tree`, in the rows above `row` (all of them without one).
local function SpentIn(tree, row)
	local spent = 0
	for _, talent in ipairs(tree.talents) do
		if not row or talent.row < row then
			spent = spent + (ranks[talent.nodeID] or 0)
		end
	end
	return spent
end

local function Spent()
	local spent = 0
	for _, rank in pairs(ranks) do
		spent = spent + rank
	end
	return spent
end

local function Full(nodeID)
	local talent = talents[nodeID]
	return talent and (ranks[nodeID] or 0) >= talent.maxRanks
end

-- What `talent` is still waiting for: the points its row needs, then each
-- talent it needs at full rank. Nothing when it's open.
local function Missing(talent)
	local missing = {}
	local need = talent.row * PER_ROW
	if SpentIn(talent.tree, talent.row) < need then
		missing[#missing + 1] = ns.L["Requires %d points in %s Talents"]:format(need, talent.tree.name or "")
	end
	for _, nodeID in ipairs(talent.needs) do
		if not Full(nodeID) then
			local other = talents[nodeID]
			missing[#missing + 1] = ns.L["Requires %d points in %s"]:format(other.maxRanks, other.name or "?")
		end
	end
	return missing
end

local function CanAdd(talent)
	return (ranks[talent.nodeID] or 0) < talent.maxRanks and Spent() < maxPoints and #Missing(talent) == 0
end

-- Every talent with points still has what it needs.
local function Valid()
	for nodeID, rank in pairs(ranks) do
		if rank > 0 and #Missing(talents[nodeID]) > 0 then
			return false
		end
	end
	return true
end

local function Add(talent)
	if not CanAdd(talent) then
		return false
	end
	ranks[talent.nodeID] = (ranks[talent.nodeID] or 0) + 1
	return true
end

-- Takes a point back, unless a talent further down needs it.
local function Remove(talent)
	local rank = ranks[talent.nodeID] or 0
	if rank == 0 then
		return false
	end
	ranks[talent.nodeID] = rank > 1 and rank - 1 or nil
	if not Valid() then
		ranks[talent.nodeID] = rank
		return false
	end
	return true
end

-------------------------------------------------------------------------------
-- Your own talents: the plan starts from them, Undo goes back to them, and
-- Copy Over Changes puts what the plan adds in the talents window.
-------------------------------------------------------------------------------
local learned = {} -- nodeID -> ranks you have

-- Your ranks as the game has them.
local function ReadLearned()
	wipe(learned)
	for nodeID, talent in pairs(talents) do
		local info = C_Traits.GetNodeInfo(configID, nodeID)
		local rank = info and (Num(info.ranksPurchased) or Num(info.activeRank)) or 0
		if rank > 0 then
			learned[nodeID] = math.min(rank, talent.maxRanks)
		end
	end
end

-- The points you have to spend.
-- The talent points your level gives you, spent or not (points waiting in
-- the talents window count either way). Whatever gives them: Talented from
-- the Legacy Tree too, if you have it.
local function YourPoints()
	local currency = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
	currency = currency and currency[1]
	return currency and Num(currency.quantity) and Num(currency.spent) and currency.quantity + currency.spent or 0
end

-- Whether you have Talented (any rank), by your points: each rank brings the
-- first point a level sooner, so you have more than a point a level from 10.
-- nil when your points can't tell: below level 9, or at the 51 points both
-- reach by the top level.
local function HasTalented()
	local without = (Num(UnitLevel("player")) or 0) - 9
	if without < 0 or without >= MOST_POINTS then
		return nil
	end
	local yours = YourPoints()
	if yours <= 0 and without > 0 then
		return nil -- (couldn't read them)
	end
	return yours > without
end

local function LoadLearned()
	ReadLearned()
	wipe(ranks)
	for nodeID, rank in pairs(learned) do
		ranks[nodeID] = rank
	end
end

-- Whether the plan differs from your talents.
local function Pending()
	for nodeID in pairs(talents) do
		if (ranks[nodeID] or 0) ~= (learned[nodeID] or 0) then
			return true
		end
	end
	return false
end

-- The points the plan adds to your talents, or nil and why it can't be
-- applied (no reason: it adds nothing).
-- Applies only with nothing you've learned taken out of the plan (no
-- clashing talents) and the plan's points within your level's.
local function ApplyCheck()
	if InCombatLockdown() then
		return nil, ns.L["Not in a fight."]
	end
	local adds = 0
	for nodeID in pairs(talents) do
		local have, want = learned[nodeID] or 0, ranks[nodeID] or 0
		if want < have then
			return nil, ns.L["The plan takes back talents you've learned: only a class trainer can unlearn them."]
		end
		adds = adds + want - have
	end
	if adds == 0 then
		return nil
	end
	-- The plan's level against yours, by the points you really get (with
	-- Talented if you have it, whatever With Legacy says).
	local yours, planned = YourPoints(), Spent()
	if planned > yours then
		local level = Num(UnitLevel("player")) or 0
		local perLevel = yours > 0 and level - yours or 9
		return nil, ns.L["The plan needs level %d; you're level %d."]:format(perLevel + planned, level)
	end
	return adds
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
local window
local Paint

-- A rank's text from the game's talent data. (The spell's own tooltip has
-- the full rank's numbers whatever the rank.)
local function Description(talent, rank)
	if not (talent.entryID and C_Traits.GetTraitDescription) then
		return nil
	end
	local ok, text = pcall(C_Traits.GetTraitDescription, talent.entryID, rank)
	if ok and type(text) == "string" and text ~= "" and not (issecretvalue and issecretvalue(text)) then
		return text
	end
end

local function TalentEnter(button)
	local talent = button.talent
	if not talent then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	local rank = ranks[talent.nodeID] or 0
	local now = Description(talent, math.max(rank, 1))
	if now then
		-- As the talents window: name, rank, Passive, this rank's text (the
		-- first's before any point), then the next rank's.
		GameTooltip:SetText(talent.name or "?", 1, 1, 1)
		GameTooltip:AddLine(ns.L["Rank %d/%d"]:format(rank, talent.maxRanks), 1, 1, 1)
		local passive = talent.spellID and (C_Spell and C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(talent.spellID)
			or IsPassiveSpell and IsPassiveSpell(talent.spellID))
		if passive then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(SPELL_PASSIVE or ns.L["Passive"], 1, 1, 1)
		end
		GameTooltip:AddLine(now, 1, 0.82, 0, true)
		local nextText = rank > 0 and rank < talent.maxRanks and Description(talent, rank + 1)
		if nextText then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(ns.L["Next rank:"], 1, 1, 1)
			GameTooltip:AddLine(nextText, 1, 0.82, 0, true)
		end
		GameTooltip:AddLine(" ")
	elseif talent.spellID then
		GameTooltip:SetSpellByID(talent.spellID)
		GameTooltip:AddLine(ns.L["Rank %d/%d"]:format(rank, talent.maxRanks), 1, 1, 1)
	else
		GameTooltip:SetText(talent.name or "?")
		GameTooltip:AddLine(ns.L["Rank %d/%d"]:format(rank, talent.maxRanks), 1, 1, 1)
	end
	for _, text in ipairs(Missing(talent)) do
		GameTooltip:AddLine(text, 1, 0.1, 0.1, true)
	end
	GameTooltip:AddLine(ns.L["Left-click: add a point. Right-click: take one back."], 0.5, 0.5, 0.5, true)
	GameTooltip:Show()
end

-- The talents window's sounds for adding and taking back a point. Adding is
-- UI_CLASS_TALENT_NODE_SPEND (seen with /cine debug sounds); taking back is
-- found by name in the game's sound list (the first talent node one with
-- these words in it), else the old talent window's.
local SPEND = SOUNDKIT and SOUNDKIT.UI_CLASS_TALENT_NODE_SPEND or 207765
local REFUND_WORDS = { "TALENT_NODE_REFUND", "TALENT_NODE_UNSPEND", "TALENT.*REFUND", "TALENT.*UNSELECT" }
local refund

local function Sound(kind)
	if kind == "add" then
		return SPEND
	end
	if refund == nil then
		refund = false
		for _, words in ipairs(REFUND_WORDS) do
			for name, id in pairs(type(SOUNDKIT) == "table" and SOUNDKIT or {}) do
				if type(name) == "string" and name:find(words) then
					refund = id
					break
				end
			end
			if refund then
				break
			end
		end
	end
	return refund or SOUNDKIT and SOUNDKIT.IG_ABILITY_ICON_DROP
end

local function TalentClick(button, mouse)
	local talent = button.talent
	if not talent then
		return
	end
	local changed
	if mouse == "RightButton" then
		changed = Remove(talent) and "remove"
	else
		changed = Add(talent) and "add"
	end
	local sound = changed and Sound(changed)
	if sound then
		PlaySound(sound)
	end
	Paint()
	if GameTooltip:IsOwned(button) then
		TalentEnter(button)
	end
end

-- The first of these font objects this client has.
local function FirstFont(...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if _G[name] then
			return name
		end
	end
end

-- An atlas, if this client has it (true), else nothing changes (false).
local function Atlas(texture, name)
	if not (texture.SetAtlas and pcall(texture.SetAtlas, texture, name)) then
		return false
	end
	local set = texture:GetAtlas()
	return type(set) == "string" and set:lower() == name:lower()
end

-- A talent, as the talents window draws one: its shadow, the icon, a dark
-- cover while it's shut, the border by state, a faint green glow while it
-- can take a point, and its rank in the corner.
local function NewTalent(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(SIZE, SIZE)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button.shadow = button:CreateTexture(nil, "BACKGROUND")
	button.shadow:SetSize(78, 78)
	button.shadow:SetPoint("CENTER")
	if not Atlas(button.shadow, "talents-node-square-shadow") then
		button.shadow:Hide()
	end
	button.icon = button:CreateTexture(nil, "BORDER")
	button.icon:SetSize(36, 36)
	button.icon:SetPoint("CENTER")
	button.cover = button:CreateTexture(nil, "BORDER", nil, 1)
	button.cover:SetAllPoints(button.icon)
	button.cover:SetColorTexture(0, 0, 0, 0.7)
	button.border = button:CreateTexture(nil, "ARTWORK")
	button.border:SetAllPoints()
	button.hover = button:CreateTexture(nil, "ARTWORK", nil, 1)
	button.hover:SetAllPoints()
	button.hover:SetBlendMode("ADD")
	button.hover:SetAlpha(0.4)
	button.hover:Hide()
	button.glow = button:CreateTexture(nil, "OVERLAY")
	button.glow:SetSize(61, 61)
	button.glow:SetPoint("CENTER")
	button.glow:SetBlendMode("ADD")
	button.glow:SetAlpha(0.14)
	button.hasGlow = Atlas(button.glow, "talents-node-square-greenglow")
	local font = FirstFont("SystemFont16_Shadow_ThickOutline", "NumberFontNormal")
	-- (The number on a frame of its own, over its edge for sure.)
	local numberHolder = CreateFrame("Frame", nil, button)
	numberHolder:SetAllPoints()
	numberHolder:SetFrameLevel(button:GetFrameLevel() + 2)
	button.rank = numberHolder:CreateFontString(nil, "OVERLAY", font)
	button.rank:SetPoint("BOTTOM", 11, 4)
	-- (Four black copies a pixel off each corner under it, as the talents
	-- window's: its thick dark edge.)
	button.rankShadows = {}
	for i, at in ipairs({ { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } }) do
		local shadow = button:CreateFontString(nil, "OVERLAY", font)
		shadow:SetDrawLayer("OVERLAY", 1)
		shadow:SetPoint("CENTER", button.rank, "CENTER", at[1], at[2])
		shadow:SetTextColor(0, 0, 0)
		button.rankShadows[i] = shadow
	end
	button:SetScript("OnEnter", function(self)
		self.hover:Show()
		TalentEnter(self)
	end)
	button:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip_Hide()
	end)
	button:SetScript("OnClick", TalentClick)
	-- The talents window's search badge, on its icon's top right corner.
	button.match = button:CreateTexture(nil, "OVERLAY", nil, 3)
	button.match:SetSize(63, 63)
	button.match:SetPoint("CENTER", button.icon, "TOPRIGHT")
	if not Atlas(button.match, "talents-search-match") then
		button.match:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
		button.match:SetSize(16, 16)
	end
	button.match:Hide()
	return button
end

-- What the search box holds, in lower case ("" for nothing).
local query = ""

-- Whether a talent's name or its first rank's text holds the search.
local function Matches(talent)
	if query == "" then
		return false
	end
	if (talent.name or ""):lower():find(query, 1, true) then
		return true
	end
	if talent.searchText == nil then
		talent.searchText = (Description(talent, 1) or ""):lower()
	end
	return talent.searchText:find(query, 1, true) ~= nil
end

-- Gold at full rank, green while it has points or can take one, else shut:
-- grey under a dark cover, no rank showing.
local function PaintTalent(button)
	local talent = button.talent
	local rank = ranks[talent.nodeID] or 0
	local open = rank > 0 or CanAdd(talent)
	local state = rank >= talent.maxRanks and "full" or open and "open" or "shut"
	button.icon:SetTexture(talent.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	button.icon:SetDesaturated(not open)
	button.cover:SetShown(not open)
	local colour = state == "full" and GOLD or state == "open" and OPEN or SHUT
	for _, texture in ipairs({ button.border, button.hover }) do
		if not Atlas(texture, BORDER[state]) then
			texture:SetTexture(RING)
			texture:SetVertexColor(colour[1], colour[2], colour[3])
		end
	end
	button.glow:SetShown(button.hasGlow and state == "open" and CanAdd(talent))
	button.rank:SetText(rank)
	button.rank:SetTextColor(colour[1], colour[2], colour[3])
	button.rank:SetShown(open)
	for _, shadow in ipairs(button.rankShadows) do
		shadow:SetText(rank)
		shadow:SetShown(open)
	end
	button.match:SetShown(Matches(talent))
end

-- Where a talent's middle sits on the talents tab, from its top left.
local function Spot(talent)
	return FIRST_X + talent.tree.x + talent.col * STEP, -(FIRST_Y + talent.row * STEP)
end

-- The line from one talent to the one it unlocks, edge to edge, with the
-- talents window's arrow head where it arrives. Gold once `from` is at full
-- rank.
local function Branch(tab, from, to)
	local lit = Full(from.nodeID)
	local x1, y1 = Spot(from)
	local x2, y2 = Spot(to)
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)
	if length == 0 then
		return
	end
	local ux, uy = dx / length, dy / length
	local colour = lit and GOLD or LINE
	tab.lines.used = tab.lines.used + 1
	local line = tab.lines[tab.lines.used]
	if not line then
		line = tab.lineHolder:CreateLine(nil, "ARTWORK")
		line:SetThickness(3)
		tab.lines[tab.lines.used] = line
	end
	line:SetColorTexture(colour[1], colour[2], colour[3], 1)
	line:SetStartPoint("TOPLEFT", tab, x1 + ux * SIZE / 2, y1 + uy * SIZE / 2)
	line:SetEndPoint("TOPLEFT", tab, x2 - ux * (SIZE / 2 + 4), y2 - uy * (SIZE / 2 + 4))
	line:Show()
	tab.arrows.used = tab.arrows.used + 1
	local arrow = tab.arrows[tab.arrows.used]
	if not arrow then
		arrow = tab.arrowHolder:CreateTexture(nil, "OVERLAY")
		arrow:SetSize(14, 12)
		if not Atlas(arrow, "talents-arrow-head-locked") then
			arrow:SetColorTexture(1, 1, 1, 1)
			arrow:SetSize(8, 8)
		end
		tab.arrows[tab.arrows.used] = arrow
	end
	arrow:SetVertexColor(lit and GOLD[1] or 1, lit and GOLD[2] or 1, lit and GOLD[3] or 1)
	-- (The head points down; turned to the line's way.)
	arrow:SetRotation(math.atan2(uy, ux) + math.pi / 2)
	arrow:ClearAllPoints()
	arrow:SetPoint("CENTER", tab, "TOPLEFT", x2 - ux * (SIZE / 2 + 4), y2 - uy * (SIZE / 2 + 4))
	arrow:Show()
end

-- A tree's icon: the game's own for it where it gives one, else its first
-- talent's.
local function TreeIcon(tree)
	if tree.icon then
		return tree.icon
	end
	local first
	for _, talent in ipairs(tree.talents) do
		if not first or talent.row < first.row or (talent.row == first.row and talent.col < first.col) then
			first = talent
		end
	end
	return first and first.icon
end

-- A tree's header, as the talents window's: its round icon in a ring, the
-- points in it in a small box, its name, and a short divider under them.
local function NewHeader(tab)
	local header = CreateFrame("Frame", nil, tab.headerHolder)
	header:SetSize(48, 48)
	header.icon = header:CreateTexture(nil, "BORDER")
	header.icon:SetSize(36, 36)
	header.icon:SetPoint("CENTER", -3, 3)
	if header.CreateMaskTexture then
		local mask = header:CreateMaskTexture()
		mask:SetSize(40, 40)
		mask:SetPoint("CENTER", -2, 2)
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
		header.icon:AddMaskTexture(mask)
	end
	header.name = header:CreateFontString(nil, "OVERLAY", FirstFont("GameFontWhiteLarge", "GameFontHighlightLarge"))
	header.name:SetPoint("LEFT", 54, 2)
	local ring = header:CreateTexture(nil, "OVERLAY")
	ring:SetSize(55, 55)
	ring:SetPoint("CENTER", header.icon)
	Atlas(ring, "Talents-Main-Ring-c60")
	local box = header:CreateTexture(nil, "OVERLAY", nil, 1)
	box:SetSize(24, 20)
	box:SetPoint("CENTER", 14, -12)
	if not Atlas(box, "Talents-Main-Ring-Box-c60") then
		box:SetColorTexture(0, 0, 0, 0.8)
	end
	header.count = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header.count:SetDrawLayer("OVERLAY", 2)
	header.count:SetPoint("CENTER", box)
	local divider = header:CreateTexture(nil, "OVERLAY")
	divider:SetSize(355, 64)
	divider:SetPoint("BOTTOM", 60, -20)
	Atlas(divider, "Talents-small-divider-c60")
	return header
end

-- The class's picture behind the trees, as the talents window has it; where
-- this client has none, the old talent window's tree pictures, one a tree.
local function PaintBackground(tab)
	if tab.classArt == nil then
		local _, class = UnitClass("player")
		tab.classArt = Atlas(tab.classBg, "talent-background-" .. tostring(class):lower())
	end
	if tab.classArt then
		return
	end
	local _, class = UnitClass("player")
	for i in ipairs(trees) do
		local pieces = tab.oldArt[i]
		if not pieces then
			pieces = {}
			for _, corner in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight" }) do
				pieces[corner] = tab:CreateTexture(nil, "BACKGROUND", nil, 1)
			end
			tab.oldArt[i] = pieces
		end
		local name = BACKGROUNDS[class] and BACKGROUNDS[class][i]
		local width, height = TAB_W / 3, 595
		-- (The picture is 300 by 331, in files of 256 + 64 across and 256 + 128
		-- down: the right and bottom ones only partly used.)
		local left, right = width * 256 / 300, width * 44 / 300
		local upper, lower = height * 256 / 331, height * 75 / 331
		pieces.TopLeft:SetPoint("TOPLEFT", tab.classBg, "TOPLEFT", (i - 1) * width, 0)
		pieces.TopRight:SetPoint("TOPLEFT", pieces.TopLeft, "TOPRIGHT")
		pieces.BottomLeft:SetPoint("TOPLEFT", pieces.TopLeft, "BOTTOMLEFT")
		pieces.BottomRight:SetPoint("TOPLEFT", pieces.TopLeft, "BOTTOMRIGHT")
		for corner, texture in pairs(pieces) do
			local isLeft, isTop = corner:find("Left"), corner:find("Top")
			texture:SetTexture(name and ART .. name .. "-" .. corner or nil, "CLAMP", "CLAMP")
			texture:SetSize(isLeft and left or right, isTop and upper or lower)
			texture:SetTexCoord(isLeft and 0 or 0.5 / 64, isLeft and 1 - 0.5 / 256 or 44 / 64,
				isTop and 0 or 0.5 / 128, isTop and 1 - 0.5 / 256 or 75 / 128)
		end
	end
end

Paint = function()
	if not (window and window:IsShown()) then
		return
	end
	local tab = window.tab
	local width, height = window:GetSize()
	tab:SetScale(math.max(math.min(width / WIN_W, height / WIN_H), 0.4))
	PaintBackground(tab)
	for i, tree in ipairs(trees) do
		local header = tab.headers[i]
		if not header then
			header = NewHeader(tab)
			header:SetPoint("CENTER", tab.border, "TOPLEFT", 140 + (i - 1) * TREE_W, -100)
			tab.headers[i] = header
		end
		header.icon:SetTexture(TreeIcon(tree) or "Interface\\Icons\\INV_Misc_QuestionMark")
		header.name:SetText(tree.name or "")
		header.count:SetText(SpentIn(tree))
		header:Show()
	end
	for i = #trees + 1, #tab.headers do
		tab.headers[i]:Hide()
	end
	local used = 0
	for _, tree in ipairs(trees) do
		for _, talent in ipairs(tree.talents) do
			used = used + 1
			local button = tab.buttons[used]
			if not button then
				button = NewTalent(tab.buttonHolder)
				tab.buttons[used] = button
			end
			button.talent = talent
			button:ClearAllPoints()
			button:SetPoint("CENTER", tab, "TOPLEFT", Spot(talent))
			PaintTalent(button)
			button:Show()
		end
	end
	for i = used + 1, #tab.buttons do
		tab.buttons[i]:Hide()
	end
	tab.lines.used, tab.arrows.used = 0, 0
	if tab.lineHolder.CreateLine then
		for _, talent in pairs(talents) do
			for _, nodeID in ipairs(talent.needs) do
				local from = talents[nodeID]
				if from and from.tree == talent.tree then
					Branch(tab, from, talent)
				end
			end
		end
	end
	for _, pool in ipairs({ tab.lines, tab.arrows }) do
		for i = pool.used + 1, #pool do
			pool[i]:Hide()
		end
	end
	local spent = Spent()
	window.level:SetText(ns.L["Level required: %s"]:format(("|cffffffff%s|r"):format(spent > 0 and offset + spent or "-")))
	window.points:SetText(maxPoints - spent)
	-- (Green while there are points to spend, as the talents window's.)
	if maxPoints - spent > 0 then
		window.points:SetTextColor(OPEN[1], OPEN[2], OPEN[3])
	else
		window.points:SetTextColor(1, 1, 1)
	end
	window.reset:SetEnabled(spent > 0)
	local adds = ApplyCheck()
	window.apply:SetEnabled(adds ~= nil)
	window.applyGlow:SetShown(adds ~= nil)
	local pending = Pending()
	window.undo:SetEnabled(pending)
	window.undo.icon:SetDesaturated(not pending)
end

-- A square icon button with the action bar's border, and a tooltip.
local function IconButton(parent, size, icon, tip)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexture(icon)
	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	button.border:SetSize(size * 64 / 36, size * 64 / 36)
	button.border:SetPoint("CENTER")
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(tip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local TALENTS_ICON = "Interface\\Icons\\Ability_Marksmanship" -- (the talents micro button's)

-- Where the talents window was last seen, so the calculator opens in its
-- place and size: { left, bottom, width, height } in UIParent's units.
local talentsRect

local function RememberTalentsRect(frame)
	local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
	local scale = Num(frame:GetEffectiveScale()) and frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	if ok and Num(left) and Num(bottom) and Num(width) and Num(height) and scale and width > 0 then
		talentsRect = { left * scale, bottom * scale, width * scale, height * scale }
	end
end

local function PlaceWindow()
	window:ClearAllPoints()
	if talentsRect then
		window:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", talentsRect[1], talentsRect[2])
		window:SetSize(talentsRect[3], talentsRect[4])
	else
		-- (Not seen yet: its size, in the middle.)
		local frame = PlayerSpellsFrame
		local width, height = frame and Num(frame:GetWidth()), frame and Num(frame:GetHeight())
		local scale = frame and Num(frame:GetEffectiveScale()) and frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		window:SetPoint("CENTER")
		if width and height and scale and width > 0 then
			window:SetSize(width * scale, height * scale)
		else
			window:SetSize(DEFAULT_W, DEFAULT_H)
		end
	end
end

-- The calculator's portrait: the talents window's own, else yours.
local function SetPortrait()
	local mine = window.PortraitContainer and window.PortraitContainer.portrait or window.portrait
	if not mine then
		return
	end
	local theirs = PlayerSpellsFrame and (PlayerSpellsFrame.PortraitContainer and PlayerSpellsFrame.PortraitContainer.portrait
		or PlayerSpellsFrame.portrait)
	local atlas = theirs and theirs.GetAtlas and theirs:GetAtlas()
	local file = theirs and theirs.GetTexture and theirs:GetTexture()
	if atlas then
		mine:SetAtlas(atlas)
	elseif file then
		mine:SetTexture(file)
		mine:SetTexCoord(theirs:GetTexCoord())
	elseif SetPortraitTexture then
		SetPortraitTexture(mine, "player")
	end
end

-- Back to your talents: the calculator closes and the talents window opens.
-- (Not in a fight: the calculator only closes then.)
local function BackToTalents()
	window:Hide()
	if InCombatLockdown() then
		return
	end
	if PlayerSpellsUtil and PlayerSpellsUtil.OpenToClassTalentsTab then
		pcall(PlayerSpellsUtil.OpenToClassTalentsTab)
	elseif PlayerSpellsFrame then
		pcall(ShowUIPanel, PlayerSpellsFrame)
	end
end

-- Copy Over Changes: puts what the plan adds into your talents window, top row
-- first, and takes you back there. Nothing is learned: they wait there, as
-- points you'd clicked in yourself, for its own Apply Changes (or its undo).
-- Anything it had waiting is dropped first. On a refusal nothing is kept.
local function ApplyPlan()
	if not ApplyCheck() then
		return
	end
	if C_Traits.ConfigHasStagedChanges and C_Traits.ConfigHasStagedChanges(configID) then
		C_Traits.RollbackConfig(configID)
	end
	ReadLearned()
	if not ApplyCheck() then
		Paint()
		return
	end
	local order = {}
	for nodeID, talent in pairs(talents) do
		for _ = 1, (ranks[nodeID] or 0) - (learned[nodeID] or 0) do
			order[#order + 1] = talent
		end
	end
	table.sort(order, function(a, b)
		if a.row ~= b.row then
			return a.row < b.row
		end
		return a.nodeID < b.nodeID
	end)
	for _, talent in ipairs(order) do
		if not C_Traits.PurchaseRank(configID, talent.nodeID) then
			C_Traits.RollbackConfig(configID)
			ns.Print(ns.L["Couldn't add a point to %s: nothing was changed."]:format(talent.name or "?"))
			return
		end
	end
	BackToTalents()
end

local function MakeWindow()
	local ok, frame = pcall(CreateFrame, "Frame", "CinematicTalentCalc", UIParent, "ButtonFrameTemplate")
	if not ok then
		frame = CreateFrame("Frame", "CinematicTalentCalc", UIParent, BackdropTemplateMixin and "BackdropTemplate")
		if frame.SetBackdrop then
			frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 8, right = 8, top = 8, bottom = 8 } })
		end
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -4, -4)
	end
	window = frame
	frame:SetSize(DEFAULT_W, DEFAULT_H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "CinematicTalentCalc")
	if frame.Inset then
		frame.Inset:Hide()
	end
	local title = ns.L["Talent calculator"]
	if frame.SetTitle then
		frame:SetTitle(title)
	else
		local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetPoint("TOP", 0, -14)
		text:SetText(title)
	end

	-- The talents tab, built as the talents window's (/cine debug talentart):
	-- its brown background, the class's picture over it, the carved frame
	-- round that, the gold rule with its ornament across the top and the
	-- dividers between the trees; then the lines, the talents and the arrow
	-- heads, the headers, and the controls where the talents window has its
	-- own.
	local tab = CreateFrame("Frame", nil, frame)
	frame.tab = tab
	tab:SetSize(TAB_W, TAB_H)
	tab:SetPoint("BOTTOM", 0, 4)
	tab.headers, tab.buttons, tab.oldArt = {}, {}, {}
	tab.lines, tab.arrows = { used = 0 }, { used = 0 }
	local background = tab:CreateTexture(nil, "BACKGROUND")
	background:SetSize(TAB_W, 701)
	background:SetPoint("BOTTOMLEFT")
	if not Atlas(background, "Talents-Background-c60") then
		background:SetColorTexture(0.11, 0.075, 0.045, 1)
	end
	tab.classBg = tab:CreateTexture(nil, "BACKGROUND", nil, 1)
	tab.classBg:SetSize(TAB_W, 595)
	tab.classBg:SetPoint("TOPLEFT", background, "TOPLEFT", 0, -70)
	tab.lineHolder = CreateFrame("Frame", nil, tab)
	tab.lineHolder:SetAllPoints()
	tab.buttonHolder = CreateFrame("Frame", nil, tab)
	tab.buttonHolder:SetAllPoints()
	tab.buttonHolder:SetFrameLevel(tab.lineHolder:GetFrameLevel() + 1)
	tab.arrowHolder = CreateFrame("Frame", nil, tab)
	tab.arrowHolder:SetAllPoints()
	tab.arrowHolder:SetFrameLevel(tab.buttonHolder:GetFrameLevel() + 2)
	-- (The frame and its rules over the picture, under the talents.)
	local art = CreateFrame("Frame", nil, tab)
	art:SetAllPoints()
	art:SetFrameLevel(tab.lineHolder:GetFrameLevel())
	tab.border = art:CreateTexture(nil, "BACKGROUND", nil, 2)
	tab.border:SetSize(1216, 603)
	tab.border:SetPoint("TOPLEFT", tab.classBg, "TOPLEFT", -2, 4)
	Atlas(tab.border, "Talents-inner-frame-c60")
	local ruleLeft = art:CreateTexture(nil, "BACKGROUND", nil, 3)
	ruleLeft:SetSize(591, 56)
	ruleLeft:SetPoint("TOPRIGHT", tab.border, "TOP", 0, -4)
	local ruleRight = art:CreateTexture(nil, "BACKGROUND", nil, 3)
	ruleRight:SetSize(595, 56)
	ruleRight:SetPoint("TOPLEFT", tab.border, "TOP", 0, -4)
	if Atlas(ruleLeft, "Talents-divider-left-c60") and Atlas(ruleRight, "Talents-divider-right-c60") then
		for i, half in ipairs({ ruleLeft, ruleRight }) do
			local divider = art:CreateTexture(nil, "BACKGROUND", nil, 3)
			divider:SetSize(2, 468)
			divider:SetPoint("TOP", half, "CENTER", i == 1 and 95 or -95, -60)
			Atlas(divider, "Talents-divider-vertical-c60")
		end
	end
	tab.headerHolder = CreateFrame("Frame", nil, tab)
	tab.headerHolder:SetAllPoints()
	tab.headerHolder:SetFrameLevel(tab.arrowHolder:GetFrameLevel() + 1)
	local controls = CreateFrame("Frame", nil, tab)
	controls:SetAllPoints()
	controls:SetFrameLevel(tab.headerHolder:GetFrameLevel() + 1)

	-- Where the talents window has its tabs: the level the build needs and
	-- With Legacy.
	frame.level = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.level:SetPoint("LEFT", tab.border, "TOPLEFT", 80, 14)
	-- "With Legacy": count Talented (Legacy Tree), the first point at level 5, not 10.
	frame.talented = CreateFrame("CheckButton", nil, controls, "UICheckButtonTemplate")
	frame.talented:SetSize(26, 26)
	frame.talented:SetPoint("LEFT", frame.level, "RIGHT", 40, 0)
	local talentedText = frame.talented.Text or frame.talented.text
	if not talentedText then
		talentedText = frame.talented:CreateFontString(nil, "OVERLAY")
		talentedText:SetPoint("LEFT", frame.talented, "RIGHT", 2, 0)
	end
	talentedText:SetFontObject("GameFontHighlight")
	talentedText:SetText(ns.L["With Legacy"])
	frame.talented:SetScript("OnShow", function(self)
		self:SetChecked(ns.db and ns.db.talentCalcTalented or false)
	end)
	frame.talented:SetScript("OnClick", function(self)
		ns.GetDB().talentCalcTalented = self:GetChecked() and true or false
		ReadLevels()
		Paint()
	end)
	frame.talented:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(ns.L["With Legacy"])
		GameTooltip:AddLine(ns.L["Count the Legacy Tree's Talented: talent points from level 5 instead of 10, so a build needs a lower level. Still 51 points at most."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame.talented:SetScript("OnLeave", GameTooltip_Hide)

	-- Its search box, at the same place: talents whose name or text holds what's
	-- typed get its search badge.
	local made, search = pcall(CreateFrame, "EditBox", nil, controls, "SearchBoxTemplate")
	if not made then
		search = CreateFrame("EditBox", nil, controls, "InputBoxTemplate")
	end
	frame.search = search
	search:SetSize(184, made and 30 or 20)
	search:SetPoint("BOTTOMRIGHT", tab.border, "TOPRIGHT", -32, made and 4 or 9)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		query = text:match("^%s*(.-)%s*$"):lower()
		Paint()
	end)
	search:HookScript("OnEscapePressed", search.ClearFocus)

	-- Where it has its calculator button (left of its search box): the way back.
	frame.back = IconButton(controls, 26, TALENTS_ICON, ns.L["Your talents"])
	frame.back:SetPoint("RIGHT", tab.border, "TOPRIGHT", -226, 19)
	frame.back:SetScript("OnClick", BackToTalents)

	-- Where it has Unspent Talents: the points left, in its box.
	local currency = CreateFrame("Frame", nil, controls)
	currency:SetSize(160, 45)
	currency:SetPoint("TOPRIGHT", tab.border, "TOPRIGHT", -20, -6)
	local box = currency:CreateTexture(nil, "ARTWORK")
	box:SetSize(125, 45)
	box:SetPoint("RIGHT")
	if not Atlas(box, "Talents-Square-Box-c60") then
		box:SetColorTexture(0, 0, 0, 0.8)
		box:SetSize(48, 40)
	end
	local label = currency:CreateFontString(nil, "OVERLAY", FirstFont("SystemFont_Shadow_Med1", "GameFontHighlight"))
	label:SetPoint("RIGHT", box, "LEFT", 60, 0)
	label:SetText(ns.L["Points left"])
	frame.points = currency:CreateFontString(nil, "OVERLAY", FirstFont("Game32Font_Shadow2", "Game30Font", "GameFontHighlightHuge",
		"GameFontHighlightLarge"))
	frame.points:SetPoint("CENTER", box, "RIGHT", -28, 0)

	-- Where it has Apply Changes: Copy Over Changes, glowing while there's
	-- something to copy over, Undo Pending Changes to its right, and Reset at
	-- the far left.
	frame.apply = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
	frame.apply:SetText(ns.L["Copy Over Changes"])
	frame.apply:SetSize(math.max(frame.apply:GetFontString():GetStringWidth() + 40, 164), 22)
	frame.apply:SetPoint("BOTTOM", tab, "BOTTOM", 0, 8)
	frame.apply:SetMotionScriptsWhileDisabled(true)
	frame.apply:SetScript("OnClick", ApplyPlan)
	frame.apply:SetScript("OnEnter", function(self)
		local adds, why = ApplyCheck()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(ns.L["Copy Over Changes"])
		if adds then
			GameTooltip:AddLine(ns.L["Put the %d points the plan adds into your talents window, for its Apply Changes."]:format(adds),
				1, 1, 1, true)
		elseif why then
			GameTooltip:AddLine(why, 1, 0.1, 0.1, true)
		else
			GameTooltip:AddLine(ns.L["The plan adds nothing to your talents."], 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	frame.apply:SetScript("OnLeave", GameTooltip_Hide)
	-- (The talents window's yellow glow round its red button, in three pieces.)
	frame.applyGlow = CreateFrame("Frame", nil, frame.apply)
	frame.applyGlow:SetPoint("LEFT", -12, 0)
	frame.applyGlow:SetSize(frame.apply:GetWidth() + 24, 1)
	local glowLeft = frame.applyGlow:CreateTexture(nil, "ARTWORK")
	glowLeft:SetSize(25, 49)
	glowLeft:SetPoint("LEFT")
	local glowRight = frame.applyGlow:CreateTexture(nil, "ARTWORK")
	glowRight:SetSize(25, 49)
	glowRight:SetPoint("RIGHT")
	local glowMiddle = frame.applyGlow:CreateTexture(nil, "ARTWORK")
	glowMiddle:SetPoint("TOPLEFT", glowLeft, "TOPRIGHT")
	glowMiddle:SetPoint("BOTTOMRIGHT", glowRight, "BOTTOMLEFT")
	for texture, name in pairs({ [glowLeft] = "left", [glowRight] = "right", [glowMiddle] = "middle" }) do
		texture:SetBlendMode("ADD")
		if not Atlas(texture, "newplayertutorial-yellowglow-redbutton-" .. name) then
			texture:SetColorTexture(1, 0.85, 0.1, 0.25)
		end
	end
	frame.undo = CreateFrame("Button", nil, controls)
	frame.undo:SetSize(25, 25)
	frame.undo:SetPoint("LEFT", frame.apply, "RIGHT", 14, 0)
	frame.undo.icon = frame.undo:CreateTexture(nil, "OVERLAY")
	frame.undo.icon:SetSize(21, 20)
	frame.undo.icon:SetPoint("CENTER")
	local undoHighlight = frame.undo:CreateTexture(nil, "HIGHLIGHT")
	undoHighlight:SetAllPoints(frame.undo.icon)
	undoHighlight:SetBlendMode("ADD")
	if not (Atlas(frame.undo.icon, "talents-button-undo") and Atlas(undoHighlight, "talents-button-undo")) then
		frame.undo.icon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
		undoHighlight:SetTexture("Interface\\Buttons\\UI-RefreshButton")
	end
	frame.undo:SetMotionScriptsWhileDisabled(true)
	frame.undo:SetScript("OnClick", function()
		LoadLearned()
		Paint()
	end)
	frame.undo:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(ns.L["Undo Pending Changes"])
		GameTooltip:Show()
	end)
	frame.undo:SetScript("OnLeave", GameTooltip_Hide)
	frame.reset = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
	frame.reset:SetText(ns.L["Reset"])
	frame.reset:SetSize(math.max(frame.reset:GetFontString():GetStringWidth() + 30, 90), 22)
	frame.reset:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 24, 8)
	frame.reset:SetScript("OnClick", function()
		wipe(ranks)
		Paint()
	end)

	frame:SetScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		Paint()
	end)
	frame:SetScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
		-- (An empty search next time it opens.)
		frame.search:SetText("")
		frame.search:ClearFocus()
	end)
	frame:SetScript("OnSizeChanged", function()
		Paint()
	end)
end

local function OpenWindow()
	if not ReadTalents() then
		ns.Print(ns.L["The talent calculator can't read your talents here."] .. " (" .. tostring(lastError) .. ")")
		return false
	end
	-- From your talents as they are, each time it opens.
	LoadLearned()
	-- With Legacy ticked if you have Talented, unticked if not (as you left it
	-- when your points can't tell).
	local talented = HasTalented()
	if talented ~= nil then
		ns.GetDB().talentCalcTalented = talented
		ReadLevels()
	end
	if not window then
		MakeWindow()
	end
	PlaceWindow()
	SetPortrait()
	window:Show()
	return true
end

function ns.ToggleTalentCalc()
	if window and window:IsShown() then
		window:Hide()
		return
	end
	OpenWindow()
end

-- From the talents window: the calculator takes its place, and it closes.
-- (In a fight it stays open, under the calculator.)
local function SwapToCalculator()
	local frame = PlayerSpellsFrame
	if frame then
		RememberTalentsRect(frame)
	end
	if OpenWindow() and frame and not InCombatLockdown() then
		pcall(HideUIPanel, frame)
	end
end

-------------------------------------------------------------------------------
-- The button on the talents window
-------------------------------------------------------------------------------
local link
local ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Calculator" -- (Media/make_calculator.py)

-- The talents tab's search box: by name, else the first edit box on it (a
-- couple of frames deep at most).
local function SearchBox(parent, depth)
	if parent.SearchBox then
		return parent.SearchBox
	end
	for _, child in ipairs({ parent:GetChildren() }) do
		if child.GetObjectType and child:GetObjectType() == "EditBox" then
			return child
		end
	end
	if (depth or 0) < 2 then
		for _, child in ipairs({ parent:GetChildren() }) do
			local found = SearchBox(child, (depth or 0) + 1)
			if found then
				return found
			end
		end
	end
end

local function ShowLink()
	if not link then
		return
	end
	local frame = PlayerSpellsFrame
	local inspecting = frame and frame.IsInspecting and ns.Flag(frame:IsInspecting())
	link:SetShown(Enabled() and not inspecting and true or false)
end

local function SetUpLink()
	local frame = PlayerSpellsFrame
	if link or not (frame and frame.HookScript) then
		return
	end
	-- (On the Talents tab only, where it has one.)
	local parent = frame.TalentsFrame or frame
	link = IconButton(parent, 26, ICON, ns.L["Talent calculator"])
	-- Just left of the talents' search box, else in the top right corner.
	local search = SearchBox(parent)
	if search then
		link:SetPoint("RIGHT", search, "LEFT", -10, 0)
	else
		link:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -40)
	end
	-- (The talents window's own layers sit thousands of levels up: its
	-- border at 5500.)
	link:SetFrameLevel(math.min(frame:GetFrameLevel() + 6000, 9000))
	link:SetScript("OnClick", SwapToCalculator)
	-- Where it is, for the calculator to open there (also from /cine talents).
	frame:HookScript("OnHide", RememberTalentsRect)
	frame:HookScript("OnShow", function()
		C_Timer.After(0, function()
			RememberTalentsRect(frame)
		end)
		ShowLink()
		-- One or the other: opening your talents closes the calculator.
		if window and window:IsShown() then
			window:Hide()
		end
	end)
	if frame.SetInspecting then
		hooksecurefunc(frame, "SetInspecting", ShowLink)
	end
	ShowLink()
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function()
	SetUpLink()
	if link then
		watcher:UnregisterAllEvents()
	end
end)

-- The option was ticked or unticked (Options.lua).
function ns.RefreshTalentCalc()
	ShowLink()
end

-- /cine debug sounds: print each sound the game plays, by number and name,
-- to find the talents window's (again to stop).
do
	local watching, hooked, names
	function ns.ToggleSoundWatch()
		watching = not watching
		if watching and not hooked then
			hooked = true
			names = {}
			for name, id in pairs(SOUNDKIT or {}) do
				names[id] = names[id] and names[id] .. "/" .. name or name
			end
			hooksecurefunc("PlaySound", function(id)
				if watching then
					ns.Print(("sound %s %s"):format(tostring(id), tostring(names[id] or "")))
				end
			end)
		end
		ns.Print(("calculator sounds: add %s, take back %s"):format(tostring(Sound("add")), tostring(Sound("remove"))))
		return watching
	end
end

-- /cine debug talentcalc
function ns.PrintTalentCalcDebug()
	local ok = ReadTalents()
	ns.Print("talent calculator: option " .. tostring(ns.db and ns.db.talentCalc) .. ", read " .. tostring(ok)
		.. (lastError and " (" .. lastError .. ")" or ""))
	print(("  config %s, tree %s, level %s, points at max level %d (level = points + %d)"):format(
		tostring(configID), tostring(treeID), tostring(UnitLevel("player")), maxPoints, offset))
	print(("  your points %d, Talented %s"):format(YourPoints(), tostring(HasTalented())))
	for i, tree in ipairs(trees) do
		local cols = 0
		for _, talent in ipairs(tree.talents) do
			cols = math.max(cols, talent.col + 1)
		end
		print(("  %d. %s: %d talents, %d rows, %d columns, starts %s across (%s), background %s"):format(i,
			tostring(tree.name), #tree.talents, tree.rows, cols, tostring(tree.x), tostring(tree.left), tostring(tree.background)))
	end
	-- The game's own row rule, for one talent per row (to check PER_ROW).
	if configID and C_Traits.GetConditionInfo then
		local tree = trees[1]
		local seen = {}
		for _, talent in ipairs(tree and tree.talents or {}) do
			if not seen[talent.row] then
				seen[talent.row] = true
				local info = C_Traits.GetNodeInfo(configID, talent.nodeID)
				local needs = {}
				for _, conditionID in ipairs(info and info.conditionIDs or {}) do
					local condition = C_Traits.GetConditionInfo(configID, conditionID)
					needs[#needs + 1] = tostring(condition and condition.spentAmountRequired)
				end
				print(("  row %d, %s: game's spent needed %s, ours %d, needs %d talents"):format(talent.row,
					tostring(talent.name), table.concat(needs, "/"), talent.row * PER_ROW, #talent.needs))
			end
		end
	end
	print("  talents window button: " .. (link and ("made, shown " .. tostring(link:IsShown())) or "not made (open your talents first)"))
end

-- /cine debug talentart: every part of the talents window (open on your
-- talents) to the log, with its size, place, texture or atlas and colours,
-- to draw the calculator with the same art; and what the game says about
-- each tree.
do
	local MAX_LINES = 4000
	local MANY = 4 -- nameless children logged per frame (a pool of talent buttons): the first few only
	local logged

	local function Safe(fn, ...)
		local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
		if ok then
			return a, b, c, d, e, f, g, h
		end
	end

	local function Str(value)
		if issecretvalue and issecretvalue(value) then
			return "secret"
		end
		if type(value) == "number" then
			return value == math.floor(value) and tostring(value) or ("%.3f"):format(value)
		end
		return tostring(value)
	end

	local function Log(depth, text)
		logged = logged + 1
		if logged <= MAX_LINES then
			ns.Log("talentart", ("  "):rep(depth) .. text)
		end
	end

	local function Describe(object, key)
		local kind = Safe(object.GetObjectType, object) or "?"
		local w, h = Safe(object.GetSize, object)
		local parts = { ("%s %s %sx%s"):format(kind, Str(key or Safe(object.GetDebugName, object)), Str(w), Str(h)) }
		parts[#parts + 1] = "shown " .. Str(Safe(object.IsShown, object))
		local point, relativeTo, relativePoint, x, y = Safe(object.GetPoint, object, 1)
		if point then
			parts[#parts + 1] = ("at %s %s %s %s,%s"):format(Str(point),
				Str(relativeTo and Safe(relativeTo.GetDebugName, relativeTo)), Str(relativePoint), Str(x), Str(y))
		end
		if kind == "Texture" or kind == "MaskTexture" then
			parts[#parts + 1] = "atlas " .. Str(Safe(object.GetAtlas, object))
			parts[#parts + 1] = "file " .. Str(Safe(object.GetTexture, object))
			local ulx, uly, _, lly, urx = Safe(object.GetTexCoord, object)
			if ulx then
				parts[#parts + 1] = ("coords %s %s %s %s"):format(Str(ulx), Str(urx), Str(uly), Str(lly))
			end
			local r, g, b, a = Safe(object.GetVertexColor, object)
			parts[#parts + 1] = ("colour %s %s %s %s"):format(Str(r), Str(g), Str(b), Str(a))
			parts[#parts + 1] = ("layer %s %s, blend %s, grey %s"):format(Str(Safe(object.GetDrawLayer, object)),
				Str(select(2, Safe(object.GetDrawLayer, object))), Str(Safe(object.GetBlendMode, object)),
				Str(Safe(object.IsDesaturated, object)))
		elseif kind == "FontString" then
			local font = Safe(object.GetFontObject, object)
			parts[#parts + 1] = ("text %q, font %s, size %s"):format(Str(Safe(object.GetText, object)),
				Str(font and Safe(font.GetName, font)), Str(select(2, Safe(object.GetFont, object))))
			local r, g, b = Safe(object.GetTextColor, object)
			parts[#parts + 1] = ("colour %s %s %s"):format(Str(r), Str(g), Str(b))
		else
			parts[#parts + 1] = "level " .. Str(Safe(object.GetFrameLevel, object))
		end
		return table.concat(parts, ", ")
	end

	local function Walk(object, key, depth)
		Log(depth, Describe(object, key))
		if depth >= 8 or Safe(object.IsForbidden, object) then
			return
		end
		-- Its parts by the names its table gives them.
		local keys = {}
		for k, v in pairs(object) do
			if type(v) == "table" and type(k) == "string" and v.GetObjectType then
				keys[v] = k
			end
		end
		for _, region in ipairs({ Safe(function() return { object:GetRegions() } end) or {} }) do
			for _, part in ipairs(region) do
				Log(depth + 1, Describe(part, keys[part]))
			end
		end
		-- Every part with a name; of a run of nameless ones (a pool of talent
		-- buttons), the first few.
		local children = Safe(function() return { object:GetChildren() } end) or {}
		local nameless, skipped = 0, 0
		for _, child in ipairs(children) do
			if keys[child] or Safe(child.GetName, child) then
				Walk(child, keys[child], depth + 1)
			else
				nameless = nameless + 1
				if nameless <= MANY then
					Walk(child, nil, depth + 1)
				else
					skipped = skipped + 1
				end
			end
		end
		if skipped > 0 then
			Log(depth + 1, ("... and %d more nameless children"):format(skipped))
		end
	end

	function ns.LogTalentArt()
		local frame = PlayerSpellsFrame
		if not (frame and Safe(frame.IsShown, frame)) then
			ns.Print("talentart: open your talents first, then run it again")
			return
		end
		logged = 0
		Walk(frame, "PlayerSpellsFrame", 0)
		if ReadTalents() then
			for _, group in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
				local fields = {}
				for k, v in pairs(group) do
					fields[#fields + 1] = tostring(k) .. "=" .. Str(v)
				end
				table.sort(fields)
				ns.Log("talentart", "group: " .. table.concat(fields, ", "))
			end
		end
		ns.Print(("talentart: logged %d parts of the talents window. /reload to write the log"):format(math.min(logged, MAX_LINES)))
	end
end
