"""Decode R#'s QPACK encoder output with pylsqpack, the reference codec."""

from pylsqpack import Decoder

blocks = {
    'req_get': '0000d1d7c150096c6f63616c686f7374',
    'resp': '0000d9f454023133',
    'req_post': '0000d451052f6563686f50093132372e302e302e31ee2707782d7273686172702d7472616365056162636465',
    'resp_204': '0000ff015f4d097273686172702d6833',
}

want = {
    'req_get': [(b':method', b'GET'), (b':scheme', b'https'), (b':path', b'/'),
                (b':authority', b'localhost')],
    'resp': [(b':status', b'200'), (b'content-type', b'text/html; charset=utf-8'),
             (b'content-length', b'13')],
    'req_post': [(b':method', b'POST'), (b':path', b'/echo'), (b':authority', b'127.0.0.1'),
                 (b'content-type', b'application/json'), (b'x-rsharp-trace', b'abcde')],
    'resp_204': [(b':status', b'204'), (b'server', b'rsharp-h3')],
}

bad = 0
for tag, hexblk in blocks.items():
    d = Decoder(0, 0)
    ctl, hdrs = d.feed_header(0, bytes.fromhex(hexblk))
    ok = hdrs == want[tag] and ctl == b''
    print(f'{tag}: {"ok" if ok else "FAIL"} {hdrs}')
    if not ok:
        bad += 1

print(f'ref_decoded={len(blocks) - bad} of {len(blocks)}')
raise SystemExit(1 if bad else 0)
