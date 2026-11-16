extern fn printf(fmt: ptr<u8>, ...) -> i32;

struct Big {
    a: [u8; 1000000],
    b: [u8; 1000000],
    c: [u8; 1000000],
    d: [u8; 1000000]
}

fn main() -> i32 {
    var s: Big;
    s.a[0] = 7;
    s.a[999999] = 9;
    s.b[0] = 11;
    s.c[999999] = 13;
    s.d[500000] = 15;
    printf("%lld %lld %lld %lld %lld\n", s.a[0] as i64, s.a[999999] as i64, s.b[0] as i64, s.c[999999] as i64, s.d[500000] as i64);
    return 0;
}
