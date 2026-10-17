-- Cinematic: inspecting someone, a button just right of their level and class
-- opens their talents, and one with their portrait on the talents window
-- takes you back to the inspect window (talentLink, on the Quality of life
-- page; WoW Forever only). Not in a fight (addons can't open or close these
-- windows then without risk of blame).
local _, ns = ...

if ns.isRetail then
	return
end

local SIZE = 24
local GAP = 6

-- The talents window, whichever this client has (it loads on demand).
local TALENT_FRAMES = { "PlayerSpellsFrame", "ClassTalentFrame", "PlayerTalentFrame", "TalentFrame" }

local function Shown(frame)
	return type(frame) == "table" and frame.IsShown and ns.Flag(frame:IsShown())
end

local function TalentFrame()
	for _, name in ipairs(TALENT_FRAMES) do
		if Shown(_G[name]) then
			return _G[name]
		end
	end
end

local function Enabled()
	return ns.db and ns.db.talentLink
end

local inspected -- the unit whose talents we opened, for the way back
local SetUpTalents -- (below)

local lastError -- why opening their talents last failed (/cine debug talents)

-- The game's own inspect-talents button, if this client has one (hidden or
-- not). (InspectPaperDollFrame.ViewButton is the dressing room here.)
local function TalentsButton()
	return InspectPaperDollItemsFrame and InspectPaperDollItemsFrame.InspectTalents
end

-- The talents window, loaded (it loads on demand).
local function LoadTalentFrame()
	if not (PlayerSpellsFrame or ClassTalentFrame) then
		if PlayerSpellsFrame_LoadUI then
			pcall(PlayerSpellsFrame_LoadUI)
		elseif ClassTalentFrame_LoadUI then
			pcall(ClassTalentFrame_LoadUI)
		end
		local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
		if load and not (PlayerSpellsFrame or ClassTalentFrame) then
			pcall(load, "Blizzard_PlayerSpells")
			if not PlayerSpellsFrame then
				pcall(load, "Blizzard_ClassTalentUI")
			end
		end
	end
	return PlayerSpellsFrame or ClassTalentFrame
end

