#!/usr/bin/env python3
"""Build and curate a glyph OCR SQLite database. Python 3.9+, stdlib only."""
import argparse
import csv
import hashlib
import sqlite3
import subprocess
import sys
from pathlib import Path

SCHEMA = """
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS glyphs (
    hash TEXT PRIMARY KEY,
    character TEXT DEFAULT NULL
);
CREATE TABLE IF NOT EXISTS candidates (
    hash TEXT NOT NULL REFERENCES glyphs(hash),
    result TEXT NOT NULL,
    source TEXT NOT NULL,
    confidence REAL,
    PRIMARY KEY (hash, result, source)
);
CREATE INDEX IF NOT EXISTS candidates_by_hash ON candidates(hash);
"""


def connect(path):
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)
    return db


def glyph_hash(path):
    stem = path.stem.lower()
    if len(stem) != 64 or any(c not in '0123456789abcdef' for c in stem):
        return None
    return stem


def import_glyphs(db, folder):
    count = 0
    for path in sorted(folder.glob('*.bmp')):
        key = glyph_hash(path)
        if key:
            db.execute('INSERT OR IGNORE INTO glyphs(hash) VALUES (?)', (key,))
            count += 1
    db.commit()
    print(f'Indexed {count} BMP files; {db.execute("SELECT count(*) FROM glyphs").fetchone()[0]} glyphs in DB.')


def add_candidate(db, key, result, source, confidence=None):
    result = result.strip()
    if not result:
        return False
    db.execute('INSERT OR IGNORE INTO glyphs(hash) VALUES (?)', (key,))
    db.execute('''INSERT INTO candidates(hash, result, source, confidence) VALUES (?, ?, ?, ?)
                  ON CONFLICT(hash, result, source) DO UPDATE SET confidence=excluded.confidence''',
               (key, result, source, confidence))
    return True


def import_tsv(db, path, source):
    n = skipped = 0
    with path.open(encoding='utf-8-sig', newline='') as f:
        for line, row in enumerate(csv.reader(f, delimiter='\t'), 1):
            if not row or all(not cell.strip() for cell in row):
                continue
            key = glyph_hash(Path(row[0].strip()))
            if key is None or len(row) < 2:
                skipped += 1
                continue
            confidence = None
            if len(row) > 2 and row[2].strip():
                try:
                    confidence = float(row[2])
                except ValueError:
                    print(f'Warning: invalid confidence at line {line}', file=sys.stderr)
            if add_candidate(db, key, row[1], source, confidence):
                n += 1
    db.commit()
    print(f'Imported {n} candidates from {source}; skipped {skipped} malformed rows (empty OCR results are ignored).')


def run_tesseract(db, folder, psm, language):
    files = sorted(folder.glob('*.bmp'))
    n = 0
    for i, path in enumerate(files, 1):
        key = glyph_hash(path)
        if key is None:
            continue
        proc = subprocess.run(['tesseract', str(path), 'stdout', '-l', language, '--psm', str(psm)],
                              capture_output=True, text=True)
        if proc.returncode:
            print(f'Error: {path.name}: {proc.stderr.strip()}', file=sys.stderr)
            continue
        if add_candidate(db, key, proc.stdout, f'tesseract:psm{psm}'):
            n += 1
        if i % 100 == 0:
            db.commit()
            print(f'Processed {i}/{len(files)}', file=sys.stderr)
    db.commit()
    print(f'Tesseract: {n} nonempty candidates from {len(files)} BMP files.')


def stats(db):
    total, validated = db.execute('SELECT count(*), count(character) FROM glyphs').fetchone()
    with_candidates = db.execute('SELECT count(DISTINCT hash) FROM candidates').fetchone()[0]
    conflicting = db.execute('''SELECT count(*) FROM (
        SELECT hash FROM candidates GROUP BY hash HAVING count(DISTINCT result) > 1
    )''').fetchone()[0]
    print(f'Glyphs: {total}\nValidated: {validated}\nUnvalidated: {total - validated}\nWith candidates: {with_candidates}\nWithout candidates: {total - with_candidates}\nConflicting candidate results: {conflicting}')
    print('By source:')
    for source, n in db.execute('SELECT source, count(*) FROM candidates GROUP BY source ORDER BY source'):
        print(f'  {source}: {n}')


