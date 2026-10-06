-- Cinematic tracking detection: keeps the minimap up while gathering or
-- creature tracking is active (see the minimapFor* settings).
local _, ns = ...

-- Gathering and creature tracking. There's no API for what appears on the
-- minimap, but the active tracking spell can be found, so the minimap can stay
-- up while it's on. Matched by spell ID (language-independent), through the
-- player's auras and the client's tracking list, plus the active tracking icon
-- on clients that only expose that.
local TRACKING = {
	{ option = "minimapForHerbs", spells = { 2383 },
		icons = { 136065, "interface\\icons\\inv_misc_flower_02" } },
	{ option = "minimapForMinerals", spells = { 2580 },
		icons = { 136025, "interface\\icons\\spell_nature_earthquake" } },
	{ option = "minimapForTreasure", spells = { 2481 },
		icons = { 135725, "interface\\icons\\racial_dwarf_findtreasure" } },
	{ option = "minimapForFish", spells = { 43308 }, icons = {} },
	{ option = "minimapForCreatures", icons = {}, spells = {
		1494, 19878, 19879, 19880, 19882, 19883, 19884, 19885, -- hunter tracking
		5225,                                                -- druid: Track Humanoids
		5500, 5502,                                          -- Sense Demons, Sense Undead
	} },
}
local TRACKING_CHECK_INTERVAL = 0.5
local trackingCheckedAt, keepMinimapForTracking = 0, false

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

-- Spell IDs of tracking that's active right now, as a set.
local function GetActiveTrackingSpells()
	local active = {}
	-- Auras (tracking spells show as buffs)
	for i = 1, 40 do
		local name, spellID
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			-- Errors (rather than returning nil) while auras are secret.
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
			if not ok or IsSecret(aura) or not aura then break end
			name, spellID = aura.name, aura.spellId
		elseif UnitBuff then
			local values = { UnitBuff("player", i) }
			name, spellID = values[1], values[10]
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

local function GetActiveTrackingIcon()
	local icon = GetTrackingTexture and GetTrackingTexture()
	if type(icon) == "string" then
		return icon:lower()
	end
	return icon
end

local function IsTrackingSomethingWanted()
	local db = ns.GetDB()
	local active = GetActiveTrackingSpells()
	local icon = GetActiveTrackingIcon()
	for _, kind in ipairs(TRACKING) do
		if db[kind.option] then
			for _, spellID in ipairs(kind.spells) do
				if active[spellID] then return true end
			end
			for _, trackingIcon in ipairs(kind.icons) do
				if icon and icon == trackingIcon then return true end
			end
		end
	end
	return false
end

-- Called from Core.lua's frame update: whether to keep the minimap up for
-- tracking. Auras are secret in combat, so the last answer is kept until it's
-- over.
function ns.IsKeepingMinimapForTracking(now)
	if now - trackingCheckedAt >= TRACKING_CHECK_INTERVAL and not InCombatLockdown()
		and not ns.Flag(UnitAffectingCombat("player")) then
		trackingCheckedAt = now
		keepMinimapForTracking = IsTrackingSomethingWanted()
	end
	return keepMinimapForTracking
end

ns.GetActiveTrackingSpells = GetActiveTrackingSpells
ns.GetActiveTrackingIcon = GetActiveTrackingIcon
ns.IsTrackingSomethingWanted = IsTrackingSomethingWanted
