include "base.rsx";

extern fn malloc(n: u64) -> ptr<u8>;
extern fn realloc(p: ptr<u8>, n: u64) -> ptr<u8>;
extern fn free(p: ptr<u8>) -> void;

struct Pr {
    c: i64,
    g: i64,
    s: i64,
    e: i64,
    x: i64,
    f: i64
}

const TY_I8: i32 = 1;
const TY_I16: i32 = 2;
const TY_I32: i32 = 3;
const TY_I64: i32 = 4;
const TY_U8: i32 = 5;
const TY_U16: i32 = 6;
const TY_U32: i32 = 7;
const TY_U64: i32 = 8;
const TY_F32: i32 = 9;
const TY_F64: i32 = 10;
const TY_BOOL: i32 = 11;
const TY_VOID: i32 = 12;
const TY_PTR: i32 = 13;
const TY_REF: i32 = 14;
const TY_HEAP: i32 = 15;
const TY_ARRAY: i32 = 16;
const TY_NAMED: i32 = 17;
const TY_INFER: i32 = 18;
const TY_TUPLE: i32 = 19;
const TY_FN: i32 = 20;
const TY_FNC: i32 = 21;
const TY_TASK: i32 = 22;
const TY_PARAM: i32 = 23;
const TY_FAT: i32 = 24;
const TY_DYN: i32 = 25;
const TY_SELF: i32 = 26;

const EX_INT: i32 = 40;
const EX_FLOAT: i32 = 41;
const EX_STR: i32 = 42;
const EX_BOOL: i32 = 43;
const EX_NULL: i32 = 44;
const EX_VAR: i32 = 45;
const EX_BIN: i32 = 46;
const EX_UN: i32 = 47;
const EX_CALL: i32 = 48;
const EX_INDEX: i32 = 49;
const EX_FIELD: i32 = 50;
const EX_DEREF: i32 = 51;
const EX_ADDR: i32 = 52;
const EX_ADDRMUT: i32 = 53;
const EX_BOXNEW: i32 = 54;
const EX_CAST: i32 = 55;
const EX_SIZEOF: i32 = 56;
const EX_ZERO: i32 = 57;
const EX_STRUCTLIT: i32 = 58;
const EX_ARRAYLIT: i32 = 59;
const EX_ENUMLIT: i32 = 60;
const EX_TUPLELIT: i32 = 61;
const EX_FNREF: i32 = 62;
const EX_CALLV: i32 = 63;
const EX_AWAIT: i32 = 64;
const EX_POLL: i32 = 65;
const EX_METHOD: i32 = 66;

const ST_LET: i32 = 80;
const ST_ASSIGN: i32 = 81;
const ST_EXPR: i32 = 82;
const ST_BLOCK: i32 = 83;
const ST_UNSAFE: i32 = 84;
const ST_IF: i32 = 85;
const ST_WHILE: i32 = 86;
const ST_LOOP: i32 = 87;
const ST_FOR: i32 = 88;
const ST_MATCH: i32 = 89;
const ST_BREAK: i32 = 90;
const ST_CONTINUE: i32 = 91;
const ST_LABEL: i32 = 92;
const ST_RETURN: i32 = 93;

const IT_CONST: i32 = 100;
const IT_STATIC: i32 = 101;
const IT_STRUCT: i32 = 102;
const IT_ENUM: i32 = 103;
const IT_EXTERN: i32 = 104;
const IT_FN: i32 = 105;
const IT_TRAIT: i32 = 106;
const IT_TM: i32 = 107;

const PT_WILD: i32 = 110;
const PT_LIT: i32 = 111;
const PT_RANGE: i32 = 112;
const PT_VARIANT: i32 = 113;

const AR_ARM: i32 = 115;

const NA_SHIFT: i64 = 12;
const NA_BLK: i64 = 4096;
const NA_MASK: i64 = 4095;

struct Nd {
    k: i32,
    m: i32,
    s: i32,
    s2: i32,
    a: i32,
    b: i32,
    c: i32,
    l: i32,
    l2: i32,
    l3: i32,
    ty: i32,
    n: i64,
    f: f64
}

struct Na {
    v: ptr<ptr<Nd>>,
    n: i64,
    nb: i64,
    bcap: i64,
    bad: i32
}

fn na_at(v: ptr<ptr<Nd>>, id: i64) -> ptr<Nd> {
    var q: ptr<Nd> = null;
    var off: i64 = 0;
    unsafe {
        q = v[id >> NA_SHIFT];
        off = id & NA_MASK;
    }
    unsafe {
        return q + off;
    }
}

