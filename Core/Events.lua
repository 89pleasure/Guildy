-- Guild events from the game's calendar, pure (docs/superpowers/specs/2026-11-22-guild-events-design.md):
-- calendar times as minutes, week groups, the four answers, the form's checks, the type in front of a
-- title (Game/Events.lua does the game).
-- A stamp is minutes since 1970-01-01 00:00 of the realm's calendar (no time zone: the calendar has none).
local _, ns = ...

local Events = {}
ns.Events = Events

local floor = math.floor

Events.TYPES = { "raid", "dungeon", "pvp", "meeting", "other" }
Events.LEAD = 30       -- minutes before the start the reminder comes (Blizzard's event has no field for it)
Events.TITLE_MAX = 31  -- the calendar's title length
Events.POST_ROOM = 25  -- the reminder is posted in guild chat only while at least this many minutes are left

-- Enum.CalendarEventType: Raid 0, Dungeon 1, PvP 2, Meeting 3, Other 4, HeroicDeprecated 5
local BY_ENUM = { [0] = "raid", "dungeon", "pvp", "meeting", "other", "dungeon" }
local ENUM_OF = { raid = 0, dungeon = 1, pvp = 2, meeting = 3, other = 4 }

function Events.TypeOf(enum)
  return BY_ENUM[enum] or "other"
end

function Events.EnumOf(kind)
  return ENUM_OF[kind] or 4
end

-- Days since 1970-01-01 of a date in the Gregorian calendar (H. Hinnant's days_from_civil)
local function Days(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = floor(y / 400)
  local yoe = y - era * 400
  local doy = floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
  local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

local function FromDays(z)
  z = z + 719468
  local era = floor(z / 146097)
  local doe = z - era * 146097
  local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  local mp = floor((5 * doy + 2) / 153)
  local d = doy - floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  return yoe + era * 400 + (m <= 2 and 1 or 0), m, d
end

function Events.Stamp(y, mo, d, h, mi)
  return Days(y, mo, d) * 1440 + (h or 0) * 60 + (mi or 0)
end

function Events.Civil(stamp)
  local days = floor(stamp / 1440)
  local rest = stamp - days * 1440
  local y, m, d = FromDays(days)
  return y, m, d, floor(rest / 60), rest % 60
end

-- 1 Monday ... 7 Sunday (1970-01-01 was a Thursday)
function Events.Weekday(stamp)
  return (floor(stamp / 1440) + 3) % 7 + 1
end

local function WeekStart(stamp)
  local day = floor(stamp / 1440)
  return day - (Events.Weekday(stamp) - 1)
end

-- "week" (this calendar week, Monday to Sunday), "next", "later"
function Events.Group(stamp, now)
  local weeks = (WeekStart(stamp) - WeekStart(now)) / 7
  if weeks <= 0 then return "week" end
  if weeks == 1 then return "next" end
  return "later"
end

-- Enum.CalendarStatus: Invited 0, Available 1, Declined 2, Confirmed 3, Out 4, Standby 5, Signedup 6,
-- NotSignedup 7, Tentative 8
local ANSWERS = { [0] = "open", "yes", "no", "yes", "no", "maybe", "yes", "open", "maybe" }

function Events.Answer(status)
  return ANSWERS[status] or "open"
end

function Events.Counts(invites)
  local counts = { yes = 0, maybe = 0, no = 0, open = 0 }
  for _, invite in ipairs(invites or {}) do
    local answer = counts[invite.answer] and invite.answer or "open"
    counts[answer] = counts[answer] + 1
  end
  return counts
end

-- true, or nil and "name" | "past"
function Events.Validate(title, stamp, now)
  if type(title) ~= "string" or not title:match("%S") then return nil, "name" end
  if type(stamp) ~= "number" or stamp <= now then return nil, "past" end
  return true
end

-- Raid and dungeon events need a dungeon picture the client of WoW Forever does not offer: they are made
-- as "other" with the type in front of the title, and read back as their type
function Events.TypedTitle(kind, title, labels)
  if (kind == "raid" or kind == "dungeon") and labels[kind] then return labels[kind] .. ": " .. title end
  return title
end

function Events.ParseTitle(title, labels)
  for _, kind in ipairs({ "raid", "dungeon" }) do
    local label = labels[kind]
    if label and title:sub(1, #label + 2) == label .. ": " then return kind, title:sub(#label + 3) end
  end
  return nil, title
end

-- The same on every character and client: title and start (the event ID is not known to be)
function Events.Key(title, stamp)
  return tostring(title) .. "@" .. tostring(stamp)
end

-- Minutes left when the reminder is due (0 < left <= LEAD), else nil
function Events.Due(stamp, now)
  local left = stamp - now
  if left > 0 and left <= Events.LEAD then return left end
  return nil
end

-- Seconds before claiming the guild chat reminder: the creator at once, the others spread out
function Events.Wait(isCreator, random)
  if isCreator then return 0 end
  return 3 + random * 17
end

-- Claims of the guild chat reminder (EVR on the addon channel): key -> { nameKey = true }
function Events.NewClaims()
  return {}
end

function Events.AddClaim(claims, key, nameKey)
  claims[key] = claims[key] or {}
  claims[key][nameKey] = true
end

function Events.Claimed(claims, key)
  return claims[key] ~= nil and next(claims[key]) ~= nil
end

-- Post only when no one with a smaller name key claimed the same reminder
function Events.ShouldPost(claims, key, myKey)
  for nameKey in pairs(claims[key] or {}) do
    if nameKey < myKey then return false end
  end
  return true
end

-- The role of a signed-up member for the groups in the Events tab: "tank" | "heal" | "dps", nil when not
-- known. spec: Core/Talents.lua's Decide (a key of Core/StatWeights.lua); classes with damage specs only
-- are "dps" without one.
local ROLES = { WARRIOR_TANK = "tank", PALADIN_PROT = "tank", DRUID_BEAR = "tank",
  PALADIN_HOLY = "heal", PRIEST_HEAL = "heal", SHAMAN_RESTO = "heal", DRUID_RESTO = "heal" }
local DAMAGE_ONLY = { HUNTER = true, ROGUE = true, MAGE = true, WARLOCK = true }
Events.ROLES = { "tank", "heal", "dps" }

function Events.RoleOf(spec, classFile)
  if spec then return ROLES[spec] or "dps" end
  if DAMAGE_ONLY[classFile] then return "dps" end
  return nil
end

-- "Fr 04.12." (monthFirst: "Fri 12/04")
function Events.ShortDate(stamp, dayNames, monthFirst)
  local _, m, d = Events.Civil(stamp)
  local day = dayNames[Events.Weekday(stamp)] or ""
  if monthFirst then return ("%s %02d/%02d"):format(day, m, d) end
  return ("%s %02d.%02d."):format(day, d, m)
end

function Events.Clock(h, mi)
  return ("%02d:%02d"):format(h, mi)
end
