include "rt.rsx";
include "sha256.rsx";
include "hmac.rsx";
include "aes_gcm.rsx";
include "x25519.rsx";
include "x509.rsx";

const TLS_OK: i32 = 0;
const TLS_ERR: i32 = -1;

const TLS_REC_CCS: i32 = 20;
const TLS_REC_ALERT: i32 = 21;
const TLS_REC_HANDSHAKE: i32 = 22;
const TLS_REC_APP: i32 = 23;

const TLS_HS_CLIENT_HELLO: i32 = 1;
const TLS_HS_SERVER_HELLO: i32 = 2;
const TLS_HS_ENCRYPTED_EXT: i32 = 8;
const TLS_HS_CERTIFICATE: i32 = 11;
const TLS_HS_CERT_VERIFY: i32 = 15;
const TLS_HS_FINISHED: i32 = 20;

const TLS_MAX_RECORD: i64 = 16640;
const TLS_MAX_CHAIN: i64 = 8;

const TLS_TAG: i64 = 16;

struct TlsKey {
    k: [u8; 16],
    iv: [u8; 12],
    seq: u64
}

struct Tls13 {
    sock: u64,
    tr: HxBuf,
    hand: HxBuf,
    inb: HxBuf,
    ro: i64,
    certs: HxBuf,
    coff: [i64; 8],
    clens: [i64; 8],
    cn: i64,
    chain: X509Chain,
    c_hs: TlsKey,
    s_hs: TlsKey,
    c_ap: TlsKey,
    s_ap: TlsKey,
    c_hs_ts: [u8; 32],
    s_hs_ts: [u8; 32],
    c_ap_ts: [u8; 32],
    s_ap_ts: [u8; 32],
    hs_secret: [u8; 32],
    phase: i32,
    alpn: [u8; 16],
    alpn_len: i64,
    closed: i32,
    alpn_mode: i32,
    xpriv: [u8; 32]
}

fn tls_u16(b: &mut HxBuf, v: i64) -> i32 {
    hxbuf_putc(b, ((v >> 8) & 255) as u8);
    return hxbuf_putc(b, (v & 255) as u8);
}

fn tls_u24(b: &mut HxBuf, v: i64) -> i32 {
    hxbuf_putc(b, ((v >> 16) & 255) as u8);
    hxbuf_putc(b, ((v >> 8) & 255) as u8);
    return hxbuf_putc(b, (v & 255) as u8);
}

fn tls_rd16(p: ptr<u8>, off: i64) -> i64 {
    var a: u8 = 0;
    var b: u8 = 0;
    unsafe {
        a = p[off];
        b = p[off + 1];
    }
    return ((a as i64) << 8) | (b as i64);
}

fn tls_rd24(p: ptr<u8>, off: i64) -> i64 {
    var a: u8 = 0;
    var b: u8 = 0;
    var c: u8 = 0;
    unsafe {
        a = p[off];
        b = p[off + 1];
        c = p[off + 2];
    }
    return ((a as i64) << 16) | ((b as i64) << 8) | (c as i64);
}

fn tls_readn(s: u64, buf: ptr<u8>, n: i64) -> i32 {
    var off: i64 = 0;
    while (off < n) {
        var q: ptr<u8> = null;
        unsafe { q = buf + off; }
        let got: i64 = hx_recv(s, q, n - off);
        if (got <= 0) {
            return TLS_ERR;
        }
        off += got;
    }
    return TLS_OK;
}

fn tls_nonce(iv: ptr<u8>, seq: u64, out: ptr<u8>) -> i32 {
    rt_copy(out, iv, 12);
    var i: i64 = 0;
    while (i < 8) {
        let shift: u64 = ((7 - i) * 8) as u64;
        let byte: u8 = ((seq >> shift) & 255) as u8;
        var cur: u8 = 0;
        unsafe { cur = out[4 + i]; }
        rt_setbyte(out, 4 + i, cur ^ byte);
        i += 1;
    }
    return TLS_OK;
}

fn tls_key_take(key: &mut TlsKey, kb: ptr<u8>, ib: ptr<u8>) -> u64 {
    var i: i64 = 0;
    while (i < 16) {
        let v: u8 = key.k[i];
        rt_setbyte(kb, i, v);
        i += 1;
    }
    i = 0;
    while (i < 12) {
        let v: u8 = key.iv[i];
        rt_setbyte(ib, i, v);
        i += 1;
    }
    let s: u64 = key.seq;
    key.seq += 1;
    return s;
}

fn tls_key_init(key: &mut TlsKey, traffic: ptr<u8>) -> i32 {
    var kb: [u8; 16] = [0];
    var kp: ptr<u8> = null;
    unsafe { kp = &mut kb[0] as ptr<u8>; }
    if (tls13_expand_label(traffic, 32, "key", null, 0, kp, 16) != 0) {
        return TLS_ERR;
    }
    var ib: [u8; 12] = [0];
    var ip: ptr<u8> = null;
    unsafe { ip = &mut ib[0] as ptr<u8>; }
    if (tls13_expand_label(traffic, 32, "iv", null, 0, ip, 12) != 0) {
        return TLS_ERR;
    }
    var i: i64 = 0;
    while (i < 16) {
        key.k[i] = kb[i];
        i += 1;
    }
    i = 0;
    while (i < 12) {
        key.iv[i] = ib[i];
        i += 1;
    }
    key.seq = 0;
    return TLS_OK;
}

