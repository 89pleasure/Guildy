-- Guild events in the game (Core/Events.lua holds the rules): the guild's calendar events as the client
-- lists them, who answered (an opened event), answering and creating through C_Calendar, the line in
-- guild chat for a new event, and the reminder 30 minutes before: locally for the player and once in guild
-- chat, posted by one Guildy user (claim EVR, Game/Sync.lua). Guild chat lines go out on the next key press
-- (GE.QueueGuild): WoW Forever blocks them from timers and game events. The server is the only
-- store: nothing of an event is kept or shared beyond what the reminders need.
local _, ns = ...

local GE = {}
ns.GameEvents = GE

local E = ns.Events

GE.CREATE_TIMEOUT = 15  -- seconds without the new event in the list or an error: it failed
GE.LOAD_GAP = 30        -- seconds between two OpenCalendar calls
GE.TICK = 20            -- seconds between two looks at the reminders
GE.RUNNING = 120        -- minutes an event stays in the list after its start
GE.DETAIL_AGE = 300     -- seconds the answers of an event count as fresh in the background
GE.LINK = "addon:Guildy:events"
GE.CLAIM_WAIT = 2       -- seconds a claim waits for a claim from a smaller name key

local cache = {}        -- key -> { creator, description, inviteType, locked, invites, counts, at }
local opened            -- key of the event the client holds open
local pendingOpen       -- { key, at }: asked to open, not open yet
local pendingAnswer     -- { key, answer }: answer once that event is open
local pendingAction     -- { key, run }: run once that event is open (the menu on a name)
local posted = {}       -- key -> true: the guild chat reminder went out (here or seen in chat)
local created = {}      -- key -> true: created from this client in this session
local creating          -- { title, stamp, key, at }
local announced = {}    -- key -> true: the line for the new event went out from here
local claims = E.NewClaims()
local running = {}      -- key -> true: this client takes part in posting the reminder
local filling, fillTimer
local lastLoad = -math.huge
local ticker
local opening           -- true while GE.Open runs: the calendar answers it with list events at once
local trace = {}        -- the last calendar steps, for /guildy events

