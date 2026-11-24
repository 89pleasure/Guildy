-- Controller mode (the game's gamepad interface): Blizzard's guild window lies under Guildy at alpha 0,
-- which the game's cursor still counts as visible. While Guildy covers it, its parts are marked as
-- ignored for the cursor (SmartNavigation_MarkFrameIgnored); Blizzard's own window shown clears them.
-- A tab built for the first time has the game collect the window's buttons again.
local T = ...

local function World(opts)
  opts = opts or {}
  local log = { ignored = {}, cleared = {}, refreshed = 0 }
  local world = dofile(T.testsDir .. "/wow.lua")(T, { setup = function(e)
    e.InputUtil = { IsGamepadUIEnabled = function() return opts.gamepad ~= false end }
    e.InCombatLockdown = function() return opts.combat == true end
    e.SmartNavigation_MarkFrameIgnored = function(f, alone) log.ignored[f] = alone and "alone" or true end
    e.SmartNavigation_ClearIgnoreStatus = function(f) log.ignored[f] = nil; log.cleared[f] = true end
    e.SMART_NAV_INPUT_DIRECTION = { LEFT = { dirKey = "left" }, RIGHT = { dirKey = "right" }, UP = { dirKey = "up" },
      DOWN = { dirKey = "down" } }
    log.anchors = {}
    e.CreateAnchor = function(point, relativeTo, relativePoint) return { point, relativeTo, relativePoint } end
    e.SmartNavigation_SetCustomCursorAnchorPointForFrame = function(f, anchor) log.anchors[f] = anchor end
    log.jumps = {}
    e.SmartNavigation_AddJumpNavigationOverride = function(button, dir, other)
      log.jumps[button] = log.jumps[button] or {}
      log.jumps[button][dir.dirKey] = other
    end
    e.SmartNavigation_ClearJumpNavigationOverridesInDirection = function(button, dir)
      log.jumps[button] = log.jumps[button] or {}
      log.jumps[button][dir.dirKey] = false
    end
    e.SmartNavigation = { RefreshButtonGroups = function(self, panel)
      if self == e.SmartNavigation and panel == e.CommunitiesFrame then log.refreshed = log.refreshed + 1 end
    end, SetTargetButtonForFrame = function(self, panel, button)
      if self == e.SmartNavigation and panel == e.CommunitiesFrame then log.target = button end
    end, GetCurrentButton = function() return log.current end }
    e.SmartNavigation.activeInfo = { frame = e.CommunitiesFrame }
    -- the game's menu system: the entries a menu was built with
    e.MenuUtil = { CreateContextMenu = function(owner, generator)
      local menu = { owner = owner, entries = {} }
      local root = {}
      function root:CreateTitle(text) menu.entries[#menu.entries + 1] = { title = text } end
      function root:CreateButton(text, fn)
        local entry = { text = text, fn = fn, enabled = true }
        menu.entries[#menu.entries + 1] = entry
        return { SetEnabled = function(_, on) entry.enabled = on end }
      end
      generator(owner, root)
      log.menu = menu
      return menu
    end }
    -- override bindings: key -> button name, per owner
    log.bindings = {}
    e.SetOverrideBindingClick = function(owner, _, key, name) log.bindings[key] = name end
    e.ClearOverrideBindings = function() log.bindings = {} end
    -- the game's frame manager: the popups it was handed
    log.popups = {}
    e.GamepadMode = { FrameControlsManager = {
      HandlePopupShown = function(_, f) log.popups[f] = "shown" end,
      HandlePopupHide = function(_, f) log.popups[f] = "hidden" end,
    } }
    -- every frame made, to find Guildy's member card
    local create = e.CreateFrame
    log.frames = {}
    e.CreateFrame = function(kind, ...)
      local made = create(kind, ...)
      log.frames[#log.frames + 1] = made
      -- its type, as in the game (a check button is a button)
      rawset(made, "IsObjectType", function(_, t) return t == kind or (t == "Button" and kind == "CheckButton") end)
      -- the template's close button, as in the game
      if select(3, ...) == "ButtonFrameTemplate" then rawset(made, "CloseButton", e.CreateFrame("Button", nil, made)) end
      return made
    end
  end })
  local env = world.env
  local host = env.CommunitiesFrame
  -- Blizzard's window and what lies in it: its member list, the member panel Guildy shows beside it, a
  -- dialog of its own, and Guildy's window (its child once embedded)
  local list, detail, dialog = env.CreateFrame("Frame"), env.CreateFrame("Frame"), env.CreateFrame("Frame")
  rawset(host, "GuildMemberDetailFrame", detail)
  rawset(host, "NotificationSettingsDialog", dialog)
  rawset(host, "GetChildren", function()
    return list, detail, dialog, rawget(env, "GuildyFrame")
  end)
  world.Fire("ADDON_LOADED", "Guildy")
  world.Fire("PLAYER_LOGIN")
  world.Fire("GUILD_ROSTER_UPDATE")
  world.RunTimers()
  world.log, world.list, world.detail, world.dialog = log, list, detail, dialog
  return world
end

T.describe("Controller mode", function()
  T.it("hides Blizzard's window under Guildy from the controller's cursor", function()
    local world = World()
    world.env.CommunitiesFrame:Show()
    local log = world.log
    T.eq(log.ignored[world.list], true) -- Blizzard's list under Guildy: never reached
    T.eq(log.ignored[world.detail], nil) -- the member panel beside Guildy can be reached
    T.eq(log.ignored[world.dialog], nil)
    T.eq(log.ignored[world.env.GuildyFrame], nil)
    T.eq(world.errors, {})
  end)

  T.it("lets the cursor into Blizzard's own window again when it is shown", function()
    local world = World()
    world.env.CommunitiesFrame:Show()
    world.ns.UI.ShowBlizzard(nil, true)
    T.eq(world.log.ignored[world.list], nil)
    T.eq(world.log.cleared[world.list], true)
    T.eq(world.errors, {})
  end)

  T.it("has the game collect the buttons again when a tab is built, once", function()
    local world = World()
    local ns, log = world.ns, world.log
    world.env.CommunitiesFrame:Show()
    local after = log.refreshed
    T.truthy(after >= 1, "the first tab")
    ns.UI.SelectTab("members")
    T.eq(log.refreshed, after + 1)
    ns.UI.SelectTab("chat")
    ns.UI.SelectTab("members")
    T.eq(log.refreshed, after + 1) -- built tabs keep their buttons
    T.eq(world.errors, {})
  end)

  T.it("starts the cursor on the tab of the view shown, not top left", function()
    local world = World()
    local ns, env = world.ns, world.env
    env.CommunitiesFrame:Show()
    world.RunTimers()
    T.truthy(world.log.target ~= nil and world.log.target == env.GuildyFrameTab1, "the chat tab")
    env.CommunitiesFrame:Hide()
    ns.UI.SelectTab("members")
    env.CommunitiesFrame:Show()
    world.RunTimers()
    T.truthy(world.log.target == env.GuildyFrameTab2, "the window comes back on the members")
    T.eq(world.errors, {})
  end)

  T.it("goes from one bottom tab to the next with left and right", function()
    local world = World()
    local env, log = world.env, world.log
    env.CommunitiesFrame:Show()
    local tabs = {}
    for i = 1, 20 do
      local tab = rawget(env, "GuildyFrameTab" .. i)
      if not tab then break end
      tabs[i] = tab
    end
    T.truthy(#tabs >= 8, "bottom tabs: " .. #tabs)
    for i, tab in ipairs(tabs) do
      local jumps = log.jumps[tab] or {}
      T.truthy(jumps.left == (tabs[i - 1] or false), "left of tab " .. i)
      T.truthy(jumps.right == (tabs[i + 1] or false), "right of tab " .. i) -- the bank's right: the hall of fame
    end
    T.eq(world.errors, {})
  end)

  T.it("goes up from a bottom tab into the chat's input line, not to the top", function()
    local world = World()
    local ns, env, log = world.ns, world.env, world.log
    env.CommunitiesFrame:Show()
    local input = ns.UI.TabView("chat").Input
    T.truthy(input ~= nil)
    T.truthy((log.jumps[env.GuildyFrameTab1] or {}).up == input, "chat tab: up to the input line")
    T.truthy((log.jumps[env.GuildyFrameTab4] or {}).up == input, "every bottom tab while the chat shows")
    T.truthy((log.jumps[input] or {}).down == env.GuildyFrameTab1, "down from the input line: the chat tab")
    T.truthy(log.anchors[input] and log.anchors[input][1] == "CENTER" and log.anchors[input][2] == rawget(input, "guildyPadSpot"), "the input line is measured from its left end")
    ns.UI.SelectTab("members") -- no input line there: the game's own choice
    T.eq((log.jumps[env.GuildyFrameTab1] or {}).up, false)
    T.eq(world.errors, {})
  end)

  T.it("finds member rows at their name, and goes along headings and toolbar in their order", function()
    local world = World()
    local ns, env, log = world.ns, world.env, world.log
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("members")
    local view = ns.UI.TabView("members")
    local row = view.List.rows[1]
    T.truthy(row and log.anchors[row] and log.anchors[row][2] == rawget(row, "guildyPadSpot"), "a row is measured from its left end")
    -- headings: each to the next shown one
    local shown = view.shown
    T.truthy(#shown >= 3, "headings: " .. #shown)
    for i = 1, #shown - 1 do
      local a, b = view.Headers[shown[i].key], view.Headers[shown[i + 1].key]
      T.truthy((log.jumps[a] or {}).right == b and (log.jumps[b] or {}).left == a, "heading " .. i)
    end
    -- a toolbar: everything focusable in it from left to right as it stands, text and hidden ones left out
    local bar = env.CreateFrame("Frame")
    local function At(kind, x, shown)
      local f = env.CreateFrame(kind)
      rawset(f, "GetLeft", function() return x end)
      if shown ~= false then f:Show() end
      return f
    end
    local search, check, reset, label, hidden = At("EditBox", 10), At("CheckButton", 300), At("Button", 500),
      At("Frame", 200), At("Button", 400, false)
    rawset(bar, "GetChildren", function() return reset, label, hidden, check, search end)
    ns.Pad.RowOf(bar)
    T.truthy((log.jumps[search] or {}).right == check, "search box, then the checkbox")
    T.truthy((log.jumps[check] or {}).right == reset and (log.jumps[reset] or {}).left == check, "then reset")
    T.eq(log.jumps[label], nil) -- text only
    T.eq(log.jumps[hidden], nil)
    T.eq(world.errors, {})
  end)

  T.it("switches the bottom tabs with the shoulder buttons while the window is open", function()
    local world = World()
    local ns, env, log = world.ns, world.env, world.log
    env.CommunitiesFrame:Show()
    T.eq(log.bindings, { PADLSHOULDER = "GuildyPadPrevTab", PADRSHOULDER = "GuildyPadNextTab" })
    T.eq(ns.UI.Current(), "chat")
    env.GuildyPadNextTab:GetScript("OnClick")(env.GuildyPadNextTab)
    T.eq(ns.UI.Current(), "members")
    T.truthy(log.target == env.GuildyFrameTab2, "the cursor follows to the tab")
    env.GuildyPadPrevTab:GetScript("OnClick")(env.GuildyPadPrevTab)
    env.GuildyPadPrevTab:GetScript("OnClick")(env.GuildyPadPrevTab) -- nothing left of the chat
    T.eq(ns.UI.Current(), "chat")
    env.CommunitiesFrame:Hide()
    env.GuildyFrame:Hide() -- (in the game it hides with its parent)
    T.eq(log.bindings, {}) -- closed: the shoulder buttons pick targets again
    env.CommunitiesFrame:Show()
    env.GuildyPadNextTab:GetParent():GetScript("OnEvent")(env.GuildyPadNextTab:GetParent(), "PLAYER_REGEN_DISABLED")
    T.eq(log.bindings, {}) -- combat: let go
    T.eq(world.errors, {})
  end)

  T.it("keeps frames that only work with the mouse from the cursor", function()
    local world = World()
    local ns, env, log = world.ns, world.env, world.log
    env.CommunitiesFrame:Show()
    -- the resize grip (a button with the size grabber art)
    local grips = 0
    for f, how in pairs(log.ignored) do
      if how == true and rawget(f, "_template") == nil and f ~= world.list then grips = grips + 1 end
    end
    T.truthy(grips >= 1, "the grip and other mouse-only frames")
    -- the chat timeline: the rail itself, not its day marks
    local alone = 0
    for _, how in pairs(log.ignored) do if how == "alone" then alone = alone + 1 end end
    T.truthy(alone >= 1, "the rail, without its marks")
    T.eq(world.errors, {})
  end)

  T.it("moves the cursor onto Blizzard's button laid over a Guildy button, so Cross clicks it", function()
    local world = World()
    local ns, env, log = world.ns, world.env, world.log
    env.CommunitiesFrame:Show()
    local close = ns.UI.frame.Close
    close:Show()
    rawset(close, "GetLeft", function() return 900 end)
    rawset(close, "GetBottom", function() return 500 end)
    rawset(close, "IsVisible", function() return true end)
    rawset(close, "IsEnabled", function() return true end)
    rawset(close, "GetEffectiveScale", function() return 1 end)
    rawset(env.UIParent, "GetEffectiveScale", function() return 1 end)
    log.current = close -- the controller's cursor came onto the close button
    close:GetScript("OnEnter")(close)
    local overlay = env.GuildySecureOverlay
    T.truthy(overlay and overlay:IsShown(), "Blizzard's button over it")
    log.target = nil
    world.RunTimers()
    T.truthy(log.target == overlay, "the cursor moved onto it")
    -- clicked: the overlay goes, the cursor back onto the close button
    log.current = overlay
    overlay:GetScript("PostClick")(overlay, "LeftButton", false)
    T.truthy(log.target == close, "back on the close button")
    -- the mouse: nothing moves
    log.current, log.target = nil, nil
    close:GetScript("OnEnter")(close)
    world.RunTimers()
    T.eq(log.target, nil)
    T.eq(world.errors, {})
  end)

  T.it("keeps a member's card while the controller's cursor is on their row", function()
    local world = World()
    local ns, env, log = world.ns, world.env, world.log
    env.CommunitiesFrame:Show()
    local row = env.CreateFrame("Button")
    row:Show()
    rawset(row, "IsMouseOver", function() return false end) -- the mouse is elsewhere
    log.current = row
    ns.UI.MemberTooltip(row, ns.Roster.Members()[1])
    local card
    for _, f in ipairs(log.frames) do
      if rawget(f, "owner") == row then card = f end
    end
    T.truthy(card and card:IsShown(), "the card shows")
    card:GetScript("OnUpdate")(card)
    T.eq(card:IsShown(), true) -- the cursor is on the row: the card stays
    log.current = nil
    card:GetScript("OnUpdate")(card)
    T.eq(card:IsShown(), false) -- the cursor moved on: gone
    T.eq(world.errors, {})
  end)

  T.it("opens dropdown menus as the game's own menus", function()
    local world = World()
    local ns, env, log = world.ns, world.env, world.log
    env.CommunitiesFrame:Show()
    local picked
    local anchor = env.CreateFrame("Button")
    ns.Widgets.OpenMenu(anchor, {
      { text = "Filter", isTitle = true },
      { text = "Mage", checked = true, onClick = function() picked = "mage" end },
      { text = "Rogue", disabled = true },
      { text = "Remove", action = function() end },
    })
    local menu = log.menu
    T.truthy(menu and menu.owner == anchor, "a game menu at the button")
    T.eq(#menu.entries, 4)
    T.eq(menu.entries[1].title, "Filter")
    T.truthy(menu.entries[2].text:find("Mage", 1, true) and menu.entries[2].text:find("|T", 1, true), "checked: marked")
    menu.entries[2].fn()
    T.eq(picked, "mage")
    T.eq({ menu.entries[3].enabled, menu.entries[4].enabled }, { false, false }) -- disabled, Blizzard action
    T.eq(rawget(env, "GuildyMenu"), nil) -- Guildy's own menu was never built
    T.eq(world.errors, {})
  end)

  T.it("hands windows outside the guild window to the controller while they show", function()
    local world = World()
    local ns, env, log = world.ns, world.env, world.log
    env.CommunitiesFrame:Show()
    ns.UI.ShowOptions("general")
    local options = ns.UI.Options()
    T.eq(log.popups[options], "shown")
    T.eq(options.SmartNavigationCloseHandler(), true) -- circle closes the options, not the guild window
    T.eq(options:IsShown(), false)
    T.eq(log.popups[options], "hidden")
    T.eq(world.errors, {})
  end)

  T.it("leaves everything alone with mouse and keyboard, and in combat", function()
    for _, opts in ipairs({ { gamepad = false }, { combat = true } }) do
      local world = World(opts)
      world.env.CommunitiesFrame:Show()
      world.ns.UI.SelectTab("members")
      world.RunTimers()
      T.eq(world.log.ignored[world.list], nil) -- Blizzard's window stays as it is
      T.eq(world.log.refreshed, 0)
      T.eq(world.log.target, nil)
      T.eq(world.log.jumps, {})
      T.eq(world.log.bindings, {})
      world.ns.Widgets.OpenMenu(world.env.CreateFrame("Button"), { { text = "A" } })
      T.eq(world.log.menu, nil) -- Guildy's own menu
      T.truthy(rawget(world.env, "GuildyMenu") ~= nil)
      T.eq(world.errors, {})
    end
  end)
end)
