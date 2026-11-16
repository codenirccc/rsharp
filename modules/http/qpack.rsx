include "rt.rsx";
include "hpack.rsx";
include "qpack_tables.rsx";

const QPACK_OK: i32 = 0;
const QPACK_ERR: i32 = -1;

struct Qpack {
    tree: HpTree,
    out: HpOut
}

fn qpack_new() -> Qpack {
    var q: Qpack = zero(Qpack);
    q.out = hp_out_new();
    if (hp_tree_init(&mut q.tree) != HPACK_OK) {
        q.tree.nodes = -1;
    }
    return q;
}

fn qpack_free(q: &mut Qpack) {
    hp_out_free(&mut q.out);
}

fn qpack_ready(q: &mut Qpack) -> i32 {
    if (q.tree.nodes <= 0) {
        return 0;
    }
    return 1;
}

fn qpk_static_at(idx: i64, o: &mut HpOut) -> i32 {
    if (idx < 0 || idx >= QPACK_STATIC_N) {
        return QPACK_ERR;
    }
    let np: ptr<u8> = qpack_static_name(idx);
    let vp: ptr<u8> = qpack_static_value(idx);
    return hp_out_add(o, np, rt_len(np), vp, rt_len(vp));
}

fn qpk_decode(q: &mut Qpack, p: ptr<u8>, n: i64) -> i32 {
    if (q.tree.nodes <= 0 || p == null || n < 2) {
        return QPACK_ERR;
    }
    hp_out_clear(&mut q.out);

    var c: HpCur = zero(HpCur);
    c.p = p;
    c.n = n;
    c.i = 0;

    let ric: i64 = hp_int(&mut c, 8);
    if (ric < 0) {
        return QPACK_ERR;
    }
    let dbase: i64 = hp_int(&mut c, 7);
    if (dbase < 0) {
        return QPACK_ERR;
    }
    if (ric != 0 || dbase != 0) {
        return QPACK_ERR;
    }

    var sn: HxBuf = hxbuf_new(256);
    var sv: HxBuf = hxbuf_new(2048);
    if (sn.p == null || sv.p == null) {
        hxbuf_free(&mut sn);
        hxbuf_free(&mut sv);
        return QPACK_ERR;
    }

    var rc: i32 = QPACK_OK;
    while (c.i < c.n) {
        var b: u8 = 0;
        unsafe { b = p[c.i]; }
        let bi: i64 = b as i64;

        if ((bi & 0x80) != 0) {
            if ((bi & 0x40) == 0) {
                rc = QPACK_ERR;
                c.i = c.n;
            } else {
                let idx: i64 = hp_int(&mut c, 6);
                if (qpk_static_at(idx, &mut q.out) != QPACK_OK) {
                    rc = QPACK_ERR;
                    c.i = c.n;
                }
            }
        } else if ((bi & 0x40) != 0) {
            if ((bi & 0x10) == 0) {
                rc = QPACK_ERR;
                c.i = c.n;
            } else {
                let idx: i64 = hp_int(&mut c, 4);
                sn.len = 0;
                sv.len = 0;
                let vl: i64 = hp_str(&mut c, &mut q.tree, &mut sv);
                if (idx < 0 || idx >= QPACK_STATIC_N || vl < 0) {
                    rc = QPACK_ERR;
                    c.i = c.n;
                } else {
                    let np: ptr<u8> = qpack_static_name(idx);
                    let nl: i64 = rt_len(np);
                    if (hp_out_add(&mut q.out, np, nl, sv.p, vl) != QPACK_OK) {
                        rc = QPACK_ERR;
                        c.i = c.n;
                    }
                }
            }
        } else if ((bi & 0x20) != 0) {
            let huff: i64 = bi & 0x08;
            let nl: i64 = hp_int(&mut c, 3);
            sn.len = 0;
            sv.len = 0;
            if (nl < 0 || c.i + nl > c.n) {
                rc = QPACK_ERR;
                c.i = c.n;
            } else {
                var np: ptr<u8> = null;
                unsafe { np = p + c.i; }
                var got: i64 = nl;
                if (huff != 0) {
                    got = hp_huff(np, nl, &mut q.tree, &mut sn);
                } else if (hxbuf_put(&mut sn, np, nl) != 0) {
                    got = -1;
                }
                c.i += nl;
                if (got < 0) {
                    rc = QPACK_ERR;
                    c.i = c.n;
                } else {
                    let vl: i64 = hp_str(&mut c, &mut q.tree, &mut sv);
                    if (vl < 0) {
                        rc = QPACK_ERR;
                        c.i = c.n;
                    } else if (hp_out_add(&mut q.out, sn.p, got, sv.p, vl) != QPACK_OK) {
                        rc = QPACK_ERR;
                        c.i = c.n;
                    }
                }
            }
        } else {
            rc = QPACK_ERR;
            c.i = c.n;
        }
    }

    hxbuf_free(&mut sn);
    hxbuf_free(&mut sv);
    if (rc != QPACK_OK) {
        hp_out_clear(&mut q.out);
        return QPACK_ERR;
    }
    return QPACK_OK;
}

