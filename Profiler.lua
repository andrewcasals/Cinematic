-- Cinematic: /cine debug cpu, a profiler for finding what the addon spends its
-- time on. The busy parts (every-frame updates, the update tick and its steps,
-- frequent events and hooks) are wrapped with ns.Profiled; while it isn't
-- running, a wrapped call costs one extra function call and a check.
--
-- A wrapped part that runs on its own (an OnUpdate, an event, a hook) is a
-- section, and the sections add up to the addon's measured time. Wrapped parts
-- called from inside one (the tick's steps, the event camera lookup) are listed
-- under it too: their times are part of its time, and may overlap each other.
-- Memory is how much Lua memory grew over each call, roughly the garbage it
-- made (a collection step running in the middle can hide some).
-- The full report goes in the log (/cine log) and opens in its window to copy;
-- chat gets the top of it.
local ADDON_NAME, ns = ...

local DEFAULT_SECONDS = 30
local CHAT_ROWS = 6     -- sections printed to chat (all of them go in the log)
local CHILD_ROWS = 12   -- parts listed under each section in the log
local CALIBRATE_CALLS = 2000

local clock = debugprofilestop
local function Memory()
	return collectgarbage("count")
end

ns.profiling = false

local sections = {}  -- [name] = { time, calls, kb, max, children = { [name] = stat } }
local counts = {}    -- [name] = how many times (see ns.ProfileCount)
local current        -- the section running now (parts called meanwhile go under it)
local run            -- the profile under way
local stepNames = {} -- [function] = name, for the tick's steps (see ns.ProfileStep)
local localNames = {} -- names for local functions run as steps (ns.ProfileName)

local function Stat(list, name)
	local stat = list[name]
	if not stat then
		stat = { time = 0, calls = 0, kb = 0, max = 0 }
		list[name] = stat
	end
	return stat
end

local function Record(name, isSection, ms, kb)
	local stat
	if isSection then
		stat = Stat(sections, name)
		run.frameMs = run.frameMs + ms
	else
		local parent = Stat(sections, current)
		parent.children = parent.children or {}
		stat = Stat(parent.children, name)
	end
	stat.time = stat.time + ms
	stat.calls = stat.calls + 1
	if kb > 0 then
		stat.kb = stat.kb + kb
	end
	if ms > stat.max then
		stat.max = ms
	end
end

local function Finish(name, isSection, started, memory, ...)
	local ms = clock() - started
	local kb = Memory() - memory
	if isSection then
		current = nil
	end
	if ns.profiling then
		Record(name, isSection, ms, kb)
	end
	return ...
end

-- fn wrapped to be timed as `name` while profiling. Return values pass through.
function ns.Profiled(name, fn)
	return function(...)
		if not ns.profiling then
			return fn(...)
		end
		local isSection = current == nil
		if isSection then
			current = name
		end
		return Finish(name, isSection, clock(), Memory(), fn(...))
	end
end

-- For code that times itself (Core.lua's Step): the start, then the end.
function ns.ProfileMark()
	return clock(), Memory()
end

function ns.ProfileStep(fn, started, memory)
	local ms = clock() - started
	local kb = Memory() - memory
	if ns.profiling then
		Record(stepNames[fn] or localNames[fn] or "(step)", current == nil, ms, kb)
	end
end

-- A name for a local function that runs as a step (functions on ns are named
-- by their key).
function ns.ProfileName(fn, name)
	localNames[fn] = name
end

-- Counts something (n times, default 1) while profiling: shown a frame.
-- Callers check ns.profiling first.
function ns.ProfileCount(name, n)
	counts[name] = (counts[name] or 0) + (n or 1)
end

-- The game's own addon profiler (retail), where there is one.
local function GameMetric(kind, metric)
	local profiler = C_AddOnProfiler
	local metrics = Enum and Enum.AddOnProfilerMetric
	local id = metrics and metrics[metric]
	if not (profiler and id) then
		return nil
	end
	local ok, value
	if kind == "addon" and profiler.GetAddOnMetric then
		ok, value = pcall(profiler.GetAddOnMetric, ADDON_NAME, id)
	elseif kind == "overall" and profiler.GetOverallMetric then
		ok, value = pcall(profiler.GetOverallMetric, id)
	elseif kind == "app" and profiler.GetApplicationMetric then
		ok, value = pcall(profiler.GetApplicationMetric, id)
	end
	if ok and type(value) == "number" and not (issecretvalue and issecretvalue(value)) then
		return value
	end
	return nil
end

local GAME_KINDS = { "addon", "overall", "app" }
local GAME_SPIKES = { "CountTimeOver1Ms", "CountTimeOver5Ms", "CountTimeOver10Ms" }

local function State()
	local group = IsInRaid() and "raid" or (IsInGroup() and "party" or "solo")
	local plates = C_NamePlate and C_NamePlate.GetNamePlates and #C_NamePlate.GetNamePlates() or 0
	return ("%s, camera %s, %s, %s, %s, %d faded frames, %d nameplates"):format(
		ns.lastCinematic and "CineMode" or "normal UI", tostring(ns.activeCam or "none"),
		InCombatLockdown() and "in combat" or "out of combat", group,
		ns.EffectPlace and ns.EffectPlace() or "?", #(ns.managed or {}), plates)
end

-- What one wrapped call costs the profiler itself, in ms.
local function Calibrate()
	local noop = ns.Profiled("(calibration)", function() end)
	local started = clock()
	for _ = 1, CALIBRATE_CALLS do
		noop()
	end
	local perCall = (clock() - started) / CALIBRATE_CALLS
	wipe(sections)
	return perCall
end

local watcher = CreateFrame("Frame")
watcher:Hide()

local function Sorted(list)
	local names = {}
	for name in pairs(list) do
		names[#names + 1] = name
	end
	table.sort(names, function(a, b) return list[a].time > list[b].time end)
	return names
end

local function BuildReport()
	local lines = {}
	local function Add(text, ...)
		lines[#lines + 1] = text:format(...)
	end
	local seconds = math.max(run.elapsed, 0.001)
	local frames = math.max(run.frames, 1)
	local total, calls, kb = 0, 0, 0
	for _, stat in pairs(sections) do
		total, calls, kb = total + stat.time, calls + stat.calls, kb + stat.kb
		for _, child in pairs(stat.children or {}) do
			calls = calls + child.calls
		end
	end
	Add("cpu profile: %.1f sec, %d frames (%.0f fps, %.2f ms a frame)", seconds, frames, frames / seconds,
		seconds * 1000 / frames)
	Add("at the start: %s", run.startState)
	Add("at the end: %s", State())
	Add("measured: %.3f ms a frame (%.2f%% of the frame time), %.1f ms a second; memory made %.0f KB a second",
		total / frames, total / (seconds * 10), total / seconds, kb / seconds)
	Add("frames with measured work over 1 / 5 / 16 ms: %d / %d / %d, the worst %.2f ms",
		run.spikes[1], run.spikes[5], run.spikes[16], run.worst)
	if run.gameFrames > 0 then
		local addon, overall, app = run.game.addon / run.gameFrames, run.game.overall / run.gameFrames,
			run.game.app / run.gameFrames
		Add("game's profiler: this addon %.3f ms a frame; all addons %.3f; the whole frame %.2f "
			.. "(not wrapped here, so missing above: %.3f ms a frame)", addon, overall, app, addon - total / frames)
		local spikes = {}
		for _, metric in ipairs(GAME_SPIKES) do
			local now = GameMetric("addon", metric)
			if now and run.gameSpikes[metric] then
				spikes[#spikes + 1] = ("%s %d"):format((metric:gsub("CountTime", "")), now - run.gameSpikes[metric])
			end
		end
		if #spikes > 0 then
			Add("game's profiler, this addon's frames: %s", table.concat(spikes, ", "))
		end
	elseif GameMetric("addon", "RecentAverageTime") then
		Add("game's profiler (its recent average): this addon %.3f ms a frame; all addons %.3f; the whole frame %.2f",
			GameMetric("addon", "RecentAverageTime"), GameMetric("overall", "RecentAverageTime") or 0,
			GameMetric("app", "RecentAverageTime") or 0)
	else
		Add("game's profiler: not available on this client")
	end
	Add("profiler's own cost: about %.2f microseconds a wrapped call, %.3f ms a frame of the above",
		run.overhead * 1000, run.overhead * calls / frames)
	Add("section: ms a frame, share of measured, calls a frame, average ms, worst ms, KB a second")
	for _, name in ipairs(Sorted(sections)) do
		local stat = sections[name]
		Add("%s: %.3f, %.0f%%, %.2f, %.4f, %.2f, %.1f", name, stat.time / frames,
			total > 0 and stat.time * 100 / total or 0, stat.calls / frames, stat.time / stat.calls, stat.max,
			stat.kb / seconds)
		if stat.children then
			for i, childName in ipairs(Sorted(stat.children)) do
				if i > CHILD_ROWS then
					break
				end
				local child = stat.children[childName]
				Add("    > %s: %.3f, -, %.2f, %.4f, %.2f, %.1f", childName, child.time / frames, child.calls / frames,
					child.time / child.calls, child.max, child.kb / seconds)
			end
		end
	end
	local countNames = {}
	for name in pairs(counts) do
		countNames[#countNames + 1] = name
	end
	table.sort(countNames)
	for _, name in ipairs(countNames) do
		Add("count %s: %.1f a frame", name, counts[name] / frames)
	end
	return lines
end

function ns.StopProfile()
	if not run then
		return false
	end
	ns.profiling = false
	current = nil
	watcher:Hide()
	local lines = BuildReport()
	for _, line in ipairs(lines) do
		ns.Log("cpu", line)
	end
	-- Chat: the summary, then the biggest sections.
	-- (Sub-parts and counts: the log only.)
	local inSections, rows = false, 0
	for i, line in ipairs(lines) do
		if line:find("^section: ") then
			inSections = true
		end
		local detail = line:find("^    > ") or line:find("^count ")
		if not inSections or (not detail and rows <= CHAT_ROWS) then
			print((i == 1 and "|cffe0b050Cinematic:|r " or "  ") .. line)
			if inSections then
				rows = rows + 1
			end
		end
	end
	ns.Print("the full report is open to copy, and in /cine log")
	ns.ShowText("/cine debug cpu: press Ctrl+C to copy",
		("/cine debug cpu (Cinematic %s)\n%s"):format(ns.Version(), table.concat(lines, "\n")))
	run = nil
	return true
end

function ns.StartProfile(seconds)
	if run then
		return false
	end
	wipe(sections)
	wipe(counts)
	wipe(stepNames)
	for key, value in pairs(ns) do
		if type(value) == "function" then
			stepNames[value] = key
		end
	end
	run = {
		frames = 0, elapsed = 0, frameMs = 0, worst = 0, spikes = { [1] = 0, [5] = 0, [16] = 0 },
		game = { addon = 0, overall = 0, app = 0 }, gameFrames = 0, gameSpikes = {},
		startState = State(),
	}
	ns.profiling = true
	run.overhead = Calibrate()
	for _, metric in ipairs(GAME_SPIKES) do
		run.gameSpikes[metric] = GameMetric("addon", metric)
	end
	run.endsAt = GetTime() + (seconds or DEFAULT_SECONDS)
	run.first = true
	watcher:Show()
	return true
end

function ns.IsProfiling()
	return run ~= nil
end

watcher:SetScript("OnUpdate", function(_, elapsed)
	current = nil -- (a wrapped call that errored never finished)
	if run.first then
		-- (The first update only starts the count: the frame before was partly unmeasured.)
		run.first, run.frameMs = false, 0
		return
	end
	-- The work measured since the last update: one frame's worth.
	local ms = run.frameMs
	run.frameMs = 0
	run.frames = run.frames + 1
	run.elapsed = run.elapsed + elapsed
	if ms > run.worst then
		run.worst = ms
	end
	for limit in pairs(run.spikes) do
		if ms > limit then
			run.spikes[limit] = run.spikes[limit] + 1
		end
	end
	-- The game's figures for the frame before.
	local addon = GameMetric("addon", "LastTime")
	if addon then
		run.gameFrames = run.gameFrames + 1
		for _, kind in ipairs(GAME_KINDS) do
			run.game[kind] = run.game[kind] + (GameMetric(kind, "LastTime") or 0)
		end
	end
	if GetTime() >= run.endsAt then
		ns.StopProfile()
	end
end)
