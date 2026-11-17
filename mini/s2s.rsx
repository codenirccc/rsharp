extern "kernel32" fn GetStdHandle(kind: i32) -> i64;
extern "kernel32" fn ReadFile(h: i64, buf: ptr<u8>, want: u32, got: ptr<u32>, ov: ptr<u8>) -> i32;
extern "kernel32" fn WriteFile(h: i64, buf: ptr<u8>, n: u32, wrote: ptr<u32>, ov: ptr<u8>) -> i32;
extern "msvcrt" fn malloc(n: u64) -> ptr<u8>;
extern "msvcrt" fn free(p: ptr<u8>);
extern "kernel32" fn ExitProcess(code: u32);
extern fn printf(fmt: ptr<u8>, ...) -> i32;

const SRC_MAX: i64 = 1048576;
const OUT_MAX: i64 = 1048576;
const FNMAX: i64 = 1024;

const TAG_I64: i64 = 0;
const TAG_BOOL: i64 = 1;
const TAG_STR: i64 = 2;

const CTX_I64: i64 = 0;
const CTX_BOOL: i64 = 1;
const CTX_RAW: i64 = 2;

struct FnName {
    off: i64,
    len: i64
}

struct C {
    src: ptr<u8>,
    out: ptr<u8>,
    slen: i64,
    olen: i64,
    pos: i64,
    fns: ptr<FnName>,
    fns_n: i64,
    case_n: i64,
    rec: i64
}

fn out_byte(c: &mut C, b: u8) {
    if (c.rec == 0) {
        return;
    }
    unsafe {
        c.out[c.olen] = b;
    }
    c.olen += 1;
}

fn out_text(c: &mut C, t: ptr<u8>) {
    var i: i64 = 0;
    unsafe {
        while (t[i] != 0) {
            out_byte(c, t[i]);
            i += 1;
        }
    }
}

fn out_slice(c: &mut C, src: ptr<u8>, off: i64, len: i64) {
    var i: i64 = 0;
    unsafe {
        while (i < len) {
            out_byte(c, src[off + i]);
            i += 1;
        }
    }
}

fn out_num(c: &mut C, v: i64) {
    if (v < 0) {
        out_byte(c, 45);
        out_num(c, 0 - v);
        return;
    }
    if (v >= 10) {
        out_num(c, v / 10);
    }
    out_byte(c, (v % 10) as u8 + 48);
}

fn out_num_to_buf(buf: &mut [u8; 64], k: i64, v: i64) -> i64 {
    var n: i64 = v;
    var digits: [u8; 24] = [0];
    var nd: i64 = 0;
    if (n == 0) {
        digits[0] = 48;
        nd = 1;
    } else {
        while (n > 0) {
            digits[nd] = (n % 10) as u8 + 48;
            n = n / 10;
            nd += 1;
        }
    }
    var i: i64 = 0;
    while (i < nd) {
        unsafe {
            buf[k + i] = digits[nd - 1 - i];
        }
        i += 1;
    }
    return k + nd;
}

fn fail(c: &mut C, off: i64, msg: ptr<u8>) {
    var line: i64 = 1;
    var k: i64 = 0;
    unsafe {
        while (k < off) {
            if (c.src[k] == 10) {
                line += 1;
            }
            k += 1;
        }
    }
    var cap: [u8; 64] = [0];
    var k2: i64 = 0;
    let prefix: ptr<u8> = "s2s: line " as ptr<u8>;
    var j: i64 = 0;
    unsafe {
        while (prefix[j] != 0) {
            cap[k2] = prefix[j];
            k2 += 1;
            j += 1;
        }
    }
    k2 = out_num_to_buf(&mut cap, k2, line);
    unsafe {
        cap[k2] = 58;
        cap[k2 + 1] = 32;
    }
    k2 += 2;
    var j2: i64 = 0;
    unsafe {
        while (msg[j2] != 0) {
            cap[k2 + j2] = msg[j2];
            j2 += 1;
        }
        cap[k2 + j2] = 10;
    }
    var wrote: u32 = 0;
    unsafe {
        WriteFile(GetStdHandle(-12), &cap[0] as ptr<u8>, (k2 + j2 + 1) as u32, &wrote as ptr<u32>, null);
    }
    ExitProcess(1);
}

fn fail_at_c(c: &mut C, msg: ptr<u8>) {
    fail(c, c.pos, msg);
}

fn is_space(b: u8) -> i64 {
    if (b == 32 || b == 9 || b == 13 || b == 10) {
        return 1;
    }
    return 0;
}

fn skip_ws(c: &mut C) {
    unsafe {
        while (c.pos < c.slen) {
            let b: u8 = c.src[c.pos];
            if (is_space(b) == 1) {
                c.pos += 1;
                continue;
            }
            if (b == 47 && c.pos + 1 < c.slen && c.src[c.pos + 1] == 47) {
                c.pos += 2;
                while (c.pos < c.slen && c.src[c.pos] != 10) {
                    c.pos += 1;
                }
                continue;
            }
            if (b == 47 && c.pos + 1 < c.slen && c.src[c.pos + 1] == 42) {
                c.pos += 2;
                while (c.pos + 1 < c.slen && !(c.src[c.pos] == 42 && c.src[c.pos + 1] == 47)) {
                    c.pos += 1;
                }
                if (c.pos + 1 < c.slen) {
                    c.pos += 2;
                }
                continue;
            }
            break;
        }
    }
}

