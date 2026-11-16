include "quic_crypto.rsx";

const QF_OK: i32 = 0;
const QF_END: i32 = 1;
const QF_ERR: i32 = -1;

const QF_PADDING: i64 = 0x00;
const QF_PING: i64 = 0x01;
const QF_ACK: i64 = 0x02;
const QF_ACK_ECN: i64 = 0x03;
const QF_RESET_STREAM: i64 = 0x04;
const QF_STOP_SENDING: i64 = 0x05;
const QF_CRYPTO: i64 = 0x06;
const QF_NEW_TOKEN: i64 = 0x07;
const QF_STREAM_BASE: i64 = 0x08;
const QF_STREAM_END: i64 = 0x0f;
const QF_MAX_DATA: i64 = 0x10;
const QF_MAX_STREAM_DATA: i64 = 0x11;
const QF_MAX_STREAMS_BIDI: i64 = 0x12;
const QF_MAX_STREAMS_UNI: i64 = 0x13;
const QF_DATA_BLOCKED: i64 = 0x14;
const QF_STREAM_DATA_BLOCKED: i64 = 0x15;
const QF_STREAMS_BLOCKED_BIDI: i64 = 0x16;
const QF_STREAMS_BLOCKED_UNI: i64 = 0x17;
const QF_NEW_CONNECTION_ID: i64 = 0x18;
const QF_RETIRE_CONNECTION_ID: i64 = 0x19;
const QF_PATH_CHALLENGE: i64 = 0x1a;
const QF_PATH_RESPONSE: i64 = 0x1b;
const QF_CONNECTION_CLOSE: i64 = 0x1c;
const QF_CONNECTION_CLOSE_APP: i64 = 0x1d;
const QF_HANDSHAKE_DONE: i64 = 0x1e;

struct QF {
    p: ptr<u8>,
    n: i64,
    i: i64,
    ty: i64,
    a: i64,
    b: i64,
    c: i64,
    d: i64,
    data: i64,
    dlen: i64,
    fin: i32,
    err: i32,
    pad: i32
}

fn qf_init(r: &mut QF, p: ptr<u8>, n: i64) {
    r.p = p;
    r.n = n;
    r.i = 0;
    r.ty = -1;
    r.a = 0;
    r.b = 0;
    r.c = 0;
    r.d = 0;
    r.data = 0;
    r.dlen = 0;
    r.fin = 0;
    r.err = 0;
    r.pad = 0;
}

fn qf_need(r: &mut QF, upto: i64) -> i32 {
    if (upto > r.n) {
        return QF_ERR;
    }
    return QF_OK;
}

