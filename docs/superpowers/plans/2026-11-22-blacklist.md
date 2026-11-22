# Guild Blacklist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A guild-shared Blacklist: every Guildy user can add a player (with a kind and a reason), only officers remove, the list spreads to all Guildy users at once and catches up through the summary, and a listed player shows in tooltips and raises a throttled chat warning with a sound.

**Architecture:** A pure module `Core/Blacklist.lua` owns the data model, the merge rule (adds, tombstones, officer checks, future times), the wire format, the fingerprint and the alert throttle. `Game/Blacklist.lua` is the glue: officer ranks from the roster, local add/remove, unit sightings, tooltip line, alerts. `Game/Sync.lua` gets one message type `BL` and one summary field. `UI/TabBlacklist.lua` is the ledger tab (direction A).

**Tech Stack:** Lua 5.1 (WoW Forever, Interface 16001), tests with `luajit tests/run.lua` from the repo root (`tests/lib.lua` helpers, `tests/wow.lua` world for smoke tests), Pillow mocks only for reference.

**Spec:** `docs/superpowers/specs/2026-11-22-blacklist-design.md` (UI direction: `.impeccable/surfaces/ui-tabblacklist-lua.md`, mock `media/gallery/mock/blacklist-a.png`)

## Global Constraints

- Protocol stays version 1; older Guildy versions drop unknown message types and fields silently. The new type is `BL`, the new SUM field `x`.
- Everyone adds; only officers remove; only officers re-add a name that carries a tombstone.
- A removal or re-add is accepted when the person *named in it* (remover `xb` / adder `a`) holds an officer rank in the receiver's own roster, whoever relays it.
- Receivers drop any add or removal stamped more than 3600 s after their own `ns.Now()`.
- Guild members and the player's own characters (`GuildyDB.ownChars`) can't be added (checked when adding and on receipt).
- Alert at most once per name every 300 s, whatever the trigger; setting `blacklistAlert`, default `true`.
- Tags (codes → enUS / deDE labels): `kos` Kill on Sight / Kill on Sight, `ninja` Ninja looter / Ninja-Looter, `insult` Insults / Beleidigungen, `scam` Scammer / Betrüger, `other` Other / Sonstiges. Unknown code shows as `other`.
- Colors: kos (255,72,72), ninja (255,146,48), insult (196,128,255), scam (64,208,200), other (176,168,150).
- Reason capped at 60 characters, names at 64 (`Core/Tenure.lua` uses the same name cap).
- Every new string in all six locales (`tests/test_locales.lua`); names in pictures and tests made up.
- Never compare or store secret values (`ns.AnySecret`); nothing that needs secure code.
- In German texts: "Blacklist", "Eintragen", "Entfernen", players' words.

## Review Focus

1. A list relayed by a non-officer that contains a forged tombstone naming a non-officer: dropped, the entry stays (Task 1 test `drops a removal whose remover is no officer`).
2. Two clients whose lists differ only in an entry one of them rejected: they must not re-send the whole list at every summary (Task 3 test `offers the list once per pair of fingerprints`).
3. A name that later joins the guild: kept, no tooltip, no alert, greyed in the tab (Task 4 test `stays quiet for a name now in the guild`).
4. A name typed with odd case or extra spaces ("  krag eisenzahn "): one key, no duplicate (Task 1 test `keys names like the roster does`).
5. Whispers/invites in combat or instances where the sender is a secret value: no error, no alert (Task 4 test `ignores a secret sender`).

---

### Task 1: Pure list module — entries, local changes, merge

**Files:**
- Create: `Core/Blacklist.lua`
- Modify: `Guildy.toc` (after `Core/Tenure.lua`), `tests/lib.lua:73-77` (add `"Core/Blacklist.lua"` to `lib.PURE`), `tests/run.lua` (add `"test_blacklist.lua"` after `"test_tenure.lua"`)
- Test: `tests/test_blacklist.lua`

