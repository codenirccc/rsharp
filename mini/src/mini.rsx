const SRCMAX: i64 = 1048576;
const OUTMAX: i64 = 33554432;
const NMAX: i64 = 65536;
const NODEB: i64 = 56;
const FNMAX: i64 = 4096;
const CHUNK: i64 = 65536;

const K_EOF: i64 = 0;
const K_ID: i64 = 1;
const K_NUM: i64 = 2;
const K_STR: i64 = 3;

const K_FN: i64 = 10;
const K_LET: i64 = 11;
const K_VAR: i64 = 12;
const K_RETURN: i64 = 13;
const K_IF: i64 = 14;
const K_ELSE: i64 = 15;
const K_WHILE: i64 = 16;
const K_BREAK: i64 = 17;
const K_CONTINUE: i64 = 18;
const K_PRINT: i64 = 19;
const K_CASE: i64 = 20;

const K_LP: i64 = 30;
const K_RP: i64 = 31;
const K_LB: i64 = 32;
const K_RB: i64 = 33;
const K_SEMI: i64 = 34;
const K_COMMA: i64 = 35;
const K_ARROW: i64 = 36;

const K_ASSIGN: i64 = 40;
const K_PLUSEQ: i64 = 41;
const K_MINUSEQ: i64 = 42;
const K_STAREQ: i64 = 43;
const K_SLASHEQ: i64 = 44;
const K_PCTEQ: i64 = 45;

const K_EQ: i64 = 50;
const K_NE: i64 = 51;
const K_LE: i64 = 52;
const K_GE: i64 = 53;
const K_LT: i64 = 54;
const K_GT: i64 = 55;

const K_PLUS: i64 = 60;
const K_MINUS: i64 = 61;
const K_STAR: i64 = 62;
const K_SLASH: i64 = 63;
const K_PCT: i64 = 64;

const K_ANDAND: i64 = 70;
const K_OROR: i64 = 71;
const K_BANG: i64 = 72;

const N_INT: i64 = 1;
const N_VAR: i64 = 2;
const N_BIN: i64 = 3;
const N_UN: i64 = 4;
const N_CALL: i64 = 5;
const N_STR: i64 = 6;
const N_BUILTIN: i64 = 7;

const B_ABS: i64 = 1;
const B_MIN: i64 = 2;
const B_MAX: i64 = 3;
const B_PUTS: i64 = 4;
const B_PUTC: i64 = 5;

struct Node {
    kind: i64,
    op: i64,
    a: i64,
    b: i64,
    next: i64,
    val: i64,
    len: i64
}

struct C {
    src: ptr<u8>,
    out: ptr<u8>,
    nodes: ptr<Node>,
    fns: ptr<i64>,
    fnlen: ptr<i64>,
    slen: i64,
    olen: i64,
    nn: i64,
    peak: i64,
    nfn: i64,
    pos: i64,
    line: i64,
    tline: i64,
    kind: i64,
    tstart: i64,
    tlen: i64,
    tval: i64,
    saw_main: i64,
    cases: i64,
    want_abs: i64,
    want_min: i64,
    want_max: i64,
    want_puts: i64,
    want_putc: i64
}

fn wlen(s: ptr<u8>) -> i64 {
    var i: i64 = 0;
    unsafe {
        while (s[i] != 0) {
            i += 1;
        }
    }
    return i;
}

fn pb(p: ptr<u8>, i: i64) -> u8 {
    unsafe {
        return p[i];
    }
}

fn pset(p: ptr<u8>, i: i64, v: u8) {
    unsafe {
        p[i] = v;
    }
}

fn write_all(s: ptr<u8>, n: i64) {
    host_out(s, n);
}

fn shout(s: ptr<u8>) {
    host_err(s);
}

fn quit(msg: ptr<u8>) {
    shout(msg);
    host_exit(1);
}

fn grab(n: i64) -> ptr<u8> {
    let p: ptr<u8> = host_grab(n);
    if (p == null) {
        quit("mini: cannot reserve memory");
    }
    return p;
}

fn ch(c: &mut C, i: i64) -> u8 {
    if (i < 0 || i >= c.slen) {
        return 0;
    }
    unsafe {
        return c.src[i];
    }
}

fn setch(c: &mut C, i: i64, v: u8) {
    unsafe {
        c.src[i] = v;
    }
}

fn out_byte(c: &mut C, b: u8) {
    if (c.olen >= OUTMAX) {
        quit("mini: output is larger than 32 MB");
    }
    unsafe {
        c.out[c.olen] = b;
    }
    c.olen += 1;
}

fn out_text(c: &mut C, s: ptr<u8>) {
    var i: i64 = 0;
    unsafe {
        while (s[i] != 0) {
            out_byte(c, s[i]);
            i += 1;
        }
    }
}

