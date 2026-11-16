include "http1.rsx";
include "https_win.rsx";

const H1C_OK: i32 = 0;
const H1C_ERR: i32 = -1;
const H1C_EOF: i32 = -2;
const H1C_BIG: i32 = -3;

struct H1Conn {
    h: Https,
    inb: HxBuf,
    tmp: HxBuf,
    out: HxBuf,
    body: HxBuf,
    head: HxBuf,
    host: [u8; 256],
    hdr: [u8; 300],
    resp: H1Resp,
    body_len: i64,
    max: i64,
    eof: i32,
    live: i32
}

fn h1c_setstr(dst: ptr<u8>, cap: i64, src: ptr<u8>) -> i64 {
    let n: i64 = rt_len(src);
    if (n >= cap) {
        return -1;
    }
    rt_copy(dst, src, n);
    rt_setbyte(dst, n, 0);
    return n;
}

fn h1c_prepare(c: &mut H1Conn, host: ptr<u8>, port: u16, max: i64) -> i32 {
    c.body_len = 0;
    c.max = max;
    c.eof = 0;
    c.live = 0;
    c.resp = zero(H1Resp);
    c.h.t.alpn_mode = 1;
    var hp: ptr<u8> = null;
    unsafe { hp = &mut c.host[0] as ptr<u8>; }
    if (h1c_setstr(hp, 256, host) < 0) {
        return H1C_ERR;
    }
    var dp: ptr<u8> = null;
    unsafe { dp = &mut c.hdr[0] as ptr<u8>; }
    let hn: i64 = rt_len(host);
    rt_copy(dp, host, hn);
    var at: i64 = hn;
    if (port != 443) {
        rt_setbyte(dp, at, 58);
        at += 1;
        var dg: [u8; 8] = [0];
        var i: i64 = 0;
        var v: i64 = port as i64;
        if (v == 0) {
            rt_setbyte(dp, at, 48);
            at += 1;
        }
        while (v > 0) {
            dg[i] = (48 + (v % 10)) as u8;
            v = v / 10;
            i += 1;
        }
        var k: i64 = i;
        while (k > 0) {
            k -= 1;
            rt_setbyte(dp, at, dg[k]);
            at += 1;
        }
    }
    rt_setbyte(dp, at, 0);
    c.inb = hxbuf_new(16384);
    c.tmp = hxbuf_new(8192);
    c.out = hxbuf_new(4096);
    c.body = hxbuf_new(max);
    c.head = hxbuf_new(16384);
    if (c.inb.p == null || c.tmp.p == null || c.out.p == null || c.body.p == null || c.head.p == null) {
        return H1C_ERR;
    }
    return H1C_OK;
}

fn h1c_hostp(c: &mut H1Conn) -> ptr<u8> {
    var p: ptr<u8> = null;
    unsafe { p = &mut c.host[0] as ptr<u8>; }
    return p;
}

fn h1c_init(c: &mut H1Conn, host: ptr<u8>, port: u16, to_ms: i32, max: i64) -> i32 {
    if (h1c_prepare(c, host, port, max) != H1C_OK) {
        h1c_free(c);
        return H1C_ERR;
    }
    let hp: ptr<u8> = h1c_hostp(c);
    if (https_open(&mut c.h, hp, port, to_ms) != HTTPS_OK) {
        h1c_free(c);
        return H1C_ERR;
    }
    c.live = 1;
    return H1C_OK;
}

fn h1c_init_anchor(c: &mut H1Conn, host: ptr<u8>, port: u16, to_ms: i32, max: i64, anchor: ptr<u8>, alen: i64) -> i32 {
    if (h1c_prepare(c, host, port, max) != H1C_OK) {
        h1c_free(c);
        return H1C_ERR;
    }
    let hp: ptr<u8> = h1c_hostp(c);
    if (https_open_anchor(&mut c.h, hp, port, to_ms, anchor, alen) != HTTPS_OK) {
        h1c_free(c);
        return H1C_ERR;
    }
    c.live = 1;
    return H1C_OK;
}

