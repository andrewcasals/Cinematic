"""Cinematic's blank font: every character is there but draws nothing. Used as
the game's world text font (DAMAGE_TEXT_FONT) to hide the floating XP text.
Our own, made from scratch here; usage: make_blank_font.py Fonts/Blank.ttf
The game won't load a font whose glyphs have no outline at all, so each one is
a speck far smaller than a pixel at any text size the game uses."""
import sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

OUT = sys.argv[1]
UPM = 1000
# Basic Latin, Latin-1 and the general punctuation block (WoW's text is mostly
# these; the XP text is digits, letters, "+", ":" and brackets).
CODES = list(range(0x20, 0x7F)) + list(range(0xA0, 0x100)) + list(range(0x2000, 0x2070))

names = [".notdef"] + ["u%04X" % c for c in CODES]


def speck():
    pen = TTGlyphPen(None)
    pen.moveTo((0, 0))
    pen.lineTo((0, 1))
    pen.lineTo((1, 1))
    pen.lineTo((1, 0))
    pen.closePath()
    return pen.glyph()


fb = FontBuilder(UPM, isTTF=True)
fb.setupGlyphOrder(names)
fb.setupCharacterMap({c: "u%04X" % c for c in CODES})
fb.setupGlyf({n: speck() for n in names})
fb.setupHorizontalMetrics({n: (500, 0) for n in names})
fb.setupHorizontalHeader(ascent=800, descent=-200)
fb.setupNameTable({
    "familyName": "Cinematic Blank", "styleName": "Regular",
    "uniqueFontIdentifier": "Cinematic Blank Regular", "fullName": "Cinematic Blank",
    "psName": "CinematicBlank-Regular", "version": "Version 1.000",
})
fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200,
            sTypoLineGap=0, sxHeight=500, sCapHeight=700)
fb.setupPost()
fb.setupDummyDSIG()
fb.save(OUT)