fn peek(c: &mut C) -> u8 {
    unsafe {
        if (c.pos < c.slen) {
            return c.src[c.pos];
        }
        return 0;
    }
}

fn peek_at(c: &mut C, n: i64) -> u8 {
    unsafe {
        if (c.pos + n < c.slen) {
            return c.src[c.pos + n];
        }
        return 0;
    }
}

fn expect_byte(c: &mut C, b: u8, msg: ptr<u8>) {
    skip_ws(c);
    if (peek(c) != b) {
        fail_at_c(c, msg);
    }
    c.pos += 1;
}

fn is_word_start(b: u8) -> i64 {
    if ((b >= 97 && b <= 122) || (b >= 65 && b <= 90) || b == 95) {
        return 1;
    }
    return 0;
}

fn is_word(b: u8) -> i64 {
    if (is_word_start(b) == 1 || (b >= 48 && b <= 57)) {
        return 1;
    }
    return 0;
}

fn is_digit(b: u8) -> i64 {
    if (b >= 48 && b <= 57) {
        return 1;
    }
    return 0;
}

fn word_len_of(s: ptr<u8>) -> i64 {
    var i: i64 = 0;
    unsafe {
        while (s[i] != 0) {
            i += 1;
        }
    }
    return i;
}

fn read_word(c: &mut C) -> (i64, i64) {
    skip_ws(c);
    let start: i64 = c.pos;
    unsafe {
        while (c.pos < c.slen && is_word(c.src[c.pos]) == 1) {
            c.pos += 1;
        }
    }
    return (start, c.pos - start);
}

fn word_is_at(c: &mut C, off: i64, len: i64, want: ptr<u8>) -> i64 {
    var wl: i64 = word_len_of(want);
    if (wl != len) {
        return 0;
    }
    var j: i64 = 0;
    while (j < len) {
        unsafe {
            if (c.src[off + j] != want[j]) {
                return 0;
            }
        }
        j += 1;
    }
    return 1;
}

fn peek_word(c: &mut C, want: ptr<u8>) -> i64 {
    let save: i64 = c.pos;
    let (s, l) = read_word(c);
    c.pos = save;
    return word_is_at(c, s, l, want);
}

fn char_value(c: &mut C, start: i64, end: i64) -> i64 {
    unsafe {
        if (c.src[start] != 92) {
            return c.src[start] as i64;
        }
        let e: u8 = c.src[start + 1];
        if (e == 110) { return 10; }
        if (e == 116) { return 9; }
        if (e == 114) { return 13; }
        if (e == 92) { return 92; }
        if (e == 39) { return 39; }
        if (e == 34) { return 34; }
        if (e == 48) { return 0; }
        if (e == 120) {
            var sum: i64 = 0;
            var j: i64 = start + 2;
            while (j < end) {
                let x: u8 = c.src[j];
                var d: i64 = 0 - 1;
                if (x >= 48 && x <= 57) { d = (x - 48) as i64; }
                else if (x >= 97 && x <= 102) { d = (x - 97 + 10) as i64; }
                else if (x >= 65 && x <= 70) { d = (x - 65 + 10) as i64; }
                if (d < 0) {
                    fail_at_c(c, "bad hex escape in a char literal" as ptr<u8>);
                }
                sum = sum * 16 + d;
                j += 1;
            }
            return sum;
        }
        fail_at_c(c, "unknown escape in a char literal" as ptr<u8>);
    }
    return 0 - 1;
}

fn emit_escape_check(c: &mut C, start: i64, end: i64) {
    unsafe {
        var i: i64 = start;
        while (i < end) {
            if (c.src[i] == 92) {
                var nx: u8 = 0;
                if (i + 1 < end) {
                    nx = c.src[i + 1];
                }
                if (!(nx == 110 || nx == 116 || nx == 114 || nx == 92 || nx == 34)) {
                    fail(c, i, "unknown escape in a string" as ptr<u8>);
                }
                i += 2;
                continue;
            }
            if (c.src[i] == 10) {
                fail(c, i, "a newline inside a string" as ptr<u8>);
            }
            i += 1;
        }
    }
}

fn parse_char_lit(c: &mut C) -> i64 {
    let open: i64 = c.pos;
    c.pos += 1;
    var close: i64 = c.pos;
    unsafe {
        while (close < c.slen) {
            let q: u8 = c.src[close];
            if (q == 92) {
                close += 2;
                continue;
            }
            if (q == 39) {
                break;
            }
            if (q == 10) {
                fail(c, close, "a newline in a char literal" as ptr<u8>);
            }
            close += 1;
        }
    }
    if (close >= c.slen) {
        fail(c, open, "unterminated char literal" as ptr<u8>);
    }
    let v: i64 = char_value(c, c.pos, close);
    c.pos = close + 1;
    out_num(c, v);
    return TAG_I64;
}

