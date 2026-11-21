# Players on a shared account, and a FAQ tab

## Why

A CurseForge comment (2026-11-21): a guild's alts were assigned to the wrong players, two of them
sharing a last name. Note matching handles shared last names (checked with a test); the likely cause
is two people playing on one WoW account. Guildy joins every character of an account
(`GuildyDB.ownChars`) into one family, and each of those characters sent that merged list to the guild
as its family record (`FAM`), which every client keeps and passes on. There was no way to split it.

## Goals

- The players of a shared account can say which character is whose (player 1, 2 or 3).
- The merged records already in the guild get replaced, also on clients with older Guildy versions.
- A FAQ tab in the options answers this and a few other recurring questions.

Not included: a guild-wide unlink, overriding links that come from notes.

## Approaches

1. **Players on the shared account (picked).** The account sorts its characters into players; Guildy
   sends a newer record under each character that had one. Uses the existing `FAM` message, so older
   clients take the fix as they are.
2. Guild-wide manual unlink: fixes any wrong link, but a new message older clients ignore, and who may
   override whom.
3. Local unlink: each guild member would have to do it.

## Design

- **Stored:** the value of `GuildyDB.ownChars[key]` is the player number: `true` (as before) is
  player 1, `2` or `3` the others. Code that only asks "is this mine" keeps working. `Store` keeps 2 and
  3, everything else becomes `true`.
- **Grouping:** `Family.Groups` joins the account's characters only within one player.
- **Records:** `Family.OwnRecords` replaces `Family.Own`. For the character played now it builds the
  record of its player (as before: only with two characters or more); for every other character of
  the account it updates a record that is already there and lists other characters. A record that
  would shrink to one character is still sent (one name), so it replaces the merged one. Unchanged
  records keep their time stamp.
- **Sync:** the changed records are stored and sent (with the share setting, as before); the summaries
  offer them to everyone else as usual.
- **Options:** the Members tab gets "Characters on this account": the account's characters in the
  guild, each with a menu Player 1 / 2 / 3. A change regroups and sends at once.
- **FAQ tab:** last tab of the options, a scrolling list of questions and answers: wrong alt links, how
  alts are found, empty gear or talents, what is shared and how to turn it off. In all locales.
