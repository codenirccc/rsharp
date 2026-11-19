extern fn malloc(n: u64) -> ptr<u8>;
extern fn realloc(p: ptr<u8>, n: u64) -> ptr<u8>;
extern fn free(p: ptr<u8>);
extern fn memcpy(dst: ptr<u8>, src: ptr<u8>, n: u64) -> ptr<u8>;
extern "msvcrt" fn strtod(s: ptr<u8>, end: ptr<u8>) -> f64;
extern fn sprintf(dst: ptr<u8>, fmt: ptr<u8>, ...) -> i32;

const TK_IDENT: i32 = 0;
const TK_INT: i32 = 1;
const TK_FLOAT: i32 = 2;
const TK_STR: i32 = 3;
const TK_SYM: i32 = 4;
const TK_EOF: i32 = 5;

const I64_MAX: i64 = 9223372036854775807;
const I64_DIV10: i64 = 922337203685477580;
const I64_DIV16: i64 = 576460752303423487;

struct LexTok {
    kind: i32,
    line: i64,
    col: i64,
    num: i64,
    fp: f64,
    sp: ptr<u8>,
    slen: i64
}

struct Lexer {
    src: ptr<u8>,
    len: i64,
    i: i64,
    line: i64,
    col: i64,
    t: ptr<LexTok>,
    ntok: i64,
    cap: i64,
    ok: i32,
    err: [u8; 256],
    wb: ptr<u8>,
    wbn: i64,
    wbcap: i64,
    tok: LexTok,
    cur: LexTok,
    peek: LexTok,
    stream: i32,
    hit: i32
}

fn lex_is_alpha(c: u8) -> bool {
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
}

fn lex_is_digit(c: u8) -> bool {
    return c >= 48 && c <= 57;
}

fn lex_is_alnum(c: u8) -> bool {
    return lex_is_alpha(c) || lex_is_digit(c);
}

fn lex_is_hex(c: u8) -> bool {
    return lex_is_digit(c) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70);
}

fn lex_is_octal(c: u8) -> bool {
    return c >= 48 && c <= 55;
}

fn lex_byte(p: ptr<u8>, i: i64) -> u8 {
    unsafe {
        return p[i];
    }
}

fn lex_prefix2(p: ptr<u8>, n: i64, a: u8, b: u8) -> bool {
    unsafe {
        if (n < 2) {
            return false;
        }
        return p[0] == a && p[1] == b;
    }
}

fn lex_prefix3(p: ptr<u8>, n: i64, a: u8, b: u8, c: u8) -> bool {
    unsafe {
        if (n < 3) {
            return false;
        }
        return p[0] == a && p[1] == b && p[2] == c;
    }
}

fn lex_sym_len(p: ptr<u8>, n: i64) -> i64 {
    if (n <= 0) {
        return 0;
    }
    let c: u8 = lex_byte(p, 0);
    if (c == 46) {
        if (lex_prefix3(p, n, 46, 46, 46)) {
            return 3;
        }
        if (lex_prefix3(p, n, 46, 46, 61)) {
            return 3;
        }
        if (lex_prefix2(p, n, 46, 46)) {
            return 2;
        }
        return 1;
    }
    if (c == 58) {
        if (lex_prefix2(p, n, 58, 58)) {
            return 2;
        }
        return 1;
    }
    if (c == 45) {
        if (lex_prefix2(p, n, 45, 62)) {
            return 2;
        }
        if (lex_prefix2(p, n, 45, 61)) {
            return 2;
        }
        return 1;
    }
    if (c == 61) {
        if (lex_prefix2(p, n, 61, 62)) {
            return 2;
        }
        if (lex_prefix2(p, n, 61, 61)) {
            return 2;
        }
        return 1;
    }
    if (c == 33) {
        if (lex_prefix2(p, n, 33, 61)) {
            return 2;
        }
        return 1;
    }
    if (c == 60) {
        if (lex_prefix3(p, n, 60, 60, 61)) {
            return 3;
        }
        if (lex_prefix2(p, n, 60, 61)) {
            return 2;
        }
        if (lex_prefix2(p, n, 60, 60)) {
            return 2;
        }
        return 1;
    }
    if (c == 62) {
        if (lex_prefix3(p, n, 62, 62, 61)) {
            return 3;
        }
        if (lex_prefix2(p, n, 62, 61)) {
            return 2;
        }
        return 1;
    }
    if (c == 38) {
        if (lex_prefix2(p, n, 38, 38)) {
            return 2;
        }
        if (lex_prefix2(p, n, 38, 61)) {
            return 2;
        }
        return 1;
    }
    if (c == 124) {
        if (lex_prefix2(p, n, 124, 124)) {
            return 2;
        }
        if (lex_prefix2(p, n, 124, 61)) {
            return 2;
        }
        return 1;
    }
    if (c == 94 || c == 43 || c == 42 || c == 47 || c == 37) {
        if (lex_prefix2(p, n, c, 61)) {
            return 2;
        }
        return 1;
    }
    if (c == 59 || c == 44 || c == 40 || c == 41 || c == 123 || c == 125
        || c == 91 || c == 93 || c == 126 || c == 39) {
        return 1;
    }
    return 0;
}