fn parse_string_lit(c: &mut C) -> i64 {
    let open: i64 = c.pos;
    c.pos += 1;
    var close: i64 = c.pos;
    unsafe {
        while (close < c.slen) {
            let q: u8 = c.src[close];
            if (q == 92 || q == 34 || q == 10) {
                if (q == 10) {
                    fail(c, close, "a newline inside a string" as ptr<u8>);
                }
                if (q == 34) {
                    break;
                }
                close += 2;
                continue;
            }
            close += 1;
        }
    }
    if (close >= c.slen) {
        fail(c, open, "unterminated string" as ptr<u8>);
    }
    emit_escape_check(c, c.pos, close);
    out_slice(c, c.src, open, close + 1 - open);
    c.pos = close + 1;
    return TAG_STR;
}

fn parse_number(c: &mut C) -> i64 {
    skip_ws(c);
    let start: i64 = c.pos;
    var v: i64 = 0;
    unsafe {
        while (c.pos < c.slen && is_digit(c.src[c.pos]) == 1) {
            v = v * 10 + ((c.src[c.pos] - 48) as i64);
            c.pos += 1;
        }
    }
    out_num(c, v);
    return TAG_I64;
}

fn at_two(c: &mut C, a: u8, b: u8) -> i64 {
    skip_ws(c);
    if (peek(c) == a && peek_at(c, 1) == b) {
        return 1;
    }
    return 0;
}

fn need_i64_suffix(c: &mut C, tag: i64) -> i64 {
    if (tag == TAG_I64) {
        return TAG_I64;
    }
    out_text(c, " as i64");
    return TAG_I64;
}

fn need_bool_suffix(c: &mut C, tag: i64) -> i64 {
    if (tag == TAG_BOOL) {
        return TAG_BOOL;
    }
    if (tag == TAG_I64) {
        out_text(c, " != 0");
        return TAG_BOOL;
    }
    out_text(c, " as i64 != 0");
    return TAG_BOOL;
}

fn root_cast(c: &mut C, tag: i64, ctx: i64) -> i64 {
    if (ctx == CTX_I64) {
        if (tag != TAG_I64) {
            out_text(c, " as i64");
        }
        return TAG_I64;
    }
    if (ctx == CTX_BOOL) {
        if (tag == TAG_I64) {
            out_text(c, " != 0");
            return TAG_BOOL;
        }
        if (tag == TAG_STR) {
            out_text(c, " as i64 != 0");
            return TAG_BOOL;
        }
        return tag;
    }
    return tag;
}

fn parse_expr(c: &mut C, ctx: i64) -> i64 {
    var t: i64 = parse_or(c);
    return root_cast(c, t, ctx);
}

fn operand_and(c: &mut C) -> i64 {
    out_byte(c, 40);
    var t: i64 = parse_and(c);
    t = need_bool_suffix(c, t);
    out_byte(c, 41);
    return t;
}

fn operand_cmp(c: &mut C) -> i64 {
    out_byte(c, 40);
    var t: i64 = parse_cmp(c);
    t = need_bool_suffix(c, t);
    out_byte(c, 41);
    return t;
}

fn operand_arith(c: &mut C) -> i64 {
    out_byte(c, 40);
    var t: i64 = parse_add(c);
    t = need_i64_suffix(c, t);
    out_byte(c, 41);
    return t;
}

fn operand_factor(c: &mut C) -> i64 {
    out_byte(c, 40);
    var t: i64 = parse_mul(c);
    t = need_i64_suffix(c, t);
    out_byte(c, 41);
    return t;
}

fn operand_term(c: &mut C) -> i64 {
    out_byte(c, 40);
    var t: i64 = parse_unary(c);
    t = need_i64_suffix(c, t);
    out_byte(c, 41);
    return t;
}

fn parse_or(c: &mut C) -> i64 {
    var sp: i64 = c.pos;
    var so: i64 = c.olen;
    var sr: i64 = c.rec;
    c.rec = 0;
    var sees: i64 = 0;
    parse_and(c);
    while (at_two(c, 124, 124) == 1) {
        c.pos += 2;
        parse_and(c);
        sees = 1;
    }
    c.pos = sp;
    c.olen = so;
    c.rec = sr;
    if (sees == 0) {
        return parse_and(c);
    }
    out_byte(c, 40);
    operand_and(c);
    while (at_two(c, 124, 124) == 1) {
        c.pos += 2;
        out_text(c, " || ");
        operand_and(c);
    }
    out_byte(c, 41);
    return TAG_BOOL;
}

fn parse_and(c: &mut C) -> i64 {
    var sp: i64 = c.pos;
    var so: i64 = c.olen;
    var sr: i64 = c.rec;
    c.rec = 0;
    var sees: i64 = 0;
    parse_cmp(c);
    while (at_two(c, 38, 38) == 1) {
        c.pos += 2;
        parse_cmp(c);
        sees = 1;
    }
    c.pos = sp;
    c.olen = so;
    c.rec = sr;
    if (sees == 0) {
        return parse_cmp(c);
    }
    out_byte(c, 40);
    operand_cmp(c);
    while (at_two(c, 38, 38) == 1) {
        c.pos += 2;
        out_text(c, " && ");
        operand_cmp(c);
    }
    out_byte(c, 41);
    return TAG_BOOL;
}

