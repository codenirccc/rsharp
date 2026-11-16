import datetime, json, pathlib

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

out_dir = pathlib.Path(r'C:\Users\1234.DESKTOP-KICPMJN\Downloads\ms[r\rsharp\work\http\certs')
out_dir.mkdir(parents=True, exist_ok=True)

key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
name = x509.Name([
    x509.NameAttribute(NameOID.COMMON_NAME, 'R# Test CA'),
    x509.NameAttribute(NameOID.ORGANIZATION_NAME, 'olltaterfx'),
])
ca = (
    x509.CertificateBuilder()
    .subject_name(name)
    .issuer_name(name)
    .public_key(key.public_key())
    .serial_number(0x0123456789ABCDEF)
    .not_valid_before(datetime.datetime(2024, 1, 1, 0, 0, 0))
    .not_valid_after(datetime.datetime(2034, 1, 1, 0, 0, 0))
    .add_extension(x509.BasicConstraints(ca=True, path_length=1), critical=True)
    .add_extension(x509.SubjectAlternativeName([x509.DNSName('ca.test')]), critical=False)
    .sign(key, hashes.SHA256())
)

leaf_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
leaf = (
    x509.CertificateBuilder()
    .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'leaf.test')]))
    .issuer_name(name)
    .public_key(leaf_key.public_key())
    .serial_number(0x0FEDCBA987654321)
    .not_valid_before(datetime.datetime(2024, 6, 1, 0, 0, 0))
    .not_valid_after(datetime.datetime(2026, 6, 1, 0, 0, 0))
    .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
    .add_extension(x509.SubjectAlternativeName([x509.DNSName('example.test')]), critical=False)
    .add_extension(x509.KeyUsage(
        digital_signature=True, content_commitment=False, key_encipherment=True,
        data_encipherment=False, key_agreement=False, key_cert_sign=False,
        crl_sign=False, encipher_only=False, decipher_only=False), critical=True)
    .sign(key, hashes.SHA256())
)

(out_dir / 'ca.der').write_bytes(ca.public_bytes(serialization.Encoding.DER))
(out_dir / 'leaf.der').write_bytes(leaf.public_bytes(serialization.Encoding.DER))
(out_dir / 'ca_key.pem').write_bytes(key.private_bytes(
    serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption()))
(out_dir / 'leaf_key.pem').write_bytes(leaf_key.private_bytes(
    serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption()))

info = {
    'ca_der_hex': ca.public_bytes(serialization.Encoding.DER).hex(),
    'leaf_der_hex': leaf.public_bytes(serialization.Encoding.DER).hex(),
    'ca_serial': format(ca.serial_number, 'x'),
    'leaf_serial': format(leaf.serial_number, 'x'),
    'ca_nb': int(ca.not_valid_before.replace(tzinfo=datetime.timezone.utc).timestamp()),
    'ca_na': int(ca.not_valid_after.replace(tzinfo=datetime.timezone.utc).timestamp()),
    'leaf_nb': int(leaf.not_valid_before.replace(tzinfo=datetime.timezone.utc).timestamp()),
    'leaf_na': int(leaf.not_valid_after.replace(tzinfo=datetime.timezone.utc).timestamp()),
    'sig_oid': '2a864886f70d01010b',
    'ca_modulus_hex': format(key.public_key().public_numbers().n, '0512x'),
    'leaf_modulus_hex': format(leaf_key.public_key().public_numbers().n, '0512x'),
    'leaf_sig_hex': leaf.signature.hex(),
    'ca_tbs_hex': None,
}
raw = leaf.public_bytes(serialization.Encoding.DER)
def tlv_len(b, i):
    if b[i] < 128:
        return b[i], 1
    n = b[i] & 127
    v = 0
    for k in range(n):
        v = (v << 8) | b[i + 1 + k]
    return v, 1 + n

seq_len, seq_hdr = tlv_len(raw, 1)
tbs_off = 1 + seq_hdr
tbs_len, tbs_hdr = tlv_len(raw, tbs_off + 1)
info['leaf_tbs_hex'] = raw[tbs_off:tbs_off + 1 + tbs_hdr + tbs_len].hex()
info['leaf_tbs_len'] = 1 + tbs_hdr + tbs_len
info['leaf_sig_alg_hex'] = raw[-(2 + len(leaf.signature)):].hex()[:0]

(out_dir / 'meta.json').write_text(json.dumps(info, indent=1), encoding='utf-8')
print('ca len', len(raw))
print('leaf tbs len', info['leaf_tbs_len'])
print('serial', info['ca_serial'], info['leaf_serial'])
print('nb/na', info['leaf_nb'], info['leaf_na'])
print('sig', leaf.signature.hex()[:32], '...')
