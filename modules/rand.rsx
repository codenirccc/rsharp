struct Rng {
    s0: u64,
    s1: u64,
    s2: u64,
    s3: u64
}

fn rotl64(x: u64, k: u64) -> u64 {
    return (x << k) | (x >> (64 - k));
}

fn rand_seed(r: &mut Rng, seed: u64) {
    var z: u64 = seed;
    z = z * 6364136223846793005 + 1442695040888963407;
    if (z == 0) {
        z = 1;
    }
    r.s0 = z;
    z = z * 6364136223846793005 + 1442695040888963407;
    if (z == 0) {
        z = 1;
    }
    r.s1 = z;
    z = z * 6364136223846793005 + 1442695040888963407;
    if (z == 0) {
        z = 1;
    }
    r.s2 = z;
    z = z * 6364136223846793005 + 1442695040888963407;
    if (z == 0) {
        z = 1;
    }
    r.s3 = z;
}

fn rand_next(r: &mut Rng) -> u64 {
    let result: u64 = rotl64(r.s1 * 5, 7) * 9;
    let t: u64 = r.s1 << 17;
    r.s2 = r.s2 ^ r.s0;
    r.s3 = r.s3 ^ r.s1;
    r.s1 = r.s1 ^ r.s2;
    r.s0 = r.s0 ^ r.s3;
    r.s2 = r.s2 ^ t;
    r.s3 = rotl64(r.s3, 45);
    return result;
}

fn rand_below(r: &mut Rng, n: u64) -> u64 {
    if (n == 0) {
        return 0;
    }
    let t: u64 = (0 - n) % n;
    while (true) {
        let x: u64 = rand_next(r);
        if (x >= t) {
            return x % n;
        }
    }
}

fn rand_range(r: &mut Rng, lo: i64, hi: i64) -> i64 {
    if (hi <= lo) {
        return lo;
    }
    return lo + rand_below(r, (hi - lo) as u64) as i64;
}

fn rand_frac(r: &mut Rng) -> f64 {
    return (rand_next(r) >> 11) as f64 / 9007199254740992.0;
}

fn rand_shuffle(r: &mut Rng, xs: ptr<i64>, n: i64) {
    var i: i64 = n - 1;
    while (i > 0) {
        let j: i64 = rand_below(r, (i as u64) + 1) as i64;
        unsafe {
            let tmp: i64 = xs[i];
            xs[i] = xs[j];
            xs[j] = tmp;
        }
        i -= 1;
    }
}
