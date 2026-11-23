-- Blizzard's member list behind Guildy (UI/Notes.lua): Guildy's pick button clicks a row of it, so the
-- list is made tall enough for every member to have a row. Blizzard redraws every row it holds on each
-- roster update (CommunitiesMemberList.lua, GUILD_ROSTER_UPDATE) and asks for the roster again: with a
-- guild of 958 (reported 2026-11-23) that was 958 rows on every update while the window was open. A big
-- guild's list stays short and grows only while the mouse is on members.
local T = ...

local ROW = 24

local function World(count)
  local w = { now = 1000 }
  local roster = {}
  for i = 1, count do
    roster[i] = { ("Name%s-Last"):format(string.char(65 + i % 26, 97 + math.floor(i / 26) % 26, 97 + math.floor(i / 676) % 26)),
      "Mitglied", 3, 30, "Krieger", "Westfall", "", "", i <= 20, 0, "WARRIOR", nil, nil, false, nil, nil,
      ("Player-1-%08X"):format(i) }
  end
  local world = dofile(T.testsDir .. "/wow.lua")(T, { roster = roster, setup = function(env)
    env.GetTime = function() return w.now end
    env.C_Club = setmetatable({ GetGuildClubId = function() return 7 end },
      { __index = function() return function() return nil end end })
  end })
  w.env, w.ns, w.Fire, w.RunTimers = world.env, world.ns, world.Fire, world.RunTimers
  local env = w.env
  rawset(env.CommunitiesFrame, "GetSelectedClubId", function() return 7 end)
  w.rows = {} -- the rows Blizzard's list holds: none until a test puts one there
  w.list = env.CreateFrame("Frame")
  w.list.ScrollBox = { ForEachFrame = function(_, fn) for _, row in ipairs(w.rows) do fn(row) end end }
  rawset(env.CommunitiesFrame, "MemberList", w.list)
  -- Blizzard's list hears the roster (its OnShow registers these): each one it hears rebuilds and sorts
  -- every member (UpdateMemberList), however few rows it holds
  w.heard = 0
  w.list:SetScript("OnEvent", function(_, event)
    if event == "GUILD_ROSTER_UPDATE" or event == "CLUB_MEMBER_PRESENCE_UPDATED" then w.heard = w.heard + 1 end
  end)
  w.list:RegisterEvent("GUILD_ROSTER_UPDATE")
  w.list:RegisterEvent("CLUB_MEMBER_PRESENCE_UPDATED")
  w.Fire("ADDON_LOADED", "Guildy")
  w.Fire("PLAYER_LOGIN")
  w.Fire("GUILD_ROSTER_UPDATE")
  w.RunTimers()
  env.CommunitiesFrame:Show()
  w.RunTimers()
  function w.Height() return w.list:GetHeight() end
  -- a member frame in Guildy with the mouse on it
  function w.Owner(m)
    local owner = env.CreateFrame("Button")
    owner.member = m
    for key, value in pairs({ GetLeft = 100, GetBottom = 200, GetWidth = 300, GetHeight = 20, GetEffectiveScale = 1,
      IsMouseOver = true, IsVisible = true }) do
      rawset(owner, key, function() return value end)
    end
    return owner
  end
  return w
end

