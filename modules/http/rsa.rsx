include "rt.rsx";
include "der.rsx";
include "bignum.rsx";
include "sha256.rsx";

const RSA_MAX_BYTES: i64 = 512;

struct RsaKey {
    n: Bn,
    e: Bn,
    nbytes: i64
}

fn rsa_load(pub_der: ptr<u8>, len: i64, key: &mut RsaKey) -> i32 {
    var d: Der = zero(Der);
    der_init(&mut d, pub_der, len);
    var seq: Tlv = zero(Tlv);
    if (der_expect(&mut d, DER_TAG_SEQUENCE, &mut seq) != 0) {
        return -1;
    }
    var sd: Der = zero(Der);
    der_sub(&mut seq, &mut sd);

    var first: Tlv = zero(Tlv);
    if (der_next(&mut sd, &mut first) != 0) {
        return -1;
    }
    if (first.tag == DER_TAG_SEQUENCE) {
        var bits: Tlv = zero(Tlv);
        if (der_next(&mut sd, &mut bits) != 0) {
            return -1;
        }
        if (bits.tag != DER_TAG_BITSTRING || bits.len < 2) {
            return -1;
        }
        var rd: Der = zero(Der);
        der_init(&mut rd, rt_add(bits.p, 1), bits.len - 1);
        var inner: Tlv = zero(Tlv);
        if (der_expect(&mut rd, DER_TAG_SEQUENCE, &mut inner) != 0) {
            return -1;
        }
        der_sub(&mut inner, &mut sd);
        if (der_next(&mut sd, &mut first) != 0) {
            return -1;
        }
    }

    var modbuf: [u8; RSA_MAX_BYTES] = [0];
    var mp: ptr<u8> = null;
    unsafe { mp = &mut modbuf[0] as ptr<u8>; }
    let nlen: i64 = der_uint(&mut first, mp, RSA_MAX_BYTES);
    if (nlen < 64 || nlen > RSA_MAX_BYTES) {
        return -1;
    }
    bn_from_be(&mut key.n, mp, nlen);
    key.nbytes = nlen;

    var exp_t: Tlv = zero(Tlv);
    if (der_next(&mut sd, &mut exp_t) != 0) {
        return -1;
    }
    if (exp_t.tag != DER_TAG_INTEGER || exp_t.len <= 0 || exp_t.len > 8) {
        return -1;
    }
    var ev: u64 = 0;
    var i: i64 = 0;
    while (i < exp_t.len) {
        var b: u8 = 0;
        unsafe { b = exp_t.p[i]; }
        ev = (ev << 8) | (b as u64);
        i += 1;
    }
    bn_set_u64(&mut key.e, ev);
    if (bn_bitlen(&mut key.e) < 1) {
        return -1;
    }
    return 0;
}

fn rsa_pow(key: &mut RsaKey, sig: ptr<u8>, siglen: i64, out: ptr<u8>, outlen: i64) -> i32 {
    if (outlen > RSA_MAX_BYTES || outlen < 64) {
        return -1;
    }
    if (siglen <= 0 || siglen > outlen) {
        return -1;
    }
    var sb: [u8; RSA_MAX_BYTES] = [0];
    var sp: ptr<u8> = null;
    unsafe { sp = &mut sb[0] as ptr<u8>; }
    rt_zero(sp, outlen);
    rt_copy(rt_add(sp, outlen - siglen), sig, siglen);

    var s: Bn = zero(Bn);
    var n: Bn = zero(Bn);
    var e: Bn = zero(Bn);
    var r: Bn = zero(Bn);
    bn_from_be(&mut s, sp, outlen);
    bn_copy(&mut n, &mut key.n);
    bn_copy(&mut e, &mut key.e);
    if (bn_cmp(&mut s, &mut n) >= 0) {
        return -1;
    }
    if (bn_modexp(&mut r, &mut s, &mut e, &mut n) != 0) {
        return -1;
    }
    bn_to_be(&mut r, out, outlen);
    return 0;
}

fn rsa_digest_info_prefix(hlen: i64, out: ptr<u8>) -> i64 {
    if (hlen == 20) {
        return rt_parse_hex("3021300906052b0e03021a05000414", out, 32);
    }
    if (hlen == 32) {
        return rt_parse_hex("3031300d060960864801650304020105000420", out, 32);
    }
    if (hlen == 48) {
        return rt_parse_hex("3041300d060960864801650304020205000430", out, 32);
    }
    if (hlen == 64) {
        return rt_parse_hex("3051300d060960864801650304020305000440", out, 32);
    }
    return -1;
}

fn rsa_pkcs1_verify(key: &mut RsaKey, hash: ptr<u8>, hlen: i64, sig: ptr<u8>, siglen: i64) -> i32 {
    let k: i64 = key.nbytes;
    if (k > RSA_MAX_BYTES || k < 64) {
        return 0;
    }
    var pre: [u8; 32] = [0];
    var pp: ptr<u8> = null;
    unsafe { pp = &mut pre[0] as ptr<u8>; }
    let pren: i64 = rsa_digest_info_prefix(hlen, pp);
    if (pren <= 0) {
        return 0;
    }
    let dil: i64 = pren + hlen;
    if (k < dil + 11) {
        return 0;
    }

    var em: [u8; RSA_MAX_BYTES] = [0];
    var emp: ptr<u8> = null;
    unsafe { emp = &mut em[0] as ptr<u8>; }
    if (rsa_pow(key, sig, siglen, emp, k) != 0) {
        return 0;
    }

    if (rt_byte(emp, 0) != 0) {
        return 0;
    }
    if (rt_byte(emp, 1) != 1) {
        return 0;
    }
    let ps: i64 = k - dil - 3;
    var i: i64 = 0;
    while (i < ps) {
        if (rt_byte(emp, 2 + i) != 255) {
            return 0;
        }
        i += 1;
    }
    if (rt_byte(emp, 2 + ps) != 0) {
        return 0;
    }

    var di: [u8; 96] = [0];
    var dip: ptr<u8> = null;
    unsafe { dip = &mut di[0] as ptr<u8>; }
    rt_copy(dip, pp, pren);
    rt_copy(rt_add(dip, pren), hash, hlen);
    if (rt_bytes_eq(rt_add(emp, k - dil), dip, dil) != 1) {
        return 0;
    }
    return 1;
}

