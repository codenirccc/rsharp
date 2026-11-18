include "bx_parse.rsx";

struct Bv {
    ok: i32,
    v: i32
}

struct Fv {
    ok: i32,
    v: f64
}

fn bv_no() -> Bv {
    var r: Bv = zero(Bv);
    return r;
}

fn bv_yes(v: i32) -> Bv {
    var r: Bv = zero(Bv);
    r.ok = 1;
    r.v = v;
    return r;
}

fn fv_no() -> Fv {
    var r: Fv = zero(Fv);
    return r;
}

fn fv_yes(v: f64) -> Fv {
    var r: Fv = zero(Fv);
    r.ok = 1;
    r.v = v;
    return r;
}

fn fx_take(x: &mut Bp, dst: i64, src: i64) {
    var t: i64 = 0;
    unsafe { t = x.na.v[dst].ty; }
    unsafe { x.na.v[dst] = x.na.v[src]; }
    unsafe { x.na.v[dst].ty = t; }
}

fn fx_kind(x: &mut Bp, e: i64) -> i32 {
    var k: i32 = 0;
    unsafe { k = x.na.v[e].k; }
    return k;
}

fn fx_ivar(x: &mut Bp, e: i64) -> i64 {
    var v: i64 = 0;
    unsafe { v = x.na.v[e].n; }
    return v;
}

fn fx_fval(x: &mut Bp, e: i64) -> f64 {
    var v: f64 = 0.0;
    unsafe { v = x.na.v[e].f; }
    return v;
}

fn fx_ty(x: &mut Bp, e: i64) -> i64 {
    var v: i64 = 0;
    unsafe { v = x.na.v[e].ty; }
    return v;
}

fn fx_set_int(x: &mut Bp, e: i64, v: i64) {
    unsafe {
        x.na.v[e].k = EX_INT;
        x.na.v[e].n = v;
    }
}

fn fx_set_float(x: &mut Bp, e: i64, v: f64) {
    unsafe {
        x.na.v[e].k = EX_FLOAT;
        x.na.v[e].f = v;
    }
}

fn fx_set_bool(x: &mut Bp, e: i64, v: i32) {
    unsafe {
        x.na.v[e].k = EX_BOOL;
        x.na.v[e].n = v as i64;
    }
}

fn fx_true(x: &mut Bp, e: i64) -> bool {
    let k: i32 = fx_kind(x, e);
    if (k != EX_BOOL) {
        return false;
    }
    return fx_ivar(x, e) != 0;
}

fn fx_is_compare(x: &mut Bp, op: i64) -> bool {
    if (sp_eqc(&mut x.sp, op, "==")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, op, "!=")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, op, "<")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, op, "<=")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, op, ">")) {
        return true;
    }
    if (sp_eqc(&mut x.sp, op, ">=")) {
        return true;
    }
    return false;
}

fn fx_shr(x: &mut Bp, t: i64, v: i64, y: i64) -> i64 {
    let w: i64 = tt_wrap(&mut x.tt, t, v);
    if (tt_is_signed(&mut x.tt, t)) {
        return tt_wrap(&mut x.tt, t, w >> y);
    }
    let uw: u64 = w as u64;
    let ur: u64 = uw >> (y as u64);
    return tt_wrap(&mut x.tt, t, ur as i64);
}

