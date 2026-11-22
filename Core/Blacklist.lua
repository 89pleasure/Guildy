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

-- The game's markup (|c colors, |H links, |T textures) in text from other players shows as plain text: a
-- single "|" becomes "||" (a run of pipes of odd length gets one more, so text escaped once stays as it is)
local function Plain(text)
  return (text:gsub("|+", function(pipes) return #pipes % 2 == 1 and pipes .. "|" or pipes end))
end

-- The first REASON_MAX letters (UTF-8: a letter is a lead byte and its continuation bytes)
local function Letters(text, count)
  local n, cut = 0, #text
  for i = 1, #text do
    local byte = text:byte(i)
    if byte < 128 or byte >= 192 then
      n = n + 1
      if n > count then
        cut = i - 1
        break
      end
    end
  end
  return text:sub(1, cut)
end

local function Reason(reason)
  if type(reason) ~= "string" then return nil end
  reason = ns.Names.Trim(reason)
  if reason == "" then return nil end
  return Plain(Letters(reason, Blacklist.REASON_MAX))
end

local function Person(name)
  return type(name) == "string" and Plain(name) or nil
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
  if type(name) ~= "string" or #name > Blacklist.NAME_MAX or name:find("|", 1, true) then return nil end
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
  entry.n, entry.t, entry.r, entry.a, entry.at = shown, Blacklist.Tag(tag), Reason(reason), Person(adder), now
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
  entry.x, entry.xb = now, Person(remover)
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
  local function TakeAdd()
    entry.n, entry.t, entry.r, entry.a, entry.at = shown, Blacklist.Tag(item.t), Reason(item.r), Person(item.a), item.at
    changed = true
  end
  if add and item.at > (entry.at or 0) then TakeAdd() end
  if x and x > (entry.x or 0) and entry.at then
    entry.x, entry.xb = x, Person(item.xb)
    changed = true
    -- an edit by a non-officer made before this removal was known: the removal wins (the others refused
    -- that edit), and the entry takes the add they hold
    if entry.at > x and not ctx.isOfficer(entry.a) then
      if Time(item.at, now) and type(item.a) == "string" and item.at <= x then TakeAdd() else entry.at = x - 1 end
    end
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

-- Sharing ---------------------------------------------------------------------------------------------------

Blacklist.WIRE_ENTRIES = 40 -- entries a message carries
local WIRE_MAX = 2000         -- entries of a message that are looked at
local FIELDS = { "n", "t", "r", "a", "at", "c", "l", "f", "x", "xb" }

-- An entry as it goes on the wire: the known fields only
function Blacklist.Item(entry)
  local item = {}
  for _, field in ipairs(FIELDS) do item[field] = entry[field] end
  return item
end

-- The whole list as messages: lists of WIRE_ENTRIES items, in key order
function Blacklist.Wire(book)
  local keys = {}
  for key, entry in pairs(book or {}) do
    if type(entry) == "table" and entry.at then keys[#keys + 1] = key end
  end
  table.sort(keys)
  local messages = {}
  for i, key in ipairs(keys) do
    local at = math.floor((i - 1) / Blacklist.WIRE_ENTRIES) + 1
    messages[at] = messages[at] or {}
    messages[at][#messages[at] + 1] = Blacklist.Item(book[key])
  end
  return messages
end

-- Takes in a received list. Returns whether anything changed.
function Blacklist.Apply(book, list, now, ctx)
  if type(list) ~= "table" then return false end
  local changed = false
  for i = 1, math.min(#list, WIRE_MAX) do
    if Blacklist.Merge(book, list[i], now, ctx) then changed = true end
  end
  return changed
end

-- What a client knows, in three numbers: entries (removed ones too), the newest event, a checksum of times
function Blacklist.Digest(book)
  local digest = { n = 0, m = 0, s = 0 }
  for _, entry in pairs(type(book) == "table" and book or {}) do
    if type(entry) == "table" and type(entry.at) == "number" then
      digest.n = digest.n + 1
      digest.m = max(digest.m, Blacklist.EventTime(entry))
      digest.s = (digest.s + entry.at + (entry.x or 0)) % 2147483647
    end
  end
  return digest
end

function Blacklist.Differs(mine, theirs)
  if type(theirs) ~= "table" then return true end
  return mine.n ~= theirs.n or mine.m ~= theirs.m or mine.s ~= theirs.s
end

-- Whether this client should offer its list: it knows a newer event, or as new but more entries
function Blacklist.Ahead(mine, theirs)
  local m, n, sum = tonumber(theirs.m) or 0, tonumber(theirs.n) or 0, tonumber(theirs.s) or 0
  -- a tie of count and newest event (a removal one side missed) goes to the larger checksum, so one side offers
  return mine.m > m or (mine.m == m and (mine.n > n or (mine.n == n and mine.s > sum)))
end

-- Warnings -------------------------------------------------------------------------------------------------

Blacklist.ALERT_GAP = 300 -- seconds between two warnings about the same name

-- Whether to warn about key now; remembers the warning in seen
function Blacklist.ShouldAlert(seen, key, now)
  if seen[key] and now - seen[key] < Blacklist.ALERT_GAP then return false end
  seen[key] = now
  return true
end
