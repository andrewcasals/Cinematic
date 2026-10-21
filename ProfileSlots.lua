-- Profile slots: the parts a built-in profile is made of. Each slot owns a
-- set of settings, so a part (a slot's template) changes only its own, and
-- a profile is one part per slot.
--
-- Which slot a setting is in comes from the options page it's on (Options.lua
-- records each page's settings for its Reset page), with KEY_SLOTS for the
-- ones that aren't on their page's slot or on any page. The Standard Frames
-- columns are shared: their action bar rows (BAR_ROWS) are the Action bars
-- slot's, the rest the UI manager's. /cine debug slots lists settings with no
-- slot, or on pages of different slots.

local _, ns = ...

-- This client, as parts and profiles name it.
ns.CLIENT = ns.isRetail and "retail" or "forever"

-- In the order a profile's parts are put together.
ns.PROFILE_SLOTS = {
	{ key = "layout", name = "Edit Mode layout" },
	{ key = "frames", name = "UI manager" },
	{ key = "bars", name = "Action bars" },
	{ key = "camera", name = "Camera" },
	{ key = "vfx", name = "Visual effects" },
	{ key = "misc", name = "Chat & misc" },
}

-- Each options page's slot, by its English name (pages not here hold no
-- profile settings: Profiles, Keybinds' own, Graphics+, What's new...).
local PAGE_SLOTS = {
	-- (the main page: on/off where and when, and fading the UI)
	["Cinematic"] = "frames",
	["CineMode"] = "frames",
	["Standard Frames"] = "frames",
	["Advanced Frames"] = "frames",
	["Nameplates"] = "frames",
	["Unit Frames"] = "frames",
	["Minimap"] = "frames",
	["Quest tracker"] = "frames",
	["Swing timer"] = "frames",
	["Tooltips"] = "frames",
	["Buffs/debuffs"] = "frames",
	["Gamepad"] = "frames",
	["Vision"] = "frames",
	["Mouseover groups"] = "bars",
	["Cooldown Manager"] = "bars",
	["Camera Modes"] = "camera",
	["Camera Triggers"] = "camera",
	["Camera Settings"] = "camera",
	["Effects"] = "vfx",
	["Tint"] = "vfx",
	["Audio"] = "misc",
	["Chat"] = "misc",
	["Chat bubbles"] = "misc",
	["General"] = "misc",
	["Fishing"] = "misc",
	["Hunter"] = "misc",
	["Keybinds"] = "misc",
}

-- The Standard Frames columns' rows that are the Action bars slot's.
local BAR_ROWS = {
	cooldowns = true, mainbar = true, art = true, bottomleft = true, bottomright = true, right1 = true,
	right2 = true, bar6 = true, bar7 = true, bar8 = true, pet = true, stance = true, totems = true,
	micro = true, bags = true, xp = true, extra = true, gamepadbars = true, gamepadxp = true,
	-- (other addons' bars: Bartender4's, and EllesmereUI's action bars,
	-- cooldowns, essential cooldowns and XP/reputation bars)
	["addon:bt4Bars"] = true, ["addon:euiBars"] = true, ["addon:euiCooldowns"] = true,
	["addon:euiEssentials"] = true, ["addon:euiDataBars"] = true,
}

-- A list's row that's the Action bars slot's (in a UI manager list).
function ns.IsBarRow(row)
	return BAR_ROWS[row] == true
end