fn h1c_init_plain(c: &mut H1Conn, host: ptr<u8>, port: u16, to_ms: i32, max: i64) -> i32 {
    if (h1c_prepare(c, host, port, max) != H1C_OK) {
        h1c_free(c);
        return H1C_ERR;
    }
    let hp: ptr<u8> = h1c_hostp(c);
    if (https_open_plain(&mut c.h, hp, port, to_ms) != HTTPS_OK) {
        h1c_free(c);
        return H1C_ERR;
    }
    c.live = 1;
    return H1C_OK;
}

fn h1c_init_proxy(c: &mut H1Conn, proxy: ptr<u8>, pport: u16, host: ptr<u8>, port: u16, to_ms: i32, max: i64) -> i32 {
    if (h1c_prepare(c, host, port, max) != H1C_OK) {
        h1c_free(c);
        return H1C_ERR;
    }
    let hp: ptr<u8> = h1c_hostp(c);
    if (https_open_proxy(&mut c.h, proxy, pport, hp, port, to_ms) != HTTPS_OK) {
        h1c_free(c);
        return H1C_ERR;
    }
    c.live = 1;
    return H1C_OK;
}

fn h1c_init_proxy_anchor(c: &mut H1Conn, proxy: ptr<u8>, pport: u16, host: ptr<u8>, port: u16, to_ms: i32, max: i64, anchor: ptr<u8>, alen: i64) -> i32 {
    if (h1c_prepare(c, host, port, max) != H1C_OK) {
        h1c_free(c);
        return H1C_ERR;
    }
    let hp: ptr<u8> = h1c_hostp(c);
    if (https_open_proxy_anchor(&mut c.h, proxy, pport, hp, port, to_ms, anchor, alen) != HTTPS_OK) {
        h1c_free(c);
        return H1C_ERR;
    }
    c.live = 1;
    return H1C_OK;
}

fn h1c_free(c: &mut H1Conn) {
    hxbuf_free(&mut c.inb);
    hxbuf_free(&mut c.tmp);
    hxbuf_free(&mut c.out);
    hxbuf_free(&mut c.body);
    hxbuf_free(&mut c.head);
    c.body_len = 0;
}

fn h1c_close(c: &mut H1Conn) {
    if (c.live == 1) {
        https_close(&mut c.h);
        c.live = 0;
    }
    h1c_free(c);
    c.eof = 1;
}

fn h1c_shutdown(c: &mut H1Conn) {
    if (c.live == 1) {
        https_close(&mut c.h);
        c.live = 0;
    }
    c.eof = 1;
}

fn h1c_fill(c: &mut H1Conn) -> i32 {
    if (c.live != 1) {
        return H1C_EOF;
    }
    if (c.inb.len >= c.max + 65536) {
        return H1C_BIG;
    }
    let tp: ptr<u8> = c.tmp.p;
    let n: i64 = https_read(&mut c.h, tp, c.tmp.cap);
    if (n == 0) {
        c.eof = 1;
        return H1C_EOF;
    }
    if (n < 0) {
        return H1C_ERR;
    }
    if (hxbuf_put(&mut c.inb, tp, n) != 0) {
        return H1C_BIG;
    }
    return n as i32;
}

fn h1c_compact(c: &mut H1Conn, used: i64) -> i32 {
    if (used < 0 || used > c.inb.len) {
        return H1C_ERR;
    }
    let rest: i64 = c.inb.len - used;
    var i: i64 = 0;
    while (i < rest) {
        var v: u8 = 0;
        unsafe { v = c.inb.p[used + i]; }
        unsafe { c.inb.p[i] = v; }
        i += 1;
    }
    c.inb.len = rest;
    return H1C_OK;
}

fn h1c_send(c: &mut H1Conn, method: ptr<u8>, target: ptr<u8>, extra: ptr<u8>, body: ptr<u8>, blen: i64) -> i32 {
    if (c.live != 1) {
        return H1C_ERR;
    }
    var hp: ptr<u8> = null;
    unsafe { hp = &mut c.hdr[0] as ptr<u8>; }
    if (h1_build_req(&mut c.out, method, hp, target, extra, body, blen) != 0) {
        return H1C_ERR;
    }
    let n: i64 = https_write(&mut c.h, c.out.p, c.out.len);
    if (n != c.out.len) {
        return H1C_ERR;
    }
    return H1C_OK;
}

