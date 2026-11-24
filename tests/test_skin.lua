-- EllesmereUI's look (UI/Skin.lua): with EllesmereUI installed Guildy registers through its skinning API
-- and hands its window, boxes, buttons, tabs, input boxes and checkboxes to the S functions it gets back;
-- without it nothing changes.
local T = ...

-- A stand-in EllesmereUI: RegisterSkin keeps the callback, S notes every call as kind -> {frames}
local function World(opts)
  opts = opts or {}
  local eui = { registered = {} }
  local painted = {}
  local S = setmetatable({}, { __index = function(_, kind)
    return function(frame, extra)
      painted[kind] = painted[kind] or {}
      table.insert(painted[kind], { frame = frame, extra = extra })
    end
  end })
  local world = dofile(T.testsDir .. "/wow.lua")(T, { width = 1200, height = 700, setup = function(e)
    if opts.eui ~= false then
      e.EllesmereUI = eui
      function eui.RegisterSkin(name, callback) eui.registered[name] = callback end
    end
    -- the template each frame was made from
    local create = e.CreateFrame
    e.CreateFrame = function(kind, name, parent, template, ...)
      local frame = create(kind, name, parent, template, ...)
      rawset(frame, "_template", template)
      if rawget(frame, "SetAlpha") == nil then
        rawset(frame, "SetAlpha", function(self, a) rawset(self, "_alpha", a) end)
        rawset(frame, "GetAlpha", function(self) return rawget(self, "_alpha") or 1 end)
      end
      -- the template's close button and scroll bar, as in the game
      if template == "ButtonFrameTemplate" then rawset(frame, "CloseButton", create("Button", nil, frame, "UIPanelCloseButton")) end
      if template == "UIPanelScrollFrameTemplate" then rawset(frame, "ScrollBar", create("Slider", nil, frame)) end
      return frame
    end
  end })
  world.Fire("ADDON_LOADED", "Guildy")
  world.Fire("PLAYER_LOGIN")
  -- EllesmereUI calls back at login (unless skinning is off for Guildy)
  if opts.eui ~= false and opts.callback ~= false then eui.registered.Guildy(S) end
  world.Fire("GUILD_ROSTER_UPDATE")
  if not opts.noTimers then world.RunTimers() end
  world.eui, world.painted, world.S = eui, painted, S
  return world
end

local function Painted(world, kind, frame)
  for _, call in ipairs(world.painted[kind] or {}) do
    if call.frame == frame then return call end
  end
  return nil
end

local function Count(world, kind)
  return #(world.painted[kind] or {})
end

T.describe("EllesmereUI skin", function()
  T.it("registers under Guildy's name and paints the window, its tabs, boxes and buttons", function()
    local world = World()
    local ns = world.ns
    T.truthy(type(world.eui.registered.Guildy) == "function")
    world.env.CommunitiesFrame:Show()
    local frame = ns.UI.frame
    T.truthy(frame ~= nil)
    T.truthy(Painted(world, "Shell", frame), "the window gets EllesmereUI's backdrop")
    T.truthy(Painted(world, "CloseButton", frame.Close), "and its close glyph")
    T.eq(frame.Emblem:GetAlpha(), 0) -- no portrait, no emblem in its place
    T.truthy(Painted(world, "Button", frame.OptionsButton), "the cog is a flat button")
    T.eq(Painted(world, "Button", frame.OptionsButton).extra, { "Icon" }) -- its cog stays
    local tabs = 0
    for _, call in ipairs(world.painted.Tab or {}) do
      if rawget(call.frame, "_template") == "PanelTabButtonTemplate" or rawget(call.frame, "_template") == "UIPanelButtonTemplate" then
        tabs = tabs + 1
      end
    end
    T.truthy(tabs >= 8, "bottom tabs painted: " .. tabs)
    T.truthy(Count(world, "Panel") > 0, "the chat tab's boxes are panels")
    T.eq(world.errors, {})
  end)

  T.it("paints the boxes, buttons, input boxes and checkboxes of every tab", function()
    local world = World()
    local ns = world.ns
    world.env.CommunitiesFrame:Show()
    for _, key in ipairs({ "members", "overview", "professions", "events", "bank", "info", "ranks", "blacklist", "fame" }) do
      ns.UI.SelectTab(key)
    end
    ns.UI.ShowOptions("general")
    T.truthy(Painted(world, "Shell", ns.UI.Options()), "the options window too")
    T.truthy(Count(world, "Button") > 10, "buttons: " .. Count(world, "Button"))
    T.truthy(Count(world, "EditBox") > 0, "input boxes")
    T.truthy(Count(world, "Checkbox") > 0, "checkboxes")
    -- every one of Guildy's boxes, buttons and input boxes went to EllesmereUI
    for kind, template in pairs({ Checkbox = "UICheckButtonTemplate", EditBox = "InputBoxTemplate" }) do
      for _, call in ipairs(world.painted[kind]) do T.eq(rawget(call.frame, "_template"), template) end
    end
    T.eq(world.errors, {})
  end)

  T.it("gives scroll bars the slim bar in white instead of gold", function()
    local world = World()
    local ns = world.ns
    world.env.CommunitiesFrame:Show()
    ns.UI.SelectTab("members")
    local list = ns.UI.TabView("members").List
    T.truthy(list and rawget(list.ScrollBar, "guildySlim"), "the member list's bar is slim")
    T.eq(world.errors, {})
  end)

  T.it("paints frames made before EllesmereUI called back once it does", function()
    local world = World({ callback = false, noTimers = true })
    local ns = world.ns
    local box = ns.Widgets.Box(world.env.UIParent)
    T.eq(Count(world, "Panel"), 0)
    world.eui.registered.Guildy(world.S)
    T.truthy(Painted(world, "Panel", box))
    T.eq(world.errors, {})
  end)

  T.it("leaves everything as it is with skinning off for Guildy (no callback)", function()
    local world = World({ callback = false })
    local ns = world.ns
    world.RunTimers() -- the frames waiting for a callback are let go after login
    world.env.CommunitiesFrame:Show()
    world.eui.registered.Guildy(world.S) -- turned on later: only frames made from now on
    T.eq(Count(world, "Shell"), 0)
    T.truthy(rawget(ns.UI.frame.Emblem, "_alpha") ~= 0)
    T.eq(world.errors, {})
  end)

  T.it("changes nothing without EllesmereUI", function()
    local world = World({ eui = false })
    local ns = world.ns
    world.env.CommunitiesFrame:Show()
    ns.UI.SelectTab("members")
    T.eq(ns.Skin.Active(), false)
    T.eq(world.painted, {})
    T.eq(world.errors, {})
  end)
end)
