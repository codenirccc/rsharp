extern fn malloc(n: u64) -> ptr<u8>;
extern fn realloc(p: ptr<u8>, n: u64) -> ptr<u8>;
extern fn free(p: ptr<u8>) -> void;
extern fn memcpy(d: ptr<u8>, s: ptr<u8>, n: u64) -> ptr<u8>;
extern fn memset(d: ptr<u8>, c: i32, n: u64) -> ptr<u8>;
extern fn strlen(s: ptr<u8>) -> u64;
extern fn sprintf(dst: ptr<u8>, fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn strtod(s: ptr<u8>, end: ptr<u8>) -> f64;
extern "kernel32" fn WriteFile(h: i64, buf: ptr<u8>, n: u32, wrote: ptr<u32>, ov: ptr<u8>) -> i32;

fn p_off(p: ptr<u8>, i: i64) -> ptr<u8> {
    var q: ptr<u8> = null;
    unsafe { q = p + i; }
    return q;
}

fn p_u8(v: &mut u8) -> ptr<u8> {
    var q: ptr<u8> = null;
    unsafe { q = v as ptr<u8>; }
    return q;
}

fn p_u32(v: &mut u32) -> ptr<u32> {
    var q: ptr<u32> = null;
    unsafe { q = v as ptr<u32>; }
    return q;
}

struct Sb {
    p: ptr<u8>,
    n: i64,
    cap: i64,
    bad: i32,
    fd: i64,
    total: i64
}

const SB_SPILL: i64 = 1048576;

fn sb_spill(b: &mut Sb, fd: i64) {
    b.fd = fd;
}

fn sb_flush(b: &mut Sb) -> i32 {
    var off: i64 = 0;
    var failed: i32 = 0;
    let fd: i64 = b.fd;
    let n: i64 = b.n;
    b.n = 0;
    b.total = b.total + n;
    if (fd == 0 || n <= 0) {
        return 0;
    }
    unsafe {
        while (off < n) {
            var wrote: u32 = 0;
            let ok: i32 = WriteFile(fd, b.p + off, (n - off) as u32, &wrote as ptr<u32>, null);
            if (ok != 1 || wrote == 0) {
                failed = 1;
                break;
            }
            off = off + (wrote as i64);
        }
    }
    if (failed == 1) {
        b.bad = 1;
        return 0 - 1;
    }
    return 0;
}

fn sb_new(cap: i64) -> Sb {
    var b: Sb = zero(Sb);
    if (cap < 32) {
        cap = 32;
    }
    b.p = malloc(cap as u64);
    if (b.p != null) {
        b.cap = cap;
    } else {
        b.bad = 1;
    }
    return b;
}

fn sb_free(b: &mut Sb) {
    if (b.p != null) {
        free(b.p);
        b.p = null;
    }
    b.n = 0;
    b.cap = 0;
    b.bad = 0;
}

fn sb_reserve(b: &mut Sb, extra: i64) -> i32 {
    if (b.bad == 1 || extra < 0) {
        b.bad = 1;
        return 0 - 1;
    }
    if (b.fd != 0 && b.n + extra > SB_SPILL) {
        if (sb_flush(b) != 0) {
            return 0 - 1;
        }
    }
    let need: i64 = b.n + extra;
    if (need <= b.cap) {
        return 0;
    }
    var cap: i64 = b.cap;
    if (cap < 32) {
        cap = 32;
    }
    while (cap < need) {
        if (cap > 1073741824) {
            b.bad = 1;
            return 0 - 1;
        }
        var grow: i64 = cap / 2;
        if (grow < 4096) {
            grow = 4096;
        }
        cap = cap + grow;
    }
    var np: ptr<u8> = realloc(b.p, cap as u64);
    if (np == null) {
        b.bad = 1;
        return 0 - 1;
    }
    b.p = np;
    b.cap = cap;
    return 0;
}

fn sb_put(b: &mut Sb, src: ptr<u8>, n: i64) -> i32 {
    if (n <= 0) {
        return 0;
    }
    if (sb_reserve(b, n) != 0) {
        return 0 - 1;
    }
    var dst: ptr<u8> = null;
    unsafe { dst = b.p + b.n; }
    memcpy(dst, src, n as u64);
    b.n += n;
    return 0;
}

fn sb_putc(b: &mut Sb, c: u8) -> i32 {
    if (sb_reserve(b, 1) != 0) {
        return 0 - 1;
    }
    unsafe { b.p[b.n] = c; }
    b.n += 1;
    return 0;
}

fn sb_puts(b: &mut Sb, s: ptr<u8>) -> i32 {
    return sb_put(b, s, strlen(s) as i64);
}

fn sb_clear(b: &mut Sb) {
    b.n = 0;
}

fn sb_drop(b: &mut Sb, n: i64) {
    if (n <= 0) {
        return;
    }
    if (n >= b.n) {
        b.n = 0;
        return;
    }
    b.n -= n;
}

fn sb_i64(b: &mut Sb, v: i64) {
    var tmp: [u8; 24] = [0];
    var i: i64 = 24;
    var n: i64 = v;
    var neg: i32 = 0;
    if (n < 0) {
        neg = 1;
        n = 0 - n;
    }
    if (n == 0) {
        i -= 1;
        tmp[i] = 48;
    }
    while (n > 0) {
        i -= 1;
        tmp[i] = (48 + (n % 10)) as u8;
        n = n / 10;
    }
    if (neg == 1) {
        i -= 1;
        tmp[i] = 45;
    }
    var k: i64 = i;
    while (k < 24) {
        sb_putc(b, tmp[k]);
        k += 1;
    }
}

fn sb_esc(b: &mut Sb, p: ptr<u8>, n: i64) {
    sb_putc(b, 34);
    var i: i64 = 0;
    while (i < n) {
        var c: u8 = 0;
        unsafe { c = p[i]; }
        if (c == 92) {
            sb_puts(b, "\\\\");
        } else if (c == 34) {
            sb_puts(b, "\\\"");
        } else if (c == 10) {
            sb_puts(b, "\\n");
        } else if (c == 9) {
            sb_puts(b, "\\t");
        } else if (c == 13) {
            sb_puts(b, "\\r");
        } else if (c >= 32 && c <= 126) {
            sb_putc(b, c);
        } else {
            sb_putc(b, 92);
            sb_putc(b, (48 + (c >> 6)) as u8);
            sb_putc(b, (48 + ((c >> 3) & 7)) as u8);
            sb_putc(b, (48 + (c & 7)) as u8);
        }
        i += 1;
    }
    sb_putc(b, 34);
}

fn utf8_cp(p: ptr<u8>, n: i64, i: i64) -> i64 {
    var c: u8 = 0;
    unsafe { c = p[i]; }
    if (c < 128) {
        return c as i64;
    }
    var need: i64 = 0;
    var cp: i64 = 0;
    if ((c & 224) == 192) {
        need = 1;
        cp = (c & 31) as i64;
    } else if ((c & 240) == 224) {
        need = 2;
        cp = (c & 15) as i64;
    } else if ((c & 248) == 240) {
        need = 3;
        cp = (c & 7) as i64;
    } else {
        return 0 - 1;
    }
    if (i + need >= n) {
        return 0 - 1;
    }
    var k: i64 = 1;
    while (k <= need) {
        var cc: u8 = 0;
        unsafe { cc = p[i + k]; }
        if ((cc & 192) != 128) {
            return 0 - 1;
        }
        cp = (cp << 6) | ((cc & 63) as i64);
        k += 1;
    }
    return cp;
}

fn utf8_adv(c: u8) -> i64 {
    if (c < 128) {
        return 1;
    }
    if ((c & 224) == 192) {
        return 2;
    }
    if ((c & 240) == 224) {
        return 3;
    }
    if ((c & 248) == 240) {
        return 4;
    }
    return 1;
}

fn esc_keep(cp: i64) -> i32 {
    if (cp < 32 || cp == 127) {
        return 0;
    }
    if (cp >= 128 && cp <= 159) {
        return 0;
    }
    if (cp == 32) {
        return 1;
    }
    if (cp == 160) {
        return 0;
    }
    if (cp >= 0x2000 && cp <= 0x200A) {
        return 0;
    }
    if (cp == 0x2028 || cp == 0x2029) {
        return 0;
    }
    if (cp == 0x202F || cp == 0x205F || cp == 0x3000) {
        return 0;
    }
    if (cp >= 0x200B && cp <= 0x200F) {
        return 0;
    }
    if (cp >= 0x202A && cp <= 0x202E) {
        return 0;
    }
    if (cp >= 0x2060 && cp <= 0x2064) {
        return 0;
    }
    if (cp >= 0x2066 && cp <= 0x206F) {
        return 0;
    }
    if (cp == 0xFEFF) {
        return 0;
    }
    if (cp >= 0xFFF9 && cp <= 0xFFFB) {
        return 0;
    }
    if (cp >= 0xE000 && cp <= 0xF8FF) {
        return 0;
    }
    if (cp >= 0xF0000 && cp <= 0xFFFFD) {
        return 0;
    }
    if (cp >= 0x100000 && cp <= 0x10FFFD) {
        return 0;
    }
    if (cp >= 0x300 && cp <= 0x36F) {
        return 0;
    }
    if (cp >= 0x1AB0 && cp <= 0x1AFF) {
        return 0;
    }
    if (cp >= 0x1DC0 && cp <= 0x1DFF) {
        return 0;
    }
    if (cp >= 0x20D0 && cp <= 0x20FF) {
        return 0;
    }
    if (cp >= 0xFE00 && cp <= 0xFE0F) {
        return 0;
    }
    if (cp >= 0xFE20 && cp <= 0xFE2F) {
        return 0;
    }
    if (cp == 0x200D) {
        return 0;
    }
    return 1;
}

fn sb_hexlo(b: &mut Sb, v: i64) {
    if (v == 0) {
        sb_putc(b, 48);
        return;
    }
    var d: [u8; 16] = [0];
    var m: i64 = 0;
    var x: i64 = v;
    while (x > 0) {
        let r: i64 = x % 16;
        var ch: u8 = 48;
        if (r < 10) {
            ch = (48 + r) as u8;
        } else {
            ch = (87 + r) as u8;
        }
        d[m] = ch;
        m += 1;
        x = x / 16;
    }
    var j: i64 = m - 1;
    while (j >= 0) {
        sb_putc(b, d[j]);
        j -= 1;
    }
}

fn sb_dbg(b: &mut Sb, p: ptr<u8>, n: i64) {
    sb_putc(b, 34);
    var i: i64 = 0;
    while (i < n) {
        var c: u8 = 0;
        unsafe { c = p[i]; }
        if (c < 128) {
            if (c == 92) {
                sb_puts(b, "\\\\");
            } else if (c == 34) {
                sb_puts(b, "\\\"");
            } else if (c == 10) {
                sb_puts(b, "\\n");
            } else if (c == 9) {
                sb_puts(b, "\\t");
            } else if (c == 13) {
                sb_puts(b, "\\r");
            } else if (c == 0) {
                sb_puts(b, "\\0");
            } else if (c < 32 || c == 127) {
                sb_puts(b, "\\u{");
                sb_hexlo(b, c as i64);
                sb_putc(b, 125);
            } else {
                sb_putc(b, c);
            }
            i += 1;
            continue;
        }
        let cp: i64 = utf8_cp(p, n, i);
        let adv: i64 = utf8_adv(c);
        if (cp >= 0 && esc_keep(cp) == 1) {
            var k: i64 = 0;
            while (k < adv) {
                var ch: u8 = 0;
                unsafe { ch = p[i + k]; }
                sb_putc(b, ch);
                k += 1;
            }
        } else {
            sb_puts(b, "\\u{");
            if (cp < 0) {
                sb_hexlo(b, 0xFFFD);
            } else {
                sb_hexlo(b, cp);
            }
            sb_putc(b, 125);
        }
        i += adv;
    }
    sb_putc(b, 34);
}

fn f64_exp(bp: ptr<u8>, v: f64, prec: i32) {
    var fmt: [u8; 8] = [0];
    fmt[0] = 37;
    fmt[1] = 46;
    var k: i64 = 2;
    if (prec >= 10) {
        fmt[2] = 49;
        fmt[3] = (48 + prec - 10) as u8;
        k = 4;
    } else {
        fmt[2] = (48 + prec) as u8;
        k = 3;
    }
    fmt[k] = 101;
    fmt[k + 1] = 0;
    var fp: ptr<u8> = null;
    unsafe { fp = &mut fmt[0] as ptr<u8>; }
    sprintf(bp, fp, v);
}

fn f64_parts(bp: ptr<u8>, dig: ptr<u8>, out: ptr<i64>) -> i64 {
    var i: i64 = 0;
    var nd: i64 = 0;
    var c: u8 = 0;
    while (true) {
        unsafe { c = bp[i]; }
        if (c == 101) {
            break;
        }
        if (c != 46) {
            unsafe { dig[nd] = c; }
            nd += 1;
        }
        i += 1;
    }
    i += 1;
    var esign: i64 = 1;
    unsafe { c = bp[i]; }
    if (c == 43) {
        i += 1;
    } else if (c == 45) {
        esign = 0 - 1;
        i += 1;
    }
    var e: i64 = 0;
    while (true) {
        unsafe { c = bp[i]; }
        if (c < 48 || c > 57) {
            break;
        }
        e = e * 10 + ((c - 48) as i64);
        i += 1;
    }
    while (nd > 1) {
        var dz: u8 = 0;
        unsafe { dz = dig[nd - 1]; }
        if (dz != 48) {
            break;
        }
        nd -= 1;
    }
    unsafe { out[0] = nd; }
    unsafe { out[1] = e * esign; }
    return nd;
}

fn f64_cand(buf: ptr<u8>, dig: ptr<u8>, nd: i64, e: i64) {
    var k: i64 = 0;
    unsafe {
        buf[0] = dig[0];
        k = 1;
        if (nd > 1) {
            buf[k] = 46;
            k += 1;
            var i: i64 = 1;
            while (i < nd) {
                buf[k] = dig[i];
                k += 1;
                i += 1;
            }
        }
        buf[k] = 101;
        k += 1;
        if (e < 0) {
            buf[k] = 45;
        } else {
            buf[k] = 43;
        }
        k += 1;
        var ae: i64 = e;
        if (ae < 0) {
            ae = 0 - ae;
        }
        var d: [u8; 8] = [0];
        var m: i64 = 0;
        if (ae == 0) {
            d[0] = 48;
            m = 1;
        }
        while (ae > 0) {
            d[m] = (48 + (ae % 10)) as u8;
            m += 1;
            ae = ae / 10;
        }
        var j: i64 = m - 1;
        while (j >= 0) {
            buf[k] = d[j];
            k += 1;
            j -= 1;
        }
        buf[k] = 0;
    }
}

fn f64_trim(dig: ptr<u8>, nd: i64) -> i64 {
    var m: i64 = nd;
    unsafe {
        while (m > 1 && dig[m - 1] == 48) {
            m -= 1;
        }
    }
    return m;
}

fn f64_round(dig: ptr<u8>, nd: i64, k: i64, ep: ptr<i64>) -> i64 {
    if (k >= nd) {
        return nd;
    }
    var up: i32 = 0;
    var c: u8 = 0;
    unsafe { c = dig[k]; }
    if (c > 53) {
        up = 1;
    } else if (c == 53) {
        var nz: i32 = 0;
        var j: i64 = k + 1;
        unsafe {
            while (j < nd) {
                if (dig[j] != 48) {
                    nz = 1;
                    break;
                }
                j += 1;
            }
        }
        if (nz == 1) {
            up = 1;
        } else {
            var pv: u8 = 0;
            unsafe { pv = dig[k - 1]; }
            if (((pv - 48) & 1) == 1) {
                up = 1;
            }
        }
    }
    var m: i64 = k;
    if (up == 1) {
        var i: i64 = k - 1;
        var carry: i32 = 1;
        unsafe {
            while (i >= 0) {
                var d: u8 = dig[i] + 1;
                if (d <= 57) {
                    dig[i] = d;
                    carry = 0;
                    break;
                }
                dig[i] = 48;
                i -= 1;
            }
            if (carry == 1) {
                var j: i64 = k;
                while (j > 0) {
                    dig[j] = dig[j - 1];
                    j -= 1;
                }
                dig[0] = 49;
                let e0: i64 = ep[0];
                ep[0] = e0 + 1;
                m = k + 1;
            }
        }
    }
    return m;
}

fn f64_fmt(b: &mut Sb, v: f64, dbg: i32) {
    var m: f64 = v;
    var neg: i32 = 0;
    if (m == 0.0) {
        var inv: f64 = 1.0 / m;
        if (inv < 0.0) {
            sb_putc(b, 45);
        }
        if (dbg == 1) {
            sb_puts(b, "0.0");
        } else {
            sb_puts(b, "0");
        }
        return;
    }
    if (m < 0.0) {
        neg = 1;
        m = 0.0 - m;
    }
    var buf: [u8; 512] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut buf[0] as ptr<u8>; }
    f64_exp(bp, m, 17);
    var dig: [u8; 32] = [0];
    var dp: ptr<u8> = null;
    unsafe { dp = &mut dig[0] as ptr<u8>; }
    var out: [i64; 2] = [0];
    var op: ptr<i64> = null;
    unsafe { op = &mut out[0] as ptr<i64>; }
    var nd: i64 = f64_parts(bp, dp, op);
    var e: i64 = 0;
    unsafe { e = out[1]; }
    var work: [u8; 32] = [0];
    var wp: ptr<u8> = null;
    unsafe { wp = &mut work[0] as ptr<u8>; }
    var cand: [u8; 512] = [0];
    var cp: ptr<u8> = null;
    unsafe { cp = &mut cand[0] as ptr<u8>; }
    var texp: [i64; 1] = [0];
    var tp: ptr<i64> = null;
    unsafe { tp = &mut texp[0] as ptr<i64>; }
    var k: i64 = 1;
    while (k < nd) {
        unsafe {
            var i: i64 = 0;
            while (i < nd) {
                work[i] = dig[i];
                i += 1;
            }
            texp[0] = e;
        }
        var m2: i64 = f64_round(wp, nd, k, tp);
        m2 = f64_trim(wp, m2);
        f64_cand(cp, wp, m2, texp[0]);
        if (strtod(cp, null) == m) {
            unsafe {
                var i: i64 = 0;
                while (i < m2) {
                    dig[i] = work[i];
                    i += 1;
                }
                e = texp[0];
            }
            nd = m2;
            break;
        }
        k += 1;
    }
    if (neg == 1) {
        sb_putc(b, 45);
    }
    if (dbg == 1 && (e < 0 - 4 || e >= 16)) {
        sb_putc(b, dig[0]);
        if (nd > 1) {
            sb_putc(b, 46);
            var k: i64 = 1;
            while (k < nd) {
                sb_putc(b, dig[k]);
                k += 1;
            }
        }
        sb_putc(b, 101);
        sb_i64(b, e);
        return;
    }
    if (e >= 0) {
        var k: i64 = 0;
        while (k <= e) {
            if (k < nd) {
                sb_putc(b, dig[k]);
            } else {
                sb_putc(b, 48);
            }
            k += 1;
        }
        if (k < nd) {
            sb_putc(b, 46);
            while (k < nd) {
                sb_putc(b, dig[k]);
                k += 1;
            }
        } else if (dbg == 1) {
            sb_puts(b, ".0");
        }
    } else {
        sb_puts(b, "0.");
        var z: i64 = 0 - e - 1;
        while (z > 0) {
            sb_putc(b, 48);
            z -= 1;
        }
        var k: i64 = 0;
        while (k < nd) {
            sb_putc(b, dig[k]);
            k += 1;
        }
    }
}

