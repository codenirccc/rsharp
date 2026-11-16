include "rt.rsx";
include "der.rsx";
include "bignum.rsx";
include "sha1.rsx";
include "sha256.rsx";
include "sha512.rsx";
include "rsa.rsx";
include "ec.rsx";

const X509_MAX_CHAIN: i64 = 8;

const X509_GN_DNS: u8 = 130;
const X509_GN_IP: u8 = 135;
const X509_TAG_EXTENSIONS: u8 = 163;

struct X509 {
    p: ptr<u8>,
    len: i64,
    ok: i32,
    tbs_off: i64,
    tbs_len: i64,
    sig_off: i64,
    sig_len: i64,
    alg_off: i64,
    alg_len: i64,
    issuer_off: i64,
    issuer_len: i64,
    subject_off: i64,
    subject_len: i64,
    spki_off: i64,
    spki_len: i64,
    ext_off: i64,
    ext_len: i64,
    nb: i64,
    na: i64
}

struct X509Chain {
    buf: ptr<u8>,
    off: [i64; 8],
    size: [i64; 8],
    n: i64
}

fn x509_ascii_lc(b: u8) -> u8 {
    if (b >= 65 && b <= 90) {
        return (b + 32) as u8;
    }
    return b;
}

fn x509_case_eq(a: ptr<u8>, b: ptr<u8>, n: i64) -> i32 {
    var i: i64 = 0;
    while (i < n) {
        var x: u8 = 0;
        var y: u8 = 0;
        unsafe {
            x = a[i];
            y = b[i];
        }
        if (x509_ascii_lc(x) != x509_ascii_lc(y)) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn x509_oid_eq(p: ptr<u8>, len: i64, hex: ptr<u8>) -> i32 {
    var b: [u8; 16] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut b[0] as ptr<u8>; }
    let n: i64 = rt_parse_hex(hex, bp, 16);
    if (n != len) {
        return 0;
    }
    return rt_bytes_eq(p, bp, n);
}

fn x509_oid_is(t: &mut Tlv, hex: ptr<u8>) -> i32 {
    if (t.tag != DER_TAG_OID) {
        return 0;
    }
    return x509_oid_eq(t.p, t.len, hex);
}

fn x509_dns_match(pat: ptr<u8>, plen: i64, host: ptr<u8>, hlen: i64) -> i32 {
    if (plen <= 0 || hlen <= 0) {
        return 0;
    }
    if (plen > 2) {
        var c0: u8 = 0;
        var c1: u8 = 0;
        unsafe {
            c0 = pat[0];
            c1 = pat[1];
        }
        if (c0 == 42 && c1 == 46) {
            var i: i64 = 0;
            var dotat: i64 = -1;
            while (i < hlen) {
                var b: u8 = 0;
                unsafe { b = host[i]; }
                if (b == 46 && dotat < 0) {
                    dotat = i;
                }
                i += 1;
            }
            if (dotat <= 0) {
                return 0;
            }
            let rest: i64 = hlen - dotat - 1;
            let prest: i64 = plen - 2;
            if (rest != prest || rest <= 0) {
                return 0;
            }
            return x509_case_eq(rt_add(pat, 2), rt_add(host, dotat + 1), rest);
        }
    }
    if (plen != hlen) {
        return 0;
    }
    return x509_case_eq(pat, host, plen);
}

fn x509_ipv4_parse(s: ptr<u8>, n: i64, out: ptr<u8>) -> i32 {
    if (n < 7 || n > 15) {
        return 0;
    }
    var val: i64 = 0;
    var digits: i64 = 0;
    var octets: i64 = 0;
    var i: i64 = 0;
    while (i < n) {
        var ch: u8 = 0;
        unsafe { ch = s[i]; }
        if (ch == 46) {
            if (digits == 0 || octets >= 3) {
                return 0;
            }
            rt_setbyte(out, octets, val as u8);
            octets += 1;
            val = 0;
            digits = 0;
        } else if (ch >= 48 && ch <= 57) {
            val = val * 10 + ((ch - 48) as i64);
            digits += 1;
            if (digits > 3 || val > 255) {
                return 0;
            }
        } else {
            return 0;
        }
        i += 1;
    }
    if (digits == 0 || octets != 3) {
        return 0;
    }
    rt_setbyte(out, 3, val as u8);
    return 1;
}

fn x509_parse(c: &mut X509, p: ptr<u8>, len: i64) -> i32 {
    c.p = p;
    c.len = 0;
    c.ok = 0;
    c.tbs_off = 0;
    c.tbs_len = 0;
    c.sig_off = 0;
    c.sig_len = 0;
    c.alg_off = 0;
    c.alg_len = 0;
    c.issuer_off = 0;
    c.issuer_len = 0;
    c.subject_off = 0;
    c.subject_len = 0;
    c.spki_off = 0;
    c.spki_len = 0;
    c.ext_off = 0;
    c.ext_len = 0;
    c.nb = 0;
    c.na = 0;

    var d: Der = zero(Der);
    der_init(&mut d, p, len);
    var cert: Tlv = zero(Tlv);
    if (der_expect(&mut d, DER_TAG_SEQUENCE, &mut cert) != 0) {
        return -1;
    }
    if (cert.hdr + cert.len != len) {
        return -1;
    }

    var cd: Der = zero(Der);
    der_sub(&mut cert, &mut cd);

    var tbs: Tlv = zero(Tlv);
    if (der_next(&mut cd, &mut tbs) != 0) {
        return -1;
    }
    if (tbs.tag != DER_TAG_SEQUENCE) {
        return -1;
    }
    c.tbs_off = cert.hdr + tbs.start;
    c.tbs_len = tbs.hdr + tbs.len;

    var salg: Tlv = zero(Tlv);
    if (der_next(&mut cd, &mut salg) != 0) {
        return -1;
    }
    if (salg.tag != DER_TAG_SEQUENCE) {
        return -1;
    }
    var sd: Der = zero(Der);
    der_sub(&mut salg, &mut sd);
    var alg: Tlv = zero(Tlv);
    if (der_expect(&mut sd, DER_TAG_OID, &mut alg) != 0) {
        return -1;
    }
    c.alg_off = cert.hdr + salg.start + salg.hdr + alg.start + alg.hdr;
    c.alg_len = alg.len;

    var sig: Tlv = zero(Tlv);
    if (der_next(&mut cd, &mut sig) != 0) {
        return -1;
    }
    if (sig.tag != DER_TAG_BITSTRING || sig.len < 2) {
        return -1;
    }
    var unused: u8 = 0;
    unsafe { unused = sig.p[0]; }
    if (unused != 0) {
        return -1;
    }
    c.sig_off = cert.hdr + sig.start + sig.hdr + 1;
    c.sig_len = sig.len - 1;

    var td: Der = zero(Der);
    der_sub(&mut tbs, &mut td);
    let tbase: i64 = c.tbs_off + tbs.hdr;

    var t: Tlv = zero(Tlv);
    if (der_peek(&mut td, &mut t) != 0) {
        return -1;
    }
    if (t.tag == 160) {
        if (der_skip(&mut td) != 0) {
            return -1;
        }
    }
    if (der_expect(&mut td, DER_TAG_INTEGER, &mut t) != 0) {
        return -1;
    }

    var ialg: Tlv = zero(Tlv);
    if (der_expect(&mut td, DER_TAG_SEQUENCE, &mut ialg) != 0) {
        return -1;
    }
    var iad: Der = zero(Der);
    der_sub(&mut ialg, &mut iad);
    var iaoid: Tlv = zero(Tlv);
    if (der_expect(&mut iad, DER_TAG_OID, &mut iaoid) != 0) {
        return -1;
    }
    if (iaoid.len != c.alg_len) {
        return -1;
    }
    if (rt_bytes_eq(iaoid.p, rt_add(c.p, c.alg_off), c.alg_len) != 1) {
        return -1;
    }

    if (der_expect(&mut td, DER_TAG_SEQUENCE, &mut t) != 0) {
        return -1;
    }
    c.issuer_off = tbase + t.start;
    c.issuer_len = t.hdr + t.len;

    var val: Tlv = zero(Tlv);
    if (der_expect(&mut td, DER_TAG_SEQUENCE, &mut val) != 0) {
        return -1;
    }
    var vd: Der = zero(Der);
    der_sub(&mut val, &mut vd);
    var nbt: Tlv = zero(Tlv);
    var nat: Tlv = zero(Tlv);
    if (der_next(&mut vd, &mut nbt) != 0) {
        return -1;
    }
    if (der_next(&mut vd, &mut nat) != 0) {
        return -1;
    }
    c.nb = der_time(&mut nbt);
    c.na = der_time(&mut nat);
    if (c.nb < 0 || c.na < 0) {
        return -1;
    }

    if (der_expect(&mut td, DER_TAG_SEQUENCE, &mut t) != 0) {
        return -1;
    }
    c.subject_off = tbase + t.start;
    c.subject_len = t.hdr + t.len;

    if (der_expect(&mut td, DER_TAG_SEQUENCE, &mut t) != 0) {
        return -1;
    }
    c.spki_off = tbase + t.start;
    c.spki_len = t.hdr + t.len;

    while (der_peek(&mut td, &mut t) == 0) {
        if (t.tag == X509_TAG_EXTENSIONS) {
            c.ext_off = tbase + t.start + t.hdr;
            c.ext_len = t.len;
        }
        if (der_skip(&mut td) != 0) {
            return -1;
        }
    }

    c.len = len;
    c.ok = 1;
    return 0;
}

fn x509_ext_find(c: &mut X509, hex: ptr<u8>, out: &mut Tlv) -> i32 {
    if (c.ok != 1 || c.ext_len <= 0) {
        return -1;
    }
    var d: Der = zero(Der);
    der_init(&mut d, rt_add(c.p, c.ext_off), c.ext_len);
    var seq: Tlv = zero(Tlv);
    if (der_expect(&mut d, DER_TAG_SEQUENCE, &mut seq) != 0) {
        return -1;
    }
    var sd: Der = zero(Der);
    der_sub(&mut seq, &mut sd);
    var ext: Tlv = zero(Tlv);
    while (der_next(&mut sd, &mut ext) == 0) {
        if (ext.tag != DER_TAG_SEQUENCE) {
            return -1;
        }
        var ed: Der = zero(Der);
        der_sub(&mut ext, &mut ed);
        var oid: Tlv = zero(Tlv);
        if (der_next(&mut ed, &mut oid) != 0) {
            return -1;
        }
        var v: Tlv = zero(Tlv);
        if (der_peek(&mut ed, &mut v) != 0) {
            return -1;
        }
        if (v.tag == DER_TAG_BOOLEAN) {
            if (der_skip(&mut ed) != 0) {
                return -1;
            }
        }
        if (der_next(&mut ed, &mut v) != 0) {
            return -1;
        }
        if (v.tag != DER_TAG_OCTETSTRING) {
            return -1;
        }
        if (x509_oid_is(&mut oid, hex) == 1) {
            out.tag = v.tag;
            out.p = v.p;
            out.len = v.len;
            out.start = 0;
            out.hdr = 0;
            return 0;
        }
    }
    return -1;
}

fn x509_is_ca(c: &mut X509) -> i32 {
    var v: Tlv = zero(Tlv);
    if (x509_ext_find(c, "551d13", &mut v) != 0) {
        return 0;
    }
    var d: Der = zero(Der);
    der_init(&mut d, v.p, v.len);
    var seq: Tlv = zero(Tlv);
    if (der_expect(&mut d, DER_TAG_SEQUENCE, &mut seq) != 0) {
        return 0;
    }
    var sd: Der = zero(Der);
    der_sub(&mut seq, &mut sd);
    var b: Tlv = zero(Tlv);
    if (der_peek(&mut sd, &mut b) != 0) {
        return 0;
    }
    if (b.tag != DER_TAG_BOOLEAN || b.len != 1) {
        return 0;
    }
    var x: u8 = 0;
    unsafe { x = b.p[0]; }
    if (x != 0) {
        return 1;
    }
    return 0;
}

fn x509_ku_bit(c: &mut X509, bit: i64) -> i32 {
    var v: Tlv = zero(Tlv);
    if (x509_ext_find(c, "551d0f", &mut v) != 0) {
        return -1;
    }
    var d: Der = zero(Der);
    der_init(&mut d, v.p, v.len);
    var bs: Tlv = zero(Tlv);
    if (der_expect(&mut d, DER_TAG_BITSTRING, &mut bs) != 0) {
        return -1;
    }
    if (bs.len < 1) {
        return -1;
    }
    let idx: i64 = bit / 8;
    if (idx >= bs.len - 1) {
        return 0;
    }
    var b: u8 = 0;
    unsafe { b = bs.p[1 + idx]; }
    let x: u32 = b as u32;
    let shift: u32 = (7 - (bit % 8)) as u32;
    if (((x >> shift) & 1) == 1) {
        return 1;
    }
    return 0;
}

fn x509_cn_match(c: &mut X509, host: ptr<u8>, hlen: i64) -> i32 {
    if (c.ok != 1) {
        return 0;
    }
    var d: Der = zero(Der);
    der_init(&mut d, rt_add(c.p, c.subject_off), c.subject_len);
    var name: Tlv = zero(Tlv);
    if (der_expect(&mut d, DER_TAG_SEQUENCE, &mut name) != 0) {
        return 0;
    }
    var nd: Der = zero(Der);
    der_sub(&mut name, &mut nd);
    var rdn: Tlv = zero(Tlv);
    while (der_next(&mut nd, &mut rdn) == 0) {
        var sd: Der = zero(Der);
        der_sub(&mut rdn, &mut sd);
        var atv: Tlv = zero(Tlv);
        while (der_next(&mut sd, &mut atv) == 0) {
            var ad: Der = zero(Der);
            der_sub(&mut atv, &mut ad);
            var oid: Tlv = zero(Tlv);
            var val: Tlv = zero(Tlv);
            if (der_next(&mut ad, &mut oid) != 0) {
                return 0;
            }
            if (der_next(&mut ad, &mut val) != 0) {
                return 0;
            }
            if (x509_oid_is(&mut oid, "550403") == 1) {
                return x509_dns_match(val.p, val.len, host, hlen);
            }
        }
    }
    return 0;
}

fn x509_check_host(c: &mut X509, host: ptr<u8>, hlen: i64) -> i32 {
    if (c.ok != 1) {
        return 0;
    }
    var v: Tlv = zero(Tlv);
    if (x509_ext_find(c, "551d11", &mut v) == 0) {
        var ip: [u8; 4] = [0];
        var ipp: ptr<u8> = null;
        unsafe { ipp = &mut ip[0] as ptr<u8>; }
        let isip: i32 = x509_ipv4_parse(host, hlen, ipp);

        var d: Der = zero(Der);
        der_init(&mut d, v.p, v.len);
        var seq: Tlv = zero(Tlv);
        if (der_expect(&mut d, DER_TAG_SEQUENCE, &mut seq) != 0) {
            return 0;
        }
        var sd: Der = zero(Der);
        der_sub(&mut seq, &mut sd);
        var gn: Tlv = zero(Tlv);
        var hit: i32 = 0;
        while (der_next(&mut sd, &mut gn) == 0) {
            if (gn.tag == X509_GN_DNS) {
                if (x509_dns_match(gn.p, gn.len, host, hlen) == 1) {
                    hit = 1;
                }
            } else if (gn.tag == X509_GN_IP && isip == 1) {
                if (gn.len == 4 && rt_bytes_eq(gn.p, ipp, 4) == 1) {
                    hit = 1;
                }
            }
        }
        return hit;
    }
    return x509_cn_match(c, host, hlen);
}

fn x509_valid_at(c: &mut X509, now: i64) -> i32 {
    if (c.ok != 1) {
        return 0;
    }
    if (now < c.nb) {
        return 0;
    }
    if (now > c.na) {
        return 0;
    }
    return 1;
}

fn x509_fingerprint(c: &mut X509, out: ptr<u8>) -> i32 {
    if (c.ok != 1) {
        return -1;
    }
    sha256(c.p, c.len, out);
    return 0;
}

fn x509_sig_hash(c: &mut X509, out: ptr<u8>) -> i64 {
    let tp: ptr<u8> = rt_add(c.p, c.tbs_off);
    let op: ptr<u8> = rt_add(c.p, c.alg_off);
    if (x509_oid_eq(op, c.alg_len, "2a864886f70d01010b") == 1) { sha256(tp, c.tbs_len, out); return 32; }
    if (x509_oid_eq(op, c.alg_len, "2a864886f70d010105") == 1) { sha1(tp, c.tbs_len, out); return 20; }
    if (x509_oid_eq(op, c.alg_len, "2a864886f70d01010c") == 1) { sha384(tp, c.tbs_len, out); return 48; }
    if (x509_oid_eq(op, c.alg_len, "2a864886f70d01010d") == 1) { sha512(tp, c.tbs_len, out); return 64; }
    if (x509_oid_eq(op, c.alg_len, "2a864886f70d01010a") == 1) { sha256(tp, c.tbs_len, out); return 32; }
    if (x509_oid_eq(op, c.alg_len, "2a8648ce3d040301") == 1) { sha1(tp, c.tbs_len, out); return 20; }
    if (x509_oid_eq(op, c.alg_len, "2a8648ce3d040302") == 1) { sha256(tp, c.tbs_len, out); return 32; }
    if (x509_oid_eq(op, c.alg_len, "2a8648ce3d040303") == 1) { sha384(tp, c.tbs_len, out); return 48; }
    if (x509_oid_eq(op, c.alg_len, "2a8648ce3d040304") == 1) { sha512(tp, c.tbs_len, out); return 64; }
    return -1;
}

fn x509_is_ecdsa(c: &mut X509) -> i32 {
    let op: ptr<u8> = rt_add(c.p, c.alg_off);
    if (x509_oid_eq(op, c.alg_len, "2a8648ce3d040301") == 1) { return 1; }
    if (x509_oid_eq(op, c.alg_len, "2a8648ce3d040302") == 1) { return 1; }
    if (x509_oid_eq(op, c.alg_len, "2a8648ce3d040303") == 1) { return 1; }
    if (x509_oid_eq(op, c.alg_len, "2a8648ce3d040304") == 1) { return 1; }
    return 0;
}

fn x509_is_pss(c: &mut X509) -> i32 {
    let op: ptr<u8> = rt_add(c.p, c.alg_off);
    return x509_oid_eq(op, c.alg_len, "2a864886f70d01010a");
}

fn x509_verify_sig(c: &mut X509, issuer: &mut X509) -> i32 {
    if (c.ok != 1 || issuer.ok != 1) {
        return 0;
    }
    var h: [u8; 64] = [0];
    var hp: ptr<u8> = null;
    unsafe { hp = &mut h[0] as ptr<u8>; }
    let hlen: i64 = x509_sig_hash(c, hp);
    if (hlen < 1) {
        return 0;
    }
    let sp: ptr<u8> = rt_add(issuer.p, issuer.spki_off);
    let sig: ptr<u8> = rt_add(c.p, c.sig_off);

    if (x509_is_ecdsa(c) == 1) {
        var ek: EcKey = zero(EcKey);
        if (ec_load(&mut ek, sp, issuer.spki_len) != 0) {
            return 0;
        }
        let r: i32 = ecdsa_verify(&mut ek, hp, hlen, sig, c.sig_len);
        return r;
    }

    var key: RsaKey = zero(RsaKey);
    if (rsa_load(sp, issuer.spki_len, &mut key) != 0) {
        return 0;
    }
    if (x509_is_pss(c) == 1) {
        let rp: i32 = rsa_pss_verify(&mut key, hp, hlen, sig, c.sig_len);
        return rp;
    }
    let rv: i32 = rsa_pkcs1_verify(&mut key, hp, hlen, sig, c.sig_len);
    return rv;
}

fn x509_name_matches(child: &mut X509, issuer: &mut X509) -> i32 {
    if (child.ok != 1 || issuer.ok != 1) {
        return 0;
    }
    if (child.issuer_len != issuer.subject_len) {
        return 0;
    }
    return rt_bytes_eq(rt_add(child.p, child.issuer_off), rt_add(issuer.p, issuer.subject_off), child.issuer_len);
}

fn x509_signed_by(child: &mut X509, issuer: &mut X509, now: i64) -> i32 {
    if (child.ok != 1 || issuer.ok != 1) {
        return 0;
    }
    if (x509_name_matches(child, issuer) != 1) {
        return 0;
    }
    if (x509_valid_at(issuer, now) != 1) {
        return 0;
    }
    if (x509_is_ca(issuer) != 1) {
        return 0;
    }
    if (x509_ku_bit(issuer, 5) == 0) {
        return 0;
    }
    let r: i32 = x509_verify_sig(child, issuer);
    return r;
}

fn x509_leaf_ok(c: &mut X509, now: i64) -> i32 {
    if (x509_valid_at(c, now) != 1) {
        return 0;
    }
    if (x509_ku_bit(c, 0) == 0) {
        return 0;
    }
    return 1;
}

fn x509_chain_init(ch: &mut X509Chain, buf: ptr<u8>) {
    ch.buf = buf;
    ch.n = 0;
    var i: i64 = 0;
    while (i < X509_MAX_CHAIN) {
        ch.off[i] = 0;
        ch.size[i] = 0;
        i += 1;
    }
}

fn x509_chain_add(ch: &mut X509Chain, off: i64, size: i64) -> i32 {
    if (ch.n >= X509_MAX_CHAIN || size <= 0) {
        return -1;
    }
    ch.off[ch.n] = off;
    ch.size[ch.n] = size;
    ch.n += 1;
    return 0;
}

fn x509_chain_parse(ch: &mut X509Chain, i: i64, c: &mut X509) -> i32 {
    if (i < 0 || i >= ch.n) {
        return -1;
    }
    return x509_parse(c, rt_add(ch.buf, ch.off[i]), ch.size[i]);
}

fn x509_chain_verify(ch: &mut X509Chain, anchor: ptr<u8>, anchor_len: i64, host: ptr<u8>, hlen: i64, now: i64) -> i32 {
    if (ch.n < 1) {
        return 0;
    }

    var leaf: X509 = zero(X509);
    if (x509_chain_parse(ch, 0, &mut leaf) != 0) {
        return 0;
    }
    if (x509_leaf_ok(&mut leaf, now) != 1) {
        return 0;
    }
    if (x509_check_host(&mut leaf, host, hlen) != 1) {
        return 0;
    }

    var i: i64 = 1;
    while (i < ch.n) {
        var child: X509 = zero(X509);
        var parent: X509 = zero(X509);
        if (x509_chain_parse(ch, i - 1, &mut child) != 0) {
            return 0;
        }
        if (x509_chain_parse(ch, i, &mut parent) != 0) {
            return 0;
        }
        if (x509_signed_by(&mut child, &mut parent, now) != 1) {
            return 0;
        }
        i += 1;
    }

    var top: X509 = zero(X509);
    var root: X509 = zero(X509);
    if (x509_chain_parse(ch, ch.n - 1, &mut top) != 0) {
        return 0;
    }
    if (x509_parse(&mut root, anchor, anchor_len) != 0) {
        return 0;
    }
    let r: i32 = x509_signed_by(&mut top, &mut root, now);
    return r;
}
