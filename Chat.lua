-- Cinematic: chat. Which new messages briefly show the chat window (by message
-- type and by channel), and typing detection.
local _, ns = ...

function ns.IsChatActive()
	return ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() ~= nil
end

-- Chat messages that briefly reveal the chat window they land in (only that
-- window: not its tabs, the input bar or the rest of the UI).
-- Message types the player can switch on or off individually (db.chatPeekTypes,
-- missing = the type's default, on unless it says otherwise). Numbered channels
-- are chosen one by one instead (db.chatPeekChannelList by channel name,
-- missing = db.chatPeekChannels). "game" types are game events rather than
-- conversation; the noisy ones default off.
ns.CHAT_PEEK_TYPES = {
	{ key = "say", label = "Say", events = { "CHAT_MSG_SAY" } },
	{ key = "yell", label = "Yell", events = { "CHAT_MSG_YELL" } },
	{ key = "emote", label = "Emotes", events = { "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" } },
	{ key = "whisper", label = "Whispers", events = { "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" } },
	{ key = "party", label = "Party", events = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" } },
	{ key = "raid", label = "Raid", events = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" } },
	{ key = "raidwarning", label = "Raid warnings", events = { "CHAT_MSG_RAID_WARNING" } },
	{ key = "instance", label = "Instance",
		events = { "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" } },
	{ key = "guild", label = "Guild", events = { "CHAT_MSG_GUILD" } },
	{ key = "officer", label = "Officer", events = { "CHAT_MSG_OFFICER" } },
	{ key = "npc", label = "NPC speech", events = {
		"CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_WHISPER",
		"CHAT_MSG_MONSTER_EMOTE" } },
	{ key = "boss", label = "Boss emotes",
		events = { "CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_RAID_BOSS_WHISPER" } },

	-- Server announcements ("[SERVER] Shutdown in 9:00"); see the AddMessage hook below.
	{ key = "server", label = "Server messages (shutdowns, restarts)", section = "game", events = {} },
	-- Level ups arrive as a system message; see LEVEL_UP_WINDOW below.
	{ key = "levelup", label = "Level ups", section = "game", events = {} },
	{ key = "skill", label = "Skill ups", section = "game", events = { "CHAT_MSG_SKILL" } },
	{ key = "achievement", label = "Achievements", section = "game",
		events = { "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT" } },
	{ key = "xp", label = "Experience", section = "game", default = false,
		events = { "CHAT_MSG_COMBAT_XP_GAIN" } },
	{ key = "reputation", label = "Reputation", section = "game", default = false,
		events = { "CHAT_MSG_COMBAT_FACTION_CHANGE" } },
	{ key = "honor", label = "Honor", section = "game", default = false,
		events = { "CHAT_MSG_COMBAT_HONOR_GAIN" } },
	{ key = "loot", label = "Loot", section = "game", events = { "CHAT_MSG_LOOT" } },
	{ key = "money", label = "Money", section = "game", events = { "CHAT_MSG_MONEY" } },
	{ key = "tradeskill", label = "Other players' crafting", section = "game", default = false,
		events = { "CHAT_MSG_TRADESKILLS" } },
	{ key = "system", label = "All other system messages", section = "game", default = false,
		events = { "CHAT_MSG_SYSTEM" } },
}
local PEEK_TYPE_DEFAULT = {}
for _, peekType in ipairs(ns.CHAT_PEEK_TYPES) do
	PEEK_TYPE_DEFAULT[peekType.key] = peekType.default ~= false
end

local function IsPeekTypeOn(key)
	local on = ns.db.chatPeekTypes[key]
	if on == nil then
		return PEEK_TYPE_DEFAULT[key]
	end
	return on
end

-- The level-up line is a plain system message among many, and matching its
-- text would break in other languages. So a system message arriving within
-- LEVEL_UP_WINDOW seconds of PLAYER_LEVEL_UP counts as the level-up line.
ns.LEVEL_UP_WINDOW = 2
ns.levelUpUntil = 0
local EVENT_PEEK_TYPE = {}
local CHAT_PEEK_EVENTS = { "CHAT_MSG_CHANNEL" }
for _, peekType in ipairs(ns.CHAT_PEEK_TYPES) do
	for _, event in ipairs(peekType.events) do
		EVENT_PEEK_TYPE[event] = peekType.key
		CHAT_PEEK_EVENTS[#CHAT_PEEK_EVENTS + 1] = event
	end
end

function ns.IsChannelPeekOn(name)
	local on = ns.db.chatPeekChannelList[name]
	if on == nil then
		return ns.db.chatPeekChannels
	end
	return on
end

-- Channels the player has joined, by name (e.g. "General", "Trade"). Depending
-- on the client GetChannelList returns id, name pairs or id, name, disabled
-- triples, so walk it by type.
function ns.GetJoinedChannels()
	local list, values = {}, { GetChannelList() }
	local i = 1
	while i <= #values do
		if type(values[i]) == "number" and type(values[i + 1]) == "string" then
			list[#list + 1] = values[i + 1]
			i = i + ((type(values[i + 2]) == "boolean") and 3 or 2)
		else
			i = i + 1
		end
	end
	return list
end

-- "1. General - Elwynn Forest" -> "General", for clients that don't pass the
-- channel's base name with the message.
local function ChannelBaseName(baseName, channelString)
	if baseName and baseName ~= "" then
		return baseName
	end
	return (channelString or ""):gsub("^%d+%.%s*", ""):gsub("%s+%-%s+.*$", "")
end
ns.chatPeekUntil = {} -- [chat frame] = GetTime() when it may fade again
ns.chatTypingUntil = 0 -- typing shows the whole chat group without leaving cinematic

-- Message filters run once per chat window that will show the message, which
-- tells us exactly which window to reveal. Never filters anything out.
local function ChatPeekFilter(chatFrame, event, _, _, _, channelString, _, _, _, _, channelBaseName)
	if not ns.db.chatPeek then
		return false
	end
	local wanted
	if event == "CHAT_MSG_CHANNEL" then
		wanted = ns.IsChannelPeekOn(ChannelBaseName(channelBaseName, channelString))
	elseif event == "CHAT_MSG_SYSTEM" and GetTime() < ns.levelUpUntil and IsPeekTypeOn("levelup") then
		wanted = true
	else
		wanted = IsPeekTypeOn(EVENT_PEEK_TYPE[event])
	end
	if wanted then
		ns.chatPeekUntil[chatFrame] = GetTime() + ns.HoldTime("chatPeekTime")
	end
	return false
end

-- Server announcements don't arrive as a chat event addons can filter, so
-- watch what each chat window adds for lines starting with the game's own
-- (localised) "[SERVER]" prefix.
local function OnChatLineAdded(chatFrame, text)
	if not ns.db.chatPeek or not IsPeekTypeOn("server") then
		return
	end
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return
	end
	local prefix = SERVER_MESSAGE_PREFIX or "[SERVER]"
	if text:find(prefix, 1, true) then
		ns.chatPeekUntil[chatFrame] = GetTime() + ns.HoldTime("chatPeekTime")
	end
end

local function HookServerMessages()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local chatFrame = _G["ChatFrame" .. i]
		if chatFrame and chatFrame.AddMessage then
			hooksecurefunc(chatFrame, "AddMessage", OnChatLineAdded)
		end
	end
end

function ns.RegisterChatPeek()
	local addFilter = ChatFrame_AddMessageEventFilter
		or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
	if not addFilter then
		return
	end
	for _, event in ipairs(CHAT_PEEK_EVENTS) do
		addFilter(event, ChatPeekFilter)
	end
	HookServerMessages()
end
