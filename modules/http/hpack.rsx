include "rt.rsx";
include "hpack_tables.rsx";

const HPACK_OK: i32 = 0;
const HPACK_ERR: i32 = -1;

const HP_TREE: i64 = 520;
const HP_ENTRIES: i64 = 64;
const HP_HEADERS: i64 = 96;
const HP_ARENA: i64 = 524288;
const HP_DEFAULT_MAX: i64 = 4096;

struct HpTree {
    left: [i64; 520],
    right: [i64; 520],
    sym: [i64; 520],
    nodes: i64
}

struct HpDyn {
    buf: HxBuf,
    noff: [i64; 64],
    nlen: [i64; 64],
    voff: [i64; 64],
    vlen: [i64; 64],
    n: i64,
    size: i64,
    max: i64
}

struct HpCur {
    p: ptr<u8>,
    n: i64,
    i: i64
}

struct HpOut {
    buf: HxBuf,
    noff: [i64; 96],
    nlen: [i64; 96],
    voff: [i64; 96],
    vlen: [i64; 96],
    n: i64
}

struct HpKV {
    np: ptr<u8>,
    nl: i64,
    vp: ptr<u8>,
    vl: i64
}

struct Hpack {
    tree: HpTree,
    dyn: HpDyn,
    out: HpOut
}

