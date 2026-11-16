struct Aes128 {
    rk: [u8; 176],
    sb: [u8; 256]
}

fn aes_sbox_fill(k: &mut Aes128) {
    var t: [u8; 256] = [
        99, 124, 119, 123, 242, 107, 111, 197, 48, 1, 103, 43, 254, 215, 171, 118,
        202, 130, 201, 125, 250, 89, 71, 240, 173, 212, 162, 175, 156, 164, 114, 192,
        183, 253, 147, 38, 54, 63, 247, 204, 52, 165, 229, 241, 113, 216, 49, 21,
        4, 199, 35, 195, 24, 150, 5, 154, 7, 18, 128, 226, 235, 39, 178, 117,
        9, 131, 44, 26, 27, 110, 90, 160, 82, 59, 214, 179, 41, 227, 47, 132,
        83, 209, 0, 237, 32, 252, 177, 91, 106, 203, 190, 57, 74, 76, 88, 207,
        208, 239, 170, 251, 67, 77, 51, 133, 69, 249, 2, 127, 80, 60, 159, 168,
        81, 163, 64, 143, 146, 157, 56, 245, 188, 182, 218, 33, 16, 255, 243, 210,
        205, 12, 19, 236, 95, 151, 68, 23, 196, 167, 126, 61, 100, 93, 25, 115,
        96, 129, 79, 220, 34, 42, 144, 136, 70, 238, 184, 20, 222, 94, 11, 219,
        224, 50, 58, 10, 73, 6, 36, 92, 194, 211, 172, 98, 145, 149, 228, 121,
        231, 200, 55, 109, 141, 213, 78, 169, 108, 86, 244, 234, 101, 122, 174, 8,
        186, 120, 37, 46, 28, 166, 180, 198, 232, 221, 116, 31, 75, 189, 139, 138,
        112, 62, 181, 102, 72, 3, 246, 14, 97, 53, 87, 185, 134, 193, 29, 158,
        225, 248, 152, 17, 105, 217, 142, 148, 155, 30, 135, 233, 206, 85, 40, 223,
        140, 161, 137, 13, 191, 230, 66, 104, 65, 153, 45, 15, 176, 84, 187, 22
    ];
    var i: i64 = 0;
    while (i < 256) {
        k.sb[i] = t[i];
        i += 1;
    }
}

fn aes_rcon(i: i64) -> u8 {
    var t: [u8; 11] = [0, 1, 2, 4, 8, 16, 32, 64, 128, 27, 54];
    return t[i];
}

fn aes_xtime(x: u8) -> u8 {
    let hi: u8 = (x >> 7) & 1;
    if (hi == 1) {
        return ((x << 1) ^ 27) as u8;
    }
    return (x << 1) as u8;
}

fn aes128_init(k: &mut Aes128, key: ptr<u8>) {
    aes_sbox_fill(k);

    var i: i64 = 0;
    while (i < 16) {
        var b: u8 = 0;
        unsafe { b = key[i]; }
        k.rk[i] = b;
        i += 1;
    }

    var w: i64 = 4;
    while (w < 44) {
        var t0: u8 = k.rk[(w - 1) * 4];
        var t1: u8 = k.rk[(w - 1) * 4 + 1];
        var t2: u8 = k.rk[(w - 1) * 4 + 2];
        var t3: u8 = k.rk[(w - 1) * 4 + 3];
        if (w % 4 == 0) {
            let r0: u8 = k.sb[t1 as i64];
            let r1: u8 = k.sb[t2 as i64];
            let r2: u8 = k.sb[t3 as i64];
            let r3: u8 = k.sb[t0 as i64];
            let rc: u8 = aes_rcon(w / 4);
            t0 = r0 ^ rc;
            t1 = r1;
            t2 = r2;
            t3 = r3;
        }
        k.rk[w * 4] = k.rk[(w - 4) * 4] ^ t0;
        k.rk[w * 4 + 1] = k.rk[(w - 4) * 4 + 1] ^ t1;
        k.rk[w * 4 + 2] = k.rk[(w - 4) * 4 + 2] ^ t2;
        k.rk[w * 4 + 3] = k.rk[(w - 4) * 4 + 3] ^ t3;
        w += 1;
    }
}