def review(db, folder, limit):
    """Interactive review; only explicit y or confirmed edit writes to SQLite."""
    import shutil

    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise SystemExit('Review requires an interactive terminal.')
    if shutil.which('chafa') is None:
        raise SystemExit('Install chafa first: brew install chafa')

    rows = db.execute("""
        SELECT g.hash
        FROM glyphs g
        LEFT JOIN candidates c ON c.hash = g.hash
        WHERE g.character IS NULL
        GROUP BY g.hash
        ORDER BY
            -- Agreement between Vision and Tesseract
            CASE
                WHEN COUNT(DISTINCT c.source) >= 2
                AND COUNT(DISTINCT c.result) = 1 THEN 0
                WHEN MAX(CASE WHEN c.source = 'vision' THEN 1 ELSE 0 END) = 1
                AND COUNT(DISTINCT c.result) = 1 THEN 1
                WHEN MAX(CASE WHEN c.source = 'vision' THEN 1 ELSE 0 END) = 1 THEN 2
                WHEN COUNT(c.result) > 0 THEN 3
                ELSE 4
            END,

            -- Higher Vision confidence first
            MAX(CASE WHEN c.source = 'vision' THEN c.confidence END) DESC,

            g.hash
        LIMIT ?
    """, (limit,)).fetchall()
    confirmed = 0
    for index, (key,) in enumerate(rows, 1):
        path = folder / (key + '.bmp')
        if not path.is_file():
            print(f'Missing image: {path}', file=sys.stderr)
            continue
        proposals = db.execute("""SELECT result, group_concat(source, ', '), max(confidence)
                                  FROM candidates WHERE hash=? GROUP BY result
                                  ORDER BY count(DISTINCT source) DESC,
                                           max(CASE WHEN source='vision' THEN 1 ELSE 0 END) DESC,
                                           result""", (key,)).fetchall()
        if not proposals:
            continue  # Nothing to confirm; leave the glyph unvalidated.
        proposal_index = 0
        while proposal_index < len(proposals):
            print('\033[2J\033[H', end='', flush=True)
            print(f'Glyph {index}/{len(rows)} | validated this session: {confirmed}')
            print(f'Hash: {key}\n')
            if subprocess.run(['chafa', '--format', 'kitty', '--size', '20x12', str(path)]).returncode:
                raise SystemExit(f'chafa failed: {path}')
            print()
            proposal = proposals[proposal_index] if proposal_index < len(proposals) else None
            if proposal:
                value, sources, confidence = proposal
                score = f' | confidence: {confidence:.2f}' if confidence is not None else ''
                print(f'Proposal {proposal_index + 1}/{len(proposals)}: {value!r}')
                source_list = sources.split(', ')
                if len(source_list) > 1:
                    print(f'Agreement ({len(source_list)} sources): {sources}{score}')
                else:
                    print(f'Source: {sources}{score}')
                print('[y] Validate proposal  [n] Next proposal  [e] Enter Unicode text')
            else:
                print('No more proposals. [e] Enter Unicode text')
            print('[s] Skip glyph  [q] Quit  [Enter] Do nothing')
            try:
                action = input('> ').strip().lower()
            except (EOFError, KeyboardInterrupt):
                print('\nStopped; previous validations saved.')
                return
            if action == 'q':
                print('Stopped; previous validations saved.')
                return
            if action == 's':
                break
            if action == 'n' and proposal:
                proposal_index += 1
                continue  # Exhausting proposals automatically skips this glyph.
            if action == 'y' and proposal:
                chosen = proposal[0]
            elif action == 'e':
                try:
                    chosen = input('Exact Unicode text (blank cancels): ')
                    if not chosen or input(f'Confirm {chosen!r}? Type y: ').strip().lower() != 'y':
                        continue
                except (EOFError, KeyboardInterrupt):
                    print('\nStopped; previous validations saved.')
                    return
            else:
                continue
            db.execute('UPDATE glyphs SET character=? WHERE hash=? AND character IS NULL', (chosen, key))
            db.commit()
            confirmed += 1
            break
    print(f'Review finished: {confirmed} newly validated glyphs.')

def validate(db, key, value):
    key = Path(key).stem.lower()
    if not db.execute('SELECT 1 FROM glyphs WHERE hash=?', (key,)).fetchone():
        raise SystemExit(f'Unknown glyph hash: {key}')
    db.execute('UPDATE glyphs SET character=? WHERE hash=?', (value, key))
    db.commit()
    print(f'{key} -> {value!r} (validated)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', type=Path, default=Path('glyph-work/glyphs.sqlite3'))
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('init', help='Index glyph BMPs (does not overwrite validation)')
    p.add_argument('--glyphs', type=Path, default=Path('glyph-work/glyphs'))
    p = sub.add_parser('import-tsv', help='Import OCR TSV: path<TAB>result<TAB>confidence')
    p.add_argument('file', type=Path)
    p.add_argument('--source', required=True)
    p = sub.add_parser('tesseract', help='Run local Tesseract on all glyph BMPs')
    p.add_argument('--glyphs', type=Path, default=Path('glyph-work/glyphs'))
    p.add_argument('--psm', type=int, default=10)
    p.add_argument('--language', default='jpn')
    sub.add_parser('stats')
    p = sub.add_parser('review', help='Interactive image review in Ghostty (requires chafa)')
    p.add_argument('--glyphs', type=Path, default=Path('glyph-work/glyphs'))
    p.add_argument('--limit', type=int, default=1693)
    p = sub.add_parser('validate', help='Confirm a glyph character (supports multi-character values)')
    p.add_argument('hash')
    p.add_argument('character')
    p = sub.add_parser('clear', help='Remove validation for a glyph')
    p.add_argument('hash')
    args = parser.parse_args()
    args.db.parent.mkdir(parents=True, exist_ok=True)
    with connect(args.db) as db:
        if args.command == 'init':
            import_glyphs(db, args.glyphs)
        elif args.command == 'import-tsv':
            import_tsv(db, args.file, args.source)
        elif args.command == 'tesseract':
            run_tesseract(db, args.glyphs, args.psm, args.language)
        elif args.command == 'stats':
            stats(db)
        elif args.command == 'review':
            review(db, args.glyphs, args.limit)
        elif args.command == 'validate':
            validate(db, args.hash, args.character)
        elif args.command == 'clear':
            validate(db, args.hash, None)


if __name__ == '__main__':
    main()
