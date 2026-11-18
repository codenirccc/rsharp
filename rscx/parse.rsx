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
    sp: Sp
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
    f.lifts = lp_add(&mut f.lp);
    f.methods = lp_add(&mut f.lp);
    f.tparams = lp_add(&mut f.lp);
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
    if (at < 0 || at >= x.lx.ntok) {
        return 0 - 1;
    }
    return lex_tok_kind(&mut x.lx, at);
}

fn p_line(x: &mut Fr, at: i64) -> i64 {
    if (at < 0 || at >= x.lx.ntok) {
        return 0;
    }
    return lex_tok_line(&mut x.lx, at);
}

fn p_col(x: &mut Fr, at: i64) -> i64 {
    if (at < 0 || at >= x.lx.ntok) {
        return 0;
    }
    return lex_tok_col(&mut x.lx, at);
}

fn p_tok_eq(x: &mut Fr, at: i64, c: ptr<u8>) -> bool {
    if (at < 0 || at >= x.lx.ntok) {
        return false;
    }
    let n: i64 = lex_tok_slen(&mut x.lx, at);
    let cn: i64 = strlen(c) as i64;
    if (n != cn) {
        return false;
    }
    let p: ptr<u8> = lex_tok_sp(&mut x.lx, at);
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

fn p_at_sym(x: &mut Fr, c: ptr<u8>) -> bool {
    let at: i64 = x.i;
    if (p_kind(x, at) != TK_SYM) {
        return false;
    }
    return p_tok_eq(x, at, c);
}

fn p_sym_at(x: &mut Fr, at: i64, c: ptr<u8>) -> bool {
    if (p_kind(x, at) != TK_SYM) {
        return false;
    }
    return p_tok_eq(x, at, c);
}

fn p_at_kw(x: &mut Fr, c: ptr<u8>) -> bool {
    let at: i64 = x.i;
    if (p_kind(x, at) != TK_IDENT) {
        return false;
    }
    return p_tok_eq(x, at, c);
}

fn p_bump(x: &mut Fr) {
    if (x.i + 1 < x.lx.ntok) {
        x.i += 1;
    }
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
        let p: ptr<u8> = lex_tok_sp(&mut x.lx, at);
        let n: i64 = lex_tok_slen(&mut x.lx, at);
        sb_putc(&mut x.des, 39);
        sb_put(&mut x.des, p, n);
        sb_putc(&mut x.des, 39);
    } else if (k == TK_INT) {
        let v: i64 = lex_tok_num(&mut x.lx, at);
        sb_puts(&mut x.des, "integer ");
        sb_i64(&mut x.des, v);
    } else if (k == TK_FLOAT) {
        let v: f64 = lex_tok_fp(&mut x.lx, at);
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
    let p: ptr<u8> = lex_tok_sp(&mut x.lx, at);
    let n: i64 = lex_tok_slen(&mut x.lx, at);
    return sp_intern(&mut x.sp, p, n);
}

fn p_take_ident(x: &mut Fr) -> i64 {
    let at: i64 = x.i;
    if (p_kind(x, at) != TK_IDENT) {
        return 0;
    }
    x.tl = p_line(x, at);
    x.tc = p_col(x, at);
    let id: i64 = p_intern_tok(x, at);
    p_bump(x);
    return id;
}

fn p_reserved(x: &mut Fr, id: i64) -> bool {
    if (sp_eqc(&mut x.sp, id, "fn")) {
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
    if (!p_at_sym(x, ")")) {
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
        x.na.v[n].l = params;
        x.na.v[n].a = ret;
    }
    return n;
}

fn p_parse_type(x: &mut Fr) -> i64 {
    if (p_eat_sym(x, "(")) {
        var items: i64 = lp_add(&mut x.lp);
        if (!p_at_sym(x, ")")) {
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
        unsafe { x.na.v[n].l = items; }
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
        unsafe { x.na.v[n].a = inner; }
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
            x.na.v[n].a = inner;
            x.na.v[n].m = mu;
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
        unsafe { x.na.v[n].a = inner; }
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
        unsafe { x.na.v[n].a = inner; }
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
            let v: i64 = lex_tok_num(&mut x.lx, at);
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
            x.na.v[n].a = inner;
            x.na.v[n].n = szl;
            x.na.v[n].s = szn;
            x.na.v[n].m = use_name;
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
                unsafe { x.na.v[p].s = first; }
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
            unsafe { x.na.v[p].s = p_cat2(x, x.pfx, first); }
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
    unsafe { x.na.v[p].s = p_cat2(x, x.pfx, joined); }
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
        x.na.v[n].s = name;
        x.na.v[n].a = ty;
        x.na.v[n].b = v;
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
        x.na.v[n].s = name;
        x.na.v[n].a = ty;
        x.na.v[n].b = v;
        x.na.v[n].m = mu;
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
    while (!p_at_sym(x, "}")) {
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
        x.na.v[n].s = name;
        x.na.v[n].l = fields;
    }
    return n;
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
    while (!p_at_sym(x, "}")) {
        let vname: i64 = p_type_name(x);
        if (x.ok == 0) {
            return 0;
        }
        var payload: i64 = lp_add(&mut x.lp);
        if (p_eat_sym(x, "(")) {
            if (!p_at_sym(x, ")")) {
                while (true) {
                    let t: i64 = p_parse_type(x);
                    if (x.ok == 0) {
                        return 0;
                    }
                    var tk: i32 = zero(i32);
                    unsafe { tk = x.na.v[t].k; }
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
        x.na.v[n].s = name;
        x.na.v[n].l = variants;
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
    if (!p_at_sym(x, ")")) {
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
        x.na.v[n].s = name;
        x.na.v[n].s2 = lib;
        x.na.v[n].l = params;
        x.na.v[n].a = ret;
        x.na.v[n].m = variadic;
    }
    return n;
}

fn p_parse_extern(x: &mut Fr, out: i64) -> i32 {
    var lib: i64 = 0;
    let at: i64 = x.i;
    if (p_kind(x, at) == TK_STR) {
        let p: ptr<u8> = lex_tok_sp(&mut x.lx, at);
        let n: i64 = lex_tok_slen(&mut x.lx, at);
        var good: i32 = 1;
        if (n == 0) {
            good = 0;
        }
        var i: i64 = 0;
        while (i < n) {
            var c: u8 = 0;
            unsafe { c = p[i]; }
            let al: i32 = ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95) as i32;
            if (al == 0) {
                good = 0;
                break;
            }
            i += 1;
        }
        if (good == 0) {
            p_msg_begin(x);
            p_msg_s(x, "a library tag is letters, digits and '_' - e.g. \"winhttp\"");
            p_fail(x);
            return 0;
        }
        lib = sp_intern(&mut x.sp, p, n);
        p_bump(x);
    }
    if (p_at_sym(x, "{")) {
        p_bump(x);
        while (!p_at_sym(x, "}")) {
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
    if (!p_at_sym(x, ")")) {
        while (true) {
            let pname: i64 = p_name(x);
            if (x.ok == 0) {
                return 0;
            }
            p_expect_sym(x, ":");
            if (x.ok == 0) {
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
    let body: i64 = p_parse_body(x);
    if (x.ok == 0) {
        return 0;
    }
    x.tparams = outer;
    let n: i64 = na_add(&mut x.na, IT_FN);
    unsafe {
        x.na.v[n].s = name;
        x.na.v[n].l = tparams;
        x.na.v[n].l2 = params;
        x.na.v[n].a = ret;
        x.na.v[n].n = is_async as i64;
        x.na.v[n].l3 = body;
    }
    return n;
}

fn p_var(x: &mut Fr, s: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_VAR);
    unsafe { x.na.v[n].s = s; }
    return n;
}

fn p_int(x: &mut Fr, v: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_INT);
    unsafe { x.na.v[n].n = v; }
    return n;
}

fn p_field(x: &mut Fr, base: i64, s: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_FIELD);
    unsafe {
        x.na.v[n].a = base;
        x.na.v[n].s = s;
    }
    return n;
}

fn p_bin(x: &mut Fr, op: i64, a: i64, b: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_BIN);
    unsafe {
        x.na.v[n].s = op;
        x.na.v[n].a = a;
        x.na.v[n].b = b;
    }
    return n;
}

fn p_parse_block(x: &mut Fr) -> i64 {
    p_expect_sym(x, "{");
    if (x.ok == 0) {
        return 0;
    }
    var body: i64 = lp_add(&mut x.lp);
    while (!p_at_sym(x, "}")) {
        if (p_kind(x, x.i) == TK_EOF) {
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
    return body;
}

fn p_parse_run(x: &mut Fr) -> i64 {
    var body: i64 = lp_add(&mut x.lp);
    while (!p_at_kw(x, "end") && !p_at_kw(x, "else")) {
        if (p_kind(x, x.i) == TK_EOF) {
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
    return body;
}

fn p_parse_end(x: &mut Fr) -> i32 {
    if (p_expect_kw(x, "end") == 0) {
        return 0;
    }
    return p_expect_sym(x, ";");
}

fn p_parse_body(x: &mut Fr) -> i64 {
    if (p_at_sym(x, "{")) {
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
        if (p_at_sym(x, "{")) {
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
            x.na.v[n].a = c;
            x.na.v[n].l = b;
            x.na.v[n].l2 = els;
        }
        els = lp_add(&mut x.lp);
        lp_push(&mut x.lp, els, n);
    }
    if (lp_len(&mut x.lp, els) == 0) {
        let n: i64 = na_add(&mut x.na, ST_BLOCK);
        let e: i64 = lp_add(&mut x.lp);
        unsafe { x.na.v[n].l = e; }
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
    if (p_at_sym(x, "'")) {
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
            x.na.v[n].s = label;
            x.na.v[n].a = inner;
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
        unsafe { x.na.v[n].l = b; }
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
        if (!p_at_sym(x, "{")) {
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
            x.na.v[n].a = cond;
            x.na.v[n].l = then;
            x.na.v[n].l2 = els;
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
            x.na.v[n].a = cond;
            x.na.v[n].l = body;
        }
        return n;
    }
    if (p_eat_kw(x, "loop")) {
        let body: i64 = p_parse_body(x);
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, ST_LOOP);
        unsafe { x.na.v[n].l = body; }
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
            x.na.v[n].s = vname;
            x.na.v[n].a = start;
            x.na.v[n].b = hi;
            x.na.v[n].l = body;
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
        while (!p_at_sym(x, "}")) {
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
                x.na.v[arm].a = pat;
                x.na.v[arm].l = body;
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
            x.na.v[n].a = scrut;
            x.na.v[n].l = arms;
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
        unsafe { x.na.v[n].s = label; }
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
        unsafe { x.na.v[n].s = label; }
        return n;
    }
    if (p_eat_kw(x, "return")) {
        if (p_at_sym(x, ";")) {
            p_bump(x);
            let n: i64 = na_add(&mut x.na, ST_RETURN);
            return n;
        }
        let e: i64 = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
        }
        if (p_expect_sym(x, ";") == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, ST_RETURN);
        unsafe { x.na.v[n].a = e; }
        return n;
    }
    if (p_at_sym(x, "{")) {
        let b: i64 = p_parse_block(x);
        if (x.ok == 0) {
            return 0;
        }
        let n: i64 = na_add(&mut x.na, ST_BLOCK);
        unsafe { x.na.v[n].l = b; }
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
                x.na.v[n].s = opid;
                x.na.v[n].a = lhs;
                x.na.v[n].b = rhs;
            }
            return n;
        }
        i += 1;
    }
    if (p_expect_sym(x, ";") == 0) {
        return 0;
    }
    let n: i64 = na_add(&mut x.na, ST_EXPR);
    unsafe { x.na.v[n].a = lhs; }
    return n;
}

fn p_eat_label(x: &mut Fr) -> i64 {
    if (p_at_sym(x, "'")) {
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
        let v: i64 = lex_tok_num(&mut x.lx, at);
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
            let hi: i64 = lex_tok_num(&mut x.lx, at2);
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
                x.na.v[n].n = lo;
                x.na.v[n].b = hi;
            }
            return n;
        }
        let n: i64 = na_add(&mut x.na, PT_LIT);
        unsafe { x.na.v[n].n = lo; }
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
        if (!p_at_sym(x, ")")) {
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
        x.na.v[n].s = en;
        x.na.v[n].s2 = vn;
        x.na.v[n].l = binds;
    }
    return n;
}

fn p_tie_to_name(x: &mut Fr, out: i64, hint: i64, rhs: i64) -> i64 {
    var k: i32 = 0;
    unsafe { k = x.na.v[rhs].k; }
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
        x.na.v[st].m = 0;
        x.na.v[st].s = temp;
        x.na.v[st].a = hint;
        x.na.v[st].b = rhs;
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
            unsafe { x.na.v[st].a = e; }
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
        let p: ptr<u8> = lex_tok_sp(&mut x.lx, at);
        var c: u8 = 0;
        unsafe { c = p[0]; }
        upper = c >= 65 && c <= 90;
    }
    if (upper && p_sym_at(x, at + 1, "{")) {
        let ty: i64 = p_parse_type(x);
        if (x.ok == 0) {
            return 0;
        }
        p_expect_sym(x, "{");
        if (x.ok == 0) {
            return 0;
        }
        var binds: i64 = lp_add(&mut x.lp);
        while (!p_at_sym(x, "}")) {
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
            let init: i64 = p_field(x, base, f);
            let st: i64 = na_add(&mut x.na, ST_LET);
            let infer: i64 = p_ty(x, TY_INFER);
            unsafe {
                x.na.v[st].m = mutable;
                x.na.v[st].s = b;
                x.na.v[st].a = infer;
                x.na.v[st].b = init;
            }
            lp_push(&mut x.lp, out, st);
            i += 2;
        }
        return out;
    }
    if (p_at_sym(x, "(") && mutable == 0) {
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
            unsafe { ak = x.na.v[ann].k; }
            if (ak != TY_TUPLE) {
                p_msg_begin(x);
                p_msg_s(x, "a tuple pattern needs a tuple type");
                return p_fail(x);
            }
            unsafe { parts = x.na.v[ann].l; }
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
                let st: i64 = na_add(&mut x.na, ST_LET);
                unsafe {
                    x.na.v[st].m = 0;
                    x.na.v[st].s = slot;
                    x.na.v[st].a = ty;
                    x.na.v[st].b = init;
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
    let st: i64 = na_add(&mut x.na, ST_LET);
    unsafe {
        x.na.v[st].m = mutable;
        x.na.v[st].s = name;
        x.na.v[st].a = ty;
        x.na.v[st].b = init;
    }
    return p_stmt_list1(x, st);
}

fn p_assign_op(x: &mut Fr) -> i64 {
    var c: ptr<u8> = null;
    if (p_at_sym(x, "=")) {
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
            x.na.v[n].a = e;
            x.na.v[n].b = t;
        }
        e = n;
    }
    return e;
}

fn p_un(x: &mut Fr, op: ptr<u8>, a: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, EX_UN);
    let o: i64 = p_interns(x, op);
    unsafe {
        x.na.v[n].s = o;
        x.na.v[n].a = a;
    }
    return n;
}

fn p_wrap(x: &mut Fr, k: i32, a: i64) -> i64 {
    let n: i64 = na_add(&mut x.na, k);
    unsafe { x.na.v[n].a = a; }
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
    if (!p_at_sym(x, ")")) {
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
        if (p_at_sym(x, "(")) {
            let args: i64 = p_parse_args(x);
            if (x.ok == 0) {
                return 0;
            }
            var ek: i32 = 0;
            unsafe { ek = x.na.v[e].k; }
            if (ek == EX_VAR) {
                let n: i64 = na_add(&mut x.na, EX_CALL);
                var nm: i64 = zero(i64);
                unsafe { nm = x.na.v[e].s; }
                unsafe {
                    x.na.v[n].s = nm;
                    x.na.v[n].l = args;
                }
                e = n;
            } else {
                let n: i64 = na_add(&mut x.na, EX_CALLV);
                unsafe {
                    x.na.v[n].a = e;
                    x.na.v[n].l = args;
                }
                e = n;
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
                x.na.v[n].a = e;
                x.na.v[n].b = idx;
            }
            e = n;
        } else if (p_eat_sym(x, ".")) {
            var f: i64 = 0;
            if (p_kind(x, x.i) == TK_INT) {
                let at: i64 = x.i;
                let v: i64 = lex_tok_num(&mut x.lx, at);
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
            if (p_at_sym(x, "(")) {
                let args: i64 = p_parse_args(x);
                if (x.ok == 0) {
                    return 0;
                }
                let n: i64 = na_add(&mut x.na, EX_METHOD);
                unsafe {
                    x.na.v[n].a = e;
                    x.na.v[n].s = f;
                    x.na.v[n].l = args;
                }
                e = n;
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
        let v: i64 = lex_tok_num(&mut x.lx, at);
        p_bump(x);
        return p_int(x, v);
    }
    if (k == TK_FLOAT) {
        let v: f64 = lex_tok_fp(&mut x.lx, at);
        p_bump(x);
        let n: i64 = na_add(&mut x.na, EX_FLOAT);
        unsafe { x.na.v[n].f = v; }
        return n;
    }
    if (k == TK_STR) {
        let s: i64 = p_intern_tok(x, at);
        p_bump(x);
        let n: i64 = na_add(&mut x.na, EX_STR);
        unsafe { x.na.v[n].s = s; }
        return n;
    }
    if (p_sym_at(x, at, "[")) {
        p_bump(x);
        var items: i64 = lp_add(&mut x.lp);
        if (!p_at_sym(x, "]")) {
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
        unsafe { x.na.v[n].l = items; }
        return n;
    }
    if (p_sym_at(x, at, "|") || p_sym_at(x, at, "||")) {
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
    if (k == TK_IDENT && p_tok_eq(x, at, "poll") && p_sym_at(x, at + 1, "(")) {
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
            unsafe { x.na.v[n].n = 1; }
            return n;
        }
        if (sp_eqc(&mut x.sp, name, "false")) {
            p_bump(x);
            let n: i64 = na_add(&mut x.na, EX_BOOL);
            unsafe { x.na.v[n].n = 0; }
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
                if (p_at_sym(x, "(")) {
                    let args: i64 = p_parse_args(x);
                    if (x.ok == 0) {
                        return 0;
                    }
                    let n: i64 = na_add(&mut x.na, EX_CALL);
                    unsafe {
                        x.na.v[n].s = joined;
                        x.na.v[n].l = args;
                    }
                    return n;
                }
                return p_var(x, joined);
            }
            let rest: i64 = ns - kk;
            if (rest == 1) {
                let joined: i64 = p_join(x, segs, "__");
                let full: i64 = p_cat2(x, x.pfx, joined);
                if (p_at_sym(x, "{")) {
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
                    if (!p_at_sym(x, ")")) {
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
                let n: i64 = na_add(&mut x.na, EX_ENUMLIT);
                unsafe {
                    x.na.v[n].s = ty;
                    x.na.v[n].s2 = vn;
                    x.na.v[n].l = args;
                }
                return n;
            }
            p_msg_begin(x);
            p_msg_s(x, "too many '::' segments: a name is 'mod::Type::Variant' at most");
            return p_fail(x);
        }
        if (p_at_sym(x, "{") && p_upper(x, name)) {
            let full: i64 = p_cat2(x, x.pfx, name);
            return p_parse_struct_lit(x, full);
        }
        return p_var(x, name);
    }
    if (p_sym_at(x, at, "(")) {
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
            unsafe { x.na.v[n].l = items; }
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
        if (!p_at_sym(x, "|")) {
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
    let body: i64 = p_parse_block(x);
    if (x.ok == 0) {
        return 0;
    }
    let pre: i64 = p_interns(x, "__clo");
    let num: i64 = p_num_id(x, x.clo);
    let name: i64 = p_cat2(x, pre, num);
    x.clo += 1;
    let tp: i64 = lp_add(&mut x.lp);
    let f: i64 = na_add(&mut x.na, IT_FN);
    unsafe {
        x.na.v[f].s = name;
        x.na.v[f].l = tp;
        x.na.v[f].l2 = params;
        x.na.v[f].a = ret;
        x.na.v[f].n = 0;
        x.na.v[f].m = 0;
        x.na.v[f].l3 = body;
    }
    lp_push(&mut x.lp, x.lifts, f);
    let n: i64 = na_add(&mut x.na, EX_FNREF);
    unsafe { x.na.v[n].s = name; }
    return n;
}

fn p_parse_struct_lit(x: &mut Fr, name: i64) -> i64 {
    if (p_expect_sym(x, "{") == 0) {
        return 0;
    }
    var fields: i64 = lp_add(&mut x.lp);
    while (!p_at_sym(x, "}")) {
        let f: i64 = p_name(x);
        if (x.ok == 0) {
            return 0;
        }
        if (p_expect_sym(x, ":") == 0) {
            return 0;
        }
        let v: i64 = p_parse_expr(x);
        if (x.ok == 0) {
            return 0;
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
        x.na.v[n].s = name;
        x.na.v[n].l = fields;
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
    unsafe { k = x.na.v[e].k; }
    if (k == EX_VAR) {
        var n: i64 = zero(i64);
        unsafe { n = x.na.v[e].s; }
        if (!p_is_local(x, stack, n)) {
            let full: i64 = p_cat2(x, pfx, n);
            if (si_has(names, &mut x.sp, full)) {
                unsafe { x.na.v[e].s = full; }
            }
        }
    } else if (k == EX_FNREF || k == EX_CALL) {
        var n: i64 = zero(i64);
        unsafe { n = x.na.v[e].s; }
        let full: i64 = p_cat2(x, pfx, n);
        if (si_has(names, &mut x.sp, full)) {
            unsafe { x.na.v[e].s = full; }
        }
        if (k == EX_CALL) {
            var l: i64 = zero(i64);
            unsafe { l = x.na.v[e].l; }
            p_rename_list(x, l, pfx, names, stack);
        }
    } else if (k == EX_BIN || k == EX_INDEX) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[e].a; }
        var b: i64 = zero(i64);
        unsafe { b = x.na.v[e].b; }
        p_rename_expr(x, a, pfx, names, stack);
        p_rename_expr(x, b, pfx, names, stack);
    } else if (k == EX_UN || k == EX_DEREF || k == EX_ADDR || k == EX_ADDRMUT || k == EX_BOXNEW || k == EX_CAST || k == EX_AWAIT || k == EX_POLL || k == EX_FIELD) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[e].a; }
        p_rename_expr(x, a, pfx, names, stack);
    } else if (k == EX_CALLV || k == EX_METHOD) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[e].a; }
        var l: i64 = zero(i64);
        unsafe { l = x.na.v[e].l; }
        p_rename_expr(x, a, pfx, names, stack);
        p_rename_list(x, l, pfx, names, stack);
    } else if (k == EX_STRUCTLIT) {
        var l: i64 = zero(i64);
        unsafe { l = x.na.v[e].l; }
        p_rename_pairs(x, l, pfx, names, stack);
    } else if (k == EX_ARRAYLIT || k == EX_TUPLELIT || k == EX_ENUMLIT) {
        var l: i64 = zero(i64);
        unsafe { l = x.na.v[e].l; }
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
    unsafe { k = x.na.v[st].k; }
    if (k == ST_LET) {
        var ini: i64 = zero(i64);
        unsafe { ini = x.na.v[st].b; }
        if (ini != 0) {
            p_rename_expr(x, ini, pfx, names, stack);
        }
        var nm: i64 = zero(i64);
        unsafe { nm = x.na.v[st].s; }
        let ns: i64 = lp_len(&mut x.lp, stack);
        let top: i64 = lp_get(&mut x.lp, stack, ns - 1);
        lp_push(&mut x.lp, top, nm);
    } else if (k == ST_ASSIGN) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[st].a; }
        var b: i64 = zero(i64);
        unsafe { b = x.na.v[st].b; }
        p_rename_expr(x, a, pfx, names, stack);
        p_rename_expr(x, b, pfx, names, stack);
    } else if (k == ST_EXPR) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[st].a; }
        p_rename_expr(x, a, pfx, names, stack);
    } else if (k == ST_BLOCK || k == ST_UNSAFE) {
        var l: i64 = zero(i64);
        unsafe { l = x.na.v[st].l; }
        let inner: i64 = p_stack_push(x, stack);
        p_rename_stmts(x, l, pfx, names, inner);
        lp_pop(&mut x.lp, stack);
    } else if (k == ST_IF) {
        var c: i64 = zero(i64);
        unsafe { c = x.na.v[st].a; }
        var th: i64 = zero(i64);
        unsafe { th = x.na.v[st].l; }
        var el: i64 = zero(i64);
        unsafe { el = x.na.v[st].l2; }
        p_rename_expr(x, c, pfx, names, stack);
        let i1: i64 = p_stack_push(x, stack);
        p_rename_stmts(x, th, pfx, names, i1);
        lp_pop(&mut x.lp, stack);
        let i2: i64 = p_stack_push(x, stack);
        p_rename_stmts(x, el, pfx, names, i2);
        lp_pop(&mut x.lp, stack);
    } else if (k == ST_WHILE) {
        var c: i64 = zero(i64);
        unsafe { c = x.na.v[st].a; }
        var bl: i64 = zero(i64);
        unsafe { bl = x.na.v[st].l; }
        p_rename_expr(x, c, pfx, names, stack);
        let inner: i64 = p_stack_push(x, stack);
        p_rename_stmts(x, bl, pfx, names, inner);
        lp_pop(&mut x.lp, stack);
    } else if (k == ST_LOOP) {
        var bl: i64 = zero(i64);
        unsafe { bl = x.na.v[st].l; }
        let inner: i64 = p_stack_push(x, stack);
        p_rename_stmts(x, bl, pfx, names, inner);
        lp_pop(&mut x.lp, stack);
    } else if (k == ST_FOR) {
        var v: i64 = zero(i64);
        unsafe { v = x.na.v[st].s; }
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[st].a; }
        var b: i64 = zero(i64);
        unsafe { b = x.na.v[st].b; }
        var bl: i64 = zero(i64);
        unsafe { bl = x.na.v[st].l; }
        p_rename_expr(x, a, pfx, names, stack);
        p_rename_expr(x, b, pfx, names, stack);
        let inner: i64 = p_stack_push(x, stack);
        lp_push(&mut x.lp, inner, v);
        p_rename_stmts(x, bl, pfx, names, inner);
        lp_pop(&mut x.lp, stack);
    } else if (k == ST_MATCH) {
        var sc: i64 = zero(i64);
        unsafe { sc = x.na.v[st].a; }
        var arms: i64 = zero(i64);
        unsafe { arms = x.na.v[st].l; }
        p_rename_expr(x, sc, pfx, names, stack);
        let na: i64 = lp_len(&mut x.lp, arms);
        var i: i64 = 0;
        while (i < na) {
            let arm: i64 = lp_get(&mut x.lp, arms, i);
            var pat: i64 = zero(i64);
            unsafe { pat = x.na.v[arm].a; }
            var body: i64 = zero(i64);
            unsafe { body = x.na.v[arm].l; }
            let inner: i64 = p_stack_push(x, stack);
            var pk: i32 = zero(i32);
            unsafe { pk = x.na.v[pat].k; }
            if (pk == PT_VARIANT) {
                var binds: i64 = zero(i64);
                unsafe { binds = x.na.v[pat].l; }
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
        unsafe { a = x.na.v[st].a; }
        p_rename_stmt(x, a, pfx, names, stack);
    } else if (k == ST_RETURN) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[st].a; }
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
    unsafe { k = x.na.v[e].k; }
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
    unsafe { k = x.na.v[e].k; }
    if (k == EX_BIN || k == EX_INDEX) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[e].a; }
        var b: i64 = zero(i64);
        unsafe { b = x.na.v[e].b; }
        if (p_fix_expr(x, a, methods) == 0) {
            return 0;
        }
        if (p_fix_expr(x, b, methods) == 0) {
            return 0;
        }
    } else if (k == EX_UN || k == EX_DEREF || k == EX_ADDR || k == EX_ADDRMUT || k == EX_BOXNEW || k == EX_CAST || k == EX_AWAIT || k == EX_POLL || k == EX_FIELD) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[e].a; }
        if (p_fix_expr(x, a, methods) == 0) {
            return 0;
        }
    } else if (k == EX_CALL || k == EX_ARRAYLIT || k == EX_TUPLELIT || k == EX_ENUMLIT) {
        var l: i64 = zero(i64);
        unsafe { l = x.na.v[e].l; }
        if (p_fix_list(x, l, methods) == 0) {
            return 0;
        }
    } else if (k == EX_CALLV) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[e].a; }
        var l: i64 = zero(i64);
        unsafe { l = x.na.v[e].l; }
        if (p_fix_expr(x, a, methods) == 0) {
            return 0;
        }
        if (p_fix_list(x, l, methods) == 0) {
            return 0;
        }
    } else if (k == EX_STRUCTLIT) {
        var l: i64 = zero(i64);
        unsafe { l = x.na.v[e].l; }
        if (p_fix_pairs(x, l, methods) == 0) {
            return 0;
        }
    } else if (k == EX_METHOD) {
        var recv: i64 = zero(i64);
        unsafe { recv = x.na.v[e].a; }
        var nm: i64 = zero(i64);
        unsafe { nm = x.na.v[e].s; }
        var args: i64 = zero(i64);
        unsafe { args = x.na.v[e].l; }
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
            i += 3;
        }
        if (hits == 0) {
            let callee: i64 = na_add(&mut x.na, EX_FIELD);
            unsafe {
                x.na.v[callee].a = recv;
                x.na.v[callee].s = nm;
            }
            unsafe {
                x.na.v[e].k = EX_CALLV;
                x.na.v[e].a = callee;
                x.na.v[e].s = 0;
                x.na.v[e].l = args;
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
            unsafe { x.na.v[base].a = recv; }
            lp_push(&mut x.lp, call, base);
            let nargs: i64 = lp_len(&mut x.lp, args);
            var j: i64 = 0;
            while (j < nargs) {
                let av: i64 = lp_get(&mut x.lp, args, j);
                lp_push(&mut x.lp, call, av);
                j += 1;
            }
            unsafe {
                x.na.v[e].k = EX_CALL;
                x.na.v[e].s = full;
                x.na.v[e].a = 0;
                x.na.v[e].l = call;
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
                j2 += 3;
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
    unsafe { k = x.na.v[st].k; }
    if (k == ST_LET) {
        var ini: i64 = zero(i64);
        unsafe { ini = x.na.v[st].b; }
        if (ini != 0) {
            var ik: i32 = zero(i32);
            unsafe { ik = x.na.v[ini].k; }
            if (ik == EX_METHOD) {
                var recv: i64 = zero(i64);
                unsafe { recv = x.na.v[ini].a; }
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
        unsafe { a = x.na.v[st].a; }
        var b: i64 = zero(i64);
        unsafe { b = x.na.v[st].b; }
        if (p_fix_expr(x, a, methods) == 0) {
            return 0;
        }
        if (p_fix_expr(x, b, methods) == 0) {
            return 0;
        }
    } else if (k == ST_EXPR) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[st].a; }
        if (p_fix_expr(x, a, methods) == 0) {
            return 0;
        }
    } else if (k == ST_BLOCK || k == ST_UNSAFE) {
        var l: i64 = zero(i64);
        unsafe { l = x.na.v[st].l; }
        if (p_fix_stmts(x, l, methods) == 0) {
            return 0;
        }
    } else if (k == ST_IF) {
        var c: i64 = zero(i64);
        unsafe { c = x.na.v[st].a; }
        var th: i64 = zero(i64);
        unsafe { th = x.na.v[st].l; }
        var el: i64 = zero(i64);
        unsafe { el = x.na.v[st].l2; }
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
        unsafe { c = x.na.v[st].a; }
        var bl: i64 = zero(i64);
        unsafe { bl = x.na.v[st].l; }
        if (p_fix_expr(x, c, methods) == 0) {
            return 0;
        }
        if (p_fix_stmts(x, bl, methods) == 0) {
            return 0;
        }
    } else if (k == ST_LOOP) {
        var bl: i64 = zero(i64);
        unsafe { bl = x.na.v[st].l; }
        if (p_fix_stmts(x, bl, methods) == 0) {
            return 0;
        }
    } else if (k == ST_FOR) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[st].a; }
        var b: i64 = zero(i64);
        unsafe { b = x.na.v[st].b; }
        var bl: i64 = zero(i64);
        unsafe { bl = x.na.v[st].l; }
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
        unsafe { sc = x.na.v[st].a; }
        var arms: i64 = zero(i64);
        unsafe { arms = x.na.v[st].l; }
        if (p_fix_expr(x, sc, methods) == 0) {
            return 0;
        }
        let na: i64 = lp_len(&mut x.lp, arms);
        var i: i64 = 0;
        while (i < na) {
            let arm: i64 = lp_get(&mut x.lp, arms, i);
            var body: i64 = zero(i64);
            unsafe { body = x.na.v[arm].l; }
            if (p_fix_stmts(x, body, methods) == 0) {
                return 0;
            }
            i += 1;
        }
    } else if (k == ST_LABEL) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[st].a; }
        if (p_fix_stmt(x, a, methods) == 0) {
            return 0;
        }
    } else if (k == ST_RETURN) {
        var a: i64 = zero(i64);
        unsafe { a = x.na.v[st].a; }
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
        unsafe { body = x.na.v[f].l3; }
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
        unsafe { ini = x.na.v[g].b; }
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
        unsafe { v = x.na.v[c].b; }
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
        unsafe { nm = x.na.v[it].s; }
        si_add(ns, &mut x.sp, nm);
        i += 1;
    }
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
    if (p_expect_sym(x, "{") == 0) {
        return 0;
    }
    let ms: i64 = x.methods;
    while (!p_at_sym(x, "}")) {
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
        let f: i64 = p_parse_fn(x, is_async);
        if (x.ok == 0) {
            return 0;
        }
        var fname: i64 = zero(i64);
        unsafe { fname = x.na.v[f].s; }
        let sep: i64 = p_interns(x, "__");
        let full: i64 = p_cat3(x, ty, sep, fname);
        var params: i64 = zero(i64);
        unsafe { params = x.na.v[f].l2; }
        let np: i64 = lp_len(&mut x.lp, params);
        if (np > 0) {
            let first: i64 = lp_get(&mut x.lp, params, 0);
            if (sp_eqc(&mut x.sp, first, "self")) {
                let fty: i64 = lp_get(&mut x.lp, params, 1);
                var fk: i32 = zero(i32);
                unsafe { fk = x.na.v[fty].k; }
                var kind: i64 = 0 - 1;
                if (fk == TY_REF) {
                    var mu: i32 = zero(i32);
                    unsafe { mu = x.na.v[fty].m; }
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
            }
        }
        unsafe { x.na.v[f].s = full; }
        lp_push(&mut x.lp, p.f, f);
    }
    if (p_expect_sym(x, "}") == 0) {
        return 0;
    }
    return 1;
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
        unsafe { params = x.na.v[f].l2; }
        var body: i64 = zero(i64);
        unsafe { body = x.na.v[f].l3; }
        p_rename_body(x, body, params, pfx, &mut ns);
        i += 1;
    }
    let nc: i64 = lp_len(&mut x.lp, inner.c);
    var ic: i64 = 0;
    while (ic < nc) {
        let c: i64 = lp_get(&mut x.lp, inner.c, ic);
        var v: i64 = zero(i64);
        unsafe { v = x.na.v[c].b; }
        p_rename_expr_top(x, v, pfx, &mut ns);
        ic += 1;
    }
    let ng: i64 = lp_len(&mut x.lp, inner.g);
    var ig: i64 = 0;
    while (ig < ng) {
        let g: i64 = lp_get(&mut x.lp, inner.g, ig);
        var v: i64 = zero(i64);
        unsafe { v = x.na.v[g].b; }
        p_rename_expr_top(x, v, pfx, &mut ns);
        ig += 1;
    }
    let total: i64 = lp_len(&mut x.lp, lf);
    var il: i64 = lift_mark;
    while (il < total) {
        let f: i64 = lp_get(&mut x.lp, lf, il);
        var params: i64 = zero(i64);
        unsafe { params = x.na.v[f].l2; }
        var body: i64 = zero(i64);
        unsafe { body = x.na.v[f].l3; }
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
        if (top == 0 && p_at_sym(x, "}")) {
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
                unsafe { x.na.v[f].m = 1; }
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
            p_msg_s(x, "expected 'const', 'struct', 'enum', 'extern', 'static', 'mod', 'impl' or 'fn', found ");
            p_msg_desc(x);
            p_fail(x);
            return 0;
        }
    }
    return 1;
}

fn fr_lex(f: &mut Fr, src: ptr<u8>, len: i64) -> i32 {
    f.ok = 1;
    if (lex_run(&mut f.lx, src, len) == 0) {
        f.ok = 0;
        sb_clear(&mut f.err);
        let e: ptr<u8> = lex_err(&mut f.lx);
        sb_puts(&mut f.err, e);
        return 0;
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
    p_resolve_methods(f, &mut p);
    return p;
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

fn fr_tok_count(f: &mut Fr) -> i64 {
    return f.lx.ntok;
}