fn tls_copy32(dst: &mut [u8; 32], src: ptr<u8>) {
    var i: i64 = 0;
    while (i < 32) {
        var v: u8 = 0;
        unsafe { v = src[i]; }
        dst[i] = v;
        i += 1;
    }
}

fn tls_read_record(t: &mut Tls13) -> i32 {
    var out: i32 = TLS_ERR;
    var done: i32 = 0;
    while (done == 0) {
        var hdr: [u8; 5] = [0];
        var hp: ptr<u8> = null;
        unsafe { hp = &mut hdr[0] as ptr<u8>; }
        if (tls_readn(t.sock, hp, 5) != TLS_OK) {
            return TLS_ERR;
        }
        var rtype: i32 = 0;
        unsafe { rtype = hdr[0] as i32; }
        let len: i64 = tls_rd16(hp, 3);
        if (len <= 0) {
            return TLS_ERR;
        }
        if (len > TLS_MAX_RECORD) {
            return TLS_ERR;
        }

        var body: HxBuf = hxbuf_new(len + TLS_TAG);
        if (body.p == null) {
            return TLS_ERR;
        }
        body.len = len;
        if (tls_readn(t.sock, body.p, len) != TLS_OK) {
            hxbuf_free(&mut body);
            return TLS_ERR;
        }

        if (rtype == TLS_REC_CCS) {
            hxbuf_free(&mut body);
        } else if (rtype == TLS_REC_ALERT) {
            hxbuf_free(&mut body);
            return TLS_ERR;
        } else if (t.phase == 0) {
            t.inb.len = 0;
            t.ro = 0;
            hxbuf_put(&mut t.inb, body.p, len);
            out = rtype;
            done = 1;
            hxbuf_free(&mut body);
        } else {
            if (len < TLS_TAG + 1) {
                hxbuf_free(&mut body);
                return TLS_ERR;
            }
            let clen: i64 = len - TLS_TAG;

            var kb: [u8; 16] = [0];
            var ib: [u8; 12] = [0];
            var kp: ptr<u8> = null;
            var ip: ptr<u8> = null;
            unsafe {
                kp = &mut kb[0] as ptr<u8>;
                ip = &mut ib[0] as ptr<u8>;
            }
            var sq: u64 = 0;
            if (t.phase == 1) {
                sq = tls_key_take(&mut t.s_hs, kp, ip);
            } else {
                sq = tls_key_take(&mut t.s_ap, kp, ip);
            }

            var nonce: [u8; 12] = [0];
            var np: ptr<u8> = null;
            unsafe { np = &mut nonce[0] as ptr<u8>; }
            tls_nonce(ip, sq, np);

            var tag: [u8; 16] = [0];
            var tp: ptr<u8> = null;
            unsafe { tp = &mut tag[0] as ptr<u8>; }
            var src: ptr<u8> = null;
            unsafe { src = body.p + clen; }
            rt_copy(tp, src, TLS_TAG);

            t.inb.len = 0;
            t.ro = 0;
            if (hxbuf_reserve(&mut t.inb, clen + 1) != 0) {
                hxbuf_free(&mut body);
                return TLS_ERR;
            }

            var a: Aes128 = zero(Aes128);
            aes128_init(&mut a, kp);
            let bad: i32 = aes128_gcm_open(&a, np, hp, 5, body.p, clen, t.inb.p, tp);
            if (bad != 0) {
                hxbuf_free(&mut body);
                return TLS_ERR;
            }

            var i: i64 = clen;
            var ctype: i32 = -1;
            var scan: i32 = 1;
            while (scan == 1) {
                i -= 1;
                if (i < 0) {
                    scan = 0;
                } else {
                    var b: u8 = 0;
                    unsafe { b = t.inb.p[i]; }
                    if (b != 0) {
                        ctype = b as i32;
                        scan = 0;
                    }
                }
            }
            if (ctype < 0) {
                hxbuf_free(&mut body);
                return TLS_ERR;
            }
            t.inb.len = i;
            out = ctype;
            done = 1;
            hxbuf_free(&mut body);
        }
    }
    return out;
}

