"""Mock-ups of guild events in Guildy: WoW's own calendar (C_Calendar) read, answered and created from the guild
window. Drawn into the real reference screenshots with the widgets of mock_blacklist.py (cut from the game).

    python media/gallery/mock_events.py  ->  mock/events-a.png  own tab: list on the left, create form docked right
                                             mock/events-b.png  own tab: agenda on the left, the picked event
                                                                with its sign-ups on the right
                                             mock/events-b-form.png  B after "Neues Ereignis": the form in place
                                                                of the event on the right (the chosen design)
                                             mock/events-c.png  no tab: a box in Overview, the form as a dialog

Names are made up like Core/Anon.lua. Needs Pillow; src/ and fonts/ are local only.
"""
import os

from PIL import Image, ImageDraw

import mock_blacklist as mb
from mock_blacklist import (BG, BX0, BX1, BY0, BY1, CLASS, DIM, F_B, F_L, F_N, F_Q, F_S, F_XS, GOLD, GREY, LINE,
                            PITCH, STRIPE, WHITE, check, clear_box, clear_toolbar, dropdown, fit, gold_box, red_button,
                            scrollbar, search_box, segmented, tabs, text_at)

OUT = mb.OUT
TAB_LABELS = ["Chat", "Mitglieder", "Übersicht", "Ruhmeshalle", "Berufe", "Info & Log", "Ränge", "Bank",
              "Ereignisse"]

# the five event types of Blizzard's create window, with a color each (no picture: Forever's list is empty)
TYPES = {
    "raid": ("Schlachtzug", (255, 140, 40)),
    "dungeon": ("Dungeon", (90, 160, 255)),
    "pvp": ("PvP", (255, 76, 64)),
    "meeting": ("Treffen", (110, 210, 110)),
    "other": ("Sonstiges", (176, 168, 150)),
}
TYPE_ORDER = ["raid", "dungeon", "pvp", "meeting", "other"]

# Blizzard's answer states, as the calendar names them
OK, MAYBE, NO = (64, 224, 64), (255, 210, 60), (230, 80, 60)
STATUS = {
    "signed": ("Angemeldet", OK),
    "tentative": ("Vorläufig", MAYBE),
    "declined": ("Abgelehnt", NO),
    "invited": ("Nicht angemeldet", GREY),
}

# day, weekday, time, title, type, yes, maybe, no, mine, by, locked, soon
EVENTS = [
    ("27.11.", "Fr", "20:00", "Geschmolzener Kern – erster Versuch", "raid", 12, 3, 2, "invited", "Alva Abendrot",
     False, "heute"),
    ("28.11.", "Sa", "15:00", "Brunnen des Grauens mit den Twinks", "dungeon", 4, 1, 0, "signed", "Pell Quellgrund",
     False, None),
    ("29.11.", "So", "19:30", "Gildentreffen in Eisenschmiede", "meeting", 18, 4, 3, "tentative", "Alva Abendrot",
     False, None),
    ("01.12.", "Di", "21:00", "Tarrens Mühle gegen Süderstade", "pvp", 6, 2, 5, "declined", "Silas Birkfeld", False,
     None),
    ("03.12.", "Do", "20:00", "Onyxias Hort", "raid", 9, 2, 1, "invited", "Alva Abendrot", True, None),
    ("06.12.", "So", "18:00", "Angelwettbewerb am Schlingendorn", "other", 7, 0, 0, "signed", "Tara Taubnessel",
     False, None),
]

DESC = "Wir treffen uns am Eingang im Schwarzfels. Feuerresistenz mitbringen, Wasser und Tränke sind im Bank-Tab 2."

