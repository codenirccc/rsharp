"""Issue an ECDSA test hierarchy next to the existing RSA one.

Two leaves: one P-256 signed with SHA-256, one P-384 signed with SHA-384. The
CA is P-256 with keyCertSign asserted, because that is what x509_signed_by
requires of an issuer.
"""
import datetime
import json
import pathlib

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

certs = pathlib.Path(r'C:\Users\1234.DESKTOP-KICPMJN\Downloads\ms[r\rsharp\work\http\certs')
meta_path = certs / 'meta.json'
meta = json.loads(meta_path.read_text(encoding='utf-8'))

not_before = datetime.datetime(2025, 1, 1, 0, 0, 0)
not_after = datetime.datetime(2030, 1, 1, 0, 0, 0)

ca_key = ec.generate_private_key(ec.SECP256R1())
ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'RSharp ECDSA Test CA')])
eca = (
    x509.CertificateBuilder()
    .subject_name(ca_name)
    .issuer_name(ca_name)
    .public_key(ca_key.public_key())
    .serial_number(0x0EA01)
    .not_valid_before(not_before)
    .not_valid_after(not_after)
    .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
    .add_extension(x509.KeyUsage(
        digital_signature=True, content_commitment=False, key_encipherment=False,
        data_encipherment=False, key_agreement=False, key_cert_sign=True,
        crl_sign=False, encipher_only=False, decipher_only=False), critical=True)
    .sign(ca_key, hashes.SHA256())
)


def leaf(name, curve, algorithm, serial):
    key = ec.generate_private_key(curve)
    cert = (
        x509.CertificateBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, name)]))
        .issuer_name(ca_name)
        .public_key(key.public_key())
        .serial_number(serial)
        .not_valid_before(not_before)
        .not_valid_after(not_after)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(x509.SubjectAlternativeName([x509.DNSName(name)]), critical=False)
        .add_extension(x509.KeyUsage(
            digital_signature=True, content_commitment=False, key_encipherment=False,
            data_encipherment=False, key_agreement=False, key_cert_sign=False,
            crl_sign=False, encipher_only=False, decipher_only=False), critical=True)
        .sign(ca_key, algorithm)
    )
    return cert


eleaf = leaf('ec.test', ec.SECP256R1(), hashes.SHA256(), 0x0EA02)
eleaf384 = leaf('ec384.test', ec.SECP384R1(), hashes.SHA384(), 0x0EA03)

for name, cert in (('eca', eca), ('eleaf', eleaf), ('eleaf384', eleaf384)):
    (certs / (name + '.der')).write_bytes(cert.public_bytes(serialization.Encoding.DER))
    meta[name + '_der_hex'] = cert.public_bytes(serialization.Encoding.DER).hex()
    meta[name + '_nb'] = int(cert.not_valid_before_utc.timestamp())
    meta[name + '_na'] = int(cert.not_valid_after_utc.timestamp())
    meta[name + '_tbs_len'] = len(cert.tbs_certificate_bytes)
    meta[name + '_sig_len'] = len(cert.signature)

meta_path.write_text(json.dumps(meta, indent=1), encoding='utf-8')
print('eca', len(eca.public_bytes(serialization.Encoding.DER)))
print('eleaf', len(eleaf.public_bytes(serialization.Encoding.DER)))
print('eleaf384', len(eleaf384.public_bytes(serialization.Encoding.DER)))
print('sig lens', len(eca.signature), len(eleaf.signature), len(eleaf384.signature))