**Interfaces:**
- Produces (all in `ns.Blacklist`, `local _, ns = ...` style as in `Core/Tenure.lua`):
  - Entry shape stored per key in `guild.blacklist`: `{ n = name, t = tag, r = reason|nil, a = adder, at = addTime, c = classFile|nil, l = level|nil, f = "A"|"H"|nil, x = removeTime|nil, xb = remover|nil }`.
  - `Blacklist.TAGS = { "kos", "ninja", "insult", "scam", "other" }`, `Blacklist.Tag(code) -> code` (unknown → `"other"`), `Blacklist.REASON_MAX = 60`, `Blacklist.NAME_MAX = 64`, `Blacklist.FUTURE = 3600`.
  - `Blacklist.Book(guild) -> table` (creates `guild.blacklist`).
  - `Blacklist.IsLive(entry) -> bool` (`at` and (not `x` or `at > x`)).
  - `Blacklist.EventTime(entry) -> number` (`max(at or 0, x or 0)`).
  - `Blacklist.Add(book, name, tag, reason, adder, now, ctx, seen) -> entry|nil, err` — `ctx = { isOfficer = fn(name) -> bool, isProtected = fn(name) -> bool }`, `seen = { c, l, f }|nil`; errors `"protected"`, `"removed"` (tombstoned and adder no officer), `"name"`.
  - `Blacklist.Remove(book, name, remover, now, ctx) -> entry|nil, err` — err `"officer"`, `"missing"`.
  - `Blacklist.Merge(book, item, now, ctx) -> bool changed` — one received wire item (Task 2 defines the item; here it is the entry shape itself).
  - `Blacklist.Sorted(book, includeRemoved) -> list` newest `EventTime` first.

- [ ] **Step 1: Write the failing tests** in `tests/test_blacklist.lua` (`local T = ...; local ns = T.pureNs(); local BL = ns.Blacklist`), `NOW = 1800000000`, `ctx` with officers `{ ["alva abendrot"] = true }` and protected `{ ["hanno glutpfad"] = true }`:
  - `adds a name with kind and reason`: `Add(book, "Krag Eisenzahn", "kos", "campt den Friedhof", "Pell Quellgrund", NOW, ctx)` → `book["krag eisenzahn"]` equals `{ n = "Krag Eisenzahn", t = "kos", r = "campt den Friedhof", a = "Pell Quellgrund", at = NOW }`.
  - `keys names like the roster does`: adding `"  krag eisenzahn "` then `"Krag Eisenzahn"` leaves one key.
  - `caps the reason and maps unknown kinds`: a 70-character reason is stored at 60; tag `"zzz"` stored as `"other"`.
  - `refuses guild members and own characters`: `Add(... "Hanno Glutpfad" ...)` → `nil, "protected"`, book unchanged.
  - `only officers remove`: `Remove(book, "Krag Eisenzahn", "Pell Quellgrund", NOW+10, ctx)` → `nil, "officer"`; with `"Alva Abendrot"` → entry with `x = NOW+10, xb = "Alva Abendrot"`, `IsLive` false.
  - `only officers re-add a removed name`: after the removal, `Add` by `"Pell Quellgrund"` → `nil, "removed"`; by `"Alva Abendrot"` at `NOW+20` → live again, `x` kept.
  - `merges the newest event per name`: an item with `at = NOW-100` against a stored tombstone `x = NOW` → no change; an item with `x = NOW+5, xb = "Alva Abendrot"` against a live entry `at = NOW` → tombstoned.
  - `drops a removal whose remover is no officer`: item `{ n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = NOW, x = NOW+5, xb = "Pell Quellgrund" }` into an empty book → stored live, without `x`/`xb`.
  - `drops a re-add by a non-officer`: stored tombstone `x = NOW`, item add `at = NOW+5, a = "Pell Quellgrund"` → no change.
  - `drops times from the future`: item `at = NOW + 3601` → `Merge` returns false, book empty; `at = NOW + 3599` → stored.
  - `drops adds of protected names on receipt` and `rejects malformed items` (non-table, name not a string or longer than 64, `at` not a number).
  - `sorts newest first`: three entries → `Sorted` order by `EventTime`; removed ones only with `includeRemoved`.