# who answered event 0: name, class, state
ROSTER = [
    ("Alva Abendrot", "priest", "signed"), ("Krag Eisenfaust", "warrior", "signed"),
    ("Bodo Felsbart", "warrior", "signed"), ("Silas Birkfeld", "mage", "signed"),
    ("Tara Taubnessel", "druid", "signed"), ("Nika Quellgrund", "warlock", "signed"),
    ("Greta Donnerkeil", "hunter", "signed"), ("Ylva Immergruen", "priest", "signed"),
    ("Pell Quellgrund", "rogue", "signed"), ("Xara Sturmruf", "shaman", "signed"),
    ("Cord Nebelstein", "paladin", "signed"), ("Finn Moorweide", "mage", "signed"),
    ("Orla Nordkamm", "rogue", "tentative"), ("Imke Fuchsbau", "hunter", "tentative"),
    ("Jorin Zunderfels", "warlock", "tentative"),
    ("Dana Glutpfad", "paladin", "declined"), ("Calla Taubnessel", "druid", "declined"),
]
CLASS_DE = {"warrior": "Krieger", "priest": "Priester", "shaman": "Schamane", "hunter": "Jäger", "rogue": "Schurke",
            "paladin": "Paladin", "druid": "Druide", "warlock": "Hexenmeister", "mage": "Magier"}


# --- small drawn marks (no glyph icons) ----------------------------------------------------------------------
def tick(d, x, y, color=OK):
    for dx, fill in ((1, (0, 0, 0)), (0, color)):
        d.line((x + dx, y - 5 + dx, x + 3 + dx, y - 1 + dx, x + 9 + dx, y - 10 + dx), fill=fill, width=2)


def cross(d, x, y, color=NO):
    mb.remove_x(d, x + 4, y, color)


def dot(d, x, y, color, r=4):
    d.ellipse((x - r + 1, y - r + 1, x + r + 1, y + r + 1), fill=(0, 0, 0))
    d.ellipse((x - r, y - r, x + r, y + r), fill=color)


def type_mark(d, x, y, t, size=5):
    color = TYPES[t][1]
    d.rectangle((x + 1, y - size - 3, x + 2 * size + 1, y + size - 3 + 1), fill=(0, 0, 0))
    d.rectangle((x, y - size - 4, x + 2 * size, y + size - 4), fill=color)


def counts(d, x, y, yes, maybe, no, font=F_S):
    """12 [tick]  3 ?  2 [x], numbers colored like the states."""
    for n, kind in ((yes, "y"), (maybe, "m"), (no, "n")):
        s = str(n)
        text_at(d, (x, y), s, font, {"y": OK, "m": MAYBE, "n": NO}[kind] if n else DIM)
        x += font.getlength(s) + 4
        if kind == "y":
            tick(d, x, y - 2, OK if n else DIM)
            x += 18
        elif kind == "m":
            text_at(d, (x, y), "?", font, MAYBE if n else DIM)
            x += 16
        else:
            cross(d, x, y, NO if n else DIM)
            x += 18
    return x


def lock_mark(d, x, y, color=GREY):
    """A small drawn padlock."""
    d.arc((x + 2, y - 15, x + 10, y - 5), 180, 360, fill=color, width=2)
    d.rectangle((x, y - 9, x + 12, y), fill=color)


def answer_buttons(img, x, y, mine, small=False):
    """Anmelden / Vorläufig / Absagen: red buttons; the current answer is shown as text instead of its button."""
    d = ImageDraw.Draw(img)
    labels = [("signed", "Anmelden"), ("tentative", "Vorläufig"), ("declined", "Absagen")]
    w = 92 if small else 110
    for key, label in labels:
        if key == mine:
            text_at(d, (x + w / 2, y + 18), STATUS[key][0], F_B, STATUS[key][1], "ms")
        else:
            red_button(img, x, y, w, label)
        x += w + 6
    return x


def base(src=None):
    img = (src or mb._members).copy()
    clear_toolbar(img)
    tabs(img, TAB_LABELS, "Ereignisse")
    return img


def text_field(img, x, y, w, value=None, hint=""):
    return search_box(img, x, y, w, hint, typed=value)


