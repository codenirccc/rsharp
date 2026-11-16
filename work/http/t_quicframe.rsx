include "../../modules/http/quic_frame.rsx";

struct Tally {
    pass: i64,
    total: i64
}

fn t_ok(t: &mut Tally, name: ptr<u8>, good: bool) {
    t.total += 1;
    if (good) {
        t.pass += 1;
    } else {
        printf("FAIL %s\n", name);
    }
}

fn t_match(got: ptr<u8>, n: i64, hex: ptr<u8>) -> bool {
    if (got == null || n <= 0) {
        return false;
    }
    var eb: [u8; 256] = [0];
    var ep: ptr<u8> = null;
    unsafe { ep = &mut eb[0] as ptr<u8>; }
    let en: i64 = rt_parse_hex(hex, ep, 256);
    if (en != n) {
        return false;
    }
    return rt_bytes_eq(got, ep, n) == 1;
}

fn t_at(base: ptr<u8>, off: i64) -> ptr<u8> {
    var p: ptr<u8> = null;
    unsafe { p = base + off; }
    return p;
}

fn phase_ping(t: &mut Tally) {
    var w: QW = zero(QW);
    if (qw_init(&mut w, 256) != QF_OK) {
        t_ok(t, "writer alloc", false);
        return;
    }
    t_ok(t, "ping write", qw_ping(&mut w) == QF_OK);
    t_ok(t, "ping bytes", t_match(w.b.p, w.b.len, "01"));
    var r: QF = zero(QF);
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "ping read", qf_next(&mut r) == QF_OK);
    t_ok(t, "ping type", r.ty == QF_PING);
    t_ok(t, "ping end", qf_next(&mut r) == QF_END);

    qw_free(&mut w);
    qw_init(&mut w, 256);
    t_ok(t, "handshake done write", qw_handshake_done(&mut w) == QF_OK);
    t_ok(t, "handshake done bytes", t_match(w.b.p, w.b.len, "1e"));
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "handshake done read", qf_next(&mut r) == QF_OK && r.ty == QF_HANDSHAKE_DONE);
    qw_free(&mut w);
}

fn phase_max(t: &mut Tally) {
    var w: QW = zero(QW);
    qw_init(&mut w, 256);
    t_ok(t, "max_data 0", qw_max_data(&mut w, 0) == QF_OK);
    t_ok(t, "max_data 0 bytes", t_match(w.b.p, w.b.len, "1000"));
    qw_free(&mut w);

    qw_init(&mut w, 256);
    t_ok(t, "max_data 64", qw_max_data(&mut w, 64) == QF_OK);
    t_ok(t, "max_data 64 bytes", t_match(w.b.p, w.b.len, "1040 40"));
    var r: QF = zero(QF);
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "max_data read", qf_next(&mut r) == QF_OK);
    t_ok(t, "max_data value", r.ty == QF_MAX_DATA && r.a == 64);
    qw_free(&mut w);

    qw_init(&mut w, 256);
    t_ok(t, "max_stream_data write", qw_max_stream_data(&mut w, 4, 512) == QF_OK);
    t_ok(t, "max_stream_data bytes", t_match(w.b.p, w.b.len, "11044200"));
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "max_stream_data read", qf_next(&mut r) == QF_OK);
    t_ok(t, "max_stream_data fields", r.ty == QF_MAX_STREAM_DATA && r.a == 4 && r.b == 512);
    qw_free(&mut w);

    qw_init(&mut w, 256);
    t_ok(t, "max_streams uni write", qw_max_streams(&mut w, 1, 3) == QF_OK);
    t_ok(t, "max_streams uni bytes", t_match(w.b.p, w.b.len, "1303"));
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "max_streams uni read", qf_next(&mut r) == QF_OK && r.ty == QF_MAX_STREAMS_UNI && r.a == 3);
    qw_free(&mut w);
}

fn phase_crypto(t: &mut Tally) {
    var w: QW = zero(QW);
    var msg: [u8; 8] = [0];
    var mp: ptr<u8> = null;
    unsafe { mp = &mut msg[0] as ptr<u8>; }
    rt_parse_hex("61626364", mp, 8);
    qw_init(&mut w, 256);
    t_ok(t, "crypto write", qw_crypto(&mut w, 0, mp, 4) == QF_OK);
    t_ok(t, "crypto bytes", t_match(w.b.p, w.b.len, "06000461626364"));

    var r: QF = zero(QF);
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "crypto read", qf_next(&mut r) == QF_OK);
    t_ok(t, "crypto fields", r.ty == QF_CRYPTO && r.a == 0 && r.dlen == 4);
    t_ok(t, "crypto payload", rt_eqn(t_at(r.p, r.data), mp, 4) == 1);
    t_ok(t, "crypto end", qf_next(&mut r) == QF_END);
    qw_free(&mut w);

    qw_init(&mut w, 256);
    t_ok(t, "crypto offset write", qw_crypto(&mut w, 4096, mp, 4) == QF_OK);
    t_ok(t, "crypto offset bytes", t_match(w.b.p, w.b.len, "0650000461626364"));
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "crypto offset read", qf_next(&mut r) == QF_OK && r.a == 4096 && r.dlen == 4);
    qw_free(&mut w);

    qw_init(&mut w, 256);
    t_ok(t, "crypto empty write", qw_crypto(&mut w, 0, mp, 0) == QF_OK);
    t_ok(t, "crypto empty bytes", t_match(w.b.p, w.b.len, "060000"));
    qw_free(&mut w);
}

