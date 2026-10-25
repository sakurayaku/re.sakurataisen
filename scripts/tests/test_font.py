#!/usr/bin/env python3
"""Tests for scripts/font.py against the real US font.

Runs standalone:

    python3 re.sakurataisen/scripts/shared/test_font.py

and works under pytest too (every check is a plain assert inside a test_*
function).  The only dependency is Python itself; the Pillow cross-checks are
skipped when Pillow is not installed.
"""

import hashlib
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.dirname(HERE)
PROJECT = os.path.dirname(SCRIPTS)
sys.path.insert(0, SCRIPTS)

import font  # noqa: E402  (needs SCRIPTS on sys.path first)

FONT_PY = os.path.join(SCRIPTS, "font.py")

# The genuine US font is shipped as a manifest override; US_FONT.BIN is the
# same bytes kept next to the project for exactly this kind of check.
US_FONT_CANDIDATES = [
    os.path.join(PROJECT, "US_FONT.BIN"),
    os.path.join(PROJECT, "workspace", "SakTaiCD1_Track1.bin", "data.bin",
                 "SAKURA1", "0100KNJ.BIN"),
]
US_FONT_MD5 = "b1fb5aff0e770953a0440828d13bd0e5"

# sha256 of the atlas font.py builds from that font.  Pins the index -> pixel
# mapping (tile order, nibble order, row order); if any of those change, the
# decoded atlas is no longer the one that was verified against the engine.
GOLDEN_ATLAS_SHA256 = \
    "24451da93ba43182a281dedd0df37de265de18efdb64a747de47e56fd41ca6cc"

# Tile 0x40 is ASCII 'A' (glyph ids are 1-based).  Rows 2..10, columns 0..7,
# read straight out of the US font; '.' is index 0, '#' is index 15 (the ink).
GOLDEN_A_ROWS = [
    "...5#C..",
    "..C#38..",
    "..7693E.",
    "..2AD1C.",
    ".C1E.56.",
    ".76..91E",
    ".2#####A",
    "C1E...56",
    "56....91",
]


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def us_font():
    for path in US_FONT_CANDIDATES:
        if os.path.exists(path):
            with open(path, "rb") as handle:
                return path, handle.read()
    return None, None


def expect_error(callable_, *args, **kwargs):
    """Assert `callable_` raises FontError; return the message."""
    try:
        callable_(*args, **kwargs)
    except font.FontError as error:
        return str(error)
    raise AssertionError("%r was expected to raise FontError"
                         % getattr(callable_, "__name__", callable_))


def rows_of(atlas):
    """4bpp atlas -> 256x256 grid of palette indices."""
    out = []
    for row in range(font.ATLAS_PX):
        line = []
        for byte in atlas[row * font.ROW_BYTES:(row + 1) * font.ROW_BYTES]:
            line.append(byte >> 4)
            line.append(byte & 0x0F)
        out.append(line)
    return out


def tiles_of(atlas):
    """4bpp atlas -> 256 tiles of 16x16 palette indices, in tile order."""
    rows = rows_of(atlas)
    out = []
    for tile in range(font.GLYPH_COUNT):
        tile_row, tile_col = divmod(tile, font.TILES_PER_ROW)
        out.append([rows[tile_row * 16 + sub][tile_col * 16:(tile_col + 1) * 16]
                    for sub in range(16)])
    return out


