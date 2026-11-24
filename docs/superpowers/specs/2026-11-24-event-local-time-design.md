# Event times in local time — design and steps

Date: 2026-11-24. CurseForge comment (mangalasolaris): "would it be possible in Events for it to use Local time?
Or at the least an option for it." Sven saw it as an option first and wanted no checkbox: always the player's
time zone.

## Intent

Players in another time zone than their realm read and enter event times on their own clock. Everyone else, and
everything other clients compare, stays as it is.

- Goal: the Events tab always shows and takes times in the player's time zone, the server's time beside it.
- Non-goal: an option, a time zone picker, 12-hour clock, local times in Blizzard's calendar.
- Anti-goal: reminders or claims that no longer match between Guildy users (`Events.Key` holds the stamp), or an
  event saved at another time than the form showed.

## Approaches

1. **Local time for everyone (picked by Sven).** Differs from Blizzard's calendar, so the server time stands
   beside it.
2. Follow the game clock's "Use local time" (`timeMgrUseLocalTime`): changes events for people who set the clock
   long ago and do not expect it.
3. An option of Guildy's own: built first, dropped.

## Decided

- Stamps stay the calendar's everywhere (`item.stamp`, keys, reminders, C_Calendar). Only `UI/TabEvents.lua`
  shifts, for display and in the form.
- Shift = local clock minus `C_DateAndTime.GetCurrentCalendarTime()`, rounded to 15 minutes. The local clock is
  `date("*t", ns.Now())`: the server's moment in the PC's zone, so a wrong PC clock does no harm.
- List: day, weekday, time and week group are local. Detail: local date and time, the server's behind it
  ("21:00 (Server 20:00)", with the date when the day differs). Delete prompt the same.
- Form: local in, server time shown behind "in n days". The form keeps the shift it was filled with.
- Guild chat lines stay server time: everyone reads them.
- Without a difference (shift 0) nothing looks different.
- Accepted: one shift for all dates. Where realm and player change to or from summer time on different days, an
  event after the next change can be an hour off until both have changed.

## Steps

1. `Events.Shift(localStamp, calendarStamp)` in `Core/Events.lua`; `GE.Shift()` in `Game/Events.lua`.
2. `UI/TabEvents.lua`: list, detail, delete prompt, form.
3. `EV_SERVER_TIME` in six locales. Tests in `tests/test_events.lua` and `tests/test_eventsflow.lua`.

Review focus: the local day differs from the server's; same time zone; no calendar time; editing without a
change keeps the event's time.
