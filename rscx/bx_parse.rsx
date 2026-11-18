include "base.rsx";
include "ast.rsx";

const SX_ATOM: i32 = 0;
const SX_LIST: i32 = 1;

const TT_I8: i32 = 1;
const TT_I16: i32 = 2;
const TT_I32: i32 = 3;
const TT_I64: i32 = 4;
const TT_U8: i32 = 5;
const TT_U16: i32 = 6;
const TT_U32: i32 = 7;
const TT_U64: i32 = 8;
const TT_F32: i32 = 9;
const TT_F64: i32 = 10;
const TT_BOOL: i32 = 11;
const TT_VOID: i32 = 12;
const TT_INFER: i32 = 13;
const TT_ERR: i32 = 14;
const TT_PTR: i32 = 21;
const TT_REF: i32 = 22;
const TT_BOX: i32 = 23;
const TT_ARRAY: i32 = 24;
const TT_STRUCT: i32 = 25;
const TT_ENUM: i32 = 26;
const TT_TUPLE: i32 = 27;
const TT_FN: i32 = 28;
const TT_FNC: i32 = 29;
const TT_TASK: i32 = 30;
const TT_VAR: i32 = 31;

const SX_MAX_DEPTH: i64 = 512;

struct Sx {
    tag: i32,
    s: i64,
    l: i64
}

struct SxAr {
    v: ptr<Sx>,
    n: i64,
    cap: i64,
    bad: i32
}

fn sx_new() -> SxAr {
    var a: SxAr = zero(SxAr);
    a.cap = 1024;
    a.v = malloc((a.cap as u64) * sizeof(Sx)) as ptr<Sx>;
    if (a.v == null) {
        a.bad = 1;
        return a;
    }
    unsafe { a.v[0] = zero(Sx); }
    a.n = 1;
    return a;
}

fn sx_free(a: &mut SxAr) {
    if (a.v != null) {
        free(a.v as ptr<u8>);
        a.v = null;
    }
    a.n = 0;
    a.cap = 0;
}

fn sx_add(a: &mut SxAr, tag: i32) -> i64 {
    if (a.bad == 1) {
        return 0;
    }
    if (a.n >= a.cap) {
        let nc: i64 = a.cap * 2;
        var raw: ptr<u8> = realloc(a.v as ptr<u8>, (nc as u64) * sizeof(Sx));
        if (raw == null) {
            a.bad = 1;
            return 0;
        }
        a.v = raw as ptr<Sx>;
        a.cap = nc;
    }
    let id: i64 = a.n;
    unsafe {
        a.v[id].tag = tag;
        a.v[id].s = 0;
        a.v[id].l = 0;
    }
    a.n += 1;
    return id;
}

struct TyEnt {
    tag: i32,
    a: i64,
    b: i64,
    n: i64,
    s: i64,
    l: i64,
    h: i64
}

struct Tt {
    v: ptr<TyEnt>,
    n: i64,
    cap: i64,
    tab: ptr<i64>,
    tcap: i64,
    bad: i32
}

fn tt_new() -> Tt {
    var t: Tt = zero(Tt);
    t.cap = 256;
    t.v = malloc((t.cap as u64) * sizeof(TyEnt)) as ptr<TyEnt>;
    t.tcap = 512;
    t.tab = malloc((t.tcap as u64) * sizeof(i64)) as ptr<i64>;
    if (t.v == null || t.tab == null) {
        t.bad = 1;
        return t;
    }
    unsafe { t.v[0] = zero(TyEnt); }
    var i: i64 = 0;
    while (i < t.tcap) {
        unsafe { t.tab[i] = 0; }
        i += 1;
    }
    t.n = 1;
    var k: i32 = 1;
    while (k <= 14) {
        let id: i64 = t.n;
        unsafe {
            t.v[id].tag = k;
            t.v[id].a = 0;
            t.v[id].b = 0;
            t.v[id].n = 0;
            t.v[id].s = 0;
            t.v[id].l = 0;
            t.v[id].h = k as i64;
        }
        var idx: i64 = (k as i64) & (t.tcap - 1);
        while (true) {
            var slot: i64 = 0;
            unsafe { slot = t.tab[idx]; }
            if (slot == 0) {
                break;
            }
            idx = (idx + 1) & (t.tcap - 1);
        }
        unsafe { t.tab[idx] = id; }
        t.n += 1;
        k += 1;
    }
    return t;
}

fn tt_free(t: &mut Tt) {
    if (t.v != null) {
        free(t.v as ptr<u8>);
        t.v = null;
    }
    if (t.tab != null) {
        free(t.tab as ptr<u8>);
        t.tab = null;
    }
    t.n = 0;
    t.cap = 0;
    t.tcap = 0;
}

fn tt_hash(tag: i32, a: i64, b: i64, n: i64, s: i64, l: i64) -> i64 {
    var h: i64 = tag as i64;
    h = (h * 1000003 + a) & 281474976710655;
    h = (h * 1000003 + b) & 281474976710655;
    h = (h * 1000003 + n) & 281474976710655;
    h = (h * 1000003 + s) & 281474976710655;
    h = (h * 1000003 + l) & 281474976710655;
    return h;
}

fn tt_rehash(t: &mut Tt) {
    let nc: i64 = t.tcap * 2;
    var nt: ptr<i64> = malloc((nc as u64) * sizeof(i64)) as ptr<i64>;
    if (nt == null) {
        t.bad = 1;
        return;
    }
    var i: i64 = 0;
    while (i < nc) {
        unsafe { nt[i] = 0; }
        i += 1;
    }
    i = 1;
    while (i < t.n) {
        var hv: i64 = 0;
        unsafe { hv = t.v[i].h; }
        var idx: i64 = hv & (nc - 1);
        while (true) {
            var slot: i64 = 0;
            unsafe { slot = nt[idx]; }
            if (slot == 0) {
                break;
            }
            idx = (idx + 1) & (nc - 1);
        }
        unsafe { nt[idx] = i; }
        i += 1;
    }
    free(t.tab as ptr<u8>);
    t.tab = nt;
    t.tcap = nc;
}

fn tt_mk(t: &mut Tt, tag: i32, a: i64, b: i64, n: i64, s: i64, l: i64) -> i64 {
    if (t.bad == 1) {
        return 0;
    }
    if (t.n * 2 >= t.tcap) {
        tt_rehash(t);
        if (t.bad == 1) {
            return 0;
        }
    }
    let h: i64 = tt_hash(tag, a, b, n, s, l);
    var idx: i64 = h & (t.tcap - 1);
    while (true) {
        var slot: i64 = 0;
        unsafe { slot = t.tab[idx]; }
        if (slot == 0) {
            break;
        }
        var et: i32 = 0;
        var ea: i64 = 0;
        var eb: i64 = 0;
        var en: i64 = 0;
        var es: i64 = 0;
        var el: i64 = 0;
        unsafe {
            et = t.v[slot].tag;
            ea = t.v[slot].a;
            eb = t.v[slot].b;
            en = t.v[slot].n;
            es = t.v[slot].s;
            el = t.v[slot].l;
        }
        if (et == tag && ea == a && eb == b && en == n && es == s && el == l) {
            return slot;
        }
        idx = (idx + 1) & (t.tcap - 1);
    }
    if (t.n >= t.cap) {
        let nc: i64 = t.cap * 2;
        var raw: ptr<u8> = realloc(t.v as ptr<u8>, (nc as u64) * sizeof(TyEnt));
        if (raw == null) {
            t.bad = 1;
            return 0;
        }
        t.v = raw as ptr<TyEnt>;
        t.cap = nc;
    }
    let id: i64 = t.n;
    unsafe {
        t.v[id].tag = tag;
        t.v[id].a = a;
        t.v[id].b = b;
        t.v[id].n = n;
        t.v[id].s = s;
        t.v[id].l = l;
        t.v[id].h = h;
    }
    unsafe { t.tab[idx] = id; }
    t.n += 1;
    return id;
}

fn tt_tag(t: &mut Tt, id: i64) -> i32 {
    if (id <= 0) {
        return 0;
    }
    var k: i32 = 0;
    unsafe { k = t.v[id].tag; }
    return k;
}

fn tt_is_int(t: &mut Tt, id: i64) -> bool {
    let k: i32 = tt_tag(t, id);
    return k >= TT_I8 && k <= TT_U64;
}

fn tt_is_float(t: &mut Tt, id: i64) -> bool {
    let k: i32 = tt_tag(t, id);
    return k == TT_F32 || k == TT_F64;
}

fn tt_is_signed(t: &mut Tt, id: i64) -> bool {
    let k: i32 = tt_tag(t, id);
    return k >= TT_I8 && k <= TT_I64;
}

fn tt_wrap(t: &mut Tt, id: i64, v: i64) -> i64 {
    let k: i32 = tt_tag(t, id);
    if (k == TT_I8) {
        return (v << 56) >> 56;
    }
    if (k == TT_I16) {
        return (v << 48) >> 48;
    }
    if (k == TT_I32) {
        return (v << 32) >> 32;
    }
    if (k == TT_U8) {
        return v & 255;
    }
    if (k == TT_U16) {
        return v & 65535;
    }
    if (k == TT_U32) {
        return v & 4294967295;
    }
    return v;
}

struct Mi {
    k: ptr<i64>,
    v: ptr<i64>,
    h: ptr<i64>,
    n: i64,
    cap: i64,
    bad: i32
}