fn fx_int_fold(x: &mut Bp, t: i64, op: i64, xv: i64, yv: i64) -> Iv {
    let a: i64 = tt_wrap(&mut x.tt, t, xv);
    let b: i64 = tt_wrap(&mut x.tt, t, yv);
    if (sp_eqc(&mut x.sp, op, "+")) {
        return iv_yes(tt_wrap(&mut x.tt, t, a + b));
    }
    if (sp_eqc(&mut x.sp, op, "-")) {
        return iv_yes(tt_wrap(&mut x.tt, t, a - b));
    }
    if (sp_eqc(&mut x.sp, op, "*")) {
        return iv_yes(tt_wrap(&mut x.tt, t, a * b));
    }
    if (sp_eqc(&mut x.sp, op, "/")) {
        if (b == 0) {
            return iv_no();
        }
        if (tt_is_signed(&mut x.tt, t)) {
            return iv_yes(tt_wrap(&mut x.tt, t, a / b));
        }
        let ua: u64 = a as u64;
        let ub: u64 = b as u64;
        return iv_yes(tt_wrap(&mut x.tt, t, (ua / ub) as i64));
    }
    if (sp_eqc(&mut x.sp, op, "%")) {
        if (b == 0) {
            return iv_no();
        }
        if (tt_is_signed(&mut x.tt, t)) {
            return iv_yes(tt_wrap(&mut x.tt, t, a % b));
        }
        let ua2: u64 = a as u64;
        let ub2: u64 = b as u64;
        return iv_yes(tt_wrap(&mut x.tt, t, (ua2 % ub2) as i64));
    }
    if (sp_eqc(&mut x.sp, op, "&")) {
        return iv_yes(a & b);
    }
    if (sp_eqc(&mut x.sp, op, "|")) {
        return iv_yes(a | b);
    }
    if (sp_eqc(&mut x.sp, op, "^")) {
        return iv_yes(a ^ b);
    }
    if (sp_eqc(&mut x.sp, op, "<<")) {
        if (b < 0 || b > 63) {
            return iv_no();
        }
        return iv_yes(tt_wrap(&mut x.tt, t, a << b));
    }
    if (sp_eqc(&mut x.sp, op, ">>")) {
        if (b < 0 || b > 63) {
            return iv_no();
        }
        return iv_yes(fx_shr(x, t, a, b));
    }
    return iv_no();
}

fn fx_float_fold(x: &mut Bp, op: i64, a: f64, b: f64) -> Fv {
    if (sp_eqc(&mut x.sp, op, "+")) {
        return fv_yes(a + b);
    }
    if (sp_eqc(&mut x.sp, op, "-")) {
        return fv_yes(a - b);
    }
    if (sp_eqc(&mut x.sp, op, "*")) {
        return fv_yes(a * b);
    }
    if (sp_eqc(&mut x.sp, op, "/")) {
        if (b == 0.0) {
            return fv_no();
        }
        return fv_yes(a / b);
    }
    return fv_no();
}

fn fx_eval_bool(x: &mut Bp, e: i64) -> Bv {
    if (e <= 0) {
        return bv_no();
    }
    let k: i32 = fx_kind(x, e);
    if (k == EX_BOOL) {
        return bv_yes(fx_ivar(x, e) as i32);
    }
    if (k != EX_UN && k != EX_BIN) {
        return bv_no();
    }
    var op: i64 = 0;
    var a: i64 = 0;
    var b: i64 = 0;
    unsafe {
        op = x.na.v[e].s;
        a = x.na.v[e].a;
        b = x.na.v[e].b;
    }
    if (k == EX_UN) {
        if (!sp_eqc(&mut x.sp, op, "!")) {
            return bv_no();
        }
        let av: Bv = fx_eval_bool(x, a);
        if (av.ok == 0) {
            return bv_no();
        }
        if (av.v != 0) {
            return bv_yes(0);
        }
        return bv_yes(1);
    }
    let is_and: bool = sp_eqc(&mut x.sp, op, "&&");
    let is_or: bool = sp_eqc(&mut x.sp, op, "||");
    if (is_and || is_or) {
        let av2: Bv = fx_eval_bool(x, a);
        if (av2.ok == 0) {
            return bv_no();
        }
        let bv2: Bv = fx_eval_bool(x, b);
        if (bv2.ok == 0) {
            return bv_no();
        }
        if (is_and) {
            if (av2.v != 0 && bv2.v != 0) {
                return bv_yes(1);
            }
            return bv_yes(0);
        }
        if (av2.v != 0 || bv2.v != 0) {
            return bv_yes(1);
        }
        return bv_yes(0);
    }
    if (!fx_is_compare(x, op)) {
        return bv_no();
    }
    let xr: Iv = bx_eval_int(x, a);
    if (xr.ok == 0) {
        return bv_no();
    }
    let yr: Iv = bx_eval_int(x, b);
    if (yr.ok == 0) {
        return bv_no();
    }
    let t: i64 = fx_ty(x, a);
    var c: i32 = 0;
    if (tt_is_signed(&mut x.tt, t)) {
        if (xr.v < yr.v) {
            c = 0 - 1;
        } else if (xr.v > yr.v) {
            c = 1;
        }
    } else {
        let ux: u64 = xr.v as u64;
        let uy: u64 = yr.v as u64;
        if (ux < uy) {
            c = 0 - 1;
        } else if (ux > uy) {
            c = 1;
        }
    }
    if (sp_eqc(&mut x.sp, op, "==")) {
        return bv_yes((c == 0) as i32);
    }
    if (sp_eqc(&mut x.sp, op, "!=")) {
        return bv_yes((c != 0) as i32);
    }
    if (sp_eqc(&mut x.sp, op, "<")) {
        return bv_yes((c < 0) as i32);
    }
    if (sp_eqc(&mut x.sp, op, "<=")) {
        return bv_yes((c <= 0) as i32);
    }
    if (sp_eqc(&mut x.sp, op, ">")) {
        return bv_yes((c > 0) as i32);
    }
    return bv_yes((c >= 0) as i32);
}

