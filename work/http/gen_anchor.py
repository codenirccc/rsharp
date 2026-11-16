"""Emit the local CA anchors as R# hex literals for the HTTPS client test.

The client takes anchors from the caller (x509_chain_verify) or from the OS
store (trust_verify). A live server on localhost is only testable through the
caller-supplied path, so the two CA DER files get baked into the test source
the same way the X.509 vectors are.

usage: python gen_anchor.py
"""

import pathlib

here = pathlib.Path(__file__).resolve().parent
certs = here / 'certs'
out = here / 'https_anchor.rsx'

lines = []
for kind in ('rsa', 'ec'):
    der = (certs / f'srv_{kind}_ca.der').read_bytes().hex()
    lines.append(f'fn https_anchor_{kind}(out: ptr<u8>, maxn: i64) -> i64 {{')
    lines.append(f'    return rt_parse_hex("{der}", out, maxn);')
    lines.append('}')
    lines.append('')

out.write_text('\n'.join(lines), encoding='utf-8', newline='\n')
print(f'wrote {out} ({out.stat().st_size} bytes)')
