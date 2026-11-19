include "base.rsx";
include "ast.rsx";
include "lex.rsx";

struct Fr {
    lx: Lexer,
    i: i64,
    lifts: i64,
    clo: i64,
    methods: i64,
    pfx: i64,
    tmpn: i64,
    tparams: i64,
    ok: i32,
    tl: i64,
    tc: i64,
    incl: i32,
    op: i64,
    prec: i64,
    ntok: i64,
    err: Sb,
    tmp: Sb,
    des: Sb,
    na: Na,
    lp: Lp,
    sp: Sp,
    tdefs: MapI,
    fmap: MapI,
    frmap: MapI,
    smap: MapI,
    fatm: MapI,
    fvmap: MapI,
    vtst: MapI,
    dynst: MapI,
    genf: i64,
    genx: i64,
    synl: i64,
    fatl: i64,
    vtl: i64,
    dynl: i64,
    scp: i64,
    rtyp: i64,
    trl: i64,
    til: i64,
    implty: i64,
    adap: i64
}

fn fr_new() -> Fr {
    var f: Fr = zero(Fr);
    f.lx = lex_new();
    f.err = sb_new(256);
    f.tmp = sb_new(256);
    f.des = sb_new(128);
    f.na = na_new();
    f.lp = lp_new();
    f.sp = sp_new();
    f.tdefs = m64_new();
    f.fmap = m64_new();
    f.frmap = m64_new();
    f.smap = m64_new();
    f.fatm = m64_new();
    f.fvmap = m64_new();
    f.vtst = m64_new();
    f.dynst = m64_new();
    f.lifts = lp_add(&mut f.lp);
    f.methods = lp_add(&mut f.lp);
    f.tparams = lp_add(&mut f.lp);
    f.genf = lp_add(&mut f.lp);
    f.genx = lp_add(&mut f.lp);
    f.synl = lp_add(&mut f.lp);
    f.fatl = lp_add(&mut f.lp);
    f.vtl = lp_add(&mut f.lp);
    f.dynl = lp_add(&mut f.lp);
    f.scp = lp_add(&mut f.lp);
    f.rtyp = lp_add(&mut f.lp);
    f.trl = lp_add(&mut f.lp);
    f.adap = 0;
    f.til = lp_add(&mut f.lp);
    f.ok = 1;
    return f;
}

fn fr_free(f: &mut Fr) {
    lex_free(&mut f.lx);
    sb_free(&mut f.err);
    sb_free(&mut f.tmp);
    sb_free(&mut f.des);
    na_free(&mut f.na);
    lp_free(&mut f.lp);
    sp_free(&mut f.sp);
    m64_free(&mut f.tdefs);
    m64_free(&mut f.fmap);
    m64_free(&mut f.frmap);
    m64_free(&mut f.smap);
    m64_free(&mut f.fatm);
    m64_free(&mut f.fvmap);
    m64_free(&mut f.vtst);
    m64_free(&mut f.dynst);
}

fn p_pr_new(x: &mut Fr) -> Pr {
    var p: Pr = zero(Pr);
    p.c = lp_add(&mut x.lp);
    p.g = lp_add(&mut x.lp);
    p.s = lp_add(&mut x.lp);
    p.e = lp_add(&mut x.lp);
    p.x = lp_add(&mut x.lp);
    p.f = lp_add(&mut x.lp);
    return p;
}

fn p_kind(x: &mut Fr, at: i64) -> i32 {
    if (at == x.i) {
        return x.lx.cur.kind;
    }
    if (at == x.i + 1) {
        return x.lx.peek.kind;
    }
    return 0 - 1;
}

fn p_line(x: &mut Fr, at: i64) -> i64 {
    if (at == x.i) {
        return x.lx.cur.line;
    }
    if (at == x.i + 1) {
        return x.lx.peek.line;
    }
    return 0;
}

fn p_col(x: &mut Fr, at: i64) -> i64 {
    if (at == x.i) {
        return x.lx.cur.col;
    }
    if (at == x.i + 1) {
        return x.lx.peek.col;
    }
    return 0;
}

fn p_tok_sp(x: &mut Fr, at: i64) -> ptr<u8> {
    if (at == x.i) {
        return x.lx.cur.sp;
    }
    return x.lx.peek.sp;
}

fn p_tok_slen(x: &mut Fr, at: i64) -> i64 {
    if (at == x.i) {
        return x.lx.cur.slen;
    }
    return x.lx.peek.slen;
}

fn p_tok_num(x: &mut Fr, at: i64) -> i64 {
    if (at == x.i) {
        return x.lx.cur.num;
    }
    return x.lx.peek.num;
}

fn p_tok_fp(x: &mut Fr, at: i64) -> f64 {
    if (at == x.i) {
        return x.lx.cur.fp;
    }
    return x.lx.peek.fp;
}

fn p_tok_eq(x: &mut Fr, at: i64, c: ptr<u8>) -> bool {
    var n: i64 = 0;
    var p: ptr<u8> = null;
    if (at == x.i) {
        n = x.lx.cur.slen;
        p = x.lx.cur.sp;
    } else if (at == x.i + 1) {
        n = x.lx.peek.slen;
        p = x.lx.peek.sp;
    } else {
        return false;
    }
    var i: i64 = 0;
    unsafe {
        while (i < n) {
            let d: u8 = c[i];
            if (d == 0 || d != p[i]) {
                return false;
            }
            i += 1;
        }
        if (c[i] != 0) {
            return false;
        }
    }
    return true;
}

fn p_at_sym(x: &mut Fr, c: ptr<u8>) -> bool {
    if (x.lx.cur.kind != TK_SYM) {
        return false;
    }
    return p_tok_eq(x, x.i, c);
}

fn p_ch_at(x: &mut Fr, at: i64, c: u8) -> bool {
    var k: i32 = 0;
    var n: i64 = 0;
    var p: ptr<u8> = null;
    if (at == x.i) {
        k = x.lx.cur.kind;
        n = x.lx.cur.slen;
        p = x.lx.cur.sp;
    } else if (at == x.i + 1) {
        k = x.lx.peek.kind;
        n = x.lx.peek.slen;
        p = x.lx.peek.sp;
    } else {
        return false;
    }
    if (k != TK_SYM || n != 1) {
        return false;
    }
    var b: u8 = 0;
    unsafe { b = p[0]; }
    return b == c;
}

fn p_sym_at(x: &mut Fr, at: i64, c: ptr<u8>) -> bool {
    if (p_kind(x, at) != TK_SYM) {
        return false;
    }
    return p_tok_eq(x, at, c);
}

fn p_at_kw(x: &mut Fr, c: ptr<u8>) -> bool {
    if (x.lx.cur.kind != TK_IDENT) {
        return false;
    }
    return p_tok_eq(x, x.i, c);
}

fn p_bump(x: &mut Fr) {
    if (lex_advance(&mut x.lx) == 0) {
        if (x.ok == 1) {
            sb_clear(&mut x.err);
            let e: ptr<u8> = lex_err(&mut x.lx);
            sb_puts(&mut x.err, e);
            x.ok = 0;
        }
        unsafe {
            x.lx.cur.kind = TK_EOF;
            x.lx.peek.kind = TK_EOF;
        }
    }
    x.i += 1;
}

fn p_eat_sym(x: &mut Fr, c: ptr<u8>) -> bool {
    if (p_at_sym(x, c)) {
        p_bump(x);
        return true;
    }
    return false;
}

fn p_eat_kw(x: &mut Fr, c: ptr<u8>) -> bool {
    if (p_at_kw(x, c)) {
        p_bump(x);
        return true;
    }
    return false;
}

fn p_describe(x: &mut Fr) {
    sb_clear(&mut x.des);
    let at: i64 = x.i;
    let k: i32 = p_kind(x, at);
    if (k == TK_IDENT || k == TK_SYM) {
        let p: ptr<u8> = p_tok_sp(x, at);
        let n: i64 = p_tok_slen(x, at);
        sb_putc(&mut x.des, 39);
        sb_put(&mut x.des, p, n);
        sb_putc(&mut x.des, 39);
    } else if (k == TK_INT) {
        let v: i64 = p_tok_num(x, at);
        sb_puts(&mut x.des, "integer ");
        sb_i64(&mut x.des, v);
    } else if (k == TK_FLOAT) {
        let v: f64 = p_tok_fp(x, at);
        sb_puts(&mut x.des, "float ");
        sb_f64_disp(&mut x.des, v);
    } else if (k == TK_STR) {
        sb_puts(&mut x.des, "a string literal");
    } else {
        sb_puts(&mut x.des, "end of file");
    }
}

fn p_fail_at(x: &mut Fr, line: i64, col: i64) -> i64 {
    sb_clear(&mut x.err);
    sb_puts(&mut x.err, "line ");
    sb_i64(&mut x.err, line);
    sb_putc(&mut x.err, 58);
    sb_i64(&mut x.err, col);
    sb_puts(&mut x.err, ": ");
    let p: ptr<u8> = x.tmp.p;
    let n: i64 = x.tmp.n;
    sb_put(&mut x.err, p, n);
    x.ok = 0;
    return 0;
}

fn p_fail(x: &mut Fr) -> i64 {
    let at: i64 = x.i;
    let line: i64 = p_line(x, at);
    let col: i64 = p_col(x, at);
    return p_fail_at(x, line, col);
}

fn p_msg_begin(x: &mut Fr) {
    sb_clear(&mut x.tmp);
}

fn p_msg_s(x: &mut Fr, c: ptr<u8>) {
    sb_puts(&mut x.tmp, c);
}

fn p_msg_c(x: &mut Fr, c: u8) {
    sb_putc(&mut x.tmp, c);
}

fn p_msg_id(x: &mut Fr, id: i64) {
    let p: ptr<u8> = sp_ptr(&mut x.sp, id);
    let n: i64 = sp_len(&mut x.sp, id);
    sb_put(&mut x.tmp, p, n);
}

fn p_msg_num(x: &mut Fr, v: i64) {
    sb_i64(&mut x.tmp, v);
}

fn p_msg_desc(x: &mut Fr) {
    p_describe(x);
    let p: ptr<u8> = x.des.p;
    let n: i64 = x.des.n;
    sb_put(&mut x.tmp, p, n);
}

fn p_expect_sym(x: &mut Fr, c: ptr<u8>) -> i32 {
    if (p_eat_sym(x, c)) {
        return 1;
    }
    p_msg_begin(x);
    p_msg_s(x, "expected '");
    p_msg_s(x, c);
    p_msg_s(x, "', found ");
    p_msg_desc(x);
    p_fail(x);
    return 0;
}

fn p_expect_kw(x: &mut Fr, c: ptr<u8>) -> i32 {
    if (p_eat_kw(x, c)) {
        return 1;
    }
    p_msg_begin(x);
    p_msg_s(x, "expected '");
    p_msg_s(x, c);
    p_msg_s(x, "', found ");
    p_msg_desc(x);
    p_fail(x);
    return 0;
}

fn p_intern_tok(x: &mut Fr, at: i64) -> i64 {
    let p: ptr<u8> = p_tok_sp(x, at);
    let n: i64 = p_tok_slen(x, at);
    return sp_intern(&mut x.sp, p, n);
}

fn p_take_ident(x: &mut Fr) -> i64 {
    if (x.lx.cur.kind != TK_IDENT) {
        return 0;
    }
    x.tl = x.lx.cur.line;
    x.tc = x.lx.cur.col;
    let tp: ptr<u8> = x.lx.cur.sp;
    let tn: i64 = x.lx.cur.slen;
    let id: i64 = sp_intern(&mut x.sp, tp, tn);
    p_bump(x);
    return id;
}

fn p_reserved(x: &mut Fr, id: i64) -> bool {
    if (sp_eqc(&mut x.sp, id, "fn")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "Fn")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "trait")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "class")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "let")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "var")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "const")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "if")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "else")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "while")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "loop")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "break")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "continue")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "return")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "struct")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "enum")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "for")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "in")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "match")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "extern")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "as")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "sizeof")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "zero")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "ptr")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "true")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "false")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "null")) {
        return true;
    }
    if (p_from_name(x, id) != 0) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "unsafe")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "mut")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "box")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "Box")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "_")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "async")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "await")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "poll")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "mod")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "impl")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, id, "static")) {
        return true;
    }
    return false;
}

fn p_from_name(x: &mut Fr, id: i64) -> i32 {
    if (sp_eqc(&mut x.sp, id, "i8")) {
        return TY_I8;
    }
    if (sp_eqc(&mut x.sp, id, "i16")) {
        return TY_I16;
    }
    if (sp_eqc(&mut x.sp, id, "i32")) {
        return TY_I32;
    }
    if (sp_eqc(&mut x.sp, id, "i64")) {
        return TY_I64;
    }
    if (sp_eqc(&mut x.sp, id, "u8")) {
        return TY_U8;
    }
    if (sp_eqc(&mut x.sp, id, "u16")) {
        return TY_U16;
    }
    if (sp_eqc(&mut x.sp, id, "u32")) {
        return TY_U32;
    }
    if (sp_eqc(&mut x.sp, id, "u64")) {
        return TY_U64;
    }
    if (sp_eqc(&mut x.sp, id, "f32")) {
        return TY_F32;
    }
    if (sp_eqc(&mut x.sp, id, "f64")) {
        return TY_F64;
    }
    if (sp_eqc(&mut x.sp, id, "bool")) {
        return TY_BOOL;
    }
    if (sp_eqc(&mut x.sp, id, "void")) {
        return TY_VOID;
    }
    return 0;
}

fn p_upper(x: &mut Fr, id: i64) -> bool {
    let n: i64 = sp_len(&mut x.sp, id);
    if (n <= 0) {
        return false;
    }
    let p: ptr<u8> = sp_ptr(&mut x.sp, id);
    var c: u8 = 0;
    unsafe { c = p[0]; }
    return c >= 65 && c <= 90;
}

fn p_msg_reserved(x: &mut Fr, id: i64) -> i64 {
    p_msg_begin(x);
    p_msg_c(x, 39);
    p_msg_id(x, id);
    p_msg_s(x, "' is a reserved word");
    return p_fail_at(x, x.tl, x.tc);
}

fn p_name(x: &mut Fr) -> i64 {
    return p_expect_name(x, 0);
}

fn p_type_name(x: &mut Fr) -> i64 {
    return p_expect_name(x, 1);
}

fn p_expect_name(x: &mut Fr, want_upper: i32) -> i64 {
    let id: i64 = p_take_ident(x);
    if (id == 0) {
        p_msg_begin(x);
        p_msg_s(x, "expected a name, found ");
        p_msg_desc(x);
        return p_fail(x);
    }
    if (p_reserved(x, id)) {
        return p_msg_reserved(x, id);
    }
    let up: bool = p_upper(x, id);
    if (want_upper == 1 && !up) {
        p_msg_begin(x);
        p_msg_s(x, "type name '");
        p_msg_id(x, id);
        p_msg_s(x, "' must start with a capital letter");
        return p_fail_at(x, x.tl, x.tc);
    }
    if (want_upper == 0 && up) {
        p_msg_begin(x);
        p_msg_s(x, "value name '");
        p_msg_id(x, id);
        p_msg_s(x, "' must start with a lowercase letter");
        return p_fail_at(x, x.tl, x.tc);
    }
    return id;
}

fn p_type_param_name(x: &mut Fr) -> i64 {
    let id: i64 = p_take_ident(x);
    if (id == 0) {
        p_msg_begin(x);
        p_msg_s(x, "expected a type parameter name, found ");
        p_msg_desc(x);
        return p_fail(x);
    }
    if (p_reserved(x, id)) {
        return p_msg_reserved(x, id);
    }
    return id;
}

fn p_const_name(x: &mut Fr) -> i64 {
    let id: i64 = p_take_ident(x);
    if (id == 0) {
        p_msg_begin(x);
        p_msg_s(x, "expected a name, found ");
        p_msg_desc(x);
        return p_fail(x);
    }
    if (p_reserved(x, id)) {
        return p_msg_reserved(x, id);
    }
    return id;
}

fn p_raw_name(x: &mut Fr) -> i64 {
    let id: i64 = p_take_ident(x);
    if (id == 0) {
        p_msg_begin(x);
        p_msg_s(x, "expected a name, found ");
        p_msg_desc(x);
        return p_fail(x);
    }
    return id;
}

fn p_cat2(x: &mut Fr, a: i64, b: i64) -> i64 {
    sb_clear(&mut x.tmp);
    let p: ptr<u8> = sp_ptr(&mut x.sp, a);
    let n: i64 = sp_len(&mut x.sp, a);
    sb_put(&mut x.tmp, p, n);
    let q: ptr<u8> = sp_ptr(&mut x.sp, b);
    let m: i64 = sp_len(&mut x.sp, b);
    sb_put(&mut x.tmp, q, m);
    let r: ptr<u8> = x.tmp.p;
    let k: i64 = x.tmp.n;
    return sp_intern(&mut x.sp, r, k);
}

fn p_cat3(x: &mut Fr, a: i64, b: i64, c: i64) -> i64 {
    sb_clear(&mut x.tmp);
    let p: ptr<u8> = sp_ptr(&mut x.sp, a);
    let n: i64 = sp_len(&mut x.sp, a);
    sb_put(&mut x.tmp, p, n);
    let q: ptr<u8> = sp_ptr(&mut x.sp, b);
    let m: i64 = sp_len(&mut x.sp, b);
    sb_put(&mut x.tmp, q, m);
    let r: ptr<u8> = sp_ptr(&mut x.sp, c);
    let k: i64 = sp_len(&mut x.sp, c);
    sb_put(&mut x.tmp, r, k);
    let u: ptr<u8> = x.tmp.p;
    let v: i64 = x.tmp.n;
    return sp_intern(&mut x.sp, u, v);
}

fn p_join(x: &mut Fr, segs: i64, sep: ptr<u8>) -> i64 {
    sb_clear(&mut x.tmp);
    let n: i64 = lp_len(&mut x.lp, segs);
    var i: i64 = 0;
    while (i < n) {
        if (i > 0) {
            sb_puts(&mut x.tmp, sep);
        }
        let id: i64 = lp_get(&mut x.lp, segs, i);
        let p: ptr<u8> = sp_ptr(&mut x.sp, id);
        let k: i64 = sp_len(&mut x.sp, id);
        sb_put(&mut x.tmp, p, k);
        i += 1;
    }
    let a: ptr<u8> = x.tmp.p;
    let b: i64 = x.tmp.n;
    return sp_intern(&mut x.sp, a, b);
}

fn p_num_id(x: &mut Fr, v: i64) -> i64 {
    sb_clear(&mut x.tmp);
    sb_i64(&mut x.tmp, v);
    let a: ptr<u8> = x.tmp.p;
    let b: i64 = x.tmp.n;
    return sp_intern(&mut x.sp, a, b);
}

fn p_interns(x: &mut Fr, c: ptr<u8>) -> i64 {
    return sp_interns(&mut x.sp, c);
}

fn p_ty(x: &mut Fr, k: i32) -> i64 {
    return na_add(&mut x.na, k);
}

fn p_parse_fn_type(x: &mut Fr, c_abi: i32) -> i64 {
    p_bump(x);
    p_expect_sym(x, "(");
    if (x.ok == 0) {
        return 0;
    }
    var params: i64 = lp_add(&mut x.lp);
    if (!p_ch_at(x, x.i, 41)) {
        while (true) {
            let t: i64 = p_parse_type(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, params, t);
            if (!p_eat_sym(x, ",")) {
                break;
            }
        }
    }
    p_expect_sym(x, ")");
    if (x.ok == 0) {
        return 0;
    }
    var ret: i64 = 0;
    if (p_eat_sym(x, "->")) {
        ret = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
    } else {
        ret = p_ty(x, TY_VOID);
    }
    var n: i64 = 0;
    if (c_abi == 1) {
        n = p_ty(x, TY_FNC);
    } else {
        n = p_ty(x, TY_FN);
    }
    unsafe {
        na_at(x.na.v, n).l = ( params) as i32;
        na_at(x.na.v, n).a = ( ret) as i32;
    }
    return n;
}

fn p_parse_fn_type_fat(x: &mut Fr) -> i64 {
    p_bump(x);
    p_expect_sym(x, "(");
    if (x.ok == 0) {
        return 0;
    }
    var params: i64 = lp_add(&mut x.lp);
    if (!p_ch_at(x, x.i, 41)) {
        while (true) {
            let t: i64 = p_parse_type(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, params, t);
            if (!p_eat_sym(x, ",")) {
                break;
            }
        }
    }
    p_expect_sym(x, ")");
    if (x.ok == 0) {
        return 0;
    }
    var ret: i64 = 0;
    if (p_eat_sym(x, "->")) {
        ret = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
    } else {
        ret = p_ty(x, TY_VOID);
    }
    return p_fat_type(x, params, ret);
}

fn p_parse_type(x: &mut Fr) -> i64 {
    if (p_eat_sym(x, "(")) {
        var items: i64 = lp_add(&mut x.lp);
        if (!p_ch_at(x, x.i, 41)) {
            while (true) {
                let t: i64 = p_parse_type(x);
                if (x.ok == 0) {
                    return 0;
                }
                lp_push(&mut x.lp, items, t);
                if (!p_eat_sym(x, ",")) {
                    break;
                }
            }
        }
        p_expect_sym(x, ")");
        if (x.ok == 0) {
            return 0;
        }
        if (lp_len(&mut x.lp, items) < 2) {
            p_msg_begin(x);
            p_msg_s(x, "a tuple type needs at least two elements");
            return p_fail(x);
        }
        let n: i64 = p_ty(x, TY_TUPLE);
        unsafe { na_at(x.na.v, n).l = ( items) as i32; }
        return n;
    }
    if (p_eat_kw(x, "extern")) {
        if (!p_at_kw(x, "fn")) {
            p_msg_begin(x);
            p_msg_s(x, "'extern' in a type names an extern function pointer; write 'extern fn(...)'");
            return p_fail(x);
        }
        return p_parse_fn_type(x, 1);
    }
    if (p_at_kw(x, "fn")) {
        return p_parse_fn_type(x, 0);
    }
    if (p_at_kw(x, "Fn")) {
        return p_parse_fn_type_fat(x);
    }
    if (p_eat_kw(x, "dyn")) {
        let first: i64 = p_type_name(x);
        if (x.ok == 0) {
            return 0;
        }
        var segs: i64 = lp_add(&mut x.lp);
        lp_push(&mut x.lp, segs, first);
        while (p_at_sym(x, "::")) {
            p_bump(x);
            let s: i64 = p_type_name(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, segs, s);
        }
        let line: i64 = p_line(x, x.i);
        let col: i64 = p_col(x, x.i);
        let joined: i64 = p_join(x, segs, "__");
        let nm: i64 = p_cat2(x, x.pfx, joined);
        if (!m64_has(&mut x.tdefs, nm)) {
            p_msg_begin(x);
            p_msg_s(x, "unknown trait '");
            p_msg_id(x, nm);
            p_msg_s(x, "'");
            return p_fail_at(x, line, col);
        }
        return p_dyn_type(x, nm);
    }
    if (p_at_kw(x, "Task")) {
        p_bump(x);
        p_expect_sym(x, "<");
        if (x.ok == 0) {
            return 0;
        }
        let inner: i64 = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
        p_expect_sym(x, ">");
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = p_ty(x, TY_TASK);
        unsafe { na_at(x.na.v, n).a = ( inner) as i32; }
        return n;
    }
    if (p_eat_sym(x, "&")) {
        var mu: i32 = 0;
        if (p_eat_kw(x, "mut")) {
            mu = 1;
        }
        let inner: i64 = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = p_ty(x, TY_REF);
        unsafe {
            na_at(x.na.v, n).a = ( inner) as i32;
            na_at(x.na.v, n).m = mu;
        }
        return n;
    }
    if (p_at_kw(x, "Box")) {
        p_bump(x);
        p_expect_sym(x, "<");
        if (x.ok == 0) {
            return 0;
        }
        let inner: i64 = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
        p_expect_sym(x, ">");
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = p_ty(x, TY_HEAP);
        unsafe { na_at(x.na.v, n).a = ( inner) as i32; }
        return n;
    }
    if (p_eat_kw(x, "ptr")) {
        p_expect_sym(x, "<");
        if (x.ok == 0) {
            return 0;
        }
        let inner: i64 = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
        p_expect_sym(x, ">");
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = p_ty(x, TY_PTR);
        unsafe { na_at(x.na.v, n).a = ( inner) as i32; }
        return n;
    }
    if (p_eat_sym(x, "[")) {
        let inner: i64 = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
        p_expect_sym(x, ";");
        if (x.ok == 0) {
            return 0;
        }
        var szl: i64 = 0;
        var szn: i64 = 0;
        var use_name: i32 = 0;
        if (p_kind(x, x.i) == TK_INT) {
            let at: i64 = x.i;
            let v: i64 = p_tok_num(x, at);
            p_bump(x);
            if (v < 0) {
                p_msg_begin(x);
                p_msg_s(x, "array size cannot be negative");
                return p_fail(x);
            }
            szl = v;
        } else if (p_kind(x, x.i) == TK_IDENT) {
            let at: i64 = x.i;
            let line: i64 = p_line(x, at);
            let col: i64 = p_col(x, at);
            let s: i64 = p_take_ident(x);
            if (p_from_name(x, s) != 0) {
                p_msg_begin(x);
                p_msg_s(x, "array size must be an integer literal or a const");
                return p_fail_at(x, line, col);
            }
            szn = p_cat2(x, x.pfx, s);
            use_name = 1;
        } else {
            p_msg_begin(x);
            p_msg_s(x, "expected an array size, found ");
            p_msg_desc(x);
            return p_fail(x);
        }
        p_expect_sym(x, "]");
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = p_ty(x, TY_ARRAY);
        unsafe {
            na_at(x.na.v, n).a = ( inner) as i32;
            na_at(x.na.v, n).n = szl;
            na_at(x.na.v, n).s = ( szn) as i32;
            na_at(x.na.v, n).m = use_name;
        }
        return n;
    }
    let at: i64 = x.i;
    let tline: i64 = p_line(x, at);
    let tcol: i64 = p_col(x, at);
    let first: i64 = p_take_ident(x);
    if (first == 0) {
        p_msg_begin(x);
        p_msg_s(x, "expected a type, found ");
        p_msg_desc(x);
        return p_fail(x);
    }
    if (sp_eqc(&mut x.sp, first, "Self")) {
        return p_ty(x, TY_SELF);
    }
    var segs: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, segs, first);
    while (p_at_sym(x, "::")) {
        p_bump(x);
        let s: i64 = p_raw_name(x);
        if (x.ok == 0) {
            return 0;
        }
        lp_push(&mut x.lp, segs, s);
    }
    if (lp_len(&mut x.lp, segs) == 1) {
        let n: i64 = lp_len(&mut x.lp, x.tparams);
        var i: i64 = 0;
        while (i < n) {
            if (lp_get(&mut x.lp, x.tparams, i) == first) {
                let p: i64 = p_ty(x, TY_PARAM);
                unsafe { na_at(x.na.v, p).s = ( first) as i32; }
                return p;
            }
            i += 1;
        }
        let tk: i32 = p_from_name(x, first);
        if (tk != 0) {
            return p_ty(x, tk);
        }
        if (p_upper(x, first)) {
            let p: i64 = p_ty(x, TY_NAMED);
            unsafe { na_at(x.na.v, p).s = ( p_cat2(x, x.pfx, first)) as i32; }
            return p;
        }
        p_msg_begin(x);
        p_msg_s(x, "unknown type '");
        p_msg_id(x, first);
        p_msg_s(x, "'");
        return p_fail_at(x, tline, tcol);
    }
    let ns: i64 = lp_len(&mut x.lp, segs);
    let last: i64 = lp_get(&mut x.lp, segs, ns - 1);
    if (!p_upper(x, last)) {
        p_msg_begin(x);
        p_msg_c(x, 39);
        p_msg_id(x, last);
        p_msg_s(x, "' is not a type; type names start with a capital letter");
        return p_fail_at(x, tline, tcol);
    }
    let joined: i64 = p_join(x, segs, "__");
    let p: i64 = p_ty(x, TY_NAMED);
    unsafe { na_at(x.na.v, p).s = ( p_cat2(x, x.pfx, joined)) as i32; }
    return p;
}

fn p_list_extend(x: &mut Fr, dst: i64, src: i64) {
    let n: i64 = lp_len(&mut x.lp, src);
    var i: i64 = 0;
    while (i < n) {
        let v: i64 = lp_get(&mut x.lp, src, i);
        lp_push(&mut x.lp, dst, v);
        i += 1;
    }
}

