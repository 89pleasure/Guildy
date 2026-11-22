# Guild-shared blacklist — design

Date: 2026-11-22. Started from a CurseForge request (tinchodin: "please, add a kill on sight shared with all
guildies"). Sven widened it: the list is for anyone the guild wants to be warned about, of either faction:
gankers, ninja looters, people who insult heavily, scammers. Name: **Blacklist** (Sven).

## Intent

A guild keeps one list of players it wants to be warned about. Every Guildy user in the guild has the same
list and is told when a listed player shows up near them or deals with them (group, whisper, trade). The
point is speed: a player flagged by one member should be known to the others within seconds, not at the next
login.

## Goals

- One list per guild (per guild entry in GuildyDB, which is keyed by name and ruleset since 1.9.9).
- Every Guildy user can add a name. Only officers can remove one.
- Each entry says why: a tag (kind) plus an optional free-text reason.
- Changes spread at once to everyone online. Whoever was offline catches up later through the summary.
- A listed player is noticed: a tooltip line, and a chat line plus warning sound when they show up or deal
  with the player.

## Non-goals

- No guild-chat or center-screen announcement ("X spotted in Stranglethorn"). Sven chose medium loudness.
- Nothing for members without Guildy, and no import from other blacklist addons.
- No per-player private list. The list is the guild's.
- No automatic action (declining invites, ignoring whispers). Guildy only warns.

## Anti-goals (a failure even if it works)

- A guildmate or one of the player's own characters ends up listed.
- A removed name comes back because an offline member's older copy re-spreads it.
- Alerts that spam: the same name alerting over and over while they run around you or whisper you.
- A non-officer able to remove entries, or to undo an officer's removal, by sending a crafted message.

## Constraints

- WoW Forever client (Interface 16001), Lua, tests with `luajit tests/run.lua` from the repo root.
- Names in Forever are "First Last" (`ns.PlayerName`, `ns.Names`). Keys come from `ns.Names.Key`.
- Addon channel messages go through `Core/Protocol.lua` (JSON, deflate, parts of 250 bytes) and the queue in
  `Game/Sync.lua`. Receivers rate-limit senders (`Proto.Allow`).
- All locales in `Locales/` get every new string (`tests/test_locales.lua` checks that).
- Pure logic lives in `Core/`, game glue in `Game/`, UI in `UI/`, as in the rest of the addon.
- Chat events may carry secret values on Forever (`ns.AnySecret`): never compare or store those.

## Approaches considered

1. **Change messages at once, plus catch-up through the summary (picked).** An add or remove sends one small
   message. The regular SUM carries a short fingerprint of the list, and when fingerprints differ, the side
   with newer entries sends the whole list. Fast and reliable, and it reuses what join dates already do.
2. Summary only. Less code, but a new name only spreads at the next summary, minutes later.
3. Change messages only. Fast, but anyone offline at the time never gets the entry.

Sven picked 1.

## Decided

**Who may change what (Sven).** Everyone may add; only officers remove. Officer rank = a rank whose flags allow
reading officer chat, from `C_GuildInfo.GuildControlGetRankFlags(rankOrder)`. If that call gives nothing to a
non-officer, the fallback is rank index 0 and 1 (Guild Master and the next rank). The builder checks in game
which one works and keeps the fallback either way.

**Own entries (Sven, 2026-11-22, after trying it in game).** Whoever added an entry may also remove it, and
rename it (a new entry plus the removal of the old one), as long as nobody else changed it since (the entry's
adder is still them). They may add back a name they removed themselves; a name an officer removed only
officers add back. A relayed removal counts when its remover is an officer or the adder of the add it
carries, and the receiver knows no newer add by someone else. Clicking a listed name opens the add row to
change its kind and reason (anyone).

**Relayed removals (Sven).** In a whole-list catch-up the list usually comes from a non-officer. A removal is
accepted when the officer *named in it* (the remover) holds an officer rank in the receiver's own roster,
whoever relays it. The accepted risk: someone could forge a removal in an officer's name. That can only take
names off, never put them on. A removal whose named remover is no officer (or not in the roster) is dropped
and never stored. A client that already stored a removal keeps it even if that officer later leaves.

**What an entry holds.** Per name key: display name, tag, optional reason (short, capped, e.g. 60
characters), who added it, when it was added. A removal keeps the key with a "removed at" time and who removed
it (a tombstone). Merge rule per key: the newest event wins (add time vs. removal time), so an old copy of an
add never beats a newer removal. Changing the tag or reason of a live entry is a new add with a newer time
(anyone may do it; builder may restrict it to the adder and officers). Tombstones are kept (they are small);
the builder may prune ones older than a long horizon (e.g. 180 days) if it is safe with the merge.

**Tags.** Kill on sight, Ninja looter, Insults/harassment, Scammer, Other. Stored as a short code so the
wire stays language-free; an unknown code (from a newer Guildy) shows as Other.

**Re-adding a removed name (Sven).** Only an officer may add a name back once it carries a tombstone. An add
newer than a tombstone is accepted only when its adder (named in the entry) holds an officer rank in the
receiver's roster, the same check as for removals. A non-officer's add of a removed name is refused in the
UI and dropped on receipt.

**Times (builder's call).** Times are the sender's server time. Receivers drop any add or removal stamped
more than an hour after their own clock, so a fake future date can't pin an entry.

**Who can be listed (Sven).** Any player who is not in the guild and not one of the player's own characters,
of either faction. Typed names are accepted on that basis too.

**Names (Sven, 2026-11-22).** Only names a Forever character can have: first and last name, letters only,
each part capitalized. Guildy fixes the case itself ("hakuna matata" -> "Hakuna Matata") and refuses digits,
marks, a missing last name or a third word, locally and on receipt. Length 2 to 24 letters per part
(generous until Forever's real limit is known). Entries stored before the check can still be removed.

**Who can't be added.** Current guild members and the player's own characters (`GuildyDB.ownChars`). Checked
when adding and again when receiving, so a crafted add of a guildmate is ignored too.

**A listed name that joins the guild later (builder's call).** The entry stays but goes quiet: no tooltip
line, no alert, shown greyed in the list as "now in the guild". Nobody's removal is faked for it.

**Sharing.** A new message type (e.g. `BL`) carries one or more entries, both for a single change and for the
whole list. SUM gets a new optional field with a fingerprint of the list (entry count incl. tombstones, newest
event time, a checksum over keys and times). An older Guildy ignores the field. When a summary's fingerprint
differs and this client has events newer than the sender's newest, it offers the whole list after a random
delay, skipping it if someone else sent the list meanwhile (same pattern as join dates in `OnSummary`), and
not again for the same pair of fingerprints (a difference that stays, e.g. a rejected removal, must not cause
an offer on every summary). A list too big for one message is split like the join dates are.

**Noticing a listed player.**
- Tooltip: a red line "Blacklist: <tag> – <reason>" on any unit tooltip of a listed player.
- Alert (chat line with Guildy tag, name, tag, reason, who added it, plus a warning sound) when a listed player:
  - has their nameplate appear (`NAME_PLATE_UNIT_ADDED`), or is targeted or moused over;
  - joins the player's group or raid, or invites the player to one;
  - whispers the player;
  - opens a trade with the player.
- At most once per name every 5 minutes, whatever the trigger. Off switch in the options, default on.
- Never in a way that needs secure code. Works in combat (it only prints and plays a sound).

**Where it lives.**
- A new Blacklist tab in the guild window, direction A "ledger" (Sven picked it from three mocks:
  `media/gallery/mock/blacklist-a.png`, script `media/gallery/mock_blacklist.py`). It works like the Members
  tab:
  - toolbar: search (name, reason), kind dropdown ("Alle Arten"), checkbox "Ohne Grund n", for officers a
    checkbox "Entfernte zeigen", the count ("11 Einträge · 1 entfernt"), and a red "Eintragen" button;
  - "Eintragen" opens an inline add form as the list's first row: name, kind dropdown, reason, Eintragen,
    Abbrechen; from a target it fills the name and shows faction and level;
  - columns: Name (class icon and color when known, "?" when only typed), Art (colored mark and label),
    Grund ("kein Grund" in orange when empty), Fraktion, St., Eingetragen von, Wann; newest first;
  - officers get a dim × per row and "Entfernen" on the row under the mouse;
  - an entry whose name joined the guild is greyed: "jetzt in der Gilde · keine Warnung";
  - with "Entfernte zeigen", removed entries follow greyed under "Entfernt · n" with who removed them and
    "Wieder eintragen" (officers only).
- So entries can show class, level and faction, an entry added from a unit also stores those (optional
  fields; a typed name has none until the player is seen, then they are filled in locally).
- An optional "So warnt Guildy" preview (tooltip and chat line, as in mock B) may go into the options next to
  the alert switch.
- `/guildy bl` adds the current target (or the name given after it, `/guildy bl <name> [reason]`), tag Other
  unless changed in the tab.
- A right-click menu entry on other players' units, "Add to Guildy blacklist", where the client allows it
  without taint.

## Left to the builder

- Exact wire field names and tag codes, the checksum, how the whole list is split, and the delays.
- Whether the 9th tab fits the tab row; if not, make the tab labels or layout fit in the existing style.
- Which sound (a stock SOUNDKIT warning sound).
- Which events give group invites, group joins and trades on Forever, without touching secret values.
- Whether a right-click entry is possible on Forever without taint; if not, leave it out and say so.
- Layout of the tab, following the existing tabs and widgets (`UI/Widgets.lua`).
- Tests: the pure list module (add, remove, merge, tombstones, rejected removals and re-adds, rejected
  guildmates, future times, fingerprint), the sync flow (change message, catch-up after a differing
  fingerprint, no repeated offers), the alert throttle, and the smoke test of the tab.
- Changelog entry and README/CurseForge description lines, like earlier releases.
