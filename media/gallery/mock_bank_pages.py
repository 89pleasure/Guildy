"""Mock-up of the Bank tab with two pages, "Bewegungen" (the ledger as it is) and "Inhalt" (the contents),
switched in the toolbar like "Levelphase | Endgame" on the overview. Drawn into two real screenshots of the
tab (src/live/bank-ledger.png, src/live/bank-contents.png): only the left end of the toolbar is new, built
from the screenshot's own buttons and background.

    python media/gallery/mock_bank_pages.py     ->  mock/pages-a.png (Bewegungen), mock/pages-b.png (Inhalt)
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "mock")
FONT = os.path.join(HERE, "fonts", "FRIZQT__.TTF")
LIVE = os.path.join(HERE, "src", "live")
F = ImageFont.truetype(FONT, 14.4)
GOLD, WHITE = (255, 209, 0), (255, 255, 255)
LEDGER = Image.open(os.path.join(LIVE, "bank-ledger.png")).convert("RGB")
# the toolbar's buttons in the ledger shot: dark = picked, red = not
BUTTON = {True: LEDGER.crop((174, 51, 266, 77)), False: LEDGER.crop((275, 51, 368, 77))}


def text_at(d, xy, s, fill, anchor="ls"):
    d.text((xy[0] + 1, xy[1] + 1), s, font=F, fill=(0, 0, 0), anchor=anchor)
    d.text(xy, s, font=F, fill=fill, anchor=anchor)


def button(img, x, y, label, picked):
    s, cap = BUTTON[picked], 9
    w = round(F.getlength(label)) + 34
    out = Image.new("RGB", (w, s.height))
    mid = s.crop((cap, 0, cap + 4, s.height))
    for px in range(cap, w - cap, mid.width):
        out.paste(mid, (px, 0))
    out.paste(s.crop((0, 0, cap, s.height)), (0, 0))
    out.paste(s.crop((s.width - cap, 0, s.width, s.height)), (w - cap, 0))
    img.paste(out, (x, y))
    text_at(ImageDraw.Draw(img), (x + w // 2, y + 18), label, WHITE if picked else GOLD, "ms")
    return x + w + 6


def toolbar(img, left, right, page):
    """Clears the toolbar from left to right with its own empty background, then: the two pages, the period."""
    strip = img.crop((right + 40, 44, right + 240, 84))
    for x in range(left, right, strip.width):
        img.paste(strip.crop((0, 0, min(strip.width, right - x), strip.height)), (x, 44))
    d = ImageDraw.Draw(img)
    x = button(img, left + 6, 51, "Bewegungen", page == 0)
    x = button(img, x, 51, "Inhalt", page == 1) + 22
    text_at(d, (x, 69), "Zeitraum", GOLD)
    x += round(F.getlength("Zeitraum")) + 14
    for i, label in enumerate(("7 Tage", "30 Tage", "90 Tage")):
        x = button(img, x, 51, label, i == 0)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    shots = ((LEDGER.copy(), 80, 640, 0, "pages-a"),
             (Image.open(os.path.join(LIVE, "bank-contents.png")).convert("RGB"), 76, 700, 1, "pages-b"))
    for img, left, right, page, name in shots:
        toolbar(img, left, right, page)
        path = os.path.join(OUT, name + ".png")
        img.save(path)
        print(path, img.size)


if __name__ == "__main__":
    main()
