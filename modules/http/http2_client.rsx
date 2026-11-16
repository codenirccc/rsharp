include "hpack.rsx";
include "http2.rsx";
include "https_win.rsx";

const H2C_OK: i32 = 0;
const H2C_ERR: i32 = -1;
const H2C_EOF: i32 = -2;
const H2C_BIG: i32 = -3;
const H2C_CLOSED: i32 = -4;
const H2C_GOAWAY: i32 = -5;

const H2C_MAX_FRAME: i64 = 16384;
const H2C_PEER_FRAME: i64 = 16384;
const H2C_WINDOW: i64 = 65535;

struct H2Span {
    off: i64,
    len: i64
}

struct H2Conn {
    h: Https,
    dec: Hpack,
    hdrs: HpOut,
    inb: HxBuf,
    tmp: HxBuf,
    out: HxBuf,
    body: HxBuf,
    blk: HxBuf,
    host: [u8; 256],
    auth: [u8; 300],
    alpn: [u8; 16],
    next_stream: i64,
    last_stream: i64,
    status: i64,
    max_body: i64,
    max_frame: i64,
    peer_frame: i64,
    send_win: i64,
    cur_win: i64,
    end_hdr: i32,
    end_body: i32,
    got_settings: i32,
    interim: i32,
    trail: i32,
    eof: i32,
    live: i32
}

fn h2c_setstr(dst: ptr<u8>, cap: i64, src: ptr<u8>) -> i64 {
    let n: i64 = rt_len(src);
    if (n < 0 || n >= cap) {
        return -1;
    }
    rt_copy(dst, src, n);
    rt_setbyte(dst, n, 0);
    return n;
}

fn h2c_atoi(p: ptr<u8>, n: i64) -> i64 {
    if (p == null || n <= 0 || n > 10) {
        return -1;
    }
    var v: i64 = 0;
    var i: i64 = 0;
    while (i < n) {
        var c: u8 = 0;
        unsafe { c = p[i]; }
        if (c < 48 || c > 57) {
            return -1;
        }
        v = v * 10 + ((c - 48) as i64);
        i += 1;
    }
    return v;
}

fn h2c_itoa(v: i64, out: ptr<u8>, cap: i64) -> i64 {
    if (v < 0 || cap < 24) {
        return -1;
    }
    var dg: [u8; 24] = [0];
    var i: i64 = 0;
    if (v == 0) {
        dg[0] = 48;
        i = 1;
    }
    while (v > 0) {
        dg[i] = (48 + (v % 10)) as u8;
        v = v / 10;
        i += 1;
    }
    var k: i64 = 0;
    while (k < i) {
        rt_setbyte(out, k, dg[i - 1 - k]);
        k += 1;
    }
    rt_setbyte(out, i, 0);
    return i;
}

fn h2c_prepare(c: &mut H2Conn, host: ptr<u8>, port: u16, max_body: i64) -> i32 {
    c.next_stream = 1;
    c.last_stream = 0;
    c.status = 0;
    c.max_body = max_body;
    c.max_frame = H2C_MAX_FRAME;
    c.peer_frame = H2C_PEER_FRAME;
    c.send_win = H2C_WINDOW;
    c.cur_win = H2C_WINDOW;
    c.end_hdr = 0;
    c.end_body = 0;
    c.got_settings = 0;
    c.interim = 0;
    c.trail = 0;
    c.eof = 0;
    c.live = 0;
    c.h.t.alpn_mode = 2;
    var hp: ptr<u8> = null;
    unsafe { hp = &mut c.host[0] as ptr<u8>; }
    if (h2c_setstr(hp, 256, host) < 0) {
        return H2C_ERR;
    }
    var ap: ptr<u8> = null;
    unsafe { ap = &mut c.auth[0] as ptr<u8>; }
    let hn: i64 = rt_len(host);
    if (hn >= 300) {
        return H2C_ERR;
    }
    rt_copy(ap, host, hn);
    var at: i64 = hn;
    if (port != 443) {
        rt_setbyte(ap, at, 58);
        at += 1;
        var dg: [u8; 8] = [0];
        var i: i64 = 0;
        var v: i64 = port as i64;
        if (v == 0) {
            rt_setbyte(ap, at, 48);
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
            rt_setbyte(ap, at, dg[k]);
            at += 1;
        }
    }
    rt_setbyte(ap, at, 0);
    c.dec = hpack_new();
    c.hdrs = hp_out_new();
    c.inb = hxbuf_new(65536);
    c.tmp = hxbuf_new(16384);
    c.out = hxbuf_new(16384);
    c.body = hxbuf_new(max_body);
    c.blk = hxbuf_new(65536);
    if (c.dec.tree.nodes <= 0 || c.hdrs.buf.p == null) {
        return H2C_ERR;
    }
    if (c.inb.p == null || c.tmp.p == null || c.out.p == null) {
        return H2C_ERR;
    }
    if (c.body.p == null || c.blk.p == null) {
        return H2C_ERR;
    }
    return H2C_OK;
}

