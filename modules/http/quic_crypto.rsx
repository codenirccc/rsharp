include "rt.rsx";
include "sha256.rsx";
include "hmac.rsx";
include "aes_gcm.rsx";

const QUIC_OK: i32 = 0;
const QUIC_ERR: i32 = -1;

const QUIC_KEY: i64 = 16;
const QUIC_IV: i64 = 12;
const QUIC_HP: i64 = 16;
const QUIC_TAG: i64 = 16;
const QUIC_SAMPLE: i64 = 16;
const QUIC_PN_MAX: i64 = 4;

const QUIC_TYPE_INITIAL: i32 = 0;
const QUIC_TYPE_0RTT: i32 = 1;
const QUIC_TYPE_HANDSHAKE: i32 = 2;
const QUIC_TYPE_RETRY: i32 = 3;

fn quic_salt_v1(out: ptr<u8>) -> i64 {
    return rt_parse_hex("38762cf7f55934b34d179ae6a4c80cadccbb7f0a", out, 32);
}

fn quic_key_derive(secret: ptr<u8>, secretlen: i64, key: ptr<u8>, iv: ptr<u8>, hp: ptr<u8>) -> i32 {
    var rc: i32 = tls13_expand_label(secret, secretlen, "quic key", null, 0, key, QUIC_KEY);
    if (rc != 0) {
        return QUIC_ERR;
    }
    rc = tls13_expand_label(secret, secretlen, "quic iv", null, 0, iv, QUIC_IV);
    if (rc != 0) {
        return QUIC_ERR;
    }
    return tls13_expand_label(secret, secretlen, "quic hp", null, 0, hp, QUIC_HP);
}

fn quic_initial_derive(dcid: ptr<u8>, dcidlen: i64, initial: ptr<u8>, client: ptr<u8>, server: ptr<u8>) -> i32 {
    var salt: [u8; 32] = [0];
    var sp: ptr<u8> = null;
    unsafe { sp = &mut salt[0] as ptr<u8>; }
    let sl: i64 = quic_salt_v1(sp);
    if (sl != 20) {
        return QUIC_ERR;
    }
    hkdf_extract(sp, sl, dcid, dcidlen, initial);
    var rc: i32 = tls13_expand_label(initial, 32, "client in", null, 0, client, 32);
    if (rc != 0) {
        return QUIC_ERR;
    }
    return tls13_expand_label(initial, 32, "server in", null, 0, server, 32);
}

fn quic_varint_len(v: i64) -> i64 {
    if (v < 64) {
        return 1;
    }
    if (v < 16384) {
        return 2;
    }
    if (v < 1073741824) {
        return 4;
    }
    return 8;
}

fn quic_varint_put(p: ptr<u8>, off: i64, v: i64) -> i64 {
    let n: i64 = quic_varint_len(v);
    if (n == 1) {
        rt_setbyte(p, off, (v & 63) as u8);
        return 1;
    }
    var tag: i64 = 0;
    if (n == 2) {
        tag = 0x40;
    }
    if (n == 4) {
        tag = 0x80;
    }
    if (n == 8) {
        tag = 0xc0;
    }
    var i: i64 = 0;
    while (i < n) {
        let sh: i64 = (n - 1 - i) * 8;
        var b: i64 = (v >> sh) & 255;
        if (i == 0) {
            b = b | tag;
        }
        rt_setbyte(p, off + i, b as u8);
        i += 1;
    }
    return n;
}

fn quic_varint_hdr_len(b0: u8) -> i64 {
    let k: i64 = ((b0 >> 6) & 3) as i64;
    var n: i64 = 1;
    var i: i64 = 0;
    while (i < k) {
        n = n * 2;
        i += 1;
    }
    return n;
}

fn quic_varint_get(p: ptr<u8>, off: i64) -> i64 {
    let b0: u8 = rt_byte(p, off);
    let n: i64 = quic_varint_hdr_len(b0);
    var v: i64 = (b0 & 63) as i64;
    var i: i64 = 1;
    while (i < n) {
        v = (v << 8) | (rt_byte(p, off + i) as i64);
        i += 1;
    }
    return v;
}

