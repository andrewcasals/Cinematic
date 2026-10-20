-- The first time Cinematic runs, a window asks the player to pick a profile,
-- so they start from a setup they chose (and know there are others). Until
-- they pick one, Cinematic does nothing and this comes back at each login
-- (unless they turn Cinematic off from it). It stays open as they pick, so
-- they can try each in turn: CineMode comes in at once behind it, and the
-- window sits above the letterbox and tint. /cine welcome brings it back.

local _, ns = ...
local L = ns.L

local window
local buttons = {} -- profile name -> its button
local status, later

local function Close()
	window:Hide()
end

-- Marks the profile being tried, and says what Done will keep.
local function Update()
	local chosen = ns.ProfileChosen() and ns.db.enabled
	local active = chosen and ns.ActiveProfile()
	for name, button in pairs(buttons) do
		if name == active then
			button:LockHighlight()
			button.check:Show()
		else
			button:UnlockHighlight()
			button.check:Hide()
		end
	end
	if chosen then
		status:SetText(L["Trying %s. Pick another to compare."]:format("|cffffd100" .. active .. "|r"))
		later:SetText(L["Done"])
	else
		status:SetText(L["Nothing runs until you pick one."])
		later:SetText(L["Decide later"])
	end
end

local function Pick(name)
	if not ns.db.enabled then ns.SetEnabled(true) end -- (turned off from here before)
	ns.SetProfile(name)
	if ns.RestartTimers then ns.RestartTimers() end -- (straight in, whichever was on)
	Update()
end

local function CreateWindow()
	window = CreateFrame("Frame", "CinematicWelcome", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	window:SetWidth(632)
	window:SetPoint("CENTER", 0, 60)
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	tinsert(UISpecialFrames, "CinematicWelcome") -- Escape closes it (decide later, or done)

	local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 18, -16)
	title:SetText(L["Welcome to Cinematic"])

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local intro = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	intro:SetWidth(596)
	intro:SetJustifyH("LEFT")
	intro:SetText(L["Between fights, Cinematic fades your UI away, adds letterbox bars and a colour " ..
		"tint, and brings the camera to life: on flights, standing still, sitting by a campfire. " ..
		"Fights, casting and opening windows bring the UI back. Hovering a faded frame shows it.\n\n" ..
		"How much of that do you want? Pick a profile to start from:"])

	local last, height = intro, 0
	for _, profile in ipairs(ns.BUILTIN_PROFILES) do
		-- Its icon, as on the Profiles page.
		local icon = window:CreateTexture(nil, "ARTWORK")
		icon:SetSize(26, 26)
		icon:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, last == intro and -16 or -10)
		icon:SetTexture(profile.icon)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
		button:SetSize(150, 26)
		button:SetPoint("LEFT", icon, "RIGHT", 6, 0)
		button:SetText(profile.name)
		button:SetScript("OnClick", function() Pick(profile.name) end)
		-- A tick on the one being tried.
		local check = button:CreateTexture(nil, "OVERLAY")
		check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		check:SetSize(20, 20)
		check:SetPoint("LEFT", button, "LEFT", 4, 0)
		button.check = check
		buttons[profile.name] = button
		local tip = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tip:SetPoint("TOPLEFT", button, "TOPRIGHT", 12, -2)
		tip:SetWidth(400)
		tip:SetJustifyH("LEFT")
		tip:SetJustifyV("TOP")
		tip:SetText(profile.tip)
		-- A long description pushes the next button down.
		local spacer = CreateFrame("Frame", nil, window)
		spacer:SetSize(1, math.max(26, tip:GetStringHeight() + 4))
		spacer:SetPoint("TOPLEFT", icon, "TOPLEFT")
		last = spacer
		height = height + spacer:GetHeight() + 10
	end

	local note = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
	note:SetWidth(596)
	note:SetJustifyH("LEFT")
	note:SetText(L["Try as many as you like: each one starts straight away behind this window. " ..
		"Afterwards you can switch any time, tweak a profile or make your own on the Profiles page " ..
		"(Options > AddOns > Cinematic, or right-click the minimap button), or with /cine profile. " ..
		"/cine toggles Cinematic on and off."])

	-- Decide later, or Done once one's picked (keeping it).
	later = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	later:SetSize(120, 22)
	later:SetPoint("BOTTOMRIGHT", -14, 14)
	later:SetText(L["Decide later"]) -- (Update changes it to Done)
	later:SetScript("OnClick", function()
		Close()
		if not ns.ProfileChosen() then
			ns.Print(L["off until you pick a profile. This window comes back next login, or now with /cine welcome."])
		else
			ns.Print(L["profile: %s. Change it any time on the Profiles settings page, or with /cine profile."]
				:format(ns.ActiveProfile()))
		end
	end)
	-- Not for them: switched off, and not asked again (/cine brings this back).
	local off = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	off:SetSize(150, 22)
	off:SetPoint("RIGHT", later, "LEFT", -8, 0)
	off:SetText(L["Turn Cinematic off"])
	off:SetScript("OnClick", function()
		ns.SetEnabled(false)
		Close()
		ns.Print(L["turned off. /cine brings this window back to pick a profile."])
	end)
	-- The settings, at the Profiles page (this window would sit over them).
	local settings = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	settings:SetSize(110, 22)
	settings:SetPoint("RIGHT", off, "LEFT", -8, 0)
	settings:SetText(L["Settings"])
	settings:SetScript("OnClick", function()
		Close()
		ns.OpenOptions("Profiles")
	end)
	-- What's on, above the buttons.
	status = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	status:SetPoint("BOTTOMLEFT", 18, 14 + 22 + 12)
	status:SetJustifyH("LEFT")

	window:SetHeight(16 + title:GetStringHeight() + 10 + intro:GetStringHeight() + 6 + height
		+ 16 + note:GetStringHeight() + 16 + 14 + 12 + 22 + 18)
end

function ns.ShowWelcome()
	if not window then CreateWindow() end
	window:Show()
	Update() -- (not from OnShow: a new frame starts shown, so it wouldn't fire the first time)
end

-- At login (and /reload), until a profile's been picked.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(_, _, isLogin, isReload)
	if (isLogin or isReload) and ns.db and not ns.db.profileChosen and ns.db.enabled then
		C_Timer.After(1, ns.ShowWelcome)
	end
end)
