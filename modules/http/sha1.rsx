include "rt.rsx";

struct Sha1 {
    h: [u32; 5],
    buf: [u8; 64],
    buflen: i64,
    total: i64
}

fn sha1_rotl(x: u32, n: u32) -> u32 {
    return (x << n) | (x >> (32 - n));
}

fn sha1_load_be32(p: ptr<u8>, off: i64) -> u32 {
    var v: u32 = 0;
    var i: i64 = 0;
    while (i < 4) {
        var b: u8 = 0;
        unsafe { b = p[off + i]; }
        v = (v << 8) | (b as u32);
        i += 1;
    }
    return v;
}

fn sha1_store_be32(p: ptr<u8>, off: i64, v: u32) {
    unsafe {
        p[off] = ((v >> 24) & 255) as u8;
        p[off + 1] = ((v >> 16) & 255) as u8;
        p[off + 2] = ((v >> 8) & 255) as u8;
        p[off + 3] = (v & 255) as u8;
    }
}

fn sha1_init(c: &mut Sha1) {
    c.h[0] = 1732584193;
    c.h[1] = 4023233417;
    c.h[2] = 2562383102;
    c.h[3] = 271733878;
    c.h[4] = 3285377520;
    c.buflen = 0;
    c.total = 0;
}

fn sha1_block(c: &mut Sha1, w: &mut [u32; 80], block: ptr<u8>) {
    var i: i64 = 0;
    while (i < 16) {
        w[i] = sha1_load_be32(block, i * 4);
        i += 1;
    }
    while (i < 80) {
        let x: u32 = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
        w[i] = sha1_rotl(x, 1);
        i += 1;
    }

    var a: u32 = c.h[0];
    var b: u32 = c.h[1];
    var cc: u32 = c.h[2];
    var d: u32 = c.h[3];
    var e: u32 = c.h[4];

    i = 0;
    while (i < 80) {
        var f: u32 = 0;
        var k: u32 = 0;
        if (i < 20) {
            f = (b & cc) | ((~b) & d);
            k = 1518500249;
        } else if (i < 40) {
            f = b ^ cc ^ d;
            k = 1859775393;
        } else if (i < 60) {
            f = (b & cc) | (b & d) | (cc & d);
            k = 2400959708;
        } else {
            f = b ^ cc ^ d;
            k = 3395469782;
        }
        let t: u32 = sha1_rotl(a, 5) + f + e + k + w[i];
        e = d;
        d = cc;
        cc = sha1_rotl(b, 30);
        b = a;
        a = t;
        i += 1;
    }

    c.h[0] = c.h[0] + a;
    c.h[1] = c.h[1] + b;
    c.h[2] = c.h[2] + cc;
    c.h[3] = c.h[3] + d;
    c.h[4] = c.h[4] + e;
}

fn sha1_update(c: &mut Sha1, data: ptr<u8>, len: i64) {
    var off: i64 = 0;
    var w: [u32; 80] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut c.buf[0] as ptr<u8>; }
    while (off < len) {
        var room: i64 = 64 - c.buflen;
        var take: i64 = len - off;
        if (take > room) {
            take = room;
        }
        rt_copy(rt_add(bp, c.buflen), rt_add(data, off), take);
        c.buflen += take;
        c.total += take;
        off += take;
        if (c.buflen == 64) {
            sha1_block(c, &mut w, bp);
            c.buflen = 0;
        }
    }
}

fn sha1_final(c: &mut Sha1, out: ptr<u8>) {
    let bits: u64 = (c.total as u64) * 8;
    var pad: [u8; 72] = [0];
    var pp: ptr<u8> = null;
    unsafe { pp = &mut pad[0] as ptr<u8>; }
    pad[0] = 128;
    let m: i64 = (c.buflen + 1) % 64;
    var zeros: i64 = 0;
    if (m > 56) {
        zeros = 64 - m + 56;
    } else if (m < 56) {
        zeros = 56 - m;
    }
    sha1_update(c, pp, 1 + zeros);

    var lenbuf: [u8; 8] = [0];
    var lp: ptr<u8> = null;
    unsafe { lp = &mut lenbuf[0] as ptr<u8>; }
    sha1_store_be32(lp, 0, ((bits >> 32) & 4294967295) as u32);
    sha1_store_be32(lp, 4, (bits & 4294967295) as u32);
    sha1_update(c, lp, 8);

    var i: i64 = 0;
    while (i < 5) {
        sha1_store_be32(out, i * 4, c.h[i]);
        i += 1;
    }
}

fn sha1(data: ptr<u8>, len: i64, out: ptr<u8>) {
    var c: Sha1 = zero(Sha1);
    sha1_init(&mut c);
    sha1_update(&mut c, data, len);
    sha1_final(&mut c, out);
}
