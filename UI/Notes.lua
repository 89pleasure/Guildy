-- Public and officer notes in Blizzard's own member panel, shown next to Guildy's window.
--
-- C_GuildInfo.SetNote is restricted on Forever (HasRestrictions in Blizzard's API docs): only untainted
-- Blizzard code may call it. The one clean path is Blizzard's own: a row of its guild member list picks
-- the member (CommunitiesFrame.GuildMemberDetailFrame), a mouse click on that panel's note box opens
-- Blizzard's note dialog with the member's GUID, and the dialog's Accept or Enter saves. Guildy must
-- never write any of those values (a GUID, the panel's member, the dialog's data or its text).
-- Approach after SuuUI (github.com/DomenikIrrgang/suuui), which reskins Blizzard's guild window itself.
--
-- Guildy lives inside Blizzard's guild window (UI/Main.lua), so Blizzard's member list and member
-- panel are there whenever Guildy is shown:
-- - Blizzard's member list is made tall enough for every member to have a row, off screen;
-- - picking: while the mouse is on a member anywhere in Guildy (a list row, a card), a secure button
--   lies over it. Its click clicks that member's row in Blizzard's list (Blizzard picks the member) and
--   is passed on to Guildy's own row (character page, menu), so no extra click is needed;
-- - while the character page shows the member Blizzard picked, Blizzard's member panel is shown as it
--   is, next to Guildy's window: its notes, rank menu and buttons are Blizzard's own.
-- (Laying Blizzard's note boxes and edit box invisibly into Guildy's own fields worked only now and
-- then in game, 2026-11-09; the plain panel is what the player asked for.)
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local Notes = {}
UI.Notes = Notes

local NOTE_POPUP = "SET_GUILD_COMMUNITIY_NOTE"
local AWAY_X = 5000 -- off screen to the right
local ROW_HEIGHT = 24
local PANEL_GAP = 10 -- between Guildy's window and Blizzard's member panel beside it
local SIDE_TABS = 60 -- room Guildy's side tabs take right of its window (UI/Main.lua clamps the same)

local placing = false -- Guildy itself is moving the member list (its SetPoint hooks ignore that)
local listHooked = false
local AfterPick -- (below) a member was just picked through the pick button
local docked = false -- Blizzard's member panel is shown next to Guildy's window
local shown -- the member the character page shows (nil: no character page)
local saved = {} -- Blizzard frame -> its anchors before Guildy moved it

-- Blizzard's frames -------------------------------------------------------------------------------

local function Host()
  return UI.Host and UI.Host()
end

-- a part of Blizzard's window (only frames: a client without it gives nil)
local function Part(frame, key)
  local part = frame and frame[key]
  return type(part) == "table" and part or nil
end

local function MemberList()
  return Part(Host(), "MemberList")
end

local function Detail()
  return Part(Host(), "GuildMemberDetailFrame")
end

local function NoteBox(officer)
  return Part(Detail(), officer and "OfficerNoteBackground" or "NoteBackground")
end

local function Save(frame)
  if not frame or saved[frame] then return end
  local points = {}
  for i = 1, frame:GetNumPoints() or 0 do points[i] = { frame:GetPoint(i) } end
  points.width, points.height = frame:GetWidth(), frame:GetHeight()
  saved[frame] = points
end

local function Restore(frame)
  local points = frame and saved[frame]
  if not points then return end
  saved[frame] = nil
  frame:ClearAllPoints()
  for _, p in ipairs(points) do frame:SetPoint(unpack(p)) end
  if points.width and points.height and points.width > 0 and points.height > 0 then
    frame:SetSize(points.width, points.height)
  end
end

local function GuildSelected()
  local host = Host()
  local guildClub = C_Club and ns.Try(C_Club.GetGuildClubId)
  local selected = host and host.GetSelectedClubId and ns.Try(host.GetSelectedClubId, host)
  return guildClub ~= nil and selected == guildClub
end

-- Whether the player may change one of m's notes at all
local function CanEdit(m)
  if not (m and m.guid) then return false end
  local can = ns.Roster.Can()
  return (can.editPublic or can.editOfficer or (ns.Roster.Me and ns.Roster.Me() == m)) and true or false
end

Notes.CanEdit = CanEdit

-- Blizzard's member list: tall and off screen ------------------------------------------------------

-- Blizzard redraws every row its list holds on each roster update and asks for the roster again
-- (CommunitiesMemberList.lua, GUILD_ROSTER_UPDATE). Up to TALL_MAX members the list holds everyone and
-- hears everything, as Blizzard made it. A bigger guild's list hears nothing (below) and grows to hold
-- everyone GROW_STEP rows a frame: grown to all ~1000 rows at once, the first hover froze the game
-- (seen with /guildy stress 2026-11-24). Blizzard's scroll box keeps the rows it has when it grows, so
-- each step costs only its new rows. It stays grown while Blizzard's window is open (a deaf list costs
-- nothing to keep) and starts short again each time the window opens (Blizzard builds every row it
-- holds then).
Notes.TALL_MAX, Notes.SHORT_ROWS, Notes.GROW_STEP, Notes.GROW_WAIT = 200, 12, 40, 1
local grown = 0 -- rows a big guild's list holds now
local growing = false
-- In the gamepad interface the game's cursor searches all of Blizzard's window again for every frame made
-- in it (SmartNavigation's CreateFrame hook), Guildy's included: each new row of the list cost a search,
-- and growing to 1000 rows froze the game for seconds (/guildy stress 2026-11-24). There the list only
-- grows once a note is to be edited (the "Edit notes" button), then for the rest of the session: the
-- rows stay in Blizzard's pool and come back without being made anew.
local demanded = false
local SizeList -- (below)

local function MemberCount()
  return ns.Stress.Count(ns.Try(rawget(_G, "GetNumGuildMembers")) or 0)
end

-- Hearing: every roster update Blizzard's list hears rebuilds and sorts all members (UpdateMemberList in
-- its OnUpdate), and each row it shows re-reads its member (CommunitiesMemberListEntryMixin:OnEvent),
-- however few rows it holds. A guild of 1000 sends one about every 1.5 s, and the window dropped to
-- 0 fps every few seconds (reported 2026-11-23 with 1.11.1, unseen by /guildy perf: it is Blizzard's
-- code). Above TALL_MAX members neither the list nor its rows hear member events. A row needs no
-- fresh data to be clicked: Blizzard's member panel reads the member afresh itself. Only a member with
-- no row (joined since the list was built) lets the next roster update through, not more often than
-- every FRESH_GAP seconds, and the list is deaf again right after Blizzard handled it. 1.11.2 did that
-- on every hover, and with the grown list each one rebuilt ~1000 rows: a freeze every 10-15 s.
-- Only events are switched: Guildy never writes into Blizzard's list (its rows feed the secure pick).
Notes.FRESH_GAP = 10
local MEMBER_EVENTS = { "GUILD_ROSTER_UPDATE", "CLUB_MEMBER_ADDED", "CLUB_MEMBER_REMOVED", "CLUB_MEMBER_UPDATED",
  "CLUB_MEMBERS_UPDATED", "CLUB_MEMBER_PRESENCE_UPDATED", "CLUB_MEMBER_ROLE_UPDATED" }