fn sb_f64_dbg(b: &mut Sb, v: f64) {
    f64_fmt(b, v, 1);
}

fn sb_f64_disp(b: &mut Sb, v: f64) {
    f64_fmt(b, v, 0);
}

struct SpEnt {
    off: i64,
    n: i64
}

struct Sp {
    e: ptr<SpEnt>,
    n: i64,
    cap: i64,
    buf: ptr<u8>,
    bn: i64,
    bcap: i64,
    tab: ptr<i64>,
    tcap: i64,
    bad: i32
}

fn sp_hash(p: ptr<u8>, n: i64) -> i64 {
    var h: i64 = 2166136261;
    var i: i64 = 0;
    while (i < n) {
        var c: i64 = 0;
        unsafe { c = p[i] as i64; }
        h = h ^ c;
        h = (h * 16777619) & 4294967295;
        i += 1;
    }
    return h;
}

fn sp_new() -> Sp {
    var s: Sp = zero(Sp);
    s.cap = 64;
    s.e = malloc((s.cap as u64) * sizeof(SpEnt)) as ptr<SpEnt>;
    s.bcap = 4096;
    s.buf = malloc(s.bcap as u64);
    s.tcap = 128;
    s.tab = malloc((s.tcap as u64) * sizeof(i64)) as ptr<i64>;
    if (s.e == null || s.buf == null || s.tab == null) {
        s.bad = 1;
        return s;
    }
    var i: i64 = 0;
    while (i < s.tcap) {
        unsafe { s.tab[i] = 0; }
        i += 1;
    }
    unsafe { s.e[0] = zero(SpEnt); }
    s.n = 1;
    return s;
}

