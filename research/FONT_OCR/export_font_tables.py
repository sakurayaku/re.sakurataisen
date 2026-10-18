#!/usr/bin/env python3
"""Export one ID=Unicode .tbl per OCR font manifest, using the SQLite annotations.

Run from the project root:
  python3 research/FONT_OCR/export_font_tables.py

Reads research/FONT_OCR/glyph-work/fonts/*.json and glyphs.sqlite3;
writes workspace/tables/<font-stem>.tbl.
"""

import argparse
import json
import sqlite3
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', type=Path, default=Path('research/FONT_OCR/glyph-work'))
    parser.add_argument('--output', type=Path, default=Path('workspace/tables'))
    args = parser.parse_args()

    manifests = sorted((args.corpus / 'fonts').glob('*.json'))
    if not manifests:
        parser.error(f'No font manifests in {args.corpus / "fonts"}')

    db_path = args.corpus / 'glyphs.sqlite3'
    if not db_path.is_file():
        parser.error(f'Database not found: {db_path}')
    with sqlite3.connect(db_path) as db:
        annotations = dict(db.execute('SELECT hash, character FROM glyphs'))

    outputs = {}
    for manifest in manifests:
        info = json.loads(manifest.read_text(encoding='utf-8'))
        artifact = info['artifact']
        name = Path(artifact).stem + '.tbl'
        hashes = info['tile_hashes']
        if not hashes:
            raise ValueError(f'Empty font manifest: {manifest}')

        lines = []
        for index, digest in enumerate(hashes, start=1):
            if digest not in annotations:
                raise ValueError(f'Missing OCR annotation: {digest} ({artifact}, glyph {index})')
            glyph = annotations[digest]
            if glyph is None:
                raise ValueError(f'NULL OCR annotation: {digest} ({artifact}, glyph {index})')
            if '\n' in glyph or '\r' in glyph:
                raise ValueError(f'Newline in OCR annotation: {digest} ({artifact}, glyph {index})')
            # Empty strings are meaningful and intentionally preserved.
            lines.append(f'{index:04X}={glyph}\n')
        content = ''.join(lines)
        if name in outputs and outputs[name][0] != content:
            raise ValueError(
                f'Conflicting manifests for {name}: {outputs[name][1]} and {artifact}. '
                'Use distinct output names before exporting.'
            )
        outputs[name] = (content, artifact)

    args.output.mkdir(parents=True, exist_ok=True)
    for name, (content, _) in sorted(outputs.items()):
        (args.output / name).write_text(content, encoding='utf-8')
    print(f'Exported {len(outputs)} tables from {len(manifests)} manifests to {args.output}')


if __name__ == '__main__':
    main()
