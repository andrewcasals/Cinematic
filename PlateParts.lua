-- Cinematic: the Nameplates page's Plate Parts grid. In CineMode each part of
-- the game's nameplates (health bar, name, cast bar, auras...) shows as its
-- row says, fading like the plates themselves. Outside CineMode, or with the
-- page's master switch off, the parts are left to the game.
local _, ns = ...

-- Each part's frame on a plate's unit frame: the first of these it has, or
-- (all) every one of them, for parts drawn by several textures. The
-- containers (health and cast bars with their borders) go first. WoW
-- Forever's level is the PlayerLevelDiffFrame box (its LevelFrame stays hidden).
-- A dotted field is one on a frame on the unit frame.
local PART_FRAMES = {
	Health = { "HealthBarsContainer", "healthBar" },
	Name = { "name" },
	CastBar = { "CastBarsContainer", "castBar", "CastBar" },
	Auras = { "AurasFrame", "BuffFrame" },
	RaidMarker = { "RaidTargetFrame" },
	Classification = { "ClassificationFrame", "classificationIndicator", all = true },
	Level = { "PlayerLevelDiffFrame", "LevelFrame", "levelText" },
	Threat = { "aggroHighlight", "aggroHighlightBase", "aggroHighlightAdditive", "aggroFlash", all = true },
	-- (Forever's is the health bar's gold border, on your target.)
	Highlight = { "selectionHighlight", "healthBar.selectedBorder", all = true },
	Widgets = { "WidgetContainer" },
}

-- How far each part shows, 0 to 1, faded at the UI's fade speeds.
local levels = {}

local function Usable(frame)
	return type(frame) == "table" and frame.SetAlpha and not (frame.IsForbidden and frame:IsForbidden())
end

local function Field(unitFrame, field)
	local value = unitFrame
	for name in field:gmatch("[^.]+") do
		if type(value) ~= "table" then
			return nil
		end
		value = value[name]
	end
	return value
end

-- Calls fn(frame, ...) for each of a part's frames on a unit frame.
local function EachPartFrame(unitFrame, part, fn, ...)
	local fields = PART_FRAMES[part]
	for _, field in ipairs(fields) do
		local frame = Field(unitFrame, field)
		if Usable(frame) then
			fn(frame, ...)
			if not fields.all then
				return
			end
		end
	end
end