- [ ] **Step 2: Run** `luajit tests/run.lua` — expected: the new tests FAIL (`ns.Blacklist` is nil), all others pass.
- [ ] **Step 3: Implement `Core/Blacklist.lua`** with the interfaces above. Keys via `ns.Names.Key(name)`, display name via `ns.Names.Normalize`. Merge keeps the newest valid add (`at`, its `n/t/r/a/c/l/f`) and the newest valid tombstone (`x/xb`) separately, so a late older add never overwrites a newer reason. Seen fields `c/l/f` from a merge only fill gaps, never overwrite.
- [ ] **Step 4: Run** `luajit tests/run.lua` — expected: all pass.
- [ ] **Step 5: Commit** `git add Core/Blacklist.lua Guildy.toc tests/lib.lua tests/run.lua tests/test_blacklist.lua` / `git commit -m "feat: blacklist data model and merge rule"`

### Task 2: Wire format, fingerprint, alert throttle

**Files:**
- Modify: `Core/Blacklist.lua`
- Test: `tests/test_blacklist.lua`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - Wire item = the stored entry table as is (short keys, JSON-safe); `Blacklist.Item(entry) -> table` copies only known fields.
  - `Blacklist.WIRE_ENTRIES = 40`; `Blacklist.Wire(book) -> { list, list, ... }` (keys sorted, 40 items per list).
  - `Blacklist.Apply(book, list, now, ctx) -> bool changed` (at most 2000 items looked at, each through `Merge`).
  - `Blacklist.Digest(book) -> { n = count incl. tombstones, m = newest EventTime, s = checksum }`, checksum = `(sum of at + x over all entries) % 2147483647`.
  - `Blacklist.Differs(mine, theirs) -> bool` (theirs not a table → true).
  - `Blacklist.Ahead(mine, theirs) -> bool` — `mine.m > theirs.m or (mine.m == theirs.m and mine.n > theirs.n)`.
  - `Blacklist.ALERT_GAP = 300`; `Blacklist.ShouldAlert(seen, key, now) -> bool` (records `seen[key] = now` when true).

- [ ] **Step 1: Write the failing tests**: `Wire` of 85 entries → 3 lists of 40/40/5 in key order; `Apply` of `Wire(a)` into empty `b` gives `Digest(b)` equal to `Digest(a)`; `Digest` changes when one `at` changes; `Differs({n=1,m=2,s=3}, nil)` true; `Ahead` cases (newer `m`; same `m`, more entries; behind → false); `ShouldAlert` true at `NOW`, false at `NOW+299`, true at `NOW+300`.
- [ ] **Step 2: Run** `luajit tests/run.lua` — expected: new tests FAIL.
- [ ] **Step 3: Implement** the functions above in `Core/Blacklist.lua`.
- [ ] **Step 4: Run** `luajit tests/run.lua` — expected: all pass.
- [ ] **Step 5: Commit** `git commit -am "feat: blacklist wire format, digest and alert throttle"`

### Task 3: Officers, local actions and sharing

