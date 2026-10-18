-- What's new, the last sub-page: a hub with New features (Changelog.lua,
-- picked by hand, newest first) and All changes (every commit, from
-- ChangelogCommits.lua). Options.lua calls ns.CreateWhatsNewPanels with the
-- page helpers it shares once the language is known.

local _, ns = ...
local L = ns.L

-- "2026-10-16" -> "16 October 2026" (the game's month names where it has them).
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August",
	"September", "October", "November", "December" }
local function FormatDate(date)
	local year, month, day = date:match("^(%d+)-(%d+)-(%d+)$")
	if not year then return date end
	month = tonumber(month)
	local name = (CALENDAR_FULLDATE_MONTH_NAMES and CALENDAR_FULLDATE_MONTH_NAMES[month]) or L[MONTHS[month]]
	return ("%d %s %s"):format(tonumber(day), name, year)
end

-- Icons for pages that aren't in a hub (those come from ns.PageIcon).
local PAGE_ICONS = {
	["CineMode"] = "Interface\\Icons\\INV_Misc_Spyglass_02",
	["Profiles"] = "Interface\\Icons\\INV_Misc_Note_02",
	["Visual Effects"] = "Interface\\Icons\\Spell_Holy_Restoration",
	["Graphics+"] = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
	["Audio"] = "Interface\\Icons\\INV_Misc_Drum_01",
	["Keybinds"] = "Interface\\Icons\\INV_Misc_Key_03",
	["UI Manager"] = "Interface\\Icons\\INV_Misc_Head_Human_01",
}

-- A page's title and subtitle; returns the subtitle, to stack the rest under.
local function Heading(kit, content, title, subtitle)
	local titleLabel = kit.Label(content, "GameFontNormalLarge", title)
	titleLabel:SetPoint("TOPLEFT", 16, -16)
	local sub = kit.Label(content, "GameFontHighlightSmall", subtitle)
	sub:SetPoint("TOPLEFT", titleLabel, "BOTTOMLEFT", 0, -8)
	sub:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	sub:SetJustifyV("TOP")
	return sub
end

