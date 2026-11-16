include "../../modules/http/rt.rsx";
include "../../modules/http/transport_win.rsx";
include "../../modules/http/quic_tls.rsx";

fn main() -> i32 {
    var t: Tls13 = zero(Tls13);
    var tp: QtTp = zero(QtTp);
    qt_tp_init(&mut tp);
    var scid: [u8; 8] = [0];
    var sp: ptr<u8> = null;
    unsafe { sp = &mut scid[0] as ptr<u8>; }
    rt_parse_hex("0102030405060708", sp, 8);
    var tpb: HxBuf = hxbuf_new(128);
    var rc: i32 = qt_client_tp(&mut tpb, sp, 8);
    printf("tp rc=%d len=%lld\n", rc, tpb.len);
    var parsed: QtTp = zero(QtTp);
    qt_tp_parse(tpb.p, tpb.len, &mut parsed);
    printf("tp scid_len=%lld max_data=%lld max_streams_bidi=%lld max_ack_delay=%lld active_cid=%lld\n",
           parsed.scid_len, parsed.max_data, parsed.max_streams_bidi, parsed.max_ack_delay, parsed.active_cid_limit);
    printf("flight_len empty=%lld\n", qt_flight_len(tpb.p, 0));
    t.phase = 0;
    return 0;
}