fn lex_utf8_ok(p: ptr<u8>, n: i64) -> bool {
    var i: i64 = 0;
    while (i < n) {
        let c: u8 = lex_byte(p, i);
        if (c < 0x80) {
            i = i + 1;
        } else if (c >= 0xC2 && c <= 0xDF) {
            if (i + 1 >= n) {
                return false;
            }
            let c1: u8 = lex_byte(p, i + 1);
            if ((c1 & 0xC0) != 0x80) {
                return false;
            }
            i = i + 2;
        } else if (c >= 0xE0 && c <= 0xEF) {
            if (i + 2 >= n) {
                return false;
            }
            let c1: u8 = lex_byte(p, i + 1);
            let c2: u8 = lex_byte(p, i + 2);
            let tail: bool = (c1 & 0xC0) == 0x80 && (c2 & 0xC0) == 0x80;
            if (!tail) {
                return false;
            }
            if (c == 0xE0 && c1 < 0xA0) {
                return false;
            }
            if (c == 0xED && c1 >= 0xA0) {
                return false;
            }
            i = i + 3;
        } else if (c >= 0xF0 && c <= 0xF4) {
            if (i + 3 >= n) {
                return false;
            }
            let c1: u8 = lex_byte(p, i + 1);
            let c2: u8 = lex_byte(p, i + 2);
            let c3: u8 = lex_byte(p, i + 3);
            let tail: bool = (c1 & 0xC0) == 0x80 && (c2 & 0xC0) == 0x80 && (c3 & 0xC0) == 0x80;
            if (!tail) {
                return false;
            }
            if (c == 0xF0 && c1 < 0x90) {
                return false;
            }
            if (c == 0xF4 && c1 >= 0x90) {
                return false;
            }
            i = i + 4;
        } else {
            return false;
        }
    }
    return true;
}

fn lex_float_shape(p: ptr<u8>, n: i64) -> bool {
    var i: i64 = 0;
    var digits: i64 = 0;
    while (i < n) {
        let c: u8 = lex_byte(p, i);
        if (lex_is_digit(c)) {
            digits = digits + 1;
        } else if (c != 46 && c != 101 && c != 69 && c != 43 && c != 45) {
            return false;
        }
        i = i + 1;
    }
    return digits > 0;
}

fn lex_tcap(lx: &mut Lexer, want: i64) -> i32 {
    if (want <= lx.cap) {
        return 1;
    }
    var nc: i64 = lx.cap * 2;
    if (nc < want) {
        nc = want;
    }
    if (nc < 64) {
        nc = 64;
    }
    var raw: ptr<u8> = null;
    unsafe {
        raw = realloc(lx.t as ptr<u8>, (nc as u64) * sizeof(LexTok));
        if (raw == null) {
            return 0;
        }
        lx.t = raw as ptr<LexTok>;
    }
    lx.cap = nc;
    return 1;
}

