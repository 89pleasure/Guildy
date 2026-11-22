-- The guild's blacklist in the game (Core/Blacklist.lua holds the rules): officers from the roster,
-- adding and removing from this client, sharing every change at once (Game/Sync.lua, message BL).
local _, ns = ...

local GameBlacklist = {}
ns.GameBlacklist = GameBlacklist

local Rules = ns.Blacklist

-- Guild members and the player's own characters are never listed
local function IsProtected(name)
  if ns.Roster.IsMember(name) or ns.Names.Same(name, ns.PlayerName()) then return true end
  local db = ns.DB()
  return db ~= nil and type(db.ownChars) == "table" and db.ownChars[ns.Names.Key(name)] ~= nil
end

local ctx = { isOfficer = function(name) return ns.Roster.IsOfficer(name) end, isProtected = IsProtected }

function GameBlacklist.Ctx()
  return ctx
end

function GameBlacklist.IsProtected(name)
  return IsProtected(name)
end

-- The list of the current guild, nil outside a guild
function GameBlacklist.Book()
  local guild = ns.GuildData()
  return guild and Rules.Book(guild)
end

function GameBlacklist.CanRemove()
  return ns.Roster.IsOfficer(ns.PlayerName())
end

-- Adds or updates a name. seen = { c = classFile, l = level, f = "A" | "H" } from a unit, optional.
-- Returns the entry, or nil and "name" | "protected" | "removed" | "guild".
function GameBlacklist.Add(name, tag, reason, seen)
  local book = GameBlacklist.Book()
  if not book then return nil, "guild" end
  local entry, err = Rules.Add(book, name, tag, reason, ns.PlayerName(), ns.Now(), ctx, seen)
  if not entry then return nil, err end
  ns.Fire("BLACKLIST")
  ns.Sync.ShareBlacklist({ entry })
  return entry
end

-- Removes a name (officers). Returns the entry, or nil and "officer" | "missing" | "guild".
function GameBlacklist.Remove(name)
  local book = GameBlacklist.Book()
  if not book then return nil, "guild" end
  local entry, err = Rules.Remove(book, name, ns.PlayerName(), ns.Now(), ctx)
  if not entry then return nil, err end
  ns.Fire("BLACKLIST")
  ns.Sync.ShareBlacklist({ entry })
  return entry
end