fn parse_cmp(c: &mut C) -> i64 {
    out_byte(c, 40);
    var t: i64 = operand_arith(c);
    while (true) {
        skip_ws(c);
        let b: u8 = peek(c);
        let b2: u8 = peek_at(c, 1);
        var eat: i64 = 0;
        var op: ptr<u8> = null;
        if (b == 60 && b2 == 61) { eat = 2; op = " <= " as ptr<u8>; }
        else if (b == 62 && b2 == 61) { eat = 2; op = " >= " as ptr<u8>; }
        else if (b == 61 && b2 == 61) { eat = 2; op = " == " as ptr<u8>; }
        else if (b == 33 && b2 == 61) { eat = 2; op = " != " as ptr<u8>; }
        else if (b == 60) { eat = 1; op = " < " as ptr<u8>; }
        else if (b == 62) { eat = 1; op = " > " as ptr<u8>; }
        if (op == null) {
            break;
        }
        c.pos += eat;
        out_text(c, op);
        var r: i64 = operand_arith(c);
        t = TAG_BOOL;
    }
    out_byte(c, 41);
    return t;
}

fn parse_add(c: &mut C) -> i64 {
    out_byte(c, 40);
    var t: i64 = operand_factor(c);
    while (true) {
        skip_ws(c);
        let b: u8 = peek(c);
        if (b == 43) {
            c.pos += 1;
            out_text(c, " + ");
            var r: i64 = operand_factor(c);
            t = TAG_I64;
            continue;
        }
        if (b == 45) {
            c.pos += 1;
            out_text(c, " - ");
            var r: i64 = operand_factor(c);
            t = TAG_I64;
            continue;
        }
        break;
    }
    out_byte(c, 41);
    return t;
}

fn parse_mul(c: &mut C) -> i64 {
    out_byte(c, 40);
    var t: i64 = operand_term(c);
    while (true) {
        skip_ws(c);
        let b: u8 = peek(c);
        if (b == 42) {
            c.pos += 1;
            out_text(c, " * ");
            var r: i64 = operand_term(c);
            t = TAG_I64;
            continue;
        }
        if (b == 47) {
            c.pos += 1;
            out_text(c, " / ");
            var r: i64 = operand_term(c);
            t = TAG_I64;
            continue;
        }
        if (b == 37) {
            c.pos += 1;
            out_text(c, " % ");
            var r: i64 = operand_term(c);
            t = TAG_I64;
            continue;
        }
        break;
    }
    out_byte(c, 41);
    return t;
}

fn parse_unary(c: &mut C) -> i64 {
    skip_ws(c);
    let b: u8 = peek(c);
    if (b == 45) {
        c.pos += 1;
        out_text(c, "(-(");
        var t: i64 = parse_unary(c);
        need_i64_suffix(c, t);
        out_byte(c, 41);
        out_byte(c, 41);
        return TAG_I64;
    }
    if (b == 33) {
        c.pos += 1;
        out_text(c, "(!(");
        var t: i64 = parse_unary(c);
        need_bool_suffix(c, t);
        out_byte(c, 41);
        out_byte(c, 41);
        return TAG_BOOL;
    }
    return parse_atom(c);
}

fn scan_string_lit(c: &mut C, open: i64) -> (i64, i64) {
    var i: i64 = open + 1;
    var n: i64 = 0;
    unsafe {
        while (i < c.slen) {
            let q: u8 = c.src[i];
            if (q == 92) { i += 2; n += 1; continue; }
            if (q == 34) { return (i + 1, n); }
            if (q == 10) {
                fail(c, i, "a newline inside a string" as ptr<u8>);
            }
            i += 1;
            n += 1;
        }
    }
    fail(c, open, "unterminated string" as ptr<u8>);
    return (0 - 1, 0 - 1);
}

