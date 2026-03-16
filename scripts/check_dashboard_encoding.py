#!/usr/bin/env python3
"""Dashboard encoding gate: detect non-ASCII characters that cause mojibake.

Scans all dashboard JSON files for non-ASCII byte sequences that commonly
render as garbled text when encoding is mishandled anywhere in the chain
(editor, git, Grafana, browser).  Emojis are allowed in dashboard titles
and text-panel content where they are used intentionally for visual branding.

Exit codes:
    0  all clear
    1  violations found
    2  runtime error

Usage:
    python scripts/check_dashboard_encoding.py [--json] [--fix]
"""
import json
import os
import re
import sys

# ---------------------------------------------------------------------------
# Replacement table: (byte_sequence, ascii_replacement, human_label)
# ---------------------------------------------------------------------------
REPLACEMENTS = [
    # Greek
    (b'\xce\x94', b'Delta', 'greek capital delta'),
    # Latin punctuation
    (b'\xc3\x97', b'x', 'multiplication sign'),
    (b'\xc3\xb7', b'/', 'division sign'),
    # Typographic quotes and dashes
    (b'\xe2\x80\x93', b'-', 'en dash'),
    (b'\xe2\x80\x94', b'--', 'em dash'),
    (b'\xe2\x80\x98', b"'", 'left single quote'),
    (b'\xe2\x80\x99', b"'", 'right single quote'),
    (b'\xe2\x80\x9c', b'"', 'left double quote'),
    (b'\xe2\x80\x9d', b'"', 'right double quote'),
    # Symbols
    (b'\xe2\x80\xa2', b'*', 'bullet'),
    (b'\xe2\x80\xa6', b'...', 'ellipsis'),
    (b'\xe2\x89\xa4', b'<=', 'less-than-or-equal'),
    (b'\xe2\x89\xa5', b'>=', 'greater-than-or-equal'),
    # Whitespace
    (b'\xc2\xa0', b' ', 'non-breaking space'),
    # Accented (common in copy-paste from web)
    (b'\xc3\xa9', b'e', 'e-acute'),
    (b'\xc3\xa8', b'e', 'e-grave'),
]

# Byte prefixes that indicate emoji sequences (F0 xx = 4-byte, EF B8 8F = VS16)
# These are intentional in titles/content and should be skipped.
EMOJI_PREFIXES = (b'\xf0', b'\xef\xb8\x8f')

DASHBOARD_DIR = os.path.join('grafana', 'provisioning', 'dashboards')


def scan_file(fpath):
    """Return list of (line_no, count, label) tuples for violations."""
    with open(fpath, 'rb') as f:
        raw = f.read()

    violations = []
    for pattern, _repl, label in REPLACEMENTS:
        # Count total occurrences
        count = raw.count(pattern)
        if count:
            # Find line numbers
            offset = 0
            while True:
                idx = raw.find(pattern, offset)
                if idx == -1:
                    break
                line_no = raw[:idx].count(b'\n') + 1
                violations.append((line_no, label))
                offset = idx + len(pattern)

    return violations


def fix_file(fpath):
    """Replace all mojibake patterns in a file. Returns (changed, details)."""
    with open(fpath, 'rb') as f:
        raw = f.read()

    original = raw
    details = []
    for pattern, replacement, label in REPLACEMENTS:
        count = raw.count(pattern)
        if count:
            # When replacing curly quotes with straight quotes inside JSON
            # strings, the straight quote must be escaped to avoid breaking
            # JSON syntax.  Try unescaped first; fall back to escaped.
            candidate = raw.replace(pattern, replacement)
            try:
                json.loads(candidate.decode('utf-8'))
                raw = candidate
            except (json.JSONDecodeError, UnicodeDecodeError):
                if replacement in (b'"', b"'"):
                    escaped = b'\\' + replacement
                    raw = raw.replace(pattern, escaped)
                else:
                    # Non-quote replacement broke JSON — skip this pattern
                    continue
            details.append((label, count))

    if raw != original:
        # Validate JSON before writing
        try:
            json.loads(raw.decode('utf-8'))
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            return False, [('JSON validation failed after fix', str(e))]
        with open(fpath, 'wb') as f:
            f.write(raw)
        return True, details

    return False, details


def main():
    as_json = '--json' in sys.argv
    do_fix = '--fix' in sys.argv

    if not os.path.isdir(DASHBOARD_DIR):
        print(f'Dashboard directory not found: {DASHBOARD_DIR}', file=sys.stderr)
        sys.exit(2)

    results = []
    total_violations = 0

    for fname in sorted(os.listdir(DASHBOARD_DIR)):
        if not fname.endswith('.json'):
            continue
        fpath = os.path.join(DASHBOARD_DIR, fname)

        if do_fix:
            changed, details = fix_file(fpath)
            if changed:
                results.append({
                    'file': fname,
                    'fixed': True,
                    'replacements': [
                        {'character': label, 'count': count}
                        for label, count in details
                    ],
                })
                total_violations += sum(c for _, c in details)
        else:
            violations = scan_file(fpath)
            if violations:
                results.append({
                    'file': fname,
                    'violations': [
                        {'line': ln, 'character': label}
                        for ln, label in violations
                    ],
                })
                total_violations += len(violations)

    passed = total_violations == 0

    if as_json:
        output = {
            'ok': passed,
            'mode': 'fix' if do_fix else 'check',
            'dashboard_dir': DASHBOARD_DIR,
            'files_checked': len([
                f for f in os.listdir(DASHBOARD_DIR) if f.endswith('.json')
            ]),
            'total_violations': total_violations,
            'details': results,
        }
        # Force UTF-8 output
        sys.stdout.buffer.write(
            json.dumps(output, indent=2, ensure_ascii=True).encode('utf-8')
        )
        sys.stdout.buffer.write(b'\n')
    else:
        if do_fix and results:
            for r in results:
                print(f"Fixed {r['file']}:")
                for rep in r['replacements']:
                    print(f"  {rep['count']}x {rep['character']}")
            print(f'\nFixed {total_violations} characters across {len(results)} files.')
        elif not do_fix and results:
            for r in results:
                print(f"{r['file']}:")
                for v in r['violations']:
                    print(f"  line {v['line']}: {v['character']}")
            print(f'\n{total_violations} violations across {len(results)} files.')
        else:
            action = 'Fixed' if do_fix else 'Found'
            print(f'{action} 0 encoding issues.')

    sys.exit(0 if passed or do_fix else 1)


if __name__ == '__main__':
    main()
