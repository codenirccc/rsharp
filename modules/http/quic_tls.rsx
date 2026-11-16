include "tls13.rsx";
include "quic_crypto.rsx";
include "quic_frame.rsx";

const QT_OK: i32 = 0;
const QT_ERR: i32 = -1;

const QT_TP_ORIGINAL_DCID: i64 = 0x00;
const QT_TP_MAX_IDLE: i64 = 0x01;
const QT_TP_MAX_UDP: i64 = 0x03;
const QT_TP_MAX_DATA: i64 = 0x04;
const QT_TP_MAX_SD_BIDI_LOCAL: i64 = 0x05;
const QT_TP_MAX_SD_BIDI_REMOTE: i64 = 0x06;
const QT_TP_MAX_SD_UNI: i64 = 0x07;
const QT_TP_MAX_STREAMS_BIDI: i64 = 0x08;
const QT_TP_MAX_STREAMS_UNI: i64 = 0x09;
const QT_TP_ACK_EXP: i64 = 0x0a;
const QT_TP_MAX_ACK_DELAY: i64 = 0x0b;
const QT_TP_NO_MIGRATION: i64 = 0x0c;
const QT_TP_ACTIVE_CID_LIMIT: i64 = 0x0e;
const QT_TP_INITIAL_SCID: i64 = 0x0f;
const QT_TP_RETRY_SCID: i64 = 0x10;

const QT_CH_MAX_DATA: i64 = 4194304;
const QT_CH_STREAM_DATA: i64 = 4194304;
const QT_CH_STREAMS: i64 = 16;
const QT_CH_IDLE: i64 = 30000;
const QT_CH_ACK_DELAY: i64 = 25;

struct QtTp {
    odcid_off: i64,
    odcid_len: i64,
    scid_off: i64,
    scid_len: i64,
    retry_off: i64,
    retry_len: i64,
    max_idle: i64,
    max_udp: i64,
    max_data: i64,
    max_sd_bidi_local: i64,
    max_sd_bidi_remote: i64,
    max_sd_uni: i64,
    max_streams_bidi: i64,
    max_streams_uni: i64,
    ack_exp: i64,
    max_ack_delay: i64,
    active_cid_limit: i64,
    no_migration: i32,
    base: ptr<u8>
}

fn qt_tp_init(tp: &mut QtTp) {
    tp.odcid_off = -1;
    tp.odcid_len = 0;
    tp.scid_off = -1;
    tp.scid_len = 0;
    tp.retry_off = -1;
    tp.retry_len = 0;
    tp.max_idle = 0;
    tp.max_udp = 65527;
    tp.max_data = 0;
    tp.max_sd_bidi_local = 0;
    tp.max_sd_bidi_remote = 0;
    tp.max_sd_uni = 0;
    tp.max_streams_bidi = 0;
    tp.max_streams_uni = 0;
    tp.ack_exp = 3;
    tp.max_ack_delay = 25;
    tp.active_cid_limit = 2;
    tp.no_migration = 0;
    tp.base = null;
}

fn qt_tp_u64(b: &mut HxBuf, id: i64, v: i64) -> i32 {
    if (hx_put_varint(b, id) != 0) {
        return QT_ERR;
    }
    if (hx_put_varint(b, quic_varint_len(v)) != 0) {
        return QT_ERR;
    }
    if (hx_put_varint(b, v) != 0) {
        return QT_ERR;
    }
    return QT_OK;
}

fn qt_tp_cid(b: &mut HxBuf, id: i64, p: ptr<u8>, n: i64) -> i32 {
    if (n < 0 || n > 20) {
        return QT_ERR;
    }
    if (hx_put_varint(b, id) != 0) {
        return QT_ERR;
    }
    if (hx_put_varint(b, n) != 0) {
        return QT_ERR;
    }
    if (n > 0 && hxbuf_put(b, p, n) != 0) {
        return QT_ERR;
    }
    return QT_OK;
}

