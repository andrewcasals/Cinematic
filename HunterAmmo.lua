-- Cinematic: after Clean Up Bags, the smallest stack of each kind of ammo goes
-- first (hunterAmmoSort, Quality of life page, Hunter section; not retail,
-- which has no ammo).
--
-- Clean Up Bags packs stacks from the first slot and leaves the odd one last,
-- but the game shoots from the first stack (first bag, first slot): it would
-- empty a full stack and leave two odd ones. Once the bags settle, the first
-- stack is dropped on the smallest: it fills that one up (or they swap, when
-- it's full), so the smaller count ends up first. Again until nothing changes.
local _, ns = ...

-- (WoW Forever only: no hooks or watchers on retail.)
if ns.isRetail then
	return
end

local Container = C_Container
local GetInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local Pickup = Container and Container.PickupContainerItem or PickupContainerItem
local NumSlots = Container and Container.GetContainerNumSlots or GetContainerNumSlots

local SETTLE = 1 -- seconds with no bag changes: the clean-up is done
local GIVE_UP = 20 -- seconds after the click
local MAX_MOVES = 8

local function SlotInfo(bag, slot)
	if Container and Container.GetContainerItemInfo then
		local info = Container.GetContainerItemInfo(bag, slot)
		if info then
			return info.itemID, info.stackCount, info.isLocked
		end
		return nil
	end
	local _, count, locked, _, _, _, _, _, _, itemID = GetContainerItemInfo(bag, slot)
	return itemID, count, locked
end

local function IsAmmo(itemID)
	local _, _, _, equipLoc = GetInfoInstant(itemID)
	return equipLoc == "INVTYPE_AMMO"
end

-- One move a time: "busy" (wait for the bags), "moved", or "done".
local function Arrange()
	if GetCursorInfo() or InCombatLockdown() then
		return "busy"
	end
	local first, smallest = {}, {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, NumSlots(bag) or 0 do
			local itemID, count, locked = SlotInfo(bag, slot)
			if locked then
				return "busy"
			end
			if type(itemID) == "number" and type(count) == "number" and IsAmmo(itemID) then
				local here = { bag = bag, slot = slot, count = count }
				first[itemID] = first[itemID] or here
				if not smallest[itemID] or count < smallest[itemID].count then
					smallest[itemID] = here
				end
			end
		end
	end
	for itemID, from in pairs(first) do
		local to = smallest[itemID]
		if to ~= from and to.count < from.count then
			Pickup(from.bag, from.slot)
			Pickup(to.bag, to.slot)
			if GetCursorInfo() then
				Pickup(from.bag, from.slot) -- (what's left goes back where it came from)
			end
			if GetCursorInfo() then
				ClearCursor()
			end
			return "moved"
		end
	end
	return "done"
end

local watcher = CreateFrame("Frame")
local giveUpAt, settleAt, moves = 0, 0, 0

local function Stop()
	watcher:SetScript("OnUpdate", nil)
	watcher:UnregisterEvent("BAG_UPDATE_DELAYED")
	watcher:UnregisterEvent("ITEM_LOCK_CHANGED")
end

local Wait = ns.Profiled("Hunter ammo after clean-up", function()
	local now = GetTime()
	if now > giveUpAt then
		Stop()
	elseif now >= settleAt then
		local result = Arrange()
		if result == "done" then
			Stop()
		else
			if result == "moved" then
				moves = moves + 1
				if moves >= MAX_MOVES then
					Stop()
					return
				end
			end
			settleAt = now + SETTLE
		end
	end
end)

watcher:SetScript("OnEvent", function()
	settleAt = GetTime() + SETTLE -- (still sorting)
end)

local function Sorted()
	if ns.isRetail or not ns.IsHunter() or not ns.Setting("hunterAmmoSort") or not GetInfoInstant then
		return
	end
	local now = GetTime()
	giveUpAt, settleAt, moves = now + GIVE_UP, now + SETTLE, 0
	watcher:RegisterEvent("BAG_UPDATE_DELAYED")
	watcher:RegisterEvent("ITEM_LOCK_CHANGED")
	watcher:SetScript("OnUpdate", Wait)
end

-- (The bag's Clean Up Bags button, and any addon or macro that calls it.)
if Container and Container.SortBags then
	hooksecurefunc(Container, "SortBags", Sorted)
elseif SortBags then
	hooksecurefunc("SortBags", Sorted)
end

-- A Fill button on arrows and bullets at a vendor (hunterQuiverFill): buys
-- enough to fill the quiver or ammo pouch that holds them, topping up its
-- part stacks and filling its empty slots, as far as your money goes.
local GetItemFamilyOf = C_Item and C_Item.GetItemFamily or GetItemFamily
local FreeSlots = Container and Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
local BagName = Container and Container.GetBagName or GetBagName
local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local MaxStack = C_Item and C_Item.GetItemMaxStackCount
local CoinText = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString

local function MerchantInfo(index)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		if info then
			return info.price, info.stackCount, info.numAvailable
		end
		return nil
	end
	local _, _, price, quantity, numAvailable = GetMerchantItemInfo(index)
	return price, quantity, numAvailable
end

local function MerchantItemID(index)
	if GetMerchantItemID then
		return GetMerchantItemID(index)
	end
	local link = GetMerchantItemLink(index)
	return link and tonumber(link:match("item:(%d+)"))
end

-- How many fit in the bags made for this ammo, and the first such bag's name.
local function Room(itemID)
	local family = GetItemFamilyOf and GetItemFamilyOf(itemID)
	local stackSize = MaxStack and MaxStack(itemID) or select(8, GetInfo(itemID))
	if type(family) ~= "number" or family == 0 or type(stackSize) ~= "number" then
		return 0
	end
	local room, name = 0, nil
	for bag = 1, NUM_BAG_SLOTS or 4 do
		local free, bagFamily = FreeSlots(bag)
		if type(bagFamily) == "number" and bit.band(bagFamily, family) ~= 0 then
			name = name or BagName(bag)
			room = room + (free or 0) * stackSize
			for slot = 1, NumSlots(bag) or 0 do
				local id, count = SlotInfo(bag, slot)
				if id == itemID and type(count) == "number" then
					room = room + math.max(stackSize - count, 0)
				end
			end
		end
	end
	return room, name
end

-- What one click buys: how many, what it costs, and into which bag.
local function FillPlan(index)
	local itemID = MerchantItemID(index)
	if type(itemID) ~= "number" or not IsAmmo(itemID) then
		return nil
	end
	local price, quantity, numAvailable = MerchantInfo(index)
	if type(price) ~= "number" or price <= 0 or type(quantity) ~= "number" or quantity < 1 then
		return nil
	end
	local room, bagName = Room(itemID)
	if not bagName then
		return nil -- (no quiver or ammo pouch for it)
	end
	local count = math.min(room, math.floor(GetMoney() * quantity / price))
	if type(numAvailable) == "number" and numAvailable >= 0 then
		count = math.min(count, numAvailable * quantity)
	end
	return math.max(count, 0), math.ceil(count * price / quantity), bagName
end

local fillButtons = {}

local function ShowFillTooltip(button)
	local count, cost, bagName = FillPlan(button.index)
	if not count then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(string.format(ns.L["Fill %s"], bagName))
	if count > 0 then
		GameTooltip:AddLine(string.format(ns.L["Buys %d for %s."], count, CoinText(cost)), 1, 1, 1)
	else
		GameTooltip:AddLine(ns.L["It's full (or you can't afford any)."], 1, 1, 1)
	end
	GameTooltip:Show()
end

local function Fill(button)
	local count = FillPlan(button.index)
	local perBuy = GetMerchantItemMaxStack and GetMerchantItemMaxStack(button.index) or 1
	while count and count > 0 do
		local buy = math.min(count, perBuy)
		BuyMerchantItem(button.index, buy)
		count = count - buy
	end
end

local function FillButton(i)
	if not fillButtons[i] then
		local item = _G["MerchantItem" .. i]
		if not item then
			return nil
		end
		local button = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
		button:SetSize(38, 18)
		button:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, 2)
		button:SetScript("OnClick", function(self)
			Fill(self)
			GameTooltip:Hide()
		end)
		button:SetScript("OnEnter", ShowFillTooltip)
		button:SetScript("OnLeave", GameTooltip_Hide)
		fillButtons[i] = button
	end
	return fillButtons[i]
end

local function UpdateFillButtons()
	local on = not ns.isRetail and ns.IsHunter() and ns.Setting("hunterQuiverFill")
		and MerchantFrame and MerchantFrame.selectedTab == 1
	for i = 1, MERCHANT_ITEMS_PER_PAGE or 10 do
		local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
		local index = itemButton and itemButton:GetID()
		local count = on and index and _G["MerchantItem" .. i]:IsShown() and FillPlan(index)
		local button = (count or fillButtons[i]) and FillButton(i)
		if button then
			button.index = index
			button:SetText(ns.L["Fill"])
			button:SetShown(count and true or false)
			button:SetEnabled(count and count > 0 or false)
		end
	end
end

if MerchantFrame_Update then
	hooksecurefunc("MerchantFrame_Update", UpdateFillButtons)
	local merchantWatch = CreateFrame("Frame")
	merchantWatch:RegisterEvent("BAG_UPDATE_DELAYED")
	merchantWatch:RegisterEvent("PLAYER_MONEY")
	merchantWatch:SetScript("OnEvent", function()
		if MerchantFrame:IsShown() then
			UpdateFillButtons()
		end
	end)
end