struct Mv {
    ok: i32,
    v: i64
}

struct Iv {
    ok: i32,
    v: i64
}

fn mi_new(cap: i64) -> Mi {
    var m: Mi = zero(Mi);
    m.cap = cap;
    m.k = malloc((cap as u64) * sizeof(i64)) as ptr<i64>;
    m.v = malloc((cap as u64) * sizeof(i64)) as ptr<i64>;
    m.h = malloc((cap as u64) * sizeof(i64)) as ptr<i64>;
    if (m.k == null || m.v == null || m.h == null) {
        m.bad = 1;
        return m;
    }
    var i: i64 = 0;
    while (i < cap) {
        unsafe { m.k[i] = 0; }
        unsafe { m.v[i] = 0; }
        unsafe { m.h[i] = 0; }
        i += 1;
    }
    return m;
}

fn mi_free(m: &mut Mi) {
    if (m.k != null) {
        free(m.k as ptr<u8>);
        m.k = null;
    }
    if (m.v != null) {
        free(m.v as ptr<u8>);
        m.v = null;
    }
    if (m.h != null) {
        free(m.h as ptr<u8>);
        m.h = null;
    }
    m.n = 0;
    m.cap = 0;
}

fn mi_grow(m: &mut Mi) {
    let nc: i64 = m.cap * 2;
    var nk: ptr<i64> = malloc((nc as u64) * sizeof(i64)) as ptr<i64>;
    var nv: ptr<i64> = malloc((nc as u64) * sizeof(i64)) as ptr<i64>;
    var nh: ptr<i64> = malloc((nc as u64) * sizeof(i64)) as ptr<i64>;
    if (nk == null || nv == null || nh == null) {
        m.bad = 1;
        return;
    }
    var i: i64 = 0;
    while (i < nc) {
        unsafe { nk[i] = 0; }
        unsafe { nv[i] = 0; }
        unsafe { nh[i] = 0; }
        i += 1;
    }
    i = 0;
    while (i < m.cap) {
        var key: i64 = 0;
        var val: i64 = 0;
        var hv: i64 = 0;
        unsafe {
            key = m.k[i];
            val = m.v[i];
            hv = m.h[i];
        }
        if (key != 0) {
            var idx: i64 = hv & (nc - 1);
            while (true) {
                var slot: i64 = 0;
                unsafe { slot = nk[idx]; }
                if (slot == 0) {
                    break;
                }
                idx = (idx + 1) & (nc - 1);
            }
            unsafe {
                nk[idx] = key;
                nv[idx] = val;
                nh[idx] = hv;
            }
        }
        i += 1;
    }
    free(m.k as ptr<u8>);
    free(m.v as ptr<u8>);
    free(m.h as ptr<u8>);
    m.k = nk;
    m.v = nv;
    m.h = nh;
    m.cap = nc;
}

fn mi_put(m: &mut Mi, h: i64, key: i64, val: i64) {
    if (m.bad == 1 || key <= 0) {
        return;
    }
    if (m.n * 2 >= m.cap) {
        mi_grow(m);
        if (m.bad == 1) {
            return;
        }
    }
    var idx: i64 = h & (m.cap - 1);
    while (true) {
        var slot: i64 = 0;
        unsafe { slot = m.k[idx]; }
        if (slot == 0) {
            unsafe { m.k[idx] = key; }
            unsafe { m.v[idx] = val; }
            unsafe { m.h[idx] = h; }
            m.n += 1;
            return;
        }
        if (slot == key) {
            unsafe { m.v[idx] = val; }
            unsafe { m.h[idx] = h; }
            return;
        }
        idx = (idx + 1) & (m.cap - 1);
    }
}

fn mi_get(m: &mut Mi, h: i64, key: i64) -> Mv {
    var r: Mv = zero(Mv);
    if (m.bad == 1 || key <= 0 || m.n == 0) {
        return r;
    }
    var idx: i64 = h & (m.cap - 1);
    while (true) {
        var slot: i64 = 0;
        unsafe { slot = m.k[idx]; }
        if (slot == 0) {
            return r;
        }
        if (slot == key) {
            var val: i64 = 0;
            unsafe { val = m.v[idx]; }
            r.ok = 1;
            r.v = val;
            return r;
        }
        idx = (idx + 1) & (m.cap - 1);
    }
}

struct Bp {
    sp: Sp,
    lp: Lp,
    na: Na,
    sx: SxAr,
    tt: Tt,
    err: Sb,
    sizes: Mi,
    enums: SetI,
    txt: ptr<u8>,
    pos: i64,
    n: i64,
    root: i64,
    ok: i32
}

fn bp_new() -> Bp {
    var x: Bp = zero(Bp);
    x.sp = sp_new();
    x.lp = lp_new();
    x.na = na_new();
    x.sx = sx_new();
    x.tt = tt_new();
    x.err = sb_new(256);
    x.sizes = mi_new(64);
    x.enums = si_new();
    x.ok = 1;
    if (x.sp.bad == 1 || x.lp.bad == 1 || x.na.bad == 1 || x.sx.bad == 1 || x.tt.bad == 1) {
        x.ok = 0;
        sb_puts(&mut x.err, "out of memory");
    }
    return x;
}

fn bp_free(x: &mut Bp) {
    sp_free(&mut x.sp);
    lp_free(&mut x.lp);
    na_free(&mut x.na);
    sx_free(&mut x.sx);
    tt_free(&mut x.tt);
    sb_free(&mut x.err);
    mi_free(&mut x.sizes);
    si_free(&mut x.enums);
}

fn bp_ok(x: &mut Bp) -> i32 {
    return x.ok;
}

fn bp_err_ptr(x: &mut Bp) -> ptr<u8> {
    return x.err.p;
}

fn bp_err_len(x: &mut Bp) -> i64 {
    return x.err.n;
}

fn bx_fail(x: &mut Bp, m: ptr<u8>) {
    sb_puts(&mut x.err, m);
    x.ok = 0;
}

fn bx_fail_id(x: &mut Bp, pre: ptr<u8>, id: i64, post: ptr<u8>) {
    sb_puts(&mut x.err, pre);
    let p: ptr<u8> = sp_ptr(&mut x.sp, id);
    let n: i64 = sp_len(&mut x.sp, id);
    sb_put(&mut x.err, p, n);
    sb_puts(&mut x.err, post);
    x.ok = 0;
}

fn bx_fail_num(x: &mut Bp, pre: ptr<u8>, v: i64, post: ptr<u8>) {
    sb_puts(&mut x.err, pre);
    sb_i64(&mut x.err, v);
    sb_puts(&mut x.err, post);
    x.ok = 0;
}

fn bx_at(p: ptr<u8>, i: i64) -> u8 {
    var c: u8 = 0;
    unsafe { c = p[i]; }
    return c;
}

fn sx_stop(c: u8) -> bool {
    if (c == 32 || c == 9 || c == 13 || c == 10) {
        return true;
    }
    if (c == 40 || c == 41 || c == 34) {
        return true;
    }
    return false;
}

fn sx_skip(x: &mut Bp) {
    let p: ptr<u8> = x.txt;
    while (x.pos < x.n) {
        var q: i64 = x.pos;
        let c: u8 = bx_at(p, q);
        if (c == 32 || c == 9 || c == 13 || c == 10) {
            x.pos += 1;
        } else if (c == 59) {
            while (x.pos < x.n) {
                var r: i64 = x.pos;
                if (bx_at(p, r) == 10) {
                    break;
                }
                x.pos += 1;
            }
        } else {
            return;
        }
    }
}

fn sx_datum(x: &mut Bp, depth: i64) -> i64 {
    if (depth > SX_MAX_DEPTH) {
        let at: i64 = x.pos;
        bx_fail_num(x, "IR nests more than 512 deep at byte ", at, "");
        return 0;
    }
    sx_skip(x);
    if (x.pos >= x.n) {
        bx_fail(x, "unexpected end of IR");
        return 0;
    }
    let p: ptr<u8> = x.txt;
    var at: i64 = x.pos;
    let c: u8 = bx_at(p, at);
    if (c == 40) {
        x.pos += 1;
        let l: i64 = lp_add(&mut x.lp);
        while (true) {
            sx_skip(x);
            if (x.pos >= x.n) {
                bx_fail(x, "unclosed list in IR");
                return 0;
            }
            var q: i64 = x.pos;
            if (bx_at(p, q) == 41) {
                x.pos += 1;
                break;
            }
            let d: i64 = sx_datum(x, depth + 1);
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, l, d);
        }
        let nd: i64 = sx_add(&mut x.sx, SX_LIST);
        if (nd == 0) {
            bx_fail(x, "out of memory");
            return 0;
        }
        unsafe { x.sx.v[nd].l = l; }
        return nd;
    }
    if (c == 41) {
        bx_fail_num(x, "unexpected ')' in IR at byte ", at, "");
        return 0;
    }
    if (c == 34) {
        let start: i64 = at;
        x.pos += 1;
        while (true) {
            if (x.pos >= x.n) {
                bx_fail(x, "unterminated string atom in IR");
                return 0;
            }
            var r: i64 = x.pos;
            let d: u8 = bx_at(p, r);
            if (d == 92) {
                x.pos += 2;
            } else if (d == 34) {
                x.pos += 1;
                break;
            } else {
                x.pos += 1;
            }
        }
        var len: i64 = x.pos - start;
        let id: i64 = sp_intern(&mut x.sp, p_off(p, start), len);
        if (id <= 0) {
            bx_fail(x, "out of memory");
            return 0;
        }
        let nd: i64 = sx_add(&mut x.sx, SX_ATOM);
        if (nd == 0) {
            bx_fail(x, "out of memory");
            return 0;
        }
        unsafe { x.sx.v[nd].s = id; }
        return nd;
    }
    let start: i64 = at;
    while (x.pos < x.n) {
        var r: i64 = x.pos;
        if (sx_stop(bx_at(p, r))) {
            break;
        }
        x.pos += 1;
    }
    var len2: i64 = x.pos - start;
    let id2: i64 = sp_intern(&mut x.sp, p_off(p, start), len2);
    if (id2 <= 0) {
        bx_fail(x, "out of memory");
        return 0;
    }
    let nd2: i64 = sx_add(&mut x.sx, SX_ATOM);
    if (nd2 == 0) {
        bx_fail(x, "out of memory");
        return 0;
    }
    unsafe { x.sx.v[nd2].s = id2; }
    return nd2;
}

