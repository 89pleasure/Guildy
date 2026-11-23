local T = ...
local ns = T.pureNs()
local Names, Store = ns.Names, ns.Store

T.describe("Names", function()
  T.it("joins Forever first and last name", function()
    T.eq(Names.Key("Ranfredo-Blanko"), Names.Key("ranfredo blanko"))
  end)
  T.it("drops a realm suffix after a full name", function()
    T.eq(Names.Key("Ran Fred-Realm"), "ran fred")
  end)
  T.it("lowercases umlauts", function()
    T.truthy(Names.Same("JÖRG Mü", "jörg mü"))
  end)
  T.it("builds server names for slash commands", function()
    T.eq(Names.ToServer("Xii Lightspark"), "Xii-Lightspark")
    T.eq(Names.ToServer("  Xii   Lightspark "), "Xii-Lightspark")
    T.eq(Names.ToServer("Xii-Lightspark"), "Xii-Lightspark")
    T.eq(Names.ToServer("Solo"), "Solo")
    T.eq(Names.ToServer(nil), "")
  end)
  T.it("handles nil", function()
    T.eq(Names.Key(nil), "")
  end)
  -- Reported 2026-11-23 from a guild of 958: every roster scan keyed every member anew, 2.3 of 3.7 ms and
  -- 615 of 1519 kB of a scan (luajit tests/bench.lua --members 958). The same name keys from memory.
  T.it("keys a name it keyed before without new garbage", function()
    local names = {}
    for i = 1, 958 do names[i] = ("Bärbel%d Sonnenschein%d"):format(i, i % 50) end
    for _, name in ipairs(names) do Names.Key(name) end
    collectgarbage()
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _, name in ipairs(names) do Names.Key(name) end
    local kb = collectgarbage("count") - before
    collectgarbage("restart")
    T.truthy(kb < 20, ("a second pass allocated %.0f kB"):format(kb))
    T.eq(Names.Key("Bärbel7 Sonnenschein7"), "bärbel7 sonnenschein7")
    T.eq(Names.Key("JÖRG-Mü"), "jörg mü")
  end)
  -- the members list lowers every name on every sort (Core/Search.lua), one redraw per roster change
  T.it("lowers a text it lowered before without new garbage", function()
    local names = {}
    for i = 1, 958 do names[i] = ("Ölaf%d Sonnenschein"):format(i) end
    for _, name in ipairs(names) do Names.Lower(name) end
    collectgarbage()
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _, name in ipairs(names) do Names.Lower(name) end
    local kb = collectgarbage("count") - before
    collectgarbage("restart")
    T.truthy(kb < 20, ("a second pass allocated %.0f kB"):format(kb))
    T.eq(Names.Lower("Ölaf7 SONNENSCHEIN"), "ölaf7 sonnenschein")
    T.eq(Names.Lower(nil), "")
  end)
  T.it("keeps its memory of keys bounded", function()
    for i = 1, Names.KEY_MEMORY * 3 do Names.Key("Name" .. i) end
    T.truthy(Names.KeyMemorySize() <= Names.KEY_MEMORY)
    T.eq(Names.Key("Name1"), "name1")
  end)
  T.it("gives an empty name for secret unit names without inspecting them", function()
    local secret = setmetatable({}, { __eq = function() error("secret value compared") end,
      __index = function() error("secret value inspected") end })
    local old = rawget(_G, "issecretvalue")
    local asked = 0
    _G.issecretvalue = function(v) asked = asked + 1; return rawequal(v, secret) end
    local ok, result = pcall(Names.FromUnit, secret, "Blanko")
    local ok2, result2 = pcall(Names.FromUnit, "Ranfredo", secret)
    _G.issecretvalue = old
    T.truthy(ok)
    T.eq(result, "")
    T.truthy(ok2)
    T.eq(result2, "Ranfredo")
    T.truthy(asked >= 2) -- the secret check runs (real secret names have type "string")
    T.eq(Names.FromUnit("Ranfredo", "Blanko"), "Ranfredo Blanko")
  end)
end)

T.describe("Store", function()
  T.it("fills defaults", function()
    local db = Store.Init(nil)
    T.eq(db.settings.activityDays, 30)
    T.eq(db.settings.share, true)
    T.eq(db.guilds, {})
  end)
  T.it("keeps existing settings", function()
    T.eq(Store.Init({ version = 1, settings = { activityDays = 90 } }).settings.activityDays, 90)
    T.eq(Store.Init({ settings = { activityDays = false } }).settings.activityDays, false)
  end)
  T.it("creates members by key and prunes", function()
    local db = Store.Init(nil)
    local guild = Store.Guild(db, "Murloc Mafia@x")
    local m = Store.Member(guild, "Ranfredo-Blanko")
    T.eq(m.name, "Ranfredo Blanko")
    T.truthy(Store.Member(guild, "ranfredo blanko") == m)
    Store.Member(guild, "Other One")
    T.eq(Store.Prune(guild, { ["ranfredo blanko"] = true }), 1)
    T.eq(guild.members["other one"], nil)
  end)
end)
