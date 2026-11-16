include "rt.rsx";
include "bignum.rsx";

const X25519_A24: i64 = 121665;
const X25519_TOP_BIT: i64 = 254;

fn x_field_p(p: &mut Bn) {
    var be: [u8; 32] = [0];
    var i: i64 = 0;
    while (i < 32) {
        be[i] = 255;
        i += 1;
    }
    be[0] = 127;
    be[31] = 237;
    var bp: ptr<u8> = null;
    unsafe { bp = &mut be[0] as ptr<u8>; }
    bn_from_be(p, bp, 32);
}

fn x_cswap(a: &mut Bn, b: &mut Bn) {
    var t: Bn = zero(Bn);
    bn_copy(&mut t, a);
    bn_copy(a, b);
    bn_copy(b, &mut t);
}

fn x_addmod(r: &mut Bn, a: &mut Bn, b: &mut Bn, p: &mut Bn) {
    var t: Bn = zero(Bn);
    bn_add(&mut t, a, b);
    bn_mod_self(&mut t, p);
    bn_copy(r, &mut t);
}

fn x_submod(r: &mut Bn, a: &mut Bn, b: &mut Bn, p: &mut Bn) {
    var t: Bn = zero(Bn);
    if (bn_cmp(a, b) >= 0) {
        bn_copy(&mut t, a);
        bn_sub_self(&mut t, b);
    } else {
        bn_add(&mut t, a, p);
        bn_sub_self(&mut t, b);
    }
    bn_copy(r, &mut t);
}

fn x_invmod(r: &mut Bn, a: &mut Bn, p: &mut Bn) {
    var e: Bn = zero(Bn);
    bn_copy(&mut e, p);
    var two: Bn = zero(Bn);
    bn_set_u64(&mut two, 2);
    bn_sub_self(&mut e, &mut two);
    bn_modexp(r, a, &mut e, p);
}

fn x25519(out: ptr<u8>, k: ptr<u8>, u: ptr<u8>) -> i32 {
    var p: Bn = zero(Bn);
    x_field_p(&mut p);

    var kb: [u8; 32] = [0];
    var ub: [u8; 32] = [0];
    var i: i64 = 0;
    while (i < 32) {
        var b0: u8 = 0;
        var b1: u8 = 0;
        unsafe {
            b0 = k[i];
            b1 = u[i];
        }
        if (i == 0) {
            b0 = (b0 & 248) as u8;
        }
        if (i == 31) {
            b0 = (b0 & 127) as u8;
            b0 = (b0 | 64) as u8;
        }
        kb[31 - i] = b0;
        ub[31 - i] = b1;
        i += 1;
    }
    ub[0] = (ub[0] & 127) as u8;

    var kp: ptr<u8> = null;
    var up: ptr<u8> = null;
    unsafe {
        kp = &mut kb[0] as ptr<u8>;
        up = &mut ub[0] as ptr<u8>;
    }

    var kk: Bn = zero(Bn);
    var x1: Bn = zero(Bn);
    bn_from_be(&mut kk, kp, 32);
    bn_from_be(&mut x1, up, 32);

    var x2: Bn = zero(Bn);
    var z2: Bn = zero(Bn);
    var x3: Bn = zero(Bn);
    var z3: Bn = zero(Bn);
    bn_set_u64(&mut x2, 1);
    bn_set_u64(&mut z2, 0);
    bn_copy(&mut x3, &mut x1);
    bn_set_u64(&mut z3, 1);

    var a: Bn = zero(Bn);
    var aa: Bn = zero(Bn);
    var b: Bn = zero(Bn);
    var bb: Bn = zero(Bn);
    var e: Bn = zero(Bn);
    var e2: Bn = zero(Bn);
    var c: Bn = zero(Bn);
    var d: Bn = zero(Bn);
    var da: Bn = zero(Bn);
    var cb: Bn = zero(Bn);
    var t1: Bn = zero(Bn);
    var t2: Bn = zero(Bn);
    var t3: Bn = zero(Bn);

    var swap: i32 = 0;
    var t: i64 = X25519_TOP_BIT;
    while (t >= 0) {
        let kt: i32 = bn_getbit(&mut kk, t);
        swap = swap ^ kt;
        if (swap == 1) {
            x_cswap(&mut x2, &mut x3);
            x_cswap(&mut z2, &mut z3);
        }
        swap = kt;

        x_addmod(&mut a, &mut x2, &mut z2, &mut p);
        bn_sqrmod(&mut aa, &mut a, &mut p);
        x_submod(&mut b, &mut x2, &mut z2, &mut p);
        bn_sqrmod(&mut bb, &mut b, &mut p);
        x_submod(&mut e, &mut aa, &mut bb, &mut p);
        x_addmod(&mut c, &mut x3, &mut z3, &mut p);
        x_submod(&mut d, &mut x3, &mut z3, &mut p);
        bn_mulmod(&mut da, &mut d, &mut a, &mut p);
        bn_mulmod(&mut cb, &mut c, &mut b, &mut p);

        x_addmod(&mut t1, &mut da, &mut cb, &mut p);
        bn_sqrmod(&mut t2, &mut t1, &mut p);
        bn_copy(&mut x3, &mut t2);

        x_submod(&mut t1, &mut da, &mut cb, &mut p);
        bn_sqrmod(&mut t2, &mut t1, &mut p);
        bn_mulmod(&mut t3, &mut x1, &mut t2, &mut p);
        bn_copy(&mut z3, &mut t3);

        bn_mulmod(&mut t1, &mut aa, &mut bb, &mut p);
        bn_copy(&mut x2, &mut t1);

        bn_copy(&mut e2, &mut e);
        bn_mul_small(&mut e2, X25519_A24);
        bn_mod_self(&mut e2, &mut p);
        x_addmod(&mut t1, &mut aa, &mut e2, &mut p);
        bn_mulmod(&mut t2, &mut e, &mut t1, &mut p);
        bn_copy(&mut z2, &mut t2);

        t -= 1;
    }

    if (swap == 1) {
        x_cswap(&mut x2, &mut x3);
        x_cswap(&mut z2, &mut z3);
    }

    var inv: Bn = zero(Bn);
    var res: Bn = zero(Bn);
    x_invmod(&mut inv, &mut z2, &mut p);
    bn_mulmod(&mut res, &mut x2, &mut inv, &mut p);

    var ob: [u8; 32] = [0];
    var op: ptr<u8> = null;
    unsafe { op = &mut ob[0] as ptr<u8>; }
    bn_to_be(&mut res, op, 32);

    i = 0;
    while (i < 32) {
        unsafe { out[i] = ob[31 - i]; }
        i += 1;
    }
    return 0;
}

fn x25519_clamp(s: ptr<u8>) {
    var b0: u8 = 0;
    var b31: u8 = 0;
    unsafe {
        b0 = s[0];
        b31 = s[31];
    }
    b0 = (b0 & 248) as u8;
    b31 = (b31 & 127) as u8;
    b31 = (b31 | 64) as u8;
    unsafe {
        s[0] = b0;
        s[31] = b31;
    }
}

fn x25519_base(out: ptr<u8>, priv_key: ptr<u8>) -> i32 {
    var base: [u8; 32] = [0];
    base[0] = 9;
    var bp: ptr<u8> = null;
    unsafe { bp = &mut base[0] as ptr<u8>; }
    return x25519(out, priv_key, bp);
}
