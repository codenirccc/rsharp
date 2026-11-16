include "../../modules/http/h3_win.rsx";
include "https_anchor.rsx";

const T_PORT: i64 = 4445;

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

fn body_is(h: &mut H3, ri: i64, want: ptr<u8>) -> bool {
    let n: i64 = h3_body_len(h, ri);
    let p: ptr<u8> = h3_body(h, ri);
    if (n != rt_len(want) || p == null) {
        return false;
    }
    return rt_bytes_eq(p, want, n) == 1;
}

fn main() -> i32 {
    var t: Tally = zero(Tally);

    var anchor: [u8; 2048] = [0];
    var ap: ptr<u8> = null;
    unsafe { ap = &mut anchor[0] as ptr<u8>; }
    let alen: i64 = https_anchor_rsa(ap, 2048);
    t_ok(&mut t, "anchor loaded", alen > 0);

    var h: H3 = h3_new();
    let rc: i32 = h3_open(&mut h, "localhost", T_PORT as u16, 400);
    t_ok(&mut t, "quic handshake", rc == H3_OK);
    t_ok(&mut t, "handshake done", h.q.hs_done == 1);
    t_ok(&mut t, "alpn is h3", h3_alpn_is(&mut h, "h3") == 1);
    t_ok(&mut t, "1rtt keys derived", h.q.have[QC_APP] == 1);

    if (rc != H3_OK) {
        printf("h3_passed=%lld of %lld\n", t.pass, t.total);
        return 1;
    }

    var store: i32 = 0;
    if (h3_trust_os(&mut h, "localhost") == H3_OK) {
        store = 1;
    }
    t_ok(&mut t, "os store rejects the local ca", store == 0);

    let tc: i32 = h3_trust_anchor(&mut h, "localhost", ap, alen);
    t_ok(&mut t, "anchor chain verifies", tc == H3_OK);
    t_ok(&mut t, "verified flag", h.q.verified == 1);

    let r1: i64 = h3_request(&mut h, "GET", "/hello", "localhost", null, 0);
    t_ok(&mut t, "hello request sent", r1 == 0);
    t_ok(&mut t, "hello stream id", h.reqs[0].id == 0);
    t_ok(&mut t, "hello response complete", h3_wait(&mut h, r1, 4000) == H3_OK);
    t_ok(&mut t, "hello status 200", h3_status(&mut h, r1) == 200);
    t_ok(&mut t, "hello content type", h3_his(&mut h, r1, "content-type", "text/plain") == 1);
    t_ok(&mut t, "hello content length", h3_his(&mut h, r1, "content-length", "13") == 1);
    t_ok(&mut t, "hello body", body_is(&mut h, r1, "rsharp-h3-ok\n"));
    t_ok(&mut t, "hello header count", h3_hcount(&mut h, r1) == 3);
    h3_release(&mut h, r1);

    let r2: i64 = h3_request(&mut h, "GET", "/big", "localhost", null, 0);
    t_ok(&mut t, "big request sent", r2 == 0);
    t_ok(&mut t, "big stream id", h.reqs[r2].id == 4);
    t_ok(&mut t, "big response complete", h3_wait(&mut h, r2, 8000) == H3_OK);
    t_ok(&mut t, "big status 200", h3_status(&mut h, r2) == 200);
    t_ok(&mut t, "big body length", h3_body_len(&mut h, r2) == 20000);
    var allx: i32 = 1;
    let bn: i64 = h3_body_len(&mut h, r2);
    let bpp: ptr<u8> = h3_body(&mut h, r2);
    var bi: i64 = 0;
    while (bi < bn) {
        if (rt_byte(bpp, bi) != 120) {
            allx = 0;
            bi = bn;
        } else {
            bi += 1;
        }
    }
    t_ok(&mut t, "big body contents", allx == 1);
    h3_release(&mut h, r2);

    let r3: i64 = h3_request(&mut h, "POST", "/echo", "localhost", "rsharp-echo", 11);
    t_ok(&mut t, "echo request sent", r3 == 0);
    t_ok(&mut t, "echo stream id", h.reqs[r3].id == 8);
    t_ok(&mut t, "echo response complete", h3_wait(&mut h, r3, 4000) == H3_OK);
    t_ok(&mut t, "echo status 200", h3_status(&mut h, r3) == 200);
    t_ok(&mut t, "echo body", body_is(&mut h, r3, "rsharp-echo"));
    t_ok(&mut t, "echo content length", h3_his(&mut h, r3, "content-length", "11") == 1);
    h3_release(&mut h, r3);

    let r4: i64 = h3_request(&mut h, "GET", "/missing", "localhost", null, 0);
    t_ok(&mut t, "missing request sent", r4 == 0);
    t_ok(&mut t, "missing response complete", h3_wait(&mut h, r4, 4000) == H3_OK);
    t_ok(&mut t, "missing status 404", h3_status(&mut h, r4) == 404);
    t_ok(&mut t, "missing body", body_is(&mut h, r4, "nope\n"));
    h3_release(&mut h, r4);

    let r5: i64 = h3_request(&mut h, "GET", "/empty", "localhost", null, 0);
    t_ok(&mut t, "empty request sent", r5 == 0);
    t_ok(&mut t, "empty stream id", h.reqs[r5].id == 16);
    t_ok(&mut t, "empty response complete", h3_wait(&mut h, r5, 4000) == H3_OK);
    t_ok(&mut t, "empty status 204", h3_status(&mut h, r5) == 204);
    t_ok(&mut t, "empty body length", h3_body_len(&mut h, r5) == 0);
    t_ok(&mut t, "empty has no content type", h3_hfind(&mut h, r5, "content-type") == -1);
    h3_release(&mut h, r5);

    t_ok(&mut t, "no protocol error", h.err == 0);
    t_ok(&mut t, "no transport error", h.q.err == 0);
    t_ok(&mut t, "four request slots cycled", h.nreq == 5);

    h3_free(&mut h);

    printf("h3_passed=%lld of %lld\n", t.pass, t.total);
    if (t.pass == t.total) {
        return 0;
    }
    return 1;
}