fn bx_read(x: &mut Bp, text: ptr<u8>, n: i64) -> i32 {
    x.txt = text;
    x.n = n;
    x.pos = 0;
    let d: i64 = sx_datum(x, 0);
    if (x.ok == 0) {
        return 0;
    }
    sx_skip(x);
    if (x.pos != x.n) {
        let at: i64 = x.pos;
        bx_fail_num(x, "trailing garbage in IR at byte ", at, "");
        return 0;
    }
    x.root = d;
    return 1;
}

fn sx_is_list(x: &mut Bp, s: i64) -> bool {
    if (s <= 0) {
        return false;
    }
    var k: i32 = 0;
    unsafe { k = x.sx.v[s].tag; }
    return k == SX_LIST;
}

fn sx_list(x: &mut Bp, s: i64) -> i64 {
    if (s <= 0) {
        return 0;
    }
    var l: i64 = 0;
    unsafe { l = x.sx.v[s].l; }
    return l;
}

fn sx_len(x: &mut Bp, s: i64) -> i64 {
    let l: i64 = sx_list(x, s);
    return lp_len(&mut x.lp, l);
}

fn sx_child(x: &mut Bp, s: i64, i: i64) -> i64 {
    let l: i64 = sx_list(x, s);
    return lp_get(&mut x.lp, l, i);
}

fn sx_head(x: &mut Bp, s: i64) -> i64 {
    if (s <= 0) {
        return 0;
    }
    var k: i32 = 0;
    unsafe { k = x.sx.v[s].tag; }
    if (k != SX_LIST) {
        return 0;
    }
    var l: i64 = 0;
    unsafe { l = x.sx.v[s].l; }
    if (lp_len(&mut x.lp, l) < 1) {
        return 0;
    }
    let e: i64 = lp_get(&mut x.lp, l, 0);
    var k0: i32 = 0;
    unsafe { k0 = x.sx.v[e].tag; }
    if (k0 != SX_ATOM) {
        return 0;
    }
    var id: i64 = 0;
    unsafe { id = x.sx.v[e].s; }
    return id;
}

fn sx_atom_id(x: &mut Bp, s: i64) -> i64 {
    if (s <= 0) {
        return 0;
    }
    var k: i32 = 0;
    unsafe { k = x.sx.v[s].tag; }
    if (k != SX_ATOM) {
        return 0;
    }
    var id: i64 = 0;
    unsafe { id = x.sx.v[s].s; }
    return id;
}

fn sx_is_atom_c(x: &mut Bp, s: i64, c: ptr<u8>) -> bool {
    let id: i64 = sx_atom_id(x, s);
    if (id <= 0) {
        return false;
    }
    return sp_eqc(&mut x.sp, id, c);
}

fn sx_head_is(x: &mut Bp, s: i64, c: ptr<u8>) -> bool {
    let id: i64 = sx_head(x, s);
    if (id <= 0) {
        return false;
    }
    return sp_eqc(&mut x.sp, id, c);
}

fn bx_atom(x: &mut Bp, s: i64) -> i64 {
    let id: i64 = sx_atom_id(x, s);
    if (id == 0) {
        bx_fail(x, "expected an atom in IR, found a list");
        return 0;
    }
    return id;
}

fn bx_unq(x: &mut Bp, id: i64) -> i64 {
    let p: ptr<u8> = sp_ptr(&mut x.sp, id);
    let n: i64 = sp_len(&mut x.sp, id);
    if (n < 2) {
        return id;
    }
    var c0: u8 = 0;
    unsafe { c0 = p[0]; }
    if (c0 != 34) {
        return id;
    }
    var out: Sb = sb_new(n);
    if (out.p == null) {
        return id;
    }
    let stop: i64 = n - 1;
    var i: i64 = 1;
    while (i < stop) {
        var c: u8 = 0;
        unsafe { c = p[i]; }
        if (c == 92 && i + 1 < stop) {
            var d: u8 = 0;
            unsafe { d = p[i + 1]; }
            var oct3: i32 = 0;
            if (d >= 48 && d <= 55 && i + 3 < stop) {
                var d2: u8 = 0;
                var d3: u8 = 0;
                unsafe {
                    d2 = p[i + 2];
                    d3 = p[i + 3];
                }
                if (d2 >= 48 && d2 <= 55 && d3 >= 48 && d3 <= 55) {
                    let v: i64 = ((d as i64) - 48) * 64 + ((d2 as i64) - 48) * 8 + ((d3 as i64) - 48);
                    sb_putc(&mut out, (v & 255) as u8);
                    i += 4;
                    oct3 = 1;
                }
            }
            if (oct3 == 0) {
                if (d == 110) {
                    sb_putc(&mut out, 10);
                } else if (d == 116) {
                    sb_putc(&mut out, 9);
                } else if (d == 114) {
                    sb_putc(&mut out, 13);
                } else if (d == 48) {
                    sb_putc(&mut out, 0);
                } else {
                    sb_putc(&mut out, d);
                }
                i += 2;
            }
        } else {
            sb_putc(&mut out, c);
            i += 1;
        }
    }
    let r: i64 = sp_intern(&mut x.sp, out.p, out.n);
    sb_free(&mut out);
    return r;
}

fn p_tag(x: &mut Bp, tag: ptr<u8>, s: i64) -> i64 {
    if (sx_head_is(x, s, tag)) {
        return sx_list(x, s);
    }
    sb_puts(&mut x.err, "expected '(");
    sb_puts(&mut x.err, tag);
    sb_puts(&mut x.err, " ...)' in IR, found '(");
    var h: i64 = 0;
    if (sx_is_list(x, s)) {
        h = sx_head(x, s);
        if (h <= 0) {
            if (sx_len(x, s) == 0) {
                sb_puts(&mut x.err, "<empty>");
            } else {
                sb_puts(&mut x.err, "<list>");
            }
        }
    } else {
        h = sx_atom_id(x, s);
    }
    if (h > 0) {
        let hp: ptr<u8> = sp_ptr(&mut x.sp, h);
        let hn: i64 = sp_len(&mut x.sp, h);
        sb_put(&mut x.err, hp, hn);
    }
    sb_puts(&mut x.err, " ...)'");
    x.ok = 0;
    return 0;
}

fn bx_num_of(p: ptr<u8>, len: i64) -> i64 {
    var i: i64 = 0;
    var neg: i32 = 0;
    var okv: i32 = 0;
    var v: i64 = 0;
    if (len > 0) {
        if (bx_at(p, 0) == 45) {
            neg = 1;
            i = 1;
        } else if (bx_at(p, 0) == 43) {
            i = 1;
        }
    }
    if (i < len && len - i > 2) {
        if (bx_at(p, i) == 48) {
            let b: u8 = bx_at(p, i + 1);
            if (b == 120 || b == 88) {
                i += 2;
                okv = 1;
                while (i < len) {
                    let c: u8 = bx_at(p, i);
                    var d: i64 = 0;
                    if (c >= 48 && c <= 57) {
                        d = (c - 48) as i64;
                    } else if (c >= 97 && c <= 102) {
                        d = (c - 87) as i64;
                    } else if (c >= 65 && c <= 70) {
                        d = (c - 55) as i64;
                    } else {
                        return 0;
                    }
                    v = v * 16 + d;
                    i += 1;
                }
            }
        }
    }
    if (okv == 0) {
        i = 0;
        if (len > 0) {
            if (bx_at(p, 0) == 45) {
                neg = 1;
                i = 1;
            } else if (bx_at(p, 0) == 43) {
                i = 1;
            }
        }
        if (i >= len) {
            return 0;
        }
        while (i < len) {
            let c: u8 = bx_at(p, i);
            if (c < 48 || c > 57) {
                return 0;
            }
            v = v * 10 + ((c - 48) as i64);
            i += 1;
        }
    }
    if (neg == 1) {
        v = 0 - v;
    }
    return v;
}

