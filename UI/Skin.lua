-- The look of EllesmereUI, when the player uses it. EllesmereUI restyles Blizzard's windows but leaves
-- every frame another addon puts into them alone, Guildy's window included; it skins an addon that
-- hands its frames over through its skinning API (SKINNING_API.md in EllesmereUI's repository):
-- EllesmereUI.RegisterSkin(name, callback) calls back once with S, a set of functions that paint a frame
-- in the player's theme (S.Shell, S.Panel, S.Button, ...) and keep it in step with later theme changes.
-- Only that API is called here; nothing of EllesmereUI's own code or art is used.
--
-- Guildy's widget makers (UI/Widgets.lua) hand each new frame to Skin.Apply. Without EllesmereUI, or
-- with its skinning turned off for Guildy, the callback never comes and Apply does nothing.
local _, ns = ...

local Skin = {}
ns.Skin = Skin

local S                 -- EllesmereUI's skin functions, once it handed them over
local waiting = nil     -- frames made before that, applied when they come: { {kind, frame, opts} }
local NAME = "Guildy"   -- the name the player sees in EllesmereUI's list of third-party addons

-- kind -> function(S, frame, opts). Each S function only changes how a frame looks, and calling one again
-- on a frame it already painted does nothing.
local PAINT = {
  -- Guildy's main and options windows (ButtonFrameTemplate): the theme's backdrop and border instead of
  -- Blizzard's frame art and portrait (the close button: "CloseButton")
  Window = function(s, frame)
    s.Shell(frame)
    local nine = rawget(frame, "NineSlice")
    if nine then s.FadeNineSlice(nine) end
    local portrait = rawget(frame, "PortraitContainer")
    if portrait then s.FadeRegions(portrait) end
    local bg = rawget(frame, "Bg")
    if type(bg) == "table" and bg.GetObjectType and bg:GetObjectType() ~= "Texture" then s.FadeRegions(bg) end
    local title = rawget(frame, "TitleContainer")
    if title then s.FadeRegions(title) end
  end,
  Panel = function(s, frame, opts) s.Panel(frame, opts) end,
  Button = function(s, frame) s.Button(frame) end,
  IconButton = function(s, frame) s.Button(frame, { "Icon" }) end,
  EditBox = function(s, frame) s.EditBox(frame) end,
  Checkbox = function(s, frame) s.Checkbox(frame) end,
  Tab = function(s, frame) s.Tab(frame) end,
  CloseButton = function(s, frame) s.CloseButton(frame) end,
}

local function Paint(kind, frame, opts)
  local paint = PAINT[kind]
  if paint then ns.Try(paint, S, frame, opts) end
end

-- True once EllesmereUI skins Guildy (the widget makers then leave out art of their own it replaces)
function Skin.Active()
  return S ~= nil
end

-- Paints frame in EllesmereUI's theme as `kind` (a key of PAINT); a frame made before EllesmereUI handed
-- its functions over is painted when they come. Without EllesmereUI it does nothing.
function Skin.Apply(kind, frame, opts)
  if type(frame) ~= "table" then return frame end
  if S then
    Paint(kind, frame, opts)
  elseif waiting then
    waiting[#waiting + 1] = { kind, frame, opts }
  end
  return frame
end

-- EllesmereUI's callback (also called by the tests with a fake S)
function Skin.Receive(s)
  if type(s) ~= "table" then return end
  S = s
  local list = waiting
  waiting = nil
  for _, entry in ipairs(list or {}) do Paint(entry[1], entry[2], entry[3]) end
end

local eui = rawget(_G, "EllesmereUI")
if type(eui) == "table" and type(eui.RegisterSkin) == "function" then
  waiting = {}
  ns.Try(eui.RegisterSkin, NAME, Skin.Receive)
  -- EllesmereUI calls back at PLAYER_LOGIN, or never when the player turned skinning off for Guildy:
  -- then the frames waiting for it are let go (turned on later, only frames made from then on are skinned)
  local watch = ns.CreateFrame("Frame")
  watch:RegisterEvent("PLAYER_LOGIN") -- (comes once a session)
  watch:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then
      C_Timer.After(10, function() waiting = nil end)
    end
  end)
end
