"""Sanity probe for the aioquic H3 fixture, independent of the R# client."""

import asyncio
import sys

from aioquic.asyncio import QuicConnectionProtocol, connect
from aioquic.h3.connection import H3_ALPN, H3Connection
from aioquic.h3.events import DataReceived, HeadersReceived
from aioquic.quic.configuration import QuicConfiguration

port = int(sys.argv[1]) if len(sys.argv) > 1 else 4445
path = sys.argv[2].encode() if len(sys.argv) > 2 else b'/hello'


class Client(QuicConnectionProtocol):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.http = None
        self.status = None
        self.body = []
        self.done = asyncio.get_event_loop().create_future()

    def quic_event_received(self, event):
        if self.http is None:
            self.http = H3Connection(self._quic)
        for ev in self.http.handle_event(event):
            if isinstance(ev, HeadersReceived):
                for name, value in ev.headers:
                    if name == b':status':
                        self.status = int(value)
            elif isinstance(ev, DataReceived):
                self.body.append(ev.data)
                if ev.stream_ended and not self.done.done():
                    self.done.set_result(True)


async def main():
    config = QuicConfiguration(is_client=True, alpn_protocols=H3_ALPN)
    config.verify_mode = 0
    async with connect('127.0.0.1', port, configuration=config, create_protocol=Client) as proto:
        sid = proto._quic.get_next_available_stream_id()
        proto.http.send_headers(sid, [(b':method', b'GET'), (b':scheme', b'https'),
                                      (b':authority', b'localhost'), (b':path', path)],
                                end_stream=True)
        proto.transmit()
        await asyncio.wait_for(proto.done, 5)
        body = b''.join(proto.body)
        print(f'status={proto.status} len={len(body)} body={body[:32]!r}', flush=True)


asyncio.run(main())
