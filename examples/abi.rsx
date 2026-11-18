struct Wide {
    a: i64,
    b: i64,
    c: i64
}

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn sum9(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64, i: i64) -> i64 {
    return a + b + c + d + e + f + g + h + i;
}

fn fsum10(a: f64, b: f64, c: f64, d: f64, e: f64, f: f64, g: f64, h: f64, i: f64, j: f64) -> f64 {
    return a + b + c + d + e + f + g + h + i + j;
}

fn mixed(a: i64, x: f64, b: i64, y: f64, c: i64, z: f64, d: i64, w: f64, e: i64, v: f64) -> f64 {
    return (a + b + c + d + e) as f64 + x + y + z + w + v;
}

fn wide(a: i64, b: i64) -> Wide {
    return Wide { a: a + b, b: a - b, c: a * b };
}

fn chain(n: i64, a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) -> i64 {
    if (n == 0) {
        return a + b + c + d + e + f + g + h;
    }
    return chain(n - 1, a + 1, b + 2, c + 3, d + 4, e + 5, f + 6, g + 7, h + 8);
}

fn bigframe(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64, i: i64) -> i64 {
    var pad: [u8; 5000] = [0];
    pad[0] = 1;
    pad[4999] = 2;
    return a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7 + h * 8 + i * 9
        + (pad[0] as i64) + (pad[4999] as i64);
}

fn main() -> i32 {
    printf("sum9 = %lld\n", sum9(1, 2, 3, 4, 5, 6, 7, 8, 9));
    printf("fsum10 = %f\n", fsum10(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0));
    printf("mixed = %f\n", mixed(1, 10.0, 2, 20.0, 3, 30.0, 4, 40.0, 5, 50.0));

    let w: Wide = wide(20, 10);
    printf("wide = %lld %lld %lld\n", w.a, w.b, w.c);

    printf("chain = %lld\n", chain(4, 1, 2, 3, 4, 5, 6, 7, 8));
    printf("bigframe = %lld\n", bigframe(1, 2, 3, 4, 5, 6, 7, 8, 9));
    return 0;
}