fn h1c_expect(c: &mut H1Conn, head_method: i32) -> i32 {
    c.body_len = 0;
    if (c.live != 1) {
        return H1C_EOF;
    }
    var go: i32 = 1;
    var guard: i32 = 0;
    var interim: i32 = 0;
    while (go == 1) {
        var have: i64 = -1;
        var spin: i32 = 1;
        while (spin == 1) {
            have = h1_scan_head(c.inb.p, c.inb.len);
            if (have >= 0) {
                spin = 0;
                break;
            }
            if (c.eof == 1) {
                return H1C_EOF;
            }
            let filled: i32 = h1c_fill(c);
            if (filled < 0) {
                if (c.eof == 1) {
                    return H1C_EOF;
                }
                return H1C_ERR;
            }
            guard += 1;
            if (guard > 8192) {
                return H1C_ERR;
            }
        }
        let hp: ptr<u8> = c.inb.p;
        let hn: i64 = c.inb.len;
        let pr: i32 = h1_parse_head(hp, hn, &mut c.resp);
        if (pr != 0) {
            return H1C_ERR;
        }
        if (c.resp.status >= 100 && c.resp.status < 200) {
            interim += 1;
            if (interim > 8) {
                return H1C_ERR;
            }
            let skip: i64 = c.resp.head_len;
            if (h1c_compact(c, skip) != H1C_OK) {
                return H1C_ERR;
            }
        } else {
            go = 0;
        }
    }

    hxbuf_clear(&mut c.head);
    if (hxbuf_put(&mut c.head, c.inb.p, c.resp.head_len) != 0) {
        return H1C_BIG;
    }
    let hp2: ptr<u8> = c.head.p;
    let hn2: i64 = c.head.len;
    if (h1_framing(hp2, hn2, &mut c.resp, head_method) != 0) {
        return H1C_ERR;
    }
    let head_len: i64 = c.resp.head_len;

    if (c.resp.framing == H1_NONE) {
        if (h1c_compact(c, head_len) != H1C_OK) {
            return H1C_ERR;
        }
        if (c.resp.keep_alive != 1) {
            h1c_shutdown(c);
        }
        return H1C_OK;
    }

    if (c.resp.framing == H1_LENGTH) {
        let need: i64 = head_len + c.resp.content_len;
        if (c.resp.content_len > c.max) {
            return H1C_BIG;
        }
        var have2: i32 = 0;
        while (have2 == 0) {
            if (c.inb.len >= need) {
                have2 = 1;
                break;
            }
            if (c.eof == 1) {
                return H1C_EOF;
            }
            let filled: i32 = h1c_fill(c);
            if (filled < 0) {
                if (c.eof == 1) {
                    return H1C_EOF;
                }
                return H1C_ERR;
            }
        }
        var sp: ptr<u8> = null;
        unsafe { sp = c.inb.p + head_len; }
        if (c.resp.content_len > 0) {
            rt_copy(c.body.p, sp, c.resp.content_len);
        }
        c.body_len = c.resp.content_len;
        if (h1c_compact(c, need) != H1C_OK) {
            return H1C_ERR;
        }
        if (c.resp.keep_alive != 1) {
            h1c_shutdown(c);
        }
        return H1C_OK;
    }

    if (c.resp.framing == H1_CHUNKED) {
        var dec: H1Dec = zero(H1Dec);
        var spin2: i32 = 1;
        while (spin2 == 1) {
            var src: ptr<u8> = null;
            unsafe { src = c.inb.p + head_len; }
            let avail: i64 = c.inb.len - head_len;
            let rc: i32 = h1_dechunk(src, avail, c.body.p, c.body.cap, &mut dec);
            if (rc != 0) {
                return H1C_ERR;
            }
            if (dec.more == 0) {
                c.body_len = dec.n;
                let used: i64 = head_len + dec.used;
                if (h1c_compact(c, used) != H1C_OK) {
                    return H1C_ERR;
                }
                if (c.resp.keep_alive != 1) {
                    h1c_shutdown(c);
                }
                return H1C_OK;
            }
            c.body_len = 0;
            if (c.eof == 1) {
                return H1C_EOF;
            }
            let filled: i32 = h1c_fill(c);
            if (filled < 0) {
                if (c.eof == 1) {
                    return H1C_EOF;
                }
                return H1C_ERR;
            }
        }
        return H1C_ERR;
    }

    var spin3: i32 = 1;
    while (spin3 == 1) {
        let avail: i64 = c.inb.len - head_len;
        if (avail > c.max) {
            return H1C_BIG;
        }
        if (c.eof == 1) {
            spin3 = 0;
            break;
        }
        let filled: i32 = h1c_fill(c);
        if (filled < 0) {
            if (c.eof == 1) {
                spin3 = 0;
                break;
            }
            return H1C_ERR;
        }
    }
    let blen: i64 = c.inb.len - head_len;
    if (blen > c.max) {
        return H1C_BIG;
    }
    var bp: ptr<u8> = null;
    unsafe { bp = c.inb.p + head_len; }
    if (blen > 0) {
        rt_copy(c.body.p, bp, blen);
    }
    c.body_len = blen;
    h1c_compact(c, c.inb.len);
    h1c_shutdown(c);
    return H1C_OK;
}

