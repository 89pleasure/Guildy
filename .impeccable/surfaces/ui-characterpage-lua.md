---
version: 1
slug: "ui-characterpage-lua"
primary_target: "UI/CharacterPage.lua"
related_targets: []
---

# Character page

Scope: the member's character page in Guildy's window (UI/CharacterPage.lua). Mode: Operate.
Jobs (confirmed 2026-11-13): ready for a raid or dungeon; weak slots and who in the guild could craft
better; looking at guildmates for fun; officers judging a promotion. Must keep: family, statistic tiles,
professions. The dungeon collection may go.

Chosen: variant A, "readiness" (mock: media/gallery/mock/character-a.png, script mock_character.py).
Pinned by Sven: the "Upgrades aus der Gilde" box (slot, better crafted item, its maker, online state,
"47 auf 58") is a must.

## Direction contract

THESIS: The page answers "is this member ready, and what would help?" at a glance; it refuses the
inspect-window copy where the answer hides in icons and tooltips.
OWN-WORLD: Blizzard's guild window as it stands: dark boxes with gold lines, FRIZQT, gold headings,
item names in quality colours, green enchantments, orange for what is missing.
STORY: The visitor sees the character, its gear slot by slot against the guild's ready mark, what lacks
an enchantment, and who in the guild can make the better piece, then whispers that crafter.
FIRST VIEWPORT: Left card: rotatable model on top, name, title, race/class, rank and zone, member since,
notes, whisper/invite. Right: four statistic tiles across; below, the gear list (slot, icon, name,
enchantment or "keine Verzauberung", item level bar with the ready tick, level) beside a column with
family, "Upgrades aus der Gilde" and professions.
FORM: candidate 3 of 7 (readiness ledger), seed: none (unavailable)
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Unresolved

- Where the upgrade data comes from (recipe -> crafted item -> slot and item level).
- The model for members who are offline (race, gender and items into the game's model frame).
