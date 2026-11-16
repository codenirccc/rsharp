"""Local HTTP/3 server for the R# h3 client test.

aioquic supplies QUIC, TLS 1.3, QPACK and the HTTP/3 framing, so a pass here
means the R# side interoperates with an implementation that is not itself.

Routes:
  /hello     200, small body
  /big       20000 bytes, forces several DATA frames on one stream
  /echo      POST, echoes the request body
  /missing   404
  /empty     204, no body

usage: python h3_server.py [port]
"""

import asyncio
import pathlib
import sys

from aioquic.asyncio import QuicConnectionProtocol, serve
from aioquic.h3.connection import H3_ALPN, H3Connection
from aioquic.h3.events import DataReceived, HeadersReceived
from aioquic.quic.configuration import QuicConfiguration
from aioquic.quic.events import ProtocolNegotiated

here = pathlib.Path(__file__).resolve().parent / 'certs'
port = int(sys.argv[1]) if len(sys.argv) > 1 else 4445

BODIES = {
    '/hello': (200, [(b'content-type', b'text/plain')], b'rsharp-h3-ok\n'),
    '/big': (200, [(b'content-type', b'text/plain')], b'x' * 20000),
    '/missing': (404, [(b'content-type', b'text/plain')], b'nope\n'),
    '/empty': (204, [], b''),
}


class Handler(QuicConnectionProtocol):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.http = None
        self.reqs = {}
        self.bodies = {}

    def quic_event_received(self, event):
        if isinstance(event, ProtocolNegotiated):
            self.http = H3Connection(self._quic)
            print(f'alpn={event.alpn_protocol}', flush=True)
        if self.http is None:
            return
        for http_event in self.http.handle_event(event):
            if isinstance(http_event, HeadersReceived):
                path = b'/'
                method = b'GET'
                for name, value in http_event.headers:
                    if name == b':path':
                        path = value
                    if name == b':method':
                        method = value
                self.reqs[http_event.stream_id] = (method, path)
                self.bodies[http_event.stream_id] = b''
                print(f'{method.decode()} {path.decode()} -> {http_event.stream_id}', flush=True)
                if http_event.stream_ended:
                    self.respond(http_event.stream_id)
            elif isinstance(http_event, DataReceived):
                self.bodies[http_event.stream_id] = self.bodies.get(http_event.stream_id, b'') + http_event.data
                if http_event.stream_ended:
                    self.respond(http_event.stream_id)

    def respond(self, stream_id):
        method, path = self.reqs.get(stream_id, (b'GET', b'/'))
        body = self.bodies.get(stream_id, b'')
        if method == b'POST':
            status, headers, out = 200, [(b'content-type', b'text/plain')], body
        else:
            status, headers, out = BODIES.get(path.decode(), BODIES['/missing'])
        self.http.send_headers(
            stream_id,
            [(b':status', str(status).encode())] + headers + [(b'content-length', str(len(out)).encode())],
            end_stream=(len(out) == 0),
        )
        if out:
            self.http.send_data(stream_id, out, end_stream=True)
        self.transmit()
        print(f'-> {status} {len(out)}B', flush=True)


async def main():
    config = QuicConfiguration(is_client=False, alpn_protocols=H3_ALPN)
    config.load_cert_chain(here / 'srv_rsa_chain.pem', here / 'srv_rsa_leaf_key.pem')
    config.max_datagram_frame_size = 65536
    await serve('127.0.0.1', port, configuration=config, create_protocol=Handler)
    (here / f'h3_{port}.pid').write_text(str(__import__('os').getpid()), encoding='ascii')
    print(f'listening h3 on 127.0.0.1:{port}', flush=True)
    await asyncio.Future()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