fn fx_fold_const(x: &mut Bp, e: i64, op: i64, a: i64, b: i64) {
    let ka: i32 = fx_kind(x, a);
    let kb: i32 = fx_kind(x, b);
    if (ka == EX_FLOAT && kb == EX_FLOAT) {
        let r: Fv = fx_float_fold(x, op, fx_fval(x, a), fx_fval(x, b));
        if (r.ok == 1) {
            fx_set_float(x, e, r.v);
        }
        return;
    }
    if (ka == EX_FLOAT && kb == EX_INT) {
        let r2: Fv = fx_float_fold(x, op, fx_fval(x, a), fx_ivar(x, b) as f64);
        if (r2.ok == 1) {
            fx_set_float(x, e, r2.v);
        }
        return;
    }
    if (ka == EX_INT && kb == EX_FLOAT) {
        let r3: Fv = fx_float_fold(x, op, fx_ivar(x, a) as f64, fx_fval(x, b));
        if (r3.ok == 1) {
            fx_set_float(x, e, r3.v);
        }
        return;
    }
    if (ka == EX_BOOL && kb == EX_BOOL) {
        let is_and2: bool = sp_eqc(&mut x.sp, op, "&&");
        let is_or2: bool = sp_eqc(&mut x.sp, op, "||");
        if (is_and2 || is_or2) {
            let av: i32 = fx_ivar(x, a) as i32;
            let bv: i32 = fx_ivar(x, b) as i32;
            if (is_and2) {
                fx_set_bool(x, e, (av != 0 && bv != 0) as i32);
            } else {
                fx_set_bool(x, e, (av != 0 || bv != 0) as i32);
            }
            return;
        }
    }
    let xr: Iv = bx_eval_int(x, a);
    if (xr.ok == 0) {
        return;
    }
    let yr: Iv = bx_eval_int(x, b);
    if (yr.ok == 0) {
        return;
    }
    let r4: Iv = fx_int_fold(x, fx_ty(x, a), op, xr.v, yr.v);
    if (r4.ok == 0) {
        return;
    }
    if (fx_is_compare(x, op)) {
        fx_set_bool(x, e, (r4.v == 1) as i32);
    } else {
        fx_set_int(x, e, r4.v);
    }
}