local function OpenTalents()
	if InCombatLockdown() or not InspectFrame then
		return
	end
	local unit = InspectFrame.unit
	if not unit then
		return
	end
	lastError = nil
	local ok, err
	local button = TalentsButton()
	if button and button.Click then
		ok, err = pcall(button.Click, button)
	else
		local frame = LoadTalentFrame()
		if not frame then
			lastError = "no talents window to load"
			return
		end
		if not frame.SetInspecting then
			lastError = "the talents window can't show someone else's talents (no SetInspecting)"
			return
		end
		ok, err = pcall(frame.SetInspecting, frame, unit)
		if ok and not Shown(frame) then
			ok, err = pcall(ShowUIPanel, frame)
		end
	end
	if not ok then
		lastError = tostring(err)
		return
	end
	inspected = unit
	-- (Whichever talents window it opened, once it's up.)
	C_Timer.After(0.1, SetUpTalents)
end

local function BackToInspect()
	if InCombatLockdown() then
		return
	end
	local unit = inspected
	local talents = TalentFrame()
	if talents then
		pcall(HideUIPanel, talents)
	end
	if unit and UnitExists(unit) and CanInspect(unit) then
		pcall(InspectUnit, unit)
	elseif InspectFrame then
		pcall(ShowUIPanel, InspectFrame)
	end
end

local function MakeButton(parent, tip, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(SIZE, SIZE)
	button:SetFrameLevel(parent:GetFrameLevel() + 10)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(tip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

-- On the inspect window: just right of the "Level 30 Paladin" text, which is
-- centred, so placed by its width each time it shows or changes.
local talentButton

local function PlaceTalentButton()
	if not talentButton then
		return
	end
	talentButton:SetShown(Enabled() and true or false)
	local text = InspectLevelText
	talentButton:ClearAllPoints()
	local width = text and text:GetStringWidth()
	if type(width) == "number" and not (issecretvalue and issecretvalue(width)) and width > 0 then
		talentButton:SetPoint("LEFT", text, "CENTER", width / 2 + GAP, 0)
	else
		talentButton:SetPoint("TOPRIGHT", InspectFrame, "TOPRIGHT", -40, -30)
	end
end

local function SetUpInspect()
	if talentButton or not (InspectFrame and InspectPaperDollFrame) then
		return
	end
	talentButton = MakeButton(InspectPaperDollFrame, TALENTS or "Talents", OpenTalents)
	-- (Above whatever frame the level text sits on.)
	local holder = InspectLevelText and InspectLevelText:GetParent()
	if holder and holder.GetFrameLevel then
		talentButton:SetFrameStrata(holder:GetFrameStrata())
		talentButton:SetFrameLevel(holder:GetFrameLevel() + 10)
	end
	talentButton.icon:SetTexture("Interface\\Icons\\Ability_Marksmanship")
	-- (The text is filled in after the window shows, so again a moment later.)
	InspectPaperDollFrame:HookScript("OnShow", function()
		PlaceTalentButton()
		C_Timer.After(0, PlaceTalentButton)
	end)
	if InspectLevelText then
		hooksecurefunc(InspectLevelText, "SetText", PlaceTalentButton)
		hooksecurefunc(InspectLevelText, "SetFormattedText", PlaceTalentButton)
	end
	PlaceTalentButton()
end

-- On the talents window, only when we opened it from the inspect window:
-- their portrait, in the empty band under the title.
local backButtons = {} -- talents window -> its button

local function ShowBackButton(frame)
	local button = backButtons[frame]
	if not button then
		return
	end
	local show = Enabled() and inspected and UnitExists(inspected) and true or false
	button:SetShown(show)
	if show then
		SetPortraitTexture(button.icon, inspected)
	end
end

function SetUpTalents()
	local frame = TalentFrame()
	if not frame then
		return
	end
	if not backButtons[frame] then
		local button = MakeButton(frame, INSPECT or "Inspect", BackToInspect)
		button:SetSize(SIZE + 8, SIZE + 8)
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, -40)
		-- (The talents window's own layers sit thousands of levels up: its
		-- border at 5500.)
		button:SetFrameLevel(math.min(frame:GetFrameLevel() + 6000, 9000))
		backButtons[frame] = button
		frame:HookScript("OnShow", ShowBackButton)
		frame:HookScript("OnHide", function()
			-- (Opened some other way next time: no way back to show.)
			inspected = nil
		end)
	end
	ShowBackButton(frame)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function()
	SetUpInspect()
	if talentButton then
		watcher:UnregisterAllEvents()
	end
end)

-- The option was ticked or unticked (Options.lua).
function ns.RefreshTalentLink()
	PlaceTalentButton()
	for frame in pairs(backButtons) do
		ShowBackButton(frame)
	end
end

-- /cine debug talents
local function PrintDebug()
	ns.Print("talentLink option: " .. tostring(ns.db and ns.db.talentLink))
	print("  InspectFrame: " .. tostring(InspectFrame ~= nil) .. ", unit " .. tostring(InspectFrame and InspectFrame.unit)
		.. ", shown " .. tostring(Shown(InspectFrame)))
	print("  game's inspect talents button: " .. tostring(TalentsButton() ~= nil)
		.. ", PlayerSpellsFrame_LoadUI: " .. tostring(PlayerSpellsFrame_LoadUI ~= nil)
		.. ", SetInspecting: " .. tostring(PlayerSpellsFrame and PlayerSpellsFrame.SetInspecting ~= nil))
	print("  last try: " .. (lastError or "no error"))
	for _, name in ipairs(TALENT_FRAMES) do
		print("  " .. name .. ": " .. tostring(_G[name] ~= nil) .. ", shown " .. tostring(Shown(_G[name])))
	end
	if PlayerSpellsUtil then
		local names = {}
		for key in pairs(PlayerSpellsUtil) do
			names[#names + 1] = tostring(key)
		end
		table.sort(names)
		print("  PlayerSpellsUtil: " .. table.concat(names, ", "))
	end
	if talentButton then
		local point, rel = talentButton:GetPoint(1)
		print(("  Talents button: shown %s, visible %s, %s to %s"):format(tostring(talentButton:IsShown()),
			tostring(talentButton:IsVisible()), tostring(point), tostring(rel and rel.GetName and rel:GetName())))
	else
		print("  Talents button: not made (inspect someone first)")
	end
end

-- (In 5 seconds: time to inspect someone after typing it.)
function ns.PrintTalentLinkDebug()
	ns.Print("inspect someone: looking in 5 seconds")
	C_Timer.After(5, PrintDebug)
end