fn bx_ty(x: &mut Bp, s: i64) -> i64 {
    if (sx_is_atom_c(x, s, "i8")) {
        return TT_I8 as i64;
    }
    if (sx_is_atom_c(x, s, "i16")) {
        return TT_I16 as i64;
    }
    if (sx_is_atom_c(x, s, "i32")) {
        return TT_I32 as i64;
    }
    if (sx_is_atom_c(x, s, "i64")) {
        return TT_I64 as i64;
    }
    if (sx_is_atom_c(x, s, "u8")) {
        return TT_U8 as i64;
    }
    if (sx_is_atom_c(x, s, "u16")) {
        return TT_U16 as i64;
    }
    if (sx_is_atom_c(x, s, "u32")) {
        return TT_U32 as i64;
    }
    if (sx_is_atom_c(x, s, "u64")) {
        return TT_U64 as i64;
    }
    if (sx_is_atom_c(x, s, "f32")) {
        return TT_F32 as i64;
    }
    if (sx_is_atom_c(x, s, "f64")) {
        return TT_F64 as i64;
    }
    if (sx_is_atom_c(x, s, "bool")) {
        return TT_BOOL as i64;
    }
    if (sx_is_atom_c(x, s, "void")) {
        return TT_VOID as i64;
    }
    if (sx_is_atom_c(x, s, "infer")) {
        return TT_INFER as i64;
    }
    if (sx_is_list(x, s)) {
        let n: i64 = sx_len(x, s);
        if (sx_head_is(x, s, "ptr") && n == 2) {
            let t: i64 = bx_ty(x, sx_child(x, s, 1));
            if (x.ok == 0) {
                return 0;
            }
            return tt_mk(&mut x.tt, TT_PTR, t, 0, 0, 0, 0);
        }
        if (sx_head_is(x, s, "ref") && n == 2) {
            let t: i64 = bx_ty(x, sx_child(x, s, 1));
            if (x.ok == 0) {
                return 0;
            }
            return tt_mk(&mut x.tt, TT_REF, t, 0, 0, 0, 0);
        }
        if (sx_head_is(x, s, "refmut") && n == 2) {
            let t: i64 = bx_ty(x, sx_child(x, s, 1));
            if (x.ok == 0) {
                return 0;
            }
            return tt_mk(&mut x.tt, TT_REF, t, 1, 0, 0, 0);
        }
        if (sx_head_is(x, s, "box") && n == 2) {
            let t: i64 = bx_ty(x, sx_child(x, s, 1));
            if (x.ok == 0) {
                return 0;
            }
            return tt_mk(&mut x.tt, TT_BOX, t, 0, 0, 0, 0);
        }
        if (sx_head_is(x, s, "array") && n == 3) {
            let elem: i64 = bx_ty(x, sx_child(x, s, 1));
            if (x.ok == 0) {
                return 0;
            }
            let na: i64 = sx_atom_id(x, sx_child(x, s, 2));
            if (na == 0) {
                bx_fail(x, "bad type in IR");
                return 0;
            }
            let p: ptr<u8> = sp_ptr(&mut x.sp, na);
            let ln: i64 = sp_len(&mut x.sp, na);
            var count: i64 = 0;
            var known: i32 = 0;
            let dec: i64 = bx_num_of(p, ln);
            var allnum: i32 = 1;
            var i: i64 = 0;
            if (ln == 0) {
                allnum = 0;
            }
            while (i < ln) {
                let c: u8 = bx_at(p, i);
                if (i == 0 && (c == 45 || c == 43)) {
                    i += 1;
                } else if (c < 48 || c > 57) {
                    allnum = 0;
                    break;
                } else {
                    i += 1;
                }
            }
            if (allnum == 1) {
                count = dec;
                known = 1;
            } else {
                let sh: i64 = si_hash(&mut x.sp, na);
                let mv: Mv = mi_get(&mut x.sizes, sh, na);
                if (mv.ok == 1) {
                    count = mv.v;
                    known = 1;
                }
            }
            if (known == 0) {
                bx_fail_id(x, "array size '", na, "' is not a known integer const");
                return 0;
            }
            if (count <= 0) {
                bx_fail_id(x, "array size must be positive, got ", na, "");
                return 0;
            }
            if (count > 1048576) {
                bx_fail_id(x, "array size ", na, " is absurd");
                return 0;
            }
            if (allnum == 1) {
                return tt_mk(&mut x.tt, TT_ARRAY, elem, 0, count, 0, 0);
            }
            return tt_mk(&mut x.tt, TT_ARRAY, elem, 1, count, na, 0);
        }
        if (sx_head_is(x, s, "named") && n == 2) {
            let na: i64 = bx_atom(x, sx_child(x, s, 1));
            if (x.ok == 0) {
                return 0;
            }
            let eh: i64 = si_hash(&mut x.sp, na);
            if (si_has_h(&mut x.enums, eh, na)) {
                return tt_mk(&mut x.tt, TT_ENUM, 0, 0, 0, na, 0);
            }
            return tt_mk(&mut x.tt, TT_STRUCT, 0, 0, 0, na, 0);
        }
        if (sx_head_is(x, s, "infer") && n == 1) {
            return TT_INFER as i64;
        }
        if (sx_head_is(x, s, "tup")) {
            let cnt: i64 = n - 1;
            if (cnt < 2) {
                bx_fail(x, "a tuple type needs at least two elements");
                return 0;
            }
            let l: i64 = lp_add(&mut x.lp);
            var i: i64 = 1;
            while (i < n) {
                let t: i64 = bx_ty(x, sx_child(x, s, i));
                if (x.ok == 0) {
                    return 0;
                }
                lp_push(&mut x.lp, l, t);
                i += 1;
            }
            return tt_mk(&mut x.tt, TT_TUPLE, 0, 0, 0, 0, l);
        }
        if ((sx_head_is(x, s, "fnty") || sx_head_is(x, s, "fntyc")) && n == 3) {
            var isc: i32 = 0;
            if (sx_head_is(x, s, "fntyc")) {
                isc = 1;
            }
            let ps: i64 = sx_child(x, s, 1);
            if (!sx_is_list(x, ps)) {
                bx_fail(x, "bad type in IR");
                return 0;
            }
            let pn: i64 = sx_len(x, ps);
            let l: i64 = lp_add(&mut x.lp);
            var i: i64 = 0;
            while (i < pn) {
                let t: i64 = bx_ty(x, sx_child(x, ps, i));
                if (x.ok == 0) {
                    return 0;
                }
                lp_push(&mut x.lp, l, t);
                i += 1;
            }
            let rt: i64 = bx_ty(x, sx_child(x, s, 2));
            if (x.ok == 0) {
                return 0;
            }
            if (isc == 1) {
                return tt_mk(&mut x.tt, TT_FNC, rt, 0, 0, 0, l);
            }
            return tt_mk(&mut x.tt, TT_FN, rt, 0, 0, 0, l);
        }
        if (sx_head_is(x, s, "task") && n == 2) {
            let t: i64 = bx_ty(x, sx_child(x, s, 1));
            if (x.ok == 0) {
                return 0;
            }
            return tt_mk(&mut x.tt, TT_TASK, t, 0, 0, 0, 0);
        }
        if (sx_head_is(x, s, "var") && n == 2) {
            let na: i64 = bx_atom(x, sx_child(x, s, 1));
            if (x.ok == 0) {
                return 0;
            }
            return tt_mk(&mut x.tt, TT_VAR, 0, 0, 0, na, 0);
        }
        bx_fail(x, "bad type in IR");
        return 0;
    }
    let na2: i64 = sx_atom_id(x, s);
    if (na2 != 0) {
        bx_fail_id(x, "bad scalar type '", na2, "' in IR");
        return 0;
    }
    bx_fail(x, "bad type in IR");
    return 0;
}

fn iv_no() -> Iv {
    var r: Iv = zero(Iv);
    return r;
}

fn iv_yes(v: i64) -> Iv {
    var r: Iv = zero(Iv);
    r.ok = 1;
    r.v = v;
    return r;
}

