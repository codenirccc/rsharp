struct Pair {
    a: i32,
    b: i32
}

struct Crate {
    p: Pair,
    v: [i32; 3],
    f: f32
}

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn sum3(x: i32, y: i32, z: i32) -> i32 {
    return x + y + z;
}

fn six(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32) -> i32 {
    return a + b + c + d + e + f;
}

fn fsum(a: f64, b: f64, c: f64, d: f64, e: f64) -> f64 {
    return a + b + c + d + e;
}

fn make() -> Pair {
    return Pair { a: 3, b: 4 };
}

fn main() -> i32 {
    let q: Pair = make();
    printf("q = %d %d\n", q.a, q.b);

    printf("sum3 = %d\n", sum3(1, 2, 3));
    printf("six = %d\n", six(1, 2, 3, 4, 5, 6));
    printf("fsum = %f\n", fsum(1.0, 2.0, 3.0, 4.0, 5.5));

    var b: Crate = Crate { p: Pair { a: 9, b: 8 }, v: [7, 8, 9], f: 1.5 };
    printf("box = %d %d %d %d %f\n", b.p.a, b.p.b, b.v[0], b.v[2], b.f);

    var i: i32 = 0;
    var acc: i32 = 0;
    loop {
        i += 1;
        if (i % 2 == 0) {
            continue;
        }
        if (i > 7) {
            break;
        }
        acc += i;
    }
    printf("acc = %d\n", acc);

    var x: f64 = 10.0;
    x *= 2.5;
    x -= 1.0;
    x /= 3.0;
    printf("x = %f\n", x);

    unsafe {
        let p: ptr<i32> = &b.v[0] as ptr<i32>;
        printf("p[1] = %d\n", p[1]);
    }
    printf("sizeof = %lld\n", sizeof(Crate) as i64);

    var s: i32 = 1;
    {
        var s: i32 = 2;
        printf("inner %d\n", s);
    }
    printf("outer %d\n", s);

    let t: bool = !(3 > 4) && (2 < 1 || true);
    printf("t = %d\n", t as i32);

    let neg: f64 = -x;
    printf("neg = %f\n", neg);

    var w: u32 = 4294967295 as u32;
    printf("w = %u\n", w);

    return 0;
}