def area(img, box, text, hint=False):
    """A multi-line edit box: the search box's edge, stretched in both directions."""
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    d.rectangle(box, fill=(8, 7, 5))
    d.rectangle(box, outline=(96, 90, 80))
    d.rectangle((x0 + 1, y0 + 1, x1 - 1, y1 - 1), outline=(30, 28, 24))
    words, line, ty = text.split(), "", y0 + 22
    for word in words:
        if F_S.getlength(line + " " + word) > (x1 - x0 - 22):
            text_at(d, (x0 + 11, ty), line.strip(), F_S, (120, 114, 100) if hint else WHITE)
            line, ty = "", ty + 20
        line += " " + word
    text_at(d, (x0 + 11, ty), line.strip(), F_S, (120, 114, 100) if hint else WHITE)


def form(img, x0, y0, x1, title=True, compact=False):
    """Guildy's own create form: Blizzard's fields plus 'announce in guild chat'. Returns the bottom y."""
    d = ImageDraw.Draw(img)
    w = x1 - x0
    y = y0
    if title:
        text_at(d, (x0, y + 22), "Neues Gilden-Ereignis", F_N, GOLD)
        y += 38
    text_at(d, (x0, y + 18), "Name", F_S, GREY)
    text_field(img, x0 + 110, y, w - 110, "Geschmolzener Kern – zweiter Versuch")
    y += 40
    text_at(d, (x0, y + 18), "Art", F_S, GREY)
    segmented(img, x0 + 110, y + 1, [(t, TYPES[t][0]) for t in TYPE_ORDER], "raid", pad=14 if compact else 18)
    y += 40
    text_at(d, (x0, y + 18), "Wann", F_S, GREY)
    xx = dropdown(img, x0 + 110, y, 150, "Fr 04.12.") + 8
    xx = dropdown(img, xx, y, 70, "20") + 4
    text_at(d, (xx + 2, y + 18), ":", F_B, WHITE)
    xx = dropdown(img, xx + 10, y, 70, "00") + 12
    text_at(d, (xx, y + 18), "in 12 Tagen", F_S, DIM)
    y += 42
    text_at(d, (x0, y + 18), "Beschreibung", F_S, GREY)
    area(img, (x0 + 110, y, x1, y + (78 if compact else 92)), DESC)
    y += (78 if compact else 92) + 14
    xx = check(img, x0 + 108, y, "Im Gildenchat ankündigen", True)
    if not compact:
        y += 30
        check(img, x0 + 108, y, "Ereignis sperren")
        text_at(d, (x0 + 108 + 30 + F_S.getlength("Ereignis sperren") + 12, y + 18), "keine Antworten mehr möglich",
                F_XS, DIM)
    else:
        check(img, xx + 26, y, "Sperren")
    y += 34
    text_at(d, (x0 + 110, y + 14), "Erinnerung 30 Minuten vorher im Gildenchat und bei Guildy-Nutzern", F_XS, DIM)
    y += 30
    red_button(img, x1 - 118, y, 118, "Erstellen")
    text_at(d, (x1 - 136, y + 18), "Abbrechen", F_S, GREY, "rs")
    return y + 30


