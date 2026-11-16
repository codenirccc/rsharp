include "quic_frame.rsx";

const QP_OK: i32 = 0;
const QP_ERR: i32 = -1;
const QP_MORE: i32 = 1;

const QP_V1: i64 = 1;

struct Qp {
    long: i32,
    ty: i32,
    version: i64,
    dcid_len: i64,
    scid_off: i64,
    scid_len: i64,
    pn_off: i64,
    pn_len: i64,
    pkt_len: i64
}

fn qp_rd32(p: ptr<u8>, off: i64) -> i64 {
    return ((rt_byte(p, off) as i64) << 24) | ((rt_byte(p, off + 1) as i64) << 16) | ((rt_byte(p, off + 2) as i64) << 8) | (rt_byte(p, off + 3) as i64);
}

fn qp_scan(p: ptr<u8>, n: i64, dcid_len_hint: i64, expect_ty: i32, q: &mut Qp) -> i32 {
    q.long = 0;
    q.ty = -1;
    q.version = 0;
    q.dcid_len = 0;
    q.scid_off = -1;
    q.scid_len = 0;
    q.pn_off = -1;
    q.pn_len = 0;
    q.pkt_len = 0;
    if (n < 1) {
        return QP_ERR;
    }
    let b0: u8 = rt_byte(p, 0);
    if ((b0 & 0x80) == 0) {
        if (dcid_len_hint < 0 || dcid_len_hint > 20) {
            return QP_ERR;
        }
        q.long = 0;
        q.dcid_len = dcid_len_hint;
        q.pn_off = 1 + dcid_len_hint;
        q.pkt_len = n;
        if (q.pn_off + 4 + 16 > q.pkt_len) {
            return QP_ERR;
        }
        return QP_OK;
    }

    if (n < 7) {
        return QP_ERR;
    }
    q.long = 1;
    q.version = qp_rd32(p, 1);
    q.dcid_len = rt_byte(p, 5) as i64;
    if (q.dcid_len > 20) {
        return QP_ERR;
    }
    var off: i64 = 6;
    if (off + q.dcid_len + 1 > n) {
        return QP_ERR;
    }
    off += q.dcid_len;
    q.scid_len = rt_byte(p, off) as i64;
    if (q.scid_len > 20) {
        return QP_ERR;
    }
    off += 1;
    q.scid_off = off;
    if (off + q.scid_len > n) {
        return QP_ERR;
    }
    off += q.scid_len;

    var ty: i32 = expect_ty;
    if (ty < 0) {
        ty = ((b0 >> 4) & 3) as i32;
        if (ty == QUIC_TYPE_RETRY) {
            return QP_MORE;
        }
    }
    q.ty = ty;

    if (ty == QUIC_TYPE_INITIAL) {
        if (off + 1 > n) {
            return QP_ERR;
        }
        let tl: i64 = quic_varint_get(p, off);
        let tn: i64 = quic_varint_hdr_len(rt_byte(p, off));
        if (tl < 0 || off + tn + tl > n) {
            return QP_ERR;
        }
        off += tn + tl;
    }

    if (off + 1 > n) {
        return QP_ERR;
    }
    let len: i64 = quic_varint_get(p, off);
    let ln: i64 = quic_varint_hdr_len(rt_byte(p, off));
    off += ln;
    q.pn_off = off;
    if (len < 1 + 16) {
        return QP_ERR;
    }
    q.pkt_len = off + len;
    if (q.pkt_len > n) {
        return QP_ERR;
    }
    return QP_OK;
}

fn qp_hdr_len(q: &Qp, pn_len: i64) -> i64 {
    return q.pn_off + pn_len;
}

fn qp_copy(dst: &mut Qp, src: &Qp) {
    dst.long = src.long;
    dst.ty = src.ty;
    dst.version = src.version;
    dst.dcid_len = src.dcid_len;
    dst.scid_off = src.scid_off;
    dst.scid_len = src.scid_len;
    dst.pn_off = src.pn_off;
    dst.pn_len = src.pn_len;
    dst.pkt_len = src.pkt_len;
}