fn aes128_encrypt_block(k: &Aes128, inb: ptr<u8>, out: ptr<u8>) {
    var s: [u8; 16] = [0];
    var i: i64 = 0;
    while (i < 16) {
        var b: u8 = 0;
        unsafe { b = inb[i]; }
        s[i] = b ^ k.rk[i];
        i += 1;
    }

    var round: i64 = 1;
    while (round < 11) {
        i = 0;
        while (i < 16) {
            s[i] = k.sb[s[i] as i64];
            i += 1;
        }

        var t: [u8; 16] = [0];
        t[0] = s[0];   t[4] = s[4];   t[8] = s[8];    t[12] = s[12];
        t[1] = s[5];   t[5] = s[9];   t[9] = s[13];   t[13] = s[1];
        t[2] = s[10];  t[6] = s[14];  t[10] = s[2];   t[14] = s[6];
        t[3] = s[15];  t[7] = s[3];   t[11] = s[7];   t[15] = s[11];
        i = 0;
        while (i < 16) {
            s[i] = t[i];
            i += 1;
        }

        if (round < 10) {
            var c: i64 = 0;
            while (c < 4) {
                let a0: u8 = s[c * 4];
                let a1: u8 = s[c * 4 + 1];
                let a2: u8 = s[c * 4 + 2];
                let a3: u8 = s[c * 4 + 3];
                let x0: u8 = aes_xtime(a0);
                let x1: u8 = aes_xtime(a1);
                let x2: u8 = aes_xtime(a2);
                let x3: u8 = aes_xtime(a3);
                s[c * 4] = (x0 ^ x1 ^ a1 ^ a2 ^ a3) as u8;
                s[c * 4 + 1] = (a0 ^ x1 ^ x2 ^ a2 ^ a3) as u8;
                s[c * 4 + 2] = (a0 ^ a1 ^ x2 ^ x3 ^ a3) as u8;
                s[c * 4 + 3] = (x0 ^ a0 ^ a1 ^ a2 ^ x3) as u8;
                c += 1;
            }
        }

        i = 0;
        while (i < 16) {
            s[i] = s[i] ^ k.rk[round * 16 + i];
            i += 1;
        }
        round += 1;
    }

    i = 0;
    while (i < 16) {
        unsafe { out[i] = s[i]; }
        i += 1;
    }
}

struct Gf {
    hi: u64,
    lo: u64
}

fn gf_from_bytes(p: ptr<u8>) -> Gf {
    var g: Gf = zero(Gf);
    var i: i64 = 0;
    while (i < 8) {
        var b: u8 = 0;
        unsafe { b = p[i]; }
        g.hi = (g.hi << 8) | (b as u64);
        i += 1;
    }
    i = 0;
    while (i < 8) {
        var b2: u8 = 0;
        unsafe { b2 = p[8 + i]; }
        g.lo = (g.lo << 8) | (b2 as u64);
        i += 1;
    }
    return g;
}

fn gf_to_bytes(g: Gf, p: ptr<u8>) {
    var i: i64 = 0;
    while (i < 8) {
        unsafe { p[i] = ((g.hi >> ((56 - i * 8) as u64)) & 255) as u8; }
        i += 1;
    }
    i = 0;
    while (i < 8) {
        unsafe { p[8 + i] = ((g.lo >> ((56 - i * 8) as u64)) & 255) as u8; }
        i += 1;
    }
}

