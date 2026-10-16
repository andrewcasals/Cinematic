-- Cinematic: the game's windows (quest log, group finder, character,
-- spellbook...), on the Quality of life page.
--
-- centerPanels: the ones the game opens on the left open in the middle of the
-- screen instead. The game still lines its windows up side by side as it
-- always does; the whole row is then slid across so it sits in the middle, so
-- two open at once still sit next to each other. Anything another addon has
-- moved (anchored any other way) is left alone, and the row with it.
-- Talking to a quest giver is the exception: the middle is where they stand,
-- so a row with a quest window in it sits a little in from the left edge
-- instead (far enough in to show it isn't stuck there: it can be dragged).
--
-- dragPanels: drag a window to move it. It opens where it was last dropped
-- from then on, saved in the profile (panelSpots, window name -> where; the
-- game puts it back in its slot whenever it or another window opens or
-- closes: it's moved back to the drop each time). The Put windows back button
-- forgets them (ns.ForgetPanelSpots). The game's own layout cache is kept out
-- of it (SetUserPlaced(false)). Windows without a name are remembered only
-- while they stay open.
--
-- Protected windows can't be moved in a fight: those wait for it to end, and
-- can't be dragged then.
local _, ns = ...

-- The game's window slots, left to right.
local AREAS = { "left", "center", "right", "doublewide" }

-- Windows for talking to someone, and how far in from the left edge a row
-- with one of them starts (a share of the screen's width).
local TALK = { QuestFrame = true, GossipFrame = true }
local TALK_LEFT = 0.12

local function Number(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return type(value) == "number" and value or nil
end

local function Locked(frame)
	return InCombatLockdown() and frame:IsProtected()
end

-- Dragging. Kept in our own tables: fields added to the game's frames taint them.
local hooked = {}  -- frame -> true once it can be dragged
local moving = {}  -- frame -> true while it's being dragged
local dropped = {} -- frame -> { point, relativePoint, x, y } for windows without a name, while they stay open

-- Where the window was last dropped, or nil.
local function Spot(frame)
	if not (ns.db and ns.db.dragPanels) then
		return nil
	end
	local name = frame:GetName()
	if name then
		local spots = ns.db and ns.db.panelSpots
		return type(spots) == "table" and spots[name] or nil
	end
	return dropped[frame]
end

local function DragStart(frame)
	if ns.db and ns.db.dragPanels and not Locked(frame) then
		moving[frame] = true
		frame:StartMoving()
	end
end

local function DragStop(frame)
	if not moving[frame] then
		return
	end
	moving[frame] = nil
	frame:StopMovingOrSizing()
	frame:SetUserPlaced(false)
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	x, y = Number(x), Number(y)
	if not x or not y then
		return
	end
	local spot = { point, relativePoint, x, y }
	local name = frame:GetName()
	if name and ns.db then
		if type(ns.db.panelSpots) ~= "table" then
			ns.db.panelSpots = {}
		end
		ns.db.panelSpots[name] = spot
	else
		dropped[frame] = spot
	end
end

local function Closed(frame)
	if moving[frame] then
		moving[frame] = nil
		frame:StopMovingOrSizing()
		frame:SetUserPlaced(false)
	end
	dropped[frame] = nil
end

-- Most windows are covered edge to edge by their contents (lists, insets,
-- the character model), which take the mouse before the window does: a strip
-- of our own along the title bar is grabbed instead. It stops short of the
-- top right corner, where the close and maximize buttons are.
local HANDLE_HEIGHT = 24
local HANDLE_RIGHT = 64

local handles = {} -- frame -> its title bar strip

local function MakeDraggable(frame, left)
	if hooked[frame] or Locked(frame) then
		return
	end
	hooked[frame] = true
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:HookScript("OnDragStart", DragStart)
	frame:HookScript("OnDragStop", DragStop)
	frame:HookScript("OnHide", Closed)
	local handle = CreateFrame("Frame", nil, frame)
	handle:SetPoint("TOPLEFT", frame, "TOPLEFT", left or 0, 0)
	handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -HANDLE_RIGHT, 0)
	handle:SetHeight(HANDLE_HEIGHT)
	handle:SetFrameLevel(frame:GetFrameLevel() + 10)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function() DragStart(frame) end)
	handle:SetScript("OnDragStop", function() DragStop(frame) end)
	handles[frame] = handle
end

local waitingForCombat = false

-- The game's windows that are open, and which of them sit where the game put
-- them (the row). nil when one is anchored some other way (another addon
-- moved it) or can't be moved now.
local open, row = {}, {}
local function OpenPanels()
	wipe(open)
	wipe(row)
	for _, area in ipairs(AREAS) do
		local ok, frame = pcall(GetUIPanel, area)
		if ok and type(frame) == "table" and frame.GetPoint and ns.Flag(frame:IsShown()) then
			if Locked(frame) then
				waitingForCombat = true
				return nil
			end
			open[#open + 1] = frame
			if not Spot(frame) then
				if frame:GetNumPoints() ~= 1 then
					return nil
				end
				local point, relativeTo, relativePoint = frame:GetPoint(1)
				if point ~= "TOPLEFT" or relativePoint ~= "TOPLEFT" or relativeTo ~= UIParent then
					return nil
				end
				row[#row + 1] = frame
			end
		end
	end
	return open, row
end

local function CenterRow()
	if #row == 0 then
		return
	end
	local uiScale = Number(UIParent:GetEffectiveScale())
	local screenWidth = Number(UIParent:GetWidth())
	if not uiScale or not screenWidth then
		return
	end
	-- The row's edges, in UIParent's units.
	local rowLeft, rowRight, talk
	for _, frame in ipairs(row) do
		talk = talk or TALK[frame:GetName() or ""]
		local left, right, scale = Number(frame:GetLeft()), Number(frame:GetRight()), Number(frame:GetEffectiveScale())
		if not left or not right or not scale then
			return
		end
		left, right = left * scale / uiScale, right * scale / uiScale
		rowLeft = rowLeft and math.min(rowLeft, left) or left
		rowRight = rowRight and math.max(rowRight, right) or right
	end
	local target = talk and screenWidth * TALK_LEFT or (screenWidth - (rowRight - rowLeft)) / 2
	-- A row wider than the screen keeps its left edge on it.
	local shift = math.max(target - rowLeft, -rowLeft)
	if math.abs(shift) < 1 then
		return
	end
	for _, frame in ipairs(row) do
		local _, _, _, x, y = frame:GetPoint(1)
		x, y = Number(x), Number(y)
		if x and y then
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x + shift * uiScale / frame:GetEffectiveScale(), y)
		end
	end
end

-- Every open window can be dragged, wherever it is.
local function HookOpen()
	for _, area in ipairs(AREAS) do
		local ok, frame = pcall(GetUIPanel, area)
		if ok and type(frame) == "table" and frame.GetPoint and ns.Flag(frame:IsShown()) then
			MakeDraggable(frame)
		end
	end
end

local function Arrange()
	if not ns.db then
		return
	end
	if ns.db.dragPanels then
		HookOpen()
	end
	for _, handle in pairs(handles) do
		handle:SetShown(ns.db.dragPanels and true or false)
	end
	if not OpenPanels() then
		return
	end
	for _, frame in ipairs(open) do
		local spot = Spot(frame)
		if spot and not moving[frame] then
			frame:ClearAllPoints()
			frame:SetPoint(spot[1], UIParent, spot[2], spot[3], spot[4])
		end
	end
	if ns.db.centerPanels then
		CenterRow()
	end
end

-- The combined backpack (one bag window for all the bags) isn't one of the
-- game's windows: the game stacks the bags up from the bottom right on its
-- own whenever one opens or closes. It's put back where it was dropped after
-- that; the other bags open next to it (the game anchors them to it). Not
-- separate bags: there are too many of them to move one at a time. Its
-- portrait, top left, opens the bag menu: the strip starts after it.
local BAG_LEFT = 48

local function PlaceBag()
	local bag = ContainerFrameCombinedBags
	if not (ns.db and bag and bag.GetPoint) then
		return
	end
	if ns.db.dragPanels then
		MakeDraggable(bag, BAG_LEFT)
	end
	if handles[bag] then
		handles[bag]:SetShown(ns.db.dragPanels and true or false)
	end
	local spot = Spot(bag)
	if spot and not moving[bag] and ns.Flag(bag:IsShown()) and not Locked(bag) then
		bag:ClearAllPoints()
		bag:SetPoint(spot[1], UIParent, spot[2], spot[3], spot[4])
	end
end

-- Again a frame later: some windows settle their width once shown.
local again = false
local function ArrangeAgain()
	again = false
	Arrange()
	PlaceBag()
end

local function Placed()
	if not (ns.db and (ns.db.centerPanels or ns.db.dragPanels or next(handles))) then
		return
	end
	Arrange()
	PlaceBag()
	if not again then
		again = true
		C_Timer.After(0, ArrangeAgain)
	end
end

-- For /cine debug panels: each open window, how it's anchored, and whether
-- it can be dragged; then what's under the mouse.
function ns.PrintPanelsDebug()
	local db = ns.db or {}
	ns.Print(("windows: centering %s, dragging %s"):format(db.centerPanels and "on" or "off",
		db.dragPanels and "on" or "off"))
	if not GetUIPanel then
		ns.Print("no GetUIPanel on this client")
		return
	end
	local any = false
	for _, area in ipairs(AREAS) do
		local ok, frame = pcall(GetUIPanel, area)
		if ok and type(frame) == "table" and frame.GetPoint then
			any = true
			local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
			local relativeName = relativeTo and (relativeTo == UIParent and "UIParent"
				or relativeTo.GetName and relativeTo:GetName()) or tostring(relativeTo)
			ns.Print(("%s: %s, shown %s, protected %s, mouse %s, movable %s, hooked %s, strip %s, saved spot %s"):format(
				area, tostring(frame:GetName()), tostring(ns.Flag(frame:IsShown())), tostring(frame:IsProtected()),
				tostring(frame:IsMouseEnabled()), tostring(frame:IsMovable()), tostring(hooked[frame] or false),
				tostring(handles[frame] and ns.Flag(handles[frame]:IsShown()) or false), tostring(Spot(frame) ~= nil)))
			ns.Print(("   %d point(s): %s %s %s %s %s"):format(frame:GetNumPoints(), tostring(point),
				tostring(relativeName), tostring(relativePoint), tostring(Number(x)), tostring(Number(y))))
		end
	end
	if not any then
		ns.Print("no game windows open")
	end
	local bag = ContainerFrameCombinedBags
	if bag and bag.GetPoint then
		local point, relativeTo, relativePoint, x, y = bag:GetPoint(1)
		local relativeName = relativeTo and (relativeTo == UIParent and "UIParent"
			or relativeTo.GetName and relativeTo:GetName()) or tostring(relativeTo)
		ns.Print(("combined backpack: shown %s, hooked %s, saved spot %s, %s %s %s %s %s"):format(
			tostring(ns.Flag(bag:IsShown())), tostring(hooked[bag] or false), tostring(Spot(bag) ~= nil),
			tostring(point), tostring(relativeName), tostring(relativePoint), tostring(Number(x)), tostring(Number(y))))
	end
	local focus
	if GetMouseFoci then
		focus = GetMouseFoci()[1]
	elseif GetMouseFocus then
		focus = GetMouseFocus()
	end
	local names = {}
	while focus and #names < 6 do
		names[#names + 1] = (focus.GetName and focus:GetName()) or (handles[focus:GetParent()] == focus and
			"(our drag strip)") or "(unnamed " .. (focus.GetObjectType and focus:GetObjectType() or "?") .. ")"
		focus = focus.GetParent and focus:GetParent()
	end
	ns.Print("under the mouse: " .. (#names > 0 and table.concat(names, " < ") or "nothing"))
end

-- Put windows back: every window opens in its usual place again (the open
-- ones go back as the next window opens or closes).
function ns.ForgetPanelSpots()
	if ns.db then
		ns.db.panelSpots = nil
	end
	wipe(dropped)
end

if GetUIPanel then
	for _, name in ipairs({ "ShowUIPanel", "HideUIPanel", "UpdateUIPanelPositions" }) do
		if _G[name] then
			hooksecurefunc(name, Placed)
		end
	end
	if UpdateContainerFrameAnchors then
		hooksecurefunc("UpdateContainerFrameAnchors", Placed)
	end
	if ContainerFrameCombinedBags then
		ContainerFrameCombinedBags:HookScript("OnShow", Placed)
	end
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function()
		if waitingForCombat then
			waitingForCombat = false
			Placed()
		end
	end)
end