fn phase_stream(t: &mut Tally) {
    var w: QW = zero(QW);
    var msg: [u8; 8] = [0];
    var mp: ptr<u8> = null;
    unsafe { mp = &mut msg[0] as ptr<u8>; }
    rt_parse_hex("48656c6c6f", mp, 8);

    qw_init(&mut w, 256);
    t_ok(t, "stream fin write", qw_stream(&mut w, 0, 0, mp, 5, 1) == QF_OK);
    t_ok(t, "stream fin bytes", t_match(w.b.p, w.b.len, "0b0005 48656c6c6f"));
    var r: QF = zero(QF);
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "stream fin read", qf_next(&mut r) == QF_OK);
    t_ok(t, "stream fin fields", r.ty == 0x0b && r.a == 0 && r.b == 0 && r.dlen == 5 && r.fin == 1);
    qw_free(&mut w);

    qw_init(&mut w, 256);
    t_ok(t, "stream off write", qw_stream(&mut w, 8, 100, mp, 5, 0) == QF_OK);
    t_ok(t, "stream off bytes", t_match(w.b.p, w.b.len, "0e08 4064 05 48656c6c6f"));
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "stream off read", qf_next(&mut r) == QF_OK);
    t_ok(t, "stream off fields", r.a == 8 && r.b == 100 && r.dlen == 5 && r.fin == 0);
    qw_free(&mut w);
}

fn phase_ack(t: &mut Tally) {
    var w: QW = zero(QW);
    qw_init(&mut w, 256);
    t_ok(t, "ack write", qw_ack(&mut w, 5, 0, 5) == QF_OK);
    t_ok(t, "ack bytes", t_match(w.b.p, w.b.len, "0205000005"));
    var r: QF = zero(QF);
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "ack read", qf_next(&mut r) == QF_OK);
    t_ok(t, "ack fields", r.ty == QF_ACK && r.a == 5 && r.b == 0 && r.c == 0 && r.d == 5);
    qw_free(&mut w);

    var raw: [u8; 64] = [0];
    var rp: ptr<u8> = null;
    unsafe { rp = &mut raw[0] as ptr<u8>; }
    let rn: i64 = rt_parse_hex("02050001010a05", rp, 64);
    qf_init(&mut r, rp, rn);
    t_ok(t, "ack with range read", qf_next(&mut r) == QF_OK);
    t_ok(t, "ack with range fields", r.ty == QF_ACK && r.a == 5 && r.c == 1 && r.d == 1);
    t_ok(t, "ack with range end", qf_next(&mut r) == QF_END);

    let bn: i64 = rt_parse_hex("020500000501", rp, 64);
    qf_init(&mut r, rp, bn);
    t_ok(t, "ack followed by next frame", qf_next(&mut r) == QF_OK);
    t_ok(t, "ack trailing frame type", qf_next(&mut r) == QF_OK && r.ty == QF_PING);
}

fn phase_close(t: &mut Tally) {
    var w: QW = zero(QW);
    qw_init(&mut w, 256);
    t_ok(t, "close app write", qw_close(&mut w, 1, 0, 0, null, 0) == QF_OK);
    t_ok(t, "close app bytes", t_match(w.b.p, w.b.len, "1d0000"));
    var r: QF = zero(QF);
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "close app read", qf_next(&mut r) == QF_OK);
    t_ok(t, "close app fields", r.ty == QF_CONNECTION_CLOSE_APP && r.a == 0 && r.dlen == 0);
    qw_free(&mut w);

    qw_init(&mut w, 256);
    var reason: [u8; 8] = [0];
    var rep: ptr<u8> = null;
    unsafe { rep = &mut reason[0] as ptr<u8>; }
    rt_parse_hex("6e6f7065", rep, 8);
    t_ok(t, "close transport write", qw_close(&mut w, 0, 10, 0, rep, 4) == QF_OK);
    t_ok(t, "close transport bytes", t_match(w.b.p, w.b.len, "1c0a00046e6f7065"));
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "close transport read", qf_next(&mut r) == QF_OK);
    t_ok(t, "close transport fields", r.a == 10 && r.b == 0 && r.dlen == 4);
    t_ok(t, "close reason", rt_eqn(t_at(r.p, r.data), rep, 4) == 1);
    qw_free(&mut w);
}

