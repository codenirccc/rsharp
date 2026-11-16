extern fn printf(fmt: ptr<u8>, ...) -> i32;

struct C {
    a: [i64; 4096],
    b: [i64; 4096],
    n: i64
}

fn main() -> i32 {
    var c: C = zero(C);
    c.a[10] = 5;
    c.b[4000] = 7;
    printf("%lld %lld\n", c.a[10], c.b[4000]);
    return 0;
}
