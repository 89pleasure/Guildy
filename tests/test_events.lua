local T = ...
local ns = T.pureNs()
local E = ns.Events

local LABELS = { raid = "Schlachtzug", dungeon = "Dungeon", pvp = "PvP", meeting = "Treffen", other = "Sonstiges" }
local DAYS = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }

T.describe("Events", function()
  T.it("turns a calendar time into minutes and back", function()
    for _, t in ipairs({ { 2026, 11, 22, 20, 0 }, { 2028, 2, 29, 0, 5 }, { 2026, 12, 31, 23, 55 }, { 2027, 1, 1, 0, 0 } }) do
      local stamp = E.Stamp(t[1], t[2], t[3], t[4], t[5])
      T.eq({ E.Civil(stamp) }, t)
    end
    T.eq(E.Stamp(2027, 1, 1, 0, 0) - E.Stamp(2026, 12, 31, 23, 55), 5)
    T.eq(E.Stamp(2028, 3, 1, 0, 0) - E.Stamp(2028, 2, 28, 0, 0), 2 * 1440)
  end)

  T.it("knows the weekday, Monday first", function()
    T.eq(E.Weekday(E.Stamp(2026, 11, 22, 12, 0)), 7) -- a Sunday
    T.eq(E.Weekday(E.Stamp(2026, 11, 23, 0, 0)), 1)
    T.eq(E.Weekday(E.Stamp(2026, 12, 4, 20, 0)), 5)
  end)

  T.it("groups by calendar week, also over the new year", function()
    local now = E.Stamp(2026, 12, 30, 18, 0) -- a Wednesday
    T.eq(E.Group(E.Stamp(2027, 1, 3, 20, 0), now), "week") -- Sunday of the same week
    T.eq(E.Group(E.Stamp(2027, 1, 4, 20, 0), now), "next")
    T.eq(E.Group(E.Stamp(2027, 1, 11, 20, 0), now), "later")
    local sunday = E.Stamp(2026, 11, 22, 21, 0)
    T.eq(E.Group(E.Stamp(2026, 11, 23, 20, 0), sunday), "next")
  end)

  T.it("sorts the calendar's states into four answers", function()
    local expected = { [0] = "open", "yes", "no", "yes", "no", "maybe", "yes", "open", "maybe" }
    for status = 0, 8 do T.eq(E.Answer(status), expected[status], "status " .. status) end
    T.eq(E.Answer(nil), "open")
    T.eq(E.Counts({ { answer = "yes" }, { answer = "yes" }, { answer = "no" }, { answer = "maybe" }, { answer = "open" } }),
      { yes = 2, maybe = 1, no = 1, open = 1 })
  end)

  T.it("is due 30 minutes before the start, until it starts", function()
    local start = E.Stamp(2026, 12, 4, 20, 0)
    T.eq(E.Due(start, start - 31), nil)
    T.eq(E.Due(start, start - 30), 30)
    T.eq(E.Due(start, start - 1), 1)
    T.eq(E.Due(start, start), nil)
    T.eq(E.Due(start, start + 5), nil)
  end)

  T.it("lets only the smallest name key post", function()
    local claims = E.NewClaims()
    T.eq(E.ShouldPost(claims, "k", "mira"), true)
    E.AddClaim(claims, "k", "zora")
    T.eq(E.ShouldPost(claims, "k", "mira"), true)
    E.AddClaim(claims, "k", "mira")
    T.eq(E.ShouldPost(claims, "k", "mira"), true)
    E.AddClaim(claims, "k", "alva")
    T.eq(E.ShouldPost(claims, "k", "mira"), false)
    T.eq(E.Claimed(claims, "k"), true)
    T.eq(E.Claimed(claims, "other"), false)
  end)

  T.it("waits nothing for the creator and 3 to 20 seconds for others", function()
    T.eq(E.Wait(true, 0.7), 0)
    T.eq(E.Wait(false, 0), 3)
    T.eq(E.Wait(false, 1), 20)
  end)

  T.it("checks the form", function()
    local now = E.Stamp(2026, 11, 22, 18, 0)
    T.eq({ E.Validate("", now + 60, now) }, { nil, "name" })
    T.eq({ E.Validate("   ", now + 60, now) }, { nil, "name" })
    T.eq({ E.Validate("Geschmolzener Kern", now - 5, now) }, { nil, "past" })
    T.eq({ E.Validate("Geschmolzener Kern", now + 60, now) }, { true })
  end)

  T.it("puts the type in front of the title and reads it back", function()
    T.eq(E.TypedTitle("raid", "Geschmolzener Kern", LABELS), "Schlachtzug: Geschmolzener Kern")
    T.eq(E.TypedTitle("meeting", "Gildentreffen", LABELS), "Gildentreffen")
    T.eq({ E.ParseTitle("Schlachtzug: Geschmolzener Kern", LABELS) }, { "raid", "Geschmolzener Kern" })
    T.eq({ E.ParseTitle("Dungeon: Tiefschlund", LABELS) }, { "dungeon", "Tiefschlund" })
    T.eq({ E.ParseTitle("Angeln am See", LABELS) }, { nil, "Angeln am See" })
  end)

  T.it("writes dates and times short", function()
    T.eq(E.ShortDate(E.Stamp(2026, 12, 4, 20, 0), DAYS), "Fr 04.12.")
    T.eq(E.Clock(20, 0), "20:00")
    T.eq(E.Clock(7, 5), "07:05")
    T.eq(E.Key("Kern", 12), "Kern@12")
  end)

  T.it("knows the role from the talent spec, or the class when it has damage specs only", function()
    T.eq(E.RoleOf("WARRIOR_TANK", "WARRIOR"), "tank")
    T.eq(E.RoleOf("DRUID_BEAR", "DRUID"), "tank")
    T.eq(E.RoleOf("PRIEST_HEAL", "PRIEST"), "heal")
    T.eq(E.RoleOf("SHAMAN_RESTO", "SHAMAN"), "heal")
    T.eq(E.RoleOf("DRUID_CAT", "DRUID"), "dps")
    T.eq(E.RoleOf("PRIEST_SHADOW", "PRIEST"), "dps")
    T.eq(E.RoleOf(nil, "MAGE"), "dps")
    T.eq(E.RoleOf(nil, "PALADIN"), nil)
  end)

  T.it("maps the five types to Blizzard's numbers", function()
    T.eq(E.EnumOf("raid"), 0)
    T.eq(E.EnumOf("other"), 4)
    T.eq(E.TypeOf(2), "pvp")
    T.eq(E.TypeOf(5), "dungeon") -- the old heroic dungeon type
    T.eq(E.TypeOf(99), "other")
  end)
end)