fn lex_wcap(lx: &mut Lexer, want: i64) -> i32 {
    if (want <= lx.wbcap) {
        return 1;
    }
    var nc: i64 = lx.wbcap * 2;
    if (nc < want) {
        nc = want;
    }
    if (nc < 128) {
        nc = 128;
    }
    var raw: ptr<u8> = null;
    unsafe {
        raw = realloc(lx.wb, nc as u64);
        if (raw == null) {
            return 0;
        }
        lx.wb = raw;
    }
    lx.wbcap = nc;
    return 1;
}

fn lex_set(lx: &mut Lexer, line: i64, tail: ptr<u8>) {
    var tmp: [u8; 300] = [0];
    unsafe {
        sprintf(&mut tmp[0] as ptr<u8>, "line %lld: %s" as ptr<u8>, line, tail);
        var i: i64 = 0;
        while (tmp[i] != 0 && i < 255) {
            lx.err[i] = tmp[i];
            i = i + 1;
        }
        lx.err[i] = 0;
    }
    lx.ok = 0;
}

fn lex_setc(lx: &mut Lexer, line: i64, tail: ptr<u8>, ch: i32) {
    var tmp: [u8; 256] = [0];
    unsafe {
        sprintf(&mut tmp[0] as ptr<u8>, tail, ch);
        lex_set(lx, line, &mut tmp[0] as ptr<u8>);
    }
}

fn lex_sets(lx: &mut Lexer, line: i64, tail: ptr<u8>, s: ptr<u8>) {
    var tmp: [u8; 256] = [0];
    unsafe {
        sprintf(&mut tmp[0] as ptr<u8>, tail, s);
        lex_set(lx, line, &mut tmp[0] as ptr<u8>);
    }
}

fn lex_push(lx: &mut Lexer, kind: i32, line: i64, col: i64, num: i64, fp: f64,
            sp: ptr<u8>, slen: i64) -> i32 {
    if (lx.stream == 1) {
        unsafe {
            lx.tok.kind = kind;
            lx.tok.line = line;
            lx.tok.col = col;
            lx.tok.num = num;
            lx.tok.fp = fp;
            lx.tok.sp = sp;
            lx.tok.slen = slen;
        }
        lx.hit = 1;
        return 1;
    }
    if (lex_tcap(lx, lx.ntok + 1) == 0) {
        lex_set(lx, line, "out of memory" as ptr<u8>);
        return 0;
    }
    let i: i64 = lx.ntok;
    unsafe {
        lx.t[i].kind = kind;
        lx.t[i].line = line;
        lx.t[i].col = col;
        lx.t[i].num = num;
        lx.t[i].fp = fp;
        lx.t[i].sp = sp;
        lx.t[i].slen = slen;
    }
    lx.ntok = i + 1;
    return 1;
}

fn lex_dec_i64(p: ptr<u8>, n: i64) -> i64 {
    var v: i64 = 0;
    var i: i64 = 0;
    unsafe {
        while (i < n) {
            let d: u8 = p[i];
            if (d != 95) {
                if (d < 48 || d > 57) {
                    return -1;
                }
                let g: i64 = (d - 48) as i64;
                if (v > I64_DIV10) {
                    return -1;
                }
                v = v * 10;
                if (v > I64_MAX - g) {
                    return -1;
                }
                v = v + g;
            }
            i = i + 1;
        }
    }
    return v;
}

fn lex_hex_i64(p: ptr<u8>, n: i64) -> i64 {
    var v: i64 = 0;
    var i: i64 = 0;
    unsafe {
        while (i < n) {
            let d: u8 = p[i];
            if (d != 95) {
                var nib: i64 = 0;
                if (d >= 48 && d <= 57) {
                    nib = (d - 48) as i64;
                } else if (d >= 97 && d <= 102) {
                    nib = (d - 97) as i64 + 10;
                } else if (d >= 65 && d <= 70) {
                    nib = (d - 65) as i64 + 10;
                } else {
                    return -1;
                }
                if (v > I64_DIV16) {
                    return -1;
                }
                v = v * 16;
                if (v > I64_MAX - nib) {
                    return -1;
                }
                v = v + nib;
            }
            i = i + 1;
        }
    }
    return v;
}