fn sp_free(s: &mut Sp) {
    if (s.e != null) {
        free(s.e as ptr<u8>);
        s.e = null;
    }
    if (s.buf != null) {
        free(s.buf);
        s.buf = null;
    }
    if (s.tab != null) {
        free(s.tab as ptr<u8>);
        s.tab = null;
    }
    s.n = 0;
    s.cap = 0;
    s.bn = 0;
    s.bcap = 0;
    s.tcap = 0;
}

fn sp_grow_ent(s: &mut Sp) -> i32 {
    let nc: i64 = s.cap * 2;
    var raw: ptr<u8> = realloc(s.e as ptr<u8>, (nc as u64) * sizeof(SpEnt));
    if (raw == null) {
        s.bad = 1;
        return 0 - 1;
    }
    s.e = raw as ptr<SpEnt>;
    s.cap = nc;
    return 0;
}

fn sp_grow_buf(s: &mut Sp, n: i64) -> i32 {
    let need: i64 = s.bn + n;
    if (need <= s.bcap) {
        return 0;
    }
    var cap: i64 = s.bcap;
    while (cap < need) {
        cap = cap * 2;
    }
    var np: ptr<u8> = realloc(s.buf, cap as u64);
    if (np == null) {
        s.bad = 1;
        return 0 - 1;
    }
    s.buf = np;
    s.bcap = cap;
    return 0;
}

