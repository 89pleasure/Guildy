-- Who has just reached the top level: the levels of one roster scan against the scan before.
-- Pure: takes and returns tables.
local _, ns = ...

local Ding = {}
ns.Ding = Ding

-- The members who were one level below max in the scan before and are at it now, and the levels of
-- this scan for the next call. before = { [key] = level }, nil on the first scan: then nobody is found.
-- A member who was not in the scan before (joined at the top level, or left and came back) is not
-- found either. Nor is a jump over several levels: scans are seconds apart, so that is a roster that
-- was wrong for a moment (the roster gives level 1 for a level the game did not send), and a banner
-- for somebody who has been 60 for months is worse than one missed.
function Ding.Find(before, members, max)
  local found, levels = {}, {}
  for _, m in ipairs(members) do
    if m.key ~= nil and type(m.level) == "number" then
      levels[m.key] = m.level
      local was = before and before[m.key]
      if was == max - 1 and m.level >= max then found[#found + 1] = m end
    end
  end
  return found, levels
end
