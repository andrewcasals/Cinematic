-- Cinematic: chat bubbles. Where the game shows them (say and yell, party; by
-- place, as the page's grid says), and how they look (text only, outline,
-- text size).
local _, ns = ...

-- Where the bubbles show is the game's own two settings, written as you
-- enter each place: chatBubbles (say, yell, NPC speech) and chatBubblesParty.
-- Your own values are put back when the page's switch goes off.
local CVARS = { Say = "chatBubbles", Party = "chatBubblesParty" }

-- Whether the page's grid hides that kind of bubble where you are.
local function OffHere(db, kind, where)
	return db["bubbles" .. kind .. "OffAlways"] or db["bubbles" .. kind .. "OffIn" .. where]
end

local function ApplyCVars(db)
	local where = ns.EffectPlace()
	for kind, cvar in pairs(CVARS) do
		if GetCVar(cvar) ~= nil then
			ns.SaveCVar(cvar)
			local want = OffHere(db, kind, where) and "0" or "1"
			if GetCVar(cvar) ~= want then
				ns.LogDetail("cvar", ("%s -> %s (chat bubbles, %s)"):format(cvar, want, where))
				SetCVar(cvar, want)
			end
		end
	end
end

local function RestoreCVars()
	for _, cvar in pairs(CVARS) do
		ns.RestoreCVar(cvar)
	end
end

-- The look: each bubble's background and border (every texture in it) faded
-- out for text only (its text outlined in black, if ticked), and its text
-- scaled. Bubbles are reused, so each is
-- looked at again as it shows. Bubbles the game keeps from addons (in
-- instances, on retail) are left as they are.
local hidden = setmetatable({}, { __mode = "k" }) -- texture -> true, while faded out
local scaled = setmetatable({}, { __mode = "k" }) -- font string -> true, while scaled
-- font string -> its own font flags and shadow, while outlined
local outlined = setmetatable({}, { __mode = "k" })

-- Outline thickness (bubblesTextOutlineSize) -> the font flags, and whether
-- it has a drop shadow too.
local OUTLINE_FLAGS = { "OUTLINE", "THICKOUTLINE", "THICKOUTLINE" }
local SHADOW_X, SHADOW_Y = 2, -2

-- size: 1-3 outlines it (see OUTLINE_FLAGS); nil puts its own look back.
local function Outline(region, size)
	local file, height, flags = region:GetFont()
	if not file then return end
	local own = outlined[region]
	if size then
		if not own then
			local x, y = region:GetShadowOffset()
			own = { flags = flags or "", x = x, y = y, color = { region:GetShadowColor() } }
			outlined[region] = own
		end
		local want = OUTLINE_FLAGS[size] or OUTLINE_FLAGS[1]
		if flags ~= want then -- (the game can set the font again as it reuses a bubble)
			region:SetFont(file, height, want)
		end
		if size == 3 then
			region:SetShadowColor(0, 0, 0, 1)
			region:SetShadowOffset(SHADOW_X, SHADOW_Y)
		else
			region:SetShadowColor(unpack(own.color))
			region:SetShadowOffset(own.x, own.y)
		end
	elseif own then
		region:SetFont(file, height, own.flags)
		region:SetShadowColor(unpack(own.color))
		region:SetShadowOffset(own.x, own.y)
		outlined[region] = nil
	end
end

local function Style(textOnly, outline, scale, ...)
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		local kind = region:GetObjectType()
		if kind == "Texture" then
			if textOnly and not hidden[region] then
				hidden[region] = true
				region:SetAlpha(0)
			elseif not textOnly and hidden[region] then
				hidden[region] = nil
				region:SetAlpha(1)
			end
		elseif kind == "FontString" then
			if outline or outlined[region] then
				Outline(region, outline)
			end
			if region.SetTextScale and (scale ~= 1 or scaled[region]) then
				region:SetTextScale(scale)
				scaled[region] = scale ~= 1 or nil
			end
		end
	end
end

