include "../../modules/http/rt.rsx";
include "../../modules/http/http1_client.rsx";
include "https_anchor.rsx";

const T_PORT: u16 = 4433;
const T_PORT_EC: u16 = 4434;
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

fn t_is(c: &mut H1Conn, want: ptr<u8>) -> bool {
    let p: ptr<u8> = h1c_body_str(c);
    if (p == null) {
        return false;
    }
    return rt_eq(p, want) == 1;
}

fn t_dial(c: &mut H1Conn, port: u16, a: ptr<u8>, alen: i64) -> i32 {
    return h1c_init_anchor(c, "localhost", port, 5000, T_MAX, a, alen);
}

fn main() -> i32 {
    var t: Tally = zero(Tally);
    t.pass = 0;
    t.total = 0;

    var ab: [u8; 4096] = [0];
    var ap: ptr<u8> = null;
    unsafe { ap = &mut ab[0] as ptr<u8>; }
    let alen: i64 = https_anchor_rsa(ap, 4096);
    if (alen <= 0) {
        printf("anchor rsa failed\n");
        fflush(null);
        return 1;
    }

    var c: H1Conn = zero(H1Conn);
    if (t_dial(&mut c, T_PORT, ap, alen) != H1C_OK) {
        printf("handshake failed\n");
        h1c_close(&mut c);
        fflush(null);
        return 2;
    }

    var alpn: [u8; 32] = [0];
    var alnp: ptr<u8> = null;
    unsafe { alnp = &mut alpn[0] as ptr<u8>; }
    let an: i64 = https_alpn(&mut c.h, alnp);
    let alpn_ok: bool = (an == 8) && (rt_eq(alnp, "http/1.1") == 1);
    t_ok(&mut t, "alpn http/1.1", alpn_ok);

    let r1: i32 = h1c_get(&mut c, "/hello");
    let s1: i64 = h1c_status(&mut c);
    let b1: bool = t_is(&mut c, "rsharp-https-ok\n");
    t_ok(&mut t, "get hello", (r1 == 0) && (s1 == 200) && b1);

    let r2: i32 = h1c_get(&mut c, "/chunked");
    let s2: i64 = h1c_status(&mut c);
    let b2: bool = t_is(&mut c, "alpha-beta-gamma");
    t_ok(&mut t, "chunked", (r2 == 0) && (s2 == 200) && b2);

    let r3: i32 = h1c_get(&mut c, "/big");
    let s3: i64 = h1c_status(&mut c);
    let n3: i64 = h1c_body_len(&mut c);
    let bp: ptr<u8> = h1c_body(&mut c);
    var first: i64 = -1;
    var last: i64 = -1;
    if (bp != null && n3 == 20000) {
        first = rt_byte(bp, 0) as i64;
        last = rt_byte(bp, 19999) as i64;
    }
    let want_first: i64 = 11;
    let want_last: i64 = (19999 * 7 + 11) % 256;
    t_ok(&mut t, "big 20000", (r3 == 0) && (s3 == 200) && (n3 == 20000) && (first == want_first) && (last == want_last));

    let r4: i32 = h1c_get(&mut c, "/missing");
    let s4: i64 = h1c_status(&mut c);
    let b4: bool = t_is(&mut c, "no such thing\n");
    t_ok(&mut t, "404", (r4 == 0) && (s4 == 404) && b4);

    let r5: i32 = h1c_get(&mut c, "/empty");
    let s5: i64 = h1c_status(&mut c);
    let n5: i64 = h1c_body_len(&mut c);
    t_ok(&mut t, "204 empty", (r5 == 0) && (s5 == 204) && (n5 == 0));

    let r6: i32 = h1c_get(&mut c, "/redirect");
    let s6: i64 = h1c_status(&mut c);
    var lb: [u8; 64] = [0];
    var lp: ptr<u8> = null;
    unsafe { lp = &mut lb[0] as ptr<u8>; }
    let ln: i64 = h1c_hdr_str(&mut c, "location", 8, lp, 64);
    let loc_ok: bool = (ln == 6) && (rt_eq(lp, "/hello") == 1);
    t_ok(&mut t, "302 location", (r6 == 0) && (s6 == 302) && loc_ok);

    let r7: i32 = h1c_head(&mut c, "/hello");
    let s7: i64 = h1c_status(&mut c);
    let n7: i64 = h1c_body_len(&mut c);
    t_ok(&mut t, "head no body", (r7 == 0) && (s7 == 200) && (n7 == 0));

    let post: ptr<u8> = "hello-post";
    let r8: i32 = h1c_post(&mut c, "/echo", "text/plain", post, 10);
    let s8: i64 = h1c_status(&mut c);
    let b8: bool = t_is(&mut c, "hello-post");
    t_ok(&mut t, "post echo", (r8 == 0) && (s8 == 200) && b8);

    let r9: i32 = h1c_get(&mut c, "/continue");
    let s9: i64 = h1c_status(&mut c);
    let b9: bool = t_is(&mut c, "after-1xx\n");
    t_ok(&mut t, "skip 1xx", (r9 == 0) && (s9 == 200) && b9);

    let r10: i32 = h1c_get(&mut c, "/keep");
    let s10: i64 = h1c_status(&mut c);
    let b10: bool = t_is(&mut c, "keep\n");
    let r11: i32 = h1c_get(&mut c, "/keep");
    let s11: i64 = h1c_status(&mut c);
    let b11: bool = t_is(&mut c, "keep\n");
    t_ok(&mut t, "keep-alive reuse", (r10 == 0) && (s10 == 200) && b10 && (r11 == 0) && (s11 == 200) && b11);
    h1c_close(&mut c);

    var c2: H1Conn = zero(H1Conn);
    if (t_dial(&mut c2, T_PORT, ap, alen) == H1C_OK) {
        let rc: i32 = h1c_send(&mut c2, "GET", "/hello", "Connection: close\r\n", null, 0);
        let rr: i32 = h1c_expect(&mut c2, 0);
        let s12: i64 = h1c_status(&mut c2);
        let n12: i64 = h1c_body_len(&mut c2);
        let live12: i32 = c2.live;
        t_ok(&mut t, "connection close", (rc == 0) && (rr == 0) && (s12 == 200) && (n12 == 16) && (live12 == 0));
        h1c_close(&mut c2);
    } else {
        t_ok(&mut t, "connection close", false);
        h1c_close(&mut c2);
    }

    var h: Https = zero(Https);
    let os_rc: i32 = https_open(&mut h, "localhost", T_PORT, 5000);
    t_ok(&mut t, "os store rejects", os_rc == HTTPS_UNTRUSTED);
    https_close(&mut h);

    var eb: [u8; 4096] = [0];
    var ep: ptr<u8> = null;
    unsafe { ep = &mut eb[0] as ptr<u8>; }
    let elen: i64 = https_anchor_ec(ep, 4096);
    t_ok(&mut t, "ec anchor parses", elen > 0);

    var ce: H1Conn = zero(H1Conn);
    if (t_dial(&mut ce, T_PORT_EC, ep, elen) == H1C_OK) {
        let re: i32 = h1c_get(&mut ce, "/hello");
        let se: i64 = h1c_status(&mut ce);
        let be: bool = t_is(&mut ce, "rsharp-https-ok\n");
        t_ok(&mut t, "ecdsa https", (re == 0) && (se == 200) && be);
    } else {
        t_ok(&mut t, "ecdsa https", false);
    }
    h1c_close(&mut ce);

    var cc: H1Conn = zero(H1Conn);
    if (h1c_init_proxy_anchor(&mut cc, "127.0.0.1", T_PROXY, "localhost", T_PORT, 8000, T_MAX, ap, alen) == H1C_OK) {
        let rp: i32 = h1c_get(&mut cc, "/hello");
        let sp2: i64 = h1c_status(&mut cc);
        let bp2: bool = t_is(&mut cc, "rsharp-https-ok\n");
        t_ok(&mut t, "proxy connect", (rp == 0) && (sp2 == 200) && bp2);
    } else {
        t_ok(&mut t, "proxy connect", false);
    }
    h1c_close(&mut cc);

    printf("https_passed=%lld of %lld\n", t.pass, t.total);
    fflush(null);
    if (t.pass != t.total) {
        return 3;
    }
    return 0;
}