fn p_parse_const(x: &mut Fr) -> i64 {
    let name: i64 = p_cat2(x, x.pfx, p_const_name(x));
    if (x.ok == 0) {
        return 0;
    }
    p_expect_sym(x, ":");
    if (x.ok == 0) {
        return 0;
    }
    let ty: i64 = p_parse_type(x);
    if (x.ok == 0) {
        return 0;
    }
    p_expect_sym(x, "=");
    if (x.ok == 0) {
        return 0;
    }
    let v: i64 = p_parse_expr(x);
    if (x.ok == 0) {
        return 0;
    }
    p_expect_sym(x, ";");
    if (x.ok == 0) {
        return 0;
    }
    let n: i64 = na_add(&mut x.na, IT_CONST);
    unsafe {
        na_at(x.na.v, n).s = ( name) as i32;
        na_at(x.na.v, n).a = ( ty) as i32;
        na_at(x.na.v, n).b = ( v) as i32;
    }
    return n;
}

fn p_parse_static(x: &mut Fr) -> i64 {
    var mu: i32 = 0;
    if (p_eat_kw(x, "mut")) {
        mu = 1;
    }
    let name: i64 = p_cat2(x, x.pfx, p_const_name(x));
    if (x.ok == 0) {
        return 0;
    }
    p_expect_sym(x, ":");
    if (x.ok == 0) {
        return 0;
    }
    let ty: i64 = p_parse_type(x);
    if (x.ok == 0) {
        return 0;
    }
    p_expect_sym(x, "=");
    if (x.ok == 0) {
        return 0;
    }
    let v: i64 = p_parse_expr(x);
    if (x.ok == 0) {
        return 0;
    }
    p_expect_sym(x, ";");
    if (x.ok == 0) {
        return 0;
    }
    let n: i64 = na_add(&mut x.na, IT_STATIC);
    unsafe {
        na_at(x.na.v, n).s = ( name) as i32;
        na_at(x.na.v, n).a = ( ty) as i32;
        na_at(x.na.v, n).b = ( v) as i32;
        na_at(x.na.v, n).m = mu;
    }
    return n;
}

fn p_parse_struct(x: &mut Fr) -> i64 {
    let name: i64 = p_cat2(x, x.pfx, p_type_name(x));
    if (x.ok == 0) {
        return 0;
    }
    p_expect_sym(x, "{");
    if (x.ok == 0) {
        return 0;
    }
    var fields: i64 = lp_add(&mut x.lp);
    while (!p_ch_at(x, x.i, 125)) {
        let fname: i64 = p_name(x);
        if (x.ok == 0) {
            return 0;
        }
        p_expect_sym(x, ":");
        if (x.ok == 0) {
            return 0;
        }
        let fty: i64 = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
        lp_push(&mut x.lp, fields, fname);
        lp_push(&mut x.lp, fields, fty);
        if (!p_eat_sym(x, ",")) {
            break;
        }
    }
    p_expect_sym(x, "}");
    if (x.ok == 0) {
        return 0;
    }
    if (lp_len(&mut x.lp, fields) == 0) {
        p_msg_begin(x);
        p_msg_s(x, "struct '");
        p_msg_id(x, name);
        p_msg_s(x, "' needs at least one field");
        return p_fail_plain(x);
    }
    let n: i64 = na_add(&mut x.na, IT_STRUCT);
    unsafe {
        na_at(x.na.v, n).s = ( name) as i32;
        na_at(x.na.v, n).l = ( fields) as i32;
    }
    m64_set(&mut x.smap, name, fields);
    return n;
}

fn p_trait_method(x: &mut Fr, tname: i64) -> i64 {
    let mname: i64 = p_name(x);
    if (x.ok == 0) {
        return 0;
    }
    p_expect_sym(x, "(");
    if (x.ok == 0) {
        return 0;
    }
    var params: i64 = lp_add(&mut x.lp);
    var self_kind: i64 = 0 - 1;
    if (!p_ch_at(x, x.i, 41)) {
        while (true) {
            var pname: i64 = 0;
            var pty: i64 = 0;
            if (p_at_sym(x, "&")) {
                p_bump(x);
                var mu: i32 = 0;
                if (p_eat_kw(x, "mut")) {
                    mu = 1;
                }
                pname = p_name(x);
                if (x.ok == 0) {
                    return 0;
                }
                if (!sp_eqc(&mut x.sp, pname, "self")) {
                    p_msg_begin(x);
                    p_msg_s(x, "only 'self' can be written without a type");
                    return p_fail_at(x, p_line(x, x.i), p_col(x, x.i));
                }
                let st: i64 = p_ty(x, TY_SELF);
                pty = p_ty(x, TY_REF);
                unsafe {
                    na_at(x.na.v, pty).a = ( st) as i32;
                    na_at(x.na.v, pty).m = mu;
                }
            } else {
                pname = p_name(x);
                if (x.ok == 0) {
                    return 0;
                }
                p_expect_sym(x, ":");
                if (x.ok == 0) {
                    return 0;
                }
                pty = p_parse_type(x);
                if (x.ok == 0) {
                    return 0;
                }
            }
            if (sp_eqc(&mut x.sp, pname, "self")) {
                if (lp_len(&mut x.lp, params) > 0) {
                    p_msg_begin(x);
                    p_msg_s(x, "'self' must be the first parameter");
                    return p_fail_plain(x);
                }
                var pk: i32 = 0;
                unsafe { pk = na_at(x.na.v, pty).k; }
                var ok_self: i32 = 0;
                if (pk == TY_REF) {
                    var inner: i64 = 0;
                    var mu2: i32 = 0;
                    unsafe {
                        inner = (na_at(x.na.v, pty).a as i64);
                        mu2 = na_at(x.na.v, pty).m;
                    }
                    var ik: i32 = 0;
                    unsafe { ik = na_at(x.na.v, inner).k; }
                    if (ik == TY_SELF) {
                        ok_self = 1;
                        self_kind = mu2 as i64;
                    }
                }
                if (ok_self == 0) {
                    p_msg_begin(x);
                    p_msg_s(x, "trait ");
                    p_msg_id(x, tname);
                    p_msg_s(x, ": 'self' must be &Self or &mut Self");
                    return p_fail_plain(x);
                }
            }
            lp_push(&mut x.lp, params, pname);
            lp_push(&mut x.lp, params, pty);
            if (!p_eat_sym(x, ",")) {
                break;
            }
        }
    }
    p_expect_sym(x, ")");
    if (x.ok == 0) {
        return 0;
    }
    var ret: i64 = 0;
    if (p_eat_sym(x, "->")) {
        ret = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
    } else {
        ret = p_ty(x, TY_VOID);
    }
    if (p_expect_sym(x, ";") == 0) {
        return 0;
    }
    if (self_kind < 0) {
        p_msg_begin(x);
        p_msg_s(x, "trait ");
        p_msg_id(x, tname);
        p_msg_s(x, ": method '");
        p_msg_id(x, mname);
        p_msg_s(x, "' needs a self parameter");
        return p_fail_plain(x);
    }
    let m: i64 = na_add(&mut x.na, IT_TM);
    unsafe {
        na_at(x.na.v, m).s = ( mname) as i32;
        na_at(x.na.v, m).l = ( params) as i32;
        na_at(x.na.v, m).a = ( ret) as i32;
        na_at(x.na.v, m).m = self_kind as i32;
    }
    return m;
}

fn p_parse_trait(x: &mut Fr) -> i64 {
    let name: i64 = p_cat2(x, x.pfx, p_type_name(x));
    if (x.ok == 0) {
        return 0;
    }
    if (p_expect_sym(x, "{") == 0) {
        return 0;
    }
    var methods: i64 = lp_add(&mut x.lp);
    while (!p_ch_at(x, x.i, 125)) {
        if (p_kind(x, x.i) == TK_EOF) {
            p_msg_begin(x);
            p_msg_s(x, "unexpected end of file inside a 'trait' block");
            p_fail(x);
            return 0;
        }
        if (p_expect_kw(x, "fn") == 0) {
            return 0;
        }
        let m: i64 = p_trait_method(x, name);
        if (x.ok == 0) {
            return 0;
        }
        var mname: i64 = 0;
        unsafe { mname = (na_at(x.na.v, m).s as i64); }
        let nm: i64 = lp_len(&mut x.lp, methods);
        var i: i64 = 0;
        while (i < nm) {
            let old: i64 = lp_get(&mut x.lp, methods, i);
            var onm: i64 = 0;
            unsafe { onm = (na_at(x.na.v, old).s as i64); }
            if (onm == mname) {
                p_msg_begin(x);
                p_msg_s(x, "trait ");
                p_msg_id(x, name);
                p_msg_s(x, ": duplicate method '");
                p_msg_id(x, mname);
                p_msg_s(x, "'");
                p_fail_plain(x);
                return 0;
            }
            i += 1;
        }
        lp_push(&mut x.lp, methods, m);
    }
    if (p_expect_sym(x, "}") == 0) {
        return 0;
    }
    if (lp_len(&mut x.lp, methods) == 0) {
        p_msg_begin(x);
        p_msg_s(x, "trait '");
        p_msg_id(x, name);
        p_msg_s(x, "' needs at least one method");
        return p_fail_plain(x);
    }
    let it: i64 = na_add(&mut x.na, IT_TRAIT);
    unsafe {
        na_at(x.na.v, it).s = ( name) as i32;
        na_at(x.na.v, it).l = ( methods) as i32;
    }
    m64_set(&mut x.tdefs, name, it);
    lp_push(&mut x.lp, x.trl, it);
    return it;
}

fn p_variant_has(x: &mut Fr, variants: i64, vname: i64) -> bool {
    let n: i64 = lp_len(&mut x.lp, variants);
    var i: i64 = 0;
    while (i < n) {
        if (lp_get(&mut x.lp, variants, i) == vname) {
            return true;
        }
        i += 2;
    }
    return false;
}

fn p_parse_enum(x: &mut Fr) -> i64 {
    let name: i64 = p_cat2(x, x.pfx, p_type_name(x));
    if (x.ok == 0) {
        return 0;
    }
    p_expect_sym(x, "{");
    if (x.ok == 0) {
        return 0;
    }
    var variants: i64 = lp_add(&mut x.lp);
    while (!p_ch_at(x, x.i, 125)) {
        let vname: i64 = p_type_name(x);
        if (x.ok == 0) {
            return 0;
        }
        var payload: i64 = lp_add(&mut x.lp);
        if (p_eat_sym(x, "(")) {
            if (!p_ch_at(x, x.i, 41)) {
                while (true) {
                    let t: i64 = p_parse_type(x);
                    if (x.ok == 0) {
                        return 0;
                    }
                    var tk: i32 = zero(i32);
                    unsafe { tk = na_at(x.na.v, t).k; }
                    if (tk == TY_VOID) {
                        p_msg_begin(x);
                        p_msg_s(x, "variant '");
                        p_msg_id(x, name);
                        p_msg_s(x, "::");
                        p_msg_id(x, vname);
                        p_msg_s(x, "' cannot carry void");
                        return p_fail_plain(x);
                    }
                    lp_push(&mut x.lp, payload, t);
                    if (!p_eat_sym(x, ",")) {
                        break;
                    }
                }
            }
            p_expect_sym(x, ")");
            if (x.ok == 0) {
                return 0;
            }
        }
        if (p_variant_has(x, variants, vname)) {
            p_msg_begin(x);
            p_msg_s(x, "duplicate variant '");
            p_msg_id(x, vname);
            p_msg_s(x, "' in enum '");
            p_msg_id(x, name);
            p_msg_s(x, "'");
            return p_fail_plain(x);
        }
        lp_push(&mut x.lp, variants, vname);
        lp_push(&mut x.lp, variants, payload);
        if (!p_eat_sym(x, ",")) {
            break;
        }
    }
    p_expect_sym(x, "}");
    if (x.ok == 0) {
        return 0;
    }
    if (lp_len(&mut x.lp, variants) == 0) {
        p_msg_begin(x);
        p_msg_s(x, "enum '");
        p_msg_id(x, name);
        p_msg_s(x, "' needs at least one variant");
        return p_fail_plain(x);
    }
    let n: i64 = na_add(&mut x.na, IT_ENUM);
    unsafe {
        na_at(x.na.v, n).s = ( name) as i32;
        na_at(x.na.v, n).l = ( variants) as i32;
    }
    return n;
}

fn p_parse_extern_one(x: &mut Fr, lib: i64) -> i64 {
    p_expect_kw(x, "fn");
    if (x.ok == 0) {
        return 0;
    }
    let name: i64 = p_raw_name(x);
    if (x.ok == 0) {
        return 0;
    }
    p_expect_sym(x, "(");
    if (x.ok == 0) {
        return 0;
    }
    var params: i64 = lp_add(&mut x.lp);
    var variadic: i32 = 0;
    if (!p_ch_at(x, x.i, 41)) {
        while (true) {
            if (p_eat_sym(x, "...")) {
                variadic = 1;
                break;
            }
            let pn: i64 = p_name(x);
            if (x.ok == 0) {
                return 0;
            }
            p_expect_sym(x, ":");
            if (x.ok == 0) {
                return 0;
            }
            let t: i64 = p_parse_type(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, params, t);
            if (!p_eat_sym(x, ",")) {
                break;
            }
        }
    }
    p_expect_sym(x, ")");
    if (x.ok == 0) {
        return 0;
    }
    var ret: i64 = 0;
    if (p_eat_sym(x, "->")) {
        ret = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
    } else {
        ret = p_ty(x, TY_VOID);
    }
    p_expect_sym(x, ";");
    if (x.ok == 0) {
        return 0;
    }
    let n: i64 = na_add(&mut x.na, IT_EXTERN);
    unsafe {
        na_at(x.na.v, n).s = ( name) as i32;
        na_at(x.na.v, n).s2 = ( lib) as i32;
        na_at(x.na.v, n).l = ( params) as i32;
        na_at(x.na.v, n).a = ( ret) as i32;
        na_at(x.na.v, n).m = variadic;
    }
    return n;
}

fn p_parse_extern(x: &mut Fr, out: i64) -> i32 {
    var lib: i64 = 0;
    let at: i64 = x.i;
    if (p_kind(x, at) == TK_STR) {
        let p: ptr<u8> = p_tok_sp(x, at);
        let n: i64 = p_tok_slen(x, at);
        var good: i32 = 1;
        if (n == 0) {
            good = 0;
        }
        var i: i64 = 0;
        while (i < n) {
            var c: u8 = 0;
            unsafe { c = p[i]; }
            let al: i32 = ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 || c == 46 || c == 47 || c == 92 || c == 45 || c == 58) as i32;
            if (al == 0) {
                good = 0;
                break;
            }
            i += 1;
        }
        if (good == 0) {
            p_msg_begin(x);
            p_msg_s(x, "a library tag is letters, digits, '_', '.', '/' or '-' - e.g. \"winhttp\" or \"python312.dll\"");
            p_fail(x);
            return 0;
        }
        lib = sp_intern(&mut x.sp, p, n);
        p_bump(x);
    }
    if (p_ch_at(x, x.i, 123)) {
        p_bump(x);
        while (!p_ch_at(x, x.i, 125)) {
            if (p_kind(x, x.i) == TK_EOF) {
                p_msg_begin(x);
                p_msg_s(x, "unexpected end of file inside an 'extern' block");
                p_fail(x);
                return 0;
            }
            let f: i64 = p_parse_extern_one(x, lib);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, out, f);
        }
        p_expect_sym(x, "}");
        if (x.ok == 0) {
            return 0;
        }
        return 1;
    }
    let f: i64 = p_parse_extern_one(x, lib);
    if (x.ok == 0) {
        return 0;
    }
    lp_push(&mut x.lp, out, f);
    return 1;
}

fn p_in_list(x: &mut Fr, l: i64, v: i64) -> bool {
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 0;
    while (i < n) {
        if (lp_get(&mut x.lp, l, i) == v) {
            return true;
        }
        i += 1;
    }
    return false;
}

fn p_parse_fn(x: &mut Fr, is_async: i32) -> i64 {
    let name: i64 = p_cat2(x, x.pfx, p_name(x));
    if (x.ok == 0) {
        return 0;
    }
    var tparams: i64 = lp_add(&mut x.lp);
    if (p_eat_sym(x, "<")) {
        while (true) {
            let t: i64 = p_type_param_name(x);
            if (x.ok == 0) {
                return 0;
            }
            if (p_in_list(x, tparams, t)) {
                p_msg_begin(x);
                p_msg_s(x, "duplicate type parameter '");
                p_msg_id(x, t);
                p_msg_s(x, "' in fn '");
                p_msg_id(x, name);
                p_msg_s(x, "'");
                return p_fail_plain(x);
            }
            lp_push(&mut x.lp, tparams, t);
            if (!p_eat_sym(x, ",")) {
                break;
            }
        }
        p_expect_sym(x, ">");
        if (x.ok == 0) {
            return 0;
        }
    }
    let outer: i64 = x.tparams;
    x.tparams = tparams;
    p_expect_sym(x, "(");
    if (x.ok == 0) {
        return 0;
    }
    var params: i64 = lp_add(&mut x.lp);
    if (!p_ch_at(x, x.i, 41)) {
        while (true) {
            var pname: i64 = 0;
            var pty: i64 = 0;
            if (p_at_sym(x, "&")) {
                p_bump(x);
                var mu: i32 = 0;
                if (p_eat_kw(x, "mut")) {
                    mu = 1;
                }
                pname = p_name(x);
                if (x.ok == 0) {
                    return 0;
                }
                if (!sp_eqc(&mut x.sp, pname, "self")) {
                    p_msg_begin(x);
                    p_msg_s(x, "only 'self' can be written without a type");
                    return p_fail_at(x, p_line(x, x.i), p_col(x, x.i));
                }
                let st: i64 = p_ty(x, TY_SELF);
                pty = p_ty(x, TY_REF);
                unsafe {
                    na_at(x.na.v, pty).a = ( st) as i32;
                    na_at(x.na.v, pty).m = mu;
                }
            } else {
                pname = p_name(x);
                if (x.ok == 0) {
                    return 0;
                }
                p_expect_sym(x, ":");
                if (x.ok == 0) {
                    return 0;
                }
                pty = p_parse_type(x);
                if (x.ok == 0) {
                    return 0;
                }
            }
            pty = p_subst_self(x, pty);
            let np: i64 = lp_len(&mut x.lp, params);
            var i: i64 = 0;
            while (i < np) {
                if (lp_get(&mut x.lp, params, i) == pname) {
                    p_msg_begin(x);
                    p_msg_s(x, "duplicate parameter '");
                    p_msg_id(x, pname);
                    p_msg_s(x, "' in fn '");
                    p_msg_id(x, name);
                    p_msg_s(x, "'");
                    return p_fail_plain(x);
                }
                i += 2;
            }
            lp_push(&mut x.lp, params, pname);
            lp_push(&mut x.lp, params, pty);
            if (!p_eat_sym(x, ",")) {
                break;
            }
        }
    }
    p_expect_sym(x, ")");
    if (x.ok == 0) {
        return 0;
    }
    var ret: i64 = 0;
    if (p_eat_sym(x, "->")) {
        ret = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
    } else {
        ret = p_ty(x, TY_VOID);
    }
    ret = p_subst_self(x, ret);
    p_push_scope(x);
    let np2: i64 = lp_len(&mut x.lp, params);
    var pi: i64 = 0;
    while (pi < np2) {
        let bn: i64 = lp_get(&mut x.lp, params, pi);
        let bt: i64 = lp_get(&mut x.lp, params, pi + 1);
        p_bind(x, bn, bt);
        pi += 2;
    }
    p_push_ret(x, ret);
    let body: i64 = p_parse_body(x);
    p_pop_ret(x);
    p_pop_scope(x);
    if (x.ok == 0) {
        return 0;
    }
    x.tparams = outer;
    m64_set(&mut x.fmap, name, params);
    m64_set(&mut x.frmap, name, ret);
    let n: i64 = na_add(&mut x.na, IT_FN);
    unsafe {
        na_at(x.na.v, n).s = ( name) as i32;
        na_at(x.na.v, n).l = ( tparams) as i32;
        na_at(x.na.v, n).l2 = ( params) as i32;
        na_at(x.na.v, n).a = ( ret) as i32;
        na_at(x.na.v, n).n = is_async as i64;
        na_at(x.na.v, n).l3 = ( body) as i32;
    }
    return n;
}

fn p_var(x: &mut Fr, s: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_VAR);
    unsafe { na_at(x.na.v, n).s = ( s) as i32; }
    return n;
}

fn p_int(x: &mut Fr, v: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_INT);
    unsafe { na_at(x.na.v, n).n = v; }
    return n;
}

fn p_field(x: &mut Fr, base: i64, s: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_FIELD);
    unsafe {
        na_at(x.na.v, n).a = ( base) as i32;
        na_at(x.na.v, n).s = ( s) as i32;
    }
    return n;
}

fn p_bin(x: &mut Fr, op: i64, a: i64, b: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_BIN);
    unsafe {
        na_at(x.na.v, n).s = ( op) as i32;
        na_at(x.na.v, n).a = ( a) as i32;
        na_at(x.na.v, n).b = ( b) as i32;
    }
    return n;
}

fn p_parse_block(x: &mut Fr) -> i64 {
    p_expect_sym(x, "{");
    if (x.ok == 0) {
        return 0;
    }
    p_push_scope(x);
    var body: i64 = lp_add(&mut x.lp);
    while (!p_ch_at(x, x.i, 125)) {
        if (p_kind(x, x.i) == TK_EOF) {
            p_pop_scope(x);
            p_msg_begin(x);
            p_msg_s(x, "unexpected end of file inside a block");
            p_fail(x);
            return 0;
        }
        let more: i64 = p_parse_stmts(x);
        if (x.ok == 0) {
            return 0;
        }
        p_list_extend(x, body, more);
    }
    p_expect_sym(x, "}");
    if (x.ok == 0) {
        return 0;
    }
    p_pop_scope(x);
    return body;
}

fn p_parse_run(x: &mut Fr) -> i64 {
    p_push_scope(x);
    var body: i64 = lp_add(&mut x.lp);
    while (!p_at_kw(x, "end") && !p_at_kw(x, "else")) {
        if (p_kind(x, x.i) == TK_EOF) {
            p_pop_scope(x);
            p_msg_begin(x);
            p_msg_s(x, "unexpected end of file; a block opened without '{' is closed by 'end;'");
            p_fail(x);
            return 0;
        }
        let more: i64 = p_parse_stmts(x);
        if (x.ok == 0) {
            return 0;
        }
        p_list_extend(x, body, more);
    }
    p_pop_scope(x);
    return body;
}

fn p_parse_end(x: &mut Fr) -> i32 {
    if (p_expect_kw(x, "end") == 0) {
        return 0;
    }
    return p_expect_sym(x, ";");
}

fn p_parse_body(x: &mut Fr) -> i64 {
    if (p_ch_at(x, x.i, 123)) {
        return p_parse_block(x);
    }
    let body: i64 = p_parse_run(x);
    if (x.ok == 0) {
        return 0;
    }
    if (p_parse_end(x) == 0) {
        return 0;
    }
    return body;
}

fn p_stmt_list1(x: &mut Fr, st: i64) -> i64 {
    var l: i64 = lp_add(&mut x.lp);
    if (st != 0) {
        lp_push(&mut x.lp, l, st);
    }
    return l;
}

fn p_parse_if_open(x: &mut Fr, cond: i64) -> i64 {
    var conds: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, conds, cond);
    var arms: i64 = lp_add(&mut x.lp);
    let a0: i64 = p_parse_run(x);
    if (x.ok == 0) {
        return 0;
    }
    lp_push(&mut x.lp, arms, a0);
    while (p_at_kw(x, "else")) {
        p_bump(x);
        var more: i32 = 0;
        if (p_at_kw(x, "if")) {
            p_bump(x);
            p_expect_sym(x, "(");
            if (x.ok == 0) {
                return 0;
            }
            let c: i64 = p_parse_expr(x);
            if (x.ok == 0) {
                return 0;
            }
            p_expect_sym(x, ")");
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, conds, c);
            more = 1;
        }
        if (p_ch_at(x, x.i, 123)) {
            let b: i64 = p_parse_block(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, arms, b);
        } else {
            let b: i64 = p_parse_run(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, arms, b);
        }
        if (more == 0) {
            break;
        }
    }
    if (p_parse_end(x) == 0) {
        return 0;
    }
    let nc: i64 = lp_len(&mut x.lp, conds);
    let na: i64 = lp_len(&mut x.lp, arms);
    var els: i64 = 0;
    if (na > nc) {
        els = lp_get(&mut x.lp, arms, nc);
    } else {
        els = lp_add(&mut x.lp);
    }
    var k: i64 = nc;
    while (k > 0) {
        k -= 1;
        let c: i64 = lp_get(&mut x.lp, conds, k);
        let b: i64 = lp_get(&mut x.lp, arms, k);
        let n: i64 = na_add(&mut x.na, ST_IF);
        unsafe {
            na_at(x.na.v, n).a = ( c) as i32;
            na_at(x.na.v, n).l = ( b) as i32;
            na_at(x.na.v, n).l2 = ( els) as i32;
        }
        els = lp_add(&mut x.lp);
        lp_push(&mut x.lp, els, n);
    }
    if (lp_len(&mut x.lp, els) == 0) {
        let n: i64 = na_add(&mut x.na, ST_BLOCK);
        let e: i64 = lp_add(&mut x.lp);
        unsafe { na_at(x.na.v, n).l = ( e) as i32; }
        return n;
    }
    return lp_get(&mut x.lp, els, 0);
}

fn p_parse_stmts(x: &mut Fr) -> i64 {
    if (p_eat_kw(x, "let")) {
        return p_parse_binding(x, 0);
    }
    if (p_eat_kw(x, "var")) {
        return p_parse_binding(x, 1);
    }
    if (p_ch_at(x, x.i, 39)) {
        p_bump(x);
        let label: i64 = p_name(x);
        if (x.ok == 0) {
            return 0;
        }
        p_expect_sym(x, ":");
        if (x.ok == 0) {
            return 0;
        }
        let inner: i64 = p_parse_stmt1(x);
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, ST_LABEL);
        unsafe {
            na_at(x.na.v, n).s = ( label) as i32;
            na_at(x.na.v, n).a = ( inner) as i32;
        }
        return p_stmt_list1(x, n);
    }
    let st: i64 = p_parse_stmt1(x);
    if (x.ok == 0) {
        return 0;
    }
    return p_stmt_list1(x, st);
}