fn na_blk(a: &mut Na, blk: i64) -> ptr<Nd> {
    var q: ptr<Nd> = null;
    unsafe { q = a.v[blk]; }
    if (q != null) {
        return q;
    }
    q = malloc((NA_BLK as u64) * sizeof(Nd)) as ptr<Nd>;
    if (q == null) {
        a.bad = 1;
        return null;
    }
    unsafe { memset(q as ptr<u8>, 0, (NA_BLK as u64) * sizeof(Nd)); }
    unsafe { a.v[blk] = q; }
    if (a.nb < blk + 1) {
        a.nb = blk + 1;
    }
    return q;
}

fn na_new() -> Na {
    var a: Na = zero(Na);
    a.bcap = 64;
    a.v = malloc((a.bcap as u64) * sizeof(ptr<Nd>)) as ptr<ptr<Nd>>;
    if (a.v == null) {
        a.bad = 1;
        return a;
    }
    unsafe { memset(a.v as ptr<u8>, 0, (a.bcap as u64) * sizeof(ptr<Nd>)); }
    if (na_blk(&mut a, 0) == null) {
        return a;
    }
    a.n = 1;
    return a;
}

fn na_copy(v: ptr<ptr<Nd>>, dst: i64, src: i64) {
    var t: Nd = zero(Nd);
    unsafe { t = na_at(v, src)[0]; }
    unsafe { na_at(v, dst)[0] = t; }
}

fn na_free(a: &mut Na) {
    if (a.v != null) {
        var i: i64 = 0;
        unsafe {
            while (i < a.bcap) {
                let q: ptr<Nd> = a.v[i];
                if (q != null) {
                    free(q as ptr<u8>);
                    a.v[i] = null;
                }
                i += 1;
            }
            free(a.v as ptr<u8>);
        }
        a.v = null;
    }
    a.n = 0;
    a.nb = 0;
    a.bcap = 0;
}

fn na_add(a: &mut Na, k: i32) -> i64 {
    if (a.bad == 1) {
        return 0;
    }
    let id: i64 = a.n;
    let blk: i64 = id >> NA_SHIFT;
    if (blk >= a.bcap) {
        var nb: i64 = a.bcap;
        while (nb <= blk) {
            nb = nb + nb / 2;
        }
        var raw: ptr<u8> = realloc(a.v as ptr<u8>, (nb as u64) * sizeof(ptr<Nd>));
        if (raw == null) {
            a.bad = 1;
            return 0;
        }
        var dir: ptr<ptr<Nd>> = raw as ptr<ptr<Nd>>;
        unsafe {
            let tail: ptr<u8> = (dir + a.bcap) as ptr<u8>;
            memset(tail, 0, ((nb - a.bcap) as u64) * sizeof(ptr<Nd>));
        }
        a.v = dir;
        a.bcap = nb;
    }
    if (na_blk(a, blk) == null) {
        return 0;
    }
    unsafe { na_at(a.v, id).k = k; }
    a.n = id + 1;
    return id;
}