fn qpack_count(q: &mut Qpack) -> i64 {
    return q.out.n;
}

fn qpack_name(q: &mut Qpack, i: i64) -> ptr<u8> {
    return hp_out_name(&mut q.out, i);
}

fn qpack_namelen(q: &mut Qpack, i: i64) -> i64 {
    return hp_out_nlen(&mut q.out, i);
}

fn qpack_value(q: &mut Qpack, i: i64) -> ptr<u8> {
    return hp_out_value(&mut q.out, i);
}

fn qpack_vallen(q: &mut Qpack, i: i64) -> i64 {
    return hp_out_vlen(&mut q.out, i);
}

fn qpack_find(q: &mut Qpack, name: ptr<u8>, nlen: i64) -> i64 {
    return hp_out_find(&mut q.out, name, nlen);
}

fn qpack_header_is(q: &mut Qpack, i: i64, name: ptr<u8>, value: ptr<u8>) -> i32 {
    if (i < 0 || i >= q.out.n) {
        return 0;
    }
    let np: ptr<u8> = hp_out_name(&mut q.out, i);
    let nl: i64 = hp_out_nlen(&mut q.out, i);
    let vp: ptr<u8> = hp_out_value(&mut q.out, i);
    let vl: i64 = hp_out_vlen(&mut q.out, i);
    let wn: i64 = rt_len(name);
    let wv: i64 = rt_len(value);
    if (nl != wn || vl != wv) {
        return 0;
    }
    if (nl > 0 && hp_ieq(np, name, nl) != 1) {
        return 0;
    }
    if (vl > 0 && hp_ieq(vp, value, vl) != 1) {
        return 0;
    }
    return 1;
}

fn qpk_find_pair(name: ptr<u8>, nlen: i64, value: ptr<u8>, vlen: i64) -> i64 {
    var i: i64 = 0;
    while (i < QPACK_STATIC_N) {
        let sn: ptr<u8> = qpack_static_name(i);
        let sv: ptr<u8> = qpack_static_value(i);
        if (rt_len(sn) == nlen && rt_len(sv) == vlen) {
            if (nlen == 0 || hp_ieq(sn, name, nlen) == 1) {
                if (vlen == 0 || hp_ieq(sv, value, vlen) == 1) {
                    return i;
                }
            }
        }
        i += 1;
    }
    return -1;
}

fn qpk_find_name(name: ptr<u8>, nlen: i64) -> i64 {
    var i: i64 = 0;
    while (i < QPACK_STATIC_N) {
        let sn: ptr<u8> = qpack_static_name(i);
        if (rt_len(sn) == nlen && (nlen == 0 || hp_ieq(sn, name, nlen) == 1)) {
            return i;
        }
        i += 1;
    }
    return -1;
}

fn qpk_block(src: &mut HpOut, out: &mut HxBuf) -> i32 {
    if (hxbuf_putc(out, 0) != 0) {
        return QPACK_ERR;
    }
    if (hxbuf_putc(out, 0) != 0) {
        return QPACK_ERR;
    }
    var i: i64 = 0;
    while (i < src.n) {
        let np: ptr<u8> = hp_out_name(src, i);
        let nl: i64 = hp_out_nlen(src, i);
        let vp: ptr<u8> = hp_out_value(src, i);
        let vl: i64 = hp_out_vlen(src, i);
        let ex: i64 = qpk_find_pair(np, nl, vp, vl);
        if (ex >= 0) {
            if (hp_put_int(out, ex, 6, 0xc0) != HPACK_OK) {
                return QPACK_ERR;
            }
        } else {
            let nm: i64 = qpk_find_name(np, nl);
            if (nm >= 0) {
                if (hp_put_int(out, nm, 4, 0x50) != HPACK_OK) {
                    return QPACK_ERR;
                }
            } else {
                if (hp_put_int(out, nl, 3, 0x20) != HPACK_OK) {
                    return QPACK_ERR;
                }
                if (nl > 0 && hxbuf_put(out, np, nl) != 0) {
                    return QPACK_ERR;
                }
            }
            if (hp_put_str(out, vp, vl) != HPACK_OK) {
                return QPACK_ERR;
            }
        }
        i += 1;
    }
    return QPACK_OK;
}
