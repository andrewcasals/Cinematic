-- Cinematic tracking detection: keeps the minimap up while gathering or
-- creature tracking is active (Keep open, Minimap page: minimapKeepGathering,
-- minimapKeepCreatures).
local _, ns = ...

-- Gathering and creature tracking. There's no API for what appears on the
-- minimap, but the active tracking spell can be found, so the minimap can stay
-- up while it's on. Matched by spell ID (language-independent), through the
-- player's auras and the client's tracking list, plus the active tracking icon
-- on clients that only expose that.
local TRACKING = {
	{ option = "minimapKeepGathering", spells = { 2383 }, -- Find Herbs
		icons = { 136065, "interface\\icons\\inv_misc_flower_02" } },
	{ option = "minimapKeepGathering", spells = { 2580 }, -- Find Minerals
		icons = { 136025, "interface\\icons\\spell_nature_earthquake" } },
	{ option = "minimapKeepGathering", spells = { 2481 }, -- Find Treasure
		icons = { 135725, "interface\\icons\\racial_dwarf_findtreasure" } },
	{ option = "minimapKeepCreatures", spells = { 43308 }, icons = {} }, -- Find Fish
	{ option = "minimapKeepCreatures", icons = {}, spells = {
		1494, 19878, 19879, 19880, 19882, 19883, 19884, 19885, -- hunter tracking
		5225,                                                -- druid: Track Humanoids
		5500, 5502,                                          -- Sense Demons, Sense Undead
	} },
}
local TRACKING_CHECK_INTERVAL = 0.5
local trackingCheckedAt, keepForGathering, keepForCreatures = 0, false, false

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

-- Spell IDs of tracking that's active right now, as a set (into active).
local function FillActiveTrackingSpells(active)
	-- Auras (tracking spells show as buffs)
	for i = 1, 40 do
		local name, spellID
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			-- Errors (rather than returning nil) while auras are secret.
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
			if not ok or IsSecret(aura) or not aura then break end
			name, spellID = aura.name, aura.spellId
		elseif UnitBuff then
			local _
			name, _, _, _, _, _, _, _, _, spellID = UnitBuff("player", i)
		end
		if IsSecret(name) or not name then break end
		if not IsSecret(spellID) and spellID then active[spellID] = true end
	end
	-- The client's tracking list
	if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
		for i = 1, C_Minimap.GetNumTrackingTypes() do
			local info = C_Minimap.GetTrackingInfo(i)
			if type(info) == "table" and info.active and info.spellID then
				active[info.spellID] = true
			end
		end
	end
	return active
end

local function GetActiveTrackingSpells()
	return FillActiveTrackingSpells({})
end

local function GetActiveTrackingIcon()
	local icon = GetTrackingTexture and GetTrackingTexture()
	if type(icon) == "string" then
		return icon:lower()
	end
	return icon
end

-- The active tracking, read afresh only once the player's auras or tracking
-- have changed: reading every aura (a table each) twice a second was most of
-- the addon's garbage in cities.
local activeSpells, activeIcon, trackingChanged = {}, nil, true
local changeWatcher = CreateFrame("Frame")
if not pcall(changeWatcher.RegisterUnitEvent, changeWatcher, "UNIT_AURA", "player") then
	changeWatcher:RegisterEvent("UNIT_AURA")
end
for _, event in ipairs({ "MINIMAP_UPDATE_TRACKING", "PLAYER_ENTERING_WORLD" }) do
	pcall(changeWatcher.RegisterEvent, changeWatcher, event)
end
changeWatcher:SetScript("OnEvent", function(_, event, unit)
	if event ~= "UNIT_AURA" or unit == "player" then
		trackingChanged = true
	end
end)

-- Whether tracking that's ticked under Keep open is on: gathering (herbs,
-- minerals, treasure), and creatures or fish.
local function IsTrackingSomethingWanted()
	local db = ns.GetDB()
	if trackingChanged then
		trackingChanged = false
		FillActiveTrackingSpells(wipe(activeSpells))
		activeIcon = GetActiveTrackingIcon()
	end
	local active, icon = activeSpells, activeIcon
	local gathering, creatures = false, false
	for _, kind in ipairs(TRACKING) do
		if db[kind.option] then
			local on = false
			for _, spellID in ipairs(kind.spells) do
				if active[spellID] then on = true end
			end
			for _, trackingIcon in ipairs(kind.icons) do
				if icon and icon == trackingIcon then on = true end
			end
			if on and kind.option == "minimapKeepGathering" then
				gathering = true
			elseif on then
				creatures = true
			end
		end
	end
	return gathering, creatures
end

-- Called from Frames.lua's frame update: whether to keep the minimap up for
-- gathering tracking, and for creature or fish tracking. Auras are secret in
-- combat, so the last answer is kept until it's over.
function ns.IsKeepingMinimapForTracking(now)
	if now - trackingCheckedAt >= TRACKING_CHECK_INTERVAL and not InCombatLockdown()
		and not ns.Flag(UnitAffectingCombat("player")) then
		trackingCheckedAt = now
		keepForGathering, keepForCreatures = IsTrackingSomethingWanted()
	end
	return keepForGathering, keepForCreatures
end

ns.GetActiveTrackingSpells = GetActiveTrackingSpells
ns.GetActiveTrackingIcon = GetActiveTrackingIcon
ns.IsTrackingSomethingWanted = IsTrackingSomethingWanted