fn p_parse_stmt1(x: &mut Fr) -> i64 {
    if (p_at_kw(x, "end")) {
        p_msg_begin(x);
        p_msg_s(x, "'end;' closes a block that opened without '{', and this one opened with '{'");
        return p_fail(x);
    }
    if (p_eat_kw(x, "unsafe")) {
        let b: i64 = p_parse_body(x);
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, ST_UNSAFE);
        unsafe { na_at(x.na.v, n).l = ( b) as i32; }
        return n;
    }
    if (p_eat_kw(x, "if")) {
        p_expect_sym(x, "(");
        if (x.ok == 0) {
            return 0;
        }
        let cond: i64 = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
        }
        p_expect_sym(x, ")");
        if (x.ok == 0) {
            return 0;
        }
        if (!p_ch_at(x, x.i, 123)) {
            return p_parse_if_open(x, cond);
        }
        let then: i64 = p_parse_block(x);
        if (x.ok == 0) {
            return 0;
        }
        var els: i64 = 0;
        if (p_eat_kw(x, "else")) {
            if (p_at_kw(x, "if")) {
                els = p_parse_stmts(x);
                if (x.ok == 0) {
                    return 0;
                }
            } else {
                els = p_parse_body(x);
                if (x.ok == 0) {
                    return 0;
                }
            }
        } else {
            els = lp_add(&mut x.lp);
        }
        let n: i64 = na_add(&mut x.na, ST_IF);
        unsafe {
            na_at(x.na.v, n).a = ( cond) as i32;
            na_at(x.na.v, n).l = ( then) as i32;
            na_at(x.na.v, n).l2 = ( els) as i32;
        }
        return n;
    }
    if (p_eat_kw(x, "while")) {
        p_expect_sym(x, "(");
        if (x.ok == 0) {
            return 0;
        }
        let cond: i64 = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
        }
        p_expect_sym(x, ")");
        if (x.ok == 0) {
            return 0;
        }
        let body: i64 = p_parse_body(x);
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, ST_WHILE);
        unsafe {
            na_at(x.na.v, n).a = ( cond) as i32;
            na_at(x.na.v, n).l = ( body) as i32;
        }
        return n;
    }
    if (p_eat_kw(x, "loop")) {
        let body: i64 = p_parse_body(x);
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, ST_LOOP);
        unsafe { na_at(x.na.v, n).l = ( body) as i32; }
        return n;
    }
    if (p_eat_kw(x, "for")) {
        let vname: i64 = p_name(x);
        if (x.ok == 0) {
            return 0;
        }
        if (p_expect_kw(x, "in") == 0) {
            return 0;
        }
        let start: i64 = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
        }
        var hi: i64 = p_parse_expr_after_range(x);
        if (x.ok == 0) {
            return 0;
        }
        if (x.incl == 1) {
            let one: i64 = p_int(x, 1);
            let plus: i64 = p_interns(x, "+");
            hi = p_bin(x, plus, hi, one);
        }
        let body: i64 = p_parse_body(x);
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, ST_FOR);
        unsafe {
            na_at(x.na.v, n).s = ( vname) as i32;
            na_at(x.na.v, n).a = ( start) as i32;
            na_at(x.na.v, n).b = ( hi) as i32;
            na_at(x.na.v, n).l = ( body) as i32;
        }
        return n;
    }
    if (p_eat_kw(x, "match")) {
        let scrut: i64 = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
        }
        p_expect_sym(x, "{");
        if (x.ok == 0) {
            return 0;
        }
        var arms: i64 = lp_add(&mut x.lp);
        while (!p_ch_at(x, x.i, 125)) {
            let pat: i64 = p_parse_pat(x);
            if (x.ok == 0) {
                return 0;
            }
            p_expect_sym(x, "=>");
            if (x.ok == 0) {
                return 0;
            }
            let body: i64 = p_parse_block(x);
            if (x.ok == 0) {
                return 0;
            }
            let arm: i64 = na_add(&mut x.na, AR_ARM);
            unsafe {
                na_at(x.na.v, arm).a = ( pat) as i32;
                na_at(x.na.v, arm).l = ( body) as i32;
            }
            lp_push(&mut x.lp, arms, arm);
            p_eat_sym(x, ",");
        }
        p_expect_sym(x, "}");
        if (x.ok == 0) {
            return 0;
        }
        if (lp_len(&mut x.lp, arms) == 0) {
            p_msg_begin(x);
            p_msg_s(x, "a 'match' needs at least one arm");
            return p_fail(x);
        }
        let n: i64 = na_add(&mut x.na, ST_MATCH);
        unsafe {
            na_at(x.na.v, n).a = ( scrut) as i32;
            na_at(x.na.v, n).l = ( arms) as i32;
        }
        return n;
    }
    if (p_eat_kw(x, "break")) {
        let label: i64 = p_eat_label(x);
        if (x.ok == 0) {
            return 0;
        }
        if (p_expect_sym(x, ";") == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, ST_BREAK);
        unsafe { na_at(x.na.v, n).s = ( label) as i32; }
        return n;
    }
    if (p_eat_kw(x, "continue")) {
        let label: i64 = p_eat_label(x);
        if (x.ok == 0) {
            return 0;
        }
        if (p_expect_sym(x, ";") == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, ST_CONTINUE);
        unsafe { na_at(x.na.v, n).s = ( label) as i32; }
        return n;
    }
    if (p_eat_kw(x, "return")) {
        if (p_ch_at(x, x.i, 59)) {
            p_bump(x);
            let n: i64 = na_add(&mut x.na, ST_RETURN);
            return n;
        }
        var e: i64 = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
        }
        if (p_expect_sym(x, ";") == 0) {
            return 0;
        }
        let nr: i64 = lp_len(&mut x.lp, x.rtyp);
        if (nr > 0) {
            let want: i64 = lp_get(&mut x.lp, x.rtyp, nr - 1);
            e = p_coerce_expr(x, e, want);
            if (x.ok == 0) {
                return 0;
            }
        }
        let n: i64 = na_add(&mut x.na, ST_RETURN);
        unsafe { na_at(x.na.v, n).a = ( e) as i32; }
        return n;
    }
    if (p_ch_at(x, x.i, 123)) {
        let b: i64 = p_parse_block(x);
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, ST_BLOCK);
        unsafe { na_at(x.na.v, n).l = ( b) as i32; }
        return n;
    }
    let lhs: i64 = p_parse_expr(x);
    if (x.ok == 0) {
        return 0;
    }
    var ops: [ptr<u8>; 11] = ["=", "+=", "-=", "*=", "/=", "%=", "<<=", ">>=", "&=", "|=", "^="];
    var i: i64 = 0;
    while (i < 11) {
        let op: ptr<u8> = ops[i];
        if (p_eat_sym(x, op)) {
            let rhs: i64 = p_parse_expr(x);
            if (x.ok == 0) {
                return 0;
            }
            if (p_expect_sym(x, ";") == 0) {
                return 0;
            }
            let n: i64 = na_add(&mut x.na, ST_ASSIGN);
            let opid: i64 = p_interns(x, op);
            unsafe {
                na_at(x.na.v, n).s = ( opid) as i32;
                na_at(x.na.v, n).a = ( lhs) as i32;
                na_at(x.na.v, n).b = ( rhs) as i32;
            }
            return n;
        }
        i += 1;
    }
    if (p_expect_sym(x, ";") == 0) {
        return 0;
    }
    let n: i64 = na_add(&mut x.na, ST_EXPR);
    unsafe { na_at(x.na.v, n).a = ( lhs) as i32; }
    return n;
}

fn p_eat_label(x: &mut Fr) -> i64 {
    if (p_ch_at(x, x.i, 39)) {
        p_bump(x);
        return p_name(x);
    }
    return 0;
}

fn p_parse_expr_after_range(x: &mut Fr) -> i64 {
    x.incl = 0;
    if (p_eat_sym(x, "..=")) {
        x.incl = 1;
    } else {
        if (p_expect_sym(x, "..") == 0) {
            return 0;
        }
    }
    return p_parse_expr(x);
}

fn p_parse_pat(x: &mut Fr) -> i64 {
    if (p_eat_kw(x, "_")) {
        return na_add(&mut x.na, PT_WILD);
    }
    var neg: i32 = 0;
    if (p_eat_sym(x, "-")) {
        neg = 1;
    }
    if (p_kind(x, x.i) == TK_INT) {
        let at: i64 = x.i;
        let v: i64 = p_tok_num(x, at);
        p_bump(x);
        var lo: i64 = v;
        if (neg == 1) {
            lo = 0 - v;
        }
        if (p_eat_sym(x, "..=")) {
            if (p_kind(x, x.i) != TK_INT) {
                p_msg_begin(x);
                p_msg_s(x, "a range pattern needs an integer on both sides");
                return p_fail(x);
            }
            let at2: i64 = x.i;
            let hi: i64 = p_tok_num(x, at2);
            p_bump(x);
            if (hi < lo) {
                p_msg_begin(x);
                p_msg_s(x, "range pattern ");
                p_msg_num(x, lo);
                p_msg_s(x, "..=");
                p_msg_num(x, hi);
                p_msg_s(x, " runs backwards");
                return p_fail_plain(x);
            }
            let n: i64 = na_add(&mut x.na, PT_RANGE);
            unsafe {
                na_at(x.na.v, n).n = lo;
                na_at(x.na.v, n).b = ( hi) as i32;
            }
            return n;
        }
        let n: i64 = na_add(&mut x.na, PT_LIT);
        unsafe { na_at(x.na.v, n).n = lo; }
        return n;
    }
    if (neg == 1) {
        p_msg_begin(x);
        p_msg_s(x, "expected a number after '-' in a pattern");
        return p_fail(x);
    }
    var segs: i64 = lp_add(&mut x.lp);
    let s0: i64 = p_type_name(x);
    if (x.ok == 0) {
        return 0;
    }
    lp_push(&mut x.lp, segs, s0);
    while (p_at_sym(x, "::")) {
        p_bump(x);
        let s: i64 = p_type_name(x);
        if (x.ok == 0) {
            return 0;
        }
        lp_push(&mut x.lp, segs, s);
    }
    let ns: i64 = lp_len(&mut x.lp, segs);
    let vn: i64 = lp_get(&mut x.lp, segs, ns - 1);
    let rest: i64 = ns - 1;
    var en: i64 = 0;
    if (rest == 1) {
        let head: i64 = lp_get(&mut x.lp, segs, 0);
        en = p_cat2(x, x.pfx, head);
    } else if (rest == 0) {
        p_msg_begin(x);
        p_msg_s(x, "a variant pattern needs 'Enum::Variant'");
        return p_fail(x);
    } else {
        var head: i64 = lp_add(&mut x.lp);
        var i: i64 = 0;
        while (i < rest) {
            let v: i64 = lp_get(&mut x.lp, segs, i);
            lp_push(&mut x.lp, head, v);
            i += 1;
        }
        let joined: i64 = p_join(x, head, "__");
        en = p_cat2(x, x.pfx, joined);
    }
    var binds: i64 = lp_add(&mut x.lp);
    if (p_eat_sym(x, "(")) {
        if (!p_ch_at(x, x.i, 41)) {
            while (true) {
                let b: i64 = p_name(x);
                if (x.ok == 0) {
                    return 0;
                }
                if (p_in_list(x, binds, b)) {
                    p_msg_begin(x);
                    p_msg_s(x, "pattern binds '");
                    p_msg_id(x, b);
                    p_msg_s(x, "' twice");
                    return p_fail_plain(x);
                }
                lp_push(&mut x.lp, binds, b);
                if (!p_eat_sym(x, ",")) {
                    break;
                }
            }
        }
        p_expect_sym(x, ")");
        if (x.ok == 0) {
            return 0;
        }
    }
    let n: i64 = na_add(&mut x.na, PT_VARIANT);
    unsafe {
        na_at(x.na.v, n).s = ( en) as i32;
        na_at(x.na.v, n).s2 = ( vn) as i32;
        na_at(x.na.v, n).l = ( binds) as i32;
    }
    return n;
}

fn p_tie_to_name(x: &mut Fr, out: i64, hint: i64, rhs: i64) -> i64 {
    var k: i32 = 0;
    unsafe { k = na_at(x.na.v, rhs).k; }
    if (k == EX_VAR || k == EX_FIELD || k == EX_INDEX || k == EX_DEREF) {
        return rhs;
    }
    let num: i64 = x.tmpn;
    x.tmpn = num + 1;
    var b: Sb = sb_new(24);
    sb_puts(&mut b, "__destr");
    sb_i64(&mut b, num);
    let temp: i64 = sp_intern(&mut x.sp, b.p, b.n);
    sb_free(&mut b);
    let st: i64 = na_add(&mut x.na, ST_LET);
    unsafe {
        na_at(x.na.v, st).m = 0;
        na_at(x.na.v, st).s = ( temp) as i32;
        na_at(x.na.v, st).a = ( hint) as i32;
        na_at(x.na.v, st).b = ( rhs) as i32;
    }
    lp_push(&mut x.lp, out, st);
    return p_var(x, temp);
}

fn p_parse_binding(x: &mut Fr, mutable: i32) -> i64 {
    if (p_at_kw(x, "_")) {
        p_bump(x);
        if (p_eat_sym(x, "=")) {
            let e: i64 = p_parse_expr(x);
            if (x.ok == 0) {
                return 0;
            }
            if (p_expect_sym(x, ";") == 0) {
                return 0;
            }
            let st: i64 = na_add(&mut x.na, ST_EXPR);
            unsafe { na_at(x.na.v, st).a = ( e) as i32; }
            return p_stmt_list1(x, st);
        }
        if (p_expect_sym(x, ";") == 0) {
            return 0;
        }
        return lp_add(&mut x.lp);
    }
    let at: i64 = x.i;
    var upper: bool = false;
    if (p_kind(x, at) == TK_IDENT) {
        let p: ptr<u8> = p_tok_sp(x, at);
        var c: u8 = 0;
        unsafe { c = p[0]; }
        upper = c >= 65 && c <= 90;
    }
    if (upper && p_ch_at(x, at + 1, 123)) {
        let ty: i64 = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
        p_expect_sym(x, "{");
        if (x.ok == 0) {
            return 0;
        }
        var binds: i64 = lp_add(&mut x.lp);
        while (!p_ch_at(x, x.i, 125)) {
            let f: i64 = p_name(x);
            if (x.ok == 0) {
                return 0;
            }
            var b: i64 = f;
            if (p_eat_sym(x, ":")) {
                b = p_name(x);
                if (x.ok == 0) {
                    return 0;
                }
            }
            lp_push(&mut x.lp, binds, f);
            lp_push(&mut x.lp, binds, b);
            if (!p_eat_sym(x, ",")) {
                break;
            }
        }
        p_expect_sym(x, "}");
        if (x.ok == 0) {
            return 0;
        }
        p_expect_sym(x, "=");
        if (x.ok == 0) {
            return 0;
        }
        let rhs: i64 = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
        }
        if (p_expect_sym(x, ";") == 0) {
            return 0;
        }
        var out: i64 = lp_add(&mut x.lp);
        let base: i64 = p_tie_to_name(x, out, ty, rhs);
        if (x.ok == 0) {
            return 0;
        }
        let nb: i64 = lp_len(&mut x.lp, binds);
        var i: i64 = 0;
        while (i < nb) {
            let f: i64 = lp_get(&mut x.lp, binds, i);
            let b: i64 = lp_get(&mut x.lp, binds, i + 1);
            var ft: i64 = p_field_type(x, ty, f);
            if (ft == 0) {
                ft = p_ty(x, TY_INFER);
            }
            p_bind(x, b, ft);
            let init: i64 = p_field(x, base, f);
            let st: i64 = na_add(&mut x.na, ST_LET);
            unsafe {
                na_at(x.na.v, st).m = mutable;
                na_at(x.na.v, st).s = ( b) as i32;
                na_at(x.na.v, st).a = ( ft) as i32;
                na_at(x.na.v, st).b = ( init) as i32;
            }
            lp_push(&mut x.lp, out, st);
            i += 2;
        }
        return out;
    }
    if (p_ch_at(x, x.i, 40) && mutable == 0) {
        p_bump(x);
        var slots: i64 = lp_add(&mut x.lp);
        while (true) {
            if (p_at_kw(x, "_")) {
                p_bump(x);
                lp_push(&mut x.lp, slots, 0);
            } else {
                let s: i64 = p_name(x);
                if (x.ok == 0) {
                    return 0;
                }
                lp_push(&mut x.lp, slots, s);
            }
            if (!p_eat_sym(x, ",")) {
                break;
            }
        }
        p_expect_sym(x, ")");
        if (x.ok == 0) {
            return 0;
        }
        var ann: i64 = 0;
        if (p_eat_sym(x, ":")) {
            ann = p_parse_type(x);
            if (x.ok == 0) {
                return 0;
            }
        }
        p_expect_sym(x, "=");
        if (x.ok == 0) {
            return 0;
        }
        let rhs: i64 = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
        }
        if (p_expect_sym(x, ";") == 0) {
            return 0;
        }
        var parts: i64 = 0;
        if (ann != 0) {
            var ak: i32 = 0;
            unsafe { ak = na_at(x.na.v, ann).k; }
            if (ak != TY_TUPLE) {
                p_msg_begin(x);
                p_msg_s(x, "a tuple pattern needs a tuple type");
                return p_fail(x);
            }
            unsafe { parts = (na_at(x.na.v, ann).l as i64); }
            let nparts: i64 = lp_len(&mut x.lp, parts);
            let nslots: i64 = lp_len(&mut x.lp, slots);
            if (nparts != nslots) {
                p_msg_begin(x);
                p_msg_s(x, "the pattern has ");
                p_msg_num(x, nslots);
                p_msg_s(x, " element(s); the tuple type has ");
                p_msg_num(x, nparts);
                return p_fail_plain(x);
            }
        }
        var out: i64 = lp_add(&mut x.lp);
        var hint: i64 = ann;
        if (hint == 0) {
            hint = p_ty(x, TY_INFER);
        }
        let base: i64 = p_tie_to_name(x, out, hint, rhs);
        if (x.ok == 0) {
            return 0;
        }
        let ns: i64 = lp_len(&mut x.lp, slots);
        var i: i64 = 0;
        while (i < ns) {
            let slot: i64 = lp_get(&mut x.lp, slots, i);
            if (slot != 0) {
                var ty: i64 = 0;
                if (i < lp_len(&mut x.lp, parts)) {
                    ty = lp_get(&mut x.lp, parts, i);
                } else {
                    ty = p_ty(x, TY_INFER);
                }
                let idx: i64 = p_num_id(x, i);
                let init: i64 = p_field(x, base, idx);
                p_bind(x, slot, ty);
                let st: i64 = na_add(&mut x.na, ST_LET);
                unsafe {
                    na_at(x.na.v, st).m = 0;
                    na_at(x.na.v, st).s = ( slot) as i32;
                    na_at(x.na.v, st).a = ( ty) as i32;
                    na_at(x.na.v, st).b = ( init) as i32;
                }
                lp_push(&mut x.lp, out, st);
            }
            i += 1;
        }
        return out;
    }
    let tline: i64 = p_line(x, x.i);
    let tcol: i64 = p_col(x, x.i);
    let name: i64 = p_name(x);
    if (x.ok == 0) {
        return 0;
    }
    if (sp_eqc(&mut x.sp, name, "self")) {
        p_msg_begin(x);
        p_msg_s(x, "'self' cannot be rebound");
        return p_fail_at(x, tline, tcol);
    }
    var ty: i64 = 0;
    if (p_eat_sym(x, ":")) {
        ty = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
    } else {
        ty = p_ty(x, TY_INFER);
    }
    var init: i64 = 0;
    if (p_eat_sym(x, "=")) {
        init = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
        }
    }
    if (p_expect_sym(x, ";") == 0) {
        return 0;
    }
    if (init != 0) {
        var tk: i32 = 0;
        unsafe { tk = na_at(x.na.v, ty).k; }
        if (tk == TY_INFER) {
            let h: i64 = p_expr_hint(x, init);
            if (h != 0) {
                var hk: i32 = 0;
                unsafe { hk = na_at(x.na.v, h).k; }
                if (hk == TY_FAT || hk == TY_DYN) {
                    ty = h;
                }
            }
        }
        init = p_coerce_expr(x, init, ty);
        if (x.ok == 0) {
            return 0;
        }
    }
    p_bind(x, name, ty);
    let st: i64 = na_add(&mut x.na, ST_LET);
    unsafe {
        na_at(x.na.v, st).m = mutable;
        na_at(x.na.v, st).s = ( name) as i32;
        na_at(x.na.v, st).a = ( ty) as i32;
        na_at(x.na.v, st).b = ( init) as i32;
    }
    return p_stmt_list1(x, st);
}

fn p_assign_op(x: &mut Fr) -> i64 {
    var c: ptr<u8> = null;
    if (p_ch_at(x, x.i, 61)) {
        c = "=";
    } else if (p_at_sym(x, "+=")) {
        c = "+=";
    } else if (p_at_sym(x, "-=")) {
        c = "-=";
    } else if (p_at_sym(x, "*=")) {
        c = "*=";
    } else if (p_at_sym(x, "/=")) {
        c = "/=";
    } else if (p_at_sym(x, "%=")) {
        c = "%=";
    } else if (p_at_sym(x, "<<=")) {
        c = "<<=";
    } else if (p_at_sym(x, ">>=")) {
        c = ">>=";
    } else if (p_at_sym(x, "&=")) {
        c = "&=";
    } else if (p_at_sym(x, "|=")) {
        c = "|=";
    } else if (p_at_sym(x, "^=")) {
        c = "^=";
    } else {
        return 0;
    }
    p_bump(x);
    return p_interns(x, c);
}

fn p_parse_expr(x: &mut Fr) -> i64 {
    return p_parse_bin(x, 1);
}

fn p_binop(x: &mut Fr) -> bool {
    let at: i64 = x.i;
    if (p_kind(x, at) != TK_SYM) {
        return false;
    }
    if (p_tok_eq(x, at, ">") && p_tok_eq(x, at + 1, ">")) {
        x.op = p_interns(x, ">>");
        x.prec = 8;
        x.ntok = 2;
        return true;
    }
    var c: ptr<u8> = null;
    var prec: i64 = 0;
    if (p_tok_eq(x, at, "||")) {
        c = "||";
        prec = 1;
    } else if (p_tok_eq(x, at, "&&")) {
        c = "&&";
        prec = 2;
    } else if (p_tok_eq(x, at, "|")) {
        c = "|";
        prec = 3;
    } else if (p_tok_eq(x, at, "^")) {
        c = "^";
        prec = 4;
    } else if (p_tok_eq(x, at, "&")) {
        c = "&";
        prec = 5;
    } else if (p_tok_eq(x, at, "==")) {
        c = "==";
        prec = 6;
    } else if (p_tok_eq(x, at, "!=")) {
        c = "!=";
        prec = 6;
    } else if (p_tok_eq(x, at, "<")) {
        c = "<";
        prec = 7;
    } else if (p_tok_eq(x, at, "<=")) {
        c = "<=";
        prec = 7;
    } else if (p_tok_eq(x, at, ">")) {
        c = ">";
        prec = 7;
    } else if (p_tok_eq(x, at, ">=")) {
        c = ">=";
        prec = 7;
    } else if (p_tok_eq(x, at, "<<")) {
        c = "<<";
        prec = 8;
    } else if (p_tok_eq(x, at, "+")) {
        c = "+";
        prec = 9;
    } else if (p_tok_eq(x, at, "-")) {
        c = "-";
        prec = 9;
    } else if (p_tok_eq(x, at, "*")) {
        c = "*";
        prec = 10;
    } else if (p_tok_eq(x, at, "/")) {
        c = "/";
        prec = 10;
    } else if (p_tok_eq(x, at, "%")) {
        c = "%";
        prec = 10;
    } else {
        return false;
    }
    x.op = p_interns(x, c);
    x.prec = prec;
    x.ntok = 1;
    return true;
}

fn p_parse_bin(x: &mut Fr, min_prec: i64) -> i64 {
    var lhs: i64 = p_parse_cast(x);
    if (x.ok == 0) {
        return 0;
    }
    while (true) {
        if (!p_binop(x)) {
            break;
        }
        let prec: i64 = x.prec;
        let nt: i64 = x.ntok;
        let op: i64 = x.op;
        if (prec < min_prec) {
            break;
        }
        var i: i64 = 0;
        while (i < nt) {
            p_bump(x);
            i += 1;
        }
        let rhs: i64 = p_parse_bin(x, prec + 1);
        if (x.ok == 0) {
            return 0;
        }
        lhs = p_bin(x, op, lhs, rhs);
    }
    return lhs;
}

fn p_parse_cast(x: &mut Fr) -> i64 {
    var e: i64 = p_parse_unary(x);
    if (x.ok == 0) {
        return 0;
    }
    while (p_eat_kw(x, "as")) {
        let t: i64 = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, EX_CAST);
        unsafe {
            na_at(x.na.v, n).a = ( e) as i32;
            na_at(x.na.v, n).b = ( t) as i32;
        }
        e = n;
    }
    return e;
}

fn p_un(x: &mut Fr, op: ptr<u8>, a: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_UN);
    let o: i64 = p_interns(x, op);
    unsafe {
        na_at(x.na.v, n).s = ( o) as i32;
        na_at(x.na.v, n).a = ( a) as i32;
    }
    return n;
}

fn p_wrap(x: &mut Fr, k: i32, a: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, k);
    unsafe { na_at(x.na.v, n).a = ( a) as i32; }
    return n;
}

fn p_parse_unary(x: &mut Fr) -> i64 {
    if (p_eat_sym(x, "-")) {
        let a: i64 = p_parse_unary(x);
        if (x.ok == 0) {
            return 0;
        }
        return p_un(x, "-", a);
    }
    if (p_eat_sym(x, "!")) {
        let a: i64 = p_parse_unary(x);
        if (x.ok == 0) {
            return 0;
        }
        return p_un(x, "!", a);
    }
    if (p_eat_sym(x, "~")) {
        let a: i64 = p_parse_unary(x);
        if (x.ok == 0) {
            return 0;
        }
        return p_un(x, "~", a);
    }
    if (p_eat_sym(x, "*")) {
        let a: i64 = p_parse_unary(x);
        if (x.ok == 0) {
            return 0;
        }
        return p_wrap(x, EX_DEREF, a);
    }
    if (p_eat_sym(x, "&")) {
        if (p_eat_kw(x, "mut")) {
            let a: i64 = p_parse_unary(x);
            if (x.ok == 0) {
                return 0;
            }
            return p_wrap(x, EX_ADDRMUT, a);
        }
        let a: i64 = p_parse_unary(x);
        if (x.ok == 0) {
            return 0;
        }
        return p_wrap(x, EX_ADDR, a);
    }
    return p_parse_postfix(x);
}

fn p_parse_args(x: &mut Fr) -> i64 {
    p_expect_sym(x, "(");
    if (x.ok == 0) {
        return 0;
    }
    var args: i64 = lp_add(&mut x.lp);
    if (!p_ch_at(x, x.i, 41)) {
        while (true) {
            let e: i64 = p_parse_expr(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, args, e);
            if (!p_eat_sym(x, ",")) {
                break;
            }
        }
    }
    p_expect_sym(x, ")");
    if (x.ok == 0) {
        return 0;
    }
    return args;
}

fn p_parse_postfix(x: &mut Fr) -> i64 {
    var e: i64 = p_parse_primary(x);
    if (x.ok == 0) {
        return 0;
    }
    while (true) {
        if (p_ch_at(x, x.i, 40)) {
            var args: i64 = p_parse_args(x);
            if (x.ok == 0) {
                return 0;
            }
            let hint: i64 = p_expr_hint(x, e);
            var turned: i32 = 0;
            if (hint != 0) {
                var hk: i32 = 0;
                unsafe { hk = na_at(x.na.v, hint).k; }
                if (hk == TY_FAT) {
                    var ps: i64 = zero(i64);
                    var rt: i64 = zero(i64);
                    unsafe {
                        ps = (na_at(x.na.v, hint).l as i64);
                        rt = (na_at(x.na.v, hint).a as i64);
                    }
                    var cps: i64 = lp_add(&mut x.lp);
                    let pu8a: i64 = p_ptr_u8(x);
                    lp_push(&mut x.lp, cps, pu8a);
                    let np: i64 = lp_len(&mut x.lp, ps);
                    var pi: i64 = 0;
                    while (pi < np) {
                        let pt: i64 = lp_get(&mut x.lp, ps, pi);
                        lp_push(&mut x.lp, cps, pt);
                        pi += 1;
                    }
                    let fty: i64 = p_fn_ty(x, cps, rt);
                    let cnm: i64 = p_interns(x, "code");
                    let fld: i64 = p_field(x, e, cnm);
                    let code: i64 = p_cast_e(x, fld, fty);
                    let enm: i64 = p_interns(x, "env");
                    let env: i64 = p_field(x, e, enm);
                    var all: i64 = lp_add(&mut x.lp);
                    lp_push(&mut x.lp, all, env);
                    let an: i64 = lp_len(&mut x.lp, args);
                    var ai: i64 = 0;
                    while (ai < an) {
                        let av: i64 = lp_get(&mut x.lp, args, ai);
                        lp_push(&mut x.lp, all, av);
                        ai += 1;
                    }
                    let cv: i64 = na_add(&mut x.na, EX_CALLV);
                    unsafe {
                        na_at(x.na.v, cv).a = ( code) as i32;
                        na_at(x.na.v, cv).l = ( all) as i32;
                    }
                    e = cv;
                    turned = 1;
                }
            }
            if (turned == 0) {
                var ek: i32 = 0;
                unsafe { ek = na_at(x.na.v, e).k; }
                if (ek == EX_VAR) {
                    var nm: i64 = zero(i64);
                    unsafe { nm = (na_at(x.na.v, e).s as i64); }
                    args = p_coerce_call(x, nm, args);
                    if (x.ok == 0) {
                        return 0;
                    }
                    let n: i64 = na_add(&mut x.na, EX_CALL);
                    unsafe {
                        na_at(x.na.v, n).s = ( nm) as i32;
                        na_at(x.na.v, n).l = ( args) as i32;
                    }
                    e = n;
                } else {
                    let n: i64 = na_add(&mut x.na, EX_CALLV);
                    unsafe {
                        na_at(x.na.v, n).a = ( e) as i32;
                        na_at(x.na.v, n).l = ( args) as i32;
                    }
                    e = n;
                }
            }
        } else if (p_eat_sym(x, "[")) {
            let idx: i64 = p_parse_expr(x);
            if (x.ok == 0) {
                return 0;
            }
            if (p_expect_sym(x, "]") == 0) {
                return 0;
            }
            let n: i64 = na_add(&mut x.na, EX_INDEX);
            unsafe {
                na_at(x.na.v, n).a = ( e) as i32;
                na_at(x.na.v, n).b = ( idx) as i32;
            }
            e = n;
        } else if (p_eat_sym(x, ".")) {
            var f: i64 = 0;
            if (p_kind(x, x.i) == TK_INT) {
                let at: i64 = x.i;
                let v: i64 = p_tok_num(x, at);
                if (v >= 0) {
                    p_bump(x);
                    f = p_num_id(x, v);
                } else {
                    f = p_name(x);
                    if (x.ok == 0) {
                        return 0;
                    }
                }
            } else {
                f = p_name(x);
                if (x.ok == 0) {
                    return 0;
                }
            }
            if (p_ch_at(x, x.i, 40)) {
                let args0: i64 = p_parse_args(x);
                if (x.ok == 0) {
                    return 0;
                }
                let hint: i64 = p_expr_hint(x, e);
                var done: i32 = 0;
                if (hint != 0) {
                    var hk: i32 = 0;
                    unsafe { hk = na_at(x.na.v, hint).k; }
                    if (hk == TY_DYN) {
                        var tr: i64 = 0;
                        unsafe { tr = (na_at(x.na.v, hint).s2 as i64); }
                        let tit: i64 = m64_get(&mut x.tdefs, tr, 0);
                        var wm: i64 = 0;
                        if (tit != 0) {
                            var msl: i64 = 0;
                            unsafe { msl = (na_at(x.na.v, tit).l as i64); }
                            let nm2: i64 = lp_len(&mut x.lp, msl);
                            var i2: i64 = 0;
                            while (i2 < nm2) {
                                let mm: i64 = lp_get(&mut x.lp, msl, i2);
                                var mnm: i64 = 0;
                                unsafe { mnm = (na_at(x.na.v, mm).s as i64); }
                                if (mnm == f) {
                                    wm = mm;
                                    break;
                                }
                                i2 += 1;
                            }
                        }
                        if (wm == 0) {
                            p_msg_begin(x);
                            p_msg_s(x, "trait ");
                            p_msg_id(x, tr);
                            p_msg_s(x, " has no method '");
                            p_msg_id(x, f);
                            p_msg_s(x, "'");
                            p_fail_plain(x);
                            return 0;
                        }
                        var pl: i64 = 0;
                        unsafe { pl = (na_at(x.na.v, wm).l as i64); }
                        let np: i64 = lp_len(&mut x.lp, pl);
                        var want: i64 = np / 2;
                        var k2: i64 = 0;
                        while (k2 < np) {
                            let pnm: i64 = lp_get(&mut x.lp, pl, k2);
                            if (sp_eqc(&mut x.sp, pnm, "self")) {
                                want -= 1;
                            }
                            k2 += 2;
                        }
                        let got: i64 = lp_len(&mut x.lp, args0);
                        if (want != got) {
                            p_msg_begin(x);
                            p_msg_id(x, tr);
                            p_msg_s(x, "::");
                            p_msg_id(x, f);
                            p_msg_s(x, " takes ");
                            p_msg_num(x, want);
                            p_msg_s(x, " argument(s), got ");
                            p_msg_num(x, got);
                            p_fail_plain(x);
                            return 0;
                        }
                        let vt: i64 = p_field(x, p_field(x, e, p_interns(x, "vt")), f);
                        let data: i64 = p_field(x, e, p_interns(x, "data"));
                        var all: i64 = lp_add(&mut x.lp);
                        lp_push(&mut x.lp, all, data);
                        var ai: i64 = 0;
                        while (ai < got) {
                            let av: i64 = lp_get(&mut x.lp, args0, ai);
                            lp_push(&mut x.lp, all, av);
                            ai += 1;
                        }
                        let cv: i64 = na_add(&mut x.na, EX_CALLV);
                        unsafe {
                            na_at(x.na.v, cv).a = ( vt) as i32;
                            na_at(x.na.v, cv).l = ( all) as i32;
                        }
                        e = cv;
                        done = 1;
                    }
                    if (done == 0) {
                        let hit: i64 = p_typed_method(x, hint, f);
                        if (hit != 0) {
                            let full: i64 = lp_get(&mut x.lp, x.methods, hit + 1);
                            let kind: i64 = lp_get(&mut x.lp, x.methods, hit + 2);
                            var base: i64 = 0;
                            if (kind == 1) {
                                base = p_wrap(x, EX_ADDRMUT, e);
                            } else {
                                base = p_wrap(x, EX_ADDR, e);
                            }
                            var cl: i64 = lp_add(&mut x.lp);
                            lp_push(&mut x.lp, cl, base);
                            let na2: i64 = lp_len(&mut x.lp, args0);
                            var aj: i64 = 0;
                            while (aj < na2) {
                                let av2: i64 = lp_get(&mut x.lp, args0, aj);
                                lp_push(&mut x.lp, cl, av2);
                                aj += 1;
                            }
                            e = p_call_e(x, full, cl);
                            done = 1;
                        }
                    }
                }
                if (done == 0) {
                    let n: i64 = na_add(&mut x.na, EX_METHOD);
                    unsafe {
                        na_at(x.na.v, n).a = ( e) as i32;
                        na_at(x.na.v, n).s = ( f) as i32;
                        na_at(x.na.v, n).l = ( args0) as i32;
                    }
                    e = n;
                }
            } else {
                e = p_field(x, e, f);
            }
        } else {
            break;
        }
    }
    return e;
}

