"""Mock-ups of the box "Inhalt" on the Bank tab: what lies in the guild bank's tabs, as a list or as the game's
grid (14 columns of 7 slots, slot 1 top left, the slots running down the columns, the columns in pairs).
Drawn into a real screenshot of the Bank tab (src/live/bank-ledger.png, 1580 x 780): its title bar, toolbar and
buttons are the game's own pixels; the boxes are drawn with the colours of its boxes, the content with the
game's font.

    python media/gallery/mock_bank_contents.py     ->  mock/contents-a.png … -c.png

A: the grid of one tab beside the tab list, which picks the tab.
B: the list, every item once; the picked row shows where it lies, in small grids beside it.
C: every tab as a grid at once; the search lights up what it finds in all of them.
Every one has the switch list/grid in its title row. Item and tab names and numbers are made up.
"""
import os
import random

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "mock")
FONT = os.path.join(HERE, "fonts", "FRIZQT__.TTF")
ICONS = os.path.join(HERE, "icons")
SHOT = os.path.join(HERE, "src", "live", "bank-ledger.png")

X0, Y0, X1, Y1, GAP = 18, 88, 1572, 770, 16      # the body of the tab in the screenshot
WINDOW = (50, 45, 41)
BG = (21, 18, 13)
TRACK, ZEBRA = (36, 31, 23), (29, 25, 19)
GOLD, WHITE, GREY = (255, 209, 0), (255, 255, 255), (150, 142, 128)
GREEN, RED, ORANGE = (64, 224, 64), (255, 90, 74), (214, 122, 50)
UNCOMMON = (30, 255, 0)
SELECTED = (66, 54, 30)
BAR_GOLD = (204, 168, 84)

F_XS = ImageFont.truetype(FONT, 11.6)
F_S = ImageFont.truetype(FONT, 13.2)
F_N = ImageFont.truetype(FONT, 15.6)
F_H = ImageFont.truetype(FONT, 26)

SLOTS = 98
BANK_TABS = [("Verbrauch", "trade_alchemy", 71), ("Handwerk", "trade_blacksmithing", 44),
             ("Kräuter & Erze", "trade_herbalism", 88), ("FFA", "trade_tailoring", 23)]
# (name, icon, stack size, quality colour)
ITEMS = [("Erheblicher Heiltrank", "inv_potion_54", 5, WHITE), ("Überragender Heiltrank", "inv_potion_51", 5, WHITE),
         ("Elixier des Mungos", "inv_potion_32", 5, WHITE), ("Gerösteter Raptor", "inv_misc_food_15", 20, WHITE),
         ("Runenstoffverband", "spell_holy_sealofsacrifice", 20, WHITE),
         ("Robustes Rüstungsset", "inv_misc_armorkit_17", 10, WHITE), ("Thoriumbarren", "trade_blacksmithing", 20, WHITE),
         ("Thoriumgranate", "trade_engineering", 10, UNCOMMON), ("Arkanitkristall", "trade_alchemy", 10, UNCOMMON),
         ("Illusionsstaub", "trade_engraving", 10, WHITE), ("Traumblatt", "trade_herbalism", 20, WHITE),
         ("Thoriumerz", "trade_mining", 20, WHITE), ("Runenstoff", "trade_tailoring", 20, WHITE),
         ("Dicker Wolfspelz", "inv_misc_pelt_wolf_01", 10, WHITE)]
POOLS = [(0, 1, 2, 3, 4), (5, 6, 7, 8, 9), (10, 11, 9, 8), (12, 13, 4, 3)]


def fill_tabs():
    """For every tab: { slot: (item, count) }, as many slots as BANK_TABS says, in runs like real banks."""
    rnd = random.Random(7)
    tabs = []
    for index, (_, _, used) in enumerate(BANK_TABS):
        slots, pool = {}, POOLS[index]
        order = sorted(range(1, SLOTS + 1), key=lambda s: s + rnd.random() * 40)
        item = pool[0]
        for slot in order[:used]:
            if rnd.random() < 0.3:
                item = rnd.choice(pool)
            stack = ITEMS[item][2]
            slots[slot] = (item, stack if rnd.random() < 0.7 else rnd.randint(1, stack))
        tabs.append(slots)
    return tabs