fn parse_atom(c: &mut C) -> i64 {
    skip_ws(c);
    let b: u8 = peek(c);
    if (b == 40) {
        c.pos += 1;
        out_byte(c, 40);
        var tag: i64 = parse_expr(c, CTX_RAW);
        expect_byte(c, 41, "expected ')' after the value" as ptr<u8>);
        out_byte(c, 41);
        return tag;
    }
    if (b == 39) {
        return parse_char_lit(c);
    }
    if (b == 34) {
        return parse_string_lit(c);
    }
    if (is_digit(b) == 1) {
        return parse_number(c);
    }
    if (is_word_start(b) == 1) {
        let (s, l) = read_word(c);
        if (word_is_at(c, s, l, "true" as ptr<u8>) == 1) {
            out_text(c, "true");
            return TAG_BOOL;
        }
        if (word_is_at(c, s, l, "false" as ptr<u8>) == 1) {
            out_text(c, "false");
            return TAG_BOOL;
        }
        skip_ws(c);
        if (peek(c) == 40) {
            c.pos += 1;
            if (word_is_at(c, s, l, "abs" as ptr<u8>) == 1) {
                out_text(c, "__s2s_abs(");
                parse_expr(c, CTX_I64);
                out_byte(c, 41);
                expect_byte(c, 41, "expected ')' after the argument" as ptr<u8>);
                return TAG_I64;
            }
            if (word_is_at(c, s, l, "min" as ptr<u8>) == 1) {
                out_text(c, "__s2s_min(");
                parse_expr(c, CTX_I64);
                out_text(c, ", ");
                expect_byte(c, 44, "expected ',' between the arguments" as ptr<u8>);
                parse_expr(c, CTX_I64);
                out_byte(c, 41);
                expect_byte(c, 41, "expected ')' after the arguments" as ptr<u8>);
                return TAG_I64;
            }
            if (word_is_at(c, s, l, "max" as ptr<u8>) == 1) {
                out_text(c, "__s2s_max(");
                parse_expr(c, CTX_I64);
                out_text(c, ", ");
                expect_byte(c, 44, "expected ',' between the arguments" as ptr<u8>);
                parse_expr(c, CTX_I64);
                out_byte(c, 41);
                expect_byte(c, 41, "expected ')' after the arguments" as ptr<u8>);
                return TAG_I64;
            }
            if (word_is_at(c, s, l, "puts" as ptr<u8>) == 1) {
                skip_ws(c);
                if (peek(c) != 34) {
                    fail(c, c.pos, "'puts' takes a string literal" as ptr<u8>);
                }
                out_text(c, "puts(");
                parse_string_lit(c);
                out_text(c, ") as i64");
                expect_byte(c, 41, "expected ')' after the argument" as ptr<u8>);
                return TAG_I64;
            }
            if (word_is_at(c, s, l, "putc" as ptr<u8>) == 1) {
                out_text(c, "putchar(");
                parse_expr(c, CTX_I64);
                out_text(c, " as i32) as i64");
                expect_byte(c, 41, "expected ')' after the argument" as ptr<u8>);
                return TAG_I64;
            }
            if (word_is_at(c, s, l, "len" as ptr<u8>) == 1) {
                skip_ws(c);
                if (peek(c) != 34) {
                    fail(c, c.pos, "'len' takes a string literal" as ptr<u8>);
                }
                let save_p: i64 = c.pos;
                let (endq, count) = scan_string_lit(c, save_p);
                emit_escape_check(c, save_p + 1, endq - 1);
                c.pos = endq;
                out_num(c, count);
                expect_byte(c, 41, "expected ')' after the argument" as ptr<u8>);
                return TAG_I64;
            }
            out_slice(c, c.src, s, l);
            out_byte(c, 40);
            var first_arg: i64 = 1;
            skip_ws(c);
            while (peek(c) != 41) {
                if (first_arg == 0) {
                    out_text(c, ", ");
                }
                parse_expr(c, CTX_I64);
                first_arg = 0;
                skip_ws(c);
                if (peek(c) == 44) {
                    c.pos += 1;
                    continue;
                }
                break;
            }
            out_byte(c, 41);
            expect_byte(c, 41, "expected ')' after the arguments" as ptr<u8>);
            return TAG_I64;
        }
        out_slice(c, c.src, s, l);
        return TAG_I64;
    }
    fail(c, c.pos, "expected a value" as ptr<u8>);
    return TAG_I64;
}

fn parse_block_body(c: &mut C, in_main: i64) {
    skip_ws(c);
    while (peek(c) != 125) {
        if (peek(c) == 0) {
            fail_at_c(c, "the file ends inside a block" as ptr<u8>);
        }
        parse_stmt(c, in_main);
        skip_ws(c);
    }
    c.pos += 1;
}

fn emit_block_open(c: &mut C) {
    out_text(c, " {\n");
    skip_ws(c);
    if (peek(c) != 123) {
        fail_at_c(c, "expected '{'" as ptr<u8>);
    }
    c.pos += 1;
}

