-- Cinematic minimap sweep: what's on the minimap, for its Reveal boxes
-- (Minimap page: nearby ore, herbs and treasure, quests, other icons).
local _, ns = ...

-- The game doesn't tell addons where the tracking dots are, but it answers a
-- pretend mouse on the minimap (Minimap:UpdateMouseoverAtPoint, in screen
-- pixels) with what its tooltip would say there
-- (C_TooltipInfo.GetMinimapMouseover): the names of the dots under it. So a
-- grid of points is tried, and each name heard is sorted (ns.NodeKind). The
-- minimap has to be full size and on the screen for that, faded or not: see
-- ns.KeepMinimapFullSize. (Shrunk, it can be grown for the sweep only and
-- put back in the same call, before the screen is drawn again, but the game
-- adds no new dots to it while it's shrunk: grow is for /cine debug nodes.)

local STEP = 12          -- minimap units between two points of the grid (a dot answers 6-30 units around it)
local SWEEP_EVERY = 1.5  -- seconds between two sweeps
local HOLD = 3           -- seconds the answer stays yes after the last sweep that found one

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

-- What a name on the minimap is (ns.NodeKind): "group" (you, someone in
-- your group, or a pet), "turnin" (a quest of yours that's done), "objective" (one of yours
-- that isn't: its area), "line" (one of that area's objectives), "herb", "ore",
-- "treasure", or "other" (quest givers among
-- them: their mark's name is just the NPC's, tested). A herb's dot has the name of
-- the herb it gives, so the client names them (item IDs, Classic's herbs); a
-- vein's or chest's name has a word for vein, deposit or chest in the client's
-- language.
local HERB_ITEMS = {
	2447, 765, 2449, 785, 2450, 3820, 2453, 3355, 3369, 3356, 3357, 3818, 3821, 3358,
	3819, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13464, 13463, 13465, 13466, 13467, 13468,
}
local WORDS = {
	enUS = { ore = { "Vein", "Deposit" }, treasure = { "Chest", "Trunk", "Strongbox" } },
	esES = { ore = { "Filón", "Depósito", "filón" }, treasure = { "Cofre", "cofre", "Baúl", "baúl" } },
	deDE = { ore = { "ader", "vorkommen", "Ader", "Vorkommen" }, treasure = { "truhe", "Truhe", "kiste", "Kiste" } },
	frFR = { ore = { "Filon", "Gisement", "filon" }, treasure = { "Coffre", "coffre", "Malle", "malle" } },
	itIT = { ore = { "Vena", "Deposito", "vena" }, treasure = { "Forziere", "forziere", "Baule", "baule" } },
	ptBR = { ore = { "Veio", "Depósito", "veio" }, treasure = { "Baú", "baú", "Arca", "arca" } },
	ruRU = { ore = { "жила", "Жила", "залежи", "Залежи" }, treasure = { "сундук", "Сундук" } },
	koKR = { ore = { "광맥", "광상" }, treasure = { "상자", "궤짝" } },
	zhCN = { ore = { "矿" }, treasure = { "箱" } },
	zhTW = { ore = { "礦" }, treasure = { "箱" } },
}
WORDS.enGB, WORDS.esMX = WORDS.enUS, WORDS.esES
local words = WORDS[GetLocale and GetLocale()] or WORDS.enUS
local herbNames, herbsMissing = {}, true

-- (Item names come from the server: ones not loaded yet are asked for, and
-- read again on a later call.)
local function LoadHerbNames()
	herbsMissing = false
	for _, id in ipairs(HERB_ITEMS) do
		local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
			or GetItemInfo and GetItemInfo(id)
		if type(name) == "string" and not Secret(name) then
			herbNames[name] = true
		else
			herbsMissing = true
			if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		end
	end
end

-- Group members' names and your quests (title -> done), read again once
-- something changed.
local groupNames, questTitles = {}, {}
local listsChanged = true
local function Plain(value)
	return type(value) == "string" and not Secret(value) and value or nil
end

local function ReadQuestLog()
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		local ok, count = pcall(C_QuestLog.GetNumQuestLogEntries)
		for i = 1, ok and type(count) == "number" and count or 0 do
			local okInfo, info = pcall(C_QuestLog.GetInfo, i)
			if okInfo and type(info) == "table" and not info.isHeader and Plain(info.title) then
				local done = C_QuestLog.IsComplete and info.questID and C_QuestLog.IsComplete(info.questID)
				questTitles[info.title] = done == true
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		for i = 1, GetNumQuestLogEntries() do
			local title, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
			if not isHeader and Plain(title) then questTitles[title] = isComplete == 1 end
		end
	end
end

local function ReadLists()
	listsChanged = false
	wipe(groupNames)
	wipe(questTitles)
	-- (Pets too: a warlock's demon is on the minimap the whole time; and you:
	-- your arrow's tooltip has your name, tested.)
	local raid = IsInRaid and IsInRaid()
	local units = { "player", "pet" }
	for i = 1, GetNumGroupMembers and GetNumGroupMembers() or 0 do
		units[#units + 1] = raid and ("raid" .. i) or ("party" .. i)
		units[#units + 1] = raid and ("raidpet" .. i) or ("partypet" .. i)
	end
	for _, unit in ipairs(units) do
		local name = Plain(UnitName(unit))
		if name then groupNames[name] = true end
	end
	-- (The raid roster too, in case a unit's name comes back secret.)
	if raid and GetRaidRosterInfo then
		for i = 1, GetNumGroupMembers() do
			local ok, name = pcall(GetRaidRosterInfo, i)
			name = ok and Plain(name)
			if name then groupNames[name] = true end
		end
	end
	pcall(ReadQuestLog)
end

local listWatcher = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA",
	"PLAYER_ENTERING_WORLD", "UNIT_PET" }) do
	pcall(listWatcher.RegisterEvent, listWatcher, event)
end
listWatcher:SetScript("OnEvent", function() listsChanged = true end)

local function HasWord(name, list)
	for _, word in ipairs(list) do
		if name:find(word, 1, true) then return true end
	end
	return false
end

function ns.NodeKind(name)
	if listsChanged then ReadLists() end
	if herbsMissing then LoadHerbNames() end
	-- (Forever's players have a surname: "Sapo Corto" on the minimap, just
	-- "Sapo" from UnitName.)
	if groupNames[name] or groupNames[name:match("^(%S+) ") or ""] then return "group" end
	-- (Under a quest area's title, its objectives: "- 0/12 Kobold Laborer slain", tested.)
	if name:sub(1, 2) == "- " then return "line" end
	local done = questTitles[name]
	if done ~= nil then return done and "turnin" or "objective" end
	if herbNames[name] then return "herb" end
	if HasWord(name, words.ore) then return "ore" end
	if HasWord(name, words.treasure) then return "treasure" end
	return "other"
end

local function MinimapEntry()
	for _, entry in ipairs(ns.managed or {}) do
		if entry.frame == Minimap then return entry end
	end
end

-- The faded minimap's size and place back (see the top). Returns what puts it
-- back as it was, or nil when it isn't shrunk or moved off the screen.
-- (Kept full size, it's moved off the screen while faded with a quest area on it, Frames.lua
-- ns.ParkFullSize: the sweep hears nothing out there, tested, so it's put
-- back in its place for the sweep too.)
local function Grow()
	local entry = MinimapEntry()
	if not (entry and (entry.shrunk or entry.parkedFullSize)) then return nil end
	local scale, points = Minimap:GetScale(), {}
	for i = 1, Minimap:GetNumPoints() do points[i] = { Minimap:GetPoint(i) } end
	if entry.shrunk then Minimap:SetScale(entry.savedScale or 1) end
	if entry.savedPoints then
		Minimap:ClearAllPoints()
		for _, p in ipairs(entry.savedPoints) do Minimap:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
	end
	return function()
		Minimap:SetScale(scale)
		Minimap:ClearAllPoints()
		for _, p in ipairs(points) do Minimap:SetPoint(unpack(p)) end
	end
end

-- Tries a grid of points over the minimap as it is now. Each name heard goes
-- to found[name] = { points, gray, list } (gray: a dot in a cave; list: the
-- points' offsets from the minimap's centre, x, y pairs); stop(name), when
-- given, ends the sweep at the first name it says yes to.
local function Probe(step, found, stop)
	local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
	local scale, width = Minimap:GetEffectiveScale(), Minimap:GetWidth()
	if not (left and bottom and scale and width) or width <= 0 then return nil, "the minimap has no place" end
	local probes = 0
	local ok, err = pcall(function()
		Minimap:SetUsingSoftCursor(true)
		local half = width / 2
		for dx = -half, half, step do
			for dy = -half, half, step do
				if dx * dx + dy * dy <= half * half then
					probes = probes + 1
					Minimap:UpdateMouseoverAtPoint((left + half + dx) * scale, (bottom + half + dy) * scale)
					local data = C_TooltipInfo.GetMinimapMouseover()
					local lines = not Secret(data) and type(data) == "table" and data.lines
					for _, line in ipairs(type(lines) == "table" and not Secret(lines) and lines or {}) do
						local text, color = line.leftText, line.leftColor
						if type(text) == "string" and not Secret(text) then
							local gray = type(color) == "table" and not Secret(color) and type(color.r) == "number"
								and math.abs(color.r - color.g) < 0.05 and math.abs(color.g - color.b) < 0.05
								and color.r < 0.8
							-- (Colour codes and icons out, one name a line.)
							local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
								:gsub("|T.-|t", ""):gsub("|A.-|a", "")
							for name in plain:gmatch("[^\n]+") do
								name = name:match("^%s*(.-)%s*$")
								if name ~= "" then
									local entry = found[name] or { points = 0 }
									entry.points = entry.points + 1
									-- (Each point, offset from the minimap's centre: where its dots are.)
									entry.list = entry.list or {}
									entry.list[#entry.list + 1], entry.list[#entry.list + 2] = dx, dy
									entry.gray = entry.gray or gray or text:find("|cff7f7f7f") ~= nil
									-- (The line as the game wrote it, and its colour: for /cine debug nodes raw.)
									entry.raw = entry.raw or text
									entry.color = entry.color or (type(color) == "table" and not Secret(color)
										and type(color.r) == "number" and ("%02x%02x%02x"):format(color.r * 255,
										color.g * 255, color.b * 255)) or nil
									found[name] = entry
									if stop and stop(name, entry) then return end
								end
							end
						end
					end
				end
			end
		end
	end)
	pcall(Minimap.SetUsingSoftCursor, Minimap, false)
	if not ok then return nil, "the game refused: " .. tostring(err) end
	return found, probes
end

-- Whether this client lets the minimap be swept at all (retail doesn't,
-- tested: its Reveal boxes that need a sweep are hidden, Options.lua).
function ns.CanSweepMinimap()
	return Minimap.UpdateMouseoverAtPoint ~= nil and Minimap.SetUsingSoftCursor ~= nil
		and C_TooltipInfo ~= nil and C_TooltipInfo.GetMinimapMouseover ~= nil
end

-- One sweep: found (name -> { points, gray }), points tried, and whether the
-- faded minimap was grown for it (grow); or nil and why not. (refresh: has
-- the game place its dots first, Minimap:UpdateBlips, for /cine debug nodes update.)
function ns.SweepMinimap(step, grow, stop, refresh)
	if not ns.CanSweepMinimap() then
		return nil, "this client can't move a pretend mouse over the minimap"
	end
	-- (Not in combat; nor with your own mouse there, whose tooltip it would change.)
	if InCombatLockdown() then return nil, "in combat" end
	if ns.Flag(Minimap:IsMouseOver()) then return nil, "your mouse is over the minimap" end
	local entry = MinimapEntry()
	local parked = entry and entry.parkedFullSize
	if parked and ns.IsEntryHovered(entry) then return nil, "your mouse is over the minimap" end
	local putBack
	if grow or parked then
		local ok, result = pcall(Grow)
		if not ok then return nil, "couldn't grow the minimap: " .. tostring(result) end
		putBack = result
	end
	if refresh and Minimap.UpdateBlips then pcall(Minimap.UpdateBlips, Minimap) end
	local found, probes = Probe(step or STEP, {}, stop)
	if putBack then
		local ok, err = pcall(putBack)
		if not ok then ns.Log("nodes", "couldn't put the minimap back: " .. tostring(err)) end
	end
	return found, probes, putBack ~= nil and not parked
end

-- Reveal (Minimap page): which kinds of name bring the minimap up. (Group
-- members and a quest area's objective lines count as nothing: the first are
-- on the minimap all the time, the second come with their quest's title.)
local REVEAL = {
	herb = "minimapRevealNodes", ore = "minimapRevealNodes", treasure = "minimapRevealNodes",
	turnin = "minimapRevealTurnIns",
	objective = "minimapRevealAreas", other = "minimapRevealIcons",
}
-- (A quest's area off the minimap has an arrow on its rim pointing to it,
-- named like the quest, there the whole time (Track Quest POIs): a quest name
-- heard only near the rim is that arrow, and counts as nothing. The area
-- counts once it reaches further in.)
local QUEST_KINDS = { objective = true, turnin = true }
local function OnlyAtRim(entry)
	local half = (Minimap:GetWidth() or 0) / 2
	local list = entry and entry.list
	if not list or half <= 0 then return false end
	local inner = (half - 2 * STEP) ^ 2
	for i = 1, #list, 2 do
		if list[i] ^ 2 + list[i + 1] ^ 2 < inner then return false end
	end
	return true
end

local function Wanted(name, entry)
	local kind = ns.NodeKind(name)
	local option = REVEAL[kind]
	if not (option ~= nil and ns.db[option] == true) then return false end
	return not (QUEST_KINDS[kind] and OnlyAtRim(entry))
end

local function AnyReveal()
	local db = ns.db
	return db and db.handleMinimap ~= false and ns.CanSweepMinimap() and (db.minimapRevealNodes
		or db.minimapRevealTurnIns or db.minimapRevealAreas or db.minimapRevealIcons) or false
end

-- While a reveal is ticked, the faded minimap isn't shrunk and moved off the
-- screen as usual (the game stops adding dots to it then, tested): it stays
-- full size in its place at alpha 0, with its icons shrunk to nothing
-- (Minimap:SetIconScale), which hides its player arrow and dots too. They get
-- their size back as soon as it fades in. (Frames.lua, ns.SetEntryAlpha.)
-- (0.01 still left the arrow as one pixel in the middle: 0, or as near it as
-- the client takes.)
local ICON_TINY = { 0, 0.0001 }
local iconScale, iconsHidden, settingIcons, tinyUsed = 1, false, false, nil
if Minimap.SetIconScale then
	-- (Another addon's own icon scale is what's put back.)
	hooksecurefunc(Minimap, "SetIconScale", function(_, scale)
		if not settingIcons and type(scale) == "number" then iconScale = scale end
	end)
end

-- (In combat the minimap can't be shrunk: the answer from before the fight
-- stands, so its arrow doesn't show meanwhile.)
local keep = false
function ns.KeepMinimapFullSize()
	if not (InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))) then
		keep = ns.minimapStayFullSize -- (/cine debug nodes stay)
			or (Minimap.SetIconScale ~= nil and AnyReveal())
	end
	return keep or false
end

function ns.SetMinimapIconsHidden(hidden)
	if hidden == iconsHidden or not Minimap.SetIconScale then return end
	iconsHidden = hidden
	settingIcons = true
	if hidden then
		tinyUsed = nil
		for _, scale in ipairs(ICON_TINY) do
			if pcall(Minimap.SetIconScale, Minimap, scale) then
				tinyUsed = scale
				break
			end
		end
	else
		pcall(Minimap.SetIconScale, Minimap, iconScale)
	end
	settingIcons = false
end

-- For /cine debug minimap.
function ns.MinimapIconState()
	local methods = {}
	for method in pairs(ns.BLOB_ALPHAS) do methods[#methods + 1] = method:gsub("^Set", ""):gsub("Alpha$", "") end
	table.sort(methods)
	return ("icons hidden %s (scale %s, put back to %s), kept full size %s; quest areas hidden %s (%s)"):format(
		tostring(iconsHidden), tostring(iconsHidden and tinyUsed or iconScale), tostring(iconScale),
		tostring(ns.KeepMinimapFullSize()), tostring(ns.minimapBlobsHidden or false),
		#methods > 0 and table.concat(methods, ", ") or "none on this client")
end

-- The quest, task and dig site areas (the blue shapes) ignore the minimap's
-- alpha as well: their own alphas go to 0 while it's faded full size. The
-- game can't say what they were, and Blizzard's UI never sets them (so 1),
-- unless another addon did: its value is what's put back.
local BLOB_ALPHAS = {}
ns.BLOB_ALPHAS = BLOB_ALPHAS -- (for /cine debug minimap)
for _, kind in ipairs({ "Quest", "Task", "Arch" }) do
	for _, part in ipairs({ "Inside", "Outside", "Ring" }) do
		local method = "Set" .. kind .. "Blob" .. part .. "Alpha"
		if Minimap[method] then BLOB_ALPHAS[method] = 1 end
	end
end
local blobsHidden, settingBlobs = false, false
for method in pairs(BLOB_ALPHAS) do
	hooksecurefunc(Minimap, method, function(_, alpha)
		if settingBlobs or type(alpha) ~= "number" or Secret(alpha) then return end
		BLOB_ALPHAS[method] = alpha
		-- (Set while hidden: back to 0, the value kept for later.)
		if blobsHidden then
			settingBlobs = true
			pcall(Minimap[method], Minimap, 0)
			settingBlobs = false
		end
	end)
end

function ns.SetMinimapBlobsHidden(hidden)
	if hidden == blobsHidden then return end
	blobsHidden = hidden
	ns.minimapBlobsHidden = hidden
	settingBlobs = true
	for method, alpha in pairs(BLOB_ALPHAS) do
		pcall(Minimap[method], Minimap, hidden and 0 or alpha)
	end
	settingBlobs = false
end

-- From the Frames.lua tick: whether something ticked under Reveal is on the
-- minimap. Swept every SWEEP_EVERY seconds while the minimap is faded (or
-- fading), or up for what the last sweep found; between sweeps, and while one
-- can't run (in combat, the mouse on the minimap), the last answer stands.
local sweptAt, seenAt = -math.huge, -math.huge
local last = {} -- the last sweep, for /cine debug tracking
-- Whether the last sweep heard a quest's area on the minimap (not just its
-- arrow on the rim): the faded minimap waits off the screen meanwhile
-- (Frames.lua), since its blue outline shows through alpha 0. Elsewhere it
-- stays in its place: off the screen the game adds no new dots, tested.
local areaShown = false
function ns.MinimapAreaShown()
	return areaShown
end

-- Nearby ore, herbs and treasure's Ping where it is (minimapNodePing): a
-- minimap ping where a node shows up, the same ping as clicking the minimap
-- (so your group sees it too). A node is the middle of the points that heard
-- its name next to each other: two dots of the same name are two nodes,
-- unless they touch. One counts as new unless a node of its name was close by
-- in the sweep before, in world yards where the client says where you are (so
-- walking past one doesn't ping it again).
local NODE_KINDS = { herb = true, ore = true, treasure = true }
-- The nodes the last sweep found: { name, x, y (offset from the minimap's
-- centre, its units), n, w (yards north and west in the world, when known) }.
local nodes = {}
local MATCH_YARDS, MATCH_UNITS = 30, 20 -- this close to one found before, of the same name: the same node
-- Nodes pinged lately, the same way (and when): one a sweep missed (its dot at
-- the minimap's edge, or hardly heard) isn't pinged again when it's back.
local pinged, PING_MEMORY = {}, 60 -- seconds

-- Yards per minimap unit and the minimap's turn (radians, 0 unless it
-- rotates), or nil where they can't be read.
local function View()
	local ok, radius = pcall(C_Minimap and C_Minimap.GetViewRadius or error)
	local width = Minimap:GetWidth()
	if not ok or type(radius) ~= "number" or Secret(radius) or radius <= 0 or not width or width <= 0 then return nil end
	local facing = 0
	if GetCVar("rotateMinimap") == "1" then
		facing = GetPlayerFacing and GetPlayerFacing()
		if type(facing) ~= "number" or Secret(facing) then return nil end
	end
	return radius / (width / 2), facing
end

-- Where you are: yards north and west (nil in instances, where it's hidden).
local function Here()
	local n, w = UnitPosition("player")
	if type(n) ~= "number" or Secret(n) or type(w) ~= "number" or Secret(w) then return nil end
	return n, w
end

-- One name's points (x, y pairs) split into nodes: points next to each
-- other on the grid are one dot's; each group's middle is where it is.
local function Groups(points, step)
	local count, group, list = #points / 2, {}, {}
	local reach = (step * 1.5) ^ 2
	for i = 1, count do
		if not group[i] then
			local sx, sy, size, queue = 0, 0, 0, { i }
			group[i] = true
			while #queue > 0 do
				local j = table.remove(queue)
				local jx, jy = points[j * 2 - 1], points[j * 2]
				sx, sy, size = sx + jx, sy + jy, size + 1
				for k = 1, count do
					if not group[k] and (points[k * 2 - 1] - jx) ^ 2 + (points[k * 2] - jy) ^ 2 <= reach then
						group[k] = true
						queue[#queue + 1] = k
					end
				end
			end
			list[#list + 1] = { sx / size, sy / size }
		end
	end
	return list
end

local function Near(node, before)
	if before.name ~= node.name then return false end
	if node.n and before.n then
		return (node.n - before.n) ^ 2 + (node.w - before.w) ^ 2 <= MATCH_YARDS ^ 2
	end
	return (node.x - before.x) ^ 2 + (node.y - before.y) ^ 2 <= MATCH_UNITS ^ 2
end

local function SeenBefore(node, now)
	for i = #pinged, 1, -1 do
		if now - pinged[i].at > PING_MEMORY then
			table.remove(pinged, i)
		elseif Near(node, pinged[i]) then
			return true
		end
	end
	for _, before in ipairs(nodes) do
		if Near(node, before) then return true end
	end
	return false
end

local function PingNodes(found)
	local db, now = ns.db, {}
	local yards, facing = View()
	local n, w = Here()
	for name, entry in pairs(found or {}) do
		if NODE_KINDS[ns.NodeKind(name)] and db.minimapRevealNodes and entry.list then
			for _, spot in ipairs(Groups(entry.list, STEP)) do
				local node = { name = name, x = spot[1], y = spot[2] }
				if yards and n then
					-- (Turned back from the minimap's turn into yards east and north.)
					local cos, sin = math.cos(facing), math.sin(facing)
					local sx, sy = node.x * yards, node.y * yards
					node.n, node.w = n + sx * sin + sy * cos, w - (sx * cos - sy * sin)
				end
				if db.minimapNodePing and Minimap.PingLocation and not SeenBefore(node, GetTime()) then
					pcall(Minimap.PingLocation, Minimap, node.x, node.y)
					node.at = GetTime()
					pinged[#pinged + 1] = node
				end
				now[#now + 1] = node
			end
		end
	end
	nodes = now
end

function ns.IsMinimapRevealed(now)
	if not AnyReveal() then
		nodes = {}
		return false
	end
	if now - sweptAt >= SWEEP_EVERY and (Minimap:GetEffectiveAlpha() < 0.99 or now - seenAt < HOLD) then
		sweptAt = now
		-- (The ping needs every point that hears a node: no stopping at the first.)
		local marking = ns.db.minimapRevealNodes and ns.db.minimapNodePing
		local found, probes, grown = ns.SweepMinimap(STEP, true, not marking and Wanted or nil)
		last.at, last.why, last.grown, last.names = now, nil, grown, nil
		if found then
			local names = {}
			areaShown = false
			for name, entry in pairs(found) do
				local wanted = Wanted(name, entry)
				local kind = ns.NodeKind(name)
				if kind == "objective" and not OnlyAtRim(entry) then areaShown = true end
				names[#names + 1] = ("%s (%s%s%s)"):format(name, kind,
					QUEST_KINDS[kind] and OnlyAtRim(entry) and ", at the rim" or "", wanted and ", reveals" or "")
				if wanted then seenAt = now end
			end
			last.names, last.probes = table.concat(names, ", "), probes
			PingNodes(found)
		else
			last.why = probes
		end
	end
	return now - seenAt < HOLD
end
ns.IsMinimapRevealed = ns.Profiled("Minimap sweep", ns.IsMinimapRevealed)

function ns.NodeSweepReport()
	if not ns.CanSweepMinimap() then return "minimap sweep: this client can't move a pretend mouse over the minimap" end
	if not last.at then return "minimap sweep: hasn't run (needs a Reveal box ticked, Minimap page)" end
	-- (Each node's place in the world should stay put as you move: if it drifts,
	-- the sums turning minimap offsets into yards are off.)
	local places = {}
	for _, node in ipairs(nodes) do
		places[#places + 1] = node.n and ("%s at %.0f N %.0f W"):format(node.name, node.n, node.w)
			or ("%s at %.0f, %.0f on the minimap (no world place)"):format(node.name, node.x, node.y)
	end
	if #places > 0 then ns.Print("nodes: " .. table.concat(places, "; ")) end
	return ("minimap sweep: %.1fs ago%s%s: %s; last reveal %s"):format(GetTime() - last.at,
		last.grown and ", minimap grown for it" or "",
		areaShown and ", a quest area on it (waits off the screen while faded)" or "",
		last.why and ("couldn't sweep (" .. tostring(last.why) .. ")")
			or (("%d points, heard %s"):format(last.probes or 0, last.names ~= "" and last.names or "nothing")),
		seenAt > -math.huge and ("%.1fs ago"):format(GetTime() - seenAt) or "never")
end
