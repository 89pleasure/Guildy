-- Blacklist tab: the guild's shared list of players to be warned about (Core/Blacklist.lua,
-- Game/Blacklist.lua). Direction A "ledger" (media/gallery/mock/blacklist-a.png): reads and filters like the
-- Members tab; "Add" opens an inline row above the list; officers remove names and, with "Show removed",
-- see the removed ones and can add them again. A name that joined the guild stays greyed and quiet.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local ROW = 18
local KINDS = { "kos", "ninja", "insult", "scam", "other" }

local function Rgb(hex)
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function KindColor(tag)
  return ns.GameBlacklist.COLORS[ns.Blacklist.Tag(tag)]
end

local function ClassIcon(classFile)
  local coords = rawget(_G, "CLASS_ICON_TCOORDS")
  local c = classFile and coords and coords[classFile]
  if not c then return "|cff6e685a?|r  " end
  return ("|TInterface\\TargetingFrame\\UI-Classes-Circles:14:14:0:0:256:256:%d:%d:%d:%d|t "):format(
    c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

-- A small square in the kind's color: the game's fonts lack a square glyph, so it is the dot texture
local DOT = "|TInterface\\AddOns\\Guildy\\Textures\\Dot:8:8:0:0:32:32:0:32:0:32:%d:%d:%d|t"
local function KindMark(hex)
  local r, g, b = Rgb(hex)
  return DOT:format(r * 255, g * 255, b * 255)
end

local function Ago(ts)
  return ns.Roster.LastOnlineText({ online = false, daysOffline = math.max(0, ns.Now() - ts) / 86400 })
end

local function Faction(f)
  if f == "A" then return "|cff78aaff" .. ns.L.BL_ALLIANCE .. "|r" end
  if f == "H" then return "|cffff5a50" .. ns.L.BL_HORDE .. "|r" end
  return "|cff6e685a?|r"
end

-- Columns: name, kind and reason from the left (the reason takes what is left), the rest from the right
local LEFT = { { key = "name", x = 8, width = 170 }, { key = "kind", x = 182, width = 116 } }
local RIGHT = { { key = "action", width = 96 }, { key = "when", width = 78 }, { key = "by", width = 140 },
  { key = "level", width = 34 }, { key = "faction", width = 70 } }
local REASON_X = 302

local function Place(parent, cells)
  for _, column in ipairs(LEFT) do
    cells[column.key]:SetPoint("LEFT", column.x, 0)
    cells[column.key]:SetWidth(column.width)
  end
  local right = -4
  for _, column in ipairs(RIGHT) do
    cells[column.key]:SetPoint("RIGHT", parent, "RIGHT", right, 0)
    cells[column.key]:SetWidth(column.width)
    right = right - column.width - 6
  end
  cells.reason:SetPoint("LEFT", REASON_X, 0)
  cells.reason:SetPoint("RIGHT", cells.faction, "LEFT", -8, 0)
end

local ERRORS = { protected = "BL_ERR_PROTECTED", removed = "BL_ERR_REMOVED", name = "BL_ERR_NAME" }

local function Build(panel)
  local L = ns.L
  local view = { query = "" }

  -- toolbar ----------------------------------------------------------------------------------------
  local page = W.Page(panel)
  local main, bar = page.Body, page.Bar

  local search = page:Left(W.EditBox(bar, W.SEARCH_W), 6)
  search.Hint = W.Text(search, "GameFontDisableSmall", L.BL_SEARCH)
  search.Hint:SetPoint("LEFT", 2, 0)
  search:SetScript("OnTextChanged", function(self)
    view.query = (self:GetText() or ""):lower()
    self.Hint:SetShown(view.query == "")
    view:Refresh()
  end)
  view.Search = search

  local function KindItems(picked, onPick, withAll)
    local items = {}
    if withAll then items[1] = { text = L.BL_ALL_KINDS, checked = picked == nil, onClick = function() onPick(nil) end } end
    for _, tag in ipairs(KINDS) do
      local r, g, b = Rgb(KindColor(tag))
      items[#items + 1] = { text = ns.GameBlacklist.TagLabel(tag), color = { r, g, b }, checked = picked == tag,
        onClick = function() onPick(tag) end }
    end
    return items
  end
  view.KindButton = page:Left(W.MenuButton(bar, L.BL_ALL_KINDS, function()
    return KindItems(view.kind, function(tag) view:SetKind(tag) end, true)
  end, 120, 170), 8)

  local function Check(label, anchor, onClick)
    local check = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
    check:SetScript("OnClick", onClick)
    check.Label = W.Text(bar, "GameFontHighlightSmall", label)
    check.Label:SetPoint("LEFT", check, "RIGHT", 0, 0)
    return check
  end
  view.NoReasonCheck = Check(L.BL_NO_REASON_FILTER, view.KindButton, function(self)
    view.noReason = self:GetChecked() or nil
    view:Refresh()
  end)
  view.RemovedCheck = Check(L.BL_SHOW_REMOVED, view.NoReasonCheck.Label, function(self)
    view.showRemoved = self:GetChecked() or nil
    view:Refresh()
  end)

  view.AddButton = page:Right(W.Button(bar, L.BL_ADD, function() view:OpenAdd() end, 100, { small = true }))
  view.Summary = page:Right(W.Text(bar, "GameFontDisableSmall"), 10)
  view.Summary:SetJustifyH("RIGHT")

  -- list box with its header ---------------------------------------------------------------------
  local listBox = W.Box(main)
  listBox:SetAllPoints()
  local header = CreateFrame("Frame", nil, listBox)
  header:SetPoint("TOPLEFT", 4, -4)
  header:SetPoint("RIGHT", listBox, "RIGHT", -26, 0)
  header:SetHeight(20)
  local headerLine = header:CreateTexture(nil, "ARTWORK")
  headerLine:SetPoint("BOTTOMLEFT", 2, -1)
  headerLine:SetPoint("BOTTOMRIGHT", -2, -1)
  headerLine:SetHeight(1)
  headerLine:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.3)
  local heads = {}
  for key, label in pairs({ name = L.BL_COL_NAME, kind = L.BL_COL_KIND, reason = L.BL_COL_REASON,
    faction = L.BL_COL_FACTION, level = L.BL_COL_LEVEL, by = L.BL_COL_BY, when = L.BL_COL_WHEN, action = "" }) do
    heads[key] = W.Text(header, "GameFontNormalSmall", label)
    heads[key]:SetWordWrap(false)
    heads[key]:SetJustifyH("LEFT")
  end
  Place(header, heads)

  -- the add row: name, kind, reason, Add, Cancel ---------------------------------------------------
  local add = CreateFrame("Frame", nil, listBox)
  add:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
  add:SetPoint("RIGHT", header, "RIGHT", 0, 0)
  add:SetHeight(26)
  local addBack = add:CreateTexture(nil, "BACKGROUND")
  addBack:SetAllPoints()
  addBack:SetColorTexture(1, 0.82, 0, 0.08)
  add:Hide()
  view.AddRow = add
  view.AddName = W.EditBox(add, 160)
  view.AddName:SetPoint("LEFT", 12, 0)
  view.AddName.Hint = W.Text(view.AddName, "GameFontDisableSmall", L.BL_NAME_HINT)
  view.AddName.Hint:SetPoint("LEFT", 2, 0)
  view.AddKindButton = W.MenuButton(add, "", function()
    return KindItems(view.addKind, function(tag) view:SetAddKind(tag) end)
  end, 116, 150)
  view.AddKindButton:SetPoint("LEFT", view.AddName, "RIGHT", 10, 0)
  view.AddReason = W.EditBox(add, 300)
  view.AddReason:SetPoint("LEFT", view.AddKindButton, "RIGHT", 10, 0)
  view.AddReason:SetMaxLetters(ns.Blacklist.REASON_MAX)
  view.AddReason.Hint = W.Text(view.AddReason, "GameFontDisableSmall", L.BL_REASON_HINT)
  view.AddReason.Hint:SetPoint("LEFT", 2, 0)
  for _, box in ipairs({ view.AddName, view.AddReason }) do
    box:SetScript("OnTextChanged", function(self) self.Hint:SetShown((self:GetText() or "") == "") end)
    box:SetScript("OnEnterPressed", function() view:Submit() end)
  end
  view.AddCancel = W.Button(add, L.BL_CANCEL, function() view:CloseAdd() end, 90, { small = true })
  view.AddCancel:SetPoint("RIGHT", -4, 0)
  view.AddSubmit = W.Button(add, L.BL_ADD, function() view:Submit() end, 100, { small = true })
  view.AddSubmit:SetPoint("RIGHT", view.AddCancel, "LEFT", -6, 0)
  view.AddFrom = W.Text(add, "GameFontDisableSmall")
  view.AddFrom:SetPoint("LEFT", view.AddReason, "RIGHT", 12, 0)
  view.AddFrom:SetPoint("RIGHT", view.AddSubmit, "LEFT", -8, 0)
  view.AddFrom:SetWordWrap(false)

  -- rows ---------------------------------------------------------------------------------------------
  view.List = W.ScrollList(listBox, ROW, function(row)
    row:EnableMouse(true)
    row.Cells = {}
    for _, key in ipairs({ "name", "kind", "reason", "faction", "level", "by", "when", "action" }) do
      local cell = W.Text(row, "GameFontHighlightSmall")
      cell:SetWordWrap(false)
      cell:SetJustifyH("LEFT")
      row.Cells[key] = cell
    end
    Place(row, row.Cells)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.1)
    row.Highlight = highlight
    row.Section = W.Text(row, "GameFontNormalSmall")
    row.Section:SetPoint("LEFT", 4, 0)
    row.SectionLine = row:CreateTexture(nil, "ARTWORK")
    row.SectionLine:SetHeight(1)
    row.SectionLine:SetPoint("LEFT", row.Section, "RIGHT", 8, 0)
    row.SectionLine:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.SectionLine:SetColorTexture(1, 1, 1, 0.12)
    -- officers: remove (or add a removed name again); dim until the row is under the mouse
    row.Action = W.Button(row, L.BL_REMOVE, function(self)
      local item = self:GetParent().item
      if not item or not item.entry then return end
      if item.removed then
        local entry, err = ns.GameBlacklist.Add(item.entry.n, item.entry.t, item.entry.r)
        if not entry then ns.Print(L[ERRORS[err] or "BL_ERR_NAME"]) end
      else
        ns.GameBlacklist.Remove(item.entry.n)
      end
    end, 90, { small = true })
    row.Action:SetPoint("RIGHT", -2, 0)
    row.Action:SetHeight(ROW)
    row.Action:SetAlpha(0.45)
    row:SetScript("OnEnter", function(self)
      self.Action:SetAlpha(1)
      local entry = self.item and self.item.entry
      if entry and entry.r then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(entry.n, 1, 0.82, 0)
        GameTooltip:AddLine(entry.r, 1, 1, 1, true)
        GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function(self)
      -- moving onto the button leaves the row: the button stays bright then
      if not (self.Action.IsMouseOver and self.Action:IsMouseOver()) then self.Action:SetAlpha(0.45) end
      GameTooltip:Hide()
    end)
    row.Action:HookScript("OnEnter", function(self) self:SetAlpha(1) end)
    row.Action:HookScript("OnLeave", function(self)
      local parent = self:GetParent()
      if not (parent and parent.IsMouseOver and parent:IsMouseOver()) then self:SetAlpha(0.45) end
    end)
  end, function(row, item)
    row.item = item
    local c = row.Cells
    local isHeader = item.header ~= nil
    row.Section:SetShown(isHeader)
    row.SectionLine:SetShown(isHeader)
    row.Highlight:SetAlpha(isHeader and 0 or 1)
    for _, cell in pairs(c) do cell:SetShown(not isHeader) end
    if isHeader then
      row.Section:SetText(item.header)
      row.Section:SetTextColor(item.removed and 0.6 or 1, item.removed and 0.6 or 0.47, item.removed and 0.6 or 0.35)
      row.Action:Hide()
      return
    end
    local e = item.entry
    local grey = item.quiet or item.removed
    c.name:SetText(ClassIcon(e.c) .. (grey and ("|cff6e685a" .. e.n .. "|r") or W.ClassName(e.n, e.c)))
    local hex = grey and "6e685a" or KindColor(e.t)
    c.kind:SetText(KindMark(hex) .. " |cff" .. hex .. ns.GameBlacklist.TagLabel(e.t) .. "|r")
    if item.removed then
      c.reason:SetText("|cff6e685a" .. L.BL_REMOVED_BY:format(e.xb or "?") .. (e.r and (": " .. e.r) or "") .. "|r")
    elseif item.quiet then
      c.reason:SetText("|cff6e685a" .. L.BL_NOW_GUILD .. "|r")
    elseif e.r then
      c.reason:SetText(e.r)
    else
      c.reason:SetText("|cffff9a5a" .. L.BL_NO_REASON .. "|r")
    end
    c.faction:SetText(grey and ("|cff6e685a" .. (e.f == "A" and L.BL_ALLIANCE or e.f == "H" and L.BL_HORDE or "?") .. "|r")
      or Faction(e.f))
    c.level:SetText(e.l and tostring(e.l) or "?")
    c.by:SetText(e.a or "?")
    c.when:SetText(Ago(item.removed and e.x or e.at))
    for _, key in ipairs({ "level", "by", "when" }) do
      if grey then c[key]:SetTextColor(0.43, 0.41, 0.35) else c[key]:SetTextColor(0.82, 0.78, 0.7) end
    end
    c.action:SetText("")
    row.Action:SetShown(view.canRemove)
    row.Action:SetText(item.removed and L.BL_READD or L.BL_REMOVE)
  end)
  view.List:SetPoint("TOPLEFT", 4, -28)
  view.List:SetPoint("BOTTOMRIGHT", -26, 4)

  view.Empty = W.Text(listBox, "GameFontDisable", L.BL_EMPTY)
  view.Empty:SetPoint("TOP", 0, -80)
  view.Empty:SetWidth(520)

  -- behaviour ----------------------------------------------------------------------------------------
  function view:SetKind(tag)
    self.kind = tag
    self:Refresh()
  end

  function view:SetAddKind(tag)
    self.addKind = ns.Blacklist.Tag(tag)
    local r, g, b = Rgb(KindColor(self.addKind))
    self.AddKindButton:SetText(ns.GameBlacklist.TagLabel(self.addKind))
    local label = self.AddKindButton.GetFontString and self.AddKindButton:GetFontString()
    if label then label:SetTextColor(r, g, b) end
  end

  -- name: filled in (target, /guildy bl); seen: { c, l, f } of a unit
  function view:OpenAdd(name, seen)
    self.addSeen = seen
    self.AddName:SetText(name or "")
    self.AddReason:SetText("")
    self:SetAddKind(self.addKind or "other")
    if seen and seen.l then
      self.AddFrom:SetText(L.BL_FROM_TARGET:format(seen.f == "H" and L.BL_HORDE or seen.f == "A" and L.BL_ALLIANCE or "?",
        seen.l))
    else
      self.AddFrom:SetText("")
    end
    self.AddRow:Show()
    self.List:SetPoint("TOPLEFT", 4, -58)
    if name then self.AddReason:SetFocus() else self.AddName:SetFocus() end
  end

  function view:CloseAdd()
    self.AddRow:Hide()
    self.AddName:ClearFocus()
    self.AddReason:ClearFocus()
    self.addSeen = nil
    self.List:SetPoint("TOPLEFT", 4, -28)
  end

  function view:Submit()
    local entry, err = ns.GameBlacklist.Add(self.AddName:GetText(), self.addKind, self.AddReason:GetText(), self.addSeen)
    if not entry then
      ns.Print(L[ERRORS[err] or "BL_ERR_NAME"])
      return
    end
    self:CloseAdd()
    self:Refresh()
  end

  local function Matches(entry, query)
    if query == "" then return true end
    return ns.Names.Lower(entry.n):find(query, 1, true) ~= nil
      or (entry.r ~= nil and ns.Names.Lower(entry.r):find(query, 1, true) ~= nil)
  end

  function view:Refresh()
    self.canRemove = ns.GameBlacklist.CanRemove()
    self.RemovedCheck:SetShown(self.canRemove)
    self.RemovedCheck.Label:SetShown(self.canRemove)
    local showRemoved = self.canRemove and self.showRemoved
    local book = ns.GameBlacklist.Book() or {}
    local live, removed, noReason, removedCount = {}, {}, 0, 0
    local query = ns.Names.Lower(self.query or "")
    for _, entry in ipairs(ns.Blacklist.Sorted(book, true)) do
      local isLive = ns.Blacklist.IsLive(entry)
      if isLive and not entry.r then noReason = noReason + 1 end
      if not isLive then removedCount = removedCount + 1 end
      local keep = (not self.kind or ns.Blacklist.Tag(entry.t) == self.kind) and (not self.noReason or not entry.r)
        and Matches(entry, query)
      if keep and isLive then
        live[#live + 1] = { entry = entry, quiet = ns.GameBlacklist.IsProtected(entry.n) or nil }
      elseif keep and showRemoved then
        removed[#removed + 1] = { entry = entry, removed = true }
      end
    end
    local items = {}
    if showRemoved then items[1] = { header = L.BL_LISTED:format(#live) } end
    for _, item in ipairs(live) do items[#items + 1] = item end
    if showRemoved and #removed > 0 then
      items[#items + 1] = { header = L.BL_REMOVED:format(#removed), removed = true }
      for _, item in ipairs(removed) do items[#items + 1] = item end
    end
    self.List:SetItems(items)
    self.Empty:SetShown(next(book) == nil)
    self.Summary:SetText(L.BL_COUNT:format(#live, removedCount))
    self.NoReasonCheck.Label:SetText(L.BL_NO_REASON_FILTER .. " |cffffd100" .. noReason .. "|r")
    self.KindButton:SetText(self.kind and ns.GameBlacklist.TagLabel(self.kind) or L.BL_ALL_KINDS)
  end

  return view
end

-- /guildy bl: the add row, filled in with the target (a player not in the guild) or the given name
function UI.BlacklistAdd(name)
  local seen
  if not name or name == "" then
    local unit = "target"
    if ns.Try(rawget(_G, "UnitIsPlayer"), unit) then
      name = ns.Names.FromUnit(ns.Try(UnitName, unit))
      local _, class = ns.Try(rawget(_G, "UnitClass"), unit)
      local faction = ns.Try(rawget(_G, "UnitFactionGroup"), unit)
      if not ns.AnySecret(class, faction) then
        seen = { c = class, l = ns.Try(rawget(_G, "UnitLevel"), unit),
          f = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil }
      end
    end
  end
  UI.Show()
  UI.SelectTab("blacklist")
  local view = UI.TabView("blacklist")
  if view then view:OpenAdd(name ~= "" and name or nil, seen) end
end

UI.RegisterTab("blacklist", 7.5, "TAB_BLACKLIST", Build)
