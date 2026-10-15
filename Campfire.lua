-- Cinematic: a Sit button at campfires. Hovering a campfire with the cursor
-- near the middle of the screen brings up a campfire icon right under the
-- cursor; clicking it does /sit, so you needn't type it. Moving the cursor
-- off it puts it away.
-- (campfireSitButton, on the Quality of life page; WoW Forever only.)
local ADDON_NAME, ns = ...

-- A campfire's name in each game language (the game's own, whatever language
-- Cinematic shows): any world tooltip with this in its first line counts, so
-- "Basic Campfire" (the one you light) does too.
local CAMPFIRE_NAMES = {
	enUS = "campfire", enGB = "campfire",
	deDE = "lagerfeuer",
	esES = "hoguera", esMX = "fogata",
	frFR = "feu de camp",
	itIT = "fuoco da campo",
	ptBR = "fogueira",
	ruRU = "костер",
	koKR = "모닥불",
	zhCN = "篝火",
	zhTW = "營火",
}
local campfireName = CAMPFIRE_NAMES[GetLocale()] or "campfire"

local CENTER_REACH = 0.1 -- how near the middle the cursor must be: this much of the screen's height
local OBJECT_REACH = 40  -- UI units the cursor may wander from where a hidden tooltip's campfire was found
local LINGER = 1.5       -- seconds a sighting of the fire counts for, to bring it up
local REST = 2.5         -- seconds after it's gone before it can show again
local REST_HOVER = 1     -- ...unless the cursor stays on the fire, near the middle, this long
local WALK_OFF = 5       -- yards you can move from where it showed before it goes
local LOOK_EVERY = 0.1   -- seconds between looks at the tooltip
local FADE_TIME = 0.5
local ICON = "Interface\\Icons\\Spell_Fire_Fire" -- Basic Campfire's icon
local MASK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\RoundIcon" -- soft rounded corners (Media/make_round_mask.py)
local SIZE = 40

local button
local foundX, foundY     -- where the cursor was when a campfire's tooltip appeared (UI units)
local lastSeen = -math.huge
local dismissed = false  -- clicked: not again until the cursor has left the campfire
local restUntil = 0      -- shown and gone again: not again until then (REST)
local alpha, sinceLook = 0, 0
local HOVER = 0.5        -- seconds the cursor must stay on the campfire before it shows
local hoverSince         -- when the cursor came onto the campfire (near the middle), or nil
local shownX, shownY     -- where you stood as it showed (yards)
local walkedOff = false  -- moved WALK_OFF from there: going, whatever the cursor's on
local leftIcon = false   -- the cursor has moved off it: going

local function CursorPosition()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	return x / scale, y / scale
end

local function NearCenter(x, y)
	local width, height = UIParent:GetSize()
	local reach = height * CENTER_REACH
	return (x - width / 2) ^ 2 + (y - height / 2) ^ 2 <= reach * reach
end

local TENT_NAME = "camp tent" -- (English only for now)

-- Whether a world tooltip is up and its first line can be read. What that line
-- names (lastWasCampfire, lastWasTent) is worked out only when it changes, so
-- looking often makes no garbage.
local lastText, lastWasCampfire, lastWasTent
local function LookAtTooltip()
	if not ns.Flag(GameTooltip:IsShown()) then
		return false
	end
	local owner = GameTooltip:GetOwner()
	if not (owner == nil or owner == UIParent or owner == WorldFrame) then
		return false
	end
	local ok, text = pcall(function() return GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText() end)
	if not ok or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return false
	end
	if text ~= lastText then
		local lower = text:lower()
		lastText = text
		lastWasCampfire = lower:find(campfireName, 1, true) ~= nil
		lastWasTent = lower:find(TENT_NAME, 1, true) ~= nil
	end
	return true
end

-- The world tooltip's first line, if it's a campfire's.
local function TooltipIsCampfire()
	return LookAtTooltip() and lastWasCampfire
end

-- Times you can't (or wouldn't) sit down by a fire.
local function CanSit()
	local db = ns.db
	if ns.isRetail or not (db and db.campfireSitButton) then
		return false
	end
	if (ns.IsSitting and ns.IsSitting()) or InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) or ns.Flag(UnitIsDeadOrGhost("player"))
		or ns.Flag(UnitOnTaxi("player")) or (IsMounted and ns.Flag(IsMounted()))
		or (UnitInVehicle and ns.Flag(UnitInVehicle("player"))) then
		return false
	end
	return true
end

