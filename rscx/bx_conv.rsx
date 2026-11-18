include "bx_parse.rsx";

struct Cv {
    map: ptr<i64>,
    cap: i64
}

fn cv_new() -> Cv {
    var c: Cv = zero(Cv);
    c.cap = 4096;
    c.map = malloc((c.cap as u64) * sizeof(i64)) as ptr<i64>;
    if (c.map == null) {
        c.cap = 0;
        return c;
    }
    var i: i64 = 0;
    while (i < c.cap) {
        unsafe { c.map[i] = 0; }
        i += 1;
    }
    return c;
}

fn cv_free(c: &mut Cv) {
    if (c.map != null) {
        free(c.map as ptr<u8>);
        c.map = null;
    }
    c.cap = 0;
}

fn cv_get(c: &mut Cv, t: i64) -> i64 {
    if (t <= 0 || t >= c.cap) {
        return 0;
    }
    var v: i64 = 0;
    unsafe { v = c.map[t]; }
    return v;
}

fn cv_set(c: &mut Cv, t: i64, v: i64) {
    if (t <= 0) {
        return;
    }
    if (t >= c.cap) {
        var nc: i64 = c.cap;
        if (nc < 16) {
            nc = 16;
        }
        while (nc <= t) {
            nc = nc * 2;
        }
        var np: ptr<i64> = realloc(c.map as ptr<u8>, (nc as u64) * sizeof(i64)) as ptr<i64>;
        if (np == null) {
            return;
        }
        c.map = np;
        var i: i64 = c.cap;
        while (i < nc) {
            unsafe { c.map[i] = 0; }
            i += 1;
        }
        c.cap = nc;
    }
    unsafe { c.map[t] = v; }
}

fn cv_prim(c: &mut Cv, x: &mut Bp, t: i64, tag: i32) -> i64 {
    let n: i64 = na_add(&mut x.na, tag);
    cv_set(c, t, n);
    return n;
}

fn cv_tup_list(c: &mut Cv, x: &mut Bp, l: i64) -> i64 {
    let out: i64 = lp_add(&mut x.lp);
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 0;
    while (i < n) {
        let t: i64 = lp_get(&mut x.lp, l, i);
        let v: i64 = cv_ty(c, x, t);
        lp_push(&mut x.lp, out, v);
        i += 1;
    }
    return out;
}

fn cv_ty(c: &mut Cv, x: &mut Bp, t: i64) -> i64 {
    if (t <= 0) {
        return 0;
    }
    let got: i64 = cv_get(c, t);
    if (got != 0) {
        return got;
    }
    let k: i32 = tt_tag(&mut x.tt, t);
    if (k == TT_ERR) {
        return 0;
    }
    if (k >= 1 && k <= 12) {
        return cv_prim(c, x, t, k);
    }
    if (k == TT_INFER) {
        return cv_prim(c, x, t, TY_INFER);
    }
    var ea: i64 = 0;
    var eb: i64 = 0;
    var en: i64 = 0;
    var es: i64 = 0;
    var el: i64 = 0;
    unsafe {
        ea = x.tt.v[t].a;
        eb = x.tt.v[t].b;
        en = x.tt.v[t].n;
        es = x.tt.v[t].s;
        el = x.tt.v[t].l;
    }
    if (k == TT_PTR) {
        let cv: i64 = cv_ty(c, x, ea);
        let n: i64 = cv_prim(c, x, t, TY_PTR);
        unsafe { x.na.v[n].a = cv; }
        return n;
    }
    if (k == TT_REF) {
        let cv: i64 = cv_ty(c, x, ea);
        let n: i64 = cv_prim(c, x, t, TY_REF);
        unsafe { x.na.v[n].a = cv; }
        if (eb == 1) {
            unsafe { x.na.v[n].m = 1; }
        }
        return n;
    }
    if (k == TT_BOX) {
        let cv: i64 = cv_ty(c, x, ea);
        let n: i64 = cv_prim(c, x, t, TY_HEAP);
        unsafe { x.na.v[n].a = cv; }
        return n;
    }
    if (k == TT_ARRAY) {
        let cv: i64 = cv_ty(c, x, ea);
        let n: i64 = cv_prim(c, x, t, TY_ARRAY);
        unsafe {
            x.na.v[n].a = cv;
            x.na.v[n].n = en;
        }
        if (eb == 1) {
            unsafe {
                x.na.v[n].m = 1;
                x.na.v[n].s = es;
            }
        }
        return n;
    }
    if (k == TT_STRUCT || k == TT_ENUM) {
        let n: i64 = cv_prim(c, x, t, TY_NAMED);
        unsafe { x.na.v[n].s = es; }
        return n;
    }
    if (k == TT_TUPLE) {
        let out: i64 = cv_tup_list(c, x, el);
        let n: i64 = cv_prim(c, x, t, TY_TUPLE);
        unsafe { x.na.v[n].l = out; }
        return n;
    }
    if (k == TT_FN || k == TT_FNC) {
        let out: i64 = cv_tup_list(c, x, el);
        let rt: i64 = cv_ty(c, x, ea);
        var tag: i32 = TY_FN;
        if (k == TT_FNC) {
            tag = TY_FNC;
        }
        let n: i64 = cv_prim(c, x, t, tag);
        unsafe {
            x.na.v[n].l = out;
            x.na.v[n].a = rt;
        }
        return n;
    }
    if (k == TT_TASK) {
        let cv: i64 = cv_ty(c, x, ea);
        let n: i64 = cv_prim(c, x, t, TY_TASK);
        unsafe { x.na.v[n].a = cv; }
        return n;
    }
    if (k == TT_VAR) {
        let n: i64 = cv_prim(c, x, t, TY_PARAM);
        unsafe { x.na.v[n].s = es; }
        return n;
    }
    return 0;
}