fn qt_client_tp(b: &mut HxBuf, scid: ptr<u8>, scidlen: i64) -> i32 {
    if (qt_tp_cid(b, QT_TP_INITIAL_SCID, scid, scidlen) != QT_OK) {
        return QT_ERR;
    }
    if (qt_tp_u64(b, QT_TP_MAX_IDLE, QT_CH_IDLE) != QT_OK) {
        return QT_ERR;
    }
    if (qt_tp_u64(b, QT_TP_MAX_DATA, QT_CH_MAX_DATA) != QT_OK) {
        return QT_ERR;
    }
    if (qt_tp_u64(b, QT_TP_MAX_SD_BIDI_LOCAL, QT_CH_STREAM_DATA) != QT_OK) {
        return QT_ERR;
    }
    if (qt_tp_u64(b, QT_TP_MAX_SD_BIDI_REMOTE, QT_CH_STREAM_DATA) != QT_OK) {
        return QT_ERR;
    }
    if (qt_tp_u64(b, QT_TP_MAX_SD_UNI, QT_CH_STREAM_DATA) != QT_OK) {
        return QT_ERR;
    }
    if (qt_tp_u64(b, QT_TP_MAX_STREAMS_BIDI, QT_CH_STREAMS) != QT_OK) {
        return QT_ERR;
    }
    if (qt_tp_u64(b, QT_TP_MAX_STREAMS_UNI, QT_CH_STREAMS) != QT_OK) {
        return QT_ERR;
    }
    if (qt_tp_u64(b, QT_TP_MAX_ACK_DELAY, QT_CH_ACK_DELAY) != QT_OK) {
        return QT_ERR;
    }
    if (qt_tp_u64(b, QT_TP_ACTIVE_CID_LIMIT, 2) != QT_OK) {
        return QT_ERR;
    }
    return QT_OK;
}

fn qt_client_hello(t: &mut Tls13, host: ptr<u8>, scid: ptr<u8>, scidlen: i64, out: &mut HxBuf) -> i32 {
    var body: HxBuf = hxbuf_new(768);
    if (body.p == null) {
        return QT_ERR;
    }

    tls_u16(&mut body, 0x0303);

    var rnd: [u8; 32] = [0];
    var rp: ptr<u8> = null;
    unsafe { rp = &mut rnd[0] as ptr<u8>; }
    if (hx_random(rp, 32) != 0) {
        hxbuf_free(&mut body);
        return QT_ERR;
    }
    hxbuf_put(&mut body, rp, 32);

    hxbuf_putc(&mut body, 0);

    tls_u16(&mut body, 2);
    tls_u16(&mut body, 0x1301);

    hxbuf_putc(&mut body, 1);
    hxbuf_putc(&mut body, 0);

    var ext: HxBuf = hxbuf_new(384);
    if (ext.p == null) {
        hxbuf_free(&mut body);
        return QT_ERR;
    }

    let hl: i64 = rt_len(host);
    tls_u16(&mut ext, 0x0000);
    tls_u16(&mut ext, 5 + hl);
    tls_u16(&mut ext, 3 + hl);
    hxbuf_putc(&mut ext, 0);
    tls_u16(&mut ext, hl);
    hxbuf_put(&mut ext, host, hl);

    tls_u16(&mut ext, 0x000a);
    tls_u16(&mut ext, 6);
    tls_u16(&mut ext, 4);
    tls_u16(&mut ext, 29);
    tls_u16(&mut ext, 23);

    tls_u16(&mut ext, 0x000d);
    tls_u16(&mut ext, 10);
    tls_u16(&mut ext, 8);
    tls_u16(&mut ext, 0x0804);
    tls_u16(&mut ext, 0x0403);
    tls_u16(&mut ext, 0x0503);
    tls_u16(&mut ext, 0x0401);

    tls_u16(&mut ext, 0x0010);
    tls_u16(&mut ext, 5);
    tls_u16(&mut ext, 3);
    hxbuf_putc(&mut ext, 2);
    hxbuf_puts(&mut ext, "h3");

    tls_u16(&mut ext, 0x002b);
    tls_u16(&mut ext, 3);
    hxbuf_putc(&mut ext, 2);
    tls_u16(&mut ext, 0x0304);

    var xp: ptr<u8> = null;
    unsafe { xp = &mut t.xpriv[0] as ptr<u8>; }
    if (hx_random(xp, 32) != 0) {
        hxbuf_free(&mut ext);
        hxbuf_free(&mut body);
        return QT_ERR;
    }
    var pubk: [u8; 32] = [0];
    var pp: ptr<u8> = null;
    unsafe { pp = &mut pubk[0] as ptr<u8>; }
    if (x25519_base(pp, xp) != 0) {
        hxbuf_free(&mut ext);
        hxbuf_free(&mut body);
        return QT_ERR;
    }
    tls_u16(&mut ext, 0x0033);
    tls_u16(&mut ext, 38);
    tls_u16(&mut ext, 36);
    tls_u16(&mut ext, 29);
    tls_u16(&mut ext, 32);
    hxbuf_put(&mut ext, pp, 32);

    var tp: HxBuf = hxbuf_new(128);
    if (tp.p == null) {
        hxbuf_free(&mut ext);
        hxbuf_free(&mut body);
        return QT_ERR;
    }
    if (qt_client_tp(&mut tp, scid, scidlen) != QT_OK) {
        hxbuf_free(&mut tp);
        hxbuf_free(&mut ext);
        hxbuf_free(&mut body);
        return QT_ERR;
    }
    tls_u16(&mut ext, 0x0039);
    tls_u16(&mut ext, tp.len);
    hxbuf_put(&mut ext, tp.p, tp.len);
    hxbuf_free(&mut tp);

    tls_u16(&mut body, ext.len);
    hxbuf_put(&mut body, ext.p, ext.len);
    hxbuf_free(&mut ext);

    hxbuf_putc(out, TLS_HS_CLIENT_HELLO as u8);
    tls_u24(out, body.len);
    hxbuf_put(out, body.p, body.len);
    hxbuf_free(&mut body);
    return QT_OK;
}

