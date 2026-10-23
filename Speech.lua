-- Cinematic: speech from behind you. With "Hide speech you can see as a
-- bubble", a say or yell whose bubble doesn't show on screen (its speaker is
-- behind you, or out of view) shows as a line of text low in the middle of
-- the screen instead of bringing up a faded chat window (db.chatSpeechBehind):
-- "Name says: ..." in the chat's own colour, looking like the chat bubbles
-- do: in a bubble of its own, or just the text (outlined, if ticked) with the
-- Chat bubbles page's Text only, and at its text size. Newer lines push older
-- ones up; each fades out after a while, longer for longer lines.
local _, ns = ...

local MAX_LINES = 3
local WIDTH = 720
local GAP = 4 -- between lines
local PAD_X, PAD_Y = 18, 12 -- round the text, in a bubble
local TAIL_SPACE = 12 -- under a bubble, for its tail
local RISE_FROM = 80 -- how far below the screen a rising line starts
local FADE_IN, FADE_OUT = 0.2, 0.6 -- seconds
local SLIDE_RATE = 10 -- how fast a line slides up into its place (higher: quicker)
local BASE_TIME, PER_LETTER, MOST_TIME = 3, 0.06, 12 -- seconds a line stays up
local SAME_LINE = 1 -- seconds: the same line again (another chat window's copy) is skipped

local holder, spot -- spot: the newest line's bottom middle (db.speechBehindX/Y)
local lines = {} -- newest first: { frame, text, born, life, y }
local spare = {}
local recent = {} -- [event .. text] = when shown

local function Font()
	return _G.ChatBubbleFont or _G.GameFontHighlightLarge
end

-- The look the chat bubbles have now: in a bubble (the game's own, or the
-- page's with Text only unticked) or not, outline thickness (1-3, nil none)
-- and size.
local function Look()
	local db = ns.db
	local textOnly = db.handleBubbles and db.bubblesTextOnly
	local outline = textOnly and db.bubblesTextOutline and (tonumber(db.bubblesTextOutlineSize) or 2) or nil
	local scale = db.handleBubbles and tonumber(db.bubblesTextScale) or 1
	return not textOnly, outline, scale
end

-- How these lines tell they're from behind you (the Chat bubbles page's
-- Behind you; its defaults while that page is off): rising up from below the
-- screen, quieter than a bubble overhead (smaller, fainter), and a bubble's
-- tail on top, pointing up, if ticked.
local function Behind()
	local db = ns.db.handleBubbles and ns.db or ns.DEFAULTS
	return db.speechBehindRise, tonumber(db.speechBehindScale) or 1, tonumber(db.speechBehindAlpha) or 1,
		db.speechBehindTailTop
end

-- A bubble like the game's: its nine-slice where the client has one, else
-- the older bubble textures.
local function Bubble(parent)
	local bubble
	if _G.NineSliceUtil and _G.NineSliceUtil.ApplyLayoutByName then
		bubble = CreateFrame("Frame", nil, parent, "NineSlicePanelTemplate")
		if not pcall(_G.NineSliceUtil.ApplyLayoutByName, bubble, "ChatBubble") then
			bubble:Hide()
			bubble = nil
		end
	end
	if not bubble and BackdropTemplateMixin then
		bubble = CreateFrame("Frame", nil, parent, "BackdropTemplate")
		bubble:SetBackdrop({
			bgFile = "Interface\\Tooltips\\ChatBubble-Background",
			edgeFile = "Interface\\Tooltips\\ChatBubble-Backdrop",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 16, right = 16, top = 16, bottom = 16 },
		})
	end
	if bubble then
		bubble:SetFrameLevel(parent:GetFrameLevel() + 1)
		-- Its tail (placed by TailAt).
		local tail = bubble:CreateTexture(nil, "OVERLAY")
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("ChatBubble-Tail") then
			tail:SetAtlas("ChatBubble-Tail", true)
			bubble.tailInto = 5 -- (how far it overlaps the bubble's edge)
		else
			tail:SetTexture("Interface\\Tooltips\\ChatBubble-Tail")
			tail:SetSize(16, 16)
			bubble.tailInto = 3
		end
		bubble.tail = tail
	end
	return bubble
end

-- The tail under the bubble pointing down, or on top turned to point up.
local function TailAt(bubble, top)
	local tail = bubble.tail
	tail:ClearAllPoints()
	if top then
		tail:SetPoint("BOTTOM", bubble, "TOP", 0, -bubble.tailInto)
	else
		tail:SetPoint("TOP", bubble, "BOTTOM", 0, bubble.tailInto)
	end
	if tail.SetRotation then
		tail:SetRotation(top and math.pi or 0)
	elseif not tail:GetAtlas() then
		tail:SetTexCoord(0, 1, top and 1 or 0, top and 0 or 1)
	end
end

local OUTLINE_FLAGS = { "OUTLINE", "THICKOUTLINE", "THICKOUTLINE" }

local function SetLook(line, words)
	local boxed, outline, scale = Look()
	scale = scale * select(2, Behind())
	local text, font = line.text, Font()
	local file, size = font:GetFont()
	text:SetWidth(WIDTH)
	text:SetText(words)
	if ns.SetPlateNameFont and file then
		-- (A font family, so every alphabet's letters show; it sets the words again.)
		ns.SetPlateNameFont(text, font, file, size, scale, outline and OUTLINE_FLAGS[outline] or "")
	end
	if outline == 3 then
		text:SetShadowColor(0, 0, 0, 1)
		text:SetShadowOffset(2, -2)
	elseif outline then
		text:SetShadowColor(0, 0, 0, 0)
		text:SetShadowOffset(0, 0)
	else
		text:SetShadowColor(font:GetShadowColor())
		text:SetShadowOffset(font:GetShadowOffset())
	end
	-- (Only as wide as its words, so a bubble fits them.)
	local wide = text.GetUnboundedStringWidth and text:GetUnboundedStringWidth() or text:GetStringWidth()
	if type(wide) == "number" and wide < WIDTH then
		text:SetWidth(math.ceil(wide) + 2)
	end
	if boxed and not line.bubble then
		line.bubble = Bubble(line.frame) or false
	end
	line.boxed = boxed and line.bubble and true or false
	local tailTop = select(4, Behind())
	-- (The tail's room is under the bubble, or over it with the tail on top.)
	text:SetPoint("BOTTOM", line.frame, "BOTTOM", 0, line.boxed and PAD_Y + (tailTop and 0 or TAIL_SPACE) or 0)
	if line.bubble then
		TailAt(line.bubble, tailTop)
		line.bubble:ClearAllPoints()
		line.bubble:SetPoint("TOPLEFT", text, "TOPLEFT", -PAD_X, PAD_Y)
		line.bubble:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", PAD_X, -PAD_Y)
		line.bubble:SetShown(line.boxed)
	end
end

local function NewLine()
	local line = table.remove(spare)
	if line then
		return line
	end
	local frame = CreateFrame("Frame", nil, holder)
	frame:SetSize(WIDTH, 1)
	-- (Its words on a frame of their own, over the bubble's.)
	local words = CreateFrame("Frame", nil, frame)
	words:SetAllPoints(frame)
	words:SetFrameLevel(frame:GetFrameLevel() + 5)
	local text = words:CreateFontString(nil, "OVERLAY")
	text:SetFontObject(Font())
	text:SetJustifyH("CENTER")
	text:SetJustifyV("BOTTOM")
	text:SetWordWrap(true)
	return { frame = frame, text = text }
end

local function Drop(i)
	local line = table.remove(lines, i)
	line.frame:Hide()
	spare[#spare + 1] = line
end

local function OnUpdate(_, elapsed)
	local now = GetTime()
	local y = 0
	for i = #lines, 1, -1 do
		local line = lines[i]
		if now >= line.born + line.life or i > MAX_LINES then
			-- (Pushed out or done: fades out where it is.)
			line.fading = line.fading or now
			local alpha = 1 - (now - line.fading) / FADE_OUT
			if alpha <= 0 then
				Drop(i)
			else
				line.frame:SetAlpha(math.min(alpha * line.most, line.frame:GetAlpha()))
			end
		end
	end
	for _, line in ipairs(lines) do
		if not line.fading then
			line.frame:SetAlpha(math.min(1, (now - line.born) / FADE_IN) * line.most)
		end
		-- (Slides up into its place as newer lines come in under it: quick at
		-- first, settling into place.)
		line.y = math.abs(y - line.y) < 0.5 and y or line.y + (y - line.y) * math.min(1, elapsed * SLIDE_RATE)
		line.frame:SetPoint("BOTTOM", spot, "BOTTOM", 0, line.y)
		y = y + line.text:GetStringHeight() + (line.boxed and PAD_Y * 2 + TAIL_SPACE or 0) + GAP
	end
	if #lines == 0 then
		holder:SetScript("OnUpdate", nil)
	end
end
local OnHolderUpdate = ns.Profiled("Speech behind", OnUpdate)

-- Where the lines go: across from the middle of the screen's bottom, and up.
local function PlaceSpot()
	spot:ClearAllPoints()
	spot:SetPoint("BOTTOM", holder, "BOTTOM", tonumber(ns.db.speechBehindX) or 0, tonumber(ns.db.speechBehindY) or 170)
end

local function Holder()
	if not holder then
		holder = CreateFrame("Frame", nil, UIParent)
		holder:SetAllPoints(UIParent)
		holder:SetFrameStrata("LOW")
		holder:EnableMouse(false)
		if ns.AddOverlay then
			ns.AddOverlay(holder) -- (stays up with the UI hidden, like the bubbles)
		end
		spot = CreateFrame("Frame", nil, holder)
		spot:SetSize(1, 1)
	end
	PlaceSpot()
	return holder
end

-- The Chat page's Move button: a box standing in for the lines, dragged to
-- where they should show. Letting go saves the spot and closes it, a line
-- showing there to see; right-click puts it back.
local mover
function ns.MoveSpeechBehind()
	Holder()
	if not mover then
		mover = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
		mover:SetSize(WIDTH / 2, 48)
		mover:SetFrameStrata("FULLSCREEN_DIALOG")
		mover:SetClampedToScreen(true)
		mover:SetMovable(true)
		mover:RegisterForDrag("LeftButton")
		mover:RegisterForClicks("RightButtonUp")
		mover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		mover:SetBackdropColor(0, 0, 0, 0.6)
		mover:SetBackdropBorderColor(1, 0.82, 0, 1)
		local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("CENTER")
		label:SetText(ns.L["Speech from behind you shows here.\nDrag it where you want it, right-click to reset."])
		local close = CreateFrame("Button", nil, mover, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 4, 4)
		local function Snap()
			mover:ClearAllPoints()
			mover:SetPoint("BOTTOM", spot, "BOTTOM", 0, 0)
		end
		mover:SetScript("OnDragStart", mover.StartMoving)
		mover:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			local x = self:GetCenter()
			local bottom = self:GetBottom()
			if type(x) == "number" and type(bottom) == "number" then
				local scale = self:GetEffectiveScale() / holder:GetEffectiveScale()
				ns.db.speechBehindX = math.floor((x * scale - holder:GetWidth() / 2) + 0.5)
				ns.db.speechBehindY = math.floor(bottom * scale + 0.5)
			end
			PlaceSpot()
			Snap()
			self:Hide()
			ns.ShowSpeechBehind("CHAT_MSG_SAY", nil, ns.L["Speech from behind you shows here."])
		end)
		mover:SetScript("OnClick", function()
			ns.db.speechBehindX, ns.db.speechBehindY = nil, nil -- (the defaults)
			PlaceSpot()
			Snap()
		end)
		mover.Snap = Snap
	end
	mover.Snap()
	mover:Show()
end

-- A player's name in their class colour (db.speechBehindClassColor), as the
-- chat window shows it; NPCs' and unknown ones as they are.
local function ClassColoured(name, guid)
	if not ns.db.speechBehindClassColor or type(guid) ~= "string" or (issecretvalue and issecretvalue(guid))
			or not guid:find("^Player%-") or not _G.GetPlayerInfoByGUID then
		return name
	end
	local ok, _, class = pcall(_G.GetPlayerInfoByGUID, guid)
	local colour = ok and type(class) == "string" and not (issecretvalue and issecretvalue(class))
		and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if colour and colour.colorStr then
		return "|c" .. colour.colorStr .. name .. "|r"
	end
	return name
end

-- event: CHAT_MSG_SAY, _YELL, _MONSTER_SAY or _MONSTER_YELL; guid: the
-- speaker's, if the chat message gave it.
function ns.ShowSpeechBehind(event, author, text, guid)
	local now = GetTime()
	local key = event .. text
	if recent[key] and now - recent[key] < SAME_LINE then
		return
	end
	recent[key] = now
	for seen, when in pairs(recent) do
		if now - when >= SAME_LINE then recent[seen] = nil end
	end

	local chatType = event:gsub("^CHAT_MSG_", "")
	local words = text
	if ns.db.speechBehindName and type(author) == "string" and author ~= ""
			and not (issecretvalue and issecretvalue(author)) then
		-- (A player's in brackets, as the chat window shows it, the brackets in
		-- the chat's colour; an NPC's without, as there too.)
		local name = ClassColoured(_G.Ambiguate and _G.Ambiguate(author, "none") or author, guid)
		if not chatType:find("^MONSTER_") then
			name = "[" .. name .. "]"
		end
		local prefix = _G["CHAT_" .. chatType .. "_GET"]
		local ok, said = false, nil
		if type(prefix) == "string" then
			ok, said = pcall(string.format, prefix, name)
		end
		words = (ok and said or (name .. ": ")) .. text
	end

	Holder()
	local line = NewLine()
	local rise, _, most = Behind()
	line.born, line.life, line.fading = now, math.min(MOST_TIME, BASE_TIME + #text * PER_LETTER), nil
	line.most = most
	-- (Rising: it starts below the screen's bottom edge and slides up into place.)
	line.y = rise and -((tonumber(ns.db.speechBehindY) or 170) + RISE_FROM) or 0
	local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]
	local r, g, b = 1, 1, 1
	if info then r, g, b = info.r or 1, info.g or 1, info.b or 1 end
	SetLook(line, words)
	line.text:SetTextColor(r, g, b, 1)
	line.frame:SetAlpha(0)
	line.frame:ClearAllPoints()
	line.frame:SetPoint("BOTTOM", spot, "BOTTOM", 0, line.y)
	line.frame:Show()
	table.insert(lines, 1, line)
	holder:SetScript("OnUpdate", OnHolderUpdate)
end