fn hx_put_varint(b: &mut HxBuf, v: i64) -> i32 {
    let n: i64 = quic_varint_len(v);
    var tag: i64 = 0;
    if (n == 2) {
        tag = 0x40;
    }
    if (n == 4) {
        tag = 0x80;
    }
    if (n == 8) {
        tag = 0xc0;
    }
    var i: i64 = 0;
    while (i < n) {
        let sh: i64 = (n - 1 - i) * 8;
        var x: i64 = (v >> sh) & 255;
        if (i == 0) {
            x = x | tag;
        }
        if (hxbuf_putc(b, x as u8) != 0) {
            return -1;
        }
        i += 1;
    }
    return 0;
}

fn quic_is_long(p: ptr<u8>) -> i32 {
    if ((rt_byte(p, 0) & 0x80) != 0) {
        return 1;
    }
    return 0;
}

fn quic_pkt_type(p: ptr<u8>) -> i32 {
    if (quic_is_long(p) == 0) {
        return -1;
    }
    return ((rt_byte(p, 0) >> 4) & 3) as i32;
}

fn quic_version(p: ptr<u8>) -> i64 {
    if (quic_is_long(p) == 0) {
        return -1;
    }
    return ((rt_byte(p, 1) as i64) << 24) | ((rt_byte(p, 2) as i64) << 16) | ((rt_byte(p, 3) as i64) << 8) | (rt_byte(p, 4) as i64);
}

fn quic_dcid_len(p: ptr<u8>, pktlen: i64) -> i64 {
    if (pktlen < 6) {
        return -1;
    }
    if (quic_is_long(p) == 0) {
        return -1;
    }
    return rt_byte(p, 5) as i64;
}

fn quic_pnlen(p: ptr<u8>) -> i64 {
    return ((rt_byte(p, 0) & 3) as i64) + 1;
}

fn quic_pn_offset(pkt: ptr<u8>, pktlen: i64, dcidlen: i64) -> i64 {
    if (pktlen < 1) {
        return -1;
    }
    if (quic_is_long(pkt) == 0) {
        let o: i64 = 1 + dcidlen;
        if (o + 1 > pktlen) {
            return -1;
        }
        return o;
    }
    var off: i64 = 5;
    if (off + 1 > pktlen) {
        return -1;
    }
    let dl: i64 = rt_byte(pkt, off) as i64;
    off = off + 1 + dl;
    if (off + 1 > pktlen) {
        return -1;
    }
    let sl: i64 = rt_byte(pkt, off) as i64;
    off = off + 1 + sl;
    let ty: i32 = quic_pkt_type(pkt);
    if (ty == QUIC_TYPE_RETRY) {
        return -1;
    }
    if (ty == QUIC_TYPE_INITIAL) {
        if (off + 1 > pktlen) {
            return -1;
        }
        let tl: i64 = quic_varint_hdr_len(rt_byte(pkt, off));
        let tv: i64 = quic_varint_get(pkt, off);
        off = off + tl + tv;
    }
    if (off + 1 > pktlen) {
        return -1;
    }
    off = off + quic_varint_hdr_len(rt_byte(pkt, off));
    if (off + 1 > pktlen) {
        return -1;
    }
    return off;
}

fn quic_nonce(iv: ptr<u8>, pn: i64, out: ptr<u8>) {
    var i: i64 = 0;
    while (i < QUIC_IV) {
        rt_setbyte(out, i, rt_byte(iv, i));
        i += 1;
    }
    i = 0;
    while (i < 8) {
        let sh: i64 = i * 8;
        let b: u8 = ((pn >> sh) & 255) as u8;
        let at: i64 = QUIC_IV - 1 - i;
        rt_setbyte(out, at, rt_byte(out, at) ^ b);
        i += 1;
    }
}

fn quic_hp_mask(hp: ptr<u8>, sample: ptr<u8>, out: ptr<u8>) {
    var k: Aes128 = zero(Aes128);
    aes128_init(&mut k, hp);
    aes128_encrypt_block(&k, sample, out);
}

fn quic_pn_decode(trunc: i64, pnlen: i64, largest: i64) -> i64 {
    if (pnlen < 1 || pnlen > QUIC_PN_MAX) {
        return -1;
    }
    var win: i64 = 1;
    var i: i64 = 0;
    while (i < pnlen * 8) {
        win = win * 2;
        i += 1;
    }
    let half: i64 = win / 2;
    let base: i64 = largest - (largest % win);
    var cand: i64 = base + trunc;
    if (cand + half <= largest) {
        if (cand + win <= 4611686018427387904) {
            cand = cand + win;
        }
    }
    if (cand > largest + half) {
        if (cand >= win) {
            cand = cand - win;
        }
    }
    return cand;
}