local deaf = false
local waiting = false -- one roster update is let through
local lastHeard = -math.huge
local hookedRows = setmetatable({}, { __mode = "k" })

local function Big()
  return MemberCount() > Notes.TALL_MAX
end

-- a row of Blizzard's list deaf (it registers again on every show: the hook follows its OnShow)
local function DeafRow(row)
  if type(row) ~= "table" or not row.UnregisterEvent then return end
  if deaf then row:UnregisterEvent("GUILD_ROSTER_UPDATE") end
  if not hookedRows[row] and row.HookScript then
    hookedRows[row] = true
    row:HookScript("OnShow", function(self) if deaf then self:UnregisterEvent("GUILD_ROSTER_UPDATE") end end)
  end
end

local function Rows(list, fn)
  local box = list and list.ScrollBox
  if box and box.ForEachFrame then box:ForEachFrame(fn) end
end

local function SetDeaf(list, on)
  if not list or deaf == on then return end
  for _, event in ipairs(MEMBER_EVENTS) do
    if on then list:UnregisterEvent(event) else list:RegisterEvent(event) end
  end
  deaf = on
  Rows(list, function(row)
    if on then DeafRow(row) elseif row.RegisterEvent and row:IsShown() then row:RegisterEvent("GUILD_ROSTER_UPDATE") end
  end)
end

-- the list deaf or hearing as the guild's size wants it (only while Blizzard's window shows: its
-- OnShow registers the events again, its OnHide drops them), its rows as well
local function Hearing()
  local host, list = Host(), MemberList()
  if not (host and list and host:IsShown()) then return end
  if Big() and not waiting then
    deaf = false -- Blizzard's OnShow may have registered them again: switch them off for sure
    SetDeaf(list, true)
    Rows(list, DeafRow)
  elseif not Big() then
    SetDeaf(list, false) -- (the guild is no longer as big: /guildy stress or biglist off)
  end
end

-- /guildy biglist: a small guild's window as a big guild's (list short, list and rows deaf), to test
-- the big guild's way with any guild; again: back. Only for this session.
function Notes.ToggleBigTest()
  Notes.TALL_MAX = Notes.TALL_MAX == 0 and 200 or 0
  local list = MemberList()
  if Notes.TALL_MAX > 0 and list and list:IsShown() then SetDeaf(list, false) end
  Hearing()
  ns.SafeCall(Notes.Prepare)
  ns.Print(Notes.TALL_MAX == 0 and "biglist on: Blizzard's member list works as in a guild over 200 members"
    or "biglist off")
end

