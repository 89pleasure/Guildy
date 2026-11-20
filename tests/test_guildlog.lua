local T = ...
local ns = T.pureNs()
local GuildLog = ns.GuildLog

local LINES = {
  { kind = "join" }, { kind = "invite" }, { kind = "promote" }, { kind = "quit" },
  { kind = "remove" }, { kind = "demote" }, { kind = "join" }, { kind = "something new" },
}

T.describe("GuildLog", function()
  T.it("puts each kind in its group", function()
    T.eq(GuildLog.Group("join"), "join")
    T.eq(GuildLog.Group("invite"), "invite")
    T.eq(GuildLog.Group("quit"), "left")
    T.eq(GuildLog.Group("remove"), "left")
    T.eq(GuildLog.Group("promote"), "rank")
    T.eq(GuildLog.Group("demote"), "rank")
    T.eq(GuildLog.Group("something new"), nil)
    T.eq(GuildLog.Group(nil), nil)
  end)

  T.it("counts the groups, all lines in all", function()
    T.eq(GuildLog.Counts(LINES), { all = 8, join = 2, invite = 1, left = 2, rank = 2 })
    T.eq(GuildLog.Counts({}), { all = 0, join = 0, invite = 0, left = 0, rank = 0 })
  end)

  T.it("keeps the lines of a group in their order", function()
    local left = GuildLog.Filter(LINES, "left")
    T.eq(#left, 2)
    T.eq(left[1], LINES[4])
    T.eq(left[2], LINES[5])
    T.eq(#GuildLog.Filter(LINES, "rank"), 2)
  end)

  T.it("shows everything for all or an unknown filter", function()
    T.eq(GuildLog.Filter(LINES, "all"), LINES)
    T.eq(GuildLog.Filter(LINES, nil), LINES)
    T.eq(GuildLog.Filter(LINES, "gone"), LINES)
  end)

  T.it("has a color for every kind it groups", function()
    for _, kind in ipairs({ "join", "invite", "quit", "remove", "promote", "demote" }) do
      local c = GuildLog.Color(kind)
      T.eq(type(c), "table")
      T.eq(#c, 3)
    end
    T.eq(GuildLog.Color("something new"), nil)
  end)
end)
