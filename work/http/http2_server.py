"""Local HTTP/2 server for the R# h2 client test.

Independent implementation: hyper-h2 does the framing and HPACK, OpenSSL does
TLS 1.3, so a pass here means the R# side interoperates with something that is
not itself.

Routes:
  /hello     200, small Content-Length body
  /keep      200, same connection, used to prove streams are independent
  /big       20000 bytes, forces multiple DATA frames
  /huge      200000 bytes, exceeds the 65535 default window, forces the client
             to emit WINDOW_UPDATE mid-body or the transfer stalls
  /missing   404
  /empty     204, no body
  /wide      response header block larger than the client's advertised max
             frame size, so the server has to split HEADERS + CONTINUATION
  /trailers  headers, DATA, then a trailing HEADERS block with END_STREAM
  /ping      server sends PING and refuses to answer until the client ACKs it
  /echo      POST, echoes the request body back after END_STREAM

usage: python http2_server.py rsa|ec [port]
"""

import pathlib
import random
import socket
import ssl
import sys
import threading

import h2.config
import h2.connection
import h2.events

here = pathlib.Path(__file__).resolve().parent / 'certs'
kind = sys.argv[1] if len(sys.argv) > 1 else 'rsa'
port = int(sys.argv[2]) if len(sys.argv) > 2 else 4443

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.minimum_version = ssl.TLSVersion.TLSv1_3
ctx.maximum_version = ssl.TLSVersion.TLSv1_3
ctx.load_cert_chain(here / f'srv_{kind}_chain.pem', here / f'srv_{kind}_leaf_key.pem')
ctx.set_alpn_protocols(['h2'])

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('127.0.0.1', port))
srv.listen(16)
(here / f'srv_{kind}_{port}.pid').write_text(str(__import__('os').getpid()), encoding='ascii')
print(f'listening h2 {kind} on 127.0.0.1:{port}', flush=True)

BIG = bytes((i * 7 + 11) & 0xFF for i in range(20000))
HUGE = bytes((i * 13 + 5) & 0xFF for i in range(200000))

rng = random.Random(20261116)
WIDE = ''.join(chr(33 + rng.randrange(94)) for _ in range(24000))

PING_DATA = b'rsharpx!'
ECHO_PATHS = ('/echo',)


def handle(conn):
    cfg = h2.config.H2Configuration(client_side=False, header_encoding='latin-1')
    h2c = h2.connection.H2Connection(config=cfg)
    h2c.initiate_connection()
    conn.sendall(h2c.data_to_send())

    bodies = {}
    pending = {}
    ping_hold = {}
    deferred = {}
    print(f'conn alpn={conn.selected_alpn_protocol()}', flush=True)

    def flush():
        data = h2c.data_to_send()
        if data:
            conn.sendall(data)

    def pump():
        for sid in list(pending.keys()):
            buf = pending[sid]
            while buf:
                win = h2c.local_flow_control_window(sid)
                if win <= 0:
                    break
                win = min(win, h2c.max_outbound_frame_size)
                chunk = buf[:win]
                buf = buf[win:]
                h2c.send_data(sid, chunk, end_stream=(len(buf) == 0))
            if buf:
                pending[sid] = buf
            else:
                del pending[sid]

    def simple(sid, code, extra, body):
        hdrs = [(':status', code), ('content-type', 'text/plain')]
        hdrs.extend(extra)
        hdrs.append(('content-length', str(len(body))))
        h2c.send_headers(sid, hdrs, end_stream=(len(body) == 0))
        if body:
            pending[sid] = body

    def respond(sid, method, path):
        if path.startswith('/hello'):
            simple(sid, '200', [], b'rsharp-h2-ok\n')
        elif path.startswith('/keep'):
            simple(sid, '200', [], b'keep\n')
        elif path.startswith('/big'):
            simple(sid, '200', [], BIG)
        elif path.startswith('/huge'):
            simple(sid, '200', [], HUGE)
        elif path.startswith('/missing'):
            simple(sid, '404', [], b'no such thing\n')
        elif path.startswith('/empty'):
            h2c.send_headers(sid, [(':status', '204')], end_stream=True)
        elif path.startswith('/wide'):
            simple(sid, '200', [('x-wide', WIDE)], b'wide\n')
        elif path.startswith('/trailers'):
            h2c.send_headers(sid, [(':status', '200'), ('content-type', 'text/plain'),
                                   ('trailer', 'x-check')], end_stream=False)
            h2c.send_data(sid, b'trail-body\n', end_stream=False)
            h2c.send_headers(sid, [('x-check', 'yes')], end_stream=True)
        elif path.startswith('/ping'):
            h2c.ping(PING_DATA)
            ping_hold[sid] = True
        elif path.startswith('/echo'):
            simple(sid, '200', [], bodies.get(sid, b''))
        else:
            simple(sid, '200', [], b'ok\n')
        print(f'{method} {path} -> {sid}', flush=True)

    while True:
        try:
            data = conn.recv(65536)
        except (ssl.SSLError, OSError) as e:
            print('recv error:', type(e).__name__, e, flush=True)
            break
        if not data:
            break
        for ev in h2c.receive_data(data):
            if isinstance(ev, h2.events.RequestReceived):
                hd = dict(ev.headers)
                sid = ev.stream_id
                bodies[sid] = b''
                m = hd.get(':method', 'GET')
                p = hd.get(':path', '/')
                deferred[sid] = (m, p)
                if not p.startswith(ECHO_PATHS):
                    respond(sid, m, p)
                    del deferred[sid]
            elif isinstance(ev, h2.events.DataReceived):
                bodies[ev.stream_id] = bodies.get(ev.stream_id, b'') + ev.data
                h2c.acknowledge_received_data(ev.flow_controlled_length, ev.stream_id)
            elif isinstance(ev, h2.events.StreamEnded):
                sid = ev.stream_id
                if sid in deferred:
                    m, p = deferred.pop(sid)
                    respond(sid, m, p)
            elif isinstance(ev, h2.events.PingAckReceived):
                if ev.ping_data == PING_DATA:
                    for s in list(ping_hold.keys()):
                        del ping_hold[s]
                        simple(s, '200', [], b'pong\n')
                        print(f'ping acked -> {s}', flush=True)
            elif isinstance(ev, h2.events.WindowUpdated):
                pass
            elif isinstance(ev, h2.events.StreamReset):
                pending.pop(ev.stream_id, None)
                deferred.pop(ev.stream_id, None)
                bodies.pop(ev.stream_id, None)
            elif isinstance(ev, h2.events.ConnectionTerminated):
                flush()
                conn.close()
                return
        pump()
        flush()

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
    threading.Thread(target=handle, args=(conn,), daemon=True).start()