fn qt_tp_parse(p: ptr<u8>, n: i64, tp: &mut QtTp) -> i32 {
    qt_tp_init(tp);
    tp.base = p;
    var off: i64 = 0;
    var seen: i64 = 0;
    while (off < n) {
        if (off + 1 > n) {
            return QT_ERR;
        }
        let id: i64 = quic_varint_get(p, off);
        off += quic_varint_hdr_len(rt_byte(p, off));
        if (off + 1 > n) {
            return QT_ERR;
        }
        let ln: i64 = quic_varint_get(p, off);
        off += quic_varint_hdr_len(rt_byte(p, off));
        if (off + ln > n) {
            return QT_ERR;
        }
        let bit: i64 = 1 << (id % 62);
        if ((seen & bit) != 0) {
            return QT_ERR;
        }
        seen = seen | bit;
        if (id == QT_TP_ORIGINAL_DCID) {
            tp.odcid_off = off;
            tp.odcid_len = ln;
        } else if (id == QT_TP_INITIAL_SCID) {
            tp.scid_off = off;
            tp.scid_len = ln;
        } else if (id == QT_TP_RETRY_SCID) {
            tp.retry_off = off;
            tp.retry_len = ln;
        } else if (id == QT_TP_MAX_UDP) {
            tp.max_udp = quic_varint_get(p, off);
        } else if (id == QT_TP_MAX_DATA) {
            tp.max_data = quic_varint_get(p, off);
        } else if (id == QT_TP_MAX_SD_BIDI_LOCAL) {
            tp.max_sd_bidi_local = quic_varint_get(p, off);
        } else if (id == QT_TP_MAX_SD_BIDI_REMOTE) {
            tp.max_sd_bidi_remote = quic_varint_get(p, off);
        } else if (id == QT_TP_MAX_SD_UNI) {
            tp.max_sd_uni = quic_varint_get(p, off);
        } else if (id == QT_TP_MAX_STREAMS_BIDI) {
            tp.max_streams_bidi = quic_varint_get(p, off);
        } else if (id == QT_TP_MAX_STREAMS_UNI) {
            tp.max_streams_uni = quic_varint_get(p, off);
        } else if (id == QT_TP_ACK_EXP) {
            tp.ack_exp = quic_varint_get(p, off);
        } else if (id == QT_TP_MAX_ACK_DELAY) {
            tp.max_ack_delay = quic_varint_get(p, off);
        } else if (id == QT_TP_MAX_IDLE) {
            tp.max_idle = quic_varint_get(p, off);
        } else if (id == QT_TP_ACTIVE_CID_LIMIT) {
            tp.active_cid_limit = quic_varint_get(p, off);
        } else if (id == QT_TP_NO_MIGRATION) {
            tp.no_migration = 1;
        }
        off += ln;
    }
    return QT_OK;
}

