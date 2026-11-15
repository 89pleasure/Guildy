-- What an item fetches at the auction house, from a price addon the player has installed: Auctionator or
-- TradeSkillMaster. Guildy has no prices of its own and shares none: the value is what the player's own
-- scans say. Opt-in: settings.bank.prices = "auctionator" | "tsm", nil: off.
local _, ns = ...

local Prices = {}
ns.Prices = Prices

local CALLER = "Guildy"

local function G(name)
  return rawget(_G, name)
end

local function Auctionator()
  local api = G("Auctionator")
  api = type(api) == "table" and type(api.API) == "table" and api.API.v1
  return type(api) == "table" and api or nil
end

local function TSM()
  local api = G("TSM_API")
  return type(api) == "table" and type(api.GetCustomPriceValue) == "function" and api or nil
end

-- source key -> { name, available(), price(entry) = copper per item or nil }; entry = { i = item string, id }
Prices.SOURCES = {
  auctionator = {
    name = "Auctionator",
    available = function() return Auctionator() ~= nil end,
    price = function(e)
      local api = Auctionator()
      if not api then return nil end
      local copper = e.id and ns.Try(api.GetAuctionPriceByItemID, CALLER, e.id)
      if not copper and e.i then copper = ns.Try(api.GetAuctionPriceByItemLink, CALLER, e.i) end
      return copper
    end,
  },
  tsm = {
    name = "TSM",
    available = function() return TSM() ~= nil end,
    price = function(e)
      local api = TSM()
      if not api then return nil end
      local item = e.i and ns.Try(api.ToItemString, e.i) or (e.id and ("i:" .. e.id))
      return item and ns.Try(api.GetCustomPriceValue, "DBMarket", item)
    end,
  },
}
Prices.ORDER = { "auctionator", "tsm" }

-- The installed sources, in ORDER
function Prices.Available()
  local list = {}
  for _, key in ipairs(Prices.ORDER) do
    if Prices.SOURCES[key].available() then list[#list + 1] = key end
  end
  return list
end

-- The source in use: the chosen one while it is installed, nil when it is off or gone
function Prices.Active(chosen)
  local source = Prices.SOURCES[chosen]
  return source and source.available() and chosen or nil
end

-- copper per item from the source, nil when it has no price (a whole number above 0 only)
function Prices.Get(key, entry)
  local source = Prices.SOURCES[key]
  local copper = source and source.price(entry)
  if type(copper) ~= "number" or copper ~= copper or copper <= 0 then return nil end
  return math.floor(copper)
end

function Prices.Name(key)
  return Prices.SOURCES[key] and Prices.SOURCES[key].name or ""
end
