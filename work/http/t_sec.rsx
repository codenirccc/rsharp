include "../../modules/http/http_request.rsx";

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


fn url_case(t: &mut Tally, name: ptr<u8>, url: ptr<u8>, want: i32) {
    var q: HReq = hreq_new();
    let rc: i32 = hreq_open(&mut q, "GET", url);
    t_ok(t, name, rc == want);
    hreq_free(&mut q);
}

fn method_case(t: &mut Tally, name: ptr<u8>, m: ptr<u8>, want: i32) {
    var q: HReq = hreq_new();
    let rc: i32 = hreq_open(&mut q, m, "http://127.0.0.1/x");
    t_ok(t, name, rc == want);
    hreq_free(&mut q);
}

fn hdr_case(t: &mut Tally, name: ptr<u8>, hn: ptr<u8>, hv: ptr<u8>, want: i32) {
    var q: HReq = hreq_new();
    let rc: i32 = hreq_header(&mut q, hn, hv);
    t_ok(t, name, rc == want);
    hreq_free(&mut q);
}

fn phase_request(t: &mut Tally) {
    url_case(t, "url plain ok", "http://127.0.0.1:8099/a", HR_OK);
    url_case(t, "url tls ok", "https://example.test/", HR_OK);
    url_case(t, "url query ok", "http://127.0.0.1/a?b=c", HR_OK);

    url_case(t, "url crlf path", "http://127.0.0.1/a\r\nX: y", HR_URL);
    url_case(t, "url crlf host", "http://127.0.0.1\r\n/a", HR_URL);
    url_case(t, "url space host", "http://exa mple/", HR_URL);
    url_case(t, "url tab host", "http://exa\tmple/", HR_URL);
    url_case(t, "url space path", "http://127.0.0.1/a b", HR_URL);
    url_case(t, "url backslash", "http://127.0.0.1/a\\b", HR_URL);
    url_case(t, "url del host", "http://exa\002ple/", HR_URL);
    url_case(t, "url no host", "http:///a", HR_URL);
    url_case(t, "url no scheme", "127.0.0.1/a", HR_URL);
    url_case(t, "url empty", "", HR_URL);

    method_case(t, "method get", "GET", HR_OK);
    method_case(t, "method post", "POST", HR_OK);
    method_case(t, "method dash", "M-SEARCH", HR_OK);
    method_case(t, "method space", "GE T", HR_URL);
    method_case(t, "method tab", "G\tT", HR_URL);
    method_case(t, "method crlf", "GET\r\nX", HR_URL);
    method_case(t, "method long", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", HR_URL);
    method_case(t, "method empty means get", "", HR_OK);

    hdr_case(t, "hdr ok", "X-Test", "ok", HR_OK);
    hdr_case(t, "hdr tab value", "X-Test", "a\tb", HR_OK);
    hdr_case(t, "hdr crlf value", "X-Test", "a\r\nInjected: 1", HR_ERR);
    hdr_case(t, "hdr lone cr value", "X-Test", "a\rb", HR_ERR);
    hdr_case(t, "hdr ctl value", "X-Test", "a\001b", HR_ERR);
    hdr_case(t, "hdr del value", "X-Test", "a\177b", HR_ERR);
    hdr_case(t, "hdr space name", "X Test", "v", HR_ERR);
    hdr_case(t, "hdr colon name", "X:Y", "v", HR_ERR);
    hdr_case(t, "hdr empty name", "", "v", HR_ERR);
}


fn h1_case(t: &mut Tally, name: ptr<u8>, raw: ptr<u8>, want: i32, fr: i32, cl: i64) {
    var r: H1Resp = zero(H1Resp);
    let n: i64 = rt_len(raw);
    let pr: i32 = h1_parse_head(raw, n, &mut r);
    var ok: bool = false;
    if (pr == want) {
        if (want == 0) {
            let f: i32 = h1_framing(raw, n, &mut r, 0);
            if (fr == H1_BAD) {
                ok = f == H1_BAD;
            } else {
                ok = f == 0 && r.framing == fr && r.content_len == cl;
            }
        } else {
            ok = true;
        }
    }
    t_ok(t, name, ok);
}

fn h1_nul_name(t: &mut Tally) {
    var b: HxBuf = hxbuf_new(64);
    hxbuf_puts(&mut b, "HTTP/1.1 200 OK\r\nX");
    hxbuf_putc(&mut b, 0);
    hxbuf_puts(&mut b, "Y: x\r\n\r\n");
    var r: H1Resp = zero(H1Resp);
    let pr: i32 = h1_parse_head(b.p, b.len, &mut r);
    t_ok(t, "h1 name nul", pr == H1_BAD);
    hxbuf_free(&mut b);
}

fn phase_h1(t: &mut Tally) {    h1_case(t, "h1 length", "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n", 0, H1_LENGTH, 5);
    h1_case(t, "h1 length spaces", "HTTP/1.1 200 OK\r\nContent-Length:   42  \r\n\r\n", 0,
            H1_LENGTH, 42);
    h1_case(t, "h1 chunked", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n", 0,
            H1_CHUNKED, -1);
    h1_case(t, "h1 no body 204", "HTTP/1.1 204 No Content\r\n\r\n", 0, H1_NONE, -1);
    h1_case(t, "h1 no body 304", "HTTP/1.1 304 Not Modified\r\n\r\n", 0, H1_NONE, -1);

    h1_case(t, "h1 te gzip", "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\n", 0, H1_BAD, -1);
    h1_case(t, "h1 te list", "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip, chunked\r\n\r\n", 0,
            H1_BAD, -1);
    h1_case(t, "h1 te and cl", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n",
            0, H1_BAD, -1);
    h1_case(t, "h1 cl twice", "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\n", 0,
            H1_BAD, -1);
    h1_case(t, "h1 te twice", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n\r\n",
            0, H1_BAD, -1);
    h1_case(t, "h1 cl plus", "HTTP/1.1 200 OK\r\nContent-Length: +5\r\n\r\n", 0, H1_BAD, -1);
    h1_case(t, "h1 cl list", "HTTP/1.1 200 OK\r\nContent-Length: 5, 5\r\n\r\n", 0, H1_BAD, -1);
    h1_case(t, "h1 cl empty", "HTTP/1.1 200 OK\r\nContent-Length: \r\n\r\n", 0, H1_BAD, -1);
    h1_case(t, "h1 cl hex", "HTTP/1.1 200 OK\r\nContent-Length: 0x10\r\n\r\n", 0, H1_BAD, -1);

    h1_case(t, "h1 name space", "HTTP/1.1 200 OK\r\nBad Header: x\r\n\r\n", H1_BAD, 0, -1);
    h1_case(t, "h1 name empty", "HTTP/1.1 200 OK\r\n: x\r\n\r\n", H1_BAD, 0, -1);
    h1_nul_name(t);
    h1_case(t, "h1 no colon", "HTTP/1.1 200 OK\r\nBare\r\n\r\n", H1_BAD, 0, -1);
    h1_case(t, "h1 value ctl", "HTTP/1.1 200 OK\r\nX: a\001b\r\n\r\n", H1_BAD, 0, -1);
    h1_case(t, "h1 value del", "HTTP/1.1 200 OK\r\nX: a\177b\r\n\r\n", H1_BAD, 0, -1);
    h1_case(t, "h1 folded", "HTTP/1.1 200 OK\r\nX: a\r\n b\r\n\r\n", H1_BAD, 0, -1);
    h1_case(t, "h1 value tab", "HTTP/1.1 200 OK\r\nX: a\tb\r\n\r\n", 0, H1_CLOSE, -1);
    h1_case(t, "h1 status short", "HTTP/1.1 20 OK\r\n\r\n", H1_BAD, 0, -1);
    h1_case(t, "h1 no terminator", "HTTP/1.1 200 OK\r\nX: a\r\n", H1_NEED, 0, -1);

    var b: HxBuf = hxbuf_new(4096);
    hxbuf_puts(&mut b, "HTTP/1.1 200 OK\r\n");
    var i: i64 = 0;
    while (i < 49) {
        hxbuf_puts(&mut b, "X: a\r\n");
        i += 1;
    }
    hxbuf_puts(&mut b, "\r\n");
    var hb: [u8; 1024] = [0];
    var hp: ptr<u8> = null;
    unsafe { hp = &mut hb[0] as ptr<u8>; }
    let hn: i64 = b.len;
    rt_copy(hp, b.p, hn);
    var r: H1Resp = zero(H1Resp);
    let pr: i32 = h1_parse_head(hp, hn, &mut r);
    t_ok(t, "h1 header cap", pr == H1_BAD);
    hxbuf_free(&mut b);
}


fn hp_case(t: &mut Tally, name: ptr<u8>, hn: ptr<u8>, hv: ptr<u8>, want: i32) {
    var o: HpOut = hp_out_new();
    let rc: i32 = hp_out_add(&mut o, hn, rt_len(hn), hv, rt_len(hv));
    t_ok(t, name, rc == want);
    hp_out_free(&mut o);
}

fn phase_hpack(t: &mut Tally) {
    hp_case(t, "hp ok", "x-test", "v", HPACK_OK);
    hp_case(t, "hp status", ":status", "200", HPACK_OK);
    hp_case(t, "hp space name", "x test", "v", HPACK_ERR);
    hp_case(t, "hp empty name", "", "v", HPACK_ERR);
    hp_case(t, "hp crlf value", "x-test", "a\r\nb", HPACK_ERR);
    hp_case(t, "hp ctl value", "x-test", "a\001b", HPACK_ERR);
    hp_case(t, "hp tab value", "x-test", "a\tb", HPACK_OK);

    var vb: [u8; 8] = [0];
    var vp: ptr<u8> = null;
    unsafe { vp = &mut vb[0] as ptr<u8>; }
    rt_copy(vp, "a", 1);
    rt_setbyte(vp, 1, 0);
    rt_setbyte(vp, 2, 98);
    var o: HpOut = hp_out_new();
    let rc: i32 = hp_out_add(&mut o, "x-test", 6, vp, 3);
    t_ok(t, "hp nul value", rc == HPACK_ERR);
    hp_out_free(&mut o);
}


fn h2_status(t: &mut Tally, name: ptr<u8>, st: ptr<u8>, want: i32, ws: i64) {
    var c: H2Conn = zero(H2Conn);
    if (h2c_prepare(&mut c, "localhost", 443, 4096) != H2C_OK) {
        t_ok(t, name, false);
        return;
    }
    hpack_put_kv(&mut c.blk, ":status", st);
    let rc: i32 = h2c_decode(&mut c, 0);
    let s: i64 = h2c_status(&mut c);
    var ok: bool = rc == want;
    if (ok && want == H2C_OK) {
        ok = s == ws;
    }
    t_ok(t, name, ok);
    h2c_free(&mut c);
}

fn h2_pair(t: &mut Tally, name: ptr<u8>, hn: ptr<u8>, hv: ptr<u8>, trailer: i32, want: i32) {
    var c: H2Conn = zero(H2Conn);
    if (h2c_prepare(&mut c, "localhost", 443, 4096) != H2C_OK) {
        t_ok(t, name, false);
        return;
    }
    hpack_put_kv(&mut c.blk, hn, hv);
    let rc: i32 = h2c_decode(&mut c, trailer);
    t_ok(t, name, rc == want);
    h2c_free(&mut c);
}

fn h2_status_twice(t: &mut Tally) {
    var c: H2Conn = zero(H2Conn);
    if (h2c_prepare(&mut c, "localhost", 443, 4096) != H2C_OK) {
        t_ok(t, "h2 status twice", false);
        return;
    }
    hpack_put_kv(&mut c.blk, ":status", "200");
    hpack_put_kv(&mut c.blk, ":status", "204");
    let rc: i32 = h2c_decode(&mut c, 0);
    t_ok(t, "h2 status twice", rc == H2C_ERR);
    h2c_free(&mut c);
}

fn phase_h2(t: &mut Tally) {
    h2_status(t, "h2 status 200", "200", H2C_OK, 200);
    h2_status(t, "h2 status 204", "204", H2C_OK, 204);
    h2_status(t, "h2 status 99", "99", H2C_ERR, 0);
    h2_status(t, "h2 status 600", "600", H2C_ERR, 0);
    h2_status(t, "h2 status abc", "abc", H2C_ERR, 0);
    h2_status(t, "h2 status 2048", "2048", H2C_ERR, 0);

    h2_pair(t, "h2 no status", "x-test", "v", 0, H2C_ERR);
    h2_pair(t, "h2 pseudo path", ":path", "/x", 0, H2C_ERR);
    h2_pair(t, "h2 status in trailer", ":status", "200", 1, H2C_ERR);
    h2_pair(t, "h2 trailer ok", "x-check", "yes", 1, H2C_OK);
    h2_pair(t, "h2 upper name", "X-Bad", "v", 0, H2C_ERR);
    h2_pair(t, "h2 inner colon", "x:y", "v", 0, H2C_ERR);
    h2_pair(t, "h2 crlf value", "x-test", "a\r\nb", 0, H2C_ERR);
    h2_status_twice(t);
}


fn alpn_case(t: &mut Tally, name: ptr<u8>, mode: i32, proto: ptr<u8>, want: i32) {
    var x: Tls13 = zero(Tls13);
    x.alpn_mode = mode;
    var base: ptr<u8> = null;
    unsafe { base = &mut x.alpn[0] as ptr<u8>; }
    let n: i64 = rt_len(proto);
    if (n > 0) {
        rt_copy(base, proto, n);
    }
    x.alpn_len = n;
    let got: i32 = tls13_alpn_ok(&mut x);
    t_ok(t, name, got == want);
}

fn phase_alpn(t: &mut Tally) {
    alpn_case(t, "alpn any none", 0, "", 1);
    alpn_case(t, "alpn any h2", 0, "h2", 1);
    alpn_case(t, "alpn any h3", 0, "h3", 1);
    alpn_case(t, "alpn any other", 0, "ftp", 1);

    alpn_case(t, "alpn h1 ok", 1, "http/1.1", 1);
    alpn_case(t, "alpn h1 none", 1, "", 1);
    alpn_case(t, "alpn h1 h2", 1, "h2", 0);

    alpn_case(t, "alpn h2 ok", 2, "h2", 1);
    alpn_case(t, "alpn h2 none", 2, "", 0);
    alpn_case(t, "alpn h2 h1", 2, "http/1.1", 0);
}


fn cert_case(t: &mut Tally, name: ptr<u8>, hex: ptr<u8>, host: ptr<u8>, want: i32) {
    var buf: [u8; 2048] = [0];
    var p: ptr<u8> = null;
    unsafe { p = &mut buf[0] as ptr<u8>; }
    let n: i64 = rt_parse_hex(hex, p, 2048);
    if (n <= 0) {
        t_ok(t, name, false);
        return;
    }
    var c: X509 = zero(X509);
    if (x509_parse(&mut c, p, n) != 0) {
        t_ok(t, name, false);
        return;
    }
    let got: i32 = x509_check_host(&mut c, host, rt_len(host));
    t_ok(t, name, got == want);
}

fn phase_x509(t: &mut Tally) {
    let cnonly: ptr<u8> = "308201413081e9a003020102020502540be40b300a06082a8648ce3d04030230163114301206035504030c0b636e6f6e6c792e74657374301e170d3234303130313030303030305a170d3334303130313030303030305a30163114301206035504030c0b636e6f6e6c792e746573743059301306072a8648ce3d020106082a8648ce3d030107034200049ad47d1c10c19e3f07cf03a8cca9cf67201cf21c169ba70dfac159f14d1d3bb63cb7b26f422a790bf9f5f40671b2a6629b06260413efdb1bc956c90ab68ae600a324302230200603551d1104193017861568747470733a2f2f636e6f6e6c792e746573742f78300a06082a8648ce3d04030203470030440220510a8532ae1c134073684ee295d51afa220535c5afe3ee58334180a9fc012a97022075371612358ae2a931c2687d5ee321fbba827ea3a5f7287d1e73ae514753bd28";
    let nosan: ptr<u8> = "3082011b3081c1a003020102020502540be40a300a06082a8648ce3d04030230153113301106035504030c0a6e6f73616e2e74657374301e170d3234303130313030303030305a170d3334303130313030303030305a30153113301106035504030c0a6e6f73616e2e746573743059301306072a8648ce3d020106082a8648ce3d030107034200048de42d5848f1ca12875a78421c013ef82111aaf811179097e8712a1e56abf40e07bd77ab4aabfb7b53616cde59bbe0766acd70e9247396c1fdcf083570774b58300a06082a8648ce3d0403020349003046022100dd255e0c9e70ee242cf03dfbacc5b6aa425f3bff6bbfc622ecc014815d155d76022100b349efef4601ca89b832257b05eacc96b6cfd2f2e091deb27e06598c2ee15cc2";

    cert_case(t, "san present beats cn", cnonly, "cnonly.test", 0);
    cert_case(t, "san absent still cn", nosan, "nosan.test", 1);
    cert_case(t, "san absent cn case", nosan, "NOSAN.TEST", 1);
    cert_case(t, "san absent cn miss", nosan, "other.test", 0);
}

fn main() -> i32 {
    var t: Tally = zero(Tally);
    phase_request(&mut t);
    phase_h1(&mut t);
    phase_hpack(&mut t);
    phase_h2(&mut t);
    phase_alpn(&mut t);
    phase_x509(&mut t);
    printf("sec_passed=%lld of %lld\n", t.pass, t.total);
    if (t.pass == t.total) {
        return 0;
    }
    return 1;
}
