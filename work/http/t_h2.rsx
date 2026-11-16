include "../../modules/http/rt.rsx";
include "../../modules/http/transport_win.rsx";
include "../../modules/http/http2_client.rsx";
include "https_anchor.rsx";

const T_PORT: u16 = 4443;
const T_PORT_EC: u16 = 4444;
const T_PROXY: u16 = 8888;
const T_MAX: i64 = 262144;

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

fn t_pat(p: ptr<u8>, n: i64, mul: i64, add: i64) -> bool {
    if (p == null || n <= 0) {
        return false;
    }
    var i: i64 = 0;
    while (i < n) {
        var v: u8 = 0;
        unsafe { v = p[i]; }
        let w: u8 = (((i * mul + add) & 255) as u8);
        if (v != w) {
            return false;
        }
        i += 1;
    }
    return true;
}

fn t_bodyis(c: &mut H2Conn, want: ptr<u8>) -> bool {
    let n: i64 = h2c_body_len(c);
    if (n != rt_len(want)) {
        return false;
    }
    let p: ptr<u8> = h2c_body(c);
    if (p == null) {
        return false;
    }
    return rt_bytes_eq(p, want, n) == 1;
}

fn phase_basic(c: &mut H2Conn, t: &mut Tally) {
    let al: ptr<u8> = h2c_alpn(c);
    t_ok(t, "alpn h2", rt_eqn(al, "h2", 2) == 1);

    let r1: i32 = h2c_get(c, "/hello");
    let s1: i64 = h2c_status(c);
    let b1: bool = t_bodyis(c, "rsharp-h2-ok\n");
    t_ok(t, "get hello", r1 == H2C_OK && s1 == 200 && b1);

    let hn: i64 = h2c_hdr_count(c);
    t_ok(t, "response headers present", hn >= 3);

    var st: [u8; 8] = [0];
    var sp: ptr<u8> = null;
    unsafe { sp = &mut st[0] as ptr<u8>; }
    let sn: i64 = h2c_hdr_str(c, ":status", 7, sp, 8);
    t_ok(t, "status header decodes", sn == 3 && rt_eqn(sp, "200", 3) == 1);

    let r2: i32 = h2c_get(c, "/keep");
    let s2: i64 = h2c_status(c);
    let b2: bool = t_bodyis(c, "keep\n");
    t_ok(t, "second stream on same conn", r2 == H2C_OK && s2 == 200 && b2);

    let r3: i32 = h2c_get(c, "/missing");
    let s3: i64 = h2c_status(c);
    let b3: bool = t_bodyis(c, "no such thing\n");
    t_ok(t, "404 path", r3 == H2C_OK && s3 == 404 && b3);

    let r4: i32 = h2c_get(c, "/empty");
    let s4: i64 = h2c_status(c);
    let n4: i64 = h2c_body_len(c);
    t_ok(t, "204 no body", r4 == H2C_OK && s4 == 204 && n4 == 0);
}

fn phase_bodies(c: &mut H2Conn, t: &mut Tally) {
    let r5: i32 = h2c_get(c, "/big");
    let s5: i64 = h2c_status(c);
    let n5: i64 = h2c_body_len(c);
    let p5: ptr<u8> = h2c_body(c);
    t_ok(t, "big body received", r5 == H2C_OK && s5 == 200 && n5 == 20000);
    t_ok(t, "big body intact", t_pat(p5, n5, 7, 11));

    let r6: i32 = h2c_get(c, "/huge");
    let s6: i64 = h2c_status(c);
    let n6: i64 = h2c_body_len(c);
    let p6: ptr<u8> = h2c_body(c);
    t_ok(t, "huge body received", r6 == H2C_OK && s6 == 200 && n6 == 200000);
    t_ok(t, "huge body intact", t_pat(p6, n6, 13, 5));
}

fn phase_headers(c: &mut H2Conn, t: &mut Tally) {
    let r7: i32 = h2c_get(c, "/wide");
    let s7: i64 = h2c_status(c);
    t_ok(t, "wide header response", r7 == H2C_OK && s7 == 200);

    var wb: [u8; 32768] = [0];
    var wp: ptr<u8> = null;
    unsafe { wp = &mut wb[0] as ptr<u8>; }
    let wn: i64 = h2c_hdr_str(c, "x-wide", 6, wp, 32768);
    t_ok(t, "continuation reassembled", wn == 24000);

    let r8: i32 = h2c_get(c, "/trailers");
    let s8: i64 = h2c_status(c);
    let b8: bool = t_bodyis(c, "trail-body\n");
    t_ok(t, "trailers body", r8 == H2C_OK && s8 == 200 && b8);

    var tb: [u8; 16] = [0];
    var tp: ptr<u8> = null;
    unsafe { tp = &mut tb[0] as ptr<u8>; }
    let tn: i64 = h2c_hdr_str(c, "x-check", 7, tp, 16);
    t_ok(t, "trailer header captured", tn == 3 && rt_eqn(tp, "yes", 3) == 1);
}