fn p_parse_primary(x: &mut Fr) -> i64 {
    let at: i64 = x.i;
    let k: i32 = p_kind(x, at);
    if (k == TK_INT) {
        let v: i64 = p_tok_num(x, at);
        p_bump(x);
        return p_int(x, v);
    }
    if (k == TK_FLOAT) {
        let v: f64 = p_tok_fp(x, at);
        p_bump(x);
        let n: i64 = na_add(&mut x.na, EX_FLOAT);
        unsafe { na_at(x.na.v, n).f = v; }
        return n;
    }
    if (k == TK_STR) {
        let s: i64 = p_intern_tok(x, at);
        p_bump(x);
        let n: i64 = na_add(&mut x.na, EX_STR);
        unsafe { na_at(x.na.v, n).s = ( s) as i32; }
        return n;
    }
    if (p_ch_at(x, at, 91)) {
        p_bump(x);
        var items: i64 = lp_add(&mut x.lp);
        if (!p_ch_at(x, x.i, 93)) {
            while (true) {
                let e: i64 = p_parse_expr(x);
                if (x.ok == 0) {
                    return 0;
                }
                lp_push(&mut x.lp, items, e);
                if (!p_eat_sym(x, ",")) {
                    break;
                }
            }
        }
        if (p_expect_sym(x, "]") == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, EX_ARRAYLIT);
        unsafe { na_at(x.na.v, n).l = ( items) as i32; }
        return n;
    }
    if (p_ch_at(x, at, 124) || p_sym_at(x, at, "||")) {
        return p_parse_closure(x);
    }
    if (k == TK_IDENT && p_tok_eq(x, at, "await")) {
        p_bump(x);
        let e: i64 = p_parse_unary(x);
        if (x.ok == 0) {
            return 0;
        }
        return p_wrap(x, EX_AWAIT, e);
    }
    if (k == TK_IDENT && p_tok_eq(x, at, "poll") && p_ch_at(x, at + 1, 40)) {
        p_bump(x);
        if (p_expect_sym(x, "(") == 0) {
            return 0;
        }
        let e: i64 = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
        }
        if (p_expect_sym(x, ")") == 0) {
            return 0;
        }
        return p_wrap(x, EX_POLL, e);
    }
    if (k == TK_IDENT) {
        let name: i64 = p_intern_tok(x, at);
        if (sp_eqc(&mut x.sp, name, "true")) {
            p_bump(x);
            let n: i64 = na_add(&mut x.na, EX_BOOL);
            unsafe { na_at(x.na.v, n).n = 1; }
            return n;
        }
        if (sp_eqc(&mut x.sp, name, "false")) {
            p_bump(x);
            let n: i64 = na_add(&mut x.na, EX_BOOL);
            unsafe { na_at(x.na.v, n).n = 0; }
            return n;
        }
        if (sp_eqc(&mut x.sp, name, "null")) {
            p_bump(x);
            return na_add(&mut x.na, EX_NULL);
        }
        if (sp_eqc(&mut x.sp, name, "sizeof")) {
            p_bump(x);
            if (p_expect_sym(x, "(") == 0) {
                return 0;
            }
            let t: i64 = p_parse_type(x);
            if (x.ok == 0) {
                return 0;
            }
            if (p_expect_sym(x, ")") == 0) {
                return 0;
            }
            return p_wrap(x, EX_SIZEOF, t);
        }
        if (sp_eqc(&mut x.sp, name, "zero")) {
            p_bump(x);
            if (p_expect_sym(x, "(") == 0) {
                return 0;
            }
            let t: i64 = p_parse_type(x);
            if (x.ok == 0) {
                return 0;
            }
            if (p_expect_sym(x, ")") == 0) {
                return 0;
            }
            return p_wrap(x, EX_ZERO, t);
        }
        if (sp_eqc(&mut x.sp, name, "box")) {
            p_bump(x);
            if (p_expect_sym(x, "(") == 0) {
                return 0;
            }
            let e: i64 = p_parse_expr(x);
            if (x.ok == 0) {
                return 0;
            }
            if (p_expect_sym(x, ")") == 0) {
                return 0;
            }
            return p_wrap(x, EX_BOXNEW, e);
        }
        p_bump(x);
        if (p_at_sym(x, "::")) {
            var segs: i64 = lp_add(&mut x.lp);
            lp_push(&mut x.lp, segs, name);
            while (p_at_sym(x, "::")) {
                p_bump(x);
                let s: i64 = p_raw_name(x);
                if (x.ok == 0) {
                    return 0;
                }
                lp_push(&mut x.lp, segs, s);
            }
            let ns: i64 = lp_len(&mut x.lp, segs);
            var kk: i64 = 0 - 1;
            var i: i64 = 0;
            while (i < ns) {
                let s: i64 = lp_get(&mut x.lp, segs, i);
                if (p_upper(x, s)) {
                    kk = i;
                    break;
                }
                i += 1;
            }
            if (kk < 0) {
                let joined: i64 = p_join(x, segs, "__");
                if (p_ch_at(x, x.i, 40)) {
                    let args: i64 = p_parse_args(x);
                    if (x.ok == 0) {
                        return 0;
                    }
                    let n: i64 = na_add(&mut x.na, EX_CALL);
                    unsafe {
                        na_at(x.na.v, n).s = ( joined) as i32;
                        na_at(x.na.v, n).l = ( args) as i32;
                    }
                    return n;
                }
                return p_var(x, joined);
            }
            let rest: i64 = ns - kk;
            if (rest == 1) {
                let joined: i64 = p_join(x, segs, "__");
                let full: i64 = p_cat2(x, x.pfx, joined);
                if (p_ch_at(x, x.i, 123)) {
                    return p_parse_struct_lit(x, full);
                }
                return p_var(x, full);
            }
            if (rest == 2) {
                var head: i64 = lp_add(&mut x.lp);
                var j: i64 = 0;
                while (j <= kk) {
                    let s: i64 = lp_get(&mut x.lp, segs, j);
                    lp_push(&mut x.lp, head, s);
                    j += 1;
                }
                let joined: i64 = p_join(x, head, "__");
                let ty: i64 = p_cat2(x, x.pfx, joined);
                let vn: i64 = lp_get(&mut x.lp, segs, kk + 1);
                var args: i64 = lp_add(&mut x.lp);
                if (p_eat_sym(x, "(")) {
                    if (!p_ch_at(x, x.i, 41)) {
                        while (true) {
                            let e: i64 = p_parse_expr(x);
                            if (x.ok == 0) {
                                return 0;
                            }
                            lp_push(&mut x.lp, args, e);
                            if (!p_eat_sym(x, ",")) {
                                break;
                            }
                        }
                    }
                    p_expect_sym(x, ")");
                    if (x.ok == 0) {
                        return 0;
                    }
                }
                let assoc: i64 = p_cat3(x, ty, p_interns(x, "__"), vn);
                if (m64_has(&mut x.fmap, assoc)) {
                    let cargs: i64 = p_coerce_call(x, assoc, args);
                    let cn: i64 = na_add(&mut x.na, EX_CALL);
                    unsafe {
                        na_at(x.na.v, cn).s = ( assoc) as i32;
                        na_at(x.na.v, cn).l = ( cargs) as i32;
                    }
                    return cn;
                }
                let n: i64 = na_add(&mut x.na, EX_ENUMLIT);
                unsafe {
                    na_at(x.na.v, n).s = ( ty) as i32;
                    na_at(x.na.v, n).s2 = ( vn) as i32;
                    na_at(x.na.v, n).l = ( args) as i32;
                }
                return n;
            }
            p_msg_begin(x);
            p_msg_s(x, "too many '::' segments: a name is 'mod::Type::Variant' at most");
            return p_fail(x);
        }
        if (p_ch_at(x, x.i, 123) && p_upper(x, name)) {
            let full: i64 = p_cat2(x, x.pfx, name);
            return p_parse_struct_lit(x, full);
        }
        return p_var(x, name);
    }
    if (p_ch_at(x, at, 40)) {
        p_bump(x);
        let first: i64 = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
        }
        if (p_eat_sym(x, ",")) {
            var items: i64 = lp_add(&mut x.lp);
            lp_push(&mut x.lp, items, first);
            while (true) {
                let e: i64 = p_parse_expr(x);
                if (x.ok == 0) {
                    return 0;
                }
                lp_push(&mut x.lp, items, e);
                if (!p_eat_sym(x, ",")) {
                    break;
                }
            }
            if (p_expect_sym(x, ")") == 0) {
                return 0;
            }
            if (lp_len(&mut x.lp, items) < 2) {
                p_msg_begin(x);
                p_msg_s(x, "a tuple needs at least two elements");
                return p_fail(x);
            }
            let n: i64 = na_add(&mut x.na, EX_TUPLELIT);
            unsafe { na_at(x.na.v, n).l = ( items) as i32; }
            return n;
        }
        if (p_expect_sym(x, ")") == 0) {
            return 0;
        }
        return first;
    }
    p_msg_begin(x);
    p_msg_s(x, "expected an expression, found ");
    p_msg_desc(x);
    return p_fail(x);
}

fn p_parse_closure(x: &mut Fr) -> i64 {
    var params: i64 = lp_add(&mut x.lp);
    if (!p_eat_sym(x, "||")) {
        if (p_expect_sym(x, "|") == 0) {
            return 0;
        }
        if (!p_ch_at(x, x.i, 124)) {
            while (true) {
                let pname: i64 = p_name(x);
                if (x.ok == 0) {
                    return 0;
                }
                if (p_expect_sym(x, ":") == 0) {
                    return 0;
                }
                let pty: i64 = p_parse_type(x);
                if (x.ok == 0) {
                    return 0;
                }
                let np: i64 = lp_len(&mut x.lp, params);
                var i: i64 = 0;
                while (i < np) {
                    if (lp_get(&mut x.lp, params, i) == pname) {
                        p_msg_begin(x);
                        p_msg_s(x, "duplicate parameter '");
                        p_msg_id(x, pname);
                        p_msg_s(x, "' in closure");
                        return p_fail_plain(x);
                    }
                    i += 2;
                }
                lp_push(&mut x.lp, params, pname);
                lp_push(&mut x.lp, params, pty);
                if (!p_eat_sym(x, ",")) {
                    break;
                }
            }
        }
        if (p_expect_sym(x, "|") == 0) {
            return 0;
        }
    }
    var ret: i64 = 0;
    if (p_eat_sym(x, "->")) {
        ret = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
    } else {
        ret = p_ty(x, TY_VOID);
    }
    p_push_scope(x);
    let npar: i64 = lp_len(&mut x.lp, params);
    var bp: i64 = 0;
    while (bp < npar) {
        let bn: i64 = lp_get(&mut x.lp, params, bp);
        let bt: i64 = lp_get(&mut x.lp, params, bp + 1);
        p_bind(x, bn, bt);
        bp += 2;
    }
    p_push_ret(x, ret);
    let body: i64 = p_parse_block(x);
    p_pop_ret(x);
    p_pop_scope(x);
    if (x.ok == 0) {
        return 0;
    }
    let idx: i64 = x.clo;
    x.clo += 1;
    var bound: i64 = lp_add(&mut x.lp);
    var pi: i64 = 0;
    while (pi < npar) {
        let bnv: i64 = lp_get(&mut x.lp, params, pi);
        lp_push(&mut x.lp, bound, bnv);
        pi += 2;
    }
    var ptys: i64 = lp_add(&mut x.lp);
    var pt: i64 = 0;
    while (pt < npar) {
        let pv: i64 = lp_get(&mut x.lp, params, pt + 1);
        lp_push(&mut x.lp, ptys, pv);
        pt += 2;
    }
    var free: i64 = lp_add(&mut x.lp);
    p_free_blk(x, body, bound, free);
    if (x.ok == 0) {
        return 0;
    }
    var caps: i64 = lp_add(&mut x.lp);
    let nfr: i64 = lp_len(&mut x.lp, free);
    var fi: i64 = 0;
    while (fi < nfr) {
        let nmv: i64 = lp_get(&mut x.lp, free, fi);
        let tyv: i64 = p_lookup_binding(x, nmv);
        if (tyv != 0) {
            var tk: i32 = 0;
            unsafe { tk = na_at(x.na.v, tyv).k; }
            if (tk == TY_INFER) {
                p_msg_begin(x);
                p_msg_s(x, "closure captures '");
                p_msg_id(x, nmv);
                p_msg_s(x, "', which needs a type annotation");
                return p_fail_plain(x);
            }
            let field: i64 = p_cat2(x, p_interns(x, "c"), p_num_id(x, lp_len(&mut x.lp, caps) / 3));
            lp_push(&mut x.lp, caps, nmv);
            lp_push(&mut x.lp, caps, tyv);
            lp_push(&mut x.lp, caps, field);
        }
        fi += 1;
    }
    let ncap: i64 = lp_len(&mut x.lp, caps) / 3;
    if (ncap == 0) {
        let pre: i64 = p_interns(x, "__clo");
        let num: i64 = p_num_id(x, idx);
        let name: i64 = p_cat2(x, pre, num);
        let tp: i64 = lp_add(&mut x.lp);
        let f: i64 = na_add(&mut x.na, IT_FN);
        unsafe {
            na_at(x.na.v, f).s = ( name) as i32;
            na_at(x.na.v, f).l = ( tp) as i32;
            na_at(x.na.v, f).l2 = ( params) as i32;
            na_at(x.na.v, f).a = ( ret) as i32;
            na_at(x.na.v, f).n = 0;
            na_at(x.na.v, f).m = 0;
            na_at(x.na.v, f).l3 = ( body) as i32;
        }
        lp_push(&mut x.lp, x.lifts, f);
        let n: i64 = na_add(&mut x.na, EX_FNREF);
        unsafe { na_at(x.na.v, n).s = ( name) as i32; }
        return n;
    }
    let envnm: i64 = p_cat2(x, p_interns(x, "__Env"), p_num_id(x, idx));
    let envvar: i64 = p_cat2(x, p_interns(x, "__env"), p_num_id(x, idx));
    var efields: i64 = lp_add(&mut x.lp);
    var ci: i64 = 0;
    while (ci < ncap) {
        let cf: i64 = lp_get(&mut x.lp, caps, ci * 3 + 2);
        let ct: i64 = lp_get(&mut x.lp, caps, ci * 3 + 1);
        lp_push(&mut x.lp, efields, cf);
        lp_push(&mut x.lp, efields, ct);
        ci += 1;
    }
    let eit: i64 = p_struct_add(x, envnm, efields);
    m64_set(&mut x.smap, envnm, efields);
    lp_push(&mut x.lp, x.synl, eit);
    let envty: i64 = p_ptr_named(x, envnm);
    p_cap_blk(x, body, envvar, caps);
    let clo: i64 = p_cat2(x, p_interns(x, "__clo"), p_num_id(x, idx));
    var wparams: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, wparams, envvar);
    lp_push(&mut x.lp, wparams, envty);
    var pj: i64 = 0;
    while (pj < npar) {
        let wn2: i64 = lp_get(&mut x.lp, params, pj);
        let wy2: i64 = lp_get(&mut x.lp, params, pj + 1);
        lp_push(&mut x.lp, wparams, wn2);
        lp_push(&mut x.lp, wparams, wy2);
        pj += 2;
    }
    var ublk: i64 = lp_add(&mut x.lp);
    var wn: i64 = lp_len(&mut x.lp, body);
    var wi: i64 = 0;
    while (wi < wn) {
        let bst: i64 = lp_get(&mut x.lp, body, wi);
        lp_push(&mut x.lp, ublk, bst);
        wi += 1;
    }
    var wbody: i64 = lp_add(&mut x.lp);
    let ust: i64 = na_add(&mut x.na, ST_UNSAFE);
    unsafe { na_at(x.na.v, ust).l = ( ublk) as i32; }
    lp_push(&mut x.lp, wbody, ust);
    let wf: i64 = na_add(&mut x.na, IT_FN);
    let wtp: i64 = lp_add(&mut x.lp);
    unsafe {
        na_at(x.na.v, wf).s = ( clo) as i32;
        na_at(x.na.v, wf).l = ( wtp) as i32;
        na_at(x.na.v, wf).l2 = ( wparams) as i32;
        na_at(x.na.v, wf).a = ( ret) as i32;
        na_at(x.na.v, wf).l3 = ( wbody) as i32;
    }
    lp_push(&mut x.lp, x.lifts, wf);
    let fat: i64 = p_fat_type(x, ptys, ret);
    var fatnm: i64 = 0;
    unsafe { fatnm = (na_at(x.na.v, fat).s as i64); }
    let mk: i64 = p_cat2(x, p_interns(x, "__mkclo"), p_num_id(x, idx));
    var mkparams: i64 = lp_add(&mut x.lp);
    var mkbody: i64 = lp_add(&mut x.lp);
    let ev: i64 = p_interns(x, "__e");
    let pbase: i64 = p_interns(x, "p");
    var mi: i64 = 0;
    while (mi < ncap) {
        let pn: i64 = p_cat2(x, pbase, p_num_id(x, mi));
        let ct2: i64 = lp_get(&mut x.lp, caps, mi * 3 + 1);
        lp_push(&mut x.lp, mkparams, pn);
        lp_push(&mut x.lp, mkparams, ct2);
        mi += 1;
    }
    let szn: i64 = na_add(&mut x.na, EX_SIZEOF);
    unsafe { na_at(x.na.v, szn).a = ( envnm) as i32; }
    let malt: i64 = p_call_e(x, p_interns(x, "malloc"), lp_add1(x, szn));
    let ec: i64 = p_cast_e(x, malt, envty);
    let elt: i64 = na_add(&mut x.na, ST_LET);
    unsafe {
        na_at(x.na.v, elt).s = ( ev) as i32;
        na_at(x.na.v, elt).a = ( envty) as i32;
        na_at(x.na.v, elt).b = ( ec) as i32;
    }
    lp_push(&mut x.lp, mkbody, elt);
    var writes: i64 = lp_add(&mut x.lp);
    var wi2: i64 = 0;
    while (wi2 < ncap) {
        let pn2: i64 = p_cat2(x, pbase, p_num_id(x, wi2));
        let lhs: i64 = p_field_e(x, p_var(x, ev), lp_get(&mut x.lp, caps, wi2 * 3 + 2));
        let a: i64 = na_add(&mut x.na, ST_ASSIGN);
        unsafe {
            na_at(x.na.v, a).s = ( p_interns(x, "=")) as i32;
            na_at(x.na.v, a).a = ( lhs) as i32;
            na_at(x.na.v, a).b = ( p_var(x, pn2)) as i32;
        }
        lp_push(&mut x.lp, writes, a);
        wi2 += 1;
    }
    let wst: i64 = na_add(&mut x.na, ST_UNSAFE);
    unsafe { na_at(x.na.v, wst).l = ( writes) as i32; }
    lp_push(&mut x.lp, mkbody, wst);
    let pu8: i64 = p_ptr_u8(x);
    let code: i64 = p_interns(x, "code");
    let envf: i64 = p_interns(x, "env");
    var sfields: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, sfields, code);
    lp_push(&mut x.lp, sfields, p_cast_e(x, p_fnref_e(x, clo), pu8));
    lp_push(&mut x.lp, sfields, envf);
    lp_push(&mut x.lp, sfields, p_cast_e(x, p_var(x, ev), pu8));
    let sl: i64 = p_structlit_e(x, fatnm, sfields);
    let rst: i64 = na_add(&mut x.na, ST_RETURN);
    unsafe { na_at(x.na.v, rst).a = ( sl) as i32; }
    lp_push(&mut x.lp, mkbody, rst);
    let mf: i64 = na_add(&mut x.na, IT_FN);
    let mtp: i64 = lp_add(&mut x.lp);
    unsafe {
        na_at(x.na.v, mf).s = ( mk) as i32;
        na_at(x.na.v, mf).l = ( mtp) as i32;
        na_at(x.na.v, mf).l2 = ( mkparams) as i32;
        na_at(x.na.v, mf).a = ( fatnm) as i32;
        na_at(x.na.v, mf).l3 = ( mkbody) as i32;
    }
    lp_push(&mut x.lp, x.genf, mf);
    var cargs: i64 = lp_add(&mut x.lp);
    var aj: i64 = 0;
    while (aj < ncap) {
        let cav: i64 = lp_get(&mut x.lp, caps, aj * 3);
        lp_push(&mut x.lp, cargs, p_var(x, cav));
        aj += 1;
    }
    return p_call_e(x, mk, cargs);
}

fn lp_add1(x: &mut Fr, v: i64) -> i64 {
    let l: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, l, v);
    return l;
}

fn p_ptr_named(x: &mut Fr, name: i64) -> i64 {
    let n: i64 = p_ty(x, TY_NAMED);
    unsafe { na_at(x.na.v, n).s = ( name) as i32; }
    return p_ptr_to(x, n);
}

fn p_field_e(x: &mut Fr, base: i64, f: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_FIELD);
    unsafe {
        na_at(x.na.v, n).a = ( base) as i32;
        na_at(x.na.v, n).s = ( f) as i32;
    }
    return n;
}

fn p_lp_clone(x: &mut Fr, l: i64) -> i64 {
    let c: i64 = lp_add(&mut x.lp);
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 0;
    while (i < n) {
        let v: i64 = lp_get(&mut x.lp, l, i);
        lp_push(&mut x.lp, c, v);
        i += 1;
    }
    return c;
}

fn p_free_add(x: &mut Fr, bound: i64, out: i64, name: i64) {
    if (p_in_list(x, bound, name)) {
        return;
    }
    if (p_in_list(x, out, name)) {
        return;
    }
    lp_push(&mut x.lp, out, name);
}

fn p_free_ex(x: &mut Fr, e: i64, bound: i64, out: i64) {
    var k: i32 = 0;
    unsafe { k = na_at(x.na.v, e).k; }
    if (k == EX_VAR) {
        var nm: i64 = 0;
        unsafe { nm = (na_at(x.na.v, e).s as i64); }
        p_free_add(x, bound, out, nm);
        return;
    }
    if (k == EX_CALL) {
        var nm2: i64 = 0;
        var args: i64 = 0;
        unsafe {
            nm2 = (na_at(x.na.v, e).s as i64);
            args = (na_at(x.na.v, e).l as i64);
        }
        p_free_add(x, bound, out, nm2);
        let n: i64 = lp_len(&mut x.lp, args);
        var i: i64 = 0;
        while (i < n) {
            let av: i64 = lp_get(&mut x.lp, args, i);
            p_free_ex(x, av, bound, out);
            i += 1;
        }
        return;
    }
    if (k == EX_BIN || k == EX_INDEX) {
        var a: i64 = 0;
        var b: i64 = 0;
        unsafe {
            a = (na_at(x.na.v, e).a as i64);
            b = (na_at(x.na.v, e).b as i64);
        }
        p_free_ex(x, a, bound, out);
        p_free_ex(x, b, bound, out);
        return;
    }
    if (k == EX_UN || k == EX_DEREF || k == EX_ADDR || k == EX_ADDRMUT || k == EX_BOXNEW || k == EX_CAST || k == EX_AWAIT || k == EX_POLL || k == EX_FIELD) {
        var a2: i64 = 0;
        unsafe { a2 = (na_at(x.na.v, e).a as i64); }
        p_free_ex(x, a2, bound, out);
        return;
    }
    if (k == EX_STRUCTLIT) {
        var fl: i64 = 0;
        unsafe { fl = (na_at(x.na.v, e).l as i64); }
        let nf: i64 = lp_len(&mut x.lp, fl);
        var j: i64 = 1;
        while (j < nf) {
            let fv: i64 = lp_get(&mut x.lp, fl, j);
            p_free_ex(x, fv, bound, out);
            j += 2;
        }
        return;
    }
    if (k == EX_ARRAYLIT || k == EX_TUPLELIT || k == EX_ENUMLIT) {
        var il: i64 = 0;
        unsafe { il = (na_at(x.na.v, e).l as i64); }
        let ni: i64 = lp_len(&mut x.lp, il);
        var q: i64 = 0;
        while (q < ni) {
            let it: i64 = lp_get(&mut x.lp, il, q);
            p_free_ex(x, it, bound, out);
            q += 1;
        }
        return;
    }
    if (k == EX_CALLV || k == EX_METHOD) {
        var cf: i64 = 0;
        var al: i64 = 0;
        unsafe {
            cf = (na_at(x.na.v, e).a as i64);
            al = (na_at(x.na.v, e).l as i64);
        }
        p_free_ex(x, cf, bound, out);
        let nl: i64 = lp_len(&mut x.lp, al);
        var m: i64 = 0;
        while (m < nl) {
            let ma: i64 = lp_get(&mut x.lp, al, m);
            p_free_ex(x, ma, bound, out);
            m += 1;
        }
        return;
    }
}

