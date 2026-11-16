include "../../modules/game/game.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn close(a: f64, b: f64, tol: f64) -> i64 {
    var d: f64 = a - b;
    if (d < 0.0) {
        d = 0.0 - d;
    }
    if (d <= tol) {
        return 1;
    }
    return 0;
}

fn expect_close(name: ptr<u8>, got: f64, want: f64, tol: f64) -> i64 {
    if (close(got, want, tol) != 1) {
        printf("t_game: fail %s got %.15f want %.15f\n", name, got, want);
        return 1;
    }
    return 0;
}

fn expect_u64(name: ptr<u8>, got: u64, want: u64) -> i64 {
    if (got != want) {
        printf("t_game: fail %s got %llu want %llu\n", name, got, want);
        return 1;
    }
    return 0;
}

fn main() -> i32 {
    var fails: i64 = 0;

    fails += expect_close("v2_len" as ptr<u8>, v2_len(3.0, 4.0), 5.0, 0.0);
    fails += expect_close("v2_dot" as ptr<u8>, v2_dot(1.0, 2.0, 3.0, 4.0), 11.0, 0.0);
    fails += expect_close("v2_cross" as ptr<u8>, v2_cross(1.0, 2.0, 3.0, 4.0), -2.0, 0.0);
    fails += expect_close("v3_len" as ptr<u8>, v3_len(2.0, 3.0, 6.0), 7.0, 0.0);
    let nx: f64 = v2_norm_x(3.0, 4.0);
    let ny: f64 = v2_norm_y(3.0, 4.0);
    fails += expect_close("normx" as ptr<u8>, nx, 0.6, 0.0000000000001);
    fails += expect_close("normy" as ptr<u8>, ny, 0.8, 0.0000000000001);

    fails += expect_close("noise_a" as ptr<u8>, noise2(0.5, 0.5), 0.39189859643870584, 0.000000000001);
    fails += expect_close("noise_b" as ptr<u8>, noise2(3.25, 7.5), 0.5969948693072467, 0.000000000001);
    fails += expect_close("noise_c" as ptr<u8>, noise2(-2.75, 4.5), 0.38769469236329757, 0.000000000001);
    fails += expect_close("noise_d" as ptr<u8>, noise2(10.0, 10.0), 0.1318545655336758, 0.000000000001);
    fails += expect_close("noise_e" as ptr<u8>, noise2(1.0, 1.0), 0.8069446196302229, 0.000000000001);
    fails += expect_close("fbm_a" as ptr<u8>, fbm2(0.5, 0.5), 0.5355327623817713, 0.000000000001);
    fails += expect_close("fbm_b" as ptr<u8>, fbm2(3.25, 7.5), 0.5828851148288453, 0.000000000001);

    fails += expect_close("quad_in" as ptr<u8>, ease_quad_in(0.25), 0.0625, 0.0);
    fails += expect_close("quad_out" as ptr<u8>, ease_quad_out(0.25), 0.4375, 0.0);
    fails += expect_close("quad_inout" as ptr<u8>, ease_quad_inout(0.75), 0.875, 0.0);
    fails += expect_close("cubic_in" as ptr<u8>, ease_cubic_in(0.25), 0.015625, 0.0);
    fails += expect_close("cubic_out" as ptr<u8>, ease_cubic_out(0.25), 0.578125, 0.0);
    fails += expect_close("cubic_inout" as ptr<u8>, ease_cubic_inout(0.75), 0.9375, 0.0);
    fails += expect_close("sine_in" as ptr<u8>, ease_sine_in(0.5), 0.2928932188134524, 0.0000000000001);
    fails += expect_close("sine_out" as ptr<u8>, ease_sine_out(0.5), 0.7071067811865476, 0.0000000000001);
    fails += expect_close("sine_inout" as ptr<u8>, ease_sine_inout(0.5), 0.49999999999999994, 0.0000000000001);
    fails += expect_close("lerp" as ptr<u8>, lerp_f64(10.0, 20.0, 0.3), 13.0, 0.0);
    fails += expect_close("smoothstep" as ptr<u8>, smoothstep_f64(0.5), 0.5, 0.0);

    fails += expect_u64("stream_seed_1" as ptr<u8>, stream_seed(42, 1), 3492396993031377468);
    fails += expect_u64("stream_seed_2" as ptr<u8>, stream_seed(42, 2), 5632471392670149845);

    var s1: Rng = stream(42, 1);
    var s2: Rng = stream(42, 2);
    var s3: Rng = stream(42, 1);
    var i: i64 = 0;
    var same: i64 = 0;
    while (i < 8) {
        if (rand_next(&mut s1) != rand_next(&mut s3)) {
            same += 1;
        }
        i += 1;
    }
    if (same != 0) {
        printf("t_game: fail stream determinism\n");
        fails += 1;
    }
    var diff: i64 = 0;
    i = 0;
    while (i < 8) {
        if (rand_next(&mut s1) == rand_next(&mut s2)) {
            diff += 1;
        }
        i += 1;
    }
    if (diff == 8) {
        printf("t_game: fail streams differ\n");
        fails += 1;
    }

    if (fails == 0) {
        printf("game suite: ok\n");
        return 0;
    }
    printf("game suite: FAIL %lld\n", fails);
    return 1;
}
