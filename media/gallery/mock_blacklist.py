"""Mock-ups of the new Blacklist tab (docs/superpowers/specs/2026-11-22-blacklist-design.md), drawn into the
real reference screenshot src/crop/02-members.png: window frame, search box, dropdowns, checkboxes and tabs
are the game's own pixels (cut and 3-sliced), the content is drawn with the game's font.

    python media/gallery/mock_blacklist.py  ->  mock/blacklist-a.png  ledger: a table like the Members tab
                                                mock/blacklist-b.png  wanted card: list and the picked entry
                                                mock/blacklist-c.png  by kind: sections per tag, add bar on top

Names are made up like Core/Anon.lua. Needs Pillow; src/ and fonts/ are local only.
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "mock")
FONT = os.path.join(HERE, "fonts", "FRIZQT__.TTF")
CROP = os.path.join(HERE, "src", "crop")
BASE = os.path.join(CROP, "02-members.png")
INFO = os.path.join(CROP, "10-info.png")
OVERVIEW = os.path.join(CROP, "03-overview.png")

F_XS = ImageFont.truetype(FONT, 12.4)
F_S = ImageFont.truetype(FONT, 14.4)
F_B = ImageFont.truetype(FONT, 14.2)
F_N = ImageFont.truetype(FONT, 16.6)
F_L = ImageFont.truetype(FONT, 22)
F_Q = ImageFont.truetype(FONT, 17.5)
F_T = ImageFont.truetype(FONT, 15.2)  # tab labels
GOLD, WHITE, GREY, DIM = (255, 209, 0), (255, 255, 255), (150, 142, 128), (110, 104, 90)
BG, STRIPE, LINE = (22, 19, 14), (30, 27, 22), (60, 52, 38)
GREEN = (64, 224, 64)

# the members box: gold line at 43..1652 x 114..797, rows as measured in 02-members.png
BX0, BY0, BX1, BY1 = 46, 117, 1651, 794
PITCH = 25.3

# tags: code -> (label, color). Kill on sight red, ninja looter orange, insults violet, scammer teal
TAGS = {
    "kos": ("Kill on Sight", (255, 72, 72)),
    "ninja": ("Ninja-Looter", (255, 146, 48)),
    "insult": ("Beleidigungen", (196, 128, 255)),
    "scam": ("Betrüger", (64, 208, 200)),
    "other": ("Sonstiges", (176, 168, 150)),
}
TAG_ORDER = ["kos", "ninja", "insult", "scam", "other"]

# class colors and the icon rows they are cut from in 02-members.png (Falk = warrior, Wanda = priest, ...)
CLASS = {
    "warrior": ((198, 155, 109), 188), "priest": ((255, 255, 255), 213), "shaman": ((0, 112, 222), 239),
    "hunter": ((170, 211, 114), 264), "rogue": ((255, 244, 104), 289), "paladin": ((245, 140, 186), 314),
    "druid": ((255, 124, 10), 365), "warlock": ((135, 136, 238), 567), "mage": ((63, 199, 235), 618),
}

# name, class (None = never seen, only typed), level, tag, reason, by, when, faction note, state
ENTRIES = [
    ("Krag Eisenzahn", "warrior", 60, "kos", "campt den Friedhof im Schlingendorntal", "Alva Abendrot", "vor 2 Std.",
     "Horde", None),
    ("Bodo Langfinger", "rogue", 52, "ninja", "würfelt Bedarf auf alles, BRD-Run am Dienstag", "Pell Quellgrund",
     "vor 5 Std.", "Allianz", None),
    ("Vexa Nachtschatten", "warlock", 58, "kos", "tötet Leute unter 30 im Brachland", "Silas Birkfeld", "vor 1 Tg.",
     "Horde", None),
    ("Gerd Großmaul", "paladin", 44, "insult", "beleidigt im Handelschannel, flüstert nach", "Tara Taubnessel",
     "vor 1 Tg.", "Allianz", None),
    ("Fenna Falschgold", "mage", 37, "scam", "Handel: 20 Gold genommen, Ware nie geliefert", "Nika Quellgrund",
     "vor 2 Tg.", "Allianz", None),
    ("Morn Schädelspalter", "shaman", 60, "kos", "", "Alva Abendrot", "vor 3 Tg.", "Horde", None),
    ("Lirra Dunkelquell", None, None, "ninja", "Lootmeister, hat Gruppenloot umgestellt und alles genommen",
     "Cord Nebelstein", "vor 4 Tg.", None, None),
    ("Ruk Knochenbrecher", "hunter", 55, "kos", "Gruppe von drei, jagt Sammler in Felwood", "Ylva Immergruen",
     "vor 5 Tg.", "Horde", None),
    ("Jule Plappermaul", "priest", 29, "insult", "spammt im Gildenchat-Rekrutierung, beleidigt bei Absage",
     "Greta Donnerkeil", "vor 6 Tg.", "Allianz", None),
    ("Tarek Sandsturm", "druid", 48, "other", "zieht Mobs in Gruppen", "Xara Quellgrund", "vor 1 Wo.", "Allianz", None),
    ("Hanno Glutpfad", "warlock", 34, "insult", "jetzt in der Gilde", "Alva Abendrot", "vor 2 Wo.", "Allianz", "guild"),
]


def text_at(d, xy, s, font=F_S, fill=WHITE, anchor="ls"):
    d.text((xy[0] + 1, xy[1] + 1), s, font=font, fill=(0, 0, 0), anchor=anchor)
    d.text(xy, s, font=font, fill=fill, anchor=anchor)


def fit(s, font, width):
    if font.getlength(s) <= width:
        return s
    while s and font.getlength(s + "...") > width:
        s = s[:-1]
    return s.rstrip() + "..."


# --- the game's widgets, cut from the screenshots ------------------------------------------------------------
_members = Image.open(BASE).convert("RGB")
_info = Image.open(INFO).convert("RGB")
_ov = Image.open(OVERVIEW).convert("RGB")

SEARCH = _members.crop((117, 75, 433, 103))
DROPDOWN = _members.crop((447, 76, 569, 104))
CHECK = _members.crop((719, 77, 745, 101))
RED = _members.crop((1535, 77, 1654, 103))           # "Zurücksetzen"
TAB = _members.crop((802, 815, 902, 852))            # "Bank", plain
TAB_ON = _members.crop((148, 815, 249, 862))         # "Mitglieder", picked
SEG = {"on": _ov.crop((507, 77, 600, 103)), "off": _ov.crop((828, 77, 920, 103))}
SEG_MID = {"on": (4, 14), "off": (5, 26)}
ICON = {k: _members.crop((106, y - 14, 123, y + 3)) for k, (_, y) in CLASS.items()}


def slice3(src, w, cap, mid, h=None):
    """Stretch a widget crop to width w, keeping cap pixels at both ends; mid = text-free columns."""
    h = h or src.height
    out = Image.new("RGB", (w, h))
    out.paste(src.crop((0, 0, cap, h)), (0, 0))
    out.paste(src.crop((mid[0], 0, mid[1], h)).resize((w - 2 * cap, h)), (cap, 0))
    out.paste(src.crop((src.width - cap, 0, src.width, h)), (w - cap, 0))
    return out


def search_box(img, x, y, w, hint, typed=None):
    img.paste(slice3(SEARCH, w, 10, (300, 306)), (x, y))
    d = ImageDraw.Draw(img)
    if typed:
        text_at(d, (x + 11, y + 19), typed, F_S, WHITE)
        cx = x + 11 + F_S.getlength(typed) + 2
        d.line((cx, y + 7, cx, y + 21), fill=WHITE, width=1)
    else:
        text_at(d, (x + 11, y + 19), hint, F_S, (120, 114, 100))
    return x + w


def dropdown(img, x, y, w, label, color=GOLD):
    piece = slice3(DROPDOWN, w, 8, (12, 18))
    arrow = DROPDOWN.crop((92, 0, 114, DROPDOWN.height))
    piece.paste(arrow, (w - 30, 0))
    img.paste(piece, (x, y))
    text_at(ImageDraw.Draw(img), (x + (w - 26) / 2 + 4, y + 19), label, F_B, color, "ms")
    return x + w


def red_button(img, x, y, w, label, color=GOLD):
    img.paste(slice3(RED, w, 6, (108, 112)), (x, y))
    text_at(ImageDraw.Draw(img), (x + w / 2, y + 18), label, F_B, color, "ms")
    return x + w


def check(img, x, y, label, on=False):
    img.paste(CHECK, (x, y))
    d = ImageDraw.Draw(img)
    if on:
        d.line((x + 6, y + 12, x + 11, y + 18, x + 20, y + 5), fill=GOLD, width=3)
    text_at(d, (x + 30, y + 18), label, F_S, WHITE)
    return round(x + 30 + F_S.getlength(label))


def segmented(img, x, y, items, picked, colors=None, pad=20):
    d = ImageDraw.Draw(img)
    for key, label in items:
        on = key == picked
        w = round(F_B.getlength(label) + pad)
        src = SEG["on" if on else "off"]
        img.paste(slice3(src, w, 4, SEG_MID["on" if on else "off"]), (x, y))
        color = (colors or {}).get(key) or (WHITE if on else GOLD)
        text_at(d, (x + w / 2, y + src.height / 2 + 1), label, F_B, color, "mm")
        x += w + 4
    return x


def tabs(img, labels, picked):
    """The tab row anew: plain tabs from "Bank", the picked one from "Mitglieder"."""
    bg = _members.crop((30, 853, 940, 880))
    img.paste(_members.crop((30, 812, 940, 880)).resize((910, 68)), (30, 812))  # keep frame edge
    # wipe the old row (the strip under the frame is plain backdrop)
    strip = _members.crop((930, 812, 1030, 880))
    for x in range(30, 1200, 100):
        img.paste(strip, (x, 812))
    img.paste(_members.crop((30, 800, 1200, 815)), (30, 800))
    d = ImageDraw.Draw(img)
    x = 41
    for label in labels:
        w = max(98, round(F_T.getlength(label) + 34))
        if label == picked:
            img.paste(slice3(TAB_ON, w + 2, 10, (88, 91)), (x - 1, 815))
            text_at(d, (x + w / 2, 843), label, F_T, WHITE, "ms")
        else:
            img.paste(slice3(TAB, w, 10, (14, 18)), (x, 815))
            text_at(d, (x + w / 2, 836), label, F_T, GOLD, "ms")
        x += w + 8
    del bg


TAB_LABELS = ["Chat", "Mitglieder", "Übersicht", "Ruhmeshalle", "Berufe", "Info & Log", "Ränge", "Bank",
              "Blacklist"]


def clear_toolbar(img):
    strip = _info.crop((560, 70, 1460, 108))
    img.paste(strip, (110, 70))
    img.paste(_info.crop((660, 70, 1290, 108)), (1010, 70))
    img.paste(_members.crop((1640, 70, 1660, 108)), (1640, 70))


def clear_box(img, box=(BX0, BY0, BX1, BY1)):
    ImageDraw.Draw(img).rectangle(box, fill=BG)


def gold_box(img, box):
    """A Guildy box: dark fill and the thin gold-brown line of the game's inset frames."""
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    d.rectangle(box, fill=BG)
    d.rectangle((x0, y0, x1, y1), outline=(92, 74, 40))
    d.rectangle((x0 + 1, y0 + 1, x1 - 1, y1 - 1), outline=(40, 33, 22))