fn p_free_blk(x: &mut Fr, body: i64, bound: i64, out: i64) {
    let n: i64 = lp_len(&mut x.lp, body);
    var i: i64 = 0;
    while (i < n) {
        let st: i64 = lp_get(&mut x.lp, body, i);
        p_free_st(x, st, bound, out);
        i += 1;
    }
}

fn p_free_st(x: &mut Fr, st: i64, bound: i64, out: i64) {
    var k: i32 = 0;
    unsafe { k = na_at(x.na.v, st).k; }
    if (k == ST_LET) {
        var nm: i64 = 0;
        var init: i64 = 0;
        unsafe {
            nm = (na_at(x.na.v, st).s as i64);
            init = (na_at(x.na.v, st).b as i64);
        }
        if (init != 0) {
            p_free_ex(x, init, bound, out);
        }
        lp_push(&mut x.lp, bound, nm);
        return;
    }
    if (k == ST_ASSIGN) {
        var a: i64 = 0;
        var b: i64 = 0;
        unsafe {
            a = (na_at(x.na.v, st).a as i64);
            b = (na_at(x.na.v, st).b as i64);
        }
        p_free_ex(x, a, bound, out);
        p_free_ex(x, b, bound, out);
        return;
    }
    if (k == ST_EXPR) {
        var e: i64 = 0;
        unsafe { e = (na_at(x.na.v, st).a as i64); }
        p_free_ex(x, e, bound, out);
        return;
    }
    if (k == ST_BLOCK || k == ST_UNSAFE) {
        var bl: i64 = 0;
        unsafe { bl = (na_at(x.na.v, st).l as i64); }
        let inner: i64 = p_lp_clone(x, bound);
        p_free_blk(x, bl, inner, out);
        return;
    }
    if (k == ST_IF) {
        var c: i64 = 0;
        var th: i64 = 0;
        var el: i64 = 0;
        unsafe {
            c = (na_at(x.na.v, st).a as i64);
            th = (na_at(x.na.v, st).l as i64);
            el = (na_at(x.na.v, st).l2 as i64);
        }
        p_free_ex(x, c, bound, out);
        let b1: i64 = p_lp_clone(x, bound);
        p_free_blk(x, th, b1, out);
        let b2: i64 = p_lp_clone(x, bound);
        p_free_blk(x, el, b2, out);
        return;
    }
    if (k == ST_WHILE) {
        var c2: i64 = 0;
        var bl2: i64 = 0;
        unsafe {
            c2 = (na_at(x.na.v, st).a as i64);
            bl2 = (na_at(x.na.v, st).l as i64);
        }
        p_free_ex(x, c2, bound, out);
        let b3: i64 = p_lp_clone(x, bound);
        p_free_blk(x, bl2, b3, out);
        return;
    }
    if (k == ST_LOOP) {
        var bl3: i64 = 0;
        unsafe { bl3 = (na_at(x.na.v, st).l as i64); }
        let b4: i64 = p_lp_clone(x, bound);
        p_free_blk(x, bl3, b4, out);
        return;
    }
    if (k == ST_FOR) {
        var fv: i64 = 0;
        var sa: i64 = 0;
        var sb: i64 = 0;
        var fb: i64 = 0;
        unsafe {
            fv = (na_at(x.na.v, st).s as i64);
            sa = (na_at(x.na.v, st).a as i64);
            sb = (na_at(x.na.v, st).b as i64);
            fb = (na_at(x.na.v, st).l as i64);
        }
        p_free_ex(x, sa, bound, out);
        p_free_ex(x, sb, bound, out);
        let b5: i64 = p_lp_clone(x, bound);
        lp_push(&mut x.lp, b5, fv);
        p_free_blk(x, fb, b5, out);
        return;
    }
    if (k == ST_MATCH) {
        var sc: i64 = 0;
        var al: i64 = 0;
        unsafe {
            sc = (na_at(x.na.v, st).a as i64);
            al = (na_at(x.na.v, st).l as i64);
        }
        p_free_ex(x, sc, bound, out);
        let na: i64 = lp_len(&mut x.lp, al);
        var ai: i64 = 0;
        while (ai < na) {
            let arm: i64 = lp_get(&mut x.lp, al, ai);
            let inner: i64 = p_lp_clone(x, bound);
            var pat: i64 = 0;
            var ab: i64 = 0;
            unsafe {
                pat = (na_at(x.na.v, arm).a as i64);
                ab = (na_at(x.na.v, arm).l as i64);
            }
            var pk: i32 = 0;
            unsafe { pk = na_at(x.na.v, pat).k; }
            if (pk == PT_VARIANT) {
                var binds: i64 = 0;
                unsafe { binds = (na_at(x.na.v, pat).l as i64); }
                let nb: i64 = lp_len(&mut x.lp, binds);
                var bi: i64 = 0;
                while (bi < nb) {
                    let bv: i64 = lp_get(&mut x.lp, binds, bi);
                    lp_push(&mut x.lp, inner, bv);
                    bi += 1;
                }
            }
            p_free_blk(x, ab, inner, out);
            ai += 1;
        }
        return;
    }
    if (k == ST_LABEL) {
        var inr: i64 = 0;
        unsafe { inr = (na_at(x.na.v, st).a as i64); }
        let b6: i64 = p_lp_clone(x, bound);
        p_free_st(x, inr, b6, out);
        return;
    }
    if (k == ST_RETURN) {
        var rv: i64 = 0;
        unsafe { rv = (na_at(x.na.v, st).a as i64); }
        if (rv != 0) {
            p_free_ex(x, rv, bound, out);
        }
        return;
    }
}

fn p_cap_find(x: &mut Fr, caps: i64, nm: i64) -> i64 {
    let n: i64 = lp_len(&mut x.lp, caps) / 3;
    var i: i64 = 0;
    while (i < n) {
        let cn: i64 = lp_get(&mut x.lp, caps, i * 3);
        if (cn == nm) {
            return i;
        }
        i += 1;
    }
    return 0 - 1;
}

fn p_fat_call(x: &mut Fr, callee: i64, ty: i64, args: i64) -> i64 {
    var ps: i64 = 0;
    var rt: i64 = 0;
    unsafe {
        ps = (na_at(x.na.v, ty).l as i64);
        rt = (na_at(x.na.v, ty).a as i64);
    }
    var cps: i64 = lp_add(&mut x.lp);
    let u8p: i64 = p_ptr_u8(x);
    lp_push(&mut x.lp, cps, u8p);
    let np: i64 = lp_len(&mut x.lp, ps);
    var i: i64 = 0;
    while (i < np) {
        let pt: i64 = lp_get(&mut x.lp, ps, i);
        lp_push(&mut x.lp, cps, pt);
        i += 1;
    }
    let ft: i64 = p_fn_ty(x, cps, rt);
    let codef: i64 = p_interns(x, "code");
    let envf: i64 = p_interns(x, "env");
    let cbase: i64 = p_field_e(x, callee, codef);
    let code: i64 = p_cast_e(x, cbase, ft);
    let envx: i64 = p_field_e(x, callee, envf);
    var all: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, all, envx);
    let na2: i64 = lp_len(&mut x.lp, args);
    var j: i64 = 0;
    while (j < na2) {
        let av: i64 = lp_get(&mut x.lp, args, j);
        lp_push(&mut x.lp, all, av);
        j += 1;
    }
    let n: i64 = na_add(&mut x.na, EX_CALLV);
    unsafe {
        na_at(x.na.v, n).a = ( code) as i32;
        na_at(x.na.v, n).l = ( all) as i32;
    }
    return n;
}

fn p_cap_ex(x: &mut Fr, e: i64, env: i64, caps: i64) {
    var k: i32 = 0;
    unsafe { k = na_at(x.na.v, e).k; }
    if (k == EX_VAR) {
        var nm: i64 = 0;
        unsafe { nm = (na_at(x.na.v, e).s as i64); }
        let ci: i64 = p_cap_find(x, caps, nm);
        if (ci >= 0) {
            let fld: i64 = lp_get(&mut x.lp, caps, ci * 3 + 2);
            let base: i64 = p_var(x, env);
            unsafe {
                na_at(x.na.v, e).k = EX_FIELD;
                na_at(x.na.v, e).a = ( base) as i32;
                na_at(x.na.v, e).s = ( fld) as i32;
            }
        }
        return;
    }
    if (k == EX_CALL) {
        var nm2: i64 = 0;
        var args: i64 = 0;
        unsafe {
            nm2 = (na_at(x.na.v, e).s as i64);
            args = (na_at(x.na.v, e).l as i64);
        }
        let na: i64 = lp_len(&mut x.lp, args);
        var i: i64 = 0;
        while (i < na) {
            let av: i64 = lp_get(&mut x.lp, args, i);
            p_cap_ex(x, av, env, caps);
            i += 1;
        }
        let ci2: i64 = p_cap_find(x, caps, nm2);
        if (ci2 >= 0) {
            let fld2: i64 = lp_get(&mut x.lp, caps, ci2 * 3 + 2);
            let ty2: i64 = lp_get(&mut x.lp, caps, ci2 * 3 + 1);
            let cenv: i64 = p_var(x, env);
            let callee: i64 = p_field_e(x, cenv, fld2);
            var tk2: i32 = 0;
            unsafe { tk2 = na_at(x.na.v, ty2).k; }
            if (tk2 == TY_FAT) {
                let fc: i64 = p_fat_call(x, callee, ty2, args);
                na_copy(x.na.v, e, fc);
            } else {
                unsafe {
                    na_at(x.na.v, e).k = EX_CALLV;
                    na_at(x.na.v, e).a = ( callee) as i32;
                    na_at(x.na.v, e).s = 0;
                }
            }
        }
        return;
    }
    if (k == EX_BIN || k == EX_INDEX) {
        var a: i64 = 0;
        var b: i64 = 0;
        unsafe {
            a = (na_at(x.na.v, e).a as i64);
            b = (na_at(x.na.v, e).b as i64);
        }
        p_cap_ex(x, a, env, caps);
        p_cap_ex(x, b, env, caps);
        return;
    }
    if (k == EX_UN || k == EX_DEREF || k == EX_ADDR || k == EX_ADDRMUT || k == EX_BOXNEW || k == EX_CAST || k == EX_AWAIT || k == EX_POLL || k == EX_FIELD) {
        var a2: i64 = 0;
        unsafe { a2 = (na_at(x.na.v, e).a as i64); }
        p_cap_ex(x, a2, env, caps);
        return;
    }
    if (k == EX_STRUCTLIT) {
        var fl: i64 = 0;
        unsafe { fl = (na_at(x.na.v, e).l as i64); }
        let nf: i64 = lp_len(&mut x.lp, fl);
        var j: i64 = 1;
        while (j < nf) {
            let fv: i64 = lp_get(&mut x.lp, fl, j);
            p_cap_ex(x, fv, env, caps);
            j += 2;
        }
        return;
    }
    if (k == EX_ARRAYLIT || k == EX_TUPLELIT || k == EX_ENUMLIT) {
        var il: i64 = 0;
        unsafe { il = (na_at(x.na.v, e).l as i64); }
        let ni: i64 = lp_len(&mut x.lp, il);
        var q: i64 = 0;
        while (q < ni) {
            let it: i64 = lp_get(&mut x.lp, il, q);
            p_cap_ex(x, it, env, caps);
            q += 1;
        }
        return;
    }
    if (k == EX_CALLV || k == EX_METHOD) {
        var cf: i64 = 0;
        var al: i64 = 0;
        unsafe {
            cf = (na_at(x.na.v, e).a as i64);
            al = (na_at(x.na.v, e).l as i64);
        }
        p_cap_ex(x, cf, env, caps);
        let nl: i64 = lp_len(&mut x.lp, al);
        var m: i64 = 0;
        while (m < nl) {
            let ma: i64 = lp_get(&mut x.lp, al, m);
            p_cap_ex(x, ma, env, caps);
            m += 1;
        }
        return;
    }
}

fn p_cap_blk(x: &mut Fr, body: i64, env: i64, caps: i64) {
    let n: i64 = lp_len(&mut x.lp, body);
    var i: i64 = 0;
    while (i < n) {
        let st: i64 = lp_get(&mut x.lp, body, i);
        p_cap_st(x, st, env, caps);
        i += 1;
    }
}

fn p_cap_st(x: &mut Fr, st: i64, env: i64, caps: i64) {
    var k: i32 = 0;
    unsafe { k = na_at(x.na.v, st).k; }
    if (k == ST_LET) {
        var init: i64 = 0;
        unsafe { init = (na_at(x.na.v, st).b as i64); }
        if (init != 0) {
            p_cap_ex(x, init, env, caps);
        }
        return;
    }
    if (k == ST_ASSIGN) {
        var a: i64 = 0;
        var b: i64 = 0;
        unsafe {
            a = (na_at(x.na.v, st).a as i64);
            b = (na_at(x.na.v, st).b as i64);
        }
        p_cap_ex(x, a, env, caps);
        p_cap_ex(x, b, env, caps);
        return;
    }
    if (k == ST_EXPR) {
        var e: i64 = 0;
        unsafe { e = (na_at(x.na.v, st).a as i64); }
        p_cap_ex(x, e, env, caps);
        return;
    }
    if (k == ST_BLOCK || k == ST_UNSAFE) {
        var bl: i64 = 0;
        unsafe { bl = (na_at(x.na.v, st).l as i64); }
        p_cap_blk(x, bl, env, caps);
        return;
    }
    if (k == ST_IF) {
        var c: i64 = 0;
        var th: i64 = 0;
        var el: i64 = 0;
        unsafe {
            c = (na_at(x.na.v, st).a as i64);
            th = (na_at(x.na.v, st).l as i64);
            el = (na_at(x.na.v, st).l2 as i64);
        }
        p_cap_ex(x, c, env, caps);
        p_cap_blk(x, th, env, caps);
        p_cap_blk(x, el, env, caps);
        return;
    }
    if (k == ST_WHILE) {
        var c2: i64 = 0;
        var bl2: i64 = 0;
        unsafe {
            c2 = (na_at(x.na.v, st).a as i64);
            bl2 = (na_at(x.na.v, st).l as i64);
        }
        p_cap_ex(x, c2, env, caps);
        p_cap_blk(x, bl2, env, caps);
        return;
    }
    if (k == ST_LOOP) {
        var bl3: i64 = 0;
        unsafe { bl3 = (na_at(x.na.v, st).l as i64); }
        p_cap_blk(x, bl3, env, caps);
        return;
    }
    if (k == ST_FOR) {
        var sa: i64 = 0;
        var sb: i64 = 0;
        var fb: i64 = 0;
        unsafe {
            sa = (na_at(x.na.v, st).a as i64);
            sb = (na_at(x.na.v, st).b as i64);
            fb = (na_at(x.na.v, st).l as i64);
        }
        p_cap_ex(x, sa, env, caps);
        p_cap_ex(x, sb, env, caps);
        p_cap_blk(x, fb, env, caps);
        return;
    }
    if (k == ST_MATCH) {
        var sc: i64 = 0;
        var al: i64 = 0;
        unsafe {
            sc = (na_at(x.na.v, st).a as i64);
            al = (na_at(x.na.v, st).l as i64);
        }
        p_cap_ex(x, sc, env, caps);
        let na: i64 = lp_len(&mut x.lp, al);
        var ai: i64 = 0;
        while (ai < na) {
            let arm: i64 = lp_get(&mut x.lp, al, ai);
            var ab: i64 = 0;
            unsafe { ab = (na_at(x.na.v, arm).l as i64); }
            p_cap_blk(x, ab, env, caps);
            ai += 1;
        }
        return;
    }
    if (k == ST_LABEL) {
        var inr: i64 = 0;
        unsafe { inr = (na_at(x.na.v, st).a as i64); }
        p_cap_st(x, inr, env, caps);
        return;
    }
    if (k == ST_RETURN) {
        var rv: i64 = 0;
        unsafe { rv = (na_at(x.na.v, st).a as i64); }
        if (rv != 0) {
            p_cap_ex(x, rv, env, caps);
        }
        return;
    }
}

fn p_parse_struct_lit(x: &mut Fr, name: i64) -> i64 {
    if (p_expect_sym(x, "{") == 0) {
        return 0;
    }
    var fields: i64 = lp_add(&mut x.lp);
    while (!p_ch_at(x, x.i, 125)) {
        let f: i64 = p_name(x);
        if (x.ok == 0) {
            return 0;
        }
        if (p_expect_sym(x, ":") == 0) {
            return 0;
        }
        var v: i64 = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
        }
        let bt: i64 = p_named_ty(x, name);
        let ft: i64 = p_field_type(x, bt, f);
        if (ft != 0) {
            v = p_coerce_expr(x, v, ft);
            if (x.ok == 0) {
                return 0;
            }
        }
        let nf: i64 = lp_len(&mut x.lp, fields);
        var i: i64 = 0;
        while (i < nf) {
            if (lp_get(&mut x.lp, fields, i) == f) {
                p_msg_begin(x);
                p_msg_s(x, "duplicate field '");
                p_msg_id(x, f);
                p_msg_s(x, "' in ");
                p_msg_id(x, name);
                p_msg_s(x, " { ... }");
                return p_fail_plain(x);
            }
            i += 2;
        }
        lp_push(&mut x.lp, fields, f);
        lp_push(&mut x.lp, fields, v);
        if (!p_eat_sym(x, ",")) {
            break;
        }
    }
    if (p_expect_sym(x, "}") == 0) {
        return 0;
    }
    if (lp_len(&mut x.lp, fields) == 0) {
        p_msg_begin(x);
        p_msg_id(x, name);
        p_msg_s(x, " { } needs at least one field");
        return p_fail_plain(x);
    }
    let n: i64 = na_add(&mut x.na, EX_STRUCTLIT);
    unsafe {
        na_at(x.na.v, n).s = ( name) as i32;
        na_at(x.na.v, n).l = ( fields) as i32;
    }
    return n;
}

fn p_fail_plain(x: &mut Fr) -> i64 {
    sb_clear(&mut x.err);
    let p: ptr<u8> = x.tmp.p;
    let n: i64 = x.tmp.n;
    sb_put(&mut x.err, p, n);
    x.ok = 0;
    return 0;
}

fn p_is_local(x: &mut Fr, stack: i64, n: i64) -> bool {
    let ns: i64 = lp_len(&mut x.lp, stack);
    var i: i64 = 0;
    while (i < ns) {
        let l: i64 = lp_get(&mut x.lp, stack, i);
        let m: i64 = lp_len(&mut x.lp, l);
        var j: i64 = 0;
        while (j < m) {
            let v: i64 = lp_get(&mut x.lp, l, j);
            if (v == n) {
                return true;
            }
            j += 1;
        }
        i += 1;
    }
    return false;
}

fn p_stack_push(x: &mut Fr, stack: i64) -> i64 {
    let l: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, stack, l);
    return l;
}

fn p_rename_list(x: &mut Fr, l: i64, pfx: i64, names: &mut SetI, stack: i64) {
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 0;
    while (i < n) {
        let e: i64 = lp_get(&mut x.lp, l, i);
        p_rename_expr(x, e, pfx, names, stack);
        i += 1;
    }
}

fn p_rename_pairs(x: &mut Fr, l: i64, pfx: i64, names: &mut SetI, stack: i64) {
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 1;
    while (i < n) {
        let e: i64 = lp_get(&mut x.lp, l, i);
        p_rename_expr(x, e, pfx, names, stack);
        i += 2;
    }
}

fn p_rename_expr(x: &mut Fr, e: i64, pfx: i64, names: &mut SetI, stack: i64) {
    if (e == 0) {
        return;
    }
    var k: i32 = zero(i32);
    unsafe { k = na_at(x.na.v, e).k; }
    if (k == EX_VAR) {
        var n: i64 = zero(i64);
        unsafe { n = (na_at(x.na.v, e).s as i64); }
        if (!p_is_local(x, stack, n)) {
            let full: i64 = p_cat2(x, pfx, n);
            if (si_has(names, &mut x.sp, full)) {
                unsafe { na_at(x.na.v, e).s = ( full) as i32; }
            }
        }
    } else if (k == EX_FNREF || k == EX_CALL) {
        var n: i64 = zero(i64);
        unsafe { n = (na_at(x.na.v, e).s as i64); }
        let full: i64 = p_cat2(x, pfx, n);
        if (si_has(names, &mut x.sp, full)) {
            unsafe { na_at(x.na.v, e).s = ( full) as i32; }
        }
        if (k == EX_CALL) {
            var l: i64 = zero(i64);
            unsafe { l = (na_at(x.na.v, e).l as i64); }
            p_rename_list(x, l, pfx, names, stack);
        }
    } else if (k == EX_BIN || k == EX_INDEX) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, e).a as i64); }
        var b: i64 = zero(i64);
        unsafe { b = (na_at(x.na.v, e).b as i64); }
        p_rename_expr(x, a, pfx, names, stack);
        p_rename_expr(x, b, pfx, names, stack);
    } else if (k == EX_UN || k == EX_DEREF || k == EX_ADDR || k == EX_ADDRMUT || k == EX_BOXNEW || k == EX_CAST || k == EX_AWAIT || k == EX_POLL || k == EX_FIELD) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, e).a as i64); }
        p_rename_expr(x, a, pfx, names, stack);
    } else if (k == EX_CALLV || k == EX_METHOD) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, e).a as i64); }
        var l: i64 = zero(i64);
        unsafe { l = (na_at(x.na.v, e).l as i64); }
        p_rename_expr(x, a, pfx, names, stack);
        p_rename_list(x, l, pfx, names, stack);
    } else if (k == EX_STRUCTLIT) {
        var l: i64 = zero(i64);
        unsafe { l = (na_at(x.na.v, e).l as i64); }
        p_rename_pairs(x, l, pfx, names, stack);
    } else if (k == EX_ARRAYLIT || k == EX_TUPLELIT || k == EX_ENUMLIT) {
        var l: i64 = zero(i64);
        unsafe { l = (na_at(x.na.v, e).l as i64); }
        p_rename_list(x, l, pfx, names, stack);
    }
}

fn p_rename_stmts(x: &mut Fr, l: i64, pfx: i64, names: &mut SetI, stack: i64) {
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 0;
    while (i < n) {
        let st: i64 = lp_get(&mut x.lp, l, i);
        p_rename_stmt(x, st, pfx, names, stack);
        i += 1;
    }
}

fn p_rename_stmt(x: &mut Fr, st: i64, pfx: i64, names: &mut SetI, stack: i64) {
    var k: i32 = zero(i32);
    unsafe { k = na_at(x.na.v, st).k; }
    if (k == ST_LET) {
        var ini: i64 = zero(i64);
        unsafe { ini = (na_at(x.na.v, st).b as i64); }
        if (ini != 0) {
            p_rename_expr(x, ini, pfx, names, stack);
        }
        var nm: i64 = zero(i64);
        unsafe { nm = (na_at(x.na.v, st).s as i64); }
        let ns: i64 = lp_len(&mut x.lp, stack);
        let top: i64 = lp_get(&mut x.lp, stack, ns - 1);
        lp_push(&mut x.lp, top, nm);
    } else if (k == ST_ASSIGN) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, st).a as i64); }
        var b: i64 = zero(i64);
        unsafe { b = (na_at(x.na.v, st).b as i64); }
        p_rename_expr(x, a, pfx, names, stack);
        p_rename_expr(x, b, pfx, names, stack);
    } else if (k == ST_EXPR) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, st).a as i64); }
        p_rename_expr(x, a, pfx, names, stack);
    } else if (k == ST_BLOCK || k == ST_UNSAFE) {
        var l: i64 = zero(i64);
        unsafe { l = (na_at(x.na.v, st).l as i64); }
        let inner: i64 = p_stack_push(x, stack);
        p_rename_stmts(x, l, pfx, names, inner);
        lp_pop(&mut x.lp, stack);
    } else if (k == ST_IF) {
        var c: i64 = zero(i64);
        unsafe { c = (na_at(x.na.v, st).a as i64); }
        var th: i64 = zero(i64);
        unsafe { th = (na_at(x.na.v, st).l as i64); }
        var el: i64 = zero(i64);
        unsafe { el = (na_at(x.na.v, st).l2 as i64); }
        p_rename_expr(x, c, pfx, names, stack);
        let i1: i64 = p_stack_push(x, stack);
        p_rename_stmts(x, th, pfx, names, i1);
        lp_pop(&mut x.lp, stack);
        let i2: i64 = p_stack_push(x, stack);
        p_rename_stmts(x, el, pfx, names, i2);
        lp_pop(&mut x.lp, stack);
    } else if (k == ST_WHILE) {
        var c: i64 = zero(i64);
        unsafe { c = (na_at(x.na.v, st).a as i64); }
        var bl: i64 = zero(i64);
        unsafe { bl = (na_at(x.na.v, st).l as i64); }
        p_rename_expr(x, c, pfx, names, stack);
        let inner: i64 = p_stack_push(x, stack);
        p_rename_stmts(x, bl, pfx, names, inner);
        lp_pop(&mut x.lp, stack);
    } else if (k == ST_LOOP) {
        var bl: i64 = zero(i64);
        unsafe { bl = (na_at(x.na.v, st).l as i64); }
        let inner: i64 = p_stack_push(x, stack);
        p_rename_stmts(x, bl, pfx, names, inner);
        lp_pop(&mut x.lp, stack);
    } else if (k == ST_FOR) {
        var v: i64 = zero(i64);
        unsafe { v = (na_at(x.na.v, st).s as i64); }
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, st).a as i64); }
        var b: i64 = zero(i64);
        unsafe { b = (na_at(x.na.v, st).b as i64); }
        var bl: i64 = zero(i64);
        unsafe { bl = (na_at(x.na.v, st).l as i64); }
        p_rename_expr(x, a, pfx, names, stack);
        p_rename_expr(x, b, pfx, names, stack);
        let inner: i64 = p_stack_push(x, stack);
        lp_push(&mut x.lp, inner, v);
        p_rename_stmts(x, bl, pfx, names, inner);
        lp_pop(&mut x.lp, stack);
    } else if (k == ST_MATCH) {
        var sc: i64 = zero(i64);
        unsafe { sc = (na_at(x.na.v, st).a as i64); }
        var arms: i64 = zero(i64);
        unsafe { arms = (na_at(x.na.v, st).l as i64); }
        p_rename_expr(x, sc, pfx, names, stack);
        let na: i64 = lp_len(&mut x.lp, arms);
        var i: i64 = 0;
        while (i < na) {
            let arm: i64 = lp_get(&mut x.lp, arms, i);
            var pat: i64 = zero(i64);
            unsafe { pat = (na_at(x.na.v, arm).a as i64); }
            var body: i64 = zero(i64);
            unsafe { body = (na_at(x.na.v, arm).l as i64); }
            let inner: i64 = p_stack_push(x, stack);
            var pk: i32 = zero(i32);
            unsafe { pk = na_at(x.na.v, pat).k; }
            if (pk == PT_VARIANT) {
                var binds: i64 = zero(i64);
                unsafe { binds = (na_at(x.na.v, pat).l as i64); }
                let nb: i64 = lp_len(&mut x.lp, binds);
                var j: i64 = 0;
                while (j < nb) {
                    let bv: i64 = lp_get(&mut x.lp, binds, j);
                    lp_push(&mut x.lp, inner, bv);
                    j += 1;
                }
            }
            p_rename_stmts(x, body, pfx, names, inner);
            lp_pop(&mut x.lp, stack);
            i += 1;
        }
    } else if (k == ST_LABEL) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, st).a as i64); }
        p_rename_stmt(x, a, pfx, names, stack);
    } else if (k == ST_RETURN) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, st).a as i64); }
        if (a != 0) {
            p_rename_expr(x, a, pfx, names, stack);
        }
    }
}

fn p_rename_body(x: &mut Fr, body: i64, params: i64, pfx: i64, names: &mut SetI) {
    var stack: i64 = lp_add(&mut x.lp);
    let l0: i64 = lp_add(&mut x.lp);
    let np: i64 = lp_len(&mut x.lp, params);
    var i: i64 = 0;
    while (i < np) {
        let nm: i64 = lp_get(&mut x.lp, params, i);
        lp_push(&mut x.lp, l0, nm);
        i += 2;
    }
    lp_push(&mut x.lp, stack, l0);
    p_rename_stmts(x, body, pfx, names, stack);
}

fn p_rename_expr_top(x: &mut Fr, e: i64, pfx: i64, names: &mut SetI) {
    var stack: i64 = lp_add(&mut x.lp);
    let l0: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, stack, l0);
    p_rename_expr(x, e, pfx, names, stack);
}

fn p_place_ok(x: &mut Fr, e: i64) -> bool {
    var k: i32 = zero(i32);
    unsafe { k = na_at(x.na.v, e).k; }
    return k == EX_VAR || k == EX_FIELD || k == EX_INDEX || k == EX_DEREF;
}

fn p_first_seg(x: &mut Fr, id: i64) -> i64 {
    let p: ptr<u8> = sp_ptr(&mut x.sp, id);
    let n: i64 = sp_len(&mut x.sp, id);
    var i: i64 = 0;
    while (i + 1 < n) {
        var a: u8 = 0;
        var b: u8 = 0;
        unsafe {
            a = p[i];
            b = p[i + 1];
        }
        if (a == 95 && b == 95) {
            break;
        }
        i += 1;
    }
    return sp_intern(&mut x.sp, p, i);
}

