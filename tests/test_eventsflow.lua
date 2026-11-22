-- Guild events in the stubbed client (tests/wow.lua) with a calendar that behaves like the game's: the
-- list, opening an event, answering, creating, and the reminder 30 minutes before (locally, and once in
-- guild chat by the Guildy user with the smallest name key). The player is Ran Fred.
local T = ...

local nowT = { year = 2026, month = 12, monthDay = 4, hour = 19, minute = 0 }
local events = {}       -- the guild's events as the server has them
local openedIndex       -- the event the client holds open
local calls = {}        -- C_Calendar calls by name
local created           -- the event being made (CreateGuildSignUpEvent ... AddEvent)
local chat, printed, sent = {}, {}, {}
local calendarShown = false
local selectedIndex

local function Count(name) calls[name] = (calls[name] or 0) + 1 end

local function Setup(env)
  env.C_DateAndTime = { GetCurrentCalendarTime = function() return nowT end }
  env.CanEditGuildEvent = function() return true end
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) printed[#printed + 1] = text end }
  env.C_ChatInfo.SendChatMessage = function(text, kind) chat[#chat + 1] = { text = text, kind = kind } end
  env.C_ChatInfo.SendAddonMessage = function(_, text) sent[#sent + 1] = text end
  env.CalendarFrame = { IsShown = function() return calendarShown end }
  env.EventRegistry = { callbacks = {}, RegisterCallback = function(self, event, fn) self.callbacks[event] = fn end }
  env.CALENDAR_ERROR_EVENT_PASSED = "Dieses Ereignis ist vorbei."
  env.C_Calendar = {
    OpenCalendar = function() Count("OpenCalendar") end,
    SetAbsMonth = function() Count("SetAbsMonth") if env.onSetMonth then env.onSetMonth() end end,
    GetMonthInfo = function() return { month = 11, year = 2026 } end,
    GetNumGuildEvents = function() return #events end,
    GetGuildEventInfo = function(i)
      local e = events[i]
      return e and { eventID = i, year = e.y, month = e.m, monthDay = e.d, weekday = 1, hour = e.h, minute = e.mi,
        eventType = e.type or 4, title = e.title, calendarType = e.calendarType or "GUILD_EVENT", texture = 0,
        inviteStatus = e.status or 7, clubID = 1 }
    end,
    GetGuildEventSelectionInfo = function(i)
      local e = events[i]
      return e and { offsetMonth = 0, monthDay = e.d, eventIndex = i }
    end,
    OpenEvent = function(_, _, index)
      Count("OpenEvent")
      openedIndex = index
      return true
    end,
    GetEventInfo = function()
      local e = events[openedIndex]
      if not e then return nil end
      return { title = e.title, description = e.desc or "", creator = e.creator, eventType = e.type or 4,
        time = { year = e.y, month = e.m, monthDay = e.d, hour = e.h, minute = e.mi }, isLocked = e.locked or false,
        inviteStatus = e.status, inviteType = e.inviteType, calendarType = "GUILD_EVENT" }
    end,
    GetNumInvites = function() local e = events[openedIndex] return e and #(e.invites or {}) or 0 end,
    EventGetInvite = function(i) return events[openedIndex].invites[i] end,
    EventSignUp = function() Count("EventSignUp") events[openedIndex].status = 6 end,
    EventAvailable = function() Count("EventAvailable") events[openedIndex].status = 1 end,
    EventTentative = function() Count("EventTentative") events[openedIndex].status = 8 end,
    EventDecline = function() Count("EventDecline") events[openedIndex].status = 2 end,
    EventGetTextures = function() return {} end,
    CreateGuildSignUpEvent = function() created = {} end,
    EventSetTitle = function(title) created.title = title end,
    EventSetType = function(kind) created.type = kind end,
    EventSetDate = function(m, d, y) created.m, created.d, created.y = m, d, y end,
    EventSetTime = function(h, mi) created.h, created.mi = h, mi end,
    EventSetDescription = function(text) created.desc = text end,
    EventSetLocked = function() created.locked = true end,
    AddEvent = function() Count("AddEvent") end,
    EventCanEdit = function() return env.canEdit end,
    ContextMenuEventCanEdit = function() return env.canEdit end,
    EventClearLocked = function() created.locked = false end,
    UpdateEvent = function()
      Count("UpdateEvent")
      local e = events[openedIndex]
      e.title, e.type, e.y, e.m, e.d, e.h, e.mi, e.desc, e.locked = created.title, created.type, created.y, created.m,
        created.d, created.h, created.mi, created.desc, created.locked
    end,
    ContextMenuSelectEvent = function(_, _, index) selectedIndex = index end,
    ContextMenuEventRemove = function() Count("Remove") table.remove(events, selectedIndex) end,
  }
end

local world = dofile(T.testsDir .. "/wow.lua")(T, { setup = Setup })
local env, ns, errors = world.env, world.ns, world.errors
local Fire, RunTimers = world.Fire, world.RunTimers
local P, GE, E = ns.Protocol, ns.GameEvents, ns.Events

local function Event(title, h, mi, extra)
  local e = { title = title, y = 2026, m = 12, d = 4, h = h, mi = mi }
  for k, v in pairs(extra or {}) do e[k] = v end
  events[#events + 1] = e
  return e
end

local function Reset()
  events, calls, chat, printed, sent, openedIndex, created, calendarShown = {}, {}, {}, {}, {}, nil, nil, false
  nowT.hour, nowT.minute = 19, 0
  GE.Reset()
  env.GuildyDB.eventReminded = nil
end

local function Find(list, pattern)
  for _, entry in ipairs(list) do
    local text = type(entry) == "table" and entry.text or entry
    if text:find(pattern, 1, true) then return text end
  end
end

T.describe("Guild events", function()
  Fire("ADDON_LOADED", "Guildy")
  Fire("PLAYER_LOGIN")
  Fire("GUILD_ROSTER_UPDATE")
  RunTimers()

  T.it("lists the guild's events by start, reading the type in front of a title", function()
    Reset()
    Event("Angeln", 21, 0)
    Event("Schlachtzug: Geschmolzener Kern", 20, 0, { type = 4 })
    Event("Gildennews", 22, 0, { calendarType = "GUILD_ANNOUNCEMENT" })
    local list = GE.List()
    T.eq(#list, 3)
    T.eq(list[1].name, "Geschmolzener Kern")
    T.eq(list[1].kind, "raid")
    T.eq(list[2].kind, "other")
    T.eq(list[3].answerable, false)
    T.eq(list[1].answer, "open")
    T.eq(errors, {})
  end)

  T.it("shows who answered once the event is open", function()
    Reset()
    Event("Kern", 20, 0, { creator = "Makira Farron", invites = {
      { name = "Makira Farron", classFilename = "PRIEST", inviteStatus = 6, modStatus = "CREATOR" },
      { name = "Au Tsch", classFilename = "WARRIOR", inviteStatus = 8 },
      { name = "Ran Fred", classFilename = "MAGE", inviteStatus = 2, inviteIsMine = true },
    } })
    local item = GE.List()[1]
    T.eq(GE.Open(item), true)
    Fire("CALENDAR_OPEN_EVENT", "GUILD_EVENT")
    local detail = GE.Detail(item.key)
    T.eq(detail.counts, { yes = 1, maybe = 1, no = 1, open = 0 })
    T.eq(detail.creator, "Makira Farron")
    T.eq(GE.IsOpen(item.key), true)
    T.eq(errors, {})
  end)

  T.it("answers an event, opening it first when another one is open", function()
    Reset()
    Event("Kern", 20, 0)
    Event("Angeln", 21, 0)
    local list = GE.List()
    GE.Open(list[2])
    Fire("CALENDAR_OPEN_EVENT", "GUILD_EVENT")
    GE.Answer(list[1], "yes")
    T.eq(calls.EventSignUp, nil, "not on the wrong event")
    Fire("CALENDAR_OPEN_EVENT", "GUILD_EVENT")
    T.eq(calls.EventSignUp, 1)
    T.eq(events[1].status, 6)
    T.eq(events[2].status, nil)
    -- invited by name: "available"
    events[2].inviteType = 0
    GE.Open(GE.List()[2])
    Fire("CALENDAR_OPEN_EVENT", "GUILD_EVENT")
    GE.Answer(GE.List()[2], "yes")
    T.eq(calls.EventAvailable, 1)
    T.eq(errors, {})
  end)

  T.it("opens nothing while Blizzard's calendar is shown", function()
    Reset()
    Event("Kern", 20, 0)
    calendarShown = true
    T.eq(GE.Open(GE.List()[1]), false)
    GE.Fill(true)
    RunTimers(2)
    GE.Fill(false)
    T.eq(calls.OpenEvent, nil)
    RunTimers(1) -- the timer still waiting ends the filling
    calendarShown = false
    GE.Fill(true)
    T.eq(calls.OpenEvent, 1)
    GE.Fill(false)
    RunTimers(2)
  end)

  -- the EVR claims sent since the last call
  local function Claims()
    for _ = 1, 50 do
      if ns.Sync.Waiting() == 0 then break end
      ns.Sync.Pump()
    end
    local assembler, found = P.NewAssembler(), {}
    for _, part in ipairs(sent) do
      local payload = P.AddPart(assembler, "x", part, 0)
      local envelope = payload and P.Decode(payload)
      if envelope and envelope.t == "EVR" then found[#found + 1] = envelope.d.k end
    end
    sent = {}
    return found
  end
  local msg = 0
  local function Receive(kind, data, sender)
    msg = msg + 1
    for _, part in ipairs(P.Chunk("e" .. msg, P.Encode(kind, data, "1.11.0"))) do
      Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", sender)
    end
  end
  local function KeyPress() GE.FlushGuild() end

  T.it("has a frame that sees every key press and passes it on", function()
    T.eq(GE.MakeCatcher(), true)
  end)

  T.it("reminds 30 minutes before and posts once in guild chat on the next key press", function()
    Reset()
    Event("Kern", 19, 30)
    GE.Tick()
    local line = Find(printed, "Kern beginnt in 30 Min.")
    T.truthy(line, "local line")
    T.truthy(line:find("|Haddon:Guildy:events|h", 1, true), "with the link to the tab")
    RunTimers(1) -- the wait before the claim
    T.eq(Claims(), { "Kern@" .. E.Stamp(2026, 12, 4, 19, 30) })
    RunTimers(1) -- the two seconds for other claims
    T.eq(#chat, 0, "not from a timer: the game blocks it")
    T.eq(GE.Queued(), 1)
    KeyPress()
    T.eq(chat[1].text, "[Guildy] Kern beginnt in 30 Min. (19:30). Anmelden im Kalender.")
    T.eq(chat[1].kind, "GUILD")
    KeyPress()
    T.eq(#chat, 1, "once")
    printed = {}
    GE.Tick()
    RunTimers()
    T.eq(#printed, 0, "once per character")
  end)

  T.it("stays quiet when a smaller name key claims the same reminder", function()
    Reset()
    Event("Tiefschlund", 19, 30)
    GE.Tick()
    RunTimers(1)
    T.eq(#Claims(), 1)
    Receive("EVR", { k = "Tiefschlund@" .. E.Stamp(2026, 12, 4, 19, 30) }, "Alva Abendrot")
    RunTimers(1)
    KeyPress()
    T.eq(#chat, 0)
  end)

  T.it("still posts when only a larger name key claims", function()
    Reset()
    Event("Tiefschlund 2", 19, 30)
    GE.Tick()
    RunTimers(1)
    Receive("EVR", { k = "Tiefschlund 2@" .. E.Stamp(2026, 12, 4, 19, 30) }, "Zora Zwielicht")
    RunTimers(1)
    KeyPress()
    T.eq(#chat, 1)
  end)

  T.it("does not post when the line shows up in guild chat before the key press", function()
    Reset()
    Event("Baden", 19, 30)
    GE.Tick()
    RunTimers()
    T.eq(GE.Queued(), 1)
    Fire("CHAT_MSG_GUILD", "[Guildy] Baden beginnt in 30 Min. (19:30). Anmelden im Kalender.", "Au Tsch-Forever")
    KeyPress()
    T.eq(#chat, 0)
  end)

  T.it("does not claim when someone claimed first", function()
    Reset()
    Event("Angeln", 19, 30)
    Receive("EVR", { k = "Angeln@" .. E.Stamp(2026, 12, 4, 19, 30) }, "Zora Zwielicht")
    GE.Tick()
    RunTimers()
    T.eq(Claims(), {})
    T.eq(GE.Queued(), 0)
  end)

  T.it("never reminds of a declined event, but still helps post it", function()
    Reset()
    Event("Kern", 19, 30, { status = 2 })
    GE.Tick()
    T.eq(Find(printed, "Kern"), nil)
    RunTimers()
    KeyPress()
    T.eq(#chat, 1)
  end)

  T.it("reminds once with the real minutes after a late login, without posting", function()
    Reset()
    Event("Spät", 19, 10)
    GE.Tick()
    T.truthy(Find(printed, "Spät beginnt in 10 Min."))
    RunTimers()
    T.eq(Claims(), {})
    T.eq(GE.Queued(), 0)
  end)

  T.it("does neither with both options off", function()
    Reset()
    Event("Ruhig", 19, 30)
    ns.Settings().eventRemind, ns.Settings().eventPost = false, false
    GE.Tick()
    RunTimers()
    T.eq(#printed, 0)
    T.eq(GE.Queued(), 0)
    ns.Settings().eventRemind, ns.Settings().eventPost = nil, nil
  end)

  T.it("creates a sign-up event, then announces it with a click of its own", function()
    Reset()
    local stamp = E.Stamp(2026, 12, 11, 20, 0)
    local done
    ns.On("EVENTS", function(kind, key) if kind == "created" then done = key end end)
    T.eq(GE.Create({ title = " Geschmolzener Kern ", kind = "raid", stamp = stamp, description = "Feuerwiderstand mitbringen",
      locked = true }), true)
    T.eq(calls.AddEvent, 1)
    T.eq(created.title, "Schlachtzug: Geschmolzener Kern") -- no dungeon pictures: "other" with the type in front
    T.eq(created.type, 4)
    T.eq({ created.y, created.m, created.d, created.h, created.mi }, { 2026, 12, 11, 20, 0 })
    T.eq(created.locked, true)
    T.eq(#chat, 0, "the Create click is used up by AddEvent")
    T.eq(done, nil, "created once the server has it")
    Event(created.title, 20, 0, { d = 11, type = 4 })
    Fire("CALENDAR_UPDATE_GUILD_EVENTS")
    T.eq(done, "Schlachtzug: Geschmolzener Kern@" .. stamp)
    local item = GE.Find(done)
    T.eq(GE.CanAnnounce(item), true)
    T.eq(GE.Announce(item), true)
    T.eq(GE.CanAnnounce(item), false)
    T.eq(GE.Announce(item), false)
    T.eq(chat[1].text, "[Guildy] Neues Ereignis: Schlachtzug: Geschmolzener Kern – Fr 11.12., 20:00. Anmelden im Kalender.")
    T.eq(#chat, 1, "announced once")
    -- the box in the form: queued once the server lists it, out on the next key press
    chat = {}
    GE.Create({ title = "Mit Ansage", kind = "meeting", stamp = stamp + 120, announce = true })
    Event("Mit Ansage", 22, 0, { d = 11, type = 3 })
    Fire("CALENDAR_UPDATE_GUILD_EVENTS")
    T.eq(#chat, 0)
    T.eq(GE.CanAnnounce(GE.Find("Mit Ansage@" .. (stamp + 120))), false, "no button for it")
    GE.FlushGuild()
    T.eq(chat[1].text, "[Guildy] Neues Ereignis: Mit Ansage – Fr 11.12., 22:00. Anmelden im Kalender.")
    T.eq(GE.List()[1].kind, "raid")
    -- the list changes without CALENDAR_UPDATE_GUILD_EVENTS: found by looking each second
    done = nil
    GE.Create({ title = "Still", kind = "meeting", stamp = stamp + 60 })
    Event("Still", 21, 0, { d = 11, type = 3 })
    RunTimers(1)
    T.eq(done, "Still@" .. (stamp + 60))
    T.eq(errors, {})
  end)

  T.it("takes the old-style 1 from CanEditGuildEvent as allowed", function()
    env.CanEditGuildEvent = function() return 1 end
    T.eq(GE.CanCreate(), true)
    env.CanEditGuildEvent = function() return nil end
    T.eq(GE.CanCreate(), false)
    env.CanEditGuildEvent = function() return true end
  end)

  T.it("shows why creating failed", function()
    Reset()
    local failed
    ns.On("EVENTS", function(kind, text) if kind == "error" then failed = text end end)
    T.eq({ GE.Create({ title = "", kind = "other", stamp = E.Stamp(2026, 12, 11, 20, 0) }) }, { nil, "name" })
    T.eq({ GE.Create({ title = "Alt", kind = "other", stamp = E.Stamp(2026, 12, 4, 18, 0) }) }, { nil, "past" })
    T.eq(GE.Create({ title = "Neu", kind = "meeting", stamp = E.Stamp(2026, 12, 11, 20, 0) }), true)
    T.eq(created.type, 3)
    Fire("CALENDAR_UPDATE_ERROR", "CALENDAR_ERROR_EVENT_PASSED")
    T.eq(failed, "Dieses Ereignis ist vorbei.")
    T.eq(GE.Creating(), false)
  end)

  T.it("makes the Events tab glow while an event was not seen yet", function()
    Reset()
    env.GuildyDB.eventSeen = nil
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("chat")
    Event("Neu im Kalender", 21, 0)
    Event("Schon beantwortet", 21, 30, { status = 6 })
    T.eq(GE.Unseen(), 1)
    Fire("CALENDAR_UPDATE_GUILD_EVENTS")
    T.eq(ns.UI.tabFlash.events, true)
    ns.UI.SelectTab("events")
    T.eq(ns.UI.tabFlash.events, nil)
    T.eq(GE.Unseen(), 0)
    ns.UI.SelectTab("chat")
    Fire("CALENDAR_UPDATE_GUILD_EVENTS")
    T.eq(ns.UI.tabFlash.events, nil, "seen stays seen")
    Event("Noch eins", 22, 0)
    Fire("CALENDAR_UPDATE_GUILD_EVENTS")
    T.eq(ns.UI.tabFlash.events, true)
    ns.UI.SelectTab("events")
    ns.UI.SelectTab("chat")
    T.eq(errors, {})
  end)

  T.it("draws the tab with events, a picked event and the form", function()
    Reset()
    Event("Kern", 20, 0, { invites = { { name = "Au Tsch", classFilename = "WARRIOR", inviteStatus = 6 } } })
    Event("Gildennews", 22, 0, { calendarType = "GUILD_ANNOUNCEMENT" })
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("events")
    Fire("CALENDAR_OPEN_EVENT", "GUILD_EVENT")
    local view = ns.UI.TabView("events")
    T.eq(view.picked, GE.List()[1].key)
    view:Pick(GE.List()[2].key)
    view:OpenForm()
    view:MoveDate(3)
    view:Submit()
    view:CloseForm()
    ns.UI.ShowEvents(GE.List()[1].key)
    events = {}
    Fire("CALENDAR_UPDATE_GUILD_EVENTS")
    ns.UI.SelectTab("chat")
    T.eq(errors, {})
  end)

  T.it("opens the picked event when the list arrives after the tab opened", function()
    Reset()
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("events")
    T.eq(calls.OpenEvent, nil, "nothing to open yet")
    Event("Spaeter da", 21, 0, { invites = { { name = "Au Tsch", classFilename = "WARRIOR", inviteStatus = 6 } } })
    Fire("CALENDAR_UPDATE_GUILD_EVENTS")
    T.truthy((calls.OpenEvent or 0) >= 1, "opened once it is listed")
    Fire("CALENDAR_OPEN_EVENT", "GUILD_EVENT")
    T.eq(GE.Detail(GE.List()[1].key).counts.yes, 1)
    ns.UI.SelectTab("chat")
    RunTimers(2)
    T.eq(errors, {})
  end)

  T.it("does not loop when the calendar reports its lists while an event opens", function()
    Reset()
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("events")
    Event("Schleife", 21, 0)
    -- like the game: switching the month fires the list events at once
    env.onSetMonth = function() Fire("CALENDAR_UPDATE_EVENT_LIST") Fire("CALENDAR_UPDATE_GUILD_EVENTS") end
    Fire("CALENDAR_UPDATE_GUILD_EVENTS")
    T.truthy((calls.OpenEvent or 0) >= 1 and calls.OpenEvent <= 3, "opened, not again and again: " .. tostring(calls.OpenEvent))
    env.onSetMonth = nil
    ns.UI.SelectTab("chat")
    RunTimers(2)
    T.eq(errors, {})
  end)

  T.it("edits an event in the form and saves it", function()
    Reset()
    env.canEdit = true
    Event("Kern", 20, 0, { desc = "alt", type = 3 })
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("events")
    Fire("CALENDAR_OPEN_EVENT", "GUILD_EVENT")
    local view = ns.UI.TabView("events")
    local f = view.Form
    T.eq(GE.CanEdit(view:PickedItem()), true)
    view:OpenForm(view:PickedItem())
    T.eq(f.Name:GetText(), "Kern")
    T.eq(f.Desc.EditBox:GetText(), "alt")
    T.eq(f.kind, "meeting")
    T.eq({ f.hour, f.minute }, { 20, 0 })
    -- the edit box keeps what is typed: set it the way a player would
    f.Name:SetText("Kern neu")
    f.hour = 21
    created = {}
    view:Submit()
    T.eq(calls.UpdateEvent, 1)
    T.eq(events[1].title, "Kern neu")
    T.eq(events[1].h, 21)
    T.eq(calls.AddEvent, nil, "no new event")
    Fire("CALENDAR_UPDATE_GUILD_EVENTS")
    T.eq(view.picked, "Kern neu@" .. E.Stamp(2026, 12, 4, 21, 0))
    T.eq(f:IsShown(), false)
    ns.UI.SelectTab("chat")
    env.canEdit = nil
    T.eq(errors, {})
  end)

  T.it("deletes an event after asking", function()
    Reset()
    env.canEdit = true
    Event("Weg", 20, 0)
    Event("Bleibt", 21, 0)
    local list = GE.List()
    T.eq(GE.Delete(list[1]), true)
    T.eq(calls.Remove, 1)
    T.eq(#events, 1)
    T.eq(events[1].title, "Bleibt")
    env.canEdit = nil
    T.eq(GE.CanEdit(GE.List()[1]), false)
    T.eq(errors, {})
  end)

  T.it("picks a dungeon in the form and finds it again in the title", function()
    Reset()
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("events")
    local view = ns.UI.TabView("events")
    local f = view.Form
    view:OpenForm()
    f.Type.buttons[2]:GetScript("OnClick")(f.Type.buttons[2]) -- Dungeon
    T.eq(f.kind, "dungeon")
    T.eq(f.Picker:IsShown(), true)
    local names = {}
    for _, row in ipairs(f.PickList.items) do
      for _, dungeon in ipairs(row) do names[#names + 1] = dungeon.name end
    end
    T.truthy(#names > 0, "dungeons to pick")
    -- a click on a dungeon fills in the name
    local tile
    for _, row in pairs(f.PickList.rows) do
      for _, side in ipairs({ "Left", "Right" }) do
        if row[side].dungeon and row[side].dungeon.name == "Festung Krol'dok" then tile = row[side] end
      end
    end
    T.truthy(tile, "Festung Krol'dok in the picker")
    tile:GetScript("OnClick")(tile)
    T.eq(f.Name:GetText(), "Festung Krol'dok")
    T.eq(f.dungeon.key, "kroldok")
    f.Type.buttons[1]:GetScript("OnClick")(f.Type.buttons[1]) -- raid: the dungeon goes
    T.eq(f.dungeon, nil)
    f.Type.buttons[5]:GetScript("OnClick")(f.Type.buttons[5])
    T.eq(f.Picker:IsShown(), false)
    view:CloseForm()
    -- an event named after a dungeon shows as one, made by Guildy or in Blizzard's window
    Event("Festung Krol'dok Abend", 20, 0)
    Fire("CALENDAR_UPDATE_GUILD_EVENTS")
    local item = view:PickedItem()
    T.eq(item.kind, "dungeon")
    T.eq(item.dungeon.key, "kroldok")
    ns.UI.SelectTab("chat")
    T.eq(errors, {})
  end)
end)
