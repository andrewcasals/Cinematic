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
-- So does a narrow row (the character, trade, merchant or mail window on its
-- own): in the middle it only covers your character, and to the side it
-- leaves the world in view. A row to the side is centered top to bottom too.
-- Wide rows sit to the right, near the top (WIDE_RIGHT, WIDE_TOP).
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

-- Rows narrower than this (UIParent's units) sit there too. Retail's
-- character window with its stats open is 540 wide; the group finder, 563,
-- stays in the middle.
local NARROW = 560
-- ...and start further in than a talking row: nearer the middle, still clear
-- of your character.
local NARROW_LEFT = 0.18
-- Wide rows (quest log, group finder, profession book...): to the right,
-- their right edge this far in from the screen's right edge and their top
-- this far down from its top (shares of the screen's width and height),
-- leaving your character in view on the left. Always kept on the screen
-- (EDGE from its edges, UIParent's units).
local WIDE_RIGHT = 0.17
local WIDE_TOP = 0.115
local EDGE = 8

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
local moving = {}  -- frame -> where the mouse and the window started, while it's being dragged
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

-- Being dragged: by us, or held down under the mouse (the game's own drags,
-- or ours before we heard of it). Moving a window then breaks the drag: the
-- window loses its place under the mouse and sticks to the screen's edge.
local function Held(frame)
	if moving[frame] then
		return true
	end
	return IsMouseButtonDown and IsMouseButtonDown("LeftButton") and ns.Flag(frame:IsMouseOver()) and true or false
end

-- For /cine debug panels: once it has run, each drag of an open window is
-- logged (where it starts and stops, the mouse, and anything else that moves
-- the window or starts moving it meanwhile, with who called), printed next time.
local dragLog, logging, logHooked = {}, false, {}
local following = false -- (our own moves while dragging aren't logged)

local function Where(frame)
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	local cx, cy = GetCursorPosition()
	return ("%s %s %s %s, top %s left %s, mouse %d %d, scale %s"):format(tostring(point), tostring(relativePoint),
		tostring(Number(x)), tostring(Number(y)), tostring(Number(frame:GetTop())), tostring(Number(frame:GetLeft())),
		cx or 0, cy or 0, tostring(Number(frame:GetEffectiveScale())))
end

local function Log(frame, what)
	if not logging then
		return
	end
	if #dragLog >= 40 then
		table.remove(dragLog, 1)
	end
	dragLog[#dragLog + 1] = ("%.2f %s %s: %s"):format(GetTime(), tostring(frame:GetName()), what, Where(frame))
end

local function Caller()
	local stack = (debugstack(3, 2, 0) or "?"):gsub("\n", " < "):gsub("Interface[/\\]AddOns[/\\]", "")
	return stack
end

local function LogHook(frame)
	if logHooked[frame] then
		return
	end
	logHooked[frame] = true
	for _, method in ipairs({ "SetPoint", "ClearAllPoints", "StartMoving", "StopMovingOrSizing" }) do
		hooksecurefunc(frame, method, function()
			if (Held(frame) or method == "StartMoving") and not following then
				Log(frame, method .. " by " .. Caller())
			end
		end)
	end
end

-- The drag itself is ours: the game's StartMoving anchors the window by
-- offsets that can be far off its real spot (seen on the settings window:
-- 500 above the screen's top), and keeping it on the screen then pins it to
-- the edge until the mouse has gone that far back. Instead the window
-- follows the mouse from where it really is, kept on the screen.
local dragger = CreateFrame("Frame")
dragger:Hide()

local function Follow(frame, drag)
	local scale = Number(frame:GetEffectiveScale())
	local width, height = Number(frame:GetWidth()), Number(frame:GetHeight())
	local uiScale = Number(UIParent:GetEffectiveScale())
	local screenWidth, screenHeight = Number(UIParent:GetWidth()), Number(UIParent:GetHeight())
	if not scale or scale <= 0 or not width or not height or not uiScale or not screenWidth or not screenHeight then
		return
	end
	-- (all in the window's own units)
	screenWidth, screenHeight = screenWidth * uiScale / scale, screenHeight * uiScale / scale
	local cx, cy = GetCursorPosition()
	local x = drag.left + (cx - drag.cx) / scale
	local y = drag.top + (cy - drag.cy) / scale
	x = math.max(0, math.min(x, screenWidth - width))
	y = math.min(screenHeight, math.max(y, height))
	following = true
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
	following = false
end

dragger:SetScript("OnUpdate", function(self)
	local any = false
	for frame, drag in pairs(moving) do
		any = true
		if Locked(frame) then
			moving[frame] = nil
		else
			Follow(frame, drag)
		end
	end
	if not any then
		self:Hide()
	end
end)

local function DragStart(frame)
	Log(frame, "drag start")
	if ns.db and ns.db.dragPanels and not Locked(frame) then
		local left, top = Number(frame:GetLeft()), Number(frame:GetTop())
		if not left or not top then
			return
		end
		local cx, cy = GetCursorPosition()
		moving[frame] = { cx = cx, cy = cy, left = left, top = top }
		dragger:Show()
	end
end

local function DragStop(frame)
	local drag = moving[frame]
	if not drag then
		return
	end
	if not Locked(frame) then
		Follow(frame, drag)
	end
	Log(frame, "drag stop")
	moving[frame] = nil
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
	moving[frame] = nil
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
	-- (letting go ends a drag too: OnDragStop doesn't always come)
	frame:HookScript("OnMouseUp", DragStop)
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
	handle:SetScript("OnMouseUp", function() DragStop(frame) end)
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
	-- (a window being dragged isn't moved under the mouse)
	for _, frame in ipairs(row) do
		if Held(frame) then
			return
		end
	end
	local uiScale = Number(UIParent:GetEffectiveScale())
	local screenWidth, screenHeight = Number(UIParent:GetWidth()), Number(UIParent:GetHeight())
	if not uiScale or not screenWidth or not screenHeight then
		return
	end
	-- The row's edges, in UIParent's units.
	local rowLeft, rowRight, rowTop, rowBottom, talk
	for _, frame in ipairs(row) do
		talk = talk or TALK[frame:GetName() or ""]
		local left, right, scale = Number(frame:GetLeft()), Number(frame:GetRight()), Number(frame:GetEffectiveScale())
		local top, bottom = Number(frame:GetTop()), Number(frame:GetBottom())
		if not left or not right or not top or not bottom or not scale then
			return
		end
		left, right = left * scale / uiScale, right * scale / uiScale
		top, bottom = top * scale / uiScale, bottom * scale / uiScale
		rowLeft = rowLeft and math.min(rowLeft, left) or left
		rowRight = rowRight and math.max(rowRight, right) or right
		rowTop = rowTop and math.max(rowTop, top) or top
		rowBottom = rowBottom and math.min(rowBottom, bottom) or bottom
	end
	local side = talk or rowRight - rowLeft < NARROW
	local target = (talk and screenWidth * TALK_LEFT) or (side and screenWidth * NARROW_LEFT)
		or screenWidth * (1 - WIDE_RIGHT) - (rowRight - rowLeft)
	-- A row wider than the screen keeps its left edge on it.
	local shift = math.max(target - rowLeft, -rowLeft)
	-- To the side, centered top to bottom (a row taller than the screen keeps
	-- its top on it).
	local rise
	if side then
		rise = math.min((screenHeight + rowTop - rowBottom) / 2, screenHeight) - rowTop
	else
		-- (A row too tall for that keeps its bottom on the screen, and its top.)
		local top = math.min(screenHeight - EDGE, math.max(screenHeight * (1 - WIDE_TOP), rowTop - rowBottom + EDGE))
		rise = top - rowTop
	end
	if math.abs(shift) < 1 and math.abs(rise) < 1 then
		return
	end
	for _, frame in ipairs(row) do
		local _, _, _, x, y = frame:GetPoint(1)
		x, y = Number(x), Number(y)
		if x and y then
			local toFrame = uiScale / frame:GetEffectiveScale()
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x + shift * toFrame, y + rise * toFrame)
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

-- Windows that settle their size after the game has placed them (the
-- profession book) are placed again when they do: hooked once each.
local sized = {}
local Placed

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
		if not sized[frame] then
			sized[frame] = true
			frame:HookScript("OnSizeChanged", function()
				Placed()
			end)
		end
		local spot = Spot(frame)
		if spot and not Held(frame) then
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
	if spot and not Held(bag) and ns.Flag(bag:IsShown()) and not Locked(bag) then
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

function Placed()
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
	ns.Print(("windows: centering %s, dragging %s, screen %s x %s"):format(db.centerPanels and "on" or "off",
		db.dragPanels and "on" or "off", tostring(Number(UIParent:GetWidth())), tostring(Number(UIParent:GetHeight()))))
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
			ns.Print(("   %d point(s): %s %s %s %s %s; size %s x %s, scale %s"):format(frame:GetNumPoints(), tostring(point),
				tostring(relativeName), tostring(relativePoint), tostring(Number(x)), tostring(Number(y)),
				tostring(Number(frame:GetWidth())), tostring(Number(frame:GetHeight())), tostring(Number(frame:GetScale()))))
		end
	end
	if not any then
		ns.Print("no game windows open")
	end
	if logging then
		ns.Print(#dragLog > 0 and "drags since last time:" or "no drags logged since last time")
		for _, line in ipairs(dragLog) do ns.Print("   " .. line) end
	else
		ns.Print("drags of the open windows are logged from now on: drag, then run this again")
	end
	wipe(dragLog)
	logging = true
	for _, area in ipairs(AREAS) do
		local ok, frame = pcall(GetUIPanel, area)
		if ok and type(frame) == "table" and frame.GetPoint then
			LogHook(frame)
		end
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
