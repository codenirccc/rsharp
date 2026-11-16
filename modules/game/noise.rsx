fn g_hash2(xi: i64, yi: i64) -> u64 {
    var h: u64 = (xi as u64) * 6364136223846793005 + (yi as u64) * 1442695040888963407;
    h = h ^ (h >> 33);
    h = h * 2147483647;
    h = h ^ (h >> 29);
    return h;
}

fn g_hash01(xi: i64, yi: i64) -> f64 {
    return (g_hash2(xi, yi) >> 11) as f64 / 9007199254740992.0;
}

fn g_floor(x: f64) -> i64 {
    let t: i64 = x as i64;
    if ((t as f64) == x) {
        return t;
    }
    if (x < 0.0) {
        return t - 1;
    }
    return t;
}

fn noise2(x: f64, y: f64) -> f64 {
    let xi: i64 = g_floor(x);
    let yi: i64 = g_floor(y);
    let xf: f64 = x - xi as f64;
    let yf: f64 = y - yi as f64;
    let u: f64 = xf * xf * (3.0 - 2.0 * xf);
    let v: f64 = yf * yf * (3.0 - 2.0 * yf);
    let a: f64 = g_hash01(xi, yi);
    let b: f64 = g_hash01(xi + 1, yi);
    let c: f64 = g_hash01(xi, yi + 1);
    let d: f64 = g_hash01(xi + 1, yi + 1);
    let ab: f64 = a + (b - a) * u;
    let cd: f64 = c + (d - c) * u;
    return ab + (cd - ab) * v;
}

fn fbm2(x: f64, y: f64) -> f64 {
    var total: f64 = 0.0;
    var amp: f64 = 0.5;
    var freq: f64 = 1.0;
    var i: i64 = 0;
    while (i < 4) {
        total = total + amp * noise2(x * freq, y * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
        i += 1;
    }
    return total;
}
