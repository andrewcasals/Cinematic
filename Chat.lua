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
	{ key = "achievement", label = "Achievements", section = "game", default = false,
		events = { "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT" } },
	{ key = "xp", label = "Experience", section = "game", default = false,
		events = { "CHAT_MSG_COMBAT_XP_GAIN" } },
	{ key = "reputation", label = "Reputation", section = "game", default = false,
		events = { "CHAT_MSG_COMBAT_FACTION_CHANGE" } },
	{ key = "honor", label = "Honor", section = "game", default = false,
		events = { "CHAT_MSG_COMBAT_HONOR_GAIN" } },
	-- Group loot rolls arrive as loot messages; see IsLootRollLine below.
	{ key = "rolls", label = "Loot rolls (need, greed, won)", section = "game", events = {} },
	{ key = "loot", label = "All loot", section = "game", default = false, events = { "CHAT_MSG_LOOT" } },
	{ key = "money", label = "Money", section = "game", default = false, events = { "CHAT_MSG_MONEY" } },
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

-- Roll lines are told apart from other loot lines by the game's own
-- (localised) format strings, turned into patterns. Missing ones (not on this
-- client) are skipped.
local LOOT_ROLL_FORMATS = {
	"LOOT_ROLL_NEED", "LOOT_ROLL_NEED_SELF", "LOOT_ROLL_GREED", "LOOT_ROLL_GREED_SELF",
	"LOOT_ROLL_DISENCHANT", "LOOT_ROLL_DISENCHANT_SELF", "LOOT_ROLL_TRANSMOG", "LOOT_ROLL_TRANSMOG_SELF",
	"LOOT_ROLL_PASSED", "LOOT_ROLL_PASSED_SELF", "LOOT_ROLL_PASSED_AUTO", "LOOT_ROLL_PASSED_AUTO_FEMALE",
	"LOOT_ROLL_PASSED_SELF_AUTO", "LOOT_ROLL_ALL_PASSED",
	"LOOT_ROLL_ROLLED_NEED", "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "LOOT_ROLL_ROLLED_GREED",
	"LOOT_ROLL_ROLLED_DE", "LOOT_ROLL_ROLLED_TRANSMOG", "LOOT_ROLL_WON", "LOOT_ROLL_YOU_WON",
}
local lootRollPatterns

local function FormatToPattern(format)
	-- Mark the %s / %d / %1$s slots, escape the rest, then fill the slots in.
	local pattern = format:gsub("%%%d*%$?([sd])", "\1%1")
	pattern = pattern:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
	pattern = pattern:gsub("\1s", ".+"):gsub("\1d", "%%d+")
	return "^" .. pattern .. "$"
end

local function IsLootRollLine(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return false
	end
	if not lootRollPatterns then
		lootRollPatterns = {}
		for _, name in ipairs(LOOT_ROLL_FORMATS) do
			local format = _G[name]
			if type(format) == "string" and format:find("%", 1, true) then
				lootRollPatterns[#lootRollPatterns + 1] = FormatToPattern(format)
			end
		end
	end
	for _, pattern in ipairs(lootRollPatterns) do
		if text:find(pattern) then
			return true
		end
	end
	return false
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

-- "1. General - Elwynn Forest" -> "General", to match GetChannelList's names.
-- Some clients don't pass the channel's base name with the message, and some
-- (Classic) pass it with the zone still attached, so trim either.
local function ChannelBaseName(baseName, channelString)
	local name = (baseName and baseName ~= "") and baseName or channelString or ""
	name = name:gsub("^%d+%.%s*", ""):gsub("%s+%-%s+.*$", "")
	return name
end
ns.chatPeekUntil = {} -- [chat frame] = GetTime() when it may fade again
ns.chatTypingUntil = 0 -- typing shows the whole chat group without leaving cinematic

-- Message filters run once per chat window that will show the message, which
-- tells us exactly which window to reveal. Never filters anything out.
local function ChatPeekFilter(chatFrame, event, text, _, _, channelString, _, _, _, _, channelBaseName)
	if not ns.db.chatPeek then
		return false
	end
	local wanted
	if event == "CHAT_MSG_CHANNEL" then
		wanted = ns.IsChannelPeekOn(ChannelBaseName(channelBaseName, channelString))
	elseif event == "CHAT_MSG_SYSTEM" and GetTime() < ns.levelUpUntil and IsPeekTypeOn("levelup") then
		wanted = true
	elseif event == "CHAT_MSG_LOOT" and IsPeekTypeOn("rolls") and IsLootRollLine(text) then
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
-- look at the newest lines in each chat window for ones starting with the
-- game's own (localised) "[SERVER]" prefix. Checked a few times a second
-- rather than by hooking AddMessage: hooking a game frame's methods breaks
-- the game's own calls to them ("attempt to call a nil value").
local SERVER_CHECK_INTERVAL = 0.25
local LINES_CHECKED = 10 -- newest lines looked at each check, at most
local serverWatch = {} -- [chat frame] = { newest = newest line already looked at, server = last [SERVER] line peeked for }

local function Readable(text)
	return type(text) == "string" and not (issecretvalue and issecretvalue(text))
end

local function CheckServerLines(chatFrame, watch, peekOn)
	local count = chatFrame:GetNumMessages()
	local newest
	for i = count, math.max(1, count - LINES_CHECKED + 1), -1 do
		local text = chatFrame:GetMessageInfo(i)
		if Readable(text) then
			if text == watch.newest then
				break
			end
			newest = newest or text
			local prefix = SERVER_MESSAGE_PREFIX or "[SERVER]"
			if peekOn and watch.newest ~= nil and text ~= watch.server and text:find(prefix, 1, true) then
				watch.server = text
				ns.chatPeekUntil[chatFrame] = GetTime() + ns.HoldTime("chatPeekTime")
			end
		end
	end
	-- (The first check only notes where chat is up to: no peeking at old lines.)
	watch.newest = newest or watch.newest or false
end

local function WatchServerMessages()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local chatFrame = _G["ChatFrame" .. i]
		if chatFrame and chatFrame.GetNumMessages and chatFrame.GetMessageInfo then
			serverWatch[chatFrame] = {}
		end
	end
	if not next(serverWatch) then
		return
	end
	local watcher = CreateFrame("Frame")
	local sinceCheck = 0
	watcher:SetScript("OnUpdate", function(_, elapsed)
		sinceCheck = sinceCheck + elapsed
		if sinceCheck < SERVER_CHECK_INTERVAL then
			return
		end
		sinceCheck = 0
		local peekOn = ns.db.chatPeek and IsPeekTypeOn("server")
		for chatFrame, watch in pairs(serverWatch) do
			CheckServerLines(chatFrame, watch, peekOn)
		end
	end)
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
	WatchServerMessages()
end
