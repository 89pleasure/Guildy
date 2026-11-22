"""Mock-ups of the Info & Log tab's guild log with filters and a color per event type, drawn into the real
screenshot src/crop/10-info.png. The buttons are cut from the real Overview toolbar (W.Segmented).

    python media/gallery/mock_guildlog.py  ->  mock/log-a.png  filter in the toolbar, colored marker
                                               mock/log-b.png  filter in the log box with counts, "Left" picked
                                               mock/log-c.png  colored filter words as legend, rows by day
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "mock")
FONT = os.path.join(HERE, "fonts", "FRIZQT__.TTF")
BASE = os.path.join(HERE, "src", "crop", "10-info.png")
OVERVIEW = os.path.join(HERE, "src", "crop", "03-overview.png")

F_S = ImageFont.truetype(FONT, 14)
F_N = ImageFont.truetype(FONT, 16.6)
F_B = ImageFont.truetype(FONT, 14.2)
GOLD, WHITE, GREY, DIM = (255, 209, 0), (255, 255, 255), (150, 142, 128), (110, 104, 90)
BG, STRIPE = (22, 19, 14), (30, 27, 22)

# color per kind: the same green and red as the Overview's "Kommen und Gehen"
KIND = {
    "join": ((90, 230, 90), "+"),
    "invite": ((120, 180, 255), "»"),
    "promote": ((255, 209, 0), "▲"),
    "demote": ((255, 140, 50), "▼"),
    "quit": ((255, 80, 80), "–"),
    "remove": ((255, 80, 80), "×"),
}

# (kind, text, when, day) — names made up like Core/Anon.lua
EVENTS = [
    ("join", "Arno Moorweide tritt der Gilde bei", "vor 2 Std.", 0),
    ("invite", "Nika Wolkenbruch lädt Arno Moorweide ein", "vor 2 Std.", 0),
    ("promote", "Sten Falkenau befördert Ylva Rabenhorst zu Freund", "vor 5 Std.", 0),
    ("quit", "Calla Taubnessel verlässt die Gilde", "vor 8 Std.", 0),
    ("join", "Ylva Rabenhorst tritt der Gilde bei", "vor 9 Std.", 0),
    ("invite", "Sten Falkenau lädt Ylva Rabenhorst ein", "vor 9 Std.", 0),
    ("remove", "Alva Abendrot wirft Bero Kesselflick aus der Gilde", "vor 11 Std.", 0),
    ("promote", "Sten Falkenau befördert Imke Fuchsbau zu Freund", "vor 1 Tg.", 1),
    ("join", "Imke Fuchsbau tritt der Gilde bei", "vor 1 Tg.", 1),
    ("invite", "Sten Falkenau lädt Imke Fuchsbau ein", "vor 1 Tg.", 1),
    ("quit", "Dana Glutpfad verlässt die Gilde", "vor 1 Tg.", 1),
    ("demote", "Alva Abendrot degradiert Wim Regenfall zu Veteran", "vor 1 Tg.", 1),
    ("join", "Orla Nordkamm tritt der Gilde bei", "vor 1 Tg.", 1),
    ("invite", "Nika Quellgrund lädt Orla Nordkamm ein", "vor 1 Tg.", 1),
    ("promote", "Sten Falkenau befördert Maren Zunderfels zu Freund", "vor 1 Tg.", 1),
    ("join", "Finn Moorweide tritt der Gilde bei", "vor 1 Tg.", 1),
    ("invite", "Sten Falkenau lädt Finn Moorweide ein", "vor 1 Tg.", 1),
    ("quit", "Hanno Erlenbruch verlässt die Gilde", "vor 2 Tg.", 2),
    ("quit", "Calla Bruchstein verlässt die Gilde", "vor 2 Tg.", 2),
    ("remove", "Sten Falkenau wirft Dana Quellgrund aus der Gilde", "vor 2 Tg.", 2),
    ("join", "Maren Zunderfels tritt der Gilde bei", "vor 2 Tg.", 2),
    ("invite", "Sten Falkenau lädt Maren Zunderfels ein", "vor 2 Tg.", 2),
    ("promote", "Alva Abendrot befördert Jorin Zunderfels zu Offizier", "vor 3 Tg.", 3),
    ("quit", "Pella Grauwind verlässt die Gilde", "vor 3 Tg.", 3),
    ("join", "Jorin Zunderfels tritt der Gilde bei", "vor 3 Tg.", 3),
    ("invite", "Sten Falkenau lädt Jorin Zunderfels ein", "vor 3 Tg.", 3),
    ("quit", "Lio Steinbach verlässt die Gilde", "vor 4 Tg.", 4),
    ("join", "Wim Regenfall tritt der Gilde bei", "vor 4 Tg.", 4),
]

FILTERS = [("all", "Alle"), ("join", "Beitritte"), ("left", "Austritte"), ("invite", "Einladungen"),
           ("rank", "Ränge")]
GROUP = {"join": "join", "invite": "invite", "quit": "left", "remove": "left", "promote": "rank", "demote": "rank"}
DAYS = ["Heute", "Gestern", "Vor 2 Tagen", "Vor 3 Tagen", "Vor 4 Tagen"]

# the log box: inner area, first row baseline, row pitch
LX0, LX1, LY0, LY1 = 862, 1626, 117, 789
TEXT_X, WHEN_X, ROW0, PITCH = 871, 1611, 168, 25.3


def text_at(d, xy, s, font=F_S, fill=WHITE, anchor="ls"):
    d.text((xy[0] + 1, xy[1] + 1), s, font=font, fill=(0, 0, 0), anchor=anchor)
    d.text(xy, s, font=font, fill=fill, anchor=anchor)


# --- buttons, 3-sliced from the Overview toolbar -------------------------------------------------------
_ov = Image.open(OVERVIEW).convert("RGB")
BTN = {"on": _ov.crop((507, 77, 600, 103)), "off": _ov.crop((828, 77, 920, 103))}
MID = {"on": (4, 14), "off": (5, 26)}  # text-free columns inside each crop
CAP = 4


def button(img, x, y, w, label, on, color=None):
    src = BTN["on" if on else "off"]
    h = src.height
    a, b = MID["on" if on else "off"]
    left, right = src.crop((0, 0, CAP, h)), src.crop((src.width - CAP, 0, src.width, h))
    mid = src.crop((a, 0, b, h)).resize((w - 2 * CAP, h))
    img.paste(left, (x, y))
    img.paste(mid, (x + CAP, y))
    img.paste(right, (x + w - CAP, y))
    d = ImageDraw.Draw(img)
    text_at(d, (x + w / 2, y + h / 2 + 1), label, F_B, color or (WHITE if on else GOLD), "mm")
    return x + w


def segmented(img, x, y, items, picked, pad=22, colors=None):
    for key, label in items:
        w = round(F_B.getlength(label) + pad)
        color = (colors or {}).get(key)
        x = button(img, x, y, w, label, key == picked, color) + 4
    return x


# --- log box ---------------------------------------------------------------------------------------------
def clear_log(img, top=LY0):
    ImageDraw.Draw(img).rectangle((LX0, top, LX1, LY1), fill=BG)


def rows(img, events, top=ROW0, marker=False, tint=False, whole=False, days=False, limit=LY1 - 8):
    d = ImageDraw.Draw(img, "RGBA")
    y, i, last_day = top, 0, None
    for kind, text, when, day in events:
        if days and day != last_day:
            last_day = day
            if y > top:
                y += 6
            text_at(d, (TEXT_X, y), DAYS[day], F_S, GOLD)
            d.line((TEXT_X + F_S.getlength(DAYS[day]) + 10, y - 5, WHEN_X, y - 5), fill=(60, 52, 38))
            y += PITCH
            i = 0
        if y > limit:
            break
        color, glyph = KIND[kind]
        r0, r1 = round(y - 18), round(y + 7)
        if i % 2 == 1:
            d.rectangle((LX0 + 3, r0, LX1 - 6, r1), fill=STRIPE)
        if tint:
            d.rectangle((LX0 + 3, r0, LX1 - 6, r1), fill=color + (26,))
            d.rectangle((LX0 + 3, r0, LX0 + 5, r1), fill=color + (220,))
        x = TEXT_X
        if marker:
            draw_marker(d, x + 6, y - 5, kind, color)
            x += 20
        text_at(d, (x, y), text, F_S, color if whole else WHITE)
        text_at(d, (WHEN_X, y), when, F_S, GREY, "rs")
        y += PITCH
        i += 1
    return y


def draw_marker(d, cx, cy, kind, color):
    """Small shapes, drawn as textures in the game too (the font has no arrows)."""
    shadow = (0, 0, 0)
    for dx, fill in ((1, shadow), (0, color)):
        x, y = cx + dx, cy + dx
        if kind == "join":
            d.rectangle((x - 5, y - 1, x + 5, y + 1), fill=fill)
            d.rectangle((x - 1, y - 5, x + 1, y + 5), fill=fill)
        elif kind == "quit":
            d.rectangle((x - 5, y - 1, x + 5, y + 1), fill=fill)
        elif kind == "remove":
            d.line((x - 4, y - 4, x + 4, y + 4), fill=fill, width=3)
            d.line((x - 4, y + 4, x + 4, y - 4), fill=fill, width=3)
        elif kind == "promote":
            d.polygon([(x - 5, y + 4), (x + 5, y + 4), (x, y - 5)], fill=fill)
        elif kind == "demote":
            d.polygon([(x - 5, y - 4), (x + 5, y - 4), (x, y + 5)], fill=fill)
        elif kind == "invite":
            d.polygon([(x - 4, y - 5), (x + 5, y), (x - 4, y + 5)], fill=fill)


def count(kind_group):
    return sum(1 for e in EVENTS if kind_group == "all" or GROUP[e[0]] == kind_group)


# --- variants --------------------------------------------------------------------------------------------
def variant_a():
    """Filter in the tab's toolbar next to the two buttons, colored marker before every line."""
    img = Image.open(BASE).convert("RGB")
    d = ImageDraw.Draw(img)
    x = 572
    text_at(d, (x, 95), "Gildenlog zeigt", F_B, GOLD)
    segmented(img, x + round(F_B.getlength("Gildenlog zeigt")) + 12, 77, FILTERS, "all")
    clear_log(img, 150)
    rows(img, EVENTS, marker=True)
    img.save(os.path.join(OUT, "log-a.png"))


