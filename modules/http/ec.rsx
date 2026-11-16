include "rt.rsx";
include "bignum.rsx";
include "der.rsx";

const EC_P256: i64 = 0;
const EC_P384: i64 = 1;

struct EcCurve {
    p: Bn,
    a: Bn,
    b: Bn,
    n: Bn,
    gx: Bn,
    gy: Bn,
    bytes: i64,
    bits: i64
}

struct EcPoint {
    x: Bn,
    y: Bn,
    z: Bn,
    inf: i32
}

struct EcKey {
    curve: i64,
    x: Bn,
    y: Bn
}

fn ec_bn_hex(r: &mut Bn, s: ptr<u8>, n: i64) -> i32 {
    bn_clear(r);
    var i: i64 = 0;
    while (i < n) {
        var ch: u8 = 0;
        unsafe { ch = s[i]; }
        var d: i64 = 0;
        if (ch >= 48 && ch <= 57) {
            d = (ch - 48) as i64;
        } else if (ch >= 97 && ch <= 102) {
            d = (ch - 97 + 10) as i64;
        } else if (ch >= 65 && ch <= 70) {
            d = (ch - 65 + 10) as i64;
        } else {
            return -1;
        }
        bn_shl1(r);
        bn_shl1(r);
        bn_shl1(r);
        bn_shl1(r);
        bn_add_small(r, d);
        i += 1;
    }
    return 0;
}

fn ec_addm(r: &mut Bn, a: &mut Bn, b: &mut Bn, m: &mut Bn) -> i32 {
    bn_add(r, a, b);
    return bn_mod_self(r, m);
}

fn ec_addm_s(r: &mut Bn, b: &mut Bn, m: &mut Bn) -> i32 {
    var t: Bn = zero(Bn);
    bn_copy(&mut t, r);
    bn_add(r, &mut t, b);
    return bn_mod_self(r, m);
}

fn ec_subm(r: &mut Bn, a: &mut Bn, b: &mut Bn, m: &mut Bn) -> i32 {
    var t: Bn = zero(Bn);
    bn_add(&mut t, a, m);
    bn_sub_self(&mut t, b);
    bn_mod_self(&mut t, m);
    bn_copy(r, &mut t);
    return 0;
}

fn ec_subm_s(r: &mut Bn, b: &mut Bn, m: &mut Bn) -> i32 {
    var a: Bn = zero(Bn);
    var t: Bn = zero(Bn);
    bn_copy(&mut a, r);
    bn_add(&mut t, &mut a, m);
    bn_sub_self(&mut t, b);
    bn_mod_self(&mut t, m);
    bn_copy(r, &mut t);
    return 0;
}

fn ec_dblm(r: &mut Bn, a: &mut Bn, m: &mut Bn) -> i32 {
    var t: Bn = zero(Bn);
    bn_copy(&mut t, a);
    bn_add(r, &mut t, a);
    return bn_mod_self(r, m);
}

fn ec_dblm_s(r: &mut Bn, m: &mut Bn) -> i32 {
    var t: Bn = zero(Bn);
    var u: Bn = zero(Bn);
    bn_copy(&mut t, r);
    bn_copy(&mut u, r);
    bn_add(r, &mut t, &mut u);
    return bn_mod_self(r, m);
}

fn ec_mulm(r: &mut Bn, a: &mut Bn, b: &mut Bn, m: &mut Bn) -> i32 {
    var rc: i32 = bn_mulmod(r, a, b, m);
    return rc;
}

fn ec_mulm_s(r: &mut Bn, b: &mut Bn, m: &mut Bn) -> i32 {
    var t: Bn = zero(Bn);
    bn_copy(&mut t, r);
    var rc: i32 = bn_mulmod(r, &mut t, b, m);
    return rc;
}

fn ec_sqrm(r: &mut Bn, a: &mut Bn, m: &mut Bn) -> i32 {
    var rc: i32 = bn_sqrmod(r, a, m);
    return rc;
}