fn phase_ping(c: &mut H2Conn, t: &mut Tally) {
    let r9: i32 = h2c_get(c, "/ping");
    let s9: i64 = h2c_status(c);
    let b9: bool = t_bodyis(c, "pong\n");
    t_ok(t, "ping acknowledged", r9 == H2C_OK && s9 == 200 && b9);
}

fn phase_echo(c: &mut H2Conn, t: &mut Tally) {
    var src: HxBuf = hxbuf_new(40000);
    if (src.p == null) {
        t_ok(t, "echo buffer", false);
        return;
    }
    var i: i64 = 0;
    while (i < 40000) {
        hxbuf_putc(&mut src, (((i * 3 + 1) & 255) as u8));
        i += 1;
    }
    let r10: i32 = h2c_post(c, "/echo", "application/octet-stream", src.p, src.len);
    let s10: i64 = h2c_status(c);
    let n10: i64 = h2c_body_len(c);
    let p10: ptr<u8> = h2c_body(c);
    t_ok(t, "post echo status", r10 == H2C_OK && s10 == 200 && n10 == 40000);
    t_ok(t, "post echo body", t_pat(p10, n10, 3, 1));

    let still: i32 = h2c_get(c, "/hello");
    let code: i64 = h2c_status(c);
    t_ok(t, "connection survives large post", still == H2C_OK && code == 200);
    hxbuf_free(&mut src);
}

fn phase_proxy(t: &mut Tally, anchor: ptr<u8>, alen: i64) {
    var c2: H2Conn = zero(H2Conn);
    let rc: i32 = h2c_init_proxy_anchor(&mut c2, "127.0.0.1", T_PROXY, "localhost", T_PORT, 5000, T_MAX, anchor, alen);
    if (rc != H2C_OK) {
        t_ok(t, "h2 through connect tunnel", false);
        h2c_close(&mut c2);
        return;
    }
    let g: i32 = h2c_get(&mut c2, "/hello");
    let s: i64 = h2c_status(&mut c2);
    let p: ptr<u8> = h2c_body(&mut c2);
    let n: i64 = h2c_body_len(&mut c2);
    let ok: bool = g == H2C_OK && s == 200 && n == 13 && rt_eqn(p, "rsharp-h2-ok\n", 13) == 1;
    t_ok(t, "h2 through connect tunnel", ok);
    h2c_close(&mut c2);
}

fn phase_ec(t: &mut Tally) {
    var eb: [u8; 4096] = [0];
    var ep: ptr<u8> = null;
    unsafe { ep = &mut eb[0] as ptr<u8>; }
    let elen: i64 = https_anchor_ec(ep, 4096);
    if (elen <= 0) {
        t_ok(t, "ec anchor loaded", false);
        return;
    }
    var c3: H2Conn = zero(H2Conn);
    let rc: i32 = h2c_init_anchor(&mut c3, "localhost", T_PORT_EC, 5000, T_MAX, ep, elen);
    if (rc != H2C_OK) {
        t_ok(t, "h2 over ecdsa cert", false);
        h2c_close(&mut c3);
        return;
    }
    let g: i32 = h2c_get(&mut c3, "/hello");
    let s: i64 = h2c_status(&mut c3);
    let p: ptr<u8> = h2c_body(&mut c3);
    let n: i64 = h2c_body_len(&mut c3);
    let ok: bool = g == H2C_OK && s == 200 && n == 13 && rt_eqn(p, "rsharp-h2-ok\n", 13) == 1;
    t_ok(t, "h2 over ecdsa cert", ok);
    h2c_close(&mut c3);
}

fn main() -> i32 {
    var t: Tally = zero(Tally);

    var ab: [u8; 4096] = [0];
    var ap: ptr<u8> = null;
    unsafe { ap = &mut ab[0] as ptr<u8>; }
    let alen: i64 = https_anchor_rsa(ap, 4096);
    if (alen <= 0) {
        printf("anchor rsa failed\n");
        fflush(null);
        return 1;
    }

    var c: H2Conn = zero(H2Conn);
    if (h2c_init_anchor(&mut c, "localhost", T_PORT, 5000, T_MAX, ap, alen) != H2C_OK) {
        printf("h2 handshake failed\n");
        h2c_close(&mut c);
        fflush(null);
        return 2;
    }

    phase_basic(&mut c, &mut t);
    phase_bodies(&mut c, &mut t);
    phase_headers(&mut c, &mut t);
    phase_ping(&mut c, &mut t);
    phase_echo(&mut c, &mut t);
    h2c_close(&mut c);

    phase_proxy(&mut t, ap, alen);
    phase_ec(&mut t);

    printf("h2_passed=%lld of %lld\n", t.pass, t.total);
    fflush(null);
    if (t.pass != t.total) {
        return 3;
    }
    return 0;
}