def base():
    img = _members.copy()
    clear_toolbar(img)
    tabs(img, TAB_LABELS, "Blacklist")
    return img


def name_cell(img, x, y, entry, font=F_S, dim=False):
    name, cls = entry[0], entry[1]
    d = ImageDraw.Draw(img)
    if cls:
        img.paste(ICON[cls], (round(x), round(y) - 14))
        color = CLASS[cls][0]
    else:
        d.rectangle((x + 2, y - 12, x + 15, y + 1), outline=LINE)
        text_at(d, (x + 8.5, y - 1), "?", F_XS, DIM, "ms")
        color = (205, 198, 182)
    if dim:
        color = DIM
    text_at(d, (x + 21, y), name, font, color)
    return x + 21 + font.getlength(name)


def tag_mark(d, x, y, tag, size=5):
    color = TAGS[tag][1]
    d.rectangle((x + 1, y - size - 3, x + 2 * size + 1, y + size - 3 + 1), fill=(0, 0, 0))
    d.rectangle((x, y - size - 4, x + 2 * size, y + size - 4), fill=color)


def remove_x(d, x, y, color=(200, 60, 50)):
    for dx, fill in ((1, (0, 0, 0)), (0, color)):
        d.line((x - 4 + dx, y - 9 + dx, x + 4 + dx, y - 1 + dx), fill=fill, width=2)
        d.line((x - 4 + dx, y - 1 + dx, x + 4 + dx, y - 9 + dx), fill=fill, width=2)