-- The game sets some of these parts' alpha itself (the cast bar fades out
-- after a cast), so while a part is faded its alpha is put back to ours every
-- frame, as with the plates. [part frame] = alpha.
local held = {}
local keeper = CreateFrame("Frame")
keeper:Hide()
keeper:SetScript("OnUpdate", ns.Profiled("Plate parts keeper", function(self)
	for frame, wanted in pairs(held) do
		-- (A secret alpha can't be compared: set ours again.)
		local alpha = frame:GetAlpha()
		if (issecretvalue and issecretvalue(alpha)) or alpha ~= wanted then
			frame:SetAlpha(wanted)
		end
	end
	if not next(held) then
		self:Hide()
	end
end))

-- WoW Forever's personal resource bars are a plate too: theirs are left alone.
local function PersonalPlate()
	return C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("player")
end

local function Fade(frame, alpha)
	if alpha < 1 then
		held[frame] = alpha
		frame:SetAlpha(alpha)
	elseif held[frame] then
		held[frame] = nil -- (let go: back to full, then the game's again)
		frame:SetAlpha(1)
	end
end

local function ApplyPlate(plate, personal)
	local unitFrame = plate and plate.UnitFrame
	if not Usable(unitFrame) or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	for _, part in ipairs(ns.PLATE_PARTS) do
		EachPartFrame(unitFrame, part, Fade, plate ~= personal and levels[part] or 1)
	end
	if next(held) then
		keeper:Show()
	end
end

local function ApplyAll()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	local personal = PersonalPlate()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		ApplyPlate(plate, personal)
	end
end
ApplyAll = ns.Profiled("Plate parts", ApplyAll)

-- Whether any part is faded (or still held from being faded).
local function AnyFaded()
	for _, part in ipairs(ns.PLATE_PARTS) do
		if (levels[part] or 1) < 1 then
			return true
		end
	end
	return next(held) ~= nil
end

-- A plate given a new unit takes the parts' alphas (or lets go of its last unit's).
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
watcher:SetScript("OnEvent", function(_, _, unit)
	if ns.db and AnyFaded() and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
		ApplyPlate(C_NamePlate.GetNamePlateForUnit(unit), PersonalPlate())
	end
end)

-- Each tick, from ns.UpdatePlates: active while the Nameplates page steers
-- plates (CineMode, its master switch on).
function ns.UpdatePlateParts(active, elapsed)
	local changed = false
	for _, part in ipairs(ns.PLATE_PARTS) do
		local target = (not active or ns.PlateRowWanted("Part" .. part)) and 1 or 0
		local level = levels[part]
		if level == nil then
			levels[part] = target -- logging in: no fade
			changed = changed or target < 1
		elseif level ~= target then
			levels[part] = ns.Approach(level, target, elapsed, target > level and ns.FadeInTime() or ns.FadeOutTime())
			changed = true
		end
	end
	if changed then
		ApplyAll()
	end
end

-- For /cine debug plates: which of each part's frames the plate has, then
-- every frame and text on it, for finding parts a client names otherwise.
-- One frame or texture for the debug listing: its type, whether it's shown,
-- a text's words and a texture's colour. (Not everything can say:
-- animations, say. Anything that errors is listed bare.)
local function Entry(name, value)
	local okType, kind = pcall(value.GetObjectType, value)
	local okShown, shown = pcall(function() return value:IsShown() end)
	local okText, text = pcall(function() return kind == "FontString" and value:GetText() or nil end)
	if okText and issecretvalue and issecretvalue(text) then
		text = "(secret)"
	end
	local okColor, color = pcall(function()
		if kind ~= "Texture" then
			return nil
		end
		local r, g, b = value:GetVertexColor()
		return ("%.2f/%.2f/%.2f"):format(r, g, b)
	end)
	return name .. ":" .. (okType and tostring(kind) or "?")
		.. ((okShown and not ns.Flag(shown)) and "(hidden)" or "")
		.. ((okText and text) and (' "' .. text .. '"') or "")
		.. ((okColor and color) and (" " .. color) or "")
end

-- Every frame and texture on a frame: by its field, then its textures and
-- texts that have none (numbered).
local function ListFields(frame)
	local children, named = {}, {}
	for field, value in pairs(frame) do
		if type(field) == "string" and type(value) == "table" and value.GetObjectType then
			named[value] = true
			children[#children + 1] = Entry(field, value)
		end
	end
	table.sort(children)
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	for i, region in ipairs(ok and regions or {}) do
		if not named[region] then
			children[#children + 1] = Entry("#" .. i, region)
		end
	end
	return table.concat(children, ", ")
end

function ns.DescribePlateParts(unitFrame)
	local found = {}
	for _, part in ipairs(ns.PLATE_PARTS) do
		local fields = PART_FRAMES[part]
		local names = {}
		for _, field in ipairs(fields) do
			local frame = Field(unitFrame, field)
			if Usable(frame) then
				-- (With its alpha now, and @ ours while held.)
				local ok, alpha = pcall(function() return ("%.2f"):format(frame:GetAlpha()) end)
				local wanted = held[frame]
				names[#names + 1] = field .. " " .. (ok and alpha or "?")
					.. (wanted and ("@" .. ("%.2f"):format(wanted)) or "")
				if not fields.all then
					break
				end
			end
		end
		found[#found + 1] = part .. "=" .. (#names > 0 and table.concat(names, "+") or "NONE")
	end
	-- The health bar's container, the bar, and any frame on the bar (its border).
	local healthFields = {}
	local container, bar = unitFrame.HealthBarsContainer, unitFrame.healthBar
	if type(container) == "table" and container.GetObjectType then
		healthFields[#healthFields + 1] = "container: " .. ListFields(container)
	end
	if type(bar) == "table" and bar.GetObjectType then
		healthFields[#healthFields + 1] = "healthBar: " .. ListFields(bar)
		for field, value in pairs(bar) do
			if type(field) == "string" and type(value) == "table" and value.GetRegions then
				healthFields[#healthFields + 1] = "healthBar." .. field .. ": " .. ListFields(value)
			end
		end
	end
	healthFields = #healthFields > 0 and table.concat(healthFields, " | ") or "NONE"
	return table.concat(found, ", "), ListFields(unitFrame), healthFields
end
