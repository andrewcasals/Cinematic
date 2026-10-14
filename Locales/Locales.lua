-- Translations. The code shows text through ns.L["English text"]; the
-- language picked on the main settings page (or the game's own) fills in what
-- it has, and anything it doesn't have stays in English. Loaded before
-- everything else.
--
-- The choice is a saved setting, and saved settings only arrive once every
-- file has run (ADDON_LOADED). Until then L gives English; text built while
-- the files run (tables of labels, mostly) is translated again then, by the
-- functions files hand to ns.OnLanguage. So changing language needs a /reload.
--
-- To try another language from the .toc instead, add a line such as
-- "## X-Cinematic-Locale: esES" and /reload.
local ADDON_NAME, ns = ...

ns.LANGUAGES = {} -- locale -> { English = translation }, from Locales/<locale>.lua
ns.L = setmetatable({}, { __index = function(_, text) return text end })
ns.locale = "enUS"

-- Languages that share a table.
local SAME_AS = { esMX = "esES" }

local onLanguage = {}
-- fn runs once the language is set, before anything is shown.
function ns.OnLanguage(fn)
	onLanguage[#onLanguage + 1] = fn
end

-- Translates the given fields of each entry in a list, in place.
function ns.TranslateFields(list, ...)
	for _, entry in pairs(list) do
		for i = 1, select("#", ...) do
			local field = select(i, ...)
			if type(entry[field]) == "string" then
				entry[field] = ns.L[entry[field]]
			end
		end
	end
end

-- The language in use: the .toc's, the one picked in settings, or the game's.
local function ChosenLocale()
	local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local forced = GetMetadata and GetMetadata(ADDON_NAME, "X-Cinematic-Locale")
	if forced and forced ~= "" then
		return forced
	end
	return (CinematicDB and CinematicDB.language) or GetLocale()
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON_NAME then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")
	ns.locale = ChosenLocale()
	local strings = ns.LANGUAGES[SAME_AS[ns.locale] or ns.locale]
	if strings then
		for english, translated in pairs(strings) do
			rawset(ns.L, english, translated)
		end
	end
	ns.LANGUAGES = nil
	for _, fn in ipairs(onLanguage) do
		fn()
	end
end)
