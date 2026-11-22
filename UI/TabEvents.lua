-- Events tab: the guild's calendar events (Game/Events.lua, Core/Events.lua). Direction B
-- (media/gallery/mock/events-b.png): the agenda on the left grouped by week, the picked event with who
-- answered on the right; "New event" puts the form in place of the event (events-b-form.png). Everything
-- is Blizzard's calendar: members without Guildy see and answer the same events there.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI
local E = ns.Events

local ROW = 36
local LEFT_W = 380
local COLORS = { raid = "ff9230", dungeon = "4aa8ff", pvp = "ff4848", meeting = "40c860", other = "b0a896" }
local ANSWER_COLORS = { yes = "40ff40", maybe = "f0e060", no = "ff4848", open = "ffd100" }
local DOT = "|TInterface\\AddOns\\Guildy\\Textures\\Dot:8:8:0:0:32:32:0:32:0:32:%d:%d:%d|t"
local ICONS = { yes = W.ICON_YES, maybe = W.ICON_WAIT, no = W.ICON_NO }
local GE

local function Rgb(hex)
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function TypeMark(kind)
  local r, g, b = Rgb(COLORS[kind] or COLORS.other)
  return DOT:format(r * 255, g * 255, b * 255)
end

local function Icon(answer, size)
  return ("|T%s:%d:%d|t"):format(ICONS[answer], size or 12, size or 12)
end

local function Colored(hex, text)
  return "|cff" .. hex .. text .. "|r"
end