fn cv_slot_a(c: &mut Cv, x: &mut Bp, n: i64, t: i64) {
    let v: i64 = cv_ty(c, x, t);
    unsafe { x.na.v[n].a = v; }
}

fn cv_slot_b(c: &mut Cv, x: &mut Bp, n: i64, t: i64) {
    let v: i64 = cv_ty(c, x, t);
    unsafe { x.na.v[n].b = v; }
}

fn cv_ex_lst(c: &mut Cv, x: &mut Bp, l: i64) {
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 0;
    while (i < n) {
        let e: i64 = lp_get(&mut x.lp, l, i);
        cv_ex(c, x, e);
        i += 1;
    }
}

fn cv_ex(c: &mut Cv, x: &mut Bp, e: i64) {
    if (e <= 0) {
        return;
    }
    var k: i32 = 0;
    unsafe { k = x.na.v[e].k; }
    if (k == EX_INT || k == EX_FLOAT || k == EX_STR || k == EX_BOOL || k == EX_NULL || k == EX_VAR || k == EX_FNREF) {
        return;
    }
    if (k == EX_SIZEOF || k == EX_ZERO) {
        var t0: i64 = 0;
        unsafe { t0 = x.na.v[e].a; }
        cv_slot_a(c, x, e, t0);
        return;
    }
    if (k == EX_CAST) {
        var a0: i64 = 0;
        var b0: i64 = 0;
        unsafe {
            a0 = x.na.v[e].a;
            b0 = x.na.v[e].b;
        }
        cv_ex(c, x, a0);
        cv_slot_b(c, x, e, b0);
        return;
    }
    var a1: i64 = 0;
    var b1: i64 = 0;
    var l1: i64 = 0;
    unsafe {
        a1 = x.na.v[e].a;
        b1 = x.na.v[e].b;
        l1 = x.na.v[e].l;
    }
    if (k == EX_BIN) {
        cv_ex(c, x, a1);
        cv_ex(c, x, b1);
    } else if (k == EX_INDEX) {
        cv_ex(c, x, a1);
        cv_ex(c, x, b1);
    } else if (k == EX_UN || k == EX_FIELD || k == EX_DEREF || k == EX_ADDR || k == EX_ADDRMUT ||
               k == EX_BOXNEW || k == EX_AWAIT || k == EX_POLL) {
        cv_ex(c, x, a1);
    } else if (k == EX_CALL || k == EX_ARRAYLIT || k == EX_ENUMLIT || k == EX_TUPLELIT) {
        cv_ex_lst(c, x, l1);
    } else if (k == EX_CALLV || k == EX_METHOD) {
        cv_ex(c, x, a1);
        cv_ex_lst(c, x, l1);
    } else if (k == EX_STRUCTLIT) {
        let n: i64 = lp_len(&mut x.lp, l1);
        var i: i64 = 0;
        while (i < n) {
            let v: i64 = lp_get(&mut x.lp, l1, i + 1);
            cv_ex(c, x, v);
            i += 2;
        }
    }
}

fn cv_blk(c: &mut Cv, x: &mut Bp, l: i64) {
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 0;
    while (i < n) {
        let st: i64 = lp_get(&mut x.lp, l, i);
        cv_st(c, x, st);
        i += 1;
    }
}

