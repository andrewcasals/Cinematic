-- Cinematic: chat bubbles. Where the game shows them (say and yell, party; by
-- place, as the page's grid says), and how they look (text only, text size).
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
-- out for text only, and its text scaled. Bubbles are reused, so each is
-- looked at again as it shows. Bubbles the game keeps from addons (in
-- instances, on retail) are left as they are.
local hidden = setmetatable({}, { __mode = "k" }) -- texture -> true, while faded out
local scaled = setmetatable({}, { __mode = "k" }) -- font string -> true, while scaled

local function Style(textOnly, scale, ...)
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
		elseif kind == "FontString" and region.SetTextScale then
			if scale ~= 1 or scaled[region] then
				region:SetTextScale(scale)
				scaled[region] = scale ~= 1 or nil
			end
		end
	end
end

local function StyleFrame(frame, textOnly, scale)
	Style(textOnly, scale, frame:GetRegions())
	for i = 1, select("#", frame:GetChildren()) do
		local child = select(i, frame:GetChildren())
		if not (child.IsForbidden and child:IsForbidden()) then
			StyleFrame(child, textOnly, scale)
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
	local scale = on and tonumber(db.bubblesTextScale) or 1
	if not on and not next(hidden) and not next(scaled) then
		return
	end
	for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
		if not (bubble.IsForbidden and bubble:IsForbidden()) then
			StyleFrame(bubble, textOnly, scale)
		end
	end
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
		or next(hidden) or next(scaled)) then
		watchLeft = WATCH_FOR
		self:SetScript("OnUpdate", OnUpdate)
	end
end))
