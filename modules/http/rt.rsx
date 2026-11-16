extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern fn malloc(n: u64) -> ptr<u8>;
extern fn free(p: ptr<u8>) -> void;
extern fn realloc(p: ptr<u8>, n: u64) -> ptr<u8>;
extern fn calloc(n: u64, sz: u64) -> ptr<u8>;
extern fn memcpy(d: ptr<u8>, s: ptr<u8>, n: u64) -> ptr<u8>;
extern fn memmove(d: ptr<u8>, s: ptr<u8>, n: u64) -> ptr<u8>;
extern fn memset(d: ptr<u8>, v: i32, n: u64) -> ptr<u8>;
extern fn strlen(s: ptr<u8>) -> u64;
extern fn strcmp(a: ptr<u8>, b: ptr<u8>) -> i32;
extern fn strncmp(a: ptr<u8>, b: ptr<u8>, n: u64) -> i32;
extern fn sprintf(buf: ptr<u8>, fmt: ptr<u8>, ...) -> i32;
extern fn time(t: ptr<i64>) -> i64;

fn rt_len(s: ptr<u8>) -> i64 {
    return strlen(s) as i64;
}

fn rt_eq(a: ptr<u8>, b: ptr<u8>) -> i32 {
    if (strcmp(a, b) == 0) {
        return 1;
    }
    return 0;
}

fn rt_eqn(a: ptr<u8>, b: ptr<u8>, n: i64) -> i32 {
    if (n <= 0) {
        return 1;
    }
    if (strncmp(a, b, n as u64) == 0) {
        return 1;
    }
    return 0;
}

fn rt_cmp(a: ptr<u8>, b: ptr<u8>, n: i64) -> i32 {
    var i: i64 = 0;
    while (i < n) {
        var x: u8 = 0;
        var y: u8 = 0;
        unsafe {
            x = a[i];
            y = b[i];
        }
        if (x < y) {
            return -1;
        }
        if (x > y) {
            return 1;
        }
        i += 1;
    }
    return 0;
}

fn rt_bytes_eq(a: ptr<u8>, b: ptr<u8>, n: i64) -> i32 {
    if (rt_cmp(a, b, n) == 0) {
        return 1;
    }
    return 0;
}

fn rt_zero(p: ptr<u8>, n: i64) {
    if (n > 0) {
        memset(p, 0, n as u64);
    }
}

fn rt_copy(d: ptr<u8>, s: ptr<u8>, n: i64) {
    if (n > 0) {
        memcpy(d, s, n as u64);
    }
}

fn rt_byte(p: ptr<u8>, i: i64) -> u8 {
    var v: u8 = 0;
    unsafe { v = p[i]; }
    return v;
}

fn rt_setbyte(p: ptr<u8>, i: i64, v: u8) {
    unsafe { p[i] = v; }
}

fn rt_add(p: ptr<u8>, n: i64) -> ptr<u8> {
    var q: ptr<u8> = null;
    unsafe { q = p + n; }
    return q;
}

struct RtBlob {
    p: ptr<u8>,
    len: i64
}

fn rt_time() -> i64 {
    var t: i64 = 0;
    var np: ptr<i64> = null;
    unsafe { t = time(np); }
    return t;
}

fn rt_ct_eq(a: ptr<u8>, b: ptr<u8>, n: i64) -> i32 {
    var diff: u32 = 0;
    var i: i64 = 0;
    while (i < n) {
        var x: u8 = 0;
        var y: u8 = 0;
        unsafe {
            x = a[i];
            y = b[i];
        }
        diff = diff | (((x ^ y) as u32) & 255);
        i += 1;
    }
    if (diff == 0) {
        return 1;
    }
    return 0;
}

fn rt_put_hex(p: ptr<u8>, n: i64) {
    var digits: ptr<u8> = "0123456789abcdef";
    var i: i64 = 0;
    while (i < n) {
        var b: u8 = 0;
        var hi: u8 = 0;
        var lo: u8 = 0;
        unsafe {
            b = p[i];
            hi = digits[(b >> 4) as i64];
            lo = digits[(b & 15) as i64];
        }
        printf("%c%c", hi as u32, lo as u32);
        i += 1;
    }
    printf("\n");
}

