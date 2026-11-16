"""Local TLS fixtures: two long-dated CA + leaf pairs for `localhost`.

RSA-2048 and ECDSA P-256, both with SAN DNS:localhost and IP:127.0.0.1, valid
from a day ago to ten years out. The earlier fixtures under certs/ were pinned
to 2026-06-01 for the X.509 test vectors and are left alone; these are the pair
the TLS handshake test drives a live server with.
"""

import datetime
import json
import pathlib
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from cryptography.x509.oid import NameOID

out = pathlib.Path(__file__).resolve().parent / 'certs'
out.mkdir(parents=True, exist_ok=True)

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
nb = now - datetime.timedelta(days=1)
na = now + datetime.timedelta(days=3650)


def build(kind):
    if kind == 'rsa':
        ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        leaf_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'R# Local RSA CA')])
        leaf_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')])
        serial_ca = 0x10A
        serial_leaf = 0x10B
    else:
        ca_key = ec.generate_private_key(ec.SECP256R1())
        leaf_key = ec.generate_private_key(ec.SECP256R1())
        ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'R# Local EC CA')])
        leaf_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')])
        serial_ca = 0x20A
        serial_leaf = 0x20B

    ca = (
        x509.CertificateBuilder()
        .subject_name(ca_name)
        .issuer_name(ca_name)
        .public_key(ca_key.public_key())
        .serial_number(serial_ca)
        .not_valid_before(nb)
        .not_valid_after(na)
        .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
        .add_extension(x509.SubjectKeyIdentifier.from_public_key(ca_key.public_key()), critical=False)
        .sign(ca_key, hashes.SHA256())
    )

    leaf = (
        x509.CertificateBuilder()
        .subject_name(leaf_name)
        .issuer_name(ca_name)
        .public_key(leaf_key.public_key())
        .serial_number(serial_leaf)
        .not_valid_before(nb)
        .not_valid_after(na)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(
            x509.SubjectAlternativeName([
                x509.DNSName('localhost'),
                x509.IPAddress(__import__('ipaddress').IPv4Address('127.0.0.1')),
            ]),
            critical=False,
        )
        .add_extension(x509.SubjectKeyIdentifier.from_public_key(leaf_key.public_key()), critical=False)
        .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()), critical=False)
        .add_extension(
            x509.KeyUsage(
                digital_signature=True, content_commitment=False, key_encipherment=True,
                data_encipherment=False, key_agreement=False, key_cert_sign=False,
                crl_sign=False, encipher_only=False, decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
        .sign(ca_key, hashes.SHA256())
    )

    (out / f'srv_{kind}_ca.der').write_bytes(ca.public_bytes(serialization.Encoding.DER))
    (out / f'srv_{kind}_leaf.der').write_bytes(leaf.public_bytes(serialization.Encoding.DER))
    (out / f'srv_{kind}_ca_key.pem').write_bytes(ca_key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    (out / f'srv_{kind}_leaf_key.pem').write_bytes(leaf_key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))

    # Python's ssl module wants a single chain file with the leaf first.
    chain = leaf.public_bytes(serialization.Encoding.PEM) + ca.public_bytes(serialization.Encoding.PEM)
    (out / f'srv_{kind}_chain.pem').write_bytes(chain)

    return {
        'kind': kind,
        'ca_len': len(ca.public_bytes(serialization.Encoding.DER)),
        'leaf_len': len(leaf.public_bytes(serialization.Encoding.DER)),
        'nb': int(ca.not_valid_before.timestamp()),
        'na': int(ca.not_valid_after.timestamp()),
    }


rows = [build('rsa'), build('ec')]
(out / 'srv_meta.json').write_text(json.dumps(rows, indent=1), encoding='utf-8')
for r in rows:
    print(r['kind'], 'ca', r['ca_len'], 'leaf', r['leaf_len'], 'nb', r['nb'], 'na', r['na'])