fn qt_ee_tp(p: ptr<u8>, n: i64, tp: &mut QtTp) -> i32 {
    qt_tp_init(tp);
    if (n < 5) {
        return QT_ERR;
    }
    if (rt_byte(p, 0) != TLS_HS_ENCRYPTED_EXT as u8) {
        return QT_ERR;
    }
    let bl: i64 = tls_rd24(p, 1);
    if (4 + bl > n || bl < 2) {
        return QT_ERR;
    }
    var bp: ptr<u8> = null;
    unsafe { bp = p + 4; }
    let el: i64 = tls_rd16(bp, 0);
    var off: i64 = 2;
    let end: i64 = off + el;
    if (end > bl) {
        return QT_ERR;
    }
    while (off + 4 <= end) {
        let et: i64 = tls_rd16(bp, off);
        let ln: i64 = tls_rd16(bp, off + 2);
        let data: i64 = off + 4;
        if (data + ln > end) {
            return QT_ERR;
        }
        if (et == 0x0039) {
            var dp: ptr<u8> = null;
            unsafe { dp = bp + data; }
            return qt_tp_parse(dp, ln, tp);
        }
        off = data + ln;
    }
    return QT_ERR;
}

fn qt_flight_len(p: ptr<u8>, n: i64) -> i64 {
    var off: i64 = 0;
    var step: i64 = 0;
    while (step < 4) {
        if (off + 4 > n) {
            return -1;
        }
        let ty: i32 = rt_byte(p, off) as i32;
        var want: i32 = TLS_HS_ENCRYPTED_EXT;
        if (step == 1) {
            want = TLS_HS_CERTIFICATE;
        }
        if (step == 2) {
            want = TLS_HS_CERT_VERIFY;
        }
        if (step == 3) {
            want = TLS_HS_FINISHED;
        }
        if (ty != want) {
            return -1;
        }
        let m: i64 = tls_rd24(p, off + 1);
        if (m < 0 || m > 1048576) {
            return -1;
        }
        if (off + 4 + m > n) {
            return -1;
        }
        off = off + 4 + m;
        step += 1;
    }
    return off;
}

fn qt_server_hello(t: &mut Tls13, p: ptr<u8>, n: i64, shared_out: ptr<u8>) -> i32 {
    if (n < 4) {
        return QT_ERR;
    }
    if (rt_byte(p, 0) != TLS_HS_SERVER_HELLO as u8) {
        return QT_ERR;
    }
    let m: i64 = tls_rd24(p, 1);
    if (4 + m > n) {
        return QT_ERR;
    }
    t.hand.len = 0;
    if (hxbuf_put(&mut t.hand, p, 4 + m) != 0) {
        return QT_ERR;
    }
    var hello: TlsHello = zero(TlsHello);
    if (tls13_parse_server_hello(t, &mut hello) != TLS_OK) {
        return QT_ERR;
    }
    if (hello.ks_off < 0 || hello.ks_len != 32) {
        return QT_ERR;
    }
    var peer: [u8; 32] = [0];
    var pp: ptr<u8> = null;
    unsafe { pp = &mut peer[0] as ptr<u8>; }
    var spp: ptr<u8> = null;
    unsafe { spp = t.hand.p + 4 + hello.ks_off; }
    rt_copy(pp, spp, 32);
    if (tls_hs_commit(t) != TLS_OK) {
        return QT_ERR;
    }
    var xp: ptr<u8> = null;
    unsafe { xp = &mut t.xpriv[0] as ptr<u8>; }
    if (x25519(shared_out, xp, pp) != 0) {
        return QT_ERR;
    }
    return QT_OK;
}

fn qt_finished(t: &mut Tls13, out: &mut HxBuf) -> i32 {
    var th: [u8; 32] = [0];
    var thp: ptr<u8> = null;
    unsafe { thp = &mut th[0] as ptr<u8>; }
    tls_transcript_hash(t, thp);
    var verify: [u8; 32] = [0];
    var vp: ptr<u8> = null;
    unsafe { vp = &mut verify[0] as ptr<u8>; }
    var ctp: ptr<u8> = null;
    unsafe { ctp = &mut t.c_hs_ts[0] as ptr<u8>; }
    if (tls13_finished_mac(ctp, thp, vp) != TLS_OK) {
        return QT_ERR;
    }
    if (hxbuf_putc(out, TLS_HS_FINISHED as u8) != 0) {
        return QT_ERR;
    }
    tls_u24(out, 32);
    if (hxbuf_put(out, vp, 32) != 0) {
        return QT_ERR;
    }
    if (hxbuf_put(&mut t.tr, out.p, out.len) != 0) {
        return QT_ERR;
    }
    return QT_OK;
}
