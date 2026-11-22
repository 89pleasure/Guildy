# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

(Recorded as `web` because the schema has no value for it: Guildy is a World of Warcraft addon. Its UI is
drawn in the game with WoW's widget API — Lua frames, font strings, textures — inside Blizzard's own guild
window. HTML and Pillow pictures exist only as mock-ups.)

## Users

Members and officers of guilds on WoW Forever, playing in German, English, French, Spanish, Russian or
Brazilian Portuguese. About 5000 installations (November 2026). The author plays in a guild of about a
hundred members, most still levelling.

## Product Purpose

Make the guild window worth opening: chat first, then members, professions, guild records and the bank.
Press J and you are in the guild chat. An addon can only read its own character, so Guildy collects the
rest — from its own character, from other Guildy users in the guild (shared and relayed), from what the
player hovers, targets or clicks, and from guild notes.

## Positioning

It lives in Blizzard's own guild window and looks like it belongs there, while knowing far more about the
guild than the game shows: what one Guildy user learns reaches every Guildy user in the guild.

## Operating Context

- Opened in the middle of play, often for a quick answer: who is online, who can craft this, who is ready.
- The window is resizable; its smallest size is 1130 x 560, where long translations run out of room first.
- Layers split the guild: an addon can only reach members on the same layer for some reads.
- `tools/bnet-sync` (the author's own script, not part of the addon) fills the saved data from the
  Battle.net profile API. Almost no user has it.

## Capabilities and Constraints

- Everything must work in the game alone, in every guild, without the script; the script only fills the
  same fields faster.
- No network access from the addon. Data about others arrives only through the guild addon channel
  (about ten messages in a burst, then one a second) or what the client hands out nearby.
- The game hands out secret values at times (in combat, in instances); addon code must not compare them.
- Older Guildy versions in the guild must never break: the protocol stays version 1, unknown fields and
  messages are dropped silently.
- Character page, its jobs (confirmed 2026-11-13, all four): check whether someone is ready for a raid or
  dungeon; see weak slots and who in the guild could craft better; look at guildmates' characters for the
  fun of it; let officers judge a promotion.
- Character page, what must stay (confirmed 2026-11-13): the family box (main and twinks), the statistic
  tiles (kills, quests, deaths, average item level with the place in the guild), professions. The dungeon
  collection may go or shrink.
- Undecided: how gear of members without Guildy reaches others (inspect nearby, sharing, the script).

## Brand Commitments

- Runs inside Blizzard's guild window and keeps Blizzard's look (README).
- Free and open source, GPL-3.0-or-later; nothing is copied from addons under other licences.
- Changelog and docs in plain, concrete language; German texts as players actually say them
  ("Cooldowns", not "Abklingzeiten").

## Evidence on Hand

- Reference screenshots of every view in six languages: `media/e2e/<language>/*.png` (git-ignored) and
  `media/gallery/src/crop/*.png`; the gallery JPGs in `media/gallery/`.
- The game's font `media/gallery/fonts/FRIZQT__.TTF` and a few icons; mock scripts drawing into real
  screenshots: `media/gallery/mock_*.py`.
- Names in pictures are made up (`Core/Anon.lua`); real member names do not go into published images.

## Product Principles

1. The game alone is enough; extra sources only make it faster.
2. Every Guildy user's knowledge serves the whole guild.
3. It belongs in Blizzard's window: familiar first, more capable second.
4. The empty state is often the normal one and must look finished.
5. Never break the guild for someone on an older version.