fn lex_number(lx: &mut Lexer, src: ptr<u8>, len: i64, c: u8) -> i32 {
    let sline: i64 = lx.line;
    let scol: i64 = lx.col;
    let start: i64 = lx.i;
    var i: i64 = lx.i;

    if (c == 48 && i + 1 < len && (lex_byte(src, i + 1) == 120 || lex_byte(src, i + 1) == 88)) {
        i = i + 2;
        lx.col = lx.col + 2;
        let hs: i64 = i;
        while (i < len && (lex_is_hex(lex_byte(src, i)) || lex_byte(src, i) == 95)) {
            i = i + 1;
            lx.col = lx.col + 1;
        }
        if (i == hs) {
            lx.i = i;
            lex_set(lx, sline, "empty hex literal" as ptr<u8>);
            return 0;
        }
        var v: i64 = 0;
        unsafe {
            v = lex_hex_i64(src + hs, i - hs);
        }
        lx.i = i;
        if (v < 0) {
            lex_set(lx, sline, "hex literal does not fit in 64 bits" as ptr<u8>);
            return 0;
        }
        unsafe {
            return lex_push(lx, TK_INT, sline, scol, v, 0.0, src + start, i - start);
        }
    }

    var is_float: bool = false;
    while (i < len && (lex_is_digit(lex_byte(src, i)) || lex_byte(src, i) == 95)) {
        i = i + 1;
        lx.col = lx.col + 1;
    }
    if (i + 1 < len && lex_byte(src, i) == 46 && lex_is_digit(lex_byte(src, i + 1))) {
        is_float = true;
        i = i + 1;
        lx.col = lx.col + 1;
        while (i < len && (lex_is_digit(lex_byte(src, i)) || lex_byte(src, i) == 95)) {
            i = i + 1;
            lx.col = lx.col + 1;
        }
    }
    if (i < len && (lex_byte(src, i) == 101 || lex_byte(src, i) == 69)) {
        let save: i64 = i;
        var j: i64 = i + 1;
        if (j < len && (lex_byte(src, j) == 43 || lex_byte(src, j) == 45)) {
            j = j + 1;
        }
        if (j < len && lex_is_digit(lex_byte(src, j))) {
            is_float = true;
            i = j;
            while (i < len && (lex_is_digit(lex_byte(src, i)) || lex_byte(src, i) == 95)) {
                i = i + 1;
            }
        } else {
            i = save;
        }
        lx.col = lx.col + (i - save);
    }

    if (!is_float) {
        var v: i64 = 0;
        unsafe {
            v = lex_dec_i64(src + start, i - start);
        }
        lx.i = i;
        if (v < 0) {
            lex_set(lx, sline, "integer literal out of range" as ptr<u8>);
            return 0;
        }
        unsafe {
            return lex_push(lx, TK_INT, sline, scol, v, 0.0, src + start, i - start);
        }
    }

    let need: i64 = i - start + 1;
    if (lex_wcap(lx, need) == 0) {
        lx.i = i;
        lex_set(lx, sline, "out of memory" as ptr<u8>);
        return 0;
    }
    var k: i64 = 0;
    var s: i64 = start;
    unsafe {
        while (s < i) {
            let ch: u8 = lex_byte(src, s);
            if (ch != 95) {
                lx.wb[k] = ch;
                k = k + 1;
            }
            s = s + 1;
        }
        lx.wb[k] = 0;
    }
    if (!lex_float_shape(lx.wb, k)) {
        lx.i = i;
        lex_sets(lx, sline, "malformed float literal '%s'" as ptr<u8>, lx.wb);
        return 0;
    }
    var v: f64 = 0.0;
    unsafe {
        v = strtod(lx.wb, null);
    }
    let z: f64 = v - v;
    lx.i = i;
    if (z != z) {
        lex_set(lx, sline, "float literal out of range" as ptr<u8>);
        return 0;
    }
    unsafe {
        return lex_push(lx, TK_FLOAT, sline, scol, 0, v, src + start, i - start);
    }
}