fn qp_classify(p: ptr<u8>, q: &mut Qp, hp: ptr<u8>) -> i32 {
    if (q.pn_off < 1 || q.pkt_len <= 0) {
        return QP_ERR;
    }
    if (q.pn_off + 4 + 16 > q.pkt_len) {
        return QP_ERR;
    }
    var sample: ptr<u8> = null;
    unsafe { sample = p + q.pn_off + 4; }
    var mask: [u8; 16] = [0];
    var mp: ptr<u8> = null;
    unsafe { mp = &mut mask[0] as ptr<u8>; }
    quic_hp_mask(hp, sample, mp);
    var b0: u8 = rt_byte(p, 0);
    if (q.long == 1) {
        b0 = b0 ^ (rt_byte(mp, 0) & 15);
        q.ty = ((b0 >> 4) & 3) as i32;
    } else {
        b0 = b0 ^ (rt_byte(mp, 0) & 31);
        q.ty = -1;
    }
    q.pn_len = ((b0 & 3) as i64) + 1;
    return QP_OK;
}

fn qp_unprotect(p: ptr<u8>, q: &Qp, hp: ptr<u8>) -> i64 {
    if (q.pn_off < 1 || q.pn_len < 1 || q.pn_len > 4) {
        return -1;
    }
    if (q.pn_off + 4 + 16 > q.pkt_len) {
        return -1;
    }
    if (q.pn_off + q.pn_len > q.pkt_len) {
        return -1;
    }
    var sample: ptr<u8> = null;
    unsafe { sample = p + q.pn_off + 4; }
    var mask: [u8; 16] = [0];
    var mp: ptr<u8> = null;
    unsafe { mp = &mut mask[0] as ptr<u8>; }
    quic_hp_mask(hp, sample, mp);

    var b0: u8 = rt_byte(p, 0);
    if (q.long == 1) {
        b0 = b0 ^ (rt_byte(mp, 0) & 15);
    } else {
        b0 = b0 ^ (rt_byte(mp, 0) & 31);
    }
    rt_setbyte(p, 0, b0);

    var i: i64 = 0;
    while (i < q.pn_len) {
        let at: i64 = q.pn_off + i;
        rt_setbyte(p, at, rt_byte(p, at) ^ rt_byte(mp, 1 + i));
        i += 1;
    }

    var trunc: i64 = 0;
    i = 0;
    while (i < q.pn_len) {
        trunc = (trunc << 8) | (rt_byte(p, q.pn_off + i) as i64);
        i += 1;
    }
    return trunc;
}

fn qp_aead_open(key: ptr<u8>, iv: ptr<u8>, pkt: ptr<u8>, pkt_len: i64, q: &Qp, pn: i64, out: ptr<u8>, out_max: i64) -> i64 {
    if (q.pn_len < 1 || q.pn_len > 4) {
        return -1;
    }
    let pend: i64 = q.pn_off + q.pn_len;
    if (pend + 16 > pkt_len) {
        return -1;
    }
    let clen: i64 = pkt_len - pend - 16;
    if (clen < 0 || clen > out_max) {
        return -1;
    }
    var nonce: [u8; 12] = [0];
    var np: ptr<u8> = null;
    unsafe { np = &mut nonce[0] as ptr<u8>; }
    quic_nonce(iv, pn, np);

    var k: Aes128 = zero(Aes128);
    aes128_init(&mut k, key);

    var cp: ptr<u8> = null;
    var tp: ptr<u8> = null;
    unsafe { cp = pkt + pend; tp = pkt + pkt_len - 16; }
    if (aes128_gcm_open(&k, np, pkt, pend, cp, clen, out, tp) != 0) {
        return -1;
    }
    return clen;
}