fn p_fix_list(x: &mut Fr, l: i64, methods: i64) -> i32 {
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 0;
    while (i < n) {
        let e: i64 = lp_get(&mut x.lp, l, i);
        if (p_fix_expr(x, e, methods) == 0) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn p_fix_pairs(x: &mut Fr, l: i64, methods: i64) -> i32 {
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 1;
    while (i < n) {
        let e: i64 = lp_get(&mut x.lp, l, i);
        if (p_fix_expr(x, e, methods) == 0) {
            return 0;
        }
        i += 2;
    }
    return 1;
}

fn p_fix_expr(x: &mut Fr, e: i64, methods: i64) -> i32 {
    if (e == 0) {
        return 1;
    }
    var k: i32 = zero(i32);
    unsafe { k = na_at(x.na.v, e).k; }
    if (k == EX_BIN || k == EX_INDEX) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, e).a as i64); }
        var b: i64 = zero(i64);
        unsafe { b = (na_at(x.na.v, e).b as i64); }
        if (p_fix_expr(x, a, methods) == 0) {
            return 0;
        }
        if (p_fix_expr(x, b, methods) == 0) {
            return 0;
        }
    } else if (k == EX_UN || k == EX_DEREF || k == EX_ADDR || k == EX_ADDRMUT || k == EX_BOXNEW || k == EX_CAST || k == EX_AWAIT || k == EX_POLL || k == EX_FIELD) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, e).a as i64); }
        if (p_fix_expr(x, a, methods) == 0) {
            return 0;
        }
    } else if (k == EX_CALL || k == EX_ARRAYLIT || k == EX_TUPLELIT || k == EX_ENUMLIT) {
        var l: i64 = zero(i64);
        unsafe { l = (na_at(x.na.v, e).l as i64); }
        if (p_fix_list(x, l, methods) == 0) {
            return 0;
        }
    } else if (k == EX_CALLV) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, e).a as i64); }
        var l: i64 = zero(i64);
        unsafe { l = (na_at(x.na.v, e).l as i64); }
        if (p_fix_expr(x, a, methods) == 0) {
            return 0;
        }
        if (p_fix_list(x, l, methods) == 0) {
            return 0;
        }
    } else if (k == EX_STRUCTLIT) {
        var l: i64 = zero(i64);
        unsafe { l = (na_at(x.na.v, e).l as i64); }
        if (p_fix_pairs(x, l, methods) == 0) {
            return 0;
        }
    } else if (k == EX_METHOD) {
        var recv: i64 = zero(i64);
        unsafe { recv = (na_at(x.na.v, e).a as i64); }
        var nm: i64 = zero(i64);
        unsafe { nm = (na_at(x.na.v, e).s as i64); }
        var args: i64 = zero(i64);
        unsafe { args = (na_at(x.na.v, e).l as i64); }
        if (p_fix_expr(x, recv, methods) == 0) {
            return 0;
        }
        if (p_fix_list(x, args, methods) == 0) {
            return 0;
        }
        let nn: i64 = lp_len(&mut x.lp, methods);
        var hits: i64 = 0;
        var hit: i64 = 0;
        var i: i64 = 0;
        while (i < nn) {
            let m: i64 = lp_get(&mut x.lp, methods, i);
            if (m == nm) {
                hits += 1;
                hit = i;
            }
            i += 5;
        }
        if (hits == 0) {
            let callee: i64 = na_add(&mut x.na, EX_FIELD);
            unsafe {
                na_at(x.na.v, callee).a = ( recv) as i32;
                na_at(x.na.v, callee).s = ( nm) as i32;
            }
            unsafe {
                na_at(x.na.v, e).k = EX_CALLV;
                na_at(x.na.v, e).a = ( callee) as i32;
                na_at(x.na.v, e).s = ( 0) as i32;
                na_at(x.na.v, e).l = ( args) as i32;
            }
        } else if (hits == 1) {
            let full: i64 = lp_get(&mut x.lp, methods, hit + 1);
            let kind: i64 = lp_get(&mut x.lp, methods, hit + 2);
            var call: i64 = lp_add(&mut x.lp);
            var base: i64 = 0;
            if (kind == 1) {
                base = na_add(&mut x.na, EX_ADDRMUT);
            } else {
                base = na_add(&mut x.na, EX_ADDR);
            }
            unsafe { na_at(x.na.v, base).a = ( recv) as i32; }
            lp_push(&mut x.lp, call, base);
            let nargs: i64 = lp_len(&mut x.lp, args);
            var j: i64 = 0;
            while (j < nargs) {
                let av: i64 = lp_get(&mut x.lp, args, j);
                lp_push(&mut x.lp, call, av);
                j += 1;
            }
            unsafe {
                na_at(x.na.v, e).k = EX_CALL;
                na_at(x.na.v, e).s = ( full) as i32;
                na_at(x.na.v, e).a = ( 0) as i32;
                na_at(x.na.v, e).l = ( call) as i32;
            }
        } else {
            p_msg_begin(x);
            p_msg_s(x, "method '");
            p_msg_id(x, nm);
            p_msg_s(x, "' is defined by ");
            p_msg_num(x, hits);
            p_msg_s(x, " types (");
            var first: i32 = 1;
            var j2: i64 = 0;
            while (j2 < nn) {
                let m: i64 = lp_get(&mut x.lp, methods, j2);
                if (m == nm) {
                    if (first == 0) {
                        p_msg_s(x, ", ");
                    }
                    let full: i64 = lp_get(&mut x.lp, methods, j2 + 1);
                    let seg: i64 = p_first_seg(x, full);
                    p_msg_id(x, seg);
                    first = 0;
                }
                j2 += 5;
            }
            p_msg_s(x, "); write Type::");
            p_msg_id(x, nm);
            p_msg_s(x, "(...) to pick one");
            p_fail_plain(x);
            return 0;
        }
    }
    return 1;
}

fn p_fix_stmts(x: &mut Fr, l: i64, methods: i64) -> i32 {
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 0;
    while (i < n) {
        let st: i64 = lp_get(&mut x.lp, l, i);
        if (p_fix_stmt(x, st, methods) == 0) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn p_fix_stmt(x: &mut Fr, st: i64, methods: i64) -> i32 {
    var k: i32 = zero(i32);
    unsafe { k = na_at(x.na.v, st).k; }
    if (k == ST_LET) {
        var ini: i64 = zero(i64);
        unsafe { ini = (na_at(x.na.v, st).b as i64); }
        if (ini != 0) {
            var ik: i32 = zero(i32);
            unsafe { ik = na_at(x.na.v, ini).k; }
            if (ik == EX_METHOD) {
                var recv: i64 = zero(i64);
                unsafe { recv = (na_at(x.na.v, ini).a as i64); }
                if (!p_place_ok(x, recv)) {
                    p_msg_begin(x);
                    p_msg_s(x, "a method call needs a name to take its address");
                    p_fail_plain(x);
                    return 0;
                }
            }
            if (p_fix_expr(x, ini, methods) == 0) {
                return 0;
            }
        }
    } else if (k == ST_ASSIGN) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, st).a as i64); }
        var b: i64 = zero(i64);
        unsafe { b = (na_at(x.na.v, st).b as i64); }
        if (p_fix_expr(x, a, methods) == 0) {
            return 0;
        }
        if (p_fix_expr(x, b, methods) == 0) {
            return 0;
        }
    } else if (k == ST_EXPR) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, st).a as i64); }
        if (p_fix_expr(x, a, methods) == 0) {
            return 0;
        }
    } else if (k == ST_BLOCK || k == ST_UNSAFE) {
        var l: i64 = zero(i64);
        unsafe { l = (na_at(x.na.v, st).l as i64); }
        if (p_fix_stmts(x, l, methods) == 0) {
            return 0;
        }
    } else if (k == ST_IF) {
        var c: i64 = zero(i64);
        unsafe { c = (na_at(x.na.v, st).a as i64); }
        var th: i64 = zero(i64);
        unsafe { th = (na_at(x.na.v, st).l as i64); }
        var el: i64 = zero(i64);
        unsafe { el = (na_at(x.na.v, st).l2 as i64); }
        if (p_fix_expr(x, c, methods) == 0) {
            return 0;
        }
        if (p_fix_stmts(x, th, methods) == 0) {
            return 0;
        }
        if (p_fix_stmts(x, el, methods) == 0) {
            return 0;
        }
    } else if (k == ST_WHILE) {
        var c: i64 = zero(i64);
        unsafe { c = (na_at(x.na.v, st).a as i64); }
        var bl: i64 = zero(i64);
        unsafe { bl = (na_at(x.na.v, st).l as i64); }
        if (p_fix_expr(x, c, methods) == 0) {
            return 0;
        }
        if (p_fix_stmts(x, bl, methods) == 0) {
            return 0;
        }
    } else if (k == ST_LOOP) {
        var bl: i64 = zero(i64);
        unsafe { bl = (na_at(x.na.v, st).l as i64); }
        if (p_fix_stmts(x, bl, methods) == 0) {
            return 0;
        }
    } else if (k == ST_FOR) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, st).a as i64); }
        var b: i64 = zero(i64);
        unsafe { b = (na_at(x.na.v, st).b as i64); }
        var bl: i64 = zero(i64);
        unsafe { bl = (na_at(x.na.v, st).l as i64); }
        if (p_fix_expr(x, a, methods) == 0) {
            return 0;
        }
        if (p_fix_expr(x, b, methods) == 0) {
            return 0;
        }
        if (p_fix_stmts(x, bl, methods) == 0) {
            return 0;
        }
    } else if (k == ST_MATCH) {
        var sc: i64 = zero(i64);
        unsafe { sc = (na_at(x.na.v, st).a as i64); }
        var arms: i64 = zero(i64);
        unsafe { arms = (na_at(x.na.v, st).l as i64); }
        if (p_fix_expr(x, sc, methods) == 0) {
            return 0;
        }
        let na: i64 = lp_len(&mut x.lp, arms);
        var i: i64 = 0;
        while (i < na) {
            let arm: i64 = lp_get(&mut x.lp, arms, i);
            var body: i64 = zero(i64);
            unsafe { body = (na_at(x.na.v, arm).l as i64); }
            if (p_fix_stmts(x, body, methods) == 0) {
                return 0;
            }
            i += 1;
        }
    } else if (k == ST_LABEL) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, st).a as i64); }
        if (p_fix_stmt(x, a, methods) == 0) {
            return 0;
        }
    } else if (k == ST_RETURN) {
        var a: i64 = zero(i64);
        unsafe { a = (na_at(x.na.v, st).a as i64); }
        if (a != 0) {
            if (p_fix_expr(x, a, methods) == 0) {
                return 0;
            }
        }
    }
    return 1;
}

fn p_resolve_methods(x: &mut Fr, p: &mut Pr) -> i32 {
    let ms: i64 = x.methods;
    let nf: i64 = lp_len(&mut x.lp, p.f);
    var i: i64 = 0;
    while (i < nf) {
        let f: i64 = lp_get(&mut x.lp, p.f, i);
        var body: i64 = zero(i64);
        unsafe { body = (na_at(x.na.v, f).l3 as i64); }
        if (p_fix_stmts(x, body, ms) == 0) {
            return 0;
        }
        i += 1;
    }
    let ng: i64 = lp_len(&mut x.lp, p.g);
    var j: i64 = 0;
    while (j < ng) {
        let g: i64 = lp_get(&mut x.lp, p.g, j);
        var ini: i64 = zero(i64);
        unsafe { ini = (na_at(x.na.v, g).b as i64); }
        if (p_fix_expr(x, ini, ms) == 0) {
            return 0;
        }
        j += 1;
    }
    let nc: i64 = lp_len(&mut x.lp, p.c);
    var k: i64 = 0;
    while (k < nc) {
        let c: i64 = lp_get(&mut x.lp, p.c, k);
        var v: i64 = zero(i64);
        unsafe { v = (na_at(x.na.v, c).b as i64); }
        if (p_fix_expr(x, v, ms) == 0) {
            return 0;
        }
        k += 1;
    }
    return 1;
}

fn p_set_names(x: &mut Fr, ns: &mut SetI, l: i64) {
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 0;
    while (i < n) {
        let it: i64 = lp_get(&mut x.lp, l, i);
        var nm: i64 = zero(i64);
        unsafe { nm = (na_at(x.na.v, it).s as i64); }
        si_add(ns, &mut x.sp, nm);
        i += 1;
    }
}

fn p_ty_key_eq(x: &mut Fr, a: i64, b: i64) -> bool {
    var ka: Sb = sb_new(64);
    var kb: Sb = sb_new(64);
    p_type_key(x, a, &mut ka);
    p_type_key(x, b, &mut kb);
    var eq: bool = false;
    if (ka.n == kb.n) {
        var i: i64 = 0;
        var same: i32 = 1;
        while (i < ka.n) {
            var ca: u8 = 0;
            var cb: u8 = 0;
            unsafe {
                ca = ka.p[i];
                cb = kb.p[i];
            }
            if (ca != cb) {
                same = 0;
                break;
            }
            i += 1;
        }
        if (same == 1) {
            eq = true;
        }
    }
    sb_free(&mut ka);
    sb_free(&mut kb);
    return eq;
}

fn p_tm_subst(x: &mut Fr, tm: i64, tyname: i64) -> i64 {
    var params: i64 = zero(i64);
    var ret: i64 = zero(i64);
    var sk: i32 = 0;
    unsafe {
        params = (na_at(x.na.v, tm).l as i64);
        ret = (na_at(x.na.v, tm).a as i64);
        sk = na_at(x.na.v, tm).m;
    }
    let saved: i64 = x.implty;
    x.implty = tyname;
    var np: i64 = lp_add(&mut x.lp);
    let n: i64 = lp_len(&mut x.lp, params);
    var i: i64 = 0;
    while (i < n) {
        let pn: i64 = lp_get(&mut x.lp, params, i);
        let pt: i64 = lp_get(&mut x.lp, params, i + 1);
        let st: i64 = p_subst_self(x, pt);
        lp_push(&mut x.lp, np, pn);
        lp_push(&mut x.lp, np, st);
        i += 2;
    }
    let nr: i64 = p_subst_self(x, ret);
    x.implty = saved;
    let m: i64 = na_add(&mut x.na, IT_TM);
    unsafe {
        na_at(x.na.v, m).s = na_at(x.na.v, tm).s;
        na_at(x.na.v, m).l = ( np) as i32;
        na_at(x.na.v, m).a = ( nr) as i32;
        na_at(x.na.v, m).m = sk;
    }
    return m;
}

fn p_trait_has_impl(x: &mut Fr, tr: i64, ty: i64) -> bool {
    let n: i64 = lp_len(&mut x.lp, x.til);
    var i: i64 = 0;
    while (i < n) {
        let ta: i64 = lp_get(&mut x.lp, x.til, i);
        let tb: i64 = lp_get(&mut x.lp, x.til, i + 1);
        if (ta == tr && tb == ty) {
            return true;
        }
        i += 2;
    }
    return false;
}

fn p_ptr_to(x: &mut Fr, t: i64) -> i64 {
    let n: i64 = p_ty(x, TY_PTR);
    unsafe { na_at(x.na.v, n).a = ( t) as i32; }
    return n;
}

fn p_named_ty(x: &mut Fr, s: i64) -> i64 {
    let n: i64 = p_ty(x, TY_NAMED);
    unsafe { na_at(x.na.v, n).s = ( s) as i32; }
    return n;
}

fn p_cast_e(x: &mut Fr, e: i64, t: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_CAST);
    unsafe {
        na_at(x.na.v, n).a = ( e) as i32;
        na_at(x.na.v, n).b = ( t) as i32;
    }
    return n;
}

fn p_null_e(x: &mut Fr) -> i64 {
    return na_add(&mut x.na, EX_NULL);
}

fn p_fnref_e(x: &mut Fr, s: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_FNREF);
    unsafe { na_at(x.na.v, n).s = ( s) as i32; }
    return n;
}

fn p_call_e(x: &mut Fr, s: i64, args: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_CALL);
    unsafe {
        na_at(x.na.v, n).s = ( s) as i32;
        na_at(x.na.v, n).l = ( args) as i32;
    }
    return n;
}

fn p_deref_e(x: &mut Fr, e: i64) -> i64 {
    return p_wrap(x, EX_DEREF, e);
}

fn p_sizeof_e(x: &mut Fr, t: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_SIZEOF);
    unsafe { na_at(x.na.v, n).a = ( t) as i32; }
    return n;
}

fn p_structlit_e(x: &mut Fr, s: i64, fields: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_STRUCTLIT);
    unsafe {
        na_at(x.na.v, n).s = ( s) as i32;
        na_at(x.na.v, n).l = ( fields) as i32;
    }
    return n;
}

fn p_let_s(x: &mut Fr, mu: i32, name: i64, ty: i64, init: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, ST_LET);
    unsafe {
        na_at(x.na.v, n).m = mu;
        na_at(x.na.v, n).s = ( name) as i32;
        na_at(x.na.v, n).a = ( ty) as i32;
        na_at(x.na.v, n).b = ( init) as i32;
    }
    return n;
}

fn p_ret_s(x: &mut Fr, e: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, ST_RETURN);
    unsafe { na_at(x.na.v, n).a = ( e) as i32; }
    return n;
}

fn p_expr_s(x: &mut Fr, e: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, ST_EXPR);
    unsafe { na_at(x.na.v, n).a = ( e) as i32; }
    return n;
}

fn p_unsafe_s(x: &mut Fr, body: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, ST_UNSAFE);
    unsafe { na_at(x.na.v, n).l = ( body) as i32; }
    return n;
}

fn p_assign_s(x: &mut Fr, op: i64, lhs: i64, rhs: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, ST_ASSIGN);
    unsafe {
        na_at(x.na.v, n).s = ( op) as i32;
        na_at(x.na.v, n).a = ( lhs) as i32;
        na_at(x.na.v, n).b = ( rhs) as i32;
    }
    return n;
}

fn p_list1(x: &mut Fr, v: i64) -> i64 {
    var l: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, l, v);
    return l;
}

fn p_arg_name(x: &mut Fr, i: i64) -> i64 {
    var b: Sb = sb_new(16);
    sb_puts(&mut b, "a");
    sb_i64(&mut b, i);
    let p: ptr<u8> = b.p;
    let n: i64 = b.n;
    let id: i64 = sp_intern(&mut x.sp, p, n);
    sb_free(&mut b);
    return id;
}

fn p_mk_name(x: &mut Fr, pfx: ptr<u8>, parts: i64) -> i64 {
    var segs: i64 = lp_add(&mut x.lp);
    let pfxid: i64 = p_interns(x, pfx);
    lp_push(&mut x.lp, segs, pfxid);
    let n: i64 = lp_len(&mut x.lp, parts);
    var i: i64 = 0;
    while (i < n) {
        let seg: i64 = lp_get(&mut x.lp, parts, i);
        lp_push(&mut x.lp, segs, seg);
        i += 1;
    }
    return p_join(x, segs, "_");
}

fn p_has_genf(x: &mut Fr, name: i64) -> bool {
    let n: i64 = lp_len(&mut x.lp, x.genf);
    var i: i64 = 0;
    while (i < n) {
        let f: i64 = lp_get(&mut x.lp, x.genf, i);
        var s: i64 = 0;
        unsafe { s = (na_at(x.na.v, f).s as i64); }
        if (s == name) {
            return true;
        }
        i += 1;
    }
    return false;
}

fn p_ensure_malloc(x: &mut Fr) {
    let n: i64 = lp_len(&mut x.lp, x.genx);
    var i: i64 = 0;
    while (i < n) {
        let it: i64 = lp_get(&mut x.lp, x.genx, i);
        var s: i64 = 0;
        unsafe { s = (na_at(x.na.v, it).s as i64); }
        if (sp_eqc(&mut x.sp, s, "malloc")) {
            return;
        }
        i += 1;
    }
    var params: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, params, p_ty(x, TY_U64));
    let nm: i64 = p_interns(x, "malloc");
    let rt: i64 = p_ptr_u8(x);
    let it: i64 = na_add(&mut x.na, IT_EXTERN);
    unsafe {
        na_at(x.na.v, it).s = ( nm) as i32;
        na_at(x.na.v, it).l = ( params) as i32;
        na_at(x.na.v, it).a = ( rt) as i32;
    }
    lp_push(&mut x.lp, x.genx, it);
}

fn p_coerce_expr(x: &mut Fr, e: i64, want: i64) -> i64 {
    if (e == 0 || want == 0) {
        return e;
    }
    var wk: i32 = 0;
    unsafe { wk = na_at(x.na.v, want).k; }
    if (wk == TY_FAT) {
        let h: i64 = p_expr_hint(x, e);
        if (h != 0) {
            var hk: i32 = 0;
            unsafe { hk = na_at(x.na.v, h).k; }
            if (hk == TY_FAT) {
                return e;
            }
        }
        var ek: i32 = 0;
        unsafe { ek = na_at(x.na.v, e).k; }
        var nm: i64 = 0;
        if (ek == EX_FNREF || ek == EX_VAR) {
            unsafe { nm = (na_at(x.na.v, e).s as i64); }
        }
        if (nm != 0 && m64_has(&mut x.frmap, nm)) {
            var ps: i64 = 0;
            var rt: i64 = 0;
            unsafe {
                ps = (na_at(x.na.v, want).l as i64);
                rt = (na_at(x.na.v, want).a as i64);
            }
            return p_fat_from_fn(x, nm, ps, rt);
        }
        return e;
    }
    if (wk == TY_DYN) {
        let h2: i64 = p_expr_hint(x, e);
        if (h2 != 0) {
            var hk2: i32 = 0;
            unsafe { hk2 = na_at(x.na.v, h2).k; }
            if (hk2 == TY_DYN) {
                return e;
            }
        }
        var tr: i64 = 0;
        unsafe { tr = (na_at(x.na.v, want).s2 as i64); }
        return p_dyn_from(x, e, tr);
    }
    return e;
}

fn p_coerce_call(x: &mut Fr, name: i64, args: i64) -> i64 {
    let fpl: i64 = m64_get(&mut x.fmap, name, 0);
    if (fpl == 0) {
        return args;
    }
    let n: i64 = lp_len(&mut x.lp, args);
    if (lp_len(&mut x.lp, fpl) != n * 2) {
        return args;
    }
    var i: i64 = 0;
    while (i < n) {
        let a: i64 = lp_get(&mut x.lp, args, i);
        let w: i64 = lp_get(&mut x.lp, fpl, i * 2 + 1);
        let c: i64 = p_coerce_expr(x, a, w);
        if (x.ok == 0) {
            return 0;
        }
        lp_set(&mut x.lp, args, i, c);
        i += 1;
    }
    return args;
}

fn p_fat_from_fn(x: &mut Fr, name: i64, params: i64, ret: i64) -> i64 {
    let ft: i64 = p_fat_type(x, params, ret);
    var fname: i64 = 0;
    unsafe { fname = (na_at(x.na.v, ft).s as i64); }
    let an: i64 = p_cat2(x, p_interns(x, "__adopt"), p_num_id(x, x.adap));
    x.adap += 1;
    let env: i64 = p_interns(x, "__env");
    var wparams: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, wparams, env);
    lp_push(&mut x.lp, wparams, p_ptr_u8(x));
    var args: i64 = lp_add(&mut x.lp);
    let n: i64 = lp_len(&mut x.lp, params);
    var i: i64 = 0;
    while (i < n) {
        let aid: i64 = p_arg_name(x, i);
        let pt2: i64 = lp_get(&mut x.lp, params, i);
        let av: i64 = p_var(x, aid);
        lp_push(&mut x.lp, wparams, aid);
        lp_push(&mut x.lp, wparams, pt2);
        lp_push(&mut x.lp, args, av);
        i += 1;
    }
    let call: i64 = p_call_e(x, name, args);
    var body: i64 = lp_add(&mut x.lp);
    var vk: i32 = 0;
    unsafe { vk = na_at(x.na.v, ret).k; }
    if (vk == TY_VOID) {
        lp_push(&mut x.lp, body, p_expr_s(x, call));
        lp_push(&mut x.lp, body, p_ret_s(x, 0));
    } else {
        lp_push(&mut x.lp, body, p_ret_s(x, call));
    }
    let f: i64 = na_add(&mut x.na, IT_FN);
    unsafe {
        na_at(x.na.v, f).s = ( an) as i32;
        na_at(x.na.v, f).l2 = ( wparams) as i32;
        na_at(x.na.v, f).a = ( ret) as i32;
        na_at(x.na.v, f).l3 = ( body) as i32;
    }
    lp_push(&mut x.lp, x.genf, f);
    let code: i64 = p_interns(x, "code");
    let envf: i64 = p_interns(x, "env");
    let pu8: i64 = p_ptr_u8(x);
    var fields: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, fields, code);
    lp_push(&mut x.lp, fields, p_cast_e(x, p_fnref_e(x, an), pu8));
    lp_push(&mut x.lp, fields, envf);
    lp_push(&mut x.lp, fields, p_cast_e(x, p_null_e(x), pu8));
    return p_structlit_e(x, fname, fields);
}

fn p_dyn_from(x: &mut Fr, e: i64, tr: i64) -> i64 {
    let tit: i64 = m64_get(&mut x.tdefs, tr, 0);
    if (tit == 0) {
        p_msg_begin(x);
        p_msg_s(x, "unknown trait '");
        p_msg_id(x, tr);
        p_msg_s(x, "'");
        p_fail_plain(x);
        return 0;
    }
    let hint: i64 = p_expr_hint(x, e);
    if (hint == 0) {
        p_msg_begin(x);
        p_msg_s(x, "a value needs a known concrete type to become dyn ");
        p_msg_id(x, tr);
        p_fail_plain(x);
        return 0;
    }
    let src: i64 = p_peel(x, hint);
    var sk: i32 = 0;
    unsafe { sk = na_at(x.na.v, src).k; }
    if (sk != TY_NAMED) {
        p_msg_begin(x);
        p_msg_s(x, "dyn ");
        p_msg_id(x, tr);
        p_msg_s(x, " needs a struct value, got ");
        p_msg_tyk(x, src);
        p_fail_plain(x);
        return 0;
    }
    var tn: i64 = 0;
    unsafe { tn = (na_at(x.na.v, src).s as i64); }
    if (!p_trait_has_impl(x, tr, tn)) {
        p_msg_begin(x);
        p_msg_id(x, tn);
        p_msg_s(x, " does not implement ");
        p_msg_id(x, tr);
        p_fail_plain(x);
        return 0;
    }
    var tp: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, tp, tr);
    lp_push(&mut x.lp, tp, tn);
    let from_nm: i64 = p_mk_name(x, "__to", tp);
    if (!p_has_genf(x, from_nm)) {
        p_dyn_gen(x, tr, tn, tit, from_nm, src);
    }
    var args: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, args, e);
    return p_call_e(x, from_nm, args);
}