**Files:**
- Create: `Game/Blacklist.lua` (in `Guildy.toc` after `Game/Roster.lua`)
- Modify: `Game/Roster.lua` (officer check), `Game/Sync.lua` (`BL` handler, SUM field `x`, sending), `tests/smoke.lua` (new describe block)
- Test: `tests/smoke.lua` → `T.describe("Blacklist", ...)`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - `Roster.IsOfficer(name) -> bool`: the member's `rankIndex`; `C_GuildInfo.GuildControlGetRankFlags(rankIndex + 1)`; if it returns a table with a boolean at index 3 (officer chat listen; verify the index with the wow-api `get_api` docs before coding), that decides; otherwise `rankIndex <= 1`. Not in the roster → false.
  - `ns.GameBlacklist.Ctx() -> ctx` (`isOfficer = Roster.IsOfficer`, `isProtected` = `Roster.IsMember(name)` or own character via `GuildyDB.ownChars[key]` or `ns.Names.Same(name, ns.PlayerName())`).
  - `GameBlacklist.Add(name, tag, reason, seen) -> entry|nil, err`, `GameBlacklist.Remove(name) -> entry|nil, err` — store, `ns.Fire("BLACKLIST")`, and `Sync.ShareBlacklist({ entry })`.
  - `GameBlacklist.CanRemove() -> bool` (`Roster.IsOfficer(ns.PlayerName())`).
  - `Sync.ShareBlacklist(entries|nil)`: `nil` sends the whole `Wire` (one `BL` message per list), else one message `{ e = { Item(entry), ... } }`.
  - `OnBlacklist(data, sender)` in `HANDLERS` as `BL = OnBlacklist`: `Apply(Book(guild), data.e, ns.Now(), Ctx())`; when changed `ns.Fire("BLACKLIST")`; counts `blacklistMessages`.
  - SUM: `full.x = Blacklist.Digest(guild.blacklist)` sent with the first slice only (like `b` and `j`). In `OnSummary`: if `whole and type(data.x) == "table" and Differs(mine, data.x) and Ahead(mine, data.x)` and `blOffered[senderKey] ~= mineState .. "|" .. theirState`, then after `7 + math.random() * 8` s send the whole list unless `blacklistMessages` grew meanwhile; record the pair in `blOffered`.

- [ ] **Step 1: Write the failing smoke tests** (world from `tests/wow.lua`; give the test roster an officer at rank 1 and a member at rank 4 as existing tests set ranks; stub `C_GuildInfo.GuildControlGetRankFlags` to return `{ true, true, rank <= 1 }` by rankOrder):
  - `adds a name and sends one BL message`: `GameBlacklist.Add("Krag Eisenzahn", "kos", "campt den Friedhof")` → entry stored, the outgoing queue holds one `BL` with `e[1].n == "Krag Eisenzahn"`.
  - `refuses removal by a non-officer`: as the rank-4 player `Remove` → `nil, "officer"`.
  - `takes a relayed removal named by an officer`: feed a `BL` from the rank-4 member with an item tombstoned by the rank-1 officer → entry not live.
  - `offers the list once per pair of fingerprints`: a SUM with an older `x` → one whole-list send after the timers; the same SUM again → no second send.
  - `an older Guildy's summary without x gets no offer`.
- [ ] **Step 2: Run** `luajit tests/run.lua` — expected: new tests FAIL.
- [ ] **Step 3: Implement** `Roster.IsOfficer`, `Game/Blacklist.lua` and the Sync changes above. Skip receiving while `ns.Anon.on` (as `OnJoined` does).
- [ ] **Step 4: Run** `luajit tests/run.lua` — expected: all pass.
- [ ] **Step 5: Commit** `git commit -am "feat: share the blacklist between Guildy users"` (include `Game/Blacklist.lua`, `Guildy.toc`).

### Task 4: Seeing listed players — tooltip, alerts, sightings

**Files:**
- Modify: `Game/Blacklist.lua`, `Core/Init.lua` (events), `Core/Store.lua:17-24` (`blacklistAlert = true`), `UI/Options.lua` (`BuildGeneral`: checkbox), `Locales/*.lua`
- Test: `tests/smoke.lua` (Blacklist block)

