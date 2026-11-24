#!/usr/bin/env python3
# /// script
# dependencies = [
#   "Pillow==12.3.0",
# ]
# ///

import argparse
import math

from PIL import Image, ImageDraw, ImageFont

CELL = 16
COLS = 16
ROWS = 16

# Baseline commune à toutes les cellules.
BASELINE = 11

# Décalage horizontal pour conserver une petite marge.
LEFT_MARGIN = 1

# adv_dialogue_jp, avec l'index 15 rouge comme marqueur d'éditeur.
JP_PALETTE = [
    0x7FFF, 0x0842, 0x1084, 0x18C6,
    0x2108, 0x294A, 0x318C, 0x39CE,
    0x4210, 0x4A52, 0x5294, 0x5AD6,
    0x6318, 0x6B5A, 0x739C, 0x001F,
]

# Poids des indices de la police JP d'origine (0100KNJ.BIN, 629 tuiles).
INK_WEIGHTS = {
    1: 15736, 2: 1529, 3: 12677, 6: 2663, 7: 14409,
    8: 721, 9: 3470, 11: 10063, 13: 4587, 14: 1112,
}
FONT_INDICES = (0,) + tuple(INK_WEIGHTS)

# Override glyphs by atlas tile index (0x00..0xFE).
OVERRIDE_GLYPHS = {
    # Music Notes
    0x00: "♪",
    0x01: "♫",
    0x02: "♬",
    # Gender symbols
    0x03: "♀",
    0x04: "♂",
    # Random symbols
    0x05: "★",
    0x06: "♠",
    0x07: "♣",
    0x08: "♥",
    0x09: "♦",
    0x0A: "☼",
    0x0B: "☽",
    0x0C: "♨",
    0x0D: "☎",
    0x0E: "✉",
}


def bgr555_to_rgb(value):
    r = (value & 0x1F) * 255 // 31
    g = ((value >> 5) & 0x1F) * 255 // 31
    b = ((value >> 10) & 0x1F) * 255 // 31
    return (r, g, b)


def to_indexed_atlas(image):
    palette = [bgr555_to_rgb(c) for c in JP_PALETTE]

    # Palette Pillow : 256 entrées RGB.
    flat_palette = [
        component
        for rgb in palette
        for component in rgb
    ]
    flat_palette += [0] * (768 - len(flat_palette))

    indexed = Image.new("P", image.size)
    indexed.putpalette(flat_palette)

    gray = [rgb[0] for rgb in image.convert("RGB").getdata()]
    ink = [pos for pos, value in enumerate(gray) if value < 255]
    ink.sort(key=lambda pos: gray[pos])

    weights = list(INK_WEIGHTS.items())
    total = sum(weight for _, weight in weights)
    pixels = [0] * len(gray)

    for rank, pos in enumerate(ink, 1):
        limit = rank * total // len(ink)
        cumulative = 0
        for index, weight in weights:
            cumulative += weight
            if limit <= cumulative:
                pixels[pos] = index
                break

    indexed.putdata(pixels)

    return indexed

def main():
    parser = argparse.ArgumentParser(
        description="Generate a Sakura Taisen font atlas from a TTF."
    )

    parser.add_argument("font", help="Input TTF font")
    parser.add_argument("--size", type=int, default=12)
    parser.add_argument("--output", default="FONT.bmp")
    parser.add_argument("--table", default="I18N_FONT.tbl")

    args = parser.parse_args()

    font = ImageFont.truetype(args.font, args.size)

    atlas = Image.new(
        "RGB",
        (COLS * CELL, ROWS * CELL),
        "white",
    )

    table = []
    warnings = []

    for tile_index, char in OVERRIDE_GLYPHS.items():
        if not isinstance(tile_index, int) or not 0 <= tile_index < 255:
            parser.error(f"Invalid override index: {tile_index!r}")
        if not isinstance(char, str) or len(char) != 1:
            parser.error(f"Override 0x{tile_index:02X} must be one Unicode character")

    for code in range(1, 256):
        tile_index = code - 1
        char = OVERRIDE_GLYPHS.get(tile_index)

        if char is None:
            try:
                char = bytes([code]).decode("cp1252")
            except UnicodeDecodeError:
                continue

            # Skip control characters unless explicitly overridden.
            if code < 32 or code == 127:
                continue

        col = tile_index % COLS
        row = tile_index // COLS

        x = col * CELL
        y = row * CELL

        # Glyph advance from the original TTF.
        advance = max(1, math.ceil(font.getlength(char)))

        # Individual glyph bounding box relative to its baseline.
        bbox = font.getbbox(char, anchor="ls")

        if bbox is None:
            continue

        left, top, right, bottom = bbox

        # Render the glyph into an isolated tile.
        tile = Image.new("RGB", (CELL, CELL), "white")
        draw = ImageDraw.Draw(tile)

        draw.text(
            (LEFT_MARGIN, BASELINE),
            char,
            font=font,
            fill="black",
            anchor="ls",
        )

        # Detect glyphs extending outside their cell.
        if (
            LEFT_MARGIN + left < 0
            or LEFT_MARGIN + right > CELL
            or BASELINE + top < 0
            or BASELINE + bottom > CELL
        ):
            warnings.append(
                f"0x{code:02X} {char!r}: "
                f"bbox={bbox}, advance={advance}"
            )

        atlas.paste(tile, (x, y))

        # Account for the left margin in the engine's advance.
        width = advance + LEFT_MARGIN

        table.append(
            f"{code:04X}={width}={char}"
        )

    indexed = to_indexed_atlas(atlas)
    save_bmp_4bpp(indexed, args.output)

    with open(args.table, "w", encoding="utf-8") as f:
        f.write("\n".join(table))

    print(f"Atlas: {args.output}")
    print(f"Table: {args.table}")
    print(f"Glyphs: {len(table)}")

    if warnings:
        print(f"\nWARNING: {len(warnings)} glyphs exceed their cells:")
        for warning in warnings:
            print(" ", warning)

import struct

def save_bmp_4bpp(image, path):
    width, height = image.size
    assert width == height == 256

    pixels = list(image.getdata())
    assert all(p in FONT_INDICES for p in pixels)

    palette = [bgr555_to_rgb(c) for c in JP_PALETTE]

    # Deux pixels par octet.
    row_size = ((width + 7) // 8) * 4
    pixel_data = bytearray()

    # BMP stocke les lignes de bas en haut.
    for y in range(height - 1, -1, -1):
        row = pixels[y * width:(y + 1) * width]

        packed = bytearray(
            (row[x] << 4) | row[x + 1]
            for x in range(0, width, 2)
        )

        packed.extend(b"\0" * (row_size - len(packed)))
        pixel_data.extend(packed)

    # Palette BMP : BGRA, 4 octets par couleur.
    color_table = b"".join(
        struct.pack("<BBBB", b, g, r, 0)
        for r, g, b in palette
    )

    pixel_offset = 14 + 40 + len(color_table)
    file_size = pixel_offset + len(pixel_data)

    with open(path, "wb") as f:
        # BITMAPFILEHEADER
        f.write(struct.pack(
            "<2sIHHI",
            b"BM", file_size, 0, 0, pixel_offset
        ))

        # BITMAPINFOHEADER
        f.write(struct.pack(
            "<IiiHHIIiiII",
            40, width, height, 1, 4, 0,
            len(pixel_data), 2835, 2835, 16, 16
        ))

        f.write(color_table)
        f.write(pixel_data)


if __name__ == "__main__":
    main()