fn h2c_hostp(c: &mut H2Conn) -> ptr<u8> {
    var p: ptr<u8> = null;
    unsafe { p = &mut c.host[0] as ptr<u8>; }
    return p;
}

fn h2c_alpn_p(c: &mut H2Conn) -> ptr<u8> {
    var p: ptr<u8> = null;
    unsafe { p = &mut c.alpn[0] as ptr<u8>; }
    return p;
}

fn h2c_free(c: &mut H2Conn) {
    hpack_free(&mut c.dec);
    hp_out_free(&mut c.hdrs);
    hxbuf_free(&mut c.inb);
    hxbuf_free(&mut c.tmp);
    hxbuf_free(&mut c.out);
    hxbuf_free(&mut c.body);
    hxbuf_free(&mut c.blk);
}

fn h2c_flush(c: &mut H2Conn) -> i32 {
    if (c.out.len == 0) {
        return H2C_OK;
    }
    let want: i64 = c.out.len;
    let n: i64 = https_write(&mut c.h, c.out.p, want);
    c.out.len = 0;
    if (n != want) {
        return H2C_ERR;
    }
    return H2C_OK;
}

fn h2c_fill(c: &mut H2Conn) -> i32 {
    if (c.live != 1) {
        return H2C_EOF;
    }
    var tp: ptr<u8> = null;
    var cap: i64 = 0;
    unsafe {
        tp = c.tmp.p;
        cap = c.tmp.cap;
    }
    let n: i64 = https_read(&mut c.h, tp, cap);
    if (n == 0) {
        c.eof = 1;
        return H2C_EOF;
    }
    if (n < 0) {
        return H2C_ERR;
    }
    if (hxbuf_put(&mut c.inb, tp, n) != 0) {
        return H2C_ERR;
    }
    return n as i32;
}

