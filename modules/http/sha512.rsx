include "rt.rsx";

struct Sha512 {
    h: [u64; 8],
    buf: [u8; 128],
    buflen: i64,
    total: i64,
    outlen: i64
}

fn sha512_mk(hi: i64, lo: i64) -> u64 {
    return ((hi as u64) << 32) | (lo as u64);
}

fn sha512_rotr(x: u64, n: u64) -> u64 {
    return (x >> n) | (x << (64 - n));
}

fn sha512_load_be64(p: ptr<u8>, off: i64) -> u64 {
    var v: u64 = 0;
    var i: i64 = 0;
    while (i < 8) {
        var b: u8 = 0;
        unsafe { b = p[off + i]; }
        v = (v << 8) | (b as u64);
        i += 1;
    }
    return v;
}

fn sha512_store_be64(p: ptr<u8>, off: i64, v: u64) {
    var i: i64 = 0;
    while (i < 8) {
        unsafe { p[off + i] = ((v >> (((7 - i) * 8) as u64)) & 255) as u8; }
        i += 1;
    }
}

fn sha512_init(c: &mut Sha512) {
    c.h[0] = sha512_mk(0x6a09e667, 0xf3bcc908);
    c.h[1] = sha512_mk(0xbb67ae85, 0x84caa73b);
    c.h[2] = sha512_mk(0x3c6ef372, 0xfe94f82b);
    c.h[3] = sha512_mk(0xa54ff53a, 0x5f1d36f1);
    c.h[4] = sha512_mk(0x510e527f, 0xade682d1);
    c.h[5] = sha512_mk(0x9b05688c, 0x2b3e6c1f);
    c.h[6] = sha512_mk(0x1f83d9ab, 0xfb41bd6b);
    c.h[7] = sha512_mk(0x5be0cd19, 0x137e2179);
    c.buflen = 0;
    c.total = 0;
    c.outlen = 64;
}

fn sha384_init(c: &mut Sha512) {
    c.h[0] = sha512_mk(0xcbbb9d5d, 0xc1059ed8);
    c.h[1] = sha512_mk(0x629a292a, 0x367cd507);
    c.h[2] = sha512_mk(0x9159015a, 0x3070dd17);
    c.h[3] = sha512_mk(0x152fecd8, 0xf70e5939);
    c.h[4] = sha512_mk(0x67332667, 0xffc00b31);
    c.h[5] = sha512_mk(0x8eb44a87, 0x68581511);
    c.h[6] = sha512_mk(0xdb0c2e0d, 0x64f98fa7);
    c.h[7] = sha512_mk(0x47b5481d, 0xbefa4fa4);
    c.buflen = 0;
    c.total = 0;
    c.outlen = 48;
}

fn sha512_block(c: &mut Sha512, w: &mut [u64; 80], khi: &mut [i64; 80], klo: &mut [i64; 80], block: ptr<u8>) {
    var i: i64 = 0;
    while (i < 16) {
        w[i] = sha512_load_be64(block, i * 8);
        i += 1;
    }
    while (i < 80) {
        let s0: u64 = sha512_rotr(w[i - 15], 1) ^ sha512_rotr(w[i - 15], 8) ^ (w[i - 15] >> 7);
        let s1: u64 = sha512_rotr(w[i - 2], 19) ^ sha512_rotr(w[i - 2], 61) ^ (w[i - 2] >> 6);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        i += 1;
    }

    var a: u64 = c.h[0];
    var b: u64 = c.h[1];
    var cc: u64 = c.h[2];
    var d: u64 = c.h[3];
    var e: u64 = c.h[4];
    var f: u64 = c.h[5];
    var g: u64 = c.h[6];
    var h: u64 = c.h[7];

    i = 0;
    while (i < 80) {
        let s1: u64 = sha512_rotr(e, 14) ^ sha512_rotr(e, 18) ^ sha512_rotr(e, 41);
        let ch: u64 = (e & f) ^ ((~e) & g);
        let t1: u64 = h + s1 + ch + sha512_mk(khi[i], klo[i]) + w[i];
        let s0: u64 = sha512_rotr(a, 28) ^ sha512_rotr(a, 34) ^ sha512_rotr(a, 39);
        let maj: u64 = (a & b) ^ (a & cc) ^ (b & cc);
        let t2: u64 = s0 + maj;
        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = cc;
        cc = b;
        b = a;
        a = t1 + t2;
        i += 1;
    }

    c.h[0] = c.h[0] + a;
    c.h[1] = c.h[1] + b;
    c.h[2] = c.h[2] + cc;
    c.h[3] = c.h[3] + d;
    c.h[4] = c.h[4] + e;
    c.h[5] = c.h[5] + f;
    c.h[6] = c.h[6] + g;
    c.h[7] = c.h[7] + h;
}