-- the member the mouse is on has no row: one roster update through, the list rebuilds once
local function HearOnce()
  local list = MemberList()
  if not (deaf and list) or GetTime() - lastHeard < Notes.FRESH_GAP then return end
  waiting = true
  -- short for the rebuild (a rebuild makes every row anew); it grows again afterwards
  grown, growing = 0, false
  ns.Perf.Mark("Blizzard's list rebuilt (a member without a row)")
  SizeList()
  SetDeaf(list, false)
  ns.Roster.Request(false, true)
end

-- Blizzard's list built anew once (/guildy stress: its members changed while it was deaf)
function Notes.Rebuild()
  lastHeard = -math.huge
  HearOnce()
end

local function ListRows(count)
  if count <= Notes.TALL_MAX then return count end
  return math.min(count, math.max(grown, Notes.SHORT_ROWS))
end

function SizeList()
  local host, list = Host(), MemberList()
  if not (host and list and host:IsShown()) or InCombatLockdown() then return end
  Save(list)
  local height = ListRows(MemberCount()) * ROW_HEIGHT + 80
  placing = true
  list:ClearAllPoints()
  -- its rows are only clicked by the secure button, never by the mouse
  list:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", AWAY_X, 0)
  list:SetSize(300, height)
  placing = false
  if not listHooked then
    listHooked = true
    -- Blizzard lays its list out again (view changes): back where Guildy wants it
    local function Again()
      if not placing and saved[list] then C_Timer.After(0, SizeList) end
    end
    hooksecurefunc(list, "SetPoint", Again)
    hooksecurefunc(list, "SetSize", Again)
    -- Blizzard's window closed: its list as it was
    host:HookScript("OnHide", function()
      grown, growing = 0, false
      Restore(list)
    end)
    -- (after Blizzard's handler: the roster update let through has marked the list for its rebuild)
    list:HookScript("OnEvent", function(_, event)
      if event ~= "GUILD_ROSTER_UPDATE" or not Big() then return end
      waiting, lastHeard = false, GetTime()
      ns.Perf.Mark("Blizzard's list rebuilds (all members)") -- (in its next OnUpdate)
      SetDeaf(list, true)
      C_Timer.After(0.1, Hearing) -- the rows of the rebuild
      C_Timer.After(Notes.GROW_WAIT, Notes.Grow) -- (rebuilt short) grows again
    end)
    list:HookScript("OnShow", function() C_Timer.After(0, Hearing) end)
  end
end

-- A big guild's list one step taller each frame until it holds every member (its new rows deaf)
local function Step()
  local host = Host()
  local count = MemberCount()
  -- (waiting: a rebuild is let through, it makes every row anew; growing goes on after it)
  if not growing or waiting or not (host and host:IsShown()) or count <= Notes.TALL_MAX or InCombatLockdown() then
    growing = false
    return
  end
  grown = math.min(count, math.max(grown, Notes.SHORT_ROWS) + Notes.GROW_STEP)
  ns.Perf.Mark("Blizzard's list grew to " .. (math.ceil(grown / 100) * 100) .. " rows")
  -- (Blizzard's scroll box makes the new rows right in the resize: measured here)
  ns.Perf.Call("grow", "Blizzard's list, a step", SizeList)
  if deaf then Rows(MemberList(), DeafRow) end
  if grown >= count then
    growing = false
    return
  end
  C_Timer.After(0, Step)
end

function Notes.Grow()
  if ns.GamepadUI() and not demanded then return end
  if growing or waiting or MemberCount() <= Notes.TALL_MAX or grown >= MemberCount() then return end
  growing = true
  Step()
end

-- The mouse is on a member somewhere in Guildy: true while a big guild's list is still growing (the
-- member's row may come in a moment), and in the gamepad interface while it is kept short (a missing row
-- is no stale roster then: no rebuild is let through for it). demand: a note is to be edited (grows in
-- the gamepad interface too)
function Notes.Wake(demand)
  if MemberCount() <= Notes.TALL_MAX then return false end
  if demand then demanded = true end
  Notes.Grow()
  return growing or (ns.GamepadUI() and not demanded)
end

-- Blizzard's list ready before the first click: its rows appear a frame after it grows, so Guildy sizes
-- it when Blizzard's window opens (UI/Main.lua) and whenever the roster changes
function Notes.Prepare()
  ns.Perf.Mark("window opened")
  grown = 0
  SizeList()
  C_Timer.After(0, Hearing)
  -- a big guild's list grows a moment after the window opened (Blizzard built the window just now)
  C_Timer.After(Notes.GROW_WAIT, function() if UI.IsShown() then Notes.Grow() end end)
end
ns.On("ROSTER", function() if UI.IsShown() then SizeList() end end)

-- Whether Blizzard's member info is guid's. In battlegrounds and instances every field of it is secret
-- (Warsong Gulch, 1.9.6: "attempt to compare field 'guid'"): then no row is found and no pick laid.
local function IsGuid(info, guid)
  return info ~= nil and not ns.AnySecret(info.guid, guid) and info.guid == guid
end

-- The member's row in Blizzard's list (rows are filled by Blizzard: clean)
local function Row(guid)
  local list = MemberList()
  local box = list and list.ScrollBox
  if not (guid and box and box.ForEachFrame) then return nil end
  local found
  box:ForEachFrame(function(frame)
    local info = frame.memberInfo
    if not found and IsGuid(info, guid) and not frame.isInvitation then found = frame end
  end)
  return found
end

-- Whether Blizzard's member panel shows m (picked by Blizzard)
local function Picked(m)
  local detail = Detail()
  if not (m and m.guid and detail and detail:IsShown() and detail.GetMemberInfo) then return false end
  local info = ns.Try(detail.GetMemberInfo, detail)
  return IsGuid(info, m.guid)
end

-- The secure pick button -------------------------------------------------------------------------

local pick

local function KeyDownMode()
  local get = (C_CVar and C_CVar.GetCVarBool) or rawget(_G, "GetCVarBool")
  return get and get("ActionButtonUseKeyDown") and true or false
end

local function HidePick()
  if pick and not InCombatLockdown() then pick:Hide() end
end

-- Passes the click on to the frame under the pick button (its own OnClick or OnMouseUp)
local function Forward(owner, button)
  if not (owner and owner.GetScript) then return end
  local onClick = owner:HasScript("OnClick") and owner:GetScript("OnClick")
  if onClick then
    onClick(owner, button, false)
    return
  end
  local onUp = owner:GetScript("OnMouseUp")
  if onUp then onUp(owner, button) end
end

-- the member a frame below the pick button shows now (rows keep it in .member or .item.member)
local function MemberOf(owner)
  return owner.member or (type(owner.item) == "table" and owner.item.member) or nil
end

local function Pick()
  if pick then return pick end
  pick = ns.CreateFrame("Button", "GuildyNotePick", UIParent, "SecureActionButtonTemplate")
  pick:SetFrameStrata("TOOLTIP")
  pick:RegisterForClicks("AnyUp", "AnyDown")
  -- left: clicks the member's row in Blizzard's list (Blizzard picks them), then Guildy's own click;
  -- right: right-clicks that row, so Blizzard opens its own guild member menu. Its "Copy character
  -- name" copies straight to the clipboard: CopyToClipboard is restricted to Blizzard's code.
  pick:SetAttribute("type1", "click")
  pick:SetAttribute("type2", "click")
  pick:SetScript("PostClick", function(self, button, down)
    if (down and true or false) ~= KeyDownMode() then return end -- registered for both; act once
    local owner, m, forward, onClick = self.owner, self.member, self.forward, self.onClick
    if not InCombatLockdown() then self:Hide() end
    -- over a name in the chat (Notes.HoverLink): the chat's own click, the right one included
    if onClick then
      if m and button ~= "RightButton" then AfterPick() end
      onClick(button)
      return
    end
    if button == "RightButton" and self.blizzardMenu then return end -- Blizzard's menu instead of Guildy's
    if m then AfterPick() end
    if forward then Forward(owner, button) end
  end)
  pick:SetScript("OnDoubleClick", function(self, button)
    local owner = self.owner
    local fn = self.forward and owner and owner:GetScript("OnDoubleClick")
    if fn then fn(owner, button) end
  end)
  -- the pick button came over the frame below: that frame keeps its tooltip and highlight
  pick:SetScript("OnEnter", function(self)
    local owner = self.owner
    if self.forward and owner and self.member then UI.MemberTooltip(owner, self.member, self.hint) end
    if owner and owner.LockHighlight then owner:LockHighlight() end
  end)
  pick:SetScript("OnLeave", function(self)
    local owner = self.owner
    GameTooltip:Hide()
    if owner and owner.UnlockHighlight then owner:UnlockHighlight() end
    HidePick()
  end)
  -- the frame below went away or shows someone else now (a list scrolled under the resting mouse)
  pick:SetScript("OnUpdate", function(self)
    local owner = self.owner
    if not owner or not owner:IsVisible() or (self.forward and MemberOf(owner) ~= self.member)
      or (self.still and not self.still()) then HidePick() end
  end)
  pick:Hide()
  return pick
end

-- Lays the pick button over owner (a frame showing member m) while the mouse is on it.
-- forward: the click goes on to owner afterwards; hint: owner's tooltip hint.
local function LayPick(owner, m, forward, hint)
  if InCombatLockdown() or not (m and m.guid) then return false end
  local host = Host()
  if not (host and host:IsShown() and GuildSelected()) then return false end
  local grew = Notes.Wake(not forward) -- (a big guild's list grows now, its rows come a frame later)
  local p = Pick()
  if p:IsShown() and p.owner == owner and p.member == m then return true end
  local row = Row(m.guid)
  if not row then
    if not grew then
      SizeList()
      HearOnce()
    end
    return false
  end
  local left, bottom = owner:GetLeft(), owner:GetBottom()
  if not (left and bottom) then return false end
  p.owner, p.member, p.forward, p.hint, p.onClick, p.still = owner, m, forward, hint, nil, nil
  -- right: Blizzard's guild member menu, but not in the gamepad interface. There the game puts the
  -- menu beside the row it opens from, and Blizzard's list lies off screen: the menu stood empty at
  -- the screen's edge (seen in game 2026-11-22). Guildy's own menu opens instead (PostClick).
  p.blizzardMenu = not ns.GamepadUI()
  p:SetAttribute("type2", p.blizzardMenu and "click" or nil)
  p:SetAttribute("clickbutton1", row)
  p:SetAttribute("clickbutton2", p.blizzardMenu and row or nil)
  local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
  p:ClearAllPoints()
  p:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
  p:SetSize(owner:GetWidth() * scale, owner:GetHeight() * scale)
  p:Show()
  return true
end

-- The mouse is on member m somewhere in Guildy (UI.MemberTooltip): the click there picks m in
-- Blizzard's list too, then goes on to that frame as always
local RETRIES = 30 -- tries every 0.1 s while a big guild's list grows towards the member's row
function Notes.HoverMember(owner, m, hint)
  ns.Perf.Mark("mouse on a member")
  if not (owner and m and MemberOf(owner) == m) or LayPick(owner, m, true, hint) then return end
  -- Blizzard's row may appear a moment later (the list grows): again while the mouse stays on the member
  local tries = 0
  local function Again()
    tries = tries + 1
    if not (MemberOf(owner) == m and owner:IsVisible() and owner:IsMouseOver()) then return end
    if not LayPick(owner, m, true, hint) and growing and tries < RETRIES then C_Timer.After(0.1, Again) end
  end
  C_Timer.After(0.1, Again)
end

-- The mouse is on member m's name in a chat (frame: its message frame, which gives no bounds for a
-- link): a small pick button under the cursor. Its left click picks m in Blizzard's list, then every
-- click goes to onClick(button) as the chat's own (right: Guildy's menu, nothing of Blizzard's).
-- Moving off it hides it; still on the name, the chat's OnHyperlinkEnter lays it again under the
-- cursor. still(): false once the text moved under it (scrolled, a new message).
local LINK_PICK = 16
function Notes.HoverLink(frame, m, onClick, still, retry)
  if InCombatLockdown() or not (frame and m and m.guid) then return end
  local host = Host()
  if not (host and host:IsShown() and GuildSelected()) then return end
  local grew = Notes.Wake()
  local row = Row(m.guid)
  if not row then
    if not grew then
      SizeList()
      HearOnce()
    end
    -- the row comes a moment later (the list grows): again while the name is still under the mouse
    retry = retry or 0
    if grew and retry < RETRIES then
      C_Timer.After(0.1, function()
        if not still or still() then Notes.HoverLink(frame, m, onClick, still, retry + 1) end
      end)
    end
    return
  end
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  if not (x and y and scale and scale > 0) then return end
  local p = Pick()
  p.owner, p.member, p.forward, p.hint, p.onClick, p.still = frame, m, false, nil, onClick, still
  p.blizzardMenu = false
  p:SetAttribute("clickbutton1", row)
  p:SetAttribute("type2", nil)
  p:SetAttribute("clickbutton2", nil)
  p:ClearAllPoints()
  p:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
  p:SetSize(LINK_PICK, LINK_PICK)
  p:Show()
end

-- The character page's "Edit notes" button (mouse on it): its click picks m in Blizzard's list like a
-- click on a member row. The page is often opened without such a click: a name in the chat, Guildy's
-- member menu, the page that stayed open while Blizzard's panel closed. Blizzard's row may appear a
-- moment after the list grew: tried again while the mouse stays on the button.
function Notes.HoverButton(owner, m)
  if not (owner and m) or LayPick(owner, m, false) then return end
  C_Timer.After(0.2, function()
    if owner:IsVisible() and owner:IsMouseOver() then LayPick(owner, m, false) end
  end)
end

-- The button was clicked but no pick lay over it (the click reached the button itself): why, in chat
function Notes.Explain(m)
  if not (m and m.guid) or Picked(m) then return end
  local L = ns.L
  if InCombatLockdown() then
    ns.Print(L.BLIZZARD_PART_MISSING)
  elseif not GuildSelected() then
    ns.Print(L.NOTES_SELECT_GUILD)
  elseif not Row(m.guid) then
    if not Notes.Wake(true) then
      SizeList()
      HearOnce()
    end
    ns.Print(L.NOTES_HIDDEN:format(m.name))
  end
end

-- Blizzard's list leaves out offline members in its roster view unless "Show offline members" is
-- ticked there (CommunitiesMemberListMixin:ShouldShowOfflinePlayers): no row, nothing to pick, and
-- Blizzard's member panel never showed for them (reported 2026-11-16). Its list reads that setting
-- from the cvar once, when Blizzard_Communities loads (on demand, after Guildy): set before that, it
-- is Blizzard's own untainted value. Guildy writes nothing of Blizzard's list.
do
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
  local set = (C_CVar and C_CVar.SetCVar) or rawget(_G, "SetCVar")
  if set and not (loaded and loaded("Blizzard_Communities")) then pcall(set, "communitiesShowOffline", "1") end
end

-- Guildy's look on Blizzard's panel and note dialog -------------------------------------------------
-- Only looks: Blizzard's frame art goes see-through (alpha, an engine value) and Guildy's own boxes lie
-- behind it. Nothing is written into Blizzard's tables; texts, buttons and the rank menu stay Blizzard's.

local hidden = {} -- Blizzard frame or texture -> its alpha before Guildy made it see-through

local function SeeThrough(object)
  if object and hidden[object] == nil then
    hidden[object] = object:GetAlpha()
    object:SetAlpha(0)
  end
end

local function Unhide(object)
  if object and hidden[object] ~= nil then
    object:SetAlpha(hidden[object])
    hidden[object] = nil
  end
end

-- a frame's own textures (not its texts)
local function Textures(frame)
  local list = {}
  for _, region in ipairs({ frame:GetRegions() }) do
    if region.GetObjectType and region:GetObjectType() == "Texture" then list[#list + 1] = region end
  end
  return list
end

local tinted = {} -- Blizzard texture -> its vertex colour before Guildy recoloured it

-- A backdrop piece in Guildy's field colours: the fill near black, the edge Guildy's dim gold
local function Tint(texture, fill)
  if tinted[texture] == nil then tinted[texture] = { texture:GetVertexColor() } end
  if fill then
    texture:SetVertexColor(0.03, 0.025, 0.02, 0.95)
  else
    texture:SetVertexColor(W.GOLD[1] * 0.6, W.GOLD[2] * 0.6, W.GOLD[3] * 0.6, 1)
  end
end

local function Untint(texture)
  local color = tinted[texture]
  if color then
    texture:SetVertexColor(unpack(color))
    tinted[texture] = nil
  end
end

local backs = {} -- Blizzard frame -> Guildy's box behind it

-- Guildy's box behind frame: a child of parent at frame level level (below frame's own parts)
local function Backing(frame, parent, level, shade, border)
  local box = backs[frame]
  if not box then
    box = W.Box(parent, shade, border)
    box:SetIgnoreParentAlpha(true)
    box:EnableMouse(false)
    backs[frame] = box
  end
  box:ClearAllPoints()
  box:SetAllPoints(frame)
  box:SetFrameLevel(math.max(0, level))
  box:Show()
end

local function Unbacking(frame)
  local box = backs[frame]
  if box then box:Hide() end
end

-- Blizzard's member panel: its dark dialog border see-through, Guildy's box behind it, the two note
-- boxes as Guildy's fields
local BUTTON_GAP, BUTTON_INSET = 6, 10
local laidButtons = {} -- Blizzard button -> its width before Guildy laid it out

-- Remove and group invite side by side at the bottom, equally wide (Guildy's button row)
local function LayButtons(detail)
  local remove, invite = Part(detail, "RemoveButton"), Part(detail, "GroupInviteButton")
  if not (remove and invite) then return end
  local width = math.floor(((detail:GetWidth() or 212) - 2 * BUTTON_INSET - BUTTON_GAP) / 2)
  for _, button in ipairs({ remove, invite }) do
    Save(button)
    if laidButtons[button] == nil then laidButtons[button] = button:GetWidth() end
    button:SetWidth(width)
    button:ClearAllPoints()
  end
  remove:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", BUTTON_INSET, BUTTON_INSET)
  invite:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -BUTTON_INSET, BUTTON_INSET)
end

local function UnlayButtons(detail)
  for _, key in ipairs({ "RemoveButton", "GroupInviteButton" }) do
    local button = Part(detail, key)
    if button and laidButtons[button] then
      button:SetWidth(laidButtons[button])
      laidButtons[button] = nil
      Restore(button)
    end
  end
end

local function SkinDetail()
  local host, detail = Host(), Detail()
  if not (host and detail) then return end
  SeeThrough(Part(detail, "Border"))
  -- part of the character page: it closes with the page, no close button of its own
  local close = Part(detail, "CloseButton")
  if close then close:Hide() end
  -- the name in its class colour, as everywhere in Guildy
  local name = Part(detail, "Name")
  if name and shown then name:SetTextColor(W.ClassColor(shown.classFile)) end
  LayButtons(detail)
  -- Guildy's box behind the whole panel, below its lowest part (Blizzard shifts its levels when the
  -- panel shows again)
  local lowest = detail:GetFrameLevel()
  for _, officer in ipairs({ false, true }) do
    local box = NoteBox(officer)
    if box then lowest = math.min(lowest, box:GetFrameLevel()) end
  end
  Backing(detail, host, lowest - 2)
  -- the note boxes keep their own backdrop, recoloured as Guildy's fields: a box of Guildy's behind
  -- them slid in front of their text once Blizzard reordered the levels (found in game)
  for _, officer in ipairs({ false, true }) do
    local box = NoteBox(officer)
    if box then
      for _, texture in ipairs(Textures(box)) do
        -- the fill: the backdrop's Center, or failing that the one big piece (edges and corners are thin)
        local w, h = texture:GetWidth() or 0, texture:GetHeight() or 0
        Tint(texture, texture == box.Center or (w > 20 and h > 20))
      end
    end
  end