fn gf_mul(x: Gf, y: Gf) -> Gf {
    var z: Gf = zero(Gf);
    var rcon: u64 = 225;
    rcon = rcon << 56;
    var v: Gf = y;
    var i: i32 = 63;
    while (i >= 0) {
        let bit: u64 = (x.hi >> (i as u64)) & 1;
        if (bit == 1) {
            z.hi = z.hi ^ v.hi;
            z.lo = z.lo ^ v.lo;
        }
        let carry: u64 = v.hi & 1;
        let low: u64 = v.lo & 1;
        v.hi = v.hi >> 1;
        v.lo = (v.lo >> 1) | (carry << 63);
        if (low == 1) {
            v.hi = v.hi ^ rcon;
        }
        i -= 1;
    }
    i = 63;
    while (i >= 0) {
        let bit2: u64 = (x.lo >> (i as u64)) & 1;
        if (bit2 == 1) {
            z.hi = z.hi ^ v.hi;
            z.lo = z.lo ^ v.lo;
        }
        let carry2: u64 = v.hi & 1;
        let low2: u64 = v.lo & 1;
        v.hi = v.hi >> 1;
        v.lo = (v.lo >> 1) | (carry2 << 63);
        if (low2 == 1) {
            v.hi = v.hi ^ rcon;
        }
        i -= 1;
    }
    return z;
}

fn ghash_absorb(h: Gf, y: &mut Gf, blk: ptr<u8>) {
    let g: Gf = gf_from_bytes(blk);
    var cur: Gf = zero(Gf);
    cur.hi = y.hi ^ g.hi;
    cur.lo = y.lo ^ g.lo;
    let m: Gf = gf_mul(cur, h);
    y.hi = m.hi;
    y.lo = m.lo;
}

fn ghash_run(h: Gf, y: &mut Gf, data: ptr<u8>, len: i64) {
    let full: i64 = len / 16;
    var i: i64 = 0;
    while (i < full) {
        var dp: ptr<u8> = null;
        unsafe { dp = data + i * 16; }
        ghash_absorb(h, y, dp);
        i += 1;
    }
    let rem: i64 = len - full * 16;
    if (rem > 0) {
        var blk: [u8; 16] = [0];
        var bp: ptr<u8> = null;
        unsafe {
            bp = &mut blk[0] as ptr<u8>;
            memcpy(bp, data + full * 16, rem as u64);
        }
        ghash_absorb(h, y, bp);
    }
}

fn gcm_inc32(ctr: &mut [u8; 16], off: i64) {
    var i: i64 = 15;
    while (i >= off) {
        ctr[i] = (ctr[i] + 1) as u8;
        if (ctr[i] != 0) {
            return;
        }
        i -= 1;
    }
}

