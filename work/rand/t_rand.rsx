include "../../modules/rand.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn t_eq_u64(got: u64, want: u64, code: i64) -> i64 {
    if (got == want) {
        return 0;
    }
    printf("t_rand: fail %lld got %llu want %llu\n", code, got, want);
    return code;
}

fn t_eq_i64(got: i64, want: i64, code: i64) -> i64 {
    if (got == want) {
        return 0;
    }
    printf("t_rand: fail %lld got %lld want %lld\n", code, got, want);
    return code;
}

fn t_close(got: f64, want: f64, code: i64) -> i64 {
    var d: f64 = got - want;
    if (d < 0.0) {
        d = 0.0 - d;
    }
    if (d > 0.000000001) {
        printf("t_rand: fail %lld got %.9f want %.9f\n", code, got, want);
        return code;
    }
    return 0;
}

fn main() -> i32 {
    var fails: i64 = 0;

    var r: Rng = zero(Rng);
    rand_seed(&mut r, 42);
    var want_below: [u64; 10] = [776, 859, 651, 236, 537, 3, 124, 801, 378, 18];
    var i: i64 = 0;
    while (i < 10) {
        fails += t_eq_u64(rand_below(&mut r, 1000), want_below[i], i + 1);
        i += 1;
    }

    rand_seed(&mut r, 42);
    var want_frac: [f64; 5] = [0.669350739, 0.319006167, 0.740534542, 0.547286416, 0.735351221];
    i = 0;
    while (i < 5) {
        fails += t_close(rand_frac(&mut r), want_frac[i], i + 11);
        i += 1;
    }

    rand_seed(&mut r, 42);
    var xs: [i64; 10] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    unsafe {
        let p: ptr<i64> = &xs[0] as ptr<i64>;
        rand_shuffle(&mut r, p, 10);
    }
    var want_shuffle: [i64; 10] = [5, 4, 9, 0, 7, 8, 2, 3, 1, 6];
    i = 0;
    while (i < 10) {
        fails += t_eq_i64(xs[i], want_shuffle[i], i + 21);
        i += 1;
    }

    var sum: i64 = 0;
    var sq: i64 = 0;
    i = 0;
    while (i < 10) {
        sum += xs[i];
        sq += xs[i] * xs[i];
        i += 1;
    }
    fails += t_eq_i64(sum, 45, 31);
    fails += t_eq_i64(sq, 285, 32);

    rand_seed(&mut r, 42);
    var a: Rng = zero(Rng);
    var b: Rng = zero(Rng);
    rand_seed(&mut a, 7);
    rand_seed(&mut b, 7);
    i = 0;
    while (i < 16) {
        if (rand_next(&mut a) != rand_next(&mut b)) {
            fails += 33;
            break;
        }
        i += 1;
    }

    rand_seed(&mut a, 1);
    rand_seed(&mut b, 42);
    var same: i64 = 0;
    i = 0;
    while (i < 8) {
        if (rand_next(&mut a) == rand_next(&mut b)) {
            same += 1;
        }
        i += 1;
    }
    if (same == 8) {
        fails += 34;
    }

    rand_seed(&mut r, 7);
    i = 0;
    var in_range: i64 = 0;
    while (i < 100) {
        let v: i64 = rand_range(&mut r, 3, 13);
        if (v >= 3 && v < 13) {
            in_range += 1;
        }
        i += 1;
    }
    if (in_range != 100) {
        fails += 35;
    }

    rand_seed(&mut r, 42);
    if (rand_below(&mut r, 0) != 0) {
        fails += 36;
    }

    if (fails == 0) {
        printf("rand suite: ok\n");
        return 0;
    }
    printf("rand suite: FAIL %lld\n", fails);
    return 1;
}