fn ec_sqrm_s(r: &mut Bn, m: &mut Bn) -> i32 {
    var t: Bn = zero(Bn);
    bn_copy(&mut t, r);
    var rc: i32 = bn_sqrmod(r, &mut t, m);
    return rc;
}

fn ec_copy_bn(r: &mut Bn, a: &mut Bn) {
    bn_copy(r, a);
}

fn ec_modinv(r: &mut Bn, a: &mut Bn, m: &mut Bn) -> i32 {
    var e: Bn = zero(Bn);
    var two: Bn = zero(Bn);
    bn_copy(&mut e, m);
    bn_set_u64(&mut two, 2);
    bn_sub_self(&mut e, &mut two);
    var rc: i32 = bn_modexp(r, a, &mut e, m);
    return rc;
}

fn ec_curve_init(cv: &mut EcCurve, id: i64) -> i32 {
    var p: Bn = zero(Bn);
    var b: Bn = zero(Bn);
    var n: Bn = zero(Bn);
    var gx: Bn = zero(Bn);
    var gy: Bn = zero(Bn);
    var three: Bn = zero(Bn);
    bn_set_u64(&mut three, 3);

    if (id == EC_P256) {
        if (ec_bn_hex(&mut p, "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff", 64) != 0) { return -1; }
        if (ec_bn_hex(&mut b, "5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b", 64) != 0) { return -1; }
        if (ec_bn_hex(&mut n, "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 64) != 0) { return -1; }
        if (ec_bn_hex(&mut gx, "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296", 64) != 0) { return -1; }
        if (ec_bn_hex(&mut gy, "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5", 64) != 0) { return -1; }
        cv.bytes = 32;
        cv.bits = 256;
    } else if (id == EC_P384) {
        if (ec_bn_hex(&mut p, "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff", 96) != 0) { return -1; }
        if (ec_bn_hex(&mut b, "b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef", 96) != 0) { return -1; }
        if (ec_bn_hex(&mut n, "ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973", 96) != 0) { return -1; }
        if (ec_bn_hex(&mut gx, "aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7", 96) != 0) { return -1; }
        if (ec_bn_hex(&mut gy, "3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f", 96) != 0) { return -1; }
        cv.bytes = 48;
        cv.bits = 384;
    } else {
        return -1;
    }

    bn_copy(&mut cv.p, &mut p);
    bn_copy(&mut cv.b, &mut b);
    bn_copy(&mut cv.n, &mut n);
    bn_copy(&mut cv.gx, &mut gx);
    bn_copy(&mut cv.gy, &mut gy);
    bn_copy(&mut cv.a, &mut p);
    bn_sub_self(&mut cv.a, &mut three);
    return 0;
}

fn ec_is_on_curve(x: &mut Bn, y: &mut Bn, cv: &mut EcCurve) -> i32 {
    var lhs: Bn = zero(Bn);
    var rhs: Bn = zero(Bn);
    var t: Bn = zero(Bn);
    var ca: Bn = zero(Bn);
    var cb: Bn = zero(Bn);
    var cp: Bn = zero(Bn);
    bn_copy(&mut ca, &mut cv.a);
    bn_copy(&mut cb, &mut cv.b);
    bn_copy(&mut cp, &mut cv.p);

    if (ec_sqrm(&mut lhs, y, &mut cp) != 0) { return 0; }
    if (ec_sqrm(&mut t, x, &mut cp) != 0) { return 0; }
    if (ec_mulm(&mut rhs, &mut t, x, &mut cp) != 0) { return 0; }
    if (ec_mulm(&mut t, &mut ca, x, &mut cp) != 0) { return 0; }
    if (ec_addm_s(&mut rhs, &mut t, &mut cp) != 0) { return 0; }
    if (ec_addm_s(&mut rhs, &mut cb, &mut cp) != 0) { return 0; }
    if (bn_cmp(&mut lhs, &mut rhs) == 0) {
        return 1;
    }
    return 0;
}

fn ec_point_zero(a: &mut EcPoint) {
    bn_clear(&mut a.x);
    bn_clear(&mut a.y);
    bn_clear(&mut a.z);
    a.inf = 1;
}

fn ec_set_affine(a: &mut EcPoint, x: &mut Bn, y: &mut Bn) {
    bn_copy(&mut a.x, x);
    bn_copy(&mut a.y, y);
    bn_clear(&mut a.z);
    bn_add_small(&mut a.z, 1);
    a.inf = 0;
}

fn ec_generator(a: &mut EcPoint, cv: &mut EcCurve) {
    bn_copy(&mut a.x, &mut cv.gx);
    bn_copy(&mut a.y, &mut cv.gy);
    bn_clear(&mut a.z);
    bn_add_small(&mut a.z, 1);
    a.inf = 0;
}

fn ec_copy(r: &mut EcPoint, a: &mut EcPoint) {
    bn_copy(&mut r.x, &mut a.x);
    bn_copy(&mut r.y, &mut a.y);
    bn_copy(&mut r.z, &mut a.z);
    r.inf = a.inf;
}

fn ec_double(r: &mut EcPoint, a: &mut EcPoint, cv: &mut EcCurve) -> i32 {
    if (a.inf == 1 || bn_is_zero(&mut a.y) == 1) {
        ec_point_zero(r);
        return 0;
    }

    var ax: Bn = zero(Bn);
    var ay: Bn = zero(Bn);
    var az: Bn = zero(Bn);
    bn_copy(&mut ax, &mut a.x);
    bn_copy(&mut ay, &mut a.y);
    bn_copy(&mut az, &mut a.z);

    var delta: Bn = zero(Bn);
    var gamma: Bn = zero(Bn);
    var beta: Bn = zero(Bn);
    var alpha: Bn = zero(Bn);
    var t: Bn = zero(Bn);
    var u: Bn = zero(Bn);
    var x3: Bn = zero(Bn);
    var y3: Bn = zero(Bn);
    var z3: Bn = zero(Bn);

    if (ec_sqrm(&mut delta, &mut az, &mut cv.p) != 0) { return -1; }
    if (ec_sqrm(&mut gamma, &mut ay, &mut cv.p) != 0) { return -1; }
    if (ec_mulm(&mut beta, &mut ax, &mut gamma, &mut cv.p) != 0) { return -1; }

    if (ec_subm(&mut t, &mut ax, &mut delta, &mut cv.p) != 0) { return -1; }
    if (ec_addm(&mut u, &mut ax, &mut delta, &mut cv.p) != 0) { return -1; }
    if (ec_mulm(&mut alpha, &mut t, &mut u, &mut cv.p) != 0) { return -1; }
    if (ec_dblm(&mut t, &mut alpha, &mut cv.p) != 0) { return -1; }
    if (ec_addm_s(&mut t, &mut alpha, &mut cv.p) != 0) { return -1; }
    bn_copy(&mut alpha, &mut t);

    if (ec_sqrm(&mut x3, &mut alpha, &mut cv.p) != 0) { return -1; }
    if (ec_dblm(&mut t, &mut beta, &mut cv.p) != 0) { return -1; }
    if (ec_dblm_s(&mut t, &mut cv.p) != 0) { return -1; }
    bn_copy(&mut u, &mut t);
    if (ec_dblm_s(&mut t, &mut cv.p) != 0) { return -1; }
    if (ec_subm_s(&mut x3, &mut t, &mut cv.p) != 0) { return -1; }

    if (ec_addm(&mut z3, &mut ay, &mut az, &mut cv.p) != 0) { return -1; }
    if (ec_sqrm_s(&mut z3, &mut cv.p) != 0) { return -1; }
    if (ec_subm_s(&mut z3, &mut gamma, &mut cv.p) != 0) { return -1; }
    if (ec_subm_s(&mut z3, &mut delta, &mut cv.p) != 0) { return -1; }

    if (ec_subm(&mut t, &mut u, &mut x3, &mut cv.p) != 0) { return -1; }
    if (ec_mulm(&mut y3, &mut alpha, &mut t, &mut cv.p) != 0) { return -1; }
    if (ec_sqrm(&mut u, &mut gamma, &mut cv.p) != 0) { return -1; }
    if (ec_dblm_s(&mut u, &mut cv.p) != 0) { return -1; }
    if (ec_dblm_s(&mut u, &mut cv.p) != 0) { return -1; }
    if (ec_dblm_s(&mut u, &mut cv.p) != 0) { return -1; }
    if (ec_subm_s(&mut y3, &mut u, &mut cv.p) != 0) { return -1; }

    bn_copy(&mut r.x, &mut x3);
    bn_copy(&mut r.y, &mut y3);
    bn_copy(&mut r.z, &mut z3);
    r.inf = 0;
    return 0;
}

fn ec_double_self(a: &mut EcPoint, cv: &mut EcCurve) -> i32 {
    var t: EcPoint = zero(EcPoint);
    ec_point_zero(&mut t);
    let rc: i32 = ec_double(&mut t, a, cv);
    ec_copy(a, &mut t);
    return rc;
}

fn ec_add(r: &mut EcPoint, a: &mut EcPoint, b: &mut EcPoint, cv: &mut EcCurve) -> i32 {
    if (a.inf == 1) {
        ec_copy(r, b);
        return 0;
    }
    if (b.inf == 1) {
        ec_copy(r, a);
        return 0;
    }

    var ax: Bn = zero(Bn);
    var ay: Bn = zero(Bn);
    var az: Bn = zero(Bn);
    var bx: Bn = zero(Bn);
    var by: Bn = zero(Bn);
    var bz: Bn = zero(Bn);
    bn_copy(&mut ax, &mut a.x);
    bn_copy(&mut ay, &mut a.y);
    bn_copy(&mut az, &mut a.z);
    bn_copy(&mut bx, &mut b.x);
    bn_copy(&mut by, &mut b.y);
    bn_copy(&mut bz, &mut b.z);

    var z1z1: Bn = zero(Bn);
    var z2z2: Bn = zero(Bn);
    var u1: Bn = zero(Bn);
    var u2: Bn = zero(Bn);
    var s1: Bn = zero(Bn);
    var s2: Bn = zero(Bn);
    var h: Bn = zero(Bn);
    var rr: Bn = zero(Bn);
    var t: Bn = zero(Bn);
    var hh: Bn = zero(Bn);
    var hhh: Bn = zero(Bn);
    var v: Bn = zero(Bn);
    var x3: Bn = zero(Bn);
    var y3: Bn = zero(Bn);
    var z3: Bn = zero(Bn);

    if (ec_sqrm(&mut z1z1, &mut az, &mut cv.p) != 0) { return -1; }
    if (ec_sqrm(&mut z2z2, &mut bz, &mut cv.p) != 0) { return -1; }
    if (ec_mulm(&mut u1, &mut ax, &mut z2z2, &mut cv.p) != 0) { return -1; }
    if (ec_mulm(&mut u2, &mut bx, &mut z1z1, &mut cv.p) != 0) { return -1; }
    if (ec_mulm(&mut s1, &mut ay, &mut bz, &mut cv.p) != 0) { return -1; }
    if (ec_mulm_s(&mut s1, &mut z2z2, &mut cv.p) != 0) { return -1; }
    if (ec_mulm(&mut s2, &mut by, &mut az, &mut cv.p) != 0) { return -1; }
    if (ec_mulm_s(&mut s2, &mut z1z1, &mut cv.p) != 0) { return -1; }

    if (ec_subm(&mut h, &mut u2, &mut u1, &mut cv.p) != 0) { return -1; }
    if (ec_subm(&mut rr, &mut s2, &mut s1, &mut cv.p) != 0) { return -1; }

    if (bn_is_zero(&mut h) == 1) {
        if (bn_is_zero(&mut rr) == 1) {
            return ec_double(r, a, cv);
        }
        ec_point_zero(r);
        return 0;
    }

    if (ec_sqrm(&mut hh, &mut h, &mut cv.p) != 0) { return -1; }
    if (ec_mulm(&mut hhh, &mut h, &mut hh, &mut cv.p) != 0) { return -1; }
    if (ec_mulm(&mut v, &mut u1, &mut hh, &mut cv.p) != 0) { return -1; }

    if (ec_sqrm(&mut x3, &mut rr, &mut cv.p) != 0) { return -1; }
    if (ec_subm_s(&mut x3, &mut hhh, &mut cv.p) != 0) { return -1; }
    if (ec_dblm(&mut t, &mut v, &mut cv.p) != 0) { return -1; }
    if (ec_subm_s(&mut x3, &mut t, &mut cv.p) != 0) { return -1; }

    if (ec_subm(&mut t, &mut v, &mut x3, &mut cv.p) != 0) { return -1; }
    if (ec_mulm(&mut y3, &mut rr, &mut t, &mut cv.p) != 0) { return -1; }
    if (ec_mulm(&mut t, &mut s1, &mut hhh, &mut cv.p) != 0) { return -1; }
    if (ec_subm_s(&mut y3, &mut t, &mut cv.p) != 0) { return -1; }

    if (ec_mulm(&mut z3, &mut az, &mut bz, &mut cv.p) != 0) { return -1; }
    if (ec_mulm_s(&mut z3, &mut h, &mut cv.p) != 0) { return -1; }

    bn_copy(&mut r.x, &mut x3);
    bn_copy(&mut r.y, &mut y3);
    bn_copy(&mut r.z, &mut z3);
    r.inf = 0;
    return 0;
}

fn ec_add_self(a: &mut EcPoint, b: &mut EcPoint, cv: &mut EcCurve) -> i32 {
    var t: EcPoint = zero(EcPoint);
    ec_point_zero(&mut t);
    let rc: i32 = ec_add(&mut t, a, b, cv);
    ec_copy(a, &mut t);
    return rc;
}

fn ec_mul(r: &mut EcPoint, pt: &mut EcPoint, k: &mut Bn, cv: &mut EcCurve) -> i32 {
    ec_point_zero(r);
    var i: i64 = bn_bitlen(k) - 1;
    while (i >= 0) {
        if (ec_double_self(r, cv) != 0) {
            return -1;
        }
        if (bn_getbit(k, i) == 1) {
            if (ec_add_self(r, pt, cv) != 0) {
                return -1;
            }
        }
        i -= 1;
    }
    return 0;
}

fn ec_affine_x(out: &mut Bn, a: &mut EcPoint, cv: &mut EcCurve) -> i32 {
    if (a.inf == 1) {
        return -1;
    }
    var zi: Bn = zero(Bn);
    var zi2: Bn = zero(Bn);
    var x: Bn = zero(Bn);
    if (ec_modinv(&mut zi, &mut a.z, &mut cv.p) != 0) {
        return -1;
    }
    if (ec_sqrm(&mut zi2, &mut zi, &mut cv.p) != 0) {
        return -1;
    }
    if (ec_mulm(&mut x, &mut a.x, &mut zi2, &mut cv.p) != 0) {
        return -1;
    }
    bn_copy(out, &mut x);
    return 0;
}

fn ec_affine(outx: &mut Bn, outy: &mut Bn, a: &mut EcPoint, cv: &mut EcCurve) -> i32 {
    if (a.inf == 1) {
        return -1;
    }
    var zi: Bn = zero(Bn);
    var zi2: Bn = zero(Bn);
    var zi3: Bn = zero(Bn);
    var x: Bn = zero(Bn);
    var y: Bn = zero(Bn);
    if (ec_modinv(&mut zi, &mut a.z, &mut cv.p) != 0) {
        return -1;
    }
    if (ec_sqrm(&mut zi2, &mut zi, &mut cv.p) != 0) {
        return -1;
    }
    if (ec_mulm(&mut zi3, &mut zi2, &mut zi, &mut cv.p) != 0) {
        return -1;
    }
    if (ec_mulm(&mut x, &mut a.x, &mut zi2, &mut cv.p) != 0) {
        return -1;
    }
    if (ec_mulm(&mut y, &mut a.y, &mut zi3, &mut cv.p) != 0) {
        return -1;
    }
    bn_copy(outx, &mut x);
    bn_copy(outy, &mut y);
    return 0;
}

fn ec_oid_eq(t: &mut Tlv, hex: ptr<u8>) -> i32 {
    var b: [u8; 16] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut b[0] as ptr<u8>; }
    let n: i64 = rt_parse_hex(hex, bp, 16);
    if (n != t.len) {
        return 0;
    }
    return rt_bytes_eq(t.p, bp, n);
}

fn ec_load(k: &mut EcKey, spki: ptr<u8>, len: i64) -> i32 {
    k.curve = -1;
    bn_clear(&mut k.x);
    bn_clear(&mut k.y);

    var d: Der = zero(Der);
    der_init(&mut d, spki, len);
    var seq: Tlv = zero(Tlv);
    if (der_expect(&mut d, DER_TAG_SEQUENCE, &mut seq) != 0) {
        return -1;
    }
    var sd: Der = zero(Der);
    der_sub(&mut seq, &mut sd);

    var alg: Tlv = zero(Tlv);
    if (der_expect(&mut sd, DER_TAG_SEQUENCE, &mut alg) != 0) {
        return -1;
    }
    var ad: Der = zero(Der);
    der_sub(&mut alg, &mut ad);
    var oid: Tlv = zero(Tlv);
    if (der_expect(&mut ad, DER_TAG_OID, &mut oid) != 0) {
        return -1;
    }
    if (ec_oid_eq(&mut oid, "2a8648ce3d0201") != 1) {
        return -1;
    }
    var curve: Tlv = zero(Tlv);
    if (der_expect(&mut ad, DER_TAG_OID, &mut curve) != 0) {
        return -1;
    }
    if (ec_oid_eq(&mut curve, "2a8648ce3d030107") == 1) {
        k.curve = EC_P256;
    } else if (ec_oid_eq(&mut curve, "2b81040022") == 1) {
        k.curve = EC_P384;
    } else {
        return -1;
    }

    var bs: Tlv = zero(Tlv);
    if (der_expect(&mut sd, DER_TAG_BITSTRING, &mut bs) != 0) {
        return -1;
    }
    if (bs.len < 2) {
        return -1;
    }
    var unused: u8 = 0;
    var form: u8 = 0;
    unsafe {
        unused = bs.p[0];
        form = bs.p[1];
    }
    if (unused != 0 || form != 4) {
        return -1;
    }

    var cv: EcCurve = zero(EcCurve);
    if (ec_curve_init(&mut cv, k.curve) != 0) {
        return -1;
    }
    let need: i64 = 1 + 2 * cv.bytes;
    if (bs.len != need + 1) {
        return -1;
    }
    bn_from_be(&mut k.x, rt_add(bs.p, 2), cv.bytes);
    bn_from_be(&mut k.y, rt_add(bs.p, 2 + cv.bytes), cv.bytes);
    if (bn_cmp(&mut k.x, &mut cv.p) >= 0) {
        return -1;
    }
    if (bn_cmp(&mut k.y, &mut cv.p) >= 0) {
        return -1;
    }

    var kx: Bn = zero(Bn);
    var ky: Bn = zero(Bn);
    bn_copy(&mut kx, &mut k.x);
    bn_copy(&mut ky, &mut k.y);
    if (ec_is_on_curve(&mut kx, &mut ky, &mut cv) != 1) {
        return -1;
    }
    return 0;
}

fn ecdsa_verify(k: &mut EcKey, hash: ptr<u8>, hlen: i64, sig: ptr<u8>, siglen: i64) -> i32 {
    var cv: EcCurve = zero(EcCurve);
    if (ec_curve_init(&mut cv, k.curve) != 0) {
        return 0;
    }

    var d: Der = zero(Der);
    der_init(&mut d, sig, siglen);
    var seq: Tlv = zero(Tlv);
    if (der_expect(&mut d, DER_TAG_SEQUENCE, &mut seq) != 0) {
        return 0;
    }
    if (seq.hdr + seq.len != siglen) {
        return 0;
    }
    var sd: Der = zero(Der);
    der_sub(&mut seq, &mut sd);
    var rt: Tlv = zero(Tlv);
    var st: Tlv = zero(Tlv);
    if (der_expect(&mut sd, DER_TAG_INTEGER, &mut rt) != 0) {
        return 0;
    }
    if (der_expect(&mut sd, DER_TAG_INTEGER, &mut st) != 0) {
        return 0;
    }
    if (rt.len <= 0 || rt.len > cv.bytes + 8 || st.len <= 0 || st.len > cv.bytes + 8) {
        return 0;
    }

    var r: Bn = zero(Bn);
    var s: Bn = zero(Bn);
    bn_from_be(&mut r, rt.p, rt.len);
    bn_from_be(&mut s, st.p, st.len);
    if (bn_is_zero(&mut r) == 1 || bn_is_zero(&mut s) == 1) {
        return 0;
    }
    if (bn_cmp(&mut r, &mut cv.n) >= 0) {
        return 0;
    }
    if (bn_cmp(&mut s, &mut cv.n) >= 0) {
        return 0;
    }

    var take: i64 = hlen;
    if (take > cv.bytes) {
        take = cv.bytes;
    }
    var e: Bn = zero(Bn);
    bn_from_be(&mut e, hash, take);

    var w: Bn = zero(Bn);
    if (ec_modinv(&mut w, &mut s, &mut cv.n) != 0) {
        return 0;
    }
    var u1: Bn = zero(Bn);
    var u2: Bn = zero(Bn);
    if (ec_mulm(&mut u1, &mut e, &mut w, &mut cv.n) != 0) {
        return 0;
    }
    if (ec_mulm(&mut u2, &mut r, &mut w, &mut cv.n) != 0) {
        return 0;
    }

    var g: EcPoint = zero(EcPoint);
    var q: EcPoint = zero(EcPoint);
    var p1: EcPoint = zero(EcPoint);
    var p2: EcPoint = zero(EcPoint);
    var sum: EcPoint = zero(EcPoint);
    ec_generator(&mut g, &mut cv);
    var qx: Bn = zero(Bn);
    var qy: Bn = zero(Bn);
    bn_copy(&mut qx, &mut k.x);
    bn_copy(&mut qy, &mut k.y);
    ec_set_affine(&mut q, &mut qx, &mut qy);
    ec_point_zero(&mut p1);
    ec_point_zero(&mut p2);
    ec_point_zero(&mut sum);

    if (ec_mul(&mut p1, &mut g, &mut u1, &mut cv) != 0) {
        return 0;
    }
    if (ec_mul(&mut p2, &mut q, &mut u2, &mut cv) != 0) {
        return 0;
    }
    if (ec_add(&mut sum, &mut p1, &mut p2, &mut cv) != 0) {
        return 0;
    }
    if (sum.inf == 1) {
        return 0;
    }

    var x: Bn = zero(Bn);
    if (ec_affine_x(&mut x, &mut sum, &mut cv) != 0) {
        return 0;
    }
    if (bn_cmp(&mut x, &mut cv.n) >= 0) {
        if (bn_mod_self(&mut x, &mut cv.n) != 0) {
            return 0;
        }
    }
    if (bn_cmp(&mut x, &mut r) == 0) {
        return 1;
    }
    return 0;
}
