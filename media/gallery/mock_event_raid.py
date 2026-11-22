"""Three ways to show the picked event on the right of the Events tab, for a raid with 25 sign-ups. Drawn into
the in-game screenshot of the tab as built (src/24-events.png, local only) with the widgets of
mock_blacklist.py; everything inside the two boxes is redrawn, so no real name of the screenshot stays.

    python media/gallery/mock_event_raid.py  ->  mock/raid-a.png  role columns: Tanks | Heiler | DPS side by side
                                                 mock/raid-b.png  numbers first: a strip of counts, then one grid
                                                 mock/raid-c.png  profile and roster: event card left, a table right

Names are made up like Core/Anon.lua. Needs Pillow.
"""
import os
from collections import Counter

from PIL import Image, ImageDraw, ImageFont

import mock_blacklist as mb
from mock_blacklist import CLASS, DIM, F_B, F_L, F_N, F_S, F_XS, GOLD, GREY, LINE, WHITE, fit, red_button, text_at
from mock_events import MAYBE, NO, OK, TYPES, counts, dot, tick, cross, type_mark

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src", "24-events.png")
OUT = mb.OUT
F_H = ImageFont.truetype(mb.FONT, 26)   # the event's title (Morpheus in game; the mock has only Friz)
F_BIG = ImageFont.truetype(mb.FONT, 30)
PARCH = (242, 227, 181)

# the boxes in the screenshot (outer edge lines excluded)
L0, L1 = 24, 545          # agenda box
R0, R1 = 570, 1666        # detail box
TOP, BOT = 93, 765
FILL = (21, 18, 13)
SEL = (58, 46, 22)

ROLE = {"tank": ("Tanks", (90, 150, 240)), "heal": ("Heiler", (90, 215, 100)), "dps": ("DPS", (230, 84, 64)),
        "none": ("Rolle unbekannt", (150, 142, 124))}
CLASS_DE = {"warrior": "Krieger", "priest": "Priester", "shaman": "Schamane", "hunter": "Jäger", "rogue": "Schurke",
            "paladin": "Paladin", "druid": "Druide", "warlock": "Hexenmeister", "mage": "Magier"}

# name, class, role, answer
ROSTER = [
    ("Krag Eisenfaust", "warrior", "tank", "yes"), ("Bodo Felsbart", "warrior", "tank", "yes"),
    ("Tara Taubnessel", "druid", "tank", "yes"),
    ("Alva Abendrot", "priest", "heal", "yes"), ("Ylva Immergrün", "priest", "heal", "yes"),
    ("Mira Lichtquell", "priest", "heal", "yes"), ("Cord Nebelstein", "paladin", "heal", "yes"),
    ("Wenna Goldhain", "paladin", "heal", "yes"), ("Lio Moosbart", "druid", "heal", "yes"),
    ("Silas Birkfeld", "mage", "dps", "yes"), ("Finn Moorweide", "mage", "dps", "yes"),
    ("Esra Frostweber", "mage", "dps", "yes"), ("Kira Silberblatt", "mage", "dps", "yes"),
    ("Nika Quellgrund", "warlock", "dps", "yes"), ("Jorin Zunderfels", "warlock", "dps", "yes"),
    ("Veit Aschenbrand", "warlock", "dps", "yes"), ("Greta Donnerkeil", "hunter", "dps", "yes"),
    ("Imke Fuchsbau", "hunter", "dps", "yes"), ("Talia Sternsang", "hunter", "dps", "yes"),
    ("Pell Quellgrund", "rogue", "dps", "yes"), ("Orla Nordkamm", "rogue", "dps", "yes"),
    ("Rune Schattenfell", "rogue", "dps", "yes"), ("Hagen Eichstamm", "warrior", "dps", "yes"),
    ("Brann Kupferhelm", "warrior", "dps", "yes"), ("Eldo Rabenwacht", "rogue", "none", "yes"),
    ("Dana Glutpfad", "paladin", "heal", "maybe"), ("Ole Steinbach", "hunter", "dps", "maybe"),
    ("Pia Nebelau", "priest", "heal", "maybe"),
    ("Calla Taubnessel", "druid", "heal", "no"), ("Gero Hammerfall", "warrior", "tank", "no"),
]
YES = [r for r in ROSTER if r[3] == "yes"]
MAYBES = [r for r in ROSTER if r[3] == "maybe"]
NOS = [r for r in ROSTER if r[3] == "no"]
TITLE = "Geschmolzener Kern"
META = "Fr 27.11.  ·  20:00  ·  heute in 3 Std.  ·  von "
BY = ("Alva Abendrot", "priest")
DESC = "Treffpunkt am Eingang im Schwarzfels. Feuerresistenz mitbringen, Tränke liegen im Bank-Tab 2."