fn sp_rehash(s: &mut Sp) -> i32 {
    let nc: i64 = s.tcap * 2;
    var nt: ptr<i64> = malloc((nc as u64) * sizeof(i64)) as ptr<i64>;
    if (nt == null) {
        s.bad = 1;
        return 0 - 1;
    }
    var i: i64 = 0;
    while (i < nc) {
        unsafe { nt[i] = 0; }
        i += 1;
    }
    var k: i64 = 1;
    while (k < s.n) {
        var ep: ptr<u8> = null;
        var en: i64 = 0;
        unsafe {
            ep = s.buf + s.e[k].off;
            en = s.e[k].n;
        }
        let h: i64 = sp_hash(ep, en);
        var at: i64 = h & (nc - 1);
        while (true) {
            var cur: i64 = 0;
            unsafe { cur = nt[at]; }
            if (cur == 0) {
                break;
            }
            at = (at + 1) & (nc - 1);
        }
        unsafe { nt[at] = k + 1; }
        k += 1;
    }
    if (s.tab != null) {
        free(s.tab as ptr<u8>);
    }
    s.tab = nt;
    s.tcap = nc;
    return 0;
}

fn sp_intern(s: &mut Sp, p: ptr<u8>, n: i64) -> i64 {
    if (s.bad == 1) {
        return 0;
    }
    if (n <= 0) {
        return 0;
    }
    if (s.n >= s.cap) {
        if (sp_grow_ent(s) != 0) {
            return 0;
        }
    }
    let h: i64 = sp_hash(p, n);
    var at: i64 = h & (s.tcap - 1);
    while (true) {
        var cur: i64 = 0;
        unsafe { cur = s.tab[at]; }
        if (cur == 0) {
            break;
        }
        let id: i64 = cur - 1;
        var ep: ptr<u8> = null;
        var en: i64 = 0;
        unsafe {
            ep = s.buf + s.e[id].off;
            en = s.e[id].n;
        }
        if (en == n) {
            var same: i32 = 1;
            var i: i64 = 0;
            while (i < n) {
                var a: u8 = 0;
                var b: u8 = 0;
                unsafe {
                    a = ep[i];
                    b = p[i];
                }
                if (a != b) {
                    same = 0;
                    break;
                }
                i += 1;
            }
            if (same == 1) {
                return id;
            }
        }
        at = (at + 1) & (s.tcap - 1);
    }
    if (sp_grow_buf(s, n) != 0) {
        return 0;
    }
    var dst: ptr<u8> = null;
    unsafe { dst = s.buf + s.bn; }
    memcpy(dst, p, n as u64);
    let id: i64 = s.n;
    unsafe {
        s.e[id].off = s.bn;
        s.e[id].n = n;
    }
    s.n += 1;
    s.bn += n;
    unsafe { s.tab[at] = id + 1; }
    if (s.n * 2 >= s.tcap) {
        sp_rehash(s);
    }
    return id;
}

