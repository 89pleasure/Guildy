"""Mock-ups of the character page with the member's gear and a 3D model, drawn into the real reference
screenshot (src/crop/14-character.png): window frame, boxes and buttons are the game's own pixels, the
content is drawn with the game's font at the sizes measured in the screenshots.

    node --env-file=<.env> media/gallery/fetch_gear.mjs <character-slug>   # src/gear.json, items/, render.png
    python media/gallery/mock_character.py                                  # mock/character-a/-b/-c.png

The gear, its icons and the rendered model come from the Battle.net profile API (the model stands in for
the game's own model frame); name, notes and numbers are made up. Needs Pillow; src/ and fonts/ are local only.
"""
import json
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
CROP = os.path.join(SRC, "crop")
ICONS = os.path.join(HERE, "icons")
OUT = os.path.join(HERE, "mock")
FONT = os.path.join(HERE, "fonts", "FRIZQT__.TTF")

# the gold lines measured in 14-character.png: left card 43..418, right area 434..1596, rows 114..795
LEFT = (43, 114, 419, 796)
R0, R1, Y0, Y1, GAP = 434, 1597, 114, 796, 16
BG = (21, 19, 14)
TRACK = (36, 31, 22)
GOLD, WHITE, GREY, MUTED = (255, 209, 0), (255, 255, 255), (128, 128, 128), (154, 143, 120)
GREEN, ORANGE = (64, 224, 64), (255, 154, 90)
BAR_GOLD = (204, 168, 84)
WARRIOR = (198, 155, 109)

F_XS = ImageFont.truetype(FONT, 12.2)
F_S = ImageFont.truetype(FONT, 13.8)   # GameFont...Small
F_N = ImageFont.truetype(FONT, 16.3)   # GameFontNormal
F_L = ImageFont.truetype(FONT, 20)
F_H = ImageFont.truetype(FONT, 27.5)   # GameFontNormalHuge

QUALITY = {"POOR": (157, 157, 157), "COMMON": (255, 255, 255), "UNCOMMON": (30, 255, 0), "RARE": (0, 112, 221),
           "EPIC": (163, 53, 238), "LEGENDARY": (255, 128, 0)}
SLOT_DE = {"HEAD": "Kopf", "NECK": "Hals", "SHOULDER": "Schulter", "BACK": "Rücken", "CHEST": "Brust",
           "SHIRT": "Hemd", "TABARD": "Wappenrock", "WRIST": "Handgelenke", "HANDS": "Hände", "WAIST": "Taille",
           "LEGS": "Beine", "FEET": "Füße", "FINGER_1": "Finger", "FINGER_2": "Finger", "TRINKET_1": "Schmuck",
           "TRINKET_2": "Schmuck", "MAIN_HAND": "Waffenhand", "OFF_HAND": "Schildhand", "RANGED": "Distanz"}
