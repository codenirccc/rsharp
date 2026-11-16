struct Pair {
    a: i32,
    b: i32
}

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn bump(p: Pair) -> i32 {
    p.a += 100;
    return p.a;
}

fn deep(n: i64) -> i64 {
    if (n == 0) {
        return 0;
    }
    return 1 + deep(n - 1);
}

fn main() -> i32 {
    var a: i8 = 100;
    a += 100;
    printf("a = %d\n", a as i32);

    var b: u8 = 200;
    b += 100;
    printf("b = %d\n", b as i32);

    printf("div = %d %d\n", -7 / 2, -7 % 2);
    printf("udiv = %u\n", (4000000000 as u32) / 3 as u32);

    var f: f32 = 1.5;
    f *= 3.0;
    printf("f = %f\n", f as f64);

    var m: i32 = 0;
    var n: i32 = 0;
    while (n < 100000) {
        m += n % 7;
        n += 1;
    }
    printf("m = %d\n", m);

    let q: Pair = Pair { a: 5, b: 6 };
    printf("bump = %d a = %d\n", bump(q), q.a);
    printf("deep = %lld\n", deep(1000));
    printf("esc = [%s]\n", "tab\there\\slash");
    return 0;
}