# --- marks ------------------------------------------------------------------------------------------------------
def role_mark(d, x, y, role, s=1.0):
    """Small drawn role signs in the role's color: shield, cross, blade; a ring for unknown. (x, y) = left, baseline."""
    color = ROLE[role][1]
    cy = y - 6 * s
    if role == "tank":
        pts = [(x, cy - 6 * s), (x + 10 * s, cy - 6 * s), (x + 10 * s, cy), (x + 5 * s, cy + 6 * s), (x, cy)]
        d.polygon([(px + 1, py + 1) for px, py in pts], fill=(0, 0, 0))
        d.polygon(pts, fill=color)
    elif role == "heal":
        for dx, fill in ((1, (0, 0, 0)), (0, color)):
            d.rectangle((x + 3.5 * s + dx, cy - 6 * s + dx, x + 6.5 * s + dx, cy + 6 * s + dx), fill=fill)
            d.rectangle((x - 1 * s + dx, cy - 1.5 * s + dx, x + 11 * s + dx, cy + 1.5 * s + dx), fill=fill)
    elif role == "dps":
        for dx, fill in ((1, (0, 0, 0)), (0, color)):
            d.line((x + dx, cy + 6 * s + dx, x + 10 * s + dx, cy - 6 * s + dx), fill=fill, width=max(2, round(2 * s)))
            d.line((x + 1 * s + dx, cy - 1 * s + dx, x + 6 * s + dx, cy + 4 * s + dx), fill=fill, width=2)
    else:
        d.ellipse((x + 1, cy - 5 * s, x + 10 * s, cy + 5 * s), outline=color, width=2)
    return x + 12 * s


def name(img, x, y, entry, dim=False, font=F_S):
    d = ImageDraw.Draw(img)
    nm, cls = entry[0], entry[1]
    img.paste(mb.ICON[cls], (round(x), round(y) - 14))
    text_at(d, (x + 21, y), nm, font, DIM if dim else CLASS[cls][0])
    return x + 21 + font.getlength(nm)


def small_button(img, x, y, w, label, color=GOLD):
    x, y = round(x), round(y)
    red_button(img, x, y, w, label, color)
    return x + w


def text_link(d, x, y, label, color, anchor="ls"):
    text_at(d, (x, y), label, F_S, color, anchor)
    w = F_S.getlength(label)
    x0 = x - w if anchor.startswith("r") else x
    d.line((x0, y + 3, x0 + w, y + 3), fill=tuple(int(c * 0.6) for c in color))


def wrap(d, x, y, text, width, font=F_S, fill=WHITE, gap=19, limit=9):
    line, lines = "", 0
    for word in text.split():
        if font.getlength(line + " " + word) > width and line:
            text_at(d, (x, y), line.strip(), font, fill)
            line, y, lines = "", y + gap, lines + 1
        line += " " + word
    text_at(d, (x, y), line.strip(), font, fill)
    return y + gap


# --- the frame: screenshot, toolbar count, agenda on the left --------------------------------------------------
AGENDA = [
    ("Diese Woche", [("27", "Fr", "20:00", TITLE, "raid", 25, 3, 2, "yes", True),
                     ("28", "Sa", "15:00", "Brunnen des Grauens", "dungeon", 4, 1, 0, "open", False)]),
    ("Nächste Woche", [("03", "Do", "20:00", "Onyxias Hort", "raid", 11, 2, 1, "open", False)]),
]


