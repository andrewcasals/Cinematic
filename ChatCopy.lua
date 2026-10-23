-- Cinematic: copying chat. A small icon in the bottom right of each chat
-- window (while the mouse is over it) opens that window's lines as text, to
-- select and copy with Ctrl+C. Addons can't put text on the clipboard, so a
-- box to copy from is as close as it gets (chatCopyButton, Quality of life).
local ADDON_NAME, ns = ...
local L = ns.L

local BUTTON_SIZE = 16
local ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Quill" -- (Media/make_quill.py)
local CHECK_INTERVAL = 0.1
local buttons = {} -- [chat frame] = its copy button
local window

local function Readable(text)
	return type(text) == "string" and not (issecretvalue and issecretvalue(text))
end

-- A chat line as plain text: links keep their shown text, colours, icons
-- and protected Battle.net names (which can't be copied) go.
local function PlainText(text)
	text = text:gsub("|T.-|t", "")
		:gsub("|A.-|a", "")
		:gsub("|K.-|k", "?")
		:gsub("|H.-|h(.-)|h", "%1")
		:gsub("|c%x%x%x%x%x%x%x%x", "")
		:gsub("|cn[^:]*:", "")
		:gsub("|r", "")
	return text
end

local function ChatLines(chatFrame)
	local lines = {}
	for i = 1, chatFrame:GetNumMessages() do
		local text = chatFrame:GetMessageInfo(i)
		if Readable(text) then
			lines[#lines + 1] = PlainText(text)
		end
	end
	return table.concat(lines, "\n")
end

local function CreateWindow()
	window = CreateFrame("Frame", "CinematicChatCopyWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	window:SetSize(620, 400)
	window:SetPoint("CENTER", 0, 40)
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:SetClampedToScreen(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	tinsert(UISpecialFrames, "CinematicChatCopyWindow") -- Escape closes it

	local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -14)
	window.title = title

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	hint:SetPoint("RIGHT", window, "RIGHT", -16, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText(L["Drag over the lines you want (or Select all), then press Ctrl+C to copy them."])

	local holder = CreateFrame("Frame", nil, window, BackdropTemplateMixin and "BackdropTemplate")
	holder:SetPoint("TOPLEFT", 14, -56)
	holder:SetPoint("BOTTOMRIGHT", -14, 44)
	holder:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	holder:SetBackdropColor(0, 0, 0, 0.6)
	local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetMaxLetters(0)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(550)
	box:SetScript("OnEscapePressed", function() window:Hide() end)
	-- Read-only: any typing puts the text back.
	box:SetScript("OnTextChanged", function(self, user)
		if user then
			self:SetText(window.text)
		end
	end)
	scroll:SetScrollChild(box)
	scroll:SetScript("OnSizeChanged", function(_, width) box:SetWidth(width) end)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	window.box, window.scroll = box, scroll

	local selectAll = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	selectAll:SetSize(110, 22)
	selectAll:SetPoint("BOTTOMRIGHT", -16, 14)
	selectAll:SetText(L["Select all"])
	selectAll:SetScript("OnClick", function()
		box:SetFocus()
		box:HighlightText()
	end)
end

-- Opens a chat window's lines, scrolled to the newest, all selected.
local function ShowCopy(chatFrame)
	if not window then CreateWindow() end
	local name = chatFrame.name
	if not Readable(name) and FCF_GetChatWindowInfo and chatFrame.GetID then
		name = FCF_GetChatWindowInfo(chatFrame:GetID())
	end
	window.title:SetText(Readable(name) and name ~= "" and L["Copy chat: %s"]:format(name) or L["Copy chat"])
	window.text = ChatLines(chatFrame)
	window:Show()
	window.box:SetText(window.text)
	window.box:SetFocus()
	window.box:HighlightText()
	C_Timer.After(0, function()
		window.scroll:SetVerticalScroll(window.scroll:GetVerticalScrollRange())
	end)
end

local function CreateButton(chatFrame)
	local button = CreateFrame("Button", nil, chatFrame)
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetFrameLevel(chatFrame:GetFrameLevel() + 10)
	button:SetNormalTexture(ICON)
	button:SetPushedTexture(ICON)
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	button:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
	button:SetScript("OnClick", function() ShowCopy(chatFrame) end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(L["Copy chat"])
		GameTooltip:AddLine(L["Opens this chat window's lines to copy."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	buttons[chatFrame] = button
	return button
end

-- Bottom right, left of the scroll-to-bottom arrow while that's up.
local function PlaceButton(button, chatFrame)
	local arrow = chatFrame.ScrollToBottomButton
	local anchor = arrow and ns.Flag(arrow:IsShown()) and arrow or nil
	if button.anchor == anchor and button.placed then
		return
	end
	button.anchor, button.placed = anchor, true
	button:ClearAllPoints()
	if anchor then
		button:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
	else
		button:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", -2, 2)
	end
end

-- Each chat window's button shows while the mouse is over the window (new
-- whisper windows get one when they first open).
local function Update(enabled)
	for _, frameName in ipairs(CHAT_FRAMES or {}) do
		local chatFrame = _G[frameName]
		if chatFrame and chatFrame.GetMessageInfo then
			local button = buttons[chatFrame]
			local show = enabled and ns.Flag(chatFrame:IsVisible())
				and (ns.Flag(chatFrame:IsMouseOver()) or button and ns.Flag(button:IsMouseOver()))
			if show then
				button = button or CreateButton(chatFrame)
				PlaceButton(button, chatFrame)
			end
			if button and button:IsShown() ~= (show and true or false) then
				button:SetShown(show)
			end
		end
	end
end

local watcher = CreateFrame("Frame")
local sinceCheck = 0
watcher:SetScript("OnUpdate", ns.Profiled("Chat copy button", function(_, elapsed)
	sinceCheck = sinceCheck + elapsed
	if sinceCheck < CHECK_INTERVAL then
		return
	end
	sinceCheck = 0
	Update(ns.Setting("chatCopyButton"))
end))