fn h1c_get(c: &mut H1Conn, target: ptr<u8>) -> i32 {
    if (h1c_send(c, "GET", target, null, null, 0) != H1C_OK) {
        return H1C_ERR;
    }
    return h1c_expect(c, 0);
}

fn h1c_head(c: &mut H1Conn, target: ptr<u8>) -> i32 {
    if (h1c_send(c, "HEAD", target, null, null, 0) != H1C_OK) {
        return H1C_ERR;
    }
    return h1c_expect(c, 1);
}

fn h1c_post(c: &mut H1Conn, target: ptr<u8>, ctype: ptr<u8>, body: ptr<u8>, blen: i64) -> i32 {
    var extra: HxBuf = hxbuf_new(128);
    if (extra.p == null) {
        return H1C_ERR;
    }
    if (ctype != null) {
        hxbuf_puts(&mut extra, "Content-Type: ");
        hxbuf_puts(&mut extra, ctype);
        hxbuf_puts(&mut extra, "\r\n");
    }
    if (hxbuf_terminate(&mut extra) != 0) {
        hxbuf_free(&mut extra);
        return H1C_ERR;
    }
    let ep: ptr<u8> = extra.p;
    let rc: i32 = h1c_send(c, "POST", target, ep, body, blen);
    hxbuf_free(&mut extra);
    if (rc != H1C_OK) {
        return H1C_ERR;
    }
    return h1c_expect(c, 0);
}

fn h1c_status(c: &mut H1Conn) -> i64 {
    return c.resp.status;
}

fn h1c_body(c: &mut H1Conn) -> ptr<u8> {
    return c.body.p;
}

fn h1c_body_len(c: &mut H1Conn) -> i64 {
    return c.body_len;
}

fn h1c_body_str(c: &mut H1Conn) -> ptr<u8> {
    if (c.body.p == null) {
        return null;
    }
    c.body.len = c.body_len;
    if (hxbuf_terminate(&mut c.body) != 0) {
        return null;
    }
    return c.body.p;
}

fn h1c_hdr(c: &mut H1Conn, name: ptr<u8>, nlen: i64) -> H1Span {
    var s: H1Span = zero(H1Span);
    let hp: ptr<u8> = c.head.p;
    let hn: i64 = c.head.len;
    let i: i64 = h1_find(hp, hn, &mut c.resp, name, nlen);
    if (i < 0) {
        return s;
    }
    s.off = c.resp.voff[i];
    s.len = c.resp.vlen[i];
    return s;
}

fn h1c_hdr_str(c: &mut H1Conn, name: ptr<u8>, nlen: i64, out: ptr<u8>, cap: i64) -> i64 {
    let s: H1Span = h1c_hdr(c, name, nlen);
    if (s.len <= 0 || s.len >= cap) {
        return -1;
    }
    var sp: ptr<u8> = null;
    unsafe { sp = c.head.p + s.off; }
    rt_copy(out, sp, s.len);
    rt_setbyte(out, s.len, 0);
    return s.len;
}