def variant_b():
    """Filter inside the log box with counts, "Austritte" picked: only leavers and kicks, rows tinted."""
    img = Image.open(BASE).convert("RGB")
    clear_log(img)
    d = ImageDraw.Draw(img)
    text_at(d, (870, 138), "Gildenlog", F_N, GOLD)
    items = [(k, f"{label} {count(k)}" if k != "all" else label) for k, label in FILTERS]
    segmented(img, 870, 150, items, "left", pad=18)
    left = [e for e in EVENTS if GROUP[e[0]] == "left"]
    text_at(d, (WHEN_X, 138), f"{len(left)} von {len(EVENTS)} Einträgen", F_S, DIM, "rs")
    rows(img, left, top=203, marker=True, tint=True)
    img.save(os.path.join(OUT, "log-b.png"))


def variant_c():
    """Filter words in their event color (the legend too), whole line colored, rows grouped by day."""
    img = Image.open(BASE).convert("RGB")
    clear_log(img)
    d = ImageDraw.Draw(img)
    text_at(d, (870, 138), "Gildenlog", F_N, GOLD)
    colors = {"join": KIND["join"][0], "left": KIND["quit"][0], "invite": KIND["invite"][0],
              "rank": KIND["promote"][0]}
    segmented(img, 870, 150, FILTERS, "all", pad=18, colors=colors)
    text_at(d, (WHEN_X, 138), f"{len(EVENTS)} Einträge", F_S, DIM, "rs")
    rows(img, EVENTS, top=203, marker=True, whole=True, days=True)
    img.save(os.path.join(OUT, "log-c.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    variant_a()
    variant_b()
    variant_c()
