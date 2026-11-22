-- What lies in the guild bank's tabs, two boxes for the board of the Bank tab (UI/Board.lua,
-- UI/TabBank.lua), from the contents read at the banker (Core/Bank.lua: Bank.Contents):
--   contents  every item once with its count, stacks, tabs and what it did in the chosen days, or one
--             tab as the game's grid; a search and a tab menu in its title rows
--   where     where the picked item lies: a row per tab, and that tab's grid with its slots lit
-- Each has Fill(ctx) with ctx = { bank, known, now, days }. view.pickItem (an item key) and
-- view.pickTab are shared by both; settings.bank.contents = "grid" keeps the grid (nil: the list).
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI
local B = ns.Bank

local ROW = 26
local MIN_SLOT, MAX_SLOT = 14, 52
local GREEN, RED, GREY = "|cff40e040", "|cffff5a4a", "|cff999999"

-- the item's name as the game shows it, else as it was read
local function ItemName(e)
  local info = rawget(_G, "GetItemInfo") or (C_Item and C_Item.GetItemInfo)
  local name = ns.Try(info, e.i or e.id)
  return type(name) == "string" and name or e.nm or e.i or "?"
end

-- The game's grid of one tab: 14 columns of 7 slots in pairs of columns, slot 1 top left, the slots
-- running down the columns. onPick(slot entry) on a click on a filled slot.
local function SlotGrid(parent, onPick)
  local H = UI.Bank
  local grid = ns.CreateFrame("Frame", nil, parent)
  grid.Pairs, grid.Buttons = {}, {}
  for p = 1, 7 do
    local edge = grid:CreateTexture(nil, "BACKGROUND", nil, -8)
    edge:SetColorTexture(0.36, 0.29, 0.15, 1)
    local fill = grid:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetColorTexture(0.13, 0.11, 0.08, 1)
    grid.Pairs[p] = { edge = edge, fill = fill }
  end
  for slot = 1, B.SLOTS do
    local button = ns.CreateFrame("Button", nil, grid)
    -- the gold edge of a slot the search found or the picked item lies in: 1 px around the slot
    button.Edge = button:CreateTexture(nil, "BACKGROUND", nil, -6)
    button.Edge:SetPoint("TOPLEFT", -1, 1)
    button.Edge:SetPoint("BOTTOMRIGHT", 1, -1)
    button.Edge:SetColorTexture(1, 0.82, 0, 1)
    button.Bg = button:CreateTexture(nil, "BACKGROUND", nil, -5)
    button.Bg:SetAllPoints()
    button.Bg:SetColorTexture(0.04, 0.035, 0.03, 1)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetPoint("TOPLEFT", 2, -2)
    button.Icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.Count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.Count:SetPoint("BOTTOMRIGHT", -2, 2)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnEnter", function(self)
      if not (self.item and self.item.i) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if pcall(GameTooltip.SetHyperlink, GameTooltip, self.item.i) then GameTooltip:Show() end
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(self)
      if self.item then onPick(self.item) end
    end)
    grid.Buttons[slot] = button
  end

  local function Gaps(size) return 2, math.max(6, math.floor(size / 5)), 2 end -- in a pair, between pairs, rows

  -- width and height of the grid at slots of `size` px
  function grid.Measure(size)
    local inner, pair, row = Gaps(size)
    return 7 * (2 * size + inner) + 6 * pair, 7 * size + 6 * row
  end

  -- the largest slots that fit width x height, within MIN_SLOT .. MAX_SLOT
  function grid.Fit(width, height)
    local size = MAX_SLOT
    while size > MIN_SLOT do
      local w, h = grid.Measure(size)
      if w <= width and h <= height then break end
      size = size - 1
    end
    return size
  end

  function grid:Place(size)
    if self.size == size then return end
    self.size = size
    local inner, pair, row = Gaps(size)
    local pw = 2 * size + inner
    local w, h = grid.Measure(size)
    self:SetSize(w, h)
    for p, frame in ipairs(self.Pairs) do
      local x = (p - 1) * (pw + pair)
      frame.edge:ClearAllPoints()
      frame.edge:SetPoint("TOPLEFT", self, "TOPLEFT", x - 3, 3)
      frame.edge:SetSize(pw + 6, h + 6)
      frame.fill:ClearAllPoints()
      frame.fill:SetPoint("TOPLEFT", self, "TOPLEFT", x - 2, 2)
      frame.fill:SetSize(pw + 4, h + 4)
    end
    for slot, button in ipairs(self.Buttons) do
      local col, r = B.SlotPlace(slot)
      button:SetSize(size, size)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", self, "TOPLEFT", math.floor((col - 1) / 2) * (pw + pair) + ((col - 1) % 2) * (size + inner),
        -(r - 1) * (size + row))
    end
  end

  -- slots: the tab's { [slot] = entry }; hit(key): whether the search found it (nil: no search);
  -- picked: the item key whose slots get the gold edge
  function grid:Fill(slots, hit, picked)
    for slot, button in ipairs(self.Buttons) do
      local s = slots and slots[slot]
      button.item = s
      button.Icon:SetShown(s ~= nil)
      if s then
        local key = B.ItemKey(s)
        local lit = hit == nil or hit(key)
        button.Icon:SetTexture(H.ItemIcon(s.id))
        button.Icon:SetAlpha(lit and 1 or 0.25)
        button.Count:SetText((s.n or 1) > 1 and tostring(s.n) or "")
        button.Count:SetAlpha(lit and 1 or 0.35)
        button.Edge:SetShown((hit ~= nil and lit) or (picked ~= nil and key == picked))
      else
        button.Count:SetText("")
        button.Edge:Hide()
      end
    end
  end

  return grid
