-- The guild's blacklist, pure: players the guild wants to be warned about (gankers, ninja looters, insults,
-- scammers), shared between Guildy users (Game/Sync.lua, message BL). Everyone adds; only officers remove,
-- and only officers add a removed name back. A removal stays as a tombstone so an older copy of the add
-- can't bring the name back. Received removals and re-adds count when the person named in them (remover
-- xb, adder a) holds an officer rank in the receiver's roster, whoever relays them.
--   guild.blacklist = { [nameKey] = { n = name, t = tag, r = reason | nil, a = adder, at = time added,
--     c = classFile | nil, l = level | nil, f = "A" | "H" | nil, x = time removed | nil, xb = remover | nil } }
-- ctx = { isOfficer = function(name) -> bool, isProtected = function(name) -> bool } (guild members and the
-- player's own characters are protected: never listed)
local _, ns = ...

local Blacklist = {}
ns.Blacklist = Blacklist

Blacklist.TAGS = { "kos", "ninja", "insult", "scam", "other" }
Blacklist.REASON_MAX = 60
Blacklist.NAME_MAX = 64
Blacklist.FUTURE = 3600 -- seconds a received time may lie after the own clock

local KNOWN = {}
for _, tag in ipairs(Blacklist.TAGS) do KNOWN[tag] = true end

local max = math.max

function Blacklist.Tag(code)
  return KNOWN[code] and code or "other"
end

function Blacklist.Book(guild)
  if type(guild.blacklist) ~= "table" then guild.blacklist = {} end
  return guild.blacklist
end

function Blacklist.IsLive(entry)
  return type(entry) == "table" and type(entry.at) == "number" and (entry.x == nil or entry.at > entry.x)
end

function Blacklist.EventTime(entry)
  return max(entry.at or 0, entry.x or 0)
end

local function Reason(reason)
  if type(reason) ~= "string" then return nil end
  reason = ns.Names.Trim(reason)
  if reason == "" then return nil end
  return reason:sub(1, Blacklist.REASON_MAX)
end

local function Faction(f)
  return (f == "A" or f == "H") and f or nil
end

local function Level(l)
  return (type(l) == "number" and l == math.floor(l) and l >= 1 and l <= 200) and l or nil
end

local function Class(c)
  return (type(c) == "string" and c:match("^%u+$") and #c <= 16) and c or nil
end

local function ValidName(name)
  if type(name) ~= "string" or #name > Blacklist.NAME_MAX then return nil end
  local shown = ns.Names.Normalize(name)
  if shown == "" then return nil end
  return shown, ns.Names.Key(shown)
end

-- Fills class, level and faction where they are still missing
local function Fill(entry, seen)
  if type(seen) ~= "table" then return false end
  local changed = false
  for field, check in pairs({ c = Class, l = Level, f = Faction }) do
    local value = check(seen[field])
    if entry[field] == nil and value ~= nil then
      entry[field] = value
      changed = true
    end
  end
  return changed
end

-- Adds or updates a name from this client. Returns the entry, or nil and "name" | "protected" | "removed".
function Blacklist.Add(book, name, tag, reason, adder, now, ctx, seen)
  local shown, key = ValidName(name)
  if not shown then return nil, "name" end
  if ctx.isProtected(shown) then return nil, "protected" end
  local entry = book[key]
  if entry and entry.x and not ctx.isOfficer(adder) then return nil, "removed" end
  entry = entry or {}
  entry.n, entry.t, entry.r, entry.a, entry.at = shown, Blacklist.Tag(tag), Reason(reason), adder, now
  Fill(entry, seen)
  book[key] = entry
  return entry
end

-- Removes a name (officers). Returns the entry, or nil and "officer" | "missing".
function Blacklist.Remove(book, name, remover, now, ctx)
  if not ctx.isOfficer(remover) then return nil, "officer" end
  local _, key = ValidName(name)
  local entry = key and book[key]
  if not Blacklist.IsLive(entry) then return nil, "missing" end
  entry.x, entry.xb = now, remover
  return entry
end

local function Time(value, now)
  return type(value) == "number" and value == value and value > 0 and value <= now + Blacklist.FUTURE
end

-- Takes in one received entry. Returns whether anything changed.
function Blacklist.Merge(book, item, now, ctx)
  if type(item) ~= "table" then return false end
  local shown, key = ValidName(item.n)
  if not shown then return false end
  local entry = book[key]
  local changed = false
  -- the removal: newer than what is stored, named remover is an officer
  local x = Time(item.x, now) and type(item.xb) == "string" and ctx.isOfficer(item.xb) and item.x or nil
  -- the add: a valid time and adder, not a protected name; after a removal only from an officer
  local add = Time(item.at, now) and type(item.a) == "string" and item.a ~= "" and not ctx.isProtected(shown)
  if add then
    local tomb = max(x or 0, entry and entry.x or 0)
    if tomb > 0 and item.at > tomb and not ctx.isOfficer(item.a) then add = false end
  end
  if not entry then
    if not add then return false end -- a lone removal of an unknown entry: nothing to remove
    entry = {}
    book[key] = entry
  end
  if add and item.at > (entry.at or 0) then
    entry.n, entry.t, entry.r, entry.a, entry.at = shown, Blacklist.Tag(item.t), Reason(item.r), item.a, item.at
    changed = true
  end
  if x and x > (entry.x or 0) and entry.at then
    entry.x, entry.xb = x, item.xb
    changed = true
  end
  if add and Fill(entry, { c = item.c, l = item.l, f = item.f }) then changed = true end
  return changed
end

-- Entries newest first (by their last event); removed ones only when asked
function Blacklist.Sorted(book, includeRemoved)
  local list = {}
  for _, entry in pairs(book or {}) do
    if type(entry) == "table" and entry.at and (includeRemoved or Blacklist.IsLive(entry)) then
      list[#list + 1] = entry
    end
  end
  table.sort(list, function(a, b)
    local ta, tb = Blacklist.EventTime(a), Blacklist.EventTime(b)
    if ta ~= tb then return ta > tb end
    return a.n < b.n
  end)
  return list
end
