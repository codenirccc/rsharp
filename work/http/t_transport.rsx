include "../../modules/http/rt.rsx";
include "../../modules/http/transport_win.rsx";

fn main() -> i32 {
    let ini: i32 = hx_net_init();
    printf("wsastartup=%d\n", ini);
    fflush(null);

    var rb: [u8; 32] = [0];
    var rbp: ptr<u8> = null;
    unsafe { rbp = &mut rb[0] as ptr<u8>; }
    let rr: i32 = hx_random(rbp, 32);
    var ok: i32 = 1;
    var i: i64 = 0;
    while (i < 32) {
        unsafe { if (rb[i] == 0) { ok = 0; } }
        i += 1;
    }
    printf("random=%d nonzero=%d\n", rr, ok);
    fflush(null);

    let s: u64 = hx_connect("127.0.0.1", 8099, 3000, 3000);
    printf("connect=%llu\n", s);
    fflush(null);
    if (s == 0) {
        return 1;
    }

    let req: ptr<u8> = "GET /hello HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\nAccept: */*\r\n\r\n";
    let sent: i64 = hx_send(s, req, strlen(req) as i64);
    printf("sent=%lld\n", sent);
    fflush(null);
    if (sent <= 0) {
        return 2;
    }

    var buf: [u8; 4096] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut buf[0] as ptr<u8>; }
    var total: i64 = 0;
    while (total < 4000) {
        var tb: ptr<u8> = null;
        unsafe { tb = bp + total; }
        let n: i64 = hx_recv(s, tb, 4000 - total);
        if (n <= 0) {
            printf("recv_stop=%lld\n", n);
            break;
        }
        total += n;
    }
    unsafe { buf[total] = 0; }
    printf("total=%lld\n", total);
    printf("----\n%s\n----\n", bp);
    fflush(null);

    hx_close(s);
    hx_net_shutdown();
    return 0;
}