fn fx_fold_bin(x: &mut Bp, e: i64, op: i64, a: i64, b: i64) {
    var changed: i32 = 0;
    if (sp_eqc(&mut x.sp, op, "&&")) {
        if (fx_true(x, a)) {
            fx_take(x, e, b);
            changed = 1;
        } else if (fx_true(x, b)) {
            fx_take(x, e, a);
            changed = 1;
        }
    } else if (sp_eqc(&mut x.sp, op, "||")) {
        if (fx_kind(x, a) == EX_BOOL) {
            if (fx_ivar(x, a) == 0) {
                fx_take(x, e, b);
                changed = 1;
            }
        }
        if (changed == 0 && fx_kind(x, b) == EX_BOOL) {
            if (fx_ivar(x, b) == 0) {
                fx_take(x, e, a);
                changed = 1;
            }
        }
    }
    if (changed == 1) {
        if (fx_kind(x, e) != EX_BIN) {
            return;
        }
    }
    var op2: i64 = 0;
    var a2: i64 = 0;
    var b2: i64 = 0;
    unsafe {
        op2 = x.na.v[e].s;
        a2 = x.na.v[e].a;
        b2 = x.na.v[e].b;
    }
    fx_fold_const(x, e, op2, a2, b2);
}

fn fx_fold_expr(x: &mut Bp, e: i64) {
    if (e <= 0) {
        return;
    }
    let k: i32 = fx_kind(x, e);
    var a: i64 = 0;
    var b: i64 = 0;
    var l: i64 = 0;
    unsafe {
        a = x.na.v[e].a;
        b = x.na.v[e].b;
        l = x.na.v[e].l;
    }
    if (k == EX_BIN || k == EX_INDEX) {
        fx_fold_expr(x, a);
        fx_fold_expr(x, b);
    } else if (k == EX_UN || k == EX_DEREF || k == EX_ADDR || k == EX_ADDRMUT || k == EX_BOXNEW || k == EX_CAST) {
        fx_fold_expr(x, a);
    } else if (k == EX_FIELD) {
        fx_fold_expr(x, a);
    } else if (k == EX_CALL || k == EX_ARRAYLIT || k == EX_ENUMLIT || k == EX_TUPLELIT) {
        let n: i64 = lp_len(&mut x.lp, l);
        var i: i64 = 0;
        while (i < n) {
            fx_fold_expr(x, lp_get(&mut x.lp, l, i));
            i += 1;
        }
    } else if (k == EX_CALLV) {
        fx_fold_expr(x, a);
        let n2: i64 = lp_len(&mut x.lp, l);
        var j: i64 = 0;
        while (j < n2) {
            fx_fold_expr(x, lp_get(&mut x.lp, l, j));
            j += 1;
        }
    } else if (k == EX_AWAIT || k == EX_POLL) {
        fx_fold_expr(x, a);
    } else if (k == EX_STRUCTLIT) {
        let n3: i64 = lp_len(&mut x.lp, l);
        var m: i64 = 0;
        while (m < n3) {
            fx_fold_expr(x, lp_get(&mut x.lp, l, m + 1));
            m += 2;
        }
    }

    let k2: i32 = fx_kind(x, e);
    var op: i64 = 0;
    unsafe { op = x.na.v[e].s; }
    var c1: i64 = 0;
    var c2: i64 = 0;
    unsafe {
        c1 = x.na.v[e].a;
        c2 = x.na.v[e].b;
    }
    if (k2 == EX_UN) {
        if (sp_eqc(&mut x.sp, op, "-")) {
            if (fx_kind(x, c1) == EX_INT) {
                fx_set_int(x, e, 0 - fx_ivar(x, c1));
                return;
            }
            if (fx_kind(x, c1) == EX_FLOAT) {
                fx_set_float(x, e, 0.0 - fx_fval(x, c1));
                return;
            }
            return;
        }
        if (sp_eqc(&mut x.sp, op, "~")) {
            let r: Iv = bx_eval_int(x, c1);
            if (r.ok == 1) {
                fx_set_int(x, e, r.v ^ (0 - 1));
            }
            return;
        }
        if (sp_eqc(&mut x.sp, op, "!")) {
            let r2: Bv = fx_eval_bool(x, c1);
            if (r2.ok == 1) {
                fx_set_bool(x, e, (r2.v == 0) as i32);
            }
            return;
        }
        return;
    }
    if (k2 == EX_CAST) {
        if (fx_ty(x, c1) == c2) {
            fx_take(x, e, c1);
        }
        return;
    }
    if (k2 == EX_BIN) {
        fx_fold_bin(x, e, op, c1, c2);
    }
}

