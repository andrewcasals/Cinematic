-- Cinematic: which units count for a quest objective you haven't finished
-- (a mob to kill, an NPC to talk to). For the Vision page's Quest Vision: their
-- plates kept up (see Effects), a quest icon on them (see PlateParts) and on the target frame.
-- Read from the unit's tooltip lines without showing the tooltip
-- (C_TooltipInfo.GetUnit): a quest objective line ("5/7 Thistle Boar slain")
-- not yet done. Where the lines can't be read, C_QuestLog.UnitIsRelatedToActiveQuest
-- (which can't tell a finished objective). Unreadable (secret) counts as no.
local _, ns = ...

-- Answers by GUID: true/false and when they were read. A yes holds until the
-- quest log changes; a no is read again after a while (a unit's tooltip lines
-- can be missing for a moment after its plate appears).
local answers = {} -- [guid] = { quest = bool, at = time }
local RECHECK_NO = 2

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

-- Whether an objective line's text says it's done: "7/7" or "100%".
local function TextDone(text)
	if type(text) ~= "string" or not Known(text) then
		return nil
	end
	local have, need = text:match("(%d+)%s*/%s*(%d+)")
	if have then
		return tonumber(have) >= tonumber(need)
	end
	local percent = text:match("(%d+)%%")
	if percent then
		return tonumber(percent) >= 100
	end
	return nil
end

-- true / false from the tooltip lines, or nil when they can't say.
local function FromTooltip(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return nil
	end
	local objective = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
	local ok, found = pcall(function()
		local data = C_TooltipInfo.GetUnit(unit)
		local lines = data and data.lines
		if type(lines) ~= "table" then
			return nil
		end
		for _, line in ipairs(lines) do
			local text = line.leftText
			if objective and line.type == objective then
				local done = line.completed
				if done == nil then
					done = TextDone(text)
				end
				if not done then
					return true
				end
			elseif type(text) == "string" and Known(text) and text:find("^%s*%-%s*%d+%s*/%s*%d+") then
				-- (Clients without line kinds: " - 5/7 Thistle Boar slain".)
				if not TextDone(text) then
					return true
				end
			end
		end
		return false
	end)
	if ok then
		return found
	end
	return nil
end

local function Read(unit)
	local ok, isPlayer = pcall(UnitIsPlayer, unit)
	if not ok or not Known(isPlayer) or isPlayer then
		return false
	end
	local found = FromTooltip(unit)
	if found ~= nil then
		return found
	end
	local related = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
	if related then
		local okRelated, yes = pcall(related, unit)
		return okRelated and Known(yes) and yes and true or false
	end
	return false
end

-- Whether a unit counts for a quest objective you haven't finished.
function ns.IsQuestMob(unit)
	if not unit then
		return false
	end
	-- (Asked every time, not kept: a mob killed with others in the fight
	-- doesn't always change the quest log, and its yes would keep its plate up.)
	local okDead, dead = pcall(UnitIsDead, unit)
	if okDead and Known(dead) and dead then
		return false
	end
	local ok, guid = pcall(UnitGUID, unit)
	if not (ok and type(guid) == "string" and Known(guid)) then
		return Read(unit)
	end
	local now = GetTime()
	local answer = answers[guid]
	if answer and (answer.quest or now - answer.at < RECHECK_NO) then
		return answer.quest
	end
	answer = answer or {}
	answer.quest, answer.at = Read(unit), now
	answers[guid] = answer
	return answer.quest
end

-- The quest log changed (progress made, a quest taken or handed in): every
-- answer is read again.
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
	"QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function()
	wipe(answers)
end)

-- The golden exclamation mark shown for them (plates' Quest Icon row, and the
-- target frame's, below).
ns.QUEST_MOB_TEXTURE = "Interface\\GossipFrame\\AvailableQuestIcon"

-- The target frame's quest icon (targetQuestIcon, Vision page's Quest Vision): the
-- same mark left of the target frame's health bar while your target is a
-- quest mob. Part of the frame, so it fades with it. Looked at again as the
-- target or the quest log changes, and now and then (progress can land a
-- moment after the event).
local targetIcon
local function TargetIcon()
	local frame = _G.TargetFrame
	if targetIcon or not (frame and frame.CreateTexture) then
		return targetIcon
	end
	local bar = frame.healthbar or frame.HealthBar or frame
	targetIcon = CreateFrame("Frame", nil, frame)
	targetIcon:SetSize(24, 24)
	if bar == frame then
		targetIcon:SetPoint("RIGHT", frame, "LEFT", 4, 0)
	else
		targetIcon:SetPoint("RIGHT", bar, "LEFT", -4, 0)
	end
	targetIcon:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 5)
	local texture = targetIcon:CreateTexture(nil, "OVERLAY")
	texture:SetAllPoints()
	texture:SetTexture(ns.QUEST_MOB_TEXTURE)
	return targetIcon
end

function ns.RefreshTargetQuestIcon()
	local db = ns.db
	local on = db and ns.QuestVisionSetting("targetQuestIcon")
	local ok, exists = pcall(UnitExists, "target")
	local show = on and ok and Known(exists) and exists and ns.IsQuestMob("target")
	if show then
		local icon = TargetIcon()
		if icon then
			icon:Show()
		end
	elseif targetIcon then
		targetIcon:Hide()
	end
end

local TARGET_EVERY = 0.5
local targetWatcher = CreateFrame("Frame")
targetWatcher.at = 0
targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
targetWatcher:SetScript("OnEvent", ns.RefreshTargetQuestIcon)
targetWatcher:SetScript("OnUpdate", function(self)
	local now = GetTime()
	if now >= self.at then
		self.at = now + TARGET_EVERY
		if (ns.db and ns.db.targetQuestIcon) or (targetIcon and targetIcon:IsShown()) then
			ns.RefreshTargetQuestIcon()
		end
	end
end)

-- For /cine debug plates: what the target's quest lines say.
function ns.DescribeQuestMob(unit)
	return ("quest mob=%s (tooltip=%s)"):format(tostring(ns.IsQuestMob(unit)), tostring(FromTooltip(unit)))
end
