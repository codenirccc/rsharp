include "rt.rsx";

const H2_OK: i32 = 0;
const H2_NEED: i32 = -1;
const H2_BAD: i32 = -2;

const H2_DATA: i64 = 0;
const H2_HEADERS: i64 = 1;
const H2_PRIORITY: i64 = 2;
const H2_RST: i64 = 3;
const H2_SETTINGS: i64 = 4;
const H2_PUSH: i64 = 5;
const H2_PING: i64 = 6;
const H2_GOAWAY: i64 = 7;
const H2_WU: i64 = 8;
const H2_CONT: i64 = 9;

const H2_F_ACK: i64 = 1;
const H2_F_END_STREAM: i64 = 1;
const H2_F_END_HEADERS: i64 = 4;
const H2_F_PADDED: i64 = 8;
const H2_F_PRIORITY: i64 = 32;

const H2_PREFACE: i64 = 24;

const H2_S_HEADER_TABLE: i64 = 1;
const H2_S_ENABLE_PUSH: i64 = 2;
const H2_S_MAX_STREAMS: i64 = 3;
const H2_S_INITIAL_WINDOW: i64 = 4;
const H2_S_MAX_FRAME: i64 = 5;
const H2_S_MAX_LIST: i64 = 6;

const H2_E_NO_ERROR: i64 = 0;
const H2_E_PROTOCOL: i64 = 1;
const H2_E_INTERNAL: i64 = 2;
const H2_E_FLOW: i64 = 3;
const H2_E_STREAM_CLOSED: i64 = 5;
const H2_E_FRAME_SIZE: i64 = 6;
const H2_E_REFUSED: i64 = 7;
const H2_E_CANCEL: i64 = 8;
const H2_E_COMPRESSION: i64 = 9;

const H2_MAX_FRAME_DEFAULT: i64 = 16384;
const H2_WINDOW_DEFAULT: i64 = 65535;
const H2_WINDOW_MAX: i64 = 2147483647;

struct H2Hdr {
    len: i64,
    ty: i64,
    flags: i64,
    stream: i64
}

struct H2Body {
    off: i64,
    len: i64
}

fn h2_rd24(p: ptr<u8>, off: i64) -> i64 {
    var a: u8 = 0;
    var b: u8 = 0;
    var c: u8 = 0;
    unsafe {
        a = p[off];
        b = p[off + 1];
        c = p[off + 2];
    }
    let hi: i64 = a as i64;
    let mid: i64 = b as i64;
    let lo: i64 = c as i64;
    return (hi << 16) | (mid << 8) | lo;
}

fn h2_rd32(p: ptr<u8>, off: i64) -> i64 {
    let hi: i64 = h2_rd24(p, off) << 8;
    var d: u8 = 0;
    unsafe { d = p[off + 3]; }
    return hi | (d as i64);
}

fn h2_hdr_parse(p: ptr<u8>, n: i64, h: &mut H2Hdr) -> i32 {
    if (n < 9) {
        return H2_NEED;
    }
    h.len = h2_rd24(p, 0);
    var ty: u8 = 0;
    var fl: u8 = 0;
    unsafe {
        ty = p[3];
        fl = p[4];
    }
    h.ty = ty as i64;
    h.flags = fl as i64;
    h.stream = h2_rd32(p, 5) & 2147483647;
    if (h.len < 0 || h.len > 16777215) {
        return H2_BAD;
    }
    if (n < 9 + h.len) {
        return H2_NEED;
    }
    return H2_OK;
}

fn h2_payload(p: ptr<u8>, n: i64, h: &mut H2Hdr, body: &mut H2Body) -> i32 {
    body.off = 9;
    body.len = h.len;
    if (n < 9 + h.len) {
        return H2_BAD;
    }
    if ((h.flags & H2_F_PADDED) != 0) {
        if (h.len < 1) {
            return H2_BAD;
        }
        var pad: u8 = 0;
        unsafe { pad = p[9]; }
        let pl: i64 = pad as i64;
        if (pl + 1 > h.len) {
            return H2_BAD;
        }
        body.off = 10;
        body.len = h.len - 1 - pl;
    }
    return H2_OK;
}

fn h2_hblock(p: ptr<u8>, n: i64, h: &mut H2Hdr, body: &mut H2Body) -> i32 {
    if (h2_payload(p, n, h, body) != H2_OK) {
        return H2_BAD;
    }
    if ((h.flags & H2_F_PRIORITY) != 0) {
        if (body.len < 5) {
            return H2_BAD;
        }
        body.off += 5;
        body.len -= 5;
    }
    return H2_OK;
}