fn hp_ieq(a: ptr<u8>, b: ptr<u8>, n: i64) -> i32 {
    var i: i64 = 0;
    while (i < n) {
        var x: u8 = 0;
        var y: u8 = 0;
        unsafe {
            x = a[i];
            y = b[i];
        }
        if (x >= 65 && x <= 90) {
            x = (x + 32) as u8;
        }
        if (y >= 65 && y <= 90) {
            y = (y + 32) as u8;
        }
        if (x != y) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn hp_tree_init(t: &mut HpTree) -> i32 {
    t.nodes = 1;
    var i: i64 = 0;
    while (i < HP_TREE) {
        t.left[i] = -1;
        t.right[i] = -1;
        t.sym[i] = -1;
        i += 1;
    }
    i = 0;
    while (i < HPACK_HUFF_N) {
        let code: i64 = hpack_huff_code(i);
        let bits: i64 = hpack_huff_bits(i);
        if (code < 0 || bits < 1 || bits > 30) {
            return HPACK_ERR;
        }
        var cur: i64 = 0;
        var b: i64 = bits - 1;
        while (b >= 0) {
            let d: i64 = (code >> b) & 1;
            var nxt: i64 = -1;
            if (d == 1) {
                nxt = t.right[cur];
            } else {
                nxt = t.left[cur];
            }
            if (nxt < 0) {
                if (t.nodes >= HP_TREE) {
                    return HPACK_ERR;
                }
                nxt = t.nodes;
                t.nodes += 1;
                if (d == 1) {
                    t.right[cur] = nxt;
                } else {
                    t.left[cur] = nxt;
                }
            }
            cur = nxt;
            b -= 1;
        }
        if (t.sym[cur] >= 0) {
            return HPACK_ERR;
        }
        t.sym[cur] = i;
        i += 1;
    }
    return HPACK_OK;
}

fn hp_int(c: &mut HpCur, prefix: i64) -> i64 {
    if (c.i < 0 || c.i >= c.n || prefix < 1 || prefix > 8) {
        return -1;
    }
    let mask: i64 = (1 << prefix) - 1;
    var b: u8 = 0;
    unsafe { b = c.p[c.i]; }
    c.i += 1;
    var v: i64 = (b as i64) & mask;
    if (v < mask) {
        return v;
    }
    var shift: i64 = 0;
    var go: i32 = 1;
    while (go == 1) {
        if (c.i >= c.n) {
            return -1;
        }
        var nb: u8 = 0;
        unsafe { nb = c.p[c.i]; }
        c.i += 1;
        v += (((nb as i64) & 127) << shift);
        shift += 7;
        if (shift > 28 || v > 1073741824) {
            return -1;
        }
        if (((nb as i64) & 128) == 0) {
            go = 0;
        }
    }
    return v;
}

fn hp_huff(p: ptr<u8>, n: i64, t: &mut HpTree, out: &mut HxBuf) -> i64 {
    var node: i64 = 0;
    var total: i64 = 0;
    var ones: i32 = 1;
    var mark: i64 = 0;
    var i: i64 = 0;
    while (i < n) {
        var b: u8 = 0;
        unsafe { b = p[i]; }
        var k: i64 = 7;
        while (k >= 0) {
            let dir: i64 = ((b as i64) >> k) & 1;
            if (dir == 1) {
                node = t.right[node];
            } else {
                node = t.left[node];
                ones = 0;
            }
            if (node < 0) {
                return -1;
            }
            let s: i64 = t.sym[node];
            if (s >= 0) {
                if (s < 256) {
                    if (hxbuf_putc(out, s as u8) != 0) {
                        return -1;
                    }
                    total += 1;
                } else if (s != 256) {
                    return -1;
                }
                node = 0;
                ones = 1;
                mark = 0;
            } else {
                mark += 1;
            }
            k -= 1;
        }
        i += 1;
    }
    if (node != 0) {
        if (mark >= 8 || ones != 1) {
            return -1;
        }
    }
    return total;
}

fn hp_str(c: &mut HpCur, t: &mut HpTree, out: &mut HxBuf) -> i64 {
    if (c.i >= c.n) {
        return -1;
    }
    var b: u8 = 0;
    unsafe { b = c.p[c.i]; }
    var huff: i32 = 0;
    if (((b as i64) & 128) != 0) {
        huff = 1;
    }
    let len: i64 = hp_int(c, 7);
    if (len < 0 || c.i + len > c.n) {
        return -1;
    }
    if (huff == 1) {
        var hp: ptr<u8> = null;
        unsafe { hp = c.p + c.i; }
        let got: i64 = hp_huff(hp, len, t, out);
        if (got < 0) {
            return -1;
        }
        c.i += len;
        return got;
    }
    var raw: ptr<u8> = null;
    unsafe { raw = c.p + c.i; }
    if (hxbuf_put(out, raw, len) != 0) {
        return -1;
    }
    c.i += len;
    return len;
}

fn hp_dyn_new() -> HpDyn {
    var d: HpDyn = zero(HpDyn);
    d.buf = hxbuf_new(1024);
    d.n = 0;
    d.size = 0;
    d.max = HP_DEFAULT_MAX;
    return d;
}

fn hp_dyn_free(d: &mut HpDyn) {
    hxbuf_free(&mut d.buf);
    d.n = 0;
    d.size = 0;
}

fn hp_dyn_reset(d: &mut HpDyn) {
    d.n = 0;
    d.size = 0;
    d.buf.len = 0;
}

fn hp_dyn_evict(d: &mut HpDyn) {
    if (d.n <= 0) {
        return;
    }
    let s: i64 = d.n - 1;
    d.size -= d.nlen[s] + d.vlen[s] + 32;
    if (d.size < 0) {
        d.size = 0;
    }
    d.n -= 1;
}

fn hp_dyn_pack(d: &mut HpDyn) -> i32 {
    var nb: HxBuf = hxbuf_new(d.buf.len + 64);
    if (nb.p == null) {
        return HPACK_ERR;
    }
    var k: i64 = 0;
    while (k < d.n) {
        var np: ptr<u8> = null;
        var vp: ptr<u8> = null;
        unsafe {
            np = d.buf.p + d.noff[k];
            vp = d.buf.p + d.voff[k];
        }
        if (hxbuf_put(&mut nb, np, d.nlen[k]) != 0) {
            hxbuf_free(&mut nb);
            return HPACK_ERR;
        }
        let no: i64 = nb.len - d.nlen[k];
        if (hxbuf_put(&mut nb, vp, d.vlen[k]) != 0) {
            hxbuf_free(&mut nb);
            return HPACK_ERR;
        }
        let vo: i64 = nb.len - d.vlen[k];
        d.noff[k] = no;
        d.voff[k] = vo;
        k += 1;
    }
    hxbuf_free(&mut d.buf);
    d.buf = nb;
    return HPACK_OK;
}

fn hp_dyn_add(d: &mut HpDyn, np: ptr<u8>, nl: i64, vp: ptr<u8>, vl: i64) -> i32 {
    if (nl < 0 || vl < 0 || np == null || vp == null) {
        return HPACK_ERR;
    }
    let esz: i64 = nl + vl + 32;
    if (esz > d.max) {
        hp_dyn_reset(d);
        return HPACK_OK;
    }
    while (d.n > 0 && d.size + esz > d.max) {
        hp_dyn_evict(d);
    }
    if (d.n >= HP_ENTRIES) {
        hp_dyn_evict(d);
    }
    if (d.buf.len > HP_ARENA) {
        if (hp_dyn_pack(d) != HPACK_OK) {
            return HPACK_ERR;
        }
    }
    var k: i64 = d.n;
    while (k > 0) {
        d.noff[k] = d.noff[k - 1];
        d.nlen[k] = d.nlen[k - 1];
        d.voff[k] = d.voff[k - 1];
        d.vlen[k] = d.vlen[k - 1];
        k -= 1;
    }
    if (hxbuf_put(&mut d.buf, np, nl) != 0) {
        return HPACK_ERR;
    }
    let no: i64 = d.buf.len - nl;
    if (hxbuf_put(&mut d.buf, vp, vl) != 0) {
        return HPACK_ERR;
    }
    let vo: i64 = d.buf.len - vl;
    d.noff[0] = no;
    d.nlen[0] = nl;
    d.voff[0] = vo;
    d.vlen[0] = vl;
    d.n += 1;
    d.size += esz;
    return HPACK_OK;
}

fn hp_resolve(d: &mut HpDyn, idx: i64) -> HpKV {
    var r: HpKV = zero(HpKV);
    if (idx <= 0) {
        return r;
    }
    if (idx <= HPACK_STATIC_N) {
        r.np = hpack_static_name(idx - 1);
        r.nl = rt_len(r.np);
        r.vp = hpack_static_value(idx - 1);
        r.vl = rt_len(r.vp);
        return r;
    }
    let s: i64 = idx - HPACK_STATIC_N - 1;
    if (s < 0 || s >= d.n || d.buf.p == null) {
        return r;
    }
    var np: ptr<u8> = null;
    var vp: ptr<u8> = null;
    unsafe {
        np = d.buf.p + d.noff[s];
        vp = d.buf.p + d.voff[s];
    }
    r.np = np;
    r.nl = d.nlen[s];
    r.vp = vp;
    r.vl = d.vlen[s];
    return r;
}

fn hp_out_new() -> HpOut {
    var o: HpOut = zero(HpOut);
    o.buf = hxbuf_new(1024);
    o.n = 0;
    return o;
}

fn hp_out_free(o: &mut HpOut) {
    hxbuf_free(&mut o.buf);
    o.n = 0;
}

fn hp_out_clear(o: &mut HpOut) {
    o.buf.len = 0;
    o.n = 0;
}

fn hp_pair_ok(np: ptr<u8>, nl: i64, vp: ptr<u8>, vl: i64) -> i32 {
    if (nl <= 0 || nl > 4096 || vl < 0 || vl > 1048576) {
        return 0;
    }
    var i: i64 = 0;
    while (i < nl) {
        let c: u8 = rt_byte(np, i);
        var ok: i32 = 0;
        if (c >= 97 && c <= 122) {
            ok = 1;
        }
        if (c >= 65 && c <= 90) {
            ok = 1;
        }
        if (c >= 48 && c <= 57) {
            ok = 1;
        }
        if (c == 33 || c == 35 || c == 36 || c == 37 || c == 38 || c == 39 || c == 42 || c == 43) {
            ok = 1;
        }
        if (c == 45 || c == 46 || c == 58 || c == 94 || c == 95 || c == 96 || c == 124 || c == 126) {
            ok = 1;
        }
        if (ok != 1) {
            return 0;
        }
        i += 1;
    }
    var k: i64 = 0;
    while (k < vl) {
        let v: u8 = rt_byte(vp, k);
        if (v == 13 || v == 10 || v == 0) {
            return 0;
        }
        if (v < 32 && v != 9) {
            return 0;
        }
        if (v == 127) {
            return 0;
        }
        k += 1;
    }
    return 1;
}

fn hp_out_add(o: &mut HpOut, np: ptr<u8>, nl: i64, vp: ptr<u8>, vl: i64) -> i32 {
    if (o.n >= HP_HEADERS || hp_pair_ok(np, nl, vp, vl) != 1) {
        return HPACK_ERR;
    }
    if (hxbuf_put(&mut o.buf, np, nl) != 0) {
        return HPACK_ERR;
    }
    let no: i64 = o.buf.len - nl;
    if (hxbuf_put(&mut o.buf, vp, vl) != 0) {
        return HPACK_ERR;
    }
    let vo: i64 = o.buf.len - vl;
    let s: i64 = o.n;
    o.noff[s] = no;
    o.nlen[s] = nl;
    o.voff[s] = vo;
    o.vlen[s] = vl;
    o.n += 1;
    return HPACK_OK;
}

fn hp_out_find(o: &mut HpOut, name: ptr<u8>, nlen: i64) -> i64 {
    if (o.buf.p == null) {
        return -1;
    }
    var i: i64 = 0;
    while (i < o.n) {
        if (o.nlen[i] == nlen) {
            var np: ptr<u8> = null;
            unsafe { np = o.buf.p + o.noff[i]; }
            if (hp_ieq(np, name, nlen) == 1) {
                return i;
            }
        }
        i += 1;
    }
    return -1;
}

fn hp_out_name(o: &mut HpOut, i: i64) -> ptr<u8> {
    if (o.buf.p == null || i < 0 || i >= o.n) {
        return null;
    }
    var np: ptr<u8> = null;
    unsafe { np = o.buf.p + o.noff[i]; }
    return np;
}

fn hp_out_value(o: &mut HpOut, i: i64) -> ptr<u8> {
    if (o.buf.p == null || i < 0 || i >= o.n) {
        return null;
    }
    var vp: ptr<u8> = null;
    unsafe { vp = o.buf.p + o.voff[i]; }
    return vp;
}

fn hp_out_vlen(o: &mut HpOut, i: i64) -> i64 {
    if (i < 0 || i >= o.n) {
        return 0;
    }
    return o.vlen[i];
}

fn hp_out_nlen(o: &mut HpOut, i: i64) -> i64 {
    if (i < 0 || i >= o.n) {
        return 0;
    }
    return o.nlen[i];
}

fn hp_block(h: &mut Hpack, p: ptr<u8>, n: i64, sn: &mut HxBuf, sv: &mut HxBuf) -> i32 {
    var c: HpCur = zero(HpCur);
    c.p = p;
    c.n = n;
    c.i = 0;
    while (c.i < n) {
        var b: u8 = 0;
        unsafe { b = c.p[c.i]; }
        let top: i64 = b as i64;

        if ((top & 128) != 0) {
            let idx: i64 = hp_int(&mut c, 7);
            let kv: HpKV = hp_resolve(&mut h.dyn, idx);
            if (kv.np == null) {
                return HPACK_ERR;
            }
            if (hp_out_add(&mut h.out, kv.np, kv.nl, kv.vp, kv.vl) != HPACK_OK) {
                return HPACK_ERR;
            }
            continue;
        }

        if ((top & 224) == 32) {
            let sz: i64 = hp_int(&mut c, 5);
            if (sz < 0 || sz > h.dyn.max) {
                return HPACK_ERR;
            }
            h.dyn.max = sz;
            while (h.dyn.n > 0 && h.dyn.size > h.dyn.max) {
                hp_dyn_evict(&mut h.dyn);
            }
            continue;
        }

        var incremental: i32 = 0;
        var prefix: i64 = 4;
        if ((top & 64) != 0) {
            incremental = 1;
            prefix = 6;
        }

        let nidx: i64 = hp_int(&mut c, prefix);
        if (nidx < 0) {
            return HPACK_ERR;
        }
        var np: ptr<u8> = null;
        var nl: i64 = 0;
        if (nidx == 0) {
            sn.len = 0;
            let got: i64 = hp_str(&mut c, &mut h.tree, sn);
            if (got < 0 || sn.p == null) {
                return HPACK_ERR;
            }
            np = sn.p;
            nl = got;
        } else {
            let kv: HpKV = hp_resolve(&mut h.dyn, nidx);
            if (kv.np == null) {
                return HPACK_ERR;
            }
            np = kv.np;
            nl = kv.nl;
        }

        sv.len = 0;
        let vlen: i64 = hp_str(&mut c, &mut h.tree, sv);
        if (vlen < 0 || sv.p == null) {
            return HPACK_ERR;
        }
        var vp: ptr<u8> = sv.p;

        if (hp_out_add(&mut h.out, np, nl, vp, vlen) != HPACK_OK) {
            return HPACK_ERR;
        }
        if (incremental == 1) {
            if (hp_dyn_add(&mut h.dyn, np, nl, vp, vlen) != HPACK_OK) {
                return HPACK_ERR;
            }
        }
    }
    return HPACK_OK;
}

fn hpack_new() -> Hpack {
    var h: Hpack = zero(Hpack);
    h.dyn = hp_dyn_new();
    h.out = hp_out_new();
    if (hp_tree_init(&mut h.tree) != HPACK_OK) {
        h.tree.nodes = -1;
    }
    return h;
}

fn hpack_free(h: &mut Hpack) {
    hp_dyn_free(&mut h.dyn);
    hp_out_free(&mut h.out);
}

fn hpack_reset(h: &mut Hpack) {
    hp_dyn_reset(&mut h.dyn);
    h.dyn.max = HP_DEFAULT_MAX;
    hp_out_clear(&mut h.out);
}

fn hpack_decode(h: &mut Hpack, p: ptr<u8>, n: i64) -> i32 {
    if (h.tree.nodes <= 0 || p == null || n <= 0) {
        return HPACK_ERR;
    }
    hp_out_clear(&mut h.out);
    var sn: HxBuf = hxbuf_new(256);
    var sv: HxBuf = hxbuf_new(256);
    if (sn.p == null || sv.p == null) {
        hxbuf_free(&mut sn);
        hxbuf_free(&mut sv);
        return HPACK_ERR;
    }
    let rc: i32 = hp_block(h, p, n, &mut sn, &mut sv);
    hxbuf_free(&mut sn);
    hxbuf_free(&mut sv);
    return rc;
}

fn hpack_count(h: &mut Hpack) -> i64 {
    return h.out.n;
}

fn hpack_name(h: &mut Hpack, i: i64) -> ptr<u8> {
    return hp_out_name(&mut h.out, i);
}

fn hpack_namelen(h: &mut Hpack, i: i64) -> i64 {
    return hp_out_nlen(&mut h.out, i);
}

fn hpack_value(h: &mut Hpack, i: i64) -> ptr<u8> {
    return hp_out_value(&mut h.out, i);
}

fn hpack_vallen(h: &mut Hpack, i: i64) -> i64 {
    return hp_out_vlen(&mut h.out, i);
}

fn hpack_find(h: &mut Hpack, name: ptr<u8>, nlen: i64) -> i64 {
    return hp_out_find(&mut h.out, name, nlen);
}

fn hp_put_int(b: &mut HxBuf, v: i64, prefix: i64, tag: u8) -> i32 {
    let mask: i64 = (1 << prefix) - 1;
    if (v < 0) {
        return HPACK_ERR;
    }
    if (v < mask) {
        return hxbuf_putc(b, ((tag as i64) | v) as u8);
    }
    if (hxbuf_putc(b, ((tag as i64) | mask) as u8) != 0) {
        return HPACK_ERR;
    }
    var rest: i64 = v - mask;
    while (rest >= 128) {
        if (hxbuf_putc(b, (((rest & 127) | 128) as u8)) != 0) {
            return HPACK_ERR;
        }
        rest = rest >> 7;
    }
    return hxbuf_putc(b, rest as u8);
}

fn hp_put_str(b: &mut HxBuf, s: ptr<u8>, n: i64) -> i32 {
    if (hp_put_int(b, n, 7, 0) != HPACK_OK) {
        return HPACK_ERR;
    }
    if (n <= 0) {
        return HPACK_OK;
    }
    return hxbuf_put(b, s, n);
}

fn hpack_static_find(name: ptr<u8>, nlen: i64) -> i64 {
    var i: i64 = 0;
    while (i < HPACK_STATIC_N) {
        let sn: ptr<u8> = hpack_static_name(i);
        if (rt_len(sn) == nlen && hp_ieq(sn, name, nlen) == 1) {
            return i + 1;
        }
        i += 1;
    }
    return -1;
}

fn hpack_static_find_pair(name: ptr<u8>, nlen: i64, value: ptr<u8>, vlen: i64) -> i64 {
    var i: i64 = 0;
    while (i < HPACK_STATIC_N) {
        let sn: ptr<u8> = hpack_static_name(i);
        if (rt_len(sn) == nlen && hp_ieq(sn, name, nlen) == 1) {
            let sv: ptr<u8> = hpack_static_value(i);
            if (rt_len(sv) == vlen && rt_eqn(sv, value, vlen) == 1) {
                return i + 1;
            }
        }
        i += 1;
    }
    return -1;
}

fn hpack_put_kvn(b: &mut HxBuf, name: ptr<u8>, nlen: i64, value: ptr<u8>, vlen: i64) -> i32 {
    let both: i64 = hpack_static_find_pair(name, nlen, value, vlen);
    if (both > 0) {
        return hp_put_int(b, both, 7, 128);
    }
    let idx: i64 = hpack_static_find(name, nlen);
    if (idx > 0) {
        if (hp_put_int(b, idx, 4, 0) != HPACK_OK) {
            return HPACK_ERR;
        }
    } else {
        if (hxbuf_putc(b, 0) != 0) {
            return HPACK_ERR;
        }
        if (hp_put_str(b, name, nlen) != HPACK_OK) {
            return HPACK_ERR;
        }
    }
    return hp_put_str(b, value, vlen);
}

fn hpack_put_kv(b: &mut HxBuf, name: ptr<u8>, value: ptr<u8>) -> i32 {
    return hpack_put_kvn(b, name, rt_len(name), value, rt_len(value));
}

fn hpack_put_size_update(b: &mut HxBuf, size: i64) -> i32 {
    return hp_put_int(b, size, 5, 32);
}
