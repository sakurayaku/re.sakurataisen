#!/usr/bin/env python3
# /// script
# dependencies = ["Pillow>=11"]
# ///
"""Build a unique Sakura Taisen 16x16/4bpp glyph corpus and per-font tables.

Requires Pillow: python3 -m pip install Pillow

  python3 sakura_glyphs.py extract --out glyph-work
  # Annotate glyph-work/glyphs.tsv: fill in the unicode column (UTF-8).
  python3 sakura_glyphs.py tables --out glyph-work

Or with uv:
  uv run --with pillow python sakura_glyphs.py extract --include-mes

By default, input files are discovered via `ludared artifacts list` and
resolved via `ludared cache path <artifact>`. Use --input-dir instead to
scan an extracted filesystem tree.
"""
import argparse
import csv
import hashlib
import json
import subprocess
from pathlib import Path

TILE_BYTES = 128


def sources(input_dir, include_mes):
    if input_dir:
        for path in sorted(input_dir.rglob('*')):
            if path.is_file() and (path.name.upper().endswith('KNJ.BIN') or
                (include_mes and path.name.upper().endswith('MES.FNT'))):
                yield str(path.relative_to(input_dir)), path
        return
    lines = subprocess.check_output(['ludared', 'artifacts', 'list'], text=True).splitlines()
    for artifact in lines:
        name = artifact.rsplit('/', 1)[-1].upper()
        if not (name.endswith('KNJ.BIN') or (include_mes and name.endswith('MES.FNT'))):
            continue
        path = subprocess.check_output(['ludared', 'cache', 'path', artifact], text=True).strip()
        if not Path(path).is_file():
            raise RuntimeError(f'Cache file not found for {artifact}: {path}')
        yield artifact, Path(path)


def tile_image(raw):
    from PIL import Image
    # Two pixels per byte; high nibble first, consistent with 4bpp packed tiles.
    pixels = bytearray()
    for byte in raw:
        pixels.extend((byte >> 4, byte & 15))
    im = Image.frombytes('P', (16, 16), bytes(pixels))
    # Index 0 is background; white foreground, grayscale levels for others.
    palette = [0, 0, 0]
    for i in range(1, 16):
        value = 255 if i == 1 else max(30, 255 - (i - 1) * 12)
        palette.extend([value, value, value])
    palette.extend([0] * (768 - len(palette)))
    im.putpalette(palette)
    return im


def extract(args):
    out = args.out
    glyph_dir = out / 'glyphs'
    glyph_dir.mkdir(parents=True, exist_ok=True)
    index = {}
    occurrences = {}
    file_count = 0
    for artifact, path in sources(args.input_dir, args.include_mes):
        raw = path.read_bytes()
        if not raw or len(raw) % TILE_BYTES:
            raise ValueError(f'Not a 128-byte tile array: {artifact} ({len(raw)} bytes)')
        hashes = []
        for pos in range(0, len(raw), TILE_BYTES):
            tile = raw[pos:pos + TILE_BYTES]
            digest = hashlib.sha256(tile).hexdigest()
            if digest not in index:
                index[digest] = tile
                tile_image(tile).save(glyph_dir / f'{digest}.bmp')
                occurrences[digest] = 0
            elif index[digest] != tile:
                raise RuntimeError('SHA-256 collision!')
            occurrences[digest] += 1
            hashes.append(digest)
        # Store original artifact path, not only basename, to avoid collisions.
        file_key = hashlib.sha256(artifact.encode('utf-8')).hexdigest()[:16]
        manifest_path = out / 'fonts' / f'{file_key}.json'
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps({'artifact': artifact, 'tile_hashes': hashes},
                                            ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        file_count += 1
    annotations = out / 'glyphs.tsv'
    old = {}
    if annotations.exists():
        with annotations.open(encoding='utf-8', newline='') as f:
            old = {row['hash']: row.get('unicode', '') for row in csv.DictReader(f, delimiter='\t')}
    with annotations.open('w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, delimiter='\t')
        writer.writerow(['hash', 'unicode', 'occurrences'])
        for digest in sorted(index):
            writer.writerow([digest, old.get(digest, ''), occurrences[digest]])
    print(f'{file_count} font files, {sum(occurrences.values())} tiles, {len(index)} unique glyphs')
    print(f'Annotate: {annotations} (unicode column); BMPs: {glyph_dir}')


def tables(args):
    out = args.out
    with (out / 'glyphs.tsv').open(encoding='utf-8', newline='') as f:
        annotations = {row['hash']: row['unicode'] for row in csv.DictReader(f, delimiter='\t')}
    table_dir = out / 'tables'
    table_dir.mkdir(parents=True, exist_ok=True)
    unresolved = 0
    count = 0
    for manifest in sorted((out / 'fonts').glob('*.json')):
        info = json.loads(manifest.read_text(encoding='utf-8'))
        basename = info['artifact'].rsplit('/', 1)[-1]
        # Preserve unique path identity in filename (disc 1 and 2 can reuse names).
        output = table_dir / f'{Path(basename).stem}_{manifest.stem}.table'
        with output.open('w', encoding='utf-8', newline='') as f:
            f.write(f'# {info["artifact"]}\n')
            f.write('# 1-based glyph ID: binary ID N refers to tile N-1\n')
            for i, digest in enumerate(info['tile_hashes'], 1):
                value = annotations.get(digest, '')
                if not value:
                    unresolved += 1
                    f.write(f'{i:04X}=<UNKNOWN:{digest}>\n')
                else:
                    f.write(f'{i:04X}={value}\n')
        count += 1
    print(f'Wrote {count} tables to {table_dir}; {unresolved} unresolved tile occurrences')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    p_extract = sub.add_parser('extract')
    p_extract.add_argument('--out', type=Path, default=Path('glyph-work'))
    p_extract.add_argument('--input-dir', type=Path, help='Scan local extracted tree instead of Ludared cache')
    p_extract.add_argument('--include-mes', action='store_true', help='Also include MES.FNT (16x16/4bpp)')
    p_tables = sub.add_parser('tables')
    p_tables.add_argument('--out', type=Path, default=Path('glyph-work'))
    args = parser.parse_args()
    (extract if args.command == 'extract' else tables)(args)


if __name__ == '__main__':
    main()
