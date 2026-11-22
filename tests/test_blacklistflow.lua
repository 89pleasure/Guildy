-- The blacklist between Guildy users in the stubbed client (tests/wow.lua): adding sends one BL message,
-- removals need an officer, relayed lists are checked against the receiver's roster, and a summary that
-- knows less gets the whole list once.
-- Roster: Ran Fred (the player) and Makira Farron are rank 1 "Offizier", Au Tsch rank 2 "Haifutter".
local T = ...

local clock = 1000
local now = 1700000000
local sent = {}
local officerOrders = { [1] = true, [2] = true } -- rank order (rank index + 1) whose flags allow officer chat

local function Setup(env)
  env.GetTime = function() return clock end
  env.GetServerTime = function() return now end
  env.C_ChatInfo.SendAddonMessage = function(_, text) sent[#sent + 1] = text end
  env.C_GuildInfo.GuildControlGetRankFlags = function(order) return { true, true, officerOrders[order] == true } end
end
local world = dofile(T.testsDir .. "/wow.lua")(T, { setup = Setup })
local env, ns, errors = world.env, world.ns, world.errors
local Fire, RunTimers = world.Fire, world.RunTimers
local P = ns.Protocol

local function SendAll()
  for _ = 1, 200 do
    if ns.Sync.Waiting() == 0 then return end
    clock = clock + 20
    ns.Sync.Pump()
  end
end

-- The messages of a kind sent since the last call
local function Messages(kind)
  SendAll()
  local assembler, found = P.NewAssembler(), {}
  for _, part in ipairs(sent) do
    local payload = P.AddPart(assembler, "x", part, 0)
    local envelope = payload and P.Decode(payload)
    if envelope and envelope.t == kind then found[#found + 1] = envelope.d end
  end
  sent = {}
  return found
end

local msg = 0
local function Receive(kind, data, sender, version)
  msg = msg + 1
  for _, part in ipairs(P.Chunk("b" .. msg, P.Encode(kind, data, version))) do
    Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", sender)
  end
end

T.describe("Blacklist between Guildy users", function()
  Fire("ADDON_LOADED", "Guildy")
  Fire("PLAYER_LOGIN")
  Fire("GUILD_ROSTER_UPDATE")
  RunTimers()
  Messages("BL")

  T.it("knows officers by the flags of their rank", function()
    T.eq(ns.Roster.IsOfficer("Makira Farron"), true)
    T.eq(ns.Roster.IsOfficer("Au Tsch"), false)
    T.eq(ns.Roster.IsOfficer("Niemand Hier"), false)
    -- without the flags: guild master and the rank below
    local flags = env.C_GuildInfo.GuildControlGetRankFlags
    env.C_GuildInfo.GuildControlGetRankFlags = nil
    T.eq(ns.Roster.IsOfficer("Makira Farron"), true)
    T.eq(ns.Roster.IsOfficer("Au Tsch"), false)
    env.C_GuildInfo.GuildControlGetRankFlags = flags
  end)

  T.it("adds a name and sends one BL message", function()
    local entry = ns.GameBlacklist.Add("Krag Eisenzahn", "kos", "campt den Friedhof")
    T.truthy(entry, "added")
    T.eq(ns.GuildData().blacklist["krag eisenzahn"].a, "Ran Fred")
    local messages = Messages("BL")
    T.eq(#messages, 1)
    T.eq(messages[1].e[1].n, "Krag Eisenzahn")
    T.eq(messages[1].e[1].r, "campt den Friedhof")
  end)

  T.it("refuses guild members", function()
    local entry, err = ns.GameBlacklist.Add("Au Tsch", "insult")
    T.eq(entry, nil)
    T.eq(err, "protected")
    T.eq(#Messages("BL"), 0)
  end)

  T.it("refuses removal by a non-officer", function()
    officerOrders[2] = false
    T.eq(ns.GameBlacklist.CanRemove(), false)
    local entry, err = ns.GameBlacklist.Remove("Krag Eisenzahn")
    T.eq(entry, nil)
    T.eq(err, "officer")
    officerOrders[2] = true
    T.eq(ns.GameBlacklist.CanRemove(), true)
    T.eq(#Messages("BL"), 0)
  end)

  T.it("takes entries from others and fires BLACKLIST", function()
    local fired = 0
    ns.On("BLACKLIST", function() fired = fired + 1 end)
    Receive("BL", { e = { { n = "Bodo Langfinger", t = "ninja", r = "Bedarf auf alles", a = "Au Tsch", at = now - 50 } } },
      "Au-Tsch")
    T.eq(ns.GuildData().blacklist["bodo langfinger"].t, "ninja")
    T.truthy(fired > 0, "fired")
  end)

  T.it("takes a relayed removal named by an officer", function()
    Receive("BL", { e = { { n = "Bodo Langfinger", t = "ninja", a = "Au Tsch", at = now - 50, x = now - 10,
      xb = "Makira Farron" } } }, "Au-Tsch")
    T.eq(ns.Blacklist.IsLive(ns.GuildData().blacklist["bodo langfinger"]), false)
  end)

  T.it("drops a relayed removal named by a non-officer", function()
    Receive("BL", { e = { { n = "Krag Eisenzahn", t = "kos", a = "Ran Fred", at = now, x = now + 5, xb = "Au Tsch" } } },
      "Au-Tsch")
    T.eq(ns.Blacklist.IsLive(ns.GuildData().blacklist["krag eisenzahn"]), true)
  end)

  T.it("sends the removal of an officer", function()
    local entry = ns.GameBlacklist.Remove("Krag Eisenzahn")
    T.eq(entry.xb, "Ran Fred")
    local messages = Messages("BL")
    T.eq(#messages, 1)
    T.eq(messages[1].e[1].x, now)
  end)

  T.it("names the list in the summary", function()
    ns.Sync.SendSummary()
    RunTimers()
    local sums = Messages("SUM")
    T.truthy(#sums >= 1, "summary sent")
    T.eq(sums[1].x, ns.Blacklist.Digest(ns.GuildData().blacklist))
  end)

  T.it("offers the list once per pair of fingerprints", function()
    Receive("SUM", { d = {}, x = { n = 0, m = 0, s = 0 } }, "Au-Tsch", "1.9.11")
    RunTimers()
    local lists = Messages("BL")
    T.eq(#lists, 1)
    T.eq(#lists[1].e, 2)
    Receive("SUM", { d = {}, x = { n = 0, m = 0, s = 0 } }, "Au-Tsch", "1.9.11")
    RunTimers()
    T.eq(#Messages("BL"), 0)
  end)

  T.it("gives no offer to a summary that knows as much", function()
    Receive("SUM", { d = {}, x = ns.Blacklist.Digest(ns.GuildData().blacklist) }, "Makira-Farron", "1.9.11")
    RunTimers()
    T.eq(#Messages("BL"), 0)
  end)

  T.it("an older Guildy's summary without x gets no offer", function()
    Receive("SUM", { d = {} }, "Makira-Farron", "1.9.10")
    RunTimers()
    T.eq(#Messages("BL"), 0)
    T.eq(errors, {})
  end)
end)
