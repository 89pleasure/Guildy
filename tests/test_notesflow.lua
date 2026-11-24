-- Blizzard's member list behind Guildy (UI/Notes.lua): Guildy's pick button clicks a row of it, so the
-- list is made tall enough for every member to have a row. Blizzard redraws every row it holds on each
-- roster update (CommunitiesMemberList.lua, GUILD_ROSTER_UPDATE) and asks for the roster again: with a
-- guild of 958 (reported 2026-11-23) that was 958 rows on every update while the window was open. A big
-- guild's list stays short and grows only while the mouse is on members.
local T = ...

local ROW = 24

local function World(count, fresh)
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
  w.list:Show() -- (shown with Blizzard's window, as in the game)
  w.Fire("ADDON_LOADED", "Guildy")
  w.Fire("PLAYER_LOGIN")
  w.Fire("GUILD_ROSTER_UPDATE")
  w.RunTimers()
  env.CommunitiesFrame:Show()
  if not fresh then w.RunTimers() end -- (fresh: the window has just opened, no timer ran yet)
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

  -- Grown to all ~1000 rows at once, the first hover froze the game (seen with /guildy stress
  -- 2026-11-24): the list grows GROW_STEP rows a frame, a moment after the window opened.
  T.it("grows a big guild's list a step a frame after the window opened, never all at once", function()
    local w = World(958, true)
    local step = w.ns.UI.Notes.GROW_STEP
    local last = w.Height()
    local steps = 0
    for _ = 1, 60 do
      w.RunTimers(1)
      local h = w.Height()
      T.truthy(h - last <= step * ROW, ("grew %d rows in one frame"):format((h - last) / ROW))
      if h > last then steps = steps + 1 end
      last = h
    end
    T.eq(last, 958 * ROW + 80)
    T.truthy(steps > 10, ("only %d steps"):format(steps))
  end)

  -- In the gamepad interface the game's cursor searched the whole window again for every new row, and
  -- growing to 1000 rows froze it for seconds (/guildy stress 2026-11-24): there the list grows only once
  -- a note is to be edited, then for the rest of the session.
  T.it("grows a big guild's list in the gamepad interface only for editing a note", function()
    local w = World(958, true)
    rawset(w.env, "InputUtil", { IsGamepadUIEnabled = function() return true end })
    rawset(w.env.UIParent, "GetEffectiveScale", function() return 1 end)
    local short = w.Height()
    w.RunTimers(60)
    T.eq(w.Height(), short) -- opened: stays short
    local m = w.ns.Roster.Members()[700]
    w.ns.UI.Notes.HoverMember(w.Owner(m), m)
    w.RunTimers(60)
    T.eq(w.Height(), short) -- the cursor passing over members: still short
    w.ns.UI.Notes.HoverButton(w.Owner(m), m) -- the cursor on "Edit notes"
    w.RunTimers(60)
    T.eq(w.Height(), 958 * ROW + 80)
    -- opened again later in the session: grows as with the mouse (Blizzard's rows are made already)
    w.env.CommunitiesFrame:Hide()
    w.env.CommunitiesFrame:Show()
    w.RunTimers(60)
    T.eq(w.Height(), 958 * ROW + 80)
  end)

  T.it("lays the pick once the list has the member's row, stays grown, and starts short when the window opens again", function()
    local w = World(958)
    rawset(w.env.UIParent, "GetEffectiveScale", function() return 1 end)
    local m = w.ns.Roster.Members()[700]
    local owner = w.Owner(m)
    w.ns.UI.Notes.HoverMember(owner, m)
    local pick = rawget(w.env, "GuildyNotePick")
    T.truthy(not (pick and pick:IsShown()), "no row yet: no pick")
    -- Blizzard fills the grown list; the mouse is still on the member
    w.rows[1] = { memberInfo = { guid = m.guid }, Click = function() end }
    w.RunTimers(60)
    pick = rawget(w.env, "GuildyNotePick")
    T.truthy(pick and pick:IsShown(), "the pick lies over the member once Blizzard has the row")
    T.eq(pick:GetAttribute("clickbutton1"), w.rows[1])
    T.eq(w.Height(), 958 * ROW + 80)
    -- minutes later, the window still open: still grown (a deaf list costs nothing to keep)
    w.now = w.now + 300
    w.RunTimers(10)
    T.eq(w.Height(), 958 * ROW + 80)
    -- closed and opened again: Blizzard builds every row its list holds when it shows, so it starts short
    w.env.CommunitiesFrame:Hide()
    w.env.CommunitiesFrame:Show()
    T.truthy(w.Height() < 30 * ROW + 80, ("height %s on opening"):format(tostring(w.Height())))
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

  -- 1.11.2 still froze every 10-15 s (reported 2026-11-23): each hover let a roster update through, and
  -- with the list grown that rebuilt ~1000 rows. The rows themselves heard every roster update too (each
  -- re-reads its member, CommunitiesMemberListEntryMixin:OnEvent). A member's row stays usable without
  -- either: Blizzard's member panel reads the member afresh on its own.
  T.it("does not rebuild the list while the mouse goes over members it has rows for", function()
    local w = World(958)
    rawset(w.env.UIParent, "GetEffectiveScale", function() return 1 end)
    local m = w.ns.Roster.Members()[10]
    w.rows[1] = { memberInfo = { guid = m.guid }, Click = function() end }
    w.heard = 0
    for _ = 1, 3 do
      w.ns.UI.Notes.HoverMember(w.Owner(m), m)
      w.RunTimers()
      w.Fire("GUILD_ROSTER_UPDATE", true)
      w.now = w.now + 20
    end
    T.eq(w.heard, 0)
  end)

  T.it("lets one roster update through when a member has no row in the grown list, then not again for a while", function()
    local w = World(958)
    rawset(w.env.UIParent, "GetEffectiveScale", function() return 1 end)
    local m = w.ns.Roster.Members()[10]
    w.heard = 0
    w.RunTimers(60) -- fully grown, and still no row for m (a member who joined since the list was built)
    w.ns.UI.Notes.HoverMember(w.Owner(m), m)
    for _ = 1, 3 do w.Fire("GUILD_ROSTER_UPDATE", true) end
    T.eq(w.heard, 1)
    w.RunTimers(60) -- (rebuilt short, grown again)
    w.now = w.now + 3
    w.ns.UI.Notes.HoverMember(w.Owner(m), m)
    w.RunTimers(5)
    w.Fire("GUILD_ROSTER_UPDATE", true)
    T.eq(w.heard, 1)
    w.now = w.now + 20
    w.ns.UI.Notes.HoverMember(w.Owner(m), m)
    w.Fire("GUILD_ROSTER_UPDATE", true)
    w.Fire("GUILD_ROSTER_UPDATE", true)
    T.eq(w.heard, 2)
  end)

  T.it("keeps the rows of a big guild's grown list from hearing roster updates", function()
    local w = World(958)
    rawset(w.env.UIParent, "GetEffectiveScale", function() return 1 end)
    local m = w.ns.Roster.Members()[10]
    local rowHeard = 0
    local function BlizzardRow(member)
      local row = w.env.CreateFrame("Button")
      row.memberInfo = { guid = member.guid }
      row:SetScript("OnShow", function(self) self:RegisterEvent("GUILD_ROSTER_UPDATE") end)
      row:SetScript("OnEvent", function(_, event) if event == "GUILD_ROSTER_UPDATE" then rowHeard = rowHeard + 1 end end)
      row:Show()
      return row
    end
    w.ns.UI.Notes.HoverMember(w.Owner(m), m)
    for i = 1, 3 do w.rows[i] = BlizzardRow(w.ns.Roster.Members()[9 + i]) end
    w.RunTimers()
    w.Fire("GUILD_ROSTER_UPDATE", true)
    T.eq(rowHeard, 0)
    -- Blizzard's scroll box hands a row out again (hidden and shown: it registers again)
    w.rows[2]:Hide()
    w.rows[2]:Show()
    w.Fire("GUILD_ROSTER_UPDATE", true)
    T.eq(rowHeard, 0)
  end)

  T.it("leaves a small guild's list hearing every roster update, as before", function()
    local w = World(120)
    w.heard = 0
    for _ = 1, 3 do w.Fire("GUILD_ROSTER_UPDATE", true) end
    T.eq(w.heard, 3)
  end)

  T.it("/guildy biglist makes a small guild's list work as a big guild's, and back", function()
    local w = World(120)
    w.ns.UI.Notes.ToggleBigTest()
    w.RunTimers()
    w.heard = 0
    w.Fire("GUILD_ROSTER_UPDATE", true)
    T.eq(w.heard, 0)
    w.ns.UI.Notes.ToggleBigTest()
    w.RunTimers()
    w.Fire("GUILD_ROSTER_UPDATE", true)
    T.eq(w.heard, 1)
    T.eq(w.Height(), 120 * ROW + 80)
  end)

  T.it("builds a big guild's deaf list anew once when asked (/guildy stress changed its members)", function()
    local w = World(958)
    w.heard = 0
    w.ns.UI.Notes.Rebuild()
    w.Fire("GUILD_ROSTER_UPDATE", true)
    w.Fire("GUILD_ROSTER_UPDATE", true)
    T.eq(w.heard, 1)
  end)

  -- a rebuild makes every row the list holds anew: the list waits short for it, then grows again
  T.it("keeps a big guild's list short while a rebuild is let through, and grows it after", function()
    local w = World(958)
    w.RunTimers(60)
    w.ns.UI.Notes.Rebuild()
    w.RunTimers(60)
    T.truthy(w.Height() < 30 * ROW + 80, ("height %s while waiting"):format(tostring(w.Height())))
    w.Fire("GUILD_ROSTER_UPDATE", true)
    w.RunTimers(60)
    T.eq(w.Height(), 958 * ROW + 80)
  end)
end)
