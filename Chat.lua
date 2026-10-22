-- Cinematic: chat. Which new messages briefly show the chat window (by message
-- type and by channel), and typing detection.
local _, ns = ...
local L = ns.L

function ns.IsChatActive()
	return ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() ~= nil
end

-- Chat messages that briefly reveal the chat window they land in (only that
-- window and its tabs: not the input bar or the rest of the UI).
-- Message types the player can switch on or off individually (db.chatPeekTypes,
-- missing = the type's default, on unless it says otherwise). Numbered channels
-- are chosen one by one instead (db.chatPeekChannelList by channel name,
-- missing = db.chatPeekChannels). "game" types are game events rather than
-- conversation; the noisy ones default off.
ns.CHAT_PEEK_TYPES = {
	{ key = "say", label = L["Say"], events = { "CHAT_MSG_SAY" } },
	{ key = "yell", label = L["Yell"], events = { "CHAT_MSG_YELL" } },
	{ key = "emote", label = L["Emotes"], events = { "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" } },
	{ key = "whisper", label = L["Whispers"], events = { "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" } },
	{ key = "party", label = L["Party"], events = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" } },
	{ key = "raid", label = L["Raid"], events = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" } },
	{ key = "raidwarning", label = L["Raid warnings"], events = { "CHAT_MSG_RAID_WARNING" } },
	{ key = "instance", label = L["Instance"],
		events = { "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" } },
	{ key = "guild", label = L["Guild"], events = { "CHAT_MSG_GUILD" } },
	{ key = "officer", label = L["Officer"], events = { "CHAT_MSG_OFFICER" } },
	{ key = "npc", label = L["NPC speech"], events = {
		"CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_WHISPER",
		"CHAT_MSG_MONSTER_EMOTE" } },
	{ key = "boss", label = L["Boss emotes"],
		events = { "CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_RAID_BOSS_WHISPER" } },

	-- Guild members' comings and goings arrive as system messages; see IsGuildLine below.
	{ key = "guildmembers", label = L["Guild members (online, offline, joins, leaves)"], section = "game",
		events = {} },
	-- Group members' comings and goings likewise; see IsGroupLine below.
	{ key = "groupmembers", label = L["Group members (joins, leaves)"], section = "game", events = {} },
	-- Server announcements ("[SERVER] Shutdown in 9:00"); see the AddMessage hook below.
	{ key = "server", label = L["Server messages (shutdowns, restarts)"], section = "game", events = {} },
	-- Level ups arrive as a system message; see LEVEL_UP_WINDOW below.
	{ key = "levelup", label = L["Level ups"], section = "game", events = {} },
	-- /who replies (shift-clicking a name in the guild list, too); see WHO_WINDOW below.
	{ key = "who", label = L["/who results (shift-clicking a name)"], section = "game", events = {} },
	{ key = "skill", label = L["Skill ups"], section = "game", events = { "CHAT_MSG_SKILL" } },
	{ key = "achievement", label = L["Achievements"], section = "game", default = false,
		events = { "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT" } },
	{ key = "xp", label = L["Experience"], section = "game", default = false,
		events = { "CHAT_MSG_COMBAT_XP_GAIN" } },
	{ key = "reputation", label = L["Reputation"], section = "game", default = false,
		events = { "CHAT_MSG_COMBAT_FACTION_CHANGE" } },
	{ key = "honor", label = L["Honor"], section = "game", default = false,
		events = { "CHAT_MSG_COMBAT_HONOR_GAIN" } },
	{ key = "battleground", label = L["Battleground objectives (assaults, captures, flags)"], section = "game",
		events = { "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_BG_SYSTEM_NEUTRAL" } },
	-- Group loot rolls arrive as loot messages; see IsLootRollLine below.
	{ key = "rolls", label = L["Loot rolls (need, greed, won)"], section = "game", events = {} },
	{ key = "loot", label = L["All loot"], section = "game", default = false, events = { "CHAT_MSG_LOOT" } },
	{ key = "money", label = L["Money"], section = "game", default = false, events = { "CHAT_MSG_MONEY" } },
	{ key = "tradeskill", label = L["Other players' crafting"], section = "game", default = false,
		events = { "CHAT_MSG_TRADESKILLS" } },
	{ key = "system", label = L["All other system messages"], section = "game", default = false,
		events = { "CHAT_MSG_SYSTEM" } },
}
ns.OnLanguage(function() ns.TranslateFields(ns.CHAT_PEEK_TYPES, "label") end)
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
-- /who replies are system messages too, so likewise: ones arriving within
-- WHO_WINDOW seconds of a /who being sent (typed, or by shift-clicking a name).
local WHO_WINDOW = 3
local whoUntil = 0
local function WhoSent()
	whoUntil = GetTime() + WHO_WINDOW
end
if C_FriendList and C_FriendList.SendWho then
	hooksecurefunc(C_FriendList, "SendWho", WhoSent)
end
if _G.SendWho then
	hooksecurefunc("SendWho", WhoSent)
end
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

-- With the loot roll window on (RollWindow.lua), roll lines stay out of chat
-- (rollWindowChat): the window shows them.
local function IsHiddenRollLine(text)
	return ns.hasRollWindow and ns.Setting("rollWindow") and ns.Setting("rollWindowChat") and IsLootRollLine(text)
end

local function RollLineFilter(_, _, text)
	return IsHiddenRollLine(text) and true or false
end

-- Guild members coming online, going offline, joining, leaving, removed,
-- promoted or demoted: told apart from other system messages the same way.
-- Coming online and going offline use the same lines as friends', so a name
-- on your friends list only counts if it's in the guild roster too (the
-- roster may leave out offline members, so a name not on it isn't enough).
local GUILD_FORMATS = {
	"ERR_FRIEND_ONLINE_SS", "ERR_FRIEND_OFFLINE_S", "ERR_GUILD_JOIN_S", "ERR_GUILD_LEAVE_S",
	"ERR_GUILD_REMOVE_SS", "ERR_GUILD_PROMOTE_SSS", "ERR_GUILD_DEMOTE_SSS", "ERR_GUILD_LEADER_CHANGED_SS",
}
local FRIEND_LINES = { ERR_FRIEND_ONLINE_SS = true, ERR_FRIEND_OFFLINE_S = true }
local guildPatterns

-- "Name-Realm" (or a link's "Name:12") -> "Name".
local function ShortName(name)
	return name:match("^[^%-:]+") or name
end

local function IsFriend(name)
	if not (C_FriendList and C_FriendList.GetFriendInfo) then
		return false
	end
	local ok, info = pcall(C_FriendList.GetFriendInfo, name)
	return ok and info ~= nil
end

local function InGuildRoster(name)
	local ok, total = pcall(GetNumGuildMembers)
	if not ok or type(total) ~= "number" then
		return false
	end
	for i = 1, total do
		local member = GetGuildRosterInfo(i)
		if type(member) == "string" and ShortName(member) == name then
			return true
		end
	end
	return false
end

local function IsGuildLine(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or not IsInGuild() then
		return false
	end
	if not guildPatterns then
		guildPatterns = {}
		for _, name in ipairs(GUILD_FORMATS) do
			local format = _G[name]
			if type(format) == "string" and format:find("%", 1, true) then
				guildPatterns[#guildPatterns + 1] = { pattern = FormatToPattern(format, true), friendLine = FRIEND_LINES[name] }
			end
		end
	end
	for _, line in ipairs(guildPatterns) do
		local name = text:match(line.pattern)
		if name then
			if not line.friendLine then
				return true
			end
			name = ShortName(name)
			return not IsFriend(name) or InGuildRoster(name)
		end
	end
	return false
end

-- Party, raid and instance group members joining and leaving, and you
-- joining, leaving or being removed, the group disbanding or becoming a
-- raid: system messages, told apart by the game's own (localised) lines.
-- (Ones a client doesn't have are skipped.)
local GROUP_FORMATS = {
	"ERR_JOINED_GROUP_S", "ERR_LEFT_GROUP_S", "ERR_RAID_MEMBER_ADDED_S", "ERR_RAID_MEMBER_REMOVED_S",
	"ERR_INSTANCE_GROUP_ADDED_S", "ERR_INSTANCE_GROUP_REMOVED_S", "ERR_LEFT_GROUP_YOU", "ERR_UNINVITE_YOU",
	"ERR_RAID_YOU_JOINED", "ERR_RAID_YOU_LEFT", "ERR_GROUP_DISBANDED", "ERR_PARTY_CONVERTED_TO_RAID",
}
local groupPatterns

local function IsGroupLine(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return false
	end
	if not groupPatterns then
		groupPatterns = {}
		for _, name in ipairs(GROUP_FORMATS) do
			local format = _G[name]
			if type(format) == "string" and format ~= "" then
				groupPatterns[#groupPatterns + 1] = FormatToPattern(format)
			end
		end
	end
	for _, pattern in ipairs(groupPatterns) do
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

-- Only a window you'd see peeks: a docked tab that isn't the selected one is
-- hidden, and peeking it would bring up just the dock's tabs.
local function PeekWindow(chatFrame)
	if ns.Flag(chatFrame:IsShown()) then
		ns.chatPeekUntil[chatFrame] = GetTime() + ns.HoldTime("chatPeekTime")
	end
end

-- Shows a chat window for at least seconds, whatever the Chat page's peek
-- settings (our own lines worth reading: the update notice).
function ns.PeekChat(chatFrame, seconds)
	if chatFrame and ns.Flag(chatFrame:IsShown()) then
		local untilTime = GetTime() + math.max(seconds, ns.HoldTime("chatPeekTime"))
		ns.chatPeekUntil[chatFrame] = math.max(ns.chatPeekUntil[chatFrame] or 0, untilTime)
	end
end

-- A chat window scrolled up to read older lines stays up, and fades after the
-- peek time once it's back at the bottom.
function ns.HoldScrolledChat(now)
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local chatFrame = _G["ChatFrame" .. i]
		if chatFrame and chatFrame.AtBottom and ns.Flag(chatFrame:IsShown()) then
			-- (Only a plain false: a secret answer mustn't keep chat up for good.)
			local atBottom = chatFrame:AtBottom()
			if not (issecretvalue and issecretvalue(atBottom)) and atBottom == false then
				ns.chatPeekUntil[chatFrame] = now + ns.HoldTime("chatPeekTime")
			end
		end
	end
end

-- With "Hide your messages" (db.chatHideOwn), your own lines don't peek: your
-- emotes ("You bow.", the campfire button's sit or kneel), says, party lines...
-- You know you did them. Told by the sender's GUID, or by name where a client
-- doesn't pass one.

local function IsFromPlayer(author, guid)
	if type(guid) == "string" and guid ~= "" and not (issecretvalue and issecretvalue(guid)) then
		return guid == UnitGUID("player")
	end
	if type(author) ~= "string" or (issecretvalue and issecretvalue(author)) then
		return false
	end
	local name = UnitName("player")
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	return author == name or (realm ~= nil and author == name .. "-" .. realm)
end

-- With "Hide speech you can see as a bubble" (db.chatHideBubbled), speech you
-- can see as a bubble on screen (a yell from someone in view) doesn't need the
-- chat window: such a line waits BUBBLE_WAIT seconds for its
-- bubble (it shows a frame or so after the message), and peeks only if none
-- with its text showed on screen. Bubbles switched off, or kept from addons
-- (in instances, on retail), peek as before.
local BUBBLE_SPEECH = {
	CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_MONSTER_SAY = true, CHAT_MSG_MONSTER_YELL = true,
}
local BUBBLE_WAIT = 0.3
local waiting = {} -- { chatFrame, text, until }
local bubbleWatch = CreateFrame("Frame")

local function WatchBubbles()
	local now = GetTime()
	for i = #waiting, 1, -1 do
		local line = waiting[i]
		if ns.IsBubbleOnScreen and ns.IsBubbleOnScreen(line[2]) then
			table.remove(waiting, i)
		elseif now >= line[3] then
			table.remove(waiting, i)
			PeekWindow(line[1])
		end
	end
	if #waiting == 0 then
		bubbleWatch:SetScript("OnUpdate", nil)
	end
end
local OnBubbleWatch = ns.Profiled("Bubble watch", WatchBubbles)

local function PeekUnlessBubble(chatFrame, event, text)
	if not (ns.db.chatHideBubbled and BUBBLE_SPEECH[event] and type(text) == "string" and not (issecretvalue and issecretvalue(text))
			and GetCVarBool and GetCVarBool("chatBubbles")) then
		PeekWindow(chatFrame)
		return
	end
	waiting[#waiting + 1] = { chatFrame, text, GetTime() + BUBBLE_WAIT }
	bubbleWatch:SetScript("OnUpdate", OnBubbleWatch)
end

-- Message filters run once per chat window that will show the message, which
-- tells us exactly which window to reveal. Never filters anything out.
local function ChatPeekFilter(chatFrame, event, text, author, _, channelString, _, _, _, _, channelBaseName,
		_, _, guid)
	if not ns.db.chatPeek then
		return false
	end
	local wanted
	if event == "CHAT_MSG_LOOT" and IsHiddenRollLine(text) then
		wanted = false -- (left out of chat: nothing to see)
	elseif ns.db.chatHideOwn and IsFromPlayer(author, guid) then
		wanted = false
	elseif event == "CHAT_MSG_CHANNEL" then
		wanted = ns.IsChannelPeekOn(ChannelBaseName(channelBaseName, channelString))
	elseif event == "CHAT_MSG_SYSTEM" and GetTime() < ns.levelUpUntil and IsPeekTypeOn("levelup") then
		wanted = true
	elseif event == "CHAT_MSG_SYSTEM" and GetTime() < whoUntil and IsPeekTypeOn("who") then
		wanted = true
	elseif event == "CHAT_MSG_LOOT" and IsPeekTypeOn("rolls") and IsLootRollLine(text) then
		wanted = true
	elseif event == "CHAT_MSG_SYSTEM" and IsPeekTypeOn("guildmembers") and IsGuildLine(text) then
		wanted = true
	elseif event == "CHAT_MSG_SYSTEM" and IsPeekTypeOn("groupmembers") and IsGroupLine(text) then
		wanted = true
	else
		wanted = IsPeekTypeOn(EVENT_PEEK_TYPE[event])
	end
	if wanted then
		PeekUnlessBubble(chatFrame, event, text)
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
				PeekWindow(chatFrame)
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
	watcher:SetScript("OnUpdate", ns.Profiled("Server message watch", function(_, elapsed)
		sinceCheck = sinceCheck + elapsed
		if sinceCheck < SERVER_CHECK_INTERVAL then
			return
		end
		sinceCheck = 0
		local peekOn = ns.db.chatPeek and IsPeekTypeOn("server")
		for chatFrame, watch in pairs(serverWatch) do
			CheckServerLines(chatFrame, watch, peekOn)
		end
	end))
end

-- Whisper tabs (the ones the game opens for each conversation) with a whisper
-- you haven't read: the game flashes such a tab until you click it, so its
-- flash starting and stopping says when. (The tab's own "alerting" field
-- isn't set on every client.) [chat frame] = true.
local unreadWhispers = {}

local function IsWhisperTab(chatFrame)
	return chatFrame ~= nil and chatFrame.isTemporary
		and (chatFrame.chatType == "WHISPER" or chatFrame.chatType == "BN_WHISPER")
end

if FCF_StartAlertFlash and FCF_StopAlertFlash then
	hooksecurefunc("FCF_StartAlertFlash", function(chatFrame)
		if IsWhisperTab(chatFrame) then
			unreadWhispers[chatFrame] = true
		end
	end)
	-- (Also called for any tab you click, flashing or not.)
	hooksecurefunc("FCF_StopAlertFlash", function(chatFrame)
		unreadWhispers[chatFrame] = nil
	end)
end

-- Whether a whisper tab is waiting to be read. Closed tabs drop out.
function ns.HasUnreadWhisper()
	for chatFrame in pairs(unreadWhispers) do
		local tab = _G[chatFrame:GetName() .. "Tab"]
		if IsWhisperTab(chatFrame) and tab and ns.Flag(tab:IsShown()) then
			return true
		end
		unreadWhispers[chatFrame] = nil
	end
	return false
end

-- LocalDefense warnings ("Dun Algaz is under attack!") also show as a title
-- where the zone name appears (db.chatAttackAlert). The channel is told by its
-- zone channel number, which every language shares, or else its English name;
-- the game sends these with no sender, so players' lines there are skipped.
-- The same place repeats at most once every ATTACK_REPEAT seconds.
do
	local LOCAL_DEFENSE_ID = 22
	local ATTACK_REPEAT = 90
	local shownAt = {} -- [text] = GetTime() it last showed

	local function OnChannelMessage(_, _, text, _, _, channelString, _, _, zoneChannelID, _, channelBaseName,
			_, _, guid)
		if not (ns.db and ns.db.chatAttackAlert and ns.db.handleChat ~= false) or not Readable(text) then
			return
		end
		if guid ~= nil and not (Readable(guid) and guid == "") then
			return -- (a player, not the game)
		end
		if not (type(zoneChannelID) == "number" and not (issecretvalue and issecretvalue(zoneChannelID))
				and zoneChannelID == LOCAL_DEFENSE_ID)
			and ChannelBaseName(Readable(channelBaseName) and channelBaseName or nil,
				Readable(channelString) and channelString or nil) ~= "LocalDefense" then
			return
		end
		local now = GetTime()
		if shownAt[text] and now - shownAt[text] < ATTACK_REPEAT then
			return
		end
		shownAt[text] = now
		ns.ShowAlertTitle(text)
	end

	local frame = CreateFrame("Frame")
	frame:RegisterEvent("CHAT_MSG_CHANNEL")
	frame:SetScript("OnEvent", ns.Profiled("Attack alert", OnChannelMessage))
end

function ns.RegisterChatPeek()
	local addFilter = ChatFrame_AddMessageEventFilter
		or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
	if not addFilter then
		return
	end
	for _, event in ipairs(CHAT_PEEK_EVENTS) do
		addFilter(event, ns.Profiled("Chat filter", ChatPeekFilter))
	end
	-- (after the peek filter: it sees every line first)
	addFilter("CHAT_MSG_LOOT", RollLineFilter)
	WatchServerMessages()
end
