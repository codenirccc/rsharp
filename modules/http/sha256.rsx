struct Sha256 {
    h: [u32; 8],
    buf: [u8; 64],
    buflen: i64,
    total: u64
}

fn sha256_rotr(x: u32, n: u32) -> u32 {
    return (x >> n) | (x << (32 - n));
}

fn sha256_load_be32(p: ptr<u8>, off: i64) -> u32 {
    var v: u32 = 0;
    unsafe {
        v = ((p[off] as u32) << 24) | ((p[off + 1] as u32) << 16) | ((p[off + 2] as u32) << 8) | (p[off + 3] as u32);
    }
    return v;
}

fn sha256_store_be32(p: ptr<u8>, off: i64, v: u32) {
    unsafe {
        p[off] = ((v >> 24) & 255) as u8;
        p[off + 1] = ((v >> 16) & 255) as u8;
        p[off + 2] = ((v >> 8) & 255) as u8;
        p[off + 3] = (v & 255) as u8;
    }
}

fn sha256_init(c: &mut Sha256) {
    c.h[0] = 1779033703;
    c.h[1] = 3144134277;
    c.h[2] = 1013904242;
    c.h[3] = 2773480762;
    c.h[4] = 1359893119;
    c.h[5] = 2600822924;
    c.h[6] = 528734635;
    c.h[7] = 1541459225;
    c.buflen = 0;
    c.total = 0;
    var i: i64 = 0;
    while (i < 64) {
        c.buf[i] = 0;
        i += 1;
    }
}

fn sha256_block(c: &mut Sha256, w: &mut [u32; 64], block: ptr<u8>) {
    var k: [u32; 64] = [
        1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221,
        3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580,
        3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986,
        2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895,
        666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037,
        2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344,
        430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779,
        1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298
    ];
    var i: i64 = 0;
    while (i < 16) {
        w[i] = sha256_load_be32(block, i * 4);
        i += 1;
    }
    while (i < 64) {
        let s0b: u32 = sha256_rotr(w[i - 15], 7) ^ sha256_rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        let s1b: u32 = sha256_rotr(w[i - 2], 17) ^ sha256_rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0b + w[i - 7] + s1b;
        i += 1;
    }

    var a: u32 = c.h[0];
    var b: u32 = c.h[1];
    var cc: u32 = c.h[2];
    var d: u32 = c.h[3];
    var e: u32 = c.h[4];
    var f: u32 = c.h[5];
    var g: u32 = c.h[6];
    var h: u32 = c.h[7];

    i = 0;
    while (i < 64) {
        let kk: u32 = k[i];
        let s1b: u32 = sha256_rotr(e, 6) ^ sha256_rotr(e, 11) ^ sha256_rotr(e, 25);
        let ch: u32 = (e & f) ^ ((~e) & g);
        let t1: u32 = h + s1b + ch + kk + w[i];
        let s0b: u32 = sha256_rotr(a, 2) ^ sha256_rotr(a, 13) ^ sha256_rotr(a, 22);
        let maj: u32 = (a & b) ^ (a & cc) ^ (b & cc);
        let t2: u32 = s0b + maj;
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

fn sha256_update(c: &mut Sha256, data: ptr<u8>, len: i64) {
    var w: [u32; 64] = [0];
    c.total += len as u64;
    var off: i64 = 0;

    if (c.buflen > 0) {
        while (c.buflen < 64 && off < len) {
            var b: u8 = 0;
            unsafe { b = data[off]; }
            c.buf[c.buflen] = b;
            c.buflen += 1;
            off += 1;
        }
        if (c.buflen == 64) {
            var bp: ptr<u8> = null;
            unsafe { bp = &mut c.buf[0] as ptr<u8>; }
            sha256_block(c, &mut w, bp);
            c.buflen = 0;
        }
    }

    while (len - off >= 64) {
        var dp: ptr<u8> = null;
        unsafe { dp = data + off; }
        sha256_block(c, &mut w, dp);
        off += 64;
    }

    while (off < len) {
        var b2: u8 = 0;
        unsafe { b2 = data[off]; }
        c.buf[c.buflen] = b2;
        c.buflen += 1;
        off += 1;
    }
}

fn sha256_final(c: &mut Sha256, out: ptr<u8>) {
    let bits: u64 = c.total * 8;

    var pad: [u8; 72] = [0];
    pad[0] = 128;
    let rem: i64 = c.buflen % 64;
    var padlen: i64 = 0;
    if (rem < 56) {
        padlen = 56 - rem;
    } else {
        padlen = 120 - rem;
    }
    var pp: ptr<u8> = null;
    unsafe { pp = &mut pad[0] as ptr<u8>; }
    sha256_update(c, pp, padlen);
    sha256_store_be32(pp, 0, (bits >> 32) as u32);
    sha256_store_be32(pp, 4, (bits & 4294967295) as u32);
    sha256_update(c, pp, 8);

    var i: i64 = 0;
    while (i < 8) {
        sha256_store_be32(out, i * 4, c.h[i]);
        i += 1;
    }
}

fn sha256(data: ptr<u8>, len: i64, out: ptr<u8>) {
    var c: Sha256 = zero(Sha256);
    sha256_init(&mut c);
    sha256_update(&mut c, data, len);
    sha256_final(&mut c, out);
}