fn gcm_run(k: &Aes128, nonce: ptr<u8>, noncelen: i64, aad: ptr<u8>, aadlen: i64, inb: ptr<u8>, len: i64, out: ptr<u8>, tag: ptr<u8>, decrypt: i32) -> i32 {
    var zero_blk: [u8; 16] = [0];
    var zero_p: ptr<u8> = null;
    unsafe { zero_p = &mut zero_blk[0] as ptr<u8>; }
    var hblk: [u8; 16] = [0];
    var h_p: ptr<u8> = null;
    unsafe { h_p = &mut hblk[0] as ptr<u8>; }
    aes128_encrypt_block(k, zero_p, h_p);
    let h: Gf = gf_from_bytes(h_p);

    var j0: [u8; 16] = [0];
    var j0_p: ptr<u8> = null;
    unsafe { j0_p = &mut j0[0] as ptr<u8>; }
    if (noncelen == 12) {
        rt_copy(j0_p, nonce, 12);
        j0[15] = 1;
    } else {
        var y0: Gf = zero(Gf);
        ghash_run(h, &mut y0, nonce, noncelen);
        var yb0: [u8; 16] = [0];
        var yb0_p: ptr<u8> = null;
        unsafe { yb0_p = &mut yb0[0] as ptr<u8>; }
        gf_to_bytes(y0, yb0_p);
        let bits: u64 = (noncelen as u64) * 8;
        var i2: i64 = 0;
        while (i2 < 8) {
            yb0[8 + i2] = (yb0[8 + i2] ^ ((bits >> ((56 - i2 * 8) as u64)) & 255) as u8) as u8;
            i2 += 1;
        }
        rt_copy(j0_p, yb0_p, 16);
    }

    var ctr: [u8; 16] = [0];
    var ctr_p: ptr<u8> = null;
    unsafe {
        ctr_p = &mut ctr[0] as ptr<u8>;
        memcpy(ctr_p, j0_p, 16);
    }
    gcm_inc32(&mut ctr, 12);

    var done: i64 = 0;
    while (done < len) {
        var ks: [u8; 16] = [0];
        var ks_p: ptr<u8> = null;
        unsafe { ks_p = &mut ks[0] as ptr<u8>; }
        aes128_encrypt_block(k, ctr_p, ks_p);
        var take: i64 = len - done;
        if (take > 16) {
            take = 16;
        }
        var j: i64 = 0;
        while (j < take) {
            var b: u8 = 0;
            var kb: u8 = 0;
            unsafe {
                b = inb[done + j];
                kb = ks[j];
                out[done + j] = b ^ kb;
            }
            j += 1;
        }
        gcm_inc32(&mut ctr, 12);
        done += take;
    }

    var y: Gf = zero(Gf);
    if (aadlen > 0) {
        ghash_run(h, &mut y, aad, aadlen);
    }
    if (len > 0) {
        if (decrypt == 0) {
            ghash_run(h, &mut y, out, len);
        } else {
            ghash_run(h, &mut y, inb, len);
        }
    }
    var lens: [u8; 16] = [0];
    let aadbits: u64 = (aadlen as u64) * 8;
    let cbits: u64 = (len as u64) * 8;
    var z: i64 = 0;
    while (z < 8) {
        lens[z] = ((aadbits >> ((56 - z * 8) as u64)) & 255) as u8;
        lens[8 + z] = ((cbits >> ((56 - z * 8) as u64)) & 255) as u8;
        z += 1;
    }
    var lp: ptr<u8> = null;
    unsafe { lp = &mut lens[0] as ptr<u8>; }
    ghash_absorb(h, &mut y, lp);

    var ek: [u8; 16] = [0];
    var ek_p: ptr<u8> = null;
    unsafe { ek_p = &mut ek[0] as ptr<u8>; }
    aes128_encrypt_block(k, j0_p, ek_p);

    var yb: [u8; 16] = [0];
    var yb_p: ptr<u8> = null;
    unsafe { yb_p = &mut yb[0] as ptr<u8>; }
    gf_to_bytes(y, yb_p);

    var calc: [u8; 16] = [0];
    var i3: i64 = 0;
    while (i3 < 16) {
        calc[i3] = ek[i3] ^ yb[i3];
        i3 += 1;
    }

    var cp: ptr<u8> = null;
    unsafe { cp = &mut calc[0] as ptr<u8>; }
    if (decrypt == 0) {
        rt_copy(tag, cp, 16);
        return 0;
    }
    if (rt_ct_eq(cp, tag, 16) == 1) {
        return 0;
    }
    return -1;
}

fn aes128_gcm_seal(k: &Aes128, nonce: ptr<u8>, aad: ptr<u8>, aadlen: i64, plain: ptr<u8>, len: i64, out: ptr<u8>, tag: ptr<u8>) -> i32 {
    return gcm_run(k, nonce, 12, aad, aadlen, plain, len, out, tag, 0);
}

fn aes128_gcm_open(k: &Aes128, nonce: ptr<u8>, aad: ptr<u8>, aadlen: i64, cipher: ptr<u8>, len: i64, out: ptr<u8>, tag: ptr<u8>) -> i32 {
    return gcm_run(k, nonce, 12, aad, aadlen, cipher, len, out, tag, 1);
}