local function Sit()
	if C_ChatInfo and C_ChatInfo.PerformEmote then
		pcall(C_ChatInfo.PerformEmote, "SIT")
	elseif DoEmote then
		pcall(DoEmote, "SIT")
	end
	-- (Its own Camera Triggers row, cozy by default, rather than /sit's.)
	if ns.SatByButton then ns.SatByButton() end
end

-- Where you are, in yards; nil where the game won't say (some instances).
local function PlayerPosition()
	local ok, y, x = pcall(UnitPosition, "player")
	if ok and type(y) == "number" and type(x) == "number"
		and not (issecretvalue and (issecretvalue(y) or issecretvalue(x))) then
		return x, y
	end
end

-- Camp Tents: nothing says one is near but its tooltip, so the cursor passing
-- over one is noted, with where you stood, and it counts as near until you've
-- moved TENT_FORGET yards from there (or, where the game won't say where you
-- are, for TENT_FORGET_TIME seconds). For the cozy camera by a fire with a
-- tent in the way. (/cine debug tent; /cine debug tent seen fakes one.)
local TENT_FORGET = 15
local TENT_FORGET_TIME = 60
-- tent: { at = GetTime(), x, y = where you stood (yards, or nil), how =
-- "tooltip"/"test", side = "left"/"right" of the screen, facing = yours then
-- (degrees, or nil), duringCozy, seq = counts each new sighting or side }
local tent
local tentSeq = 0
-- The latest cozy camera, for /cine debug tent: whether the tent was known
-- as it started, or first seen during it (seconds in).
local cozy = { on = false, at = nil, ended = nil, tentAtStart = false, tentAfter = nil }

local function Facing()
	local ok, facing = pcall(GetPlayerFacing)
	if ok and type(facing) == "number" and not (issecretvalue and issecretvalue(facing)) then
		return math.deg(facing)
	end
end

-- side: which half of the screen it's on (by the cursor, if not given).
local function SawTent(how, side)
	side = side or (CursorPosition() > UIParent:GetWidth() / 2 and "right" or "left")
	-- Where it was first seen is what counts: the sway moves the camera, so the
	-- same tent crosses the screen, and taking each side afresh would turn the
	-- camera back and forth. (A test sighting always counts afresh.)
	if not tent or how == "test" then
		tentSeq = tentSeq + 1
		ns.Log("campfire", ("Camp Tent seen (%s), %s of the screen"):format(how, side))
		tent = tent or {}
		tent.side, tent.seq, tent.facing, tent.duringCozy = side, tentSeq, Facing(), cozy.on
	end
	tent.at, tent.how = GetTime(), how
	tent.x, tent.y = PlayerPosition()
	-- (A test sighting counts as seen while sitting even if one was known before.)
	if cozy.on and (not cozy.tentAtStart or how == "test") and not cozy.tentAfter then
		cozy.tentAfter = GetTime() - cozy.at
		ns.Log("campfire", ("Camp Tent seen %.1f sec into the cozy camera"):format(cozy.tentAfter))
	end
end

-- Following the cozy camera starting and ending (looked at every LOOK_EVERY).
local function WatchCozy()
	local now = ns.IsCozy and ns.IsCozy() or false
	if now and not cozy.on then
		cozy.on, cozy.at, cozy.ended, cozy.tentAtStart, cozy.tentAfter = true, GetTime(), nil, tent ~= nil, nil
		ns.Log("campfire", "cozy camera started, Camp Tent " .. (tent and "already seen" or "not seen"))
	elseif cozy.on and not now then
		cozy.on, cozy.ended = false, GetTime()
		ns.Log("campfire", ("cozy camera ended after %.0f sec"):format(cozy.ended - cozy.at))
	end
end

-- Yards from where you stood when the tent was last seen (nil if unknown).
local function TentDistance()
	if not (tent and tent.x) then
		return nil
	end
	local x, y = PlayerPosition()
	if x then
		return math.sqrt((x - tent.x) ^ 2 + (y - tent.y) ^ 2)
	end
end

local function ForgetTentIfAway()
	if not tent then
		return
	end
	local distance = TentDistance()
	if (distance and distance > TENT_FORGET) or (not distance and GetTime() - tent.at > TENT_FORGET_TIME) then
		ns.Log("campfire", ("Camp Tent forgotten (%s)"):format(distance and ("%.0f yards away"):format(distance)
			or "no position"))
		tent = nil
	end
end

-- Whether a Camp Tent has been seen near where you are (the cozy zoom then
-- comes in closer: cozyTentClose).
function ns.TentNearby()
	return tent ~= nil
end

-- The latest sighting, for the cozy camera's sway: its number (new each
-- sighting or change of side), the screen side, your facing then (degrees,
-- or nil) and whether the cozy camera was on. Nil if none is remembered.
function ns.TentSighting()
	if tent then
		return tent.seq, tent.side, tent.facing, tent.duringCozy
	end
end