fn p_dyn_gen(x: &mut Fr, tr: i64, tn: i64, tit: i64, from_nm: i64, src: i64) {
    var tms: i64 = 0;
    unsafe { tms = (na_at(x.na.v, tit).l as i64); }
    let nmeth: i64 = lp_len(&mut x.lp, tms);
    let tnt: i64 = p_named_ty(x, tn);
    let ptn: i64 = p_ptr_to(x, tnt);
    let pu8: i64 = p_ptr_u8(x);
    let szx: i64 = p_sizeof_e(x, tnt);
    let vtn: i64 = p_pre_hash(x, "__Vt_", tr);
    let vtt: i64 = p_named_ty(x, vtn);
    let pvt: i64 = p_ptr_to(x, vtt);
    let szv: i64 = p_sizeof_e(x, vtt);
    var i: i64 = 0;
    while (i < nmeth) {
        let m: i64 = lp_get(&mut x.lp, tms, i);
        var mname: i64 = 0;
        var pl: i64 = 0;
        var rt: i64 = 0;
        var sk: i32 = 0;
        unsafe {
            mname = (na_at(x.na.v, m).s as i64);
            pl = (na_at(x.na.v, m).l as i64);
            rt = (na_at(x.na.v, m).a as i64);
            sk = na_at(x.na.v, m).m;
        }
        var fp: i64 = lp_add(&mut x.lp);
        lp_push(&mut x.lp, fp, tn);
        lp_push(&mut x.lp, fp, tr);
        lp_push(&mut x.lp, fp, mname);
        let full: i64 = p_join(x, fp, "__");
        var wp: i64 = lp_add(&mut x.lp);
        lp_push(&mut x.lp, wp, tr);
        lp_push(&mut x.lp, wp, tn);
        lp_push(&mut x.lp, wp, mname);
        let wn: i64 = p_mk_name(x, "__w", wp);
        var wparams: i64 = lp_add(&mut x.lp);
        let dnm: i64 = p_interns(x, "__d");
        lp_push(&mut x.lp, wparams, dnm);
        lp_push(&mut x.lp, wparams, pu8);
        let recv: i64 = p_deref_e(x, p_cast_e(x, p_var(x, dnm), ptn));
        var base: i64 = 0;
        if (sk == 1) {
            base = p_wrap(x, EX_ADDRMUT, recv);
        } else {
            base = p_wrap(x, EX_ADDR, recv);
        }
        var callargs: i64 = lp_add(&mut x.lp);
        lp_push(&mut x.lp, callargs, base);
        let np: i64 = lp_len(&mut x.lp, pl);
        var j: i64 = 0;
        while (j < np / 2) {
            let pn: i64 = lp_get(&mut x.lp, pl, j * 2);
            if (!sp_eqc(&mut x.sp, pn, "self")) {
                let aid: i64 = p_arg_name(x, j);
                let pt3: i64 = lp_get(&mut x.lp, pl, j * 2 + 1);
                let av3: i64 = p_var(x, aid);
                lp_push(&mut x.lp, wparams, aid);
                lp_push(&mut x.lp, wparams, pt3);
                lp_push(&mut x.lp, callargs, av3);
            }
            j += 1;
        }
        let call: i64 = p_call_e(x, full, callargs);
        var vk: i32 = 0;
        unsafe { vk = na_at(x.na.v, rt).k; }
        var body: i64 = lp_add(&mut x.lp);
        if (vk == TY_VOID) {
            lp_push(&mut x.lp, body, p_unsafe_s(x, p_list1(x, p_expr_s(x, call))));
            lp_push(&mut x.lp, body, p_ret_s(x, 0));
        } else {
            lp_push(&mut x.lp, body, p_unsafe_s(x, p_list1(x, p_ret_s(x, call))));
        }
        let f: i64 = na_add(&mut x.na, IT_FN);
        unsafe {
            na_at(x.na.v, f).s = ( wn) as i32;
            na_at(x.na.v, f).l2 = ( wparams) as i32;
            na_at(x.na.v, f).a = ( rt) as i32;
            na_at(x.na.v, f).l3 = ( body) as i32;
        }
        lp_push(&mut x.lp, x.genf, f);
        i += 1;
    }
    var vp: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, vp, tr);
    lp_push(&mut x.lp, vp, tn);
    let vtnm: i64 = p_mk_name(x, "__vt", vp);
    var vfields: i64 = lp_add(&mut x.lp);
    i = 0;
    while (i < nmeth) {
        let m2: i64 = lp_get(&mut x.lp, tms, i);
        var mn2: i64 = 0;
        unsafe { mn2 = (na_at(x.na.v, m2).s as i64); }
        var wp2: i64 = lp_add(&mut x.lp);
        lp_push(&mut x.lp, wp2, tr);
        lp_push(&mut x.lp, wp2, tn);
        lp_push(&mut x.lp, wp2, mn2);
        let wn2: i64 = p_mk_name(x, "__w", wp2);
        lp_push(&mut x.lp, vfields, mn2);
        lp_push(&mut x.lp, vfields, p_fnref_e(x, wn2));
        i += 1;
    }
    let vnm: i64 = p_interns(x, "__v");
    var vbody: i64 = lp_add(&mut x.lp);
    let vinit: i64 = p_cast_e(x, p_call_e(x, p_interns(x, "malloc"), p_list1(x, szv)), pvt);
    lp_push(&mut x.lp, vbody, p_let_s(x, 0, vnm, pvt, vinit));
    let vas: i64 = p_assign_s(x, p_interns(x, "="), p_deref_e(x, p_var(x, vnm)), p_structlit_e(x, vtn, vfields));
    lp_push(&mut x.lp, vbody, p_unsafe_s(x, p_list1(x, vas)));
    lp_push(&mut x.lp, vbody, p_ret_s(x, p_var(x, vnm)));
    let vempty: i64 = lp_add(&mut x.lp);
    let vf: i64 = na_add(&mut x.na, IT_FN);
    unsafe {
        na_at(x.na.v, vf).s = ( vtnm) as i32;
        na_at(x.na.v, vf).l2 = ( vempty) as i32;
        na_at(x.na.v, vf).a = ( pvt) as i32;
        na_at(x.na.v, vf).l3 = ( vbody) as i32;
    }
    lp_push(&mut x.lp, x.genf, vf);
    let dn: i64 = p_pre_hash(x, "__Dyn_", tr);
    let dynt: i64 = p_dyn_type(x, tr);
    let xnm: i64 = p_interns(x, "__x");
    let pnm: i64 = p_interns(x, "__p");
    var cparams: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, cparams, xnm);
    lp_push(&mut x.lp, cparams, src);
    var cbody: i64 = lp_add(&mut x.lp);
    let cinit: i64 = p_cast_e(x, p_call_e(x, p_interns(x, "malloc"), p_list1(x, szx)), ptn);
    lp_push(&mut x.lp, cbody, p_let_s(x, 0, pnm, ptn, cinit));
    let cas: i64 = p_assign_s(x, p_interns(x, "="), p_deref_e(x, p_var(x, pnm)), p_var(x, xnm));
    lp_push(&mut x.lp, cbody, p_unsafe_s(x, p_list1(x, cas)));
    var df: i64 = lp_add(&mut x.lp);
    let dnf: i64 = p_interns(x, "data");
    let dcode: i64 = p_cast_e(x, p_var(x, pnm), pu8);
    let vnmi: i64 = p_interns(x, "vt");
    let vlist: i64 = lp_add(&mut x.lp);
    let vcall: i64 = p_call_e(x, vtnm, vlist);
    lp_push(&mut x.lp, df, dnf);
    lp_push(&mut x.lp, df, dcode);
    lp_push(&mut x.lp, df, vnmi);
    lp_push(&mut x.lp, df, vcall);
    let dlit: i64 = p_structlit_e(x, dn, df);
    lp_push(&mut x.lp, cbody, p_ret_s(x, dlit));
    let cf: i64 = na_add(&mut x.na, IT_FN);
    unsafe {
        na_at(x.na.v, cf).s = ( from_nm) as i32;
        na_at(x.na.v, cf).l2 = ( cparams) as i32;
        na_at(x.na.v, cf).a = ( dynt) as i32;
        na_at(x.na.v, cf).l3 = ( cbody) as i32;
    }
    lp_push(&mut x.lp, x.genf, cf);
    p_ensure_malloc(x);
}

fn p_typed_method(x: &mut Fr, hint: i64, nm: i64) -> i64 {
    if (hint == 0) {
        return 0;
    }
    let base: i64 = p_peel(x, hint);
    var bk: i32 = 0;
    unsafe { bk = na_at(x.na.v, base).k; }
    if (bk != TY_NAMED) {
        return 0;
    }
    var ty: i64 = 0;
    unsafe { ty = (na_at(x.na.v, base).s as i64); }
    let ms: i64 = x.methods;
    let nn: i64 = lp_len(&mut x.lp, ms);
    var hits: i64 = 0;
    var first: i64 = 0;
    var any_tr: i32 = 0;
    var i: i64 = 0;
    while (i < nn) {
        let si: i64 = lp_get(&mut x.lp, ms, i);
        let st: i64 = lp_get(&mut x.lp, ms, i + 3);
        if (si == nm && st == ty) {
            if (hits == 0) {
                first = i;
            }
            hits += 1;
            let trm: i64 = lp_get(&mut x.lp, ms, i + 4);
            if (trm != 0) {
                any_tr = 1;
            }
        }
        i += 5;
    }
    if (hits == 0) {
        return 0;
    }
    if (hits > 1 && any_tr == 1) {
        let f0: i64 = lp_get(&mut x.lp, ms, first + 1);
        var diff: i64 = 0;
        var j: i64 = 0;
        while (j < nn) {
            let sj: i64 = lp_get(&mut x.lp, ms, j);
            let sjt: i64 = lp_get(&mut x.lp, ms, j + 3);
            if (sj == nm && sjt == ty) {
                let fj: i64 = lp_get(&mut x.lp, ms, j + 1);
                if (fj != f0) {
                    diff += 1;
                }
            }
            j += 5;
        }
        if (diff > 0) {
            return 0;
        }
    }
    if (hits == 1 && lp_get(&mut x.lp, ms, first + 4) == 0) {
        return 0;
    }
    return first;
}

fn p_parse_impl(x: &mut Fr, p: &mut Pr) -> i32 {
    var segs: i64 = lp_add(&mut x.lp);
    let s0: i64 = p_type_name(x);
    if (x.ok == 0) {
        return 0;
    }
    lp_push(&mut x.lp, segs, s0);
    while (p_at_sym(x, "::")) {
        p_bump(x);
        let s: i64 = p_type_name(x);
        if (x.ok == 0) {
            return 0;
        }
        lp_push(&mut x.lp, segs, s);
    }
    let nseg: i64 = lp_len(&mut x.lp, segs);
    var ty: i64 = 0;
    if (nseg == 1) {
        let h: i64 = lp_get(&mut x.lp, segs, 0);
        let pfx: i64 = x.pfx;
        ty = p_cat2(x, pfx, h);
    } else {
        ty = p_join(x, segs, "__");
    }
    if (p_eat_kw(x, "for")) {
        let tn: i64 = ty;
        let tit: i64 = m64_get(&mut x.tdefs, tn, 0);
        if (tit == 0) {
            p_msg_begin(x);
            p_msg_s(x, "unknown trait '");
            p_msg_id(x, tn);
            p_msg_s(x, "'");
            p_fail_plain(x);
            return 0;
        }
        var tsegs: i64 = lp_add(&mut x.lp);
        let t0: i64 = p_type_name(x);
        if (x.ok == 0) {
            return 0;
        }
        lp_push(&mut x.lp, tsegs, t0);
        while (p_at_sym(x, "::")) {
            p_bump(x);
            let s: i64 = p_type_name(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, tsegs, s);
        }
        var ity: i64 = 0;
        if (lp_len(&mut x.lp, tsegs) == 1) {
            ity = p_cat2(x, x.pfx, lp_get(&mut x.lp, tsegs, 0));
        } else {
            ity = p_join(x, tsegs, "__");
        }
        if (p_expect_sym(x, "{") == 0) {
            return 0;
        }
        var done: i64 = lp_add(&mut x.lp);
        var tms: i64 = zero(i64);
        unsafe { tms = (na_at(x.na.v, tit).l as i64); }
        let ms: i64 = x.methods;
        while (!p_ch_at(x, x.i, 125)) {
            if (p_kind(x, x.i) == TK_EOF) {
                p_msg_begin(x);
                p_msg_s(x, "unexpected end of file inside an 'impl' block");
                p_fail(x);
                return 0;
            }
            var is_async: i32 = 0;
            if (p_at_kw(x, "async")) {
                p_bump(x);
                is_async = 1;
            }
            if (p_expect_kw(x, "fn") == 0) {
                return 0;
            }
            let saved: i64 = x.implty;
            x.implty = ity;
            let f: i64 = p_parse_fn(x, is_async);
            x.implty = saved;
            if (x.ok == 0) {
                return 0;
            }
            var fname: i64 = zero(i64);
            unsafe { fname = (na_at(x.na.v, f).s as i64); }
            var wm: i64 = 0;
            let nm: i64 = lp_len(&mut x.lp, tms);
            var mi: i64 = 0;
            while (mi < nm) {
                let cand: i64 = lp_get(&mut x.lp, tms, mi);
                var cs: i64 = zero(i64);
                unsafe { cs = (na_at(x.na.v, cand).s as i64); }
                if (cs == fname) {
                    wm = cand;
                    break;
                }
                mi += 1;
            }
            if (wm == 0) {
                p_msg_begin(x);
                p_msg_s(x, "trait ");
                p_msg_id(x, tn);
                p_msg_s(x, " has no method '");
                p_msg_id(x, fname);
                p_msg_s(x, "'");
                p_fail_plain(x);
                return 0;
            }
            if (p_in_list(x, done, fname)) {
                p_msg_begin(x);
                p_msg_s(x, "trait ");
                p_msg_id(x, tn);
                p_msg_s(x, ": duplicate method '");
                p_msg_id(x, fname);
                p_msg_s(x, "'");
                p_fail_plain(x);
                return 0;
            }
            lp_push(&mut x.lp, done, fname);
            let want: i64 = p_tm_subst(x, wm, ity);
            var wps: i64 = zero(i64);
            var wret: i64 = zero(i64);
            unsafe {
                wps = (na_at(x.na.v, want).l as i64);
                wret = (na_at(x.na.v, want).a as i64);
            }
            var fparams: i64 = zero(i64);
            var fret: i64 = zero(i64);
            unsafe {
                fparams = (na_at(x.na.v, f).l2 as i64);
                fret = (na_at(x.na.v, f).a as i64);
            }
            let nfp: i64 = lp_len(&mut x.lp, fparams);
            let nwp: i64 = lp_len(&mut x.lp, wps);
            if (nfp != nwp) {
                p_msg_begin(x);
                p_msg_s(x, "trait ");
                p_msg_id(x, tn);
                p_msg_s(x, ": method '");
                p_msg_id(x, fname);
                p_msg_s(x, "' takes ");
                p_msg_num(x, nfp / 2);
                p_msg_s(x, " parameter(s); the trait declares ");
                p_msg_num(x, nwp / 2);
                p_fail_plain(x);
                return 0;
            }
            let np: i64 = lp_len(&mut x.lp, fparams);
            var pi: i64 = 0;
            while (pi < np) {
                let ga: i64 = lp_get(&mut x.lp, fparams, pi + 1);
                let wa: i64 = lp_get(&mut x.lp, wps, pi + 1);
                if (!p_ty_key_eq(x, ga, wa)) {
                    p_msg_begin(x);
                    p_msg_s(x, "trait ");
                    p_msg_id(x, tn);
                    p_msg_s(x, ": method '");
                    p_msg_id(x, fname);
                    p_msg_s(x, "' parameter ");
                    p_msg_num(x, pi / 2 + 1);
                    p_msg_s(x, " is ");
                    p_msg_tyk(x, ga);
                    p_msg_s(x, "; the trait declares ");
                    p_msg_tyk(x, wa);
                    p_fail_plain(x);
                    return 0;
                }
                pi += 2;
            }
            if (!p_ty_key_eq(x, fret, wret)) {
                p_msg_begin(x);
                p_msg_s(x, "trait ");
                p_msg_id(x, tn);
                p_msg_s(x, ": method '");
                p_msg_id(x, fname);
                p_msg_s(x, "' returns ");
                p_msg_tyk(x, fret);
                p_msg_s(x, "; the trait declares ");
                p_msg_tyk(x, wret);
                p_fail_plain(x);
                return 0;
            }
            var kind2: i64 = 0;
            if (lp_len(&mut x.lp, fparams) > 0) {
                let firstp: i64 = lp_get(&mut x.lp, fparams, 0);
                if (sp_eqc(&mut x.sp, firstp, "self")) {
                    let fty: i64 = lp_get(&mut x.lp, fparams, 1);
                    var fk: i32 = 0;
                    unsafe { fk = na_at(x.na.v, fty).k; }
                    if (fk == TY_REF) {
                        var mu: i32 = 0;
                        unsafe { mu = na_at(x.na.v, fty).m; }
                        if (mu == 1) {
                            kind2 = 1;
                        } else {
                            kind2 = 0;
                        }
                    } else {
                        p_msg_begin(x);
                        p_msg_s(x, "impl ");
                        p_msg_id(x, tn);
                        p_msg_s(x, " for ");
                        p_msg_id(x, ity);
                        p_msg_s(x, ": 'self' must be a reference");
                        p_fail_plain(x);
                        return 0;
                    }
                }
            }
            let sep1: i64 = p_interns(x, "__");
            let base: i64 = p_cat3(x, tn, sep1, fname);
            let full: i64 = p_cat3(x, ity, sep1, base);
            lp_push(&mut x.lp, ms, fname);
            lp_push(&mut x.lp, ms, full);
            lp_push(&mut x.lp, ms, kind2);
            lp_push(&mut x.lp, ms, ity);
            lp_push(&mut x.lp, ms, tn);
            unsafe { na_at(x.na.v, f).s = ( full) as i32; }
            m64_set(&mut x.fmap, full, fparams);
            m64_set(&mut x.frmap, full, fret);
            lp_push(&mut x.lp, p.f, f);
        }
        if (p_expect_sym(x, "}") == 0) {
            return 0;
        }
        var miss: i64 = lp_add(&mut x.lp);
        let nm2: i64 = lp_len(&mut x.lp, tms);
        var mj: i64 = 0;
        while (mj < nm2) {
            let cand2: i64 = lp_get(&mut x.lp, tms, mj);
            var cs2: i64 = zero(i64);
            unsafe { cs2 = (na_at(x.na.v, cand2).s as i64); }
            if (!p_in_list(x, done, cs2)) {
                lp_push(&mut x.lp, miss, cs2);
            }
            mj += 1;
        }
        if (lp_len(&mut x.lp, miss) > 0) {
            p_msg_begin(x);
            p_msg_s(x, "impl ");
            p_msg_id(x, tn);
            p_msg_s(x, " for ");
            p_msg_id(x, ity);
            p_msg_s(x, ": missing method(s) ");
            let joined: i64 = p_join(x, miss, ", ");
            p_msg_id(x, joined);
            p_fail_plain(x);
            return 0;
        }
        lp_push(&mut x.lp, x.til, tn);
        lp_push(&mut x.lp, x.til, ity);
        return 1;
    }
    if (p_expect_sym(x, "{") == 0) {
        return 0;
    }
    let ms: i64 = x.methods;
    while (!p_ch_at(x, x.i, 125)) {
        if (p_kind(x, x.i) == TK_EOF) {
            p_msg_begin(x);
            p_msg_s(x, "unexpected end of file inside an 'impl' block");
            p_fail(x);
            return 0;
        }
        var is_async: i32 = 0;
        if (p_at_kw(x, "async")) {
            p_bump(x);
            is_async = 1;
        }
        if (p_expect_kw(x, "fn") == 0) {
            return 0;
        }
        let saved: i64 = x.implty;
        x.implty = ty;
        let f: i64 = p_parse_fn(x, is_async);
        x.implty = saved;
        if (x.ok == 0) {
            return 0;
        }
        var fname: i64 = zero(i64);
        unsafe { fname = (na_at(x.na.v, f).s as i64); }
        let sep: i64 = p_interns(x, "__");
        let full: i64 = p_cat3(x, ty, sep, fname);
        var params: i64 = zero(i64);
        var ret_ty: i64 = zero(i64);
        unsafe {
            params = (na_at(x.na.v, f).l2 as i64);
            ret_ty = (na_at(x.na.v, f).a as i64);
        }
        let np: i64 = lp_len(&mut x.lp, params);
        if (np > 0) {
            let first: i64 = lp_get(&mut x.lp, params, 0);
            if (sp_eqc(&mut x.sp, first, "self")) {
                let fty: i64 = lp_get(&mut x.lp, params, 1);
                var fk: i32 = zero(i32);
                unsafe { fk = na_at(x.na.v, fty).k; }
                var kind: i64 = 0 - 1;
                if (fk == TY_REF) {
                    var mu: i32 = zero(i32);
                    unsafe { mu = na_at(x.na.v, fty).m; }
                    if (mu == 1) {
                        kind = 1;
                    } else {
                        kind = 0;
                    }
                }
                if (kind < 0) {
                    p_msg_begin(x);
                    p_msg_s(x, "impl ");
                    p_msg_id(x, ty);
                    p_msg_s(x, ": 'self' must be a reference, &");
                    p_msg_id(x, ty);
                    p_msg_s(x, " or &mut ");
                    p_msg_id(x, ty);
                    p_fail_plain(x);
                    return 0;
                }
                lp_push(&mut x.lp, ms, fname);
                lp_push(&mut x.lp, ms, full);
                lp_push(&mut x.lp, ms, kind);
                lp_push(&mut x.lp, ms, ty);
                lp_push(&mut x.lp, ms, 0);
            }
        }
        unsafe { na_at(x.na.v, f).s = ( full) as i32; }
        m64_set(&mut x.fmap, full, params);
        m64_set(&mut x.frmap, full, ret_ty);
        lp_push(&mut x.lp, p.f, f);
    }
    if (p_expect_sym(x, "}") == 0) {
        return 0;
    }
    return 1;
}

fn p_msg_tyk(x: &mut Fr, t: i64) {
    var b: Sb = sb_new(64);
    p_type_key(x, t, &mut b);
    let p: ptr<u8> = b.p;
    let n: i64 = b.n;
    sb_put(&mut x.tmp, p, n);
    sb_free(&mut b);
}

fn p_parse_mod(x: &mut Fr, p: &mut Pr) -> i32 {
    let name: i64 = p_name(x);
    if (x.ok == 0) {
        return 0;
    }
    if (p_expect_sym(x, "{") == 0) {
        return 0;
    }
    let saved: i64 = x.pfx;
    let us: i64 = p_interns(x, "__");
    let t0: i64 = p_cat2(x, saved, name);
    x.pfx = p_cat2(x, t0, us);
    var inner: Pr = p_pr_new(x);
    let lf: i64 = x.lifts;
    let lift_mark: i64 = lp_len(&mut x.lp, lf);
    let r: i32 = p_parse_items(x, &mut inner, 0);
    let pfx: i64 = x.pfx;
    x.pfx = saved;
    if (r == 0 || x.ok == 0) {
        return 0;
    }
    if (p_expect_sym(x, "}") == 0) {
        return 0;
    }
    var ns: SetI = si_new();
    p_set_names(x, &mut ns, inner.f);
    p_set_names(x, &mut ns, inner.c);
    p_set_names(x, &mut ns, inner.g);
    let nf: i64 = lp_len(&mut x.lp, inner.f);
    var i: i64 = 0;
    while (i < nf) {
        let f: i64 = lp_get(&mut x.lp, inner.f, i);
        var params: i64 = zero(i64);
        unsafe { params = (na_at(x.na.v, f).l2 as i64); }
        var body: i64 = zero(i64);
        unsafe { body = (na_at(x.na.v, f).l3 as i64); }
        p_rename_body(x, body, params, pfx, &mut ns);
        i += 1;
    }
    let nc: i64 = lp_len(&mut x.lp, inner.c);
    var ic: i64 = 0;
    while (ic < nc) {
        let c: i64 = lp_get(&mut x.lp, inner.c, ic);
        var v: i64 = zero(i64);
        unsafe { v = (na_at(x.na.v, c).b as i64); }
        p_rename_expr_top(x, v, pfx, &mut ns);
        ic += 1;
    }
    let ng: i64 = lp_len(&mut x.lp, inner.g);
    var ig: i64 = 0;
    while (ig < ng) {
        let g: i64 = lp_get(&mut x.lp, inner.g, ig);
        var v: i64 = zero(i64);
        unsafe { v = (na_at(x.na.v, g).b as i64); }
        p_rename_expr_top(x, v, pfx, &mut ns);
        ig += 1;
    }
    let total: i64 = lp_len(&mut x.lp, lf);
    var il: i64 = lift_mark;
    while (il < total) {
        let f: i64 = lp_get(&mut x.lp, lf, il);
        var params: i64 = zero(i64);
        unsafe { params = (na_at(x.na.v, f).l2 as i64); }
        var body: i64 = zero(i64);
        unsafe { body = (na_at(x.na.v, f).l3 as i64); }
        p_rename_body(x, body, params, pfx, &mut ns);
        il += 1;
    }
    var ip: i64 = lift_mark;
    while (ip < total) {
        let f: i64 = lp_get(&mut x.lp, lf, ip);
        lp_push(&mut x.lp, p.f, f);
        ip += 1;
    }
    while (lp_len(&mut x.lp, lf) > lift_mark) {
        lp_pop(&mut x.lp, lf);
    }
    p_list_extend(x, p.c, inner.c);
    p_list_extend(x, p.g, inner.g);
    p_list_extend(x, p.s, inner.s);
    p_list_extend(x, p.e, inner.e);
    p_list_extend(x, p.x, inner.x);
    p_list_extend(x, p.f, inner.f);
    si_free(&mut ns);
    return 1;
}

fn p_parse_items(x: &mut Fr, p: &mut Pr, top: i32) -> i32 {
    while (true) {
        if (p_kind(x, x.i) == TK_EOF) {
            if (top == 1) {
                break;
            }
            p_msg_begin(x);
            p_msg_s(x, "unexpected end of file inside a 'mod'");
            p_fail(x);
            return 0;
        }
        if (top == 0 && p_ch_at(x, x.i, 125)) {
            break;
        }
        if (p_eat_kw(x, "const")) {
            let it: i64 = p_parse_const(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, p.c, it);
        } else if (p_eat_kw(x, "struct")) {
            let it: i64 = p_parse_struct(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, p.s, it);
        } else if (p_eat_kw(x, "class")) {
            let it: i64 = p_parse_struct(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, p.s, it);
        } else if (p_eat_kw(x, "trait")) {
            let it: i64 = p_parse_trait(x);
            if (x.ok == 0) {
                return 0;
            }
        } else if (p_eat_kw(x, "enum")) {
            let it: i64 = p_parse_enum(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, p.e, it);
        } else if (p_eat_kw(x, "extern")) {
            var cext: i32 = 0;
            if (p_kind(x, x.i) == TK_STR && p_tok_eq(x, x.i, "C") && p_kind(x, x.i + 1) == TK_IDENT && p_tok_eq(x, x.i + 1, "fn")) {
                cext = 1;
            }
            if (cext == 1) {
                p_bump(x);
                p_bump(x);
                let f: i64 = p_parse_fn(x, 0);
                if (x.ok == 0) {
                    return 0;
                }
                unsafe { na_at(x.na.v, f).m = 1; }
                lp_push(&mut x.lp, p.f, f);
            } else {
                if (p_parse_extern(x, p.x) == 0) {
                    return 0;
                }
            }
        } else if (p_eat_kw(x, "static")) {
            let it: i64 = p_parse_static(x);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, p.g, it);
        } else if (p_eat_kw(x, "mod")) {
            if (p_parse_mod(x, p) == 0) {
                return 0;
            }
        } else if (p_eat_kw(x, "impl")) {
            if (p_parse_impl(x, p) == 0) {
                return 0;
            }
        } else if (p_eat_kw(x, "fn")) {
            let f: i64 = p_parse_fn(x, 0);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, p.f, f);
        } else if (p_at_kw(x, "async")) {
            p_bump(x);
            if (p_expect_kw(x, "fn") == 0) {
                return 0;
            }
            let f: i64 = p_parse_fn(x, 1);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, p.f, f);
        } else if (p_at_kw(x, "end")) {
            p_msg_begin(x);
            p_msg_s(x, "'end;' closes a block that opened without '{', and no block is open here");
            p_fail(x);
            return 0;
        } else {
            p_msg_begin(x);
            p_msg_s(x, "expected 'const', 'struct', 'class', 'trait', 'enum', 'extern', 'static', 'mod', 'impl' or 'fn', found ");
            p_msg_desc(x);
            p_fail(x);
            return 0;
        }
    }
    return 1;
}

fn fr_lex_take(f: &mut Fr) -> i32 {
    f.ok = 0;
    sb_clear(&mut f.err);
    let e: ptr<u8> = lex_err(&mut f.lx);
    sb_puts(&mut f.err, e);
    return 0;
}

fn fr_lex(f: &mut Fr, src: ptr<u8>, len: i64) -> i32 {
    f.ok = 1;
    if (lex_open(&mut f.lx, src, len) == 0) {
        return fr_lex_take(f);
    }
    f.i = 0;
    return 1;
}

fn fr_lex_all(f: &mut Fr, src: ptr<u8>, len: i64) -> i32 {
    f.ok = 1;
    if (lex_run(&mut f.lx, src, len) == 0) {
        return fr_lex_take(f);
    }
    f.i = 0;
    return 1;
}

fn fr_parse(f: &mut Fr) -> Pr {
    var p: Pr = p_pr_new(f);
    if (p_parse_items(f, &mut p, 1) == 0) {
        return p;
    }
    let lf: i64 = f.lifts;
    let total: i64 = lp_len(&mut f.lp, lf);
    var i: i64 = 0;
    while (i < total) {
        let d: i64 = lp_get(&mut f.lp, lf, i);
        lp_push(&mut f.lp, p.f, d);
        i += 1;
    }
    while (lp_len(&mut f.lp, lf) > 0) {
        lp_pop(&mut f.lp, lf);
    }
    let nt: i64 = lp_len(&mut f.lp, f.trl);
    var ti: i64 = 0;
    while (ti < nt) {
        let it: i64 = lp_get(&mut f.lp, f.trl, ti);
        var nm: i64 = 0;
        unsafe { nm = (na_at(f.na.v, it).s as i64); }
        p_dyn_type(f, nm);
        ti += 1;
    }
    p_extend(f, p.s, f.fatl);
    p_extend(f, p.s, f.synl);
    p_extend(f, p.s, f.vtl);
    p_extend(f, p.s, f.dynl);
    p_extend(f, p.x, f.genx);
    p_extend(f, p.f, f.genf);
    p_resolve_methods(f, &mut p);
    return p;
}