def frame():
    img = Image.open(SRC).convert("RGB")
    d = ImageDraw.Draw(img)
    d.rectangle((L0, TOP, L1, BOT), fill=FILL)
    d.rectangle((R0, TOP, R1, BOT), fill=FILL)
    # toolbar: "Kommende 1" -> 3 (the textured strip copied from an empty stretch of the same bar)
    img.paste(img.crop((700, 50, 840, 78)), (95, 50))
    text_at(d, (102, 70), "Kommende 3", F_N, GOLD)
    y = 132
    for head, rows in AGENDA:
        text_at(d, (34, y), head, F_S, GOLD)
        d.line((34 + F_S.getlength(head) + 12, y - 5, L1 - 8, y - 5), fill=LINE)
        y += 12
        for day, wd, time, title, t, yes, maybe, no, mine, picked in rows:
            if picked:
                d.rectangle((L0 + 1, y, L1 - 2, y + 48), fill=SEL)
            text_at(d, (52, y + 25), day, F_L, GOLD, "ms")
            text_at(d, (52, y + 42), wd, F_XS, GREY, "ms")
            text_at(d, (88, y + 22), title, F_N, WHITE)
            type_mark(d, 88, y + 43, t, 4)
            text_at(d, (100, y + 41), time + " · ", F_XS, GREY)
            text_at(d, (100 + F_XS.getlength(time + " · "), y + 41), TYPES[t][0], F_XS, TYPES[t][1])
            label, color = ("Angemeldet", OK) if mine == "yes" else ("offen", GOLD)
            text_at(d, (L1 - 12, y + 20), label, F_XS, color, "rs")
            counts(d, L1 - 104, y + 41, yes, maybe, no, F_XS)
            y += 54
        y += 14
    return img, d


def header(img, d, x, y, right, compact=False):
    """Title with type badge, the meta line and the description; returns the y below."""
    text_at(d, (x, y + 26), TITLE, F_H, PARCH)
    bx = x + F_H.getlength(TITLE) + 16
    label, color = TYPES["raid"]
    type_mark(d, bx, y + 22, "raid", 4)
    text_at(d, (bx + 14, y + 21), label + "  ·  Stufe 60  ·  40 Plätze", F_S, color)
    d.line((x, y + 38, x + 360, y + 38), fill=(92, 74, 40))
    text_at(d, (x, y + 64), META, F_N, WHITE)
    text_at(d, (x + F_N.getlength(META), y + 64), BY[0], F_N, CLASS[BY[1]][0])
    if compact:
        return y + 76
    return wrap(d, x, y + 90, DESC, right - x, F_S, (216, 208, 188)) + 2


def answer_block(img, d, x, y, label_first=True):
    """'Deine Antwort: Angemeldet' and the two other answers as buttons; returns the x after."""
    text_at(d, (x, y + 17), "Deine Antwort:", F_N, GOLD)
    xx = x + F_N.getlength("Deine Antwort: ")
    text_at(d, (xx, y + 17), "Angemeldet", F_N, OK)
    xx += F_N.getlength("Angemeldet") + 18
    xx = small_button(img, xx, y, 110, "Vorläufig") + 8
    return small_button(img, xx, y, 110, "Absagen")


def footer(img, d, y, x0, x1):
    """Actions: calendar and edit as buttons, announce as a button while it is pending, delete as a quiet red
    link on the far right (never the same weight as the rest)."""
    d.line((x0, y - 12, x1, y - 12), fill=LINE)
    x = small_button(img, x0, y, 226, "Im Blizzard-Kalender öffnen") + 8
    x = small_button(img, x, y, 120, "Bearbeiten") + 8
    small_button(img, x, y, 226, "Im Gildenchat ankündigen")
    text_link(d, x1, y + 17, "Löschen", (220, 80, 60), "rs")


