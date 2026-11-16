const PI: f64 = 3.141592653589793;
const FRAC_PI_2: f64 = 1.5707963267948966;

fn fabs(x: f64) -> f64 {
    if (x < 0.0) {
        return 0.0 - x;
    }
    return x;
}

fn fmin(a: f64, b: f64) -> f64 {
    if (a < b) {
        return a;
    }
    return b;
}

fn fmax(a: f64, b: f64) -> f64 {
    if (a > b) {
        return a;
    }
    return b;
}

fn fsqrt(x: f64) -> f64 {
    if (x < 0.0) {
        return -1.0;
    }
    if (x == 0.0) {
        return 0.0;
    }
    var g: f64 = 0.0;
    if (x >= 1.0) {
        g = x * 0.5;
    } else {
        g = 1.0;
    }
    var i: i64 = 0;
    while (i < 40) {
        g = 0.5 * (g + x / g);
        i += 1;
    }
    return g;
}

fn sin_series(r: f64) -> f64 {
    var sum: f64 = 0.0;
    var term: f64 = r;
    var sign: f64 = 1.0;
    var i: i64 = 1;
    while (i <= 15) {
        sum = sum + sign * term;
        term = term * r * r / ((i + 1) as f64 * (i + 2) as f64);
        sign = 0.0 - sign;
        i += 2;
    }
    return sum;
}

fn cos_series(r: f64) -> f64 {
    var sum: f64 = 0.0;
    var term: f64 = 1.0;
    var sign: f64 = 1.0;
    var i: i64 = 0;
    while (i <= 14) {
        sum = sum + sign * term;
        term = term * r * r / ((i + 1) as f64 * (i + 2) as f64);
        sign = 0.0 - sign;
        i += 2;
    }
    return sum;
}

fn reduce_pio2(x: f64) -> (i64, f64) {
    var k: i64 = (x / FRAC_PI_2) as i64;
    if (x < 0.0) {
        let v: f64 = x / FRAC_PI_2;
        if (v != (k as f64)) {
            k -= 1;
        }
    }
    var q: i64 = k % 4;
    if (q < 0) {
        q += 4;
    }
    return (q, x - (k as f64) * FRAC_PI_2);
}

fn fsin(x: f64) -> f64 {
    let t: (i64, f64) = reduce_pio2(x);
    let q: i64 = t.0;
    let r: f64 = t.1;
    let sr: f64 = sin_series(r);
    let cr: f64 = cos_series(r);
    if (q == 0) {
        return sr;
    }
    if (q == 1) {
        return cr;
    }
    if (q == 2) {
        return 0.0 - sr;
    }
    return 0.0 - cr;
}

fn fcos(x: f64) -> f64 {
    let t: (i64, f64) = reduce_pio2(x);
    let q: i64 = t.0;
    let r: f64 = t.1;
    let sr: f64 = sin_series(r);
    let cr: f64 = cos_series(r);
    if (q == 0) {
        return cr;
    }
    if (q == 1) {
        return 0.0 - sr;
    }
    if (q == 2) {
        return 0.0 - cr;
    }
    return sr;
}

fn ftan(x: f64) -> f64 {
    return fsin(x) / fcos(x);
}

fn ftrunc(x: f64) -> f64 {
    let t: i64 = x as i64;
    return t as f64;
}

fn ffloor(x: f64) -> f64 {
    let t: i64 = x as i64;
    if ((t as f64) == x) {
        return t as f64;
    }
    if (x < 0.0) {
        return (t - 1) as f64;
    }
    return t as f64;
}

fn fceil(x: f64) -> f64 {
    let t: i64 = x as i64;
    if ((t as f64) == x) {
        return t as f64;
    }
    if (x > 0.0) {
        return (t + 1) as f64;
    }
    return t as f64;
}

fn fround(x: f64) -> f64 {
    if (x >= 0.0) {
        return ffloor(x + 0.5);
    }
    return fceil(x - 0.5);
}

fn fmod(x: f64, y: f64) -> f64 {
    if (y == 0.0) {
        return 0.0;
    }
    return x - ftrunc(x / y) * y;
}

fn fpow_i(x: f64, n: i64) -> f64 {
    if (n == 0) {
        return 1.0;
    }
    if (n < 0) {
        return 1.0 / fpow_i(x, 0 - n);
    }
    var base: f64 = x;
    var e: i64 = n;
    var result: f64 = 1.0;
    while (e > 0) {
        if ((e & 1) == 1) {
            result = result * base;
        }
        base = base * base;
        e = e >> 1;
    }
    return result;
}

fn isqrt(n: i64) -> i64 {
    if (n < 0) {
        return -1;
    }
    if (n < 2) {
        return n;
    }
    var g: i64 = n >> 1;
    while (true) {
        let gn: i64 = (g + n / g) >> 1;
        if (gn >= g) {
            return g;
        }
        g = gn;
    }
}

fn ipow(b: i64, exp: i64) -> i64 {
    if (exp == 0) {
        return 1;
    }
    var base: i64 = b;
    var e: i64 = exp;
    var r: i64 = 1;
    while (e > 0) {
        if ((e & 1) == 1) {
            r = r * base;
        }
        base = base * base;
        e = e >> 1;
    }
    return r;
}
