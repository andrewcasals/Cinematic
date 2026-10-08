-- Hide the UI like Blizzard's Alt+Z, but keep the addon's own overlays (tint,
-- letterbox, death screen, time-of-day title) on screen.
--
-- The overlays live on UIParent, so hiding it would take them along. While
-- the UI is hidden they move to a parentless holder that copies UIParent's
-- size and scale, then go back when UIParent shows again (by this key,
-- Blizzard's own, or anything else).
local _, ns = ...

local overlays = {}  -- frame -> { parent, strata, level }
local holder
local hidden = false

local function SyncHolder()
	holder:SetScale(UIParent:GetScale())
	holder:ClearAllPoints()
	holder:SetAllPoints(UIParent)
end

local function Move(frame, parent)
	local saved = overlays[frame]
	frame:SetParent(parent)
	frame:SetFrameStrata(saved.strata)
	frame:SetFrameLevel(saved.level)
end

local function Restore()
	if not hidden then
		return
	end
	hidden = false
	for frame, saved in pairs(overlays) do
		Move(frame, saved.parent)
	end
	holder:Hide()
end

local function Detach()
	if not holder then
		holder = CreateFrame("Frame", "CinematicOverlayHolder")
		holder:SetFrameStrata("BACKGROUND")
		holder:SetFrameLevel(0)
		holder:EnableMouse(false)
		holder:RegisterEvent("UI_SCALE_CHANGED")
		holder:RegisterEvent("DISPLAY_SIZE_CHANGED")
		holder:SetScript("OnEvent", SyncHolder)
		UIParent:HookScript("OnShow", Restore)
	end
	SyncHolder()
	holder:Show()
	hidden = true
	for frame in pairs(overlays) do
		Move(frame, holder)
	end
end

-- Called by each overlay when it's created (some are made on demand, perhaps
-- while the UI is already hidden).
function ns.AddOverlay(frame)
	overlays[frame] = {
		parent = frame:GetParent(),
		strata = frame:GetFrameStrata(),
		level = frame:GetFrameLevel(),
	}
	if hidden then
		Move(frame, holder)
	end
end

function ns.ToggleUI()
	local show = not UIParent:IsShown()
	if not show then
		Detach()
	end
	if SetUIVisibility then
		-- What Blizzard's key uses: works in combat and hides nameplates too.
		SetUIVisibility(show)
	elseif not InCombatLockdown() then
		UIParent:SetShown(show)
	end
	if UIParent:IsShown() then
		Restore() -- shown, or the hide was blocked
	end
end