fn rt_hex_str(out: ptr<u8>, inb: ptr<u8>, n: i64) {
    var digits: ptr<u8> = "0123456789abcdef";
    var i: i64 = 0;
    while (i < n) {
        var b: u8 = 0;
        unsafe {
            b = inb[i];
            out[i * 2] = digits[(b >> 4) as i64];
            out[i * 2 + 1] = digits[(b & 15) as i64];
        }
        i += 1;
    }
    unsafe { out[n * 2] = 0; }
}

fn rt_parse_hex(s: ptr<u8>, out: ptr<u8>, maxn: i64) -> i64 {
    var n: i64 = 0;
    var i: i64 = 0;
    var hi: i32 = -1;
    while (true) {
        var c: u8 = 0;
        unsafe { c = s[i]; }
        if (c == 0) {
            break;
        }
        var v: i32 = -1;
        if (c >= 48 && c <= 57) {
            v = (c - 48) as i32;
        } else if (c >= 97 && c <= 102) {
            v = (c - 87) as i32;
        } else if (c >= 65 && c <= 70) {
            v = (c - 55) as i32;
        }
        if (v >= 0) {
            if (hi < 0) {
                hi = v;
            } else {
                if (n < maxn) {
                    unsafe { out[n] = ((hi << 4) | v) as u8; }
                    n += 1;
                }
                hi = -1;
            }
        }
        i += 1;
    }
    return n;
}

struct HxBuf {
    p: ptr<u8>,
    len: i64,
    cap: i64
}

fn hxbuf_new(cap: i64) -> HxBuf {
    var b: HxBuf = zero(HxBuf);
    if (cap < 16) {
        cap = 16;
    }
    b.p = malloc(cap as u64);
    b.len = 0;
    b.cap = cap;
    if (b.p == null) {
        b.cap = 0;
    }
    return b;
}

fn hxbuf_free(b: &mut HxBuf) {
    if (b.p != null) {
        free(b.p);
        b.p = null;
    }
    b.len = 0;
    b.cap = 0;
}

fn hxbuf_reserve(b: &mut HxBuf, extra: i64) -> i32 {
    let need: i64 = b.len + extra;
    if (need <= b.cap) {
        return 0;
    }
    var cap: i64 = b.cap;
    if (cap < 16) {
        cap = 16;
    }
    while (cap < need) {
        cap = cap * 2;
        if (cap < 0) {
            return -1;
        }
    }
    var np: ptr<u8> = realloc(b.p, cap as u64);
    if (np == null) {
        return -1;
    }
    b.p = np;
    b.cap = cap;
    return 0;
}

fn hxbuf_put(b: &mut HxBuf, src: ptr<u8>, n: i64) -> i32 {
    if (n <= 0) {
        return 0;
    }
    if (hxbuf_reserve(b, n) != 0) {
        return -1;
    }
    var dst: ptr<u8> = null;
    unsafe { dst = b.p + b.len; }
    memcpy(dst, src, n as u64);
    b.len += n;
    return 0;
}

fn hxbuf_putc(b: &mut HxBuf, c: u8) -> i32 {
    if (hxbuf_reserve(b, 1) != 0) {
        return -1;
    }
    unsafe { b.p[b.len] = c; }
    b.len += 1;
    return 0;
}

fn hxbuf_puts(b: &mut HxBuf, s: ptr<u8>) -> i32 {
    return hxbuf_put(b, s, rt_len(s));
}

fn hxbuf_putu(b: &mut HxBuf, v: i64) -> i32 {
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
    var sp: ptr<u8> = null;
    unsafe { sp = &mut tmp[0] as ptr<u8>; }
    var off: ptr<u8> = null;
    unsafe { off = sp + i; }
    return hxbuf_put(b, off, 24 - i);
}

fn hxbuf_clear(b: &mut HxBuf) {
    b.len = 0;
}

fn hxbuf_terminate(b: &mut HxBuf) -> i32 {
    if (hxbuf_reserve(b, 1) != 0) {
        return -1;
    }
    unsafe { b.p[b.len] = 0; }
    return 0;
}
