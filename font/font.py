#!/usr/bin/env python3
"""Sakura Taisen (Saturn) — KNJ font <-> single editable BMP atlas.

    font.py decode INPUT.BIN OUTPUT.bmp
    font.py encode INPUT.bmp OUTPUT.BIN

The KNJ file
------------
A bare tile array, no header, no palette, no checksums:

    256 glyphs x 16x16 pixels x 4bpp = 128 bytes per glyph = 32768 bytes
    within a glyph: 16 rows of 8 bytes, row-major, high nibble = left pixel

Glyph IDs are 1-based in the engine: glyph G lives in tile G-1.  ASCII 'A'
(0x41) is therefore tile 0x40, and the atlas is ordered by physical tile index
so it reads left to right, top to bottom as glyphs 0x01..0xFF.

The atlas
---------
A 256x256 4bpp indexed BMP: 16x16 tiles of 16x16 pixels, bottom-up rows, the
16-entry colour table written from PALETTE below.  Its pixel array and the
KNJ's 4bpp index stream carry the same values — the conversion is a pure
permutation of 8-byte blocks, no nibble ever changes value, and nothing is
mapped through RGB.

Palette indices are copied verbatim in both directions, which is why
`decode` then `encode` on an untouched font reproduces the input byte for
byte, and why editing pixels in an editor cannot silently quantise anything.

What is rejected
----------------
Anything that would make the write-back ambiguous, rather than guessed at:

  * an input whose size is not exactly 256 glyphs
  * an atlas that is not 256x256
  * a BMP whose mode cannot be mapped back to 4bpp indices: 1/2/8-with-256-
    colours/16/24/32bpp, or compression, or bitfields
  * a 4bpp BMP that does not declare 16 palette entries, or an 8bpp BMP that
    declares more than 16 (a 16-colour 8bpp file is accepted: its index space
    is identical)
  * an index at or above 16 in an 8bpp atlas
  * a truncated header, palette or pixel array

A colour table that differs from PALETTE is *not* rejected — indices are what
get written, so it cannot corrupt the result — but it is reported, because
what the editor shows then differs from what the engine will draw.
"""

import argparse
import struct
import sys

# ---------------------------------------------------------------------------
# Palette — edit here
# ---------------------------------------------------------------------------
# Sixteen BGR555 colours, index 0 first, in the order the engine's font palette
# uses them.  These are the values the US build patches into the executable
# (verified against the shipped release and against the tool's own
# Data/8x12_SLG.bmp):
#
#     index  0       0x7FFF  white        the background
#     index  1..14           a grey ramp, BGR555 5,5,5 up to 29,29,29
#     index 15       0x0C63  near black   the ink
#
# The US font sheet draws its letter bodies with index 15.  A palette whose
# index 15 is light renders the text hollow and thin — that is exactly the bug
# the US build fixes by swapping this palette in.  Keep 15 dark.
#
# This list is written into the atlas BMP's colour table so the file opens
# looking like the game.  It is display only: nothing here maps a pixel through
# RGB and PALETTE is never read back on import.
#
#     as a hex dump: 7FFF 14A5 1CE7 2529 294A 318C 35AD 4210 4631 5294 5AD6
#                    5EF7 6739 6F7B 77BD 0C63
PALETTE = [
    0x7FFF,  #  0  background, white
    0x14A5,  #  1
    0x1CE7,  #  2
    0x2529,  #  3
    0x294A,  #  4
    0x318C,  #  5
    0x35AD,  #  6
    0x4210,  #  7
    0x4631,  #  8
    0x5294,  #  9
    0x5AD6,  # 10
    0x5EF7,  # 11
    0x6739,  # 12
    0x6F7B,  # 13
    0x77BD,  # 14
    0x0C63,  # 15  ink, near black
]

# ---------------------------------------------------------------------------
# Format constants
# ---------------------------------------------------------------------------

GLYPH_COUNT = 256                      # glyphs in a KNJ font
TILE_PX = 16                           # pixels per glyph side
TILES_PER_ROW = 16                     # atlas is a 16x16 grid of tiles
ATLAS_PX = TILES_PER_ROW * TILE_PX     # 256

BYTES_PER_TILE_ROW = TILE_PX // 2      # 8 bytes per 16-pixel row at 4bpp
BYTES_PER_TILE = TILE_PX * BYTES_PER_TILE_ROW          # 128
BIN_BYTES = GLYPH_COUNT * BYTES_PER_TILE               # 32768
ROW_BYTES = ATLAS_PX // 2                              # 128 bytes per atlas row