local function StyleFrame(frame, textOnly, outline, scale)
	Style(textOnly, outline, scale, frame:GetRegions())
	for i = 1, select("#", frame:GetChildren()) do
		local child = select(i, frame:GetChildren())
		if not (child.IsForbidden and child:IsForbidden()) then
			StyleFrame(child, textOnly, outline, scale)
		end
	end
end

local function StyleBubbles()
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then
		return
	end
	local db = ns.db
	local on = db.handleBubbles
	local textOnly = on and db.bubblesTextOnly or false
	local outline = textOnly and db.bubblesTextOutline and (tonumber(db.bubblesTextOutlineSize) or 2) or nil
	local scale = on and tonumber(db.bubblesTextScale) or 1
	if not on and not next(hidden) and not next(scaled) and not next(outlined) then
		return
	end
	for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
		if not (bubble.IsForbidden and bubble:IsForbidden()) then
			StyleFrame(bubble, textOnly, outline, scale)
		end
	end
end

-- Whether a bubble saying exactly this text is showing on screen (so its chat
-- line needn't show the chat window). Bubbles the game keeps from addons can't
-- be read, so those count as not showing.
local function SaysText(frame, text)
	for i = 1, select("#", frame:GetRegions()) do
		local region = select(i, frame:GetRegions())
		if region:GetObjectType() == "FontString" then
			local shown = region:GetText()
			if type(shown) == "string" and not (issecretvalue and issecretvalue(shown)) and shown == text then
				return true
			end
		end
	end
	for i = 1, select("#", frame:GetChildren()) do
		local child = select(i, frame:GetChildren())
		if not (child.IsForbidden and child:IsForbidden()) and SaysText(child, text) then
			return true
		end
	end
	return false
end

function ns.IsBubbleOnScreen(text)
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then
		return false
	end
	local width, height = WorldFrame:GetWidth(), WorldFrame:GetHeight()
	for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
		if not (bubble.IsForbidden and bubble:IsForbidden()) and ns.Flag(bubble:IsVisible())
			and SaysText(bubble, text) then
			-- (Its centre in the world frame's own units, inside the screen.)
			local x, y = bubble:GetCenter()
			local scale = bubble:GetEffectiveScale() / WorldFrame:GetEffectiveScale()
			if type(x) == "number" and not (issecretvalue and issecretvalue(x)) then
				x, y = x * scale, y * scale
				if x >= 0 and x <= width and y >= 0 and y <= height then
					return true
				end
			end
		end
	end
	return false
end

-- A bubble appears a frame or so after its chat message: the bubbles are
-- looked at for a short while after each one.
local BUBBLE_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY",
}
local WATCH_FOR = 0.5
local watchLeft = 0

local watcher = CreateFrame("Frame")
local function OnUpdate(self, elapsed)
	StyleBubbles()
	watchLeft = watchLeft - elapsed
	if watchLeft <= 0 then
		self:SetScript("OnUpdate", nil)
	end
end

local wasOn = false
-- The settings changing (on the page, a profile, a reset) or a new place.
function ns.ApplyBubbles()
	local db = ns.db
	if not db then return end
	if db.handleBubbles then
		ApplyCVars(db)
	elseif wasOn then
		RestoreCVars()
	end
	wasOn = db.handleBubbles and true or false
	StyleBubbles()
end

watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
for _, event in ipairs(BUBBLE_EVENTS) do
	pcall(watcher.RegisterEvent, watcher, event) -- (not every client has every event)
end
watcher:SetScript("OnEvent", ns.Profiled("chat bubbles event", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		ns.ApplyBubbles()
	-- (Also while any bubble is still styled from before: the game hides
	-- bubbles and reuses them, and those only come back as they show again.)
	elseif ns.db and (ns.db.handleBubbles and (ns.db.bubblesTextOnly or ns.db.bubblesTextScale ~= 1)
		or next(hidden) or next(scaled) or next(outlined)) then
		watchLeft = WATCH_FOR
		self:SetScript("OnUpdate", OnUpdate)
	end
end))