fn sha512_rounds(c: &mut Sha512, bp: ptr<u8>) {
    var w: [u64; 80] = [0];
    var khi: [i64; 80] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
        0xca273ece, 0xd186b8c7, 0xeada7dd6, 0xf57d4f7f, 0x06f067aa, 0x0a637dc5, 0x113f9804, 0x1b710b35,
        0x28db77f5, 0x32caab7b, 0x3c9ebe0a, 0x431d67c4, 0x4cc5d4be, 0x597f299c, 0x5fcb6fab, 0x6c44198c
    ];
    var klo: [i64; 80] = [
        0xd728ae22, 0x23ef65cd, 0xec4d3b2f, 0x8189dbbc, 0xf348b538, 0xb605d019, 0xaf194f9b, 0xda6d8118,
        0xa3030242, 0x45706fbe, 0x4ee4b28c, 0xd5ffb4e2, 0xf27b896f, 0x3b1696b1, 0x25c71235, 0xcf692694,
        0x9ef14ad2, 0x384f25e3, 0x8b8cd5b5, 0x77ac9c65, 0x592b0275, 0x6ea6e483, 0xbd41fbd4, 0x831153b5,
        0xee66dfab, 0x2db43210, 0x98fb213f, 0xbeef0ee4, 0x3da88fc2, 0x930aa725, 0xe003826f, 0x0a0e6e70,
        0x46d22ffc, 0x5c26c926, 0x5ac42aed, 0x9d95b3df, 0x8baf63de, 0x3c77b2a8, 0x47edaee6, 0x1482353b,
        0x4cf10364, 0xbc423001, 0xd0f89791, 0x0654be30, 0xd6ef5218, 0x5565a910, 0x5771202a, 0x32bbd1b8,
        0xb8d2d0c8, 0x5141ab53, 0xdf8eeb99, 0xe19b48a8, 0xc5c95a63, 0xe3418acb, 0x7763e373, 0xd6b2b8a3,
        0x5defb2fc, 0x43172f60, 0xa1f0ab72, 0x1a6439ec, 0x23631e28, 0xde82bde9, 0xb2c67915, 0xe372532b,
        0xea26619c, 0x21c0c207, 0xcde0eb1e, 0xee6ed178, 0x72176fba, 0xa2c898a6, 0xbef90dae, 0x131c471b,
        0x23047d84, 0x40c72493, 0x15c9bebc, 0x9c100d4c, 0xcb3e42b6, 0xfc657e2a, 0x3ad6faec, 0x4a475817
    ];
    sha512_block(c, &mut w, &mut khi, &mut klo, bp);
}

fn sha512_update(c: &mut Sha512, data: ptr<u8>, len: i64) {
    var off: i64 = 0;
    var bp: ptr<u8> = null;
    unsafe { bp = &mut c.buf[0] as ptr<u8>; }
    while (off < len) {
        var room: i64 = 128 - c.buflen;
        var take: i64 = len - off;
        if (take > room) {
            take = room;
        }
        rt_copy(rt_add(bp, c.buflen), rt_add(data, off), take);
        c.buflen += take;
        c.total += take;
        off += take;
        if (c.buflen == 128) {
            sha512_rounds(c, bp);
            c.buflen = 0;
        }
    }
}

fn sha512_final(c: &mut Sha512, out: ptr<u8>) {
    let bits: u64 = (c.total as u64) * 8;
    var pad: [u8; 128] = [0];
    var pp: ptr<u8> = null;
    unsafe { pp = &mut pad[0] as ptr<u8>; }
    pad[0] = 128;
    let m: i64 = (c.buflen + 1) % 128;
    var zeros: i64 = 0;
    if (m > 112) {
        zeros = 128 - m + 112;
    } else if (m < 112) {
        zeros = 112 - m;
    }
    sha512_update(c, pp, 1 + zeros);

    var lenbuf: [u8; 16] = [0];
    var lp: ptr<u8> = null;
    unsafe { lp = &mut lenbuf[0] as ptr<u8>; }
    sha512_store_be64(lp, 0, 0);
    sha512_store_be64(lp, 8, bits);
    sha512_update(c, lp, 16);

    var i: i64 = 0;
    while (i * 8 < c.outlen) {
        sha512_store_be64(out, i * 8, c.h[i]);
        i += 1;
    }
}

fn sha512(data: ptr<u8>, len: i64, out: ptr<u8>) {
    var c: Sha512 = zero(Sha512);
    sha512_init(&mut c);
    sha512_update(&mut c, data, len);
    sha512_final(&mut c, out);
}

fn sha384(data: ptr<u8>, len: i64, out: ptr<u8>) {
    var c: Sha512 = zero(Sha512);
    sha384_init(&mut c);
    sha512_update(&mut c, data, len);
    sha512_final(&mut c, out);
}
