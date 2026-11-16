"""Local TLS 1.3 echo server for the R# handshake test.

Pinned to exactly what the client offers: TLS 1.3, TLS_AES_128_GCM_SHA256,
x25519, ALPN h2 + http/1.1. A mismatched parameter is a failure the test should
see, not something the server quietly negotiates around.

usage: python tls_server.py rsa|ec [port]
"""

import pathlib
import socket
import ssl
import sys
import threading

here = pathlib.Path(__file__).resolve().parent / 'certs'
kind = sys.argv[1] if len(sys.argv) > 1 else 'rsa'
port = int(sys.argv[2]) if len(sys.argv) > 2 else 4433

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.minimum_version = ssl.TLSVersion.TLSv1_3
ctx.maximum_version = ssl.TLSVersion.TLSv1_3
ctx.load_cert_chain(here / f'srv_{kind}_chain.pem', here / f'srv_{kind}_leaf_key.pem')
ctx.set_alpn_protocols(['h2', 'http/1.1'])

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('127.0.0.1', port))
srv.listen(8)
(here / f'srv_{kind}_{port}.pid').write_text(str(__import__('os').getpid()), encoding='ascii')
print(f'listening {kind} on 127.0.0.1:{port}', flush=True)


def drain(conn):
    try:
        while True:
            data = conn.recv(4096)
            if not data:
                return
            conn.sendall(data)
    except (ssl.SSLError, OSError):
        pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


while True:
    raw, addr = srv.accept()
    try:
        conn = ctx.wrap_socket(raw, server_side=True)
    except Exception as e:
        print('handshake error:', type(e).__name__, e, flush=True)
        try:
            raw.close()
        except OSError:
            pass
        continue
    print('handshake ok', conn.version(), conn.cipher()[0], conn.selected_alpn_protocol(), flush=True)
    threading.Thread(target=drain, args=(conn,), daemon=True).start()