fn p_extend(x: &mut Fr, dst: i64, src: i64) {
    if (dst == 0 || src == 0) {
        return;
    }
    let n: i64 = lp_len(&mut x.lp, src);
    var i: i64 = 0;
    while (i < n) {
        let sv: i64 = lp_get(&mut x.lp, src, i);
        lp_push(&mut x.lp, dst, sv);
        i += 1;
    }
}

fn fr_emit(f: &mut Fr, p: &mut Pr, out: &mut Sb) {
    var a: Na = zero(Na);
    a = f.na;
    var l: Lp = zero(Lp);
    l = f.lp;
    var s: Sp = zero(Sp);
    s = f.sp;
    prog_w(&mut a, &mut l, &mut s, out, p);
}

fn fr_err_ptr(f: &mut Fr) -> ptr<u8> {
    return f.err.p;
}

fn fr_err_len(f: &mut Fr) -> i64 {
    return f.err.n;
}

fn fr_ok(f: &mut Fr) -> i32 {
    return f.ok;
}

fn p_struct_add(x: &mut Fr, name: i64, fields: i64) -> i64 {
    let it: i64 = na_add(&mut x.na, IT_STRUCT);
    unsafe {
        na_at(x.na.v, it).s = ( name) as i32;
        na_at(x.na.v, it).l = ( fields) as i32;
    }
    return it;
}

fn p_ptr_u8(x: &mut Fr) -> i64 {
    let u: i64 = p_ty(x, TY_U8);
    let p: i64 = p_ty(x, TY_PTR);
    unsafe { na_at(x.na.v, p).a = ( u) as i32; }
    return p;
}

fn p_fn_ty(x: &mut Fr, params: i64, ret: i64) -> i64 {
    let n: i64 = p_ty(x, TY_FN);
    unsafe {
        na_at(x.na.v, n).l = ( params) as i32;
        na_at(x.na.v, n).a = ( ret) as i32;
    }
    return n;
}

fn p_fnv(x: &mut Fr, p: ptr<u8>, n: i64) -> u64 {
    var h: u64 = (0 as u64) - (3750763034362895579 as u64);
    var i: i64 = 0;
    while (i < n) {
        var c: u8 = 0;
        unsafe { c = p[i]; }
        h = (h ^ (c as u64)) * 1099511628211;
        i += 1;
    }
    return h;
}

fn p_hex16(b: &mut Sb, h: u64) {
    var i: i64 = 15;
    while (i >= 0) {
        let nib: u64 = (h >> ((i as u64) * 4)) & 15;
        var d: u8 = 0;
        if (nib < 10) {
            d = (48 + nib) as u8;
        } else {
            d = (87 + nib) as u8;
        }
        sb_putc(b, d);
        i -= 1;
    }
}

fn p_pre_hash(x: &mut Fr, pre: ptr<u8>, id: i64) -> i64 {
    let sp: ptr<u8> = sp_ptr(&mut x.sp, id);
    let sn: i64 = sp_len(&mut x.sp, id);
    let h: u64 = p_fnv(x, sp, sn);
    sb_clear(&mut x.tmp);
    sb_puts(&mut x.tmp, pre);
    p_hex16(&mut x.tmp, h);
    let a: ptr<u8> = x.tmp.p;
    let n: i64 = x.tmp.n;
    return sp_intern(&mut x.sp, a, n);
}

fn p_type_key(x: &mut Fr, t: i64, b: &mut Sb) {
    var k: i32 = 0;
    unsafe { k = na_at(x.na.v, t).k; }
    if (k == TY_I8) {
        sb_puts(b, "i8");
    } else if (k == TY_I16) {
        sb_puts(b, "i16");
    } else if (k == TY_I32) {
        sb_puts(b, "i32");
    } else if (k == TY_I64) {
        sb_puts(b, "i64");
    } else if (k == TY_U8) {
        sb_puts(b, "u8");
    } else if (k == TY_U16) {
        sb_puts(b, "u16");
    } else if (k == TY_U32) {
        sb_puts(b, "u32");
    } else if (k == TY_U64) {
        sb_puts(b, "u64");
    } else if (k == TY_F32) {
        sb_puts(b, "f32");
    } else if (k == TY_F64) {
        sb_puts(b, "f64");
    } else if (k == TY_BOOL) {
        sb_puts(b, "bool");
    } else if (k == TY_VOID) {
        sb_puts(b, "void");
    } else if (k == TY_INFER) {
        sb_putc(b, 63);
    } else if (k == TY_SELF) {
        sb_puts(b, "self");
    } else if (k == TY_PTR || k == TY_HEAP || k == TY_TASK) {
        if (k == TY_PTR) {
            sb_putc(b, 112);
        } else if (k == TY_HEAP) {
            sb_putc(b, 98);
        } else {
            sb_putc(b, 107);
        }
        var c: i64 = 0;
        unsafe { c = (na_at(x.na.v, t).a as i64); }
        p_type_key(x, c, b);
    } else if (k == TY_REF) {
        var mu: i32 = 0;
        unsafe { mu = na_at(x.na.v, t).m; }
        if (mu == 1) {
            sb_putc(b, 109);
        } else {
            sb_putc(b, 114);
        }
        var c: i64 = 0;
        unsafe { c = (na_at(x.na.v, t).a as i64); }
        p_type_key(x, c, b);
    } else if (k == TY_ARRAY) {
        sb_putc(b, 97);
        var c: i64 = 0;
        var sz: i64 = 0;
        var nm: i64 = 0;
        var us: i32 = 0;
        unsafe {
            c = (na_at(x.na.v, t).a as i64);
            sz = na_at(x.na.v, t).n;
            nm = (na_at(x.na.v, t).s as i64);
            us = na_at(x.na.v, t).m;
        }
        if (us == 1) {
            sp_put(&mut x.sp, b, nm);
        } else {
            sb_i64(b, sz);
        }
        p_type_key(x, c, b);
    } else if (k == TY_NAMED || k == TY_PARAM) {
        if (k == TY_NAMED) {
            sb_putc(b, 110);
        } else {
            sb_putc(b, 118);
        }
        var nm2: i64 = 0;
        unsafe { nm2 = (na_at(x.na.v, t).s as i64); }
        sp_put(&mut x.sp, b, nm2);
    } else if (k == TY_DYN) {
        sb_putc(b, 100);
        var tr: i64 = 0;
        unsafe { tr = (na_at(x.na.v, t).s2 as i64); }
        sp_put(&mut x.sp, b, tr);
    } else if (k == TY_TUPLE) {
        sb_putc(b, 116);
        var l: i64 = 0;
        unsafe { l = (na_at(x.na.v, t).l as i64); }
        let n: i64 = lp_len(&mut x.lp, l);
        var i: i64 = 0;
        while (i < n) {
            p_type_key(x, lp_get(&mut x.lp, l, i), b);
            sb_putc(b, 95);
            i += 1;
        }
    } else if (k == TY_FN || k == TY_FNC || k == TY_FAT) {
        if (k == TY_FN) {
            sb_putc(b, 102);
        } else if (k == TY_FNC) {
            sb_putc(b, 99);
        } else {
            sb_putc(b, 70);
        }
        var l2: i64 = 0;
        var r2: i64 = 0;
        unsafe {
            l2 = (na_at(x.na.v, t).l as i64);
            r2 = (na_at(x.na.v, t).a as i64);
        }
        let n2: i64 = lp_len(&mut x.lp, l2);
        var j: i64 = 0;
        while (j < n2) {
            p_type_key(x, lp_get(&mut x.lp, l2, j), b);
            sb_putc(b, 95);
            j += 1;
        }
        p_type_key(x, r2, b);
    }
}

fn p_fat_type(x: &mut Fr, params: i64, ret: i64) -> i64 {
    sb_clear(&mut x.tmp);
    sb_puts(&mut x.tmp, "Fn(");
    let np: i64 = lp_len(&mut x.lp, params);
    var i: i64 = 0;
    while (i < np) {
        let pt: i64 = lp_get(&mut x.lp, params, i);
        p_type_key(x, pt, &mut x.tmp);
        sb_putc(&mut x.tmp, 44);
        i += 1;
    }
    sb_puts(&mut x.tmp, ")->");
    p_type_key(x, ret, &mut x.tmp);
    let kp: ptr<u8> = x.tmp.p;
    let kn: i64 = x.tmp.n;
    let h: u64 = p_fnv(x, kp, kn);
    sb_clear(&mut x.tmp);
    sb_puts(&mut x.tmp, "__Fn_");
    p_hex16(&mut x.tmp, h);
    let a: ptr<u8> = x.tmp.p;
    let n: i64 = x.tmp.n;
    let nm: i64 = sp_intern(&mut x.sp, a, n);
    if (!m64_has(&mut x.fatm, nm)) {
        var fields: i64 = lp_add(&mut x.lp);
        let code: i64 = p_interns(x, "code");
        let env: i64 = p_interns(x, "env");
        let pu8: i64 = p_ptr_u8(x);
        lp_push(&mut x.lp, fields, code);
        lp_push(&mut x.lp, fields, pu8);
        lp_push(&mut x.lp, fields, env);
        lp_push(&mut x.lp, fields, pu8);
        let it: i64 = p_struct_add(x, nm, fields);
        lp_push(&mut x.lp, x.fatl, it);
        let sig: i64 = lp_add(&mut x.lp);
        lp_push(&mut x.lp, sig, params);
        lp_push(&mut x.lp, sig, ret);
        m64_set(&mut x.fatm, nm, sig);
    }
    let t: i64 = p_ty(x, TY_FAT);
    unsafe {
        na_at(x.na.v, t).s = ( nm) as i32;
        na_at(x.na.v, t).l = ( params) as i32;
        na_at(x.na.v, t).a = ( ret) as i32;
    }
    return t;
}

fn p_fn_ref_list(x: &mut Fr, pl: i64) -> i64 {
    var out: i64 = lp_add(&mut x.lp);
    let n: i64 = lp_len(&mut x.lp, pl);
    var i: i64 = 0;
    while (i < n) {
        let pn: i64 = lp_get(&mut x.lp, pl, i);
        if (!sp_eqc(&mut x.sp, pn, "self")) {
            let pt: i64 = lp_get(&mut x.lp, pl, i + 1);
            lp_push(&mut x.lp, out, pt);
        }
        i += 2;
    }
    return out;
}

fn p_dyn_type(x: &mut Fr, tr: i64) -> i64 {
    let vtn: i64 = p_pre_hash(x, "__Vt_", tr);
    if (!m64_has(&mut x.vtst, vtn)) {
        var fields: i64 = lp_add(&mut x.lp);
        let tit: i64 = m64_get(&mut x.tdefs, tr, 0);
        if (tit != 0) {
            var ms: i64 = 0;
            unsafe { ms = (na_at(x.na.v, tit).l as i64); }
            let nm: i64 = lp_len(&mut x.lp, ms);
            var i: i64 = 0;
            while (i < nm) {
                let m: i64 = lp_get(&mut x.lp, ms, i);
                var fname: i64 = 0;
                var pl: i64 = 0;
                var rt: i64 = 0;
                unsafe {
                    fname = (na_at(x.na.v, m).s as i64);
                    pl = (na_at(x.na.v, m).l as i64);
                    rt = (na_at(x.na.v, m).a as i64);
                }
                var ps: i64 = lp_add(&mut x.lp);
                lp_push(&mut x.lp, ps, p_ptr_u8(x));
                let rest: i64 = p_fn_ref_list(x, pl);
                let nr: i64 = lp_len(&mut x.lp, rest);
                var j: i64 = 0;
                while (j < nr) {
                    let rv: i64 = lp_get(&mut x.lp, rest, j);
                    lp_push(&mut x.lp, ps, rv);
                    j += 1;
                }
                lp_push(&mut x.lp, fields, fname);
                lp_push(&mut x.lp, fields, p_fn_ty(x, ps, rt));
                i += 1;
            }
        }
        let it: i64 = p_struct_add(x, vtn, fields);
        lp_push(&mut x.lp, x.vtl, it);
        m64_set(&mut x.vtst, vtn, 1);
    }
    let dynn: i64 = p_pre_hash(x, "__Dyn_", tr);
    if (!m64_has(&mut x.dynst, dynn)) {
        var fields2: i64 = lp_add(&mut x.lp);
        let data: i64 = p_interns(x, "data");
        let vt: i64 = p_interns(x, "vt");
        let pvt: i64 = p_ty(x, TY_PTR);
        let vtn2: i64 = p_ty(x, TY_NAMED);
        unsafe {
            na_at(x.na.v, vtn2).s = ( vtn) as i32;
            na_at(x.na.v, pvt).a = ( vtn2) as i32;
        }
        lp_push(&mut x.lp, fields2, data);
        lp_push(&mut x.lp, fields2, p_ptr_u8(x));
        lp_push(&mut x.lp, fields2, vt);
        lp_push(&mut x.lp, fields2, pvt);
        let it2: i64 = p_struct_add(x, dynn, fields2);
        lp_push(&mut x.lp, x.dynl, it2);
        m64_set(&mut x.dynst, dynn, 1);
    }
    let t: i64 = p_ty(x, TY_DYN);
    unsafe {
        na_at(x.na.v, t).s = ( dynn) as i32;
        na_at(x.na.v, t).s2 = ( tr) as i32;
    }
    return t;
}

fn p_subst_self(x: &mut Fr, t: i64) -> i64 {
    if (t == 0 || x.implty == 0) {
        return t;
    }
    var k: i32 = 0;
    unsafe { k = na_at(x.na.v, t).k; }
    if (k == TY_SELF) {
        let n: i64 = p_ty(x, TY_NAMED);
        unsafe { na_at(x.na.v, n).s = ( x.implty) as i32; }
        return n;
    }
    if (k == TY_PTR || k == TY_REF || k == TY_HEAP || k == TY_TASK) {
        var c: i64 = 0;
        var mu: i32 = 0;
        unsafe {
            c = (na_at(x.na.v, t).a as i64);
            mu = na_at(x.na.v, t).m;
        }
        let nc: i64 = p_subst_self(x, c);
        let n2: i64 = p_ty(x, k);
        unsafe {
            na_at(x.na.v, n2).a = ( nc) as i32;
            na_at(x.na.v, n2).m = mu;
        }
        return n2;
    }
    if (k == TY_ARRAY) {
        var c2: i64 = 0;
        var sz: i64 = 0;
        var nm: i64 = 0;
        var us: i32 = 0;
        unsafe {
            c2 = (na_at(x.na.v, t).a as i64);
            sz = na_at(x.na.v, t).n;
            nm = (na_at(x.na.v, t).s as i64);
            us = na_at(x.na.v, t).m;
        }
        let nc2: i64 = p_subst_self(x, c2);
        let n3: i64 = p_ty(x, TY_ARRAY);
        unsafe {
            na_at(x.na.v, n3).a = ( nc2) as i32;
            na_at(x.na.v, n3).n = sz;
            na_at(x.na.v, n3).s = ( nm) as i32;
            na_at(x.na.v, n3).m = us;
        }
        return n3;
    }
    if (k == TY_TUPLE || k == TY_FN || k == TY_FNC || k == TY_FAT) {
        var l: i64 = 0;
        var r: i64 = 0;
        unsafe {
            l = (na_at(x.na.v, t).l as i64);
            r = (na_at(x.na.v, t).a as i64);
        }
        var nl: i64 = lp_add(&mut x.lp);
        let n: i64 = lp_len(&mut x.lp, l);
        var i: i64 = 0;
        while (i < n) {
            let item: i64 = lp_get(&mut x.lp, l, i);
            let sub: i64 = p_subst_self(x, item);
            lp_push(&mut x.lp, nl, sub);
            i += 1;
        }
        var nr: i64 = 0;
        if (k != TY_TUPLE) {
            nr = p_subst_self(x, r);
        }
        if (k == TY_FAT) {
            return p_fat_type(x, nl, nr);
        }
        let n4: i64 = p_ty(x, k);
        unsafe {
            na_at(x.na.v, n4).l = ( nl) as i32;
            na_at(x.na.v, n4).a = ( nr) as i32;
        }
        return n4;
    }
    return t;
}

fn p_peel(x: &mut Fr, t: i64) -> i64 {
    var cur: i64 = t;
    while (true) {
        var k: i32 = 0;
        unsafe { k = na_at(x.na.v, cur).k; }
        if (k == TY_REF || k == TY_PTR || k == TY_HEAP) {
            unsafe { cur = (na_at(x.na.v, cur).a as i64); }
        } else {
            return cur;
        }
    }
}

fn p_field_type(x: &mut Fr, base: i64, field: i64) -> i64 {
    let b: i64 = p_peel(x, base);
    var k: i32 = 0;
    unsafe { k = na_at(x.na.v, b).k; }
    if (k == TY_NAMED) {
        var nm: i64 = 0;
        unsafe { nm = (na_at(x.na.v, b).s as i64); }
        let fl: i64 = m64_get(&mut x.smap, nm, 0);
        if (fl == 0) {
            return 0;
        }
        let n: i64 = lp_len(&mut x.lp, fl);
        var i: i64 = 0;
        while (i < n) {
            if (lp_get(&mut x.lp, fl, i) == field) {
                return lp_get(&mut x.lp, fl, i + 1);
            }
            i += 2;
        }
        return 0;
    }
    if (k == TY_TUPLE) {
        var l: i64 = 0;
        unsafe { l = (na_at(x.na.v, b).l as i64); }
        let n2: i64 = lp_len(&mut x.lp, l);
        var j: i64 = 0;
        while (j < n2) {
            if (p_num_id(x, j) == field) {
                return lp_get(&mut x.lp, l, j);
            }
            j += 1;
        }
        return 0;
    }
    return 0;
}

fn p_fn_value_type(x: &mut Fr, name: i64) -> i64 {
    let rt: i64 = m64_get(&mut x.frmap, name, 0);
    if (rt == 0) {
        return 0;
    }
    let ps: i64 = m64_get(&mut x.fmap, name, 0);
    if (ps == 0) {
        return 0;
    }
    return p_fn_ty(x, ps, rt);
}

fn p_push_scope(x: &mut Fr) {
    let s: i64 = lp_add(&mut x.lp);
    lp_push(&mut x.lp, x.scp, s);
}

fn p_pop_scope(x: &mut Fr) {
    lp_pop(&mut x.lp, x.scp);
}

fn p_bind(x: &mut Fr, name: i64, ty: i64) {
    let ns: i64 = lp_len(&mut x.lp, x.scp);
    if (ns == 0) {
        return;
    }
    let s: i64 = lp_get(&mut x.lp, x.scp, ns - 1);
    let n: i64 = lp_len(&mut x.lp, s);
    var i: i64 = 0;
    while (i < n) {
        if (lp_get(&mut x.lp, s, i) == name) {
            lp_set(&mut x.lp, s, i + 1, ty);
            return;
        }
        i += 2;
    }
    lp_push(&mut x.lp, s, name);
    lp_push(&mut x.lp, s, ty);
}

fn p_lookup_binding(x: &mut Fr, name: i64) -> i64 {
    let ns: i64 = lp_len(&mut x.lp, x.scp);
    var j: i64 = ns - 1;
    while (j >= 0) {
        let s: i64 = lp_get(&mut x.lp, x.scp, j);
        let n: i64 = lp_len(&mut x.lp, s);
        var i: i64 = n - 2;
        while (i >= 0) {
            if (lp_get(&mut x.lp, s, i) == name) {
                return lp_get(&mut x.lp, s, i + 1);
            }
            i -= 2;
        }
        j -= 1;
    }
    return 0;
}

fn p_is_cmp(x: &mut Fr, op: i64) -> i32 {
    if (sp_eqc(&mut x.sp, op, "==")) {
        return 1;
    }
    if (sp_eqc(&mut x.sp, op, "!=")) {
        return 1;
    }
    if (sp_eqc(&mut x.sp, op, "<")) {
        return 1;
    }
    if (sp_eqc(&mut x.sp, op, "<=")) {
        return 1;
    }
    if (sp_eqc(&mut x.sp, op, ">")) {
        return 1;
    }
    if (sp_eqc(&mut x.sp, op, ">=")) {
        return 1;
    }
    if (sp_eqc(&mut x.sp, op, "&&")) {
        return 1;
    }
    if (sp_eqc(&mut x.sp, op, "||")) {
        return 1;
    }
    return 0;
}

fn p_expr_hint(x: &mut Fr, e: i64) -> i64 {
    if (e == 0) {
        return 0;
    }
    var k: i32 = 0;
    unsafe { k = na_at(x.na.v, e).k; }
    if (k == EX_INT) {
        return p_ty(x, TY_I32);
    }
    if (k == EX_FLOAT) {
        return p_ty(x, TY_F64);
    }
    if (k == EX_BOOL) {
        return p_ty(x, TY_BOOL);
    }
    if (k == EX_STR) {
        return p_ptr_u8(x);
    }
    if (k == EX_NULL) {
        let u: i64 = p_ty(x, TY_VOID);
        let p: i64 = p_ty(x, TY_PTR);
        unsafe { na_at(x.na.v, p).a = ( u) as i32; }
        return p;
    }
    if (k == EX_VAR) {
        var s: i64 = 0;
        unsafe { s = (na_at(x.na.v, e).s as i64); }
        let b: i64 = p_lookup_binding(x, s);
        if (b != 0) {
            return b;
        }
        return p_fn_value_type(x, s);
    }
    if (k == EX_SIZEOF) {
        return p_ty(x, TY_U64);
    }
    if (k == EX_ZERO) {
        var t: i64 = 0;
        unsafe { t = (na_at(x.na.v, e).a as i64); }
        return t;
    }
    if (k == EX_CAST) {
        var t: i64 = 0;
        unsafe { t = (na_at(x.na.v, e).b as i64); }
        return t;
    }
    if (k == EX_ADDR || k == EX_ADDRMUT) {
        var a: i64 = 0;
        unsafe { a = (na_at(x.na.v, e).a as i64); }
        let h: i64 = p_expr_hint(x, a);
        if (h == 0) {
            return 0;
        }
        let r: i64 = p_ty(x, TY_REF);
        unsafe {
            na_at(x.na.v, r).a = ( h) as i32;
            na_at(x.na.v, r).m = ( k == EX_ADDRMUT) as i32;
        }
        return r;
    }
    if (k == EX_DEREF) {
        var a: i64 = 0;
        unsafe { a = (na_at(x.na.v, e).a as i64); }
        let h: i64 = p_expr_hint(x, a);
        if (h == 0) {
            return 0;
        }
        var hk: i32 = 0;
        unsafe { hk = na_at(x.na.v, h).k; }
        if (hk == TY_PTR || hk == TY_REF || hk == TY_HEAP) {
            var t: i64 = 0;
            unsafe { t = (na_at(x.na.v, h).a as i64); }
            return t;
        }
        return 0;
    }
    if (k == EX_BOXNEW) {
        var a: i64 = 0;
        unsafe { a = (na_at(x.na.v, e).a as i64); }
        let h: i64 = p_expr_hint(x, a);
        if (h == 0) {
            return 0;
        }
        let b: i64 = p_ty(x, TY_HEAP);
        unsafe { na_at(x.na.v, b).a = ( h) as i32; }
        return b;
    }
    if (k == EX_INDEX) {
        var a: i64 = 0;
        unsafe { a = (na_at(x.na.v, e).a as i64); }
        let h: i64 = p_expr_hint(x, a);
        if (h == 0) {
            return 0;
        }
        var hk: i32 = 0;
        unsafe { hk = na_at(x.na.v, h).k; }
        if (hk == TY_PTR || hk == TY_ARRAY) {
            var t: i64 = 0;
            unsafe { t = (na_at(x.na.v, h).a as i64); }
            return t;
        }
        if (hk == TY_REF || hk == TY_HEAP) {
            var inner: i64 = 0;
            unsafe { inner = (na_at(x.na.v, h).a as i64); }
            var ik: i32 = 0;
            unsafe { ik = na_at(x.na.v, inner).k; }
            if (ik == TY_ARRAY || ik == TY_PTR) {
                var t2: i64 = 0;
                unsafe { t2 = (na_at(x.na.v, inner).a as i64); }
                return t2;
            }
            return 0;
        }
        return 0;
    }
    if (k == EX_FIELD) {
        var a2: i64 = 0;
        unsafe { a2 = (na_at(x.na.v, e).a as i64); }
        let base: i64 = p_expr_hint(x, a2);
        if (base == 0) {
            return 0;
        }
        var f: i64 = 0;
        unsafe { f = (na_at(x.na.v, e).s as i64); }
        return p_field_type(x, base, f);
    }
    if (k == EX_STRUCTLIT) {
        var s2: i64 = 0;
        unsafe { s2 = (na_at(x.na.v, e).s as i64); }
        let sig: i64 = m64_get(&mut x.fatm, s2, 0);
        if (sig != 0) {
            let ps: i64 = lp_get(&mut x.lp, sig, 0);
            let rt: i64 = lp_get(&mut x.lp, sig, 1);
            return p_fat_type(x, ps, rt);
        }
        let n: i64 = p_ty(x, TY_NAMED);
        unsafe { na_at(x.na.v, n).s = ( s2) as i32; }
        return n;
    }
    if (k == EX_ENUMLIT) {
        var s3: i64 = 0;
        unsafe { s3 = (na_at(x.na.v, e).s as i64); }
        let n2: i64 = p_ty(x, TY_NAMED);
        unsafe { na_at(x.na.v, n2).s = ( s3) as i32; }
        return n2;
    }
    if (k == EX_TUPLELIT) {
        var l: i64 = 0;
        unsafe { l = (na_at(x.na.v, e).l as i64); }
        let n3: i64 = lp_len(&mut x.lp, l);
        var items: i64 = lp_add(&mut x.lp);
        var i2: i64 = 0;
        while (i2 < n3) {
            let h2: i64 = p_expr_hint(x, lp_get(&mut x.lp, l, i2));
            if (h2 == 0) {
                return 0;
            }
            lp_push(&mut x.lp, items, h2);
            i2 += 1;
        }
        let t3: i64 = p_ty(x, TY_TUPLE);
        unsafe { na_at(x.na.v, t3).l = ( items) as i32; }
        return t3;
    }
    if (k == EX_FNREF) {
        var s4: i64 = 0;
        unsafe { s4 = (na_at(x.na.v, e).s as i64); }
        return p_fn_value_type(x, s4);
    }
    if (k == EX_CALL) {
        var n4: i64 = 0;
        unsafe { n4 = (na_at(x.na.v, e).s as i64); }
        let sig2: i64 = m64_get(&mut x.fvmap, n4, 0);
        if (sig2 != 0) {
            let ps2: i64 = lp_get(&mut x.lp, sig2, 0);
            let rt2: i64 = lp_get(&mut x.lp, sig2, 1);
            return p_fat_type(x, ps2, rt2);
        }
        return m64_get(&mut x.frmap, n4, 0);
    }
    if (k == EX_CALLV) {
        var f2: i64 = 0;
        unsafe { f2 = (na_at(x.na.v, e).a as i64); }
        let hf: i64 = p_expr_hint(x, f2);
        if (hf == 0) {
            return 0;
        }
        var fk: i32 = 0;
        unsafe { fk = na_at(x.na.v, hf).k; }
        if (fk == TY_FN || fk == TY_FNC || fk == TY_FAT) {
            var r2: i64 = 0;
            unsafe { r2 = (na_at(x.na.v, hf).a as i64); }
            return r2;
        }
        return 0;
    }
    if (k == EX_BIN) {
        var op: i64 = 0;
        unsafe { op = (na_at(x.na.v, e).s as i64); }
        if (p_is_cmp(x, op) != 0) {
            return p_ty(x, TY_BOOL);
        }
        var ba: i64 = 0;
        unsafe { ba = (na_at(x.na.v, e).a as i64); }
        let ha: i64 = p_expr_hint(x, ba);
        if (ha != 0) {
            return ha;
        }
        var bb: i64 = 0;
        unsafe { bb = (na_at(x.na.v, e).b as i64); }
        return p_expr_hint(x, bb);
    }
    if (k == EX_UN) {
        var ua: i64 = 0;
        unsafe { ua = (na_at(x.na.v, e).a as i64); }
        return p_expr_hint(x, ua);
    }
    if (k == EX_AWAIT) {
        var aa: i64 = 0;
        unsafe { aa = (na_at(x.na.v, e).a as i64); }
        let hh: i64 = p_expr_hint(x, aa);
        if (hh == 0) {
            return 0;
        }
        var hk2: i32 = 0;
        unsafe { hk2 = na_at(x.na.v, hh).k; }
        if (hk2 == TY_TASK) {
            var ti: i64 = 0;
            unsafe { ti = (na_at(x.na.v, hh).a as i64); }
            return ti;
        }
        return 0;
    }
    if (k == EX_POLL) {
        return p_ty(x, TY_I64);
    }
    return 0;
}

fn p_push_ret(x: &mut Fr, t: i64) {
    lp_push(&mut x.lp, x.rtyp, t);
}

fn p_pop_ret(x: &mut Fr) {
    lp_pop(&mut x.lp, x.rtyp);
}


