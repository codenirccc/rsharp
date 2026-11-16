// work/http/t_request.rsx — the high-level request API against the loopback
// fixtures: one URL parser and one request object driving all three transports.
include "../../modules/http/http_request.rsx";
include "https_anchor.rsx";

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

fn body_is(r: &mut HResp, want: ptr<u8>) -> bool {
    let n: i64 = hresp_body_len(r);
    let p: ptr<u8> = hresp_body(r);
    if (n != rt_len(want) || p == null) {
        return false;
    }
    return rt_bytes_eq(p, want, n) == 1;
}

fn hdr_is(r: &mut HResp, name: ptr<u8>, want: ptr<u8>) -> bool {
    let n: i64 = hresp_header_len(r, name);
    if (n < 0 || n != rt_len(want)) {
        return false;
    }
    let p: ptr<u8> = hresp_header(r, name);
    if (p == null) {
        return false;
    }
    return rt_bytes_eq(p, want, n) == 1;
}

fn main() -> i32 {
    var t: Tally = zero(Tally);
    var q: HReq = hreq_new();
    var r: HResp = hresp_new();
    t_ok(&mut t, "request alloc", hreq_ready(&mut q) == 1 && r.hdr.buf.p != null);

    let u1: i32 = hreq_open(&mut q, "GET", "https://example.com");
    t_ok(&mut t, "https defaults", u1 == HR_OK && q.port == 443 && q.tls == 1);
    t_ok(&mut t, "https path", rt_eq(q.path.p, "/") == 1);
    t_ok(&mut t, "https host", rt_eq(q.host.p, "example.com") == 1);

    let u2: i32 = hreq_open(&mut q, "GET", "http://example.com:8080/a?b=c#frag");
    t_ok(&mut t, "http port", u2 == HR_OK && q.port == 8080 && q.tls == 0);
    t_ok(&mut t, "query kept fragment dropped", rt_eq(q.path.p, "/a?b=c") == 1);

    let u3: i32 = hreq_open(&mut q, "GET", "https://[::1]:8443/x");
    t_ok(&mut t, "ipv6 host", u3 == HR_OK && rt_eq(q.host.p, "[::1]") == 1 && q.port == 8443);

    let u4: i32 = hreq_open(&mut q, "GET", "https://example.com?q=1");
    t_ok(&mut t, "query only", u4 == HR_OK && rt_eq(q.path.p, "/?q=1") == 1);

    t_ok(&mut t, "reject scheme", hreq_open(&mut q, "GET", "ftp://example.com/") == HR_URL);
    t_ok(&mut t, "reject empty host", hreq_open(&mut q, "GET", "https://") == HR_URL);
    t_ok(&mut t, "reject port", hreq_open(&mut q, "GET", "https://h:70000/") == HR_URL);
    t_ok(&mut t, "reject version", hreq_set_version(&mut q, 9) == HR_VER);

    let g1: i32 = http_get("http://127.0.0.1:8099/hello", &mut r);
    t_ok(&mut t, "plain get", g1 == HR_OK);
    t_ok(&mut t, "plain status", hresp_status(&mut r) == 200);
    t_ok(&mut t, "plain body", body_is(&mut r, "rsharp-http-ok\n"));
    t_ok(&mut t, "plain version", hresp_version(&mut r) == HTTP_V11);
    t_ok(&mut t, "plain header", hdr_is(&mut r, "x-test", "yes"));
    t_ok(&mut t, "missing header", hresp_header_len(&mut r, "x-nope") == -1);

    var xb: [u8; 32] = [0];
    var xp: ptr<u8> = null;
    unsafe { xp = &mut xb[0] as ptr<u8>; }
    let xc: i64 = hresp_header_copy(&mut r, "x-test", xp, 32);
    t_ok(&mut t, "header copy", xc == 3 && rt_eq(xp, "yes") == 1);

    var ab: [u8; 4096] = [0];
    var ap: ptr<u8> = null;
    unsafe { ap = &mut ab[0] as ptr<u8>; }
    let alen: i64 = https_anchor_rsa(ap, 4096);
    t_ok(&mut t, "anchor loaded", alen > 0);

    let os_rc: i32 = http_get("https://localhost:4433/hello", &mut r);
    t_ok(&mut t, "os store rejects local ca", os_rc == HR_TLS);

    let g2: i32 = http_get_anchor("https://localhost:4433/hello", ap, alen, &mut r);
    t_ok(&mut t, "tls get", g2 == HR_OK);
    t_ok(&mut t, "tls status", hresp_status(&mut r) == 200);
    t_ok(&mut t, "tls body", body_is(&mut r, "rsharp-https-ok\n"));
    t_ok(&mut t, "tls content type", hdr_is(&mut r, "content-type", "text/plain"));

    var q2: HReq = hreq_new();
    let o2: i32 = hreq_open(&mut q2, "GET", "https://localhost:4433/hdr");
    let n2: i32 = hreq_header(&mut q2, "X-RSharp", "from-rsharp");
    let s2: i32 = hreq_fetch_anchor(&mut q2, &mut r, ap, alen);
    t_ok(&mut t, "custom header sent", o2 == HR_OK && n2 == HR_OK && s2 == HR_OK);
    t_ok(&mut t, "custom header echoed", body_is(&mut r, "from-rsharp"));

    let p1: i32 = http_post_anchor("https://localhost:4433/echo", "text/plain", "rsharp-post", 11, ap, alen, &mut r);
    t_ok(&mut t, "tls post", p1 == HR_OK);
    t_ok(&mut t, "tls post status", hresp_status(&mut r) == 200);
    t_ok(&mut t, "tls post echo", body_is(&mut r, "rsharp-post"));

    let n1: i32 = http_get_anchor("https://localhost:4433/missing", ap, alen, &mut r);
    t_ok(&mut t, "missing status", n1 == HR_OK && hresp_status(&mut r) == 404);
    t_ok(&mut t, "missing body", body_is(&mut r, "no such thing\n"));

    let o3: i32 = hreq_open(&mut q2, "GET", "https://localhost:4443/hello");
    let v3: i32 = hreq_set_version(&mut q2, HTTP_V2);
    let s3: i32 = hreq_fetch_anchor(&mut q2, &mut r, ap, alen);
    t_ok(&mut t, "h2 get", o3 == HR_OK && v3 == HR_OK && s3 == HR_OK);
    t_ok(&mut t, "h2 status", hresp_status(&mut r) == 200);
    t_ok(&mut t, "h2 body", body_is(&mut r, "rsharp-h2-ok\n"));
    t_ok(&mut t, "h2 version", hresp_version(&mut r) == HTTP_V2);
    t_ok(&mut t, "h2 headers", hresp_header_count(&mut r) >= 3);

    let o4: i32 = hreq_open(&mut q2, "POST", "https://localhost:4443/echo");
    let c4: i32 = hreq_header(&mut q2, "content-type", "text/plain");
    let b4: i32 = hreq_body(&mut q2, "h2-body", 7);
    let s4: i32 = hreq_fetch_anchor(&mut q2, &mut r, ap, alen);
    t_ok(&mut t, "h2 post", o4 == HR_OK && c4 == HR_OK && b4 == HR_OK && s4 == HR_OK);
    t_ok(&mut t, "h2 post echo", body_is(&mut r, "h2-body"));

    let o5: i32 = hreq_open(&mut q2, "GET", "https://localhost:4445/hello");
    let v5: i32 = hreq_set_version(&mut q2, HTTP_V3);
    let s5: i32 = hreq_fetch_anchor(&mut q2, &mut r, ap, alen);
    t_ok(&mut t, "h3 get", o5 == HR_OK && v5 == HR_OK && s5 == HR_OK);
    t_ok(&mut t, "h3 status", hresp_status(&mut r) == 200);
    t_ok(&mut t, "h3 body", body_is(&mut r, "rsharp-h3-ok\n"));
    t_ok(&mut t, "h3 version", hresp_version(&mut r) == HTTP_V3);

    let o6: i32 = hreq_open(&mut q2, "POST", "https://localhost:4445/echo");
    let b6: i32 = hreq_body(&mut q2, "h3-body", 7);
    let s6: i32 = hreq_fetch_anchor(&mut q2, &mut r, ap, alen);
    t_ok(&mut t, "h3 post", o6 == HR_OK && b6 == HR_OK && s6 == HR_OK);
    t_ok(&mut t, "h3 post echo", body_is(&mut r, "h3-body"));

    let m1: i32 = http_send_anchor("DELETE", "https://localhost:4433/echo", null, 0, ap, alen, &mut r);
    t_ok(&mut t, "http_send delete", m1 == HR_OK && hresp_status(&mut r) == 200);

    hreq_free(&mut q);
    hreq_free(&mut q2);
    hresp_free(&mut r);
    printf("request_passed=%lld of %lld\n", t.pass, t.total);
    fflush(null);
    if (t.pass == t.total) {
        return 0;
    }
    return 1;
}
