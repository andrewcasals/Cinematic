-- Cinematic: dragging something you can wear out of the bags opens the
-- character window (dragEquipCharacter, on the Quality of life page), so the
-- slots are there to drop it on. "Out of the bags" is the cursor reaching the
-- game world: bags are UI however an addon draws them, so moving things
-- between bags never opens it. If it opened the window and you put the item back without
-- wearing it, the window closes again. Not in a fight (the window can't be
-- opened by addons then without risk of blame, and most gear can't be changed).
local _, ns = ...

-- Worn in bag slots, not on the character window.
local NOT_ON_CHARACTER = {
	[""] = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_NON_EQUIP = true,
	INVTYPE_BAG = true, INVTYPE_QUIVER = true,
}

local openedIt = false -- we opened the window for the item on the cursor
local equipped = false -- ...and something was put on since

local GetInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant

local function Wearable(itemID)
	if type(itemID) ~= "number" or not GetInfoInstant then
		return false
	end
	local _, _, _, equipLoc = GetInfoInstant(itemID)
	return type(equipLoc) == "string" and not NOT_ON_CHARACTER[equipLoc]
end

local function CharacterShown()
	return CharacterFrame and ns.Flag(CharacterFrame:IsShown())
end

local function CloseUnlessEquipped()
	if not openedIt and not equipped and not GetCursorInfo() and CharacterShown() and not InCombatLockdown() then
		ns.togglingCharacter = true
		pcall(HideUIPanel, CharacterFrame)
		ns.togglingCharacter = false
	end
end

-- Waiting for the cursor to leave the UI (OnUpdate set only while an item that
-- could open it is on the cursor).
local LOOK_EVERY = 0.1
local sinceLook = 0
local waiter = CreateFrame("Frame")

local function StopWaiting()
	waiter:SetScript("OnUpdate", nil)
end

-- Opening and closing the window update your player and pet frames' bars
-- (health, heal prediction, the numbers). On WoW Forever those are secret, and
-- done by us, Blizzard's comparison errors (TextStatusBar.lua, HealthBar.lua,
-- UnitFrame.lua) though the window works fine: secret-value errors during
-- these calls are kept quiet (ns.togglingCharacter, Diagnostics.lua).
local function OpenCharacter()
	ns.togglingCharacter = true
	pcall(ToggleCharacter, "PaperDollFrame")
	ns.togglingCharacter = false
end

local function CanOpen()
	return not openedIt and ns.db and ns.db.dragEquipCharacter and not CharacterShown()
		and not InCombatLockdown() and ToggleCharacter and ns.MouseOverWorld
end

local Wait = ns.Profiled("Drag gear watch", function(_, elapsed)
	sinceLook = sinceLook + elapsed
	if sinceLook < LOOK_EVERY then
		return
	end
	sinceLook = 0
	if GetCursorInfo() ~= "item" or not CanOpen() then
		StopWaiting()
	elseif ns.MouseOverWorld() then
		-- Out over the game world: past any bags, whichever addon draws them.
		StopWaiting()
		OpenCharacter()
		openedIt, equipped = CharacterShown(), false
	end
end)

local function CursorChanged()
	local kind, itemID = GetCursorInfo()
	if kind == "item" then
		if CanOpen() and Wearable(itemID) then
			sinceLook = 0
			waiter:SetScript("OnUpdate", Wait)
		end
	elseif not kind then
		StopWaiting()
	end
	if openedIt and not kind then
		-- Put down: back in the bags (or destroyed, or sold) closes it again.
		-- (A moment later: putting it on may tell us just after the cursor empties.)
		openedIt = false
		C_Timer.After(0.3, CloseUnlessEquipped)
	end
end

local watcher = CreateFrame("Frame")
-- (CURSOR_CHANGED isn't on every client: ITEM_LOCK_CHANGED, on picking up and
-- putting down from bags or the character window, is the fallback.)
pcall(watcher.RegisterEvent, watcher, "CURSOR_CHANGED")
watcher:RegisterEvent("ITEM_LOCK_CHANGED")
watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_EQUIPMENT_CHANGED" then
		equipped = true
	else
		CursorChanged()
	end
end)