local function ClassIcon(classFile)
  local coords = rawget(_G, "CLASS_ICON_TCOORDS")
  local c = classFile and coords and coords[classFile]
  if not c then return "" end
  return ("|TInterface\\TargetingFrame\\UI-Classes-Circles:12:12:0:0:256:256:%d:%d:%d:%d|t "):format(
    c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

local function ClassLabel(classFile)
  local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  return (names and names[classFile]) or classFile or "?"
end

-- The calendar's name of an answer; invited players answer "available" instead of signing up
local function StatusName(answer, inviteType)
  local L = ns.L
  if answer == "yes" then return inviteType == 0 and L.EV_ST_AVAILABLE or L.EV_ST_YES end
  if answer == "maybe" then return L.EV_ST_MAYBE end
  if answer == "no" then return L.EV_ST_NO end
  return L.EV_OPEN_ANSWER
end

local function CountsText(counts)
  if not counts then return "" end
  return ("%s %d  %s %d  %s %d"):format(Icon("yes"), counts.yes, Icon("maybe"), counts.maybe, Icon("no"), counts.no)
end

local function DateText(stamp)
  local L = ns.L
  local _, _, _, h, mi = E.Civil(stamp)
  return E.ShortDate(stamp, GE.DayNames(), L.EV_MONTH_FIRST == "1"), E.Clock(h, mi)
end

-- "in 20 min", "today in 3 h", "tomorrow", "in 5 days", "started"
local function Relative(stamp, now)
  local L = ns.L
  local left = stamp - now
  if left <= 0 then return L.EV_RUNNING end
  if left < 60 then return L.EV_IN_MIN:format(left) end
  local days = math.floor(stamp / 1440) - math.floor(now / 1440)
  if days == 0 then return L.EV_IN_HOURS:format(math.floor(left / 60)) end
  if days == 1 then return L.EV_TOMORROW end
  return L.EV_IN_DAYS:format(days)
end

-- Dungeons and raids (the catalog of the Hall of Fame, Core/Stats.lua): name, level range, picture. WoW
-- Forever's calendar offers no dungeon pictures, so the dungeon lives in the event's title and is found
-- there again by its name.
local dungeonList
local function Dungeons()
  if dungeonList then return dungeonList end
  local list = {}
  for _, def in ipairs(ns.Stats.DUNGEONS or ns.Stats.ALL_DUNGEONS or {}) do
    local name = UI.DungeonTitle and UI.DungeonTitle(def)
    if type(name) == "string" and name ~= "" and not name:match("^#") then
      local icon, cropped = nil, nil
      if UI.DungeonIcon then icon, cropped = UI.DungeonIcon(def) end
      list[#list + 1] = { key = def.key, name = name, lower = ns.Names.Lower(name), min = def.min, max = def.max,
        raid = def.raid == true, icon = icon, cropped = cropped }
    end
  end
  if #list > 0 then dungeonList = list end
  return list
end

-- The dungeon an event title names (the longest name found in it)
local function DungeonOf(title)
  if type(title) ~= "string" then return nil end
  local lower, best = ns.Names.Lower(title), nil
  for _, dungeon in ipairs(Dungeons()) do
    if lower:find(dungeon.lower, 1, true) and (not best or #dungeon.lower > #best.lower) then best = dungeon end
  end
  return best
end

local function DungeonMark(dungeon, size)
  if not (dungeon and dungeon.icon) then return "" end
  if dungeon.cropped then return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t "):format(dungeon.icon, size, size) end
  return ("|T%s:%d:%d|t "):format(dungeon.icon, size, size)
end

local function DungeonLevels(dungeon)
  if dungeon.raid or not dungeon.min then return ns.L.EV_TYPE_RAID end
  return ns.L.FAME_DUNGEON_LEVEL:format(dungeon.min, dungeon.max)
end

local function OpenBlizzard(item)
  if not rawget(_G, "CalendarFrame") then
    local load = (rawget(_G, "C_AddOns") and C_AddOns.LoadAddOn) or rawget(_G, "LoadAddOn")
    if load then pcall(load, "Blizzard_Calendar") end
  end
  local open = rawget(_G, "CalendarFrame_OpenToGuildEventIndex")
  if item and open then
    pcall(open, item.index)
  elseif rawget(_G, "ToggleCalendar") then
    pcall(ToggleCalendar)
  end
end

local function Check(parent, label)
  local check = ns.CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  check:SetSize(24, 24)
  check.Label = W.Text(parent, "GameFontHighlightSmall", label)
  check.Label:SetPoint("LEFT", check, "RIGHT", 0, 0)
  return check
end

-- The detail of the picked event -----------------------------------------------------------------------------

local function BuildDetail(view, box)
  local L = ns.L
  local d = ns.CreateFrame("Frame", nil, box)
  d:SetPoint("TOPLEFT", 14, -12)
  d:SetPoint("BOTTOMRIGHT", -14, 10)
  view.Detail = d

  d.Title = W.Heading(d, "", 20, 260)
  d.Title:SetPoint("TOPLEFT", 0, 0)
  d.Title.Divider:ClearAllPoints()
  d.Title.Divider:SetPoint("TOPLEFT", d.Title, "BOTTOMLEFT", -4, -2)
  d.Title:SetWordWrap(false)
  d.Badge = W.Text(d, "GameFontNormalSmall")
  d.Badge:SetPoint("LEFT", d.Title, "RIGHT", 12, 0)
  d.When = W.Text(d, "GameFontHighlight")
  d.When:SetPoint("TOPLEFT", d.Title, "BOTTOMLEFT", 0, -16)
  d.When:SetPoint("RIGHT", d, "RIGHT", 0, 0)
  d.When:SetWordWrap(false)
  d.Desc = W.Text(d, "GameFontHighlightSmall")
  d.Desc:SetPoint("TOPLEFT", d.When, "BOTTOMLEFT", 0, -8)
  d.Desc:SetPoint("RIGHT", d, "RIGHT", 0, 0)
  d.Desc:SetJustifyV("TOP")
  if d.Desc.SetMaxLines then d.Desc:SetMaxLines(4) end
  d.Desc:SetTextColor(0.85, 0.82, 0.74)

  d.State = W.Text(d, "GameFontNormal")
  d.State:SetPoint("TOPLEFT", d.Desc, "BOTTOMLEFT", 0, -12)
  d.Buttons = {}
  local previous
  for _, answer in ipairs({ "yes", "maybe", "no" }) do
    local button = W.Button(d, "", function()
      local item = view:PickedItem()
      if item then GE.Answer(item, answer) end
    end, 100, { small = true })
    if previous then button:SetPoint("LEFT", previous, "RIGHT", 6, 0) else button:SetPoint("TOPLEFT", d.State, "BOTTOMLEFT", 0, -6) end
    previous = button
    d.Buttons[answer] = button
  end

  -- the bar split by signed / tentative / declined
  d.Bar = ns.CreateFrame("Frame", nil, d)
  d.Bar:SetHeight(8)
  d.Bar:SetPoint("TOPLEFT", d.Buttons.yes, "BOTTOMLEFT", 0, -12)
  d.Bar:SetPoint("RIGHT", d, "RIGHT", 0, 0)
  d.Bar.Track = d.Bar:CreateTexture(nil, "BACKGROUND")
  d.Bar.Track:SetAllPoints()
  d.Bar.Track:SetColorTexture(0.13, 0.11, 0.08, 1)
  d.Bar.Parts = {}
  for _, answer in ipairs({ "yes", "maybe", "no" }) do
    local part = d.Bar:CreateTexture(nil, "ARTWORK")
    part:SetPoint("TOP")
    part:SetPoint("BOTTOM")
    local r, g, b = Rgb(ANSWER_COLORS[answer])
    part:SetColorTexture(r, g, b, 0.85)
    d.Bar.Parts[answer] = part
  end

  -- who answered: groups of names in four columns, in a scroll frame
  d.Scroll = ns.CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
  d.Scroll:SetPoint("TOPLEFT", d.Bar, "BOTTOMLEFT", 0, -10)
  d.Scroll:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -22, 28)
  local function NamesBar()
    local bar = d.Scroll.ScrollBar
    if type(bar) ~= "table" or not bar.SetShown then return end
    local range = d.Scroll.GetVerticalScrollRange and d.Scroll:GetVerticalScrollRange() or 0
    bar:SetShown((tonumber(range) or 0) > 0.5)
  end
  d.NamesBar = NamesBar
  if d.Scroll.HookScript then d.Scroll:HookScript("OnScrollRangeChanged", NamesBar) end
  d.Names = ns.CreateFrame("Frame", nil, d.Scroll)
  d.Names:SetSize(400, 10)
  d.Scroll:SetScrollChild(d.Names)
  d.Pool = {}
  d.Message = W.Text(d, "GameFontDisable")
  d.Message:SetPoint("TOPLEFT", d.Scroll, "TOPLEFT", 0, -6)
  d.Message:SetPoint("RIGHT", d, "RIGHT", 0, 0)

  d.Link = W.Button(d, L.EV_OPEN_BLIZZARD, function() OpenBlizzard(view:PickedItem()) end, 180, { small = true })
  d.Link:SetPoint("BOTTOMLEFT", 0, 0)
  d.Announce = W.Button(d, L.EV_ANNOUNCE_BUTTON, function()
    local item = view:PickedItem()
    if item then GE.Announce(item) end
  end, 180, { small = true })
  d.Announce:SetPoint("LEFT", d.Link, "RIGHT", 8, 0)
  d.Edit = W.Button(d, L.EV_EDIT, function()
    local item = view:PickedItem()
    if item then view:OpenForm(item) end
  end, 110, { small = true })
  d.Delete = W.Button(d, L.EV_DELETE, function()
    local item = view:PickedItem()
    if not item then return end
    local date, clock = DateText(item.stamp)
    UI.Confirm(L.EV_DELETE_CONFIRM:format(item.name, date .. ", " .. clock), { run = function() GE.Delete(item) end },
      L.EV_DELETE, true)
  end, 110, { small = true })
  local deleteLabel = d.Delete:GetFontString()
  if deleteLabel then deleteLabel:SetTextColor(1, 0.3, 0.25) end
  d.EditHint = W.Text(d, "GameFontDisableSmall", L.EV_EDIT_HINT)
  d.EditHint:SetPoint("LEFT", d.Link, "RIGHT", 10, 0)
  d.EditHint:SetPoint("RIGHT", d, "RIGHT", 0, 0)
  d.EditHint:SetWordWrap(false)
  return d
end

-- The role of a member who answered (their talent spec as Guildy knows it, Core/Events.lua RoleOf)
local function RoleOfInvite(invite)
  local m = ns.Roster and ns.Roster.Find and ns.Roster.Find(invite.name)
  local spec
  if m and ns.GameGear and ns.GameGear.SpecFor then
    local guild = ns.GuildData()
    local tal = guild and type(guild.talents) == "table" and guild.talents[m.key] or nil
    local rec = guild and type(guild.gear) == "table" and guild.gear[m.key] or nil
    spec = ns.GameGear.SpecFor(m, rec, tal)
  end
  return E.RoleOf(spec, invite.classFile or (m and m.classFile))
end

-- The game's small role icons (tank, healer, damage), nothing where the client lacks them
local ROLE_ICON = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local ROLE_COORDS = { tank = "0:67:67:134", heal = "67:134:0:67", dps = "67:134:67:134" }
local function RoleMark(role)
  if not (role and ROLE_COORDS[role] and W.TextureExists(ROLE_ICON)) then return "" end
  return ("|T%s:14:14:0:0:256:256:%s|t "):format(ROLE_ICON, ROLE_COORDS[role])
end

local function NameLabel(d, i)
  local label = d.Pool[i]
  if not label then
    label = W.Text(d.Names, "GameFontHighlightSmall")
    label:SetWordWrap(false)
    d.Pool[i] = label
  end
  label:Show()
  return label
end

-- Lays out the groups of names; returns the height used
local function FillNames(d, detail)
  local L = ns.L
  local width = math.max(200, (d.Scroll:GetWidth() or 400))
  d.Names:SetWidth(width)
  local column = math.floor(width / 4)
  local used, y = 0, 0
  local function Put(text, x, top, w)
    used = used + 1
    local label = NameLabel(d, used)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", x, -top)
    label:SetWidth(w)
    label:SetText(text)
    return label
  end
  local groups = { { "yes", L.EV_GROUP_YES }, { "maybe", L.EV_GROUP_MAYBE }, { "no", L.EV_GROUP_NO }, { "open", L.EV_GROUP_OPEN } }
  local byClass, classOrder = {}, {}
  for _, group in ipairs(groups) do
    local names = {}
    for _, invite in ipairs(detail.invites) do
      if invite.answer == group[1] then names[#names + 1] = invite end
    end
    if #names > 0 then
      local head = Put(Colored(ANSWER_COLORS[group[1]], group[2]:format(#names)), 0, y, width)
      head:SetFontObject("GameFontNormalSmall")
      y = y + 18
      local function Names(list, indent)
        for i, invite in ipairs(list) do
          local col = (i - 1) % 4
          local label = Put(ClassIcon(invite.classFile) .. W.ClassName(invite.name, invite.classFile), indent + col * column,
            y + math.floor((i - 1) / 4) * 16, column - 6)
          label:SetFontObject("GameFontHighlightSmall")
        end
        y = y + math.ceil(#list / 4) * 16
      end
      if group[1] == "yes" then
        -- the signed-up by role: tank, healer, damage, then those whose role Guildy does not know
        local byRole = { tank = {}, heal = {}, dps = {}, none = {} }
        for _, invite in ipairs(names) do
          local role = RoleOfInvite(invite) or "none"
          byRole[role][#byRole[role] + 1] = invite
          if invite.classFile then
            if not byClass[invite.classFile] then classOrder[#classOrder + 1] = invite.classFile end
            byClass[invite.classFile] = (byClass[invite.classFile] or 0) + 1
          end
        end
        local labels = { tank = L.EV_ROLE_TANK, heal = L.EV_ROLE_HEAL, dps = L.EV_ROLE_DPS, none = L.EV_ROLE_NONE }
        for _, role in ipairs({ "tank", "heal", "dps", "none" }) do
          local list = byRole[role]
          if #list > 0 then
            local sub = Put(RoleMark(role) .. labels[role] .. " · " .. #list, 8, y, width - 8)
            sub:SetFontObject("GameFontNormalSmall")
            y = y + 16
            Names(list, 8)
            y = y + 4
          end
        end
      else
        Names(names, 0)
      end
      y = y + 8
    end
  end
  if #classOrder > 0 then
    table.sort(classOrder, function(a, b)
      if byClass[a] ~= byClass[b] then return byClass[a] > byClass[b] end
      return a < b
    end)
    local head = Put(L.EV_BY_CLASS, 0, y, width)
    head:SetFontObject("GameFontNormalSmall")
    y = y + 18
    local parts = {}
    for _, classFile in ipairs(classOrder) do
      parts[#parts + 1] = W.ClassName(ClassLabel(classFile), classFile) .. " " .. byClass[classFile]
    end
    local line = Put(table.concat(parts, "   "), 0, y, width)
    line:SetFontObject("GameFontHighlightSmall")
    line:SetWordWrap(true)
    y = y + 32
  end
  for i = used + 1, #d.Pool do d.Pool[i]:Hide() end
  d.Names:SetHeight(math.max(10, y))
  return y
end

-- The form ----------------------------------------------------------------------------------------------------

local FORM_LABEL = 100
local PICK_ROW = 24
local DATE_DAYS = 90 -- (also the fit of the Create button: "Erstellen" / "Speichern") -- how far ahead the date can be moved (Blizzard allows more; this keeps the arrows short)

local function BuildForm(view, box)
  local L = ns.L
  local f = ns.CreateFrame("Frame", nil, box)
  f:SetPoint("TOPLEFT", 14, -12)
  f:SetPoint("BOTTOMRIGHT", -14, 10)
  f:Hide()
  view.Form = f

  f.Heading = W.Heading(f, L.EV_FORM_TITLE, 20, 260)
  f.Heading:SetPoint("TOPLEFT", 0, 0)
  f.Heading.Divider:ClearAllPoints()
  f.Heading.Divider:SetPoint("TOPLEFT", f.Heading, "BOTTOMLEFT", -4, -2)

  local function Label(text, anchor, gap)
    local label = W.Text(f, "GameFontNormalSmall", text)
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 14))
    label:SetWidth(FORM_LABEL)
    return label
  end

  local nameLabel = W.Text(f, "GameFontNormalSmall", L.EV_FORM_NAME)
  nameLabel:SetPoint("TOPLEFT", f.Heading, "BOTTOMLEFT", 0, -24)
  f.Name = W.EditBox(f, 320)
  f.Name:SetPoint("LEFT", nameLabel, "LEFT", FORM_LABEL + 6, 0)
  f.Name:SetMaxLetters(E.TITLE_MAX)

  local typeLabel = Label(L.EV_FORM_TYPE, nameLabel, 20)
  local options = {}
  for _, kind in ipairs(E.TYPES) do options[#options + 1] = { value = kind, text = GE.Labels()[kind] } end
  f.Type = W.Segmented(f, options, function(kind)
    f.kind = kind
    if f.dungeon and f.dungeon.raid ~= (kind == "raid") then f.dungeon = nil end
    view:FormChanged()
  end)
  f.Type:SetPoint("LEFT", typeLabel, "LEFT", FORM_LABEL, 0)

  -- the dungeon or raid: two to a row, picture, name, level range
  f.Picker = W.Box(f)
  f.Picker:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", FORM_LABEL, -10)
  f.Picker:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.Picker:SetHeight(PICK_ROW * 5 + 10) -- five rows: the form still fits the smallest window
  f.Picker:Hide()
  local function PickTile(row, side)
    local tile = ns.CreateFrame("Button", nil, row)
    tile:SetHeight(PICK_ROW - 2)
    local light = tile:CreateTexture(nil, "HIGHLIGHT")
    light:SetAllPoints()
    light:SetColorTexture(1, 0.82, 0, 0.1)
    tile.Selected = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
    tile.Selected:SetAllPoints()
    tile.Selected:SetColorTexture(1, 0.82, 0, 0.2)
    tile.Levels = W.Text(tile, "GameFontDisableSmall")
    tile.Levels:SetPoint("RIGHT", -6, 0)
    tile.Name = W.Text(tile, "GameFontHighlightSmall")
    tile.Name:SetPoint("LEFT", 4, 0)
    tile.Name:SetPoint("RIGHT", tile.Levels, "LEFT", -6, 0)
    tile.Name:SetWordWrap(false)
    tile:SetScript("OnClick", function(self)
      local dungeon = self.dungeon
      if not dungeon then return end
      local name = ns.Names.Trim(f.Name:GetText() or "")
      if name == "" or name == f.autoName then
        f.Name:SetText(dungeon.name)
        f.autoName = dungeon.name
      end
      f.dungeon = dungeon
      view:FormChanged()
    end)
    row[side] = tile
  end
  local function Halves(row, width)
    if type(width) ~= "number" or width < 10 then return end
    local half = math.floor(width / 2) - 2
    row.Left:SetWidth(half)
    row.Right:SetWidth(half)
  end
  f.PickList = W.ScrollList(f.Picker, PICK_ROW, function(row)
    PickTile(row, "Left")
    PickTile(row, "Right")
    row.Left:SetPoint("LEFT", 0, 0)
    row.Right:SetPoint("RIGHT", 0, 0)
    row:SetScript("OnSizeChanged", function(self, width) Halves(self, width) end)
  end, function(row, item)
    Halves(row, row:GetWidth())
    for _, side in ipairs({ "Left", "Right" }) do
      local dungeon = item[side == "Left" and 1 or 2]
      local tile = row[side]
      tile.dungeon = dungeon
      tile:SetShown(dungeon ~= nil)
      if dungeon then
        tile.Name:SetText(DungeonMark(dungeon, 18) .. dungeon.name)
        tile.Levels:SetText(dungeon.raid and "" or DungeonLevels(dungeon))
        tile.Selected:SetShown(f.dungeon ~= nil and f.dungeon.key == dungeon.key)
      end
    end
  end)
  f.PickList:Place(4, -4, -4, 4)

  local whenLabel = Label(L.EV_FORM_WHEN, typeLabel, 20)
  f.WhenLabel = whenLabel
  f.TypeLabel = typeLabel
  f.Prev = W.Button(f, "<", function() view:MoveDate(-1) end, 26, { small = true })
  f.Prev:SetPoint("LEFT", whenLabel, "LEFT", FORM_LABEL, 0)
  f.Date = W.Text(f, "GameFontHighlight")
  f.Date:SetPoint("LEFT", f.Prev, "RIGHT", 6, 0)
  f.Date:SetWidth(110)
  f.Date:SetJustifyH("CENTER")
  f.Next = W.Button(f, ">", function() view:MoveDate(1) end, 26, { small = true })
  f.Next:SetPoint("LEFT", f.Date, "RIGHT", 6, 0)
  f.Hour = W.MenuButton(f, "20", function()
    local items = {}
    for h = 0, 23 do
      items[#items + 1] = { text = ("%02d"):format(h), checked = f.hour == h, onClick = function() f.hour = h view:FormChanged() end }
    end
    return items
  end, 60)
  f.Hour:SetPoint("LEFT", f.Next, "RIGHT", 16, 0)
  local colon = W.Text(f, "GameFontHighlight", ":")
  colon:SetPoint("LEFT", f.Hour, "RIGHT", 4, 0)
  f.Minute = W.MenuButton(f, "00", function()
    local items = {}
    for m = 0, 55, 5 do
      items[#items + 1] = { text = ("%02d"):format(m), checked = f.minute == m, onClick = function() f.minute = m view:FormChanged() end }
    end
    return items
  end, 60)
  f.Minute:SetPoint("LEFT", colon, "RIGHT", 4, 0)
  f.Relative = W.Text(f, "GameFontDisableSmall")
  f.Relative:SetPoint("LEFT", f.Minute, "RIGHT", 10, 0)

  local descLabel = Label(L.EV_FORM_DESC, whenLabel, 22)
  f.DescBox = W.Box(f)
  f.DescBox:SetPoint("TOPLEFT", descLabel, "TOPLEFT", FORM_LABEL, 4)
  f.DescBox:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.DescBox:SetHeight(72)
  f.Desc = W.InputArea(f.DescBox)
  f.Desc:SetPoint("TOPLEFT", 6, -6)
  f.Desc:SetPoint("BOTTOMRIGHT", -26, 6)
  f.Desc.EditBox:SetMaxLetters(255)
  f.Desc:SetScript("OnSizeChanged", function(self, width) self.EditBox:SetWidth(math.max(50, width or 300)) end)

  f.Announce = Check(f, L.EV_FORM_ANNOUNCE)
  f.Announce:SetPoint("TOPLEFT", f.DescBox, "BOTTOMLEFT", -4, -10)
  f.Lock = Check(f, L.EV_FORM_LOCK)
  f.Lock:SetPoint("TOPLEFT", f.Announce, "BOTTOMLEFT", 0, -2)
  f.LockHint = W.Text(f, "GameFontDisableSmall", L.EV_FORM_LOCK_HINT)
  f.LockHint:SetPoint("LEFT", f.Lock.Label, "RIGHT", 8, 0)
  f.Remind = W.Text(f, "GameFontDisableSmall", L.EV_FORM_REMIND)
  f.Remind:SetPoint("TOPLEFT", f.Lock, "BOTTOMLEFT", 4, -8)
  f.Remind:SetPoint("RIGHT", f, "RIGHT", 0, 0)

  f.Error = W.Text(f, "GameFontNormalSmall")
  f.Error:SetPoint("TOPLEFT", f.Remind, "BOTTOMLEFT", 0, -10)
  f.Error:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.Error:SetTextColor(1, 0.35, 0.3)

  f.Create = W.Button(f, L.EV_FORM_CREATE, function() view:Submit() end, 110, { fit = { L.EV_FORM_CREATE, L.EV_FORM_CREATING, L.EV_FORM_SAVE, L.EV_FORM_SAVING } })
  f.Create:SetPoint("BOTTOMRIGHT", 0, 0)
  f.Cancel = W.Button(f, L.EV_FORM_CANCEL, function() view:CloseForm() end, 110)
  f.Cancel:SetPoint("RIGHT", f.Create, "LEFT", -8, 0)
  return f
end

-- The tab -----------------------------------------------------------------------------------------------------

local ERRORS

local function Build(panel)
  local L = ns.L
  GE = ns.GameEvents
  ERRORS = { name = L.EV_ERR_NAME, past = L.EV_ERR_PAST, rights = L.EV_ERR_RIGHTS, trial = L.EV_ERR_TRIAL,
    busy = L.EV_ERR_BUSY, api = L.EV_ERR_API, notopen = L.EV_ERR_NOTOPEN }
  local view = {}

  local page = W.Page(panel)
  local bar, body = page.Bar, page.Body
  view.Count = page:Left(W.Text(bar, "GameFontNormal"), 6)
  view.OnlyOpen = Check(bar, L.EV_ONLY_OPEN)
  view.OnlyOpen:SetPoint("LEFT", view.Count, "RIGHT", 16, 0)
  view.OnlyOpen:SetScript("OnClick", function(self)
    view.onlyOpen = self:GetChecked() or nil
    view:Refresh()
  end)
  view.New = page:Right(W.Button(bar, L.EV_NEW, function() view:OpenForm() end, 130, { small = true }))

  local left = W.Box(body)
  left:SetPoint("TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", 0, 0)
  left:SetWidth(LEFT_W)
  local right = W.Box(body)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", W.GAP, 0)
  right:SetPoint("BOTTOMRIGHT", 0, 0)

  -- the agenda ----------------------------------------------------------------------------------------------
  view.List = W.ScrollList(left, ROW, function(row)
    row:EnableMouse(true)
    row.Selected = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.Selected:SetAllPoints()
    row.Selected:SetColorTexture(1, 0.82, 0, 0.14)
    row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.Highlight:SetAllPoints()
    row.Highlight:SetColorTexture(1, 0.82, 0, 0.08)
    row.Day = W.Text(row, "GameFontNormalLarge")
    row.Day:SetPoint("TOPLEFT", 4, -3)
    row.Day:SetWidth(32)
    row.Day:SetJustifyH("CENTER")
    row.Weekday = W.Text(row, "GameFontDisableSmall")
    row.Weekday:SetPoint("TOP", row.Day, "BOTTOM", 0, 0)
    row.Answer = W.Text(row, "GameFontNormalSmall")
    row.Answer:SetPoint("TOPRIGHT", -6, -5)
    row.Answer:SetJustifyH("RIGHT")
    row.Counts = W.Text(row, "GameFontHighlightSmall")
    row.Counts:SetPoint("TOPRIGHT", -6, -20)
    row.Counts:SetJustifyH("RIGHT")
    row.Title = W.Text(row, "GameFontHighlight")
    row.Title:SetPoint("TOPLEFT", 44, -4)
    row.Title:SetPoint("RIGHT", row.Answer, "LEFT", -6, 0)
    row.Title:SetWordWrap(false)
    row.Sub = W.Text(row, "GameFontDisableSmall")
    row.Sub:SetPoint("TOPLEFT", 44, -20)
    row.Sub:SetPoint("RIGHT", row.Counts, "LEFT", -6, 0)
    row.Sub:SetWordWrap(false)
    row.Section = W.Text(row, "GameFontNormalSmall")
    row.Section:SetPoint("BOTTOMLEFT", 6, 5)
    row.SectionLine = row:CreateTexture(nil, "ARTWORK")
    row.SectionLine:SetHeight(1)
    row.SectionLine:SetPoint("LEFT", row.Section, "RIGHT", 8, 0)
    row.SectionLine:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.SectionLine:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.3)
    row:SetScript("OnMouseUp", function(self, button)
      if button == "LeftButton" and self.item and self.item.key then view:Pick(self.item.key) end
    end)
  end, function(row, item)
    row.item = item
    local isHeader = item.header ~= nil
    row.Section:SetShown(isHeader)
    row.SectionLine:SetShown(isHeader)
    row.Highlight:SetAlpha(isHeader and 0 or 1)
    for _, part in ipairs({ row.Day, row.Weekday, row.Title, row.Sub, row.Answer, row.Counts }) do part:SetShown(not isHeader) end
    row.Selected:SetShown(not isHeader and item.key == view.picked)
    if isHeader then
      row.Section:SetText(item.header)
      return
    end
    local _, _, day, h, mi = E.Civil(item.stamp)
    row.Day:SetText(day)
    row.Weekday:SetText(GE.DayNames()[E.Weekday(item.stamp)])
    local title = DungeonMark(item.dungeon, 16) .. item.name
    if item.key == GE.reminded then title = Colored("ffd100", title) end
    row.Title:SetText(title)
    local sub = TypeMark(item.kind) .. " " .. E.Clock(h, mi) .. " · " .. Colored(COLORS[item.kind] or COLORS.other, GE.Labels()[item.kind])
    local detail = GE.Detail(item.key)
    if detail and detail.locked then sub = sub .. " · " .. L.EV_FORM_LOCK end
    row.Sub:SetText(sub)
    if not item.answerable then
      row.Answer:SetText("")
      row.Counts:SetText("")
    else
      row.Answer:SetText(Colored(ANSWER_COLORS[item.answer], StatusName(item.answer, detail and detail.inviteType)))
      row.Counts:SetText(detail and CountsText(detail.counts) or "")
    end
  end)
  view.List:Place(4, -4, -4, 4)

  view.Empty = W.Text(left, "GameFontDisable", L.EV_EMPTY)
  view.Empty:SetPoint("TOP", 0, -60)
  view.Empty:SetWidth(LEFT_W - 40)
  view.Empty:SetJustifyH("CENTER")

  BuildDetail(view, right)
  BuildForm(view, right)

  -- nothing picked (no events yet): what the tab is, and the way to the first event
  local intro = ns.CreateFrame("Frame", nil, right)
  intro:SetPoint("TOPLEFT", 40, -60)
  intro:SetPoint("RIGHT", right, "RIGHT", -40, 0)
  intro:SetHeight(220)
  view.Intro = intro
  intro.Heading = W.Heading(intro, L.EV_INTRO_TITLE, 20, 300)
  intro.Heading:SetPoint("TOP", 0, 0)
  intro.Text = W.Text(intro, "GameFontHighlight", L.EV_INTRO)
  intro.Text:SetPoint("TOP", intro.Heading, "BOTTOM", 0, -22)
  intro.Text:SetWidth(520)
  intro.Text:SetJustifyH("CENTER")
  intro.Text:SetTextColor(0.85, 0.82, 0.74)
  intro.New = W.Button(intro, L.EV_NEW, function() view:OpenForm() end, 160)
  intro.New:SetPoint("TOP", intro.Text, "BOTTOM", 0, -20)

  -- behaviour -----------------------------------------------------------------------------------------------
  function view:PickedItem()
    for _, item in ipairs(self.items or {}) do
      if item.key == self.picked then return item end
    end
  end

  function view:Pick(key)
    self.picked = key
    local item = self:PickedItem()
    if item and item.answerable then
      local detail = GE.Detail(key)
      if not GE.IsOpen(key) or not detail then GE.Open(item) end
    end
    self:CloseForm(true)
    self:Refresh()
  end

  function view:RenderDetail()
    local d = self.Detail
    local item = self:PickedItem()
    local formShown = self.Form:IsShown()
    d:SetShown(item ~= nil and not formShown)
    self.Intro:SetShown(item == nil and not formShown)
    if not item then
      return
    end
    local detail = GE.Detail(item.key)
    local now = GE.Now()
    d.Title:SetText(DungeonMark(item.dungeon, 26) .. item.name)
    local badge = TypeMark(item.kind) .. " " .. Colored(COLORS[item.kind] or COLORS.other, GE.Labels()[item.kind])
    if item.dungeon and not item.dungeon.raid then badge = badge .. "  ·  " .. DungeonLevels(item.dungeon) end
    d.Badge:SetText(badge)
    local date, clock = DateText(item.stamp)
    local parts = { date, clock, Relative(item.stamp, now) }
    if detail and detail.creator then parts[#parts + 1] = L.EV_BY:format(detail.creator) end
    d.When:SetText(table.concat(parts, "  ·  "))
    d.Desc:SetText(detail and detail.description or "")
    local locked = detail and detail.locked
    local inviteType = detail and detail.inviteType
    if not item.answerable then
      d.State:SetText(L.EV_ANNOUNCEMENT)
    elseif locked then
      d.State:SetText(L.EV_LOCKED .. "  ·  " .. L.EV_YOU:format(StatusName(item.answer, inviteType)))
    elseif item.answer == "open" then
      d.State:SetText(L.EV_YOU_OPEN)
    else
      d.State:SetText(L.EV_YOU:format(Colored(ANSWER_COLORS[item.answer], StatusName(item.answer, inviteType))))
    end
    local buttons = item.answerable and not locked and not item.started
    local previous, first
    for _, answer in ipairs({ "yes", "maybe", "no" }) do
      local button = d.Buttons[answer]
      local shown = buttons and item.answer ~= answer
      button:SetShown(shown)
      if shown then
        button:ClearAllPoints()
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 6, 0) else button:SetPoint("TOPLEFT", d.State, "BOTTOMLEFT", 0, -6) end
        previous = button
        first = first or button
      end
    end
    d.Buttons.yes:SetText(inviteType == 0 and L.EV_ANSWER_AVAILABLE or L.EV_ANSWER_YES)
    d.Buttons.maybe:SetText(L.EV_ANSWER_MAYBE)
    d.Buttons.no:SetText(L.EV_ANSWER_NO)
    d.Bar:ClearAllPoints()
    d.Bar:SetPoint("TOPLEFT", first or d.State, "BOTTOMLEFT", 0, first and -12 or -10)
    d.Bar:SetPoint("RIGHT", d, "RIGHT", 0, 0)

    -- the bar and the names
    local counts = detail and detail.counts
    local total = counts and (counts.yes + counts.maybe + counts.no) or 0
    d.Bar:SetShown(item.answerable and total > 0)
    if total > 0 then
      local width, x = math.max(1, d.Bar:GetWidth() or 300), 0
      for _, answer in ipairs({ "yes", "maybe", "no" }) do
        local part = d.Bar.Parts[answer]
        local w = width * counts[answer] / total
        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", x, 0)
        part:SetPoint("BOTTOMLEFT", x, 0)
        part:SetWidth(math.max(0.01, w))
        part:SetShown(w > 0)
        x = x + w
      end
    end
    local message
    if not item.answerable then
      message = ""
    elseif not detail then
      local frame = rawget(_G, "CalendarFrame")
      message = (frame and frame:IsShown()) and L.EV_CALENDAR_OPEN or L.EV_LOADING
    elseif #detail.invites == 0 then
      message = L.EV_NOBODY
    end
    d.Message:SetText(message or "")
    d.Message:SetShown(message ~= nil)
    d.Scroll:SetShown(message == nil)
    if message == nil then
      FillNames(d, detail)
      d.NamesBar()
    end
    -- the buttons at the bottom: calendar, announce, edit, delete, then the hint
    local canEdit = GE.CanEdit(item)
    local last = d.Link
    for _, entry in ipairs({ { d.Announce, GE.CanAnnounce(item) }, { d.Edit, canEdit }, { d.Delete, canEdit } }) do
      local button, shown = entry[1], entry[2] and true or false
      button:SetShown(shown)
      if shown then
        button:ClearAllPoints()
        button:SetPoint("LEFT", last, "RIGHT", 8, 0)
        last = button
      end
    end
    d.EditHint:ClearAllPoints()
    d.EditHint:SetPoint("LEFT", last, "RIGHT", 10, 0)
    d.EditHint:SetPoint("RIGHT", d, "RIGHT", 0, 0)
    d.EditHint:SetShown(canEdit)
  end

  function view:Refresh(_, kind, key)
    if (kind == "created" or kind == "saved") and key then
      self.Form:Hide()
      self.picked = key
    elseif kind == "error" and self.Form:IsShown() then
      self:FormError(key)
    end
    local all = GE.List()
    for _, item in ipairs(all) do
      item.dungeon = DungeonOf(item.name)
      if item.dungeon and item.kind == "other" then item.kind = item.dungeon.raid and "raid" or "dungeon" end
    end
    local now = GE.Now()
    local items, shown, lastGroup = {}, {}, nil
    for _, item in ipairs(all) do
      if not self.onlyOpen or (item.answerable and item.answer == "open") then shown[#shown + 1] = item end
    end
    local headers = { week = L.EV_GROUP_WEEK, next = L.EV_GROUP_NEXT, later = L.EV_GROUP_LATER }
    for _, item in ipairs(shown) do
      local group = E.Group(item.stamp, now)
      if group ~= lastGroup then
        items[#items + 1] = { header = headers[group] }
        lastGroup = group
      end
      items[#items + 1] = item
    end
    self.items = all
    if UI.IsShown() and UI.Current() == "events" then GE.MarkSeen(all) end
    self.Count:SetText(L.EV_UPCOMING:format(#all))
    if not self:PickedItem() then
      local first = shown[1] or all[1]
      self.picked = first and first.key or nil
    end
    -- the picked event's answers: open it while they are not known (also a new event, picked once created)
    local picked = self:PickedItem()
    if picked and picked.answerable and not GE.Detail(picked.key) and UI.IsShown() and UI.Current() == "events" then
      GE.Open(picked)
    end
    self.List:SetItems(items)
    local empty = #shown == 0
    self.Empty:SetShown(empty)
    self.Empty:SetText(#all == 0 and L.EV_EMPTY or L.EV_EMPTY_OPEN)
    self:RenderDetail()
    if self.Form:IsShown() then self:FormChanged() end
  end

  -- the form ------------------------------------------------------------------------------------------------
  local f = view.Form

  -- editing: the event (an item of the list) whose values fill the form
  function view:OpenForm(editing)
    local now = GE.Now()
    local today = math.floor(now / 1440)
    f.editing = editing
    f.Heading:SetText(editing and L.EV_FORM_EDIT_TITLE or L.EV_FORM_TITLE)
    if editing then
      GE.Open(editing) -- saving needs it open in the client
      local detail = GE.Detail(editing.key)
      local _, _, _, h, mi = E.Civil(editing.stamp)
      f.day, f.hour, f.minute = math.floor(editing.stamp / 1440), h, mi
      f.kind = editing.kind
      f.dungeon = editing.dungeon
      f.autoName = editing.dungeon and editing.name == editing.dungeon.name and editing.name or nil
      f.Type:SetValue(f.kind)
      f.Name:SetText(editing.name)
      f.Desc.EditBox:SetText(detail and detail.description or "")
    else
      f.day = today
      f.hour, f.minute = 20, 0
      if today * 1440 + 20 * 60 <= now + 30 then f.day = today + 1 end
      f.kind = "other"
      f.dungeon, f.autoName = nil, nil
      f.Type:SetValue("other")
      f.Name:SetText("")
      f.Desc.EditBox:SetText("")
    end
    local detail = editing and GE.Detail(editing.key)
    f.Lock:SetChecked(detail and detail.locked or false)
    f.Announce:SetChecked(not editing)
    f.Announce:SetShown(not editing)
    f.Announce.Label:SetShown(not editing)
    f.Error:SetText("")
    f.Create:SetEnabled(true)
    f.Create:SetText(editing and L.EV_FORM_SAVE or L.EV_FORM_CREATE)
    f:Show()
    self.Detail:Hide()
    self.Intro:Hide()
    self:FormChanged()
    f.Name:SetFocus()
  end

  function view:CloseForm(quiet)
    if not f:IsShown() then return end
    f:Hide()
    f.Name:ClearFocus()
    f.Desc.EditBox:ClearFocus()
    if not quiet then self:Refresh() end
  end

  function view:MoveDate(step)
    local today = math.floor(GE.Now() / 1440)
    f.day = math.max(today, math.min(today + DATE_DAYS, (f.day or today) + step))
    self:FormChanged()
  end

  local function FormStamp()
    return (f.day or 0) * 1440 + (f.hour or 0) * 60 + (f.minute or 0)
  end

  function view:FormChanged()
    -- the picker for dungeons and raids, the rest of the form below it
    local picking = f.kind == "dungeon" or f.kind == "raid"
    f.Picker:SetShown(picking)
    f.WhenLabel:ClearAllPoints()
    if picking then
      f.WhenLabel:SetPoint("TOPLEFT", f.Picker, "BOTTOMLEFT", -FORM_LABEL, -14)
      local rows, pending = {}, nil
      for _, dungeon in ipairs(Dungeons()) do
        if dungeon.raid == (f.kind == "raid") then
          if pending then
            rows[#rows + 1] = { pending, dungeon }
            pending = nil
          else
            pending = dungeon
          end
        end
      end
      if pending then rows[#rows + 1] = { pending } end
      f.PickList:SetItems(rows)
    else
      f.WhenLabel:SetPoint("TOPLEFT", f.TypeLabel, "BOTTOMLEFT", 0, -20)
    end
    local now = GE.Now()
    local today = math.floor(now / 1440)
    f.Date:SetText(E.ShortDate((f.day or today) * 1440, GE.DayNames(), L.EV_MONTH_FIRST == "1"))
    f.Hour:SetText(("%02d"):format(f.hour or 0))
    f.Minute:SetText(("%02d"):format(f.minute or 0))
    f.Prev:SetEnabled((f.day or today) > today)
    f.Next:SetEnabled((f.day or today) < today + DATE_DAYS)
    local stamp = FormStamp()
    local days = (f.day or today) - today
    f.Relative:SetText(stamp <= now and Colored("ff5a4c", L.EV_ERR_PAST)
      or days == 0 and L.EV_TODAY or days == 1 and L.EV_TOMORROW or L.EV_IN_DAYS:format(days))
  end

  function view:FormError(text)
    f.Error:SetText(text or "")
    f.Create:SetEnabled(true)
    f.Create:SetText(f.editing and L.EV_FORM_SAVE or L.EV_FORM_CREATE)
  end

  -- inside the click: AddEvent needs the key press
  function view:Submit()
    local send = f.editing and function(form) return GE.Edit(f.editing, form) end or GE.Create
    local ok, err = send({
      title = f.Name:GetText() or "", kind = f.kind or "other", stamp = FormStamp(),
      description = f.Desc.EditBox:GetText() or "", locked = f.Lock:GetChecked() == true,
      announce = not f.editing and f.Announce:GetChecked() == true,
    })
    if not ok then
      self:FormError(ERRORS[err] or L.EV_ERR_API)
      return
    end
    f.Error:SetText("")
    f.Create:SetEnabled(false)
    f.Create:SetText(f.editing and L.EV_FORM_SAVING or L.EV_FORM_CREATING)
  end

  function view:OnShow()
    GE.Load(true)
    GE.Fill(true)
  end

  function view:OnHide()
    GE.Fill(false)
  end

  return view
end

-- Opens the tab, on an event when given (the reminder's chat link)
function UI.ShowEvents(key)
  UI.Show()
  UI.SelectTab("events")
  local view = UI.TabView("events")
  if view and key and view.Pick then view:Pick(key) end
end

UI.RegisterTab("events", 7.2, "TAB_EVENTS", Build)