fn tls_write_record(t: &mut Tls13, use_app: i32, ctype: i32, p: ptr<u8>, n: i64) -> i32 {
    if (n < 0 || n > TLS_MAX_RECORD - TLS_TAG - 1) {
        return TLS_ERR;
    }

    var inner: HxBuf = hxbuf_new(n + 2);
    if (inner.p == null) {
        return TLS_ERR;
    }
    hxbuf_put(&mut inner, p, n);
    hxbuf_putc(&mut inner, ctype as u8);

    let total: i64 = inner.len + TLS_TAG;
    var hdr: [u8; 5] = [0];
    var hp: ptr<u8> = null;
    unsafe {
        hp = &mut hdr[0] as ptr<u8>;
        hdr[0] = TLS_REC_APP as u8;
        hdr[1] = 3;
        hdr[2] = 3;
        hdr[3] = ((total >> 8) & 255) as u8;
        hdr[4] = (total & 255) as u8;
    }

    var kb: [u8; 16] = [0];
    var ib: [u8; 12] = [0];
    var kp: ptr<u8> = null;
    var ip: ptr<u8> = null;
    unsafe {
        kp = &mut kb[0] as ptr<u8>;
        ip = &mut ib[0] as ptr<u8>;
    }
    var sq: u64 = 0;
    if (use_app == 1) {
        sq = tls_key_take(&mut t.c_ap, kp, ip);
    } else {
        sq = tls_key_take(&mut t.c_hs, kp, ip);
    }

    var nonce: [u8; 12] = [0];
    var np: ptr<u8> = null;
    unsafe { np = &mut nonce[0] as ptr<u8>; }
    tls_nonce(ip, sq, np);

    var body: HxBuf = hxbuf_new(total + TLS_TAG);
    if (body.p == null) {
        hxbuf_free(&mut inner);
        return TLS_ERR;
    }
    if (hxbuf_reserve(&mut body, total + TLS_TAG) != 0) {
        hxbuf_free(&mut inner);
        hxbuf_free(&mut body);
        return TLS_ERR;
    }
    body.len = total;

    var tag: [u8; 16] = [0];
    var tp: ptr<u8> = null;
    unsafe { tp = &mut tag[0] as ptr<u8>; }
    var a: Aes128 = zero(Aes128);
    aes128_init(&mut a, kp);
    if (aes128_gcm_seal(&a, np, hp, 5, inner.p, inner.len, body.p, tp) != 0) {
        hxbuf_free(&mut inner);
        hxbuf_free(&mut body);
        return TLS_ERR;
    }
    hxbuf_free(&mut inner);

    var tail: ptr<u8> = null;
    unsafe { tail = body.p + total - TLS_TAG; }
    rt_copy(tail, tp, TLS_TAG);

    var sent: i64 = hx_send(t.sock, hp, 5);
    if (sent != 5) {
        hxbuf_free(&mut body);
        return TLS_ERR;
    }
    sent = hx_send(t.sock, body.p, total);
    hxbuf_free(&mut body);
    if (sent != total) {
        return TLS_ERR;
    }
    return TLS_OK;
}

fn tls_transcript_hash(t: &mut Tls13, out: ptr<u8>) -> i32 {
    sha256(t.tr.p, t.tr.len, out);
    return TLS_OK;
}

fn tls_hs_next(t: &mut Tls13) -> i32 {
    var want: i32 = 1;
    while (want == 1) {
        if (t.hand.len >= 4) {
            let m: i64 = tls_rd24(t.hand.p, 1);
            if (m >= 0 && m <= 65536 && t.hand.len >= 4 + m) {
                var ty: u8 = 0;
                unsafe { ty = t.hand.p[0]; }
                return ty as i32;
            }
        }
        let ct: i32 = tls_read_record(t);
        if (ct == TLS_REC_HANDSHAKE) {
            var ip: ptr<u8> = null;
            var il: i64 = 0;
            unsafe { ip = t.inb.p; }
            il = t.inb.len;
            if (hxbuf_put(&mut t.hand, ip, il) != 0) {
                return TLS_ERR;
            }
        } else {
            return TLS_ERR;
        }
    }
    return TLS_ERR;
}

fn tls_hs_body_len(t: &mut Tls13) -> i64 {
    return tls_rd24(t.hand.p, 1);
}

fn tls_hs_commit(t: &mut Tls13) -> i32 {
    let ml: i64 = 4 + tls_hs_body_len(t);
    var src: ptr<u8> = null;
    unsafe { src = t.hand.p; }
    if (hxbuf_put(&mut t.tr, src, ml) != 0) {
        return TLS_ERR;
    }
    var tail: ptr<u8> = null;
    unsafe { tail = src + ml; }
    memmove(src, tail, (t.hand.len - ml) as u64);
    t.hand.len -= ml;
    return TLS_OK;
}

