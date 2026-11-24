-- Families (main and twinks) of guild members. Pure: takes and returns tables.
-- Three sources, joined into groups:
--   * own characters: every character of the account that ran Guildy in a guild (GuildyDB.ownChars,
--     a set of keys)
--   * shared lists: Guildy users send their characters in the guild (FAM, Game/Sync.lua), kept as
--     guild.families[ownerKey] = FamilyRec = { ts, chars = { "Name", ... } }
--   * notes: a public or officer note naming another member with a twink word ("Twink von Ran Fred",
--     "Main: Ran Fred", "alt of Ran Fred")
local _, ns = ...

local Family = {}
ns.Family = Family

Family.MAX_CHARS = 20
-- words that mark a note as pointing at the member's main (or twink); lowercase, matched as words
Family.NOTE_WORDS = { "twink", "twinks", "alt", "alts", "main", "zweitchar", "hauptchar" }

-- A FamilyRec from the wire or SavedVariables, or nil when malformed
function Family.Validate(raw)
  if type(raw) ~= "table" or type(raw.ts) ~= "number" or type(raw.c or raw.chars) ~= "table" then return nil end
  local chars, seen = {}, {}
  for _, name in ipairs(raw.c or raw.chars) do
    if type(name) == "string" and name ~= "" and #chars < Family.MAX_CHARS then
      local normal = ns.Names.Normalize(name)
      local key = ns.Names.Key(normal)
      if not seen[key] then
        seen[key] = true
        chars[#chars + 1] = normal
      end
    end
  end
  if #chars == 0 then return nil end
  return { ts = raw.ts, chars = chars }
end

function Family.Wire(rec)
  return { ts = rec.ts, c = rec.chars }
end

-- Keeps rec as the family of owner when newer than what the guild has. Returns true when it changed.
function Family.Merge(guild, owner, rec)
  if type(guild) ~= "table" or not rec then return false end
  guild.families = type(guild.families) == "table" and guild.families or {}
  local key = ns.Names.Key(owner)
  local known = guild.families[key]
  if type(known) == "table" and type(known.ts) == "number" and known.ts >= rec.ts then return false end
  guild.families[key] = rec
  return true
end

-- { ownerKey = ts } for SUM
function Family.Digest(guild)
  local digest = {}
  for key, rec in pairs(type(guild) == "table" and type(guild.families) == "table" and guild.families or {}) do
    if type(rec) == "table" and type(rec.ts) == "number" then digest[key] = rec.ts end
  end
  return digest
end

-- Players on one account: two people sharing a WoW account sort its characters into players, and only
-- the characters of one player are a family. GuildyDB.ownChars[key] holds the player: true (as stored
-- before there were players) is player 1, else the number. nil for a character not of the account.
Family.MAX_PLAYERS = 3
function Family.Player(ownChars, key)
  local value = type(ownChars) == "table" and ownChars[key]
  if not value then return nil end
  if type(value) == "number" and value >= 2 and value <= Family.MAX_PLAYERS then return math.floor(value) end
  return 1
end

-- The own family records that changed, { [ownerKey] = FamilyRec }, from the account's characters in
-- the guild. Each character of the account that ever played sent a record under its own name, so a
-- record of each of them that lists other characters than its player's gets replaced (one name is
-- enough there: it replaces a merged record); the character played now (meKey) gets the record of its
-- player when that has two characters or more, as before. Records that stay the same keep their time.
-- memberKeys: { [key] = true } of the roster, nameOf: { [key] = name }, families: guild.families.
function Family.OwnRecords(ownChars, memberKeys, nameOf, families, meKey, now)
  families = type(families) == "table" and families or {}
  local byPlayer = {}
  for key in pairs(type(ownChars) == "table" and ownChars or {}) do
    if memberKeys[key] then
      local player = Family.Player(ownChars, key)
      byPlayer[player] = byPlayer[player] or {}
      table.insert(byPlayer[player], nameOf[key] or key)
    end
  end
  for _, chars in pairs(byPlayer) do table.sort(chars) end
  local changed = {}
  for key in pairs(type(ownChars) == "table" and ownChars or {}) do
    local chars = memberKeys[key] and byPlayer[Family.Player(ownChars, key)]
    local known = families[key]
    local knownChars = type(known) == "table" and type(known.chars) == "table" and known.chars or nil
    if chars and (knownChars or (key == meKey and #chars >= 2))
      and not (knownChars and table.concat(knownChars, ",") == table.concat(chars, ",")) then
      local copy = {}
      for i, name in ipairs(chars) do copy[i] = name end
      changed[key] = { ts = now, chars = copy }
    end
  end
  return changed
end

-- A character that is not of this account after all (a WTF folder copied from another player's PC
-- brings their characters along in GuildyDB.ownChars): takes key out of ownChars. Returns the record
-- that replaces the one under key in the guild, { ts, chars = { name } }, when that one lists another
-- character still of this account (the merged list this account sent for it), else nil: a record
-- the character's own player sent stays. Logging in with the character makes it one of the account's
-- again (TradeSkill's OwnMember).
function Family.Disown(ownChars, families, key, name, now)
  if type(ownChars) ~= "table" or not ownChars[key] then return nil end
  ownChars[key] = nil
  local known = type(families) == "table" and families[key]
  if type(known) ~= "table" or type(known.chars) ~= "table" then return nil end
  for _, other in ipairs(known.chars) do
    local otherKey = ns.Names.Key(other)
    if otherKey ~= key and ownChars[otherKey] then return { ts = now, chars = { name } } end
  end
  return nil
end

local function HasWord(text)
  for word in text:gmatch("[%a\128-\255]+") do
    for _, w in ipairs(Family.NOTE_WORDS) do
      if word == w then return true end
    end
  end
  return false
end

-- Members a note names together with a twink word, as keys: "Twink von Ran Fred" on Fredwild,
-- "Twinks: Fredwild, Ranfredo" on Ran Fred. note: the note text, selfKey: the note owner, members:
-- { {key, name} }. Names count as whole words; a longer name wins over one inside it ("Ran Fred"
-- over "Ran"); never the owner.
-- Looking through every member for every note took most of the member list's refresh in a big guild
-- (tests/bench.lua): the names of a roster are indexed once by their first word, and a note only
-- looks at the members whose first word it contains.
local indexes = setmetatable({}, { __mode = "k" }) -- members list -> { byWord = { word -> {entry} }, other = {entry} }

local function NameIndex(members)
  local index = indexes[members]
  if index and index.count == #members then return index end
  index = { byWord = {}, other = {}, count = #members }
  for i, m in ipairs(members) do
    local name = m.name and m.name:lower()
    if name and #name >= 3 then
      local entry = { key = m.key, name = name, order = i }
      -- a whole-word match of the name starts with its first word as a whole word of the note
      local word = name:match("^[%a\128-\255]+")
      local list = index.other
      if word then
        list = index.byWord[word]
        if not list then
          list = {}
          index.byWord[word] = list
        end
      end
      list[#list + 1] = entry
    end
  end
  indexes[members] = index
  return index
end

function Family.NoteLinks(note, selfKey, members)
  local links = {}
  if type(note) ~= "string" or note == "" then return links end
  local text = note:lower()
  if not HasWord(text) then return links end
  local index = NameIndex(members)
  local found = {}
  local function Look(entry)
    local name = entry.name
    local from = 1
    while true do
      local start = text:find(name, from, true)
      if not start then break end
      local stop = start + #name - 1
      local before, after = text:sub(start - 1, start - 1), text:sub(stop + 1, stop + 1)
      if not before:match("[%a\128-\255]") and not after:match("[%a\128-\255]") then
        -- the owner's own name only blocks names inside it ("Ran" in "Ran Fred")
        found[#found + 1] = { key = entry.key, start = start, stop = stop, len = #name, own = entry.key == selfKey,
          order = entry.order }
        break
      end
      from = start + 1
    end
  end
  local looked = {}
  for word in text:gmatch("[%a\128-\255]+") do
    if not looked[word] then
      looked[word] = true
      for _, entry in ipairs(index.byWord[word] or {}) do Look(entry) end
    end
  end
  for _, entry in ipairs(index.other) do Look(entry) end
  -- the longest name first, names of one length in roster order
  table.sort(found, function(a, b)
    if a.len ~= b.len then return a.len > b.len end
    return a.order < b.order
  end)
  local taken = {}
  for _, f in ipairs(found) do
    local free = true
    for _, t in ipairs(taken) do
      if f.start <= t.stop and f.stop >= t.start then free = false break end
    end
    if free then
      taken[#taken + 1] = f
      if not f.own then links[#links + 1] = f.key end
    end
  end
  return links
end

-- Groups of member keys: { [key] = groupId }. members: { {key, name, note, officerNote} } (the
-- roster), families: guild.families, ownChars: GuildyDB.ownChars. Only members of the roster count.
function Family.Groups(members, families, ownChars)
  local parent, inRoster, byKey = {}, {}, {}
  for _, m in ipairs(members) do
    parent[m.key] = m.key
    inRoster[m.key] = true
    byKey[m.key] = m
  end
  local function Find(key)
    while parent[key] ~= key do
      parent[key] = parent[parent[key]]
      key = parent[key]
    end
    return key
  end
  local function Join(a, b)
    if not (inRoster[a] and inRoster[b]) then return end
    local ra, rb = Find(a), Find(b)
    if ra ~= rb then parent[rb] = ra end
  end
  local function JoinAll(keys)
    local first
    for _, key in ipairs(keys) do
      if inRoster[key] then
        if first then Join(first, key) else first = key end
      end
    end
  end
  for owner, rec in pairs(type(families) == "table" and families or {}) do
    if type(rec) == "table" and type(rec.chars) == "table" then
      local keys = { owner }
      for _, name in ipairs(rec.chars) do keys[#keys + 1] = ns.Names.Key(name) end
      JoinAll(keys)
    end
  end
  -- the account's characters, one family per player on the account
  local own = {}
  for key in pairs(type(ownChars) == "table" and ownChars or {}) do
    local player = Family.Player(ownChars, key)
    own[player] = own[player] or {}
    table.insert(own[player], key)
  end
  for _, keys in pairs(own) do JoinAll(keys) end
  for _, m in ipairs(members) do
    for _, other in ipairs(Family.NoteLinks(m.note, m.key, members)) do Join(m.key, other) end
    for _, other in ipairs(Family.NoteLinks(m.officerNote, m.key, members)) do Join(m.key, other) end
  end
  local groups = {}
  for key in pairs(inRoster) do groups[key] = Find(key) end
  return groups, byKey
end

-- The other characters of member key, highest level first: { member, ... }
function Family.Of(key, members, families, ownChars)
  local groups, byKey = Family.Groups(members, families, ownChars)
  local group = groups[key]
  local list = {}
  if not group then return list end
  for other, id in pairs(groups) do
    if id == group and other ~= key then list[#list + 1] = byKey[other] end
  end
  table.sort(list, function(a, b)
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    return (a.name or "") < (b.name or "")
  end)
  return list
end

-- Guild notes in the form "Main, <group>" or "Alt, <main>": the kind ("main" or "alt") and the rest
-- (the guild's own group name like "Murloc Raid" or "Friends", or the main's name). Any group name
-- works; nothing is fixed to one guild. nil for other notes.
local KINDS = { main = "main", hauptchar = "main", alt = "alt", twink = "alt", zweitchar = "alt" }
function Family.ParseNote(note)
  if type(note) ~= "string" then return nil end
  local head, rest = note:match("^%s*([%a\128-\255]+)%s*[,:;%-]?%s*(.-)%s*$")
  local kind = head and KINDS[head:lower()]
  if not kind then return nil end
  return kind, rest ~= "" and rest or nil
end

-- Main of every member in a family: { [key] = mainKey } (members without family are left out).
-- The main is the one whose note says "Main", else the one an "Alt" note names, else the highest level.
function Family.Mains(members, families, ownChars)
  local groups, byKey = Family.Groups(members, families, ownChars)
  local byGroup = {}
  for key, id in pairs(groups) do
    byGroup[id] = byGroup[id] or {}
    table.insert(byGroup[id], byKey[key])
  end
  local named = {}
  for _, m in ipairs(members) do
    local kind = Family.ParseNote(m.note or "")
    if kind == "alt" then
      for _, other in ipairs(Family.NoteLinks(m.note, m.key, members)) do named[other] = true end
    end
  end
  local mains = {}
  for _, list in pairs(byGroup) do
    if #list > 1 then
      table.sort(list, function(a, b)
        local am, bm = Family.ParseNote(a.note or "") == "main", Family.ParseNote(b.note or "") == "main"
        if am ~= bm then return am end
        if (named[a.key] or false) ~= (named[b.key] or false) then return named[a.key] or false end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return (a.name or "") < (b.name or "")
      end)
      for _, m in ipairs(list) do mains[m.key] = list[1].key end
    end
  end
  return mains
end
