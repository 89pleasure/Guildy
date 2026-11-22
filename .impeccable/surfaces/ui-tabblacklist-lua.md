---
version: 1
slug: "ui-tabblacklist-lua"
primary_target: "UI/TabBlacklist.lua"
related_targets: []
---

# Blacklist tab

Scope: the guild's shared Blacklist tab in Guildy's window (UI/TabBlacklist.lua). Mode: Operate.
Jobs: add a player the guild should be warned about (ganker, ninja looter, insults, scammer) in seconds;
look someone up; officers clean the list up. Spec: docs/superpowers/specs/2026-11-22-blacklist-design.md.

Chosen 2026-11-22: variant A, "ledger" (mock: media/gallery/mock/blacklist-a.png, script
mock_blacklist.py). Rejected: B wanted card (list + detail card), C sections by kind.

## Direction contract

THESIS: The list reads and filters like the Members tab the player already knows; adding a name is one
inline row, not a dialog.
OWN-WORLD: Blizzard's guild window as Guildy draws it: the members box, gold column headings, striped rows,
FRIZQT, class colors on names, the game's red buttons, dropdowns and checkboxes.
STORY: The player was ganked or ninja-looted, opens the tab, presses Eintragen, the name is filled from
the target, picks the kind, types a reason, and every Guildy user in the guild has it seconds later.
FIRST VIEWPORT: Toolbar (search, kind dropdown, "Ohne Grund", "Entfernte zeigen" for officers, count,
Eintragen); table with Name, Art, Grund, Fraktion, St., Eingetragen von, Wann; × for officers.
Kind colors: Kill on Sight red, Ninja-Looter orange, Beleidigungen violet, Betrüger teal, Sonstiges grey.