# --- A: list + docked form ------------------------------------------------------------------------------------
def variant_a():
    img = base()
    d = ImageDraw.Draw(img)
    items = [("all", f"Alle {len(EVENTS)}")] + [(t, TYPES[t][0]) for t in TYPE_ORDER]
    x = segmented(img, 118, 77, items, "all") + 18
    check(img, x, 77, "Nur offene Antworten")
    text_at(d, (1517, 95), "aus dem Kalender · 6 kommende", F_S, DIM, "rs")
    red_button(img, 1535, 77, 118, "Neues Ereignis")
    clear_box(img)
    split = 1080
    d.line((split, BY0 + 6, split, BY1 - 6), fill=LINE)
    cols = [("Wann", 52), ("Ereignis", 210), ("Antworten", 610), ("Du", 760)]
    for label, cx in cols:
        text_at(d, (cx, 136), label, F_B, GOLD)
    y = 172
    for i, e in enumerate(EVENTS):
        day, wd, time, title, t, yes, maybe, no, mine, by, locked, soon = e
        r0, r1 = y - 20, y + 22
        if i % 2 == 1:
            d.rectangle((BX0 + 3, r0, split - 4, r1), fill=STRIPE)
        if i == 0:
            d.rectangle((BX0 + 3, r0, split - 4, r1), outline=(120, 96, 40))
        text_at(d, (52, y), f"{wd} {day}", F_S, WHITE)
        text_at(d, (52, y + 18), time + (" · heute" if soon else ""), F_XS, GOLD if soon else GREY)
        type_mark(d, 210, y, t)
        text_at(d, (228, y), fit(title, F_S, 360), F_S, WHITE)
        tx = 228
        text_at(d, (tx, y + 18), TYPES[t][0], F_XS, TYPES[t][1])
        tx += F_XS.getlength(TYPES[t][0])
        text_at(d, (tx, y + 18), f" · von {by}", F_XS, GREY)
        if locked:
            lock_mark(d, 228 + F_S.getlength(title) + 10, y, GREY)
        counts(d, 610, y + 6, yes, maybe, no)
        if locked:
            text_at(d, (760, y + 6), "gesperrt · " + STATUS[mine][0], F_S, DIM)
        elif mine in ("invited",) or i == 0:
            answer_buttons(img, 760, y - 11, mine, small=True)
        else:
            text_at(d, (760, y + 6), STATUS[mine][0], F_S, STATUS[mine][1])
            text_at(d, (900, y + 6), "ändern", F_XS, GREY)
        y += 52
    # past events, folded
    y += 4
    text_at(d, (52, y), "Vergangene · 4", F_S, GREY)
    d.line((52 + F_S.getlength("Vergangene · 4") + 10, y - 5, split - 20, y - 5), fill=LINE)
    # the reminder as Guildy users see it in chat
    cy = 690
    text_at(d, (52, cy - 8), "Erinnerung im Chat, 30 Minuten vorher", F_XS, DIM)
    d.rectangle((50, cy, split - 20, cy + 60), fill=(10, 9, 7))
    parts = [("[Gilde] ", (64, 255, 64)), ("[Alva Abendrot]: ", (64, 255, 64)),
             ("[Guildy] Geschmolzener Kern – erster Versuch beginnt in 30 Min. (20:00)", (64, 255, 64))]
    x = 60
    for s, c in parts:
        text_at(d, (x, cy + 22), s, F_S, c)
        x += F_S.getlength(s)
    parts = [("[Guildy] ", (212, 160, 23)), ("Geschmolzener Kern beginnt in 30 Min. · du bist ", WHITE),
             ("nicht angemeldet", GREY), (" · Anmelden", GOLD)]
    x = 60
    for s, c in parts:
        text_at(d, (x, cy + 46), s, F_S, c)
        x += F_S.getlength(s)
    # docked form
    form(img, split + 22, 128, BX1 - 22, compact=True)
    scrollbar(img, split - 26, 148, 792)
    img.save(os.path.join(OUT, "events-a.png"))