fn fx_terminal(x: &mut Bp, st: i64) -> i32 {
    let k: i32 = fx_kind(x, st);
    if (k == ST_RETURN || k == ST_BREAK || k == ST_CONTINUE) {
        return 1;
    }
    return 0;
}

fn fx_new(x: &mut Bp, tag: i32) -> i64 {
    return na_add(&mut x.na, tag);
}

fn fx_block(x: &mut Bp, l: i64) -> i64 {
    let n: i64 = fx_new(x, ST_BLOCK);
    unsafe { x.na.v[n].l = l; }
    return n;
}

fn fx_clone(x: &mut Bp, st: i64) -> i64 {
    var k: i32 = 0;
    unsafe { k = x.na.v[st].k; }
    let n: i64 = fx_new(x, k);
    unsafe { x.na.v[n] = x.na.v[st]; }
    return n;
}

fn fx_prune(x: &mut Bp, body: i64) -> i64 {
    let out: i64 = lp_add(&mut x.lp);
    let n: i64 = lp_len(&mut x.lp, body);
    var i: i64 = 0;
    while (i < n) {
        let st: i64 = lp_get(&mut x.lp, body, i);
        let s2: i64 = fx_prune_stmt(x, st);
        if (s2 != 0) {
            lp_push(&mut x.lp, out, s2);
            if (fx_terminal(x, s2) == 1) {
                return out;
            }
        }
        i += 1;
    }
    return out;
}

