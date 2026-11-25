-- The "Guildy Creator" line in the tooltips of the creator's characters (Game/Creator.lua)
local T = ...

local OWN = "Player-6949-00219DC4"

-- One client, with the tooltip processor of Forever
local function Boot()
  local callbacks = {}
  local world = dofile(T.testsDir .. "/wow.lua")(T, { setup = function(env)
    env.Enum = env.Enum or {}
    env.Enum.TooltipDataType = { Unit = 2 }
    env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
      T.eq(kind, 2)
      callbacks[#callbacks + 1] = fn
    end }
  end })
  local env, lines = world.env, {}
  local tip = env.GameTooltip
  rawset(tip, "GetUnit", function() return nil, nil end)
  rawset(tip, "IsForbidden", function() return false end)
  rawset(tip, "AddLine", function(_, text, r, g, b) lines[#lines + 1] = { text, r, g, b } end)
  world.Fire("ADDON_LOADED", "Guildy")
  world.Fire("PLAYER_LOGIN")
  local function Show(data, tooltip)
    for _, fn in ipairs(callbacks) do fn(tooltip or tip, data) end
    return #lines
  end
  local function Clear()
    lines = {}
    local cleared = tip:GetScript("OnTooltipCleared")
    if cleared then cleared(tip) end
  end
  return world, Show, Clear, function() return lines end, callbacks
end

T.describe("Creator tooltip", function()
  local world, Show, Clear, Lines, callbacks = Boot()
  local env = world.env
  local atLogin = #callbacks
  world.Fire("PLAYER_ENTERING_WORLD")
  world.Fire("PLAYER_ENTERING_WORLD") -- a loading screen

  T.it("hooks once, after the lines added at login", function() T.eq(#callbacks, atLogin + 1) end)

  T.it("marks every one of the creator's characters", function()
    for _, id in ipairs({ "00219DC4", "0021AECE", "0021A0D8", "05E29238" }) do
      Clear()
      T.eq(Show({ guid = "Player-6949-" .. id }), 1, id)
      T.eq(Lines()[1], { "|TInterface\\Icons\\INV_Shirt_GuildTabard_01:0|t Guildy Creator", 0, 229 / 255, 1 })
    end
  end)

  T.it("marks a tooltip once until it is cleared", function()
    Clear()
    Show({ guid = OWN })
    T.eq(Show({ guid = OWN }), 1)
  end)

  T.it("leaves everyone else alone", function()
    for _, guid in ipairs({ "Player-6949-00000000", "Player-5149-00219DC4", "Creature-0-0-0-0-6949-00219DC4" }) do
      Clear()
      T.eq(Show({ guid = guid }), 0, guid)
    end
    Clear()
    T.eq(Show({}), 0)
    T.eq(Show(nil), 0)
  end)

  T.it("asks the tooltip's unit when the data has no GUID", function()
    Clear()
    rawset(env.GameTooltip, "GetUnit", function() return "Ran", "target" end)
    local old = rawget(env, "UnitGUID")
    env.UnitGUID = function(unit) return unit == "target" and OWN or nil end
    T.eq(Show({}), 1)
    env.UnitGUID = old
    rawset(env.GameTooltip, "GetUnit", function() return nil, nil end)
  end)

  T.it("never looks into secret values, restricted data or other tooltips", function()
    Clear()
    local isSecret = env.issecretvalue
    env.issecretvalue = function(v) return v == OWN or isSecret(v) end
    T.eq(Show({ guid = OWN }), 0)
    env.issecretvalue = isSecret
    local restricted = setmetatable({}, { __index = function() error("restricted tooltip data") end })
    env.issecrettable = function(v) return v == restricted end
    T.eq(Show(restricted), 0)
    env.issecrettable = nil
    local other = setmetatable({}, { __index = function() error("another tooltip") end })
    callbacks[#callbacks](other, { guid = OWN })
    T.eq(#Lines(), 0)
    rawset(env.GameTooltip, "IsForbidden", function() return true end)
    T.eq(Show({ guid = OWN }), 0)
    rawset(env.GameTooltip, "IsForbidden", function() return false end)
    T.eq(world.errors, {})
  end)
end)
