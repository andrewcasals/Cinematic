-- Cinematic: players' guilds under their names on plates showing their name
-- alone (CineMode, away from dungeons and raids). There the name sits on the
-- plate in place of the one over the unit's head, which the game takes away
-- with its guild line: this puts that line back, as far as the Names grid's
-- Guild Names row keeps guilds up (ns.plateGuildLevel, from Effects) and the
-- name shows. Drawn like the name above it: its font, colour, shadow and size.
local _, ns = ...

local lines = {} -- [plate] = guild text
local shares = {} -- [plate] = how far its name shows on a name-only plate (0 to 1)

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

local function Hide(plate)
	if lines[plate] then
		lines[plate]:Hide()
	end
end

local function Refresh(plate)
	local share = (shares[plate] or 0) * (ns.plateGuildLevel or 0)
	local unitFrame = plate.UnitFrame
	local name = Usable(unitFrame) and unitFrame.name
	if share <= 0 or not Usable(name) or not name.GetFont then
		Hide(plate)
		return
	end
	local text = GuildText(plate.namePlateUnitToken or unitFrame.unit)
	if not text then
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
watcher:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
watcher:RegisterEvent("UNIT_NAME_UPDATE")
watcher:SetScript("OnEvent", function(_, event, unit)
	if not (type(unit) == "string" and unit:find("^nameplate") and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		return
	end
	if event == "NAME_PLATE_UNIT_REMOVED" then
		shares[plate] = nil
		Hide(plate)
	elseif shares[plate] then
		Refresh(plate)
	end
end)
