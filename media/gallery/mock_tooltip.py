"""Mock-ups of the member tooltip in Guildy's own floating style (UI/Widgets.lua W.FloatingPanel), opened at
the mouse over a row of the Hall of Fame's gear table (src/crop/04-fame-general.png, names made up).

    python media/gallery/mock_tooltip.py      # mock/tooltip-a/-b/-c.png

Needs Pillow; src/, icons/ and fonts/ are local only.
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "mock")
FONT = os.path.join(HERE, "fonts", "FRIZQT__.TTF")
ICONS = os.path.join(HERE, "icons")
BG_PATH = os.path.join(HERE, "src", "crop", "04-fame-general.png")

GROUND = (9, 8, 6)
GOLD_EDGE = (201, 163, 74)        # W.GOLD
GOLD = (255, 209, 0)              # GameFontNormal
WHITE, MUTED, DIM = (255, 255, 255), (154, 143, 120), (110, 102, 86)
GREEN, ORANGE = (64, 224, 64), (255, 154, 90)
PRIEST = (255, 255, 255)

F_XS = ImageFont.truetype(FONT, 12.4)
F_S = ImageFont.truetype(FONT, 13.8)
F_N = ImageFont.truetype(FONT, 15.2)
F_H = ImageFont.truetype(FONT, 20)

M = {
    "name": "Wanda Nordkamm", "line": "Stufe 60 Priesterin", "rank": "Offizier", "zone": "Winterquell",
    "online": True, "since": "13.11.2026 · 1 Tg.", "guildy": "v1.8.0", "note": "Heilerin · Raid Do",
    "officer": "Main", "ilvl": "49,3",
    "profs": [("trade_tailoring", "Schneiderei", 300, 300, "Mondstoff"), ("trade_engraving", "Verzauberkunst", 300, 300, None),
              ("spell_holy_sealofsacrifice", "Erste Hilfe", 300, 300, None), ("inv_misc_food_15", "Kochkunst", 225, 300, None)],
    "cds": [("Mondstoff", "in 2 Tg.", False), ("Transmutieren: Arkanit", "bereit", True)],
    "age": "Stand: vor 3 Std.",
    "hint": "Klick: Charakterseite · Rechtsklick: Menü · Shift-Klick: flüstern",
}


def icon(name, size):
    im = Image.open(os.path.join(ICONS, name + ".jpg")).convert("RGB")
    im = im.crop((4, 4, im.width - 4, im.height - 4))  # the game trims the icon border
    return im.resize((size, size), Image.LANCZOS)


def tw(font, text):
    return font.getlength(text)


class Canvas:
    """Records draw calls so the panel can be sized first and drawn second"""

    def __init__(self):
        self.ops, self.w, self.h = [], 0, 0

    def text(self, x, y, s, font, fill, anchor="la"):
        self.ops.append(("text", x, y, s, font, fill, anchor))
        right = x if anchor[0] == "r" else x + tw(font, s)
        self.w, self.h = max(self.w, right), max(self.h, y + font.size)

    def icon(self, x, y, name, size):
        self.ops.append(("icon", x, y, name, size))
        self.w, self.h = max(self.w, x + size), max(self.h, y + size)

    def rule(self, x0, x1, y, fill=(201, 163, 74, 70)):
        self.ops.append(("rule", x0, x1, y, fill))

    def bar(self, x, y, w, frac, fill):
        self.ops.append(("bar", x, y, w, frac, fill))

    def dot(self, x, y, r, fill):
        self.ops.append(("dot", x, y, r, fill))


def panel(img, x, y, w, h, ops):
    d = ImageDraw.Draw(img, "RGBA")
    for i, a in enumerate((0.55, 0.35, 0.2, 0.1), start=1):  # FLOAT_SHADOW rings
        d.rounded_rectangle((x - i * 2 + 1, y - i * 2 + 1, x + w + i * 2 + 1, y + h + i * 2 + 3), 6, fill=(0, 0, 0, int(a * 255)))
    d.rounded_rectangle((x, y, x + w, y + h), 5, fill=GROUND + (255,), outline=GOLD_EDGE, width=2)
    for op in ops:
        kind = op[0]
        if kind == "text":
            _, ox, oy, s, font, fill, anchor = op
            d.text((x + ox, y + oy), s, font=font, fill=fill, anchor=anchor)
        elif kind == "icon":
            _, ox, oy, name, size = op
            img.paste(icon(name, size), (int(x + ox), int(y + oy)))
            d.rectangle((x + ox - 1, y + oy - 1, x + ox + size, y + oy + size), outline=(0, 0, 0, 200))
        elif kind == "rule":
            _, x0, x1, oy, fill = op
            d.line((x + x0, y + oy, x + x1, y + oy), fill=fill, width=1)
        elif kind == "bar":
            _, ox, oy, bw, frac, fill = op
            d.rectangle((x + ox, y + oy, x + ox + bw, y + oy + 3), fill=(255, 255, 255, 22))
            d.rectangle((x + ox, y + oy, x + ox + bw * frac, y + oy + 3), fill=fill)
        elif kind == "dot":
            _, ox, oy, r, fill = op
            d.ellipse((x + ox - r, y + oy - r, x + ox + r, y + oy + r), fill=fill)


PAD = 14


def variant_a():
    """Quiet order: one column, muted labels, gold only for section heads, a hairline between groups"""
    c = Canvas()
    W = 340
    y = PAD
    c.text(PAD, y, M["name"], F_H, PRIEST); y += 25
    c.text(PAD, y, M["line"] + " · " + M["rank"], F_S, MUTED); y += 22
    c.dot(PAD + 4, y + 7, 4, GREEN)
    c.text(PAD + 14, y, "online", F_S, GREEN)
    c.text(PAD + 14 + tw(F_S, "online "), y, "· " + M["zone"], F_S, WHITE); y += 26
    c.rule(PAD, W - PAD, y); y += 10
    col = PAD + 112
    for label, value in (("Mitglied seit", M["since"]), ("Guildy", M["guildy"]), ("Notiz", M["note"]), ("Offiziersnotiz", M["officer"])):
        c.text(PAD, y, label, F_S, MUTED)
        c.text(col, y, value, F_S, WHITE)
        y += 20
    y += 8
    c.rule(PAD, W - PAD, y); y += 12
    c.text(PAD, y, "Berufe", F_S, GOLD); y += 22
    for ic, name, rank, mx, _ in M["profs"]:
        c.icon(PAD, y, ic, 18)
        c.text(PAD + 26, y + 1, name, F_S, WHITE)
        c.text(W - PAD, y + 1, f"{rank}/{mx}", F_S, WHITE if rank == mx else MUTED, "ra")
        y += 24
    y += 6
    c.text(PAD, y, "Cooldowns", F_S, GOLD)
    c.text(W - PAD, y + 1, M["age"], F_XS, DIM, "ra"); y += 22
    for name, left, ready in M["cds"]:
        c.text(PAD, y, name, F_S, WHITE)
        c.text(W - PAD, y, left, F_S, GREEN if ready else ORANGE, "ra")
        y += 20
    y += 8
    c.rule(PAD, W - PAD, y); y += 9
    c.text(PAD, y, "Klick: Charakterseite · Rechtsklick: Menü", F_XS, DIM); y += 16
    c.text(PAD, y, "Shift-Klick: flüstern", F_XS, DIM); y += 16
    return c, W, y + PAD - 4


def variant_b():
    """Two columns: who they are on the left, what they make on the right; wide and short"""
    c = Canvas()
    W = 560
    y = PAD
    c.text(PAD, y, M["name"], F_H, PRIEST)
    c.dot(W - PAD - tw(F_S, "online · " + M["zone"]) - 10, y + 12, 4, GREEN)
    c.text(W - PAD, y + 5, "online · " + M["zone"], F_S, GREEN, "ra"); y += 25
    c.text(PAD, y, M["line"] + " · " + M["rank"], F_S, MUTED)
    c.text(W - PAD, y, "Ø Gegenstandsstufe " + M["ilvl"], F_S, WHITE, "ra"); y += 24
    c.rule(PAD, W - PAD, y); y += 12
    top = y
    left_w = 250
    for label, value in (("Mitglied seit", M["since"]), ("Guildy", M["guildy"]), ("Notiz", M["note"]), ("Offiziersnotiz", M["officer"])):
        c.text(PAD, y, label, F_XS, MUTED); y += 15
        c.text(PAD, y, value, F_S, WHITE); y += 23
    left_bottom = y
    x2 = PAD + left_w + 16
    c.ops.append(("rule", x2 - 9, x2 - 8, top, (0, 0, 0, 0)))
    y = top
    c.text(x2, y, "Berufe", F_S, GOLD); y += 22
    for ic, name, rank, mx, _ in M["profs"]:
        c.icon(x2, y, ic, 18)
        c.text(x2 + 26, y + 1, name, F_S, WHITE)
        c.text(W - PAD, y + 1, f"{rank}/{mx}", F_S, WHITE if rank == mx else MUTED, "ra")
        c.bar(x2 + 26, y + 19, W - PAD - x2 - 26, rank / mx, (201, 163, 74, 200))
        y += 27
    y += 6
    c.text(x2, y, "Cooldowns", F_S, GOLD)
    c.text(W - PAD, y + 1, M["age"], F_XS, DIM, "ra"); y += 22
    for name, left, ready in M["cds"]:
        c.text(x2, y, name, F_S, WHITE)
        c.text(W - PAD, y, left, F_S, GREEN if ready else ORANGE, "ra")
        y += 20
    y = max(y, left_bottom) + 8
    c.ops.insert(0, ("rule", PAD + left_w + 4, PAD + left_w + 4, top, (0, 0, 0, 0)))
    # vertical divider between the columns
    for yy in range(int(top), int(y) - 4):
        c.ops.append(("rule", PAD + left_w + 4, PAD + left_w + 5, yy, (201, 163, 74, 40)))
    c.rule(PAD, W - PAD, y); y += 9
    c.text(PAD, y, M["hint"], F_XS, DIM); y += 16
    return c, W, y + PAD - 4


def variant_c():
    """Compact card: notes up front as the reason to hover, professions as a 2x2 grid of icon and level"""
    c = Canvas()
    W = 330
    y = PAD
    c.text(PAD, y, M["name"], F_H, PRIEST)
    c.text(W - PAD, y + 5, "online", F_S, GREEN, "ra"); y += 25
    c.text(PAD, y, M["line"], F_S, MUTED)
    c.text(W - PAD, y, M["zone"], F_S, WHITE, "ra"); y += 19
    c.text(PAD, y, M["rank"] + " · seit " + M["since"], F_S, MUTED)
    c.text(W - PAD, y, "Guildy " + M["guildy"], F_XS, DIM, "ra"); y += 26
    # the notes as a quiet inset
    c.ops.append(("box", PAD, y, W - PAD, y + 46))
    c.text(PAD + 10, y + 7, M["note"], F_N, WHITE)
    c.text(PAD + 10, y + 27, "Offiziersnotiz: " + M["officer"], F_XS, MUTED); y += 58
    cell = (W - 2 * PAD - 10) / 2
    for i, (ic, name, rank, mx, _) in enumerate(M["profs"]):
        cx = PAD + (i % 2) * (cell + 10)
        cy = y + (i // 2) * 30
        c.icon(cx, cy, ic, 24)
        c.text(cx + 32, cy - 1, name, F_XS, MUTED)
        c.text(cx + 32, cy + 13, f"{rank}", F_S, WHITE if rank == mx else (220, 210, 190))
        c.text(cx + 32 + tw(F_S, f"{rank}"), cy + 15, f" / {mx}", F_XS, DIM)
    y += 64
    c.rule(PAD, W - PAD, y); y += 10
    for name, left, ready in M["cds"]:
        c.text(PAD, y, name, F_S, WHITE)
        c.text(W - PAD, y, left, F_S, GREEN if ready else ORANGE, "ra")
        y += 20
    c.text(PAD, y + 2, M["age"], F_XS, DIM); y += 24
    c.text(PAD, y, "Klick: Seite · Rechts: Menü · Shift: flüstern", F_XS, DIM); y += 16
    return c, W, y + PAD - 4


def render(make, out, cursor=(330, 504)):
    bg = Image.open(BG_PATH).convert("RGB")
    canvas, w, h = make()
    # Guildy at the mouse: right and below the pointer, flipped up and kept on the screen when there is no room
    x, y = cursor[0] + 18, cursor[1] + 14
    if y + h > bg.height - 6:
        y = max(6, cursor[1] - h - 8)
    if x + w > bg.width - 6:
        x = cursor[0] - w - 12
    img = bg.copy()
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle((26, cursor[1] - 9, 1640, cursor[1] + 9), fill=(255, 209, 0, 22))  # the hovered row
    ops = []
    for op in canvas.ops:
        if op[0] == "box":
            _, x0, y0, x1, y1 = op
            ops.append(("rule", x0, x1, y0, (0, 0, 0, 0)))
            ImageDraw.Draw(img, "RGBA")
        ops.append(op)
    panel(img, x, y, w, h, [o for o in ops if o[0] != "box"])
    for op in canvas.ops:
        if op[0] == "box":
            _, x0, y0, x1, y1 = op
            d.rounded_rectangle((x + x0, y + y0, x + x1, y + y1), 3, fill=(255, 255, 255, 10), outline=(201, 163, 74, 60))
    # redraw text on top of the inset box
    panel_text = [o for o in canvas.ops if o[0] == "text"]
    dd = ImageDraw.Draw(img, "RGBA")
    for _, ox, oy, s, font, fill, anchor in panel_text:
        dd.text((x + ox, y + oy), s, font=font, fill=fill, anchor=anchor)
    # the pointer
    px, py = cursor
    dd.polygon([(px, py), (px, py + 20), (px + 5, py + 15), (px + 9, py + 23), (px + 12, py + 22), (px + 8, py + 14), (px + 14, py + 14)],
               fill=(240, 220, 160), outline=(40, 30, 10))
    img.save(out)
    print(out, w, "x", h)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    render(variant_a, os.path.join(OUT, "tooltip-a.png"))
    render(variant_b, os.path.join(OUT, "tooltip-b.png"))
    render(variant_c, os.path.join(OUT, "tooltip-c.png"))