fn quic_seal(key: ptr<u8>, iv: ptr<u8>, hp: ptr<u8>, hdr: ptr<u8>, hdrlen: i64, pnlen: i64, pn: i64, payload: ptr<u8>, plen: i64, out: ptr<u8>) -> i64 {
    if (pnlen < 1 || pnlen > QUIC_PN_MAX) {
        return -1;
    }
    if (hdrlen < pnlen || plen < 0) {
        return -1;
    }
    if (plen + QUIC_TAG + pnlen < 4 + QUIC_SAMPLE) {
        return -1;
    }
    var i: i64 = 0;
    while (i < hdrlen) {
        rt_setbyte(out, i, rt_byte(hdr, i));
        i += 1;
    }

    var nonce: [u8; 12] = [0];
    var np: ptr<u8> = null;
    unsafe { np = &mut nonce[0] as ptr<u8>; }
    quic_nonce(iv, pn, np);

    var k: Aes128 = zero(Aes128);
    aes128_init(&mut k, key);

    var cp: ptr<u8> = null;
    var tp: ptr<u8> = null;
    unsafe { cp = out + hdrlen; tp = out + hdrlen + plen; }
    if (aes128_gcm_seal(&k, np, hdr, hdrlen, payload, plen, cp, tp) != 0) {
        return -1;
    }

    let pn_off: i64 = hdrlen - pnlen;
    var sample: ptr<u8> = null;
    unsafe { sample = out + pn_off + 4; }
    var mask: [u8; 16] = [0];
    var mp: ptr<u8> = null;
    unsafe { mp = &mut mask[0] as ptr<u8>; }
    quic_hp_mask(hp, sample, mp);

    if (quic_is_long(out) == 1) {
        rt_setbyte(out, 0, rt_byte(out, 0) ^ (rt_byte(mp, 0) & 15));
    } else {
        rt_setbyte(out, 0, rt_byte(out, 0) ^ (rt_byte(mp, 0) & 31));
    }
    i = 0;
    while (i < pnlen) {
        let at: i64 = pn_off + i;
        rt_setbyte(out, at, rt_byte(out, at) ^ rt_byte(mp, 1 + i));
        i += 1;
    }
    return hdrlen + plen + QUIC_TAG;
}

fn quic_open(key: ptr<u8>, iv: ptr<u8>, hp: ptr<u8>, pkt: ptr<u8>, pktlen: i64, pn_offset: i64, pnlen: i64, pn: i64, out: ptr<u8>, outmax: i64) -> i64 {
    if (pnlen < 1 || pnlen > QUIC_PN_MAX) {
        return -1;
    }
    let pend: i64 = pn_offset + pnlen;
    if (pend + QUIC_TAG > pktlen) {
        return -1;
    }
    let clen: i64 = pktlen - pend - QUIC_TAG;
    if (clen > outmax) {
        return -1;
    }
    if (pn_offset + 4 + QUIC_SAMPLE > pktlen) {
        return -1;
    }

    var sample: ptr<u8> = null;
    unsafe { sample = pkt + pn_offset + 4; }
    var mask: [u8; 16] = [0];
    var mp: ptr<u8> = null;
    unsafe { mp = &mut mask[0] as ptr<u8>; }
    quic_hp_mask(hp, sample, mp);

    if (quic_is_long(pkt) == 1) {
        rt_setbyte(pkt, 0, rt_byte(pkt, 0) ^ (rt_byte(mp, 0) & 15));
    } else {
        rt_setbyte(pkt, 0, rt_byte(pkt, 0) ^ (rt_byte(mp, 0) & 31));
    }
    var i: i64 = 0;
    while (i < pnlen) {
        let at: i64 = pn_offset + i;
        rt_setbyte(pkt, at, rt_byte(pkt, at) ^ rt_byte(mp, 1 + i));
        i += 1;
    }

    var nonce: [u8; 12] = [0];
    var np: ptr<u8> = null;
    unsafe { np = &mut nonce[0] as ptr<u8>; }
    quic_nonce(iv, pn, np);

    var k: Aes128 = zero(Aes128);
    aes128_init(&mut k, key);

    var cp: ptr<u8> = null;
    var tp: ptr<u8> = null;
    unsafe { cp = pkt + pend; tp = pkt + pktlen - QUIC_TAG; }
    if (aes128_gcm_open(&k, np, pkt, pend, cp, clen, out, tp) != 0) {
        return -1;
    }
    return clen;
}
