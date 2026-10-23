-- Cinematic: Naowh Forever, a WoW Forever suite (one addon per module). Its
-- Quality of Life module's top bar, along the top of the screen, gets a row
-- on the Advanced Frames page; its own RestedXP guide window, standing in for
-- RestedXP's, fades with the Quest tracker row as RestedXP's does.
--
-- The top bar and its FPS / MS readout set their own alpha (its Show On
-- Mouseover fading): they're its own frames, so they're hooked.
local _, ns = ...
local L = ns.L

-- Advanced Frames row. (The readout is an unnamed frame on UIParent, kept
-- as the bar's sys.)
table.insert(ns.ADDON_FRAMES, {
	key = "naowhTopBar", addon = "NaowhForever_QoL", suite = "Naowh Forever",
	label = "Naowh Forever top bar", short = "Naowh top bar",
	about = L["its top bar along the top of the screen, with its FPS and MS readout"],
	names = { "NaowhForeverTopBar" },
	match = function(frame)
		local bar = _G.NaowhForeverTopBar
		return type(bar) == "table" and frame == bar.sys
	end,
	hookAlpha = true,
})

ns.WhenAddonLoads("NaowhForever", function()
	ns.FadeWithRow("quests", "quests", { "NaowhRXPWindow" })
end)
