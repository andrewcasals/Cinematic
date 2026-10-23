-- Cinematic: Deadly Boss Mods. Its timer bars all sit in one unnamed anchor
-- on UIParent (its big bars are only placed by a second anchor, they stay in
-- the first), so fading that fades them all. It's found by its first bar,
-- which DBM makes at the first timer: until then there's nothing to fade.
-- Its info frame, range check, arrow and battle res timer are named frames.
-- Its raid warnings and special warnings aren't faded, like the game's.
-- It leaves those frames' alpha alone (its bars fade in their own frames),
-- so they aren't hooked.
local _, ns = ...
local L = ns.L

table.insert(ns.ADDON_FRAMES, {
	key = "dbm", addon = "DBM-Core", label = "Deadly Boss Mods", short = "DBM",
	about = L["its timer bars, info frame, range check, arrow and battle res timer"],
	note = L["Its warnings aren't faded, like the game's raid warnings."],
	names = { "DBMInfoFrame", "DBMRangeCheck", "DBMRangeCheckRadar", "DBMArrow", "DBMBattleRezTimerFrame" },
	match = function(frame)
		local first = frame:GetChildren()
		-- (an unnamed frame of the game's can hold a forbidden one first)
		if not first or (first.IsForbidden and first:IsForbidden()) then
			return false
		end
		local name = first:GetName()
		return name and name:find("^DBT_Bar_%d+$") and true or false
	end,
})