fn phase_cid(t: &mut Tally) {
    var w: QW = zero(QW);
    var cid: [u8; 20] = [0];
    var tok: [u8; 16] = [0];
    var cp: ptr<u8> = null;
    var tp: ptr<u8> = null;
    unsafe { cp = &mut cid[0] as ptr<u8>; tp = &mut tok[0] as ptr<u8>; }
    rt_parse_hex("0102030405060708", cp, 20);
    rt_parse_hex("1112131415161718191a1b1c1d1e1f20", tp, 16);
    qw_init(&mut w, 256);
    t_ok(t, "new cid write", qw_new_cid(&mut w, 1, 0, cp, 8, tp) == QF_OK);
    t_ok(t, "new cid bytes", t_match(w.b.p, w.b.len, "1801000801020304050607081112131415161718191a1b1c1d1e1f20"));
    var r: QF = zero(QF);
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "new cid read", qf_next(&mut r) == QF_OK);
    t_ok(t, "new cid fields", r.ty == QF_NEW_CONNECTION_ID && r.a == 1 && r.b == 0 && r.c == 8 && r.dlen == 0);
    t_ok(t, "new cid cid bytes", rt_eqn(t_at(r.p, r.data), cp, 8) == 1);
    t_ok(t, "new cid token bytes", rt_eqn(t_at(r.p, r.d), tp, 16) == 1);
    qw_free(&mut w);

    qw_init(&mut w, 256);
    t_ok(t, "retire cid write", qw_retire_cid(&mut w, 2) == QF_OK);
    t_ok(t, "retire cid bytes", t_match(w.b.p, w.b.len, "1902"));
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "retire cid read", qf_next(&mut r) == QF_OK && r.a == 2);
    qw_free(&mut w);
}

fn phase_mix(t: &mut Tally) {
    var w: QW = zero(QW);
    var msg: [u8; 8] = [0];
    var mp: ptr<u8> = null;
    unsafe { mp = &mut msg[0] as ptr<u8>; }
    rt_parse_hex("aabb", mp, 8);
    qw_init(&mut w, 256);
    qw_crypto(&mut w, 0, mp, 2);
    qw_ping(&mut w);
    qw_max_data(&mut w, 1048576);
    qw_padding(&mut w, 3);
    qw_stream(&mut w, 4, 0, mp, 2, 1);

    var r: QF = zero(QF);
    qf_init(&mut r, w.b.p, w.b.len);
    t_ok(t, "mix crypto", qf_next(&mut r) == QF_OK && r.ty == QF_CRYPTO && r.dlen == 2);
    t_ok(t, "mix ping", qf_next(&mut r) == QF_OK && r.ty == QF_PING);
    t_ok(t, "mix max data", qf_next(&mut r) == QF_OK && r.ty == QF_MAX_DATA && r.a == 1048576);
    t_ok(t, "mix padding", qf_next(&mut r) == QF_OK && r.ty == QF_PADDING && r.dlen == 3);
    t_ok(t, "mix stream", qf_next(&mut r) == QF_OK && r.ty == 0x0b && r.a == 4 && r.fin == 1);
    t_ok(t, "mix end", qf_next(&mut r) == QF_END);
    qw_free(&mut w);

    var bad: [u8; 8] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut bad[0] as ptr<u8>; }
    let bn: i64 = rt_parse_hex("3f00", bp, 8);
    qf_init(&mut r, bp, bn);
    t_ok(t, "unknown frame rejected", qf_next(&mut r) == QF_ERR);

    let tn: i64 = rt_parse_hex("0600", bp, 8);
    qf_init(&mut r, bp, tn);
    t_ok(t, "truncated frame rejected", qf_next(&mut r) == QF_ERR);

    let en: i64 = rt_parse_hex("0b0009aabb", bp, 8);
    qf_init(&mut r, bp, en);
    t_ok(t, "short stream body rejected", qf_next(&mut r) == QF_ERR);
}

fn main() -> i32 {
    var t: Tally = zero(Tally);
    t.pass = 0;
    t.total = 0;

    phase_ping(&mut t);
    phase_max(&mut t);
    phase_crypto(&mut t);
    phase_stream(&mut t);
    phase_ack(&mut t);
    phase_close(&mut t);
    phase_cid(&mut t);
    phase_mix(&mut t);

    printf("quicframe_passed=%lld of %lld\n", t.pass, t.total);
    if (t.pass == t.total) {
        return 0;
    }
    return 1;
}