fn qf_next(r: &mut QF) -> i32 {
    r.ty = -1;
    r.a = 0;
    r.b = 0;
    r.c = 0;
    r.d = 0;
    r.data = 0;
    r.dlen = 0;
    r.fin = 0;
    r.pad = 0;
    if (r.i >= r.n) {
        return QF_END;
    }
    let at: i64 = r.i;
    let ty: i64 = quic_varint_get(r.p, at);
    let tl: i64 = quic_varint_hdr_len(rt_byte(r.p, at));
    var off: i64 = at + tl;

    if (ty == QF_PADDING) {
        var k: i64 = at;
        while (k < r.n && rt_byte(r.p, k) == 0) {
            k += 1;
        }
        r.pad = 1;
        r.ty = QF_PADDING;
        r.dlen = k - at;
        r.i = k;
        return QF_OK;
    }

    r.ty = ty;

    if (ty == QF_PING || ty == QF_HANDSHAKE_DONE) {
        r.i = off;
        return QF_OK;
    }

    if (ty == QF_ACK || ty == QF_ACK_ECN) {
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.a = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.b = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.c = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.d = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        var k: i64 = 0;
        while (k < r.c) {
            if (qf_need(r, off + 1) != QF_OK) {
                r.err = 1;
                return QF_ERR;
            }
            off += quic_varint_hdr_len(rt_byte(r.p, off));
            if (qf_need(r, off + 1) != QF_OK) {
                r.err = 1;
                return QF_ERR;
            }
            off += quic_varint_hdr_len(rt_byte(r.p, off));
            k += 1;
        }
        if (ty == QF_ACK_ECN) {
            var e: i64 = 0;
            while (e < 3) {
                if (qf_need(r, off + 1) != QF_OK) {
                    r.err = 1;
                    return QF_ERR;
                }
                off += quic_varint_hdr_len(rt_byte(r.p, off));
                e += 1;
            }
        }
        r.i = off;
        return QF_OK;
    }

    if (ty == QF_RESET_STREAM) {
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.a = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.b = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.c = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        r.i = off;
        return QF_OK;
    }

    if (ty == QF_STOP_SENDING) {
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.a = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.b = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        r.i = off;
        return QF_OK;
    }

    if (ty == QF_CRYPTO || ty == QF_NEW_TOKEN) {
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        if (ty == QF_CRYPTO) {
            r.a = quic_varint_get(r.p, off);
            off += quic_varint_hdr_len(rt_byte(r.p, off));
        }
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        let dl: i64 = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (qf_need(r, off + dl) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.data = off;
        r.dlen = dl;
        r.i = off + dl;
        return QF_OK;
    }

    if (ty >= QF_STREAM_BASE && ty <= QF_STREAM_END) {
        let has_off: i64 = ty & 0x04;
        let has_len: i64 = ty & 0x02;
        let has_fin: i64 = ty & 0x01;
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.a = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (has_off != 0) {
            if (qf_need(r, off + 1) != QF_OK) {
                r.err = 1;
                return QF_ERR;
            }
            r.b = quic_varint_get(r.p, off);
            off += quic_varint_hdr_len(rt_byte(r.p, off));
        }
        var dl: i64 = r.n - off;
        if (has_len != 0) {
            if (qf_need(r, off + 1) != QF_OK) {
                r.err = 1;
                return QF_ERR;
            }
            dl = quic_varint_get(r.p, off);
            off += quic_varint_hdr_len(rt_byte(r.p, off));
        }
        if (qf_need(r, off + dl) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        if (has_fin != 0) {
            r.fin = 1;
        }
        r.data = off;
        r.dlen = dl;
        r.i = off + dl;
        return QF_OK;
    }

    if (ty == QF_MAX_DATA || ty == QF_DATA_BLOCKED) {
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.a = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        r.i = off;
        return QF_OK;
    }

    if (ty == QF_MAX_STREAM_DATA || ty == QF_STREAM_DATA_BLOCKED) {
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.a = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.b = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        r.i = off;
        return QF_OK;
    }

    if (ty == QF_MAX_STREAMS_BIDI || ty == QF_MAX_STREAMS_UNI || ty == QF_STREAMS_BLOCKED_BIDI || ty == QF_STREAMS_BLOCKED_UNI) {
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.a = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        r.i = off;
        return QF_OK;
    }

    if (ty == QF_NEW_CONNECTION_ID) {
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.a = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.b = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        let cl: i64 = rt_byte(r.p, off) as i64;
        off += 1;
        if (cl < 1 || cl > 20) {
            r.err = 1;
            return QF_ERR;
        }
        if (qf_need(r, off + cl + 16) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.c = cl;
        r.data = off;
        r.d = off + cl;
        r.i = off + cl + 16;
        return QF_OK;
    }

    if (ty == QF_RETIRE_CONNECTION_ID) {
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.a = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        r.i = off;
        return QF_OK;
    }

    if (ty == QF_PATH_CHALLENGE || ty == QF_PATH_RESPONSE) {
        if (qf_need(r, off + 8) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.data = off;
        r.dlen = 8;
        r.i = off + 8;
        return QF_OK;
    }

    if (ty == QF_CONNECTION_CLOSE || ty == QF_CONNECTION_CLOSE_APP) {
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.a = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (ty == QF_CONNECTION_CLOSE) {
            if (qf_need(r, off + 1) != QF_OK) {
                r.err = 1;
                return QF_ERR;
            }
            r.b = quic_varint_get(r.p, off);
            off += quic_varint_hdr_len(rt_byte(r.p, off));
        }
        if (qf_need(r, off + 1) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        let rl: i64 = quic_varint_get(r.p, off);
        off += quic_varint_hdr_len(rt_byte(r.p, off));
        if (qf_need(r, off + rl) != QF_OK) {
            r.err = 1;
            return QF_ERR;
        }
        r.data = off;
        r.dlen = rl;
        r.i = off + rl;
        return QF_OK;
    }

    r.err = 1;
    return QF_ERR;
}

struct QW {
    b: HxBuf
}

fn qw_init(w: &mut QW, cap: i64) -> i32 {
    w.b = hxbuf_new(cap);
    if (w.b.p == null) {
        return QF_ERR;
    }
    return QF_OK;
}

fn qw_free(w: &mut QW) {
    hxbuf_free(&mut w.b);
}

fn qw_varint(w: &mut QW, v: i64) -> i32 {
    if (hx_put_varint(&mut w.b, v) != 0) {
        return QF_ERR;
    }
    return QF_OK;
}

fn qw_padding(w: &mut QW, n: i64) -> i32 {
    var i: i64 = 0;
    while (i < n) {
        if (hxbuf_putc(&mut w.b, 0) != 0) {
            return QF_ERR;
        }
        i += 1;
    }
    return QF_OK;
}

fn qw_ping(w: &mut QW) -> i32 {
    return hxbuf_putc(&mut w.b, QF_PING as u8);
}

fn qw_handshake_done(w: &mut QW) -> i32 {
    return hxbuf_putc(&mut w.b, QF_HANDSHAKE_DONE as u8);
}

fn qw_ack(w: &mut QW, largest: i64, delay: i64, first_range: i64) -> i32 {
    if (hxbuf_putc(&mut w.b, QF_ACK as u8) != 0) {
        return QF_ERR;
    }
    if (qw_varint(w, largest) != QF_OK) {
        return QF_ERR;
    }
    if (qw_varint(w, delay) != QF_OK) {
        return QF_ERR;
    }
    if (qw_varint(w, 0) != QF_OK) {
        return QF_ERR;
    }
    return qw_varint(w, first_range);
}

fn qw_crypto(w: &mut QW, off: i64, p: ptr<u8>, n: i64) -> i32 {
    if (hxbuf_putc(&mut w.b, QF_CRYPTO as u8) != 0) {
        return QF_ERR;
    }
    if (qw_varint(w, off) != QF_OK) {
        return QF_ERR;
    }
    if (qw_varint(w, n) != QF_OK) {
        return QF_ERR;
    }
    if (n > 0 && hxbuf_put(&mut w.b, p, n) != 0) {
        return QF_ERR;
    }
    return QF_OK;
}

fn qw_stream(w: &mut QW, id: i64, off: i64, p: ptr<u8>, n: i64, fin: i32) -> i32 {
    var ty: i64 = QF_STREAM_BASE;
    if (off > 0) {
        ty += 0x04;
    }
    ty += 0x02;
    if (fin == 1) {
        ty += 0x01;
    }
    if (hxbuf_putc(&mut w.b, ty as u8) != 0) {
        return QF_ERR;
    }
    if (qw_varint(w, id) != QF_OK) {
        return QF_ERR;
    }
    if (off > 0) {
        if (qw_varint(w, off) != QF_OK) {
            return QF_ERR;
        }
    }
    if (qw_varint(w, n) != QF_OK) {
        return QF_ERR;
    }
    if (n > 0 && hxbuf_put(&mut w.b, p, n) != 0) {
        return QF_ERR;
    }
    return QF_OK;
}

fn qw_max_data(w: &mut QW, v: i64) -> i32 {
    if (hxbuf_putc(&mut w.b, QF_MAX_DATA as u8) != 0) {
        return QF_ERR;
    }
    return qw_varint(w, v);
}

fn qw_max_stream_data(w: &mut QW, id: i64, v: i64) -> i32 {
    if (hxbuf_putc(&mut w.b, QF_MAX_STREAM_DATA as u8) != 0) {
        return QF_ERR;
    }
    if (qw_varint(w, id) != QF_OK) {
        return QF_ERR;
    }
    return qw_varint(w, v);
}

fn qw_max_streams(w: &mut QW, uni: i32, v: i64) -> i32 {
    var ty: i64 = QF_MAX_STREAMS_BIDI;
    if (uni == 1) {
        ty = QF_MAX_STREAMS_UNI;
    }
    if (hxbuf_putc(&mut w.b, ty as u8) != 0) {
        return QF_ERR;
    }
    return qw_varint(w, v);
}

fn qw_reset_stream(w: &mut QW, id: i64, code: i64, final_size: i64) -> i32 {
    if (hxbuf_putc(&mut w.b, QF_RESET_STREAM as u8) != 0) {
        return QF_ERR;
    }
    if (qw_varint(w, id) != QF_OK) {
        return QF_ERR;
    }
    if (qw_varint(w, code) != QF_OK) {
        return QF_ERR;
    }
    return qw_varint(w, final_size);
}

fn qw_stop_sending(w: &mut QW, id: i64, code: i64) -> i32 {
    if (hxbuf_putc(&mut w.b, QF_STOP_SENDING as u8) != 0) {
        return QF_ERR;
    }
    if (qw_varint(w, id) != QF_OK) {
        return QF_ERR;
    }
    return qw_varint(w, code);
}

fn qw_new_cid(w: &mut QW, seq: i64, retire: i64, cid: ptr<u8>, clen: i64, token: ptr<u8>) -> i32 {
    if (clen < 1 || clen > 20) {
        return QF_ERR;
    }
    if (hxbuf_putc(&mut w.b, QF_NEW_CONNECTION_ID as u8) != 0) {
        return QF_ERR;
    }
    if (qw_varint(w, seq) != QF_OK) {
        return QF_ERR;
    }
    if (qw_varint(w, retire) != QF_OK) {
        return QF_ERR;
    }
    if (hxbuf_putc(&mut w.b, clen as u8) != 0) {
        return QF_ERR;
    }
    if (hxbuf_put(&mut w.b, cid, clen) != 0) {
        return QF_ERR;
    }
    if (hxbuf_put(&mut w.b, token, 16) != 0) {
        return QF_ERR;
    }
    return QF_OK;
}

fn qw_path_response(w: &mut QW, p: ptr<u8>) -> i32 {
    if (hxbuf_putc(&mut w.b, QF_PATH_RESPONSE as u8) != 0) {
        return QF_ERR;
    }
    if (hxbuf_put(&mut w.b, p, 8) != 0) {
        return QF_ERR;
    }
    return QF_OK;
}

fn qw_retire_cid(w: &mut QW, seq: i64) -> i32 {
    if (hxbuf_putc(&mut w.b, QF_RETIRE_CONNECTION_ID as u8) != 0) {
        return QF_ERR;
    }
    return qw_varint(w, seq);
}

fn qw_close(w: &mut QW, app: i32, code: i64, frame_type: i64, reason: ptr<u8>, rlen: i64) -> i32 {
    var ty: i64 = QF_CONNECTION_CLOSE;
    if (app == 1) {
        ty = QF_CONNECTION_CLOSE_APP;
    }
    if (hxbuf_putc(&mut w.b, ty as u8) != 0) {
        return QF_ERR;
    }
    if (qw_varint(w, code) != QF_OK) {
        return QF_ERR;
    }
    if (app == 0) {
        if (qw_varint(w, frame_type) != QF_OK) {
            return QF_ERR;
        }
    }
    if (qw_varint(w, rlen) != QF_OK) {
        return QF_ERR;
    }
    if (rlen > 0 && hxbuf_put(&mut w.b, reason, rlen) != 0) {
        return QF_ERR;
    }
    return QF_OK;
}
