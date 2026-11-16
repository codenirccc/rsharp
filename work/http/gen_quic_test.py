"""Emit QUIC v1 packet-protection vectors for the R# QUIC layer.

Everything cryptographic here comes from aioquic, not from the RFC text typed by
hand: initial secrets, packet keys, and the protected packets themselves. A
match means the R# side agrees with a working QUIC implementation byte for byte.

usage: python gen_quic_test.py
"""

import pathlib

from aioquic.quic.crypto import (
    CryptoContext,
    INITIAL_SALT_VERSION_1,
    cipher_suite_hash,
    derive_key_iv_hp,
    hkdf_expand_label,
    hkdf_extract,
)
from aioquic.tls import CipherSuite

here = pathlib.Path(__file__).resolve().parent
out = here / 'quic_vec.rsx'

SUITE = CipherSuite.TLS_AES_128_GCM_SHA256
ALGO = cipher_suite_hash(SUITE)
VERSION = 1


def initial_chain(dcid: bytes) -> dict:
    initial = hkdf_extract(ALGO, INITIAL_SALT_VERSION_1, dcid)
    client = hkdf_expand_label(ALGO, initial, b'client in', b'', 32)
    server = hkdf_expand_label(ALGO, initial, b'server in', b'', 32)
    return {
        'initial': initial,
        'client': client,
        'server': server,
        'c_key': derive_key_iv_hp(cipher_suite=SUITE, secret=client, version=VERSION),
        's_key': derive_key_iv_hp(cipher_suite=SUITE, secret=server, version=VERSION),
    }


def varint(v: int) -> bytes:
    if v < 64:
        return bytes([v])
    if v < 16384:
        return (v | 0x4000).to_bytes(2, 'big')
    if v < 1073741824:
        return (v | 0x80000000).to_bytes(4, 'big')
    return (v | 0xC000000000000000).to_bytes(8, 'big')


def long_header(dcid: bytes, scid: bytes, pn: int, pnlen: int, payload_len: int) -> bytes:
    body = dcid + bytes([len(scid)]) + scid + b'\x00' + varint(pnlen + payload_len + 16) + pn.to_bytes(pnlen, 'big')
    return bytes([0xC0 | (pnlen - 1)]) + b'\x00\x00\x00\x01' + bytes([len(dcid)]) + body


def short_header(dcid: bytes, pn: int, pnlen: int) -> bytes:
    return bytes([0x40 | (pnlen - 1)]) + dcid + pn.to_bytes(pnlen, 'big')


DCID_A = bytes.fromhex('8394c8f03e515708')
DCID_B = bytes.fromhex('c0ffee0001020304')


def payload_a() -> bytes:
    crypto = b'http3-test-clienthello-bytes' * 2
    frame = b'\x06' + varint(len(crypto)) + varint(0) + crypto
    return frame + b'\x00' * 40


def payload_b() -> bytes:
    return b'\x01' + bytes(range(64))


cases = [
    ('a', DCID_A, long_header(DCID_A, b'', 2, 4, len(payload_a())), payload_a(), 2),
    ('b', DCID_B, long_header(DCID_B, DCID_A, 0x1234, 2, len(payload_b())), payload_b(), 0x1234),
    ('c', DCID_A, short_header(DCID_A, 7, 1), b'\x01ping-payload' + b'\x00' * 8, 7),
]

vecs = []
for name, dcid, header, payload, pn in cases:
    chain = initial_chain(dcid)
    ctx = CryptoContext()
    ctx.setup(cipher_suite=SUITE, secret=chain['client'], version=VERSION)
    packet = ctx.encrypt_packet(header, payload, pn)
    vecs.append(
        {
            'name': name,
            'dcid': dcid,
            'header': header,
            'payload': payload,
            'pn': pn,
            'packet': packet,
            'chain': chain,
        }
    )

chain_a = initial_chain(DCID_A)

lines = []


def pstr(name, text):
    lines.append(f'fn {name}() -> ptr<u8> {{')
    lines.append(f'    return "{text}";')
    lines.append('}')
    lines.append('')


pstr('qvec_dcid_a', DCID_A.hex())
pstr('qvec_dcid_b', DCID_B.hex())
pstr('qvec_initial_a', chain_a['initial'].hex())
pstr('qvec_client_secret_a', chain_a['client'].hex())
pstr('qvec_server_secret_a', chain_a['server'].hex())
pstr('qvec_client_key_a', chain_a['c_key'][0].hex())
pstr('qvec_client_iv_a', chain_a['c_key'][1].hex())
pstr('qvec_client_hp_a', chain_a['c_key'][2].hex())
pstr('qvec_server_key_a', chain_a['s_key'][0].hex())
pstr('qvec_server_iv_a', chain_a['s_key'][1].hex())
pstr('qvec_server_hp_a', chain_a['s_key'][2].hex())

lines.append(f'fn qvec_cases() -> i64 {{')
lines.append(f'    return {len(vecs)};')
lines.append('}')
lines.append('')

for field in ('dcid', 'header', 'payload', 'packet'):
    lines.append(f'fn qvec_{field}(i: i64) -> ptr<u8> {{')
    lines.append(f'    var t: [ptr<u8>; {len(vecs)}] = [')
    lines.append(',\n'.join(f'        "{v[field].hex()}"' for v in vecs))
    lines.append('    ];')
    lines.append('    if (i < 0 || i >= ' + str(len(vecs)) + ') {')
    lines.append('        return "";')
    lines.append('    }')
    lines.append('    return t[i];')
    lines.append('}')
    lines.append('')

lines.append('fn qvec_pn(i: i64) -> i64 {')
lines.append('    var t: [i64; ' + str(len(vecs)) + '] = [' + ', '.join(str(v['pn']) for v in vecs) + '];')
lines.append('    if (i < 0 || i >= ' + str(len(vecs)) + ') {')
lines.append('        return -1;')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')

lines.append('fn qvec_ty(i: i64) -> i32 {')
lines.append('    var t: [i32; ' + str(len(vecs)) + '] = [' + ', '.join('0' if v['header'][0] & 0x80 else '-1' for v in vecs) + '];')
lines.append('    if (i < 0 || i >= ' + str(len(vecs)) + ') {')
lines.append('        return -2;')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')

lines.append('fn qvec_pnlen(i: i64) -> i64 {')
lines.append('    var t: [i64; ' + str(len(vecs)) + '] = [' + ', '.join(str((v['header'][0] & 3) + 1) for v in vecs) + '];')
lines.append('    if (i < 0 || i >= ' + str(len(vecs)) + ') {')
lines.append('        return -1;')
lines.append('    }')
lines.append('    return t[i];')
lines.append('}')
lines.append('')

chain_b = initial_chain(DCID_B)
lines.append('fn qvec_initial_b() -> ptr<u8> {')
lines.append(f'    return "{chain_b["initial"].hex()}";')
lines.append('}')
lines.append('')

out.write_text('\n'.join(lines), encoding='utf-8', newline='\n')
print(f'wrote {out} ({out.stat().st_size} bytes) cases={len(vecs)}')
for v in vecs:
    print(f'  {v["name"]}: header={len(v["header"])}B payload={len(v["payload"])}B packet={len(v["packet"])}B')
print('initial_a =', chain_a['initial'].hex())
print('client_key_a =', chain_a['c_key'][0].hex())
