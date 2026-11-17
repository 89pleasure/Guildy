-- A guild member reaches level 60 in the stubbed client (tests/wow.lua): Guildy finds it in the roster
-- and shows the banner to this player. Nothing goes to guild chat.
local T = ...

local function World()
  local w = { sent = {}, guild = "Murloc Mafia" }
  w.roster = {
    { "Ran-Fred", "Offizier", 1, 60, "Druide", "Sturmwind", "", "", true, 0, "DRUID", nil, nil, false, nil, nil, "Player-1-01" },
    { "Makira-Farron", "Offizier", 1, 59, "Paladin", "Eisenschmiede", "", "", true, 0, "PALADIN", nil, nil, false, nil, nil, "Player-1-02" },
    { "Au-Tsch", "Haifutter", 2, 59, "Schurke", "Dämmerwald", "", "", true, 0, "ROGUE", nil, nil, false, nil, nil, "Player-1-03" },
  }
  w.tickers = {}
  local world = dofile(T.testsDir .. "/wow.lua")(T, { roster = w.roster, setup = function(env)
    env.C_Timer.NewTicker = function(seconds, fn)
      w.tickers[#w.tickers + 1] = { seconds = seconds, fn = fn }
      return { Cancel = function() end }
    end
    env.C_ChatInfo.SendChatMessage = function(text, kind) w.sent[#w.sent + 1] = { text, kind } end
    env.GetGuildInfo = function() return w.guild, "Haifutter", 1 end
  end })
  w.env, w.ns, w.errors, w.Fire, w.RunTimers = world.env, world.ns, world.errors, world.Fire, world.RunTimers
  w.Fire("ADDON_LOADED", "Guildy")
  w.Fire("PLAYER_LOGIN")
  w.Fire("GUILD_ROSTER_UPDATE")
  w.RunTimers()
  -- row i of the roster is level 60 now and the game says the roster changed; rounds = how often the
  -- timers run (1: only the roster scan)
  function w.Reach(rows, rounds)
    for _, i in ipairs(rows) do w.roster[i][4] = 60 end
    w.Fire("GUILD_ROSTER_UPDATE")
    w.RunTimers(rounds)
  end
  function w.Banner() return rawget(w.env, "GuildyDing") end
  return w
end

T.describe("Level 60", function()
  T.it("shows nothing after the first roster", function()
    local w = World()
    T.truthy(not (w.Banner() and w.Banner():IsShown()), "no banner for who is 60 already")
    T.eq(w.errors, {})
  end)

  T.it("shows the banner once and says nothing in guild chat", function()
    local w = World()
    w.Reach({ 2 })
    T.truthy(w.Banner():IsShown(), "banner shown")
    T.truthy(w.Banner().Name:GetText():find("Makira Farron", 1, true), "banner names the member")
    local banner = w.Banner()
    banner:GetScript("OnUpdate")(banner, 60)
    w.Fire("GUILD_ROSTER_UPDATE") -- the next roster: nothing again
    w.RunTimers()
    T.truthy(not banner:IsShown(), "no second banner")
    T.eq(w.sent, {})
    T.eq(w.errors, {})
  end)

  T.it("says nothing in guild chat even with the old option of 1.9.4 still saved", function()
    local w = World()
    w.ns.Settings().ding60Post = true
    w.Reach({ 2 })
    w.roster[1][4] = 59 -- the player's own level 60 neither
    w.Fire("GUILD_ROSTER_UPDATE")
    w.RunTimers()
    w.Fire("PLAYER_LEVEL_UP", 60)
    w.RunTimers()
    T.eq(w.sent, {})
    T.eq(w.errors, {})
  end)

  T.it("shows nothing with the banner option off", function()
    local w = World()
    w.ns.Settings().ding60 = false
    w.Reach({ 2 })
    T.truthy(not (w.Banner() and w.Banner():IsShown()), "no banner")
  end)

  T.it("shows two at once one after the other", function()
    local w = World()
    w.Reach({ 2, 3 })
    local banner = w.Banner()
    local first = banner.Name:GetText()
    banner:GetScript("OnUpdate")(banner, 1)
    T.eq(banner.Name:GetText(), first) -- still the first
    banner:GetScript("OnUpdate")(banner, 60)
    T.truthy(banner:IsShown(), "the second is shown")
    T.truthy(banner.Name:GetText() ~= first, "and it is another name")
    banner:GetScript("OnUpdate")(banner, 60)
    T.truthy(not banner:IsShown(), "hidden after the last")
    T.eq(w.errors, {})
  end)

  T.it("shows nobody of a guild the player has just changed to", function()
    local w = World()
    w.guild = "Other Guild"
    w.Reach({ 2 })
    T.truthy(not (w.Banner() and w.Banner():IsShown()), "no banner")
    w.Reach({ 3 }) -- from now on that guild is known
    T.truthy(w.Banner():IsShown(), "banner shown")
  end)

  T.it("shows the own level 60 at once, and not again when the roster shows it", function()
    local w = World()
    w.roster[1][4] = 59 -- Ran Fred, the player
    w.Fire("GUILD_ROSTER_UPDATE")
    w.RunTimers()
    w.Fire("PLAYER_LEVEL_UP", 59)
    w.RunTimers()
    T.truthy(not (w.Banner() and w.Banner():IsShown()), "no banner at 59")
    w.Fire("PLAYER_LEVEL_UP", 60)
    w.RunTimers()
    local banner = w.Banner()
    T.truthy(banner:IsShown(), "banner shown")
    T.truthy(banner.Name:GetText():find("Ran Fred", 1, true), "own name")
    banner:GetScript("OnUpdate")(banner, 60)
    w.Reach({ 1 })
    T.truthy(not banner:IsShown(), "no second banner")
    T.eq(w.errors, {})
  end)

  T.it("shows no second banner when the roster falls back a level for a moment", function()
    local w = World()
    w.Reach({ 2 })
    local banner = w.Banner()
    banner:GetScript("OnUpdate")(banner, 60)
    w.roster[2][4] = 59
    w.Fire("GUILD_ROSTER_UPDATE")
    w.RunTimers()
    w.Reach({ 2 })
    T.truthy(not banner:IsShown(), "no second banner")
  end)

  T.it("asks for the roster every 30 seconds, not for the event log, and not with the banner off", function()
    local w = World()
    local ticker
    for _, t in ipairs(w.tickers) do if t.seconds == 30 then ticker = t end end
    T.truthy(ticker, "a ticker of 30 seconds")
    local asked, logs = 0, 0
    w.env.C_GuildInfo.GuildRoster = function() asked = asked + 1 end
    w.env.QueryGuildEventLog = function() logs = logs + 1 end
    ticker.fn()
    T.eq({ asked, logs }, { 1, 0 })
    w.ns.Settings().ding60 = false
    ticker.fn()
    T.eq(asked, 1)
    T.eq(w.errors, {})
  end)

  T.it("shows the banner for the own character on /guildy ding", function()
    local w = World()
    w.env.SlashCmdList.GUILDY("ding")
    w.RunTimers()
    T.truthy(w.Banner():IsShown(), "banner shown")
    T.truthy(w.Banner().Name:GetText():find("Ran Fred", 1, true), "own name")
    T.eq(w.sent, {})
    T.eq(w.errors, {})
  end)

  T.it("has the banner option on the general page, and no chat option", function()
    local w = World()
    w.env.CommunitiesFrame:Show() -- J opens the guild window, Guildy follows
    w.RunTimers()
    w.ns.UI.ShowOptions("general")
    local panel = w.ns.UI.Options().Panels.general
    T.truthy(panel.Ding, "check box")
    T.eq(rawget(panel, "DingPost"), nil)
    T.eq(panel.Ding:GetChecked(), true)
    w.ns.Settings().ding60 = false
    panel:Refresh()
    T.eq(panel.Ding:GetChecked(), false)
    w.ns.Settings().ding60Post = false -- left over from 1.9.4
    panel.ResetAll:GetScript("OnClick")(panel.ResetAll)
    T.eq({ w.ns.Settings().ding60, w.ns.Settings().ding60Post }, {})
    T.eq(w.errors, {})
  end)
end)
