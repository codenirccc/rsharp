"""Fetch real chains through the local proxy and record them for the R# tests.

Python 3.12's ssl module only exposes the leaf as DER, so the intermediate comes
from the leaf's CA Issuers URL. Each recorded path is leaf -> intermediate ->
root in the Windows store, which is exactly the walk the R# verifier performs.

Two hosts, on purpose: one RSA end to end and one ECDSA end to end, so both
signature paths get exercised against live certificates rather than fixtures.
"""
import json
import pathlib
import socket
import ssl
import sys
import urllib.request

from cryptography import x509
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa
from cryptography.x509.oid import AuthorityInformationAccessOID

PROXY = 'http://127.0.0.1:1280'
HOSTS = ['www.apple.com', 'www.cloudflare.com']
work = pathlib.Path(r'C:\Users\1234.DESKTOP-KICPMJN\Downloads\ms[r\rsharp\work\http')


def connect_through_proxy(host, port):
    raw = socket.create_connection(('127.0.0.1', 1280), timeout=15)
    req = 'CONNECT %s:%d HTTP/1.1\r\nHost: %s:%d\r\n\r\n' % (host, port, host, port)
    raw.sendall(req.encode('ascii'))
    buf = b''
    while b'\r\n\r\n' not in buf:
        chunk = raw.recv(4096)
        if not chunk:
            raise RuntimeError('proxy closed during CONNECT: %r' % buf)
        buf += chunk
    if b' 200' not in buf.split(b'\r\n')[0]:
        raise RuntimeError('CONNECT failed: %r' % buf.split(b'\r\n')[0])
    return raw


def fetch_leaf(host):
    raw = connect_through_proxy(host, 443)
    ctx = ssl.create_default_context()
    tls = ctx.wrap_socket(raw, server_hostname=host)
    try:
        return tls.getpeercert(binary_form=True), tls.version(), tls.cipher()
    finally:
        tls.close()


def fetch_aia(cert):
    aia = cert.extensions.get_extension_for_class(x509.AuthorityInformationAccess).value
    for desc in aia:
        if desc.access_method == AuthorityInformationAccessOID.CA_ISSUERS:
            url = desc.access_location.value
            opener = urllib.request.build_opener(
                urllib.request.ProxyHandler({'http': PROXY, 'https': PROXY}))
            with opener.open(url, timeout=20) as resp:
                return url, resp.read()
    return None, None


def key_kind(cert):
    k = cert.public_key()
    if isinstance(k, rsa.RSAPublicKey):
        return 'rsa%d' % k.key_size
    if isinstance(k, ec.EllipticCurvePublicKey):
        return 'ec-%s' % k.curve.name
    return type(k).__name__


def verify_with_python(inter, leaf):
    key = inter.public_key()
    if isinstance(key, rsa.RSAPublicKey):
        key.verify(leaf.signature, leaf.tbs_certificate_bytes,
                   padding.PKCS1v15(), leaf.signature_hash_algorithm)
    else:
        key.verify(leaf.signature, leaf.tbs_certificate_bytes,
                   ec.ECDSA(leaf.signature_hash_algorithm))


def main():
    chains = []
    for host in HOSTS:
        try:
            leaf_der, version, cipher = fetch_leaf(host)
        except Exception as exc:
            print(host, 'fetch failed:', exc)
            continue
        leaf = x509.load_der_x509_certificate(leaf_der)
        url, inter_der = fetch_aia(leaf)
        if inter_der is None:
            print(host, 'no CA Issuers URL')
            continue
        inter = x509.load_der_x509_certificate(inter_der)
        verify_with_python(inter, leaf)
        row = {
            'host': host,
            'leaf': leaf_der.hex(),
            'inter': inter_der.hex(),
            'leaf_kind': key_kind(leaf),
            'inter_kind': key_kind(inter),
            'leaf_nb': int(leaf.not_valid_before_utc.timestamp()),
            'leaf_na': int(leaf.not_valid_after_utc.timestamp()),
            'inter_nb': int(inter.not_valid_before_utc.timestamp()),
            'inter_na': int(inter.not_valid_after_utc.timestamp()),
            'leaf_sig_oid': leaf.signature_algorithm_oid.dotted_string,
            'inter_issuer': inter.issuer.rfc4514_string(),
        }
        chains.append(row)
        print(host, version, cipher[0], row['leaf_kind'], '->', row['inter_kind'],
              '-> anchored at', row['inter_issuer'])

    if not chains:
        print('nothing fetched')
        return 2
    (work / 'certs' / 'live.json').write_text(json.dumps({'chains': chains}, indent=1),
                                              encoding='utf-8')
    print('wrote certs/live.json with', len(chains), 'chains')
    return 0


if __name__ == '__main__':
    sys.exit(main())