fn out_slice(c: &mut C, off: i64, len: i64) {
    var i: i64 = 0;
    while (i < len) {
        out_byte(c, ch(c, off + i));
        i += 1;
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

fn fail(c: &mut C, msg: ptr<u8>) {
    let mark: i64 = c.olen;
    out_text(c, "mini: line ");
    out_num(c, c.tline);
    out_text(c, ": ");
    out_text(c, msg);
    out_text(c, "\n");
    if (c.slen > 0) {
        var start: i64 = c.tstart;
        if (start > c.slen) {
            start = c.slen;
        }
        while (start > 0 && ch(c, start - 1) != 10) {
            start -= 1;
        }
        var line_end: i64 = start;
        while (line_end < c.slen && ch(c, line_end) != 10) {
            line_end += 1;
        }
        var from: i64 = start;
        if (c.tstart > from + 60) {
            from = c.tstart - 40;
        }
        var pad: i64 = c.tstart - from;
        if (pad < 0) {
            pad = 0;
        }
        var stop: i64 = line_end;
        if (stop > from + 100) {
            stop = from + 100;
        }
        out_text(c, "  ");
        out_slice(c, from, stop - from);
        out_text(c, "\n  ");
        var k: i64 = 0;
        while (k < pad) {
            out_byte(c, 32);
            k += 1;
        }
        out_text(c, "^\n");
    }
    unsafe {
        write_all(c.out + mark, c.olen - mark);
    }
    host_exit(1);
}

fn is_digit(b: u8) -> bool {
    return b >= 48 && b <= 57;
}

fn is_alpha(b: u8) -> bool {
    return (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95;
}

fn word_is(c: &mut C, start: i64, len: i64, w: ptr<u8>) -> bool {
    var i: i64 = 0;
    unsafe {
        while (i < len) {
            if (w[i] == 0 || w[i] != ch(c, start + i)) {
                return false;
            }
            i += 1;
        }
        if (w[i] != 0) {
            return false;
        }
    }
    return true;
}

fn keyword(c: &mut C, start: i64, len: i64) -> i64 {
    if (word_is(c, start, len, "fn")) {
        return K_FN;
    }
    if (word_is(c, start, len, "let")) {
        return K_LET;
    }
    if (word_is(c, start, len, "var")) {
        return K_VAR;
    }
    if (word_is(c, start, len, "return")) {
        return K_RETURN;
    }
    if (word_is(c, start, len, "if")) {
        return K_IF;
    }
    if (word_is(c, start, len, "else")) {
        return K_ELSE;
    }
    if (word_is(c, start, len, "while")) {
        return K_WHILE;
    }
    if (word_is(c, start, len, "break")) {
        return K_BREAK;
    }
    if (word_is(c, start, len, "continue")) {
        return K_CONTINUE;
    }
    if (word_is(c, start, len, "print")) {
        return K_PRINT;
    }
    if (word_is(c, start, len, "case")) {
        return K_CASE;
    }
    return K_ID;
}

fn at(c: &mut C, o: i64) -> u8 {
    return ch(c, c.pos + o);
}
fn advance(c: &mut C) {
    var going: bool = true;
    while (going) {
        going = false;
        while (c.pos < c.slen) {
            let b: u8 = ch(c, c.pos);
            if (b == 32 || b == 9 || b == 13) {
                c.pos += 1;
            } else if (b == 10) {
                c.pos += 1;
                c.line += 1;
            } else if (b == 47 && at(c, 1) == 47) {
                while (c.pos < c.slen && ch(c, c.pos) != 10) {
                    c.pos += 1;
                }
                going = true;
            } else {
                break;
            }
        }
    }

    c.tline = c.line;
    if (c.pos >= c.slen) {
        c.kind = K_EOF;
        c.tstart = c.pos;
        c.tlen = 0;
        return;
    }

    let b: u8 = ch(c, c.pos);
    if (is_alpha(b)) {
        let start: i64 = c.pos;
        while (c.pos < c.slen && (is_alpha(ch(c, c.pos)) || is_digit(ch(c, c.pos)))) {
            c.pos += 1;
        }
        c.tstart = start;
        c.tlen = c.pos - start;
        c.kind = keyword(c, start, c.tlen);
        return;
    }
    if (is_digit(b)) {
        let start: i64 = c.pos;
        var v: i64 = 0;
        while (c.pos < c.slen && is_digit(ch(c, c.pos))) {
            v = v * 10 + (ch(c, c.pos) - 48) as i64;
            c.pos += 1;
        }
        c.tstart = start;
        c.tlen = c.pos - start;
        c.tval = v;
        c.kind = K_NUM;
        return;
    }
    if (b == 34) {
        let start: i64 = c.pos + 1;
        c.pos += 1;
        while (c.pos < c.slen) {
            let q: u8 = ch(c, c.pos);
            if (q == 92) {
                let e: u8 = at(c, 1);
                if (e == 110 || e == 116 || e == 114 || e == 92 || e == 34) {
                    c.pos += 2;
                } else {
                    fail(c, "unknown escape in a string");
                }
            } else if (q == 34) {
                break;
            } else if (q == 10) {
                fail(c, "a string cannot span lines");
            } else {
                c.pos += 1;
            }
        }
        if (c.pos >= c.slen) {
            fail(c, "unterminated string");
        }
        c.tstart = start;
        c.tlen = c.pos - start;
        c.pos += 1;
        c.kind = K_STR;
        return;
    }

    c.tstart = c.pos;
    c.tlen = 1;
    if (b == 40) {
        c.pos += 1;
        c.kind = K_LP;
        return;
    }
    if (b == 41) {
        c.pos += 1;
        c.kind = K_RP;
        return;
    }
    if (b == 123) {
        c.pos += 1;
        c.kind = K_LB;
        return;
    }
    if (b == 125) {
        c.pos += 1;
        c.kind = K_RB;
        return;
    }
    if (b == 59) {
        c.pos += 1;
        c.kind = K_SEMI;
        return;
    }
    if (b == 44) {
        c.pos += 1;
        c.kind = K_COMMA;
        return;
    }
    if (b == 43) {
        if (at(c, 1) == 61) {
            c.pos += 2;
            c.kind = K_PLUSEQ;
        } else {
            c.pos += 1;
            c.kind = K_PLUS;
        }
        return;
    }
    if (b == 45) {
        if (at(c, 1) == 61) {
            c.pos += 2;
            c.kind = K_MINUSEQ;
        } else {
            c.pos += 1;
            c.kind = K_MINUS;
        }
        return;
    }
    if (b == 42) {
        if (at(c, 1) == 61) {
            c.pos += 2;
            c.kind = K_STAREQ;
        } else {
            c.pos += 1;
            c.kind = K_STAR;
        }
        return;
    }
    if (b == 47) {
        if (at(c, 1) == 61) {
            c.pos += 2;
            c.kind = K_SLASHEQ;
        } else {
            c.pos += 1;
            c.kind = K_SLASH;
        }
        return;
    }
    if (b == 37) {
        if (at(c, 1) == 61) {
            c.pos += 2;
            c.kind = K_PCTEQ;
        } else {
            c.pos += 1;
            c.kind = K_PCT;
        }
        return;
    }
    if (b == 61) {
        if (at(c, 1) == 61) {
            c.pos += 2;
            c.kind = K_EQ;
        } else if (at(c, 1) == 62) {
            c.pos += 2;
            c.kind = K_ARROW;
        } else {
            c.pos += 1;
            c.kind = K_ASSIGN;
        }
        return;
    }
    if (b == 33) {
        if (at(c, 1) == 61) {
            c.pos += 2;
            c.kind = K_NE;
        } else {
            c.pos += 1;
            c.kind = K_BANG;
        }
        return;
    }
    if (b == 60) {
        if (at(c, 1) == 61) {
            c.pos += 2;
            c.kind = K_LE;
        } else {
            c.pos += 1;
            c.kind = K_LT;
        }
        return;
    }
    if (b == 62) {
        if (at(c, 1) == 61) {
            c.pos += 2;
            c.kind = K_GE;
        } else {
            c.pos += 1;
            c.kind = K_GT;
        }
        return;
    }
    if (b == 38 && at(c, 1) == 38) {
        c.pos += 2;
        c.kind = K_ANDAND;
        return;
    }
    if (b == 124 && at(c, 1) == 124) {
        c.pos += 2;
        c.kind = K_OROR;
        return;
    }
    fail(c, "unexpected character");
}

fn peek_kind(c: &mut C) -> i64 {
    let p: i64 = c.pos;
    let k: i64 = c.kind;
    let s: i64 = c.tstart;
    let l: i64 = c.tlen;
    let v: i64 = c.tval;
    let ln: i64 = c.tline;
    advance(c);
    let r: i64 = c.kind;
    c.pos = p;
    c.kind = k;
    c.tstart = s;
    c.tlen = l;
    c.tval = v;
    c.tline = ln;
    return r;
}

fn node_new(c: &mut C, kind: i64) -> i64 {
    if (c.nn >= NMAX) {
        fail(c, "expression is too deep");
    }
    let i: i64 = c.nn;
    c.nn += 1;
    if (c.nn > c.peak) {
        c.peak = c.nn;
    }
    unsafe {
        let n: ptr<Node> = c.nodes;
        n[i].kind = kind;
        n[i].op = -1;
        n[i].a = -1;
        n[i].b = -1;
        n[i].next = -1;
        n[i].val = 0;
        n[i].len = 0;
    }
    return i;
}

fn node_kind(c: &mut C, i: i64) -> i64 {
    unsafe {
        return c.nodes[i].kind;
    }
}

fn node_op(c: &mut C, i: i64) -> i64 {
    unsafe {
        return c.nodes[i].op;
    }
}

fn node_a(c: &mut C, i: i64) -> i64 {
    unsafe {
        return c.nodes[i].a;
    }
}

fn node_b(c: &mut C, i: i64) -> i64 {
    unsafe {
        return c.nodes[i].b;
    }
}

fn node_next(c: &mut C, i: i64) -> i64 {
    unsafe {
        return c.nodes[i].next;
    }
}

fn node_val(c: &mut C, i: i64) -> i64 {
    unsafe {
        return c.nodes[i].val;
    }
}

fn node_len(c: &mut C, i: i64) -> i64 {
    unsafe {
        return c.nodes[i].len;
    }
}

fn set_op(c: &mut C, i: i64, v: i64) {
    unsafe {
        c.nodes[i].op = v;
    }
}

fn set_a(c: &mut C, i: i64, v: i64) {
    unsafe {
        c.nodes[i].a = v;
    }
}

fn set_b(c: &mut C, i: i64, v: i64) {
    unsafe {
        c.nodes[i].b = v;
    }
}

fn set_next(c: &mut C, i: i64, v: i64) {
    unsafe {
        c.nodes[i].next = v;
    }
}

fn set_span(c: &mut C, i: i64, val: i64, len: i64) {
    unsafe {
        c.nodes[i].val = val;
        c.nodes[i].len = len;
    }
}

fn op_text(c: &mut C, k: i64) {
    if (k == K_PLUS) {
        out_text(c, "+");
    } else if (k == K_MINUS) {
        out_text(c, "-");
    } else if (k == K_STAR) {
        out_text(c, "*");
    } else if (k == K_SLASH) {
        out_text(c, "/");
    } else if (k == K_PCT) {
        out_text(c, "%");
    } else if (k == K_LT) {
        out_text(c, "<");
    } else if (k == K_LE) {
        out_text(c, "<=");
    } else if (k == K_GT) {
        out_text(c, ">");
    } else if (k == K_GE) {
        out_text(c, ">=");
    } else if (k == K_EQ) {
        out_text(c, "==");
    } else if (k == K_NE) {
        out_text(c, "!=");
    } else if (k == K_ANDAND) {
        out_text(c, "&&");
    } else if (k == K_OROR) {
        out_text(c, "||");
    } else if (k == K_BANG) {
        out_text(c, "!");
    } else if (k == K_ASSIGN) {
        out_text(c, "=");
    } else if (k == K_PLUSEQ) {
        out_text(c, "+=");
    } else if (k == K_MINUSEQ) {
        out_text(c, "-=");
    } else if (k == K_STAREQ) {
        out_text(c, "*=");
    } else if (k == K_SLASHEQ) {
        out_text(c, "/=");
    } else if (k == K_PCTEQ) {
        out_text(c, "%=");
    } else {
        fail(c, "compiler lost an operator");
    }
}

fn builtin_call(c: &mut C, i: i64) {
    let k: i64 = node_op(c, i);
    if (k == B_ABS) {
        out_text(c, "(call mini_abs ");
        emit_node(c, node_a(c, i));
        out_text(c, ")");
    } else if (k == B_MIN) {
        out_text(c, "(call mini_min ");
        emit_node(c, node_a(c, i));
        out_text(c, " ");
        emit_node(c, node_next(c, node_a(c, i)));
        out_text(c, ")");
    } else if (k == B_MAX) {
        out_text(c, "(call mini_max ");
        emit_node(c, node_a(c, i));
        out_text(c, " ");
        emit_node(c, node_next(c, node_a(c, i)));
        out_text(c, ")");
    } else if (k == B_PUTS) {
        out_text(c, "(cast (call puts ");
        emit_node(c, node_a(c, i));
        out_text(c, ") i64)");
    } else if (k == B_PUTC) {
        out_text(c, "(cast (call putchar (cast ");
        emit_node(c, node_a(c, i));
        out_text(c, " i32)) i64)");
    }
}

fn emit_node(c: &mut C, n: i64) {
    let k: i64 = node_kind(c, n);
    if (k == N_INT) {
        out_text(c, "(int ");
        out_num(c, node_val(c, n));
        out_text(c, ")");
        return;
    }
    if (k == N_VAR) {
        out_text(c, "(var ");
        out_slice(c, node_val(c, n), node_len(c, n));
        out_text(c, ")");
        return;
    }
    if (k == N_STR) {
        out_text(c, "(str \"");
        out_slice(c, node_val(c, n), node_len(c, n));
        out_text(c, "\")");
        return;
    }
    if (k == N_BIN) {
        out_text(c, "(bin ");
        op_text(c, node_op(c, n));
        out_text(c, " ");
        emit_node(c, node_a(c, n));
        out_text(c, " ");
        emit_node(c, node_b(c, n));
        out_text(c, ")");
        return;
    }
    if (k == N_UN) {
        out_text(c, "(un ");
        op_text(c, node_op(c, n));
        out_text(c, " ");
        emit_node(c, node_a(c, n));
        out_text(c, ")");
        return;
    }
    if (k == N_BUILTIN) {
        builtin_call(c, n);
        return;
    }
    out_text(c, "(call ");
    out_slice(c, node_val(c, n), node_len(c, n));
    var a: i64 = node_a(c, n);
    while (a != -1) {
        out_text(c, " ");
        emit_node(c, a);
        a = node_next(c, a);
    }
    out_text(c, ")");
}
fn is_assign(k: i64) -> bool {
    return k == K_ASSIGN || k == K_PLUSEQ || k == K_MINUSEQ || k == K_STAREQ
        || k == K_SLASHEQ || k == K_PCTEQ;
}

fn expect(c: &mut C, k: i64, msg: ptr<u8>) {
    if (c.kind != k) {
        fail(c, msg);
    }
    advance(c);
}

fn str_bytes(c: &mut C, off: i64, len: i64) -> i64 {
    var i: i64 = 0;
    var n: i64 = 0;
    while (i < len) {
        if (ch(c, off + i) == 92) {
            i += 2;
        } else {
            i += 1;
        }
        n += 1;
    }
    return n;
}

fn one_arg(c: &mut C, what: ptr<u8>) -> i64 {
    advance(c);
    let e: i64 = expr(c);
    if (c.kind == K_COMMA) {
        fail(c, what);
    }
    expect(c, K_RP, "expected ')' after the argument");
    return e;
}

fn builtin_node(c: &mut C, s: i64, l: i64) -> i64 {
    if (word_is(c, s, l, "abs")) {
        let e: i64 = one_arg(c, "'abs' takes exactly one value");
        c.want_abs = 1;
        let n: i64 = node_new(c, N_BUILTIN);
        set_op(c, n, B_ABS);
        set_a(c, n, e);
        return n;
    }
    if (word_is(c, s, l, "puts")) {
        let e: i64 = one_arg(c, "'puts' takes exactly one string");
        c.want_puts = 1;
        let n: i64 = node_new(c, N_BUILTIN);
        set_op(c, n, B_PUTS);
        set_a(c, n, e);
        return n;
    }
    if (word_is(c, s, l, "putc")) {
        let e: i64 = one_arg(c, "'putc' takes exactly one value");
        c.want_putc = 1;
        let n: i64 = node_new(c, N_BUILTIN);
        set_op(c, n, B_PUTC);
        set_a(c, n, e);
        return n;
    }
    if (word_is(c, s, l, "len")) {
        let e: i64 = one_arg(c, "'len' takes exactly one string literal");
        if (node_kind(c, e) != N_STR) {
            fail(c, "'len' wants a string literal");
        }
        let n: i64 = node_new(c, N_INT);
        set_span(c, n, str_bytes(c, node_val(c, e), node_len(c, e)), 0);
        return n;
    }
    if (word_is(c, s, l, "min") || word_is(c, s, l, "max")) {
        advance(c);
        let a: i64 = expr(c);
        expect(c, K_COMMA, "'min' and 'max' take two values");
        let b: i64 = expr(c);
        expect(c, K_RP, "expected ')' after the second value");
        let n: i64 = node_new(c, N_BUILTIN);
        if (word_is(c, s, l, "min")) {
            set_op(c, n, B_MIN);
            c.want_min = 1;
        } else {
            set_op(c, n, B_MAX);
            c.want_max = 1;
        }
        set_a(c, n, a);
        set_next(c, a, b);
        return n;
    }
    return -1;
}

fn primary(c: &mut C) -> i64 {
    if (c.kind == K_NUM) {
        let n: i64 = node_new(c, N_INT);
        set_span(c, n, c.tval, 0);
        advance(c);
        return n;
    }
    if (c.kind == K_STR) {
        let n: i64 = node_new(c, N_STR);
        set_span(c, n, c.tstart, c.tlen);
        advance(c);
        return n;
    }
    if (c.kind == K_LP) {
        advance(c);
        let e: i64 = expr(c);
        expect(c, K_RP, "expected ')'");
        return e;
    }
    if (c.kind == K_ID) {
        let s: i64 = c.tstart;
        let l: i64 = c.tlen;
        advance(c);
        if (c.kind == K_LP) {
            let b: i64 = builtin_node(c, s, l);
            if (b != -1) {
                return b;
            }
            let n: i64 = node_new(c, N_CALL);
            set_span(c, n, s, l);
            advance(c);
            var last: i64 = -1;
            while (c.kind != K_RP) {
                let arg: i64 = expr(c);
                if (last == -1) {
                    set_a(c, n, arg);
                } else {
                    set_next(c, last, arg);
                }
                last = arg;
                if (c.kind == K_COMMA) {
                    advance(c);
                } else if (c.kind != K_RP) {
                    fail(c, "expected ',' or ')' in a call");
                }
            }
            advance(c);
            return n;
        }
        let v: i64 = node_new(c, N_VAR);
        set_span(c, v, s, l);
        return v;
    }
    fail(c, "expected an expression");
    return 0;
}

fn unary(c: &mut C) -> i64 {
    if (c.kind == K_MINUS || c.kind == K_BANG) {
        let op: i64 = c.kind;
        advance(c);
        let a: i64 = unary(c);
        let n: i64 = node_new(c, N_UN);
        set_op(c, n, op);
        set_a(c, n, a);
        return n;
    }
    return primary(c);
}

fn mul_expr(c: &mut C) -> i64 {
    var left: i64 = unary(c);
    while (c.kind == K_STAR || c.kind == K_SLASH || c.kind == K_PCT) {
        let op: i64 = c.kind;
        advance(c);
        let right: i64 = unary(c);
        let n: i64 = node_new(c, N_BIN);
        set_op(c, n, op);
        set_a(c, n, left);
        set_b(c, n, right);
        left = n;
    }
    return left;
}

fn add_expr(c: &mut C) -> i64 {
    var left: i64 = mul_expr(c);
    while (c.kind == K_PLUS || c.kind == K_MINUS) {
        let op: i64 = c.kind;
        advance(c);
        let right: i64 = mul_expr(c);
        let n: i64 = node_new(c, N_BIN);
        set_op(c, n, op);
        set_a(c, n, left);
        set_b(c, n, right);
        left = n;
    }
    return left;
}

fn cmp_expr(c: &mut C) -> i64 {
    var left: i64 = add_expr(c);
    while (c.kind == K_LT || c.kind == K_LE || c.kind == K_GT || c.kind == K_GE
        || c.kind == K_EQ || c.kind == K_NE) {
        let op: i64 = c.kind;
        advance(c);
        let right: i64 = add_expr(c);
        let n: i64 = node_new(c, N_BIN);
        set_op(c, n, op);
        set_a(c, n, left);
        set_b(c, n, right);
        left = n;
    }
    return left;
}

fn and_expr(c: &mut C) -> i64 {
    var left: i64 = cmp_expr(c);
    while (c.kind == K_ANDAND) {
        advance(c);
        let right: i64 = cmp_expr(c);
        let n: i64 = node_new(c, N_BIN);
        set_op(c, n, K_ANDAND);
        set_a(c, n, left);
        set_b(c, n, right);
        left = n;
    }
    return left;
}

fn expr(c: &mut C) -> i64 {
    var left: i64 = and_expr(c);
    while (c.kind == K_OROR) {
        advance(c);
        let right: i64 = and_expr(c);
        let n: i64 = node_new(c, N_BIN);
        set_op(c, n, K_OROR);
        set_a(c, n, left);
        set_b(c, n, right);
        left = n;
    }
    return left;
}

fn remember(c: &mut C, s: i64, l: i64) {
    var i: i64 = 0;
    while (i < c.nfn) {
        var len_i: i64 = 0;
        var off_i: i64 = 0;
        unsafe {
            len_i = c.fnlen[i];
            off_i = c.fns[i];
        }
        if (len_i == l) {
            var k: i64 = 0;
            var hit: bool = true;
            while (k < l) {
                if (ch(c, off_i + k) != ch(c, s + k)) {
                    hit = false;
                }
                k += 1;
            }
            if (hit) {
                fail(c, "that function is already defined");
            }
        }
        i += 1;
    }
    if (c.nfn >= FNMAX) {
        fail(c, "too many functions");
    }
    unsafe {
        c.fns[c.nfn] = s;
        c.fnlen[c.nfn] = l;
    }
    c.nfn += 1;
}

fn reserved_name(c: &mut C, s: i64, l: i64) {
    if (word_is(c, s, l, "print") || word_is(c, s, l, "abs") || word_is(c, s, l, "min")
        || word_is(c, s, l, "max") || word_is(c, s, l, "puts") || word_is(c, s, l, "putc")
        || word_is(c, s, l, "len")) {
        fail(c, "that name is built in, pick another");
    }
}

fn parse_block(c: &mut C, in_main: i64) -> i64 {
    expect(c, K_LB, "expected '{'");
    var last: i64 = 0;
    while (c.kind != K_RB) {
        if (c.kind == K_EOF) {
            fail(c, "the file ends inside a block");
        }
        last = parse_stmt(c, in_main);
    }
    advance(c);
    return last;
}

fn parse_print(c: &mut C) -> i64 {
    advance(c);
    expect(c, K_LP, "expected '(' after 'print'");
    var first: i64 = -1;
    var last: i64 = -1;
    while (c.kind != K_RP) {
        if (c.kind == K_EOF) {
            fail(c, "the file ends inside a print");
        }
        let e: i64 = expr(c);
        if (first == -1) {
            first = e;
        } else {
            set_next(c, last, e);
        }
        last = e;
        if (c.kind == K_COMMA) {
            advance(c);
        } else if (c.kind != K_RP) {
            fail(c, "expected ',' or ')' after a printed value");
        }
    }
    advance(c);
    expect(c, K_SEMI, "expected ';' after 'print'");
    out_text(c, "(expr (call printf (str \"");
    var n: i64 = first;
    var nb: i64 = 0;
    while (n != -1) {
        if (nb > 0) {
            out_byte(c, 32);
        }
        if (node_kind(c, n) == N_STR) {
            out_text(c, "%s");
        } else {
            out_text(c, "%lld");
        }
        nb += 1;
        n = node_next(c, n);
    }
    out_text(c, "\\n\")");
    n = first;
    while (n != -1) {
        out_byte(c, 32);
        emit_node(c, n);
        n = node_next(c, n);
    }
    out_text(c, "))\n");
    return 0;
}
fn case_test(c: &mut C, tmp: i64, v: i64) {
    out_text(c, "(bin == (var __mini_case");
    out_num(c, tmp);
    out_text(c, ") ");
    emit_node(c, v);
    out_text(c, ")");
}

fn case_cond(c: &mut C, tmp: i64, first: i64, count: i64) {
    var wraps: i64 = count - 1;
    var w: i64 = 0;
    while (w < wraps) {
        out_text(c, "(bin || ");
        w += 1;
    }
    var n: i64 = first;
    var i: i64 = 0;
    while (n != -1) {
        if (i > 0) {
            out_text(c, " ");
            case_test(c, tmp, n);
            out_text(c, ")");
        } else {
            case_test(c, tmp, n);
        }
        i += 1;
        n = node_next(c, n);
    }
}

fn parse_case(c: &mut C, in_main: i64) -> i64 {
    advance(c);
    expect(c, K_LP, "expected '(' after 'case'");
    let subject: i64 = expr(c);
    expect(c, K_RP, "expected ')' after the case value");
    let tmp: i64 = c.cases;
    c.cases += 1;
    out_text(c, "(let __mini_case");
    out_num(c, tmp);
    out_text(c, " i64 ");
    emit_node(c, subject);
    out_text(c, ")\n");
    expect(c, K_LB, "expected '{' to open a case");
    var opens: i64 = 0;
    var default: i64 = 0;
    while (c.kind != K_RB) {
        if (c.kind == K_EOF) {
            fail(c, "the file ends inside a case");
        }
        if (default == 1) {
            fail(c, "the 'else' arm has to come last");
        }
        if (c.kind == K_ELSE) {
            advance(c);
            expect(c, K_ARROW, "expected '=>' after 'else'");
            out_text(c, "(block\n");
            parse_block(c, in_main);
            out_text(c, ")\n");
            default = 1;
        } else {
            var first: i64 = -1;
            var last: i64 = -1;
            var cnt: i64 = 0;
            var more: bool = true;
            while (more) {
                let v: i64 = expr(c);
                if (first == -1) {
                    first = v;
                } else {
                    set_next(c, last, v);
                }
                last = v;
                cnt += 1;
                if (c.kind == K_COMMA) {
                    advance(c);
                } else {
                    more = false;
                }
            }
            expect(c, K_ARROW, "expected '=>' after a case value");
            out_text(c, "(if ");
            case_cond(c, tmp, first, cnt);
            out_text(c, " (then\n");
            parse_block(c, in_main);
            out_text(c, ")");
            opens += 1;
        }
        if (c.kind != K_RB) {
            out_text(c, " (else ");
            opens += 1;
        }
    }
    advance(c);
    var i: i64 = 0;
    while (i < opens) {
        out_text(c, ")");
        i += 1;
    }
    out_text(c, "\n");
    return 0;
}

fn reserved_bind(c: &mut C, s: i64, l: i64) {
    if (l >= 7 && word_is(c, s, 7, "__mini_")) {
        fail(c, "names starting with '__mini_' belong to the compiler");
    }
}

fn parse_stmt(c: &mut C, in_main: i64) -> i64 {
    c.nn = 0;

    if (c.kind == K_LET || c.kind == K_VAR) {
        var mutable: i64 = 0;
        if (c.kind == K_VAR) {
            mutable = 1;
        }
        advance(c);
        if (c.kind != K_ID) {
            fail(c, "expected a name after 'let' or 'var'");
        }
        let s: i64 = c.tstart;
        let l: i64 = c.tlen;
        reserved_bind(c, s, l);
        advance(c);
        expect(c, K_ASSIGN, "expected '=' after a name");
        let e: i64 = expr(c);
        expect(c, K_SEMI, "expected ';'");
        if (mutable == 1) {
            out_text(c, "(var ");
        } else {
            out_text(c, "(let ");
        }
        out_slice(c, s, l);
        out_text(c, " i64 ");
        emit_node(c, e);
        out_text(c, ")\n");
        return 0;
    }

    if (c.kind == K_RETURN) {
        advance(c);
        if (c.kind == K_SEMI) {
            advance(c);
            out_text(c, "(return (int 0))\n");
            return 1;
        }
        let e: i64 = expr(c);
        expect(c, K_SEMI, "expected ';' after 'return'");
        if (in_main == 1) {
            out_text(c, "(return (cast ");
            emit_node(c, e);
            out_text(c, " i32))\n");
        } else {
            out_text(c, "(return ");
            emit_node(c, e);
            out_text(c, ")\n");
        }
        return 1;
    }

    if (c.kind == K_PRINT) {
        return parse_print(c);
    }

    if (c.kind == K_CASE) {
        return parse_case(c, in_main);
    }

    if (c.kind == K_BREAK) {
        advance(c);
        expect(c, K_SEMI, "expected ';' after 'break'");
        out_text(c, "(break)\n");
        return 1;
    }

    if (c.kind == K_CONTINUE) {
        advance(c);
        expect(c, K_SEMI, "expected ';' after 'continue'");
        out_text(c, "(continue)\n");
        return 1;
    }

    if (c.kind == K_IF) {
        advance(c);
        expect(c, K_LP, "expected '(' after 'if'");
        let cond: i64 = expr(c);
        expect(c, K_RP, "expected ')' after the condition");
        out_text(c, "(if ");
        emit_node(c, cond);
        out_text(c, " (then\n");
        parse_block(c, in_main);
        out_text(c, ")");
        if (c.kind == K_ELSE) {
            advance(c);
            out_text(c, " (else\n");
            if (c.kind == K_IF) {
                parse_stmt(c, in_main);
            } else {
                parse_block(c, in_main);
            }
            out_text(c, ")");
        }
        out_text(c, ")\n");
        return 0;
    }

    if (c.kind == K_WHILE) {
        advance(c);
        expect(c, K_LP, "expected '(' after 'while'");
        let cond: i64 = expr(c);
        expect(c, K_RP, "expected ')' after the condition");
        out_text(c, "(while ");
        emit_node(c, cond);
        out_text(c, "\n");
        if (c.kind != K_LB) {
            fail(c, "expected '{' after a 'while' condition");
        }
        advance(c);
        while (c.kind != K_RB) {
            if (c.kind == K_EOF) {
                fail(c, "the file ends inside a loop");
            }
            parse_stmt(c, in_main);
        }
        advance(c);
        out_text(c, ")\n");
        return 0;
    }

    if (c.kind == K_LB) {
        out_text(c, "(block\n");
        parse_block(c, in_main);
        out_text(c, ")\n");
        return 0;
    }

    if (c.kind == K_ID && is_assign(peek_kind(c))) {
        let target: i64 = expr(c);
        let op: i64 = c.kind;
        advance(c);
        let rhs: i64 = expr(c);
        expect(c, K_SEMI, "expected ';' after an assignment");
        if (node_kind(c, target) != N_VAR) {
            fail(c, "the left side of an assignment must be a name");
        }
        out_text(c, "(assign ");
        op_text(c, op);
        out_text(c, " ");
        emit_node(c, target);
        out_text(c, " ");
        emit_node(c, rhs);
        out_text(c, ")\n");
        return 0;
    }

    let e: i64 = expr(c);
    expect(c, K_SEMI, "expected ';' after a statement");
    out_text(c, "(expr ");
    emit_node(c, e);
    out_text(c, ")\n");
    return 0;
}

fn parse_fn(c: &mut C) {
    advance(c);
    if (c.kind != K_ID) {
        fail(c, "expected a function name");
    }
    let s: i64 = c.tstart;
    let l: i64 = c.tlen;
    reserved_name(c, s, l);
    remember(c, s, l);
    var is_main: i64 = 0;
    if (word_is(c, s, l, "main")) {
        is_main = 1;
        c.saw_main = 1;
    }
    out_text(c, "  (fn ");
    out_slice(c, s, l);
    advance(c);
    expect(c, K_LP, "expected '(' after a function name");
    var np: i64 = 0;
    while (c.kind != K_RP) {
        if (c.kind != K_ID) {
            fail(c, "expected a parameter name");
        }
        reserved_bind(c, c.tstart, c.tlen);
        out_text(c, " (param ");
        out_slice(c, c.tstart, c.tlen);
        out_text(c, " i64)");
        np += 1;
        advance(c);
        if (c.kind == K_COMMA) {
            advance(c);
        } else if (c.kind != K_RP) {
            fail(c, "expected ',' or ')' in the parameter list");
        }
    }
    advance(c);
    if (is_main == 1) {
        if (np != 0) {
            fail(c, "'main' takes no parameters");
        }
        out_text(c, " (ret i32) (body\n");
    } else {
        out_text(c, " (ret i64) (body\n");
    }
    let last: i64 = parse_block(c, is_main);
    if (last == 0) {
        out_text(c, "    (return (int 0))\n");
    }
    out_text(c, "  ))\n");
}

fn emit_helpers(c: &mut C) {
    if (c.want_puts == 1) {
        out_text(c, "  (extern puts (param (ptr u8)) (ret i32))\n");
    }
    if (c.want_putc == 1) {
        out_text(c, "  (extern putchar (param i32) (ret i32))\n");
    }
    if (c.want_abs == 1) {
        out_text(c, "  (fn mini_abs (param x i64) (ret i64) (body\n");
        out_text(c, "    (if (bin < x (int 0)) (then\n");
        out_text(c, "      (return (un - x))\n");
        out_text(c, "    ))\n");
        out_text(c, "    (return x)\n");
        out_text(c, "  ))\n");
    }
    if (c.want_min == 1) {
        out_text(c, "  (fn mini_min (param a i64) (param b i64) (ret i64) (body\n");
        out_text(c, "    (if (bin < a b) (then (return a)))\n");
        out_text(c, "    (return b)\n");
        out_text(c, "  ))\n");
    }
    if (c.want_max == 1) {
        out_text(c, "  (fn mini_max (param a i64) (param b i64) (ret i64) (body\n");
        out_text(c, "    (if (bin > a b) (then (return a)))\n");
        out_text(c, "    (return b)\n");
        out_text(c, "  ))\n");
    }
}

fn parse_program(c: &mut C) {
    out_text(c, "(program\n");
    out_text(c, "  (extern printf (param (ptr u8)) (variadic) (ret i32))\n");
    advance(c);
    while (c.kind != K_EOF) {
        if (c.kind != K_FN) {
            fail(c, "only 'fn' definitions belong at the top level");
        }
        parse_fn(c);
    }
    if (c.saw_main == 0) {
        fail(c, "no 'main' function");
    }
    emit_helpers(c);
    out_text(c, ")\n");
}

fn reset(c: &mut C) {
    c.slen = 0;
    c.olen = 0;
    c.nn = 0;
    c.peak = 0;
    c.nfn = 0;
    c.pos = 0;
    c.line = 1;
    c.tline = 1;
    c.kind = K_EOF;
    c.tstart = 0;
    c.tlen = 0;
    c.tval = 0;
    c.saw_main = 0;
    c.cases = 0;
    c.want_abs = 0;
    c.want_min = 0;
    c.want_max = 0;
    c.want_puts = 0;
    c.want_putc = 0;
}

fn compile(c: &mut C) {
    parse_program(c);
}
fn read_stdin(c: &mut C) {
    var got: i64 = 1;
    unsafe {
        while (got > 0 && c.slen < SRCMAX) {
            var room: i64 = SRCMAX - c.slen;
            if (room > CHUNK) {
                room = CHUNK;
            }
            got = host_read_stdin(c.src + c.slen, room);
            if (got <= 0) {
                break;
            }
            c.slen += got;
        }
    }
    if (c.slen >= SRCMAX) {
        quit("mini: the source is larger than 1 MB");
    }
}

fn read_path(c: &mut C, path: ptr<u8>) -> i32 {
    let got: i64 = host_read_file(path, c.src, SRCMAX);
    if (got < 0) {
        return 1;
    }
    c.slen = got;
    if (c.slen >= SRCMAX) {
        return 2;
    }
    return 0;
}

fn write_path(path: ptr<u8>, buf: ptr<u8>, n: i64) -> i32 {
    return host_write_file(path, buf, n);
}

fn same(a: ptr<u8>, b: ptr<u8>) -> bool {
    var i: i64 = 0;
    while (true) {
        let x: u8 = pb(a, i);
        if (x != pb(b, i)) {
            return false;
        }
        if (x == 0) {
            return true;
        }
        i += 1;
    }
    return false;
}

fn cat(dst: ptr<u8>, k: i64, cap: i64, s: ptr<u8>) -> i64 {
    var i: i64 = 0;
    while (pb(s, i) != 0 && k < cap - 1) {
        pset(dst, k, pb(s, i));
        k += 1;
        i += 1;
    }
    pset(dst, k, 0);
    return k;
}

fn num_to(dst: ptr<u8>, k: i64, v: i64) -> i64 {
    if (v >= 10) {
        k = num_to(dst, k, v / 10);
    }
    pset(dst, k, (v % 10) as u8 + 48);
    pset(dst, k + 1, 0);
    return k + 1;
}

fn derive_exe(dst: ptr<u8>, src: ptr<u8>) -> i64 {
    var i: i64 = 0;
    var dot: i64 = -1;
    var slash: i64 = -1;
    while (pb(src, i) != 0) {
        if (pb(src, i) == 46) {
            dot = i;
        }
        if (pb(src, i) == 92 || pb(src, i) == 47) {
            slash = i;
        }
        pset(dst, i, pb(src, i));
        i += 1;
    }
    if (dot > slash) {
        i = dot;
    }
    let ext: ptr<u8> = host_ext();
    var k: i64 = 0;
    while (pb(ext, k) != 0) {
        pset(dst, i + k, pb(ext, k));
        k += 1;
    }
    pset(dst, i + k, 0);
    return i + k;
}

fn temp_file(dst: ptr<u8>, cap: i64, tag: ptr<u8>) -> i64 {
    var k: i64 = host_temp(dst, cap);
    k = cat(dst, k, cap, "mini");
    k = num_to(dst, k, host_pid());
    k = cat(dst, k, cap, "-");
    k = cat(dst, k, cap, tag);
    return k;
}

fn backend_path(dst: ptr<u8>, cap: i64) -> i64 {
    let n: i64 = host_self(dst, cap);
    var i: i64 = n;
    while (i > 0 && pb(dst, i - 1) != 92 && pb(dst, i - 1) != 47) {
        i -= 1;
    }
    var k: i64 = i;
    k = cat(dst, k, cap, "..");
    k = cat(dst, k, cap, host_sep());
    k = cat(dst, k, cap, "backend");
    k = cat(dst, k, cap, host_sep());
    k = cat(dst, k, cap, "rscb");
    k = cat(dst, k, cap, host_ext());
    return k;
}

fn run_cmd(line: ptr<u8>) -> i32 {
    return host_run(line);
}

fn usage() -> i32 {
    shout("usage: mini [--emit|--aot|--jit] file.mini [-o out]");
    shout("       mini -v");
    shout("       mini < prog.mini > prog.rsi");
    return 2;
}

fn do_emit(c: &mut C, sp: ptr<u8>, outp: ptr<u8>, have_out: i64) -> i32 {
    if (read_path(c, sp) != 0) {
        shout("mini: cannot read the source file");
        return 1;
    }
    compile(c);
    if (have_out == 0) {
        write_all(c.out, c.olen);
        return 0;
    }
    if (write_path(outp, c.out, c.olen) != 0) {
        shout("mini: cannot write the ir file");
        return 1;
    }
    return 0;
}

fn do_aot(c: &mut C, sp: ptr<u8>, outp: ptr<u8>, have_out: i64) -> i32 {
    if (read_path(c, sp) != 0) {
        shout("mini: cannot read the source file");
        return 1;
    }
    compile(c);
    var ob: [u8; 1024] = [0];
    var ib: [u8; 1024] = [0];
    var bb: [u8; 1024] = [0];
    var lb: [u8; 4096] = [0];
    var op: ptr<u8> = null;
    var ip: ptr<u8> = null;
    var bp: ptr<u8> = null;
    var lp: ptr<u8> = null;
    unsafe {
        op = &mut ob[0] as ptr<u8>;
        ip = &mut ib[0] as ptr<u8>;
        bp = &mut bb[0] as ptr<u8>;
        lp = &mut lb[0] as ptr<u8>;
    }
    if (have_out == 0) {
        derive_exe(op, sp);
    } else {
        cat(op, 0, 1024, outp);
    }
    temp_file(ip, 1024, "rsi");
    if (write_path(ip, c.out, c.olen) != 0) {
        shout("mini: cannot write the ir file");
        return 1;
    }
    backend_path(bp, 1024);
    var k: i64 = 0;
    k = cat(lp, k, 4096, "\"");
    k = cat(lp, k, 4096, bp);
    k = cat(lp, k, 4096, "\" \"");
    k = cat(lp, k, 4096, ip);
    k = cat(lp, k, 4096, "\" -o \"");
    k = cat(lp, k, 4096, op);
    k = cat(lp, k, 4096, "\" -t ");
    k = cat(lp, k, 4096, host_target());
    let rc: i32 = run_cmd(lp);
    host_delete(ip);
    if (rc != 0) {
        shout("mini: the back end refused the program");
        return 1;
    }
    return 0;
}

fn do_jit(c: &mut C, sp: ptr<u8>, start: i64) -> i32 {
    if (read_path(c, sp) != 0) {
        shout("mini: cannot read the source file");
        return 1;
    }
    compile(c);
    var ib: [u8; 1024] = [0];
    var bb: [u8; 1024] = [0];
    var eb: [u8; 1024] = [0];
    var lb: [u8; 4096] = [0];
    var ab: [u8; 1024] = [0];
    var ip: ptr<u8> = null;
    var bp: ptr<u8> = null;
    var ep: ptr<u8> = null;
    var lp: ptr<u8> = null;
    var ap: ptr<u8> = null;
    unsafe {
        ip = &mut ib[0] as ptr<u8>;
        bp = &mut bb[0] as ptr<u8>;
        ep = &mut eb[0] as ptr<u8>;
        lp = &mut lb[0] as ptr<u8>;
        ap = &mut ab[0] as ptr<u8>;
    }
    temp_file(ip, 1024, "rsi");
    temp_file(ep, 1024, "bin");
    if (write_path(ip, c.out, c.olen) != 0) {
        shout("mini: cannot write the ir file");
        return 1;
    }
    backend_path(bp, 1024);
    var k: i64 = 0;
    k = cat(lp, k, 4096, "\"");
    k = cat(lp, k, 4096, bp);
    k = cat(lp, k, 4096, "\" \"");
    k = cat(lp, k, 4096, ip);
    k = cat(lp, k, 4096, "\" -o \"");
    k = cat(lp, k, 4096, ep);
    k = cat(lp, k, 4096, "\" -t ");
    k = cat(lp, k, 4096, host_target());
    let bc: i32 = run_cmd(lp);
    host_delete(ip);
    if (bc != 0) {
        shout("mini: the back end refused the program");
        return 1;
    }
    k = 0;
    k = cat(lp, k, 4096, "\"");
    k = cat(lp, k, 4096, ep);
    k = cat(lp, k, 4096, "\"");
    var i: i64 = start;
    let argc: i64 = host_argc();
    while (i < argc) {
        if (host_arg(i, ap, 1024) < 0) {
            break;
        }
        if (k > 3000) {
            shout("mini: too many program arguments");
            host_delete(ep);
            return 1;
        }
        k = cat(lp, k, 4096, " \"");
        k = cat(lp, k, 4096, ap);
        k = cat(lp, k, 4096, "\"");
        i += 1;
    }
    let rc: i32 = run_cmd(lp);
    host_delete(ep);
    if (rc < 0) {
        shout("mini: cannot run the program");
        return 1;
    }
    return rc;
}

const BANNER: ptr<u8> = "                                         :::::::\n                                     ::::::::::::::\n                                  :::::::::::::::::::::\n                              ::::::::::::::::::::::::::::\n                           :::::::::::::::::::::::::::::::::::\n                       ::::::::::::::::::::::::::::::::::::::::::\n                    :::::::::::::::::::::::::::::::::::::::::::::::::\n                ::::::::::::::::::::::::::::::::::::::::::::::::::::::::\n             :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::\n          ::::::::::::::::                           :::::::::::::::::::::::::\n         :::::::::::::::::                               ::::::::::::::::::::::\n         :::::::::::::::::                                 :::::::::::::::::::::\n         :::::::::::::::::                   :              ::::::::::::::::::::\n         :::::::::::::::::          ::::::::::::::           :::::::::::::::::::\n         :::::::::::::::::          ::::::::::::::::         :::::::::::::::::::\n         :::::::::::::::::          ::::::::::::::::         :::::::::::::::::::\n         :::::::::::::::::          ::::::::::::::::         :::::::::::::::::::\n         :::::::::::::::::          :::::::::::::::          :::: ::::  ::::::::\n         :::::::::::::::::          ::::::::::::::           ::           ::::::\n         :::::::::::::::::                                 ::::::  :::  ::::::::\n         :::::::::::::::::                                :::::::  :::  ::::::::\n         :::::::::::::::::                             ::::::::           ::::::\n         :::::::::::::::::                            :+::::::::: ::::  ::::::::\n         :::::::::::::::::          :::::::::          :+:::::::::::::::::::::::\n         :::::::::::::::::          ::::::::+:          :+++::::::::::::::::::::\n         :::::::::::::::::          ::::::::++:          :+++++:::::::::::::::::\n         :::::::::::::::::          ::::::::+++:          :++++++++:::::::::::::\n         :::::::::::::::::          ::::::::++++:           :+++++++++::::::::::\n         :::::::::::::::::          ::::::::++++++:          :++++++++++++::::::\n         :::::::::::::::::          ::::::::+++++++:          :+++++++++++++++:\n          :::::::::::::::::        :::::::::++++++++:::::::::: :+++++++++++++:\n            ::::::::::::::::::::::::::::::::+++++++++++++++++++++++++++++:::\n                ::::::::::::::::::::::::::::++++++++++++++++++++++++++::\n                   :::::::::::::::::::::::::++++++++++++++++++++++:::\n                       :::::::::::::::::::::+++++++++++++++++++::\n                          ::::::::::::::::::+++++++++++++++:::\n                              ::::::::::::::++++++++++++:::\n                                 :::::::::::++++++++:::\n                                     :::::::+++++:::\n                                        ::::::::\n\n                                mini Compiler for R# 1.2\n                           jit + aot - one file - no runtime\n\n";

fn main() -> i32 {
    var c: C = zero(C);
    c.src = grab(SRCMAX);
    c.out = grab(OUTMAX);
    c.nodes = grab(NMAX * NODEB) as ptr<Node>;
    c.fns = grab(FNMAX * 8) as ptr<i64>;
    c.fnlen = grab(FNMAX * 8) as ptr<i64>;
    reset(&mut c);

    let argc: i64 = host_argc();
    if (argc < 2) {
        read_stdin(&mut c);
        compile(&mut c);
        write_all(c.out, c.olen);
        return 0;
    }

    var b1: [u8; 512] = [0];
    var b2: [u8; 512] = [0];
    var b3: [u8; 512] = [0];
    var p1: ptr<u8> = null;
    var p2: ptr<u8> = null;
    var p3: ptr<u8> = null;
    unsafe {
        p1 = &mut b1[0] as ptr<u8>;
        p2 = &mut b2[0] as ptr<u8>;
        p3 = &mut b3[0] as ptr<u8>;
    }
    if (host_arg(1, p1, 512) < 0) {
        return usage();
    }

    if (same(p1, "-v") || same(p1, "--version")) {
        write_all(BANNER, wlen(BANNER));
        return 0;
    }
    if (same(p1, "--help") || same(p1, "-h")) {
        return usage();
    }

    if (same(p1, "--emit")) {
        if (host_arg(2, p2, 512) < 0) {
            return usage();
        }
        if (host_arg(3, p3, 512) >= 0) {
            if (same(p3, "-o")) {
                if (host_arg(4, p3, 512) < 0) {
                    return usage();
                }
                let r: i32 = do_emit(&mut c, p2, p3, 1);
                return r;
            }
        }
        let r: i32 = do_emit(&mut c, p2, p3, 0);
        return r;
    }

    if (same(p1, "--aot")) {
        if (host_arg(2, p2, 512) < 0) {
            return usage();
        }
        if (host_arg(3, p3, 512) >= 0) {
            if (same(p3, "-o")) {
                if (host_arg(4, p3, 512) < 0) {
                    return usage();
                }
                let r: i32 = do_aot(&mut c, p2, p3, 1);
                return r;
            }
        }
        let r: i32 = do_aot(&mut c, p2, p3, 0);
        return r;
    }

    if (same(p1, "--jit")) {
        if (host_arg(2, p2, 512) < 0) {
            return usage();
        }
        let r: i32 = do_jit(&mut c, p2, 3);
        return r;
    }

    if (pb(p1, 0) == 45) {
        return usage();
    }

    let r: i32 = do_emit(&mut c, p1, p3, 0);
    return r;
}