-- Settings whose slot isn't their page's, or that are on no page.
local KEY_SLOTS = {
	editModeLayout = "layout",
	cooldownManagerOn = "bars",
	-- (on no page)
	addonFrames = "frames", -- (Advanced Frames' added frames)
	targetShow = "frames",
	alwaysShowWaypoint = "frames",
	buffHoverPadX = "frames",
	buffHoverPadY = "frames",
	chatPeekChannelList = "misc",
	chatPeekChannels = "misc",
	talentCalcTalented = "misc",
}

-- Settings on no page (a page shows only this client's, class's or camera
-- style's), by the start of their name: the first that matches.
local KEY_PATTERNS = {
	{ "^%l+Orbit", "camera" },        -- (each camera's orbit: idleOrbitMode, walkOrbitSpeed...)
	{ "^idleOpening", "camera" },
	{ "^indoor", "camera" },          -- (cameras indoors)
	{ "^teleZoom", "camera" },
	{ "^cozyTent", "camera" },
	{ "^deathSong", "camera" },
	{ "^plate", "frames" },
	{ "^unitPart", "frames" },
	{ "^swingRangedOnTop", "frames" }, -- (one per class)
	{ "^tintCustom", "vfx" },
}

-- The map, made once the options pages are: keys[key] = slot, and for a
-- shared list rows[key][row] = slot. Also what /cine debug slots reports.
local map
local function BuildMap()
	local L = ns.L
	local byName = {}
	for english, slot in pairs(PAGE_SLOTS) do
		byName[english] = slot
		byName[L[english]] = slot -- (some pages are registered under their shown name)
	end
	local keys, rows, clashes, unknownPages = {}, {}, {}, {}
	local function Claim(key, slot, page)
		if keys[key] and keys[key] ~= slot then
			clashes[key] = clashes[key] or { keys[key] }
			table.insert(clashes[key], slot .. " (" .. page .. ")")
		else
			keys[key] = slot
		end
	end
	for page, settings in pairs(ns.PageSettings and ns.PageSettings() or {}) do
		local slot = byName[page]
		if not slot then
			-- (only pages with profile settings: not Profiles, Graphics+, What's new...)
			for key in pairs(settings.keys) do
				if ns.IsProfileKey(key) and ns.DEFAULTS[key] ~= nil then unknownPages[page] = true end
			end
		end
		if slot then
			for key in pairs(settings.keys) do
				if not settings.rows[key] then Claim(key, KEY_SLOTS[key] or slot, page) end
			end
			for key, list in pairs(settings.rows) do
				rows[key] = rows[key] or {}
				for row in pairs(list) do
					rows[key][row] = (slot == "frames" and BAR_ROWS[row]) and "bars" or slot
				end
				-- (the list as a whole: its page's slot, for rows no page shows)
				Claim(key, KEY_SLOTS[key] or slot, page)
			end
		end
	end
	for key, slot in pairs(KEY_SLOTS) do keys[key] = slot end
	for key in pairs(ns.DEFAULTS) do
		if not keys[key] then
			for _, pattern in ipairs(KEY_PATTERNS) do
				if key:find(pattern[1]) then
					keys[key] = pattern[2]
					break
				end
			end
		end
	end
	map ={ keys = keys, rows = rows, clashes = clashes, unknownPages = unknownPages }
	return map
end

-- The slot a setting (or a row of a shared list) is in; nil: none.
function ns.SettingSlot(key, row)
	map = map or BuildMap()
	if row ~= nil then
		local slot = map.rows[key] and map.rows[key][row]
		if slot then return slot end
		if map.keys[key] == "frames" and BAR_ROWS[row] then return "bars" end
	end
	return map.keys[key]
end

-- /cine debug slots: how many settings each slot has, and (in the log) the
-- profile settings with no slot, settings on pages of different slots,
-- pages that aren't given one, parts setting another slot's, and built-ins'
-- parts that aren't there. all: also how each shared list is split.
function ns.SlotsDebug(all)
	map = BuildMap()
	local function Sorted(set)
		local list = {}
		for k in pairs(set) do list[#list + 1] = k end
		table.sort(list)
		return list
	end
	local profileKeys = {}
	for key in pairs(ns.DEFAULTS) do
		if ns.IsProfileKey(key) then profileKeys[key] = true end
	end
	for _, key in ipairs(ns.PROFILE_TABLES) do profileKeys[key] = true end
	local counts, missing = {}, {}
	for key in pairs(profileKeys) do
		local slot = map.keys[key]
		if slot then
			counts[slot] = (counts[slot] or 0) + 1
		else
			missing[key] = true
		end
	end
	for _, slot in ipairs(ns.PROFILE_SLOTS) do
		ns.Log("slots", ("%s: %d settings"):format(slot.name, counts[slot.key] or 0))
	end
	for key, list in pairs(all and map.rows or {}) do
		local bySlot = {}
		for row, slot in pairs(list) do
			bySlot[slot] = bySlot[slot] or {}
			table.insert(bySlot[slot], row)
		end
		if next(bySlot, next(bySlot)) then
			for slot, rowList in pairs(bySlot) do
				table.sort(rowList)
				ns.Log("slots", ("split list %s: %s rows: %s"):format(key, slot, table.concat(rowList, ", ")))
			end
		end
	end
	local missingList = Sorted(missing)
	for _, key in ipairs(missingList) do ns.Log("slots", "no slot: " .. key) end
	local clashList = Sorted(map.clashes)
	for _, key in ipairs(clashList) do
		ns.Log("slots", ("clash: %s in %s"):format(key, table.concat(map.clashes[key], ", ")))
	end
	local pageList = Sorted(map.unknownPages)
	for _, page in ipairs(pageList) do ns.Log("slots", "page with no slot: " .. page) end
	-- Each part changing only its own slot's settings (and its own rows of a list).
	local strays = 0
	local said = {}
	for _, slot in ipairs(ns.PROFILE_SLOTS) do
		for name, part in pairs(ns.PROFILE_PARTS[slot.key] or {}) do
			for _, client in ipairs({ "forever", "retail" }) do
				part.apply(function(key, value)
					local wrong = {}
					if type(value) == "table" then
						for row in pairs(value) do
							local rowSlot = ns.SettingSlot(key, row)
							if rowSlot ~= slot.key then wrong[#wrong + 1] = ("%s.%s (%s)"):format(key, tostring(row), tostring(rowSlot)) end
						end
					elseif ns.SettingSlot(key) ~= slot.key then
						wrong[1] = ("%s (%s)"):format(key, tostring(ns.SettingSlot(key)))
					end
					for _, text in ipairs(wrong) do
						local line = ("part %s.%s sets another slot's: %s"):format(slot.key, name, text)
						if not said[line] then
							said[line] = true
							strays = strays + 1
							ns.Log("slots", line)
						end
					end
				end, client)
			end
		end
	end
	-- Each built-in's parts there on each client it's on, and no two of a
	-- client's built-ins with the same name or label.
	local recipes = 0
	for _, client in ipairs({ "forever", "retail" }) do
		local seen = {}
		for _, profile in ipairs(ns.ALL_BUILTIN_PROFILES) do
			if not profile.client or profile.client == client then
				for _, shown in ipairs({ profile.name, profile.label ~= profile.name and profile.label or nil }) do
					if seen[shown:lower()] then
						recipes = recipes + 1
						ns.Log("slots", ("%s: two profiles called %s"):format(client, shown))
					end
					seen[shown:lower()] = true
				end
				for _, slot in ipairs(ns.PROFILE_SLOTS) do
					local part, name = ns.ProfilePart(profile.parts, slot.key, client)
					local problem
					if not part and name ~= "standard" then
						problem = "no such part"
					elseif part and part.client and part.client ~= client then
						problem = "that part is " .. part.client .. "'s only"
					elseif part and part.editMode and part.editMode ~= ns.LAYOUT_PRESET
						and not ns.EDIT_MODE_LAYOUTS[part.editMode] then
						problem = "layout " .. part.editMode .. " isn't one of Cinematic's (Layouts.lua)"
					end
					if problem then
						recipes = recipes + 1
						ns.Log("slots", ("%s on %s: %s.%s: %s"):format(profile.name, client, slot.key, name, problem))
					end
				end
			end
		end
	end
	ns.Print(("slots: %d settings with no slot, %d on pages of different slots, %d pages with no slot,"
		.. " %d settings parts set in another slot, %d problems with built-in profiles' parts (details in"
		.. " /cine log)"):format(#missingList, #clashList, #pageList, strays, recipes))
end
