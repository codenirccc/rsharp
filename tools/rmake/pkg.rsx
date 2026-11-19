include "base.rsx";
include "scan.rsx";

fn repo_default() -> ptr<u8> {
    return "https://www.plaguevm.publicvm.com/basicRresp";
}

const PKGN: i64 = 32;
const IDXB: i64 = 131072;
const RECB: i64 = 16384;
const HEXLEN: i64 = 64;
const LISTB: i64 = 1024;
const PATHB: i64 = 1024;

struct Pkg {
    name: i64,
    ver: i64,
    bytes: i64,
    sha: i64,
    file: i64,
    deps: i64,
    inc: i64
}

struct Idx {
    p: [Pkg; 32],
    n: i64
}

struct Sha {
    h: [u32; 8],
    k: [u32; 64],
    w: [u32; 64],
    buf: [u8; 64],
    dig: [u8; 32],
    n: i64,
    total: u64
}

fn cf_clear(c: &mut Ctx) {
    c.cn = 0;
}

fn cf_ch(c: &mut Ctx, b: u8) {
    if (cmd_room(c, 1) == 0) {
        return;
    }
    wr8(c.cp, c.cn, b);
    c.cn += 1;
}

fn cf_put(c: &mut Ctx, p: ptr<u8>) {
    let n: i64 = sl(p);
    if (cmd_room(c, n) == 0) {
        return;
    }
    var k: i64 = 0;
    while (k < n) {
        wr8(c.cp, c.cn, rd8(p, k));
        c.cn += 1;
        k += 1;
    }
}

fn cf_put_native(c: &mut Ctx, p: ptr<u8>) {
    let n: i64 = sl(p);
    if (cmd_room(c, n) == 0) {
        return;
    }
    var k: i64 = 0;
    while (k < n) {
        var b: u8 = rd8(p, k);
        if (c.win == 1 && b == SLASH) {
            b = BSLASH;
        }
        wr8(c.cp, c.cn, b);
        c.cn += 1;
        k += 1;
    }
}

fn cf_quote(c: &mut Ctx, p: ptr<u8>) {
    cf_ch(c, QUOTE);
    cf_put_native(c, p);
    cf_ch(c, QUOTE);
}

fn cf_quote_raw(c: &mut Ctx, p: ptr<u8>) {
    cf_ch(c, QUOTE);
    cf_put(c, p);
    cf_ch(c, QUOTE);
}

fn cf_done(c: &mut Ctx) -> ptr<u8> {
    if (cmd_room(c, 1) == 0) {
        wr8(c.cp, CBUF - 1, 0);
        return c.cp;
    }
    wr8(c.cp, c.cn, 0);
    return c.cp;
}

fn is_url(p: ptr<u8>) -> i32 {
    let n: i64 = sl(p);
    var k: i64 = 0;
    while (k + 2 < n) {
        if (rd8(p, k) == COLON && rd8(p, k + 1) == SLASH && rd8(p, k + 2) == SLASH) {
            return 1;
        }
        k += 1;
    }
    return 0;
}

fn run_cmd(c: &mut Ctx) -> i32 {
    if (c.err != 0) {
        return 1;
    }
    let p: ptr<u8> = cf_done(c);
    if (c.err != 0) {
        return 1;
    }
    fflush(null);
    return system(p);
}

fn fetch(c: &mut Ctx, src: ptr<u8>, dst: ptr<u8>) -> i32 {
    cf_clear(c);
    if (is_url(src) == 1) {
        cf_put(c, "curl -fsSL --retry 2 -o ");
        cf_quote(c, dst);
        cf_ch(c, SPACE);
        cf_quote_raw(c, src);
    } else if (c.win == 1) {
        cf_put(c, "copy /y ");
        cf_quote(c, src);
        cf_ch(c, SPACE);
        cf_quote(c, dst);
        cf_put(c, " >nul");
    } else {
        cf_put(c, "cp -f ");
        cf_quote(c, src);
        cf_ch(c, SPACE);
        cf_quote(c, dst);
    }
    return run_cmd(c);
}

fn mkdir_p(c: &mut Ctx, path: ptr<u8>) -> i32 {
    cf_clear(c);
    if (c.win == 1) {
        cf_put(c, "mkdir ");
        cf_quote(c, path);
        cf_put(c, " 2>nul");
    } else {
        cf_put(c, "mkdir -p ");
        cf_quote(c, path);
    }
    return run_cmd(c);
}

fn rd_all(p: ptr<u8>, buf: ptr<u8>, cap: i64) -> i64 {
    let f: ptr<u8> = fopen(p, "rb");
    if (f == null) {
        return -1;
    }
    var n: i64 = 0;
    while (n < cap) {
        let got: u64 = fread(ob(buf, n), 1, (cap - n) as u64, f);
        if (got == 0) {
            break;
        }
        n += got as i64;
    }
    fclose(f);
    return n;
}

fn p_reset(c: &mut Ctx) {
    c.pn = TS4;
    wr8(c.tp, TS4, 0);
}

fn p_cat(c: &mut Ctx, p: ptr<u8>) {
    let n: i64 = sl(p);
    if (c.pn + n + 1 > TBUF) {
        printf("rmake: path too long for the scratch area\n");
        c.err = 1;
        return;
    }
    var k: i64 = 0;
    while (k < n) {
        wr8(c.tp, c.pn, rd8(p, k));
        c.pn += 1;
        k += 1;
    }
    wr8(c.tp, c.pn, 0);
}

