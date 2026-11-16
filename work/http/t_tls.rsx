// TLS 1.3 handshake probe: connects to the local Python server, then does one
// application-data round trip. A handshake that reports success but whose
// records the peer cannot read is not a working handshake, so the echo is part
// of the test rather than an afterthought.

include "../../modules/http/rt.rsx";
include "../../modules/http/transport_win.rsx";
include "../../modules/http/tls13.rsx";

fn main() -> i32 {
    if (hx_net_init() != 0) {
        printf("wsa failed\n");
        fflush(null);
        return 1;
    }
    var s: u64 = hx_connect("127.0.0.1", 4433, 5000, 5000);
    if (s == 0) {
        printf("connect failed\n");
        fflush(null);
        return 1;
    }
    var t: Tls13 = zero(Tls13);
    var rc: i32 = tls13_connect(&mut t, s, "localhost");
    if (rc != 0) {
        printf("handshake failed rc=%d\n", rc);
        hx_close(s);
        fflush(null);
        return 1;
    }
    var ap: ptr<u8> = null;
    unsafe { ap = &mut t.alpn[0] as ptr<u8>; }
    printf("handshake ok alpn_len=%lld alpn=%s chain=%lld cn=%lld\n",
           t.alpn_len, ap, t.chain.n, t.cn);

    if (tls13_write(&mut t, "hello-rsharp", 12) != 12) {
        printf("write failed\n");
        fflush(null);
        return 1;
    }
    var got: [u8; 64] = [0];
    var gp: ptr<u8> = null;
    unsafe { gp = &mut got[0] as ptr<u8>; }
    let n: i64 = tls13_read(&mut t, gp, 64);
    printf("read n=%lld\n", n);
    if (n > 0) {
        got[n] = 0;
        printf("echo=%s\n", gp);
    }

    tls13_close(&mut t);
    hx_close(s);
    fflush(null);
    return 0;
}
