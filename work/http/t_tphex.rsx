include "../../modules/http/rt.rsx";
include "../../modules/http/transport_win.rsx";
include "../../modules/http/quic_tls.rsx";

fn main() -> i32 {
    var tp: QtTp = zero(QtTp);
    qt_tp_init(&mut tp);
    var scid: [u8; 8] = [0];
    var sp: ptr<u8> = null;
    unsafe { sp = &mut scid[0] as ptr<u8>; }
    rt_parse_hex("0102030405060708", sp, 8);
    var b: HxBuf = hxbuf_new(128);
    let rc: i32 = qt_client_tp(&mut b, sp, 8);
    printf("rc=%d len=%lld\n", rc, b.len);
    var i: i64 = 0;
    while (i < b.len) {
        printf("%02x", rt_byte(b.p, i) as i64);
        i += 1;
    }
    printf("\n");
    var t2: Tls13 = zero(Tls13);
    var ch: HxBuf = hxbuf_new(1024);
    let crc: i32 = qt_client_hello(&mut t2, "localhost", sp, 8, &mut ch);
    printf("ch rc=%d len=%lld\n", crc, ch.len);
    i = 0;
    while (i < ch.len) {
        printf("%02x", rt_byte(ch.p, i) as i64);
        i += 1;
    }
    printf("\n");
    return 0;
}