fn sp_interns(s: &mut Sp, c: ptr<u8>) -> i64 {
    return sp_intern(s, c, strlen(c) as i64);
}

fn sp_put(s: &mut Sp, dst: &mut Sb, id: i64) {
    if (id <= 0) {
        return;
    }
    var p: ptr<u8> = null;
    var n: i64 = 0;
    unsafe {
        p = s.buf + s.e[id].off;
        n = s.e[id].n;
    }
    sb_put(dst, p, n);
}

fn sp_ptr(s: &mut Sp, id: i64) -> ptr<u8> {
    if (id <= 0) {
        return "";
    }
    var p: ptr<u8> = null;
    unsafe { p = s.buf + s.e[id].off; }
    return p;
}

fn sp_len(s: &mut Sp, id: i64) -> i64 {
    if (id <= 0) {
        return 0;
    }
    var n: i64 = 0;
    unsafe { n = s.e[id].n; }
    return n;
}

fn sp_eqc(s: &mut Sp, id: i64, c: ptr<u8>) -> bool {
    let n: i64 = strlen(c) as i64;
    if (sp_len(s, id) != n) {
        return false;
    }
    if (n == 0) {
        return true;
    }
    var p: ptr<u8> = null;
    unsafe { p = s.buf + s.e[id].off; }
    var i: i64 = 0;
    while (i < n) {
        var a: u8 = 0;
        var b: u8 = 0;
        unsafe {
            a = p[i];
            b = c[i];
        }
        if (a != b) {
            return false;
        }
        i += 1;
    }
    return true;
}

