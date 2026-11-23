-- /guildy stress [count]: the guild as a guild of `count` members (default 1000), for testing what a big
-- guild costs with a small one. The real members are copied under made-up names until the count is
-- reached, in Guildy's roster (Game/Roster.lua reads through Stress.Count/Info/LastOnline) and in what
-- Blizzard's own member list reads (C_Club.GetClubMembers and C_Club.GetMemberInfo are wrapped), and
-- the roster is asked for every REQUEST_EVERY seconds, as often as a guild of a thousand sends it.
-- Nothing of the made-up members is kept or sent: no saved member data while it is on (Store, Roster,
-- Activity), no addon messages (Game/Sync.lua), no profession scan (Game/Harvest.lua).
-- Wrapping C_Club taints Blizzard's guild window for the session: /reload once the test is done.
local _, ns = ...

local Stress = {}
ns.Stress = Stress

Stress.on = false
Stress.total = 1000
Stress.REQUEST_EVERY = 1.5
Stress.FAKE_ID = 900000 -- memberIds of the made-up members in C_Club start above this

-- a made-up name suffix per index: "ab", "ac", ... (lowercase, so it reads as a name)
local function Suffix(i)
  local a, b, c = i % 26, math.floor(i / 26) % 26, math.floor(i / 676) % 26
  return string.char(97 + c, 97 + b, 97 + a)
end
Stress.Suffix = Suffix

-- "Name-Realm" or "Name" with the suffix after the name
local function FakeName(name, i)
  if type(name) ~= "string" then return name end
  local short, realm = name:match("^([^%-]+)(%-.*)$")
  if short then return short .. Suffix(i) .. realm end
  return name .. Suffix(i)
end
Stress.FakeName = FakeName

function Stress.Guid(i)
  return ("Player-0-F%07X"):format(i)
end

-- the real member a made-up member at roster index i copies (real: the real member count)
local function Base(i, real)
  return ((i - real - 1) % real) + 1
end

-- members in the guild as Guildy sees it
function Stress.Count(real)
  if not Stress.on or real <= 0 then return real end
  return math.max(real, Stress.total)
end

-- GetGuildRosterInfo(i), made up for indexes past the real members (a quarter of them online)
function Stress.Info(i, real)
  local get = rawget(_G, "GetGuildRosterInfo")
  if not Stress.on or i <= real or real <= 0 then return get(i) end
  local name, rank, rankIndex, level, className, zone, note, officerNote, _, status, classFile,
    points, achRank, _, soR, rep = get(Base(i, real))
  local online = i % 4 == 0
  return FakeName(name, i), rank, rankIndex, level, className, zone, note, officerNote, online, status, classFile,
    points, achRank, false, soR, rep, Stress.Guid(i)
end

-- GetGuildRosterLastOnline(i) likewise (made-up members were away i % 40 days)
function Stress.LastOnline(i, real)
  local get = rawget(_G, "GetGuildRosterLastOnline")
  if not Stress.on or i <= real or real <= 0 then return get(i) end
  if i % 4 == 0 then return 0, 0, 0, 0 end
  return 0, 0, i % 40, i % 24
end

-- Blizzard's side: C_Club's member list of the guild with the made-up members appended -------------

local original -- { GetClubMembers, GetMemberInfo } while wrapped
local ticker

local function GuildClub()
  return C_Club and ns.Try(C_Club.GetGuildClubId)
end

local function Wrap()
  if original or not C_Club then return end
  original = { GetClubMembers = C_Club.GetClubMembers, GetMemberInfo = C_Club.GetMemberInfo }
  local realIds = {}
  C_Club.GetClubMembers = function(clubId, streamId)
    local ids = original.GetClubMembers(clubId, streamId)
    if not (Stress.on and type(ids) == "table" and clubId == GuildClub() and #ids > 0) then return ids end
    realIds[clubId] = { unpack(ids) }
    local real = #ids
    for i = real + 1, Stress.total do ids[#ids + 1] = Stress.FAKE_ID + i end
    return ids
  end
  C_Club.GetMemberInfo = function(clubId, memberId)
    if not (Stress.on and type(memberId) == "number" and memberId > Stress.FAKE_ID) then
      return original.GetMemberInfo(clubId, memberId)
    end
    local ids = realIds[clubId] or original.GetClubMembers(clubId)
    local real = ids and #ids or 0
    if real == 0 then return nil end
    local i = memberId - Stress.FAKE_ID
    local info = original.GetMemberInfo(clubId, ids[Base(i, real)])
    if type(info) ~= "table" then return nil end
    local copy = {}
    for k, v in pairs(info) do copy[k] = v end
    copy.memberId, copy.guid, copy.name = memberId, Stress.Guid(i), FakeName(info.name, i)
    copy.isSelf = false
    local enum = rawget(_G, "Enum")
    local presence = enum and enum.ClubMemberPresence
    if presence then copy.presence = (i % 4 == 0) and presence.Online or presence.Offline end
    return copy
  end
end

local function Unwrap()
  if not original then return end
  C_Club.GetClubMembers, C_Club.GetMemberInfo = original.GetClubMembers, original.GetMemberInfo
  original = nil
end

-- /guildy stress [count]: on (with count members) or, without a count while on, off again
function Stress.Toggle(count)
  count = tonumber(count)
  if Stress.on and not count then
    Stress.on = false
    Unwrap()
    if ticker then ticker:Cancel() end
    ticker = nil
    ns.Roster.Request(true)
    ns.Print("stress off: /reload to have Blizzard's guild window clean again")
    return
  end
  Stress.total = math.max(1, math.floor(count or 1000))
  Stress.on = true
  Wrap()
  if not ticker then
    ticker = C_Timer.NewTicker(Stress.REQUEST_EVERY, function()
      if IsInGuild() then ns.Roster.Request(true, true) end
    end)
  end
  ns.Roster.Request(true)
  ns.Print(("stress on: the guild as %d members (copies of the real ones, nothing kept or sent). "
    .. "/guildy stress again: off, then /reload"):format(Stress.total))
end