# --- A: role columns ---------------------------------------------------------------------------------------------
def variant_a():
    img, d = frame()
    x0, x1 = R0 + 22, R1 - 22
    y = header(img, d, x0, TOP + 12, x1)
    answer_block(img, d, x0, y + 2)
    # the count with a thin bar under it
    y += 52
    text_at(d, (x0, y + 4), "25", F_BIG, OK)
    text_at(d, (x0 + F_BIG.getlength("25") + 8, y + 4), "angemeldet", F_N, OK)
    xx = x0 + F_BIG.getlength("25") + 8 + F_N.getlength("angemeldet") + 22
    text_at(d, (xx, y + 4), "3 vorläufig", F_N, MAYBE)
    xx += F_N.getlength("3 vorläufig") + 22
    text_at(d, (xx, y + 4), "2 abgelehnt", F_N, NO)
    # class composition on the right of the count line
    cnt = Counter(r[1] for r in YES)
    cx = x1
    for cls in reversed(["warrior", "paladin", "druid", "priest", "rogue", "hunter", "mage", "warlock"]):
        s = str(cnt.get(cls, 0))
        cx -= F_S.getlength(s)
        text_at(d, (cx, y + 2), s, F_S, CLASS[cls][0])
        cx -= 21
        img.paste(mb.ICON[cls], (round(cx), round(y + 2) - 14))
        cx -= 12
    y += 26
    # three columns: tanks | healers | damage (damage twice as wide, two lists)
    cols = [("tank", 1), ("heal", 1), ("dps", 2)]
    unit = (x1 - x0 - 3 * 14) / 4
    cx = x0
    top = y
    for role, span in cols:
        w = unit * span + 14 * (span - 1)
        rows = [r for r in YES if r[2] == role]
        mb.gold_box(img, (cx, top, cx + w, top + 312))
        role_mark(d, cx + 12, top + 24, role, 1.2)
        text_at(d, (cx + 32, top + 24), ROLE[role][0], F_N, ROLE[role][1])
        text_at(d, (cx + w - 12, top + 24), str(len(rows)), F_L, ROLE[role][1], "rs")
        d.line((cx + 10, top + 34, cx + w - 10, top + 34), fill=LINE)
        per = 9
        for i, r in enumerate(rows):
            sub, row = divmod(i, per)
            name(img, cx + 12 + sub * (unit + 14), top + 58 + row * 26, r)
        cx += w + 14
    y = top + 312 + 28
    # unknown role, tentative, declined: one line each
    for label, color, rows in (("Rolle unbekannt", ROLE["none"][1], [r for r in YES if r[2] == "none"]),
                               ("Vorläufig", MAYBE, MAYBES), ("Abgelehnt", NO, NOS)):
        text_at(d, (x0, y), f"{label} · {len(rows)}", F_S, color)
        xx = x0 + 150
        for r in rows:
            xx = name(img, xx, y, r, dim=(label == "Abgelehnt")) + 22
        y += 24
    footer(img, d, BOT - 38, x0, x1)
    img.save(os.path.join(OUT, "raid-a.png"))


# --- B: numbers first, one grid -----------------------------------------------------------------------------------
def tile(img, d, x, y, w, number, label, color, mark=None):
    mb.gold_box(img, (x, y, x + w, y + 62))
    text_at(d, (x + w / 2, y + 34), str(number), F_BIG, color, "ms")
    lw = F_XS.getlength(label) + (16 if mark else 0)
    lx = x + (w - lw) / 2
    if mark:
        role_mark(d, lx, y + 53, mark, 0.9)
        lx += 16
    text_at(d, (lx, y + 53), label, F_XS, GREY)


