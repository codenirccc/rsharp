extern fn malloc(n: u64) -> ptr<u8>;
extern fn realloc(p: ptr<u8>, n: u64) -> ptr<u8>;
extern fn free(p: ptr<u8>) -> void;
extern fn memcpy(d: ptr<u8>, s: ptr<u8>, n: u64) -> ptr<u8>;
extern fn strlen(s: ptr<u8>) -> u64;
extern fn sprintf(dst: ptr<u8>, fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn strtod(s: ptr<u8>, end: ptr<u8>) -> f64;

struct Sb {
    p: ptr<u8>,
    n: i64,
    cap: i64,
    bad: i32
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
        cap = cap * 2;
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

struct Lst {
    p: ptr<i64>,
    n: i64,
    cap: i64
}

struct Lp {
    v: ptr<Lst>,
    n: i64,
    cap: i64,
    bad: i32
}

fn lp_new() -> Lp {
    var l: Lp = zero(Lp);
    l.cap = 64;
    l.v = malloc((l.cap as u64) * sizeof(Lst)) as ptr<Lst>;
    if (l.v == null) {
        l.bad = 1;
        return l;
    }
    unsafe { l.v[0] = zero(Lst); }
    l.n = 1;
    return l;
}

fn lp_free(l: &mut Lp) {
    var i: i64 = 1;
    while (i < l.n) {
        var p: ptr<i64> = null;
        unsafe { p = l.v[i].p; }
        if (p != null) {
            free(p as ptr<u8>);
        }
        i += 1;
    }
    if (l.v != null) {
        free(l.v as ptr<u8>);
        l.v = null;
    }
    l.n = 0;
    l.cap = 0;
}

fn lp_add(l: &mut Lp) -> i64 {
    if (l.bad == 1) {
        return 0;
    }
    if (l.n >= l.cap) {
        let nc: i64 = l.cap * 2;
        var raw: ptr<u8> = realloc(l.v as ptr<u8>, (nc as u64) * sizeof(Lst));
        if (raw == null) {
            l.bad = 1;
            return 0;
        }
        l.v = raw as ptr<Lst>;
        l.cap = nc;
    }
    let id: i64 = l.n;
    unsafe {
        l.v[id].p = null;
        l.v[id].n = 0;
        l.v[id].cap = 0;
    }
    l.n += 1;
    return id;
}

fn lp_push(l: &mut Lp, id: i64, v: i64) -> i32 {
    if (l.bad == 1 || id <= 0) {
        l.bad = 1;
        return 0 - 1;
    }
    var n: i64 = 0;
    var cap: i64 = 0;
    var p: ptr<i64> = null;
    unsafe {
        n = l.v[id].n;
        cap = l.v[id].cap;
        p = l.v[id].p;
    }
    if (n >= cap) {
        var nc: i64 = cap * 2;
        if (nc < 8) {
            nc = 8;
        }
        var raw: ptr<u8> = realloc(p as ptr<u8>, (nc as u64) * sizeof(i64));
        if (raw == null) {
            l.bad = 1;
            return 0 - 1;
        }
        p = raw as ptr<i64>;
        unsafe { l.v[id].p = p; }
        unsafe { l.v[id].cap = nc; }
    }
    unsafe { p[n] = v; }
    unsafe { l.v[id].n = n + 1; }
    return 0;
}

fn lp_len(l: &mut Lp, id: i64) -> i64 {
    if (id <= 0) {
        return 0;
    }
    var n: i64 = 0;
    unsafe { n = l.v[id].n; }
    return n;
}

fn lp_pop(l: &mut Lp, id: i64) {
    if (id <= 0) {
        return;
    }
    var n: i64 = 0;
    unsafe { n = l.v[id].n; }
    if (n > 0) {
        unsafe { l.v[id].n = n - 1; }
    }
}

fn lp_get(l: &mut Lp, id: i64, i: i64) -> i64 {
    if (id <= 0) {
        return 0;
    }
    var v: i64 = 0;
    unsafe { v = l.v[id].p[i]; }
    return v;
}

fn lp_set(l: &mut Lp, id: i64, i: i64, v: i64) {
    if (id <= 0) {
        return;
    }
    unsafe { l.v[id].p[i] = v; }
}

struct SetI {
    t: ptr<i64>,
    cap: i64,
    n: i64,
    bad: i32
}

fn si_new() -> SetI {
    var s: SetI = zero(SetI);
    s.cap = 64;
    s.t = malloc((s.cap as u64) * sizeof(i64)) as ptr<i64>;
    if (s.t == null) {
        s.bad = 1;
        return s;
    }
    var i: i64 = 0;
    while (i < s.cap) {
        unsafe { s.t[i] = 0; }
        i += 1;
    }
    return s;
}

fn si_free(s: &mut SetI) {
    if (s.t != null) {
        free(s.t as ptr<u8>);
        s.t = null;
    }
    s.cap = 0;
    s.n = 0;
}

fn si_hash(sp: &mut Sp, id: i64) -> i64 {
    let p: ptr<u8> = sp_ptr(sp, id);
    let n: i64 = sp_len(sp, id);
    return sp_hash(p, n);
}

fn si_add(s: &mut SetI, sp: &mut Sp, id: i64) {
    if (s.bad == 1 || id <= 0) {
        return;
    }
    if (s.n * 2 >= s.cap) {
        let oc: i64 = s.cap;
        let nc: i64 = oc * 2;
        var nt: ptr<i64> = malloc((nc as u64) * sizeof(i64)) as ptr<i64>;
        if (nt == null) {
            s.bad = 1;
            return;
        }
        var i: i64 = 0;
        while (i < nc) {
            unsafe { nt[i] = 0; }
            i += 1;
        }
        var k: i64 = 0;
        while (k < oc) {
            var cur: i64 = 0;
            unsafe { cur = s.t[k]; }
            if (cur != 0) {
                let h: i64 = si_hash(sp, cur);
                var at: i64 = h & (nc - 1);
                while (true) {
                    var c2: i64 = 0;
                    unsafe { c2 = nt[at]; }
                    if (c2 == 0) {
                        break;
                    }
                    at = (at + 1) & (nc - 1);
                }
                unsafe { nt[at] = cur; }
            }
            k += 1;
        }
        free(s.t as ptr<u8>);
        s.t = nt;
        s.cap = nc;
    }
    let h: i64 = si_hash(sp, id);
    var at: i64 = h & (s.cap - 1);
    while (true) {
        var cur: i64 = 0;
        unsafe { cur = s.t[at]; }
        if (cur == 0) {
            unsafe { s.t[at] = id; }
            s.n += 1;
            return;
        }
        if (cur == id) {
            return;
        }
        at = (at + 1) & (s.cap - 1);
    }
}

fn si_has(s: &mut SetI, sp: &mut Sp, id: i64) -> bool {
    if (s.bad == 1 || id <= 0) {
        return false;
    }
    let h: i64 = si_hash(sp, id);
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
