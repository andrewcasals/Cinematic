-- Cinematic: WeakAuras. Its auras sit in one screen-sized frame (and two
-- small ones for auras attached to the mouse or the personal resource
-- display), so fading those fades them all. Auras anchored to another frame
-- are that frame's children and fade with it. It leaves those frames' alpha
-- alone, so they aren't hooked.
local _, ns = ...
local L = ns.L

table.insert(ns.ADDON_FRAMES, {
	key = "weakauras", addon = "WeakAuras", label = "WeakAuras",
	about = L["its auras"],
	note = L["Auras anchored to another frame fade with that frame."],
	names = { "WeakAurasFrame", "WeakAurasAttachToMouseFrame", "WeakAurasAttachToPRD" },
})
