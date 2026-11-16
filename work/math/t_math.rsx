include "../../modules/math.rsx";

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
        printf("t_math: fail %s got %.15f want %.15f\n", name, got, want);
        return 1;
    }
    return 0;
}

fn expect_i64(name: ptr<u8>, got: i64, want: i64) -> i64 {
    if (got != want) {
        printf("t_math: fail %s got %lld want %lld\n", name, got, want);
        return 1;
    }
    return 0;
}

fn main() -> i32 {
    var fails: i64 = 0;

    fails += expect_close("sqrt2" as ptr<u8>, fsqrt(2.0), 1.4142135623730951, 0.0000000000001);
    fails += expect_close("sqrt4" as ptr<u8>, fsqrt(4.0), 2.0, 0.000000000000001);
    fails += expect_close("sqrt025" as ptr<u8>, fsqrt(0.25), 0.5, 0.000000000000001);
    fails += expect_close("sqrtbig" as ptr<u8>, fsqrt(12345.6789), 111.11111060555555, 0.000000000001);
    fails += expect_close("sqrtneg" as ptr<u8>, fsqrt(-1.0), -1.0, 0.0);

    fails += expect_close("sin0" as ptr<u8>, fsin(0.0), 0.0, 0.0);
    fails += expect_close("sinpi6" as ptr<u8>, fsin(PI / 6.0), 0.49999999999999994, 0.000000000001);
    fails += expect_close("sin1" as ptr<u8>, fsin(1.0), 0.8414709848078965, 0.000000000001);
    fails += expect_close("sin2.5" as ptr<u8>, fsin(2.5), 0.5984721441039564, 0.000000000001);
    fails += expect_close("sinneg" as ptr<u8>, fsin(-1.5), -0.9974949866040544, 0.000000000001);
    fails += expect_close("sin100" as ptr<u8>, fsin(100.0), -0.5063656411097588, 0.0000000001);
    fails += expect_close("cos0" as ptr<u8>, fcos(0.0), 1.0, 0.0);
    fails += expect_close("cospi" as ptr<u8>, fcos(PI), -1.0, 0.0000000000001);
    fails += expect_close("cos1" as ptr<u8>, fcos(1.0), 0.5403023058681398, 0.000000000001);
    fails += expect_close("cos2.5" as ptr<u8>, fcos(2.5), -0.8011436155469337, 0.000000000001);
    fails += expect_close("cos100" as ptr<u8>, fcos(100.0), 0.8623188722876839, 0.0000000001);
    fails += expect_close("tan0.5" as ptr<u8>, ftan(0.5), 0.5463024898437905, 0.000000000001);

    fails += expect_close("floor2.7" as ptr<u8>, ffloor(2.7), 2.0, 0.0);
    fails += expect_close("floorneg" as ptr<u8>, ffloor(-2.7), -3.0, 0.0);
    fails += expect_close("floor2" as ptr<u8>, ffloor(2.0), 2.0, 0.0);
    fails += expect_close("ceil2.3" as ptr<u8>, fceil(2.3), 3.0, 0.0);
    fails += expect_close("ceilneg" as ptr<u8>, fceil(-2.3), -2.0, 0.0);
    fails += expect_close("trunc2.7" as ptr<u8>, ftrunc(2.7), 2.0, 0.0);
    fails += expect_close("truncneg" as ptr<u8>, ftrunc(-2.7), -2.0, 0.0);
    fails += expect_close("round2.4" as ptr<u8>, fround(2.4), 2.0, 0.0);
    fails += expect_close("round2.5" as ptr<u8>, fround(2.5), 3.0, 0.0);
    fails += expect_close("round2.6" as ptr<u8>, fround(2.6), 3.0, 0.0);
    fails += expect_close("roundneg" as ptr<u8>, fround(-2.5), -3.0, 0.0);
    fails += expect_close("roundneg2" as ptr<u8>, fround(-2.6), -3.0, 0.0);

    fails += expect_close("fmod" as ptr<u8>, fmod(5.5, 2.0), 1.5, 0.0);
    fails += expect_close("fmod2" as ptr<u8>, fmod(-5.5, 2.0), -1.5, 0.0);
    fails += expect_close("fmod3" as ptr<u8>, fmod(5.5, -2.0), 1.5, 0.0);

    fails += expect_close("pow2_10" as ptr<u8>, fpow_i(2.0, 10), 1024.0, 0.0);
    fails += expect_close("pow1.5_4" as ptr<u8>, fpow_i(1.5, 4), 5.0625, 0.0);
    fails += expect_close("pow10_neg2" as ptr<u8>, fpow_i(10.0, -2), 0.01, 0.0000000000001);

    fails += expect_i64("isqrt25" as ptr<u8>, isqrt(25), 5);
    fails += expect_i64("isqrt99" as ptr<u8>, isqrt(99), 9);
    fails += expect_i64("isqrt0" as ptr<u8>, isqrt(0), 0);
    fails += expect_i64("isqrt1" as ptr<u8>, isqrt(1), 1);
    fails += expect_i64("isqrtbig" as ptr<u8>, isqrt(12345678), 3513);
    fails += expect_i64("ipow2_10" as ptr<u8>, ipow(2, 10), 1024);
    fails += expect_i64("ipow3_6" as ptr<u8>, ipow(3, 6), 729);

    if (fails == 0) {
        printf("math suite: ok\n");
        return 0;
    }
    printf("math suite: FAIL %lld\n", fails);
    return 1;
}
