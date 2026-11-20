-- Shared runtime helpers: time, printing, safe calls, the player's name and a tiny internal event bus
-- (ns.On / ns.Fire) the UI listens to. Nothing here touches the game at load time.
local addonName, ns = ...

ns.ADDON = addonName or "Guildy"
ns.CHAT_TAG = "[Guildy]"

function ns.Now()
  local serverTime = rawget(_G, "GetServerTime")
  return serverTime and serverTime() or os.time()
end

function ns.DB()
  return rawget(_G, "GuildyDB")
end

function ns.Settings()
  local db = ns.DB()
  return db and db.settings or {}
end

function ns.Version()
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
  local version = getMeta and getMeta(ns.ADDON, "Version")
  if not version or version == "" or version:find("@", 1, true) then return "dev" end
  return version
end

-- Own full character name ("First Last"; Forever returns the last name as second value of UnitName)
function ns.PlayerName()
  return ns.Names.FromUnit(UnitName("player"))
end

-- Loads the interface anew (the language choice, /guildy shots all). False when the client has no way.
function ns.ReloadUI()
  local reload = rawget(_G, "ReloadUI") or (rawget(_G, "C_UI") and rawget(_G, "C_UI").Reload)
  if not reload then return false end
  reload()
  return true
end

function ns.Print(text)
  local frame = rawget(_G, "DEFAULT_CHAT_FRAME")
  local line = "|cffd4a017" .. ns.CHAT_TAG .. "|r " .. tostring(text)
  if frame and frame.AddMessage then frame:AddMessage(line) else print(line) end
end

-- Runs fn and reports errors through the client's error handler instead of breaking the caller
function ns.SafeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    local handler = rawget(_G, "geterrorhandler")
    if handler then handler()(err) else print(err) end
  end
  return ok
end

-- Forever has Retail's secret values: in instances and encounters chat texts and senders can be secret,
-- and addon code must not inspect them (no indexing, comparing or pattern matching).
function ns.IsSecret(value)
  local check = rawget(_G, "issecretvalue")
  return check ~= nil and check(value) == true
end

-- Chat messaging lockdown (battlegrounds, instances): the client's C_Club reads (communities, their
-- channels, members and messages, flagged SecretInChatMessagingLockdown in its API documentation)
-- answer with secret values then, so Guildy leaves the club data alone while it lasts
function ns.ChatLockdown()
  local info = rawget(_G, "C_ChatInfo")
  local check = type(info) == "table" and info.InChatMessagingLockdown
  return check ~= nil and ns.Try(check) == true
end

-- True when any of the values is secret
function ns.AnySecret(...)
  for i = 1, select("#", ...) do
    if ns.IsSecret((select(i, ...))) then return true end
  end
  return false
end

-- Calls fn(...) only if it exists; returns its results, or nil when missing or failing
-- (no table for the results: it is called for every item read, and a table per call was a third of the
-- garbage of reading an item's info)
local function Passed(ok, ...)
  if not ok then return nil end
  return ...
end
function ns.Try(fn, ...)
  if type(fn) ~= "function" then return nil end
  return Passed(pcall(fn, ...))
end

-- Internal events: "ROSTER" (roster changed), "PROFS" (profession data changed), "CHAT" (new chat line)
local listeners = {}

function ns.On(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
end

local function FireAll(event, ...)
  for _, fn in ipairs(listeners[event] or {}) do ns.SafeCall(fn, ...) end
end

function ns.Fire(event, ...)
  ns.Perf.Call("fire", event, FireAll, event, ...)
end

-- The realm for the guild key. GetNormalizedRealmName gave "" after a /reload and then at every login
-- (found in game 2026-11-20): Guildy made a guild "Murloc Mafia@" of its own and showed it empty. So
-- the realm name is asked too (without spaces and dashes, as the normalized name is), then the last one
-- known (kept in GuildyDB.lastRealm across sessions), then the server ID in the player's GUID
-- ("Player-<serverID>-<id>"), so a fresh install after the patch (client build 71037) or a guild
-- never seen still gets a key; nil while none is known.
local lastRealm

-- The server ID of the player's GUID as text, nil when the game gives none
local function ServerId()
  local guid = ns.Try(rawget(_G, "UnitGUID"), "player")
  if type(guid) ~= "string" or ns.IsSecret(guid) then return nil end
  return guid:match("^Player%-(%d+)%-")
end

function ns.Realm()
  local realm = ns.Try(rawget(_G, "GetNormalizedRealmName"))
  if type(realm) ~= "string" or realm == "" or ns.IsSecret(realm) then
    local name = ns.Try(rawget(_G, "GetRealmName"))
    realm = type(name) == "string" and not ns.IsSecret(name) and (name:gsub("[%s%-]", "")) or nil
  end
  local db = ns.DB and ns.DB()
  if realm and realm ~= "" then
    lastRealm = realm
    if db then db.lastRealm = realm end
  end
  return lastRealm or (db and type(db.lastRealm) == "string" and db.lastRealm ~= "" and db.lastRealm)
    or ServerId()
end

-- Tests: as after a fresh login, no realm known in this session
function ns._ForgetRealm()
  lastRealm = nil
end

-- The guild stored under name with some realm, the one with the most members: the realm text of the
-- client is not to be trusted (see ns.Realm), the guild's data must not get lost over it
local resolved = {} -- name .. "\0" .. realm text -> the stored guild key found for it (ns.GuildKey)
local function StoredGuildKey(db, name)
  local best, most
  local prefix = name .. "@"
  for key, guild in pairs(type(db) == "table" and type(db.guilds) == "table" and db.guilds or {}) do
    if type(key) == "string" and key:sub(1, #prefix) == prefix and #key > #prefix and type(guild) == "table" then
      local count = 0
      for _ in pairs(type(guild.members) == "table" and guild.members or {}) do count = count + 1 end
      if not most or count > most then best, most = key, count end
    end
  end
  return best
end

-- Current guild key: guild name + realm; a guild stored under that name with another realm text when
-- none is stored under it; nil when not in a guild or nothing is known to key it with
function ns.GuildKey()
  if not IsInGuild or not IsInGuild() then return nil end
  local name = GetGuildInfo("player")
  if not name then return nil end
  local realm, db = ns.Realm(), ns.DB and ns.DB()
  local key = realm and (name .. "@" .. realm)
  if db and type(db.guilds) == "table" and not (key and type(db.guilds[key]) == "table") then
    -- the search runs once per name and realm text in a session, while the guild it found is stored
    local asked = name .. "\0" .. tostring(realm)
    local found = resolved[asked]
    if not (found and type(db.guilds[found]) == "table") then
      found = StoredGuildKey(db, name)
      resolved[asked] = found
    end
    key = found or key
  end
  return key
end

-- Data of the current guild in GuildyDB (created on first use), nil when not in a guild. A guild
-- stored without a realm (see ns.Realm) goes into it once.
function ns.GuildData()
  local key, db = ns.GuildKey(), ns.DB()
  if not key or not db then return nil end
  local guild = ns.Store.Guild(db, key)
  local broken = key:match("^(.*@)")
  if broken and broken ~= key and type(db.guilds[broken]) == "table" then
    ns.Store.MergeGuild(db, broken, key)
  end
  return guild
end