fn h2_put_hdr(b: &mut HxBuf, len: i64, ty: i64, flags: i64, stream: i64) -> i32 {
    if (len < 0 || len > 16777215) {
        return H2_BAD;
    }
    if (hxbuf_putc(b, (((len >> 16) & 255) as u8)) != 0) {
        return H2_BAD;
    }
    if (hxbuf_putc(b, (((len >> 8) & 255) as u8)) != 0) {
        return H2_BAD;
    }
    if (hxbuf_putc(b, ((len & 255) as u8)) != 0) {
        return H2_BAD;
    }
    if (hxbuf_putc(b, (ty as u8)) != 0) {
        return H2_BAD;
    }
    if (hxbuf_putc(b, (flags as u8)) != 0) {
        return H2_BAD;
    }
    let s: i64 = stream & 2147483647;
    if (hxbuf_putc(b, (((s >> 24) & 127) as u8)) != 0) {
        return H2_BAD;
    }
    if (hxbuf_putc(b, (((s >> 16) & 255) as u8)) != 0) {
        return H2_BAD;
    }
    if (hxbuf_putc(b, (((s >> 8) & 255) as u8)) != 0) {
        return H2_BAD;
    }
    return hxbuf_putc(b, ((s & 255) as u8));
}

fn h2_put_frame(b: &mut HxBuf, ty: i64, flags: i64, stream: i64, p: ptr<u8>, len: i64) -> i32 {
    if (h2_put_hdr(b, len, ty, flags, stream) != H2_OK) {
        return H2_BAD;
    }
    if (len <= 0) {
        return H2_OK;
    }
    return hxbuf_put(b, p, len);
}

fn h2_put_preface(b: &mut HxBuf) -> i32 {
    return hxbuf_puts(b, "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n");
}

fn h2_put_u16(b: &mut HxBuf, v: i64) -> i32 {
    if (hxbuf_putc(b, (((v >> 8) & 255) as u8)) != 0) {
        return H2_BAD;
    }
    return hxbuf_putc(b, ((v & 255) as u8));
}

fn h2_put_u32(b: &mut HxBuf, v: i64) -> i32 {
    if (hxbuf_putc(b, (((v >> 24) & 255) as u8)) != 0) {
        return H2_BAD;
    }
    if (hxbuf_putc(b, (((v >> 16) & 255) as u8)) != 0) {
        return H2_BAD;
    }
    if (hxbuf_putc(b, (((v >> 8) & 255) as u8)) != 0) {
        return H2_BAD;
    }
    return hxbuf_putc(b, ((v & 255) as u8));
}

fn h2_put_settings(b: &mut HxBuf, table: i64, push: i64, initwin: i64, maxframe: i64) -> i32 {
    var pl: HxBuf = hxbuf_new(64);
    if (pl.p == null) {
        return H2_BAD;
    }
    if (h2_put_u16(&mut pl, H2_S_ENABLE_PUSH) != H2_OK) {
        hxbuf_free(&mut pl);
        return H2_BAD;
    }
    if (h2_put_u32(&mut pl, push) != H2_OK) {
        hxbuf_free(&mut pl);
        return H2_BAD;
    }
    if (h2_put_u16(&mut pl, H2_S_INITIAL_WINDOW) != H2_OK) {
        hxbuf_free(&mut pl);
        return H2_BAD;
    }
    if (h2_put_u32(&mut pl, initwin) != H2_OK) {
        hxbuf_free(&mut pl);
        return H2_BAD;
    }
    if (h2_put_u16(&mut pl, H2_S_MAX_FRAME) != H2_OK) {
        hxbuf_free(&mut pl);
        return H2_BAD;
    }
    if (h2_put_u32(&mut pl, maxframe) != H2_OK) {
        hxbuf_free(&mut pl);
        return H2_BAD;
    }
    if (h2_put_u16(&mut pl, H2_S_HEADER_TABLE) != H2_OK) {
        hxbuf_free(&mut pl);
        return H2_BAD;
    }
    if (h2_put_u32(&mut pl, table) != H2_OK) {
        hxbuf_free(&mut pl);
        return H2_BAD;
    }
    let rc: i32 = h2_put_frame(b, H2_SETTINGS, 0, 0, pl.p, pl.len);
    hxbuf_free(&mut pl);
    return rc;
}

fn h2_put_settings_ack(b: &mut HxBuf) -> i32 {
    return h2_put_frame(b, H2_SETTINGS, H2_F_ACK, 0, null, 0);
}

fn h2_put_window(b: &mut HxBuf, stream: i64, inc: i64) -> i32 {
    if (inc <= 0 || inc > H2_WINDOW_MAX) {
        return H2_BAD;
    }
    var pl: HxBuf = hxbuf_new(16);
    if (pl.p == null) {
        return H2_BAD;
    }
    if (h2_put_u32(&mut pl, inc) != H2_OK) {
        hxbuf_free(&mut pl);
        return H2_BAD;
    }
    let rc: i32 = h2_put_frame(b, H2_WU, 0, stream, pl.p, pl.len);
    hxbuf_free(&mut pl);
    return rc;
}

