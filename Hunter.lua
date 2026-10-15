-- Cinematic: hunter helpers (Quality of life page, Hunter section; not retail,
-- where right-click already shoots).
--
-- Addons can't cast by themselves, so both work through secure buttons that
-- your own key press or click lands on:
--  - Smart attack key (bound under Key Bindings > Cinematic): starts Auto Shot,
--    and melee too when out of a fight. In melee range Auto Shot fails ("too
--    close") and the swing carries on.
--  - Right-click pulls with Auto Shot (hunterRightClickShot): while the mouse
--    is on a living enemy, right-click is bound to a button that targets it
--    and starts Auto Shot. Out of combat that's done here, watching the mouse
--    buttons too. In a fight bindings only change from secure code, so a state
--    driver ([combat,@mouseover,harm,nodead]) does it there: the game checks
--    that a few times a second, so a very quick right-click on a new enemy can
--    still be a melee one.
local _, ns = ...

local AUTO_SHOT = 75

local isHunter = select(2, UnitClass("player")) == "HUNTER"
function ns.IsHunter()
	return isHunter
end

local function AutoShotName()
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(AUTO_SHOT)
		or GetSpellInfo and GetSpellInfo(AUTO_SHOT)
	return type(name) == "string" and name or "Auto Shot"
end

local function SecureButton(name)
	local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	button:SetAttribute("type", "macro")
	-- Click on key down or up, as the game's action buttons do (not both:
	-- that would run it twice).
	button:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
	return button
end

-- (Made as the file runs, so the key binding finds it by name. The "!" keeps
-- Auto Shot on when it already is, rather than toggling it off.)
local attackButton = SecureButton("CinematicHunterAttackButton")
local pullButton = SecureButton("CinematicHunterPullButton")
_G["BINDING_NAME_CLICK CinematicHunterAttackButton:LeftButton"] = "Cinematic: " .. ns.L["Hunter smart attack"]
ns.OnLanguage(function()
	_G["BINDING_NAME_CLICK CinematicHunterAttackButton:LeftButton"] = "Cinematic: " .. ns.L["Hunter smart attack"]
end)

local BOTH_BUTTONS_WINDOW = 0.25 -- seconds: a left-click this close before the right one counts as both
local leftDownAt = -math.huge
local bound = false -- right-click is ours

local function SetPull(on)
	if bound == on or InCombatLockdown() then
		return
	end
	bound = on
	if on then
		SetOverrideBindingClick(pullButton, true, "BUTTON2", pullButton:GetName())
	else
		ClearOverrideBindings(pullButton)
	end
end

-- The mouse on a living enemy you could shoot, and nothing in the way.
local function WantPull()
	local db = ns.db
	if not (db and db.hunterRightClickShot) or ns.Flag(UnitAffectingCombat("player")) then
		return false
	end
	if IsMouseButtonDown("LeftButton") or GetTime() - leftDownAt < BOTH_BUTTONS_WINDOW then
		return false -- (both buttons run you forward)
	end
	if ns.Flag(UnitIsDeadOrGhost("player")) or (IsMounted and ns.Flag(IsMounted()))
		or ns.Flag(UnitOnTaxi("player")) or (UnitInVehicle and ns.Flag(UnitInVehicle("player"))) then
		return false
	end
	if not ns.Flag(UnitExists("mouseover")) then
		return false
	end
	-- (Dead: right-click loots it. Secret answers count as no.)
	local okDead, dead = pcall(UnitIsDead, "mouseover")
	if not okDead or (issecretvalue and issecretvalue(dead)) or dead then
		return false
	end
	local okAttack, canAttack = pcall(UnitCanAttack, "player", "mouseover")
	return okAttack and ns.Flag(canAttack)
end

-- In a fight: its own binding, set and cleared by the state driver.
local combatHandler = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
combatHandler:SetAttribute("_onstate-pull", [[
	if newstate == "on" then
		self:SetBindingClick(true, "BUTTON2", "CinematicHunterPullButton")
	else
		self:ClearBindings()
	end
]])
local driverOn = false

-- The state driver follows the setting (not in a fight: once it's over).
function ns.ApplyHunter()
	if ns.isRetail or not isHunter then
		return
	end
	local want = ns.db and ns.db.hunterRightClickShot and true or false
	if want == driverOn then
		return
	end
	if InCombatLockdown() then
		return
	end
	driverOn = want
	if want then
		RegisterStateDriver(combatHandler, "pull", "[nocombat] off; [@mouseover,harm,nodead,nomounted] on; off")
	else
		UnregisterStateDriver(combatHandler, "pull")
		combatHandler:SetAttribute("state-pull", "off")
		ClearOverrideBindings(combatHandler)
	end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
watcher:SetScript("OnEvent", function(_, event, mouseButton)
	if event == "GLOBAL_MOUSE_DOWN" then
		if mouseButton == "LeftButton" then
			leftDownAt = GetTime()
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		SetPull(false) -- a fight: the state driver's binding takes over (let go just before lockdown)
	elseif event == "PLAYER_LOGIN" then
		isHunter = select(2, UnitClass("player")) == "HUNTER"
		if ns.isRetail or not isHunter then
			watcher:UnregisterAllEvents()
			return
		end
		local shot = AutoShotName()
		attackButton:SetAttribute("macrotext", "/startattack [nocombat]\n/cast !" .. shot)
		pullButton:SetAttribute("macrotext", "/target mouseover\n/startattack\n/cast !" .. shot)
		ns.ApplyHunter()
		watcher:SetScript("OnUpdate", ns.Profiled("Hunter right-click watch", function()
			-- Right button held: the binding stays as it was pressed (swapping it
			-- mid-press would leave a right-drag turning stuck).
			if not IsMouseButtonDown("RightButton") then
				SetPull(WantPull())
			end
			ns.ApplyHunter() -- (the setting changed: page, profile or Reset)
		end))
	end
end)
