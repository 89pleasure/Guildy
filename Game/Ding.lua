-- The game side of Core/Ding.lua: after every roster scan finds who has just reached the top level,
-- shows the banner (UI/Ding.lua), to this player only. Guildy says nothing in guild chat about it:
-- players want to announce their level 60 themselves, and one Guildy user's choice would speak for all.
-- The game sends the roster only when asked, so Guildy asks every POLL seconds. Nothing is saved: the
-- first roster of a session (or of another guild) only sets the levels to compare with.
local _, ns = ...

local GameDing = {}
ns.GameDing = GameDing

local D = ns.Ding
local POLL = 30 -- seconds between two requests for the roster
local levels, guildKey
local announced = {} -- memberKey -> true: found once this session, never again (a roster can fall back)

local function Max()
  return ns.Census.MAX_LEVEL
end

local function Announce(m)
  if announced[m.key] then return end
  announced[m.key] = true
  if ns.Settings().ding60 ~= false and ns.UI and ns.UI.ShowDing then ns.UI.ShowDing(m) end
end

ns.On("ROSTER", function()
  local key = ns.GuildKey()
  if key ~= guildKey then guildKey, levels, announced = key, nil, {} end
  if not key then return end
  local found
  found, levels = D.Find(levels, ns.Roster.Members(), Max())
  for _, m in ipairs(found) do Announce(m) end
end)

-- The own character went up a level. At the top level it is announced at once, without waiting for
-- the roster to show it (the game may not answer a request so soon after the last one); the roster
-- is asked all the same, for the tabs.
function GameDing.OnLevelUp(level)
  if type(level) ~= "number" or level < Max() or not ns.GuildKey() then return end
  local _, classFile = UnitClass("player")
  local name = ns.PlayerName()
  Announce(ns.Roster.Me() or { key = ns.Names.Key(name), name = name, classFile = classFile })
  C_Timer.After(1, function() ns.Roster.Request(true) end)
end

function GameDing.Start()
  C_Timer.NewTicker(POLL, function()
    if ns.Settings().ding60 == false then return end
    if IsInGuild() then ns.Roster.Request(true, true) end
  end)
end

-- /guildy ding: the banner for the own character, to look at it.
function GameDing.Test()
  local _, classFile = UnitClass("player")
  ns.UI.ShowDing(ns.Roster.Me() or { name = ns.PlayerName(), classFile = classFile })
end