COLOUR_COUNT = 16
BMP_FILE_HEADER_BYTES = 14
BMP_INFO_HEADER_BYTES = 40
BMP_PALETTE_BYTES = COLOUR_COUNT * 4                   # 64
BMP_PIXEL_OFFSET = BMP_FILE_HEADER_BYTES + BMP_INFO_HEADER_BYTES + BMP_PALETTE_BYTES  # 118


class FontError(Exception):
    """Anything that makes the conversion impossible or ambiguous."""


# ---------------------------------------------------------------------------
# Glyph IDs
# ---------------------------------------------------------------------------

def tile_index(glyph_id):
    """Tile holding `glyph_id`, which is 1-based in the engine.

    ASCII 'A' (0x41) is tile 0x40.
    """
    if not 1 <= glyph_id <= GLYPH_COUNT:
        raise FontError("glyph id 0x%X is outside 1..%d" % (glyph_id, GLYPH_COUNT))
    return glyph_id - 1


def glyph_id(tile):
    """Inverse of `tile_index`."""
    if not 0 <= tile < GLYPH_COUNT:
        raise FontError("tile 0x%X is outside 0..%d" % (tile, GLYPH_COUNT - 1))
    return tile + 1


# ---------------------------------------------------------------------------
# Colour
# ---------------------------------------------------------------------------

