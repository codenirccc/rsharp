include "http1_client.rsx";
include "http2_client.rsx";
include "h3_win.rsx";

const HR_OK: i32 = 0;
const HR_ERR: i32 = -1;
const HR_URL: i32 = -2;
const HR_TLS: i32 = -3;
const HR_VER: i32 = -4;

const HR_MAX_HDR: i64 = 24;

const HTTP_V11: i32 = 1;
const HTTP_V2: i32 = 2;
const HTTP_V3: i32 = 3;

struct HReq {
    m: HxBuf,
    host: HxBuf,
    path: HxBuf,
    kn: [HxBuf; 24],
    kv: [HxBuf; 24],
    nh: i64,
    body: HxBuf,
    port: u16,
    tls: i32,
    ver: i32,
    to_ms: i32,
    max: i64
}

struct HResp {
    status: i64,
    ver: i32,
    hdr: HpOut,
    body: HxBuf
}

fn hr_lower(c: u8) -> u8 {
    if (c >= 65 && c <= 90) {
        return (c + 32) as u8;
    }
    return c;
}

fn hr_ci_eq(p: ptr<u8>, q: ptr<u8>, n: i64) -> i32 {
    var i: i64 = 0;
    while (i < n) {
        if (hr_lower(rt_byte(p, i)) != hr_lower(rt_byte(q, i))) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn hr_token(c: u8) -> i32 {
    if (c >= 48 && c <= 57) {
        return 1;
    }
    if (c >= 65 && c <= 90) {
        return 1;
    }
    if (c >= 97 && c <= 122) {
        return 1;
    }
    if (c == 33 || c == 35 || c == 36 || c == 37 || c == 38 || c == 39 || c == 42 || c == 43) {
        return 1;
    }
    if (c == 45 || c == 46 || c == 94 || c == 95 || c == 96 || c == 124 || c == 126) {
        return 1;
    }
    return 0;
}

fn hr_url_ok(p: ptr<u8>, a: i64, z: i64, host: i32) -> i32 {
    var i: i64 = a;
    while (i < z) {
        let c: i64 = rt_byte(p, i) as i64;
        if (c <= 32 || c == 127) {
            return 0;
        }
        if (host == 1) {
            if (c >= 128 || c == 34 || c == 39 || c == 60 || c == 62 || c == 92 || c == 96) {
                return 0;
            }
            if (c == 123 || c == 125 || c == 124 || c == 94) {
                return 0;
            }
        } else {
            if (c == 92) {
                return 0;
            }
        }
        i += 1;
    }
    return 1;
}

fn hr_seg(b: &mut HxBuf, p: ptr<u8>, a: i64, z: i64) -> i32 {
    hxbuf_clear(b);
    if (z > a) {
        var sp: ptr<u8> = null;
        unsafe { sp = p + a; }
        if (hxbuf_put(b, sp, z - a) != 0) {
            return HR_ERR;
        }
    }
    if (hxbuf_terminate(b) != 0) {
        return HR_ERR;
    }
    return HR_OK;
}

fn hr_port(p: ptr<u8>, i: i64, n: i64) -> i64 {
    if (i >= n) {
        return -1;
    }
    var v: i64 = 0;
    var k: i64 = i;
    while (k < n) {
        let c: i64 = rt_byte(p, k) as i64;
        if (c < 48 || c > 57) {
            return -1;
        }
        v = v * 10 + (c - 48);
        if (v > 65535) {
            return -1;
        }
        k += 1;
    }
    if (v == 0) {
        return -1;
    }
    return v;
}

fn hreq_new() -> HReq {
    var q: HReq = zero(HReq);
    q.m = hxbuf_new(32);
    q.host = hxbuf_new(256);
    q.path = hxbuf_new(2048);
    q.body = hxbuf_new(65536);
    var i: i64 = 0;
    while (i < HR_MAX_HDR) {
        q.kn[i] = hxbuf_new(64);
        q.kv[i] = hxbuf_new(256);
        i += 1;
    }
    q.nh = 0;
    q.port = 443;
    q.tls = 1;
    q.ver = HTTP_V11;
    q.to_ms = 10000;
    q.max = 8388608;
    return q;
}

fn hreq_free(q: &mut HReq) {
    hxbuf_free(&mut q.m);
    hxbuf_free(&mut q.host);
    hxbuf_free(&mut q.path);
    hxbuf_free(&mut q.body);
    var i: i64 = 0;
    while (i < HR_MAX_HDR) {
        hxbuf_free(&mut q.kn[i]);
        hxbuf_free(&mut q.kv[i]);
        i += 1;
    }
    q.nh = 0;
}

fn hreq_ready(q: &mut HReq) -> i32 {
    if (q.m.p == null || q.host.p == null || q.path.p == null || q.body.p == null) {
        return 0;
    }
    return 1;
}

fn hreq_open(q: &mut HReq, method: ptr<u8>, url: ptr<u8>) -> i32 {
    if (hreq_ready(q) != 1) {
        return HR_ERR;
    }
    hxbuf_clear(&mut q.body);
    q.nh = 0;

    let n: i64 = rt_len(url);
    var skip: i64 = 0;
    var tls: i32 = 1;
    if (n >= 8 && hr_ci_eq(url, "https://", 8) == 1) {
        skip = 8;
    } else if (n >= 7 && hr_ci_eq(url, "http://", 7) == 1) {
        skip = 7;
        tls = 0;
    } else {
        return HR_URL;
    }

    var j: i64 = skip;
    var scan: i32 = 1;
    while (scan == 1 && j < n) {
        let c: i64 = rt_byte(url, j) as i64;
        if (c == 47 || c == 63 || c == 35) {
            scan = 0;
        } else {
            j += 1;
        }
    }

    var hs: i64 = skip;
    var k: i64 = skip;
    while (k < j) {
        if (rt_byte(url, k) as i64 == 64) {
            hs = k + 1;
        }
        k += 1;
    }

    var he: i64 = j;
    var port: i64 = 0;
    if (hs < j && rt_byte(url, hs) as i64 == 91) {
        var c2: i64 = hs;
        var hit: i64 = -1;
        while (c2 < j) {
            if (rt_byte(url, c2) as i64 == 93) {
                hit = c2;
                c2 = j;
            } else {
                c2 += 1;
            }
        }
        if (hit < 0) {
            return HR_URL;
        }
        he = hit + 1;
        if (he < j) {
            if (rt_byte(url, he) as i64 != 58) {
                return HR_URL;
            }
            port = hr_port(url, he + 1, j);
            if (port < 0) {
                return HR_URL;
            }
        }
    } else {
        var c3: i64 = j;
        var colon: i64 = -1;
        while (c3 > hs) {
            c3 -= 1;
            if (rt_byte(url, c3) as i64 == 58) {
                colon = c3;
                c3 = hs;
            }
        }
        if (colon >= 0) {
            he = colon;
            port = hr_port(url, colon + 1, j);
            if (port < 0) {
                return HR_URL;
            }
        }
    }
    if (he <= hs) {
        return HR_URL;
    }
    if (hr_url_ok(url, hs, he, 1) != 1) {
        return HR_URL;
    }
    if (port == 0) {
        if (tls == 1) {
            port = 443;
        } else {
            port = 80;
        }
    }

    if (method != null && rt_len(method) > 0) {
        let mn: i64 = rt_len(method);
        if (mn > 32) {
            return HR_URL;
        }
        var mi: i64 = 0;
        while (mi < mn) {
            if (hr_token(rt_byte(method, mi)) != 1) {
                return HR_URL;
            }
            mi += 1;
        }
        if (hr_seg(&mut q.m, method, 0, mn) != HR_OK) {
            return HR_ERR;
        }
    } else {
        if (hr_seg(&mut q.m, "GET", 0, 3) != HR_OK) {
            return HR_ERR;
        }
    }
    if (hr_seg(&mut q.host, url, hs, he) != HR_OK) {
        return HR_ERR;
    }

    var pe: i64 = j;
    while (pe < n && rt_byte(url, pe) as i64 != 35) {
        pe += 1;
    }
    if (pe > j && hr_url_ok(url, j, pe, 0) != 1) {
        return HR_URL;
    }
    hxbuf_clear(&mut q.path);
    if (pe <= j) {
        if (hxbuf_putc(&mut q.path, 47) != 0) {
            return HR_ERR;
        }
    } else {
        if (rt_byte(url, j) as i64 == 63) {
            if (hxbuf_putc(&mut q.path, 47) != 0) {
                return HR_ERR;
            }
        }
        var sp2: ptr<u8> = null;
        unsafe { sp2 = url + j; }
        if (hxbuf_put(&mut q.path, sp2, pe - j) != 0) {
            return HR_ERR;
        }
    }
    if (hxbuf_terminate(&mut q.path) != 0) {
        return HR_ERR;
    }

    q.port = port as u16;
    q.tls = tls;
    return HR_OK;
}

fn hreq_set_version(q: &mut HReq, ver: i32) -> i32 {
    if (ver != HTTP_V11 && ver != HTTP_V2 && ver != HTTP_V3) {
        return HR_VER;
    }
    q.ver = ver;
    return HR_OK;
}

fn hreq_set_timeout(q: &mut HReq, ms: i32) -> i32 {
    if (ms <= 0) {
        return HR_ERR;
    }
    q.to_ms = ms;
    return HR_OK;
}

fn hreq_set_limit(q: &mut HReq, n: i64) -> i32 {
    if (n <= 0) {
        return HR_ERR;
    }
    q.max = n;
    return HR_OK;
}

fn hreq_header(q: &mut HReq, name: ptr<u8>, value: ptr<u8>) -> i32 {
    if (q.nh >= HR_MAX_HDR || name == null || value == null) {
        return HR_ERR;
    }
    let nl: i64 = rt_len(name);
    let vl: i64 = rt_len(value);
    if (nl <= 0 || nl >= 64) {
        return HR_ERR;
    }
    var i: i64 = 0;
    while (i < nl) {
        if (hr_token(rt_byte(name, i)) != 1) {
            return HR_ERR;
        }
        i += 1;
    }
    var k: i64 = 0;
    while (k < vl) {
        let c2: i64 = rt_byte(value, k) as i64;
        if (c2 == 13 || c2 == 10 || c2 == 0) {
            return HR_ERR;
        }
        if (c2 < 32 && c2 != 9) {
            return HR_ERR;
        }
        if (c2 == 127) {
            return HR_ERR;
        }
        k += 1;
    }
    let s: i64 = q.nh;
    hxbuf_clear(&mut q.kn[s]);
    hxbuf_clear(&mut q.kv[s]);
    if (hxbuf_put(&mut q.kn[s], name, nl) != 0) {
        return HR_ERR;
    }
    if (hxbuf_put(&mut q.kv[s], value, vl) != 0) {
        return HR_ERR;
    }
    if (hxbuf_terminate(&mut q.kn[s]) != 0) {
        return HR_ERR;
    }
    if (hxbuf_terminate(&mut q.kv[s]) != 0) {
        return HR_ERR;
    }
    q.nh += 1;
    return HR_OK;
}

fn hreq_body(q: &mut HReq, p: ptr<u8>, n: i64) -> i32 {
    if (n < 0 || (n > 0 && p == null)) {
        return HR_ERR;
    }
    if (n > q.max) {
        return HR_ERR;
    }
    hxbuf_clear(&mut q.body);
    if (n > 0 && hxbuf_put(&mut q.body, p, n) != 0) {
        return HR_ERR;
    }
    if (hxbuf_terminate(&mut q.body) != 0) {
        return HR_ERR;
    }
    return HR_OK;
}

fn hreq_is_head(q: &mut HReq) -> i32 {
    if (q.m.len == 4 && hr_ci_eq(q.m.p, "HEAD", 4) == 1) {
        return 1;
    }
    return 0;
}

fn hreq_kind(q: &mut HReq, i: i64) -> i32 {
    if (i < 0 || i >= q.nh) {
        return 0;
    }
    let p: ptr<u8> = q.kn[i].p;
    let n: i64 = q.kn[i].len;
    if (n == 4 && hr_ci_eq(p, "host", 4) == 1) {
        return 1;
    }
    if (n == 12 && hr_ci_eq(p, "content-type", 12) == 1) {
        return 2;
    }
    if (n == 14 && hr_ci_eq(p, "content-length", 14) == 1) {
        return 3;
    }
    if (n == 10 && hr_ci_eq(p, "connection", 10) == 1) {
        return 4;
    }
    if (n == 17 && hr_ci_eq(p, "transfer-encoding", 17) == 1) {
        return 4;
    }
    if (n == 2 && hr_ci_eq(p, "te", 2) == 1) {
        return 4;
    }
    if (n == 7 && hr_ci_eq(p, "upgrade", 7) == 1) {
        return 4;
    }
    if (n == 9 && hr_ci_eq(p, "keep-alive", 9) == 1) {
        return 4;
    }
    if (n == 16 && hr_ci_eq(p, "proxy-connection", 16) == 1) {
        return 4;
    }
    return 0;
}

fn hreq_ctype(q: &mut HReq, out: ptr<u8>, cap: i64) -> i64 {
    if (out == null || cap <= 0) {
        return -1;
    }
    var i: i64 = 0;
    while (i < q.nh) {
        if (hreq_kind(q, i) == 2) {
            let n: i64 = q.kv[i].len;
            if (n + 1 > cap) {
                return -1;
            }
            rt_copy(out, q.kv[i].p, n);
            rt_setbyte(out, n, 0);
            return n;
        }
        i += 1;
    }
    return -1;
}

fn hreq_h1_extra(q: &mut HReq, ex: &mut HxBuf) -> i32 {
    hxbuf_clear(ex);
    var i: i64 = 0;
    while (i < q.nh) {
        let kind: i32 = hreq_kind(q, i);
        if (kind != 1 && kind != 3) {
            if (hxbuf_put(ex, q.kn[i].p, q.kn[i].len) != 0) {
                return HR_ERR;
            }
            if (hxbuf_puts(ex, ": ") != 0) {
                return HR_ERR;
            }
            if (hxbuf_put(ex, q.kv[i].p, q.kv[i].len) != 0) {
                return HR_ERR;
            }
            if (hxbuf_puts(ex, "\r\n") != 0) {
                return HR_ERR;
            }
        }
        i += 1;
    }
    if (hxbuf_terminate(ex) != 0) {
        return HR_ERR;
    }
    return HR_OK;
}

fn hreq_h2_extra(q: &mut HReq, ex: &mut HxBuf) -> i32 {
    hxbuf_clear(ex);
    var ln: [u8; 96] = [0];
    var lnp: ptr<u8> = null;
    unsafe { lnp = &mut ln[0] as ptr<u8>; }
    var i: i64 = 0;
    while (i < q.nh) {
        let kind: i32 = hreq_kind(q, i);
        if (kind == 0) {
            let n: i64 = q.kn[i].len;
            if (n >= 96) {
                return HR_ERR;
            }
            var c: i64 = 0;
            while (c < n) {
                rt_setbyte(lnp, c, hr_lower(rt_byte(q.kn[i].p, c)));
                c += 1;
            }
            rt_setbyte(lnp, n, 0);
            if (hpack_put_kvn(ex, lnp, n, q.kv[i].p, q.kv[i].len) != 0) {
                return HR_ERR;
            }
        }
        i += 1;
    }
    return HR_OK;
}

fn hreq_h3_extra(q: &mut HReq, ex: &mut HpOut) -> i32 {
    var ln: [u8; 96] = [0];
    var lnp: ptr<u8> = null;
    unsafe { lnp = &mut ln[0] as ptr<u8>; }
    var i: i64 = 0;
    while (i < q.nh) {
        let kind: i32 = hreq_kind(q, i);
        if (kind == 0 || kind == 2) {
            let n: i64 = q.kn[i].len;
            if (n >= 96) {
                return HR_ERR;
            }
            var c: i64 = 0;
            while (c < n) {
                rt_setbyte(lnp, c, hr_lower(rt_byte(q.kn[i].p, c)));
                c += 1;
            }
            rt_setbyte(lnp, n, 0);
            if (hp_out_add(ex, lnp, n, q.kv[i].p, q.kv[i].len) != 0) {
                return HR_ERR;
            }
        }
        i += 1;
    }
    return HR_OK;
}

fn hresp_new() -> HResp {
    var r: HResp = zero(HResp);
    r.status = 0;
    r.ver = 0;
    r.hdr = hp_out_new();
    r.body = hxbuf_new(65536);
    return r;
}

fn hresp_free(r: &mut HResp) {
    hp_out_free(&mut r.hdr);
    hxbuf_free(&mut r.body);
    r.status = 0;
    r.ver = 0;
}

fn hresp_clear(r: &mut HResp) {
    hp_out_clear(&mut r.hdr);
    hxbuf_clear(&mut r.body);
    r.status = 0;
    r.ver = 0;
}

fn hresp_status(r: &mut HResp) -> i64 {
    return r.status;
}

fn hresp_version(r: &mut HResp) -> i32 {
    return r.ver;
}

fn hresp_body(r: &mut HResp) -> ptr<u8> {
    return r.body.p;
}

fn hresp_body_len(r: &mut HResp) -> i64 {
    return r.body.len;
}

fn hresp_body_str(r: &mut HResp) -> ptr<u8> {
    if (r.body.p == null) {
        return null;
    }
    hxbuf_terminate(&mut r.body);
    return r.body.p;
}

fn hresp_header(r: &mut HResp, name: ptr<u8>) -> ptr<u8> {
    let i: i64 = hp_out_find(&mut r.hdr, name, rt_len(name));
    if (i < 0) {
        return null;
    }
    return hp_out_value(&mut r.hdr, i);
}

fn hresp_header_len(r: &mut HResp, name: ptr<u8>) -> i64 {
    let i: i64 = hp_out_find(&mut r.hdr, name, rt_len(name));
    if (i < 0) {
        return -1;
    }
    return hp_out_vlen(&mut r.hdr, i);
}

fn hresp_header_copy(r: &mut HResp, name: ptr<u8>, out: ptr<u8>, cap: i64) -> i64 {
    let i: i64 = hp_out_find(&mut r.hdr, name, rt_len(name));
    if (i < 0 || out == null || cap <= 0) {
        return -1;
    }
    let n: i64 = hp_out_vlen(&mut r.hdr, i);
    if (n + 1 > cap) {
        return -1;
    }
    let vp: ptr<u8> = hp_out_value(&mut r.hdr, i);
    rt_copy(out, vp, n);
    rt_setbyte(out, n, 0);
    return n;
}

fn hresp_header_at(r: &mut HResp, i: i64) -> ptr<u8> {
    return hp_out_name(&mut r.hdr, i);
}

fn hresp_header_count(r: &mut HResp) -> i64 {
    return r.hdr.n;
}

fn hr_take_body(r: &mut HResp, p: ptr<u8>, n: i64) -> i32 {
    hxbuf_clear(&mut r.body);
    if (n > 0 && p != null) {
        if (hxbuf_put(&mut r.body, p, n) != 0) {
            return HR_ERR;
        }
    }
    if (hxbuf_terminate(&mut r.body) != 0) {
        return HR_ERR;
    }
    return HR_OK;
}

fn hr_send_h1(q: &mut HReq, r: &mut HResp, anchor: ptr<u8>, alen: i64) -> i32 {
    var c: H1Conn = zero(H1Conn);
    let hp: ptr<u8> = q.host.p;
    var rc: i32 = 0;
    if (q.tls == 0) {
        rc = h1c_init_plain(&mut c, hp, q.port, q.to_ms, q.max);
    } else {
        if (anchor != null && alen > 0) {
            rc = h1c_init_anchor(&mut c, hp, q.port, q.to_ms, q.max, anchor, alen);
        } else {
            rc = h1c_init(&mut c, hp, q.port, q.to_ms, q.max);
        }
    }
    if (rc != H1C_OK) {
        h1c_close(&mut c);
        return HR_TLS;
    }

    var ex: HxBuf = hxbuf_new(1024);
    if (ex.p == null) {
        h1c_close(&mut c);
        return HR_ERR;
    }
    if (hreq_h1_extra(q, &mut ex) != HR_OK) {
        hxbuf_free(&mut ex);
        h1c_close(&mut c);
        return HR_ERR;
    }

    let bp: ptr<u8> = q.body.p;
    rc = h1c_send(&mut c, q.m.p, q.path.p, ex.p, bp, q.body.len);
    hxbuf_free(&mut ex);
    if (rc != H1C_OK) {
        h1c_close(&mut c);
        return HR_ERR;
    }
    let hm: i32 = hreq_is_head(q);
    if (h1c_expect(&mut c, hm) != H1C_OK) {
        h1c_close(&mut c);
        return HR_ERR;
    }

    hp_out_clear(&mut r.hdr);
    hxbuf_clear(&mut r.body);
    r.status = h1c_status(&mut c);
    r.ver = HTTP_V11;
    var hi: i64 = 0;
    while (hi < c.resp.hn) {
        var np: ptr<u8> = null;
        var vp: ptr<u8> = null;
        unsafe {
            np = c.head.p + c.resp.hoff[hi];
            vp = c.head.p + c.resp.voff[hi];
        }
        if (hp_out_add(&mut r.hdr, np, c.resp.hlen[hi], vp, c.resp.vlen[hi]) != 0) {
            h1c_close(&mut c);
            return HR_ERR;
        }
        hi += 1;
    }
    let bn: i64 = h1c_body_len(&mut c);
    let bpp: ptr<u8> = h1c_body(&mut c);
    rc = hr_take_body(r, bpp, bn);
    h1c_close(&mut c);
    if (rc != HR_OK) {
        return HR_ERR;
    }
    return HR_OK;
}

fn hr_send_h2(q: &mut HReq, r: &mut HResp, anchor: ptr<u8>, alen: i64) -> i32 {
    if (q.tls == 0) {
        return HR_URL;
    }
    var c: H2Conn = zero(H2Conn);
    let hp: ptr<u8> = q.host.p;
    var rc: i32 = 0;
    if (anchor != null && alen > 0) {
        rc = h2c_init_anchor(&mut c, hp, q.port, q.to_ms, q.max, anchor, alen);
    } else {
        rc = h2c_init(&mut c, hp, q.port, q.to_ms, q.max);
    }
    if (rc != H2C_OK) {
        h2c_close(&mut c);
        return HR_TLS;
    }

    var ct: [u8; 128] = [0];
    var ctp: ptr<u8> = null;
    unsafe { ctp = &mut ct[0] as ptr<u8>; }
    if (hreq_ctype(q, ctp, 128) < 0) {
        ctp = null;
    }

    var ex: HxBuf = hxbuf_new(1024);
    if (ex.p == null) {
        h2c_close(&mut c);
        return HR_ERR;
    }
    if (hreq_h2_extra(q, &mut ex) != HR_OK) {
        hxbuf_free(&mut ex);
        h2c_close(&mut c);
        return HR_ERR;
    }

    let bp: ptr<u8> = q.body.p;
    rc = h2c_send_reqx(&mut c, q.m.p, q.path.p, ctp, &mut ex, bp, q.body.len);
    hxbuf_free(&mut ex);
    if (rc != H2C_OK) {
        h2c_close(&mut c);
        return HR_ERR;
    }
    if (h2c_read(&mut c) != H2C_OK) {
        h2c_close(&mut c);
        return HR_ERR;
    }

    hp_out_clear(&mut r.hdr);
    hxbuf_clear(&mut r.body);
    r.status = h2c_status(&mut c);
    r.ver = HTTP_V2;
    let hn: i64 = h2c_hdr_count(&mut c);
    var hi: i64 = 0;
    while (hi < hn) {
        let np: ptr<u8> = h2c_hdr_at_name(&mut c, hi);
        let nl: i64 = h2c_hdr_at_nlen(&mut c, hi);
        let vp: ptr<u8> = h2c_hdr_at_value(&mut c, hi);
        let vl: i64 = h2c_hdr_at_vlen(&mut c, hi);
        if (hp_out_add(&mut r.hdr, np, nl, vp, vl) != 0) {
            h2c_close(&mut c);
            return HR_ERR;
        }
        hi += 1;
    }
    let bn: i64 = h2c_body_len(&mut c);
    let bpp: ptr<u8> = h2c_body(&mut c);
    rc = hr_take_body(r, bpp, bn);
    h2c_close(&mut c);
    if (rc != HR_OK) {
        return HR_ERR;
    }
    return HR_OK;
}

fn hr_send_h3(q: &mut HReq, r: &mut HResp, anchor: ptr<u8>, alen: i64) -> i32 {
    if (q.tls == 0) {
        return HR_URL;
    }
    var h: H3 = h3_new();
    let hp: ptr<u8> = q.host.p;
    var rc: i32 = 0;
    if (anchor != null && alen > 0) {
        rc = h3_open(&mut h, hp, q.port, q.to_ms);
        if (rc == H3_OK) {
            rc = h3_trust_anchor(&mut h, hp, anchor, alen);
        }
    } else {
        rc = h3_open_os(&mut h, hp, q.port, q.to_ms);
    }
    if (rc != H3_OK) {
        h3_free(&mut h);
        return HR_TLS;
    }

    var ex: HpOut = hp_out_new();
    if (ex.buf.p == null) {
        h3_free(&mut h);
        return HR_ERR;
    }
    if (hreq_h3_extra(q, &mut ex) != HR_OK) {
        hp_out_free(&mut ex);
        h3_free(&mut h);
        return HR_ERR;
    }

    let bp: ptr<u8> = q.body.p;
    let rid: i64 = h3_requestx(&mut h, q.m.p, q.path.p, hp, &mut ex, bp, q.body.len);
    hp_out_free(&mut ex);
    if (rid < 0) {
        h3_free(&mut h);
        return HR_ERR;
    }
    if (h3_wait(&mut h, rid, q.to_ms as i64) != H3_OK) {
        h3_release(&mut h, rid);
        h3_free(&mut h);
        return HR_ERR;
    }

    hp_out_clear(&mut r.hdr);
    hxbuf_clear(&mut r.body);
    r.status = h3_status(&mut h, rid);
    r.ver = HTTP_V3;
    let hn: i64 = h3_hcount(&mut h, rid);
    var hi: i64 = 0;
    while (hi < hn) {
        let np: ptr<u8> = h3_hname(&mut h, rid, hi);
        let nl: i64 = h3_hnlen(&mut h, rid, hi);
        let vp: ptr<u8> = h3_hvalue(&mut h, rid, hi);
        let vl: i64 = h3_hvlen(&mut h, rid, hi);
        if (hp_out_add(&mut r.hdr, np, nl, vp, vl) != 0) {
            h3_release(&mut h, rid);
            h3_free(&mut h);
            return HR_ERR;
        }
        hi += 1;
    }
    let bn: i64 = h3_body_len(&mut h, rid);
    let bpp: ptr<u8> = h3_body(&mut h, rid);
    rc = hr_take_body(r, bpp, bn);
    h3_release(&mut h, rid);
    h3_free(&mut h);
    if (rc != HR_OK) {
        return HR_ERR;
    }
    return HR_OK;
}

fn hreq_fetch(q: &mut HReq, r: &mut HResp) -> i32 {
    return hreq_fetch_anchor(q, r, null, 0);
}

fn hreq_fetch_anchor(q: &mut HReq, r: &mut HResp, anchor: ptr<u8>, alen: i64) -> i32 {
    if (hreq_ready(q) != 1 || r.hdr.buf.p == null || r.body.p == null) {
        return HR_ERR;
    }
    if (q.m.len <= 0 || q.host.len <= 0 || q.path.len <= 0) {
        return HR_ERR;
    }
    hresp_clear(r);
    if (q.ver == HTTP_V11) {
        return hr_send_h1(q, r, anchor, alen);
    }
    if (q.ver == HTTP_V2) {
        return hr_send_h2(q, r, anchor, alen);
    }
    if (q.ver == HTTP_V3) {
        return hr_send_h3(q, r, anchor, alen);
    }
    return HR_VER;
}

fn http_get(url: ptr<u8>, r: &mut HResp) -> i32 {
    return http_get_anchor(url, null, 0, r);
}

fn http_get_anchor(url: ptr<u8>, anchor: ptr<u8>, alen: i64, r: &mut HResp) -> i32 {
    var q: HReq = hreq_new();
    var rc: i32 = hreq_open(&mut q, "GET", url);
    if (rc == HR_OK) {
        rc = hreq_fetch_anchor(&mut q, r, anchor, alen);
    }
    hreq_free(&mut q);
    return rc;
}

fn http_post(url: ptr<u8>, ctype: ptr<u8>, body: ptr<u8>, blen: i64, r: &mut HResp) -> i32 {
    return http_post_anchor(url, ctype, body, blen, null, 0, r);
}

fn http_post_anchor(url: ptr<u8>, ctype: ptr<u8>, body: ptr<u8>, blen: i64, anchor: ptr<u8>, alen: i64, r: &mut HResp) -> i32 {
    var q: HReq = hreq_new();
    var rc: i32 = hreq_open(&mut q, "POST", url);
    if (rc == HR_OK && ctype != null) {
        rc = hreq_header(&mut q, "content-type", ctype);
    }
    if (rc == HR_OK) {
        rc = hreq_body(&mut q, body, blen);
    }
    if (rc == HR_OK) {
        rc = hreq_fetch_anchor(&mut q, r, anchor, alen);
    }
    hreq_free(&mut q);
    return rc;
}

fn http_send(method: ptr<u8>, url: ptr<u8>, body: ptr<u8>, blen: i64, r: &mut HResp) -> i32 {
    return http_send_anchor(method, url, body, blen, null, 0, r);
}

fn http_send_anchor(method: ptr<u8>, url: ptr<u8>, body: ptr<u8>, blen: i64, anchor: ptr<u8>, alen: i64, r: &mut HResp) -> i32 {
    var q: HReq = hreq_new();
    var rc: i32 = hreq_open(&mut q, method, url);
    if (rc == HR_OK) {
        rc = hreq_body(&mut q, body, blen);
    }
    if (rc == HR_OK) {
        rc = hreq_fetch_anchor(&mut q, r, anchor, alen);
    }
    hreq_free(&mut q);
    return rc;
}