fn tls13_client_hello(t: &mut Tls13, host: ptr<u8>, out: &mut HxBuf) -> i32 {
    var body: HxBuf = hxbuf_new(512);
    if (body.p == null) {
        return TLS_ERR;
    }

    tls_u16(&mut body, 0x0303);

    var rnd: [u8; 32] = [0];
    var rp: ptr<u8> = null;
    unsafe { rp = &mut rnd[0] as ptr<u8>; }
    if (hx_random(rp, 32) != 0) {
        hxbuf_free(&mut body);
        return TLS_ERR;
    }
    hxbuf_put(&mut body, rp, 32);

    var sid: [u8; 32] = [0];
    var sp: ptr<u8> = null;
    unsafe { sp = &mut sid[0] as ptr<u8>; }
    if (hx_random(sp, 32) != 0) {
        hxbuf_free(&mut body);
        return TLS_ERR;
    }
    hxbuf_putc(&mut body, 32);
    hxbuf_put(&mut body, sp, 32);

    tls_u16(&mut body, 2);
    tls_u16(&mut body, 0x1301);

    hxbuf_putc(&mut body, 1);
    hxbuf_putc(&mut body, 0);

    var ext: HxBuf = hxbuf_new(256);
    if (ext.p == null) {
        hxbuf_free(&mut body);
        return TLS_ERR;
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

    if (t.alpn_mode == 2) {
        tls_u16(&mut ext, 0x0010);
        tls_u16(&mut ext, 5);
        tls_u16(&mut ext, 3);
        hxbuf_putc(&mut ext, 2);
        hxbuf_puts(&mut ext, "h2");
    } else if (t.alpn_mode == 1) {
        tls_u16(&mut ext, 0x0010);
        tls_u16(&mut ext, 11);
        tls_u16(&mut ext, 9);
        hxbuf_putc(&mut ext, 8);
        hxbuf_puts(&mut ext, "http/1.1");
    } else {
        tls_u16(&mut ext, 0x0010);
        tls_u16(&mut ext, 14);
        tls_u16(&mut ext, 12);
        hxbuf_putc(&mut ext, 2);
        hxbuf_puts(&mut ext, "h2");
        hxbuf_putc(&mut ext, 8);
        hxbuf_puts(&mut ext, "http/1.1");
    }

    tls_u16(&mut ext, 0x002b);
    tls_u16(&mut ext, 3);
    hxbuf_putc(&mut ext, 2);
    tls_u16(&mut ext, 0x0304);

    var xp: ptr<u8> = null;
    unsafe { xp = &mut t.xpriv[0] as ptr<u8>; }
    if (hx_random(xp, 32) != 0) {
        hxbuf_free(&mut ext);
        hxbuf_free(&mut body);
        return TLS_ERR;
    }
    var pubk: [u8; 32] = [0];
    var pp: ptr<u8> = null;
    unsafe { pp = &mut pubk[0] as ptr<u8>; }
    if (x25519_base(pp, xp) != 0) {
        hxbuf_free(&mut ext);
        hxbuf_free(&mut body);
        return TLS_ERR;
    }
    tls_u16(&mut ext, 0x0033);
    tls_u16(&mut ext, 38);
    tls_u16(&mut ext, 36);
    tls_u16(&mut ext, 29);
    tls_u16(&mut ext, 32);
    hxbuf_put(&mut ext, pp, 32);

    tls_u16(&mut body, ext.len);
    hxbuf_put(&mut body, ext.p, ext.len);
    hxbuf_free(&mut ext);

    hxbuf_putc(out, TLS_HS_CLIENT_HELLO as u8);
    tls_u24(out, body.len);
    hxbuf_put(out, body.p, body.len);
    hxbuf_free(&mut body);
    return TLS_OK;
}

struct TlsHello {
    group: i32,
    ks_off: i64,
    ks_len: i64
}

fn tls13_parse_server_hello(t: &mut Tls13, hs: &mut TlsHello) -> i32 {
    hs.group = -1;
    hs.ks_off = -1;
    hs.ks_len = 0;

    let bl: i64 = tls_hs_body_len(t);
    var bp: ptr<u8> = null;
    unsafe { bp = t.hand.p + 4; }
    if (bl < 38) {
        return TLS_ERR;
    }

    var off: i64 = 34;
    let sid: u8 = rt_byte(bp, off);
    off += 1 + (sid as i64);
    if (off + 3 > bl) {
        return TLS_ERR;
    }
    let cs: i64 = tls_rd16(bp, off);
    off += 2;
    let comp: u8 = rt_byte(bp, off);
    off += 1;
    if (comp != 0) {
        return TLS_ERR;
    }
    if (cs != 0x1301) {
        return TLS_ERR;
    }

    if (off + 2 > bl) {
        return TLS_ERR;
    }
    let el: i64 = tls_rd16(bp, off);
    off += 2;
    if (off + el > bl) {
        return TLS_ERR;
    }

    var version: i32 = 0;
    var i: i64 = 0;
    while (i < el) {
        if (off + i + 4 > bl) {
            return TLS_ERR;
        }
        let ty: i64 = tls_rd16(bp, off + i);
        let ln: i64 = tls_rd16(bp, off + i + 2);
        let data: i64 = off + i + 4;
        if (data + ln > bl) {
            return TLS_ERR;
        }
        if (ty == 0x002b) {
            if (ln == 2) {
                if (tls_rd16(bp, data) == 0x0304) {
                    version = 1;
                }
            }
        } else if (ty == 0x0033) {
            if (ln >= 36) {
                let g: i64 = tls_rd16(bp, data);
                let kl: i64 = tls_rd16(bp, data + 2);
                if (data + 4 + kl <= bl && kl > 0) {
                    hs.group = g as i32;
                    hs.ks_off = data + 4;
                    hs.ks_len = kl;
                }
            }
        }
        i += 4 + ln;
    }
    if (version != 1) {
        return TLS_ERR;
    }
    if (hs.group != 29 || hs.ks_len != 32) {
        return TLS_ERR;
    }
    return TLS_OK;
}

fn tls13_verify_scheme(spki: ptr<u8>, spki_len: i64, scheme: i64, msg: ptr<u8>, msglen: i64, sig: ptr<u8>, siglen: i64) -> i32 {
    var h: [u8; 64] = [0];
    var hp: ptr<u8> = null;
    unsafe { hp = &mut h[0] as ptr<u8>; }

    if (scheme == 0x0403 || scheme == 0x0804 || scheme == 0x0401) {
        sha256(msg, msglen, hp);
    } else if (scheme == 0x0503) {
        sha384(msg, msglen, hp);
    } else {
        return 0;
    }

    if (scheme == 0x0403) {
        var ek: EcKey = zero(EcKey);
        if (ec_load(&mut ek, spki, spki_len) != 0) {
            return 0;
        }
        let r: i32 = ecdsa_verify(&mut ek, hp, 32, sig, siglen);
        return r;
    }
    if (scheme == 0x0503) {
        var ek2: EcKey = zero(EcKey);
        if (ec_load(&mut ek2, spki, spki_len) != 0) {
            return 0;
        }
        let r2: i32 = ecdsa_verify(&mut ek2, hp, 48, sig, siglen);
        return r2;
    }

    var key: RsaKey = zero(RsaKey);
    if (rsa_load(spki, spki_len, &mut key) != 0) {
        return 0;
    }
    if (scheme == 0x0804) {
        let r3: i32 = rsa_pss_verify(&mut key, hp, 32, sig, siglen);
        return r3;
    }
    let r4: i32 = rsa_pkcs1_verify(&mut key, hp, 32, sig, siglen);
    return r4;
}

fn tls13_cert_verify_msg(t: &mut Tls13, out: &mut HxBuf) -> i32 {
    var i: i64 = 0;
    while (i < 64) {
        hxbuf_putc(out, 0x20);
        i += 1;
    }
    hxbuf_puts(out, "TLS 1.3, server CertificateVerify");
    hxbuf_putc(out, 0);
    var th: [u8; 32] = [0];
    var thp: ptr<u8> = null;
    unsafe { thp = &mut th[0] as ptr<u8>; }
    tls_transcript_hash(t, thp);
    return hxbuf_put(out, thp, 32);
}

fn tls13_handshake_keys(t: &mut Tls13, shared: ptr<u8>) -> i32 {
    var zero32: [u8; 32] = [0];
    var zp: ptr<u8> = null;
    unsafe { zp = &mut zero32[0] as ptr<u8>; }

    var empty_hash: [u8; 32] = [0];
    var ehp: ptr<u8> = null;
    unsafe { ehp = &mut empty_hash[0] as ptr<u8>; }
    sha256(zp, 0, ehp);

    var early: [u8; 32] = [0];
    var ep: ptr<u8> = null;
    unsafe { ep = &mut early[0] as ptr<u8>; }
    hkdf_extract(zp, 32, zp, 32, ep);

    var derived: [u8; 32] = [0];
    var dp: ptr<u8> = null;
    unsafe { dp = &mut derived[0] as ptr<u8>; }
    if (tls13_derive_secret(ep, "derived", ehp, dp) != 0) {
        return TLS_ERR;
    }

    var hsp: ptr<u8> = null;
    unsafe { hsp = &mut t.hs_secret[0] as ptr<u8>; }
    hkdf_extract(dp, 32, shared, 32, hsp);

    var th: [u8; 32] = [0];
    var thp: ptr<u8> = null;
    unsafe { thp = &mut th[0] as ptr<u8>; }
    tls_transcript_hash(t, thp);

    var cts: [u8; 32] = [0];
    var ctp: ptr<u8> = null;
    unsafe { ctp = &mut cts[0] as ptr<u8>; }
    if (tls13_derive_secret(hsp, "c hs traffic", thp, ctp) != 0) {
        return TLS_ERR;
    }
    tls_copy32(&mut t.c_hs_ts, ctp);
    if (tls_key_init(&mut t.c_hs, ctp) != 0) {
        return TLS_ERR;
    }

    var sts: [u8; 32] = [0];
    var stp: ptr<u8> = null;
    unsafe { stp = &mut sts[0] as ptr<u8>; }
    if (tls13_derive_secret(hsp, "s hs traffic", thp, stp) != 0) {
        return TLS_ERR;
    }
    tls_copy32(&mut t.s_hs_ts, stp);
    return tls_key_init(&mut t.s_hs, stp);
}

fn tls13_app_keys(t: &mut Tls13) -> i32 {
    var zero32: [u8; 32] = [0];
    var zp: ptr<u8> = null;
    unsafe { zp = &mut zero32[0] as ptr<u8>; }

    var empty_hash: [u8; 32] = [0];
    var ehp: ptr<u8> = null;
    unsafe { ehp = &mut empty_hash[0] as ptr<u8>; }
    sha256(zp, 0, ehp);

    var th: [u8; 32] = [0];
    var thp: ptr<u8> = null;
    unsafe { thp = &mut th[0] as ptr<u8>; }
    tls_transcript_hash(t, thp);

    var hsp: ptr<u8> = null;
    unsafe { hsp = &mut t.hs_secret[0] as ptr<u8>; }

    var derived: [u8; 32] = [0];
    var dp: ptr<u8> = null;
    unsafe { dp = &mut derived[0] as ptr<u8>; }
    if (tls13_derive_secret(hsp, "derived", ehp, dp) != 0) {
        return TLS_ERR;
    }

    var master: [u8; 32] = [0];
    var mp: ptr<u8> = null;
    unsafe { mp = &mut master[0] as ptr<u8>; }
    hkdf_extract(dp, 32, zp, 32, mp);

    var ck: [u8; 32] = [0];
    var ckp: ptr<u8> = null;
    unsafe { ckp = &mut ck[0] as ptr<u8>; }
    if (tls13_derive_secret(mp, "c ap traffic", thp, ckp) != 0) {
        return TLS_ERR;
    }
    tls_copy32(&mut t.c_ap_ts, ckp);
    if (tls_key_init(&mut t.c_ap, ckp) != 0) {
        return TLS_ERR;
    }

    var sk: [u8; 32] = [0];
    var skp: ptr<u8> = null;
    unsafe { skp = &mut sk[0] as ptr<u8>; }
    if (tls13_derive_secret(mp, "s ap traffic", thp, skp) != 0) {
        return TLS_ERR;
    }
    tls_copy32(&mut t.s_ap_ts, skp);
    return tls_key_init(&mut t.s_ap, skp);
}

fn tls13_finished_mac(traffic: ptr<u8>, th: ptr<u8>, out: ptr<u8>) -> i32 {
    var fk: [u8; 32] = [0];
    var fkp: ptr<u8> = null;
    unsafe { fkp = &mut fk[0] as ptr<u8>; }
    if (tls13_expand_label(traffic, 32, "finished", null, 0, fkp, 32) != 0) {
        return TLS_ERR;
    }
    hmac_sha256(fkp, 32, th, 32, out);
    return TLS_OK;
}

fn tls13_alpn_eq(t: &mut Tls13, s: ptr<u8>, n: i64) -> i32 {
    if (t.alpn_len != n) {
        return 0;
    }
    var i: i64 = 0;
    while (i < n) {
        if (t.alpn[i] != rt_byte(s, i)) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn tls13_alpn_ok(t: &mut Tls13) -> i32 {
    if (t.alpn_len == 0) {
        if (t.alpn_mode == 2) {
            return 0;
        }
        return 1;
    }
    if (t.alpn_mode == 1) {
        return tls13_alpn_eq(t, "http/1.1", 8);
    }
    if (t.alpn_mode == 2) {
        return tls13_alpn_eq(t, "h2", 2);
    }
    return 1;
}

fn tls13_read_encrypted(t: &mut Tls13, host: ptr<u8>) -> i32 {
    var have_leaf: i32 = 0;
    var leaf_off: i64 = 0;
    var leaf_len: i64 = 0;
    var leaf_ok: i32 = 0;
    var step: i32 = 0;

    var running: i32 = 1;
    while (running == 1) {
        let ty: i32 = tls_hs_next(t);
        if (ty < 0) {
            return TLS_ERR;
        }

        if (ty == TLS_HS_ENCRYPTED_EXT) {
            if (step != 0) {
                return TLS_ERR;
            }
            let bl: i64 = tls_hs_body_len(t);
            var bp: ptr<u8> = null;
            unsafe { bp = t.hand.p + 4; }
            if (bl < 2) {
                return TLS_ERR;
            }
            let el: i64 = tls_rd16(bp, 0);
            var off: i64 = 2;
            var i: i64 = 0;
            while (i < el) {
                if (off + i + 4 > bl) {
                    return TLS_ERR;
                }
                let et: i64 = tls_rd16(bp, off + i);
                let ln: i64 = tls_rd16(bp, off + i + 2);
                let data: i64 = off + i + 4;
                if (data + ln > bl) {
                    return TLS_ERR;
                }
                if (et == 0x0010 && ln >= 5) {
                    let listlen: i64 = tls_rd16(bp, data);
                    if (2 + listlen <= ln && listlen >= 3) {
                        let nlen: u8 = rt_byte(bp, data + 2);
                        if (3 + (nlen as i64) <= ln && nlen < 16) {
                            var k: i64 = 0;
                            while (k < (nlen as i64)) {
                                t.alpn[k] = rt_byte(bp, data + 3 + k);
                                k += 1;
                            }
                            t.alpn_len = nlen as i64;
                        }
                    }
                }
                i += 4 + ln;
            }
            if (tls13_alpn_ok(t) != 1) {
                return TLS_ERR;
            }
            if (tls_hs_commit(t) != TLS_OK) {
                return TLS_ERR;
            }
            step = 1;
        } else if (ty == TLS_HS_CERTIFICATE) {
            if (step != 1) {
                return TLS_ERR;
            }
            let bl: i64 = tls_hs_body_len(t);
            var bp: ptr<u8> = null;
            unsafe { bp = t.hand.p + 4; }
            if (bl < 4) {
                return TLS_ERR;
            }
            var off: i64 = 0;
            let ctx: u8 = rt_byte(bp, off);
            off += 1 + (ctx as i64);
            if (off + 3 > bl) {
                return TLS_ERR;
            }
            let list: i64 = tls_rd24(bp, off);
            off += 3;
            if (off + list > bl) {
                return TLS_ERR;
            }
            t.certs.len = 0;
            t.cn = 0;
            var end: i64 = off + list;
            while (off + 3 <= end) {
                let cl: i64 = tls_rd24(bp, off);
                off += 3;
                if (off + cl > end || cl <= 0) {
                    return TLS_ERR;
                }
                if (t.cn < TLS_MAX_CHAIN) {
                    var der: ptr<u8> = null;
                    unsafe { der = bp + off; }
                    let where: i64 = t.certs.len;
                    if (hxbuf_put(&mut t.certs, der, cl) != 0) {
                        return TLS_ERR;
                    }
                    let slot: i64 = t.cn;
                    t.coff[slot] = where;
                    t.clens[slot] = cl;
                    if (slot == 0) {
                        leaf_len = cl;
                        have_leaf = 1;
                    }
                    t.cn += 1;
                }
                off += cl;
                if (off + 2 > end) {
                    return TLS_ERR;
                }
                let exl: i64 = tls_rd16(bp, off);
                off += 2 + exl;
            }
            if (tls_hs_commit(t) != TLS_OK) {
                return TLS_ERR;
            }
            step = 2;
        } else if (ty == TLS_HS_CERT_VERIFY) {
            if (step != 2 || have_leaf != 1) {
                return TLS_ERR;
            }
            let bl: i64 = tls_hs_body_len(t);
            var bp: ptr<u8> = null;
            unsafe { bp = t.hand.p + 4; }
            if (bl < 4) {
                return TLS_ERR;
            }
            let scheme: i64 = tls_rd16(bp, 0);
            let siglen: i64 = tls_rd16(bp, 2);
            if (4 + siglen > bl) {
                return TLS_ERR;
            }

            var msg: HxBuf = hxbuf_new(192);
            if (msg.p == null) {
                return TLS_ERR;
            }
            if (tls13_cert_verify_msg(t, &mut msg) != TLS_OK) {
                hxbuf_free(&mut msg);
                return TLS_ERR;
            }

            var leaf: X509 = zero(X509);
            if (x509_parse(&mut leaf, t.certs.p, leaf_len) != 0) {
                hxbuf_free(&mut msg);
                return TLS_ERR;
            }
            var sp: ptr<u8> = null;
            unsafe { sp = t.certs.p + leaf.spki_off; }
            var sig: ptr<u8> = null;
            unsafe { sig = bp + 4; }
            let okv: i32 = tls13_verify_scheme(sp, leaf.spki_len, scheme, msg.p, msg.len, sig, siglen);
            hxbuf_free(&mut msg);
            if (okv != 1) {
                return TLS_ERR;
            }

            let now: i64 = rt_time();
            if (x509_leaf_ok(&mut leaf, now) != 1) {
                return TLS_ERR;
            }
            if (x509_check_host(&mut leaf, host, rt_len(host)) != 1) {
                return TLS_ERR;
            }
            leaf_ok = 1;

            if (tls_hs_commit(t) != TLS_OK) {
                return TLS_ERR;
            }
            step = 3;
        } else if (ty == TLS_HS_FINISHED) {
            if (step != 3 || leaf_ok != 1) {
                return TLS_ERR;
            }
            let bl: i64 = tls_hs_body_len(t);
            if (bl != 32) {
                return TLS_ERR;
            }

            var th: [u8; 32] = [0];
            var thp: ptr<u8> = null;
            unsafe { thp = &mut th[0] as ptr<u8>; }
            tls_transcript_hash(t, thp);

            var want: [u8; 32] = [0];
            var wp: ptr<u8> = null;
            unsafe { wp = &mut want[0] as ptr<u8>; }
            var stp: ptr<u8> = null;
            unsafe { stp = &mut t.s_hs_ts[0] as ptr<u8>; }
            if (tls13_finished_mac(stp, thp, wp) != TLS_OK) {
                return TLS_ERR;
            }
            var got: ptr<u8> = null;
            unsafe { got = t.hand.p + 4; }
            if (rt_ct_eq(got, wp, 32) != 1) {
                return TLS_ERR;
            }

            if (tls_hs_commit(t) != TLS_OK) {
                return TLS_ERR;
            }
            running = 0;
        } else {
            return TLS_ERR;
        }
    }

    var cbase: ptr<u8> = null;
    unsafe { cbase = t.certs.p; }
    x509_chain_init(&mut t.chain, cbase);
    var i: i64 = 0;
    while (i < t.cn) {
        let o: i64 = t.coff[i];
        let n: i64 = t.clens[i];
        if (n <= 0) {
            return TLS_ERR;
        }
        if (x509_chain_add(&mut t.chain, o, n) != 0) {
            return TLS_ERR;
        }
        i += 1;
    }
    return leaf_ok;
}

fn tls13_cleanup(t: &mut Tls13) {
    hxbuf_free(&mut t.tr);
    hxbuf_free(&mut t.hand);
    hxbuf_free(&mut t.inb);
    hxbuf_free(&mut t.certs);
    t.closed = 1;
}

fn tls13_connect(t: &mut Tls13, sock: u64, host: ptr<u8>) -> i32 {
    t.sock = sock;
    t.phase = 0;
    t.closed = 0;
    t.cn = 0;
    t.alpn_len = 0;
    t.ro = 0;
    t.tr = hxbuf_new(4096);
    t.hand = hxbuf_new(4096);
    t.inb = hxbuf_new(4096);
    t.certs = hxbuf_new(4096);
    if (t.tr.p == null || t.hand.p == null || t.inb.p == null || t.certs.p == null) {
        return TLS_ERR;
    }

    var ch: HxBuf = hxbuf_new(512);
    if (ch.p == null) {
        return TLS_ERR;
    }
    if (tls13_client_hello(t, host, &mut ch) != TLS_OK) {
        hxbuf_free(&mut ch);
        return TLS_ERR;
    }
    hxbuf_put(&mut t.tr, ch.p, ch.len);

    var hdr: [u8; 5] = [0];
    var hp: ptr<u8> = null;
    unsafe {
        hp = &mut hdr[0] as ptr<u8>;
        hdr[0] = TLS_REC_HANDSHAKE as u8;
        hdr[1] = 3;
        hdr[2] = 1;
        hdr[3] = (((ch.len) >> 8) & 255) as u8;
        hdr[4] = ((ch.len) & 255) as u8;
    }
    if (hx_send(sock, hp, 5) != 5) {
        hxbuf_free(&mut ch);
        return TLS_ERR;
    }
    if (hx_send(sock, ch.p, ch.len) != ch.len) {
        hxbuf_free(&mut ch);
        return TLS_ERR;
    }
    hxbuf_free(&mut ch);

    let ty: i32 = tls_hs_next(t);
    if (ty != TLS_HS_SERVER_HELLO) {
        return TLS_ERR;
    }
    var hello: TlsHello = zero(TlsHello);
    if (tls13_parse_server_hello(t, &mut hello) != TLS_OK) {
        return TLS_ERR;
    }
    var server_pub: [u8; 32] = [0];
    var spp: ptr<u8> = null;
    unsafe { spp = &mut server_pub[0] as ptr<u8>; }
    var ksrc: ptr<u8> = null;
    unsafe { ksrc = t.hand.p + 4 + hello.ks_off; }
    rt_copy(spp, ksrc, 32);
    if (tls_hs_commit(t) != TLS_OK) {
        return TLS_ERR;
    }

    var shared: [u8; 32] = [0];
    var shp: ptr<u8> = null;
    unsafe { shp = &mut shared[0] as ptr<u8>; }
    var xp: ptr<u8> = null;
    unsafe { xp = &mut t.xpriv[0] as ptr<u8>; }
    if (x25519(shp, xp, spp) != 0) {
        return TLS_ERR;
    }
    if (tls13_handshake_keys(t, shp) != TLS_OK) {
        return TLS_ERR;
    }
    t.phase = 1;

    let leaf_ok: i32 = tls13_read_encrypted(t, host);
    if (leaf_ok != 1) {
        return TLS_ERR;
    }

    if (tls13_app_keys(t) != TLS_OK) {
        return TLS_ERR;
    }

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
        return TLS_ERR;
    }

    var fin: HxBuf = hxbuf_new(64);
    if (fin.p == null) {
        return TLS_ERR;
    }
    hxbuf_putc(&mut fin, TLS_HS_FINISHED as u8);
    tls_u24(&mut fin, 32);
    hxbuf_put(&mut fin, vp, 32);
    if (tls_write_record(t, 0, TLS_REC_HANDSHAKE, fin.p, fin.len) != TLS_OK) {
        hxbuf_free(&mut fin);
        return TLS_ERR;
    }
    hxbuf_put(&mut t.tr, fin.p, fin.len);
    hxbuf_free(&mut fin);

    t.phase = 2;
    t.inb.len = 0;
    t.ro = 0;
    t.hand.len = 0;
    return TLS_OK;
}

fn tls13_write(t: &mut Tls13, p: ptr<u8>, n: i64) -> i64 {
    if (t.phase != 2) {
        return TLS_ERR as i64;
    }
    if (n <= 0) {
        return 0;
    }
    var off: i64 = 0;
    while (off < n) {
        var chunk: i64 = n - off;
        if (chunk > 16384) {
            chunk = 16384;
        }
        var src: ptr<u8> = null;
        unsafe { src = p + off; }
        if (tls_write_record(t, 1, TLS_REC_APP, src, chunk) != TLS_OK) {
            return TLS_ERR as i64;
        }
        off += chunk;
    }
    return off;
}

fn tls13_read(t: &mut Tls13, out: ptr<u8>, cap: i64) -> i64 {
    if (cap <= 0) {
        return 0;
    }
    var guard: i32 = 0;
    while (t.ro >= t.inb.len) {
        if (t.closed == 1) {
            return 0;
        }
        if (t.phase != 2) {
            return TLS_ERR as i64;
        }
        let ct: i32 = tls_read_record(t);
        if (ct == TLS_REC_APP) {
            t.ro = 0;
        } else if (ct == TLS_REC_HANDSHAKE) {
            t.inb.len = 0;
            t.ro = 0;
        } else if (ct == TLS_REC_ALERT) {
            t.closed = 1;
            return 0;
        } else {
            return TLS_ERR as i64;
        }
        guard += 1;
        if (guard > 64) {
            return TLS_ERR as i64;
        }
    }
    var n: i64 = t.inb.len - t.ro;
    if (n > cap) {
        n = cap;
    }
    var src: ptr<u8> = null;
    unsafe { src = t.inb.p + t.ro; }
    rt_copy(out, src, n);
    t.ro += n;
    return n;
}

fn tls13_close(t: &mut Tls13) {
    if (t.phase == 2 && t.closed == 0) {
        var alert: [u8; 2] = [0];
        alert[0] = 1;
        alert[1] = 0;
        var ap: ptr<u8> = null;
        unsafe { ap = &mut alert[0] as ptr<u8>; }
        tls_write_record(t, 1, TLS_REC_ALERT, ap, 2);
    }
    tls13_cleanup(t);
}