fn bx_eval_int(x: &mut Bp, e: i64) -> Iv {
    if (e <= 0) {
        return iv_no();
    }
    var k: i32 = 0;
    unsafe { k = x.na.v[e].k; }
    if (k == EX_INT) {
        var v: i64 = 0;
        unsafe { v = x.na.v[e].n; }
        return iv_yes(v);
    }
    if (k == EX_UN) {
        var op: i64 = 0;
        var a: i64 = 0;
        unsafe {
            op = x.na.v[e].s;
            a = x.na.v[e].a;
        }
        let av: Iv = bx_eval_int(x, a);
        if (av.ok == 0) {
            return iv_no();
        }
        if (sp_eqc(&mut x.sp, op, "-")) {
            return iv_yes(0 - av.v);
        }
        if (sp_eqc(&mut x.sp, op, "~")) {
            return iv_yes(av.v ^ (0 - 1));
        }
        return iv_no();
    }
    if (k == EX_CAST) {
        var a2: i64 = 0;
        var t: i64 = 0;
        unsafe {
            a2 = x.na.v[e].a;
            t = x.na.v[e].b;
        }
        if (tt_is_int(&mut x.tt, t)) {
            let av2: Iv = bx_eval_int(x, a2);
            if (av2.ok == 0) {
                return iv_no();
            }
            let w: i64 = tt_wrap(&mut x.tt, t, av2.v);
            return iv_yes(w);
        }
        if (tt_tag(&mut x.tt, t) == TT_BOOL) {
            let av3: Iv = bx_eval_int(x, a2);
            if (av3.ok == 0) {
                return iv_no();
            }
            return iv_yes((av3.v != 0) as i64);
        }
        return iv_no();
    }
    if (k == EX_BIN) {
        var op2: i64 = 0;
        var a3: i64 = 0;
        var b3: i64 = 0;
        unsafe {
            op2 = x.na.v[e].s;
            a3 = x.na.v[e].a;
            b3 = x.na.v[e].b;
        }
        let xr: Iv = bx_eval_int(x, a3);
        if (xr.ok == 0) {
            return iv_no();
        }
        let yr: Iv = bx_eval_int(x, b3);
        if (yr.ok == 0) {
            return iv_no();
        }
        var ty: i64 = 0;
        unsafe { ty = x.na.v[a3].ty; }
        let xs: i64 = tt_wrap(&mut x.tt, ty, xr.v);
        let ys: i64 = tt_wrap(&mut x.tt, ty, yr.v);
        var r: i64 = 0;
        if (sp_eqc(&mut x.sp, op2, "+")) {
            r = tt_wrap(&mut x.tt, ty, xs + ys);
        } else if (sp_eqc(&mut x.sp, op2, "-")) {
            r = tt_wrap(&mut x.tt, ty, xs - ys);
        } else if (sp_eqc(&mut x.sp, op2, "*")) {
            r = tt_wrap(&mut x.tt, ty, xs * ys);
        } else if (sp_eqc(&mut x.sp, op2, "/")) {
            if (ys == 0) {
                return iv_no();
            }
            if (tt_is_signed(&mut x.tt, ty)) {
                r = tt_wrap(&mut x.tt, ty, xs / ys);
            } else {
                let ux: u64 = xs as u64;
                let uy: u64 = ys as u64;
                let ur: u64 = ux / uy;
                r = tt_wrap(&mut x.tt, ty, ur as i64);
            }
        } else if (sp_eqc(&mut x.sp, op2, "%")) {
            if (ys == 0) {
                return iv_no();
            }
            if (tt_is_signed(&mut x.tt, ty)) {
                r = tt_wrap(&mut x.tt, ty, xs % ys);
            } else {
                let ux2: u64 = xs as u64;
                let uy2: u64 = ys as u64;
                let ur2: u64 = ux2 % uy2;
                r = tt_wrap(&mut x.tt, ty, ur2 as i64);
            }
        } else if (sp_eqc(&mut x.sp, op2, "&")) {
            r = xs & ys;
        } else if (sp_eqc(&mut x.sp, op2, "|")) {
            r = xs | ys;
        } else if (sp_eqc(&mut x.sp, op2, "^")) {
            r = xs ^ ys;
        } else if (sp_eqc(&mut x.sp, op2, "<<")) {
            if (ys < 0 || ys > 63) {
                return iv_no();
            }
            r = tt_wrap(&mut x.tt, ty, xs << ys);
        } else if (sp_eqc(&mut x.sp, op2, ">>")) {
            if (ys < 0 || ys > 63) {
                return iv_no();
            }
            if (tt_is_signed(&mut x.tt, ty)) {
                r = tt_wrap(&mut x.tt, ty, xs >> ys);
            } else {
                let ux3: u64 = xs as u64;
                let sh3: u64 = ys as u64;
                let ur3: u64 = ux3 >> sh3;
                r = tt_wrap(&mut x.tt, ty, ur3 as i64);
            }
        } else if (sp_eqc(&mut x.sp, op2, "==")) {
            r = (xs == ys) as i64;
        } else if (sp_eqc(&mut x.sp, op2, "!=")) {
            r = (xs != ys) as i64;
        } else if (sp_eqc(&mut x.sp, op2, "<")) {
            if (tt_is_signed(&mut x.tt, ty)) {
                r = (xs < ys) as i64;
            } else {
                r = ((xs as u64) < (ys as u64)) as i64;
            }
        } else if (sp_eqc(&mut x.sp, op2, "<=")) {
            if (tt_is_signed(&mut x.tt, ty)) {
                r = (xs <= ys) as i64;
            } else {
                r = ((xs as u64) <= (ys as u64)) as i64;
            }
        } else if (sp_eqc(&mut x.sp, op2, ">")) {
            if (tt_is_signed(&mut x.tt, ty)) {
                r = (xs > ys) as i64;
            } else {
                r = ((xs as u64) > (ys as u64)) as i64;
            }
        } else if (sp_eqc(&mut x.sp, op2, ">=")) {
            if (tt_is_signed(&mut x.tt, ty)) {
                r = (xs >= ys) as i64;
            } else {
                r = ((xs as u64) >= (ys as u64)) as i64;
            }
        } else {
            return iv_no();
        }
        return iv_yes(r);
    }
    return iv_no();
}

fn bx_expr(x: &mut Bp, s: i64) -> i64 {
    if (!sx_is_list(x, s)) {
        bx_fail(x, "unrecognised expression in IR");
        return 0;
    }
    let n: i64 = sx_len(x, s);
    let h: i64 = sx_head(x, s);
    if (h == 0) {
        bx_fail(x, "unrecognised expression in IR");
        return 0;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "int")) {
        let a: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let p: ptr<u8> = sp_ptr(&mut x.sp, a);
        let ln: i64 = sp_len(&mut x.sp, a);
        let v: i64 = bx_num_of(p, ln);
        let e: i64 = na_add(&mut x.na, EX_INT);
        unsafe { x.na.v[e].n = v; }
        return e;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "float")) {
        let a: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let p: ptr<u8> = sp_ptr(&mut x.sp, a);
        let ln: i64 = sp_len(&mut x.sp, a);
        var tb: Sb = sb_new(ln + 2);
        if (tb.p == null) {
            bx_fail(x, "out of memory");
            return 0;
        }
        sb_put(&mut tb, p, ln);
        sb_putc(&mut tb, 0);
        let f: f64 = strtod(tb.p, null);
        sb_free(&mut tb);
        let e: i64 = na_add(&mut x.na, EX_FLOAT);
        unsafe { x.na.v[e].f = f; }
        return e;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "str")) {
        let a0: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let a: i64 = bx_unq(x, a0);
        let e: i64 = na_add(&mut x.na, EX_STR);
        unsafe { x.na.v[e].s = a; }
        return e;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "bool")) {
        let a: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        var yes: i32 = 0;
        if (sp_eqc(&mut x.sp, a, "true")) {
            yes = 1;
        }
        let e: i64 = na_add(&mut x.na, EX_BOOL);
        unsafe { x.na.v[e].n = yes as i64; }
        return e;
    }
    if (n == 1 && sp_eqc(&mut x.sp, h, "null")) {
        return na_add(&mut x.na, EX_NULL);
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "var")) {
        let a: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let e: i64 = na_add(&mut x.na, EX_VAR);
        unsafe { x.na.v[e].s = a; }
        return e;
    }
    if (n == 4 && sp_eqc(&mut x.sp, h, "bin")) {
        let op: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let a: i64 = bx_expr(x, sx_child(x, s, 2));
        if (x.ok == 0) {
            return 0;
        }
        let b: i64 = bx_expr(x, sx_child(x, s, 3));
        if (x.ok == 0) {
            return 0;
        }
        let e: i64 = na_add(&mut x.na, EX_BIN);
        unsafe {
            x.na.v[e].s = op;
            x.na.v[e].a = a;
            x.na.v[e].b = b;
        }
        return e;
    }
    if (n == 3 && sp_eqc(&mut x.sp, h, "un")) {
        let op2: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let a2: i64 = bx_expr(x, sx_child(x, s, 2));
        if (x.ok == 0) {
            return 0;
        }
        let e: i64 = na_add(&mut x.na, EX_UN);
        unsafe {
            x.na.v[e].s = op2;
            x.na.v[e].a = a2;
        }
        return e;
    }
    if (n >= 2 && sp_eqc(&mut x.sp, h, "call")) {
        let nm: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let l: i64 = lp_add(&mut x.lp);
        var i: i64 = 2;
        while (i < n) {
            let a: i64 = bx_expr(x, sx_child(x, s, i));
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, l, a);
            i += 1;
        }
        let e: i64 = na_add(&mut x.na, EX_CALL);
        unsafe {
            x.na.v[e].s = nm;
            x.na.v[e].l = l;
        }
        return e;
    }
    if (n == 3 && sp_eqc(&mut x.sp, h, "index")) {
        let a: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let b: i64 = bx_expr(x, sx_child(x, s, 2));
        if (x.ok == 0) {
            return 0;
        }
        let e: i64 = na_add(&mut x.na, EX_INDEX);
        unsafe {
            x.na.v[e].a = a;
            x.na.v[e].b = b;
        }
        return e;
    }
    if (n == 3 && sp_eqc(&mut x.sp, h, "field")) {
        let a: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let f: i64 = bx_atom(x, sx_child(x, s, 2));
        if (x.ok == 0) {
            return 0;
        }
        let e: i64 = na_add(&mut x.na, EX_FIELD);
        unsafe {
            x.na.v[e].a = a;
            x.na.v[e].s = f;
        }
        return e;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "deref")) {
        let a: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let e: i64 = na_add(&mut x.na, EX_DEREF);
        unsafe { x.na.v[e].a = a; }
        return e;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "addr")) {
        let a2: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let e2: i64 = na_add(&mut x.na, EX_ADDR);
        unsafe { x.na.v[e2].a = a2; }
        return e2;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "addrmut")) {
        let a3: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let e3: i64 = na_add(&mut x.na, EX_ADDRMUT);
        unsafe { x.na.v[e3].a = a3; }
        return e3;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "boxnew")) {
        let a4: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let e4: i64 = na_add(&mut x.na, EX_BOXNEW);
        unsafe { x.na.v[e4].a = a4; }
        return e4;
    }
    if (n == 3 && sp_eqc(&mut x.sp, h, "cast")) {
        let a5: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let t: i64 = bx_ty(x, sx_child(x, s, 2));
        if (x.ok == 0) {
            return 0;
        }
        let e5: i64 = na_add(&mut x.na, EX_CAST);
        unsafe {
            x.na.v[e5].a = a5;
            x.na.v[e5].b = t;
        }
        return e5;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "sizeof")) {
        let t2: i64 = bx_ty(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let e6: i64 = na_add(&mut x.na, EX_SIZEOF);
        unsafe { x.na.v[e6].a = t2; }
        return e6;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "zero")) {
        let t3: i64 = bx_ty(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let e7: i64 = na_add(&mut x.na, EX_ZERO);
        unsafe { x.na.v[e7].a = t3; }
        return e7;
    }
    if (n >= 2 && sp_eqc(&mut x.sp, h, "structlit")) {
        let nm2: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let l2: i64 = lp_add(&mut x.lp);
        var i2: i64 = 2;
        while (i2 < n) {
            let f: i64 = sx_child(x, s, i2);
            let fl: i64 = p_tag(x, "field", f);
            if (x.ok == 0) {
                return 0;
            }
            if (lp_len(&mut x.lp, fl) != 3) {
                bx_fail(x, "malformed field in struct literal");
                return 0;
            }
            let fname: i64 = bx_atom(x, lp_get(&mut x.lp, fl, 1));
            if (x.ok == 0) {
                return 0;
            }
            let fv: i64 = bx_expr(x, lp_get(&mut x.lp, fl, 2));
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, l2, fname);
            lp_push(&mut x.lp, l2, fv);
            i2 += 1;
        }
        let e8: i64 = na_add(&mut x.na, EX_STRUCTLIT);
        unsafe {
            x.na.v[e8].s = nm2;
            x.na.v[e8].l = l2;
        }
        return e8;
    }
    if (n >= 1 && sp_eqc(&mut x.sp, h, "arraylit")) {
        let l3: i64 = lp_add(&mut x.lp);
        var i3: i64 = 1;
        while (i3 < n) {
            let a6: i64 = bx_expr(x, sx_child(x, s, i3));
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, l3, a6);
            i3 += 1;
        }
        let e9: i64 = na_add(&mut x.na, EX_ARRAYLIT);
        unsafe { x.na.v[e9].l = l3; }
        return e9;
    }
    if (n >= 3 && sp_eqc(&mut x.sp, h, "enumlit")) {
        let en: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let vn: i64 = bx_atom(x, sx_child(x, s, 2));
        if (x.ok == 0) {
            return 0;
        }
        let l4: i64 = lp_add(&mut x.lp);
        var i4: i64 = 3;
        while (i4 < n) {
            let a7: i64 = bx_expr(x, sx_child(x, s, i4));
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, l4, a7);
            i4 += 1;
        }
        let e10: i64 = na_add(&mut x.na, EX_ENUMLIT);
        unsafe {
            x.na.v[e10].s = en;
            x.na.v[e10].s2 = vn;
            x.na.v[e10].l = l4;
        }
        return e10;
    }
    if (n >= 1 && sp_eqc(&mut x.sp, h, "tuplelit")) {
        let l5: i64 = lp_add(&mut x.lp);
        var i5: i64 = 1;
        while (i5 < n) {
            let a8: i64 = bx_expr(x, sx_child(x, s, i5));
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, l5, a8);
            i5 += 1;
        }
        let e11: i64 = na_add(&mut x.na, EX_TUPLELIT);
        unsafe { x.na.v[e11].l = l5; }
        return e11;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "fnref")) {
        let nm3: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let e12: i64 = na_add(&mut x.na, EX_FNREF);
        unsafe { x.na.v[e12].s = nm3; }
        return e12;
    }
    if (n >= 2 && sp_eqc(&mut x.sp, h, "callv")) {
        let f2: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let l6: i64 = lp_add(&mut x.lp);
        var i6: i64 = 2;
        while (i6 < n) {
            let a9: i64 = bx_expr(x, sx_child(x, s, i6));
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, l6, a9);
            i6 += 1;
        }
        let e13: i64 = na_add(&mut x.na, EX_CALLV);
        unsafe {
            x.na.v[e13].a = f2;
            x.na.v[e13].l = l6;
        }
        return e13;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "await")) {
        let a10: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let e14: i64 = na_add(&mut x.na, EX_AWAIT);
        unsafe { x.na.v[e14].a = a10; }
        return e14;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "poll")) {
        let a11: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let e15: i64 = na_add(&mut x.na, EX_POLL);
        unsafe { x.na.v[e15].a = a11; }
        return e15;
    }
    bx_fail(x, "unrecognised expression in IR");
    return 0;
}