fn parse_stmt(c: &mut C, in_main: i64) {
    skip_ws(c);
    let b: u8 = peek(c);
    if (b == 0) {
        return;
    }
    if (peek_word(c, "let" as ptr<u8>) == 1 || peek_word(c, "var" as ptr<u8>) == 1) {
        let mutable: i64 = peek_word(c, "var" as ptr<u8>);
        read_word(c);
        let (s, l) = read_word(c);
        if (mutable == 1) {
            out_text(c, "var ");
        } else {
            out_text(c, "let ");
        }
        out_slice(c, c.src, s, l);
        out_text(c, ": i64 = ");
        expect_byte(c, 61, "expected '=' after the name" as ptr<u8>);
        parse_expr(c, CTX_I64);
        expect_byte(c, 59, "expected ';' after the declaration" as ptr<u8>);
        out_text(c, ";\n");
        return;
    }
    if (peek_word(c, "print" as ptr<u8>) == 1) {
        parse_print(c);
        return;
    }
    if (peek_word(c, "if" as ptr<u8>) == 1) {
        read_word(c);
        out_text(c, "if (");
        expect_byte(c, 40, "expected '(' after 'if'" as ptr<u8>);
        parse_expr(c, CTX_BOOL);
        out_text(c, ")");
        expect_byte(c, 41, "expected ')' after the condition" as ptr<u8>);
        emit_block_open(c);
        parse_block_body(c, in_main);
        out_text(c, "}\n");
        skip_ws(c);
        if (peek_word(c, "else" as ptr<u8>) == 1) {
            read_word(c);
            out_text(c, " else ");
            skip_ws(c);
            if (peek(c) == 123) {
                out_text(c, "{\n");
                c.pos += 1;
                parse_block_body(c, in_main);
                out_text(c, "}\n");
            } else {
                parse_stmt(c, in_main);
            }
        }
        return;
    }
    if (peek_word(c, "while" as ptr<u8>) == 1) {
        read_word(c);
        out_text(c, "while (");
        expect_byte(c, 40, "expected '(' after 'while'" as ptr<u8>);
        parse_expr(c, CTX_BOOL);
        out_text(c, ")");
        expect_byte(c, 41, "expected ')' after the condition" as ptr<u8>);
        emit_block_open(c);
        parse_block_body(c, in_main);
        out_text(c, "}\n");
        return;
    }
    if (peek_word(c, "case" as ptr<u8>) == 1) {
        parse_case(c, in_main);
        return;
    }
    if (peek_word(c, "return" as ptr<u8>) == 1) {
        read_word(c);
        skip_ws(c);
        if (peek(c) == 59) {
            c.pos += 1;
            out_text(c, "return 0;\n");
            return;
        }
        out_text(c, "return ");
        parse_expr(c, CTX_I64);
        if (in_main == 1) {
            out_text(c, " as i32");
        }
        expect_byte(c, 59, "expected ';' after the return value" as ptr<u8>);
        out_text(c, ";\n");
        return;
    }
    if (peek_word(c, "break" as ptr<u8>) == 1) {
        read_word(c);
        expect_byte(c, 59, "expected ';' after 'break'" as ptr<u8>);
        out_text(c, "break;\n");
        return;
    }
    if (peek_word(c, "continue" as ptr<u8>) == 1) {
        read_word(c);
        expect_byte(c, 59, "expected ';' after 'continue'" as ptr<u8>);
        out_text(c, "continue;\n");
        return;
    }
    if (try_assign(c) == 1) {
        return;
    }
    parse_expr(c, CTX_I64);
    expect_byte(c, 59, "expected ';' after the statement" as ptr<u8>);
    out_text(c, ";\n");
}

fn try_assign(c: &mut C) -> i64 {
    skip_ws(c);
    if (is_word_start(peek(c)) != 1) {
        return 0;
    }
    let sp: i64 = c.pos;
    let (s, l) = read_word(c);
    skip_ws(c);
    let b: u8 = peek(c);
    let b2: u8 = peek_at(c, 1);
    var op: ptr<u8> = null;
    var eat: i64 = 1;
    if (b == 61 && b2 != 61) { op = " = " as ptr<u8>; eat = 1; }
    else if (b == 43 && b2 == 61) { op = " += " as ptr<u8>; eat = 2; }
    else if (b == 45 && b2 == 61) { op = " -= " as ptr<u8>; eat = 2; }
    else if (b == 42 && b2 == 61) { op = " *= " as ptr<u8>; eat = 2; }
    else if (b == 47 && b2 == 61) { op = " /= " as ptr<u8>; eat = 2; }
    else if (b == 37 && b2 == 61) { op = " %= " as ptr<u8>; eat = 2; }
    else {
        c.pos = sp;
        return 0;
    }
    out_slice(c, c.src, s, l);
    out_text(c, op);
    c.pos += eat;
    parse_expr(c, CTX_I64);
    expect_byte(c, 59, "expected ';' after the assignment" as ptr<u8>);
    out_text(c, ";\n");
    return 1;
}

fn parse_print(c: &mut C) {
    read_word(c);
    expect_byte(c, 40, "expected '(' after 'print'" as ptr<u8>);
    var arg_start: [i64; 64] = [0];
    var arg_tag: [i64; 64] = [0];
    var n: i64 = 0;
    skip_ws(c);
    if (peek(c) != 41) {
        while (true) {
            skip_ws(c);
            if (n >= 64) {
                fail_at_c(c, "print takes at most 64 arguments" as ptr<u8>);
            }
            arg_start[n] = c.pos;
            var so: i64 = c.olen;
            var sr: i64 = c.rec;
            c.rec = 0;
            var etag: i64 = TAG_I64;
            if (peek(c) == 34) {
                parse_string_lit(c);
                etag = TAG_STR;
            } else {
                etag = parse_expr(c, CTX_RAW);
            }
            c.olen = so;
            c.rec = sr;
            arg_tag[n] = etag;
            n += 1;
            skip_ws(c);
            if (peek(c) == 44) {
                c.pos += 1;
                continue;
            }
            break;
        }
    }
    expect_byte(c, 41, "expected ')' after the printed values" as ptr<u8>);
    expect_byte(c, 59, "expected ';' after 'print'" as ptr<u8>);
    out_text(c, "printf(\"");
    var end_pos: i64 = c.pos;
    var i: i64 = 0;
    var sep: i64 = 0;
    while (i < n) {
        if (sep == 1) {
            out_byte(c, 32);
        }
        if (arg_tag[i] == TAG_STR) {
            out_text(c, "%s");
        } else {
            out_text(c, "%lld");
        }
        sep = 1;
        i += 1;
    }
    out_text(c, "\\n\"");
    i = 0;
    while (i < n) {
        unsafe {
            c.pos = arg_start[i];
        }
        out_text(c, ", ");
        if (arg_tag[i] == TAG_STR) {
            parse_string_lit(c);
        } else {
            parse_expr(c, CTX_I64);
        }
        i += 1;
    }
    out_text(c, ");\n");
    c.pos = end_pos;
}