# --- B: agenda + detail ---------------------------------------------------------------------------------------
def variant_b(with_form=False):
    img = base()
    d = ImageDraw.Draw(img)
    x = segmented(img, 118, 77, [("next", "Kommende 6"), ("past", "Vergangene")], "next") + 18
    check(img, x, 77, "Nur meine offenen")
    red_button(img, 1535, 77, 118, "Neues Ereignis")
    clear_box(img)
    split = 560
    d.line((split, BY0 + 6, split, BY1 - 6), fill=LINE)
    y = 142
    picked = 0
    groups = [("Diese Woche", EVENTS[:3]), ("Nächste Woche", EVENTS[3:])]
    idx = 0
    for head, rows in groups:
        text_at(d, (58, y), head, F_S, GOLD)
        d.line((58 + F_S.getlength(head) + 10, y - 5, split - 16, y - 5), fill=LINE)
        y += 18
        for e in rows:
            day, wd, time, title, t, yes, maybe, no, mine, by, locked, soon = e
            r0, r1 = y, y + 64
            if idx == picked:
                d.rectangle((BX0 + 3, r0, split - 4, r1), fill=(58, 46, 22))
                d.rectangle((BX0 + 3, r0, BX0 + 4, r1), fill=GOLD)
            # date block
            text_at(d, (84, y + 30), day[:2], F_L, WHITE, "ms")
            text_at(d, (84, y + 50), wd, F_XS, GREY, "ms")
            type_mark(d, 120, y + 26, t, 4)
            text_at(d, (134, y + 26), fit(title, F_S, 300), F_S, WHITE)
            text_at(d, (134, y + 48), f"{time} · {TYPES[t][0]}", F_XS, GREY)
            if locked:
                lock_mark(d, 134 + F_XS.getlength(f"{time} · {TYPES[t][0]}") + 10, y + 49, DIM)
            label, color = STATUS[mine]
            if mine == "invited":
                label, color = "offen", GOLD
            text_at(d, (split - 18, y + 26), label, F_XS, color, "rs")
            counts(d, split - 120, y + 48, yes, maybe, no, F_XS)
            y += 70
            idx += 1
        y += 14
    if with_form:
        red_button(img, 1535, 77, 118, "Neues Ereignis", WHITE)
        bottom = form(img, split + 32, 128, BX1 - 40)
        d.line((split + 32, bottom + 16, BX1 - 40, bottom + 16), fill=LINE)
        text_at(d, (split + 32, bottom + 46), "Nur für Ränge mit Kalenderrecht. Einladen einzelner Spieler und "
                "Bearbeiten im Blizzard-Kalender.", F_XS, DIM)
        img.save(os.path.join(OUT, "events-b-form.png"))
        return
    # detail
    e = EVENTS[picked]
    day, wd, time, title, t, yes, maybe, no, mine, by, locked, soon = e
    cx = split + 32
    text_at(d, (cx, 166), title, F_L, WHITE)
    label, color = TYPES[t]
    bw = round(F_B.getlength(label) + 26)
    d.rounded_rectangle((BX1 - 40 - bw, 146, BX1 - 40, 172), 4, fill=tuple(c // 4 for c in color), outline=color)
    text_at(d, (BX1 - 40 - bw / 2, 164), label, F_B, color, "ms")
    text_at(d, (cx, 192), f"Freitag, 27. November · 20:00 · heute in 3 Std. · von ", F_S, GREY)
    xx = cx + F_S.getlength("Freitag, 27. November · 20:00 · heute in 3 Std. · von ")
    text_at(d, (xx, 192), by, F_S, CLASS["priest"][0])
    words, line, ty = ("„" + DESC + "“").split(), "", 228
    for word in words:
        if F_S.getlength(line + " " + word) > 760:
            text_at(d, (cx, ty), line.strip(), F_S, WHITE)
            line, ty = "", ty + 20
        line += " " + word
    text_at(d, (cx, ty), line.strip(), F_S, WHITE)
    d.line((cx, 268, BX1 - 30, 268), fill=LINE)
    text_at(d, (cx, 298), "Du bist nicht angemeldet", F_N, GOLD)
    answer_buttons(img, cx + 260, 280, mine)
    # headcount bar
    total = yes + maybe + no
    by0, bx0, bx1 = 330, cx, BX1 - 30
    wid = bx1 - bx0
    segs = [(yes, OK), (maybe, MAYBE), (no, NO)]
    xx = bx0
    for n, c in segs:
        ww = wid * n / total
        d.rectangle((xx, by0, xx + ww - 2, by0 + 8), fill=tuple(int(v * 0.75) for v in c))
        xx += ww
    yy = 366
    for state, head in (("signed", f"Angemeldet · {yes}"), ("tentative", f"Vorläufig · {maybe}"),
                        ("declined", f"Abgelehnt · {no}")):
        text_at(d, (cx, yy), head, F_S, STATUS[state][1])
        d.line((cx + F_S.getlength(head) + 10, yy - 5, BX1 - 30, yy - 5), fill=LINE)
        yy += 26
        rows = [r for r in ROSTER if r[2] == state]
        colw = 260
        for i, (name, cls, _) in enumerate(rows):
            col, row = i % 4, i // 4
            px, py = cx + col * colw, yy + row * PITCH
            img.paste(mb.ICON[cls], (round(px), round(py) - 14))
            text_at(d, (px + 21, py), name, F_S, CLASS[cls][0])
        yy += PITCH * ((len(rows) + 3) // 4) + 12
    # class summary
    text_at(d, (cx, yy + 6), "Zusagen nach Klasse", F_S, GOLD)
    yy += 30
    from collections import Counter
    cnt = Counter(c for _, c, s in ROSTER if s == "signed")
    xx = cx
    for cls in ["warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid"]:
        n = cnt.get(cls, 0)
        s = f"{CLASS_DE[cls]} {n}"
        text_at(d, (xx, yy), s, F_S, CLASS[cls][0] if n else DIM)
        xx += F_S.getlength(s) + 22
    text_at(d, (cx, BY1 - 16), "Einladen und Sperren im Blizzard-Kalender", F_S, GOLD)
    text_at(d, (BX1 - 30, BY1 - 16), "nur für Ränge mit Kalenderrecht: Bearbeiten · Löschen", F_XS, DIM, "rs")
    img.save(os.path.join(OUT, "events-b.png"))


# --- C: Overview box + dialog ---------------------------------------------------------------------------------
def variant_c():
    img = mb._ov.copy()
    d = ImageDraw.Draw(img)
    # replace "Kommen und Gehen" with "Nächste Ereignisse"
    box = (586, 553, 1111, 796)
    gold_box(img, box)
    text_at(d, (598, 577), "Nächste Ereignisse", F_N, GOLD)
    red_button(img, 1000, 560, 100, "Neu")
    y = 606
    for i, e in enumerate(EVENTS[:5]):
        day, wd, time, title, t, yes, maybe, no, mine, by, locked, soon = e
        if i % 2 == 1:
            d.rectangle((589, y - 17, 1108, y + 8), fill=STRIPE)
        text_at(d, (600, y), f"{wd} {time}" if not soon else f"heute {time}", F_S, GOLD if soon else GREY)
        type_mark(d, 700, y, t, 4)
        text_at(d, (714, y), fit(title, F_S, 190), F_S, WHITE)
        counts(d, 915, y, yes, maybe, no, F_XS)
        if mine == "invited":
            text_at(d, (1100, y), "Anmelden", F_XS, GOLD, "rs")
        else:
            dot(d, 1090, y - 5, STATUS[mine][1])
        y += 37
    text_at(d, (598, 788), "Punkt = deine Antwort · Klick zeigt, wer kommt", F_XS, DIM)
    # dim the window, then the dialog
    over = Image.new("RGBA", img.size, (0, 0, 0, 120))
    img = Image.alpha_composite(img.convert("RGBA"), over).convert("RGB")
    d = ImageDraw.Draw(img)
    dx0, dy0, dx1, dy1 = 1000, 112, 1640, 536
    d.rectangle((dx0 + 6, dy0 + 8, dx1 + 6, dy1 + 8), fill=(0, 0, 0))
    gold_box(img, (dx0, dy0, dx1, dy1))
    d.rectangle((dx0 + 2, dy0 + 2, dx1 - 2, dy0 + 40), fill=(42, 32, 18))
    d.line((dx0 + 2, dy0 + 41, dx1 - 2, dy0 + 41), fill=(92, 74, 40))
    text_at(d, ((dx0 + dx1) / 2, dy0 + 28), "Neues Gilden-Ereignis", F_N, GOLD, "ms")
    img.paste(mb._ov.crop((1636, 26, 1670, 60)), (dx1 - 38, dy0 + 4))
    form(img, dx0 + 22, dy0 + 56, dx1 - 22, title=False)
    img.save(os.path.join(OUT, "events-c.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    variant_a()
    variant_b()
    variant_b(with_form=True)
    variant_c()
