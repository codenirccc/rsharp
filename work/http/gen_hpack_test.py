"""Generate HPACK conformance vectors for the R# decoder.

The blocks come out of the reference encoder, so the expected decode output is
whatever a spec-compliant decoder must produce for that byte string. Two
sequences: one request-shaped (dynamic table carries across blocks, so indexed
references to entries added by an earlier block get exercised) and one
response-shaped with Huffman.

usage: python gen_hpack_test.py
"""

import pathlib

import hpack
from hpack.huffman import HuffmanEncoder

here = pathlib.Path(__file__).resolve().parent
out = here / 'hpack_vec.rsx'

cases = []

REQ1 = [
    (b':method', b'GET'),
    (b':scheme', b'http'),
    (b':path', b'/'),
    (b':authority', b'www.example.com'),
]
REQ2 = [
    (b':method', b'GET'),
    (b':scheme', b'http'),
    (b':path', b'/'),
    (b':authority', b'www.example.com'),
    (b'cache-control', b'no-cache'),
]
REQ3 = [
    (b':method', b'GET'),
    (b':scheme', b'https'),
    (b':path', b'/index.html'),
    (b':authority', b'www.example.com'),
    (b'custom-key', b'custom-value'),
]

enc = hpack.Encoder()
for hdrs in (REQ1, REQ2, REQ3):
    cases.append((enc.encode(hdrs), [(n.decode('latin-1'), v.decode('latin-1')) for n, v in hdrs]))

RESP1 = [
    (b':status', b'302'),
    (b'cache-control', b'private'),
    (b'date', b'Mon, 21 Oct 2013 20:13:21 GMT'),
    (b'location', b'https://www.example.com'),
]
RESP2 = [
    (b':status', b'307'),
    (b'cache-control', b'private'),
    (b'date', b'Mon, 21 Oct 2013 20:13:21 GMT'),
    (b'location', b'https://www.example.com'),
]
RESP3 = [
    (b':status', b'200'),
    (b'cache-control', b'private'),
    (b'date', b'Mon, 21 Oct 2013 20:13:22 GMT'),
    (b'location', b'https://www.example.com'),
    (b'content-encoding', b'gzip'),
    (b'set-cookie', b'foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1'),
]

enc2 = hpack.Encoder()
for hdrs in (RESP1, RESP2, RESP3):
    cases.append((enc2.encode(hdrs), [(n.decode('latin-1'), v.decode('latin-1')) for n, v in hdrs]))

HARD = [
    (b':status', b'200'),
    (b'x-empty', b''),
    (b'x-long', b'a' * 300),
    (b'set-cookie', b'sessionid=' + b'9f' * 60),
]
enc3 = hpack.Encoder()
cases.append((enc3.encode(HARD, huffman=False), [(n.decode('latin-1'), v.decode('latin-1')) for n, v in HARD]))

huff = HuffmanEncoder(hpack.huffman_constants.REQUEST_CODES, hpack.huffman_constants.REQUEST_CODES_LENGTH)
HUFF_STRINGS = [
    'www.example.com',
    'custom-key',
    'custom-value',
    'no-cache',
    'application/json; charset=utf-8',
    'Mon, 21 Oct 2013 20:13:21 GMT',
    'a',
    '~',
    '0',
    '\x00\x01\x02\x7f',
    'the quick brown fox jumps over the lazy dog',
    'https://www.example.com',
    'gzip',
    'max-age=3600',
]
huff_cases = [(huff.encode(s.encode('latin-1')), s) for s in HUFF_STRINGS]

lines = []
lines.append('fn hvec_cases() -> i64 {')
lines.append(f'    return {len(cases)};')
lines.append('}')
lines.append('')
lines.append('fn hvec_blk(i: i64) -> ptr<u8> {')
lines.append(f'    var t: [ptr<u8>; {len(cases)}] = [')
lines.append(',\n'.join(f'        "{blk.hex()}"' for blk, _ in cases))
lines.append('    ];')
lines.append('    if (i < 0 || i >= ' + str(len(cases)) + ') {')
lines.append('        return "";')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')

flat = []
offsets = [0]
for _, hdrs in cases:
    flat.extend(hdrs)
    offsets.append(len(flat))

lines.append('fn hvec_off(i: i64) -> i64 {')
lines.append(f'    var t: [i64; {len(offsets)}] = [' + ', '.join(str(o) for o in offsets) + '];')
lines.append('    if (i < 0 || i >= ' + str(len(offsets)) + ') {')
lines.append('        return -1;')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')

lines.append('fn hvec_nm(i: i64) -> ptr<u8> {')
lines.append(f'    var t: [ptr<u8>; {len(flat)}] = [')
lines.append(',\n'.join(f'        "{n.encode("latin-1").hex()}"' for n, _ in flat))
lines.append('    ];')
lines.append('    if (i < 0 || i >= ' + str(len(flat)) + ') {')
lines.append('        return "";')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')

lines.append('fn hvec_vl(i: i64) -> ptr<u8> {')
lines.append(f'    var t: [ptr<u8>; {len(flat)}] = [')
lines.append(',\n'.join(f'        "{v.encode("latin-1").hex()}"' for _, v in flat))
lines.append('    ];')
lines.append('    if (i < 0 || i >= ' + str(len(flat)) + ') {')
lines.append('        return "";')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')

lines.append('fn hvec_hn() -> i64 {')
lines.append(f'    return {len(flat)};')
lines.append('}')
lines.append('')
lines.append('fn hvec_hnuff() -> i64 {')
lines.append(f'    return {len(huff_cases)};')
lines.append('}')
lines.append('')
lines.append('fn hvec_huff(i: i64) -> ptr<u8> {')
lines.append(f'    var t: [ptr<u8>; {len(huff_cases)}] = [')
lines.append(',\n'.join(f'        "{blk.hex()}"' for blk, _ in huff_cases))
lines.append('    ];')
lines.append('    if (i < 0 || i >= ' + str(len(huff_cases)) + ') {')
lines.append('        return "";')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')
lines.append('fn hvec_hwant(i: i64) -> ptr<u8> {')
lines.append(f'    var t: [ptr<u8>; {len(huff_cases)}] = [')
lines.append(',\n'.join(f'        "{s.encode("latin-1").hex()}"' for _, s in huff_cases))
lines.append('    ];')
lines.append('    if (i < 0 || i >= ' + str(len(huff_cases)) + ') {')
lines.append('        return "";')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')

out.write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
print(f'wrote {out} ({out.stat().st_size} bytes) cases={len(cases)} headers={len(flat)} huff={len(huff_cases)}')
