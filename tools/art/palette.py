"""The game's colour palette: the single source of truth for assets/palette.png.

Every flat-coloured model (tools/blender/*.py) maps its faces onto these swatches by name, so
props from different scripts, and recoloured third-party models, share one look (ASSETS §1).
The PNG is a grid of COLS x ROWS swatches, each SWATCH x SWATCH pixels; a name's swatch centre
is the UV a face uses. Regenerate the PNG with `python3 tools/art/make_palette.py` after editing.

Append new colours at the end of a row (or in a new row) rather than reordering: models store
UVs, not names, so moving a swatch recolours every model already exported.
"""

SWATCH = 16
COLS = 8

# One row per family, left to right. GDD colour codes: rat_green #7BD389, safety_yellow #FFC93C,
# alarm_red #E84A5F, rad_green #9CFF2E.
ROWS = [
    # neutrals
    [("black", "1b1b1f"), ("charcoal", "34343c"), ("grey_dark", "4e5058"), ("grey", "74777f"),
     ("grey_light", "a3a6ad"), ("silver", "c9ccd1"), ("off_white", "e8e6df"), ("white", "ffffff")],
    # plant metals and pipes
    [("steel_dark", "3d4a55"), ("steel", "5b6b78"), ("steel_light", "8597a3"), ("teal_dark", "2f5d62"),
     ("teal", "4e8a8b"), ("teal_light", "84b8b3"), ("pipe_green", "5e8c61"), ("pipe_green_light", "8db580")],
    # warm environment
    [("beige_dark", "9c8b6e"), ("beige", "c9b89a"), ("beige_light", "e5d9bf"), ("brown_dark", "5a3e2b"),
     ("brown", "8a5a3b"), ("wood", "b98552"), ("wood_light", "d9ae7a"), ("cardboard", "c49a62")],
    # gameplay signal colours
    [("safety_yellow", "ffc93c"), ("yellow_dark", "d9a21b"), ("orange", "f28c28"), ("orange_dark", "c2601a"),
     ("alarm_red", "e84a5f"), ("red_dark", "a8303f"), ("rat_green", "7bd389"), ("rad_green", "9cff2e")],
    # blues and purples
    [("navy", "1f2a44"), ("blue_dark", "2e4c7a"), ("blue", "3f7cc0"), ("sky", "7fb7e6"),
     ("glass", "bfe3f2"), ("purple_dark", "4b3b6b"), ("purple", "7a5fa0"), ("lavender", "b4a3d3")],
    # people
    [("skin_light", "f2c9a0"), ("skin", "d9a27a"), ("skin_dark", "a0694a"), ("shirt_white", "f4f4f0"),
     ("tie_red", "c83a3a"), ("pants_navy", "2c3550"), ("hardhat", "ffd23f"), ("boot_brown", "4a3020")],
    # rats
    [("rat_grey_dark", "5e5a63"), ("rat_grey", "8c8792"), ("rat_grey_light", "b7b2bc"), ("rat_pink", "f2a0b0"),
     ("rat_pink_dark", "d9788e"), ("eye_black", "141414"), ("eye_shine", "fafafa"), ("tooth", "fff6d8")],
    # food, screens, misc
    [("dough", "e3a857"), ("icing_pink", "ff8fb8"), ("sprinkle_blue", "57c7ff"), ("sprinkle_yellow", "ffe45c"),
     ("coffee", "4b2e1f"), ("cheese", "ffd34d"), ("screen_green", "35e07a"), ("screen_blue", "49b6ff")],
]

ROW_COUNT = len(ROWS)
WIDTH = COLS * SWATCH
HEIGHT = ROW_COUNT * SWATCH

COLORS = {}  # name -> (r, g, b) floats 0..1 (sRGB)
INDEX = {}  # name -> (col, row)
for _r, _row in enumerate(ROWS):
    assert len(_row) == COLS, "row %d must have %d colours" % (_r, COLS)
    for _c, (_name, _hex) in enumerate(_row):
        assert _name not in COLORS, "duplicate palette name " + _name
        COLORS[_name] = tuple(int(_hex[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
        INDEX[_name] = (_c, _r)


def uv(name):
    """UV (u, v) of a swatch's centre, with v measured from the top (glTF/Godot convention)."""
    c, r = INDEX[name]
    return ((c + 0.5) / COLS, (r + 0.5) / ROW_COUNT)


def nearest(rgb):
    """The palette name closest to an sRGB colour (0..1), for recolouring third-party models."""
    best, best_d = None, 1e9
    for name, col in COLORS.items():
        d = sum((a - b) ** 2 for a, b in zip(rgb, col))
        if d < best_d:
            best, best_d = name, d
    return best
