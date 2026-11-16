"""Minimal CONNECT tunnel so the HTTPS client's proxy path is exercised.

It does nothing but splice bytes: the TLS session still terminates at the
target, so the client's certificate and host checks run unchanged.

usage: python proxy_server.py [port]
"""

import os
import socket
import sys
import threading

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8888

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('127.0.0.1', port))
srv.listen(8)
open(f'proxy_{port}.pid', 'w').write(str(os.getpid()))
print(f'proxy listening on 127.0.0.1:{port}', flush=True)


def pump(a, b):
    try:
        while True:
            data = a.recv(65536)
            if not data:
                break
            b.sendall(data)
    except OSError:
        pass
    finally:
        try:
            b.shutdown(socket.SHUT_WR)
        except OSError:
            pass


while True:
    raw, _ = srv.accept()
    f = raw.makefile('rb')
    line = f.readline().decode('latin-1').strip()
    target = line.split(' ')[1] if len(line.split(' ')) > 1 else ''
    while True:
        h = f.readline()
        if not h or h in (b'\r\n', b'\n'):
            break
    host, _, p = target.rpartition(':')
    try:
        up = socket.create_connection((host, int(p)), timeout=10)
    except OSError as e:
        raw.sendall(b'HTTP/1.1 502 Bad Gateway\r\n\r\n')
        print('connect failed:', e, flush=True)
        raw.close()
        continue
    raw.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
    print('tunnel', target, flush=True)
    threading.Thread(target=pump, args=(raw, up), daemon=True).start()
    threading.Thread(target=pump, args=(up, raw), daemon=True).start()
