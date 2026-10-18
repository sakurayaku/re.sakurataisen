#!/usr/bin/env python3
"""Decode original Sakura Taisen TBL dialogues using FONT_OCR glyph mappings.

Run from the re.sakurataisen root:
  python3 research/FONT_OCR/extract_dialogues.py path/to/0100TBL.BIN

The matching 0100KNJ.BIN font must already have a manifest in
research/FONT_OCR/glyph-work/fonts/*.json (produced by sakura_glyphs.py).
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_WORK = HERE / "glyph-work"


def u16(data: bytes, offset: int) -> int:
    if offset < 0 or offset + 2 > len(data):
        raise ValueError(f"Read outside file at 0x{offset:X}")
    return struct.unpack_from(">H", data, offset)[0]


def load_font_manifest(fonts_dir: Path, font_name: str, selected: Path | None):
    if selected:
        manifest = json.loads(selected.read_text(encoding="utf-8"))
        if not isinstance(manifest.get("tile_hashes"), list):
            raise ValueError(f"Missing tile_hashes in {selected}")
        return manifest, selected

    matches = []
    for path in sorted(fonts_dir.glob("*.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        artifact = str(doc.get("artifact", "")).replace("\\", "/")
        if Path(artifact).name.casefold() == font_name.casefold():
            matches.append((doc, path))
    if not matches:
        raise ValueError(f"No manifest for {font_name} in {fonts_dir}; use --manifest PATH")
    if len(matches) > 1:
        paths = "\n".join(str(p) for _, p in matches)
        raise ValueError(f"Multiple manifests for {font_name}; choose --manifest:\n{paths}")
    return matches[0]


def parse_tbl(data: bytes):
    if len(data) < 8:
        raise ValueError("TBL file too small")
    header_end = u16(data, 0) * 2
    timing_start = u16(data, 2) * 2
    if not (8 <= header_end <= timing_start <= len(data)) or header_end % 4:
        raise ValueError(f"Invalid header/timing offsets: {header_end:#x}, {timing_start:#x}")

    # Original Saturn TBL: u16 BE header/timing halfword offsets, followed
    # by u16 BE string ID + u16 BE string offset (also in halfwords).
    entries = []
    for pos in range(4, header_end, 4):
        string_id, halfword_offset = struct.unpack_from(">HH", data, pos)
        start = header_end + 2 * halfword_offset
        if not (header_end <= start < timing_start):
            raise ValueError(f"Invalid string offset for ID {string_id:04X}: {start:#x}")
        entries.append((string_id, start))

    result = []
    for ordinal, (string_id, start) in enumerate(entries):
        end = entries[ordinal + 1][1] if ordinal + 1 < len(entries) else timing_start
        if end <= start:
            raise ValueError(f"Non-increasing string offsets at entry {ordinal}")
        if start + 4 > end:
            raise ValueError(f"Missing 4-byte prefix for entry {ordinal}")
        prefix = (u16(data, start), u16(data, start + 2))
        codes = []
        terminated = False
        for pos in range(start + 4, end - 1, 2):
            value = u16(data, pos)
            if value == 0:
                terminated = True
                break
            codes.append(value)
        result.append((ordinal, string_id, start, prefix, codes, terminated))
    return result


def render(codes, tile_hashes, known):
    text = []
    problems = []
    for code in codes:
        if code == 0x0A0D:
            text.append("\\n")
            continue
        tile_index = code - 1  # Game glyph ID N selects font tile N-1.
        if not 0 <= tile_index < len(tile_hashes):
            text.append(f"[CODE:{code:04X}]")
            problems.append(f"code=0x{code:04X} (out of font range)")
            continue
        glyph_hash = tile_hashes[tile_index]
        char = known.get(glyph_hash)
        if char is None:
            text.append(f"[?{code:04X}:{glyph_hash[:12]}]")
            problems.append(f"code=0x{code:04X} tile={tile_index} hash={glyph_hash}")
        else:
            text.append(char)
    return "".join(text), problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("tbl", type=Path, help="Original 0100TBL.BIN (not a patched single-byte TBL)")
    parser.add_argument("--manifest", type=Path, help="Explicit font JSON manifest")
    parser.add_argument("--work", type=Path, default=DEFAULT_WORK, help="FONT_OCR/glyph-work directory")
    parser.add_argument("--output", type=Path, help="Output UTF-8 file (default: FONT_OCR/dialogues/<stem>.txt)")
    args = parser.parse_args()

    tbl = args.tbl
    if not tbl.is_file():
        parser.error(f"File not found: {tbl}")
    font_name = tbl.name[:-7] + "KNJ.BIN"
    manifest, manifest_path = load_font_manifest(args.work / "fonts", font_name, args.manifest)
    hashes = manifest["tile_hashes"]
    with sqlite3.connect(f"file:{(args.work / 'glyphs.sqlite3').resolve()}?mode=ro", uri=True) as db:
        known = dict(db.execute("SELECT hash, character FROM glyphs WHERE character IS NOT NULL"))

    entries = parse_tbl(tbl.read_bytes())
    lines = [f"# Source: {tbl}", f"# Font: {font_name}", f"# Manifest: {manifest_path}",
             f"# Dialogues: {len(entries)}", "# [CODE:XXXX] = out-of-range glyph; [?XXXX:HASH] = unknown glyph", ""]
    unknown = 0
    unterminated = 0
    for ordinal, string_id, offset, prefix, codes, terminated in entries:
        decoded, problems = render(codes, hashes, known)
        unknown += len(problems)
        unterminated += not terminated
        lines.append(f"[{ordinal + 1:04d}] id=0x{string_id:04X} offset=0x{offset:X} prefix={prefix[0]:04X},{prefix[1]:04X}" + (" [UNTERMINATED]" if not terminated else ""))
        lines.append(decoded)
        if problems:
            lines.extend("  # " + p for p in problems)
        lines.append("")

    output = args.output or HERE / "dialogues" / (tbl.name[:-4] + ".txt")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {len(entries)} dialogues to {output}")
    print(f"Unresolved glyph occurrences: {unknown}; unterminated entries: {unterminated}")


if __name__ == "__main__":
    main()