TABS = fill_tabs()
TODAY = (BANK_TABS, POOLS)
FULL = ([("Verbrauch", "trade_alchemy", 94), ("Handwerk", "trade_blacksmithing", 88),
         ("Kräuter & Erze", "trade_herbalism", 98), ("Stoffe & Leder", "trade_tailoring", 91),
         ("Raid", "inv_potion_51", 80), ("Verzauberung", "trade_engraving", 97),
         ("Ingenieur", "trade_engineering", 66), ("FFA", "inv_misc_pelt_wolf_01", 23)],
        [(0, 1, 2, 3, 4), (5, 6, 7, 8), (10, 11, 9), (12, 13, 4), (1, 2, 3, 0, 8), (9, 8, 12), (7, 6, 11, 12), (13, 3, 12, 0)])


def setup(which):
    global BANK_TABS, POOLS, TABS
    BANK_TABS, POOLS = which
    TABS = fill_tabs()


def room():
    return len(BANK_TABS) * SLOTS


def contents(only=None):
    """Every item once: { item, n, stacks, tabs }, most first."""
    by = {}
    for index, slots in enumerate(TABS):
        if only is not None and index != only:
            continue
        for item, count in slots.values():
            e = by.setdefault(item, {"item": item, "n": 0, "stacks": 0, "tabs": []})
            e["n"] += count
            e["stacks"] += 1
            if index not in e["tabs"]:
                e["tabs"].append(index)
    return sorted(by.values(), key=lambda e: -e["n"])


# --- drawing --------------------------------------------------------------------------------------------

def text_at(d, xy, s, font=F_S, fill=WHITE, anchor="ls"):
    d.text((xy[0] + 1, xy[1] + 1), s, font=font, fill=(0, 0, 0), anchor=anchor)
    d.text(xy, s, font=font, fill=fill, anchor=anchor)


def parts(d, x, y, pieces, font=F_S, right=False):
    if right:
        x -= sum(font.getlength(s) for s, _ in pieces)
    for s, color in pieces:
        text_at(d, (round(x), y), s, font, color)
        x += font.getlength(s)
    return x


def blend(color, alpha, bg=BG):
    return tuple(round(c * alpha + b * (1 - alpha)) for c, b in zip(color, bg))


