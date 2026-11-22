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

  T.it("refuses removal of someone else's entry by a non-officer", function()
    Receive("BL", { e = { { n = "Zora Kalt", t = "other", a = "Au Tsch", at = now - 60 } } }, "Au-Tsch")
    Messages("BL")
    officerOrders[2] = false
    T.eq(ns.GameBlacklist.CanRemove(), false)
    local book = ns.GameBlacklist.Book()
    T.eq(ns.GameBlacklist.CanRemoveEntry(book["zora kalt"]), false)
    T.eq(ns.GameBlacklist.CanRemoveEntry(book["krag eisenzahn"]), true) -- added by the player
    local entry, err = ns.GameBlacklist.Remove("Zora Kalt")
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

  T.it("holds messages until the roster is there", function()
    local members = ns.Roster.Members
    ns.Roster.Members = function() return {} end
    Receive("BL", { e = { { n = "Ilka Sturm", t = "scam", a = "Au Tsch", at = now - 40 } } }, "Au-Tsch")
    T.eq(ns.GuildData().blacklist["ilka sturm"], nil)
    ns.Roster.Members = members
    ns.Fire("ROSTER")
    T.eq(ns.GuildData().blacklist["ilka sturm"].t, "scam")
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
    T.eq(#lists[1].e, 4)
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

T.describe("The Blacklist tab", function()
  local function View()
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("blacklist")
    return ns.UI.TabView("blacklist")
  end

  T.it("opens and lists entries newest first", function()
    local view = View()
    T.eq(ns.UI.Current(), "blacklist")
    local items = view.List.items
    T.truthy(#items >= 4, "entries listed")
    for i = 2, #items do
      if items[i].entry and items[i - 1].entry and not items[i].removed and not items[i - 1].removed then
        T.truthy(ns.Blacklist.EventTime(items[i - 1].entry) >= ns.Blacklist.EventTime(items[i].entry), "newest first")
      end
    end
    T.eq(errors, {})
  end)

  T.it("marks the kind with the dot texture, not a glyph the font may lack", function()
    local view = View()
    local row = view.List.rows[1]
    T.truthy(row, "first row built")
    local text = row.Cells.kind:GetText()
    T.eq(text:find("■", 1, true), nil)
    T.truthy(text:find("Textures\\Dot", 1, true), "dot texture")
  end)

  T.it("keeps the row button bright while the mouse is on it", function()
    local view = View()
    local row = view.List.rows[1]
    local alpha
    rawset(row.Action, "SetAlpha", function(_, a) alpha = a end)
    row:GetScript("OnEnter")(row)
    T.eq(alpha, 1)
    row:GetScript("OnLeave")(row)
    row.Action:GetScript("OnEnter")(row.Action)
    T.eq(alpha, 1)
    row.Action:GetScript("OnLeave")(row.Action)
    T.eq(alpha, 0.45)
    rawset(row.Action, "SetAlpha", nil)
  end)

  T.it("greys a name that is now in the guild", function()
    local view = View()
    local found
    for _, item in ipairs(view.List.items) do
      if item.entry and item.entry.n == "Au Tsch" then found = item end
    end
    T.truthy(found, "listed")
    T.eq(found.quiet, true)
  end)

  T.it("filters by kind, reason and text", function()
    local view = View()
    view:SetKind("insult")
    for _, item in ipairs(view.List.items) do
      if item.entry then T.eq(item.entry.t, "insult") end
    end
    view:SetKind(nil)
    view.NoReasonCheck:SetChecked(true)
    view.NoReasonCheck:GetScript("OnClick")(view.NoReasonCheck)
    for _, item in ipairs(view.List.items) do
      if item.entry then T.eq(item.entry.r, nil) end
    end
    view.NoReasonCheck:SetChecked(false)
    view.NoReasonCheck:GetScript("OnClick")(view.NoReasonCheck)
    view.Search:SetText("vexa")
    view.Search:GetScript("OnTextChanged")(view.Search)
    T.eq(#view.List.items, 1)
    view.Search:SetText("")
    view.Search:GetScript("OnTextChanged")(view.Search)
  end)

  T.it("shows removed entries only to officers with the box ticked", function()
    local view = View()
    local function Removed()
      local n = 0
      for _, item in ipairs(view.List.items) do if item.removed then n = n + 1 end end
      return n
    end
    T.eq(Removed(), 0)
    view.RemovedCheck:SetChecked(true)
    view.RemovedCheck:GetScript("OnClick")(view.RemovedCheck)
    T.truthy(Removed() >= 1, "removed shown")
    T.eq(view.canRemove, true)
    officerOrders[2] = false
    view:Refresh()
    T.eq(view.canRemove, false)
    T.eq(Removed(), 0)
    officerOrders[2] = true
    view.RemovedCheck:SetChecked(false)
    view.RemovedCheck:GetScript("OnClick")(view.RemovedCheck)
  end)

  T.it("adds from the add row", function()
    local view = View()
    view:OpenAdd()
    T.eq(view.AddRow:IsShown(), true)
    view.AddName:SetText("Ruk Knochenbrecher")
    view:SetAddKind("kos")
    view.AddReason:SetText("jagt Sammler in Felwood")
    view:Submit()
    T.eq(view.AddRow:IsShown(), false)
    local entry = ns.GameBlacklist.Book()["ruk knochenbrecher"]
    T.eq(entry.t, "kos")
    T.eq(entry.r, "jagt Sammler in Felwood")
    T.eq(view.List.items[1].entry.n, "Ruk Knochenbrecher")
  end)

  T.it("Add takes the name from the search box and the kind from the filter", function()
    local view = View()
    view.Search:SetText("Leckk Eyer")
    view.Search:GetScript("OnTextChanged")(view.Search)
    view:SetKind("insult")
    view.AddButton:GetScript("OnClick")(view.AddButton)
    T.eq(view.AddRow:IsShown(), true)
    T.eq(view.AddName:GetText(), "Leckk Eyer")
    T.eq(view.addKind, "insult")
    -- the list shows everything again, the search was only the name
    T.eq(view.Search:GetText(), "")
    T.eq(view.kind, nil)
    view.AddReason:SetText("beleidigt im Handelschannel")
    view:Submit()
    T.eq(ns.GameBlacklist.Book()["leckk eyer"].r, "beleidigt im Handelschannel")
    T.eq(ns.GameBlacklist.Book()["leckk eyer"].t, "insult")
  end)

  T.it("edits an entry with a click on its row", function()
    local view = View()
    local row
    for _, r in pairs(view.List.rows) do
      if r.item and r.item.entry and r.item.entry.n == "Leckk Eyer" then row = r end
    end
    T.truthy(row, "row of the entry")
    row:GetScript("OnMouseUp")(row, "LeftButton")
    T.eq(view.AddRow:IsShown(), true)
    T.eq(view.AddName:GetText(), "Leckk Eyer")
    T.eq(view.AddReason:GetText(), "beleidigt im Handelschannel")
    T.eq(view.addKind, "insult")
    T.eq(view.AddSubmit:GetText(), ns.L.BL_SAVE)
    view:SetAddKind("scam")
    view.AddReason:SetText("will Gold für nichts")
    view:Submit()
    local entry = ns.GameBlacklist.Book()["leckk eyer"]
    T.eq(entry.t, "scam")
    T.eq(entry.r, "will Gold für nichts")
    -- a new entry again says Add
    view:OpenAdd()
    T.eq(view.AddSubmit:GetText(), ns.L.BL_ADD)
    view:CloseAdd()
  end)

  T.it("renames an own entry instead of making a second one", function()
    local view = View()
    officerOrders[2] = false
    view:OpenAdd("Hakuna Markarta", nil, "kos")
    view:Submit()
    view:OpenAdd("Hakuna Markarta", nil, "kos", nil)
    T.eq(view.editing, "Hakuna Markarta")
    view.AddName:SetText("Hakuna Matata")
    view:Submit()
    local book = ns.GameBlacklist.Book()
    T.eq(ns.Blacklist.IsLive(book["hakuna markarta"]), false)
    T.eq(book["hakuna markarta"].xb, "Ran Fred")
    T.eq(ns.Blacklist.IsLive(book["hakuna matata"]), true)
    T.eq(book["hakuna matata"].t, "kos")
    officerOrders[2] = true
  end)

  T.it("refuses to rename someone else's entry for a non-officer", function()
    local view = View()
    local printed = {}
    rawset(env.DEFAULT_CHAT_FRAME, "AddMessage", function(_, text) printed[#printed + 1] = text end)
    officerOrders[2] = false
    view:OpenAdd("Zora Kalt", nil, "other")
    view.AddName:SetText("Zora Kälte")
    view:Submit()
    local book = ns.GameBlacklist.Book()
    T.eq(book["zora kälte"], nil)
    T.eq(ns.Blacklist.IsLive(book["zora kalt"]), true)
    T.truthy(printed[1] and printed[1]:find(ns.L.BL_ERR_RENAME, 1, true), "says why")
    view:CloseAdd()
    officerOrders[2] = true
  end)

  T.it("shows the remove button on own entries for a non-officer", function()
    local view = View()
    officerOrders[2] = false
    local function RowOf(name)
      view.Search:SetText(name)
      view.Search:GetScript("OnTextChanged")(view.Search)
      for _, r in pairs(view.List.rows) do
        local e = r.item and r.item.entry
        if e and e.n == name then return r end
      end
    end
    local own = RowOf("Hakuna Matata")
    T.truthy(own, "own row")
    T.eq(own.Action:IsShown(), true)
    local other = RowOf("Zora Kalt")
    T.truthy(other, "other row")
    T.eq(other.Action:IsShown(), false)
    view.Search:SetText("")
    view.Search:GetScript("OnTextChanged")(view.Search)
    officerOrders[2] = true
    view:Refresh()
  end)

  T.it("refuses a guild member from the add row with the message", function()
    local view = View()
    local printed = {}
    rawset(env.DEFAULT_CHAT_FRAME, "AddMessage", function(_, text) printed[#printed + 1] = text end)
    view:OpenAdd()
    view.AddName:SetText("Makira Farron")
    view:Submit()
    T.eq(view.AddRow:IsShown(), true)
    T.truthy(printed[1] and printed[1]:find(ns.L.BL_ERR_PROTECTED, 1, true), "says why")
    view:CloseAdd()
  end)

  T.it("/guildy bl opens the add row with the target", function()
    env.SlashCmdList.GUILDY("bl")
    local view = ns.UI.TabView("blacklist")
    T.eq(ns.UI.Current(), "blacklist")
    T.eq(view.AddRow:IsShown(), true)
    T.eq(view.AddName:GetText(), "Vexa Nachtschatten")
    view:CloseAdd()
    env.SlashCmdList.GUILDY("bl Lirra Dunkelquell")
    T.eq(view.AddName:GetText(), "Lirra Dunkelquell")
    view:CloseAdd()
    T.eq(errors, {})
  end)
end)

T.describe("Right-click entry", function()
  local callbacks = {}
  env.Menu = { ModifyMenu = function(tag, fn) callbacks[tag] = fn end }
  ns.GameBlacklist.HookMenu()

  local function Open(tag, context)
    local buttons = {}
    local root = {
      CreateDivider = function() end,
      CreateButton = function(_, text, onClick) buttons[#buttons + 1] = { text = text, onClick = onClick } end,
    }
    callbacks[tag](nil, root, context)
    return buttons
  end

  T.it("adds the menu entry for other players", function()
    T.truthy(callbacks.MENU_UNIT_PLAYER and callbacks.MENU_UNIT_ENEMY_PLAYER, "hooked")
    local buttons = Open("MENU_UNIT_ENEMY_PLAYER", { name = "Grom", server = "Blutfaust" })
    T.eq(#buttons, 1)
    T.eq(buttons[1].text, ns.L.BL_MENU)
    buttons[1].onClick()
    local view = ns.UI.TabView("blacklist")
    T.eq(view.AddRow:IsShown(), true)
    T.eq(view.AddName:GetText(), "Grom Blutfaust")
    view:CloseAdd()
  end)

  T.it("leaves guild members and the player alone", function()
    T.eq(#Open("MENU_UNIT_PLAYER", { name = "Makira", server = "Farron" }), 0)
    T.eq(#Open("MENU_UNIT_PLAYER", { name = "Ran", server = "Fred" }), 0)
    T.eq(#Open("MENU_UNIT_PLAYER", { name = world.SECRET }), 0)
    T.eq(errors, {})
  end)
end)