end

-- view: the tab (view.pickItem, view.pickTab, view:Refresh())
function UI.BankContents(parent, view)
  local L = ns.L
  local H = UI.Bank
  local widgets = {}

  local function TabName(bank, index)
    local tab = bank and bank.tabs[index]
    return (tab and tab.name) or L.BANK_TAB_N:format(index)
  end

  local function Pick(entry, tab)
    view.pickItem, view.pickTab = B.ItemKey(entry), tab
    view:Refresh()
  end

  -- the contents: a list or one tab's grid ----------------------------------------------------------
  local contents = W.Box(parent)
  local title = W.Text(contents, "GameFontNormal", L.BANK_CONTENTS)
  title:SetPoint("TOPLEFT", 10, -12)
  contents.query, contents.sort, contents.desc = "", "n", true
  -- the tab it shows: all of them or one (the grid always shows one)
  contents.TabMenu = W.MenuButton(contents, L.BANK_TABS_ALL, function()
    local bank, grid = contents.bank, contents.grid
    local items = {}
    if not grid then
      items[1] = { text = L.BANK_TABS_ALL, checked = contents.tab == nil, onClick = function()
        contents.tab = nil
        view:Refresh()
      end }
    end
    for index = 1, B.MAX_TABS do
      if bank and bank.tabs[index] then
        items[#items + 1] = { text = TabName(bank, index), checked = contents.shownTab == index, onClick = function()
          contents.tab = index
          view:Refresh()
        end }
      end
    end
    return items
  end, 110, 170)
  -- the title row as in the ledger: the title, list or grid and the tab right behind it, the sums at the right
  contents.Mode = W.Segmented(contents, { { value = "list", text = L.BANK_LIST }, { value = "grid", text = L.BANK_GRID } },
    function(value)
      UI.SetBankSetting("contents", value == "grid" and "grid" or nil)
      view:Refresh()
    end)
  contents.Mode:SetPoint("LEFT", title, "RIGHT", 14, 0)
  contents.TabMenu:SetPoint("LEFT", contents.Mode, "RIGHT", 12, 0)
  contents.Sum = W.Text(contents, "GameFontDisableSmall")
  contents.Sum:SetPoint("TOPRIGHT", -10, -14)
  contents.Sum:SetPoint("LEFT", contents.TabMenu, "RIGHT", 12, 0)
  contents.Sum:SetJustifyH("RIGHT")
  contents.Sum:SetWordWrap(false)
  -- below: the search alone, in line with the list (the edit box art starts left of its frame)
  local search = W.EditBox(contents, 240)
  search:SetPoint("TOPLEFT", 18, -40)
  search.Hint = W.Text(search, "GameFontDisableSmall", L.BANK_CONTENTS_SEARCH)
  search.Hint:SetPoint("LEFT", 2, 0)
  search:SetScript("OnTextChanged", function(self)
    contents.query = self:GetText() or ""
    self.Hint:SetShown(contents.query == "")
    view:Refresh()
  end)
  contents.Search = search

  -- the list's columns: the name takes what the others leave; tabs and the movement can be switched off
  local KEYS = { "name", "n", "stacks", "tabs", "value", "flow" }
  local HEADS = { name = L.BANK_COL_ITEM, n = L.BANK_COL_COUNT, stacks = L.BANK_COL_STACKS, tabs = L.BANK_TABS,
    flow = L.BANK_COL_FLOW, value = L.BANK_COL_VALUE }
  local function Cols()
    local o = contents.opts or {}
    local c, r = {}, -4
    local function Right(key, width, justify)
      c[key] = { r, width, justify }
      r = r - width - 8
    end
    if o.flow ~= false then Right("flow", 80, "RIGHT") end
    if contents.prices and o.value ~= false then Right("value", 110, "RIGHT") end
    if o.tabs ~= false then Right("tabs", 190, "LEFT") end
    Right("stacks", 50, "RIGHT")
    Right("n", 60, "RIGHT")
    c.right = r
    return c
  end
  local function Arrange(owner, cells, c)
    for _, key in ipairs(KEYS) do
      local cell, col = cells[key], c[key]
      if key == "name" then
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", owner, "LEFT", cell.indent or 4, 0)
        cell:SetPoint("RIGHT", owner, "RIGHT", c.right, 0)
      else
        cell:SetShown(col ~= nil)
        if col then
          cell:ClearAllPoints()
          cell:SetPoint("RIGHT", owner, "RIGHT", col[1], 0)
          cell:SetWidth(col[2])
        end
      end
    end
  end
  local head = ns.CreateFrame("Frame", nil, contents)
  head:SetPoint("TOPLEFT", 8, -68)
  head:SetPoint("RIGHT", -28, 0)
  head:SetHeight(16)
  contents.Heads = {}
  for _, key in ipairs(KEYS) do
    local button = ns.CreateFrame("Button", nil, head)
    button:SetHeight(16)
    button.Text = W.Text(button, "GameFontDisableSmall", HEADS[key])
    button.Text:SetAllPoints()
    button.Text:SetJustifyH((key == "name" or key == "tabs") and "LEFT" or "RIGHT")
    if key ~= "tabs" then
      button:SetScript("OnClick", function()
        if contents.sort == key then
          contents.desc = not contents.desc
        else
          contents.sort, contents.desc = key, key ~= "name"
        end
        view:Refresh()
      end)
    end
    contents.Heads[key] = button
  end
  contents.Heads.name.indent = ROW + 4

  contents.List = W.ScrollList(contents, ROW, function(row)
    row.Picked = row:CreateTexture(nil, "BORDER")
    row.Picked:SetAllPoints()
    row.Picked:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.28)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(ROW - 6, ROW - 6)
    row.Icon:SetPoint("LEFT", 4, 0)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.Cells = {}
    for _, key in ipairs(KEYS) do
      local cell = W.Text(row, key == "n" and "GameFontNormalSmall" or (key == "name" or key == "value") and "GameFontHighlightSmall"
        or "GameFontDisableSmall")
      cell:SetJustifyH((key == "name" or key == "tabs") and "LEFT" or "RIGHT")
      cell:SetWordWrap(false)
      row.Cells[key] = cell
    end
    row.Cells.name.indent = ROW + 4
    row.Click = ns.CreateFrame("Button", nil, row)
    row.Click:SetAllPoints()
    row.Click:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.Click:SetScript("OnClick", function()
      if row.entry then Pick(row.entry, contents.tab) end
    end)
    -- the item's tooltip over its icon and name
    row.Click:SetScript("OnEnter", function(self)
      local e = row.entry
      if not (e and e.i) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if pcall(GameTooltip.SetHyperlink, GameTooltip, e.i) then GameTooltip:Show() end
    end)
    row.Click:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, e)
    Arrange(row, row.Cells, contents.cols)
    row.entry = e
    row.Picked:SetShown(view.pickItem == e.key)
    row.Icon:SetTexture(H.ItemIcon(e.id))
    row.Cells.name:SetText(H.ItemText(e))
    row.Cells.n:SetText(tostring(e.n))
    row.Cells.stacks:SetText(tostring(e.stacks))
    local names = {}
    for i, index in ipairs(e.tabs) do names[i] = TabName(contents.bank, index) end
    row.Cells.tabs:SetText(table.concat(names, ", "))
    row.Cells.value:SetText(e.value and H.Money(e.value) or (GREY .. "-|r"))
    local flow = e.flow or 0
    row.Cells.flow:SetText(flow > 0 and (GREEN .. "+" .. flow .. "|r") or flow < 0 and (RED .. flow .. "|r") or (GREY .. "-|r"))
  end)
  contents.List:SetPoint("TOPLEFT", 8, -86)
  contents.List:SetPoint("BOTTOMRIGHT", -28, 8)
  contents.Grid = SlotGrid(contents, function(entry) Pick(entry, contents.shownTab) end)
  contents.Empty = W.Text(contents, "GameFontDisable")
  contents.Empty:SetPoint("TOPLEFT", 24, -100)
  contents.Empty:SetPoint("RIGHT", -24, 0)
  contents.Empty:SetJustifyH("CENTER")

  -- the first tab whose contents were read (nil: none)
  local function FirstRead(bank)
    for index = 1, B.MAX_TABS do
      local tab = bank.tabs[index]
      if tab and type(tab.slots) == "table" then return index end
    end
  end

  function contents:Fill(ctx)
    local bank = ctx.known and ctx.bank or nil
    self.bank = bank
    self.prices = ctx.prices
    local mode = UI.bankShot and UI.bankShot.contents or UI.BankSetting("contents") -- a picture of the run sets its own
    local grid = mode == "grid"
    self.grid = grid
    self.Mode:SetValue(grid and "grid" or "list")
    if self.tab and not (bank and bank.tabs[self.tab]) then self.tab = nil end
    local read = bank and FirstRead(bank)
    -- the grid shows one tab: the chosen one, else the first that was read
    local shown = self.tab or (grid and read) or nil
    self.shownTab = shown
    self.TabMenu:SetText(shown and TabName(bank, shown) or L.BANK_TABS_ALL)
    self.TabMenu:SetShown(bank ~= nil and next(bank.tabs) ~= nil)
    local query = self.query ~= "" and self.query or nil
    local list = bank and read and B.Contents(bank, shown, query, ItemName) or {}
    local used, room = 0, 0
    if bank then used, room = B.Slots(bank) end
    local stacks = 0
    for _, e in ipairs(list) do stacks = stacks + e.stacks end
    self.Sum:SetText(bank and read and L.BANK_CONTENTS_SUM:format(#list, stacks, used, room) or "")

    for _, cell in pairs(self.Heads) do cell:SetShown(not grid) end
    self.List:SetShown(not grid)
    self.Grid:SetShown(grid and shown ~= nil and type(bank.tabs[shown].slots) == "table")
    local empty
    if not read then
      empty = L.BANK_TABS_EMPTY
    elseif grid then
      if not self.Grid:IsShown() then empty = L.BANK_CONTENTS_UNREAD end
    elseif #list == 0 then
      empty = shown and type(bank.tabs[shown].slots) ~= "table" and L.BANK_CONTENTS_UNREAD or L.BANK_CONTENTS_NONE
    end
    self.Empty:SetShown(empty ~= nil)
    self.Empty:SetText(empty or "")

    if grid then
      if self.Grid:IsShown() then
        local width, height = (self:GetWidth() or 0) - 24, (self:GetHeight() or 0) - 86
        self.Grid:Place(self.Grid.Fit(width, height))
        self.Grid:ClearAllPoints()
        self.Grid:SetPoint("TOP", self, "TOP", 0, -78)
        local hit
        if query then
          local found = {}
          for _, e in ipairs(list) do found[e.key] = true end
          hit = function(key) return found[key] == true end
        end
        self.Grid:Fill(bank.tabs[shown].slots, hit, view.pickItem)
      end
      return
    end
    self.cols = Cols()
    Arrange(head, self.Heads, self.cols)
    local flow = B.ItemFlow(bank or { logs = {} }, ctx.now, ctx.days)
    for _, e in ipairs(list) do
      e.flow = flow[e.key] or 0
      e.name = ItemName(e)
    end
    if ctx.prices then B.Worth(list, function(e) return ns.Prices.Get(ctx.prices, e) end) end
    if self.sort == "value" and not ctx.prices then self.sort, self.desc = "n", true end
    local key, desc = self.sort, self.desc
    table.sort(list, function(x, y)
      local p, q = x[key], y[key]
      if key == "value" then p, q = p or -1, q or -1 end
      if p == q then return x.name < y.name end
      if desc then return p > q end
      return p < q
    end)
    self.List:SetItems(list)
  end
  widgets.contents = contents

  -- where the picked item lies -------------------------------------------------------------------------
  local where = W.Box(parent)
  where.Icon = where:CreateTexture(nil, "ARTWORK")
  where.Icon:SetSize(20, 20)
  where.Icon:SetPoint("TOPLEFT", 10, -6)
  where.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  where.Name = W.Text(where, "GameFontNormal", L.BANK_WHERE)
  where.Name:SetPoint("TOPLEFT", 10, -8)
  where.Name:SetWordWrap(false)
  where.Title = W.Text(where, "GameFontDisableSmall", L.BANK_WHERE)
  where.Title:SetPoint("TOPRIGHT", -10, -10)
  where.Name:SetPoint("RIGHT", where.Title, "LEFT", -8, 0)
  where.Hint = W.Text(where, "GameFontDisable", L.BANK_WHERE_HINT)
  where.Hint:SetPoint("TOPLEFT", 12, -34)
  where.Hint:SetPoint("RIGHT", -12, 0)
  where.Sum = W.Text(where, "GameFontHighlightSmall")
  where.Sum:SetPoint("TOPLEFT", 12, -36)
  where.Rows = {}
  local function TabRow(position)
    local row = where.Rows[position]
    if not row then
      row = ns.CreateFrame("Button", nil, where)
      row:SetHeight(22)
      row:SetPoint("TOPLEFT", 6, -54 - (position - 1) * 24)
      row:SetPoint("RIGHT", -6, 0)
      row.Picked = row:CreateTexture(nil, "BORDER")
      row.Picked:SetAllPoints()
      row.Picked:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.28)
      row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      row.Icon = row:CreateTexture(nil, "ARTWORK")
      row.Icon:SetSize(18, 18)
      row.Icon:SetPoint("LEFT", 6, 0)
      row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      row.Name = W.Text(row, "GameFontHighlightSmall")
      row.Name:SetPoint("LEFT", 30, 0)
      row.Name:SetWordWrap(false)
      row.Count = W.Text(row, "GameFontDisableSmall")
      row.Count:SetPoint("RIGHT", -6, 0)
      row.Count:SetJustifyH("RIGHT")
      row.Name:SetPoint("RIGHT", row.Count, "LEFT", -8, 0)
      row:SetScript("OnClick", function(self)
        view.pickTab = self.tab
        view:Refresh()
      end)
      where.Rows[position] = row
    end
    return row
  end
  where.Grid = SlotGrid(where, function(entry) Pick(entry, where.shownTab) end)

  function where:Fill(ctx)
    local bank = ctx.known and ctx.bank or nil
    local key = view.pickItem
    -- per tab: how many of the picked item lie in it and in how many slots
    local tabs, total, stacks, sample = {}, 0, 0, nil
    if bank and key then
      for index = 1, B.MAX_TABS do
        local tab = bank.tabs[index]
        if tab and type(tab.slots) == "table" then
          local n, count = 0, 0
          for slot = 1, B.SLOTS do
            local s = tab.slots[slot]
            if s and B.ItemKey(s) == key then
              n, count, sample = n + (s.n or 1), count + 1, sample or s
            end
          end
          if count > 0 then tabs[#tabs + 1] = { index = index, n = n, stacks = count } end
          total, stacks = total + n, stacks + count
        end
      end
    end
    local found = sample ~= nil
    self.Hint:SetShown(not found)
    self.Sum:SetShown(found)
    self.Icon:SetShown(found)
    self.Title:SetShown(found)
    self.Grid:SetShown(found)
    self.Name:ClearAllPoints()
    self.Name:SetPoint("TOPLEFT", found and 36 or 10, -8)
    self.Name:SetPoint("RIGHT", self.Title, "LEFT", -8, 0)
    self.Hint:SetText(key and L.BANK_WHERE_GONE or L.BANK_WHERE_HINT)
    if not found then
      self.Name:SetText(L.BANK_WHERE)
      for _, row in ipairs(self.Rows) do row:Hide() end
      return
    end
    self.Icon:SetTexture(H.ItemIcon(sample.id))
    self.Name:SetText(H.ItemText(sample))
    local sum = L.BANK_WHERE_SUM:format(total, stacks)
    local each = ctx.prices and ns.Prices.Get(ctx.prices, sample)
    if each then sum = sum .. GREY .. "  ·  " .. L.BANK_COL_VALUE .. "|r  " .. H.Money(each * total) end
    self.Sum:SetText(sum)
    local shown = tabs[1].index
    for _, t in ipairs(tabs) do
      if t.index == view.pickTab then shown = t.index end
    end
    self.shownTab = shown
    for position, t in ipairs(tabs) do
      local row = TabRow(position)
      row.tab = t.index
      row.Picked:SetShown(t.index == shown and #tabs > 1)
      row.Icon:SetTexture(bank.tabs[t.index].icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      row.Name:SetText(TabName(bank, t.index))
      row.Count:SetText(L.BANK_WHERE_TAB:format(t.n, t.stacks))
      row:Show()
    end
    for position = #tabs + 1, #self.Rows do self.Rows[position]:Hide() end
    local top = 54 + #tabs * 24 + 10
    local size = self.Grid.Fit((self:GetWidth() or 0) - 24, (self:GetHeight() or 0) - top - 12)
    self.Grid:Place(size)
    self.Grid:ClearAllPoints()
    self.Grid:SetPoint("TOP", self, "TOP", 0, -top - 4)
    self.Grid:Fill(bank.tabs[shown].slots, nil, key)
  end
  widgets.where = where

  return widgets
end