fn bx_pat(x: &mut Bp, s: i64) -> i64 {
    let l: i64 = p_tag(x, "pat", s);
    if (x.ok == 0) {
        return 0;
    }
    let n: i64 = lp_len(&mut x.lp, l);
    if (n == 2) {
        if (sx_is_atom_c(x, lp_get(&mut x.lp, l, 1), "wild")) {
            return na_add(&mut x.na, PT_WILD);
        }
    }
    if (n >= 3) {
        let a1: i64 = lp_get(&mut x.lp, l, 1);
        let a2: i64 = lp_get(&mut x.lp, l, 2);
        let i1: i64 = sx_atom_id(x, a1);
        let i2: i64 = sx_atom_id(x, a2);
        if (i1 != 0 && i2 != 0) {
            let binds: i64 = lp_add(&mut x.lp);
            var i: i64 = 3;
            while (i < n) {
                let b: i64 = sx_atom_id(x, lp_get(&mut x.lp, l, i));
                if (b == 0) {
                    bx_fail(x, "bad pattern binding");
                    return 0;
                }
                lp_push(&mut x.lp, binds, b);
                i += 1;
            }
            let nd: i64 = na_add(&mut x.na, PT_VARIANT);
            unsafe {
                x.na.v[nd].s = i1;
                x.na.v[nd].s2 = i2;
                x.na.v[nd].l = binds;
            }
            return nd;
        }
    }
    bx_fail(x, "malformed (pat ...) in IR");
    return 0;
}

fn bx_arm(x: &mut Bp, s: i64) -> i64 {
    let l: i64 = p_tag(x, "arm", s);
    if (x.ok == 0) {
        return 0;
    }
    if (lp_len(&mut x.lp, l) != 3) {
        bx_fail(x, "malformed (arm ...) in IR");
        return 0;
    }
    let p: i64 = bx_pat(x, lp_get(&mut x.lp, l, 1));
    if (x.ok == 0) {
        return 0;
    }
    let body: i64 = p_tag(x, "body", lp_get(&mut x.lp, l, 2));
    if (x.ok == 0) {
        return 0;
    }
    let out: i64 = lp_add(&mut x.lp);
    let bn: i64 = lp_len(&mut x.lp, body);
    var i: i64 = 1;
    while (i < bn) {
        let st: i64 = bx_stmt(x, lp_get(&mut x.lp, body, i));
        if (x.ok == 0) {
            return 0;
        }
        lp_push(&mut x.lp, out, st);
        i += 1;
    }
    let nd: i64 = na_add(&mut x.na, AR_ARM);
    unsafe {
        x.na.v[nd].a = p;
        x.na.v[nd].l = out;
    }
    return nd;
}

fn bx_stmt_list(x: &mut Bp, l: i64) -> i64 {
    let out: i64 = lp_add(&mut x.lp);
    let n: i64 = lp_len(&mut x.lp, l);
    var i: i64 = 1;
    while (i < n) {
        let st: i64 = bx_stmt(x, lp_get(&mut x.lp, l, i));
        if (x.ok == 0) {
            return 0;
        }
        lp_push(&mut x.lp, out, st);
        i += 1;
    }
    return out;
}