fn c_eq(a: ptr<u8>, b: ptr<u8>) -> bool {
    var i: i64 = 0;
    while (true) {
        var ca: u8 = 0;
        var cb: u8 = 0;
        unsafe {
            ca = a[i];
            cb = b[i];
        }
        if (ca != cb) {
            return false;
        }
        if (ca == 0) {
            return true;
        }
        i += 1;
    }
    return false;
}

struct Lst {
    p: ptr<i64>,
    n: i32,
    cap: i32
}

const LP_SHIFT: i64 = 10;
const LP_BLK: i64 = 1024;
const LP_MASK: i64 = 1023;

struct Lp {
    v: ptr<ptr<Lst>>,
    n: i64,
    nb: i64,
    bcap: i64,
    bad: i32
}

fn lp_at(v: ptr<ptr<Lst>>, id: i64) -> ptr<Lst> {
    var q: ptr<Lst> = null;
    var off: i64 = 0;
    unsafe {
        q = v[id >> LP_SHIFT];
        off = id & LP_MASK;
    }
    unsafe {
        return q + off;
    }
}

fn lp_blk(l: &mut Lp, blk: i64) -> ptr<Lst> {
    var q: ptr<Lst> = null;
    unsafe { q = l.v[blk]; }
    if (q != null) {
        return q;
    }
    q = malloc((LP_BLK as u64) * sizeof(Lst)) as ptr<Lst>;
    if (q == null) {
        l.bad = 1;
        return null;
    }
    unsafe { memset(q as ptr<u8>, 0, (LP_BLK as u64) * sizeof(Lst)); }
    unsafe { l.v[blk] = q; }
    if (l.nb < blk + 1) {
        l.nb = blk + 1;
    }
    return q;
}

fn lp_new() -> Lp {
    var l: Lp = zero(Lp);
    l.bcap = 64;
    l.v = malloc((l.bcap as u64) * sizeof(ptr<Lst>)) as ptr<ptr<Lst>>;
    if (l.v == null) {
        l.bad = 1;
        return l;
    }
    unsafe { memset(l.v as ptr<u8>, 0, (l.bcap as u64) * sizeof(ptr<Lst>)); }
    if (lp_blk(&mut l, 0) == null) {
        return l;
    }
    l.n = 1;
    return l;
}

fn lp_free(l: &mut Lp) {
    if (l.v != null) {
        var b: i64 = 0;
        unsafe {
            while (b < l.bcap) {
                let q: ptr<Lst> = l.v[b];
                if (q != null) {
                    var i: i64 = 0;
                    while (i < LP_BLK) {
                        let ep: ptr<i64> = q[i].p;
                        if (ep != null) {
                            free(ep as ptr<u8>);
                        }
                        i += 1;
                    }
                    free(q as ptr<u8>);
                    l.v[b] = null;
                }
                b += 1;
            }
            free(l.v as ptr<u8>);
        }
        l.v = null;
    }
    l.n = 0;
    l.nb = 0;
    l.bcap = 0;
}

fn lp_add(l: &mut Lp) -> i64 {
    if (l.bad == 1) {
        return 0;
    }
    let id: i64 = l.n;
    let blk: i64 = id >> LP_SHIFT;
    if (blk >= l.bcap) {
        var nb: i64 = l.bcap;
        while (nb <= blk) {
            nb = nb + nb / 2;
        }
        var raw: ptr<u8> = realloc(l.v as ptr<u8>, (nb as u64) * sizeof(ptr<Lst>));
        if (raw == null) {
            l.bad = 1;
            return 0;
        }
        var dir: ptr<ptr<Lst>> = raw as ptr<ptr<Lst>>;
        unsafe {
            let tail: ptr<u8> = (dir + l.bcap) as ptr<u8>;
            memset(tail, 0, ((nb - l.bcap) as u64) * sizeof(ptr<Lst>));
        }
        l.v = dir;
        l.bcap = nb;
    }
    if (lp_blk(l, blk) == null) {
        return 0;
    }
    l.n = id + 1;
    return id;
}