-- /cine debug tent: the tent (nil if none is remembered) and the latest cozy
-- camera (nil if there's been none since loading in).
function ns.GetTentDebug()
	local seen, camera
	if tent then
		seen = { ago = GetTime() - tent.at, distance = TentDistance(), how = tent.how, forget = TENT_FORGET,
			side = tent.side, duringCozy = tent.duringCozy }
	end
	if cozy.at then
		camera = { on = cozy.on, length = (cozy.ended or GetTime()) - cozy.at,
			endedAgo = cozy.ended and GetTime() - cozy.ended, tentAtStart = cozy.tentAtStart, tentAfter = cozy.tentAfter }
	end
	return seen, camera
end

-- /cine debug tent seen [left|right] (as if one had just been moused over
-- there; right if not said) or clear.
function ns.TentTest(clear, side)
	if clear then
		tent = nil
		ns.Log("campfire", "Camp Tent cleared (test)")
	else
		SawTent("test", side or "right")
	end
end

-- Whether you've moved WALK_OFF yards from where you stood as it showed.
local function WalkedOff()
	if not shownX then
		return false
	end
	local x, y = PlayerPosition()
	return x ~= nil and (x - shownX) ^ 2 + (y - shownY) ^ 2 > WALK_OFF * WALK_OFF
end

-- Whether the cursor is on a campfire now: its tooltip is up, or (with
-- Cinematic hiding world tooltips) you're standing still and the cursor
-- hasn't wandered from where its tooltip appeared.
local function OnCampfire()
	if IsMouselooking and IsMouselooking() then
		return false -- (turning the view: no cursor)
	end
	if TooltipIsCampfire() then
		return true
	end
	if foundX and not ns.Flag(GameTooltip:IsShown()) and not ns.playerMoving then
		local x, y = CursorPosition()
		return (x - foundX) ^ 2 + (y - foundY) ^ 2 <= OBJECT_REACH * OBJECT_REACH
	end
	foundX, foundY = nil, nil
	return false
end

-- Looked at every frame, and the tooltip every LOOK_EVERY seconds: the game
-- often moves its tooltip from one thing to the next without showing it
-- again (walking past a fire with the cursor still), so OnShow alone misses it.
local function OnUpdate(_, elapsed)
	local now = GetTime()
	sinceLook = sinceLook + elapsed
	if sinceLook >= LOOK_EVERY then
		sinceLook = 0
		WatchCozy()
		-- (Sitting or not: a tent seen just after you sit counts too.)
		if LookAtTooltip() and lastWasTent then
			SawTent("tooltip")
		end
		ForgetTentIfAway()
		local onFire = CanSit() and OnCampfire()
		if not CanSit() then
			lastSeen, dismissed, hoverSince = -math.huge, false, nil
		elseif onFire and NearCenter(CursorPosition()) then
			-- (Once it's up, staying on the fire keeps it there without the wait.)
			hoverSince = hoverSince or now
			-- (Kept on the fire for REST_HOVER since it went: back without the REST wait.)
			if alpha == 0 and now < restUntil and now - hoverSince >= REST_HOVER then
				restUntil = now
			end
			if now >= restUntil and (alpha > 0 or now - hoverSince >= HOVER) then
				lastSeen = now
			end
		else
			hoverSince = nil
			if not onFire then
				dismissed = false
			end
		end
		if alpha > 0 and not walkedOff and WalkedOff() then
			walkedOff = true
		end
	end
	-- It shows under the cursor, so once it's up the cursor leaving it puts it
	-- away (and the REST wait after starts as it's gone).
	if alpha > 0 and button:IsShown() and not button:IsMouseOver() then
		leftIcon = true
	end
	-- (Up already: stays while the cursor's on it. Not up: needs a fresh
	-- sighting of the fire, and the REST wait over.)
	local want = not dismissed and not walkedOff and not leftIcon and CanSit()
		and (alpha > 0 or now >= restUntil)
		and (now - lastSeen < LINGER or (button:IsShown() and button:IsMouseOver()))
	if want then
		if alpha == 0 then
			shownX, shownY = PlayerPosition()
			-- Right under the cursor, and left there to be clicked.
			local x, y = CursorPosition()
			button:ClearAllPoints()
			button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
		end
		alpha = math.min(1, alpha + elapsed / FADE_TIME)
	elseif alpha > 0 then
		alpha = math.max(0, alpha - elapsed / FADE_TIME)
		if alpha == 0 then
			restUntil, walkedOff, leftIcon, shownX, shownY = now + REST, false, false, nil, nil
			-- (Gone: the sighting that brought it up is used up, so it doesn't
			-- come straight back wherever the cursor is now.)
			lastSeen, hoverSince = -math.huge, nil
		end
	else
		return
	end
	button:SetAlpha(alpha)
	button:SetShown(alpha > 0)
	button:EnableMouse(alpha > 0.5)
end

-- A campfire's tooltip appeared: noted where, in case Cinematic hides it at
-- once (the Tooltips page), so the cursor still counts as on the fire.
local function OnTooltipShow()
	if not LookAtTooltip() then
		return
	end
	if lastWasTent then
		SawTent("tooltip")
	end
	if lastWasCampfire and not ns.Flag(UnitExists("mouseover")) then
		foundX, foundY = CursorPosition()
		sinceLook = LOOK_EVERY -- (look now)
	end
end

-- The button: the campfire icon (placed as it shows, under the cursor).
button = CreateFrame("Button", "CinematicSitButton", UIParent)
button:SetSize(SIZE, SIZE)
button:SetFrameStrata("DIALOG")
button:SetClampedToScreen(true)
local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()
icon:SetTexture(ICON)
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- (trims the icon's own edge)
local highlight = button:CreateTexture(nil, "HIGHLIGHT")
highlight:SetAllPoints(icon)
highlight:SetColorTexture(1, 0.85, 0.4, 0.25)
if button.CreateMaskTexture then
	local mask = button:CreateMaskTexture()
	mask:SetAllPoints(icon)
	mask:SetTexture(MASK, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
	icon:AddMaskTexture(mask)
	highlight:AddMaskTexture(mask)
end
button:SetScript("OnMouseDown", function()
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", 1, -1)
end)
button:SetScript("OnMouseUp", function()
	icon:ClearAllPoints()
	icon:SetAllPoints()
end)
button:SetScript("OnClick", function()
	Sit()
	dismissed = true
end)
button:SetAlpha(0)
button:Hide()
ns.AddOverlay(button) -- (stays with the UI hidden, like the bars)

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", ns.Profiled("Campfire sit button", OnUpdate))

GameTooltip:HookScript("OnShow", OnTooltipShow)

-- Standing up once the camp is done (campfireStandUp): sitting by a Welcoming
-- Campfire for its minute gives Camp Benefits, or renews it if you have it
-- already. As it arrives, or its end moves later, you stand. Not as you log
-- in or reload with it already on you.
local CAMP_BENEFITS = 1229741 -- Camp Benefits' spell ID
local RENEWED = 5 -- seconds its end must move later by to count as renewed
local campBenefitsName -- (by name where the game can't look up an aura by ID)

local function Number(value)
	if type(value) == "number" and not (issecretvalue and issecretvalue(value)) then
		return value
	end
end

-- Whether you have Camp Benefits, and when it ends (nil if the game won't say).
local function CampBenefits()
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, CAMP_BENEFITS)
		if ok and type(aura) == "table" then
			local okEnd, ends = pcall(function() return aura.expirationTime end)
			return true, okEnd and Number(ends) or nil
		end
		return false
	end
	if not campBenefitsName then
		local ok, name = pcall(function()
			if C_Spell and C_Spell.GetSpellName then
				return C_Spell.GetSpellName(CAMP_BENEFITS)
			end
			return (GetSpellInfo(CAMP_BENEFITS))
		end)
		campBenefitsName = ok and type(name) == "string" and name or "Camp Benefits"
	end
	if AuraUtil and AuraUtil.FindAuraByName then
		local ok, found, _, _, _, _, ends = pcall(AuraUtil.FindAuraByName, campBenefitsName, "player", "HELPFUL")
		if ok and found ~= nil then
			return true, Number(ends)
		end
	end
	return false
end

local function StandUp()
	local ok, err
	if C_ChatInfo and C_ChatInfo.PerformEmote then
		ok, err = pcall(C_ChatInfo.PerformEmote, "STAND")
	elseif DoEmote then
		ok, err = pcall(DoEmote, "STAND")
	end
	ns.Log("campfire", ("stand up: %s %s"):format(tostring(ok), ok and "" or tostring(err)))
end

local had, hadEnds -- nil until the first look after loading in
local campWatcher = CreateFrame("Frame")
campWatcher:RegisterUnitEvent("UNIT_AURA", "player")
campWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
campWatcher:SetScript("OnEvent", ns.Profiled("UNIT_AURA (camp benefits)", function(_, event)
	if ns.isRetail then
		return
	end
	local has, ends = CampBenefits()
	local gained = event == "UNIT_AURA" and has and (had == false
		or (had and ends and hadEnds and ends > hadEnds + RENEWED))
	if has ~= had or (ends and hadEnds and math.abs(ends - hadEnds) > RENEWED) then
		ns.Log("campfire", ("Camp Benefits %s, ends %s (was %s, %s)%s"):format(tostring(has), tostring(ends),
			tostring(had), tostring(hadEnds), gained and ": gained" or ""))
	end
	had, hadEnds = has, ends
	local db = ns.db
	-- (It only comes while you sit, so no need to ask whether you are.)
	if gained and db and db.campfireSitButton and db.campfireStandUp then
		StandUp()
	end
end))