fn h2c_drop(c: &mut H2Conn, used: i64) -> i32 {
    if (used < 0 || used > c.inb.len) {
        return H2C_ERR;
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
    return H2C_OK;
}

fn h2c_next(c: &mut H2Conn, h: &mut H2Hdr) -> i32 {
    var tries: i64 = 0;
    while (tries < 8192) {
        let rc: i32 = h2_hdr_parse(c.inb.p, c.inb.len, h);
        if (rc == H2_OK) {
            return H2C_OK;
        }
        if (rc == H2_BAD) {
            return H2C_ERR;
        }
        if (c.eof == 1) {
            return H2C_EOF;
        }
        let got: i32 = h2c_fill(c);
        if (got == H2C_ERR) {
            return H2C_ERR;
        }
        tries += 1;
    }
    return H2C_ERR;
}

fn h2c_alpn_ok(c: &mut H2Conn) -> i32 {
    let ap: ptr<u8> = h2c_alpn_p(c);
    var i: i64 = 0;
    while (i < 16) {
        rt_setbyte(ap, i, 0);
        i += 1;
    }
    let n: i64 = https_alpn(&mut c.h, ap);
    if (n != 2) {
        return 0;
    }
    return rt_eqn(ap, "h2", 2);
}

fn h2c_start(c: &mut H2Conn) -> i32 {
    if (h2c_alpn_ok(c) != 1) {
        return H2C_ERR;
    }
    hxbuf_clear(&mut c.out);
    if (h2_put_preface(&mut c.out) != H2_OK) {
        return H2C_ERR;
    }
    if (h2_put_settings(&mut c.out, 4096, 0, H2C_WINDOW, H2C_MAX_FRAME) != H2_OK) {
        return H2C_ERR;
    }
    return h2c_flush(c);
}

fn h2c_init(c: &mut H2Conn, host: ptr<u8>, port: u16, to_ms: i32, max_body: i64) -> i32 {
    if (h2c_prepare(c, host, port, max_body) != H2C_OK) {
        h2c_free(c);
        return H2C_ERR;
    }
    let hp: ptr<u8> = h2c_hostp(c);
    if (https_open(&mut c.h, hp, port, to_ms) != HTTPS_OK) {
        h2c_free(c);
        return H2C_ERR;
    }
    c.live = 1;
    if (h2c_start(c) != H2C_OK) {
        h2c_shutdown(c);
        return H2C_ERR;
    }
    return H2C_OK;
}

fn h2c_init_anchor(c: &mut H2Conn, host: ptr<u8>, port: u16, to_ms: i32, max_body: i64, anchor: ptr<u8>, alen: i64) -> i32 {
    if (h2c_prepare(c, host, port, max_body) != H2C_OK) {
        h2c_free(c);
        return H2C_ERR;
    }
    let hp: ptr<u8> = h2c_hostp(c);
    if (https_open_anchor(&mut c.h, hp, port, to_ms, anchor, alen) != HTTPS_OK) {
        h2c_free(c);
        return H2C_ERR;
    }
    c.live = 1;
    if (h2c_start(c) != H2C_OK) {
        h2c_shutdown(c);
        return H2C_ERR;
    }
    return H2C_OK;
}

fn h2c_init_proxy(c: &mut H2Conn, proxy: ptr<u8>, pport: u16, host: ptr<u8>, port: u16, to_ms: i32, max_body: i64) -> i32 {
    if (h2c_prepare(c, host, port, max_body) != H2C_OK) {
        h2c_free(c);
        return H2C_ERR;
    }
    let hp: ptr<u8> = h2c_hostp(c);
    if (https_open_proxy(&mut c.h, proxy, pport, hp, port, to_ms) != HTTPS_OK) {
        h2c_free(c);
        return H2C_ERR;
    }
    c.live = 1;
    if (h2c_start(c) != H2C_OK) {
        h2c_shutdown(c);
        return H2C_ERR;
    }
    return H2C_OK;
}

fn h2c_init_proxy_anchor(c: &mut H2Conn, proxy: ptr<u8>, pport: u16, host: ptr<u8>, port: u16, to_ms: i32, max_body: i64, anchor: ptr<u8>, alen: i64) -> i32 {
    if (h2c_prepare(c, host, port, max_body) != H2C_OK) {
        h2c_free(c);
        return H2C_ERR;
    }
    let hp: ptr<u8> = h2c_hostp(c);
    if (https_open_proxy_anchor(&mut c.h, proxy, pport, hp, port, to_ms, anchor, alen) != HTTPS_OK) {
        h2c_free(c);
        return H2C_ERR;
    }
    c.live = 1;
    if (h2c_start(c) != H2C_OK) {
        h2c_shutdown(c);
        return H2C_ERR;
    }
    return H2C_OK;
}

fn h2c_close(c: &mut H2Conn) {
    if (c.live == 1) {
        https_close(&mut c.h);
        c.live = 0;
    }
    h2c_free(c);
    c.eof = 1;
}

fn h2c_shutdown(c: &mut H2Conn) {
    if (c.live == 1) {
        https_close(&mut c.h);
        c.live = 0;
    }
    c.eof = 1;
}

fn h2c_put_auth(c: &mut H2Conn) -> i32 {
    var ap: ptr<u8> = null;
    unsafe { ap = &mut c.auth[0] as ptr<u8>; }
    return hpack_put_kvn(&mut c.blk, ":authority", 10, ap, rt_len(ap));
}

fn h2c_build_hdrs(c: &mut H2Conn, method: ptr<u8>, path: ptr<u8>, ctype: ptr<u8>, blen: i64) -> i32 {
    hxbuf_clear(&mut c.blk);
    if (hpack_put_kvn(&mut c.blk, ":method", 7, method, rt_len(method)) != 0) {
        return H2C_ERR;
    }
    if (hpack_put_kv(&mut c.blk, ":scheme", "https") != 0) {
        return H2C_ERR;
    }
    if (hpack_put_kvn(&mut c.blk, ":path", 5, path, rt_len(path)) != 0) {
        return H2C_ERR;
    }
    if (h2c_put_auth(c) != 0) {
        return H2C_ERR;
    }
    if (hpack_put_kv(&mut c.blk, "user-agent", "rsharp-http2") != 0) {
        return H2C_ERR;
    }
    if (ctype != null) {
        if (hpack_put_kvn(&mut c.blk, "content-type", 12, ctype, rt_len(ctype)) != 0) {
            return H2C_ERR;
        }
    }
    if (blen > 0) {
        var nb: [u8; 24] = [0];
        var np: ptr<u8> = null;
        unsafe { np = &mut nb[0] as ptr<u8>; }
        let nd: i64 = h2c_itoa(blen, np, 24);
        if (nd <= 0) {
            return H2C_ERR;
        }
        if (hpack_put_kvn(&mut c.blk, "content-length", 14, np, nd) != 0) {
            return H2C_ERR;
        }
    }
    return H2C_OK;
}

fn h2c_decode(c: &mut H2Conn, trailer: i32) -> i32 {
    if (c.blk.len <= 0) {
        return H2C_OK;
    }
    let rc: i32 = hpack_decode(&mut c.dec, c.blk.p, c.blk.len);
    if (rc != HPACK_OK) {
        return H2C_ERR;
    }
    let n: i64 = hpack_count(&mut c.dec);
    var i: i64 = 0;
    var seen: i32 = 0;
    var status: i64 = 0;
    while (i < n) {
        let np: ptr<u8> = hpack_name(&mut c.dec, i);
        let nn: i64 = hpack_namelen(&mut c.dec, i);
        let vp: ptr<u8> = hpack_value(&mut c.dec, i);
        let vn: i64 = hpack_vallen(&mut c.dec, i);
        if (nn <= 0) {
            return H2C_ERR;
        }
        if (rt_byte(np, 0) == 58) {
            if (trailer == 1 || nn != 7 || rt_eqn(np, ":status", 7) != 1 || seen == 1) {
                return H2C_ERR;
            }
            if (vn != 3) {
                return H2C_ERR;
            }
            status = h2c_atoi(vp, vn);
            if (status < 100 || status > 599) {
                return H2C_ERR;
            }
            seen = 1;
        } else {
            var k: i64 = 0;
            while (k < nn) {
                let hc: u8 = rt_byte(np, k);
                if ((hc >= 65 && hc <= 90) || hc == 58) {
                    return H2C_ERR;
                }
                k += 1;
            }
        }
        if (hp_out_add(&mut c.hdrs, np, nn, vp, vn) != HPACK_OK) {
            return H2C_ERR;
        }
        i += 1;
    }
    if (trailer == 1) {
        return H2C_OK;
    }
    if (seen != 1) {
        return H2C_ERR;
    }
    c.status = status;
    return H2C_OK;
}

fn h2c_handle(c: &mut H2Conn, h: &mut H2Hdr) -> i32 {
    let flen: i64 = h.len;
    let ty: i64 = h.ty;
    let fl: i64 = h.flags;
    let stream: i64 = h.stream;

    if (flen > c.max_frame) {
        return H2C_ERR;
    }

    if (ty == H2_SETTINGS) {
        if ((fl & H2_F_ACK) == 0) {
            var sp: ptr<u8> = null;
            unsafe { sp = c.inb.p + 9; }
            var sout: [i64; 8] = [0, 0, 0, 0, 0, 0, 0, 0];
            if (h2_settings_read(sp, flen, &mut sout) != H2_OK) {
                return H2C_ERR;
            }
            if (sout[4] >= 16384 && sout[4] <= 16777215) {
                c.peer_frame = sout[4];
            }
            c.got_settings = 1;
            hxbuf_clear(&mut c.out);
            if (h2_put_settings_ack(&mut c.out) != H2_OK) {
                return H2C_ERR;
            }
            if (h2c_flush(c) != H2C_OK) {
                return H2C_ERR;
            }
        }
        return H2C_OK;
    }

    if (ty == H2_PING) {
        if ((fl & H2_F_ACK) == 0 && flen == 8) {
            var pp: ptr<u8> = null;
            unsafe { pp = c.inb.p + 9; }
            hxbuf_clear(&mut c.out);
            if (h2_put_ping_ack(&mut c.out, pp) != H2_OK) {
                return H2C_ERR;
            }
            if (h2c_flush(c) != H2C_OK) {
                return H2C_ERR;
            }
        }
        return H2C_OK;
    }

    if (ty == H2_GOAWAY) {
        return H2C_GOAWAY;
    }

    if (ty == H2_PUSH) {
        return H2C_ERR;
    }

    if (ty == H2_WU) {
        var wp: ptr<u8> = null;
        unsafe { wp = c.inb.p + 9; }
        let inc: i64 = h2_rd32(wp, 0) & 2147483647;
        if (stream == 0) {
            c.send_win += inc;
        } else if (stream == c.last_stream) {
            c.cur_win += inc;
        }
        return H2C_OK;
    }

    if (ty == H2_RST) {
        if (stream == c.last_stream) {
            c.eof = 1;
            return H2C_CLOSED;
        }
        return H2C_OK;
    }

    if (ty == H2_DATA) {
        if (stream != c.last_stream) {
            return H2C_OK;
        }
        if (c.end_hdr != 1) {
            return H2C_ERR;
        }
        var db: H2Body = zero(H2Body);
        if (h2_payload(c.inb.p, 9 + flen, h, &mut db) != H2_OK) {
            return H2C_ERR;
        }
        if (db.len > 0) {
            if (c.body.len + db.len > c.max_body) {
                return H2C_BIG;
            }
            var dp: ptr<u8> = null;
            unsafe { dp = c.inb.p + db.off; }
            if (hxbuf_put(&mut c.body, dp, db.len) != 0) {
                return H2C_BIG;
            }
            hxbuf_clear(&mut c.out);
            if (h2_put_window(&mut c.out, 0, db.len) != H2_OK) {
                return H2C_ERR;
            }
            if (h2_put_window(&mut c.out, stream, db.len) != H2_OK) {
                return H2C_ERR;
            }
            if (h2c_flush(c) != H2C_OK) {
                return H2C_ERR;
            }
        }
        if ((fl & H2_F_END_STREAM) != 0) {
            c.end_body = 1;
        }
        return H2C_OK;
    }

    if (ty == H2_HEADERS) {
        if (stream != c.last_stream) {
            return H2C_OK;
        }
        let trailer: i32 = c.end_hdr;
        c.trail = trailer;
        var hb: H2Body = zero(H2Body);
        if (h2_hblock(c.inb.p, 9 + flen, h, &mut hb) != H2_OK) {
            return H2C_ERR;
        }
        hxbuf_clear(&mut c.blk);
        if (hb.len > 0) {
            var hp: ptr<u8> = null;
            unsafe { hp = c.inb.p + hb.off; }
            if (hxbuf_put(&mut c.blk, hp, hb.len) != 0) {
                return H2C_BIG;
            }
        }
        if ((fl & H2_F_END_STREAM) != 0) {
            c.end_body = 1;
        }
        if ((fl & H2_F_END_HEADERS) != 0) {
            let dr: i32 = h2c_decode(c, trailer);
            if (dr != H2C_OK) {
                return dr;
            }
            if (trailer == 1) {
                return H2C_OK;
            }
            if (c.status >= 100 && c.status < 200) {
                if (c.end_body == 1) {
                    return H2C_ERR;
                }
                c.interim += 1;
                if (c.interim > 8) {
                    return H2C_ERR;
                }
                c.status = 0;
                c.end_hdr = 0;
                hxbuf_clear(&mut c.blk);
                hp_out_clear(&mut c.hdrs);
                return H2C_OK;
            }
            c.end_hdr = 1;
            return H2C_OK;
        }
        return H2C_OK;
    }

    if (ty == H2_CONT) {
        if (stream != c.last_stream) {
            return H2C_ERR;
        }
        if (c.end_hdr == 1 && c.trail != 1) {
            return H2C_ERR;
        }
        if (flen > 0) {
            var cp: ptr<u8> = null;
            unsafe { cp = c.inb.p + 9; }
            if (hxbuf_put(&mut c.blk, cp, flen) != 0) {
                return H2C_BIG;
            }
        }
        if ((fl & H2_F_END_HEADERS) != 0) {
            if (c.trail != 1) {
                c.end_hdr = 1;
            }
            return h2c_decode(c, c.trail);
        }
        return H2C_OK;
    }

    return H2C_OK;
}

fn h2c_frame(c: &mut H2Conn) -> i32 {
    var h: H2Hdr = zero(H2Hdr);
    let rc: i32 = h2c_next(c, &mut h);
    if (rc != H2C_OK) {
        return rc;
    }
    let total: i64 = 9 + h.len;
    let hr: i32 = h2c_handle(c, &mut h);
    if (hr != H2C_OK) {
        return hr;
    }
    return h2c_drop(c, total);
}

fn h2c_pump(c: &mut H2Conn) -> i32 {
    var guard: i64 = 0;
    while (guard < 200000) {
        if (c.end_hdr == 1 && c.end_body == 1) {
            return H2C_OK;
        }
        let rc: i32 = h2c_frame(c);
        if (rc != H2C_OK) {
            return rc;
        }
        guard += 1;
    }
    return H2C_ERR;
}

fn h2c_send_body(c: &mut H2Conn, stream: i64, body: ptr<u8>, blen: i64) -> i32 {
    var off: i64 = 0;
    var guard: i64 = 0;
    while (off < blen) {
        var room: i64 = c.send_win;
        if (c.cur_win < room) {
            room = c.cur_win;
        }
        if (c.peer_frame < room) {
            room = c.peer_frame;
        }
        if (room <= 0) {
            let rc: i32 = h2c_frame(c);
            if (rc != H2C_OK) {
                return rc;
            }
            guard += 1;
            if (guard > 8192) {
                return H2C_ERR;
            }
            continue;
        }
        var take: i64 = blen - off;
        if (take > room) {
            take = room;
        }
        var ep: ptr<u8> = null;
        unsafe { ep = body + off; }
        var last: i32 = 0;
        if (off + take >= blen) {
            last = 1;
        }
        if (h2_put_data(&mut c.out, stream, ep, take, last) != H2_OK) {
            return H2C_ERR;
        }
        if (h2c_flush(c) != H2C_OK) {
            return H2C_ERR;
        }
        c.send_win -= take;
        c.cur_win -= take;
        off += take;
    }
    return H2C_OK;
}

fn h2c_send_req(c: &mut H2Conn, method: ptr<u8>, path: ptr<u8>, ctype: ptr<u8>, body: ptr<u8>, blen: i64) -> i32 {
    if (c.live != 1) {
        return H2C_ERR;
    }
    if (blen < 0 || (blen > 0 && body == null)) {
        return H2C_ERR;
    }
    if (h2c_build_hdrs(c, method, path, ctype, blen) != H2C_OK) {
        return H2C_ERR;
    }
    let stream: i64 = c.next_stream;
    if (stream > 2147483645) {
        return H2C_ERR;
    }
    c.next_stream += 2;
    var es: i32 = 0;
    if (blen == 0) {
        es = 1;
    }
    hxbuf_clear(&mut c.out);
    if (h2_put_headers_split(&mut c.out, stream, c.blk.p, c.blk.len, es, c.peer_frame) != H2_OK) {
        return H2C_ERR;
    }
    if (h2c_flush(c) != H2C_OK) {
        return H2C_ERR;
    }
    c.last_stream = stream;
    c.cur_win = H2C_WINDOW;
    if (blen > 0) {
        return h2c_send_body(c, stream, body, blen);
    }
    return H2C_OK;
}

fn h2c_send_reqx(c: &mut H2Conn, method: ptr<u8>, path: ptr<u8>, ctype: ptr<u8>, extra: &mut HxBuf, body: ptr<u8>, blen: i64) -> i32 {
    if (c.live != 1) {
        return H2C_ERR;
    }
    if (blen < 0 || (blen > 0 && body == null)) {
        return H2C_ERR;
    }
    if (h2c_build_hdrs(c, method, path, ctype, blen) != H2C_OK) {
        return H2C_ERR;
    }
    if (extra.len > 0) {
        if (hxbuf_put(&mut c.blk, extra.p, extra.len) != 0) {
            return H2C_ERR;
        }
    }
    let stream: i64 = c.next_stream;
    if (stream > 2147483645) {
        return H2C_ERR;
    }
    c.next_stream += 2;
    var es: i32 = 0;
    if (blen == 0) {
        es = 1;
    }
    hxbuf_clear(&mut c.out);
    if (h2_put_headers_split(&mut c.out, stream, c.blk.p, c.blk.len, es, c.peer_frame) != H2_OK) {
        return H2C_ERR;
    }
    if (h2c_flush(c) != H2C_OK) {
        return H2C_ERR;
    }
    c.last_stream = stream;
    c.cur_win = H2C_WINDOW;
    if (blen > 0) {
        return h2c_send_body(c, stream, body, blen);
    }
    return H2C_OK;
}

fn h2c_read(c: &mut H2Conn) -> i32 {
    if (c.live != 1) {
        return H2C_EOF;
    }
    c.end_hdr = 0;
    c.end_body = 0;
    c.status = 0;
    c.interim = 0;
    c.trail = 0;
    hxbuf_clear(&mut c.body);
    hp_out_clear(&mut c.hdrs);
    return h2c_pump(c);
}

fn h2c_get(c: &mut H2Conn, target: ptr<u8>) -> i32 {
    if (h2c_send_req(c, "GET", target, null, null, 0) != H2C_OK) {
        return H2C_ERR;
    }
    return h2c_read(c);
}

fn h2c_post(c: &mut H2Conn, target: ptr<u8>, ctype: ptr<u8>, body: ptr<u8>, blen: i64) -> i32 {
    if (h2c_send_req(c, "POST", target, ctype, body, blen) != H2C_OK) {
        return H2C_ERR;
    }
    return h2c_read(c);
}

fn h2c_status(c: &mut H2Conn) -> i64 {
    return c.status;
}

fn h2c_body(c: &mut H2Conn) -> ptr<u8> {
    return c.body.p;
}

fn h2c_body_len(c: &mut H2Conn) -> i64 {
    return c.body.len;
}

fn h2c_body_str(c: &mut H2Conn) -> ptr<u8> {
    if (c.body.p == null) {
        return null;
    }
    if (hxbuf_terminate(&mut c.body) != 0) {
        return null;
    }
    return c.body.p;
}

fn h2c_hdr_count(c: &mut H2Conn) -> i64 {
    return c.hdrs.n;
}

fn h2c_hdr(c: &mut H2Conn, name: ptr<u8>, nlen: i64) -> H2Span {
    var s: H2Span = zero(H2Span);
    let i: i64 = hp_out_find(&mut c.hdrs, name, nlen);
    if (i < 0) {
        return s;
    }
    s.off = c.hdrs.voff[i];
    s.len = c.hdrs.vlen[i];
    return s;
}

fn h2c_hdr_str(c: &mut H2Conn, name: ptr<u8>, nlen: i64, out: ptr<u8>, cap: i64) -> i64 {
    let s: H2Span = h2c_hdr(c, name, nlen);
    if (s.len < 0 || s.len >= cap) {
        return -1;
    }
    if (s.len > 0) {
        var sp: ptr<u8> = null;
        unsafe { sp = c.hdrs.buf.p + s.off; }
        rt_copy(out, sp, s.len);
    }
    rt_setbyte(out, s.len, 0);
    return s.len;
}

fn h2c_hdr_at_name(c: &mut H2Conn, i: i64) -> ptr<u8> {
    return hp_out_name(&mut c.hdrs, i);
}

fn h2c_hdr_at_nlen(c: &mut H2Conn, i: i64) -> i64 {
    return hp_out_nlen(&mut c.hdrs, i);
}

fn h2c_hdr_at_value(c: &mut H2Conn, i: i64) -> ptr<u8> {
    return hp_out_value(&mut c.hdrs, i);
}

fn h2c_hdr_at_vlen(c: &mut H2Conn, i: i64) -> i64 {
    return hp_out_vlen(&mut c.hdrs, i);
}

fn h2c_alpn(c: &mut H2Conn) -> ptr<u8> {
    return h2c_alpn_p(c);
}