**Interfaces:**
- Consumes: Task 3.
- Produces:
  - `GameBlacklist.Find(name) -> entry|nil` — live and not now protected (a name in the guild returns nil: quiet).
  - `GameBlacklist.OnUnit(unit, trigger)`: only `UnitIsPlayer(unit)`, name from `ns.Names.FromUnit(UnitName(unit))`; if listed, fill missing `c/l/f` locally from `UnitClass`/`UnitLevel`/`UnitFactionGroup` (no send), then `Alert(entry, trigger)`.
  - `GameBlacklist.OnName(name, trigger)` for name-only triggers.
  - `GameBlacklist.Alert(entry, trigger)`: if `ns.Settings().blacklistAlert ~= false` and `ShouldAlert(seen, key, ns.Now())`: `ns.Print` the line and `PlaySound(SOUNDKIT.RAID_WARNING)` (pcall, fall back silently).
  - Tooltip: `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, fn)` when present, else `GameTooltip:HookScript("OnTooltipSetUnit", fn)`; adds `L.BL_TOOLTIP:format(tagLabel)` in the tag color and the reason below in (255,200,150).
  - Triggers in `Core/Init.lua`: `NAME_PLATE_UNIT_ADDED(unit)`, `PLAYER_TARGET_CHANGED` ("target"), `UPDATE_MOUSEOVER_UNIT` ("mouseover") next to the existing handlers; `GROUP_ROSTER_UPDATE` (each `party1..4`/`raid1..40` unit, trigger `"group"`); `PARTY_INVITE_REQUEST(name)` (`"invite"`); `CHAT_MSG_WHISPER(text, sender)` (`"whisper"`, inside the existing handler); `TRADE_SHOW` (unit `"NPC"`, `"trade"`). Every name passes `ns.AnySecret` first.
  - Locale keys (enUS / deDE): `BL_TOOLTIP` "Blacklist: %s" / same; `BL_ALERT` "Blacklist: %s %s" with trigger phrases `BL_SEEN` "is near you" / "ist in deiner Nähe", `BL_GROUP` "is in your group" / "ist in deiner Gruppe", `BL_INVITE` "invites you" / "lädt dich ein", `BL_WHISPER` "whispers you" / "flüstert dir", `BL_TRADE` "wants to trade" / "will handeln"; second line `BL_ALERT_REASON` "%s · %s (%s)" (kind · reason (adder)); option `OPT_BL_ALERT` "Warn when a blacklisted player shows up (chat and sound)" / "Warnen, wenn jemand von der Blacklist auftaucht (Chat und Ton)"; tag labels `BL_TAG_KOS`, `BL_TAG_NINJA`, `BL_TAG_INSULT`, `BL_TAG_SCAM`, `BL_TAG_OTHER` as in Global Constraints. Other four locales translated.

- [ ] **Step 1: Write the failing smoke tests**: `warns once per 5 minutes` (fire `NAME_PLATE_UNIT_ADDED` for a listed unit twice → one chat line, `PlaySound` called once; advance `ns.Now` by 300 → second line); `warns on whisper, invite and trade`; `fills class, level and faction from a seen unit`; `stays quiet for a name now in the guild`; `ignores a secret sender` (whisper with `SECRET` → no error, no line); `adds the tooltip line`; `respects the option` (`blacklistAlert = false` → no line).
- [ ] **Step 2: Run** `luajit tests/run.lua` — expected: new tests FAIL.
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run** `luajit tests/run.lua` — expected: all pass (locale test included).
- [ ] **Step 5: Commit** `git commit -am "feat: blacklist tooltip line and throttled warnings"`

### Task 5: The Blacklist tab (direction A) and `/guildy bl`

**Files:**
- Create: `UI/TabBlacklist.lua` (in `Guildy.toc` after `UI/TabBank.lua`)
- Modify: `Core/Init.lua` (slash `bl`), `Locales/*.lua`, `tests/smoke.lua` (tab list at line 368 gets `"blacklist"`; Blacklist block)
- Test: `tests/smoke.lua`