end

local function UnskinDetail()
  local detail = Detail()
  if not detail then return end
  Unhide(Part(detail, "Border"))
  local close = Part(detail, "CloseButton")
  if close then close:Show() end
  local name = Part(detail, "Name")
  if name then name:SetTextColor(1, 0.82, 0) end
  UnlayButtons(detail)
  Unbacking(detail)
  for _, officer in ipairs({ false, true }) do
    local box = NoteBox(officer)
    if box then
      for _, texture in ipairs(Textures(box)) do Untint(texture) end
    end
  end
end

-- Blizzard's note dialog: its frame art see-through (every part but its buttons, edit box and close
-- button), Guildy's box behind it and behind its edit box
local DIALOG_KEEP = { ButtonContainer = true, EditBox = true, CloseButton = true, CoverFrame = true,
  ExtraButton = true, GamepadSequence = true }
local dialogArt = {} -- dialog -> the parts Guildy made see-through

local function SkinDialog(dialog)
  local art = {}
  for _, child in ipairs({ dialog:GetChildren() }) do
    local keep = false
    for key in pairs(DIALOG_KEEP) do
      if dialog[key] == child then keep = true end
    end
    if not keep then art[#art + 1] = child end
  end
  for _, texture in ipairs(Textures(dialog)) do art[#art + 1] = texture end
  local edit = Part(dialog, "EditBox")
  if edit then
    for _, texture in ipairs(Textures(edit)) do art[#art + 1] = texture end
  end
  for _, object in ipairs(art) do SeeThrough(object) end
  dialogArt[dialog] = art
  local level = dialog:GetFrameLevel()
  Backing(dialog, UIParent, level - 1, 0.07, 0.9)
  backs[dialog]:SetFrameStrata(dialog:GetFrameStrata())
  if edit then
    Backing(edit, UIParent, level, 0.02, 0.6)
    backs[edit]:SetFrameStrata(dialog:GetFrameStrata())
  end
end

local function UnskinDialog(dialog)
  for _, object in ipairs(dialogArt[dialog] or {}) do Unhide(object) end
  dialogArt[dialog] = nil
  Unbacking(dialog)
  local edit = Part(dialog, "EditBox")
  if edit then Unbacking(edit) end
end

-- Blizzard's member panel next to Guildy -----------------------------------------------------------


local Undock -- (below)

-- Blizzard's panel shows someone else now (its own list, a guild change) or closed
local hookedDetail = false
local function HookDetail()
  local detail = Detail()
  if hookedDetail or not detail then return end
  hookedDetail = true
  detail:HookScript("OnHide", function() if docked then Undock() end end)
end

function Undock()
  local detail = Detail()
  -- (Blizzard's member panel and Guildy's boxes aren't protected: this works in combat too, so the
  -- panel never stays half shown after a fight)
  if not docked or not detail then return end
  docked = false
  UnskinDetail()
  detail:SetIgnoreParentAlpha(false)
  Restore(detail)
end

-- Blizzard's panel beside Guildy's window, left of it (right when there is no room), by coordinates:
-- it is a child of Blizzard's window, never anchored to Guildy's frame. Drawn (it ignores its window's
-- alpha 0) and outside Guildy's window, so nothing lies over it and its own note boxes, rank menu and
-- buttons work as in Blizzard's window.
local function Dock()
  local detail, guildy = Detail(), UI.frame
  if not (detail and guildy) then return end
  local left, top, right = guildy:GetLeft(), guildy:GetTop(), guildy:GetRight()
  if not (left and top and right) then return end
  -- Guildy's edges in the panel's units: Guildy's window may have a size of its own (UI.SetScale)
  local own, theirs = guildy.GetEffectiveScale and guildy:GetEffectiveScale(), detail.GetEffectiveScale and detail:GetEffectiveScale()
  if type(own) == "number" and type(theirs) == "number" and theirs > 0 then
    local factor = own / theirs
    left, top, right = left * factor, top * factor, right * factor
  end
  Save(detail)
  docked = true
  local width = detail:GetWidth() or 212
  local x = left - width - PANEL_GAP
  -- no room on the left: right of Guildy's window, past its side tabs (guild, communities) outside its edge
  if x < 0 then x = right + SIDE_TABS end
  detail:SetIgnoreParentAlpha(true)
  detail:ClearAllPoints()
  detail:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top - 60)
  SkinDetail()
  HookDetail()
end

-- Docked while the character page shows the member Blizzard picked. Guildy never shows Blizzard's
-- panel itself: its Show runs Blizzard's OnShow from Guildy's code (CommunitiesFrame:RegisterDialogShown
-- closes Blizzard's popups and keeps the panel as its last dialog), and that taint reached Blizzard's
-- rank menu and note dialog until a reload. Blizzard hides the panel when its window closes and for a
-- moment during a rank change (its member info without a rank); a click on the member or on "Edit notes"
-- picks them again (reported 2026-11-17: rank changes stopped working after a while).
local function Update()
  local wanted = shown and UI.IsShown() and CanEdit(shown)
  if wanted and Picked(shown) then Dock() else Undock() end
end
Notes.Follow = function() if docked then Dock() end end

-- The character page shows m (nil: it went away)
function Notes.Show(m)
  shown = m
  Update()
  -- again after Blizzard's own handlers ran (its window just opened: they may hide the panel)
  C_Timer.After(0, Update)
end

function Notes.Hide()
  shown = nil
  Undock()
end

-- Blizzard's own window is shown instead of Guildy (UI.ShowBlizzard): its member list back where and
-- as big as it was. Blizzard's chat is anchored to that list, and with the list still parked off
-- screen the chat's frame stretched across the whole screen and showed nothing (reported on Reddit
-- and seen in game 2026-11-10). Opening Guildy again parks it again (Notes.Prepare).
function Notes.Release()
  Notes.Hide()
  if InCombatLockdown() then return end
  if pick then pick:Hide() end
  placing = true
  Restore(MemberList())
  placing = false
  waiting = false
  local list = MemberList()
  if list and list:IsShown() then SetDeaf(list, false) end -- Blizzard's own list hears everything again
end

-- After a pick (the click on a member in a Guildy list): dock once Blizzard shows them
function AfterPick()
  HookDetail()
  C_Timer.After(0, Update)
end

-- Blizzard's note dialog: once it closes Guildy asks for a fresh roster so the saved note shows up
local hookedDialogs = {} -- dialogs whose OnHide Guildy hooked (kept here: nothing is written into Blizzard's)

hooksecurefunc("StaticPopup_Show", function(which)
  if which ~= NOTE_POPUP or not docked then return end
  local find = rawget(_G, "StaticPopup_FindVisible")
  local dialog = find and find(which)
  if not dialog then return end
  SkinDialog(dialog)
  if hookedDialogs[dialog] then return end
  hookedDialogs[dialog] = true
  -- (the popup frames are shared by every dialog: Guildy's look goes again when this one closes)
  dialog:HookScript("OnHide", function(self)
    if not dialogArt[self] then return end
    UnskinDialog(self)
    C_Timer.After(1, function() ns.Roster.Request(true) end)
  end)
end)

-- /guildy notedebug: where Blizzard's frames are (for bug reports)
function Notes.Debug()
  local lines = {}
  local function add(...) lines[#lines + 1] = table.concat({ ... }, " ") end
  local function state(f)
    if not f then return "nil" end
    local l, b, w, h = f:GetRect()
    return ("shown %s visible %s alpha %.2f %s/%s rect %s,%s %sx%s"):format(tostring((f:IsShown())),
      tostring((f:IsVisible())), (f:GetEffectiveAlpha() or 0), tostring((f:GetFrameStrata())),
      tostring((f:GetFrameLevel())),
      tostring(l and math.floor(l)), tostring(b and math.floor(b)), tostring(w and math.floor(w)),
      tostring(h and math.floor(h)))
  end
  local m = shown
  add("guild", tostring(GuildSelected()), "combat", tostring(InCombatLockdown()), "member", tostring(m and m.name),
    "picked", tostring(Picked(m)), "row", tostring(m and Row(m.guid) ~= nil), "can", tostring(CanEdit(m)))
  add("host:", state(Host()))
  -- taint: who wrote the values Blizzard's rank menu and note dialog read (nil = Blizzard itself)
  local secure = rawget(_G, "issecurevariable")
  if secure then
    local function by(t, key)
      if not t then return "-" end
      local ok, isSecure, addon = pcall(secure, t, key)
      if not ok then return "?" end
      return isSecure and "clean" or ("tainted by " .. tostring(addon))
    end
    add("taint lastActiveDialog", by(Host(), "lastActiveDialog"), "clubId", by(Detail(), "clubId"),
      "memberId", by(Detail(), "memberId"))
  end
  local club = C_Club and ns.Try(C_Club.GetGuildClubId)
  local me = club and ns.Try(C_Club.GetMemberInfoForSelf, club)
  add("club", tostring(club), "ready", tostring(club and ns.Try(C_Club.AreMembersReady, club)),
    "my rank order", tostring(me and me.guildRankOrder))
  add("guildy:", state(UI.frame))
  add("list:", state(MemberList()))
  add("hearing:", "deaf", tostring(deaf), "waiting", tostring(waiting), "big", tostring(Big()))
  add("detail:", state(Detail()))
  for _, officer in ipairs({ false, true }) do
    local box = NoteBox(officer)
    add(officer and "officer box:" or "note box:", state(box), "mouse", tostring(box and box:IsMouseEnabled()))
  end
  local foci = rawget(_G, "GetMouseFoci") and _G.GetMouseFoci()
  if type(foci) == "table" then
    for i, f in ipairs(foci) do
      if i > 4 then break end
      add("  mouse " .. i .. ":", tostring(f.GetDebugName and f:GetDebugName()))
    end
  end
  return lines
end