def scrollbar(img, x, y0, y1):
    """The game's scroll arrows, cut from the members box."""
    img.paste(_members.crop((1626, 150, 1650, 200)), (x, y0))
    img.paste(_members.crop((1626, 765, 1650, 790)), (x, y1 - 25))


# --- A: ledger ---------------------------------------------------------------------------------------------
def variant_a():
    """A table like the Members tab: search, kind filter, the add form as the list's first row."""
    img = base()
    d = ImageDraw.Draw(img)
    x = search_box(img, 118, 75, 300, "Name, Grund suchen ...") + 15
    x = dropdown(img, x, 76, 150, "Alle Arten") + 18
    x = check(img, x, 77, "Ohne Grund 1") + 22
    x = check(img, x, 77, "Entfernte zeigen", True) + 22
    text_at(d, (1517, 95), f"{len(ENTRIES)} Einträge · 1 entfernt", F_S, DIM, "rs")
    red_button(img, 1535, 77, 118, "Eintragen")
    clear_box(img)
    cols = [("Name", 52), ("Art", 300), ("Grund", 470), ("Fraktion", 950), ("St.", 1050), ("Eingetragen von", 1110),
            ("Wann", 1320), ("", 1440)]
    for label, cx in cols:
        text_at(d, (cx, 136), label, F_B, GOLD)
    # add row: the inline form
    y = 168
    d.rectangle((BX0 + 3, y - 18, BX1 - 26, y + 10), fill=(40, 33, 20))
    search_box(img, 50, y - 19, 236, "", typed="Grom Blutfaust")
    dropdown(img, 296, y - 20, 160, "Kill on Sight", TAGS["kos"][1])
    search_box(img, 466, y - 19, 470, "Grund (optional)", typed="lauert am Flugpunkt Kargath")
    text_at(d, (950, y), "aus dem Ziel: Horde, St. 57", F_S, DIM)
    red_button(img, 1340, y - 18, 118, "Eintragen")
    text_at(d, (1610, y), "Abbrechen", F_S, GREY, "rs")
    y = 207
    text_at(d, (52, y), "Eingetragen · " + str(len(ENTRIES)), F_S, (255, 120, 90))
    d.line((52 + F_S.getlength("Eingetragen · 11") + 10, y - 5, 1600, y - 5), fill=LINE)
    y += PITCH
    for i, e in enumerate(ENTRIES):
        name, cls, level, tag, reason, by, when, faction, state = e
        r0, r1 = round(y - 18), round(y + 7)
        if i % 2 == 1:
            d.rectangle((BX0 + 3, r0, BX1 - 26, r1), fill=STRIPE)
        dim = state == "guild"
        name_cell(img, 52, y, e, dim=dim)
        tag_mark(d, 300, y, tag)
        text_at(d, (318, y), TAGS[tag][0], F_S, DIM if dim else TAGS[tag][1])
        if dim:
            text_at(d, (470, y), "jetzt in der Gilde · keine Warnung", F_S, DIM)
        else:
            text_at(d, (470, y), fit(reason, F_S, 460) if reason else "kein Grund", F_S,
                    WHITE if reason else (255, 120, 90))
        fac_color = (255, 90, 80) if faction == "Horde" else ((120, 170, 255) if faction else DIM)
        text_at(d, (950, y), faction or "?", F_S, DIM if dim else fac_color)
        text_at(d, (1050, y), str(level) if level else "?", F_S, DIM if dim else WHITE)
        text_at(d, (1110, y), by, F_S, DIM if dim else (210, 200, 180))
        text_at(d, (1320, y), when, F_S, GREY)
        if i == 3:  # the row under the mouse
            d.rectangle((BX0 + 3, r0, BX1 - 26, r1), outline=(120, 96, 40))
            remove_x(d, 1446, y)
            text_at(d, (1460, y), "Entfernen", F_S, (230, 120, 100))
        else:
            remove_x(d, 1446, y, DIM if dim else (150, 60, 50))
        y += PITCH
    # a removed entry, shown greyed for officers
    y += 8
    text_at(d, (52, y), "Entfernt · 1", F_S, GREY)
    d.line((52 + F_S.getlength("Entfernt · 1") + 10, y - 5, 1600, y - 5), fill=LINE)
    y += PITCH
    name_cell(img, 52, y, ("Sira Feuerhuf", "hunter"), dim=True)
    text_at(d, (300, y), "Kill on Sight", F_S, DIM)
    text_at(d, (470, y), "entfernt von Alva Abendrot: hat sich entschuldigt", F_S, DIM)
    text_at(d, (1320, y), "vor 3 Tg.", F_S, DIM)
    text_at(d, (1460, y), "Wieder eintragen", F_S, DIM)
    scrollbar(img, 1626, 148, 792)
    img.save(os.path.join(OUT, "blacklist-a.png"))