local function Trace(text, ...)
  trace[#trace + 1] = ("%.1f "):format(GetTime and GetTime() or 0) .. text:format(...)
  if #trace > 12 then table.remove(trace, 1) end
end

local function Cal()
  return rawget(_G, "C_Calendar")
end

local function Clock()
  local get = rawget(_G, "GetTime")
  return get and get() or 0
end

local function Call(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function BlizzardShown()
  local frame = rawget(_G, "CalendarFrame")
  return frame ~= nil and frame.IsShown ~= nil and frame:IsShown() == true
end

local function InCombat()
  return ns.Try(rawget(_G, "InCombatLockdown")) == true
end

local function CalendarTime()
  local dt = rawget(_G, "C_DateAndTime")
  local t = dt and ns.Try(dt.GetCurrentCalendarTime)
  if type(t) == "table" and t.year and not ns.AnySecret(t.year) then return t end
  local d = (rawget(_G, "date") or os.date)("*t")
  return { year = d.year, month = d.month, monthDay = d.day, hour = d.hour, minute = d.min }
end

-- Now as a stamp of the realm's calendar
function GE.Now()
  local t = CalendarTime()
  return E.Stamp(t.year, t.month, t.monthDay, t.hour, t.minute)
end

-- The five type names in the player's language
function GE.Labels()
  local L = ns.L
  return { raid = L.EV_TYPE_RAID, dungeon = L.EV_TYPE_DUNGEON, pvp = L.EV_TYPE_PVP, meeting = L.EV_TYPE_MEETING,
    other = L.EV_TYPE_OTHER }
end

-- The type a title carries in front ("Schlachtzug: ..."), in any of Guildy's languages
local function ParseAny(title)
  local kind, rest = E.ParseTitle(title, GE.Labels())
  if kind then return kind, rest end
  for _, texts in pairs(ns.LocaleTables or {}) do
    kind, rest = E.ParseTitle(title, { raid = texts.EV_TYPE_RAID, dungeon = texts.EV_TYPE_DUNGEON })
    if kind then return kind, rest end
  end
  return nil, title
end

-- Reading the list ----------------------------------------------------------------------------------------

-- The guild's events from just started (GE.RUNNING) on, by start:
-- { index, id, key, title, name, kind, stamp, calendarType, answerable, answer, started }
function GE.List()
  local C = Cal()
  if not (C and C.GetNumGuildEvents and C.GetGuildEventInfo) then return {} end
  local now, items = GE.Now(), {}
  for i = 1, tonumber(ns.Try(C.GetNumGuildEvents)) or 0 do
    local info = ns.Try(C.GetGuildEventInfo, i)
    if type(info) == "table" and type(info.title) == "string" and not ns.AnySecret(info.title, info.year)
      and info.year and info.month and info.monthDay then
      local stamp = E.Stamp(info.year, info.month, info.monthDay, info.hour or 0, info.minute or 0)
      if stamp + GE.RUNNING > now then
        local typed, name = ParseAny(info.title)
        items[#items + 1] = {
          index = i, id = info.eventID, key = E.Key(info.title, stamp), title = info.title, name = name,
          kind = typed or E.TypeOf(info.eventType), typed = typed ~= nil, stamp = stamp,
          calendarType = info.calendarType, answerable = info.calendarType ~= "GUILD_ANNOUNCEMENT",
          answer = E.Answer(info.inviteStatus), status = info.inviteStatus, started = stamp <= now,
        }
      end
    end
  end
  table.sort(items, function(a, b)
    if a.stamp ~= b.stamp then return a.stamp < b.stamp end
    return a.title < b.title
  end)
  return items
end

function GE.Find(key)
  for _, item in ipairs(GE.List()) do
    if item.key == key then return item end
  end
end

-- The client fills its calendar only after OpenCalendar (at most every LOAD_GAP seconds unless forced)
function GE.Load(force)
  local C = Cal()
  if not (C and C.OpenCalendar) then return end
  if not force and Clock() - lastLoad < GE.LOAD_GAP then return end
  lastLoad = Clock()
  Call(C.OpenCalendar)
end

function GE.Detail(key)
  return cache[key]
end

function GE.IsOpen(key)
  return key ~= nil and opened == key
end

-- Whether the player created the event (Guildy here, or the opened event names them)
function GE.IsCreator(key)
  if created[key] then return true end
  local detail = cache[key]
  return detail ~= nil and detail.creator ~= nil and ns.Names.Same(detail.creator, ns.PlayerName())
end

-- Opening an event (who answered) -------------------------------------------------------------------------

-- Opens an event of the list in the client. Never while Blizzard's calendar is shown (it holds its own).
-- Where an event of the list sits in the calendar: month offset, day, index; nil when the calendar does not
-- know it. The month offsets count from the shown month: switched only when it is another one (switching
-- makes the client report its lists anew at once, GE.OnGuildEvents ignores that while `opening`).
local function Place(item)
  local C = Cal()
  local t = CalendarTime()
  opening = true
  local shown = ns.Try(C.GetMonthInfo, 0)
  if type(shown) ~= "table" or shown.month ~= t.month or shown.year ~= t.year then Call(C.SetAbsMonth, t.month, t.year) end
  -- by its ID, else by its place in the guild's list
  local sel = item.id and ns.Try(C.GetEventIndexInfo, item.id)
  if type(sel) ~= "table" or not sel.monthDay then sel = ns.Try(C.GetGuildEventSelectionInfo, item.index) end
  opening = nil
  if type(sel) ~= "table" or not sel.monthDay or not sel.eventIndex then return nil end
  return sel.offsetMonths or sel.offsetMonth or 0, sel.monthDay, sel.eventIndex -- (docs: offsetMonths; Blizzard reads offsetMonth)
end

-- Opens an event of the list in the client. Never while Blizzard's calendar is shown (it holds its own).
function GE.Open(item)
  local C = Cal()
  if not (C and item and C.OpenEvent and C.GetGuildEventSelectionInfo) or BlizzardShown() then return false end
  -- asked for this one a moment ago: its answer is on the way
  if pendingOpen and pendingOpen.key == item.key and Clock() - pendingOpen.at < 3 then return true end
  local offset, day, index = Place(item)
  if not offset then
    Trace("open %s: no place in the calendar", item.title)
    return false
  end
  pendingOpen = { key = item.key, at = Clock() }
  opening = true
  local ok, result = Call(C.OpenEvent, offset, day, index)
  opening = nil
  Trace("open %s: OpenEvent(%s, %s, %s) -> %s %s", item.title, tostring(offset), tostring(day), tostring(index),
    tostring(ok), tostring(result))
  return ok and result ~= false
end

-- Whether the player may edit and delete the event (Blizzard's rule: its creator and ranks with the right)
function GE.CanEdit(item)
  local C = Cal()
  if not (C and item and item.answerable ~= nil) or item.started then return false end
  local detail = cache[item.key]
  if detail and detail.canEdit ~= nil and opened == item.key then return detail.canEdit end
  if not C.ContextMenuEventCanEdit or BlizzardShown() then return false end
  local offset, day, index = Place(item)
  if not offset then return false end
  local can = ns.Try(C.ContextMenuEventCanEdit, offset, day, index)
  return can ~= nil and can ~= false
end

-- The statuses the calendar lets the player set for an invite of the opened event (Enum.CalendarStatus),
-- with the game's own names: { { status, label } }
local STATUS_KEYS = { [0] = "EV_ST_INVITED", "EV_ST_AVAILABLE", "EV_ST_NO", "EV_ST_CONFIRMED", "EV_ST_OUT", "EV_ST_STANDBY",
  "EV_ST_YES", "EV_OPEN_ANSWER", "EV_ST_MAYBE" }
function GE.StatusLabel(status, statusString)
  local text = type(statusString) == "string" and rawget(_G, statusString)
  if type(text) == "string" and text ~= "" then return text end
  local L = ns.L
  local names = { [0] = L.EV_ST_INVITED, L.EV_ST_AVAILABLE, L.EV_ST_NO, L.EV_ST_CONFIRMED, L.EV_ST_OUT, L.EV_ST_STANDBY,
    L.EV_ST_YES, L.EV_OPEN_ANSWER, L.EV_ST_MAYBE }
  return names[status] or tostring(status)
end
GE.STATUS_KEYS = STATUS_KEYS

function GE.StatusOptionsAt(index)
  local C = Cal()
  local raw = C and ns.Try(C.EventGetStatusOptions, index)
  local options = {}
  for _, option in ipairs(type(raw) == "table" and raw or {}) do
    if type(option) == "table" and type(option.status) == "number" then
      options[#options + 1] = { status = option.status, label = GE.StatusLabel(option.status, option.statusString) }
    end
  end
  return options
end

local function ReadOpened()
  local C = Cal()
  local info = C and ns.Try(C.GetEventInfo)
  if type(info) ~= "table" or type(info.time) ~= "table" or type(info.title) ~= "string" or ns.AnySecret(info.title) then
    Trace("read: no event info (%s)", type(info))
    return nil
  end
  local t = info.time
  local stamp = E.Stamp(t.year, t.month, t.monthDay, t.hour or 0, t.minute or 0)
  local key = E.Key(info.title, stamp)
  local invites, creator, myIndex = {}, info.creator, nil
  -- (GetNumInvites: Blizzard's calendar counts with it; EventGetNumInvites does not exist on WoW Forever)
  local count = tonumber(ns.Try(C.GetNumInvites)) or tonumber(ns.Try(C.EventGetNumInvites)) or 0
  for i = 1, count do
    local invite = ns.Try(C.EventGetInvite, i)
    if type(invite) == "table" and type(invite.name) == "string" and invite.name ~= "" and not ns.AnySecret(invite.name) then
      invites[#invites + 1] = { name = invite.name, classFile = invite.classFilename, answer = E.Answer(invite.inviteStatus),
        mine = invite.inviteIsMine or nil, index = i, status = invite.inviteStatus, mod = invite.modStatus }
      if invite.inviteIsMine then myIndex = i end
      if invite.modStatus == "CREATOR" then creator = creator or invite.name end
    end
  end
  table.sort(invites, function(a, b) return ns.Names.Key(a.name) < ns.Names.Key(b.name) end)
  Trace("read %s: %d answers", key, #invites)
  local can = ns.Try(C.EventCanEdit)
  can = can ~= nil and can ~= false
  local myStatus
  for _, invite in ipairs(invites) do
    if invite.index == myIndex then myStatus = invite.status end
  end
  cache[key] = { creator = creator, description = info.description, inviteType = info.inviteType,
    locked = info.isLocked == true, canEdit = can, myIndex = myIndex, myStatus = myStatus,
    -- who may edit sets their own answer like anyone else's (Blizzard: "Einladungsstatus festlegen")
    myOptions = (can and myIndex) and GE.StatusOptionsAt(myIndex) or nil,
    status = info.inviteStatus, invites = invites, counts = E.Counts(invites), at = Clock() }
  return key
end

local FillNext

-- CALENDAR_OPEN_EVENT
function GE.OnOpenEvent(calendarType)
  Trace("CALENDAR_OPEN_EVENT %s", tostring(calendarType))
  if calendarType == "HOLIDAY" or calendarType == "RAID_LOCKOUT" or calendarType == "RAID_RESET" then return end
  local key = ReadOpened()
  if not key then return end
  opened = key
  if pendingOpen and pendingOpen.key == key then pendingOpen = nil end
  if pendingAnswer and pendingAnswer.key == key then
    local answer = pendingAnswer.answer
    pendingAnswer = nil
    GE.Answer(GE.Find(key), answer)
  end
  if pendingAction and pendingAction.key == key then
    local run = pendingAction.run
    pendingAction = nil
    ns.SafeCall(run)
  end
  ns.Fire("EVENTS", "detail", key)
  if filling and not fillTimer then FillNext() end
end

-- CALENDAR_UPDATE_INVITE_LIST, CALENDAR_UPDATE_EVENT: the opened event changed
function GE.OnEventChanged()
  if not opened then return end
  local key = ReadOpened()
  if key then
    opened = key
    ns.Fire("EVENTS", "detail", key)
  end
end

-- Answering -----------------------------------------------------------------------------------------------

local INVITE_NORMAL = 0 -- Enum.CalendarInviteType.Normal: invited by name (answered "available")

local INVITE_SIGNUP = 1 -- Enum.CalendarInviteType.Signup
local NOT_SIGNED_UP = 7 -- Enum.CalendarStatus.NotSignedup

-- The answers the player can give now, in order, as Blizzard's own window offers them: a sign-up event
-- (a guild event with invite type Signup) has "yes" and "maybe" until answered, then only "remove" (and
-- nothing for its creator); an event the player is invited to has "yes" (available), "maybe", "no" but the
-- current answer. Empty for announcements, locked and started events.
function GE.Choices(item)
  if not (item and item.answerable) or item.started then return {} end
  local detail = cache[item.key]
  if detail and detail.locked then return {} end
  if detail and detail.myOptions and #detail.myOptions > 0 then
    local choices = {}
    for _, option in ipairs(detail.myOptions) do
      if option.status ~= detail.myStatus then choices[#choices + 1] = option.status end
    end
    return choices
  end
  local signup = detail == nil or detail.inviteType == INVITE_SIGNUP or detail.inviteType == nil
  if signup then
    if item.answer == "open" or (detail and detail.status == NOT_SIGNED_UP) then return { "yes", "maybe" } end
    if GE.IsCreator(item.key) then return {} end
    return { "remove" }
  end
  local choices = {}
  for _, answer in ipairs({ "yes", "maybe", "no" }) do
    if item.answer ~= answer then choices[#choices + 1] = answer end
  end
  return choices
end

-- answer: "yes" | "maybe" | "no" | "remove" (take back a sign-up). Opens the event first when another one is
-- open.
function GE.Answer(item, answer)
  local C = Cal()
  if not (C and item and item.answerable) then return false end
  local detail = cache[item.key]
  if detail and detail.locked then return false end
  if opened ~= item.key then
    pendingAnswer = { key = item.key, answer = answer }
    return GE.Open(item)
  end
  local ok
  if answer == "yes" then
    local normal = detail and detail.inviteType == INVITE_NORMAL
    ok = Call(normal and C.EventAvailable or C.EventSignUp)
  elseif answer == "maybe" then
    ok = Call(C.EventTentative)
  elseif answer == "no" then
    ok = Call(C.EventDecline)
  elseif answer == "remove" then
    ok = Call(C.RemoveEvent)
  elseif type(answer) == "number" and detail and detail.myIndex then
    ok = Call(C.EventSetInviteStatus, detail.myIndex, answer)
  end
  Trace("answer %s %s -> %s", item.key, tostring(answer), tostring(ok))
  if ok then
    item.answer = type(answer) == "number" and E.Answer(answer) or answer == "remove" and "open" or answer
    ns.Fire("EVENTS", "answer", item.key)
  end
  return ok == true
end

-- Who may edit the event manages its invites (Blizzard's menu on a name): their status, moderator, removal.
-- The event must be open; when it is not, it is opened and run(true) comes once it is.
function GE.WithOpen(item, run)
  if opened == item.key then return run(false) end
  pendingAction = { key = item.key, run = function() run(true) end }
  GE.Open(item)
end

function GE.SetStatus(item, invite, status)
  local C = Cal()
  if not (C and invite and invite.index) or opened ~= item.key then return false end
  local ok = Call(C.EventSetInviteStatus, invite.index, status)
  Trace("status %s %s -> %s", invite.name, tostring(status), tostring(ok))
  return ok
end

function GE.SetModerator(item, invite, on)
  local C = Cal()
  if not (C and invite and invite.index) or opened ~= item.key then return false end
  return Call(on and C.EventSetModerator or C.EventClearModerator, invite.index)
end

function GE.RemoveInvite(item, invite)
  local C = Cal()
  if not (C and invite and invite.index) or opened ~= item.key then return false end
  return Call(C.EventRemoveInvite, invite.index)
end

-- Creating ------------------------------------------------------------------------------------------------

function GE.CanCreate()
  -- an old-style function: 1 or nil on some clients, true or false on others
  local can = ns.Try(rawget(_G, "CanEditGuildEvent"))
  return can ~= nil and can ~= false and not ns.AnySecret(can)
end

function GE.Creating()
  return creating ~= nil
end

-- The first count letters of a text (UTF-8)
local function Letters(text, count)
  local n = 0
  for i = 1, #text do
    local byte = text:byte(i)
    if byte < 128 or byte >= 192 then
      n = n + 1
      if n > count then return text:sub(1, i - 1) end
    end
  end
  return text
end

-- Guild chat on the next key press ------------------------------------------------------------------------
-- WoW Forever lets an addon write in guild chat only inside a key press or click (from a timer or a game
-- event the game blocks it, ADDON_ACTION_BLOCKED). Lines that are due wait here and go out on the player's
-- next key press, whatever key (moving, jumping): an invisible frame sees every key and passes it on.
local chatQueue = {}    -- { { key, text, check = function() -> bool (still to be sent) } }
local catcher

function GE.QueueGuild(key, text, check)
  for _, entry in ipairs(chatQueue) do
    if entry.key == key then return end
  end
  chatQueue[#chatQueue + 1] = { key = key, text = text, check = check }
  Trace("queued %s", key)
end

function GE.Queued()
  return #chatQueue
end

-- Inside a key press: send what waits
function GE.FlushGuild()
  if #chatQueue == 0 then return end
  local due = chatQueue
  chatQueue = {}
  for _, entry in ipairs(due) do
    if not entry.check or entry.check() then
      Trace("sent %s", entry.key)
      ns.Chat.Send("guild", entry.text)
    end
  end
end

-- The frame that sees the key presses; SetPropagateKeyboardInput may not be called in combat, so it is made
-- outside of it (and keeps passing every key on once made)
local function MakeCatcher()
  if catcher or InCombat() then return catcher ~= nil end
  local frame = ns.CreateFrame("Frame", "GuildyKeyCatcher", rawget(_G, "UIParent"))
  if not (frame.EnableKeyboard and frame.SetPropagateKeyboardInput) then return false end
  frame:EnableKeyboard(true)
  frame:SetPropagateKeyboardInput(true)
  frame:SetScript("OnKeyDown", function()
    if #chatQueue > 0 then ns.SafeCall(GE.FlushGuild) end
  end)
  frame:Show()
  catcher = frame
  return true
end
GE.MakeCatcher = MakeCatcher

local function Fail(text)
  creating = nil
  ns.Fire("EVENTS", "error", text)
end

local function CreatedLine(title, stamp)
  local L = ns.L
  local _, _, _, h, mi = E.Civil(stamp)
  return L.EV_ANNOUNCE:format(title, E.ShortDate(stamp, GE.DayNames(), L.EV_MONTH_FIRST == "1"), E.Clock(h, mi))
end

function GE.DayNames()
  local L = ns.L
  return { L.EV_DAY_1, L.EV_DAY_2, L.EV_DAY_3, L.EV_DAY_4, L.EV_DAY_5, L.EV_DAY_6, L.EV_DAY_7 }
end

-- The new event is in the list: done
local function CheckCreated()
  if not creating then return end
  local item = GE.Find(creating.key)
  if not item then return end
  local done = creating
  creating = nil
  if done.old then
    -- an edit: what this client knew of the old one goes to the new key
    if created[done.old] then created[done.key] = true end
    if announced[done.old] then announced[done.key] = true end
    if done.old ~= done.key then cache[done.old] = nil end
    Trace("saved %s", done.key)
    ns.Fire("EVENTS", "saved", done.key)
    return
  end
  created[done.key] = true
  Trace("created %s", done.key)
  if done.announce then
    announced[done.key] = true
    GE.QueueGuild("new:" .. done.key, CreatedLine(done.title, done.stamp))
  end
  ns.Fire("EVENTS", "created", done.key)
end
GE.CheckCreated = CheckCreated

-- Runs inside the Erstellen click (AddEvent needs the key press). form = { title, kind, stamp, description,
-- locked, announce }; announce: the line goes out on the next key press once the server lists the event. Returns true (the result comes as EVENTS "created" | "error"), or nil and
-- "name" | "past" | "rights" | "trial" | "busy" | "api".
-- The title and type the calendar gets: raid and dungeon as "other" with the type in front while it fits
-- (WoW Forever offers no dungeon pictures; Blizzard's own picker is empty), cut to the calendar's length
local function CalendarTitle(C, kind, title)
  if kind == "raid" or kind == "dungeon" then
    local textures = ns.Try(C.EventGetTextures, E.EnumOf(kind))
    if type(textures) ~= "table" or #textures == 0 then
      -- a dungeon's name alone is recognized by the Events tab
      local typed = E.TypedTitle(kind, title, GE.Labels())
      if Letters(typed, E.TITLE_MAX) == typed then title = typed end
      kind = "other"
    end
  end
  return Letters(title, E.TITLE_MAX), kind
end

-- Sets the event the client holds (new or opened) and sends it with send (AddEvent | UpdateEvent); the
-- result comes as EVENTS "created" | "saved" | "error". old: the key of an edited event.
local function Submit(C, form, first, send, old)
  if creating and Clock() - creating.at < GE.CREATE_TIMEOUT then return nil, "busy" end
  local title = ns.Names.Trim(form.title or "")
  local ok, err = E.Validate(title, form.stamp, GE.Now())
  if not ok then return nil, err end
  local kind
  title, kind = CalendarTitle(C, form.kind, title)
  local y, m, d, h, mi = E.Civil(form.stamp)
  local steps = {
    first, { C.EventSetTitle, title }, { C.EventSetType, E.EnumOf(kind) },
    { C.EventSetDate, m, d, y }, { C.EventSetTime, h, mi }, { C.EventSetDescription, form.description or "" },
  }
  if form.locked then
    steps[#steps + 1] = { C.EventSetLocked }
  elseif old then
    steps[#steps + 1] = { C.EventClearLocked }
  end
  for _, step in ipairs(steps) do
    if step[1] ~= nil and not Call(unpack(step)) then return nil, "api" end
  end
  local mine = { title = title, stamp = form.stamp, key = E.Key(title, form.stamp), old = old, announce = form.announce,
    at = Clock() }
  creating = mine
  if not Call(send) then
    creating = nil
    return nil, "api"
  end
  Trace("%s %s", old and "UpdateEvent" or "AddEvent", mine.key)
  -- the event shows up in the guild's list without a word on some clients: look every second, and load
  -- the calendar anew once on the way
  for second = 1, GE.CREATE_TIMEOUT do
    C_Timer.After(second, function()
      if creating ~= mine then return end
      if second == 3 then GE.Load(true) end
      CheckCreated()
      if creating == mine and second == GE.CREATE_TIMEOUT then Fail(ns.L.EV_ERR_TIMEOUT) end
    end)
  end
  return true
end

-- Runs inside the Erstellen click (AddEvent needs the key press). form = { title, kind, stamp, description,
-- locked }. Returns true, or nil and "name" | "past" | "trial" | "busy" | "api".
function GE.Create(form)
  local C = Cal()
  if not (C and C.CreateGuildSignUpEvent and C.AddEvent) then return nil, "api" end
  -- no check of CanEditGuildEvent here: it said no on WoW Forever for a rank that may create (found in
  -- game 2026-11-22); the server refuses a rank without the right (CALENDAR_UPDATE_ERROR, shown in the form)
  local trial, veteran = ns.Try(rawget(_G, "IsTrialAccount")), ns.Try(rawget(_G, "IsVeteranTrialAccount"))
  if (trial and trial ~= 0) or (veteran and veteran ~= 0) then
    return nil, "trial"
  end
  return Submit(C, form, { C.CreateGuildSignUpEvent }, C.AddEvent)
end

-- Saves changes to an event of the list (inside the Speichern click). The event must be open in the
-- client (the tab opens it with the form). Returns true, or nil and "notopen" | "name" | "past" | "busy" | "api".
function GE.Edit(item, form)
  local C = Cal()
  if not (C and item and C.UpdateEvent) then return nil, "api" end
  if opened ~= item.key then
    GE.Open(item)
    return nil, "notopen"
  end
  return Submit(C, form, { nil }, C.UpdateEvent, item.key)
end

-- Deletes an event of the list for everyone (inside the click that confirms it)
function GE.Delete(item)
  local C = Cal()
  if not (C and item and C.ContextMenuSelectEvent and C.ContextMenuEventRemove) or BlizzardShown() then return false end
  local offset, day, index = Place(item)
  if not offset then return false end
  if not Call(C.ContextMenuSelectEvent, offset, day, index) then return false end
  local ok = Call(C.ContextMenuEventRemove)
  Trace("delete %s -> %s", item.key, tostring(ok))
  if ok then
    cache[item.key] = nil
    if opened == item.key then opened = nil end
    ns.Fire("EVENTS", "deleted", item.key)
  end
  return ok == true
end

-- The line in guild chat for an event: a click of its own (WoW Forever lets an addon write in guild chat only
-- inside a click, and AddEvent uses up the Create click). Once per event from this client.
function GE.CanAnnounce(item)
  return item ~= nil and not item.started and not announced[item.key] and GE.IsCreator(item.key)
end

function GE.Announced(key)
  return announced[key] == true
end

function GE.Announce(item)
  if not item or announced[item.key] then return false end
  announced[item.key] = true
  Trace("announce %s", item.key)
  ns.Chat.Send("guild", CreatedLine(item.title, item.stamp))
  ns.Fire("EVENTS", "announced", item.key)
  return true
end

-- CALENDAR_UPDATE_ERROR*: the calendar's message (a global string's name)
function GE.OnError(message, arg)
  if ns.AnySecret(message, arg) then return end
  local text = type(message) == "string" and rawget(_G, message) or message
  if type(text) ~= "string" then text = tostring(message) end
  if arg ~= nil and text:find("%%") then
    local ok, formatted = pcall(string.format, text, arg)
    if ok then text = formatted end
  end
  if creating then
    Fail(text)
  else
    ns.Fire("EVENTS", "error", text)
  end
end

-- Seen events (the Events tab glows while there is one not seen yet) -----------------------------------------

local function Seen()
  local db = ns.DB()
  if not db then return nil end
  if type(db.eventSeen) ~= "table" then db.eventSeen = {} end
  local me = ns.Names.Key(ns.PlayerName())
  db.eventSeen[me] = type(db.eventSeen[me]) == "table" and db.eventSeen[me] or {}
  return db.eventSeen[me]
end

-- Events the player has not seen in the tab yet; one already answered counts as seen (answered in
-- Blizzard's calendar), and so does one that started
function GE.Unseen(items)
  local seen = Seen()
  if not seen then return 0 end
  local count = 0
  for _, item in ipairs(items or GE.List()) do
    if not seen[item.key] and not item.started and (not item.answerable or item.answer == "open") then count = count + 1 end
  end
  return count
end

-- The tab shows these events: seen, and old marks go
function GE.MarkSeen(items)
  local seen = Seen()
  if not seen then return end
  local now = GE.Now()
  for key, stamp in pairs(seen) do
    if type(stamp) ~= "number" or stamp + GE.RUNNING < now then seen[key] = nil end
  end
  for _, item in ipairs(items) do seen[item.key] = item.stamp end
  ns.UI.SetTabFlash("events", false)
end

-- /guildy events glow: this character has seen no event, and the tab glows now (to see the glow; opening
-- the Events tab ends it like any other time)
function GE.TestGlow()
  local db = ns.DB()
  if db and type(db.eventSeen) == "table" then db.eventSeen[ns.Names.Key(ns.PlayerName())] = nil end
  ns.UI.SetTabFlash("events", true)
  ns.Print(ns.L.EV_GLOW_TEST:format(GE.Unseen()))
end

function GE.UpdateFlash()
  local shown = ns.UI.IsShown() and ns.UI.Current() == "events"
  if shown then return end -- the tab marks what it shows
  ns.UI.SetTabFlash("events", GE.Unseen() > 0)
end

-- CALENDAR_UPDATE_GUILD_EVENTS, CALENDAR_UPDATE_EVENT_LIST
function GE.OnGuildEvents()
  if opening then return end -- (answered by our own GE.Open: nothing new in the list)
  local live = {}
  for _, item in ipairs(GE.List()) do live[item.key] = true end
  for key in pairs(cache) do
    if not live[key] then cache[key] = nil end
  end
  CheckCreated()
  ns.Fire("EVENTS", "list")
  GE.UpdateFlash()
  -- the tab opened before the list was there: the answers load now
  if filling and not fillTimer then FillNext() end
end

-- Counts in the background ---------------------------------------------------------------------------------

-- Opens the events whose answers are not known (or old) one after another, while on is true (the tab shows)
FillNext = function()
  if not filling or fillTimer then return end
  local wait = 2.5
  if not (BlizzardShown() or InCombat() or (pendingOpen and Clock() - pendingOpen.at < 3)) then
    local next
    for _, item in ipairs(GE.List()) do
      local detail = cache[item.key]
      if item.answerable and (not detail or Clock() - detail.at > GE.DETAIL_AGE) then
        next = item
        break
      end
    end
    if not next then return end
    fillTimer = true -- before opening: the calendar may answer at once with events that come back here
    if not GE.Open(next) then wait = 5 end
  end
  fillTimer = true
  C_Timer.After(wait, function()
    fillTimer = nil
    FillNext()
  end)
end

function GE.Fill(on)
  filling = on and true or nil
  if filling then FillNext() end
end

-- Reminders -------------------------------------------------------------------------------------------------

local function Marks()
  local db = ns.DB()
  if not db then return {} end
  if type(db.eventReminded) ~= "table" then db.eventReminded = {} end
  local me = ns.Names.Key(ns.PlayerName())
  db.eventReminded[me] = type(db.eventReminded[me]) == "table" and db.eventReminded[me] or {}
  return db.eventReminded[me]
end

local function Link()
  return "|cffffd100|H" .. GE.LINK .. "|h[" .. ns.L.EV_LINK .. "]|h|r"
end

-- WoW Forever lets an addon write in guild chat only inside a click or key press: the guild chat reminder
-- is a link in the player's own reminder line. Whoever clicks first posts it; the others' links then
-- say it was posted (the line is seen in guild chat, GE.OnGuildLine).
local function GuildReminder(item)
  local left = E.Due(item.stamp, GE.Now()) or E.LEAD
  local _, _, _, h, mi = E.Civil(item.stamp)
  return ns.L.EV_REMIND_GUILD:format(item.title, left, E.Clock(h, mi))
end

local function Remind(item, left)
  local L = ns.L
  local state = item.answer == "yes" and L.EV_REMIND_YES or item.answer == "maybe" and L.EV_REMIND_MAYBE or L.EV_REMIND_OPEN
  ns.Print(L.EV_REMIND_LOCAL:format(item.title, left, state .. " · " .. Link()))
  GE.reminded = item.key
  ns.Fire("EVENTS", "reminded", item.key)
end

-- One of possibly many Guildy users posts: the creator first, the rest after a random wait; whoever sees a
-- claim or the line first stays quiet, and of two claims the smaller name key posts. The winner's line goes
-- out on their next key press, unless the line shows up in guild chat before.
local function TakePart(item)
  local key = item.key
  if running[key] or posted[key] then return end
  running[key] = true
  local me = ns.Names.Key(ns.PlayerName())
  C_Timer.After(E.Wait(GE.IsCreator(key), math.random()), function()
    if posted[key] or E.Claimed(claims, key) then return end
    E.AddClaim(claims, key, me)
    ns.Sync.SendClaim(key)
    C_Timer.After(GE.CLAIM_WAIT, function()
      if posted[key] or not E.ShouldPost(claims, key, me) then return end
      GE.QueueGuild("remind:" .. key, GuildReminder(item), function()
        if posted[key] or item.stamp <= GE.Now() then return false end
        posted[key] = true
        return true
      end)
    end)
  end)
end

function GE.Tick()
  if not catcher then MakeCatcher() end
  local now = GE.Now()
  local marks = Marks()
  for key, stamp in pairs(marks) do
    if type(stamp) ~= "number" or stamp <= now then marks[key] = nil end
  end
  local settings = ns.Settings()
  for _, item in ipairs(GE.List()) do
    local left = item.answerable and E.Due(item.stamp, now)
    if left and not marks[item.key] then
      marks[item.key] = item.stamp
      if settings.eventRemind ~= false and item.answer ~= "no" then Remind(item, left) end
      if settings.eventPost ~= false and left >= E.POST_ROOM then TakePart(item) end
    end
  end
end

-- EVR {k = key} from another Guildy user
function GE.OnClaim(data, sender)
  local key = type(data) == "table" and data.k
  if type(key) ~= "string" or #key > 120 or type(sender) ~= "string" then return end
  E.AddClaim(claims, key, ns.Names.Key(sender))
end

-- A guild chat line: the reminder of an event, posted by someone: this client stays quiet
function GE.OnGuildLine(text)
  if type(text) ~= "string" or ns.AnySecret(text) or not text:find("[Guildy]", 1, true) then return end
  local now = GE.Now()
  for _, item in ipairs(GE.List()) do
    if E.Due(item.stamp, now) and text:find(item.title, 1, true) then posted[item.key] = true end
  end
end

-- After login: the calendar loads, then the reminders are looked at every TICK seconds; chat links open the tab
function GE.Start()
  local registry = rawget(_G, "EventRegistry")
  if registry and registry.RegisterCallback then
    pcall(registry.RegisterCallback, registry, "SetItemRef", function(_, link)
      if type(link) ~= "string" or ns.AnySecret(link) then return end
      if link:sub(1, #GE.LINK) == GE.LINK then ns.SafeCall(ns.UI.ShowEvents, GE.reminded) end
    end, GE)
  end
  C_Timer.After(8, function() ns.SafeCall(GE.Load, true) end)
  -- the key press catcher, outside of combat (tried again with the reminders until it is made)
  C_Timer.After(5, function() ns.SafeCall(MakeCatcher) end)
  C_Timer.After(15, function()
    ns.SafeCall(GE.Tick)
    if not ticker then ticker = C_Timer.NewTicker(GE.TICK, function() ns.SafeCall(GE.Tick) end) end
  end)
end

-- /guildy events: what the calendar answers
function GE.Debug()
  local lines = {}
  local C = Cal()
  lines[#lines + 1] = ("calendar API %s, CanEditGuildEvent %s, Blizzard's calendar shown %s, now %s"):format(
    tostring(C ~= nil), tostring(ns.Try(rawget(_G, "CanEditGuildEvent"))), tostring(BlizzardShown()), tostring(GE.Now()))
  for _, item in ipairs(GE.List()) do
    local sel = C and ns.Try(C.GetGuildEventSelectionInfo, item.index)
    local byId = C and item.id and ns.Try(C.GetEventIndexInfo, item.id)
    local function Where(t)
      if type(t) ~= "table" then return tostring(t) end
      return ("%s/%s/%s"):format(tostring(t.offsetMonths or t.offsetMonth), tostring(t.monthDay), tostring(t.eventIndex))
    end
    local detail = cache[item.key]
    lines[#lines + 1] = ("%d %s id %s %s answer %s place %s byId %s detail %s"):format(item.index, item.key,
      tostring(item.id), tostring(item.calendarType), item.answer, Where(sel), Where(byId),
      detail and (#detail.invites .. " answers") or "none")
  end
  lines[#lines + 1] = "open: " .. tostring(opened) .. ", waiting: " .. tostring(pendingOpen and pendingOpen.key)
  for _, line in ipairs(trace) do lines[#lines + 1] = line end
  return lines
end

-- Tests: forget everything this session knows
function GE.Reset()
  cache, opened, pendingOpen, pendingAnswer = {}, nil, nil, nil
  posted, created, creating, announced, running, claims, chatQueue = {}, {}, nil, {}, {}, E.NewClaims(), {}
  filling, fillTimer, lastLoad = nil, nil, -math.huge
end
