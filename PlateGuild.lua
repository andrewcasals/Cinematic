-- Cinematic: players' guilds and NPCs' titles under their names on plates
-- showing their name alone (CineMode, away from dungeons and raids). There
-- the name sits on the plate in place of the one over the unit's head, which
-- the game takes away with its second line: this puts that line back. A
-- guild as far as the Names grid's Guild Names row keeps guilds up
-- (ns.plateGuildLevel, from Effects) and the name shows; an NPC's title
-- (<Innkeeper>) wherever its name shows, as over heads. Drawn like the name
-- above it: its font, colour, shadow and size.
local _, ns = ...

local lines = {} -- [plate] = guild text
local shares = {} -- [plate] = how far its name shows on a name-only plate (0 to 1)
-- [plate] = its NPC's title, or false for none; nil not read yet (or the
-- game wouldn't say: read again in a while, or after the fight).
local titles = {}
local titleTried = {} -- [plate] = when its title was last asked for and not given
local TITLE_RETRY = 2 -- seconds

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function Usable(frame)
	return type(frame) == "table" and frame.SetAlpha and not (frame.IsForbidden and frame:IsForbidden())
end

-- The unit's guild as the game writes it under names, or nil.
local function GuildText(unit)
	local ok, guild = pcall(GetGuildInfo, unit)
	if not ok or type(guild) ~= "string" then
		return nil
	end
	if issecretvalue and issecretvalue(guild) then
		return nil
	end
	return guild ~= "" and ("<" .. guild .. ">") or nil
end

-- Whether a unit is a player (by its GUID: on WoW Forever UnitIsPlayer can
-- say no for players after a buff).
local function IsPlayer(unit)
	local ok, guid = pcall(UnitGUID, unit)
	if ok and Known(guid) and type(guid) == "string" then
		return guid:find("^Player%-") ~= nil
	end
	local okPlayer, player = pcall(UnitIsPlayer, unit)
	return okPlayer and Known(player) and player and true or false
end

-- An NPC's title as the game writes it under its name (<Innkeeper>): the
-- second line of its tooltip, unless that's its level line ("Level 30
-- Humanoid": no title). false for none, nil when the game won't say (no
-- tooltip data, a secret line). Pets, totems and other units players control
-- have none (their second line is their owner's).
local function NPCTitle(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return false
	end
	local okControlled, controlled = pcall(UnitPlayerControlled, unit)
	if okControlled and Known(controlled) and controlled then
		return false
	end
	local ok, title = pcall(function()
		local data = C_TooltipInfo.GetUnit(unit)
		local line = data and type(data.lines) == "table" and data.lines[2]
		if not line then
			return false
		end
		local text = line.leftText
		if not Known(text) then
			return nil
		end
		if type(text) ~= "string" or text == "" or (LEVEL and text:find(LEVEL, 1, true)) then
			return false
		end
		return "<" .. text .. ">"
	end)
	if ok then
		return title
	end
	return nil
end

-- The line under a plate's name: its player's guild or its NPC's title, and
-- whether it's a guild (with the Guild Names row, then).
local function LineText(plate, unit)
	if IsPlayer(unit) then
		return GuildText(unit), true
	end
	if titles[plate] == nil and GetTime() - (titleTried[plate] or -TITLE_RETRY) >= TITLE_RETRY then
		titles[plate] = NPCTitle(unit)
		titleTried[plate] = titles[plate] == nil and GetTime() or nil
	end
	return titles[plate] or nil, false
end

local function Hide(plate)
	if lines[plate] then
		lines[plate]:Hide()
	end
end

local function Refresh(plate)
	local share = shares[plate] or 0
	local unitFrame = plate.UnitFrame
	-- (Under our own text for the name where it's drawn: PlateParts.)
	local name = Usable(unitFrame) and (ns.PlateNameText and ns.PlateNameText(plate) or unitFrame.name)
	local unit = plate.namePlateUnitToken or (Usable(unitFrame) and unitFrame.unit)
	if share <= 0 or not unit or not Usable(name) or not name.GetFont then
		Hide(plate)
		return
	end
	local text, guild = LineText(plate, unit)
	if guild then
		share = share * (ns.plateGuildLevel or 0)
	end
	if not text or share <= 0 then
		Hide(plate)
		return
	end
	local line = lines[plate]
	if not line then
		line = unitFrame:CreateFontString(nil, "OVERLAY")
		lines[plate] = line
	end
	-- (Its parent can change with the plate's unit frame: anchored anew each time.)
	line:ClearAllPoints()
	line:SetPoint("TOP", name, "BOTTOM", 0, -1)
	-- (Its font object, not its file: a file has one alphabet, and a guild in
	-- another, Cyrillic say, would show as boxes. The name's is a family.)
	local object = name.GetFontObject and name:GetFontObject()
	if object then
		line:SetFontObject(object)
	else
		local file, size, flags = name:GetFont()
		if file then
			pcall(line.SetFont, line, file, size, flags)
		end
	end
	pcall(function()
		line:SetShadowOffset(name:GetShadowOffset())
		line:SetShadowColor(name:GetShadowColor())
		local r, g, b = name:GetTextColor()
		line:SetTextColor(r, g, b)
		if line.SetVertexColor then line:SetVertexColor(r, g, b) end
		if name.GetScale then line:SetScale(name:GetScale()) end
	end)
	line:SetText(text)
	line:SetAlpha(share)
	line:Show()
end

-- From PlateParts, each time it lays out a plate: how far its name shows
-- while the plate shows its name alone (0: not name-only).
function ns.SetPlateGuild(plate, share)
	shares[plate] = share > 0 and share or nil
	if shares[plate] or lines[plate] then
		Refresh(plate)
	end
end

-- From Effects, as the Guild Names row fades guilds up or down.
function ns.RefreshPlateGuilds()
	for plate in pairs(shares) do
		Refresh(plate)
	end
end

-- A plate let go of hides its line; a guild read late (or changed) shows.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
watcher:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
watcher:RegisterEvent("UNIT_NAME_UPDATE")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event, unit)
	-- (After a fight: titles the game wouldn't give in it, asked for again.)
	if event == "PLAYER_REGEN_ENABLED" then
		wipe(titleTried)
		for plate in pairs(shares) do
			Refresh(plate)
		end
		return
	end
	if not (type(unit) == "string" and unit:find("^nameplate") and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		return
	end
	-- (A plate given a new unit, or let go of: its title read afresh.)
	if event ~= "UNIT_NAME_UPDATE" then
		titles[plate], titleTried[plate] = nil, nil
	end
	if event == "NAME_PLATE_UNIT_REMOVED" then
		shares[plate] = nil
		Hide(plate)
	elseif shares[plate] then
		Refresh(plate)
	end
end)
