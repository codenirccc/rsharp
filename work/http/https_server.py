"""Local HTTPS server for the R# HTTP/1.1 client test.

Pinned the way tls_server.py is: TLS 1.3 only, ALPN h2 + http/1.1. Every route
exercises one body-framing path, because a parser that only ever sees
Content-Length has not been tested.

usage: python https_server.py rsa|ec [port]
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
srv.listen(16)
(here / f'srv_{kind}_{port}.pid').write_text(str(__import__('os').getpid()), encoding='ascii')
print(f'listening {kind} on 127.0.0.1:{port}', flush=True)

BIG = bytes((i * 7 + 11) & 0xFF for i in range(20000))


def read_line(f):
    line = f.readline()
    if not line:
        return None
    return line


def send(conn, code, headers, body, head_only=False):
    out = [f'HTTP/1.1 {code}\r\n'.encode('latin-1')]
    for k, v in headers:
        out.append(f'{k}: {v}\r\n'.encode('latin-1'))
    out.append(b'\r\n')
    if not head_only:
        out.append(body)
    conn.sendall(b''.join(out))


def serve(conn):
    f = conn.makefile('rb')
    try:
        while True:
            line = read_line(f)
            if line is None:
                return
            line = line.rstrip(b'\r\n')
            if not line:
                continue
            parts = line.split(b' ')
            if len(parts) < 3:
                return
            method = parts[0].decode('latin-1')
            path = parts[1].decode('latin-1')
            hdrs = {}
            while True:
                h = read_line(f)
                if h is None:
                    return
                h = h.rstrip(b'\r\n')
                if not h:
                    break
                k, _, v = h.partition(b':')
                hdrs[k.strip().lower().decode('latin-1')] = v.strip().decode('latin-1')
            body = b''
            if 'content-length' in hdrs:
                body = f.read(int(hdrs['content-length']))
            keep = hdrs.get('connection', 'keep-alive').lower() != 'close'
            def reply(sock, code, headers, body):
                send(sock, code, headers, body, method == 'HEAD')
            ch = [('Content-Type', 'text/plain')]
            if not keep:
                ch.append(('Connection', 'close'))

            if path.startswith('/hello'):
                reply(conn, '200 OK', ch + [('Content-Length', '16')], b'rsharp-https-ok\n')
            elif path.startswith('/hdr'):
                v = hdrs.get('x-rsharp', 'none').encode('latin-1')
                reply(conn, '200 OK', ch + [('Content-Length', str(len(v)))], v)
            elif path.startswith('/keep'):
                reply(conn, '200 OK', ch + [('Content-Length', '5')], b'keep\n')
            elif path.startswith('/chunked'):
                head = [f'HTTP/1.1 200 OK\r\n'.encode('latin-1')]
                for k, v in ch:
                    head.append(f'{k}: {v}\r\n'.encode('latin-1'))
                head.append(b'Transfer-Encoding: chunked\r\n\r\n')
                conn.sendall(b''.join(head))
                for piece in (b'alpha-', b'beta-', b'gamma'):
                    conn.sendall(f'{len(piece):x};x=1\r\n'.encode('latin-1'))
                    conn.sendall(piece + b'\r\n')
                conn.sendall(b'0\r\nX-Trail: yes\r\n\r\n')
            elif path.startswith('/big'):
                reply(conn, '200 OK', ch + [('Content-Length', str(len(BIG)))], BIG)
            elif path.startswith('/missing'):
                reply(conn, '404 Not Found', ch + [('Content-Length', '14')], b'no such thing\n')
            elif path.startswith('/empty'):
                reply(conn, '204 No Content', ch + [('Content-Length', '0')], b'')
            elif path.startswith('/redirect'):
                reply(conn, '302 Found', ch + [('Content-Length', '0'), ('Location', '/hello')], b'')
            elif path.startswith('/continue'):
                conn.sendall(b'HTTP/1.1 100 Continue\r\n\r\n')
                reply(conn, '200 OK', ch + [('Content-Length', '10')], b'after-1xx\n')
            elif path.startswith('/echo'):
                reply(conn, '200 OK', ch + [('Content-Length', str(len(body)))], body)
            else:
                reply(conn, '200 OK', ch + [('Content-Length', '3')], b'ok\n')
            print(f'{method} {path} -> done', flush=True)
            if not keep:
                return
    except (ssl.SSLError, OSError) as e:
        print('conn error:', type(e).__name__, e, flush=True)
    finally:
        try:
            f.close()
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
    threading.Thread(target=serve, args=(conn,), daemon=True).start()
