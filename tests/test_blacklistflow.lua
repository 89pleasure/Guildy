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

T.describe("Seeing blacklisted players", function()
  local lines, sounds, tipLines = {}, 0, {}
  local units = {
    nameplate1 = { "Vexa", "Nachtschatten", "WARLOCK", 58, "Horde" },
    target = { "Vexa", "Nachtschatten", "WARLOCK", 58, "Horde" },
    party1 = { "Gerd", "Großmaul", "PALADIN", 44, "Alliance" },
    NPC = { "Fenna", "Falschgold", "MAGE", 37, "Alliance" },
    nameplate2 = { "Au", "Tsch", "ROGUE", 21, "Alliance" },
  }
  env.UnitName = function(unit)
    local u = units[unit]
    if u then return u[1], u[2] end
    return "Ran", "Fred"
  end
  env.UnitExists = function(unit) return units[unit] ~= nil end
  env.UnitIsPlayer = function(unit) return units[unit] ~= nil end
  env.UnitClass = function(unit) return "x", units[unit] and units[unit][3] or "MAGE" end
  env.UnitLevel = function(unit) return units[unit] and units[unit][4] or 33 end
  env.UnitFactionGroup = function(unit) return units[unit] and units[unit][5] or "Alliance" end
  env.IsInRaid = function() return false end
  env.GetNumGroupMembers = function() return 2 end
  env.SOUNDKIT = { RAID_WARNING = 8959 }
  env.PlaySound = function() sounds = sounds + 1 end
  rawset(env.DEFAULT_CHAT_FRAME, "AddMessage", function(_, text) lines[#lines + 1] = text end)
  local function Reset() lines, sounds = {}, 0 end

  local book = ns.GameBlacklist.Book()
  ns.Blacklist.Add(book, "Vexa Nachtschatten", "kos", "tötet Leute unter 30", "Makira Farron", now, ns.GameBlacklist.Ctx())
  ns.Blacklist.Add(book, "Gerd Großmaul", "insult", "beleidigt im Handel", "Makira Farron", now, ns.GameBlacklist.Ctx())
  ns.Blacklist.Add(book, "Fenna Falschgold", "scam", nil, "Makira Farron", now, ns.GameBlacklist.Ctx())
  ns.Blacklist.Add(book, "Jule Plappermaul", "insult", nil, "Makira Farron", now, ns.GameBlacklist.Ctx())
  -- Au Tsch is in the guild now: an old entry from before
  book["au tsch"] = { n = "Au Tsch", t = "insult", a = "Makira Farron", at = now - 9999 }

  T.it("warns once per 5 minutes", function()
    Reset()
    Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    Fire("PLAYER_TARGET_CHANGED")
    T.eq(#lines, 1)
    T.eq(sounds, 1)
    T.truthy(lines[1]:find("Vexa Nachtschatten", 1, true), "names the player")
    T.truthy(lines[1]:find("tötet Leute unter 30", 1, true), "gives the reason")
    now = now + 300
    Fire("PLAYER_TARGET_CHANGED")
    T.eq(#lines, 2)
    T.eq(sounds, 2)
  end)

  T.it("fills class, level and faction from a seen unit", function()
    local entry = ns.GameBlacklist.Book()["vexa nachtschatten"]
    T.eq(entry.c, "WARLOCK")
    T.eq(entry.l, 58)
    T.eq(entry.f, "H")
  end)

  T.it("warns on group, whisper, invite and trade", function()
    Reset()
    Fire("GROUP_ROSTER_UPDATE")
    T.eq(#lines, 1)
    T.truthy(lines[1]:find("Gerd Großmaul", 1, true), "group")
    Fire("TRADE_SHOW")
    T.eq(#lines, 2)
    T.truthy(lines[2]:find("Fenna Falschgold", 1, true), "trade")
    Fire("CHAT_MSG_WHISPER", "hallo", "Jule-Plappermaul")
    T.eq(#lines, 3)
    now = now + 300
    Fire("PARTY_INVITE_REQUEST", "Jule Plappermaul")
    T.eq(#lines, 4)
  end)

  T.it("stays quiet for a name now in the guild", function()
    Reset()
    Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    T.eq(#lines, 0)
    T.eq(ns.GameBlacklist.Find("Au Tsch"), nil)
    T.truthy(ns.GameBlacklist.Find("Vexa Nachtschatten"), "listed")
  end)

  T.it("ignores a secret sender", function()
    Reset()
    Fire("CHAT_MSG_WHISPER", "hallo", world.SECRET)
    Fire("PARTY_INVITE_REQUEST", world.SECRET)
    T.eq(#lines, 0)
    T.eq(errors, {})
  end)

  T.it("respects the option", function()
    Reset()
    now = now + 600
    ns.Settings().blacklistAlert = false
    Fire("PLAYER_TARGET_CHANGED")
    T.eq(#lines, 0)
    ns.Settings().blacklistAlert = true
    Fire("PLAYER_TARGET_CHANGED")
    T.eq(#lines, 1)
    T.eq(ns.Store.DEFAULTS.blacklistAlert, true)
  end)

  T.it("adds the tooltip line", function()
    rawset(env.GameTooltip, "GetUnit", function() return "Vexa", "target" end)
    rawset(env.GameTooltip, "AddLine", function(_, text) tipLines[#tipLines + 1] = text end)
    local hook = env.GameTooltip:GetScript("OnTooltipSetUnit")
    T.truthy(hook, "hooked")
    hook(env.GameTooltip)
    T.eq(tipLines[1], ns.L.BL_TOOLTIP:format(ns.L.BL_TAG_KOS))
    T.eq(tipLines[2], "tötet Leute unter 30")
    T.eq(errors, {})
  end)
end)