T.describe("Blizzard's member list", function()
  T.it("holds every member of a small guild, as before", function()
    local w = World(120)
    T.eq(w.Height(), 120 * ROW + 80)
  end)

  T.it("stays short in a big guild while nobody points at a member", function()
    local w = World(958)
    T.truthy(w.Height() < 30 * ROW + 80, ("height %s"):format(tostring(w.Height())))
    w.Fire("GUILD_ROSTER_UPDATE")
    w.RunTimers()
    T.truthy(w.Height() < 30 * ROW + 80, "a roster update keeps it short")
  end)

  T.it("grows when the mouse is on a member, lays the pick once the row is there, and shrinks again", function()
    local w = World(958)
    local rawset_ = rawset
    rawset_(w.env.UIParent, "GetEffectiveScale", function() return 1 end)
    local m = w.ns.Roster.Members()[700]
    local owner = w.Owner(m)
    w.ns.UI.Notes.HoverMember(owner, m)
    T.eq(w.Height(), 958 * ROW + 80)
    local pick = rawget(w.env, "GuildyNotePick")
    T.truthy(not (pick and pick:IsShown()), "no row yet: no pick")
    -- Blizzard fills the grown list a frame later; the mouse is still on the member
    w.rows[1] = { memberInfo = { guid = m.guid }, Click = function() end }
    w.RunTimers()
    pick = rawget(w.env, "GuildyNotePick")
    T.truthy(pick and pick:IsShown(), "the pick lies over the member once Blizzard has the row")
    T.eq(pick:GetAttribute("clickbutton1"), w.rows[1])
    -- half a minute without the mouse on a member: short again
    w.now = w.now + 31
    w.RunTimers()
    T.truthy(w.Height() < 30 * ROW + 80, ("height %s after the pause"):format(tostring(w.Height())))
  end)

  -- Moving Guildy's window moved Blizzard's (drawn at alpha 0 under it) on every frame of the drag:
  -- a guild of 958 lagged "really" while moving it (2026-11-23). It follows once, when the drag ends.
  T.it("moves Blizzard's hidden window once a drag ends, not on every frame of it", function()
    local w = World(958)
    local host, frame = w.env.CommunitiesFrame, rawget(w.env, "GuildyFrame")
    rawset(frame, "GetLeft", function() return 200 end)
    rawset(frame, "GetTop", function() return 700 end)
    local placed = 0
    local setPoint = host.SetPoint
    rawset(host, "SetPoint", function(self, ...)
      placed = placed + 1
      return setPoint(self, ...)
    end)
    frame:GetScript("OnDragStart")(frame)
    local onUpdate = frame:GetScript("OnUpdate")
    for _ = 1, 30 do if onUpdate then onUpdate(frame, 0.016) end end
    w.RunTimers()
    T.eq(placed, 0)
    frame:GetScript("OnDragStop")(frame)
    T.eq(placed, 1)
  end)

  T.it("stays grown while the mouse keeps coming back to members", function()
    local w = World(958)
    rawset(w.env.UIParent, "GetEffectiveScale", function() return 1 end)
    local m = w.ns.Roster.Members()[10]
    w.ns.UI.Notes.HoverMember(w.Owner(m), m)
    w.now = w.now + 20
    w.ns.UI.Notes.HoverMember(w.Owner(m), m)
    w.now = w.now + 20
    w.RunTimers()
    T.eq(w.Height(), 958 * ROW + 80)
  end)

  -- A guild of 1000 still dropped to 0 fps every few seconds with the window open (reported 2026-11-23,
  -- 1.11.1): Blizzard's list rebuilt and sorted all members on every roster update, about every 1.5 s,
  -- with few rows as with many. Guildy's own measurements could not see it (Blizzard's code).
  T.it("keeps a big guild's list from hearing roster updates while nobody points at a member", function()
    local w = World(958)
    w.heard = 0
    for _ = 1, 5 do
      w.Fire("GUILD_ROSTER_UPDATE", true)
      w.Fire("CLUB_MEMBER_PRESENCE_UPDATED", 7, 1, 1)
    end
    w.RunTimers()
    T.eq(w.heard, 0)
  end)

  T.it("lets one roster update through when the mouse comes to a member, then not again for a while", function()
    local w = World(958)
    rawset(w.env.UIParent, "GetEffectiveScale", function() return 1 end)
    local m = w.ns.Roster.Members()[10]
    w.heard = 0
    w.ns.UI.Notes.HoverMember(w.Owner(m), m)
    for _ = 1, 4 do w.Fire("GUILD_ROSTER_UPDATE", true) end
    T.eq(w.heard, 1)
    -- still on members a few seconds later: the list is fresh enough
    w.now = w.now + 3
    w.ns.UI.Notes.HoverMember(w.Owner(m), m)
    w.Fire("GUILD_ROSTER_UPDATE", true)
    T.eq(w.heard, 1)
    -- later on: one more
    w.now = w.now + 20
    w.ns.UI.Notes.HoverMember(w.Owner(m), m)
    w.Fire("GUILD_ROSTER_UPDATE", true)
    w.Fire("GUILD_ROSTER_UPDATE", true)
    T.eq(w.heard, 2)
  end)

  T.it("leaves a small guild's list hearing every roster update, as before", function()
    local w = World(120)
    w.heard = 0
    for _ = 1, 3 do w.Fire("GUILD_ROSTER_UPDATE", true) end
    T.eq(w.heard, 3)
  end)
end)
