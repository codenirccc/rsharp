"""Emit the HPACK constant tables as R# source.

Both tables are transcribed from the library that implements RFC 7541 rather
than typed by hand: 61 static entries and 257 Huffman codes is exactly the kind
of data a human gets subtly wrong.

usage: python gen_hpack.py
"""

import pathlib

from hpack.huffman_constants import REQUEST_CODES, REQUEST_CODES_LENGTH
from hpack.table import HeaderTable

STATIC_TABLE = HeaderTable.STATIC_TABLE

out = pathlib.Path(__file__).resolve().parents[2] / 'modules' / 'http' / 'hpack_tables.rsx'

entries = [(n.decode('latin-1'), v.decode('latin-1')) for n, v in STATIC_TABLE]
assert len(entries) == 61, len(entries)
assert len(REQUEST_CODES) == 257
assert len(REQUEST_CODES_LENGTH) == 257

lines = []
lines.append('const HPACK_STATIC_N: i64 = 61;')
lines.append('const HPACK_HUFF_N: i64 = 257;')
lines.append('')
lines.append('fn hpack_static_name(i: i64) -> ptr<u8> {')
lines.append('    var t: [ptr<u8>; 61] = [')
lines.append(',\n'.join(f'        "{n}"' for n, _ in entries))
lines.append('    ];')
lines.append('    if (i < 0 || i >= 61) {')
lines.append('        return "";')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')
lines.append('fn hpack_static_value(i: i64) -> ptr<u8> {')
lines.append('    var t: [ptr<u8>; 61] = [')
lines.append(',\n'.join(f'        "{v}"' for _, v in entries))
lines.append('    ];')
lines.append('    if (i < 0 || i >= 61) {')
lines.append('        return "";')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')

codes = ', '.join(str(c) for c in REQUEST_CODES)
lines.append('fn hpack_huff_code(i: i64) -> i64 {')
lines.append('    var t: [i64; 257] = [' + codes + '];')
lines.append('    if (i < 0 || i >= 257) {')
lines.append('        return -1;')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')

lens = ', '.join(str(c) for c in REQUEST_CODES_LENGTH)
lines.append('fn hpack_huff_bits(i: i64) -> i64 {')
lines.append('    var t: [i64; 257] = [' + lens + '];')
lines.append('    if (i < 0 || i >= 257) {')
lines.append('        return -1;')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')

text = '\n'.join(lines) + '\n'
out.write_text(text, encoding='utf-8', newline='\n')
print(f'wrote {out} ({out.stat().st_size} bytes)')