fn lex_str(lx: &mut Lexer, src: ptr<u8>, len: i64) -> i32 {
    let sline: i64 = lx.line;
    let scol: i64 = lx.col;
    lx.i = lx.i + 1;
    lx.col = lx.col + 1;
    let room: i64 = len - lx.i + 1;
    if (lex_wcap(lx, room) == 0) {
        lex_set(lx, sline, "out of memory" as ptr<u8>);
        return 0;
    }
    var bn: i64 = 0;
    var done: i32 = 0;
    while (done == 0) {
        if (lx.i >= len) {
            lex_set(lx, sline, "unterminated string literal" as ptr<u8>);
            return 0;
        }
        let ch: u8 = lex_byte(src, lx.i);
        if (ch == 34) {
            lx.i = lx.i + 1;
            lx.col = lx.col + 1;
            done = 1;
        } else if (ch == 92) {
            if (lx.i + 1 >= len) {
                lex_set(lx, lx.line, "unterminated escape" as ptr<u8>);
                return 0;
            }
            let e: u8 = lex_byte(src, lx.i + 1);
            if (lex_is_octal(e)) {
                var v: i64 = 0;
                var n: i64 = 0;
                while (n < 3 && lx.i + 1 + n < len && lex_is_octal(lex_byte(src, lx.i + 1 + n))) {
                    v = v * 8 + (lex_byte(src, lx.i + 1 + n) - 48) as i64;
                    n = n + 1;
                }
                if (v > 255) {
                    lex_set(lx, lx.line, "octal escape is larger than a byte" as ptr<u8>);
                    return 0;
                }
                unsafe {
                    lx.wb[bn] = v as u8;
                }
                bn = bn + 1;
                lx.i = lx.i + 1 + n;
                lx.col = lx.col + 1 + n;
            } else {
                var rep: u8 = 0;
                var known: i32 = 1;
                if (e == 110) {
                    rep = 10;
                } else if (e == 116) {
                    rep = 9;
                } else if (e == 114) {
                    rep = 13;
                } else if (e == 92) {
                    rep = 92;
                } else if (e == 34) {
                    rep = 34;
                } else if (e == 39) {
                    rep = 39;
                } else {
                    known = 0;
                }
                if (known == 0) {
                    lex_setc(lx, lx.line, "unknown escape '\\%c'" as ptr<u8>, e as i32);
                    return 0;
                }
                unsafe {
                    lx.wb[bn] = rep;
                }
                bn = bn + 1;
                lx.i = lx.i + 2;
                lx.col = lx.col + 2;
            }
        } else if (ch == 10) {
            lex_set(lx, lx.line, "newline inside string literal" as ptr<u8>);
            return 0;
        } else {
            unsafe {
                lx.wb[bn] = ch;
            }
            bn = bn + 1;
            lx.i = lx.i + 1;
            lx.col = lx.col + 1;
        }
    }

    if (!lex_utf8_ok(lx.wb, bn)) {
        lex_set(lx, sline, "string literal is not valid UTF-8" as ptr<u8>);
        return 0;
    }
    var mem: ptr<u8> = null;
    unsafe {
        mem = malloc((bn + 1) as u64);
        if (mem == null) {
            lex_set(lx, sline, "out of memory" as ptr<u8>);
            return 0;
        }
        memcpy(mem, lx.wb, bn as u64);
        mem[bn] = 0;
    }
    return lex_push(lx, TK_STR, sline, scol, 0, 0.0, mem, bn);
}

fn lex_new() -> Lexer {
    var lx: Lexer = zero(Lexer);
    unsafe {
        lx.t = malloc((64 as u64) * sizeof(LexTok)) as ptr<LexTok>;
        lx.wb = malloc(256);
    }
    lx.cap = 64;
    lx.wbcap = 256;
    return lx;
}

fn lex_free(lx: &mut Lexer) {
    var i: i64 = 0;
    unsafe {
        while (i < lx.ntok) {
            if (lx.t[i].kind == TK_STR && lx.t[i].sp != null) {
                free(lx.t[i].sp);
            }
            i = i + 1;
        }
        if (lx.cur.kind == TK_STR && lx.cur.sp != null) {
            free(lx.cur.sp);
            lx.cur.sp = null;
        }
        if (lx.peek.kind == TK_STR && lx.peek.sp != null) {
            free(lx.peek.sp);
            lx.peek.sp = null;
        }
        if (lx.t != null) {
            free(lx.t as ptr<u8>);
        }
        if (lx.wb != null) {
            free(lx.wb);
        }
        lx.t = null;
        lx.wb = null;
    }
    lx.ntok = 0;
    lx.cap = 0;
    lx.wbcap = 0;
}

