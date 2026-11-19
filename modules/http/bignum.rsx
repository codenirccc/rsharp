const BN_MAX: i64 = 160;
const BN_MASK: i64 = 67108863;

struct Bn {
    n: i64,
    d: [i64; 160]
}

fn bn_clear(b: &mut Bn) {
    var i: i64 = 0;
    while (i < BN_MAX) {
        b.d[i] = 0;
        i += 1;
    }
    b.n = 0;
}

fn bn_copy(r: &mut Bn, a: &mut Bn) {
    var i: i64 = 0;
    while (i < a.n) {
        r.d[i] = a.d[i];
        i += 1;
    }
    while (i < BN_MAX) {
        r.d[i] = 0;
        i += 1;
    }
    r.n = a.n;
}

fn bn_trim(b: &mut Bn) {
    var n: i64 = b.n;
    while (n > 0 && b.d[n - 1] == 0) {
        n -= 1;
    }
    b.n = n;
}

fn bn_set_u64(b: &mut Bn, v: u64) {
    bn_clear(b);
    b.d[0] = (v & 67108863) as i64;
    b.d[1] = ((v >> 26) & 67108863) as i64;
    b.d[2] = ((v >> 52) & 67108863) as i64;
    b.n = 3;
    bn_trim(b);
}

fn bn_is_zero(a: &mut Bn) -> i32 {
    var i: i64 = 0;
    while (i < a.n) {
        if (a.d[i] != 0) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn bn_bitlen(a: &mut Bn) -> i64 {
    if (a.n == 0) {
        return 0;
    }
    let top: i64 = a.d[a.n - 1];
    var bits: i64 = 0;
    var v: i64 = top;
    while (v > 0) {
        bits += 1;
        v = v >> 1;
    }
    return (a.n - 1) * 26 + bits;
}

fn bn_getbit(a: &mut Bn, i: i64) -> i32 {
    if (i < 0) {
        return 0;
    }
    let limb: i64 = i / 26;
    if (limb >= a.n) {
        return 0;
    }
    let off: i64 = i - limb * 26;
    return ((a.d[limb] >> off) & 1) as i32;
}

fn bn_setbit(b: &mut Bn, i: i64, v: i32) {
    let limb: i64 = i / 26;
    if (limb < 0 || limb >= BN_MAX) {
        return;
    }
    let off: i64 = i - limb * 26;
    if (v == 1) {
        b.d[limb] = b.d[limb] | (1 << off);
        if (limb + 1 > b.n) {
            b.n = limb + 1;
        }
    } else {
        b.d[limb] = b.d[limb] & ~(1 << off);
        bn_trim(b);
    }
}

fn bn_cmp(a: &mut Bn, b: &mut Bn) -> i32 {
    if (a.n != b.n) {
        if (a.n > b.n) {
            return 1;
        }
        return -1;
    }
    var i: i64 = a.n - 1;
    while (i >= 0) {
        if (a.d[i] != b.d[i]) {
            if (a.d[i] > b.d[i]) {
                return 1;
            }
            return -1;
        }
        i -= 1;
    }
    return 0;
}

fn bn_add(r: &mut Bn, a: &mut Bn, b: &mut Bn) {
    var n: i64 = a.n;
    if (b.n > n) {
        n = b.n;
    }
    var carry: i64 = 0;
    var i: i64 = 0;
    while (i < n) {
        var av: i64 = 0;
        var bv: i64 = 0;
        if (i < a.n) {
            av = a.d[i];
        }
        if (i < b.n) {
            bv = b.d[i];
        }
        let s: i64 = av + bv + carry;
        r.d[i] = s & BN_MASK;
        carry = s >> 26;
        i += 1;
    }
    if (carry != 0 && n < BN_MAX) {
        r.d[n] = carry;
        n += 1;
        i += 1;
    }
    while (i < BN_MAX) {
        r.d[i] = 0;
        i += 1;
    }
    r.n = n;
    bn_trim(r);
}

fn bn_sub_self(a: &mut Bn, b: &mut Bn) {
    var borrow: i64 = 0;
    var i: i64 = 0;
    while (i < a.n) {
        var bv: i64 = 0;
        if (i < b.n) {
            bv = b.d[i];
        }
        var s: i64 = a.d[i] - bv - borrow;
        if (s < 0) {
            s += 67108864;
            borrow = 1;
        } else {
            borrow = 0;
        }
        a.d[i] = s;
        i += 1;
    }
    bn_trim(a);
}

fn bn_shl1(b: &mut Bn) {
    var carry: i64 = 0;
    var i: i64 = 0;
    while (i < b.n) {
        let v: i64 = b.d[i];
        b.d[i] = ((v << 1) | carry) & BN_MASK;
        carry = (v >> 25) & 1;
        i += 1;
    }
    if (carry != 0 && b.n < BN_MAX) {
        b.d[b.n] = carry;
        b.n += 1;
    }
}

fn bn_add_small(b: &mut Bn, v: i64) {
    var carry: i64 = v;
    var i: i64 = 0;
    while (carry != 0 && i < BN_MAX) {
        if (i >= b.n) {
            b.n = i + 1;
        }
        let s: i64 = b.d[i] + carry;
        b.d[i] = s & BN_MASK;
        carry = s >> 26;
        i += 1;
    }
}

fn bn_mul_small(b: &mut Bn, v: i64) {
    var carry: i64 = 0;
    var i: i64 = 0;
    while (i < b.n) {
        let p: i64 = b.d[i] * v + carry;
        b.d[i] = p & BN_MASK;
        carry = p >> 26;
        i += 1;
    }
    while (carry != 0 && i < BN_MAX) {
        b.d[i] = carry & BN_MASK;
        carry = carry >> 26;
        if (b.n < i + 1) {
            b.n = i + 1;
        }
        i += 1;
    }
}

fn bn_from_be(r: &mut Bn, p: ptr<u8>, len: i64) {
    bn_clear(r);
    var i: i64 = 0;
    while (i < len) {
        var b: u8 = 0;
        unsafe { b = p[i]; }
        bn_mul_small(r, 256);
        bn_add_small(r, b as i64);
        i += 1;
    }
    bn_trim(r);
}

fn bn_to_be(a: &mut Bn, p: ptr<u8>, len: i64) {
    var i: i64 = 0;
    while (i < len) {
        var v: i64 = 0;
        var j: i64 = 0;
        let base: i64 = (len - 1 - i) * 8;
        while (j < 8) {
            v = (v << 1) | (bn_getbit(a, base + 7 - j) as i64);
            j += 1;
        }
        unsafe { p[i] = v as u8; }
        i += 1;
    }
}

fn bn_mul(r: &mut Bn, a: &mut Bn, b: &mut Bn) {
    var acc: [i64; 160] = [0];
    var i: i64 = 0;
    while (i < a.n) {
        let ai: i64 = a.d[i];
        if (ai != 0) {
            var j: i64 = 0;
            while (j < b.n && i + j < BN_MAX) {
                acc[i + j] = acc[i + j] + ai * b.d[j];
                j += 1;
            }
        }
        i += 1;
    }

    var carry: i64 = 0;
    var k: i64 = 0;
    while (k < BN_MAX) {
        let v: i64 = acc[k] + carry;
        r.d[k] = v & BN_MASK;
        carry = v >> 26;
        k += 1;
    }
    var used: i64 = a.n + b.n;
    if (used > BN_MAX) {
        used = BN_MAX;
    }
    r.n = used;
    bn_trim(r);
}

fn bn_mod(r: &mut Bn, a: &mut Bn, m: &mut Bn) -> i32 {
    if (bn_is_zero(m) == 1) {
        return -1;
    }
    var rem: Bn = zero(Bn);
    var i: i64 = bn_bitlen(a) - 1;
    while (i >= 0) {
        bn_shl1(&mut rem);
        if (bn_getbit(a, i) == 1) {
            bn_add_small(&mut rem, 1);
        }
        if (bn_cmp(&mut rem, m) >= 0) {
            bn_sub_self(&mut rem, m);
        }
        i -= 1;
    }
    bn_copy(r, &mut rem);
    return 0;
}

fn bn_mod_self(a: &mut Bn, m: &mut Bn) -> i32 {
    if (bn_is_zero(m) == 1) {
        return -1;
    }
    var rem: Bn = zero(Bn);
    var i: i64 = bn_bitlen(a) - 1;
    while (i >= 0) {
        bn_shl1(&mut rem);
        if (bn_getbit(a, i) == 1) {
            bn_add_small(&mut rem, 1);
        }
        if (bn_cmp(&mut rem, m) >= 0) {
            bn_sub_self(&mut rem, m);
        }
        i -= 1;
    }
    bn_copy(a, &mut rem);
    return 0;
}

fn bn_mulmod(r: &mut Bn, a: &mut Bn, b: &mut Bn, m: &mut Bn) -> i32 {
    var p: Bn = zero(Bn);
    bn_mul(&mut p, a, b);
    let rc: i32 = bn_mod(r, &mut p, m);
    return rc;
}

fn bn_sqr(r: &mut Bn, a: &mut Bn) {
    var acc: [i64; 160] = [0];
    var i: i64 = 0;
    while (i < a.n) {
        let ai: i64 = a.d[i];
        if (ai != 0) {
            var j: i64 = i;
            while (j < a.n && i + j < BN_MAX) {
                var w: i64 = ai * a.d[j];
                if (j != i) {
                    w = w * 2;
                }
                acc[i + j] = acc[i + j] + w;
                j += 1;
            }
        }
        i += 1;
    }

    var carry: i64 = 0;
    var k: i64 = 0;
    while (k < BN_MAX) {
        let v: i64 = acc[k] + carry;
        r.d[k] = v & BN_MASK;
        carry = v >> 26;
        k += 1;
    }
    var used: i64 = a.n * 2;
    if (used > BN_MAX) {
        used = BN_MAX;
    }
    r.n = used;
    bn_trim(r);
}

fn bn_sqrmod(r: &mut Bn, a: &mut Bn, m: &mut Bn) -> i32 {
    var p: Bn = zero(Bn);
    bn_sqr(&mut p, a);
    let rc: i32 = bn_mod(r, &mut p, m);
    return rc;
}

fn bn_modexp(r: &mut Bn, base: &mut Bn, exp: &mut Bn, m: &mut Bn) -> i32 {
    if (bn_is_zero(m) == 1) {
        return -1;
    }

    var b: Bn = zero(Bn);
    if (bn_mod(&mut b, base, m) != 0) {
        return -1;
    }

    var acc: Bn = zero(Bn);
    var one: Bn = zero(Bn);
    bn_set_u64(&mut one, 1);
    if (bn_mod(&mut acc, &mut one, m) != 0) {
        return -1;
    }

    var t: Bn = zero(Bn);
    var i: i64 = bn_bitlen(exp) - 1;
    while (i >= 0) {
        if (bn_sqrmod(&mut t, &mut acc, m) != 0) {
            return -1;
        }
        bn_copy(&mut acc, &mut t);
        if (bn_getbit(exp, i) == 1) {
            if (bn_mulmod(&mut t, &mut acc, &mut b, m) != 0) {
                return -1;
            }
            bn_copy(&mut acc, &mut t);
        }
        i -= 1;
    }
    bn_copy(r, &mut acc);
    return 0;
}
