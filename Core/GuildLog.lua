-- The guild event log's filter, pure: each kind of entry the game names (GetGuildEventInfo) belongs to
-- one group the Info & Log tab can show alone, and has a color for its mark. Unknown kinds stay in "all"
-- only, so a kind a later client adds still shows.
local _, ns = ...

local GuildLog = {}
ns.GuildLog = GuildLog

GuildLog.GROUPS = { "all", "join", "left", "invite", "rank" }

local GROUP = { join = "join", invite = "invite", quit = "left", remove = "left", promote = "rank", demote = "rank" }

-- the green and red of the Overview's comings and goings, gold up, orange down, blue for invites
local COLOR = {
  join = { 0.35, 0.9, 0.35 }, invite = { 0.47, 0.71, 1 }, quit = { 1, 0.31, 0.31 }, remove = { 1, 0.31, 0.31 },
  promote = { 1, 0.82, 0 }, demote = { 1, 0.55, 0.2 },
}

function GuildLog.Group(kind)
  return GROUP[kind]
end

function GuildLog.Color(kind)
  return COLOR[kind]
end

-- lines: { { kind = ... }, ... } -> { all = n, join = n, left = n, invite = n, rank = n }
function GuildLog.Counts(lines)
  local counts = { all = #lines, join = 0, left = 0, invite = 0, rank = 0 }
  for _, line in ipairs(lines) do
    local group = GROUP[line.kind]
    if group then counts[group] = counts[group] + 1 end
  end
  return counts
end

-- The lines of one group in their order; all of them for "all" or a group that does not exist
function GuildLog.Filter(lines, group)
  if group == nil or group == "all" or not GuildLog.Known(group) then return lines end
  local kept = {}
  for _, line in ipairs(lines) do
    if GROUP[line.kind] == group then kept[#kept + 1] = line end
  end
  return kept
end

function GuildLog.Known(group)
  for _, known in ipairs(GuildLog.GROUPS) do
    if known == group then return true end
  end
  return false
end
