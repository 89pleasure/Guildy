-- The "Guildy Creator" line in the tooltips of the creator's characters.
local _, ns = ...

local Creator = {}
ns.Creator = Creator

-- Add a character by the GUID that /dump UnitGUID("player") prints in game.
local CHARACTERS = {
  ["Player-6949-00219DC4"] = true,
  ["Player-6949-0021AECE"] = true,
  ["Player-6949-0021A0D8"] = true,
  ["Player-6949-05E29238"] = true,
}
local LINE = [[|TInterface\Icons\INV_Shirt_GuildTabard_01:0|t Guildy Creator]] -- the same in every language

local marked, hooked -- marked: the line is in the tooltip already, which the game can build again without clearing it

local function OnTooltip(tooltip, data)
  if marked or tooltip ~= GameTooltip or tooltip:IsForbidden() then return end
  if ns.IsSecret(data) or type(data) ~= "table" then return end
  local restricted = rawget(_G, "issecrettable")
  if restricted and restricted(data) then return end
  local guid = data.guid
  if guid == nil then
    local _, unit = tooltip:GetUnit()
    if ns.IsSecret(unit) or type(unit) ~= "string" then return end
    guid = ns.Try(rawget(_G, "UnitGUID"), unit)
  end
  if ns.IsSecret(guid) or type(guid) ~= "string" or not CHARACTERS[guid] then return end
  tooltip:AddLine(LINE, 0, 229 / 255, 1)
  marked = true
end

-- Called on entering the world, after the login in which other addons add their Target rows, so the line
-- stands below them
function Creator.HookTooltip()
  local processor, enum = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
  local unit = enum and enum.TooltipDataType and enum.TooltipDataType.Unit
  if hooked or not (unit and processor and processor.AddTooltipPostCall) then return end
  hooked = true
  GameTooltip:HookScript("OnTooltipCleared", function() marked = nil end)
  processor.AddTooltipPostCall(unit, function(tooltip, data) ns.SafeCall(OnTooltip, tooltip, data) end)
end