fn ty_w(a: &mut Na, lp: &mut Lp, sp: &mut Sp, b: &mut Sb, t: i64) {
    var k: i32 = 0;
    unsafe { k = na_at(a.v, t).k; }
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
        sb_puts(b, "(infer)");
    } else if (k == TY_PTR) {
        sb_puts(b, "(ptr ");
        var c: i64 = 0;
        unsafe { c = (na_at(a.v, t).a as i64); }
        ty_w(a, lp, sp, b, c);
        sb_putc(b, 41);
    } else if (k == TY_REF) {
        var mu: i32 = 0;
        unsafe { mu = na_at(a.v, t).m; }
        if (mu == 1) {
            sb_puts(b, "(refmut ");
        } else {
            sb_puts(b, "(ref ");
        }
        var c: i64 = 0;
        unsafe { c = (na_at(a.v, t).a as i64); }
        ty_w(a, lp, sp, b, c);
        sb_putc(b, 41);
    } else if (k == TY_HEAP) {
        sb_puts(b, "(box ");
        var c: i64 = 0;
        unsafe { c = (na_at(a.v, t).a as i64); }
        ty_w(a, lp, sp, b, c);
        sb_putc(b, 41);
    } else if (k == TY_ARRAY) {
        sb_puts(b, "(array ");
        var c: i64 = 0;
        var sz: i64 = 0;
        var nm: i64 = 0;
        var us: i32 = 0;
        unsafe {
            c = (na_at(a.v, t).a as i64);
            sz = na_at(a.v, t).n;
            nm = (na_at(a.v, t).s as i64);
            us = na_at(a.v, t).m;
        }
        ty_w(a, lp, sp, b, c);
        sb_putc(b, 32);
        if (us == 1) {
            sp_put(sp, b, nm);
        } else {
            sb_i64(b, sz);
        }
        sb_putc(b, 41);
    } else if (k == TY_NAMED) {
        sb_puts(b, "(named ");
        var nm: i64 = 0;
        unsafe { nm = (na_at(a.v, t).s as i64); }
        sp_put(sp, b, nm);
        sb_putc(b, 41);
    } else if (k == TY_TUPLE) {
        sb_puts(b, "(tup");
        var l: i64 = 0;
        unsafe { l = (na_at(a.v, t).l as i64); }
        let n: i64 = lp_len(lp, l);
        var i: i64 = 0;
        while (i < n) {
            sb_putc(b, 32);
            ty_w(a, lp, sp, b, lp_get(lp, l, i));
            i += 1;
        }
        sb_putc(b, 41);
    } else if (k == TY_FN || k == TY_FNC) {
        if (k == TY_FN) {
            sb_puts(b, "(fnty (");
        } else {
            sb_puts(b, "(fntyc (");
        }
        var l: i64 = 0;
        var r: i64 = 0;
        unsafe {
            l = (na_at(a.v, t).l as i64);
            r = (na_at(a.v, t).a as i64);
        }
        let n: i64 = lp_len(lp, l);
        var i: i64 = 0;
        while (i < n) {
            if (i > 0) {
                sb_putc(b, 32);
            }
            ty_w(a, lp, sp, b, lp_get(lp, l, i));
            i += 1;
        }
        sb_puts(b, ") ");
        ty_w(a, lp, sp, b, r);
        sb_putc(b, 41);
    } else if (k == TY_TASK) {
        sb_puts(b, "(task ");
        var c: i64 = 0;
        unsafe { c = (na_at(a.v, t).a as i64); }
        ty_w(a, lp, sp, b, c);
        sb_putc(b, 41);
    } else if (k == TY_PARAM) {
        sb_puts(b, "(var ");
        var nm: i64 = 0;
        unsafe { nm = (na_at(a.v, t).s as i64); }
        sp_put(sp, b, nm);
        sb_putc(b, 41);
    } else if (k == TY_FAT || k == TY_DYN) {
        sb_puts(b, "(named ");
        var nm: i64 = 0;
        unsafe { nm = (na_at(a.v, t).s as i64); }
        sp_put(sp, b, nm);
        sb_putc(b, 41);
    } else if (k == TY_SELF) {
        sb_puts(b, "(named Self)");
    }
}