def bgr555_to_rgb888(colour):
    """Saturn BGR555 -> (r, g, b) in 0..255, the rounding the tooling here uses."""
    b5 = (colour >> 10) & 0x1F
    g5 = (colour >> 5) & 0x1F
    r5 = colour & 0x1F
    return ((r5 * 255 + 15) // 31, (g5 * 255 + 15) // 31, (b5 * 255 + 15) // 31)


# ---------------------------------------------------------------------------
# KNJ <-> atlas
#
# Both are 4bpp, high nibble first, so a row of a glyph is a run of whole bytes
# in both.  The conversion moves those runs between a linear tile order (KNJ)
# and a 16-tiles-across atlas order.  It is a permutation: nothing is resampled.
# ---------------------------------------------------------------------------

def _check_bin_size(data):
    if len(data) != BIN_BYTES:
        raise FontError(
            "expected a %d-glyph KNJ font of exactly %d bytes (%d x %d), got %d bytes"
            % (GLYPH_COUNT, BIN_BYTES, GLYPH_COUNT, BYTES_PER_TILE, len(data)))


def bin_to_atlas(data):
    """KNJ tile array -> 4bpp atlas rows (ATLAS_PX rows of ROW_BYTES bytes)."""
    _check_bin_size(data)
    out = bytearray(BIN_BYTES)
    for tile in range(GLYPH_COUNT):
        tile_row, tile_col = divmod(tile, TILES_PER_ROW)
        src = tile * BYTES_PER_TILE
        for sub_row in range(TILE_PX):
            atlas_row = tile_row * TILE_PX + sub_row
            dst = atlas_row * ROW_BYTES + tile_col * BYTES_PER_TILE_ROW
            out[dst:dst + BYTES_PER_TILE_ROW] = \
                data[src + sub_row * BYTES_PER_TILE_ROW:
                     src + (sub_row + 1) * BYTES_PER_TILE_ROW]
    return bytes(out)


def atlas_to_bin(atlas):
    """4bpp atlas rows -> KNJ tile array (exact inverse of `bin_to_atlas`)."""
    if len(atlas) != BIN_BYTES:
        raise FontError("atlas is %d bytes; %d expected (a %dx%d 4bpp image)"
                        % (len(atlas), BIN_BYTES, ATLAS_PX, ATLAS_PX))
    out = bytearray(BIN_BYTES)
    for tile in range(GLYPH_COUNT):
        tile_row, tile_col = divmod(tile, TILES_PER_ROW)
        dst = tile * BYTES_PER_TILE
        for sub_row in range(TILE_PX):
            atlas_row = tile_row * TILE_PX + sub_row
            src = atlas_row * ROW_BYTES + tile_col * BYTES_PER_TILE_ROW
            out[dst + sub_row * BYTES_PER_TILE_ROW:
                dst + (sub_row + 1) * BYTES_PER_TILE_ROW] = \
                atlas[src:src + BYTES_PER_TILE_ROW]
    return bytes(out)


# ---------------------------------------------------------------------------
# BMP
# ---------------------------------------------------------------------------

def atlas_to_bmp(atlas, palette=None):
    """4bpp atlas rows -> a 256x256 4bpp indexed BMP (bottom-up, 16 colours)."""
    if len(atlas) != BIN_BYTES:
        raise FontError("atlas is %d bytes; %d expected (a %dx%d 4bpp image)"
                        % (len(atlas), BIN_BYTES, ATLAS_PX, ATLAS_PX))

    colours = PALETTE if palette is None else palette
    if len(colours) != COLOUR_COUNT:
        raise FontError("a 4bpp BMP palette needs exactly %d colours, got %d"
                        % (COLOUR_COUNT, len(colours)))

    table = bytearray()
    for colour in colours:
        red, green, blue = bgr555_to_rgb888(colour)
        table += struct.pack("<BBBB", blue, green, red, 0)

    # BMP rows run bottom-up, so the pixel array is the atlas upside down.
    pixels = b"".join(atlas[row * ROW_BYTES:(row + 1) * ROW_BYTES]
                      for row in range(ATLAS_PX - 1, -1, -1))

    file_header = struct.pack("<2sIHHI", b"BM",
                              BMP_PIXEL_OFFSET + len(pixels), 0, 0,
                              BMP_PIXEL_OFFSET)
    info_header = struct.pack("<IiiHHIIiiII", BMP_INFO_HEADER_BYTES,
                              ATLAS_PX, ATLAS_PX, 1, 4, 0, len(pixels),
                              2835, 2835, COLOUR_COUNT, COLOUR_COUNT)
    return file_header + info_header + bytes(table) + pixels


def bmp_to_atlas(data):
    """BMP bytes -> (4bpp atlas rows, colour table as [(b, g, r, x), ...]).

    Only the indices are read.  The colour table is returned so the caller can
    report a table that no longer matches PALETTE; it never affects the result.
    """
    if len(data) < BMP_FILE_HEADER_BYTES + BMP_INFO_HEADER_BYTES:
        raise FontError("BMP is truncated: %d bytes" % len(data))
    if data[0:2] != b"BM":
        raise FontError("not a BMP file (no 'BM' signature)")

    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    info_len = struct.unpack_from("<I", data, 14)[0]
    if info_len < BMP_INFO_HEADER_BYTES:
        raise FontError("BMP DIB header is %d bytes; %d or more expected"
                        % (info_len, BMP_INFO_HEADER_BYTES))
    if pixel_offset < BMP_FILE_HEADER_BYTES + info_len:
        raise FontError("BMP pixel offset %d overlaps its headers" % pixel_offset)

    width, height, planes, bpp, compression = struct.unpack_from("<iiHHI", data, 18)
    clr_used = struct.unpack_from("<I", data, 46)[0]

    top_down = height < 0
    height = abs(height)

    if (width, height) != (ATLAS_PX, ATLAS_PX):
        raise FontError("atlas is %dx%d; a %dx%d atlas is expected (%d tiles of "
                        "%dx%d)" % (width, height, ATLAS_PX, ATLAS_PX,
                                    GLYPH_COUNT, TILE_PX, TILE_PX))
    if planes != 1:
        raise FontError("BMP declares %d colour planes; 1 expected" % planes)
    if compression != 0:
        raise FontError("BMP is compressed (compression %d); only uncompressed "
                        "indexed data can be read back" % compression)

    if bpp == 4:
        if clr_used not in (0, COLOUR_COUNT):
            raise FontError("4bpp BMP declares %d palette entries; %d expected"
                            % (clr_used, COLOUR_COUNT))
        entries = COLOUR_COUNT
    elif bpp == 8:
        if clr_used != COLOUR_COUNT:
            raise FontError(
                "8bpp BMP declares %d palette entries; an atlas must declare "
                "exactly %d, otherwise an 8-bit index cannot be mapped back to "
                "a 4bpp glyph index" % (clr_used, COLOUR_COUNT))
        entries = COLOUR_COUNT
    else:
        raise FontError("%dbpp is not an indexed atlas; saved colour modes "
                        "cannot be read back without quantising (4bpp with %d "
                        "colours is the atlas format)" % (bpp, COLOUR_COUNT))

    table_start = BMP_FILE_HEADER_BYTES + info_len
    if pixel_offset < table_start + entries * 4:
        raise FontError("BMP palette is truncated: %d bytes there, %d expected"
                        % (pixel_offset - table_start, entries * 4))
    colour_table = [struct.unpack_from("<BBBB", data, table_start + i * 4)
                    for i in range(entries)]

    stride = ((width * bpp + 31) // 32) * 4
    needed = ROW_BYTES if bpp == 4 else ATLAS_PX
    if stride < needed:
        raise FontError("BMP row stride is %d bytes; at least %d needed" % (stride, needed))
    if pixel_offset + stride * height > len(data):
        raise FontError("BMP pixel data is truncated: %d bytes there, %d expected"
                        % (len(data) - pixel_offset, stride * height))

    atlas = bytearray(BIN_BYTES)
    for row in range(ATLAS_PX):
        src_row = row if top_down else height - 1 - row
        base = pixel_offset + src_row * stride
        row_start = row * ROW_BYTES

        if bpp == 4:
            atlas[row_start:row_start + ROW_BYTES] = data[base:base + ROW_BYTES]
        else:
            for x in range(ATLAS_PX):
                value = data[base + x]
                if value >= COLOUR_COUNT:
                    raise FontError(
                        "pixel (%d, %d) has index %d, outside the %d-colour "
                        "palette" % (x, row, value, COLOUR_COUNT))
                if x % 2 == 0:
                    atlas[row_start + x // 2] = value << 4
                else:
                    atlas[row_start + x // 2] |= value

    return bytes(atlas), colour_table


def palette_differences(colour_table):
    """Indices whose BMP colour differs from PALETTE, as (index, want, got)."""
    differences = []
    for index in range(COLOUR_COUNT):
        blue, green, red = colour_table[index][0], colour_table[index][1], colour_table[index][2]
        wanted = bgr555_to_rgb888(PALETTE[index])
        got = (red, green, blue)
        if got != wanted:
            differences.append((index, wanted, got))
    return differences


# ---------------------------------------------------------------------------
# Files and command line
# ---------------------------------------------------------------------------

def _read(path):
    try:
        with open(path, "rb") as handle:
            return handle.read()
    except OSError as error:
        raise FontError("cannot read '%s': %s" % (path, error))


def _write(path, data):
    try:
        with open(path, "wb") as handle:
            handle.write(data)
    except OSError as error:
        raise FontError("cannot write '%s': %s" % (path, error))


def decode_file(input_path, output_path):
    bin_data = _read(input_path)
    atlas = bin_to_atlas(bin_data)
    bmp = atlas_to_bmp(atlas)
    _write(output_path, bmp)
    print("font.py: %s -> %s (%d glyphs, %dx%d, 4bpp, %d colours)"
          % (input_path, output_path, GLYPH_COUNT, ATLAS_PX, ATLAS_PX, COLOUR_COUNT))
    return bmp


def encode_file(input_path, output_path):
    bmp = _read(input_path)
    atlas, colour_table = bmp_to_atlas(bmp)
    for index, wanted, got in palette_differences(colour_table):
        print("font.py: warning: index %d is RGB%s in the BMP and RGB%s in "
              "PALETTE" % (index, got, wanted), file=sys.stderr)
    bin_data = atlas_to_bin(atlas)
    _write(output_path, bin_data)
    print("font.py: %s -> %s (%d glyphs, %d bytes)"
          % (input_path, output_path, GLYPH_COUNT, len(bin_data)))
    return bin_data


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="font.py",
        description="Convert a Sakura Taisen 256-glyph KNJ font and a 256x256 "
                    "4bpp indexed BMP atlas.")
    commands = parser.add_subparsers(dest="command", required=True)

    decode = commands.add_parser("decode", help="KNJ .BIN -> .bmp atlas")
    decode.add_argument("input", help="input NNNNKNJ.BIN (32768 bytes)")
    decode.add_argument("output", help="output BMP atlas")

    encode = commands.add_parser("encode", help=".bmp atlas -> KNJ .BIN")
    encode.add_argument("input", help="input 256x256 4bpp indexed BMP atlas")
    encode.add_argument("output", help="output NNNNKNJ.BIN")

    args = parser.parse_args(argv)

    try:
        if args.command == "decode":
            decode_file(args.input, args.output)
        else:
            encode_file(args.input, args.output)
    except FontError as error:
        print("font.py: error: %s" % error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