fn p_end(c: &mut Ctx) -> ptr<u8> {
    if (c.pn >= TBUF) {
        c.pn = TBUF - 1;
    }
    wr8(c.tp, c.pn, 0);
    return ob(c.tp, TS4);
}

fn p_root(c: &mut Ctx) {
    let n: i64 = dir_of(c, c.man);
    if (c.err != 0) {
        return;
    }
    if (n > 0) {
        p_cat(c, ob(c.tp, TS2));
        p_cat(c, "/");
    }
}

fn p_at_root(c: &mut Ctx, rel: ptr<u8>) {
    p_reset(c);
    p_root(c);
    p_cat(c, rel);
}

fn cstr(buf: ptr<u8>, p: ptr<u8>) -> i64 {
    let n: i64 = sl(p);
    var k: i64 = 0;
    while (k < n) {
        wr8(buf, k, rd8(p, k));
        k += 1;
    }
    wr8(buf, n, 0);
    return n;
}

fn dec_val(p: ptr<u8>, n: i64) -> i64 {
    var v: i64 = 0;
    var k: i64 = 0;
    while (k < n) {
        let b: u8 = rd8(p, k);
        if (b < 48 || b > 57) {
            return v;
        }
        v = v * 10 + ((b - 48) as i64);
        k += 1;
    }
    return v;
}

fn hex_nib(b: u8) -> i32 {
    if (b >= 48 && b <= 57) {
        return (b - 48) as i32;
    }
    if (b >= 97 && b <= 102) {
        return (b - 87) as i32;
    }
    if (b >= 65 && b <= 70) {
        return (b - 55) as i32;
    }
    return -1;
}

fn hex_eq(dig: ptr<u8>, hex: ptr<u8>) -> i32 {
    if (sl(hex) != HEXLEN) {
        return 0;
    }
    var k: i64 = 0;
    while (k < 32) {
        let hi: i32 = hex_nib(rd8(hex, k * 2));
        let lo: i32 = hex_nib(rd8(hex, k * 2 + 1));
        if (hi < 0 || lo < 0) {
            return 0;
        }
        let want: u8 = (hi * 16 + lo) as u8;
        if (rd8(dig, k) != want) {
            return 0;
        }
        k += 1;
    }
    return 1;
}

fn sha_k(s: &mut Sha) {
    s.k[0] = 0x428a2f98;
    s.k[1] = 0x71374491;
    s.k[2] = 0xb5c0fbcf;
    s.k[3] = 0xe9b5dba5;
    s.k[4] = 0x3956c25b;
    s.k[5] = 0x59f111f1;
    s.k[6] = 0x923f82a4;
    s.k[7] = 0xab1c5ed5;
    s.k[8] = 0xd807aa98;
    s.k[9] = 0x12835b01;
    s.k[10] = 0x243185be;
    s.k[11] = 0x550c7dc3;
    s.k[12] = 0x72be5d74;
    s.k[13] = 0x80deb1fe;
    s.k[14] = 0x9bdc06a7;
    s.k[15] = 0xc19bf174;
    s.k[16] = 0xe49b69c1;
    s.k[17] = 0xefbe4786;
    s.k[18] = 0x0fc19dc6;
    s.k[19] = 0x240ca1cc;
    s.k[20] = 0x2de92c6f;
    s.k[21] = 0x4a7484aa;
    s.k[22] = 0x5cb0a9dc;
    s.k[23] = 0x76f988da;
    s.k[24] = 0x983e5152;
    s.k[25] = 0xa831c66d;
    s.k[26] = 0xb00327c8;
    s.k[27] = 0xbf597fc7;
    s.k[28] = 0xc6e00bf3;
    s.k[29] = 0xd5a79147;
    s.k[30] = 0x06ca6351;
    s.k[31] = 0x14292967;
    s.k[32] = 0x27b70a85;
    s.k[33] = 0x2e1b2138;
    s.k[34] = 0x4d2c6dfc;
    s.k[35] = 0x53380d13;
    s.k[36] = 0x650a7354;
    s.k[37] = 0x766a0abb;
    s.k[38] = 0x81c2c92e;
    s.k[39] = 0x92722c85;
    s.k[40] = 0xa2bfe8a1;
    s.k[41] = 0xa81a664b;
    s.k[42] = 0xc24b8b70;
    s.k[43] = 0xc76c51a3;
    s.k[44] = 0xd192e819;
    s.k[45] = 0xd6990624;
    s.k[46] = 0xf40e3585;
    s.k[47] = 0x106aa070;
    s.k[48] = 0x19a4c116;
    s.k[49] = 0x1e376c08;
    s.k[50] = 0x2748774c;
    s.k[51] = 0x34b0bcb5;
    s.k[52] = 0x391c0cb3;
    s.k[53] = 0x4ed8aa4a;
    s.k[54] = 0x5b9cca4f;
    s.k[55] = 0x682e6ff3;
    s.k[56] = 0x748f82ee;
    s.k[57] = 0x78a5636f;
    s.k[58] = 0x84c87814;
    s.k[59] = 0x8cc70208;
    s.k[60] = 0x90befffa;
    s.k[61] = 0xa4506ceb;
    s.k[62] = 0xbef9a3f7;
    s.k[63] = 0xc67178f2;
}