fn ex_w(a: &mut Na, lp: &mut Lp, sp: &mut Sp, b: &mut Sb, e: i64) {
    var k: i32 = 0;
    unsafe { k = na_at(a.v, e).k; }
    if (k == EX_INT) {
        var v: i64 = 0;
        unsafe { v = na_at(a.v, e).n; }
        sb_puts(b, "(int ");
        sb_i64(b, v);
        sb_putc(b, 41);
    } else if (k == EX_FLOAT) {
        var v: f64 = 0.0;
        unsafe { v = na_at(a.v, e).f; }
        sb_puts(b, "(float ");
        sb_f64_dbg(b, v);
        sb_putc(b, 41);
    } else if (k == EX_STR) {
        var s: i64 = 0;
        unsafe { s = (na_at(a.v, e).s as i64); }
        sb_puts(b, "(str ");
        sb_esc(b, sp_ptr(sp, s), sp_len(sp, s));
        sb_putc(b, 41);
    } else if (k == EX_BOOL) {
        var v: i64 = 0;
        unsafe { v = na_at(a.v, e).n; }
        if (v == 1) {
            sb_puts(b, "(bool true)");
        } else {
            sb_puts(b, "(bool false)");
        }
    } else if (k == EX_NULL) {
        sb_puts(b, "(null)");
    } else if (k == EX_VAR) {
        var s: i64 = 0;
        unsafe { s = (na_at(a.v, e).s as i64); }
        sb_puts(b, "(var ");
        sp_put(sp, b, s);
        sb_putc(b, 41);
    } else if (k == EX_BIN) {
        sb_puts(b, "(bin ");
        var s: i64 = 0;
        var x: i64 = 0;
        var y: i64 = 0;
        unsafe {
            s = (na_at(a.v, e).s as i64);
            x = (na_at(a.v, e).a as i64);
            y = (na_at(a.v, e).b as i64);
        }
        sp_put(sp, b, s);
        sb_putc(b, 32);
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 32);
        ex_w(a, lp, sp, b, y);
        sb_putc(b, 41);
    } else if (k == EX_UN) {
        sb_puts(b, "(un ");
        var s: i64 = 0;
        var x: i64 = 0;
        unsafe {
            s = (na_at(a.v, e).s as i64);
            x = (na_at(a.v, e).a as i64);
        }
        sp_put(sp, b, s);
        sb_putc(b, 32);
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 41);
    } else if (k == EX_CALL) {
        sb_puts(b, "(call ");
        var s: i64 = 0;
        var l: i64 = 0;
        unsafe {
            s = (na_at(a.v, e).s as i64);
            l = (na_at(a.v, e).l as i64);
        }
        sp_put(sp, b, s);
        let n: i64 = lp_len(lp, l);
        var i: i64 = 0;
        while (i < n) {
            sb_putc(b, 32);
            ex_w(a, lp, sp, b, lp_get(lp, l, i));
            i += 1;
        }
        sb_putc(b, 41);
    } else if (k == EX_INDEX) {
        sb_puts(b, "(index ");
        var x: i64 = 0;
        var y: i64 = 0;
        unsafe {
            x = (na_at(a.v, e).a as i64);
            y = (na_at(a.v, e).b as i64);
        }
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 32);
        ex_w(a, lp, sp, b, y);
        sb_putc(b, 41);
    } else if (k == EX_FIELD) {
        sb_puts(b, "(field ");
        var x: i64 = 0;
        var s: i64 = 0;
        unsafe {
            x = (na_at(a.v, e).a as i64);
            s = (na_at(a.v, e).s as i64);
        }
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 32);
        sp_put(sp, b, s);
        sb_putc(b, 41);
    } else if (k == EX_DEREF) {
        sb_puts(b, "(deref ");
        var x: i64 = 0;
        unsafe { x = (na_at(a.v, e).a as i64); }
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 41);
    } else if (k == EX_ADDR) {
        sb_puts(b, "(addr ");
        var x: i64 = 0;
        unsafe { x = (na_at(a.v, e).a as i64); }
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 41);
    } else if (k == EX_ADDRMUT) {
        sb_puts(b, "(addrmut ");
        var x: i64 = 0;
        unsafe { x = (na_at(a.v, e).a as i64); }
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 41);
    } else if (k == EX_BOXNEW) {
        sb_puts(b, "(boxnew ");
        var x: i64 = 0;
        unsafe { x = (na_at(a.v, e).a as i64); }
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 41);
    } else if (k == EX_CAST) {
        sb_puts(b, "(cast ");
        var x: i64 = 0;
        var t: i64 = 0;
        unsafe {
            x = (na_at(a.v, e).a as i64);
            t = (na_at(a.v, e).b as i64);
        }
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 32);
        ty_w(a, lp, sp, b, t);
        sb_putc(b, 41);
    } else if (k == EX_SIZEOF) {
        sb_puts(b, "(sizeof ");
        var t: i64 = 0;
        unsafe { t = (na_at(a.v, e).a as i64); }
        ty_w(a, lp, sp, b, t);
        sb_putc(b, 41);
    } else if (k == EX_ZERO) {
        sb_puts(b, "(zero ");
        var t: i64 = 0;
        unsafe { t = (na_at(a.v, e).a as i64); }
        ty_w(a, lp, sp, b, t);
        sb_putc(b, 41);
    } else if (k == EX_STRUCTLIT) {
        sb_puts(b, "(structlit ");
        var s: i64 = 0;
        var l: i64 = 0;
        unsafe {
            s = (na_at(a.v, e).s as i64);
            l = (na_at(a.v, e).l as i64);
        }
        sp_put(sp, b, s);
        let n: i64 = lp_len(lp, l);
        var i: i64 = 0;
        while (i < n) {
            sb_puts(b, " (field ");
            sp_put(sp, b, lp_get(lp, l, i));
            sb_putc(b, 32);
            ex_w(a, lp, sp, b, lp_get(lp, l, i + 1));
            sb_putc(b, 41);
            i += 2;
        }
        sb_putc(b, 41);
    } else if (k == EX_ARRAYLIT) {
        sb_puts(b, "(arraylit");
        var l: i64 = 0;
        unsafe { l = (na_at(a.v, e).l as i64); }
        let n: i64 = lp_len(lp, l);
        var i: i64 = 0;
        while (i < n) {
            sb_putc(b, 32);
            ex_w(a, lp, sp, b, lp_get(lp, l, i));
            i += 1;
        }
        sb_putc(b, 41);
    } else if (k == EX_ENUMLIT) {
        sb_puts(b, "(enumlit ");
        var s: i64 = 0;
        var s2: i64 = 0;
        var l: i64 = 0;
        unsafe {
            s = (na_at(a.v, e).s as i64);
            s2 = (na_at(a.v, e).s2 as i64);
            l = (na_at(a.v, e).l as i64);
        }
        sp_put(sp, b, s);
        sb_putc(b, 32);
        sp_put(sp, b, s2);
        let n: i64 = lp_len(lp, l);
        var i: i64 = 0;
        while (i < n) {
            sb_putc(b, 32);
            ex_w(a, lp, sp, b, lp_get(lp, l, i));
            i += 1;
        }
        sb_putc(b, 41);
    } else if (k == EX_TUPLELIT) {
        sb_puts(b, "(tuplelit");
        var l: i64 = 0;
        unsafe { l = (na_at(a.v, e).l as i64); }
        let n: i64 = lp_len(lp, l);
        var i: i64 = 0;
        while (i < n) {
            sb_putc(b, 32);
            ex_w(a, lp, sp, b, lp_get(lp, l, i));
            i += 1;
        }
        sb_putc(b, 41);
    } else if (k == EX_FNREF) {
        sb_puts(b, "(fnref ");
        var s: i64 = 0;
        unsafe { s = (na_at(a.v, e).s as i64); }
        sp_put(sp, b, s);
        sb_putc(b, 41);
    } else if (k == EX_CALLV) {
        sb_puts(b, "(callv ");
        var x: i64 = 0;
        var l: i64 = 0;
        unsafe {
            x = (na_at(a.v, e).a as i64);
            l = (na_at(a.v, e).l as i64);
        }
        ex_w(a, lp, sp, b, x);
        let n: i64 = lp_len(lp, l);
        var i: i64 = 0;
        while (i < n) {
            sb_putc(b, 32);
            ex_w(a, lp, sp, b, lp_get(lp, l, i));
            i += 1;
        }
        sb_putc(b, 41);
    } else if (k == EX_AWAIT) {
        sb_puts(b, "(await ");
        var x: i64 = 0;
        unsafe { x = (na_at(a.v, e).a as i64); }
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 41);
    } else if (k == EX_POLL) {
        sb_puts(b, "(poll ");
        var x: i64 = 0;
        unsafe { x = (na_at(a.v, e).a as i64); }
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 41);
    } else if (k == EX_METHOD) {
        sb_puts(b, "(method ");
        var x: i64 = 0;
        var s: i64 = 0;
        var l: i64 = 0;
        unsafe {
            x = (na_at(a.v, e).a as i64);
            s = (na_at(a.v, e).s as i64);
            l = (na_at(a.v, e).l as i64);
        }
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 32);
        sp_put(sp, b, s);
        let n: i64 = lp_len(lp, l);
        var i: i64 = 0;
        while (i < n) {
            sb_putc(b, 32);
            ex_w(a, lp, sp, b, lp_get(lp, l, i));
            i += 1;
        }
        sb_putc(b, 41);
    }
}