fn h2_put_rst(b: &mut HxBuf, stream: i64, code: i64) -> i32 {
    var pl: HxBuf = hxbuf_new(16);
    if (pl.p == null) {
        return H2_BAD;
    }
    if (h2_put_u32(&mut pl, code) != H2_OK) {
        hxbuf_free(&mut pl);
        return H2_BAD;
    }
    let rc: i32 = h2_put_frame(b, H2_RST, 0, stream, pl.p, pl.len);
    hxbuf_free(&mut pl);
    return rc;
}

fn h2_put_goaway(b: &mut HxBuf, last_stream: i64, code: i64) -> i32 {
    var pl: HxBuf = hxbuf_new(16);
    if (pl.p == null) {
        return H2_BAD;
    }
    if (h2_put_u32(&mut pl, last_stream & 2147483647) != H2_OK) {
        hxbuf_free(&mut pl);
        return H2_BAD;
    }
    if (h2_put_u32(&mut pl, code) != H2_OK) {
        hxbuf_free(&mut pl);
        return H2_BAD;
    }
    let rc: i32 = h2_put_frame(b, H2_GOAWAY, 0, 0, pl.p, pl.len);
    hxbuf_free(&mut pl);
    return rc;
}

fn h2_put_ping_ack(b: &mut HxBuf, p: ptr<u8>) -> i32 {
    return h2_put_frame(b, H2_PING, H2_F_ACK, 0, p, 8);
}

fn h2_put_data(b: &mut HxBuf, stream: i64, p: ptr<u8>, len: i64, end_stream: i32) -> i32 {
    var fl: i64 = 0;
    if (end_stream == 1) {
        fl = H2_F_END_STREAM;
    }
    return h2_put_frame(b, H2_DATA, fl, stream, p, len);
}

fn h2_put_headers(b: &mut HxBuf, stream: i64, p: ptr<u8>, len: i64, end_stream: i32) -> i32 {
    var fl: i64 = H2_F_END_HEADERS;
    if (end_stream == 1) {
        fl = fl | H2_F_END_STREAM;
    }
    return h2_put_frame(b, H2_HEADERS, fl, stream, p, len);
}

fn h2_put_continuation(b: &mut HxBuf, stream: i64, p: ptr<u8>, len: i64, end_headers: i32) -> i32 {
    var fl: i64 = 0;
    if (end_headers == 1) {
        fl = H2_F_END_HEADERS;
    }
    return h2_put_frame(b, H2_CONT, fl, stream, p, len);
}

fn h2_put_headers_split(b: &mut HxBuf, stream: i64, p: ptr<u8>, len: i64, end_stream: i32, maxframe: i64) -> i32 {
    if (maxframe < 16) {
        return H2_BAD;
    }
    if (len <= maxframe) {
        return h2_put_headers(b, stream, p, len, end_stream);
    }
    var first: i32 = 0;
    let fl: i64 = H2_F_END_STREAM;
    if (end_stream == 1) {
        first = h2_put_frame(b, H2_HEADERS, fl, stream, p, maxframe);
    } else {
        first = h2_put_frame(b, H2_HEADERS, 0, stream, p, maxframe);
    }
    if (first != H2_OK) {
        return H2_BAD;
    }
    var off: i64 = maxframe;
    while (off < len) {
        var take: i64 = len - off;
        if (take > maxframe) {
            take = maxframe;
        }
        var endh: i32 = 0;
        if (off + take >= len) {
            endh = 1;
        }
        var cp: ptr<u8> = null;
        unsafe { cp = p + off; }
        if (h2_put_continuation(b, stream, cp, take, endh) != H2_OK) {
            return H2_BAD;
        }
        off += take;
    }
    return H2_OK;
}

fn h2_settings_read(p: ptr<u8>, n: i64, out: &mut [i64; 8]) -> i32 {
    var i: i64 = 0;
    while (i < 8) {
        out[i] = -1;
        i += 1;
    }
    if (n < 0 || (n % 6) != 0) {
        return H2_BAD;
    }
    var off: i64 = 0;
    while (off + 6 <= n) {
        var a: u8 = 0;
        var b: u8 = 0;
        unsafe {
            a = p[off];
            b = p[off + 1];
        }
        let id: i64 = ((a as i64) << 8) | (b as i64);
        let v: i64 = h2_rd32(p, off + 2) & 2147483647;
        if (id >= 1 && id <= 6) {
            out[id - 1] = v;
        }
        off += 6;
    }
    return H2_OK;
}

fn h2_is_stream_frame(ty: i64) -> i32 {
    if (ty == H2_DATA || ty == H2_HEADERS || ty == H2_PRIORITY || ty == H2_RST) {
        return 1;
    }
    if (ty == H2_PUSH || ty == H2_CONT) {
        return 1;
    }
    return 0;
}