fn lex_begin(lx: &mut Lexer, src: ptr<u8>, len: i64) {
    lx.src = src;
    lx.len = len;
    lx.i = 0;
    lx.line = 1;
    lx.col = 1;
    lx.ok = 1;
    lx.ntok = 0;
    unsafe {
        lx.err[0] = 0;
    }
}

fn lex_scan(lx: &mut Lexer, src: ptr<u8>, len: i64) -> i32 {
    lx.hit = 0;
    var i: i64 = lx.i;
    var line: i64 = lx.line;
    var col: i64 = lx.col;
    while (i < len) {
        var c: u8 = 0;
        unsafe { c = src[i]; }
        if (c == 32 || c == 9 || c == 13) {
            i = i + 1;
            col = col + 1;
            continue;
        }
        if (c == 10) {
            i = i + 1;
            line = line + 1;
            col = 1;
            continue;
        }
        if (c == 47 && i + 1 < len) {
            var d: u8 = 0;
            unsafe { d = src[i + 1]; }
            if (d == 47) {
                i = i + 2;
                while (i < len) {
                    var e: u8 = 0;
                    unsafe { e = src[i]; }
                    if (e == 10) {
                        break;
                    }
                    i = i + 1;
                }
                continue;
            }
            if (d == 42) {
                i = i + 2;
                col = col + 2;
                var shut: i32 = 0;
                while (shut == 0) {
                    if (i + 1 >= len) {
                        lx.i = i;
                        lx.line = line;
                        lx.col = col;
                        lex_set(lx, line, "unterminated block comment" as ptr<u8>);
                        return 0;
                    }
                    var a: u8 = 0;
                    var b: u8 = 0;
                    unsafe {
                        a = src[i];
                        b = src[i + 1];
                    }
                    if (a == 42 && b == 47) {
                        i = i + 2;
                        col = col + 2;
                        shut = 1;
                    } else if (a == 10) {
                        line = line + 1;
                        col = 1;
                        i = i + 1;
                    } else {
                        i = i + 1;
                        col = col + 1;
                    }
                }
                continue;
            }
        }
        if (c >= 97 && c <= 122) {
            if (lex_ident(lx, src, len, i, line, col) == 0) {
                return 0;
            }
            i = lx.i;
            col = lx.col;
            line = lx.line;
            if (lx.stream == 1 && lx.hit == 1) {
                return 1;
            }
            continue;
        }
        if (c >= 65 && c <= 90) {
            if (lex_ident(lx, src, len, i, line, col) == 0) {
                return 0;
            }
            i = lx.i;
            col = lx.col;
            line = lx.line;
            if (lx.stream == 1 && lx.hit == 1) {
                return 1;
            }
            continue;
        }
        if (c == 95) {
            if (lex_ident(lx, src, len, i, line, col) == 0) {
                return 0;
            }
            i = lx.i;
            col = lx.col;
            line = lx.line;
            if (lx.stream == 1 && lx.hit == 1) {
                return 1;
            }
            continue;
        }
        if (c >= 48 && c <= 57) {
            lx.i = i;
            lx.line = line;
            lx.col = col;
            if (lex_number(lx, src, len, c) == 0) {
                return 0;
            }
            i = lx.i;
            line = lx.line;
            col = lx.col;
            if (lx.stream == 1 && lx.hit == 1) {
                return 1;
            }
            continue;
        }
        if (c == 34) {
            lx.i = i;
            lx.line = line;
            lx.col = col;
            if (lex_str(lx, src, len) == 0) {
                return 0;
            }
            i = lx.i;
            line = lx.line;
            col = lx.col;
            if (lx.stream == 1 && lx.hit == 1) {
                return 1;
            }
            continue;
        }
        let sline: i64 = line;
        var sl: i64 = 0;
        unsafe {
            sl = lex_sym_len(src + i, len - i);
        }
        if (sl == 0) {
            lx.i = i;
            lx.line = line;
            lx.col = col;
            lex_setc(lx, sline, "unexpected character '%c'" as ptr<u8>, c as i32);
            return 0;
        }
        col = col + sl;
        unsafe {
            if (lex_push(lx, TK_SYM, sline, col - sl, 0, 0.0, src + i, sl) == 0) {
                return 0;
            }
        }
        i = i + sl;
        if (lx.stream == 1 && lx.hit == 1) {
            lx.i = i;
            lx.line = line;
            lx.col = col;
            return 1;
        }
    }

    lx.i = i;
    lx.line = line;
    lx.col = col;
    unsafe {
        if (lex_push(lx, TK_EOF, line, col, 0, 0.0, src + len, 0) == 0) {
            return 0;
        }
    }
    return 1;
}