def build_bmp(rows, bpp=4, entries=16, compression=0, top_down=False,
              colours=None, width=None, height=None):
    """Hand-built BMP, so the negative tests can build files font.py must reject."""
    height = len(rows) if height is None else height
    width = len(rows[0]) if width is None else width

    if colours is None:
        colours = [font.bgr555_to_rgb888(c) for c in font.PALETTE]
    colours = list(colours)[:entries]

    stride = ((width * bpp + 31) // 32) * 4
    pixels = bytearray()
    for row in rows:
        packed = bytearray()
        if bpp == 4:
            for x in range(0, width, 2):
                hi = row[x] & 0x0F
                lo = row[x + 1] & 0x0F if x + 1 < width else 0
                packed.append((hi << 4) | lo)
        elif bpp == 8:
            packed += bytes(v & 0xFF for v in row)
        else:
            # 1/2/16/24/32bpp: font.py must reject these on the header alone,
            # so the pixels only have to be the right length.
            packed += bytes(stride)
        packed += b"\x00" * (stride - len(packed))
        pixels += packed
    if not top_down:
        pixels = b"".join(pixels[y * stride:(y + 1) * stride]
                          for y in range(height - 1, -1, -1))

    table = b"".join(struct.pack("<BBBB", blue, green, red, 0)
                     for (red, green, blue) in colours)
    table += b"\x00" * (entries * 4 - len(table))

    offset = 14 + 40 + entries * 4
    header = struct.pack("<2sIHHI", b"BM", offset + len(pixels), 0, 0, offset)
    info = struct.pack("<IiiHHIIiiII", 40, width, -height if top_down else height,
                       1, bpp, compression, 0, 2835, 2835, entries, entries)
    return header + info + table + bytes(pixels)


def bmp_set_pixel(bmp, x, y, value):
    """Set one atlas pixel in a BMP font.py wrote (bottom-up), return new bytes."""
    out = bytearray(bmp)
    base = font.BMP_PIXEL_OFFSET + (font.ATLAS_PX - 1 - y) * font.ROW_BYTES
    index = base + x // 2
    if x % 2 == 0:
        out[index] = (out[index] & 0x0F) | (value << 4)
    else:
        out[index] = (out[index] & 0xF0) | value
    return bytes(out)


def bin_pixel(bin_data, x, y):
    """Palette index at atlas coordinate (x, y) inside a KNJ tile array."""
    tile = (y // 16) * font.TILES_PER_ROW + x // 16
    byte = bin_data[tile * font.BYTES_PER_TILE + (y % 16) * font.BYTES_PER_TILE_ROW
                    + (x % 16) // 2]
    return (byte >> 4) if x % 2 == 0 else (byte & 0x0F)


# ---------------------------------------------------------------------------
# the real US font
# ---------------------------------------------------------------------------

def test_us_font_is_present_and_genuine():
    path, data = us_font()
    assert path is not None, "no US font found; looked at %s" % US_FONT_CANDIDATES
    assert len(data) == font.BIN_BYTES
    assert hashlib.md5(data).hexdigest() == US_FONT_MD5, \
        "%s is not the verified US font" % path


def test_golden_atlas_hash():
    _, data = us_font()
    atlas = font.bin_to_atlas(data)
    assert hashlib.sha256(atlas).hexdigest() == GOLDEN_ATLAS_SHA256


def test_atlas_matches_an_independent_retile():
    """Recompute the atlas from the BIN a second, separate way."""
    _, data = us_font()
    expected = bytearray(font.BIN_BYTES)
    for tile in range(font.GLYPH_COUNT):
        tile_row, tile_col = divmod(tile, font.TILES_PER_ROW)
        for sub in range(16):
            src = tile * font.BYTES_PER_TILE + sub * font.BYTES_PER_TILE_ROW
            row = tile_row * 16 + sub
            dst = row * font.ROW_BYTES + tile_col * font.BYTES_PER_TILE_ROW
            expected[dst:dst + 8] = data[src:src + 8]
    assert font.bin_to_atlas(data) == bytes(expected)


def test_glyph_ids_are_one_based():
    assert font.tile_index(0x41) == 0x40, "ASCII 'A' must be tile 0x40"
    assert font.glyph_id(0x40) == 0x41
    assert font.tile_index(1) == 0
    assert font.glyph_id(255) == 256
    expect_error(font.tile_index, 0)
    expect_error(font.tile_index, 257)
    expect_error(font.glyph_id, -1)


def test_tile_0x40_looks_like_an_A():
    _, data = us_font()
    tile = tiles_of(font.bin_to_atlas(data))[font.tile_index(0x41)]
    rendered = ["".join("." if v == 0 else ("#" if v == 15 else "%X" % v)
                        for v in row[:8]) for row in tile[2:11]]
    assert rendered == GOLDEN_A_ROWS, "\n".join(rendered)


def test_space_is_blank_and_exclamation_is_not():
    _, data = us_font()
    tiles = tiles_of(font.bin_to_atlas(data))
    assert not any(any(row) for row in tiles[font.tile_index(0x20)]), \
        "glyph 0x20 (space) must be an empty tile"
    assert sum(1 for row in tiles[font.tile_index(0x21)] for v in row if v), \
        "glyph 0x21 ('!') must have ink"


def test_round_trip_is_byte_identical():
    """BIN -> atlas -> BMP -> (import) -> BIN on an untouched font."""
    _, data = us_font()
    bmp = font.atlas_to_bmp(font.bin_to_atlas(data))
    atlas, _table = font.bmp_to_atlas(bmp)
    assert font.atlas_to_bin(atlas) == data


def test_round_trip_is_byte_identical_through_the_cli():
    _, data = us_font()
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "0100KNJ.BIN")
        bmp = os.path.join(tmp, "0100KNJ.bmp")
        out = os.path.join(tmp, "0100KNJ.out.BIN")
        with open(src, "wb") as handle:
            handle.write(data)
        run = subprocess.run([sys.executable, FONT_PY, "decode", src, bmp],
                             capture_output=True, text=True)
        assert run.returncode == 0, run.stderr
        assert os.path.getsize(bmp) == 32886
        run = subprocess.run([sys.executable, FONT_PY, "encode", bmp, out],
                             capture_output=True, text=True)
        assert run.returncode == 0, run.stderr
        with open(out, "rb") as handle:
            assert handle.read() == data


# ---------------------------------------------------------------------------
# the atlas BMP itself
# ---------------------------------------------------------------------------

def test_bmp_shape_and_palette():
    _, data = us_font()
    bmp = font.atlas_to_bmp(font.bin_to_atlas(data))
    width, height, planes, bpp, compression = struct.unpack_from("<iiHHI", bmp, 18)
    assert (width, height) == (256, 256)
    assert planes == 1
    assert bpp == 4
    assert compression == 0
    assert struct.unpack_from("<I", bmp, 46)[0] == 16, "16 palette entries declared"
    assert struct.unpack_from("<I", bmp, 10)[0] == 118, "pixel data after 16 colours"
    assert len(bmp) == 118 + 32768

    table = [struct.unpack_from("<BBBB", bmp, 54 + i * 4) for i in range(16)]
    assert table[0][:3] == (0xFF, 0xFF, 0xFF), "index 0 must be white background"
    assert table[15][:3] == (25, 25, 25), "index 15 must be the dark ink"


def test_bmp_pixel_array_is_the_atlas_upside_down():
    _, data = us_font()
    atlas = font.bin_to_atlas(data)
    bmp = font.atlas_to_bmp(atlas)
    pixels = bmp[font.BMP_PIXEL_OFFSET:]
    assert pixels == b"".join(atlas[r * font.ROW_BYTES:(r + 1) * font.ROW_BYTES]
                              for r in range(255, -1, -1))


# ---------------------------------------------------------------------------
# editing, i.e. index preservation
# ---------------------------------------------------------------------------

def test_edited_pixel_lands_in_the_right_nibble():
    _, data = us_font()
    bmp = font.atlas_to_bmp(font.bin_to_atlas(data))
    for x, y in ((0, 0), (1, 0), (8, 2), (255, 255), (100, 100), (65, 65)):
        value = (bin_pixel(data, x, y) + 1) % 16  # always a real change
        edited = bmp_set_pixel(bmp, x, y, value)
        atlas, _table = font.bmp_to_atlas(edited)
        out = font.atlas_to_bin(atlas)
        assert bin_pixel(out, x, y) == value, "pixel (%d, %d)" % (x, y)
        # and nothing else moved
        assert sum(1 for i in range(font.BIN_BYTES) if out[i] != data[i]) == 1, \
            "pixel (%d, %d) disturbed more than its own nibble" % (x, y)


def test_every_index_survives_a_round_trip():
    """A synthetic atlas holding all 16 indices in every tile."""
    atlas = bytearray(font.BIN_BYTES)
    for row in range(font.ATLAS_PX):
        for x in range(font.ATLAS_PX):
            value = (row + x) % 16
            if x % 2 == 0:
                atlas[row * font.ROW_BYTES + x // 2] = value << 4
            else:
                atlas[row * font.ROW_BYTES + x // 2] |= value
    atlas = bytes(atlas)
    bin_data = font.atlas_to_bin(atlas)
    assert font.bin_to_atlas(bin_data) == atlas
    again, _table = font.bmp_to_atlas(font.atlas_to_bmp(atlas))
    assert font.atlas_to_bin(again) == bin_data


def test_8bpp_atlas_with_16_colours_is_accepted():
    _, data = us_font()
    atlas = font.bin_to_atlas(data)
    rows = rows_of(atlas)
    bmp = build_bmp(rows, bpp=8, entries=16)
    again, _table = font.bmp_to_atlas(bmp)
    assert font.atlas_to_bin(again) == data


def test_top_down_bmp_is_accepted():
    _, data = us_font()
    rows = rows_of(font.bin_to_atlas(data))
    again, _table = font.bmp_to_atlas(build_bmp(rows, top_down=True))
    assert font.atlas_to_bin(again) == data


def test_palette_edit_does_not_change_the_bytes():
    """Recolouring the table must not move a single pixel."""
    _, data = us_font()
    atlas = font.bin_to_atlas(data)
    bmp = bytearray(font.atlas_to_bmp(atlas))
    for i in range(16):
        bmp[54 + i * 4:54 + i * 4 + 4] = struct.pack("<BBBB", i * 3, i * 3, i * 3, 0)
    again, table = font.bmp_to_atlas(bytes(bmp))
    assert font.atlas_to_bin(again) == data
    assert font.palette_differences(table), "recolouring must be reported"
    unchanged, table = font.bmp_to_atlas(font.atlas_to_bmp(atlas))
    assert font.palette_differences(table) == []


# ---------------------------------------------------------------------------
# rejection
# ---------------------------------------------------------------------------

def test_the_tool_refuses_bad_bin_sizes():
    expect_error(font.bin_to_atlas, b"")
    expect_error(font.bin_to_atlas, bytes(100))
    expect_error(font.bin_to_atlas, bytes(font.BIN_BYTES + 128))


def test_the_tool_refuses_bad_dimensions():
    _, data = us_font()
    rows = rows_of(font.bin_to_atlas(data))
    assert "atlas is 128x256" in expect_error(
        font.bmp_to_atlas, build_bmp([r[:128] for r in rows]))
    assert "atlas is 256x128" in expect_error(
        font.bmp_to_atlas, build_bmp(rows[:128]))
    # 512x512: valid maths, wrong atlas
    assert "atlas is 512x512" in expect_error(
        font.bmp_to_atlas, build_bmp([r * 2 for r in rows] * 2))


def test_the_tool_refuses_colour_modes_it_cannot_map():
    _, data = us_font()
    rows = rows_of(font.bin_to_atlas(data))
    assert "not an indexed atlas" in expect_error(
        font.bmp_to_atlas, build_bmp(rows, bpp=24))
    assert "not an indexed atlas" in expect_error(
        font.bmp_to_atlas, build_bmp(rows, bpp=32))
    assert "not an indexed atlas" in expect_error(
        font.bmp_to_atlas, build_bmp(rows, bpp=1))
    # 8bpp + 256 colours: an index no longer identifies a 4bpp nibble
    assert "declares 256 palette entries" in expect_error(
        font.bmp_to_atlas, build_bmp(rows, bpp=8, entries=256,
                                     colours=[(0, 0, 0)] * 256))
    # 4bpp cannot declare more than 16 either
    assert "declares 256 palette entries" in expect_error(
        font.bmp_to_atlas, build_bmp(rows, bpp=4, entries=256,
                                     colours=[(0, 0, 0)] * 256))


def test_the_tool_refuses_out_of_range_indices():
    _, data = us_font()
    rows = rows_of(font.bin_to_atlas(data))
    rows[3][9] = 200
    assert "index 200" in expect_error(font.bmp_to_atlas, build_bmp(rows, bpp=8))


def test_the_tool_refuses_compressed_and_malformed_bmp():
    _, data = us_font()
    rows = rows_of(font.bin_to_atlas(data))
    assert "compressed" in expect_error(
        font.bmp_to_atlas, build_bmp(rows, compression=1))
    assert "not a BMP" in expect_error(font.bmp_to_atlas, b"GIF89a" + bytes(200))
    assert "truncated" in expect_error(font.bmp_to_atlas, bytes(20))
    good = build_bmp(rows, bpp=4)
    assert "truncated" in expect_error(font.bmp_to_atlas, good[:-10])
    assert "truncated" in expect_error(font.bmp_to_atlas,
                                        good[:54 + 16 * 4 - 8] + good[54 + 16 * 4:])
    assert "DIB header" in expect_error(
        font.bmp_to_atlas, good[:14] + struct.pack("<I", 12) + good[18:])
    assert "planes" in expect_error(
        font.bmp_to_atlas, good[:26] + struct.pack("<H", 2) + good[28:])


def test_missing_files_report_clearly():
    assert "cannot read" in expect_error(font.decode_file, "/nope/nope.BIN",
                                         "/tmp/unused.bmp")
    assert "expected a 256-glyph KNJ font" in expect_error(
        font.bin_to_atlas, bytes(4))
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "x.bmp")
        with open(src, "wb") as handle:
            handle.write(font.atlas_to_bmp(font.bin_to_atlas(us_font()[1])))
        assert "cannot write" in expect_error(
            font.encode_file, src, os.path.join(tmp, "no", "such", "dir", "x.BIN"))


# ---------------------------------------------------------------------------
# independent check: Pillow, when it happens to be installed
# ---------------------------------------------------------------------------

def test_pillow_reads_our_bmp():
    try:
        from PIL import Image
    except ImportError:
        return
    import io
    _, data = us_font()
    atlas = font.bin_to_atlas(data)
    image = Image.open(io.BytesIO(font.atlas_to_bmp(atlas)))
    assert image.size == (256, 256)
    assert image.mode == "P"
    assert image.getpalette()[0:3] == [255, 255, 255]
    assert image.getpalette()[15 * 3:15 * 3 + 3] == [25, 25, 25]
    pixels = image.load()
    for x, y in ((0, 0), (64, 2), (255, 255), (123, 7)):
        assert pixels[x, y] == bin_pixel(data, x, y)


def test_pillow_written_bmps_import_identically():
    try:
        from PIL import Image
    except ImportError:
        return
    import io
    _, data = us_font()
    atlas = font.bin_to_atlas(data)
    image = Image.open(io.BytesIO(font.atlas_to_bmp(atlas)))
    for mode in ("P",):
        for path_bpp in (4, 8):
            buffer = io.BytesIO()
            try:
                image.save(buffer, format="BMP", bits=path_bpp)
            except (ValueError, OSError):
                continue  # Pillow refused this depth; nothing to check
            again, _table = font.bmp_to_atlas(buffer.getvalue())
            assert font.atlas_to_bin(again) == data, "Pillow %dbpp" % path_bpp


# ---------------------------------------------------------------------------
# runner
# ---------------------------------------------------------------------------

def main():
    tests = [(name, value) for name, value in sorted(globals().items())
             if name.startswith("test_") and callable(value)]
    failed = 0
    for name, test in tests:
        try:
            test()
        except Exception as error:  # noqa: BLE001 - report anything as a failure
            failed += 1
            print("FAIL %s: %s: %s" % (name, type(error).__name__, error))
        else:
            print("ok   %s" % name)
    print("\n%d passed, %d failed" % (len(tests) - failed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
