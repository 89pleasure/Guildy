# Guild events from the game's calendar — design

Date: 2026-11-22. Started from a CurseForge comment (bornabe_wylde: "Will this eventually get Event / Sign-up /
Raid management by chance?"). Sven did not want a raid planner in Guildy ("not really something that blizzard
provides … looks kind of mandatory to have"), but wanted Guildy to use what WoW's own calendar already does:
create guild events, show them, announce them, remind people. Raid planning stays in Raidy.

## Intent

Guildy becomes a handier front door to Blizzard's calendar. Everything is a real Blizzard guild event, stored
by the server, so members without Guildy see the same events in their calendar and answer there. Guildy adds
what the calendar lacks: one place in the guild window to see what is coming and who comes, one click to
answer, an announcement in guild chat when an event is created, and a reminder before it starts.

## Goals

- A new tab **Ereignisse** (enUS "Events") in the guild window that lists the guild's upcoming calendar
  events and, for the picked one, who answered.
- Answer an event (sign up, tentative, decline) from Guildy with one click.
- Create a guild sign-up event from Guildy's own form, for ranks allowed to do so.
- When an event is created from Guildy: one line in guild chat (optional per event, ticked by default).
- 30 minutes before each guild event: one line in guild chat, posted by exactly one Guildy user, and a local
  reminder for every Guildy user who did not decline.

## Non-goals

- No DKP, loot, lineups, roles, soft reserves, attendance. That is Raidy.
- No sign-up system of Guildy's own and no event data synced over the addon channel. The server is the only
  store; Guildy only reads and calls `C_Calendar`.
- No editing, deleting, inviting single players or locking existing events in Guildy. A link opens
  Blizzard's calendar for that.
- No past events in this version (the "Vergangene" segment in the mock is cut; builder may add it later).
- No dungeon/raid picture picker: Forever's client returns an empty list (`C_Calendar.EventGetTextures`),
  Blizzard's own picker is empty too.
- No reminder lead time per event: Blizzard's event has no field for it. Fixed 30 minutes (Sven).

## Anti-goals (a failure even if it works)

- Guild chat gets the same reminder twice or more from several Guildy users.
- Guildy feels mandatory: anything a member without Guildy can't see or answer.
- A member is nagged about an event they declined.
- Creating an event fails silently (no permission, free-trial account, missing field) and the user thinks it
  worked.

## Constraints

- WoW Forever client (Interface 16001), Lua, tests with `luajit tests/run.lua` from the repo root. Pure logic
  in `Core/`, game glue in `Game/`, UI in `UI/`, as in the rest of the addon.
- Forever ships Blizzard's modern calendar (`Blizzard_Calendar/Mainline`), API `C_Calendar`.
- `C_Calendar.AddEvent` is `#hwevent`: it must run from a click (Guildy's "Erstellen" button). Not available
  to free-trial accounts.
- Who may create guild events: `CanEditGuildEvent()` (rank permission), the same check Blizzard's window uses.
- Guild chat (`GUILD`) needs no hardware event, so a timer may post the reminder. Sending goes through
  `ns.Chat.Send("guild", text)` (`Game/Chat.lua`).
- Upcoming guild events: `C_Calendar.GetNumGuildEvents()` / `GetGuildEventInfo(i)` (fields: eventID, date,
  time, eventType, title, inviteStatus, …), refreshed on `CALENDAR_UPDATE_GUILD_EVENTS`. The client fills
  calendar data only after `C_Calendar.OpenCalendar()`.
- Who answered: `C_Calendar.OpenEvent(...)`, then on `CALENDAR_OPEN_EVENT` `EventGetNumInvites()` /
  `EventGetInvite(i)`. The client holds one opened event at a time.
- Answering: `C_Calendar.EventSignUp()` / `EventTentative()` / `EventDecline()` act on the opened event (no
  hardware event per the docs).
- Addon channel messages go through `Core/Protocol.lua` and the queue in `Game/Sync.lua`. Protocol stays
  version 1; older Guildy versions drop unknown message kinds silently.
- All six locales get every new string (`tests/test_locales.lua`). Guild-chat lines go out in the poster's
  language; keep them short and lead with date and time.
- Smallest window size 1130 x 560 must still fit the tab, including the form.

## Approaches considered

**Where it lives** (three mocks, `media/gallery/mock/events-a|b|c.png`, script `media/gallery/mock_events.py`):

1. A — own tab, a table of events with the create form docked permanently on the right.
2. **B — own tab, agenda on the left, the picked event with everyone who answered on the right (picked).**
3. C — no tab, a "Nächste Ereignisse" box in Overview, the form as a dialog. Lightest, but no room for who
   comes, and Overview loses a box.

Sven picked B, with A's form shown in place of the event on the right after "Neues Ereignis"
(`media/gallery/mock/events-b-form.png`). Reason: people look up who comes far more often than they create.

**How events are created:**

1. Open Blizzard's own create window from Guildy and hook `AddEvent` to announce. Least code, Blizzard's look,
   but no per-event announce switch.
2. **Guildy's own form calling `C_Calendar` itself (picked by Sven).** Everything inside Guildy, with an
   "announce in guild chat" checkbox.

**Reminder in guild chat:**

1. None; only the creation line and the highlight in Guildy.
2. **One reminder 30 minutes before, posted by exactly one Guildy user (picked by Sven),** plus a local
   reminder for Guildy users.

## Decided

**Tab (Sven: B).** Registered like the others, `UI.RegisterTab("events", 7.2, "TAB_EVENTS", Build)` (between
Bank and Blacklist; order number is the builder's call).

- Toolbar: segmented "Kommende n" (only upcoming in this version, so it may also be a plain count label —
  builder's call), checkbox "Nur meine offenen" (events the player has not answered), and on the right a red
  "Neues Ereignis" button shown only when `CanEditGuildEvent()` is true.
- Left (about a third of the width): upcoming events grouped "Diese Woche" / "Nächste Woche" / "Später"
  (groups by calendar week, builder's call). Each row: big day number with weekday under it, a small square in
  the type's color, title, time and type name, a lock mark when locked, the player's own answer on the right
  ("offen" in gold when not answered, else the calendar's state name and color), and the headcount
  (n signed green tick, n tentative yellow "?", n declined red cross; counts only known for events the client
  has opened, see "Loading").
- Right, the picked event: title, a badge with the type, full date, time, "heute in 3 Std." when close, and
  creator; the description; "Du bist nicht angemeldet" (or the current answer) with the three buttons
  Anmelden / Vorläufig / Absagen, where the current answer replaces its own button; a bar split by signed /
  tentative / declined; then the names grouped "Angemeldet · n", "Vorläufig · n", "Abgelehnt · n" in class
  colors with class icons, four columns; then "Zusagen nach Klasse" (count per class of the signed). At the
  bottom a link "Im Blizzard-Kalender öffnen" (edit, delete, invite single players there) and, for creators
  or ranks with the permission, a dim hint that editing happens there.
- A locked event shows its answer as text, no buttons.
- The first upcoming event is picked when the tab opens.
- Empty state: "Keine Gilden-Ereignisse im Kalender." and, for ranks allowed, the "Neues Ereignis" button
  centered (principle 4: the empty state is normal and must look finished).

**Form (Sven: A's form, in place of the right side).** "Neues Ereignis" replaces the event panel with:

- Name (required, Blizzard's title length limit), Art as five buttons Schlachtzug / Dungeon / PvP / Treffen /
  Sonstiges (Sonstiges preselected, like Blizzard's window), Wann: a date dropdown (today and the next days,
  builder picks how far, at least 4 weeks), hour 00–23, minute in 5-minute steps, and "in n Tagen" next to it,
  Beschreibung (multi-line), "Im Gildenchat ankündigen" (ticked), "Ereignis sperren" with the hint "keine
  Antworten mehr möglich", and the dim line "Erinnerung 30 Minuten vorher im Gildenchat und bei
  Guildy-Nutzern". Buttons Abbrechen and Erstellen.
- Erstellen: `CreateGuildSignUpEvent()`, `EventSetTitle`, `EventSetType`, `EventSetDate`, `EventSetTime`,
  `EventSetDescription`, `EventSetLocked` when ticked, then `AddEvent()`, all inside the click handler.
  Guildy always creates a **sign-up** event (Sven asked for sign-ups), never a pure guild announcement.
- Errors are shown in the form, never swallowed: date in the past, empty name, no permission, free trial, and
  whatever the client reports (`CALENDAR_ACTION_PENDING` / error events, `Enum.CalendarErrorType`). On
  success the form closes and the new event is picked once it appears in the list.
- With "Im Gildenchat ankündigen" ticked, after success one line in guild chat, e.g.
  `[Guildy] Neues Ereignis: Geschmolzener Kern – Fr 04.12., 20:00. Anmelden im Kalender.`

**Reminders (Sven: guild chat and Guildy users, fixed 30 minutes).**

- Local, for every Guildy user: at 30 minutes before start, for each answerable guild event whose own answer is not
  "declined", one line in the chat frame with the Guildy tag ("Geschmolzener Kern beginnt in 30 Min. · du
  bist nicht angemeldet · Anmelden", the last word a clickable link to the tab) and the event highlighted in
  the tab. Logging in after the 30-minute mark but before the start gives the line once with the real minutes.
  Once per event per character.
- Guild chat, exactly one poster. At the 30-minute mark every online Guildy user whose option allows posting
  runs this:
  1. Wait: the event's creator 0 seconds, everyone else a random 3–20 seconds.
  2. If a claim for this event arrived meanwhile, or the reminder line for it was already seen in guild chat,
     do nothing.
  3. Otherwise send a claim (new message kind, e.g. `EVR`, payload event id + start time) on the addon
     channel, wait 2 seconds, and post only if no claim from a name with a smaller key arrived in those 2
     seconds.
  4. Line: `[Guildy] Geschmolzener Kern beginnt in 30 Min. (20:00). Anmelden im Kalender.`
  Older Guildy versions don't take part (they drop `EVR`). With no Guildy user online, nothing is posted.
  Accepted risk: two posts when claims arrive late (lag spikes, a client throttled by its send queue). The
  claim should skip the normal queue or go first in it.
- Event identity across clients: the event id plus start time. The builder confirms in game that
  `eventID` is the same on two characters; if not, title + start time is the key.
- "Creator" for step 1: the builder finds it from the opened event (`modStatus` "CREATOR" or the invite list's
  creator flag). If it can't be known cheaply without opening each event, every client waits randomly.

**Which events get reminders (Sven, after the builder check).** Every guild event people can answer, whoever
created it and with whatever tool (Guildy or Blizzard's window). Pure guild announcements get no reminder;
they are listed in the tab without answer buttons, headcount or "offen".

**Invite-type events (my call, after the builder check).** Guild events that use invitations instead of
open sign-up are answered too: the three buttons map to the invite calls (`EventAvailable` /
`EventTentative` / `EventDecline`), and the tab shows Blizzard's own state names for them. One code path with
a mapping, no second UI. "offen" means: no answer given yet, in either kind.

**Raid and dungeon without a dungeon picture (Sven, after the builder check).** The builder tests in game
whether Schlachtzug and Dungeon events can be created with no dungeon picked (Forever's list is empty). If
`AddEvent` or the server refuses them, Guildy creates the event as Sonstiges and puts the type in front of the
title ("Schlachtzug: Geschmolzener Kern"); the form keeps all five buttons and shows no error for this. Titles
that start that way are shown with the type's color and name in the tab.

**Options (my calls).** Two switches in Guildy's options, both on by default: "Erinnerung vor Gilden-Ereignissen"
(local reminder) and "Erinnerungen im Gildenchat posten" (take part in posting; some people don't want an
addon writing in their name). The announce line at creation is controlled only by the form's checkbox.

**Loading (my call).** `OpenCalendar()` once a little after login (for reminders) and when the tab opens.
The list comes from `GetGuildEventInfo`. Names and counts come from opening an event: the picked event is
opened at once; the counts in the left list for other events are filled by opening them one after another in
the background while the tab is shown (never in combat), and cached per event id until
`CALENDAR_UPDATE_INVITE_LIST` or the guild events list changes. Events not yet opened show no counts (blank,
not zero). Opening an event must not disturb Blizzard's calendar if the player has it open: if
`CalendarFrame` is shown, Guildy does not open events in the background.

## Left to the builder

- Exact layout numbers, fonts and widget reuse (`UI/Widgets.lua`), how the "Später" group and long titles are
  cut, colors for the five types (mock: raid orange, dungeon blue, PvP red, meeting green, other grey).
- Whether the hour/minute dropdowns follow the 12/24-hour setting of the client (Blizzard's window does).
- Which client events signal success or failure of `AddEvent`, and how long to wait before treating silence
  as failure.
- Wording in all six locales, following the plain style of the existing texts.
- In-game checks: GetNumGuildEvents range (how far ahead it lists), whether answering needs the event opened
  first, eventID stability across characters, and the Forever names of the calendar states.
- Tests: pure parts (week grouping, reminder due times, the poster rule with claims, chat line building, form
  validation) in `Core/` with tests in `tests/`.

## Changed after the first test in game (2026-11-22)

- WoW Forever blocks `SendChatMessage` to `GUILD` outside a click or key press (`ADDON_ACTION_BLOCKED` from a
  calendar event handler). So the creation line goes out inside the Erstellen click, before the server has
  confirmed the event (a refusal afterwards leaves a line about an event that does not exist; rare, since
  name, date and time are checked first). The guild chat reminder is no longer posted by a timer: the
  reminder line carries a link [Gilde erinnern] that posts it; whoever clicks first posts, the others' links
  say it was posted once the line is seen. The `EVR` claim and the poster rule are gone.
- `CanEditGuildEvent()` said no for an officer who may create guild events: the "Neues Ereignis" button
  always shows, and the server's refusal is shown in the form.
- Who answered is counted with `C_Calendar.GetNumInvites()` (`EventGetNumInvites` does not exist).
- The Events tab glows while there is an unanswered event not yet seen in the tab (per character).
- Editing and deleting moved into Guildy (Sven, 2026-11-22): "Bearbeiten" fills the form with the event and
  saves with `UpdateEvent`; "Löschen" asks first and removes it with `ContextMenuSelectEvent` +
  `ContextMenuEventRemove`. Both show only where `ContextMenuEventCanEdit` / `EventCanEdit` allow it.
  Inviting single players stays in Blizzard's calendar.
- Dungeon and raid picker in the form (Sven): the Hall of Fame's catalog with picture and level range; the
  dungeon is found again from its name in the title. The signed-up are grouped by role (tank, healer,
  damage, unknown) from the talent spec Guildy knows.
- Guild chat lines now wait for the player's next key press (Sven: "it needs to work 100%"): an invisible
  frame with `EnableKeyboard` + `SetPropagateKeyboardInput(true)` sees every key (moving, jumping) and
  passes it on; queued lines go out inside that key press. The announcement is a box in the form again
  (queued once the server lists the event); the reminder is posted again by one Guildy user (the `EVR`
  claim is back), the winner's line waits for their next key press and is dropped if the line shows up in
  guild chat first. The [Gilde erinnern] link is gone; the announce button stays for events made without the box.