def variant_b():
    img, d = frame()
    x0, x1 = R0 + 22, R1 - 22
    y = header(img, d, x0, TOP + 12, x1 - 380, compact=True)
    # the answer, top right beside the title
    text_at(d, (x1, TOP + 36), "Deine Antwort: Angemeldet", F_N, OK, "rs")
    small_button(img, x1 - 228, TOP + 50, 110, "Vorläufig")
    small_button(img, x1 - 110, TOP + 50, 110, "Absagen")
    y = wrap(d, x0, y + 14, DESC, x1 - x0, F_S, (216, 208, 188)) + 4
    # the strip of counts
    items = [(25, "Angemeldet", OK, None), (3, "Tanks", ROLE["tank"][1], "tank"), (6, "Heiler", ROLE["heal"][1], "heal"),
             (15, "DPS", ROLE["dps"][1], "dps"), (3, "Vorläufig", MAYBE, None), (2, "Abgelehnt", NO, None)]
    gap = 10
    w = (x1 - x0 - gap * (len(items) - 1)) / len(items)
    for i, (n, label, color, mark) in enumerate(items):
        tile(img, d, x0 + i * (w + gap), y, w, n, label, color, mark)
    y += 62 + 18
    # composition: one bar split by class color, the counts under it
    cnt = Counter(r[1] for r in YES)
    order = ["warrior", "paladin", "druid", "priest", "rogue", "hunter", "mage", "warlock"]
    xx = x0
    for cls in order:
        n = cnt.get(cls, 0)
        ww = (x1 - x0) * n / len(YES)
        d.rectangle((xx, y, xx + ww - 2, y + 6), fill=CLASS[cls][0])
        if ww > 40:
            text_at(d, (xx + ww / 2, y + 22), f"{CLASS_DE[cls]} {n}", F_XS, CLASS[cls][0], "ms")
        xx += ww
    y += 44
    # one grid, five columns, ordered by role; the role sign before each name
    cols = 5
    colw = (x1 - x0) / cols
    ordered = [r for role in ("tank", "heal", "dps", "none") for r in YES if r[2] == role]
    for i, r in enumerate(ordered):
        col, row = i % cols, i // cols
        px, py = x0 + col * colw, y + row * 28
        role_mark(d, px, py, r[2], 0.9)
        name(img, px + 16, py, r)
    y += 28 * ((len(ordered) + cols - 1) // cols) + 10
    d.line((x0, y - 6, x1, y - 6), fill=LINE)
    for i, r in enumerate(MAYBES):
        px = x0 + i * colw
        text_at(d, (px + 4, y + 16), "?", F_S, MAYBE)
        name(img, px + 16, y + 16, r, dim=True)
    y += 26
    text_at(d, (x0, y + 14), "Abgelehnt:", F_XS, NO)
    xx = x0 + 80
    for r in NOS:
        text_at(d, (xx, y + 14), r[0], F_XS, DIM)
        xx += F_XS.getlength(r[0]) + 16
    footer(img, d, BOT - 38, x0, x1)
    img.save(os.path.join(OUT, "raid-b.png"))


# --- C: profile card left, roster table right ----------------------------------------------------------------------
def variant_c():
    img, d = frame()
    split = R0 + 400
    d.line((split, TOP + 14, split, BOT - 14), fill=LINE)
    x0, x1 = R0 + 22, split - 22
    text_at(d, (x0, TOP + 40), TITLE, F_H, PARCH)
    type_mark(d, x0, TOP + 66, "raid", 4)
    text_at(d, (x0 + 14, TOP + 64), "Schlachtzug  ·  Stufe 60", F_S, TYPES["raid"][1])
    d.line((x0, TOP + 78, x1, TOP + 78), fill=(92, 74, 40))
    text_at(d, (x0, TOP + 104), "Freitag, 27. November", F_N, WHITE)
    text_at(d, (x0, TOP + 126), "20:00  ·  heute in 3 Std.", F_N, WHITE)
    text_at(d, (x0, TOP + 148), "von ", F_S, GREY)
    text_at(d, (x0 + F_S.getlength("von "), TOP + 148), BY[0], F_S, CLASS[BY[1]][0])
    y = wrap(d, x0, TOP + 178, DESC, x1 - x0, F_S, (216, 208, 188))
    y += 6
    text_at(d, (x0, y + 10), "Deine Antwort:", F_S, GOLD)
    text_at(d, (x0 + F_S.getlength("Deine Antwort: "), y + 10), "Angemeldet", F_S, OK)
    small_button(img, x0, y + 20, 170, "Vorläufig")
    small_button(img, x0 + 180, y + 20, 170, "Absagen")
    y += 70
    # composition by role and class
    text_at(d, (x0, y), "Aufstellung", F_S, GOLD)
    d.line((x0 + F_S.getlength("Aufstellung") + 10, y - 5, x1, y - 5), fill=LINE)
    y += 24
    for role in ("tank", "heal", "dps"):
        n = sum(1 for r in YES if r[2] == role)
        role_mark(d, x0, y, role)
        text_at(d, (x0 + 18, y), ROLE[role][0], F_S, ROLE[role][1])
        bar0, bar1 = x0 + 110, x1 - 30
        d.rectangle((bar0, y - 9, bar1, y - 3), fill=(40, 34, 24))
        d.rectangle((bar0, y - 9, bar0 + (bar1 - bar0) * n / len(YES), y - 3), fill=ROLE[role][1])
        text_at(d, (x1, y), str(n), F_S, WHITE, "rs")
        y += 22
    y += 8
    cnt = Counter(r[1] for r in YES)
    xx, line = x0, 0
    for cls in ["warrior", "paladin", "druid", "priest", "rogue", "hunter", "mage", "warlock"]:
        s = f"{CLASS_DE[cls]} {cnt.get(cls, 0)}"
        if xx + F_XS.getlength(s) > x1:
            xx, y = x0, y + 18
        text_at(d, (xx, y), s, F_XS, CLASS[cls][0])
        xx += F_XS.getlength(s) + 14
    # actions, stacked under the card
    by = BOT - 38
    red_button(img, x0, by - 32, 170, "Bearbeiten")
    red_button(img, x0 + 180, by - 32, 170, "Ankündigen")
    small_button(img, x0, by, 260, "Im Blizzard-Kalender öffnen")
    text_link(d, x1, by + 17, "Löschen", (220, 80, 60), "rs")
    # the roster as a table, grouped by role
    tx0, tx1 = split + 20, R1 - 40
    head_y = TOP + 34
    for label, x in (("Name", tx0 + 22), ("Klasse", tx0 + 270), ("Antwort", tx1)):
        text_at(d, (x, head_y), label, F_S, GOLD, "rs" if label == "Antwort" else "ls")
    d.line((tx0, head_y + 8, tx1, head_y + 8), fill=(92, 74, 40))
    y = head_y + 30
    stripe = False
    groups = [(role, [r for r in YES if r[2] == role]) for role in ("tank", "heal", "dps", "none")]
    groups += [("maybe", MAYBES), ("no", NOS)]
    for role, rows in groups:
        if role in ROLE:
            role_mark(d, tx0, y, role)
            text_at(d, (tx0 + 18, y), f"{ROLE[role][0]} · {len(rows)}", F_XS, ROLE[role][1])
        else:
            label, color = ("Vorläufig", MAYBE) if role == "maybe" else ("Abgelehnt", NO)
            text_at(d, (tx0, y), f"{label} · {len(rows)}", F_XS, color)
        y += 10
        for r in rows:
            if y + 18 > BOT - 8:
                break
            if stripe:
                d.rectangle((tx0, y + 2, tx1 + 10, y + 21), fill=(29, 25, 18))
            stripe = not stripe
            dim = role == "no"
            name(img, tx0 + 4, y + 17, r, dim=dim)
            text_at(d, (tx0 + 270, y + 17), CLASS_DE[r[1]], F_XS, DIM if dim else CLASS[r[1]][0])
            label, color = {"yes": ("Angemeldet", OK), "maybe": ("Vorläufig", MAYBE), "no": ("Abgelehnt", NO)}[r[3]]
            text_at(d, (tx1, y + 17), label, F_XS, color, "rs")
            y += 19
        y += 16
    mb.scrollbar(img, R1 - 30, TOP + 18, BOT - 8)
    img.save(os.path.join(OUT, "raid-c.png"))


if __name__ == "__main__":
    variant_a()
    variant_b()
    variant_c()
    print("raid-a.png, raid-b.png, raid-c.png in", OUT)