fn cv_st(c: &mut Cv, x: &mut Bp, st: i64) {
    if (st <= 0) {
        return;
    }
    var k: i32 = 0;
    unsafe { k = x.na.v[st].k; }
    var a0: i64 = 0;
    var b0: i64 = 0;
    var l0: i64 = 0;
    var l20: i64 = 0;
    unsafe {
        a0 = x.na.v[st].a;
        b0 = x.na.v[st].b;
        l0 = x.na.v[st].l;
        l20 = x.na.v[st].l2;
    }
    if (k == ST_LET) {
        cv_slot_a(c, x, st, a0);
        cv_ex(c, x, b0);
    } else if (k == ST_ASSIGN) {
        cv_ex(c, x, a0);
        cv_ex(c, x, b0);
    } else if (k == ST_EXPR) {
        cv_ex(c, x, a0);
    } else if (k == ST_BLOCK || k == ST_UNSAFE || k == ST_LOOP) {
        cv_blk(c, x, l0);
    } else if (k == ST_IF) {
        cv_ex(c, x, a0);
        cv_blk(c, x, l0);
        cv_blk(c, x, l20);
    } else if (k == ST_WHILE) {
        cv_ex(c, x, a0);
        cv_blk(c, x, l0);
    } else if (k == ST_FOR) {
        cv_ex(c, x, a0);
        cv_ex(c, x, b0);
        cv_blk(c, x, l0);
    } else if (k == ST_MATCH) {
        cv_ex(c, x, a0);
        let n: i64 = lp_len(&mut x.lp, l0);
        var i: i64 = 0;
        while (i < n) {
            let arm: i64 = lp_get(&mut x.lp, l0, i);
            var bl: i64 = 0;
            unsafe { bl = x.na.v[arm].l; }
            cv_blk(c, x, bl);
            i += 1;
        }
    } else if (k == ST_LABEL) {
        var inner: i64 = 0;
        unsafe { inner = x.na.v[st].a; }
        cv_st(c, x, inner);
    } else if (k == ST_RETURN) {
        cv_ex(c, x, a0);
    }
}

fn cv_ty_pairs(c: &mut Cv, x: &mut Bp, l: i64) {
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 1;
    while (i < n) {
        let t: i64 = lp_get(&mut x.lp, l, i);
        let v: i64 = cv_ty(c, x, t);
        lp_set(&mut x.lp, l, i, v);
        i += 2;
    }
}

fn cv_it(c: &mut Cv, x: &mut Bp, it: i64) {
    var k: i32 = 0;
    unsafe { k = x.na.v[it].k; }
    if (k == IT_CONST || k == IT_STATIC) {
        var a0: i64 = 0;
        var b0: i64 = 0;
        unsafe {
            a0 = x.na.v[it].a;
            b0 = x.na.v[it].b;
        }
        cv_slot_a(c, x, it, a0);
        cv_ex(c, x, b0);
        return;
    }
    if (k == IT_STRUCT) {
        var l0: i64 = 0;
        unsafe { l0 = x.na.v[it].l; }
        cv_ty_pairs(c, x, l0);
        return;
    }
    if (k == IT_ENUM) {
        var l0: i64 = 0;
        unsafe { l0 = x.na.v[it].l; }
        let n: i64 = lp_len(&mut x.lp, l0);
        var i: i64 = 1;
        while (i < n) {
            let pl: i64 = lp_get(&mut x.lp, l0, i);
            let np: i64 = lp_len(&mut x.lp, pl);
            var j: i64 = 0;
            while (j < np) {
                let t: i64 = lp_get(&mut x.lp, pl, j);
                let v: i64 = cv_ty(c, x, t);
                lp_set(&mut x.lp, pl, j, v);
                j += 1;
            }
            i += 2;
        }
        return;
    }
    if (k == IT_EXTERN) {
        var a0: i64 = 0;
        var l0: i64 = 0;
        unsafe {
            a0 = x.na.v[it].a;
            l0 = x.na.v[it].l;
        }
        let n: i64 = lp_len(&mut x.lp, l0);
        var i: i64 = 0;
        while (i < n) {
            let t: i64 = lp_get(&mut x.lp, l0, i);
            let v: i64 = cv_ty(c, x, t);
            lp_set(&mut x.lp, l0, i, v);
            i += 1;
        }
        cv_slot_a(c, x, it, a0);
        return;
    }
    if (k == IT_FN) {
        var a0: i64 = 0;
        var l20: i64 = 0;
        var l30: i64 = 0;
        unsafe {
            a0 = x.na.v[it].a;
            l20 = x.na.v[it].l2;
            l30 = x.na.v[it].l3;
        }
        cv_ty_pairs(c, x, l20);
        cv_slot_a(c, x, it, a0);
        cv_blk(c, x, l30);
    }
}

fn bx_conv(x: &mut Bp, p: &mut Pr) {
    var c: Cv = cv_new();
    if (c.map == null) {
        return;
    }
    var g: i64 = 0;
    while (g < 6) {
        var l: i64 = 0;
        if (g == 0) {
            l = p.c;
        } else if (g == 1) {
            l = p.g;
        } else if (g == 2) {
            l = p.s;
        } else if (g == 3) {
            l = p.e;
        } else if (g == 4) {
            l = p.x;
        } else {
            l = p.f;
        }
        let n: i64 = lp_len(&mut x.lp, l);
        var i: i64 = 0;
        while (i < n) {
            let it: i64 = lp_get(&mut x.lp, l, i);
            cv_it(&mut c, x, it);
            i += 1;
        }
        g += 1;
    }
    cv_free(&mut c);
}
