-- Cinematic: support for other addons. Each one's file (Support/) adds its rows
-- for the 3rd Party Frames page (plain data: the page lists them installed or
-- not) and any setup code, which only runs once that addon has loaded. So an
-- addon that isn't loaded costs nothing beyond its rows.
local ADDON_NAME, ns = ...

-- Other addons' frames faded out of the box, listed on the 3rd Party Frames page.
-- Each fades as its own group ("addon:<key>") while its addon is loaded and
-- it isn't switched off (db.addonFrames[key] = false). names: its named
-- frames. about: what they are, for the options page (note: more to say there).
-- patterns: name patterns for top-level frames numbered per window.
-- match(frame): whether an unnamed frame on UIParent is one of its
-- own, for addons that don't name their frames (those can't be added with
-- /cine add, which saves frames by name). short: a shorter label, if needed.
-- suite: listed once, under this name, among the addons not installed.
-- hookAlpha: its frames set their own alpha all the time, so follow it at once
-- (see HookOwnAlpha in Frames.lua). loaded: set once its addon has loaded.
ns.ADDON_FRAMES = {}

local setups = {} -- addon name -> setup functions still to run
local started = false -- (Cinematic itself loaded: the setups can run)

function ns.WhenAddonLoads(addon, setup)
	setups[addon] = setups[addon] or {}
	table.insert(setups[addon], setup)
end

local function IsLoaded(addon)
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	return isLoaded and isLoaded(addon) and true or false
end

local function OnLoaded(addon)
	for _, known in ipairs(ns.ADDON_FRAMES) do
		if known.addon == addon then
			known.loaded = true
		end
	end
	local list = setups[addon]
	setups[addon] = nil
	for _, setup in ipairs(list or {}) do
		local ok, err = pcall(setup)
		if not ok then
			ns.Log("error", ("support for %s: %s"):format(addon, tostring(err)))
		end
	end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, _, addon)
	if addon == ADDON_NAME then
		-- Addons loaded before this one, now that all of its files are in.
		started = true
		local loaded = {}
		for _, known in ipairs(ns.ADDON_FRAMES) do
			loaded[known.addon] = true
		end
		for name in pairs(setups) do
			loaded[name] = true
		end
		for name in pairs(loaded) do
			if IsLoaded(name) then
				OnLoaded(name)
			end
		end
	elseif started then
		OnLoaded(addon)
	end
end)