class Kit:
    def __init__(self):
        self.shot = Image.open(SHOT).convert("RGB")
        # the toolbar's buttons: dark = picked, red = not; caps and a column without text to stretch
        self.btn = {True: self.shot.crop((174, 51, 266, 77)), False: self.shot.crop((275, 51, 366, 77))}

    def base(self):
        img = self.shot.copy()
        ImageDraw.Draw(img).rectangle((X0 - 10, Y0 - 6, X1 + 4, Y1 + 4), fill=WINDOW)
        return img

    def box(self, img, x0, y0, x1, y1):
        """A box like the tab's: a dark rim, the gold line (lighter on top), a dark inner edge."""
        d = ImageDraw.Draw(img)
        d.rectangle((x0 - 1, y0 - 1, x1 + 1, y1 + 1), outline=(27, 24, 21))
        d.rectangle((x0, y0, x1, y1), outline=(60, 48, 25))
        d.rectangle((x0 + 1, y0 + 1, x1 - 1, y1 - 1), outline=(59, 48, 25))
        d.line((x0, y0, x1, y0), fill=(100, 80, 39))
        d.line((x0 + 1, y0 + 1, x1 - 1, y0 + 1), fill=(45, 38, 24))
        d.rectangle((x0 + 2, y0 + 2, x1 - 2, y1 - 2), fill=BG, outline=(11, 10, 7))
        d.line((x0 + 3, y0 + 3, x1 - 3, y0 + 3), fill=(17, 15, 11))
        return (x0, y0, x1, y1)

    def button(self, img, x, y, text, picked, w=None):
        s, cap = self.btn[picked], 9
        w = w or round(F_S.getlength(text)) + 30
        out = Image.new("RGB", (w, s.height))
        mid = s.crop((cap, 0, cap + 4, s.height))
        for px in range(cap, w - cap, mid.width):
            out.paste(mid, (px, 0))
        out.paste(s.crop((0, 0, cap, s.height)), (0, 0))
        out.paste(s.crop((s.width - cap, 0, s.width, s.height)), (w - cap, 0))
        img.paste(out, (x, y))
        text_at(ImageDraw.Draw(img), (x + w // 2, y + 18), text, F_S, WHITE if picked else GOLD, "ms")
        return x + w + 4


def title(d, box, text, hint=None, right=None):
    x = box[0] + 12
    text_at(d, (x, box[1] + 23), text, F_N, GOLD)
    if hint:
        text_at(d, (x + round(F_N.getlength(text)) + 14, box[1] + 23), hint, F_S, GREY)
    if right:
        text_at(d, (box[2] - 12, box[1] + 23), right, F_S, GREY, "rs")


def bar(d, x0, y, x1, share, color, h=7):
    d.rectangle((x0, y, x1 - 1, y + h - 1), fill=TRACK)
    w = round((x1 - x0) * share)
    if w > 0:
        d.rectangle((x0, y, x0 + w - 1, y + h - 1), fill=color)


ICON_CACHE = {}


def icon(img, name, x, y, size=18):
    key = (name, size)
    if key not in ICON_CACHE:
        src = Image.open(os.path.join(ICONS, name + ".jpg")).convert("RGB").crop((4, 4, 52, 52))
        ICON_CACHE[key] = src.resize((size, size), Image.LANCZOS)
    img.paste(ICON_CACHE[key], (x, y))


def coin(img, x, y, size=12):
    d = ImageDraw.Draw(img)
    d.ellipse((x, y, x + size - 1, y + size - 1), fill=(122, 78, 8))
    d.ellipse((x + 1, y + 1, x + size - 2, y + size - 2), fill=(238, 186, 40))
    d.ellipse((x + size * 0.25, y + size * 0.2, x + size * 0.55, y + size * 0.45), fill=(255, 236, 150))


def switch(kit, img, box, grid_on):
    """[Liste][Raster] at the right end of a box's title row; returns its left x."""
    x = box[2] - 10 - 66 - 4 - 66
    kit.button(img, x, box[1] + 6, "Liste", not grid_on, 66)
    kit.button(img, x + 70, box[1] + 6, "Raster", grid_on, 66)
    return x


def search(img, x1, y, w, text=None):
    """The game's input box ending at x1; its hint while it is empty. Returns its left x."""
    d = ImageDraw.Draw(img)
    x0 = x1 - w
    d.rectangle((x0, y, x1, y + 23), fill=(6, 5, 4), outline=(88, 80, 66))
    d.line((x0 + 1, y + 1, x1 - 1, y + 1), fill=(34, 31, 26))
    if text:
        text_at(d, (x0 + 8, y + 17), text, F_S, WHITE)
        cx = round(x0 + 9 + F_S.getlength(text))
        d.line((cx, y + 5, cx, y + 18), fill=WHITE)
    else:
        text_at(d, (x0 + 8, y + 17), "Gegenstand suchen ...", F_S, GREY)
    return x0


def grid_size(s):
    inner, pair, row = 3, max(8, s // 5), 3
    pw = 2 * s + inner
    return 7 * pw + 6 * pair, 7 * s + 6 * row


def grid(img, x, y, s, slots, match=None, picked=None, hover=None):
    """The 14 x 7 grid of one tab at x, y, slots s px, the columns in pairs like the game. match: items to light
    up (the rest dims); picked: the item whose slots get a gold edge. Returns {slot: (x, y)}."""
    d = ImageDraw.Draw(img)
    inner, pair, row = 3, max(8, s // 5), 3
    pw = 2 * s + inner
    w, h = grid_size(s)
    for p in range(7):
        px = x + p * (pw + pair)
        d.rectangle((px - 4, y - 4, px + pw + 3, y + h + 3), fill=(34, 29, 20), outline=(92, 74, 38))
        d.line((px - 3, y - 3, px + pw + 2, y - 3), fill=(120, 96, 48))
    where = {}
    for slot in range(1, SLOTS + 1):
        col, r = (slot - 1) // 7, (slot - 1) % 7
        sx = x + (col // 2) * (pw + pair) + (col % 2) * (s + inner)
        sy = y + r * (s + row)
        where[slot] = (sx, sy)
        have = slots.get(slot)
        dim = match is not None and (not have or have[0] not in match)
        d.rectangle((sx, sy, sx + s - 1, sy + s - 1), fill=(10, 9, 8), outline=(58, 50, 36) if not dim else (40, 35, 27))
        d.line((sx + 1, sy + 1, sx + s - 2, sy + 1), fill=(26, 23, 19))
        if not have:
            continue
        item, count = have
        icon(img, ITEMS[item][1], sx + 2, sy + 2, s - 4)
        if dim:
            box = (sx + 2, sy + 2, sx + s - 2, sy + s - 2)
            img.paste(Image.blend(img.crop(box), Image.new("RGB", (s - 4, s - 4), (10, 9, 7)), 0.75), box[:2])
        d = ImageDraw.Draw(img)
        if count > 1:
            text_at(d, (sx + s - 4, sy + s - 4), str(count), F_XS if s < 44 else F_S, GREY if dim else WHITE, "rs")
        if (match is not None and not dim) or (picked is not None and item == picked):
            d.rectangle((sx - 1, sy - 1, sx + s, sy + s), outline=GOLD)
        if hover == slot:
            d.rectangle((sx - 1, sy - 1, sx + s, sy + s), outline=(130, 180, 255))
            d.rectangle((sx, sy, sx + s - 1, sy + s - 1), outline=(70, 110, 190))
    return where


def tooltip(img, x, y, lines):
    """The game's tooltip: near black, a thin grey edge. lines: lists of (text, colour, font), None for a gap."""
    w = round(max(sum(f.getlength(t) for t, _, f in line) for line in lines if line)) + 24
    h = 14 + sum(22 if line and line[0][2] is F_N else 18 if line else 8 for line in lines)
    box = (x, y, x + w, y + h)
    img.paste(Image.blend(img.crop(box), Image.new("RGB", (w, h), (4, 4, 10)), 0.93), box[:2])
    d = ImageDraw.Draw(img)
    d.rectangle(box, outline=(120, 120, 128))
    d.rectangle((box[0] + 1, box[1] + 1, box[2] - 1, box[3] - 1), outline=(36, 36, 44))
    cy = y + 9
    for line in lines:
        if not line:
            cy += 8
            continue
        step = 22 if line[0][2] is F_N else 18
        cx = x + 12
        for t, color, f in line:
            text_at(d, (round(cx), cy + step - 6), t, f, color)
            cx += f.getlength(t)
        cy += step


def total_box(kit, img, box):
    d = ImageDraw.Draw(img)
    title(d, box, "Gildenbank")
    text_at(d, (box[0] + 14, box[1] + 60), "5", F_H, GOLD)
    coin(img, box[0] + 32, box[1] + 41, 20)
    text_at(d, (box[0] + 62, box[1] + 60), "64", F_H, GOLD)
    d = ImageDraw.Draw(img)
    text_at(d, (box[0] + 14, box[1] + 90), "in den letzten 7 Tagen", F_S, GREY)
    rows = (("Eingezahlt", "+104", GREEN), ("Abgehoben", "-110", RED), ("Reparaturen", "-0", RED))
    for i, (label, value, color) in enumerate(rows):
        y = box[1] + 116 + i * 19
        text_at(d, (box[0] + 14, y), label, F_S, WHITE)
        text_at(d, (box[2] - 30, y), value, F_S, color, "rs")
        coin(img, box[2] - 26, y - 10, 11)
    y = box[1] + 116 + 3 * 19
    text_at(d, (box[0] + 14, y), "Gegenstände", F_S, WHITE)
    parts(d, box[2] - 14, y, [("+100", GREEN), ("  /  ", GREY), ("-1", RED)], right=True)


def tabs_box(kit, img, box, picked, pitch=44):
    """The tabs box as the picker of variant A: the picked tab lit like a picked row."""
    d = ImageDraw.Draw(img)
    title(d, box, "Fächer", "Klick zeigt den Inhalt")
    for i, (name, ico, used) in enumerate(BANK_TABS):
        y = box[1] + 38 + i * pitch
        if i == picked:
            d.rectangle((box[0] + 6, y - 4, box[2] - 6, y + pitch - 8), fill=SELECTED)
            d.rectangle((box[0] + 6, y - 4, box[0] + 8, y + pitch - 8), fill=GOLD)
        icon(img, ico, box[0] + 16, y + 2, 26)
        text_at(d, (box[0] + 52, y + 13), name, F_S, WHITE)
        bar(d, box[0] + 52, y + 20, box[2] - 16, used / SLOTS, BAR_GOLD if used < 80 else ORANGE)
        parts(d, box[2] - 16, y + 13, [(str(used), GOLD), (" / 98", GREY)], right=True)
    y = box[1] + 38 + len(BANK_TABS) * pitch + 8
    if len(BANK_TABS) == 8:
        text_at(d, (box[0] + 52, y + 10), "Alle 8 Fächer gekauft", F_S, GREY)
        return
    text_at(d, (box[0] + 52, y + 10), "Fach %d kostet" % (len(BANK_TABS) + 1), F_S, GREY)
    text_at(d, (box[2] - 30, y + 10), "250", F_S, GREY, "rs")
    coin(img, box[2] - 26, y, 11)


def scrollbar(img, x, y0, y1):
    """The game's slim scroll bar: a dark track, a gold thumb."""
    d = ImageDraw.Draw(img)
    d.rectangle((x, y0, x + 5, y1), fill=(12, 10, 8))
    d.rectangle((x, y0 + 4, x + 5, y0 + (y1 - y0) // 3), fill=(150, 120, 60))


# --- A: the grid of one tab beside the tab list -------------------------------------------------------------

def variant_a(kit):
    img = kit.base()
    side = 395
    total_box(kit, img, kit.box(img, X0, Y0, side, 284))
    tabs_box(kit, img, kit.box(img, X0, 284 + GAP, side, Y1), 0, 44 if len(BANK_TABS) <= 4 else 42)

    box = kit.box(img, side + GAP, Y0, X1, Y1)
    d = ImageDraw.Draw(img)
    title(d, box, "Inhalt", "Verbrauch · %d von 98 Plätzen" % BANK_TABS[0][2])
    sx = switch(kit, img, box, True)
    search(img, sx - 12, box[1] + 7, 220)
    s = 62
    w, h = grid_size(s)
    gx = (box[0] + box[2]) // 2 - w // 2
    gy = box[1] + 48 + (box[3] - box[1] - 48 - 34 - h) // 2
    hover = 12
    where = grid(img, gx, gy, s, TABS[0], hover=hover)
    d = ImageDraw.Draw(img)
    text_at(d, ((box[0] + box[2]) // 2, box[3] - 14),
            "Stand: vor 1 Std. · Platz 1 oben links, die Plätze laufen die Spalten hinunter wie im Spiel", F_S, GREY,
            "ms")
    item, count = TABS[0][hover]
    hx, hy = where[hover]
    same = [c for i, c in TABS[0].values() if i == item]
    every = [c for t in TABS for i, c in t.values() if i == item]
    tooltip(img, hx + s + 8, hy + 8, [
        [(ITEMS[item][0], ITEMS[item][3], F_N)],
        [("Benutzen: Stellt 455 bis 585 Punkt(e) Gesundheit wieder her.", GREEN, F_S)],
        [("Benötigt Stufe 35", WHITE, F_S)],
        None,
        [("In diesem Fach: ", GREY, F_S), ("%d in %d Plätzen" % (sum(same), len(same)), WHITE, F_S)],
        [("In der ganzen Bank: ", GREY, F_S), (str(sum(every)), WHITE, F_S)],
    ])
    return img


# --- B: the list, with where it lies --------------------------------------------------------------------

def variant_b(kit):
    img = kit.base()
    split = 1060
    rows = contents()
    picked = rows[1]["item"] if len(BANK_TABS) <= 4 else max(rows, key=lambda r: (len(r["tabs"]), r["n"]))["item"]

    box = kit.box(img, X0, Y0, split, Y1)
    d = ImageDraw.Draw(img)
    title(d, box, "Inhalt")
    x = box[0] + 12 + round(F_N.getlength("Inhalt")) + 16
    if len(BANK_TABS) <= 4:
        for i, label in enumerate(["Alle"] + [t[0] for t in BANK_TABS]):
            x = kit.button(img, x, box[1] + 6, label, i == 0)
    else:  # eight tabs do not fit as buttons: a menu, like the ledger's
        kit.button(img, x, box[1] + 6, "Fach: Alle", False, 120)
        ImageDraw.Draw(img).polygon([(x + 100, box[1] + 16), (x + 108, box[1] + 16), (x + 104, box[1] + 21)], fill=GOLD)
    switch(kit, img, box, False)
    d = ImageDraw.Draw(img)
    used = sum(t[2] for t in BANK_TABS)
    text_at(d, (box[0] + 14, box[1] + 56), "%d Gegenstände · %d Stapel · %d von %d Plätzen belegt" % (
        len(rows), sum(r["stacks"] for r in rows), used, room()), F_S, GREY)
    search(img, box[2] - 12, box[1] + 39, 240)
    cn, cc, cs, ct, cm = box[0] + 14, box[0] + 430, box[0] + 510, box[0] + 550, box[2] - 30
    hy = box[1] + 86
    d = ImageDraw.Draw(img)
    for label, x, anchor, on in (("Gegenstand", cn, "ls", False), ("Anzahl", cc, "rs", True), ("Stapel", cs, "rs", False),
                                 ("Fächer", ct, "ls", False), ("Bewegung 7 Tage", cm, "rs", False)):
        text_at(d, (x, hy), label, F_S, GOLD if on else GREY, anchor)
    d.polygon([(cc + 4, hy - 8), (cc + 12, hy - 8), (cc + 8, hy - 3)], fill=GOLD)
    d.line((box[0] + 8, hy + 7, box[2] - 22, hy + 7), fill=TRACK)
    pitch, top = 32, hy + 12
    rnd = random.Random(3)
    shown = (box[3] - top - 6) // pitch
    scrollbar(img, box[2] - 14, top, box[3] - 8)
    d = ImageDraw.Draw(img)
    for i, r in enumerate(rows[:shown]):
        y = top + i * pitch
        base = y + pitch - 11
        if i % 2:
            d.rectangle((box[0] + 6, y, box[2] - 22, y + pitch - 2), fill=ZEBRA)
        if r["item"] == picked:
            d.rectangle((box[0] + 6, y, box[2] - 22, y + pitch - 2), fill=SELECTED)
        name, ico, _, color = ITEMS[r["item"]]
        icon(img, ico, cn, y + 4, 22)
        text_at(d, (cn + 32, base), name, F_S, color)
        text_at(d, (cc, base), str(r["n"]), F_S, GOLD, "rs")
        text_at(d, (cs, base), str(r["stacks"]), F_S, GREY, "rs")
        text_at(d, (ct, base), "  ·  ".join(BANK_TABS[t][0] for t in r["tabs"]), F_S, (205, 195, 175))
        delta = rnd.choice((0, 0, 20, -10, 40, -5, 15, -60))
        text_at(d, (cm, base), "%+d" % delta if delta else "–", F_S, GREEN if delta > 0 else RED if delta < 0 else GREY,
                "rs")

    side = kit.box(img, split + GAP, Y0, X1, Y1)
    d = ImageDraw.Draw(img)
    name, ico, _, color = ITEMS[picked]
    icon(img, ico, side[0] + 12, side[1] + 8, 22)
    text_at(d, (side[0] + 42, side[1] + 25), name, F_N, color)
    text_at(d, (side[2] - 12, side[1] + 25), "Wo es liegt", F_S, GREY, "rs")
    pr = next(r for r in rows if r["item"] == picked)
    text_at(d, (side[0] + 14, side[1] + 52), "%d Stück in %d Stapeln" % (pr["n"], pr["stacks"]), F_S, WHITE)
    y = side[1] + 74
    s = 25
    w, h = grid_size(s)
    if len(pr["tabs"]) > 2:  # more tabs than grids fit: a row per tab, the grid of the picked one below
        for n, t in enumerate(pr["tabs"]):
            here = [c for i, c in TABS[t].values() if i == picked]
            ry = y + n * 28
            if n == 0:
                d.rectangle((side[0] + 6, ry - 4, side[2] - 6, ry + 22), fill=SELECTED)
                d.rectangle((side[0] + 6, ry - 4, side[0] + 8, ry + 22), fill=GOLD)
            icon(img, BANK_TABS[t][1], side[0] + 16, ry, 18)
            text_at(d, (side[0] + 42, ry + 14), BANK_TABS[t][0], F_S, WHITE)
            text_at(d, (side[2] - 14, ry + 14), "%d in %d Plätzen" % (sum(here), len(here)), F_S, GREY, "rs")
        y += len(pr["tabs"]) * 28 + 16
        t = pr["tabs"][0]
        text_at(d, (side[0] + 14, y + 12), BANK_TABS[t][0], F_N, GOLD)
        grid(img, (side[0] + side[2]) // 2 - w // 2, y + 30, s, TABS[t], match={picked})
        d = ImageDraw.Draw(img)
        text_at(d, (side[0] + 14, side[3] - 14), "Klick auf ein Fach zeigt seine Plätze", F_S, GREY)
        return img
    for t in pr["tabs"]:
        here = [c for i, c in TABS[t].values() if i == picked]
        icon(img, BANK_TABS[t][1], side[0] + 14, y, 20)
        parts(d, side[0] + 42, y + 15, [(BANK_TABS[t][0], WHITE), ("   %d in %d Plätzen" % (sum(here), len(here)), GREY)])
        grid(img, (side[0] + side[2]) // 2 - w // 2, y + 34, s, TABS[t], match={picked})
        d = ImageDraw.Draw(img)
        y += 34 + h + 28
    text_at(d, (side[0] + 14, side[3] - 14), "Klick auf eine Zeile zeigt, wo sie liegt", F_S, GREY)
    return img


# --- C: every tab at once ---------------------------------------------------------------------------------

def variant_c(kit):
    img = kit.base()
    box = kit.box(img, X0, Y0, X1, Y1)
    d = ImageDraw.Draw(img)
    query = "heiltrank"
    match = {i for i, it in enumerate(ITEMS) if query in it[0].lower()}
    found = [r for r in contents() if r["item"] in match]
    title(d, box, "Inhalt", "alle Fächer · %d von %d Plätzen belegt" % (sum(t[2] for t in BANK_TABS), room()))
    sx = switch(kit, img, box, True)
    search(img, sx - 12, box[1] + 7, 240, query)
    cols = 2 if len(BANK_TABS) <= 4 else 4
    s = 32 if cols == 2 else 21
    w, h = grid_size(s)
    d = ImageDraw.Draw(img)
    for t, (name, ico, used) in enumerate(BANK_TABS):
        col, row = t % cols, t // cols
        cx = box[0] + 22 + col * (w + (40 if cols == 2 else 18))
        cy = box[1] + 46 + row * (h + 62)
        icon(img, ico, cx, cy, 22)
        text_at(d, (cx + 30, cy + 17), name, F_N, GOLD)
        here = sum(c for i, c in TABS[t].values() if i in match)
        parts(d, cx + w, cy + 17, ([("%d Treffer   " % here, GOLD)] if here else []) + [
            (str(used), WHITE), (" / 98", GREY)], right=True)
        grid(img, cx + 4, cy + 36, s, TABS[t], match=match)
        d = ImageDraw.Draw(img)
    if cols == 4:  # the hits go below the grids, side by side
        y = box[1] + 46 + 2 * (h + 62) + 4
        d.line((box[0] + 14, y - 14, box[2] - 14, y - 14), fill=TRACK)
        text_at(d, (box[0] + 22, y + 10), "Treffer", F_N, GOLD)
        text_at(d, (box[0] + 22, y + 30), "%d Stück" % sum(r["n"] for r in found), F_S, GREY)
        x = box[0] + 140
        for r in found:
            name, ico, _, color = ITEMS[r["item"]]
            icon(img, ico, x, y - 4, 26)
            text_at(d, (x + 36, y + 10), name, F_S, color)
            text_at(d, (x + 330, y + 10), str(r["n"]), F_S, GOLD, "rs")
            for n, t in enumerate(r["tabs"]):
                here = [c for i, c in TABS[t].values() if i == r["item"]]
                parts(d, x + 36, y + 30 + n * 18, [(BANK_TABS[t][0], (205, 195, 175)),
                                                   ("   %d in %d Plätzen" % (sum(here), len(here)), GREY)])
            x += 380
        text_at(d, (box[0] + 22, box[3] - 14), "21 px je Platz: die Symbole sind noch zu erkennen, die Zahlen kaum",
                F_S, GREY)
        return img
    # beside the grids: what the search found
    lx = box[0] + 22 + 2 * (w + 40) + 4
    d.line((lx - 18, box[1] + 44, lx - 18, box[3] - 14), fill=TRACK)
    text_at(d, (lx, box[1] + 62), "Treffer", F_N, GOLD)
    text_at(d, (box[2] - 14, box[1] + 62), "%d Stück" % sum(r["n"] for r in found), F_S, GREY, "rs")
    y = box[1] + 76
    for r in found:
        name, ico, _, color = ITEMS[r["item"]]
        icon(img, ico, lx, y, 26)
        text_at(d, (lx + 36, y + 13), name, F_S, color)
        text_at(d, (box[2] - 14, y + 13), str(r["n"]), F_S, GOLD, "rs")
        for t in r["tabs"]:
            here = [c for i, c in TABS[t].values() if i == r["item"]]
            y += 18
            parts(d, lx + 36, y + 13, [(BANK_TABS[t][0], (205, 195, 175)), ("   %d in %d Plätzen" % (sum(here), len(here)),
                                                                           GREY)])
        y += 38
    text_at(d, (lx, box[3] - 14), "Klick auf einen Treffer lässt nur ihn leuchten", F_S, GREY)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    kit = Kit()
    for suffix, which in (("", TODAY), ("-full", FULL)):
        setup(which)
        for key, build in (("a", variant_a), ("b", variant_b), ("c", variant_c)):
            img = build(kit)
            path = os.path.join(OUT, "contents-%s%s.png" % (key, suffix))
            img.save(path)
            print(path, img.size)


if __name__ == "__main__":
    main()