fn out_case_var(c: &mut C, n: i64) {
    out_text(c, "__s2s_case");
    out_num(c, n);
}

fn expect_arm_arrow(c: &mut C) {
    expect_byte(c, 61, "expected '=>' after the arm values" as ptr<u8>);
    expect_byte(c, 62, "expected '=>' after the arm values" as ptr<u8>);
}

fn parse_case(c: &mut C, in_main: i64) {
    read_word(c);
    let hn: i64 = c.case_n;
    c.case_n += 1;
    out_text(c, "{\nlet ");
    out_case_var(c, hn);
    out_text(c, ": i64 = ");
    expect_byte(c, 40, "expected '(' after 'case'" as ptr<u8>);
    parse_expr(c, CTX_I64);
    expect_byte(c, 41, "expected ')' after the case value" as ptr<u8>);
    out_text(c, ";\n");
    expect_byte(c, 123, "expected '{' to open the case arms" as ptr<u8>);
    var chain: i64 = 0;
    while (true) {
        skip_ws(c);
        let b: u8 = peek(c);
        if (b == 125) {
            c.pos += 1;
            break;
        }
        if (b == 0) {
            fail_at_c(c, "the file ends inside a case" as ptr<u8>);
        }
        if (peek_word(c, "else" as ptr<u8>) == 1) {
            if (chain == 2) {
                fail_at_c(c, "the case already has an else arm" as ptr<u8>);
            }
            read_word(c);
            expect_arm_arrow(c);
            out_text(c, " else {\n");
            expect_byte(c, 123, "expected '{' for the else arm body" as ptr<u8>);
            parse_block_body(c, in_main);
            out_text(c, "}\n");
            chain = 2;
            continue;
        }
        if (chain == 2) {
            fail_at_c(c, "an arm follows the else arm" as ptr<u8>);
        }
        if (chain == 1) {
            out_text(c, " else ");
        }
        out_text(c, "if (");
        out_case_var(c, hn);
        out_text(c, " == (");
        parse_expr(c, CTX_I64);
        out_byte(c, 41);
        while (true) {
            skip_ws(c);
            if (peek(c) == 44) {
                c.pos += 1;
                out_text(c, " || ");
                out_case_var(c, hn);
                out_text(c, " == (");
                parse_expr(c, CTX_I64);
                out_byte(c, 41);
                continue;
            }
            break;
        }
        out_text(c, ") {\n");
        expect_arm_arrow(c);
        expect_byte(c, 123, "expected '{' for the arm body" as ptr<u8>);
        parse_block_body(c, in_main);
        out_text(c, "}\n");
        chain = 1;
    }
    out_text(c, "}\n");
}

fn is_reserved(c: &mut C, s: i64, l: i64) -> i64 {
    if (word_is_at(c, s, l, "print" as ptr<u8>) == 1 || word_is_at(c, s, l, "abs" as ptr<u8>) == 1) {
        return 1;
    }
    if (word_is_at(c, s, l, "min" as ptr<u8>) == 1 || word_is_at(c, s, l, "max" as ptr<u8>) == 1) {
        return 1;
    }
    if (word_is_at(c, s, l, "puts" as ptr<u8>) == 1 || word_is_at(c, s, l, "putc" as ptr<u8>) == 1) {
        return 1;
    }
    if (word_is_at(c, s, l, "len" as ptr<u8>) == 1) {
        return 1;
    }
    unsafe {
        if (l >= 2 && c.src[s] == 95 && c.src[s + 1] == 95) {
            return 1;
        }
    }
    return 0;
}

fn fn_name_taken(c: &mut C, s: i64, l: i64) -> i64 {
    unsafe {
        var i: i64 = 0;
        while (i < c.fns_n) {
            if (c.fns[i].len == l) {
                var j: i64 = 0;
                var hit: i64 = 1;
                while (j < l) {
                    if (c.src[c.fns[i].off + j] != c.src[s + j]) {
                        hit = 0;
                        break;
                    }
                    j += 1;
                }
                if (hit == 1) {
                    return 1;
                }
            }
            i += 1;
        }
    }
    return 0;
}

fn remember_fn(c: &mut C, s: i64, l: i64) {
    unsafe {
        if (c.fns_n >= FNMAX) {
            fail(c, s, "too many functions" as ptr<u8>);
        }
        c.fns[c.fns_n].off = s;
        c.fns[c.fns_n].len = l;
        c.fns_n += 1;
    }
}

