extern fn printf(fmt: ptr<u8>, ...) -> i32;

struct Big {
    a: [u8; 100000],
    b: [u8; 100000],
    c: [u8; 100000],
    d: [u8; 100000]
}

fn main() -> i32 {
    var s: Big;
    s.a[0] = 7;
    s.a[99999] = 9;
    s.b[0] = 11;
    s.c[99999] = 13;
    s.d[50000] = 15;
    printf("%lld %lld %lld %lld %lld\n", s.a[0] as i64, s.a[99999] as i64, s.b[0] as i64, s.c[99999] as i64, s.d[50000] as i64);
    return 0;
}
