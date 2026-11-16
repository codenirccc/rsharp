"""Generate QPACK decode vectors from pylsqpack (the aioquic reference codec).

Every vector is a header block produced by the reference encoder, plus the
header list it was built from. R#'s decoder must reproduce the header list
from the block, which pins the RFC 9204 static table indices to a working
implementation instead of to a transcription.

usage: python gen_qpack_test.py
"""

import pathlib

from pylsqpack import Decoder, Encoder

from qpack_static import STATIC

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / 'qpack_vec.rsx'


def ref_decode(block: bytes) -> list:
    d = Decoder(0, 0)
    ctl, hdrs = d.feed_header(0, block)
    assert ctl == b'', f'decoder emitted control data on a static-only block: {ctl.hex()}'
    return hdrs


def ref_encode(headers: list) -> bytes:
    e = Encoder()
    enc, blk = e.encode(0, list(headers))
    assert enc == b'', f'encoder stream data on a capacity-0 encoder: {enc.hex()}'
    back = ref_decode(blk)
    assert back == list(headers), f'ref round trip failed: {back}'
    return blk


def esc(b: bytes) -> str:
    s = b.decode('utf-8')
    s = s.replace('\\', '\\\\').replace('"', '\\"')
    return '"' + s + '"'


vectors = []

for i, (name, value) in enumerate(STATIC):
    vectors.append((ref_encode([(name, value)]), [(name, value)]))

composites = [
    [(b':method', b'GET'), (b':scheme', b'https'), (b':path', b'/'),
     (b':authority', b'localhost')],
    [(b':status', b'200'), (b'content-type', b'text/html; charset=utf-8'),
     (b'content-length', b'0'), (b'server', b'rsharp')],
    [(b':method', b'POST'), (b':scheme', b'https'), (b':path', b'/echo'),
     (b':authority', b'localhost'), (b'content-type', b'application/json'),
     (b'accept', b'*/*'), (b'user-agent', b'rsharp-http')],
    [(b'x-rsharp-a', b'one'), (b'x-rsharp-b', b'two'), (b'x-rsharp-a', b'one')],
    [(b':status', b'404'), (b'content-length', b'0')],
    [(b':status', b'204')],
]

for hdrs in composites:
    vectors.append((ref_encode(hdrs), hdrs))

# A capacity-0 field section prefix is always the two zero bytes; if that ever
# drifts the vectors stop describing a client that never blocks.
for block, _ in vectors:
    assert block[:2] == b'\x00\x00', f'unexpected prefix {block[:2].hex()}'

flat = []
counts = []
offs = []
for _block, hdrs in vectors:
    offs.append(len(flat))
    counts.append(len(hdrs))
    flat.extend(hdrs)

lines = []
lines.append(f'const QPACK_VEC_N: i64 = {len(vectors)};')
lines.append(f'const QPACK_VEC_H: i64 = {len(flat)};')
lines.append('')


def emit(name: str, typ: str, values: list, zero: str) -> None:
    lines.append(f'fn {name}(i: i64) -> {typ} {{')
    lines.append(f'    var t: [{typ}; {len(values)}] = [')
    lines.append(',\n'.join('        ' + v for v in values))
    lines.append('    ];')
    lines.append(f'    if (i < 0 || i >= {len(values)}) {{')
    lines.append(f'        return {zero};')
    lines.append('    }')
    lines.append('    return t[i];')
    lines.append('}')
    lines.append('')


emit('qvec_block', 'ptr<u8>', ['"' + b.hex() + '"' for b, _ in vectors], '""')
emit('qvec_hn', 'i64', [str(c) for c in counts], '0')
emit('qvec_hoff', 'i64', [str(o) for o in offs], '0')
emit('qvec_hname', 'ptr<u8>', [esc(n) for n, _ in flat], '""')
emit('qvec_hval', 'ptr<u8>', [esc(v) for _, v in flat], '""')

OUT.write_text('\n'.join(lines), newline='\n')
print(f'wrote {OUT} vectors={len(vectors)} headers={len(flat)}')