fn qp_build_long(hdr: &mut HxBuf, ty: i32, dcid: ptr<u8>, dcid_len: i64, scid: ptr<u8>, scid_len: i64, token: ptr<u8>, token_len: i64, pn: i64, pn_len: i64, plen: i64) -> i32 {
    if (ty < 0 || ty > 2) {
        return QP_ERR;
    }
    if (dcid_len < 0 || dcid_len > 20 || scid_len < 0 || scid_len > 20) {
        return QP_ERR;
    }
    if (pn_len < 1 || pn_len > 4) {
        return QP_ERR;
    }
    if (plen < 0) {
        return QP_ERR;
    }
    let b0: i64 = 0xc0 | ((ty as i64) << 4) | (pn_len - 1);
    if (hxbuf_putc(hdr, b0 as u8) != 0) {
        return QP_ERR;
    }
    var v: i64 = QP_V1;
    var i: i64 = 3;
    while (i >= 0) {
        if (hxbuf_putc(hdr, ((v >> (i * 8)) & 255) as u8) != 0) {
            return QP_ERR;
        }
        i -= 1;
    }
    if (hxbuf_putc(hdr, dcid_len as u8) != 0) {
        return QP_ERR;
    }
    if (dcid_len > 0 && hxbuf_put(hdr, dcid, dcid_len) != 0) {
        return QP_ERR;
    }
    if (hxbuf_putc(hdr, scid_len as u8) != 0) {
        return QP_ERR;
    }
    if (scid_len > 0 && hxbuf_put(hdr, scid, scid_len) != 0) {
        return QP_ERR;
    }
    if (ty == QUIC_TYPE_INITIAL) {
        if (hx_put_varint(hdr, token_len) != 0) {
            return QP_ERR;
        }
        if (token_len > 0 && hxbuf_put(hdr, token, token_len) != 0) {
            return QP_ERR;
        }
    }
    let len: i64 = pn_len + plen + 16;
    if (hx_put_varint(hdr, len) != 0) {
        return QP_ERR;
    }
    i = pn_len - 1;
    while (i >= 0) {
        if (hxbuf_putc(hdr, ((pn >> (i * 8)) & 255) as u8) != 0) {
            return QP_ERR;
        }
        i -= 1;
    }
    return QP_OK;
}

fn qp_build_short(hdr: &mut HxBuf, dcid: ptr<u8>, dcid_len: i64, pn: i64, pn_len: i64, plen: i64) -> i32 {
    if (dcid_len < 0 || dcid_len > 20) {
        return QP_ERR;
    }
    if (pn_len < 1 || pn_len > 4 || plen < 0) {
        return QP_ERR;
    }
    let b0: i64 = 0x40 | (pn_len - 1);
    if (hxbuf_putc(hdr, b0 as u8) != 0) {
        return QP_ERR;
    }
    if (dcid_len > 0 && hxbuf_put(hdr, dcid, dcid_len) != 0) {
        return QP_ERR;
    }
    var i: i64 = pn_len - 1;
    while (i >= 0) {
        if (hxbuf_putc(hdr, ((pn >> (i * 8)) & 255) as u8) != 0) {
            return QP_ERR;
        }
        i -= 1;
    }
    return QP_OK;
}

struct QcBuf {
    b: HxBuf,
    n: i64,
    err: i32
}

fn qcb_init(s: &mut QcBuf, cap: i64) -> i32 {
    s.b = hxbuf_new(cap);
    s.n = 0;
    s.err = 0;
    if (s.b.p == null) {
        s.err = 1;
        return QP_ERR;
    }
    return QP_OK;
}

fn qcb_add(s: &mut QcBuf, off: i64, p: ptr<u8>, n: i64) -> i32 {
    if (n <= 0) {
        return QP_OK;
    }
    if (off < 0) {
        s.err = 1;
        return QP_ERR;
    }
    if (off > s.n) {
        s.err = 1;
        return QP_ERR;
    }
    if (off + n <= s.n) {
        return QP_OK;
    }
    var src: ptr<u8> = p;
    var take: i64 = n;
    if (off < s.n) {
        let skip: i64 = s.n - off;
        unsafe { src = p + skip; }
        take -= skip;
    }
    if (hxbuf_put(&mut s.b, src, take) != 0) {
        s.err = 1;
        return QP_ERR;
    }
    s.n += take;
    return QP_OK;
}

fn qcb_free(s: &mut QcBuf) {
    hxbuf_free(&mut s.b);
    s.n = 0;
}