fn rotr(x: u32, n: u32) -> u32 {
    return (x >> n) | (x << (32 - n));
}

fn sha_block(s: &mut Sha, p: ptr<u8>) {
    var i: i64 = 0;
    while (i < 16) {
        let b: i64 = i * 4;
        var v: u32 = rd8(p, b) as u32;
        v = (v << 8) | (rd8(p, b + 1) as u32);
        v = (v << 8) | (rd8(p, b + 2) as u32);
        v = (v << 8) | (rd8(p, b + 3) as u32);
        s.w[i] = v;
        i += 1;
    }
    while (i < 64) {
        let x: u32 = s.w[i - 15];
        let y: u32 = s.w[i - 2];
        let s0: u32 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
        let s1: u32 = rotr(y, 17) ^ rotr(y, 19) ^ (y >> 10);
        s.w[i] = s.w[i - 16] + s0 + s.w[i - 7] + s1;
        i += 1;
    }
    var a: u32 = s.h[0];
    var b: u32 = s.h[1];
    var cc: u32 = s.h[2];
    var d: u32 = s.h[3];
    var e: u32 = s.h[4];
    var f: u32 = s.h[5];
    var g: u32 = s.h[6];
    var h: u32 = s.h[7];
    i = 0;
    while (i < 64) {
        let big1: u32 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        let ch: u32 = (e & f) ^ ((e ^ 0xffffffff) & g);
        let t1: u32 = h + big1 + ch + s.k[i] + s.w[i];
        let big0: u32 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        let maj: u32 = (a & b) ^ (a & cc) ^ (b & cc);
        let t2: u32 = big0 + maj;
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
    s.h[0] += a;
    s.h[1] += b;
    s.h[2] += cc;
    s.h[3] += d;
    s.h[4] += e;
    s.h[5] += f;
    s.h[6] += g;
    s.h[7] += h;
}

fn sha_flush(s: &mut Sha) {
    var q: ptr<u8> = null;
    unsafe { q = &mut s.buf[0] as ptr<u8>; }
    sha_block(s, q);
    s.n = 0;
}

fn sha_init(s: &mut Sha) {
    s.h[0] = 0x6a09e667;
    s.h[1] = 0xbb67ae85;
    s.h[2] = 0x3c6ef372;
    s.h[3] = 0xa54ff53a;
    s.h[4] = 0x510e527f;
    s.h[5] = 0x9b05688c;
    s.h[6] = 0x1f83d9ab;
    s.h[7] = 0x5be0cd19;
    s.n = 0;
    s.total = 0;
    sha_k(s);
}

fn sha_push(s: &mut Sha, b: u8) {
    s.buf[s.n] = b;
    s.n += 1;
    s.total += 1;
    if (s.n == 64) {
        sha_flush(s);
    }
}

fn sha_update(s: &mut Sha, p: ptr<u8>, n: i64) {
    var k: i64 = 0;
    while (k < n) {
        sha_push(s, rd8(p, k));
        k += 1;
    }
}

fn sha_final(s: &mut Sha) {
    let bits: u64 = s.total * 8;
    sha_push(s, 128);
    while (s.n != 56) {
        sha_push(s, 0);
    }
    var k: i64 = 7;
    while (k >= 0) {
        let sh: u64 = (k * 8) as u64;
        sha_push(s, ((bits >> sh) & 255) as u8);
        k -= 1;
    }
    var i: i64 = 0;
    while (i < 8) {
        let v: u32 = s.h[i];
        s.dig[i * 4] = ((v >> 24) & 255) as u8;
        s.dig[i * 4 + 1] = ((v >> 16) & 255) as u8;
        s.dig[i * 4 + 2] = ((v >> 8) & 255) as u8;
        s.dig[i * 4 + 3] = (v & 255) as u8;
        i += 1;
    }
}

fn sha_file(c: &mut Ctx, path: ptr<u8>, out: ptr<u8>) -> i32 {
    let f: ptr<u8> = fopen(path, "rb");
    if (f == null) {
        return 0;
    }
    var s: Sha;
    sha_init(&mut s);
    var got: u64 = fread(c.lp, 1, 1024, f);
    while (got > 0) {
        sha_update(&mut s, c.lp, got as i64);
        got = fread(c.lp, 1, 1024, f);
    }
    fclose(f);
    sha_final(&mut s);
    var k: i64 = 0;
    while (k < 32) {
        wr8(out, k, s.dig[k]);
        k += 1;
    }
    return 1;
}

fn tok_is(p: ptr<u8>, a: i64, b: i64, s: ptr<u8>) -> i32 {
    if (b - a != sl(s)) {
        return 0;
    }
    return sn(ob(p, a), s, b - a);
}

fn parse_index(c: &mut Ctx, ib: ptr<u8>, n: i64, idx: &mut Idx) -> i32 {
    idx.n = 0;
    var i: i64 = 0;
    while (i < n) {
        var j: i64 = i;
        while (j < n && rd8(ib, j) != NEWLINE) {
            j += 1;
        }
        var a: i64 = i;
        while (a < j && ws(rd8(ib, a)) == 1) {
            a += 1;
        }
        if (a < j && rd8(ib, a) != HASH) {
            if (idx.n >= PKGN) {
                printf("rmake: more than %d packages in the index\n", PKGN as i32);
                c.err = 1;
                return 0;
            }
            var t: [i64; 14];
            var nt: i64 = 0;
            var k: i64 = a;
            while (k < j && nt < 7) {
                while (k < j && ws(rd8(ib, k)) == 1) {
                    k += 1;
                }
                if (k >= j) {
                    break;
                }
                let s0: i64 = k;
                while (k < j && ws(rd8(ib, k)) == 0) {
                    k += 1;
                }
                t[nt * 2] = s0;
                t[nt * 2 + 1] = k;
                nt += 1;
            }
            if (nt < 7) {
                printf("rmake: bad index line at byte %d\n", i as i32);
                c.err = 1;
                return 0;
            }
            let pi: i64 = idx.n;
            idx.p[pi].name = intern(c, ib, t[0], t[1]);
            idx.p[pi].ver = intern(c, ib, t[2], t[3]);
            idx.p[pi].bytes = dec_val(ob(ib, t[4]), t[5] - t[4]);
            idx.p[pi].sha = intern(c, ib, t[6], t[7]);
            idx.p[pi].file = intern(c, ib, t[8], t[9]);
            idx.p[pi].deps = intern(c, ib, t[10], t[11]);
            idx.p[pi].inc = intern(c, ib, t[12], t[13]);
            idx.n += 1;
        }
        i = j + 1;
    }
    return 1;
}

fn vcmp(a: ptr<u8>, b: ptr<u8>) -> i32 {
    var i: i64 = 0;
    var j: i64 = 0;
    let na: i64 = sl(a);
    let nb: i64 = sl(b);
    while (1 == 1) {
        var x: i64 = 0;
        while (i < na && rd8(a, i) != PERIOD) {
            let d: u8 = rd8(a, i);
            if (d >= 48 && d <= 57) {
                x = x * 10 + ((d - 48) as i64);
            }
            i += 1;
        }
        var y: i64 = 0;
        while (j < nb && rd8(b, j) != PERIOD) {
            let d: u8 = rd8(b, j);
            if (d >= 48 && d <= 57) {
                y = y * 10 + ((d - 48) as i64);
            }
            j += 1;
        }
        if (x != y) {
            if (x > y) {
                return 1;
            }
            return -1;
        }
        if (i >= na && j >= nb) {
            return 0;
        }
        if (i < na) {
            i += 1;
        }
        if (j < nb) {
            j += 1;
        }
    }
    return 0;
}

fn find_pkg(c: &mut Ctx, idx: &mut Idx, name: ptr<u8>, want: ptr<u8>) -> i64 {
    var best: i64 = -1;
    var i: i64 = 0;
    while (i < idx.n) {
        if (sq(ob(c.bp, idx.p[i].name), name) == 1) {
            if (want != null && sl(want) > 0) {
                if (sq(ob(c.bp, idx.p[i].ver), want) == 1) {
                    return i;
                }
            } else if (best < 0) {
                best = i;
            } else if (vcmp(ob(c.bp, idx.p[i].ver), ob(c.bp, idx.p[best].ver)) > 0) {
                best = i;
            }
        }
        i += 1;
    }
    return best;
}

fn in_list(order: &mut [i64; 32], n: i64, v: i64) -> i32 {
    var k: i64 = 0;
    while (k < n) {
        if (order[k] == v) {
            return 1;
        }
        k += 1;
    }
    return 0;
}

fn plan(c: &mut Ctx, idx: &mut Idx, i: i64, depth: i64, order: &mut [i64; 32], n: &mut i64) -> i32 {
    if (depth > 16) {
        printf("rmake: dependency chain deeper than 16\n");
        c.err = 1;
        return 0;
    }
    if (in_list(order, *n, i) == 1) {
        return 1;
    }
    if (*n >= PKGN) {
        printf("rmake: more than %d packages to install\n", PKGN as i32);
        c.err = 1;
        return 0;
    }
    let d: ptr<u8> = ob(c.bp, idx.p[i].deps);
    let dn: i64 = sl(d);
    if (dn > 0 && sq(d, "-") == 0) {
        var k: i64 = 0;
        while (k < dn) {
            var e: i64 = k;
            while (e < dn && rd8(d, e) != 44) {
                e += 1;
            }
            if (e > k) {
                var tmp: [u8; 128];
                var q: ptr<u8> = null;
                unsafe { q = &mut tmp[0] as ptr<u8>; }
                var m: i64 = 0;
                while (k + m < e && m < 127) {
                    wr8(q, m, rd8(d, k + m));
                    m += 1;
                }
                wr8(q, m, 0);
                let j: i64 = find_pkg(c, idx, q, null);
                if (j < 0) {
                    printf("rmake: missing dependency '%s' for '%s'\n", q, ob(c.bp, idx.p[i].name));
                    c.err = 1;
                    return 0;
                }
                if (plan(c, idx, j, depth + 1, order, n) == 0) {
                    return 0;
                }
            }
            k = e + 1;
        }
    }
    order[*n] = i;
    *n += 1;
    return 1;
}

fn rec_path(c: &mut Ctx) -> ptr<u8> {
    p_reset(c);
    p_cat(c, ".rmake/pkgs");
    return p_end(c);
}

fn rec_match(c: &mut Ctx, rb: ptr<u8>, rn: i64, name: ptr<u8>, ver: ptr<u8>) -> i32 {
    var i: i64 = 0;
    while (i < rn) {
        var j: i64 = i;
        while (j < rn && rd8(rb, j) != NEWLINE) {
            j += 1;
        }
        var a: i64 = i;
        while (a < j && ws(rd8(rb, a)) == 1) {
            a += 1;
        }
        var e: i64 = a;
        while (e < j && ws(rd8(rb, e)) == 0) {
            e += 1;
        }
        if (tok_is(rb, a, e, name) == 1) {
            var z: i64 = e;
            while (z < j && ws(rd8(rb, z)) == 1) {
                z += 1;
            }
            var w: i64 = z;
            while (w < j && ws(rd8(rb, w)) == 0) {
                w += 1;
            }
            if (tok_is(rb, z, w, ver) == 1) {
                return 1;
            }
        }
        i = j + 1;
    }
    return 0;
}

fn rec_line(q: ptr<u8>, name: ptr<u8>, ver: ptr<u8>, files: ptr<u8>) -> i64 {
    var m: i64 = 0;
    m += cstr(q, name);
    wr8(q, m, SPACE);
    m += 1;
    m += cstr(ob(q, m), ver);
    wr8(q, m, SPACE);
    m += 1;
    m += cstr(ob(q, m), files);
    wr8(q, m, NEWLINE);
    m += 1;
    wr8(q, m, 0);
    return m;
}

fn rec_set(c: &mut Ctx, rb: ptr<u8>, rn: i64, name: ptr<u8>, ver: ptr<u8>, files: ptr<u8>) -> i32 {
    let rp: ptr<u8> = rec_path(c);
    if (c.err != 0) {
        return 0;
    }
    let f: ptr<u8> = fopen(rp, "wb");
    if (f == null) {
        printf("rmake: cannot write '%s'\n", rp);
        return 0;
    }
    var buf: [u8; 1024];
    var q: ptr<u8> = null;
    unsafe { q = &mut buf[0] as ptr<u8>; }
    var hit: i32 = 0;
    var i: i64 = 0;
    while (i < rn) {
        var j: i64 = i;
        while (j < rn && rd8(rb, j) != NEWLINE) {
            j += 1;
        }
        var a: i64 = i;
        while (a < j && ws(rd8(rb, a)) == 1) {
            a += 1;
        }
        var e: i64 = a;
        while (e < j && ws(rd8(rb, e)) == 0) {
            e += 1;
        }
        if (tok_is(rb, a, e, name) == 1) {
            if (hit == 0) {
                let m: i64 = rec_line(q, name, ver, files);
                fwrite(q, 1, m as u64, f);
                hit = 1;
            }
        } else if (j > a) {
            fwrite(ob(rb, a), 1, (j - a) as u64, f);
            fwrite("\n", 1, 1, f);
        }
        i = j + 1;
    }
    if (hit == 0) {
        let m: i64 = rec_line(q, name, ver, files);
        fwrite(q, 1, m as u64, f);
    }
    fclose(f);
    return 1;
}

fn rec_drop(c: &mut Ctx, rb: ptr<u8>, rn: i64, name: ptr<u8>) -> i32 {
    let rp: ptr<u8> = rec_path(c);
    if (c.err != 0) {
        return 0;
    }
    let f: ptr<u8> = fopen(rp, "wb");
    if (f == null) {
        return 0;
    }
    var i: i64 = 0;
    while (i < rn) {
        var j: i64 = i;
        while (j < rn && rd8(rb, j) != NEWLINE) {
            j += 1;
        }
        var a: i64 = i;
        while (a < j && ws(rd8(rb, a)) == 1) {
            a += 1;
        }
        var e: i64 = a;
        while (e < j && ws(rd8(rb, e)) == 0) {
            e += 1;
        }
        if (tok_is(rb, a, e, name) == 0 && j > a) {
            fwrite(ob(rb, a), 1, (j - a) as u64, f);
            fwrite("\n", 1, 1, f);
        }
        i = j + 1;
    }
    fclose(f);
    return 1;
}

fn rec_files(c: &mut Ctx, rb: ptr<u8>, rn: i64, name: ptr<u8>, out: ptr<u8>) -> i32 {
    wr8(out, 0, 0);
    var i: i64 = 0;
    while (i < rn) {
        var j: i64 = i;
        while (j < rn && rd8(rb, j) != NEWLINE) {
            j += 1;
        }
        var a: i64 = i;
        while (a < j && ws(rd8(rb, a)) == 1) {
            a += 1;
        }
        var e: i64 = a;
        while (e < j && ws(rd8(rb, e)) == 0) {
            e += 1;
        }
        if (tok_is(rb, a, e, name) == 1) {
            var z: i64 = e;
            while (z < j && ws(rd8(rb, z)) == 1) {
                z += 1;
            }
            var w: i64 = z;
            while (w < j && ws(rd8(rb, w)) == 0) {
                w += 1;
            }
            var t: i64 = w;
            while (t < j && ws(rd8(rb, t)) == 1) {
                t += 1;
            }
            var n: i64 = 0;
            while (t < j && n < LISTB - 1) {
                wr8(out, n, rd8(rb, t));
                n += 1;
                t += 1;
            }
            wr8(out, n, 0);
            return 1;
        }
        i = j + 1;
    }
    return 0;
}

fn safe_entry(p: ptr<u8>) -> i32 {
    let n: i64 = sl(p);
    if (n < 5) {
        return 0;
    }
    if (sn(p, "lib/", 4) == 0) {
        return 0;
    }
    var k: i64 = 0;
    while (k < n) {
        let b: u8 = rd8(p, k);
        if (b == BSLASH || b == COLON) {
            return 0;
        }
        if (b == PERIOD && k + 1 < n && rd8(p, k + 1) == PERIOD) {
            return 0;
        }
        k += 1;
    }
    return 1;
}

fn dir_of_ptr(c: &mut Ctx, p: ptr<u8>) -> ptr<u8> {
    let n: i64 = sl(p);
    var cut: i64 = 0;
    var k: i64 = n - 1;
    var hit: i32 = 0;
    while (k >= 0) {
        if (rd8(p, k) == SLASH) {
            cut = k;
            hit = 1;
            k = -1;
        } else {
            k -= 1;
        }
    }
    if (hit == 0) {
        cut = 0;
    }
    if (cut >= 1024) {
        cut = 1023;
    }
    var m: i64 = 0;
    while (m < cut) {
        wr8(c.tp, TS3 + m, rd8(p, m));
        m += 1;
    }
    wr8(c.tp, TS3 + cut, 0);
    return ob(c.tp, TS3);
}

fn list_add(out: ptr<u8>, at: &mut i64, rel: ptr<u8>) {
    let n: i64 = sl(rel);
    var k: i64 = 0;
    if (*at > 0) {
        wr8(out, *at, 44);
        *at += 1;
    }
    while (k < n && *at < LISTB - 1) {
        wr8(out, *at, rd8(rel, k));
        *at += 1;
        k += 1;
    }
    wr8(out, *at, 0);
}

fn unpack(c: &mut Ctx, rsp: ptr<u8>, list: ptr<u8>) -> i32 {
    var name: [u8; PATHB];
    var np: ptr<u8> = null;
    unsafe { np = &mut name[0] as ptr<u8>; }
    cstr(np, rsp);
    let f: ptr<u8> = fopen(np, "rb");
    if (f == null) {
        printf("rmake: cannot read '%s'\n", np);
        return 0;
    }
    var line: ptr<u8> = fgets(c.lp, MAXL, f);
    if (line == null) {
        fclose(f);
        printf("rmake: '%s' is not a package\n", np);
        return 0;
    }
    if (sn(c.lp, "rspkg 1", 7) == 0) {
        fclose(f);
        printf("rmake: '%s' is not a package\n", np);
        return 0;
    }
    var count: i64 = 0;
    var lat: i64 = 0;
    wr8(list, 0, 0);
    while (1 == 1) {
        line = fgets(c.lp, MAXL, f);
        if (line == null) {
            break;
        }
        let n: i64 = sl(c.lp);
        if (n == 0) {
            break;
        }
        if (sn(c.lp, "file ", 5) == 0) {
            fclose(f);
            printf("rmake: bad entry in '%s'\n", np);
            return 0;
        }
        var a: i64 = 5;
        var b: i64 = a;
        while (b < n && ws(rd8(c.lp, b)) == 0) {
            b += 1;
        }
        var s0: i64 = b;
        while (s0 < n && ws(rd8(c.lp, s0)) == 1) {
            s0 += 1;
        }
        let size: i64 = dec_val(ob(c.lp, s0), n - s0);
        var rel: [u8; PATHB];
        var q: ptr<u8> = null;
        unsafe { q = &mut rel[0] as ptr<u8>; }
        var m: i64 = 0;
        var k: i64 = a;
        while (k < b && m < PATHB - 1) {
            wr8(q, m, rd8(c.lp, k));
            m += 1;
            k += 1;
        }
        wr8(q, m, 0);
        if (b >= n || size < 0 || safe_entry(q) == 0) {
            fclose(f);
            printf("rmake: unsafe path in '%s'\n", np);
            return 0;
        }
        p_at_root(c, q);
        var out: [u8; PATHB];
        var op: ptr<u8> = null;
        unsafe { op = &mut out[0] as ptr<u8>; }
        cstr(op, p_end(c));
        mkdir_p(c, dir_of_ptr(c, op));
        let g: ptr<u8> = fopen(op, "wb");
        if (g == null) {
            fclose(f);
            printf("rmake: cannot write '%s'\n", op);
            return 0;
        }
        var left: i64 = size;
        while (left > 0) {
            var chunk: i64 = 1024;
            if (left < chunk) {
                chunk = left;
            }
            let got: u64 = fread(c.tp, 1, chunk as u64, f);
            if (got == 0) {
                fclose(g);
                fclose(f);
                printf("rmake: '%s' ends early\n", np);
                return 0;
            }
            fwrite(c.tp, 1, got, g);
            left -= got as i64;
        }
        fclose(g);
        fgets(c.lp, MAXL, f);
        list_add(list, &mut lat, q);
        count += 1;
    }
    fclose(f);
    if (count == 0) {
        printf("rmake: '%s' holds no files\n", np);
        return 0;
    }
    return 1;
}

fn tmp_path(c: &mut Ctx, file: ptr<u8>) -> ptr<u8> {
    p_reset(c);
    p_cat(c, ".rmake/");
    p_cat(c, file);
    return p_end(c);
}

fn install_one(c: &mut Ctx, idx: &mut Idx, i: i64, base: ptr<u8>, rb: ptr<u8>, rn: i64) -> i32 {
    let name: ptr<u8> = ob(c.bp, idx.p[i].name);
    let ver: ptr<u8> = ob(c.bp, idx.p[i].ver);
    if (rec_match(c, rb, rn, name, ver) == 1) {
        printf("  ok    %s %s\n", name, ver);
        return 1;
    }
    let file: ptr<u8> = ob(c.bp, idx.p[i].file);
    var tmp: [u8; PATHB];
    var tp: ptr<u8> = null;
    unsafe { tp = &mut tmp[0] as ptr<u8>; }
    cstr(tp, tmp_path(c, file));
    if (c.err != 0) {
        return 0;
    }
    var url: [u8; 768];
    var up: ptr<u8> = null;
    unsafe { up = &mut url[0] as ptr<u8>; }
    var m: i64 = 0;
    m = cstr(up, base);
    wr8(up, m, SLASH);
    m += 1;
    cstr(ob(up, m), file);
    printf("  get   %s %s\n", name, ver);
    if (fetch(c, up, tp) != 0) {
        printf("rmake: cannot fetch '%s'\n", up);
        printf("rmake: set RMAKE_REPO to a mirror or a local directory\n");
        return 0;
    }
    var dig: [u8; 32];
    var dp: ptr<u8> = null;
    unsafe { dp = &mut dig[0] as ptr<u8>; }
    if (sha_file(c, tp, dp) == 0) {
        printf("rmake: cannot read '%s'\n", tp);
        remove(tp);
        return 0;
    }
    if (hex_eq(dp, ob(c.bp, idx.p[i].sha)) == 0) {
        printf("rmake: checksum mismatch for '%s' - dropping it\n", name);
        remove(tp);
        return 0;
    }
    var files: [u8; LISTB];
    var fp: ptr<u8> = null;
    unsafe { fp = &mut files[0] as ptr<u8>; }
    if (unpack(c, tp, fp) == 0) {
        remove(tp);
        return 0;
    }
    remove(tp);
    if (rec_set(c, rb, rn, name, ver, fp) == 0) {
        return 0;
    }
    printf("  use   include \"%s\";\n", ob(c.bp, idx.p[i].inc));
    return 1;
}

fn pkg_install(c: &mut Ctx, repo: i64) -> i32 {
    if (c.npos < 2) {
        printf("rmake: install needs a package name\n");
        return 2;
    }
    var base: ptr<u8> = null;
    if (repo != 0) {
        base = ob(c.bp, repo);
    } else {
        base = getenv("RMAKE_REPO");
        if (base == null || sl(base) == 0) {
            base = repo_default();
        }
    }
    if (sl(base) < 1 || sl(base) > 480) {
        printf("rmake: repository URL is empty or too long\n");
        return 2;
    }
    var bbuf: [u8; 512];
    var bq: ptr<u8> = null;
    unsafe { bq = &mut bbuf[0] as ptr<u8>; }
    var bn: i64 = sl(base);
    var bi: i64 = 0;
    while (bi < bn) {
        wr8(bq, bi, rd8(base, bi));
        bi += 1;
    }
    while (bn > 0 && rd8(bq, bn - 1) == SLASH) {
        bn -= 1;
    }
    wr8(bq, bn, 0);
    base = bq;

    let ib: ptr<u8> = zalloc(IDXB);
    let rb: ptr<u8> = zalloc(RECB);
    if (ib == null || rb == null) {
        printf("rmake: out of memory\n");
        return 1;
    }
    var idx: Idx;
    var ipath: [u8; PATHB];
    var ip: ptr<u8> = null;
    unsafe { ip = &mut ipath[0] as ptr<u8>; }
    cstr(ip, tmp_path(c, "index.txt"));
    if (c.err != 0) {
        return 1;
    }
    var iurl: [u8; 768];
    var up: ptr<u8> = null;
    unsafe { up = &mut iurl[0] as ptr<u8>; }
    var m: i64 = cstr(up, base);
    wr8(up, m, SLASH);
    m += 1;
    cstr(ob(up, m), "index.txt");
    if (fetch(c, up, ip) != 0) {
        printf("rmake: cannot fetch '%s'\n", up);
        printf("rmake: set RMAKE_REPO to a mirror or a local directory\n");
        return 1;
    }
    let n: i64 = rd_all(ip, ib, IDXB);
    if (n <= 0) {
        printf("rmake: cannot read '%s'\n", ip);
        return 1;
    }
    if (parse_index(c, ib, n, &mut idx) == 0) {
        return 1;
    }
    var rpath: [u8; PATHB];
    var rp: ptr<u8> = null;
    unsafe { rp = &mut rpath[0] as ptr<u8>; }
    cstr(rp, rec_path(c));
    var rl: i64 = rd_all(rp, rb, RECB);
    if (rl < 0) {
        rl = 0;
    }
    var ord: [i64; 32];
    var nord: i64 = 0;
    var k: i64 = 1;
    while (k < c.npos) {
        let spec: ptr<u8> = ob(c.bp, c.pos[k]);
        var nm: [u8; 256];
        var np: ptr<u8> = null;
        unsafe { np = &mut nm[0] as ptr<u8>; }
        var vr: [u8; 64];
        var vp: ptr<u8> = null;
        unsafe { vp = &mut vr[0] as ptr<u8>; }
        var e: i64 = 0;
        while (e < sl(spec) && rd8(spec, e) != 64) {
            e += 1;
        }
        var t: i64 = 0;
        while (t < e && t < 250) {
            wr8(np, t, rd8(spec, t));
            t += 1;
        }
        wr8(np, t, 0);
        t = 0;
        if (e < sl(spec)) {
            var z: i64 = e + 1;
            while (z < sl(spec) && t < 60) {
                wr8(vp, t, rd8(spec, z));
                t += 1;
                z += 1;
            }
        }
        wr8(vp, t, 0);
        let j: i64 = find_pkg(c, &mut idx, np, vp);
        if (j < 0) {
            printf("rmake: no package named '%s'\n", np);
            return 1;
        }
        if (plan(c, &mut idx, j, 0, &mut ord, &mut nord) == 0) {
            return 1;
        }
        k += 1;
    }
    var done: i32 = 0;
    k = 0;
    while (k < nord) {
        if (install_one(c, &mut idx, ord[k], base, rb, rl) == 0) {
            return 1;
        }
        done += 1;
        rl = rd_all(rp, rb, RECB);
        if (rl < 0) {
            rl = 0;
        }
        k += 1;
    }
    if (done == 1) {
        printf("rmake: 1 package installed\n");
    } else {
        printf("rmake: %d packages installed\n", done);
    }
    return 0;
}

fn rm_rel(c: &mut Ctx, rel: ptr<u8>) -> i32 {
    var buf: [u8; PATHB];
    var bp2: ptr<u8> = null;
    unsafe { bp2 = &mut buf[0] as ptr<u8>; }
    p_at_root(c, rel);
    if (c.err != 0) {
        return 0;
    }
    cstr(bp2, p_end(c));
    if (remove(bp2) == 0) {
        return 1;
    }
    return 0;
}

fn pkg_remove(c: &mut Ctx) -> i32 {
    if (c.npos < 2) {
        printf("rmake: remove needs a package name\n");
        return 2;
    }
    let rb: ptr<u8> = zalloc(RECB);
    if (rb == null) {
        printf("rmake: out of memory\n");
        return 1;
    }
    var rpath: [u8; PATHB];
    var rp: ptr<u8> = null;
    unsafe { rp = &mut rpath[0] as ptr<u8>; }
    cstr(rp, rec_path(c));
    var rl: i64 = rd_all(rp, rb, RECB);
    if (rl < 0) {
        rl = 0;
    }
    var k: i64 = 1;
    while (k < c.npos) {
        let name: ptr<u8> = ob(c.bp, c.pos[k]);
        var files: [u8; LISTB];
        var fp: ptr<u8> = null;
        unsafe { fp = &mut files[0] as ptr<u8>; }
        if (rec_files(c, rb, rl, name, fp) == 0) {
            printf("rmake: '%s' is not installed\n", name);
            return 1;
        }
        var f: i64 = 0;
        var got: i32 = 0;
        while (f < sl(fp)) {
            var e: i64 = f;
            while (e < sl(fp) && rd8(fp, e) != 44) {
                e += 1;
            }
            if (e > f) {
                var one: [u8; PATHB];
                var op: ptr<u8> = null;
                unsafe { op = &mut one[0] as ptr<u8>; }
                var m: i64 = 0;
                var s: i64 = f;
                while (s < e && m < PATHB - 1) {
                    wr8(op, m, rd8(fp, s));
                    m += 1;
                    s += 1;
                }
                wr8(op, m, 0);
                rm_rel(c, op);
                printf("  rm    %s\n", op);
                got += 1;
            }
            f = e + 1;
        }
        if (got == 0) {
            printf("rmake: '%s' has no recorded files\n", name);
        }
        rec_drop(c, rb, rl, name);
        rl = rd_all(rp, rb, RECB);
        if (rl < 0) {
            rl = 0;
        }
        k += 1;
    }
    printf("rmake: removed\n");
    return 0;
}

fn pkg_list(c: &mut Ctx) -> i32 {
    let rb: ptr<u8> = zalloc(RECB);
    if (rb == null) {
        printf("rmake: out of memory\n");
        return 1;
    }
    var rpath: [u8; PATHB];
    var rp: ptr<u8> = null;
    unsafe { rp = &mut rpath[0] as ptr<u8>; }
    cstr(rp, rec_path(c));
    let rn: i64 = rd_all(rp, rb, RECB);
    if (rn <= 0) {
        printf("rmake: no packages installed\n");
        return 0;
    }
    var count: i64 = 0;
    var i: i64 = 0;
    while (i < rn) {
        var j: i64 = i;
        while (j < rn && rd8(rb, j) != NEWLINE) {
            j += 1;
        }
        var a: i64 = i;
        while (a < j && ws(rd8(rb, a)) == 1) {
            a += 1;
        }
        if (j > a) {
            var a2: i64 = a;
            while (a2 < j && ws(rd8(rb, a2)) == 0) {
                a2 += 1;
            }
            var v0: i64 = a2;
            while (v0 < j && ws(rd8(rb, v0)) == 1) {
                v0 += 1;
            }
            var v1: i64 = v0;
            while (v1 < j && ws(rd8(rb, v1)) == 0) {
                v1 += 1;
            }
            printf("  %.*s %.*s\n", (a2 - a) as i32, ob(rb, a), (v1 - v0) as i32, ob(rb, v0));
            count += 1;
        }
        i = j + 1;
    }
    printf("rmake: %d installed\n", count);
    return 0;
}
