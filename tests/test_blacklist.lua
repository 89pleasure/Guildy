local T = ...
local ns = T.pureNs()
local BL = ns.Blacklist

local NOW = 1800000000
local OFFICERS = { ["alva abendrot"] = true }
local PROTECTED = { ["hanno glutpfad"] = true }
local ctx = {
  isOfficer = function(name) return OFFICERS[ns.Names.Key(name)] == true end,
  isProtected = function(name) return PROTECTED[ns.Names.Key(name)] == true end,
}

local function Count(book)
  local n = 0
  for _ in pairs(book) do n = n + 1 end
  return n
end

T.describe("Blacklist", function()
  T.it("adds a name with kind and reason", function()
    local book = {}
    local entry = BL.Add(book, "Krag Eisenzahn", "kos", "campt den Friedhof", "Pell Quellgrund", NOW, ctx)
    T.truthy(entry, "added")
    T.eq(book["krag eisenzahn"], { n = "Krag Eisenzahn", t = "kos", r = "campt den Friedhof", a = "Pell Quellgrund", at = NOW })
    T.eq(BL.IsLive(entry), true)
  end)

  T.it("keeps what was seen of the player", function()
    local book = {}
    BL.Add(book, "Krag Eisenzahn", "kos", nil, "Pell Quellgrund", NOW, ctx, { c = "WARRIOR", l = 60, f = "H" })
    T.eq(book["krag eisenzahn"].c, "WARRIOR")
    T.eq(book["krag eisenzahn"].l, 60)
    T.eq(book["krag eisenzahn"].f, "H")
    T.eq(book["krag eisenzahn"].r, nil)
  end)

  T.it("keys names like the roster does", function()
    local book = {}
    BL.Add(book, "  krag eisenzahn ", "kos", nil, "Pell Quellgrund", NOW, ctx)
    BL.Add(book, "Krag Eisenzahn", "ninja", nil, "Pell Quellgrund", NOW + 1, ctx)
    T.eq(Count(book), 1)
    T.eq(book["krag eisenzahn"].t, "ninja")
  end)

  T.it("caps the reason and maps unknown kinds", function()
    local book = {}
    BL.Add(book, "Krag Eisenzahn", "zzz", string.rep("a", 70), "Pell Quellgrund", NOW, ctx)
    T.eq(#book["krag eisenzahn"].r, 60)
    T.eq(book["krag eisenzahn"].t, "other")
    T.eq(BL.Tag("scam"), "scam")
    T.eq(BL.Tag(nil), "other")
  end)

  T.it("treats an empty reason as none", function()
    local book = {}
    BL.Add(book, "Krag Eisenzahn", "kos", "   ", "Pell Quellgrund", NOW, ctx)
    T.eq(book["krag eisenzahn"].r, nil)
  end)

  T.it("refuses guild members and own characters", function()
    local book = {}
    local entry, err = BL.Add(book, "Hanno Glutpfad", "kos", nil, "Pell Quellgrund", NOW, ctx)
    T.eq(entry, nil)
    T.eq(err, "protected")
    T.eq(book, {})
  end)

  T.it("refuses an empty name", function()
    local book = {}
    local entry, err = BL.Add(book, "  ", "kos", nil, "Pell Quellgrund", NOW, ctx)
    T.eq(entry, nil)
    T.eq(err, "name")
    T.eq(book, {})
  end)

  T.it("only officers remove", function()
    local book = {}
    BL.Add(book, "Krag Eisenzahn", "kos", nil, "Pell Quellgrund", NOW, ctx)
    local entry, err = BL.Remove(book, "Krag Eisenzahn", "Tara Kiesel", NOW + 10, ctx)
    T.eq(entry, nil)
    T.eq(err, "officer")
    T.eq(BL.IsLive(book["krag eisenzahn"]), true)
    entry = BL.Remove(book, "Krag Eisenzahn", "Alva Abendrot", NOW + 10, ctx)
    T.eq(entry.x, NOW + 10)
    T.eq(entry.xb, "Alva Abendrot")
    T.eq(BL.IsLive(entry), false)
    local _, missing = BL.Remove(book, "Niemand Hier", "Alva Abendrot", NOW + 10, ctx)
    T.eq(missing, "missing")
  end)

  T.it("only officers re-add a removed name", function()
    local book = {}
    BL.Add(book, "Krag Eisenzahn", "kos", nil, "Pell Quellgrund", NOW, ctx)
    BL.Remove(book, "Krag Eisenzahn", "Alva Abendrot", NOW + 10, ctx)
    local entry, err = BL.Add(book, "Krag Eisenzahn", "kos", nil, "Pell Quellgrund", NOW + 20, ctx)
    T.eq(entry, nil)
    T.eq(err, "removed")
    T.eq(BL.IsLive(book["krag eisenzahn"]), false)
    entry = BL.Add(book, "Krag Eisenzahn", "kos", "wieder da", "Alva Abendrot", NOW + 20, ctx)
    T.eq(BL.IsLive(entry), true)
    T.eq(entry.x, NOW + 10)
    T.eq(entry.r, "wieder da")
  end)

  T.it("merges the newest event per name", function()
    local book = {}
    BL.Add(book, "Krag Eisenzahn", "kos", "neu", "Pell Quellgrund", NOW, ctx)
    -- an older add changes nothing
    T.eq(BL.Merge(book, { n = "Krag Eisenzahn", t = "ninja", r = "alt", a = "Tara Kiesel", at = NOW - 100 }, NOW, ctx), false)
    T.eq(book["krag eisenzahn"].r, "neu")
    -- a newer removal by an officer wins
    T.eq(BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = NOW, x = NOW + 5,
      xb = "Alva Abendrot" }, NOW + 10, ctx), true)
    T.eq(BL.IsLive(book["krag eisenzahn"]), false)
    -- an old copy of the add does not bring it back
    T.eq(BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = NOW }, NOW + 10, ctx), false)
    T.eq(BL.IsLive(book["krag eisenzahn"]), false)
  end)

  T.it("takes a new entry from a merge", function()
    local book = {}
    T.eq(BL.Merge(book, { n = "Bodo Langfinger", t = "ninja", r = "Bedarf auf alles", a = "Pell Quellgrund", at = NOW,
      c = "ROGUE", l = 52, f = "A" }, NOW, ctx), true)
    T.eq(book["bodo langfinger"], { n = "Bodo Langfinger", t = "ninja", r = "Bedarf auf alles", a = "Pell Quellgrund",
      at = NOW, c = "ROGUE", l = 52, f = "A" })
  end)

  T.it("fills what was seen but never overwrites it", function()
    local book = {}
    BL.Add(book, "Bodo Langfinger", "ninja", nil, "Pell Quellgrund", NOW, ctx, { c = "ROGUE" })
    T.eq(BL.Merge(book, { n = "Bodo Langfinger", t = "ninja", a = "Pell Quellgrund", at = NOW, c = "MAGE", l = 52 },
      NOW, ctx), true)
    T.eq(book["bodo langfinger"].c, "ROGUE")
    T.eq(book["bodo langfinger"].l, 52)
  end)

  T.it("drops a removal whose remover is no officer", function()
    local book = {}
    BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = NOW, x = NOW + 5,
      xb = "Tara Kiesel" }, NOW + 10, ctx)
    local entry = book["krag eisenzahn"]
    T.eq(BL.IsLive(entry), true)
    T.eq(entry.x, nil)
    T.eq(entry.xb, nil)
    -- a lone forged removal of an unknown entry stores nothing
    local other = {}
    T.eq(BL.Merge(other, { n = "Krag Eisenzahn", x = NOW, xb = "Tara Kiesel" }, NOW, ctx), false)
    T.eq(other, {})
  end)

  T.it("drops a re-add by a non-officer", function()
    local book = {}
    BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = NOW - 10, x = NOW,
      xb = "Alva Abendrot" }, NOW, ctx)
    T.eq(BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = NOW + 5 }, NOW + 10, ctx), false)
    T.eq(BL.IsLive(book["krag eisenzahn"]), false)
    T.eq(BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", a = "Alva Abendrot", at = NOW + 5 }, NOW + 10, ctx), true)
    T.eq(BL.IsLive(book["krag eisenzahn"]), true)
  end)

  T.it("drops times from the future", function()
    local book = {}
    T.eq(BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = NOW + 3601 }, NOW, ctx), false)
    T.eq(book, {})
    T.eq(BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = NOW + 3599 }, NOW, ctx), true)
    -- a future removal is dropped, the entry stays live
    T.eq(BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = NOW + 3599, x = NOW + 9999,
      xb = "Alva Abendrot" }, NOW, ctx), false)
    T.eq(BL.IsLive(book["krag eisenzahn"]), true)
  end)

  T.it("drops adds of protected names on receipt", function()
    local book = {}
    T.eq(BL.Merge(book, { n = "Hanno Glutpfad", t = "insult", a = "Pell Quellgrund", at = NOW }, NOW, ctx), false)
    T.eq(book, {})
  end)

  T.it("rejects malformed items", function()
    local book = {}
    T.eq(BL.Merge(book, "Krag", NOW, ctx), false)
    T.eq(BL.Merge(book, { n = 7, t = "kos", a = "Pell Quellgrund", at = NOW }, NOW, ctx), false)
    T.eq(BL.Merge(book, { n = string.rep("a", 65), t = "kos", a = "Pell Quellgrund", at = NOW }, NOW, ctx), false)
    T.eq(BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = "jetzt" }, NOW, ctx), false)
    T.eq(BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", at = NOW }, NOW, ctx), false)
    T.eq(BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = NOW, r = 5, l = "x" }, NOW, ctx), true)
    T.eq(book["krag eisenzahn"].r, nil)
    T.eq(book["krag eisenzahn"].l, nil)
  end)

  T.it("sorts newest first", function()
    local book = {}
    BL.Add(book, "Krag Eisenzahn", "kos", nil, "Pell Quellgrund", NOW, ctx)
    BL.Add(book, "Bodo Langfinger", "ninja", nil, "Pell Quellgrund", NOW + 20, ctx)
    BL.Add(book, "Gerd Großmaul", "insult", nil, "Pell Quellgrund", NOW + 10, ctx)
    BL.Remove(book, "Bodo Langfinger", "Alva Abendrot", NOW + 30, ctx)
    local live = BL.Sorted(book)
    T.eq(#live, 2)
    T.eq(live[1].n, "Gerd Großmaul")
    T.eq(live[2].n, "Krag Eisenzahn")
    local all = BL.Sorted(book, true)
    T.eq(#all, 3)
    T.eq(all[1].n, "Bodo Langfinger")
  end)
  T.it("packs the list into messages of 40", function()
    local book = {}
    for i = 1, 85 do BL.Add(book, ("Gegner %03d"):format(i), "kos", nil, "Pell Quellgrund", NOW + i, ctx) end
    local lists = BL.Wire(book)
    T.eq(#lists, 3)
    T.eq(#lists[1], 40)
    T.eq(#lists[3], 5)
    T.eq(lists[1][1].n, "Gegner 001")
    T.eq(lists[3][5].n, "Gegner 085")
  end)

  T.it("copies only known fields onto the wire", function()
    local item = BL.Item({ n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = NOW, junk = true })
    T.eq(item, { n = "Krag Eisenzahn", t = "kos", a = "Pell Quellgrund", at = NOW })
  end)

  T.it("gives the same digest after a whole-list exchange", function()
    local a, b = {}, {}
    BL.Add(a, "Krag Eisenzahn", "kos", "Friedhof", "Pell Quellgrund", NOW, ctx)
    BL.Add(a, "Bodo Langfinger", "ninja", nil, "Pell Quellgrund", NOW + 5, ctx)
    BL.Remove(a, "Bodo Langfinger", "Alva Abendrot", NOW + 9, ctx)
    for _, list in ipairs(BL.Wire(a)) do BL.Apply(b, list, NOW + 10, ctx) end
    T.eq(BL.Digest(b), BL.Digest(a))
    T.eq(BL.Digest(a), { n = 2, m = NOW + 9, s = (NOW + NOW + 5 + NOW + 9) % 2147483647 })
    T.eq(BL.Apply(b, "kaputt", NOW, ctx), false)
  end)

  T.it("changes the digest when one time changes", function()
    local book = {}
    BL.Add(book, "Krag Eisenzahn", "kos", nil, "Pell Quellgrund", NOW, ctx)
    local before = BL.Digest(book)
    book["krag eisenzahn"].at = NOW + 1
    T.eq(BL.Differs(before, BL.Digest(book)), true)
    T.eq(BL.Differs(before, before), false)
    T.eq(BL.Differs({ n = 1, m = 2, s = 3 }, nil), true)
    T.eq(BL.Digest(nil), { n = 0, m = 0, s = 0 })
  end)

  T.it("knows when it is ahead", function()
    T.eq(BL.Ahead({ n = 1, m = 10, s = 1 }, { n = 5, m = 9, s = 1 }), true)
    T.eq(BL.Ahead({ n = 3, m = 10, s = 1 }, { n = 2, m = 10, s = 2 }), true)
    T.eq(BL.Ahead({ n = 2, m = 10, s = 1 }, { n = 2, m = 10, s = 2 }), false)
    T.eq(BL.Ahead({ n = 9, m = 8, s = 1 }, { n = 2, m = 10, s = 2 }), false)
  end)

  T.it("warns once every five minutes per name", function()
    local seen = {}
    T.eq(BL.ShouldAlert(seen, "krag eisenzahn", NOW), true)
    T.eq(BL.ShouldAlert(seen, "krag eisenzahn", NOW + 299), false)
    T.eq(BL.ShouldAlert(seen, "bodo langfinger", NOW + 299), true)
    T.eq(BL.ShouldAlert(seen, "krag eisenzahn", NOW + 300), true)
  end)
  T.it("breaks a tie of count and newest time by the checksum", function()
    local a, b = {}, {}
    BL.Add(a, "Ylva Grimm", "kos", nil, "Pell Quellgrund", NOW + 50, ctx)
    BL.Add(b, "Ylva Grimm", "kos", nil, "Pell Quellgrund", NOW + 50, ctx)
    BL.Remove(a, "Ylva Grimm", "Alva Abendrot", NOW + 90, ctx)
    BL.Add(a, "Wim Rauch", "kos", nil, "Pell Quellgrund", NOW + 100, ctx)
    BL.Add(b, "Wim Rauch", "kos", nil, "Pell Quellgrund", NOW + 100, ctx)
    local da, db = BL.Digest(a), BL.Digest(b)
    T.eq(da.n, db.n)
    T.eq(da.m, db.m)
    T.eq(BL.Differs(da, db), true)
    -- exactly one side offers
    T.truthy(BL.Ahead(da, db) ~= BL.Ahead(db, da), "one side is ahead")
  end)

  T.it("cuts a long reason on a whole letter", function()
    local book = {}
    BL.Add(book, "Krag Eisenzahn", "kos", string.rep("ж", 70), "Pell Quellgrund", NOW, ctx)
    local r = book["krag eisenzahn"].r
    T.eq(select(2, r:gsub("[\128-\191]", "")), 60) -- 60 letters, each with one continuation byte
    T.eq(#r, 120)
    BL.Add(book, "Bodo Langfinger", "kos", "a" .. string.rep("ö", 70), "Pell Quellgrund", NOW, ctx)
    T.eq(#book["bodo langfinger"].r, 1 + 59 * 2)
  end)

  T.it("lets an officer's removal beat an own edit made before it was known", function()
    local book = {}
    BL.Add(book, "Krag Eisenzahn", "kos", "alt", "Pell Quellgrund", NOW, ctx)
    -- this member edits it before the officer's removal (at NOW + 100) arrived
    BL.Add(book, "Krag Eisenzahn", "kos", "neu", "Tara Kiesel", NOW + 105, ctx)
    T.eq(BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", r = "alt", a = "Pell Quellgrund", at = NOW, x = NOW + 100,
      xb = "Alva Abendrot" }, NOW + 200, ctx), true)
    local entry = book["krag eisenzahn"]
    T.eq(BL.IsLive(entry), false)
    T.eq(entry.r, "alt")
    T.eq(entry.at, NOW)
  end)

  T.it("escapes the game's markup in received text", function()
    local book = {}
    BL.Merge(book, { n = "Krag Eisenzahn", t = "kos", r = "|TInterface\\Icons\\x:64|t |Hitem:1|h[x]|h",
      a = "Pell|cffff0000Quellgrund", at = NOW }, NOW, ctx)
    local entry = book["krag eisenzahn"]
    T.eq(entry.r, "||TInterface\\Icons\\x:64||t ||Hitem:1||h[x]||h")
    T.eq(entry.a, "Pell||cffff0000Quellgrund")
  end)
  T.it("lets the adder remove their own entry", function()
    local book = {}
    BL.Add(book, "Hakuna Markarta", "kos", nil, "Pell Quellgrund", NOW, ctx)
    local _, err = BL.Remove(book, "Hakuna Markarta", "Tara Kiesel", NOW + 5, ctx)
    T.eq(err, "officer")
    local entry = BL.Remove(book, "Hakuna Markarta", "Pell Quellgrund", NOW + 5, ctx)
    T.eq(BL.IsLive(entry), false)
    T.eq(BL.CanRemove(book["hakuna markarta"], "Pell Quellgrund", ctx), false) -- removed already
    BL.Add(book, "Fat Tekk", "kos", nil, "Pell Quellgrund", NOW, ctx)
    T.eq(BL.CanRemove(book["fat tekk"], "Pell Quellgrund", ctx), true)
    T.eq(BL.CanRemove(book["fat tekk"], "Tara Kiesel", ctx), false)
    T.eq(BL.CanRemove(book["fat tekk"], "Alva Abendrot", ctx), true)
  end)

  T.it("no longer lets the first adder remove it once someone else changed it", function()
    local book = {}
    BL.Add(book, "Fat Tekk", "kos", nil, "Pell Quellgrund", NOW, ctx)
    BL.Add(book, "Fat Tekk", "scam", "Gold genommen", "Tara Kiesel", NOW + 5, ctx)
    local _, err = BL.Remove(book, "Fat Tekk", "Pell Quellgrund", NOW + 10, ctx)
    T.eq(err, "officer")
  end)

  T.it("takes a relayed removal by the adder and drops one by someone else", function()
    local book = {}
    BL.Add(book, "Holz Elliot", "kos", nil, "Pell Quellgrund", NOW, ctx)
    T.eq(BL.Merge(book, { n = "Holz Elliot", t = "kos", a = "Pell Quellgrund", at = NOW, x = NOW + 5,
      xb = "Tara Kiesel" }, NOW + 10, ctx), false)
    T.eq(BL.IsLive(book["holz elliot"]), true)
    T.eq(BL.Merge(book, { n = "Holz Elliot", t = "kos", a = "Pell Quellgrund", at = NOW, x = NOW + 5,
      xb = "Pell Quellgrund" }, NOW + 10, ctx), true)
    T.eq(BL.IsLive(book["holz elliot"]), false)
    -- an empty book takes the add and its removal by the adder together
    local other = {}
    BL.Merge(other, { n = "Holz Elliot", t = "kos", a = "Pell Quellgrund", at = NOW, x = NOW + 5,
      xb = "Pell Quellgrund" }, NOW + 10, ctx)
    T.eq(BL.IsLive(other["holz elliot"]), false)
  end)

  T.it("lets the adder add their own removed name again, but not one an officer removed", function()
    local book = {}
    BL.Add(book, "Holz Elliot", "kos", nil, "Pell Quellgrund", NOW, ctx)
    BL.Remove(book, "Holz Elliot", "Pell Quellgrund", NOW + 5, ctx)
    T.truthy(BL.Add(book, "Holz Elliot", "kos", nil, "Pell Quellgrund", NOW + 10, ctx), "own name again")
    local _, err = BL.Add(book, "Holz Elliot", "kos", nil, "Tara Kiesel", NOW + 12, ctx)
    T.eq(err, nil) -- live again: anyone may change it
    BL.Remove(book, "Holz Elliot", "Alva Abendrot", NOW + 20, ctx)
    local _, again = BL.Add(book, "Holz Elliot", "kos", nil, "Tara Kiesel", NOW + 30, ctx)
    T.eq(again, "removed")
  end)
end)
