# Guild events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An "Ereignisse" tab that lists the guild's calendar events, answers and creates them through `C_Calendar`, announces new ones and reminds 30 minutes before.

**Architecture:** Pure rules in `Core/Events.lua` (time stamps, grouping, answers, validation, typed titles, claim rule). Game glue in `Game/Events.lua` (`ns.GameEvents`: reading the list, opening events, answering, creating, reminders, the `EVR` claim through `Game/Sync.lua`). UI in `UI/TabEvents.lua`. Options and locales as in the rest.

**Tech Stack:** Lua 5.1 (WoW Forever, Interface 16001), `luajit tests/run.lua`.

**Spec:** `docs/superpowers/specs/2026-11-22-guild-events-design.md`

## Global Constraints

- Server is the only store; no event data over the addon channel except the `EVR` claim `{k = key}`. Protocol stays version 1.
- `C_Calendar.AddEvent` only inside the Erstellen click handler.
- Reminder lead fixed at 30 minutes. Announcements (`calendarType == "GUILD_ANNOUNCEMENT"`) get no reminder, no buttons, no counts.
- Every new string in all six locales (`tests/test_locales.lua`); prefix `EV_` (the `EVENT_*` keys belong to the guild log).
- Options default on: `settings.eventRemind`, `settings.eventPost`.
- Calendar times are realm time: "now" comes from `C_DateAndTime.GetCurrentCalendarTime()`, never `time()`.

## Review Focus

1. Year change: an event on 2 January seen on 30 December groups as next week and its countdown is right (Stamp works on absolute days). Test in Task 1.
2. Two Guildy users reach the 30-minute mark together: only the smaller name key posts. Test in Task 1 (`ShouldPost`) and Task 3 (flow).
3. A declined event never gives a local reminder. Test in Task 3.
4. Logging in 10 minutes before the start gives the local line once with 10 minutes, and no guild post. Test in Task 3.
5. Blizzard's calendar is open: Guildy opens no event in the background. Test in Task 3.

---

### Task 1: Core/Events.lua (pure rules)

**Files:** Create `Core/Events.lua`, `tests/test_events.lua`; modify `Guildy.toc` (after `Core/Blacklist.lua`), `tests/lib.lua` (PURE list), `tests/run.lua` (FILES).

**Produces (`ns.Events`):**
- `TYPES = {"raid","dungeon","pvp","meeting","other"}`, `Events.TypeOf(enum) -> kind`, `Events.EnumOf(kind) -> 0..4`
- `Events.Stamp(y, mo, d, h, mi) -> minutes` (absolute, proleptic Gregorian), `Events.Civil(stamp) -> y, mo, d, h, mi`, `Events.Weekday(stamp) -> 1..7` (Monday 1)
- `Events.Group(stamp, now) -> "week" | "next" | "later"` (weeks Monday to Sunday)
- `Events.Answer(status) -> "yes" | "maybe" | "no" | "open"` (Enum.CalendarStatus: 1,3,6 yes; 5,8 maybe; 2,4 no; 0,7,nil open)
- `Events.Counts(invites) -> {yes, maybe, no, open}` (invites: `{answer = ...}`)
- `Events.Validate(title, stamp, now) -> true | nil, "name" | "past"`; `TITLE_MAX = 31`
- `Events.TypedTitle(kind, title, labels) -> string` (only raid/dungeon: `"<label>: <title>"`), `Events.ParseTitle(title, labels) -> kind | nil, rest`
- `Events.Key(title, stamp) -> string`
- `Events.LEAD = 30`, `Events.Due(stamp, now) -> minutesLeft | nil` (`0 < left <= LEAD`)
- `Events.Wait(isCreator, random) -> seconds` (0, or `3 + random * 17`)
- `Events.NewClaims()`, `Events.AddClaim(claims, key, nameKey)`, `Events.ShouldPost(claims, key, myKey) -> bool` (false when a claim from a smaller name key exists)
- `Events.ShortDate(stamp, dayNames) -> "Fr 04.12."`, `Events.Clock(h, mi) -> "20:00"`

- [ ] Tests: Stamp/Civil round trip incl. 29 Feb 2028 and 31 Dec → 1 Jan; Weekday of 2026-11-22 is 7; Group across a year change; Answer mapping of all nine statuses; Due at 31, 30, 1, 0, -5 minutes; ShouldPost with smaller/larger/own claims; Validate empty, whitespace, past, ok; TypedTitle/ParseTitle round trip and "other" unchanged; ShortDate/Clock.
- [ ] Run `luajit tests/run.lua`: FAIL, implement, PASS. Commit.

### Task 2: Game/Events.lua (calendar glue)

**Files:** Create `Game/Events.lua`; modify `Guildy.toc` (after `Game/Blacklist.lua`), `Core/Init.lua` (events, login start), `Core/Store.lua` (defaults), `Game/Sync.lua` (`EVR` handler, `Sync.SendClaim`), `tests/wow.lua` (C_Calendar stub, `C_DateAndTime`), `tests/test_eventsflow.lua`.

**Produces (`ns.GameEvents`):**
- `List() -> items` sorted by stamp, upcoming only: `{index, id, key, title, kind, typed, stamp, calendarType, answerable, answer}`
- `Load()` (OpenCalendar, at most every 30 s), `Detail(key) -> {creator, description, inviteType, locked, invites, counts} | nil`
- `Open(item) -> bool` (false while `CalendarFrame` shows), `IsOpen(key) -> bool`
- `Answer(item, "yes"|"maybe"|"no") -> bool` (sign-up → `EventSignUp`, invite → `EventAvailable`; `EventTentative`; `EventDecline`)
- `CanCreate() -> bool`, `Create(form) -> true | nil, err` with form `{title, kind, stamp, description, locked, announce}`; result fires `ns.Fire("EVENTS", "created", key)` or `("EVENTS", "error", text)`
- `Fill(on)` background counts while the tab shows; `Tick()` reminders; `OnClaim(key, sender)`, `OnGuildLine(text)`
- Fires `"EVENTS"` on every change. Events wired in Init: `CALENDAR_UPDATE_GUILD_EVENTS`, `CALENDAR_OPEN_EVENT`, `CALENDAR_UPDATE_INVITE_LIST`, `CALENDAR_UPDATE_EVENT`, `CALENDAR_UPDATE_ERROR(_WITH_COUNT/_WITH_PLAYER_NAME)`, `CALENDAR_NEW_EVENT`.

Decisions: raid/dungeon fallback is decided before `AddEvent`: when `EventGetTextures(enum)` is empty, create as Other with `TypedTitle`. Create times out after 10 s without the event showing up. Reminder marks in `GuildyDB.eventReminded[charKey][key] = stamp`, pruned after the start. Guild post only when the mark is reached with at least 25 minutes left. Chat link `|Haddon:Guildy:events|h[...]|h`, handled through `EventRegistry` "SetItemRef".

- [ ] Flow tests (Review Focus 2–5) with the stubbed calendar; implement; PASS; commit.

### Task 3: UI/TabEvents.lua, options, locales

**Files:** Create `UI/TabEvents.lua`; modify `Guildy.toc`, `UI/Main.lua` (`EVENTS` refresh), `UI/Options.lua` (two checks), all six `Locales/*.lua`, `tests/smoke.lua` (tab list).

- `UI.RegisterTab("events", 7.2, "TAB_EVENTS", Build)`; `UI.ShowEvents(key)` opens the tab on an event.
- Layout per the spec (agenda left at a third, detail right; form in place of the detail).
- [ ] Smoke test opens the tab with no events, with events, opens the form; locales test passes; commit.