fn shout(s: ptr<u8>) {
    var wrote: u32 = 0;
    var n: i64 = 0;
    unsafe {
        while (s[n] != 0) {
            n += 1;
        }
        WriteFile(GetStdHandle(-12), s, n as u32, &wrote as ptr<u32>, null);
        WriteFile(GetStdHandle(-12), "\n" as ptr<u8>, 1, &wrote as ptr<u32>, null);
    }
}

fn main() -> i32 {
    var src: ptr<u8> = null;
    var out: ptr<u8> = null;
    var fns: ptr<FnName> = null;
    unsafe {
        src = malloc(SRC_MAX as u64);
        out = malloc(OUT_MAX as u64);
        fns = malloc((FNMAX * 16) as u64) as ptr<FnName>;
        if (src == null || out == null || fns == null) {
            shout("s2s: cannot allocate the buffers" as ptr<u8>);
            return 1;
        }
    }
    var got: u32 = 0;
    var total: i64 = 0;
    unsafe {
        let h: i64 = GetStdHandle(-10);
        while (total < SRC_MAX) {
            let ok: i32 = ReadFile(h, src + total, (SRC_MAX - total) as u32, &got as ptr<u32>, null);
            if (ok != 1 || got == 0) {
                break;
            }
            total += got as i64;
        }
    }
    var st: C = C { src: src, out: out, slen: total, olen: 0, pos: 0, fns: fns, fns_n: 0, case_n: 0, rec: 1 };
    emit_header(&mut st);
    let saw_main: i64 = parse_program(&mut st);
    if (saw_main != 1) {
        shout("s2s: no main function" as ptr<u8>);
        free(src);
        free(out);
        free(fns as ptr<u8>);
        return 1;
    }
    var wrote2: u32 = 0;
    let h2: i64 = GetStdHandle(-11);
    var off: i64 = 0;
    unsafe {
        while (off < st.olen) {
            let ok: i32 = WriteFile(h2, out + off, (st.olen - off) as u32, &wrote2 as ptr<u32>, null);
            if (ok != 1) {
                shout("s2s: cannot write the output" as ptr<u8>);
                free(src);
                free(out);
                free(fns as ptr<u8>);
                return 1;
            }
            off += wrote2 as i64;
        }
        free(src);
        free(out);
        free(fns as ptr<u8>);
    }
    return 0;
}

fn emit_header(c: &mut C) {
    out_text(c, "extern fn printf(fmt: ptr<u8>, ...) -> i32;\n");
    out_text(c, "extern fn puts(s: ptr<u8>) -> i32;\n");
    out_text(c, "extern fn putchar(c: i32) -> i32;\n\n");
    out_text(c, "fn __s2s_abs(x: i64) -> i64 {\n    if (x < 0) {\n        return 0 - x;\n    }\n    return x;\n}\n\n");
    out_text(c, "fn __s2s_min(a: i64, b: i64) -> i64 {\n    if (a < b) {\n        return a;\n    }\n    return b;\n}\n\n");
    out_text(c, "fn __s2s_max(a: i64, b: i64) -> i64 {\n    if (a > b) {\n        return a;\n    }\n    return b;\n}\n\n");
}

fn parse_program(c: &mut C) -> i64 {
    var saw_main: i64 = 0;
    while (true) {
        skip_ws(c);
        if (peek(c) == 0) {
            break;
        }
        if (peek_word(c, "fn" as ptr<u8>) != 1) {
            fail_at_c(c, "expected 'fn' at the top level" as ptr<u8>);
        }
        read_word(c);
        let (s, l) = read_word(c);
        if (is_reserved(c, s, l) == 1) {
            fail(c, s, "that name is reserved" as ptr<u8>);
        }
        if (fn_name_taken(c, s, l) == 1) {
            fail(c, s, "duplicate function name" as ptr<u8>);
        }
        remember_fn(c, s, l);
        var in_main: i64 = 0;
        if (word_is_at(c, s, l, "main" as ptr<u8>) == 1) {
            in_main = 1;
            saw_main = 1;
        }
        out_text(c, "fn ");
        out_slice(c, c.src, s, l);
        out_text(c, "(");
        expect_byte(c, 40, "expected '(' after the function name" as ptr<u8>);
        var param_n: i64 = 0;
        skip_ws(c);
        if (peek(c) != 41) {
            var first: i64 = 1;
            while (true) {
                let (ps, pl) = read_word(c);
                if (in_main == 1) {
                    fail(c, ps, "main takes no parameters" as ptr<u8>);
                }
                if (first == 0) {
                    out_text(c, ", ");
                }
                out_slice(c, c.src, ps, pl);
                out_text(c, ": i64");
                first = 0;
                param_n += 1;
                skip_ws(c);
                if (peek(c) == 44) {
                    c.pos += 1;
                    continue;
                }
                break;
            }
        }
        expect_byte(c, 41, "expected ')' after the parameters" as ptr<u8>);
        if (in_main == 1) {
            out_text(c, ") -> i32 {\n");
        } else {
            out_text(c, ") -> i64 {\n");
        }
        c.case_n = 0;
        expect_byte(c, 123, "expected '{' to open the function body" as ptr<u8>);
        parse_block_body(c, in_main);
        out_text(c, "return 0;\n}\n");
    }
    return saw_main;
}