-- New features: by day, newest first; each with its page's icon and Show me.
local function CreateFeaturesPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local last = Heading(kit, content, L["New features"],
		L["What's new in Cinematic, newest first. Show me opens the page a feature is on. " ..
		"Every change, fixes too, is on the All changes page."])

	local entries = {}
	for i, entry in ipairs(ns.CHANGELOG_FEATURES or {}) do
		if not entry.client or (entry.client == "retail") == (ns.isRetail and true or false) then
			entries[#entries + 1] = { entry = entry, order = i }
		end
	end
	-- (the same day's in the file's order)
	table.sort(entries, function(a, b)
		if a.entry.date ~= b.entry.date then return a.entry.date > b.entry.date end
		return a.order < b.order
	end)

	local ICON = 32
	local rows = {}
	local shownDate
	for _, item in ipairs(entries) do
		local entry = item.entry
		if entry.date ~= shownDate then
			shownDate = entry.date
			local day = kit.Label(content, "GameFontNormal", FormatDate(entry.date))
			day:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -18)
			last = day
		end
		-- Each feature in a row of its own, as tall as its icon or its text.
		local row = CreateFrame("Frame", nil, content)
		row:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -10)
		row:SetPoint("RIGHT", content, "RIGHT", -16, 0)
		row:SetHeight(ICON)

		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(ICON, ICON)
		icon:SetPoint("TOPLEFT")
		icon:SetTexture((entry.page and (ns.PageIcon(entry.page) or PAGE_ICONS[entry.page]))
			or "Interface\\Icons\\INV_Misc_Gift_01")
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		local show
		if entry.page then
			show = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			show:SetSize(80, 20)
			show:SetPoint("TOPRIGHT")
			show:SetText(L["Show me"])
			show.searchSkip = true
			show:SetScript("OnClick", function() ns.OpenOptions(entry.page) end)
		end

		local title = kit.Label(row, "GameFontHighlight", L[entry.title])
		title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
		title:SetPoint("RIGHT", row, "RIGHT", -96, 0)

		local text = kit.Label(row, "GameFontHighlightSmall", L[entry.text])
		text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
		text:SetPoint("RIGHT", title, "RIGHT")
		text:SetJustifyV("TOP")
		text:SetTextColor(0.8, 0.8, 0.8)

		row.title, row.text = title, text
		rows[#rows + 1] = row
		last = row
	end

	if #entries == 0 then
		local none = kit.Label(content, "GameFontDisable", L["Nothing yet."])
		none:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -18)
	end

	-- Rows grow to fit their text once it's wrapped to the page's width.
	local function Fit()
		for _, row in ipairs(rows) do
			local height = 1 + row.title:GetStringHeight() + 4 + row.text:GetStringHeight()
			row:SetHeight(math.max(ICON, height))
		end
	end
	content:HookScript("OnSizeChanged", Fit)
	canvas:SetScript("OnShow", kit.PageShown(Fit, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "New features")
end

-- All changes: every commit message as written, by release, newest first.
local function CreateCommitsPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local intro = Heading(kit, content, L["All changes"],
		L["Every change made to Cinematic, newest first, as written when it was made (in English)."])

	-- (built the first time it's shown: a few hundred lines)
	local built
	local function Build()
		if built then return end
		built = true
		local commits = ns.CHANGELOG_COMMITS
		if not commits or #commits == 0 then
			local none = kit.Label(content, "GameFontDisable",
				L["The list comes with each release. (For the dev copy, run Tools/commits.sh and /reload.)"])
			none:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -18)
			return
		end
		-- Each line under the last one's text, back out at its dash (indent: how
		-- far in from the column edge that text starts).
		local last, indent, version = intro, 0, nil
		for _, commit in ipairs(commits) do
			if commit[1] ~= version then
				version = commit[1]
				local header = kit.Label(content, "GameFontNormal", (version == "next" and L["Coming next"]
					or ("v" .. version)) .. "  |cff808080" .. FormatDate(commit[2]) .. "|r")
				header:SetPoint("TOPLEFT", last, "BOTTOMLEFT", -indent, -16)
				last, indent = header, 0
			end
			local dash = kit.Label(content, "GameFontHighlightSmall", "-")
			dash:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 4 - indent, -6)
			-- (as written: a | in a message isn't a colour code)
			local line = kit.Label(content, "GameFontHighlightSmall", (commit[3]:gsub("|", "||")))
			line:SetPoint("TOPLEFT", dash, "TOPRIGHT", 6, 0)
			line:SetPoint("RIGHT", content, "RIGHT", -16, 0)
			line:SetJustifyV("TOP")
			line:SetTextColor(0.8, 0.8, 0.8)
			last, indent = line, 4 + dash:GetStringWidth() + 6
		end
	end

	canvas:SetScript("OnShow", kit.PageShown(Build, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "All changes")
end

ns.CreateWhatsNewPanels = function(kit)
	CreateFeaturesPanel(kit)
	CreateCommitsPanel(kit)
end

-- After an update with new features, a line in chat at login with a [What's
-- new] link to the page (a release of fixes only says nothing). Told by the
-- newest feature's date (db.lastFeatureDate), so the dev copy gets it too.
-- Not on a fresh install: the welcome window is enough then. Off with
-- db.updateNotice (Chat page).
local LINK = "garrmission:cinematic:whatsnew" -- (a type every client passes to SetItemRef quietly)

-- How many of this client's features are newer than date (nil: all), and the newest date.
local function FeaturesSince(date)
	local count, newest = 0, nil
	for _, entry in ipairs(ns.CHANGELOG_FEATURES or {}) do
		if not entry.client or (entry.client == "retail") == (ns.isRetail and true or false) then
			if not date or entry.date > date then count = count + 1 end
			if not newest or entry.date > newest then newest = entry.date end
		end
	end
	return count, newest
end

-- count: new features since the last login (nil: unknown, not said).
function ns.ShowUpdateNotice(count)
	local version = ns.Version()
	if version:match("^%d") then version = "v" .. version end
	local link = "|cff71d5ff|H" .. LINK .. "|h[" .. L["What's new"] .. "]|h|r"
	if count == 1 then
		ns.Print(L["updated to %s: a new feature, see %s."]:format(version, link))
	elseif count and count > 1 then
		ns.Print(L["updated to %s: %d new features, see %s."]:format(version, count, link))
	else
		ns.Print(L["updated to %s: see %s for the changes."]:format(version, link))
	end
	if ns.PeekChat then ns.PeekChat(DEFAULT_CHAT_FRAME, 20) end -- (up through CineMode, to be seen)
end

hooksecurefunc("SetItemRef", function(link)
	if link == LINK then ns.OpenOptions("New features") end
end)

local notice = CreateFrame("Frame")
notice:RegisterEvent("PLAYER_ENTERING_WORLD")
notice:SetScript("OnEvent", function(self, _, isLogin, isReload)
	if not (isLogin or isReload) or not ns.db then return end
	self:UnregisterAllEvents()
	local db = ns.db
	local newest = select(2, FeaturesSince(nil))
	if db.updateNotice ~= false and not ns.newInstall and newest and newest > (db.lastFeatureDate or "") then
		-- (no count the first time: every feature would be new)
		local count = db.lastFeatureDate and FeaturesSince(db.lastFeatureDate) or nil
		C_Timer.After(3, function() ns.ShowUpdateNotice(count) end) -- (after the login chat)
	end
	db.lastFeatureDate = newest
end)
