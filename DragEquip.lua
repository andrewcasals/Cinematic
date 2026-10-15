-- Cinematic: picking up something you can wear opens the character window
-- (dragEquipCharacter, on the Quality of life page), so the slots are there to
-- drop it on. If it opened the window and you put the item back without
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
		HideUIPanel(CharacterFrame)
	end
end

local function CursorChanged()
	local kind, itemID = GetCursorInfo()
	if kind == "item" then
		if openedIt or not (ns.db and ns.db.dragEquipCharacter) or CharacterShown()
			or InCombatLockdown() or not Wearable(itemID) or not ToggleCharacter then
			return
		end
		ToggleCharacter("PaperDollFrame")
		openedIt, equipped = CharacterShown(), false
	elseif openedIt and not kind then
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
