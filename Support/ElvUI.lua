-- Cinematic: ElvUI, a whole-UI replacement. It swaps the game's unit frames,
-- action bars, buffs, data bars and chat panels for its own, which fade with
-- the frames they stand in for and follow the same rows on the Standard
-- Frames page. Its parts with no game frame to follow get rows of their own
-- on the Advanced Frames page.
--
-- It sets its frames' alpha all the time (its bars' opacity and mouseover
-- fading, its unit frames' range and fader fading): they're its own frames,
-- so they're hooked.
local _, ns = ...
local L = ns.L

-- Advanced Frames rows.
for _, known in ipairs({
	{
		key = "elvBars", addon = "ElvUI",
		label = "ElvUI other bars", short = "ElvUI bars",
		about = L["its action bars 2 and 7 to 10"],
		note = L["Its other bars, pet, stance, totem, micro, bag and data bars are rows on the Standard " ..
			"Frames page, with its unit frames, buffs and chat panels."],
		names = { "ElvUI_Bar2", "ElvUI_Bar7", "ElvUI_Bar8", "ElvUI_Bar9", "ElvUI_Bar10" },
	},
	{
		key = "elvPanels", addon = "ElvUI",
		label = "ElvUI top and bottom panels", short = "ElvUI panels",
		about = L["its panels along the top and bottom of the screen"],
		names = { "ElvUI_TopPanel", "ElvUI_BottomPanel" },
	},
	{
		key = "elvThreat", addon = "ElvUI",
		label = "ElvUI threat bar", short = "ElvUI threat",
		about = L["its threat bar"],
		names = { "ElvUI_ThreatBarHolder" },
	},
}) do
	known.hookAlpha = true
	table.insert(ns.ADDON_FRAMES, known)
end

-- Its frames standing in for the game's, by Standard Frames row: the row,
-- the fade group, and the frames. (Its bars 1 and 3-6 show the game's action
-- pages 1 and 3-6, so the bars that page sits on; 13-15 are retail's bars 6-8.
-- Its cast bars are on its unit frames and fade with them.)
local ROWS = {
	{ "player", "player", "ElvUF_Player" },
	{ "petframe", "player", "ElvUF_Pet", "ElvUF_PetTarget" },
	{ "target", "target", "ElvUF_Target" },
	{ "tot", "target", "ElvUF_TargetTarget", "ElvUF_TargetTargetTarget" },
	{ "focus", "target", "ElvUF_Focus" },
	{ "focustot", "target", "ElvUF_FocusTarget" },
	{ "party", "party", "ElvUF_Party" },
	{ "buffs", "buffs", "ElvUIPlayerBuffs", "ElvUIPlayerDebuffs" },
	{ "mainbar", "bars", "ElvUI_Bar1", "VehicleLeaveButtonHolder" },
	{ "right1", "sidebars", "ElvUI_Bar3" },
	{ "right2", "sidebars", "ElvUI_Bar4" },
	{ "bottomright", "bars", "ElvUI_Bar5" },
	{ "bottomleft", "bars", "ElvUI_Bar6" },
	{ "bar6", "bars", "ElvUI_Bar13" },
	{ "bar7", "bars", "ElvUI_Bar14" },
	{ "bar8", "bars", "ElvUI_Bar15" },
	{ "pet", "bars", "ElvUI_BarPet" },
	{ "stance", "bars", "ElvUI_StanceBar" },
	{ "totems", "totems", "ElvUI_TotemBar", "ElvUI_TotemTracker" },
	{ "micro", "bars", "ElvUI_MicroBar" },
	-- (Classic clients have no Bags row: their bags go with the micro menu.)
	{ _G.BagsBar and "bags" or "micro", "bars", "ElvUIBagBar" },
	{ "xp", "bars", "ElvUI_ExperienceBarHolder", "ElvUI_ReputationBarHolder", "ElvUI_PetExperienceBarHolder" },
	-- Its chat panels hold the game's chat frames, with its data texts and
	-- toggle buttons (no row: the Chat page's).
	{ "chat", "chat", "LeftChatPanel", "RightChatPanel", "LeftChatToggleButton", "RightChatToggleButton" },
}

-- Its nameplates are its own frames on the game's plates (plate.unitFrame),
-- standing in for the game's (hidden), and it sets their alpha for its
-- target and range fading. They're hooked, as Plater's are: while a plate is
-- faded its alpha is ours times its own, and at full it's left to it again.
local applying = false

local function Apply(frame)
	applying = true
	frame:SetAlpha((frame.cinematicOwnAlpha or 1) * (frame.cinematicPlateAlpha or 1))
	applying = false
end

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function HookPlate(frame)
	if frame.cinematicHooked then
		return
	end
	frame.cinematicHooked = true
	local alpha = frame:GetAlpha()
	frame.cinematicOwnAlpha = Known(alpha) and alpha or nil
	hooksecurefunc(frame, "SetAlpha", ns.Profiled("ElvUI plate SetAlpha hook", function(self, own)
		if applying then
			return
		end
		self.cinematicOwnAlpha = type(own) == "number" and Known(own) and own or nil
		if self.cinematicPlateAlpha then
			Apply(self)
		end
	end))
end

local function SetPlateAlpha(plate, alpha)
	local frame = plate.unitFrame
	if type(frame) ~= "table" or not frame.isNameplate or not frame.SetAlpha then
		return
	end
	if alpha and alpha < 1 then
		HookPlate(frame)
		if frame.cinematicPlateAlpha ~= alpha then
			frame.cinematicPlateAlpha = alpha
			Apply(frame)
		end
	elseif frame.cinematicPlateAlpha then
		frame.cinematicPlateAlpha = nil
		Apply(frame) -- (back to its own alpha)
	end
end

-- Its raid frames fade with the game's on the Standard Frames page (Players
-- and Pets): those groups are found by scans, not names.
local RAID = {
	raidplayers = { "ElvUF_Raid1", "ElvUF_Raid2", "ElvUF_Raid3", "ElvUF_Tank", "ElvUF_Assist" },
	raidpets = { "ElvUF_Raidpet" },
}

ns.WhenAddonLoads("ElvUI", function()
	for _, row in ipairs(ROWS) do
		ns.FadeWithRow(row[1], row[2], { unpack(row, 3) }, true, true)
	end
	ns.AddScanner(function()
		for group, names in pairs(RAID) do
			for _, name in ipairs(names) do
				local frame = _G[name]
				if type(frame) == "table" and not ns.IsFaded(frame) then
					ns.AddFoundFrame(frame, group, true, true)
				end
			end
		end
	end)
	local other = ns.addonPlateAlpha
	ns.addonPlateAlpha = function(plate, alpha)
		if other then
			other(plate, alpha)
		end
		SetPlateAlpha(plate, alpha)
	end
end)
