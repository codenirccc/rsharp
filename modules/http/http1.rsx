include "rt.rsx";

const H1_MAX_HDR: i64 = 48;

const H1_NEED: i32 = -1;
const H1_BAD: i32 = -2;

const H1_CHUNKED: i32 = 1;
const H1_LENGTH: i32 = 2;
const H1_CLOSE: i32 = 3;
const H1_NONE: i32 = 4;

struct H1Resp {
    status: i64,
    minor: i64,
    head_len: i64,
    hn: i64,
    hoff: [i64; 48],
    hlen: [i64; 48],
    voff: [i64; 48],
    vlen: [i64; 48],
    content_len: i64,
    framing: i32,
    keep_alive: i32
}

struct H1Dec {
    n: i64,
    used: i64,
    more: i32
}

struct H1Span {
    off: i64,
    len: i64
}

fn h1_lower(c: u8) -> u8 {
    if (c >= 65 && c <= 90) {
        return (c + 32) as u8;
    }
    return c;
}

fn h1_ieq(a: ptr<u8>, b: ptr<u8>, n: i64) -> i32 {
    var i: i64 = 0;
    while (i < n) {
        if (h1_lower(rt_byte(a, i)) != h1_lower(rt_byte(b, i))) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn h1_scan_head(p: ptr<u8>, n: i64) -> i64 {
    if (n < 4) {
        return -1;
    }
    var i: i64 = 0;
    while (i + 3 < n) {
        if (rt_byte(p, i) == 13 && rt_byte(p, i + 1) == 10 && rt_byte(p, i + 2) == 13 && rt_byte(p, i + 3) == 10) {
            return i + 4;
        }
        i += 1;
    }
    return -1;
}

fn h1_digit(c: u8) -> i64 {
    if (c >= 48 && c <= 57) {
        return (c as i64) - 48;
    }
    return -1;
}

fn h1_tchar(c: u8) -> i32 {
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

fn h1_parse_head(p: ptr<u8>, n: i64, r: &mut H1Resp) -> i32 {
    let end: i64 = h1_scan_head(p, n);
    if (end < 0) {
        return H1_NEED;
    }
    if (end < 14) {
        return H1_BAD;
    }
    if (rt_byte(p, 0) != 72 || rt_byte(p, 1) != 84 || rt_byte(p, 2) != 84 || rt_byte(p, 3) != 80) {
        return H1_BAD;
    }
    if (rt_byte(p, 4) != 47) {
        return H1_BAD;
    }
    let d9: i64 = h1_digit(rt_byte(p, 9));
    let d10: i64 = h1_digit(rt_byte(p, 10));
    let d11: i64 = h1_digit(rt_byte(p, 11));
    if (d9 < 0 || d10 < 0 || d11 < 0) {
        return H1_BAD;
    }
    r.status = d9 * 100 + d10 * 10 + d11;
    r.minor = h1_digit(rt_byte(p, 7));
    r.head_len = end;
    r.hn = 0;

    var ls: i64 = 0;
    var found: i32 = 0;
    while (ls + 1 < end && found == 0) {
        if (rt_byte(p, ls) == 13 && rt_byte(p, ls + 1) == 10) {
            ls += 2;
            found = 1;
        } else {
            ls += 1;
        }
    }
    if (found == 0) {
        return H1_BAD;
    }

    var i: i64 = ls;
    while (i + 1 < end) {
        if (rt_byte(p, i) == 13 && rt_byte(p, i + 1) == 10) {
            return 0;
        }
        var colon: i64 = i;
        while (colon < end && rt_byte(p, colon) != 58) {
            if (h1_tchar(rt_byte(p, colon)) != 1) {
                return H1_BAD;
            }
            colon += 1;
        }
        if (colon >= end || colon == i) {
            return H1_BAD;
        }
        var vs: i64 = colon + 1;
        while (vs < end && (rt_byte(p, vs) == 32 || rt_byte(p, vs) == 9)) {
            vs += 1;
        }
        var ve: i64 = vs;
        var closed: i32 = 0;
        while (ve + 1 < end && closed == 0) {
            if (rt_byte(p, ve) == 13 && rt_byte(p, ve + 1) == 10) {
                closed = 1;
            } else {
                let vc: u8 = rt_byte(p, ve);
                if ((vc < 32 && vc != 9) || vc == 127) {
                    return H1_BAD;
                }
                ve += 1;
            }
        }
        if (closed == 0) {
            return H1_BAD;
        }
        if (r.hn >= H1_MAX_HDR) {
            return H1_BAD;
        }
        let slot: i64 = r.hn;
        r.hoff[slot] = i;
        r.hlen[slot] = colon - i;
        r.voff[slot] = vs;
        r.vlen[slot] = ve - vs;
        r.hn += 1;
        i = ve + 2;
    }
    return H1_BAD;
}

fn h1_find(p: ptr<u8>, n: i64, r: &mut H1Resp, name: ptr<u8>, nlen: i64) -> i64 {
    var i: i64 = 0;
    while (i < r.hn) {
        if (r.hlen[i] == nlen) {
            if (r.hoff[i] < n && r.hoff[i] + nlen <= n) {
                var hp: ptr<u8> = null;
                unsafe { hp = p + r.hoff[i]; }
                if (h1_ieq(hp, name, nlen) == 1) {
                    return i;
                }
            }
        }
        i += 1;
    }
    return -1;
}

fn h1_value(r: &mut H1Resp, i: i64) -> H1Span {
    var s: H1Span = zero(H1Span);
    if (i < 0 || i >= r.hn) {
        return s;
    }
    s.off = r.voff[i];
    s.len = r.vlen[i];
    return s;
}

fn h1_value_has(p: ptr<u8>, n: i64, r: &mut H1Resp, i: i64, word: ptr<u8>, wlen: i64) -> i32 {
    if (i < 0 || i >= r.hn) {
        return 0;
    }
    let start: i64 = r.voff[i];
    let stop: i64 = start + r.vlen[i];
    if (stop > n) {
        return 0;
    }
    var at: i64 = start;
    while (at + wlen <= stop) {
        var vp: ptr<u8> = null;
        unsafe { vp = p + at; }
        if (h1_ieq(vp, word, wlen) == 1) {
            let after: i64 = at + wlen;
            if (after == stop) {
                return 1;
            }
            let c: u8 = rt_byte(p, after);
            if (c == 44 || c == 59 || c == 32) {
                return 1;
            }
        }
        at += 1;
    }
    return 0;
}

fn h1_value_int(p: ptr<u8>, n: i64, r: &mut H1Resp, i: i64) -> i64 {
    if (i < 0 || i >= r.hn) {
        return -1;
    }
    let start: i64 = r.voff[i];
    let stop: i64 = start + r.vlen[i];
    if (stop > n) {
        return -1;
    }
    var v: i64 = 0;
    var digits: i64 = 0;
    var at: i64 = start;
    while (at < stop) {
        let d: i64 = h1_digit(rt_byte(p, at));
        if (d < 0) {
            if (digits == 0) {
                return -1;
            }
            return v;
        }
        v = v * 10 + d;
        digits += 1;
        if (v > 1073741824) {
            return -1;
        }
        at += 1;
    }
    if (digits == 0) {
        return -1;
    }
    return v;
}

fn h1_count(p: ptr<u8>, n: i64, r: &mut H1Resp, name: ptr<u8>, nlen: i64) -> i64 {
    var i: i64 = 0;
    var cnt: i64 = 0;
    while (i < r.hn) {
        if (r.hlen[i] == nlen) {
            if (r.hoff[i] < n && r.hoff[i] + nlen <= n) {
                var hp: ptr<u8> = null;
                unsafe { hp = p + r.hoff[i]; }
                if (h1_ieq(hp, name, nlen) == 1) {
                    cnt += 1;
                }
            }
        }
        i += 1;
    }
    return cnt;
}

fn h1_cl_strict(p: ptr<u8>, n: i64, r: &mut H1Resp, i: i64) -> i64 {
    if (i < 0 || i >= r.hn) {
        return -1;
    }
    if (r.voff[i] < 0 || r.voff[i] + r.vlen[i] > n) {
        return -1;
    }
    var a: i64 = r.voff[i];
    var z: i64 = r.voff[i] + r.vlen[i];
    while (a < z && (rt_byte(p, a) == 32 || rt_byte(p, a) == 9)) {
        a += 1;
    }
    while (z > a && (rt_byte(p, z - 1) == 32 || rt_byte(p, z - 1) == 9)) {
        z -= 1;
    }
    if (z <= a) {
        return -1;
    }
    var v: i64 = 0;
    var at: i64 = a;
    while (at < z) {
        let d: i64 = h1_digit(rt_byte(p, at));
        if (d < 0) {
            return -1;
        }
        v = v * 10 + d;
        if (v > 1073741824) {
            return -1;
        }
        at += 1;
    }
    return v;
}

fn h1_te_exact(p: ptr<u8>, n: i64, r: &mut H1Resp, i: i64) -> i32 {
    if (i < 0 || i >= r.hn) {
        return 0;
    }
    if (r.voff[i] < 0 || r.voff[i] + r.vlen[i] > n) {
        return 0;
    }
    var a: i64 = r.voff[i];
    var z: i64 = r.voff[i] + r.vlen[i];
    while (a < z && (rt_byte(p, a) == 32 || rt_byte(p, a) == 9)) {
        a += 1;
    }
    while (z > a && (rt_byte(p, z - 1) == 32 || rt_byte(p, z - 1) == 9)) {
        z -= 1;
    }
    if (z - a != 7) {
        return 0;
    }
    var vp: ptr<u8> = null;
    unsafe { vp = p + a; }
    return h1_ieq(vp, "chunked", 7);
}

fn h1_framing(p: ptr<u8>, n: i64, r: &mut H1Resp, head_method: i32) -> i32 {
    r.content_len = -1;
    r.framing = H1_CLOSE;
    let conn: i64 = h1_find(p, n, r, "connection", 10);
    r.keep_alive = 0;
    if (h1_value_has(p, n, r, conn, "keep-alive", 10) == 1) {
        r.keep_alive = 1;
    }
    if (h1_value_has(p, n, r, conn, "close", 5) == 1) {
        r.keep_alive = 0;
    }
    if (r.minor == 1) {
        if (h1_value_has(p, n, r, conn, "close", 5) == 0) {
            r.keep_alive = 1;
        }
    }
    if (head_method == 1) {
        r.framing = H1_NONE;
        return 0;
    }
    if (r.status == 204 || r.status == 304) {
        r.framing = H1_NONE;
        return 0;
    }
    let nte: i64 = h1_count(p, n, r, "transfer-encoding", 17);
    let ncl: i64 = h1_count(p, n, r, "content-length", 14);
    if (nte > 1 || ncl > 1) {
        return H1_BAD;
    }
    if (nte == 1 && ncl == 1) {
        return H1_BAD;
    }
    if (nte == 1) {
        let te: i64 = h1_find(p, n, r, "transfer-encoding", 17);
        if (h1_te_exact(p, n, r, te) != 1) {
            return H1_BAD;
        }
        r.framing = H1_CHUNKED;
        return 0;
    }
    if (ncl == 1) {
        let cl: i64 = h1_find(p, n, r, "content-length", 14);
        let v: i64 = h1_cl_strict(p, n, r, cl);
        if (v < 0) {
            return H1_BAD;
        }
        r.content_len = v;
        r.framing = H1_LENGTH;
        return 0;
    }
    return 0;
}

fn h1_dechunk(src: ptr<u8>, n: i64, out: ptr<u8>, cap: i64, d: &mut H1Dec) -> i32 {
    d.n = 0;
    d.used = 0;
    d.more = 0;
    var i: i64 = 0;
    var o: i64 = 0;
    while (i < n) {
        var sz: i64 = 0;
        var digits: i64 = 0;
        var stop: i64 = 0;
        while (i < n && stop == 0) {
            let c: u8 = rt_byte(src, i);
            var dv: i64 = -1;
            if (c >= 48 && c <= 57) {
                dv = (c as i64) - 48;
            } else if (c >= 97 && c <= 102) {
                dv = (c as i64) - 87;
            } else if (c >= 65 && c <= 70) {
                dv = (c as i64) - 55;
            }
            if (dv < 0) {
                stop = 1;
            } else {
                sz = sz * 16 + dv;
                digits += 1;
                i += 1;
                if (digits > 15 || sz > 16777216) {
                    return H1_BAD;
                }
            }
        }
        if (digits == 0) {
            return H1_BAD;
        }
        while (i < n && rt_byte(src, i) != 10) {
            i += 1;
        }
        if (i >= n) {
            d.n = o;
            d.more = 1;
            return 0;
        }
        i += 1;
        if (sz == 0) {
            if (i + 1 < n && rt_byte(src, i) == 13 && rt_byte(src, i + 1) == 10) {
                d.n = o;
                d.used = i + 2;
                return 0;
            }
            var k: i64 = i;
            while (k + 3 < n) {
                if (rt_byte(src, k) == 13 && rt_byte(src, k + 1) == 10 && rt_byte(src, k + 2) == 13 && rt_byte(src, k + 3) == 10) {
                    d.n = o;
                    d.used = k + 4;
                    return 0;
                }
                k += 1;
            }
            d.n = o;
            d.more = 1;
            return 0;
        }
        if (i + sz > n) {
            d.n = o;
            d.more = 1;
            return 0;
        }
        if (o + sz > cap) {
            return H1_BAD;
        }
        var dst: ptr<u8> = null;
        var srcp: ptr<u8> = null;
        unsafe {
            dst = out + o;
            srcp = src + i;
        }
        rt_copy(dst, srcp, sz);
        o += sz;
        i += sz;
        if (i + 1 >= n) {
            d.n = o;
            d.more = 1;
            return 0;
        }
        if (rt_byte(src, i) == 13 && rt_byte(src, i + 1) == 10) {
            i += 2;
        } else if (rt_byte(src, i) == 10) {
            i += 1;
        } else {
            return H1_BAD;
        }
    }
    d.n = o;
    d.more = 1;
    return 0;
}

fn h1_build_req(b: &mut HxBuf, method: ptr<u8>, host: ptr<u8>, target: ptr<u8>, extra: ptr<u8>, body: ptr<u8>, blen: i64) -> i32 {
    hxbuf_clear(b);
    if (hxbuf_puts(b, method) != 0) {
        return H1_BAD;
    }
    if (hxbuf_putc(b, 32) != 0) {
        return H1_BAD;
    }
    if (hxbuf_puts(b, target) != 0) {
        return H1_BAD;
    }
    if (hxbuf_puts(b, " HTTP/1.1\r\nHost: ") != 0) {
        return H1_BAD;
    }
    if (hxbuf_puts(b, host) != 0) {
        return H1_BAD;
    }
    if (hxbuf_puts(b, "\r\nUser-Agent: rsharp-http/1.1\r\nAccept: */*\r\nConnection: keep-alive\r\n") != 0) {
        return H1_BAD;
    }
    if (blen > 0) {
        if (hxbuf_puts(b, "Content-Length: ") != 0) {
            return H1_BAD;
        }
        if (hxbuf_putu(b, blen) != 0) {
            return H1_BAD;
        }
        if (hxbuf_puts(b, "\r\n") != 0) {
            return H1_BAD;
        }
    }
    if (extra != null) {
        if (hxbuf_puts(b, extra) != 0) {
            return H1_BAD;
        }
    }
    if (hxbuf_puts(b, "\r\n") != 0) {
        return H1_BAD;
    }
    if (blen > 0 && body != null) {
        if (hxbuf_put(b, body, blen) != 0) {
            return H1_BAD;
        }
    }
    return 0;
}