fn lp_push(l: &mut Lp, id: i64, v: i64) -> i32 {
    if (l.bad == 1 || id <= 0) {
        l.bad = 1;
        return 0 - 1;
    }
    var n: i64 = 0;
    var cap: i64 = 0;
    var ep: ptr<i64> = null;
    unsafe {
        n = lp_at(l.v, id).n as i64;
        cap = lp_at(l.v, id).cap as i64;
        ep = lp_at(l.v, id).p;
    }
    if (n >= cap) {
        var nc: i64 = cap + cap / 2;
        if (nc < cap + 2) {
            nc = cap + 2;
        }
        var raw: ptr<u8> = realloc(ep as ptr<u8>, (nc as u64) * sizeof(i64));
        if (raw == null) {
            l.bad = 1;
            return 0 - 1;
        }
        ep = raw as ptr<i64>;
        unsafe {
            lp_at(l.v, id).p = ep;
            lp_at(l.v, id).cap = nc as i32;
        }
    }
    unsafe {
        ep[n] = v;
        lp_at(l.v, id).n = (n + 1) as i32;
    }
    return 0;
}

fn lp_len(l: &mut Lp, id: i64) -> i64 {
    if (id <= 0) {
        return 0;
    }
    var n: i32 = 0;
    unsafe { n = lp_at(l.v, id).n; }
    return n as i64;
}

fn lp_pop(l: &mut Lp, id: i64) {
    if (id <= 0) {
        return;
    }
    var n: i32 = 0;
    unsafe { n = lp_at(l.v, id).n; }
    if (n > 0) {
        unsafe { lp_at(l.v, id).n = n - 1; }
    }
}

fn lp_get(l: &mut Lp, id: i64, i: i64) -> i64 {
    if (id <= 0) {
        return 0;
    }
    var v: i64 = 0;
    unsafe { v = lp_at(l.v, id).p[i]; }
    return v;
}

fn lp_set(l: &mut Lp, id: i64, i: i64, v: i64) {
    if (id <= 0) {
        return;
    }
    unsafe { lp_at(l.v, id).p[i] = v; }
}

fn lp_bytes(l: &mut Lp) -> i64 {
    var tot: i64 = 0;
    var b: i64 = 0;
    unsafe {
        while (b < l.nb) {
            let q: ptr<Lst> = l.v[b];
            if (q != null) {
                var i: i64 = 0;
                while (i < LP_BLK) {
                    tot = tot + (q[i].cap as i64) * (sizeof(i64) as i64);
                    i += 1;
                }
                tot = tot + LP_BLK * (sizeof(Lst) as i64);
            }
            b += 1;
        }
    }
    return tot;
}

struct SetI {
    t: ptr<i64>,
    th: ptr<i64>,
    cap: i64,
    n: i64,
    bad: i32
}

fn si_new() -> SetI {
    var s: SetI = zero(SetI);
    s.cap = 64;
    s.t = malloc((s.cap as u64) * sizeof(i64)) as ptr<i64>;
    s.th = malloc((s.cap as u64) * sizeof(i64)) as ptr<i64>;
    if (s.t == null || s.th == null) {
        s.bad = 1;
        return s;
    }
    var i: i64 = 0;
    while (i < s.cap) {
        unsafe { s.t[i] = 0; }
        unsafe { s.th[i] = 0; }
        i += 1;
    }
    return s;
}

fn si_free(s: &mut SetI) {
    if (s.t != null) {
        free(s.t as ptr<u8>);
        s.t = null;
    }
    if (s.th != null) {
        free(s.th as ptr<u8>);
        s.th = null;
    }
    s.cap = 0;
    s.n = 0;
}

fn si_hash(sp: &mut Sp, id: i64) -> i64 {
    let p: ptr<u8> = sp_ptr(sp, id);
    let n: i64 = sp_len(sp, id);
    return sp_hash(p, n);
}

fn si_add_h(s: &mut SetI, h: i64, id: i64) {
    if (s.bad == 1 || id <= 0) {
        return;
    }
    if (s.n * 2 >= s.cap) {
        let oc: i64 = s.cap;
        let nc: i64 = oc * 2;
        var nt: ptr<i64> = malloc((nc as u64) * sizeof(i64)) as ptr<i64>;
        var nh: ptr<i64> = malloc((nc as u64) * sizeof(i64)) as ptr<i64>;
        if (nt == null || nh == null) {
            s.bad = 1;
            return;
        }
        var i: i64 = 0;
        while (i < nc) {
            unsafe { nt[i] = 0; }
            unsafe { nh[i] = 0; }
            i += 1;
        }
        var k: i64 = 0;
        while (k < oc) {
            var cur: i64 = 0;
            var ch: i64 = 0;
            unsafe {
                cur = s.t[k];
                ch = s.th[k];
            }
            if (cur != 0) {
                var at: i64 = ch & (nc - 1);
                while (true) {
                    var c2: i64 = 0;
                    unsafe { c2 = nt[at]; }
                    if (c2 == 0) {
                        break;
                    }
                    at = (at + 1) & (nc - 1);
                }
                unsafe {
                    nt[at] = cur;
                    nh[at] = ch;
                }
            }
            k += 1;
        }
        free(s.t as ptr<u8>);
        free(s.th as ptr<u8>);
        s.t = nt;
        s.th = nh;
        s.cap = nc;
    }
    var at2: i64 = h & (s.cap - 1);
    while (true) {
        var cur2: i64 = 0;
        unsafe { cur2 = s.t[at2]; }
        if (cur2 == 0) {
            unsafe { s.t[at2] = id; }
            unsafe { s.th[at2] = h; }
            s.n += 1;
            return;
        }
        if (cur2 == id) {
            return;
        }
        at2 = (at2 + 1) & (s.cap - 1);
    }
}

