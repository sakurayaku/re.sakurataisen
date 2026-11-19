#!/usr/bin/env -S uv run --with pillow

import argparse
import struct
from pathlib import Path

from PIL import Image

LINE_HEIGHT = 13    
TEXT_TOP_CROP = 0
TEXT_BOTTOM_CROP = 2
TEXT_HEIGHT = LINE_HEIGHT - TEXT_TOP_CROP - TEXT_BOTTOM_CROP

BACKGROUND = 0
TEXT_BACKGROUND = 1
RIGHT_MARGIN = 1
ALIGNMENT = 8

BORDER_NAMES = (
    "TOP_LEFT", "TOP", "TOP_RIGHT",
    "LEFT", "RIGHT",
    "BOTTOM_LEFT", "BOTTOM", "BOTTOM_RIGHT",
)


def load(path):
    image = Image.open(path)
    if image.mode != "P":
        raise ValueError(f"{path} must be indexed")
    if max(image.getdata()) > 15:
        raise ValueError(f"{path} contains palette indices above 15")
    return image


def paste_tiled(dst, tile, x, y, width, height):
    for ty in range(y, y + height, tile.height):
        for tx in range(x, x + width, tile.width):
            w = min(tile.width, x + width - tx)
            h = min(tile.height, y + height - ty)
            dst.paste(tile.crop((0, 0, w, h)), (tx, ty))


def save_bmp4(image, path):
    width, height = image.size
    stride = ((width + 7) // 8) * 4

    palette = image.getpalette()[:48]
    if len(palette) != 48:
        raise ValueError("Expected a palette with at least 16 colors")

    colors = b"".join(
        bytes((palette[i + 2], palette[i + 1], palette[i], 0))
        for i in range(0, 48, 3)
    )

    rows = []
    for y in range(height - 1, -1, -1):
        pixels = list(image.crop((0, y, width, y + 1)).getdata())
        packed = bytes(
            (pixels[x] << 4) | pixels[x + 1]
            for x in range(0, width, 2)
        )
        rows.append(packed.ljust(stride, b"\0"))

    data = b"".join(rows)
    offset = 14 + 40 + len(colors)

    header = struct.pack("<2sIHHI", b"BM", offset + len(data), 0, 0, offset)
    dib = struct.pack(
        "<IiiHHIIiiII",
        40, width, height, 1, 4, 0,
        len(data), 0, 0, 16, 16,
    )

    path.write_bytes(header + dib + colors + data)


def generate(directory, first, last):
    texts = load(directory / "TEXTS.bmp")
    borders = {
        name: load(directory / f"BORDER_{name}.bmp")
        for name in BORDER_NAMES
    }

    palette = texts.getpalette()
    for name, border in borders.items():
        if border.getpalette()[:48] != palette[:48]:
            raise ValueError(f"BORDER_{name}.bmp has a different palette")

    ul, up, ur = (borders[n] for n in ("TOP_LEFT", "TOP", "TOP_RIGHT"))
    left, right = (borders[n] for n in ("LEFT", "RIGHT"))
    bl, bottom, br = (
        borders[n] for n in ("BOTTOM_LEFT", "BOTTOM", "BOTTOM_RIGHT")
    )

    if not (
        ul.width == left.width == bl.width
        and ur.width == right.width == br.width
        and ul.height == up.height == ur.height
        and bl.height == bottom.height == br.height
    ):
        raise ValueError("Inconsistent border dimensions")

    count = last - first + 1

    if texts.height != count * LINE_HEIGHT:
        raise ValueError(
            f"Expected TEXTS.bmp height {count * LINE_HEIGHT}, "
            f"got {texts.height}"
        )

    for index in range(count):
        number = first + index
        y = index * LINE_HEIGHT

        # strip = texts.crop((0, y, texts.width, y + LINE_HEIGHT))
        strip = texts.crop((0, y + TEXT_TOP_CROP, texts.width, y + LINE_HEIGHT))

        bbox = strip.point(
            lambda value: 255 if value != TEXT_BACKGROUND else 0
        ).getbbox()

        text_width = bbox[2] if bbox else 0
        inner_width = text_width + RIGHT_MARGIN
        content_width = left.width + inner_width + right.width

        width = (
            (content_width + ALIGNMENT - 1) // ALIGNMENT
        ) * ALIGNMENT

        height = up.height + TEXT_HEIGHT + bottom.height

        result = Image.new("P", (width, height), BACKGROUND)
        result.putpalette(palette)
        # Fill the interior with palette index 1.
        result.paste(
            TEXT_BACKGROUND,
            (left.width, up.height, left.width + inner_width, up.height + TEXT_HEIGHT),
        )

        right_x = left.width + inner_width
        bottom_y = up.height + TEXT_HEIGHT

        # Corners
        result.paste(ul, (0, 0))
        result.paste(ur, (right_x, 0))
        result.paste(bl, (0, bottom_y))
        result.paste(br, (right_x, bottom_y))

        # Horizontal borders
        paste_tiled(result, up, left.width, 0, inner_width, up.height)
        paste_tiled(
            result, bottom, left.width, bottom_y,
            inner_width, bottom.height,
        )

        # Vertical borders
        paste_tiled(
            result, left, 0, up.height,
            left.width, TEXT_HEIGHT,
        )
        paste_tiled(
            result, right, right_x, up.height,
            right.width, TEXT_HEIGHT,
        )

        # Text
        result.paste(
            strip.crop((0, 0, text_width, TEXT_HEIGHT)),
            (left.width, up.height),
        )

        output = directory / f"{number:02d}.bmp"
        save_bmp4(result, output)

        print(f"{output.name}: {width}x{height} (text: {text_width}px)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("first", type=int)
    parser.add_argument("last", type=int)
    args = parser.parse_args()

    if args.first < 0 or args.last < args.first:
        parser.error("Invalid image range")

    generate(args.directory, args.first, args.last)


if __name__ == "__main__":
    main()