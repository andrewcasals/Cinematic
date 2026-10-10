-- Cinematic: Forever Enhanced Cooldown Manager.
local _, ns = ...

table.insert(ns.ADDON_FRAMES, {
	key = "fecm", addon = "ForeverEnhancedCooldownManager", label = "Forever Enhanced Cooldown Manager",
	short = "Enhanced Cooldown Manager", -- (the Standard Frames page's label column is narrow)
	about = "its cooldown and buff bars, and the pulse when a cooldown is ready",
	names = { "FECMPulse" },
	-- Its bars are unnamed: told apart by the parts each bar is made with.
	match = function(frame)
		return (frame.kind == "cooldown" or frame.kind == "aura")
			and type(frame.icons) == "table" and type(frame.mover) == "table"
	end,
})