fn si_add(s: &mut SetI, sp: &mut Sp, id: i64) {
    let h: i64 = si_hash(sp, id);
    si_add_h(s, h, id);
}

fn si_has_h(s: &mut SetI, h: i64, id: i64) -> bool {
    if (s.bad == 1 || id <= 0) {
        return false;
    }
    var at: i64 = h & (s.cap - 1);
    while (true) {
        var cur: i64 = 0;
        unsafe { cur = s.t[at]; }
        if (cur == 0) {
            return false;
        }
        if (cur == id) {
            return true;
        }
        at = (at + 1) & (s.cap - 1);
    }
}

fn si_has(s: &mut SetI, sp: &mut Sp, id: i64) -> bool {
    let h: i64 = si_hash(sp, id);
    return si_has_h(s, h, id);
}

struct MapI {
    k: ptr<i64>,
    v: ptr<i64>,
    cap: i64,
    n: i64,
    bad: i32
}

fn m64_new() -> MapI {
    var m: MapI = zero(MapI);
    m.cap = 64;
    m.k = malloc((m.cap as u64) * sizeof(i64)) as ptr<i64>;
    m.v = malloc((m.cap as u64) * sizeof(i64)) as ptr<i64>;
    if (m.k == null || m.v == null) {
        m.bad = 1;
        return m;
    }
    var i: i64 = 0;
    while (i < m.cap) {
        unsafe { m.k[i] = 0; }
        unsafe { m.v[i] = 0; }
        i += 1;
    }
    return m;
}

fn m64_free(m: &mut MapI) {
    if (m.k != null) {
        free(m.k as ptr<u8>);
        m.k = null;
    }
    if (m.v != null) {
        free(m.v as ptr<u8>);
        m.v = null;
    }
    m.cap = 0;
    m.n = 0;
}

fn mi_hash(key: i64) -> i64 {
    var h: i64 = key * 2654435761;
    h = h & 2147483647;
    return h;
}

fn m64_grow(m: &mut MapI) -> i32 {
    let oc: i64 = m.cap;
    let nc: i64 = oc * 2;
    var nk: ptr<i64> = malloc((nc as u64) * sizeof(i64)) as ptr<i64>;
    var nv: ptr<i64> = malloc((nc as u64) * sizeof(i64)) as ptr<i64>;
    if (nk == null || nv == null) {
        m.bad = 1;
        return 0;
    }
    var i: i64 = 0;
    while (i < nc) {
        unsafe { nk[i] = 0; }
        unsafe { nv[i] = 0; }
        i += 1;
    }
    var j: i64 = 0;
    while (j < oc) {
        var ck: i64 = 0;
        var cv: i64 = 0;
        unsafe {
            ck = m.k[j];
            cv = m.v[j];
        }
        if (ck != 0) {
            var at: i64 = mi_hash(ck) & (nc - 1);
            while (true) {
                var probe: i64 = 0;
                unsafe { probe = nk[at]; }
                if (probe == 0) {
                    break;
                }
                at = (at + 1) & (nc - 1);
            }
            unsafe {
                nk[at] = ck;
                nv[at] = cv;
            }
        }
        j += 1;
    }
    free(m.k as ptr<u8>);
    free(m.v as ptr<u8>);
    m.k = nk;
    m.v = nv;
    m.cap = nc;
    return 1;
}

fn m64_set(m: &mut MapI, key: i64, val: i64) -> i32 {
    if (m.bad == 1 || key == 0) {
        return 0;
    }
    if ((m.n + 1) * 2 >= m.cap) {
        if (m64_grow(m) == 0) {
            return 0;
        }
    }
    let h: i64 = mi_hash(key);
    var at: i64 = h & (m.cap - 1);
    while (true) {
        var ck: i64 = 0;
        unsafe { ck = m.k[at]; }
        if (ck == 0) {
            unsafe {
                m.k[at] = key;
                m.v[at] = val;
            }
            m.n += 1;
            return 1;
        }
        if (ck == key) {
            unsafe { m.v[at] = val; }
            return 1;
        }
        at = (at + 1) & (m.cap - 1);
    }
}

fn m64_get(m: &mut MapI, key: i64, dflt: i64) -> i64 {
    if (m.bad == 1 || key == 0 || m.n == 0) {
        return dflt;
    }
    var at: i64 = mi_hash(key) & (m.cap - 1);
    while (true) {
        var ck: i64 = 0;
        unsafe { ck = m.k[at]; }
        if (ck == 0) {
            return dflt;
        }
        if (ck == key) {
            var cv: i64 = 0;
            unsafe { cv = m.v[at]; }
            return cv;
        }
        at = (at + 1) & (m.cap - 1);
    }
}

fn m64_has(m: &mut MapI, key: i64) -> bool {
    if (m.bad == 1 || key == 0 || m.n == 0) {
        return false;
    }
    var at: i64 = mi_hash(key) & (m.cap - 1);
    while (true) {
        var ck: i64 = 0;
        unsafe { ck = m.k[at]; }
        if (ck == 0) {
            return false;
        }
        if (ck == key) {
            return true;
        }
        at = (at + 1) & (m.cap - 1);
    }
}
