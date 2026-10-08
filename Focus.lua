-- Cinematic depth of field (faked): a soft haze around the screen edges, as if
-- the camera had pulled focus onto you. Shown in the camera modes while
-- cinematic mode is on (depthOfField), at each mode's own strength (dof*,
-- set on its page). /cine doftest shows it on demand.
local _, ns = ...

local FOCUS_TEXTURE = "Interface\\AddOns\\Cinematic\\Textures\\Focus"
local FOCUS_IN_TIME = 3    -- seconds to pull focus in: slow, like a focus pull
local FOCUS_OUT_TIME = 0.8 -- ...and to clear again once you move
local BLEND_TIME = 1.5     -- seconds to go from no haze to full, changing modes
local DEMO_STRENGTH = 0.3  -- /cine doftest's strength, unless told another
local DEFAULT_SECONDS = 30
local PREVIEW_SECONDS = 3  -- shown this long after a strength slider moves

-- The strength setting for each camera mode (ns.CameraMode()).
local MODE_KEY = { idle = "dofIdle", cozy = "dofCozy", vista = "dofVista", fish = "dofFish",
	flight = "dofFlight", walk = "dofWalk", run = "dofRun" }

local frame, haze
local level, strength = 0, 0 -- how far in the focus pull is, and the haze it pulls to
local stopAt, demoStrength = 0, nil

-- The strength wanted now: the demo's, else the current camera mode's.
local function WantedStrength()
	if GetTime() < stopAt then
		return demoStrength or DEMO_STRENGTH
	end
	local db = ns.db
	if not db or not db.enabled or not db.depthOfField or not ns.lastCinematic then
		return 0
	end
	local mode = ns.CameraMode()
	return mode and db[MODE_KEY[mode]] or 0
end

local function OnUpdate(_, elapsed)
	local want = WantedStrength()
	if want > 0 then
		level = math.min(1, level + elapsed / FOCUS_IN_TIME)
		-- Coming in from nothing, start at the new strength; otherwise (one mode
		-- to the next) glide to it.
		if strength == 0 then
			strength = want
		elseif strength ~= want then
			local step = elapsed / BLEND_TIME
			strength = strength < want and math.min(want, strength + step) or math.max(want, strength - step)
		end
	else
		level = math.max(0, level - elapsed / FOCUS_OUT_TIME) -- (fades at the strength it had)
		if level == 0 then
			strength = 0
		end
	end
	-- Eased, so the pull starts gently and settles.
	local eased = level * level * (3 - 2 * level)
	haze:SetAlpha(strength * eased)
	haze:SetShown(level > 0)
end

-- Over the world, beside the tint and under the letterbox bars and the UI.
frame = CreateFrame("Frame", "CinematicFocus", UIParent)
frame:SetAllPoints(UIParent)
frame:SetFrameStrata("BACKGROUND")
frame:SetFrameLevel(0)
frame:EnableMouse(false)
ns.AddOverlay(frame)

haze = frame:CreateTexture(nil, "ARTWORK", nil, 1)
haze:SetAllPoints()
haze:SetTexture(FOCUS_TEXTURE)
haze:SetBlendMode("BLEND")
haze:SetAlpha(0)
haze:Hide()

frame:SetScript("OnUpdate", OnUpdate)

-- Shows the haze for a while (default 30 seconds), at `value` (0-1) or the
-- demo strength. Returns false if a demo was already showing and has now
-- been stopped instead.
function ns.FocusDemo(seconds, value)
	if GetTime() < stopAt and not seconds and not value then
		stopAt = 0
		return false
	end
	if value then
		demoStrength = math.max(0, math.min(1, value))
		strength = demoStrength -- (show a new value at once, for comparing)
	end
	stopAt = GetTime() + (seconds or DEFAULT_SECONDS)
	return true
end

-- A strength slider moved: show that strength for a moment.
function ns.FocusPreview(value)
	ns.FocusDemo(PREVIEW_SECONDS, value)
	level = 1 -- straight in, so you see the value now
end

-- The demo's strength (for /cine doftest's message).
function ns.FocusDemoStrength()
	return demoStrength or DEMO_STRENGTH
end