fn bx_stmt(x: &mut Bp, s: i64) -> i64 {
    if (!sx_is_list(x, s)) {
        bx_fail(x, "unrecognised statement in IR");
        return 0;
    }
    let n: i64 = sx_len(x, s);
    let h: i64 = sx_head(x, s);
    if (h == 0) {
        bx_fail(x, "unrecognised statement in IR");
        return 0;
    }
    let is_let: bool = sp_eqc(&mut x.sp, h, "let");
    let is_var: bool = sp_eqc(&mut x.sp, h, "var");
    if (is_let || is_var) {
        var isvar: i32 = 0;
        if (is_var) {
            isvar = 1;
        }
        if (n == 3) {
            let nm: i64 = bx_atom(x, sx_child(x, s, 1));
            if (x.ok == 0) {
                return 0;
            }
            let t: i64 = bx_ty(x, sx_child(x, s, 2));
            if (x.ok == 0) {
                return 0;
            }
            let st: i64 = na_add(&mut x.na, ST_LET);
            unsafe {
                x.na.v[st].m = isvar;
                x.na.v[st].s = nm;
                x.na.v[st].a = t;
            }
            return st;
        }
        if (n == 4) {
            let nm2: i64 = bx_atom(x, sx_child(x, s, 1));
            if (x.ok == 0) {
                return 0;
            }
            let t2: i64 = bx_ty(x, sx_child(x, s, 2));
            if (x.ok == 0) {
                return 0;
            }
            let init: i64 = sx_child(x, s, 3);
            var val: i64 = 0;
            var isnone: i32 = 0;
            if (sx_is_list(x, init)) {
                if (sx_len(x, init) == 1) {
                    if (sx_is_atom_c(x, sx_child(x, init, 0), "none")) {
                        isnone = 1;
                    }
                }
            }
            if (isnone == 0) {
                val = bx_expr(x, init);
                if (x.ok == 0) {
                    return 0;
                }
            }
            let st2: i64 = na_add(&mut x.na, ST_LET);
            unsafe {
                x.na.v[st2].m = isvar;
                x.na.v[st2].s = nm2;
                x.na.v[st2].a = t2;
                x.na.v[st2].b = val;
            }
            return st2;
        }
        bx_fail(x, "malformed binding in IR");
        return 0;
    }
    if (n == 4 && sp_eqc(&mut x.sp, h, "assign")) {
        let op: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let a: i64 = bx_expr(x, sx_child(x, s, 2));
        if (x.ok == 0) {
            return 0;
        }
        let b: i64 = bx_expr(x, sx_child(x, s, 3));
        if (x.ok == 0) {
            return 0;
        }
        let st3: i64 = na_add(&mut x.na, ST_ASSIGN);
        unsafe {
            x.na.v[st3].s = op;
            x.na.v[st3].a = a;
            x.na.v[st3].b = b;
        }
        return st3;
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "expr")) {
        let a2: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let st4: i64 = na_add(&mut x.na, ST_EXPR);
        unsafe { x.na.v[st4].a = a2; }
        return st4;
    }
    if (n == 1 && sp_eqc(&mut x.sp, h, "break")) {
        return na_add(&mut x.na, ST_BREAK);
    }
    if (n == 1 && sp_eqc(&mut x.sp, h, "continue")) {
        return na_add(&mut x.na, ST_CONTINUE);
    }
    if (n == 1 && sp_eqc(&mut x.sp, h, "return")) {
        return na_add(&mut x.na, ST_RETURN);
    }
    if (n == 2 && sp_eqc(&mut x.sp, h, "return")) {
        let a3: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let st5: i64 = na_add(&mut x.na, ST_RETURN);
        unsafe { x.na.v[st5].a = a3; }
        return st5;
    }
    let is_blk: bool = sp_eqc(&mut x.sp, h, "block");
    let is_uns: bool = sp_eqc(&mut x.sp, h, "unsafe");
    if (n >= 1 && (is_blk || is_uns)) {
        var k: i32 = ST_BLOCK;
        if (is_uns) {
            k = ST_UNSAFE;
        }
        let bl: i64 = lp_add(&mut x.lp);
        var i: i64 = 1;
        while (i < n) {
            let st6: i64 = bx_stmt(x, sx_child(x, s, i));
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, bl, st6);
            i += 1;
        }
        let nd: i64 = na_add(&mut x.na, k);
        unsafe { x.na.v[nd].l = bl; }
        return nd;
    }
    if (n >= 3 && sp_eqc(&mut x.sp, h, "if")) {
        let cond: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let th: i64 = p_tag(x, "then", sx_child(x, s, 2));
        if (x.ok == 0) {
            return 0;
        }
        let thl: i64 = bx_stmt_list(x, th);
        if (x.ok == 0) {
            return 0;
        }
        var el: i64 = 0;
        if (n > 3) {
            if (n != 4) {
                bx_fail(x, "malformed (if ...) in IR");
                return 0;
            }
            let ebl: i64 = p_tag(x, "else", sx_child(x, s, 3));
            if (x.ok == 0) {
                return 0;
            }
            el = bx_stmt_list(x, ebl);
            if (x.ok == 0) {
                return 0;
            }
        } else {
            el = lp_add(&mut x.lp);
        }
        let st7: i64 = na_add(&mut x.na, ST_IF);
        unsafe {
            x.na.v[st7].a = cond;
            x.na.v[st7].l = thl;
            x.na.v[st7].l2 = el;
        }
        return st7;
    }
    if (n >= 2 && sp_eqc(&mut x.sp, h, "while")) {
        let cond2: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let bl2: i64 = lp_add(&mut x.lp);
        var i2: i64 = 2;
        while (i2 < n) {
            let st8: i64 = bx_stmt(x, sx_child(x, s, i2));
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, bl2, st8);
            i2 += 1;
        }
        let st9: i64 = na_add(&mut x.na, ST_WHILE);
        unsafe {
            x.na.v[st9].a = cond2;
            x.na.v[st9].l = bl2;
        }
        return st9;
    }
    if (n >= 1 && sp_eqc(&mut x.sp, h, "loop")) {
        let bl3: i64 = lp_add(&mut x.lp);
        var i3: i64 = 1;
        while (i3 < n) {
            let st10: i64 = bx_stmt(x, sx_child(x, s, i3));
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, bl3, st10);
            i3 += 1;
        }
        let st11: i64 = na_add(&mut x.na, ST_LOOP);
        unsafe { x.na.v[st11].l = bl3; }
        return st11;
    }
    if (n >= 4 && sp_eqc(&mut x.sp, h, "for")) {
        let vnm: i64 = bx_atom(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let a4: i64 = bx_expr(x, sx_child(x, s, 2));
        if (x.ok == 0) {
            return 0;
        }
        let b4: i64 = bx_expr(x, sx_child(x, s, 3));
        if (x.ok == 0) {
            return 0;
        }
        let bl4: i64 = lp_add(&mut x.lp);
        var i4: i64 = 4;
        while (i4 < n) {
            let st12: i64 = bx_stmt(x, sx_child(x, s, i4));
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, bl4, st12);
            i4 += 1;
        }
        let st13: i64 = na_add(&mut x.na, ST_FOR);
        unsafe {
            x.na.v[st13].s = vnm;
            x.na.v[st13].a = a4;
            x.na.v[st13].b = b4;
            x.na.v[st13].l = bl4;
        }
        return st13;
    }
    if (n >= 2 && sp_eqc(&mut x.sp, h, "match")) {
        let scrut: i64 = bx_expr(x, sx_child(x, s, 1));
        if (x.ok == 0) {
            return 0;
        }
        let arms: i64 = lp_add(&mut x.lp);
        var i5: i64 = 2;
        while (i5 < n) {
            let ar: i64 = bx_arm(x, sx_child(x, s, i5));
            if (x.ok == 0) {
                return 0;
            }
            lp_push(&mut x.lp, arms, ar);
            i5 += 1;
        }
        let st14: i64 = na_add(&mut x.na, ST_MATCH);
        unsafe {
            x.na.v[st14].a = scrut;
            x.na.v[st14].l = arms;
        }
        return st14;
    }
    bx_fail(x, "unrecognised statement in IR");
    return 0;
}