**Interfaces:**
- Consumes: Tasks 3–4 (`GameBlacklist.Add/Remove/CanRemove/Find`, `Blacklist.Sorted/Tag`).
- Produces: `UI.RegisterTab("blacklist", 7.5, "TAB_BLACKLIST", Build)`; view methods `view:Refresh()` (listens to `"BLACKLIST"` and `"ROSTER"`), `view:OpenAdd(name, seen)`.
- Layout exactly as the surface brief and mock A: toolbar `W.EditBox` search (name, reason) · `W.MenuButton` kind filter ("Alle Arten" + five kinds) · check "Ohne Grund n" · officers only check "Entfernte zeigen" · count `BL_COUNT` "%d entries · %d removed" / "%d Einträge · %d entfernt" · red `W.Button` "Eintragen". Inline add row (name box, kind menu, reason box, Eintragen, Abbrechen; from a target shows `BL_FROM_TARGET` "from target: %s, level %d" / "aus dem Ziel: %s, St. %d"). `W.ScrollList` rows: class icon and color (or "?"), kind mark + label in its color, reason or `BL_NO_REASON` ("no reason" / "kein Grund", orange), faction, level, adder, relative time (reuse the "vor 2 Std." helper the other tabs use), officers: dim × and on hover "Entfernen". Greyed rows: `BL_NOW_GUILD` "now in the guild · no warning" / "jetzt in der Gilde · keine Warnung"; removed section `BL_REMOVED` "Removed · %d" / "Entfernt · %d" with `BL_REMOVED_BY` "removed by %s" and "Wieder eintragen" (officers). Errors from `Add` print `BL_ERR_PROTECTED` "Guild members and your own characters can't be blacklisted." and `BL_ERR_REMOVED` "An officer removed this name; only officers can add it again."; empty list shows `BL_EMPTY` "Nobody on the blacklist yet. Press Add, or type /guildy bl on a target." (deDE: "Noch niemand auf der Blacklist. Eintragen drücken oder /guildy bl auf ein Ziel.").
- `/guildy bl` (target, adds with tag `other` and opens the tab with the row in edit) and `/guildy bl <name> [reason]`.
- If the nine tabs don't fit the smallest window (1130 px) in every locale, shorten labels with `W.Shorten` as other tabs do.

- [ ] **Step 1: Write the failing smoke tests**: `opens the blacklist tab` (in the every-tab loop); `lists entries newest first and greys a guild member`; `hides remove for non-officers`; `shows removed entries only to officers with the box ticked`; `/guildy bl adds the target`; `refuses a guild member from the add row with the message`.
- [ ] **Step 2: Run** `luajit tests/run.lua` — expected: new tests FAIL.
- [ ] **Step 3: Implement** `UI/TabBlacklist.lua` and the slash command.
- [ ] **Step 4: Run** `luajit tests/run.lua` — expected: all pass. Then compare against `media/gallery/mock/blacklist-a.png` with a screenshot in game (`/guildy shots` if it covers the tab, else by hand) at 1130 × 560 in German and Russian.
- [ ] **Step 5: Commit** `git commit -am "feat: Blacklist tab and /guildy bl"`

### Task 6: Right-click entry, docs

**Files:**
- Modify: `Game/Blacklist.lua` (menu entry), `README.md`, `docs/curseforge.md`, `CHANGELOG.md`, `Locales/*.lua` (`BL_MENU` "Add to Guildy blacklist" / "Zur Guildy-Blacklist hinzufügen")
- Test: `tests/smoke.lua`

- [ ] **Step 1:** Check the wow-api source for `Menu.ModifyMenu("MENU_UNIT_PLAYER", ...)` / `MENU_UNIT_TARGET` on Forever. If present, write the failing test `adds the menu entry for other players` (stub `Menu.ModifyMenu`, call the callback with a player context → one button `BL_MENU`; for a guild member none); if absent, skip the entry and note it in the changelog.
- [ ] **Step 2: Run** `luajit tests/run.lua` — FAIL (if the entry is built).
- [ ] **Step 3: Implement** it, opening the tab's add row with the name filled.
- [ ] **Step 4: Run** `luajit tests/run.lua` — all pass.
- [ ] **Step 5:** Changelog entry in the style of 1.9.10, README and CurseForge lines (English, plain). Commit `git commit -am "feat: blacklist menu entry; docs"`.
