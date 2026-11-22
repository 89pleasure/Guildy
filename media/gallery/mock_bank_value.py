"""Mock-up of the Bank tab's "Inhalt" page with the gold and, from a price addon (Auctionator or TSM, opt-in),
what the items would fetch at the auction house and the total. Drawn into mock/pages-b.png (the real contents
page with the page buttons, see mock_bank_pages.py): the contents box moves down two rows, figures in their
place.

    python media/gallery/mock_bank_value.py    ->  mock/value-a.png (with a price addon), value-b.png (without)
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "mock")
FONT = os.path.join(HERE, "fonts", "FRIZQT__.TTF")
BASE = os.path.join(OUT, "pages-b.png")

F_S = ImageFont.truetype(FONT, 14.2)
F_N = ImageFont.truetype(FONT, 16.6)
F_H = ImageFont.truetype(FONT, 27)
GOLD, WHITE, GREY = (255, 209, 0), (255, 255, 255), (150, 142, 128)
BG, WINDOW = (21, 18, 13), None
X0, X1, TOP, SHIFT = 13, 1107, 88, 112

# unit price at the auction house, copper (made up), per row of the list in the screenshot
ROWS = [("Gekochte Muscheln", 50, 110), ("Kaldorei-Spinnenkebab", 30, 85), ("Trockene Schweinerippchen", 10, 60),
        ("Scharfe Muscheln nach Goblin-Art", 9, 240)]
GOLD_IN_BANK = 5 * 10000 + 64 * 100
ITEMS_VALUE = sum(n * p for _, n, p in ROWS)


def text_at(d, xy, s, font=F_S, fill=WHITE, anchor="ls"):
    d.text((xy[0] + 1, xy[1] + 1), s, font=font, fill=(0, 0, 0), anchor=anchor)
    d.text(xy, s, font=font, fill=fill, anchor=anchor)


def coin(img, x, y, size, kind):
    fill, rim, light = {"g": ((238, 186, 40), (122, 78, 8), (255, 236, 150)),
                        "s": ((196, 198, 204), (84, 86, 94), (246, 246, 250)),
                        "c": ((200, 112, 52), (98, 48, 18), (240, 172, 120))}[kind]
    k = 6
    big = Image.new("RGBA", (size * k, size * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.ellipse((0, 0, size * k - 1, size * k - 1), fill=rim + (255,))
    d.ellipse((k, k, size * k - k - 1, size * k - k - 1), fill=fill + (255,))
    d.ellipse((size * k * 0.24, size * k * 0.18, size * k * 0.56, size * k * 0.46), fill=light + (255,))
    small = big.resize((size, size), Image.LANCZOS)
    img.paste(small, (round(x), round(y)), small)


def money(img, x, y, copper, font=F_S, color=WHITE, anchor="l", measure=False):
    """Gold, silver and copper with coins behind the numbers, baseline y; anchor l, r or m."""
    size = 13 if font is F_S else 24
    gap = 3 if font is F_S else 5
    pieces = [(str(v), k) for v, k in ((copper // 10000, "g"), (copper // 100 % 100, "s"), (copper % 100, "c")) if v]
    width = sum(font.getlength(s) + gap + size for s, _ in pieces) + (len(pieces) - 1) * (gap + 3)
    if measure:
        return width
    x -= {"l": 0, "r": width, "m": width / 2}[anchor]
    d = ImageDraw.Draw(img)
    for s, kind in pieces:
        text_at(d, (round(x), y), s, font, color)
        x += font.getlength(s) + gap
        coin(img, x, y - size + (1 if font is F_S else 2), size, kind)
        x += size + gap + 3


def box(img, x0, y0, x1, y1):
    d = ImageDraw.Draw(img)
    d.rectangle((x0 - 1, y0 - 1, x1 + 1, y1 + 1), outline=(27, 24, 21))
    d.rectangle((x0, y0, x1, y1), outline=(60, 48, 25))
    d.rectangle((x0 + 1, y0 + 1, x1 - 1, y1 - 1), outline=(59, 48, 25))
    d.line((x0, y0, x1, y0), fill=(100, 80, 39))
    d.line((x0 + 1, y0 + 1, x1 - 1, y0 + 1), fill=(45, 38, 24))
    d.rectangle((x0 + 2, y0 + 2, x1 - 2, y1 - 2), fill=BG, outline=(11, 10, 7))
    d.line((x0 + 3, y0 + 3, x1 - 3, y0 + 3), fill=(17, 15, 11))


def tile(img, x0, x1, value, label, color=GOLD, hint=None):
    box(img, x0, TOP, x1, TOP + SHIFT - 16)
    d = ImageDraw.Draw(img)
    cx, cy = (x0 + x1) / 2, TOP + 52
    if isinstance(value, int):
        money(img, cx, cy, value, F_H, color, "m")
    else:
        text_at(d, (cx, cy), value[0], F_H, color, "ms")
        text_at(d, (cx + F_H.getlength(value[0]) / 2 + 2, cy), value[1], F_N, GREY, "ls")
    text_at(d, (cx, TOP + 78), label, F_S, GREY, "ms")
    if hint:
        text_at(d, (x1 - 10, TOP + 20), hint, F_S, (110, 104, 90), "rs")


def build(prices):
    img = Image.open(BASE).convert("RGB")
    window = img.getpixel((1116, 400))
    # the contents box two rows lower (the empty part of its list goes), the free room the window's again
    moved = img.crop((X0 - 3, TOP - 2, X1 + 4, 768 - SHIFT - 2))
    ImageDraw.Draw(img).rectangle((X0 - 6, TOP - 4, X1 + 6, TOP + SHIFT), fill=window)
    img.paste(moved, (X0 - 3, TOP - 2 + SHIFT))
    used = ("7", " / 98")
    if prices:
        w = (X1 - X0 - 3 * 16) / 4
        xs = [round(X0 + i * (w + 16)) for i in range(4)]
        tile(img, xs[0], xs[0] + round(w), GOLD_IN_BANK, "Gold in der Bank")
        tile(img, xs[1], xs[1] + round(w), ITEMS_VALUE, "Gegenstände · Auktionshaus", WHITE, "Auctionator")
        tile(img, xs[2], xs[2] + round(w), GOLD_IN_BANK + ITEMS_VALUE, "Gesamtwert der Bank")
        tile(img, xs[3], X1, used, "Plätze belegt · 1 Fach", WHITE)
    else:
        w = (X1 - X0 - 16) / 2
        tile(img, X0, round(X0 + w), GOLD_IN_BANK, "Gold in der Bank")
        tile(img, round(X0 + w + 16), X1, used, "Plätze belegt · 1 Fach", WHITE)
    d = ImageDraw.Draw(img)
    if prices:
        # a column "AH-Wert" in the list, between the tabs and the movement
        col = 900
        text_at(d, (col, 187 + SHIFT), "AH-Wert", F_S, GREY, "rs")
        for i, (_, n, price) in enumerate(ROWS):
            money(img, col, 221 + SHIFT + i * 37, n * price, F_S, WHITE, "r")
        # where it lies: the value of the picked item
        x = 1138 + F_S.getlength("50 Stück in 3 Stapeln") + 14
        text_at(d, (x, 149), "·  AH-Wert", F_S, GREY)
        money(img, x + F_S.getlength("·  AH-Wert") + 8, 149, ROWS[0][1] * ROWS[0][2], F_S, WHITE)
    return img


def main():
    for name, prices in (("value-a", True), ("value-b", False)):
        img = build(prices)
        path = os.path.join(OUT, name + ".png")
        img.save(path)
        print(path, img.size)


if __name__ == "__main__":
    main()