# the game's character frame: left column, right column, weapons below
PAPERDOLL_L = ["HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "SHIRT", "TABARD", "WRIST"]
PAPERDOLL_R = ["HANDS", "WAIST", "LEGS", "FEET", "FINGER_1", "FINGER_2", "TRINKET_1", "TRINKET_2"]
WEAPONS = ["MAIN_HAND", "OFF_HAND", "RANGED"]
COSMETIC = {"SHIRT", "TABARD"}
# slots an enchanter can enchant in classic (head, legs and shoulders need reputation items)
ENCHANTABLE = {"BACK", "CHEST", "WRIST", "HANDS", "FEET", "MAIN_HAND", "OFF_HAND"}
RAID_READY = 56   # the guild's mark for "ready" (Overview's endgame view)

CHARACTER = {"name": "Edda Sternfall", "level": 60, "title": "„Schlächter“",
             "ident": "Nachtelf · weiblich · Kriegerin", "where": ("Offizier", "Silithus"),
             "since": "12.03.2026 · 8 Mon.", "note": "Main, Tank", "officer": "Raid-Kern"}
TWINKS = [("Kalle Kupferkessel", 34, "Magier", (63, 199, 235)), ("Mirra Moos", 22, "Priesterin", (255, 255, 255))]
PROFS = [("trade_mining.jpg", "Bergbau", 300, 300, None), ("trade_blacksmithing.jpg", "Schmiedekunst", 284, 300, "Waffen"),
         ("inv_misc_food_15.jpg", "Kochkunst", 175, 300, None),
         ("spell_holy_sealofsacrifice.jpg", "Erste Hilfe", 275, 300, None)]
# what the guild's recipe books know (Guildy's professions data): a better piece for a weak slot
CRAFTERS = {"WAIST": ("Gürtel des Rechtsprechers", 58, "Falk Donnerkeil", True),
            "NECK": ("Anhänger der Wacht", 54, "Runa Quellgrund", False)}


def de(value, digits=1):
    return ("%.*f" % (digits, value)).replace(".", ",")


def text_at(d, xy, s, font=F_S, fill=WHITE, anchor="ls"):
    d.text((xy[0] + 1, xy[1] + 1), s, font=font, fill=(0, 0, 0), anchor=anchor)
    d.text(xy, s, font=font, fill=fill, anchor=anchor)


def parts(d, x, y, pieces, font=F_S):
    for s, color in pieces:
        text_at(d, (round(x), y), s, font, color)
        x += font.getlength(s)
    return x


def fit(s, font, width):
    if font.getlength(s) <= width:
        return s
    while s and font.getlength(s + "…") > width:
        s = s[:-1]
    return s + "…"


def title(d, box, text, right=None):
    text_at(d, (box[0] + 13, box[1] + 23), text, F_N, GOLD)
    if right:
        text_at(d, (box[2] - 14, box[1] + 23), right, F_S, GREY, "rs")


def bar(d, x0, y, x1, share, color, h=8):
    d.rectangle((x0, y, x1 - 1, y + h - 1), fill=TRACK)
    w = round((x1 - x0) * max(0, min(1, share)))
    if w > 0:
        d.rectangle((x0, y, x0 + w - 1, y + h - 1), fill=color)


# --- data ---------------------------------------------------------------------------------------------

def load_gear():
    with open(os.path.join(SRC, "gear.json"), encoding="utf-8") as f:
        return {item["slot"]: item for item in json.load(f)}


def average_level(gear):
    levels = [it["level"] for slot, it in gear.items() if slot not in COSMETIC and it.get("level")]
    return sum(levels) / len(levels)


# --- the game's own pixels ----------------------------------------------------------------------------

class Kit:
    def __init__(self):
        src = Image.open(os.path.join(CROP, "14-character.png")).convert("RGB")
        self.src = src
        self.box_src = src.crop((430, 110, 1601, 206))        # the family box with its outer fringe
        self.texture = src.crop((700, 66, 1520, 104))         # bare window background (toolbar band)
        self.buttons = src.crop((50, 676, 412, 790))          # whisper, invite, officers' remove
        self.render = Image.open(os.path.join(SRC, "render.png")).convert("RGBA")
        bbox = self.render.getchannel("A").getbbox()
        self.figure = self.render.crop((bbox[0] - 10, bbox[1] - 6, bbox[2] + 10, bbox[3] + 4))

    def base(self):
        img = self.src.copy()
        tex, flip = self.texture, self.texture.transpose(Image.FLIP_TOP_BOTTOM)
        wide = Image.new("RGB", (tex.width * 2, tex.height))
        y, i = 106, 0
        while y < 806:
            row = flip if i % 2 == 0 else tex
            wide.paste(row, (0, 0))
            wide.paste(row.transpose(Image.FLIP_LEFT_RIGHT), (tex.width, 0))
            h = min(tex.height, 806 - y)
            img.paste(wide.crop((0, 0, 1604 - 31, h)), (31, y))
            y, i = y + tex.height, i + 1
        return img

    def box(self, img, x0, y0, x1, y1):
        """A box whose gold lines run along x0, y0, x1 - 1, y1 - 1."""
        s, c, f = self.box_src, 14, 4
        w, h = x1 - x0 + 2 * f, y1 - y0 + 2 * f
        out = Image.new("RGB", (w, h), BG)
        top, bottom = s.crop((c, 0, s.width - c, c)), s.crop((c, s.height - c, s.width - c, s.height))
        left, right = s.crop((0, c, c, s.height - c)), s.crop((s.width - c, c, s.width, s.height - c))
        for x in range(c, w - c, top.width):
            out.paste(top, (x, 0))
            out.paste(bottom, (x, h - c))
        for y in range(c, h - c, left.height):
            out.paste(left, (0, y))
            out.paste(right, (w - c, y))
        out.paste(Image.new("RGB", (w - 2 * c, h - 2 * c), BG), (c, c))
        out.paste(s.crop((0, 0, c, c)), (0, 0))
        out.paste(s.crop((s.width - c, 0, s.width, c)), (w - c, 0))
        out.paste(s.crop((0, s.height - c, c, s.height)), (0, h - c))
        out.paste(s.crop((s.width - c, s.height - c, s.width, s.height)), (w - c, h - c))
        img.paste(out, (x0 - f, y0 - f))
        return (x0, y0, x1, y1)

    def model(self, img, cx, bottom, height):
        """The character standing with its feet at bottom, centred on cx."""
        fig = self.figure
        w = round(fig.width * height / fig.height)
        fig = fig.resize((w, height), Image.LANCZOS)
        shadow = Image.new("RGBA", (round(w * 1.3), 26), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse((0, 0, shadow.width - 1, 25), fill=(0, 0, 0, 150))
        shadow = shadow.filter(ImageFilter.GaussianBlur(6))
        img.paste(shadow, (cx - shadow.width // 2, bottom - 16), shadow)
        img.paste(fig, (cx - w // 2, bottom - height), fig)


def stage(img, box, center=None):
    """The model's viewport: a soft light behind the figure, darker towards the edges."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    cx, cy = center or (w // 2, int(h * 0.42))
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse((cx - w * 0.55, cy - h * 0.48, cx + w * 0.55, cy + h * 0.48), fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(min(w, h) // 5))
    lit = Image.new("RGB", (w, h), (48, 41, 29))
    region = img.crop(box)
    img.paste(Image.composite(lit, region, glow.point(lambda v: v * 0.75)), (x0, y0))
    d = ImageDraw.Draw(img)
    text_at(d, (x1 - 10, y1 - 10), "Ziehen zum Drehen · Mausrad zum Zoomen", F_XS, MUTED, "rs")


def icon(img, item, x, y, size, pip=True, level=False):
    path = os.path.join(SRC, "items", "%d.jpg" % item["id"])
    try:
        pic = Image.open(path).convert("RGB").resize((size, size), Image.LANCZOS)
    except (OSError, ValueError):   # an icon the API did not deliver: the slot with its quality frame
        pic = Image.new("RGB", (size, size), (28, 24, 18))
    pic = pic.crop((round(size * 0.06), round(size * 0.06), size - round(size * 0.06), size - round(size * 0.06)))
    pic = pic.resize((size - 4, size - 4), Image.LANCZOS)
    d = ImageDraw.Draw(img)
    color = QUALITY.get(item["quality"], WHITE)
    d.rectangle((x, y, x + size - 1, y + size - 1), fill=(0, 0, 0))
    img.paste(pic, (x + 2, y + 2))
    d.rectangle((x, y, x + size - 1, y + size - 1), outline=color, width=2 if item["quality"] != "COMMON" else 1)
    if pip and item["enchants"]:
        r = max(4, size // 9)
        cx, cy = x + size - r - 3, y + r + 3
        d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=GREEN, outline=(0, 0, 0))
    if level and item.get("level") and item["slot"] not in COSMETIC:
        text_at(d, (x + size - 4, y + size - 4), str(item["level"]), F_XS, WHITE, "rs")


def empty_slot(img, x, y, size):
    d = ImageDraw.Draw(img)
    d.rectangle((x, y, x + size - 1, y + size - 1), fill=(10, 9, 7), outline=(60, 52, 38))


def level_ring(d, cx, cy, level, r=19):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(14, 11, 8), outline=(189, 148, 62), width=2)
    text_at(d, (cx, cy + 6), str(level), F_N, GOLD, "ms")


def identity(d, x, y, width, center=True, ring=None):
    """Name, title, race and class, rank and zone; returns the y below it."""
    a = "ms" if center else "ls"
    cx = x + width // 2 if center else x
    text_at(d, (cx, y), CHARACTER["name"], F_H, WARRIOR, a)
    text_at(d, (cx, y + 25), CHARACTER["title"], F_N, GOLD, a)
    text_at(d, (cx, y + 49), CHARACTER["ident"], F_S, WHITE, a)
    rank, zone = CHARACTER["where"]
    line = [(rank, MUTED), (" · ", MUTED), (zone, MUTED), (" · ", MUTED), ("online", GREEN)]
    lw = sum(F_S.getlength(s) for s, _ in line)
    parts(d, cx - lw / 2 if center else cx, y + 70, line)
    return y + 92


def notes(d, x, y):
    for label, value in (("Mitglied seit", CHARACTER["since"]), ("Notiz", CHARACTER["note"]),
                         ("Offiziersnotiz", CHARACTER["officer"])):
        parts(d, x, y, [(label + ": ", GOLD), (value, WHITE)])
        y += 17
    return y


def tiles(kit, img, x0, y0, x1, y1, gear, cols=4):
    """The statistic tiles: kills, quests, deaths, average item level (with the quality bar)."""
    d = ImageDraw.Draw(img)
    data = [("Kills", "15.112", "Platz 1 von 91"), ("Quests", "910", "Platz 2 von 91"), ("Tode", "67", None),
            ("Ø Itemlevel", de(average_level(gear)), "Platz 4 von 91")]
    rows = (len(data) + cols - 1) // cols
    tw = (x1 - x0 - GAP * (cols - 1)) // cols
    th = (y1 - y0 - GAP * (rows - 1)) // rows
    for i, (label, value, place) in enumerate(data):
        bx = x0 + (i % cols) * (tw + GAP)
        by = y0 + (i // cols) * (th + GAP)
        box = kit.box(img, bx, by, bx + tw, by + th)
        text_at(d, (box[0] + 14, box[1] + 20), label, F_S, MUTED)
        text_at(d, (box[0] + 14, box[1] + 50), value, F_H, WHITE)
        if place:
            text_at(d, (box[0] + 14, box[1] + 68), place, F_S, GOLD)
        if label.startswith("Ø"):
            counts = {}
            for slot, it in gear.items():
                if slot not in COSMETIC:
                    counts[it["quality"]] = counts.get(it["quality"], 0) + 1
            total, x = sum(counts.values()), box[0] + 14
            w = box[2] - box[0] - 28
            yb = box[3] - 14
            for q in ("EPIC", "RARE", "UNCOMMON", "COMMON", "POOR"):
                n = counts.get(q, 0)
                if n:
                    seg = round(w * n / total)
                    d.rectangle((x, yb, x + seg - 1, yb + 7), fill=QUALITY[q])
                    x += seg


def family(kit, img, box):
    d = ImageDraw.Draw(img)
    kit.box(img, *box)
    title(d, box, "Familie", "2 Twinks")
    y = box[1] + 48
    for name, level, cls, color in TWINKS:
        parts(d, box[0] + 14, y, [(name, color), ("  Stufe %d %s" % (level, cls), MUTED)])
        y += 20


def professions(kit, img, box, compact=False):
    d = ImageDraw.Draw(img)
    kit.box(img, *box)
    title(d, box, "Berufe")
    y = box[1] + 42
    for file, name, rank, cap, spec in PROFS:
        pic = Image.open(os.path.join(ICONS, file)).convert("RGB").resize((18, 18), Image.LANCZOS)
        img.paste(pic, (box[0] + 14, y))
        label = name + ("  " if spec else "")
        x = parts(d, box[0] + 40, y + 14, [(name, WHITE)] + ([("  " + spec, (143, 130, 104))] if spec else []))
        right = box[2] - 14
        bar_w = 110 if not compact else 80
        text_at(d, (right - bar_w - 10, y + 14), "%d/%d" % (rank, cap), F_S, WHITE, "rs")
        bar(d, right - bar_w, y + 6, right, rank / 300, BAR_GOLD, 8)
        y += 31


def tooltip(img, x, y, item):
    """The game's item tooltip, as it shows when the mouse rests on a slot."""
    lines = [(item["name"], F_N, QUALITY[item["quality"]]), ("Beim Anlegen gebunden", F_S, WHITE),
             (SLOT_DE[item["slot"]] + "\tPlatte", F_S, WHITE)]
    if item.get("armor"):
        lines.append((item["armor"], F_S, WHITE))
    for s in item["stats"]:
        lines.append((s, F_S, WHITE))
    for e in item["enchants"]:
        lines.append((e, F_S, GREEN))
    lines.append(("Gegenstandsstufe %d" % item["level"], F_S, GOLD))
    w = 18 + max(f.getlength(s.replace("\t", "      ")) for s, f, _ in lines)
    h = 16 + sum(22 if f is F_N else 18 for _, f, _ in lines)
    panel = Image.new("RGBA", (round(w), h), (6, 8, 18, 235))
    ImageDraw.Draw(panel).rectangle((0, 0, panel.width - 1, h - 1), outline=(150, 150, 150, 255))
    img.paste(panel, (x, y), panel)
    d = ImageDraw.Draw(img)
    yy = y + 22
    for s, f, color in lines:
        if "\t" in s:
            left, right = s.split("\t")
            text_at(d, (x + 9, yy), left, f, color)
            text_at(d, (x + panel.width - 9, yy), right, f, color, "rs")
        else:
            text_at(d, (x + 9, yy), s, f, color)
        yy += 22 if f is F_N else 18
    return panel.width


def left_card(kit, img, model_area=None, model_height=0):
    box = kit.box(img, *LEFT)
    img.paste(kit.buttons, (50, 676))
    return box


# --- variant A: readiness -----------------------------------------------------------------------------

def variant_a(kit, gear):
    img = kit.base()
    d = ImageDraw.Draw(img)
    box = left_card(kit, img)
    viewport = (box[0] + 6, box[1] + 6, box[2] - 6, box[1] + 340)
    stage(img, viewport)
    kit.model(img, (box[0] + box[2]) // 2, viewport[3] - 22, 300)
    level_ring(d, box[2] - 40, box[1] + 36, CHARACTER["level"])
    y = identity(d, box[0], viewport[3] + 32, box[2] - box[0])
    notes(d, box[0] + 18, y + 8)

    tiles(kit, img, R0, Y0, R1, Y0 + 92, gear)
    gx1 = 1180
    g = kit.box(img, R0, Y0 + 92 + GAP, gx1, Y1)
    avg = average_level(gear)
    missing = [s for s in ENCHANTABLE if s in gear and not gear[s]["enchants"]]
    title(d, g, "Ausrüstung", "Ø %s · bereit ab %d · %d ohne Verzauberung" % (de(avg), RAID_READY, len(missing)))
    rows = [s for s in PAPERDOLL_L + PAPERDOLL_R + WEAPONS if s not in COSMETIC and s in gear]
    weakest = sorted(rows, key=lambda s: gear[s]["level"])[:3]
    y, pitch = g[1] + 56, 29
    lo, hi = 25, 66
    bx0, bx1 = g[2] - 220, g[2] - 46
    text_at(d, (bx0, g[1] + 44), "Gegenstandsstufe", F_XS, MUTED)
    for i, slot in enumerate(rows):
        it = gear[slot]
        if i % 2 == 1:
            d.rectangle((g[0] + 6, y - 4, g[2] - 7, y + pitch - 5), fill=(27, 24, 18))
        text_at(d, (g[0] + 14, y + 15), SLOT_DE[slot], F_S, MUTED)
        icon(img, it, g[0] + 108, y - 1, 22, pip=False)
        name_w = bx0 - (g[0] + 140) - 12
        x = parts(d, g[0] + 140, y + 15, [(fit(it["name"], F_S, name_w * 0.62), QUALITY[it["quality"]])])
        if it["enchants"]:
            parts(d, x + 10, y + 15, [(fit(it["enchants"][0], F_XS, name_w * 0.38), GREEN)], F_XS)
        elif slot in ENCHANTABLE:
            parts(d, x + 10, y + 15, [("keine Verzauberung", ORANGE)], F_XS)
        share = (it["level"] - lo) / (hi - lo)
        bar(d, bx0, y + 7, bx1, share, QUALITY[it["quality"]], 8)
        tick = bx0 + round((bx1 - bx0) * (RAID_READY - lo) / (hi - lo))
        d.line((tick, y + 3, tick, y + 18), fill=GOLD, width=1)
        text_at(d, (g[2] - 14, y + 15), str(it["level"]), F_S, WHITE if it["level"] >= RAID_READY else GREY, "rs")
        y += pitch
    rx0 = gx1 + GAP
    top = Y0 + 92 + GAP
    family(kit, img, (rx0, top, R1, top + 96))
    # what the guild's recipe books could make for the weak slots, and who makes it
    up = kit.box(img, rx0, top + 96 + GAP, R1, top + 96 + GAP + 148)
    title(d, up, "Upgrades aus der Gilde")
    y = up[1] + 50
    for slot, (item, level, who, online) in CRAFTERS.items():
        parts(d, up[0] + 14, y, [(SLOT_DE[slot] + "  ", MUTED), (item, QUALITY["RARE"])])
        text_at(d, (up[2] - 14, y), "%d auf %d" % (gear[slot]["level"], level), F_S, WHITE, "rs")
        parts(d, up[0] + 14, y + 18, [(who, WHITE), ("  Schmied", MUTED),
                                      ("  online" if online else "  offline", GREEN if online else GREY)], F_XS)
        y += 44
    professions(kit, img, (rx0, top + 96 + GAP * 2 + 148, R1, Y1), compact=True)
    return img


# --- variant B: the model beside the list -------------------------------------------------------------

def variant_b(kit, gear):
    img = kit.base()
    d = ImageDraw.Draw(img)
    box = left_card(kit, img)
    y = identity(d, box[0], box[1] + 40, box[2] - box[0])
    viewport = (box[0] + 6, y + 6, box[2] - 6, 668)
    stage(img, viewport, ((viewport[2] - viewport[0]) // 2, int((viewport[3] - viewport[1]) * 0.5)))
    kit.model(img, (box[0] + box[2]) // 2, viewport[3] - 26, viewport[3] - viewport[1] - 60)
    level_ring(d, box[2] - 40, box[1] + 36, CHARACTER["level"])

    gx1 = 1112
    g = kit.box(img, R0, Y0, gx1, Y1)
    avg = average_level(gear)
    title(d, g, "Ausrüstung", "Ø Itemlevel %s" % de(avg))
    col_w = (g[2] - g[0] - 28 - GAP) // 2
    for c, column in enumerate((PAPERDOLL_L, PAPERDOLL_R)):
        x = g[0] + 14 + c * (col_w + GAP)
        y = g[1] + 44
        for slot in column:
            it = gear.get(slot)
            if it:
                icon(img, it, x, y, 36)
                text_at(d, (x + 46, y + 15), fit(it["name"], F_S, col_w - 80), F_S, QUALITY[it["quality"]])
                second = it["enchants"][0] if it["enchants"] else SLOT_DE[slot]
                text_at(d, (x + 46, y + 32), fit(second, F_XS, col_w - 80), F_XS, GREEN if it["enchants"] else MUTED)
                if slot not in COSMETIC:
                    text_at(d, (x + col_w, y + 15), str(it["level"]), F_S, GREY, "rs")
            else:
                empty_slot(img, x, y, 36)
                text_at(d, (x + 46, y + 22), SLOT_DE[slot], F_S, MUTED)
            y += 60
    y = g[3] - 74
    d.line((g[0] + 14, y, g[2] - 14, y), fill=(70, 60, 40))
    y += 16
    ww = (g[2] - g[0] - 28 - GAP * 2) // 3
    for i, slot in enumerate(WEAPONS):
        it = gear[slot]
        x = g[0] + 14 + i * (ww + GAP)
        icon(img, it, x, y, 36)
        text_at(d, (x + 46, y + 15), fit(it["name"], F_S, ww - 50), F_S, QUALITY[it["quality"]])
        text_at(d, (x + 46, y + 32), "%s · %d" % (SLOT_DE[slot], it["level"]), F_XS, MUTED)

    rx0 = gx1 + GAP
    tiles(kit, img, rx0, Y0, R1, Y0 + 220, gear, cols=2)
    family(kit, img, (rx0, Y0 + 220 + GAP, R1, Y0 + 220 + GAP + 100))
    professions(kit, img, (rx0, Y0 + 220 + GAP * 2 + 100, R1, Y1), compact=True)
    return img


# --- variant C: the character sheet -------------------------------------------------------------------

def variant_c(kit, gear):
    img = kit.base()
    d = ImageDraw.Draw(img)
    box = left_card(kit, img)
    level_ring(d, (box[0] + box[2]) // 2, box[1] + 44, CHARACTER["level"], r=24)
    y = identity(d, box[0], box[1] + 108, box[2] - box[0])
    y = notes(d, box[0] + 18, y + 12)
    text_at(d, (box[0] + 18, y + 22), "Titel", F_S, GOLD)
    text_at(d, (box[0] + 18, y + 42), "Schlächter · Platz 1 bei den Kills", F_S, WHITE)
    text_at(d, (box[0] + 18, y + 60), "Wandersmann · Platz 2 bei den Quests", F_S, WHITE)

    gx1 = 1112
    g = kit.box(img, R0, Y0, gx1, Y1)
    avg = average_level(gear)
    title(d, g, "Ausrüstung", "Ø Itemlevel %s" % de(avg))
    size, pitch = 46, 60
    top = g[1] + 50
    lx, rx = g[0] + 18, g[2] - 18 - size
    viewport = (lx + size + 14, g[1] + 40, rx - 14, g[3] - 96)
    stage(img, viewport)
    kit.model(img, (g[0] + g[2]) // 2, viewport[3] - 20, viewport[3] - viewport[1] - 50)
    for column, x in ((PAPERDOLL_L, lx), (PAPERDOLL_R, rx)):
        for i, slot in enumerate(column):
            it = gear.get(slot)
            if it:
                icon(img, it, x, top + i * pitch, size, level=True)
            else:
                empty_slot(img, x, top + i * pitch, size)
    wy = g[3] - 74
    wx = (g[0] + g[2]) // 2 - (3 * size + 2 * 16) // 2
    for i, slot in enumerate(WEAPONS):
        icon(img, gear[slot], wx + i * (size + 16), wy, size, level=True)
    # the mouse rests on the gloves: the game's tooltip, with the enchantment
    hx, hy = rx, top
    d.rectangle((hx - 2, hy - 2, hx + size + 1, hy + size + 1), outline=GOLD, width=2)
    tw = tooltip(img, 0, -1000, gear["HANDS"])   # measure
    img_tip_x = hx - tw - 10
    tooltip(img, img_tip_x, hy, gear["HANDS"])

    rx0 = gx1 + GAP
    tiles(kit, img, rx0, Y0, R1, Y0 + 220, gear, cols=2)
    family(kit, img, (rx0, Y0 + 220 + GAP, R1, Y0 + 220 + GAP + 100))
    professions(kit, img, (rx0, Y0 + 220 + GAP * 2 + 100, R1, Y1), compact=True)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    kit, gear = Kit(), load_gear()
    for name, fn in (("a", variant_a), ("b", variant_b), ("c", variant_c)):
        fn(kit, gear).save(os.path.join(OUT, "character-%s.png" % name))
        print("mock/character-%s.png" % name)


if __name__ == "__main__":
    main()
