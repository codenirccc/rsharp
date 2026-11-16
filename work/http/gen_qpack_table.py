"""Emit the QPACK static table as R# source.

usage: python gen_qpack_table.py
"""

import pathlib

from qpack_static import STATIC

here = pathlib.Path(__file__).resolve().parent
out = here.parent.parent / 'modules' / 'http' / 'qpack_tables.rsx'


def esc(v: bytes) -> str:
    s = v.decode('utf-8')
    s = s.replace('\\', '\\\\').replace('"', '\\"')
    return '"' + s + '"'


lines = []
lines.append(f'const QPACK_STATIC_N: i64 = {len(STATIC)};')
lines.append('')
lines.append('fn qpack_static_name(i: i64) -> ptr<u8> {')
lines.append(f'    var t: [ptr<u8>; {len(STATIC)}] = [')
lines.append(',\n'.join('        ' + esc(n) for n, _ in STATIC))
lines.append('    ];')
lines.append(f'    if (i < 0 || i >= {len(STATIC)}) {{')
lines.append('        return "";')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')
lines.append('fn qpack_static_value(i: i64) -> ptr<u8> {')
lines.append(f'    var t: [ptr<u8>; {len(STATIC)}] = [')
lines.append(',\n'.join('        ' + esc(v) for _, v in STATIC))
lines.append('    ];')
lines.append(f'    if (i < 0 || i >= {len(STATIC)}) {{')
lines.append('        return "";')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')

out.write_text('\n'.join(lines), newline='\n')
print(f'wrote {out} entries={len(STATIC)}')
