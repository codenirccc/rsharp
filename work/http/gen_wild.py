import datetime
import json
import pathlib

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.x509.oid import NameOID

certs = pathlib.Path(r'C:\Users\1234.DESKTOP-KICPMJN\Downloads\ms[r\rsharp\work\http\certs')
meta_path = certs / 'meta.json'
meta = json.loads(meta_path.read_text(encoding='utf-8'))

ca_key = serialization.load_pem_private_key((certs / 'ca_key.pem').read_bytes(), None)
ca_der = (certs / 'ca.der').read_bytes()
ca = x509.load_der_x509_certificate(ca_der)

key = __import__('cryptography.hazmat.primitives.asymmetric.rsa', fromlist=['rsa']).generate_private_key(
    public_exponent=65537, key_size=2048)

wild = (
    x509.CertificateBuilder()
    .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'wild.test')]))
    .issuer_name(ca.subject)
    .public_key(key.public_key())
    .serial_number(0x1122334455667788)
    .not_valid_before(datetime.datetime(2024, 6, 1, 0, 0, 0))
    .not_valid_after(datetime.datetime(2026, 6, 1, 0, 0, 0))
    .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
    .add_extension(x509.SubjectAlternativeName([
        x509.DNSName('*.wild.test'),
        x509.DNSName('exact.wild.test'),
        x509.IPAddress(__import__('ipaddress').ip_address('10.20.30.40')),
    ]), critical=False)
    .add_extension(x509.KeyUsage(
        digital_signature=True, content_commitment=False, key_encipherment=True,
        data_encipherment=False, key_agreement=False, key_cert_sign=False,
        crl_sign=False, encipher_only=False, decipher_only=False), critical=True)
    .sign(ca_key, hashes.SHA256())
)

(certs / 'wild.der').write_bytes(wild.public_bytes(serialization.Encoding.DER))
(certs / 'wild_key.pem').write_bytes(key.private_bytes(
    serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption()))

meta['wild_der_hex'] = wild.public_bytes(serialization.Encoding.DER).hex()
meta['wild_nb'] = int(wild.not_valid_before_utc.timestamp())
meta['wild_na'] = int(wild.not_valid_after_utc.timestamp())
meta['wild_serial'] = format(wild.serial_number, 'x')
meta['wild_tbs_len'] = None
meta_path.write_text(json.dumps(meta, indent=1), encoding='utf-8')

print('wild der bytes', len(wild.public_bytes(serialization.Encoding.DER)))
print('wild nb/na', meta['wild_nb'], meta['wild_na'])