fn rsa_mgf1_sha256(seed: ptr<u8>, seedlen: i64, mask: ptr<u8>, masklen: i64) -> i32 {
    var counter: [u8; 4] = [0];
    var cp: ptr<u8> = null;
    unsafe { cp = &mut counter[0] as ptr<u8>; }
    var done: i64 = 0;
    var c: u32 = 0;
    while (done < masklen) {
        counter[0] = ((c >> 24) & 255) as u8;
        counter[1] = ((c >> 16) & 255) as u8;
        counter[2] = ((c >> 8) & 255) as u8;
        counter[3] = (c & 255) as u8;

        var ctx: Sha256 = zero(Sha256);
        sha256_init(&mut ctx);
        sha256_update(&mut ctx, seed, seedlen);
        sha256_update(&mut ctx, cp, 4);
        var h: [u8; 32] = [0];
        var hp: ptr<u8> = null;
        unsafe { hp = &mut h[0] as ptr<u8>; }
        sha256_final(&mut ctx, hp);

        var n: i64 = masklen - done;
        if (n > 32) {
            n = 32;
        }
        rt_copy(rt_add(mask, done), hp, n);
        done += n;
        c += 1;
    }
    return 0;
}

fn rsa_pss_verify(key: &mut RsaKey, hash: ptr<u8>, hlen: i64, sig: ptr<u8>, siglen: i64) -> i32 {
    if (hlen != 32) {
        return 0;
    }
    let bits: i64 = bn_bitlen(&mut key.n);
    if (bits < 512) {
        return 0;
    }
    let embits: i64 = bits - 1;
    let emlen: i64 = (embits + 7) / 8;
    if (emlen > RSA_MAX_BYTES || emlen < hlen + 2) {
        return 0;
    }
    let dblen: i64 = emlen - hlen - 1;
    if (dblen < 1) {
        return 0;
    }

    var em: [u8; RSA_MAX_BYTES] = [0];
    var emp: ptr<u8> = null;
    unsafe { emp = &mut em[0] as ptr<u8>; }
    if (rsa_pow(key, sig, siglen, emp, emlen) != 0) {
        return 0;
    }
    if (rt_byte(emp, emlen - 1) != 188) {
        return 0;
    }

    let topbits: i64 = 8 * emlen - embits;
    var hb: [u8; 32] = [0];
    var hbp: ptr<u8> = null;
    unsafe { hbp = &mut hb[0] as ptr<u8>; }
    rt_copy(hbp, rt_add(emp, dblen), hlen);

    var db: [u8; RSA_MAX_BYTES] = [0];
    var dbp: ptr<u8> = null;
    unsafe { dbp = &mut db[0] as ptr<u8>; }
    if (rsa_mgf1_sha256(hbp, hlen, dbp, dblen) != 0) {
        return 0;
    }
    var i: i64 = 0;
    while (i < dblen) {
        rt_setbyte(dbp, i, (rt_byte(emp, i) ^ rt_byte(dbp, i)) as u8);
        i += 1;
    }
    if (topbits > 0) {
        var mask: u8 = 0;
        mask = (255 >> topbits) as u8;
        rt_setbyte(dbp, 0, (rt_byte(dbp, 0) & mask) as u8);
    }

    let saltlen: i64 = hlen;
    let ps: i64 = dblen - saltlen - 1;
    if (ps < 0) {
        return 0;
    }
    i = 0;
    while (i < ps) {
        if (rt_byte(dbp, i) != 0) {
            return 0;
        }
        i += 1;
    }
    if (rt_byte(dbp, ps) != 1) {
        return 0;
    }

    var zero8: [u8; 8] = [0];
    var z8: ptr<u8> = null;
    unsafe { z8 = &mut zero8[0] as ptr<u8>; }
    var rest: [u8; 96] = [0];
    var rp: ptr<u8> = null;
    unsafe { rp = &mut rest[0] as ptr<u8>; }
    rt_copy(rp, hash, hlen);
    rt_copy(rt_add(rp, hlen), rt_add(dbp, ps + 1), saltlen);

    var ctx: Sha256 = zero(Sha256);
    sha256_init(&mut ctx);
    sha256_update(&mut ctx, z8, 8);
    sha256_update(&mut ctx, rp, hlen + saltlen);
    var h2: [u8; 32] = [0];
    var h2p: ptr<u8> = null;
    unsafe { h2p = &mut h2[0] as ptr<u8>; }
    sha256_final(&mut ctx, h2p);

    if (rt_ct_eq(h2p, hbp, hlen) != 1) {
        return 0;
    }
    return 1;
}
