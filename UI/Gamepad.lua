-- Controller mode (the game's gamepad interface). The game's cursor (Blizzard_GamepadSmartNavigation)
-- collects the clickable frames of the open window: buttons, edit boxes and frames with a mouse up or
-- down script. A direction goes to the nearest of them whose center lies within 45 degrees of it,
-- measured from center to center; alpha 0 still counts as visible. Blizzard lets addons steer that
-- outside combat, through the functions used here (they store their marks on the frames through
-- Blizzard's own secure helper, so nothing of Guildy's runs inside the game's navigation):
--   ignored frames      never reached (Blizzard's window under Guildy, frames that are not to be seen)
--   jumps               the frame a direction goes to from a frame, where the nearest one is wrong
--   cursor anchors      the point a frame is measured from: the left edge of a wide frame, so it lies
--                       above and below what starts at its left, not far off at its middle
-- Every call does nothing in combat (the game would refuse it with an error message) and without the
-- game's controller code.
local _, ns = ...

local Pad = {}
ns.Pad = Pad

local function Api(name)
  local fn = rawget(_G, name)
  return type(fn) == "function" and fn or nil
end

local function Direction(key)
  local dirs = rawget(_G, "SMART_NAV_INPUT_DIRECTION")
  return type(dirs) == "table" and dirs[key] or nil
end

-- Marks can be set now: outside combat, with the game's controller code loaded
function Pad.CanMark()
  return rawget(_G, "SmartNavigation") ~= nil and not InCombatLockdown()
end

-- Controller mode is on and marks can be set
function Pad.Active()
  return ns.GamepadUI() and Pad.CanMark()
end

-- frame is never reached by the cursor (true), or again (false); with its children, or with alone only
-- the frame itself (a bar whose marks on it can be reached)
function Pad.Ignore(frame, ignored, alone)
  if type(frame) ~= "table" or not Pad.CanMark() then return end
  local fn = Api(ignored and "SmartNavigation_MarkFrameIgnored" or "SmartNavigation_ClearIgnoreStatus")
  if fn then ns.Try(fn, frame, ignored and alone or nil) end
end

-- Frames that only work with the mouse (dragging, the mouse's position) and would only catch the cursor:
-- never reached by it. Set where they are made, whatever the mode, so turning controller mode on later
-- needs no new pass.
function Pad.MouseOnly(frame, alone)
  Pad.Ignore(frame, true, alone)
  return frame
end

-- From frame, direction ("LEFT", "RIGHT", "UP", "DOWN") goes to target; nil: the game's own choice again
function Pad.Jump(frame, direction, target)
  local dir = Direction(direction)
  if type(frame) ~= "table" or not dir or not Pad.CanMark() then return end
  if target then
    local fn = Api("SmartNavigation_AddJumpNavigationOverride")
    if fn then ns.Try(fn, frame, dir, target) end
  else
    local fn = Api("SmartNavigation_ClearJumpNavigationOverridesInDirection")
    if fn then ns.Try(fn, frame, dir) end
  end
end

-- The game's cursor can go to frame: a button or edit box, or a frame with a mouse up or down script
function Pad.Focusable(frame)
  if type(frame) ~= "table" or not frame.IsObjectType then return false end
  if frame:IsObjectType("Button") or frame:IsObjectType("EditBox") then return true end
  return frame.GetScript ~= nil and (frame:GetScript("OnMouseUp") ~= nil or frame:GetScript("OnMouseDown") ~= nil)
end

-- Left and right along a row of frames in their order (the bottom tabs, the headings of a list): each goes
-- to the one beside it, the ends to the game's own choice. Frames not shown or not focusable are left out.
function Pad.Row(frames)
  local shown = {}
  for _, f in ipairs(frames) do
    if Pad.Focusable(f) and f:IsShown() then shown[#shown + 1] = f end
  end
  for i, f in ipairs(shown) do
    Pad.Jump(f, "LEFT", shown[i - 1])
    Pad.Jump(f, "RIGHT", shown[i + 1])
  end
  return shown
end

-- Left and right along everything focusable in container (a toolbar), from left to right as it stands
-- on the screen: controls placed in any way (a chain, checkboxes beside each other) and only those shown
function Pad.RowOf(container)
  if type(container) ~= "table" or not container.GetChildren or not Pad.Active() then return end
  local found = {}
  local function Walk(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
      if child:IsShown() then
        if Pad.Focusable(child) then found[#found + 1] = child end
        if depth < 2 then Walk(child, depth + 1) end
      end
    end
  end
  Walk(container, 0)
  local order = {}
  for i, f in ipairs(found) do order[f] = i end
  table.sort(found, function(a, b)
    local la, lb = a:GetLeft(), b:GetLeft()
    if type(la) == "number" and type(lb) == "number" and la ~= lb then return la < lb end
    return order[a] < order[b]
  end)
  return Pad.Row(found)
end

-- frame is measured from near its left edge (a wide input line or row): from a point MEASURE_INSET in,
-- not the edge itself. The game takes the point of the anchor, never its offset, and a row in a list
-- counts only while its point lies strictly inside the list: the edge of a row is the list's edge, and
-- the row was never reached (the cursor went to a small button inside it, seen 2026-11-24). Set while
-- marks can be set, so also for players who turn controller mode on later in the session.
local MEASURE_INSET = 12
function Pad.MeasureLeft(frame)
  local set, anchor = Api("SmartNavigation_SetCustomCursorAnchorPointForFrame"), Api("CreateAnchor")
  if type(frame) ~= "table" or not (set and anchor) or not frame.CreateTexture or not Pad.CanMark() then return end
  local spot = rawget(frame, "guildyPadSpot")
  if not spot then
    spot = frame:CreateTexture(nil, "BACKGROUND")
    spot:SetSize(1, 1)
    spot:SetPoint("LEFT", frame, "LEFT", MEASURE_INSET, 0)
    rawset(frame, "guildyPadSpot", spot)
  end
  local point = ns.Try(anchor, "CENTER", spot, "CENTER", 0, 0)
  if point then ns.Try(set, frame, point) end
end

-- A window of Guildy's own outside Blizzard's guild window (the options, a confirmation, the title picker,
-- the copy box): the game's cursor only knows the guild window. Shown, it is handed to the game's frame
-- manager as a popup (GamepadMode.FrameControlsManager:HandlePopupShown, made for addons): it takes the
-- cursor, and when it hides the cursor goes back where it was. The cancel button (circle) hides it.
local function Manager()
  local mode = rawget(_G, "GamepadMode")
  local fcm = type(mode) == "table" and mode.FrameControlsManager
  return type(fcm) == "table" and fcm or nil
end

function Pad.Popup(frame)
  if type(frame) ~= "table" or not frame.HookScript then return frame end
  frame:HookScript("OnShow", function(self)
    local fcm = Manager()
    if fcm and type(fcm.HandlePopupShown) == "function" and Pad.Active() then ns.Try(fcm.HandlePopupShown, fcm, self) end
  end)
  frame:HookScript("OnHide", function(self)
    local fcm = Manager()
    if fcm and type(fcm.HandlePopupHide) == "function" and Pad.Active() then ns.Try(fcm.HandlePopupHide, fcm, self) end
  end)
  -- the game asks the window itself first when the cancel button is pressed
  if rawget(frame, "SmartNavigationCloseHandler") == nil then
    frame.SmartNavigationCloseHandler = function()
      frame:Hide()
      return true
    end
  end
  return frame
end

-- The game's own menu system works with the controller (its menus take the cursor, the cancel button
-- closes only them, the cursor goes back): Guildy's dropdown menus open through it in controller mode
-- (W.OpenMenu). True when it can.
function Pad.GameMenus()
  local util = rawget(_G, "MenuUtil")
  return Pad.Active() and type(util) == "table" and type(util.CreateContextMenu) == "function"
end

-- The game collects the buttons of panel (Blizzard's window) again: frames were made since it opened
function Pad.Refresh(panel)
  local nav = rawget(_G, "SmartNavigation")
  if type(panel) ~= "table" or type(nav) ~= "table" or not Pad.Active() then return end
  if type(nav.RefreshButtonGroups) == "function" then ns.Try(nav.RefreshButtonGroups, nav, panel) end
end

-- The button the controller's cursor is on (nil without controller mode)
function Pad.Current()
  local nav = rawget(_G, "SmartNavigation")
  if type(nav) ~= "table" or not ns.GamepadUI() then return nil end
  return ns.Try(nav.GetCurrentButton, nav)
end

-- The cursor moves to button in the window it is in now (the guild window, a popup)
function Pad.MoveTo(button)
  local nav = rawget(_G, "SmartNavigation")
  local info = type(nav) == "table" and rawget(nav, "activeInfo")
  local panel = type(info) == "table" and info.frame
  if panel then Pad.Target(panel, button) end
end

-- The cursor goes to button in panel (now, or when panel next takes the controller)
function Pad.Target(panel, button)
  local nav = rawget(_G, "SmartNavigation")
  if type(panel) ~= "table" or type(button) ~= "table" or type(nav) ~= "table" or not Pad.Active() then return end
  if type(nav.SetTargetButtonForFrame) == "function" then ns.Try(nav.SetTargetButtonForFrame, nav, panel, button) end
end
