-- /guildy cpu: what the game itself charges Guildy per frame (C_AddOnProfiler, the source AddonProfiler
-- shows), in phases of PHASE seconds: as it is, with the parked bodies of the model pool hidden
-- (Game/ModelPool.lua), and with every visible frame named Guildy* hidden. /guildy perf measures only
-- Guildy's own Lua; this also sees what the client does for Guildy's frames (templates' scripts, models).
-- Every frame hidden for a phase is shown again at the end. The measuring frame itself costs the same in
-- every phase.
local _, ns = ...

local CpuProbe = {}
ns.CpuProbe = CpuProbe

CpuProbe.PHASE = 5

local runner -- the measuring frame while a run goes on

-- Guildy's time in the last frame in ms, nil when the client has no addon profiler
local function LastTime()
  local profiler, enum = rawget(_G, "C_AddOnProfiler"), rawget(_G, "Enum")
  local metric = enum and enum.AddOnProfilerMetric and enum.AddOnProfilerMetric.LastTime
  if not (profiler and profiler.GetAddOnMetric and metric) then return nil end
  local value = ns.Try(profiler.GetAddOnMetric, ns.ADDON, metric)
  if ns.IsSecret(value) or type(value) ~= "number" then return nil end
  return value
end

-- The visible frames named Guildy* (but not the measuring one): { frame }
local function NamedVisible()
  local list = {}
  local enumerate = rawget(_G, "EnumerateFrames")
  if not enumerate then return list end
  local frame = enumerate()
  while frame do
    -- forbidden frames (the auras' cooldowns, for one) refuse even GetName: skipped
    local ok, name = pcall(frame.GetName, frame)
    if ok and type(name) == "string" and name:find("^Guildy") and frame:IsVisible() then list[#list + 1] = frame end
    frame = enumerate(frame)
  end
  return list
end

local PHASES = {
  { label = "as it is" },
  { label = "pool bodies hidden",
    on = function(state) state.pool = ns.ModelPool.Hold(true) end,
    off = function() ns.ModelPool.Hold(false) end },
  { label = "Guildy* frames hidden",
    on = function(state)
      state.hidden = NamedVisible()
      for _, frame in ipairs(state.hidden) do frame:Hide() end
    end,
    off = function(state)
      for _, frame in ipairs(state.hidden or {}) do frame:Show() end
    end },
}

local function Report(results, state)
  ns.Print(("cpu: %d pooled bodies parked; visible Guildy* frames: %s"):format(state.pool or 0,
    #state.named == 0 and "none" or table.concat(state.named, ", ")))
  for _, r in ipairs(results) do
    ns.Print(("cpu: %-22s %.3f ms a frame (%d frames, peak %.2f ms)"):format(r.label, r.frames > 0 and r.total / r.frames or 0,
      r.frames, r.peak))
  end
end

function CpuProbe.Runner() return runner end -- the measuring frame (tests)

function CpuProbe.Run()
  if runner and runner.running then return ns.Print("cpu: a measurement is running") end
  if not LastTime() then return ns.Print("cpu: this client has no addon profiler (C_AddOnProfiler)") end
  runner = runner or CreateFrame("Frame")
  local state, results = { named = {} }, {}
  for _, frame in ipairs(NamedVisible()) do state.named[#state.named + 1] = frame:GetName() end
  local index, elapsed, current = 0, 0, nil
  local function Next()
    if current and PHASES[index].off then ns.SafeCall(PHASES[index].off, state) end
    index = index + 1
    local phase = PHASES[index]
    if not phase then
      runner.running = false
      runner:SetScript("OnUpdate", nil)
      Report(results, state)
      return
    end
    if phase.on then ns.SafeCall(phase.on, state) end
    -- the first frame after a change still carries the change itself: not counted
    current = { label = phase.label, total = 0, frames = 0, peak = 0, skip = true }
    results[#results + 1] = current
    elapsed = 0
  end
  runner.running = true
  ns.Print(("cpu: measuring %d phases of %d s, keep playing as before ..."):format(#PHASES, CpuProbe.PHASE))
  Next()
  runner:SetScript("OnUpdate", function(_, dt)
    if not runner.running then return end
    if current.skip then
      current.skip = false
    else
      local ms = LastTime() or 0
      current.total, current.frames = current.total + ms, current.frames + 1
      if ms > current.peak then current.peak = ms end
    end
    elapsed = elapsed + (dt or 0)
    if elapsed >= CpuProbe.PHASE then Next() end
  end)
end
