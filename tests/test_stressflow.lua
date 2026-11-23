-- /guildy stress (Core/Stress.lua): a small guild as a guild of a thousand, in Guildy's roster and in
-- what Blizzard's member list reads; nothing of the made-up members is kept or sent.
local T = ...

local function World(count)
  local w = { now = 1000 }
  local roster = {}
  for i = 1, count do
    roster[i] = { ("Real%s-Realm"):format(string.char(65 + i % 26, 97 + math.floor(i / 26) % 26)),
      "Mitglied", 3, 60, "Krieger", "Westfall", "Alch/Kräuter", "", i <= 5, 0, "WARRIOR", nil, nil, false, nil, nil,
      ("Player-1-%08X"):format(i) }
  end
  local world = dofile(T.testsDir .. "/wow.lua")(T, { roster = roster, setup = function(env)
    env.GetTime = function() return w.now end
    local ids = {}
    for i = 1, count do ids[i] = i end
    env.C_Club = setmetatable({
      GetGuildClubId = function() return 7 end,
      GetClubMembers = function() local copy = {} for i, id in ipairs(ids) do copy[i] = id end return copy end,
      GetMemberInfo = function(_, id) return ids[id] and { memberId = id, name = roster[id][1], guid = roster[id][17] } or nil end,
    }, { __index = function() return function() return nil end end })
  end })
  w.env, w.ns, w.Fire, w.RunTimers = world.env, world.ns, world.Fire, world.RunTimers
  w.Fire("ADDON_LOADED", "Guildy")
  w.Fire("PLAYER_LOGIN")
  w.Fire("GUILD_ROSTER_UPDATE")
  w.RunTimers()
  return w
end

local function Scan(w)
  w.now = w.now + 30
  w.Fire("GUILD_ROSTER_UPDATE")
  w.RunTimers()
end

T.describe("/guildy stress", function()
  T.it("makes a guild of 20 a guild of 1000 in Guildy's roster, with names and guids of their own", function()
    local w = World(20)
    w.ns.Stress.Toggle("1000")
    Scan(w)
    local members = w.ns.Roster.Members()
    T.eq(#members, 1000)
    local keys, guids = {}, {}
    for _, m in ipairs(members) do
      T.truthy(not keys[m.key], "a name twice: " .. m.key)
      T.truthy(not guids[m.guid], "a guid twice: " .. tostring(m.guid))
      keys[m.key], guids[m.guid] = true, true
    end
  end)

  T.it("keeps nothing of the made-up members and sends nothing while on", function()
    local w = World(20)
    local guild = w.ns.GuildData()
    local before = 0
    for _ in pairs(guild.members) do before = before + 1 end
    w.ns.Stress.Toggle("1000")
    Scan(w)
    local after = 0
    for _ in pairs(guild.members) do after = after + 1 end
    T.eq(after, before)
    w.ns.Sync.SendSummary()
    T.eq(w.ns.Sync.Waiting(), 0)
  end)

  T.it("gives Blizzard's member list the made-up members too, with the guids Guildy has", function()
    local w = World(20)
    w.ns.Stress.Toggle("1000")
    Scan(w)
    local ids = w.env.C_Club.GetClubMembers(7)
    T.eq(#ids, 1000)
    local info = w.env.C_Club.GetMemberInfo(7, ids[500])
    T.eq(info.guid, w.ns.Roster.Members()[500].guid)
    T.truthy(info.name ~= w.env.C_Club.GetMemberInfo(7, 1).name)
  end)

  T.it("goes back to the real guild when switched off", function()
    local w = World(20)
    w.ns.Stress.Toggle("1000")
    Scan(w)
    w.ns.Stress.Toggle()
    Scan(w)
    T.eq(#w.ns.Roster.Members(), 20)
    T.eq(#w.env.C_Club.GetClubMembers(7), 20)
  end)
end)