fn bx_program(x: &mut Bp) -> Pr {
    var p: Pr = zero(Pr);
    p.c = lp_add(&mut x.lp);
    p.g = lp_add(&mut x.lp);
    p.s = lp_add(&mut x.lp);
    p.e = lp_add(&mut x.lp);
    p.x = lp_add(&mut x.lp);
    p.f = lp_add(&mut x.lp);
    let items: i64 = p_tag(x, "program", x.root);
    if (x.ok == 0) {
        return p;
    }
    let n: i64 = lp_len(&mut x.lp, items);
    var i: i64 = 1;
    while (i < n) {
        let it: i64 = lp_get(&mut x.lp, items, i);
        if (sx_head_is(x, it, "enum")) {
            let nm: i64 = sx_atom_id(x, sx_child(x, it, 1));
            if (nm != 0) {
                let eh: i64 = si_hash(&mut x.sp, nm);
                si_add_h(&mut x.enums, eh, nm);
            }
        }
        i += 1;
    }
    i = 1;
    while (i < n) {
        let it2: i64 = lp_get(&mut x.lp, items, i);
        if (sx_head_is(x, it2, "const")) {
            let sc: i64 = sx_len(x, it2);
            if (sc != 4) {
                bx_fail(x, "malformed const in IR");
                return p;
            }
            let nm2: i64 = bx_atom(x, sx_child(x, it2, 1));
            if (x.ok == 0) {
                return p;
            }
            let t: i64 = bx_ty(x, sx_child(x, it2, 2));
            if (x.ok == 0) {
                return p;
            }
            let v: i64 = bx_expr(x, sx_child(x, it2, 3));
            if (x.ok == 0) {
                return p;
            }
            let cv: Iv = bx_eval_int(x, v);
            if (cv.ok == 1) {
                let ch: i64 = si_hash(&mut x.sp, nm2);
                mi_put(&mut x.sizes, ch, nm2, cv.v);
            }
            let nd: i64 = na_add(&mut x.na, IT_CONST);
            unsafe {
                x.na.v[nd].s = nm2;
                x.na.v[nd].a = t;
                x.na.v[nd].b = v;
            }
            lp_push(&mut x.lp, p.c, nd);
        }
        i += 1;
    }
    i = 1;
    while (i < n) {
        let it3: i64 = lp_get(&mut x.lp, items, i);
        let hn: i64 = sx_head(x, it3);
        if (hn == 0) {
            bx_fail(x, "unexpected top-level item in IR");
            return p;
        }
        if (sp_eqc(&mut x.sp, hn, "const")) {
        } else if (sp_eqc(&mut x.sp, hn, "struct")) {
            let sc2: i64 = sx_len(x, it3);
            let nm3: i64 = bx_atom(x, sx_child(x, it3, 1));
            if (x.ok == 0) {
                return p;
            }
            let fl: i64 = lp_add(&mut x.lp);
            var j: i64 = 2;
            while (j < sc2) {
                let f: i64 = p_tag(x, "field", sx_child(x, it3, j));
                if (x.ok == 0) {
                    return p;
                }
                if (lp_len(&mut x.lp, f) != 3) {
                    bx_fail(x, "malformed struct field in IR");
                    return p;
                }
                let fnm: i64 = bx_atom(x, lp_get(&mut x.lp, f, 1));
                if (x.ok == 0) {
                    return p;
                }
                let ft: i64 = bx_ty(x, lp_get(&mut x.lp, f, 2));
                if (x.ok == 0) {
                    return p;
                }
                lp_push(&mut x.lp, fl, fnm);
                lp_push(&mut x.lp, fl, ft);
                j += 1;
            }
            let sd: i64 = na_add(&mut x.na, IT_STRUCT);
            unsafe {
                x.na.v[sd].s = nm3;
                x.na.v[sd].l = fl;
            }
            lp_push(&mut x.lp, p.s, sd);
        } else if (sp_eqc(&mut x.sp, hn, "enum")) {
            let sc3: i64 = sx_len(x, it3);
            let nm4: i64 = bx_atom(x, sx_child(x, it3, 1));
            if (x.ok == 0) {
                return p;
            }
            let vl: i64 = lp_add(&mut x.lp);
            var j2: i64 = 2;
            while (j2 < sc3) {
                let v: i64 = p_tag(x, "variant", sx_child(x, it3, j2));
                if (x.ok == 0) {
                    return p;
                }
                let vn: i64 = lp_len(&mut x.lp, v);
                var vnm: i64 = 0;
                var payload: i64 = 0;
                if (vn == 2) {
                    vnm = bx_atom(x, lp_get(&mut x.lp, v, 1));
                    if (x.ok == 0) {
                        return p;
                    }
                    payload = lp_add(&mut x.lp);
                } else if (vn == 3) {
                    vnm = bx_atom(x, lp_get(&mut x.lp, v, 1));
                    if (x.ok == 0) {
                        return p;
                    }
                    let pl: i64 = p_tag(x, "payload", lp_get(&mut x.lp, v, 2));
                    if (x.ok == 0) {
                        return p;
                    }
                    let pn: i64 = lp_len(&mut x.lp, pl);
                    if (pn <= 1) {
                        bx_fail_id(x, "empty payload in enum '", nm4, "'");
                        return p;
                    }
                    payload = lp_add(&mut x.lp);
                    var k2: i64 = 1;
                    while (k2 < pn) {
                        let pt: i64 = bx_ty(x, lp_get(&mut x.lp, pl, k2));
                        if (x.ok == 0) {
                            return p;
                        }
                        lp_push(&mut x.lp, payload, pt);
                        k2 += 1;
                    }
                } else {
                    bx_fail(x, "malformed variant in IR");
                    return p;
                }
                lp_push(&mut x.lp, vl, vnm);
                lp_push(&mut x.lp, vl, payload);
                j2 += 1;
            }
            let ed: i64 = na_add(&mut x.na, IT_ENUM);
            unsafe {
                x.na.v[ed].s = nm4;
                x.na.v[ed].l = vl;
            }
            lp_push(&mut x.lp, p.e, ed);
        } else if (sp_eqc(&mut x.sp, hn, "extern")) {
            let sc4: i64 = sx_len(x, it3);
            let nm5: i64 = bx_atom(x, sx_child(x, it3, 1));
            if (x.ok == 0) {
                return p;
            }
            let ps: i64 = lp_add(&mut x.lp);
            var lib: i64 = 0;
            var variadic: i32 = 0;
            var ret: i64 = TT_VOID as i64;
            var j3: i64 = 2;
            while (j3 < sc4) {
                let part: i64 = sx_child(x, it3, j3);
                if (sx_head_is(x, part, "param") && sx_len(x, part) == 2) {
                    let pt2: i64 = bx_ty(x, sx_child(x, part, 1));
                    if (x.ok == 0) {
                        return p;
                    }
                    lp_push(&mut x.lp, ps, pt2);
                } else if (sx_head_is(x, part, "variadic") && sx_len(x, part) == 1) {
                    variadic = 1;
                } else if (sx_head_is(x, part, "ret") && sx_len(x, part) == 2) {
                    ret = bx_ty(x, sx_child(x, part, 1));
                    if (x.ok == 0) {
                        return p;
                    }
                } else if (sx_head_is(x, part, "lib") && sx_len(x, part) == 2) {
                    var lname: i64 = sx_atom_id(x, sx_child(x, part, 1));
                    if (lname == 0) {
                        bx_fail(x, "malformed extern in IR");
                        return p;
                    }
                    let lp2: ptr<u8> = sp_ptr(&mut x.sp, lname);
                    let llen: i64 = sp_len(&mut x.sp, lname);
                    var s0: u8 = 0;
                    var s1: u8 = 0;
                    if (llen >= 2) {
                        unsafe {
                            s0 = lp2[0];
                            s1 = lp2[llen - 1];
                        }
                    }
                    if (llen >= 2 && s0 == 34 && s1 == 34) {
                        lib = sp_intern(&mut x.sp, p_off(lp2, 1), llen - 2);
                    } else {
                        lib = lname;
                    }
                } else {
                    bx_fail(x, "malformed extern in IR");
                    return p;
                }
                j3 += 1;
            }
            let xd: i64 = na_add(&mut x.na, IT_EXTERN);
            unsafe {
                x.na.v[xd].s = nm5;
                x.na.v[xd].s2 = lib;
                x.na.v[xd].l = ps;
                x.na.v[xd].a = ret;
                x.na.v[xd].m = variadic;
            }
            lp_push(&mut x.lp, p.x, xd);
        } else if (sp_eqc(&mut x.sp, hn, "fn")) {
            let sc5: i64 = sx_len(x, it3);
            let nm6: i64 = bx_atom(x, sx_child(x, it3, 1));
            if (x.ok == 0) {
                return p;
            }
            let ps2: i64 = lp_add(&mut x.lp);
            let gens: i64 = lp_add(&mut x.lp);
            var ret2: i64 = TT_VOID as i64;
            var asy: i32 = 0;
            var cab: i32 = 0;
            var body: i64 = 0;
            var j4: i64 = 2;
            while (j4 < sc5) {
                let part2: i64 = sx_child(x, it3, j4);
                if (sx_head_is(x, part2, "param") && sx_len(x, part2) == 3) {
                    let pn: i64 = bx_atom(x, sx_child(x, part2, 1));
                    if (x.ok == 0) {
                        return p;
                    }
                    let pt3: i64 = bx_ty(x, sx_child(x, part2, 2));
                    if (x.ok == 0) {
                        return p;
                    }
                    lp_push(&mut x.lp, ps2, pn);
                    lp_push(&mut x.lp, ps2, pt3);
                } else if (sx_head_is(x, part2, "ret") && sx_len(x, part2) == 2) {
                    ret2 = bx_ty(x, sx_child(x, part2, 1));
                    if (x.ok == 0) {
                        return p;
                    }
                } else if (sx_head_is(x, part2, "async") && sx_len(x, part2) == 1) {
                    asy = 1;
                } else if (sx_head_is(x, part2, "c-abi") && sx_len(x, part2) == 1) {
                    cab = 1;
                } else if (sx_head_is(x, part2, "generic")) {
                    let gn: i64 = sx_len(x, part2);
                    var k3: i64 = 1;
                    while (k3 < gn) {
                        let g: i64 = bx_atom(x, sx_child(x, part2, k3));
                        if (x.ok == 0) {
                            return p;
                        }
                        lp_push(&mut x.lp, gens, g);
                        k3 += 1;
                    }
                } else if (sx_head_is(x, part2, "body")) {
                    let bl: i64 = sx_list(x, part2);
                    let b2: i64 = lp_add(&mut x.lp);
                    let bn: i64 = lp_len(&mut x.lp, bl);
                    var k4: i64 = 1;
                    while (k4 < bn) {
                        let st: i64 = bx_stmt(x, lp_get(&mut x.lp, bl, k4));
                        if (x.ok == 0) {
                            return p;
                        }
                        lp_push(&mut x.lp, b2, st);
                        k4 += 1;
                    }
                    body = b2;
                } else {
                    bx_fail(x, "malformed fn in IR");
                    return p;
                }
                j4 += 1;
            }
            if (body == 0) {
                body = lp_add(&mut x.lp);
            }
            let fd: i64 = na_add(&mut x.na, IT_FN);
            unsafe {
                x.na.v[fd].s = nm6;
                x.na.v[fd].l = gens;
                x.na.v[fd].l2 = ps2;
                x.na.v[fd].a = ret2;
                x.na.v[fd].n = asy as i64;
                x.na.v[fd].m = cab;
                x.na.v[fd].l3 = body;
            }
            lp_push(&mut x.lp, p.f, fd);
        } else {
            bx_fail(x, "unexpected top-level item in IR");
            return p;
        }
        i += 1;
    }
    return p;
}

fn bx_parse_ir(x: &mut Bp, text: ptr<u8>, n: i64) -> Pr {
    var p: Pr = zero(Pr);
    if (bx_read(x, text, n) == 0) {
        return p;
    }
    return bx_program(x);
}