# --- B: wanted card ----------------------------------------------------------------------------------------
def tooltip(img, x, y, lines, w):
    """GameTooltip: black, slightly see-through, grey-blue edge."""
    h = 14 + 20 * len(lines)
    over = Image.new("RGBA", img.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(over)
    od.rounded_rectangle((x, y, x + w, y + h), 5, fill=(6, 6, 14, 236), outline=(120, 128, 150, 255), width=2)
    img.paste(Image.alpha_composite(img.convert("RGBA"), over).convert("RGB"))
    d = ImageDraw.Draw(img)
    ty = y + 24
    for text, color, font in lines:
        text_at(d, (x + 10, ty), text, font, color)
        ty += 20


def variant_b():
    """List on the left, the picked entry as a card on the right, with how the warning looks."""
    img = base()
    d = ImageDraw.Draw(img)
    x = search_box(img, 118, 75, 260, "Name suchen ...") + 15
    items = [("all", "Alle 11")] + [(t, TAGS[t][0]) for t in TAG_ORDER]
    segmented(img, x, 77, items, "all", colors={t: TAGS[t][1] for t in TAG_ORDER})
    red_button(img, 1535, 77, 118, "Neu eintragen")
    clear_box(img)
    # left list
    d.line((560, BY0 + 6, 560, BY1 - 6), fill=LINE)
    y = 142
    picked = 1
    for i, e in enumerate(ENTRIES):
        name, cls, level, tag, reason, by, when, faction, state = e
        r0, r1 = y - 22, y + 18
        if i == picked:
            d.rectangle((BX0 + 3, r0, 556, r1), fill=(58, 46, 22))
            d.rectangle((BX0 + 3, r0, BX0 + 5, r1), fill=GOLD)
        elif i % 2 == 1:
            d.rectangle((BX0 + 3, r0, 556, r1), fill=STRIPE)
        dim = state == "guild"
        name_cell(img, 58, y - 2, e, dim=dim)
        tag_mark(d, 79, y + 16, tag, 4)
        text_at(d, (93, y + 14), TAGS[tag][0] if not dim else "jetzt in der Gilde", F_XS,
                DIM if dim else TAGS[tag][1])
        text_at(d, (544, y - 2), when, F_XS, GREY, "rs")
        y += 46
        if y > BY1 - 20:
            break
    # right card
    e = ENTRIES[picked]
    name, cls, level, tag, reason, by, when, faction, state = e
    cx = 590
    img.paste(ICON[cls].resize((34, 34)), (cx, 140))
    text_at(d, (cx + 46, 166), name, F_L, CLASS[cls][0])
    text_at(d, (cx + 46, 188), f"Stufe {level} · Mensch · Schurke · {faction}", F_S, GREY)
    # tag badge
    label, color = TAGS[tag]
    bw = round(F_B.getlength(label) + 26)
    d.rounded_rectangle((1410, 145, 1410 + bw, 171), 4, fill=tuple(c // 4 for c in color), outline=color)
    text_at(d, (1410 + bw / 2, 163), label, F_B, color, "ms")
    d.line((cx, 210, 1610, 210), fill=LINE)
    text_at(d, (cx, 244), "„" + reason + "“", F_Q, WHITE)
    text_at(d, (cx, 278), "Eingetragen von ", F_S, GREY)
    x = cx + F_S.getlength("Eingetragen von ")
    text_at(d, (x, 278), "Pell Quellgrund", F_S, CLASS["rogue"][0])
    x += F_S.getlength("Pell Quellgrund")
    text_at(d, (x, 278), " · heute 14:12 · geteilt mit 23 Guildy-Nutzern", F_S, GREY)
    red_button(img, cx, 296, 120, "Bearbeiten")
    red_button(img, cx + 130, 296, 120, "Entfernen", (255, 140, 120))
    text_at(d, (cx + 262, 314), "nur Offiziere entfernen", F_XS, DIM)
    # what the guild sees
    d.line((cx, 350, 1610, 350), fill=LINE)
    text_at(d, (cx, 380), "So warnt Guildy", F_N, GOLD)
    text_at(d, (cx, 402), "beim Namensschild, Ziel oder Mouseover, in der Gruppe, beim Flüstern und Handeln · "
            "einmal in 5 Minuten", F_S, GREY)
    tooltip(img, cx, 420, [
        (name, CLASS[cls][0], F_N),
        (f"Stufe {level} Mensch Schurke (Spieler)", WHITE, F_S),
        ("Allianz", WHITE, F_S),
        ("Blacklist: Ninja-Looter", TAGS["ninja"][1], F_S),
        ("würfelt Bedarf auf alles", (255, 200, 150), F_S),
    ], 330)
    # chat line
    chat_y = 470
    text_at(d, (960, chat_y - 22), "im Chat", F_XS, DIM)
    d.rectangle((958, chat_y - 14, 1610, chat_y + 46), fill=(10, 9, 7))
    parts = [("[Guildy] ", (212, 160, 23)), ("Blacklist: ", TAGS["ninja"][1]), (name, CLASS[cls][0]),
             (" ist in deiner Gruppe", WHITE)]
    x = 968
    for s, c in parts:
        text_at(d, (x, chat_y + 6), s, F_S, c)
        x += F_S.getlength(s)
    text_at(d, (968, chat_y + 32), "Ninja-Looter · würfelt Bedarf auf alles (Pell Quellgrund)", F_S,
            (255, 200, 150))
    # history
    d.line((cx, 560, 1610, 560), fill=LINE)
    text_at(d, (cx, 590), "Verlauf", F_N, GOLD)
    history = [("heute 14:12", "Pell Quellgrund", "trägt ein: Ninja-Looter"),
               ("heute 14:20", "Alva Abendrot", "ergänzt den Grund: BRD-Run am Dienstag"),
               ("heute 18:47", "Guildy", "Warnung bei Tara Taubnessel: Einladung in ihre Gruppe")]
    hy = 620
    for when_, who, what in history:
        text_at(d, (cx, hy), when_, F_S, GREY)
        text_at(d, (cx + 110, hy), who, F_S, (210, 200, 180))
        text_at(d, (cx + 260, hy), what, F_S, WHITE)
        hy += PITCH
    img.save(os.path.join(OUT, "blacklist-b.png"))


# --- C: by kind --------------------------------------------------------------------------------------------
def variant_c():
    """The add bar is the toolbar (name, kind as colored buttons, reason); sections per kind below."""
    img = base()
    d = ImageDraw.Draw(img)
    x = search_box(img, 118, 75, 220, "", typed="Grom Blutfaust") + 12
    items = [(t, TAGS[t][0]) for t in TAG_ORDER]
    x = segmented(img, x, 77, items, "kos", colors={t: TAGS[t][1] for t in TAG_ORDER if t != "kos"}) + 8
    search_box(img, x, 75, 1525 - x, "Grund (optional) ...")
    red_button(img, 1535, 77, 118, "Eintragen")
    clear_box(img)
    y = 150
    for tag in TAG_ORDER:
        rows = [e for e in ENTRIES if e[3] == tag]
        if not rows:
            continue
        label, color = TAGS[tag]
        head = f"{label} · {len(rows)}"
        tag_mark(d, 52, y, tag, 6)
        text_at(d, (72, y), head, F_N, color)
        d.line((72 + F_N.getlength(head) + 12, y - 6, 1600, y - 6), fill=LINE)
        y += PITCH + 2
        for i, e in enumerate(rows):
            name, cls, level, tag_, reason, by, when, faction, state = e
            dim = state == "guild"
            if i % 2 == 1:
                d.rectangle((BX0 + 3, round(y - 18), BX1 - 26, round(y + 7)), fill=STRIPE)
            name_cell(img, 72, y, e, dim=dim)
            meta = (f"{level} " if level else "") + ({"warrior": "Krieger", "rogue": "Schurke", "warlock": "Hexer",
                     "paladin": "Paladin", "mage": "Magier", "shaman": "Schamane", "hunter": "Jäger",
                     "priest": "Priester", "druid": "Druide"}.get(cls, "nie gesehen"))
            text_at(d, (300, y), meta, F_S, DIM if dim else GREY)
            if dim:
                text_at(d, (460, y), "jetzt in der Gilde · keine Warnung", F_S, DIM)
            else:
                text_at(d, (460, y), fit(reason, F_S, 640) if reason else "kein Grund", F_S,
                        WHITE if reason else DIM)
            text_at(d, (1140, y), by, F_S, DIM if dim else (210, 200, 180))
            text_at(d, (1440, y), when, F_S, GREY, "rs")
            remove_x(d, 1470, y)
            y += PITCH
        y += 12
    # footer hint
    text_at(d, (52, 784), "Auch per /guildy bl oder Rechtsklick auf einen Spieler · Entfernen nur für Offiziere",
            F_S, DIM)
    img.save(os.path.join(OUT, "blacklist-c.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    variant_a()
    variant_b()
    variant_c()
