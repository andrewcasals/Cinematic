-- Cinematic: the dev build's Name Style page, for trying how names on
-- name-only plates look (PlateParts.lua's NAME_STYLE), live on the plates
-- around you. Kept in ns.db.devNameStyle; "Print as code" puts the
-- NAME_STYLE line in chat, to make it the default. Only CinematicDev.toc
-- loads this file.
local _, ns = ...

local function Value(key)
	local own = ns.db.devNameStyle
	local value = own and own[key]
	if value == nil then
		return ns.NAME_STYLE_DEFAULTS[key]
	end
	return value
end

local function SetValue(key, value)
	ns.db.devNameStyle = ns.db.devNameStyle or {}
	ns.db.devNameStyle[key] = value
	ns.RefreshPlateNameStyle()
end

-- The sliders: key, label, min, max, step, format.
local SLIDERS = {
	{ "outline", "Outline", 0, 2, 1, "%d" },
	{ "size", "Size (times the game's)", 0.5, 2, 0.05, "%.2f" },
	{ "shadowX", "Shadow across", -4, 4, 0.5, "%.1f" },
	{ "shadowY", "Shadow up/down", -4, 4, 0.5, "%.1f" },
	{ "shadowAlpha", "Shadow darkness", 0, 1, 0.05, "%.2f" },
}

-- NAME_STYLE as a line of code, keys in the defaults' order.
local ORDER = { "colour", "classColours", "outline", "size", "shadow", "shadowX", "shadowY", "shadowAlpha" }
local function AsCode()
	local parts = {}
	for _, key in ipairs(ORDER) do
		local value = Value(key)
		parts[#parts + 1] = key .. " = " .. (type(value) == "number" and (("%.2f"):format(value):gsub("%.?0+$", ""))
			or tostring(value))
	end
	return "local NAME_STYLE = { " .. table.concat(parts, ", ") .. " }"
end

function ns.CreateNameStylePanel(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", "|cffff4040DEV ONLY|r Name Style")
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.Label(content, "GameFontHighlight", "How names look on plates showing only their " ..
		"name (CineMode, plates faded, names on). Changes show at once on the plates around you.")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	intro:SetWidth(560)
	intro:SetJustifyH("LEFT")

	local controls = {}
	local function Check(key, label, tip, anchor, y)
		local check = kit.Check(content, {}, label, tip, function(value) SetValue(key, value) end)
		check.Refresh = function(self) self:SetChecked(Value(key)) end
		check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
		controls[#controls + 1] = check
		return check
	end
	local colour = Check("colour", "Colour names (red hostile, yellow neutral, green friendly)",
		"Off: the game's own colour (white or grey on most plates).", intro, -12)
	local classColours = Check("classColours", "Class colours on friendly players",
		"The game's colours for them on plates. Off: blue, as the game's names over their heads.", colour, -4)
	local shadow = Check("shadow", "Drop shadow", nil, classColours, -4)

	local anchor, y = shadow, -30
	for _, info in ipairs(SLIDERS) do
		local key = info[1]
		local slider = kit.Slider(content, {
			get = function() return Value(key) end,
			set = function(value) SetValue(key, value) end,
		}, info[2], info[3], info[4], info[5], info[6])
		slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor == shadow and 4 or 0, y)
		slider:SetWidth(300)
		controls[#controls + 1] = slider
		anchor, y = slider, -34
	end

	local function Refresh()
		for _, control in ipairs(controls) do
			control:Refresh()
		end
	end

	local printButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	printButton:SetSize(140, 24)
	printButton:SetText("Print as code")
	printButton:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -4, -24)
	kit.Tooltip(printButton, "Puts this style in chat as PlateParts.lua's NAME_STYLE line, to make it the default.")
	printButton:SetScript("OnClick", function()
		ns.Print(AsCode())
	end)
	local defaults = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	defaults:SetSize(140, 24)
	defaults:SetText("Back to defaults")
	defaults:SetPoint("LEFT", printButton, "RIGHT", 8, 0)
	kit.Tooltip(defaults, "The style everyone gets (PlateParts.lua's NAME_STYLE).")
	defaults:SetScript("OnClick", function()
		ns.db.devNameStyle = nil
		ns.RefreshPlateNameStyle()
		Refresh()
	end)

	canvas:SetScript("OnShow", kit.PageShown(Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Name Style", "Name Style")
end