fn ind_w(b: &mut Sb, d: i64) {
    var i: i64 = 0;
    while (i < d) {
        sb_puts(b, "  ");
        i += 1;
    }
}

fn st_w(a: &mut Na, lp: &mut Lp, sp: &mut Sp, b: &mut Sb, st: i64, d: i64) {
    var k: i32 = 0;
    unsafe { k = na_at(a.v, st).k; }
    if (k == ST_LET) {
        ind_w(b, d);
        var mu: i32 = 0;
        var s: i64 = 0;
        var t: i64 = 0;
        var init: i64 = 0;
        unsafe {
            mu = na_at(a.v, st).m;
            s = (na_at(a.v, st).s as i64);
            t = (na_at(a.v, st).a as i64);
            init = (na_at(a.v, st).b as i64);
        }
        if (mu == 1) {
            sb_puts(b, "(var ");
        } else {
            sb_puts(b, "(let ");
        }
        sp_put(sp, b, s);
        sb_putc(b, 32);
        ty_w(a, lp, sp, b, t);
        if (init != 0) {
            sb_putc(b, 32);
            ex_w(a, lp, sp, b, init);
        }
        sb_puts(b, ")\n");
    } else if (k == ST_ASSIGN) {
        ind_w(b, d);
        var s: i64 = 0;
        var x: i64 = 0;
        var y: i64 = 0;
        unsafe {
            s = (na_at(a.v, st).s as i64);
            x = (na_at(a.v, st).a as i64);
            y = (na_at(a.v, st).b as i64);
        }
        sb_puts(b, "(assign ");
        sp_put(sp, b, s);
        sb_putc(b, 32);
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 32);
        ex_w(a, lp, sp, b, y);
        sb_puts(b, ")\n");
    } else if (k == ST_EXPR) {
        ind_w(b, d);
        var x: i64 = 0;
        unsafe { x = (na_at(a.v, st).a as i64); }
        sb_puts(b, "(expr ");
        ex_w(a, lp, sp, b, x);
        sb_puts(b, ")\n");
    } else if (k == ST_BLOCK || k == ST_UNSAFE) {
        ind_w(b, d);
        if (k == ST_BLOCK) {
            sb_puts(b, "(block\n");
        } else {
            sb_puts(b, "(unsafe\n");
        }
        var l: i64 = 0;
        unsafe { l = (na_at(a.v, st).l as i64); }
        st_blk(a, lp, sp, b, l, d + 1);
        ind_w(b, d);
        sb_puts(b, ")\n");
    } else if (k == ST_IF) {
        ind_w(b, d);
        var c: i64 = 0;
        var tl: i64 = 0;
        var el: i64 = 0;
        unsafe {
            c = (na_at(a.v, st).a as i64);
            tl = (na_at(a.v, st).l as i64);
            el = (na_at(a.v, st).l2 as i64);
        }
        sb_puts(b, "(if ");
        ex_w(a, lp, sp, b, c);
        sb_putc(b, 10);
        ind_w(b, d + 1);
        sb_puts(b, "(then\n");
        st_blk(a, lp, sp, b, tl, d + 2);
        ind_w(b, d + 1);
        sb_puts(b, ")\n");
        if (lp_len(lp, el) > 0) {
            ind_w(b, d + 1);
            sb_puts(b, "(else\n");
            st_blk(a, lp, sp, b, el, d + 2);
            ind_w(b, d + 1);
            sb_puts(b, ")\n");
        }
        ind_w(b, d);
        sb_puts(b, ")\n");
    } else if (k == ST_WHILE) {
        ind_w(b, d);
        var c: i64 = 0;
        var bl: i64 = 0;
        unsafe {
            c = (na_at(a.v, st).a as i64);
            bl = (na_at(a.v, st).l as i64);
        }
        sb_puts(b, "(while ");
        ex_w(a, lp, sp, b, c);
        sb_putc(b, 10);
        st_blk(a, lp, sp, b, bl, d + 1);
        ind_w(b, d);
        sb_puts(b, ")\n");
    } else if (k == ST_LOOP) {
        ind_w(b, d);
        var bl: i64 = 0;
        unsafe { bl = (na_at(a.v, st).l as i64); }
        sb_puts(b, "(loop\n");
        st_blk(a, lp, sp, b, bl, d + 1);
        ind_w(b, d);
        sb_puts(b, ")\n");
    } else if (k == ST_FOR) {
        ind_w(b, d);
        var s: i64 = 0;
        var x: i64 = 0;
        var y: i64 = 0;
        var bl: i64 = 0;
        unsafe {
            s = (na_at(a.v, st).s as i64);
            x = (na_at(a.v, st).a as i64);
            y = (na_at(a.v, st).b as i64);
            bl = (na_at(a.v, st).l as i64);
        }
        sb_puts(b, "(for ");
        sp_put(sp, b, s);
        sb_putc(b, 32);
        ex_w(a, lp, sp, b, x);
        sb_putc(b, 32);
        ex_w(a, lp, sp, b, y);
        sb_putc(b, 10);
        st_blk(a, lp, sp, b, bl, d + 1);
        ind_w(b, d);
        sb_puts(b, ")\n");
    } else if (k == ST_MATCH) {
        ind_w(b, d);
        var sc: i64 = 0;
        var al: i64 = 0;
        unsafe {
            sc = (na_at(a.v, st).a as i64);
            al = (na_at(a.v, st).l as i64);
        }
        sb_puts(b, "(match ");
        ex_w(a, lp, sp, b, sc);
        sb_putc(b, 10);
        let na: i64 = lp_len(lp, al);
        var i: i64 = 0;
        while (i < na) {
            let arm: i64 = lp_get(lp, al, i);
            ind_w(b, d + 1);
            var pk: i32 = 0;
            var p: i64 = 0;
            var bl: i64 = 0;
            unsafe {
                p = (na_at(a.v, arm).a as i64);
                bl = (na_at(a.v, arm).l as i64);
            }
            unsafe { pk = na_at(a.v, p).k; }
            if (pk == PT_WILD) {
                sb_puts(b, "(arm (pat wild)\n");
            } else if (pk == PT_LIT) {
                var v: i64 = 0;
                unsafe { v = na_at(a.v, p).n; }
                sb_puts(b, "(arm (pat lit ");
                sb_i64(b, v);
                sb_puts(b, ")\n");
            } else if (pk == PT_RANGE) {
                var lo: i64 = 0;
                var hi: i64 = 0;
                unsafe {
                    lo = na_at(a.v, p).n;
                    hi = (na_at(a.v, p).b as i64);
                }
                sb_puts(b, "(arm (pat range ");
                sb_i64(b, lo);
                sb_putc(b, 32);
                sb_i64(b, hi);
                sb_puts(b, ")\n");
            } else if (pk == PT_VARIANT) {
                var s: i64 = 0;
                var s2: i64 = 0;
                var bl2: i64 = 0;
                unsafe {
                    s = (na_at(a.v, p).s as i64);
                    s2 = (na_at(a.v, p).s2 as i64);
                    bl2 = (na_at(a.v, p).l as i64);
                }
                sb_puts(b, "(arm (pat ");
                sp_put(sp, b, s);
                sb_putc(b, 32);
                sp_put(sp, b, s2);
                let nb: i64 = lp_len(lp, bl2);
                var j: i64 = 0;
                while (j < nb) {
                    sb_putc(b, 32);
                    sp_put(sp, b, lp_get(lp, bl2, j));
                    j += 1;
                }
                sb_puts(b, ")\n");
            }
            ind_w(b, d + 2);
            sb_puts(b, "(body\n");
            st_blk(a, lp, sp, b, bl, d + 3);
            ind_w(b, d + 2);
            sb_puts(b, ")\n");
            ind_w(b, d + 1);
            sb_puts(b, ")\n");
            i += 1;
        }
        ind_w(b, d);
        sb_puts(b, ")\n");
    } else if (k == ST_BREAK || k == ST_CONTINUE) {
        ind_w(b, d);
        var s: i64 = 0;
        unsafe { s = (na_at(a.v, st).s as i64); }
        if (k == ST_BREAK) {
            if (s != 0) {
                sb_puts(b, "(break ");
                sp_put(sp, b, s);
                sb_puts(b, ")\n");
            } else {
                sb_puts(b, "(break)\n");
            }
        } else {
            if (s != 0) {
                sb_puts(b, "(continue ");
                sp_put(sp, b, s);
                sb_puts(b, ")\n");
            } else {
                sb_puts(b, "(continue)\n");
            }
        }
    } else if (k == ST_LABEL) {
        ind_w(b, d);
        var s: i64 = 0;
        var inner: i64 = 0;
        unsafe {
            s = (na_at(a.v, st).s as i64);
            inner = (na_at(a.v, st).a as i64);
        }
        sb_puts(b, "(label ");
        sp_put(sp, b, s);
        sb_putc(b, 10);
        st_w(a, lp, sp, b, inner, d + 1);
        ind_w(b, d);
        sb_puts(b, ")\n");
    } else if (k == ST_RETURN) {
        ind_w(b, d);
        var x: i64 = 0;
        unsafe { x = (na_at(a.v, st).a as i64); }
        if (x == 0) {
            sb_puts(b, "(return)\n");
        } else {
            sb_puts(b, "(return ");
            ex_w(a, lp, sp, b, x);
            sb_puts(b, ")\n");
        }
    }
}