fn lex_ident(lx: &mut Lexer, src: ptr<u8>, len: i64, at: i64, line: i64, col: i64) -> i32 {
    var i: i64 = at;
    while (i < len) {
        var d: u8 = 0;
        unsafe { d = src[i]; }
        if (d >= 97 && d <= 122) {
            i = i + 1;
        } else if (d >= 65 && d <= 90) {
            i = i + 1;
        } else if (d >= 48 && d <= 57) {
            i = i + 1;
        } else if (d == 95) {
            i = i + 1;
        } else {
            break;
        }
    }
    lx.i = i;
    lx.line = line;
    lx.col = col + (i - at);
    unsafe {
        return lex_push(lx, TK_IDENT, line, col, 0, 0.0, src + at, i - at);
    }
}

fn lex_run(lx: &mut Lexer, src: ptr<u8>, len: i64) -> i32 {
    lx.stream = 0;
    lex_begin(lx, src, len);
    return lex_scan(lx, src, len);
}

fn lex_open(lx: &mut Lexer, src: ptr<u8>, len: i64) -> i32 {
    lx.stream = 1;
    lex_begin(lx, src, len);
    if (lex_scan(lx, src, len) == 0) {
        return 0;
    }
    lx.cur = lx.tok;
    if (lex_scan(lx, src, len) == 0) {
        return 0;
    }
    lx.peek = lx.tok;
    return 1;
}

fn lex_advance(lx: &mut Lexer) -> i32 {
    if (lx.cur.kind == TK_STR && lx.cur.sp != null) {
        free(lx.cur.sp);
        lx.cur.sp = null;
    }
    lx.cur = lx.peek;
    if (lx.cur.kind == TK_EOF) {
        return 1;
    }
    if (lex_scan(lx, lx.src, lx.len) == 0) {
        return 0;
    }
    lx.peek = lx.tok;
    return 1;
}

fn lex_tok_count(lx: &mut Lexer) -> i64 {
    return lx.ntok;
}

fn lex_tok_kind(lx: &mut Lexer, i: i64) -> i32 {
    unsafe {
        return lx.t[i].kind;
    }
}

fn lex_tok_line(lx: &mut Lexer, i: i64) -> i64 {
    unsafe {
        return lx.t[i].line;
    }
}

fn lex_tok_col(lx: &mut Lexer, i: i64) -> i64 {
    unsafe {
        return lx.t[i].col;
    }
}

fn lex_tok_num(lx: &mut Lexer, i: i64) -> i64 {
    unsafe {
        return lx.t[i].num;
    }
}

fn lex_tok_fp(lx: &mut Lexer, i: i64) -> f64 {
    unsafe {
        return lx.t[i].fp;
    }
}

fn lex_tok_sp(lx: &mut Lexer, i: i64) -> ptr<u8> {
    unsafe {
        return lx.t[i].sp;
    }
}

fn lex_tok_slen(lx: &mut Lexer, i: i64) -> i64 {
    unsafe {
        return lx.t[i].slen;
    }
}

fn lex_err(lx: &mut Lexer) -> ptr<u8> {
    unsafe {
        return &mut lx.err[0] as ptr<u8>;
    }
}