fn fx_prune_stmt(x: &mut Bp, st: i64) -> i64 {
    let k: i32 = fx_kind(x, st);
    if (k == ST_BLOCK || k == ST_UNSAFE) {
        var l: i64 = 0;
        unsafe { l = x.na.v[st].l; }
        let nl: i64 = fx_prune(x, l);
        let n: i64 = fx_clone(x, st);
        unsafe { x.na.v[n].l = nl; }
        return n;
    }
    if (k == ST_IF) {
        var c: i64 = 0;
        var th: i64 = 0;
        var el: i64 = 0;
        unsafe {
            c = x.na.v[st].a;
            th = x.na.v[st].l;
            el = x.na.v[st].l2;
        }
        fx_fold_expr(x, c);
        let nt: i64 = fx_prune(x, th);
        let ne: i64 = fx_prune(x, el);
        let ct: Bv = fx_eval_bool(x, c);
        if (ct.ok == 1) {
            if (ct.v != 0) {
                return fx_block(x, nt);
            }
            let ne_len: i64 = lp_len(&mut x.lp, ne);
            if (ne_len == 0) {
                return 0;
            }
            return fx_block(x, ne);
        }
        let nt_len: i64 = lp_len(&mut x.lp, nt);
        let ne_len2: i64 = lp_len(&mut x.lp, ne);
        if (nt_len == 0 && ne_len2 == 0) {
            return 0;
        }
        let n2: i64 = fx_clone(x, st);
        unsafe {
            x.na.v[n2].a = c;
            x.na.v[n2].l = nt;
            x.na.v[n2].l2 = ne;
        }
        return n2;
    }
    if (k == ST_WHILE) {
        var c2: i64 = 0;
        var bd: i64 = 0;
        unsafe {
            c2 = x.na.v[st].a;
            bd = x.na.v[st].l;
        }
        fx_fold_expr(x, c2);
        let nb: i64 = fx_prune(x, bd);
        let ct2: Bv = fx_eval_bool(x, c2);
        if (ct2.ok == 1 && ct2.v == 0) {
            return 0;
        }
        let n3: i64 = fx_clone(x, st);
        unsafe {
            x.na.v[n3].a = c2;
            x.na.v[n3].l = nb;
        }
        return n3;
    }
    if (k == ST_LOOP) {
        var l2: i64 = 0;
        unsafe { l2 = x.na.v[st].l; }
        let nl2: i64 = fx_prune(x, l2);
        let n4: i64 = fx_clone(x, st);
        unsafe { x.na.v[n4].l = nl2; }
        return n4;
    }
    if (k == ST_FOR) {
        var a2: i64 = 0;
        var b2: i64 = 0;
        var l3: i64 = 0;
        unsafe {
            a2 = x.na.v[st].a;
            b2 = x.na.v[st].b;
            l3 = x.na.v[st].l;
        }
        fx_fold_expr(x, a2);
        fx_fold_expr(x, b2);
        let nl3: i64 = fx_prune(x, l3);
        let n5: i64 = fx_clone(x, st);
        unsafe {
            x.na.v[n5].a = a2;
            x.na.v[n5].b = b2;
            x.na.v[n5].l = nl3;
        }
        return n5;
    }
    if (k == ST_MATCH) {
        var sc: i64 = 0;
        var arms: i64 = 0;
        unsafe {
            sc = x.na.v[st].a;
            arms = x.na.v[st].l;
        }
        fx_fold_expr(x, sc);
        let na: i64 = lp_add(&mut x.lp);
        let cnt: i64 = lp_len(&mut x.lp, arms);
        var i: i64 = 0;
        while (i < cnt) {
            let arm: i64 = lp_get(&mut x.lp, arms, i);
            var bl: i64 = 0;
            unsafe { bl = x.na.v[arm].l; }
            let nbl: i64 = fx_prune(x, bl);
            let na2: i64 = fx_new(x, AR_ARM);
            unsafe { x.na.v[na2] = x.na.v[arm]; }
            unsafe { x.na.v[na2].l = nbl; }
            lp_push(&mut x.lp, na, na2);
            i += 1;
        }
        let n6: i64 = fx_clone(x, st);
        unsafe {
            x.na.v[n6].a = sc;
            x.na.v[n6].l = na;
        }
        return n6;
    }
    if (k == ST_EXPR) {
        var e1: i64 = 0;
        unsafe { e1 = x.na.v[st].a; }
        fx_fold_expr(x, e1);
        return st;
    }
    if (k == ST_LET) {
        var init: i64 = 0;
        unsafe { init = x.na.v[st].b; }
        fx_fold_expr(x, init);
        return st;
    }
    if (k == ST_ASSIGN) {
        var lhs: i64 = 0;
        var rhs: i64 = 0;
        unsafe {
            lhs = x.na.v[st].a;
            rhs = x.na.v[st].b;
        }
        fx_fold_expr(x, lhs);
        fx_fold_expr(x, rhs);
        return st;
    }
    if (k == ST_RETURN) {
        var rv: i64 = 0;
        unsafe { rv = x.na.v[st].a; }
        fx_fold_expr(x, rv);
        return st;
    }
    return st;
}

fn fx_run(x: &mut Bp, p: &mut Pr) {
    let nc: i64 = lp_len(&mut x.lp, p.c);
    var i: i64 = 0;
    while (i < nc) {
        let it: i64 = lp_get(&mut x.lp, p.c, i);
        var v: i64 = 0;
        unsafe { v = x.na.v[it].b; }
        fx_fold_expr(x, v);
        i += 1;
    }
    let nf: i64 = lp_len(&mut x.lp, p.f);
    var j: i64 = 0;
    while (j < nf) {
        let fn_: i64 = lp_get(&mut x.lp, p.f, j);
        var bd: i64 = 0;
        unsafe { bd = x.na.v[fn_].l3; }
        let nbd: i64 = fx_prune(x, bd);
        unsafe { x.na.v[fn_].l3 = nbd; }
        j += 1;
    }
}