fn st_blk(a: &mut Na, lp: &mut Lp, sp: &mut Sp, b: &mut Sb, l: i64, d: i64) {
    let n: i64 = lp_len(lp, l);
    var i: i64 = 0;
    while (i < n) {
        st_w(a, lp, sp, b, lp_get(lp, l, i), d);
        i += 1;
    }
}

fn it_w(a: &mut Na, lp: &mut Lp, sp: &mut Sp, b: &mut Sb, it: i64) {
    var k: i32 = 0;
    unsafe { k = na_at(a.v, it).k; }
    if (k == IT_CONST) {
        var s: i64 = 0;
        var t: i64 = 0;
        var v: i64 = 0;
        unsafe {
            s = (na_at(a.v, it).s as i64);
            t = (na_at(a.v, it).a as i64);
            v = (na_at(a.v, it).b as i64);
        }
        sb_puts(b, "  (const ");
        sp_put(sp, b, s);
        sb_putc(b, 32);
        ty_w(a, lp, sp, b, t);
        sb_putc(b, 32);
        ex_w(a, lp, sp, b, v);
        sb_puts(b, ")\n");
    } else if (k == IT_STATIC) {
        var s: i64 = 0;
        var t: i64 = 0;
        var v: i64 = 0;
        var mu: i32 = 0;
        unsafe {
            s = (na_at(a.v, it).s as i64);
            t = (na_at(a.v, it).a as i64);
            v = (na_at(a.v, it).b as i64);
            mu = na_at(a.v, it).m;
        }
        sb_puts(b, "  (static ");
        sp_put(sp, b, s);
        sb_putc(b, 32);
        ty_w(a, lp, sp, b, t);
        sb_putc(b, 32);
        ex_w(a, lp, sp, b, v);
        if (mu == 1) {
            sb_puts(b, " mut)\n");
        } else {
            sb_puts(b, " const)\n");
        }
    } else if (k == IT_STRUCT) {
        var s: i64 = 0;
        var l: i64 = 0;
        unsafe {
            s = (na_at(a.v, it).s as i64);
            l = (na_at(a.v, it).l as i64);
        }
        sb_puts(b, "  (struct ");
        sp_put(sp, b, s);
        sb_putc(b, 10);
        let n: i64 = lp_len(lp, l);
        var i: i64 = 0;
        while (i < n) {
            sb_puts(b, "    (field ");
            sp_put(sp, b, lp_get(lp, l, i));
            sb_putc(b, 32);
            ty_w(a, lp, sp, b, lp_get(lp, l, i + 1));
            sb_puts(b, ")\n");
            i += 2;
        }
        sb_puts(b, "  )\n");
    } else if (k == IT_ENUM) {
        var s: i64 = 0;
        var l: i64 = 0;
        unsafe {
            s = (na_at(a.v, it).s as i64);
            l = (na_at(a.v, it).l as i64);
        }
        sb_puts(b, "  (enum ");
        sp_put(sp, b, s);
        sb_putc(b, 10);
        let n: i64 = lp_len(lp, l);
        var i: i64 = 0;
        while (i < n) {
            let nm: i64 = lp_get(lp, l, i);
            let pl: i64 = lp_get(lp, l, i + 1);
            sb_puts(b, "    (variant ");
            sp_put(sp, b, nm);
            let np: i64 = lp_len(lp, pl);
            if (np > 0) {
                sb_puts(b, " (payload");
                var j: i64 = 0;
                while (j < np) {
                    sb_putc(b, 32);
                    ty_w(a, lp, sp, b, lp_get(lp, pl, j));
                    j += 1;
                }
                sb_putc(b, 41);
            }
            sb_puts(b, ")\n");
            i += 2;
        }
        sb_puts(b, "  )\n");
    } else if (k == IT_EXTERN) {
        var s: i64 = 0;
        var s2: i64 = 0;
        var pl: i64 = 0;
        var rt: i64 = 0;
        var va: i32 = 0;
        unsafe {
            s = (na_at(a.v, it).s as i64);
            s2 = (na_at(a.v, it).s2 as i64);
            pl = (na_at(a.v, it).l as i64);
            rt = (na_at(a.v, it).a as i64);
            va = na_at(a.v, it).m;
        }
        sb_puts(b, "  (extern ");
        sp_put(sp, b, s);
        sb_putc(b, 10);
        if (s2 != 0) {
            sb_puts(b, "    (lib \"");
            sp_put(sp, b, s2);
            sb_puts(b, "\")\n");
        }
        let n: i64 = lp_len(lp, pl);
        var i: i64 = 0;
        while (i < n) {
            sb_puts(b, "    (param ");
            ty_w(a, lp, sp, b, lp_get(lp, pl, i));
            sb_puts(b, ")\n");
            i += 1;
        }
        if (va == 1) {
            sb_puts(b, "    (variadic)\n");
        }
        sb_puts(b, "    (ret ");
        ty_w(a, lp, sp, b, rt);
        sb_puts(b, ")\n");
        sb_puts(b, "  )\n");
    } else if (k == IT_FN) {
        var s: i64 = 0;
        var tp: i64 = 0;
        var ps: i64 = 0;
        var rt: i64 = 0;
        var asy: i32 = 0;
        var cab: i32 = 0;
        var bl: i64 = 0;
        unsafe {
            s = (na_at(a.v, it).s as i64);
            tp = (na_at(a.v, it).l as i64);
            ps = (na_at(a.v, it).l2 as i64);
            rt = (na_at(a.v, it).a as i64);
            asy = na_at(a.v, it).n as i32;
            cab = na_at(a.v, it).m;
            bl = (na_at(a.v, it).l3 as i64);
        }
        sb_puts(b, "  (fn ");
        sp_put(sp, b, s);
        sb_putc(b, 10);
        if (lp_len(lp, tp) > 0) {
            sb_puts(b, "    (generic ");
            let n: i64 = lp_len(lp, tp);
            var i: i64 = 0;
            while (i < n) {
                if (i > 0) {
                    sb_putc(b, 32);
                }
                sp_put(sp, b, lp_get(lp, tp, i));
                i += 1;
            }
            sb_puts(b, ")\n");
        }
        let np: i64 = lp_len(lp, ps);
        var i: i64 = 0;
        while (i < np) {
            sb_puts(b, "    (param ");
            sp_put(sp, b, lp_get(lp, ps, i));
            sb_putc(b, 32);
            ty_w(a, lp, sp, b, lp_get(lp, ps, i + 1));
            sb_puts(b, ")\n");
            i += 2;
        }
        sb_puts(b, "    (ret ");
        ty_w(a, lp, sp, b, rt);
        sb_puts(b, ")\n");
        if (asy == 1) {
            sb_puts(b, "    (async)\n");
        }
        if (cab == 1) {
            sb_puts(b, "    (c-abi)\n");
        }
        sb_puts(b, "    (body\n");
        st_blk(a, lp, sp, b, bl, 3);
        sb_puts(b, "    )\n");
        sb_puts(b, "  )\n");
    }
}

fn prog_w(a: &mut Na, lp: &mut Lp, sp: &mut Sp, b: &mut Sb, p: &mut Pr) {
    sb_puts(b, "(program\n");
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
        let n: i64 = lp_len(lp, l);
        var i: i64 = 0;
        while (i < n) {
            it_w(a, lp, sp, b, lp_get(lp, l, i));
            i += 1;
        }
        g += 1;
    }
    sb_puts(b, ")\n");
}
