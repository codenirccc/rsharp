const HMAC_BLOCK: i64 = 64;

struct HmacSha256 {
    inner: Sha256,
    opad: [u8; 64]
}

fn hmac_init(m: &mut HmacSha256, key: ptr<u8>, keylen: i64) {
    var k: [u8; 64] = [0];
    var kp: ptr<u8> = null;
    unsafe { kp = &mut k[0] as ptr<u8>; }

    if (keylen > 64) {
        sha256(key, keylen, kp);
    } else if (keylen > 0) {
        rt_copy(kp, key, keylen);
    }

    var pad: [u8; 64] = [0];
    var pp: ptr<u8> = null;
    unsafe { pp = &mut pad[0] as ptr<u8>; }

    var i: i64 = 0;
    while (i < 64) {
        pad[i] = k[i] ^ 54;
        m.opad[i] = k[i] ^ 92;
        i += 1;
    }
    sha256_init(&mut m.inner);
    sha256_update(&mut m.inner, pp, 64);
}

fn hmac_update(m: &mut HmacSha256, data: ptr<u8>, len: i64) {
    sha256_update(&mut m.inner, data, len);
}

fn hmac_final(m: &mut HmacSha256, out: ptr<u8>) {
    var ih: [u8; 32] = [0];
    var ihp: ptr<u8> = null;
    unsafe { ihp = &mut ih[0] as ptr<u8>; }
    sha256_final(&mut m.inner, ihp);

    var outer: Sha256 = zero(Sha256);
    sha256_init(&mut outer);
    var op: ptr<u8> = null;
    unsafe { op = &mut m.opad[0] as ptr<u8>; }
    sha256_update(&mut outer, op, 64);
    sha256_update(&mut outer, ihp, 32);
    sha256_final(&mut outer, out);
}

fn hmac_sha256(key: ptr<u8>, keylen: i64, msg: ptr<u8>, msglen: i64, out: ptr<u8>) {
    var m: HmacSha256 = zero(HmacSha256);
    hmac_init(&mut m, key, keylen);
    hmac_update(&mut m, msg, msglen);
    hmac_final(&mut m, out);
}

fn hkdf_extract(salt: ptr<u8>, saltlen: i64, ikm: ptr<u8>, ikmlen: i64, out: ptr<u8>) {
    hmac_sha256(salt, saltlen, ikm, ikmlen, out);
}

fn hkdf_expand(prk: ptr<u8>, prklen: i64, info: ptr<u8>, infolen: i64, out: ptr<u8>, outlen: i64) -> i32 {
    if (outlen < 0 || outlen > 8160) {
        return -1;
    }
    var t: [u8; 32] = [0];
    var tp: ptr<u8> = null;
    unsafe { tp = &mut t[0] as ptr<u8>; }
    var tlen: i64 = 0;
    var done: i64 = 0;
    var counter: i32 = 1;
    var scratch: HxBuf = hxbuf_new(96);

    while (done < outlen) {
        hxbuf_clear(&mut scratch);
        if (tlen > 0) {
            hxbuf_put(&mut scratch, tp, tlen);
        }
        if (infolen > 0) {
            hxbuf_put(&mut scratch, info, infolen);
        }
        hxbuf_putc(&mut scratch, counter as u8);

        var hm: HmacSha256 = zero(HmacSha256);
        hmac_init(&mut hm, prk, prklen);
        hmac_update(&mut hm, scratch.p, scratch.len);
        hmac_final(&mut hm, tp);
        tlen = 32;

        var take: i64 = outlen - done;
        if (take > 32) {
            take = 32;
        }
        var dst: ptr<u8> = null;
        unsafe { dst = out + done; }
        rt_copy(dst, tp, take);
        done += take;
        counter += 1;
    }
    hxbuf_free(&mut scratch);
    return 0;
}

fn tls13_expand_label(secret: ptr<u8>, secretlen: i64, label: ptr<u8>, ctx: ptr<u8>, ctxlen: i64, out: ptr<u8>, outlen: i64) -> i32 {
    var info: HxBuf = hxbuf_new(128);
    hxbuf_putc(&mut info, ((outlen >> 8) & 255) as u8);
    hxbuf_putc(&mut info, (outlen & 255) as u8);

    let lab: i64 = rt_len(label);
    hxbuf_putc(&mut info, (6 + lab) as u8);
    hxbuf_puts(&mut info, "tls13 ");
    hxbuf_put(&mut info, label, lab);

    if (ctxlen > 255) {
        hxbuf_free(&mut info);
        return -1;
    }
    hxbuf_putc(&mut info, ctxlen as u8);
    if (ctxlen > 0) {
        hxbuf_put(&mut info, ctx, ctxlen);
    }

    let rc: i32 = hkdf_expand(secret, secretlen, info.p, info.len, out, outlen);
    hxbuf_free(&mut info);
    return rc;
}

const DERIVE_SECRET_LEN: i64 = 32;

fn tls13_derive_secret(secret: ptr<u8>, label: ptr<u8>, transcript_hash: ptr<u8>, out: ptr<u8>) -> i32 {
    return tls13_expand_label(secret, 32, label, transcript_hash, 32, out, 32);
}
