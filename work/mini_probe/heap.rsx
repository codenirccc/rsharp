extern fn printf(fmt: ptr<u8>, ...) -> i32;

struct C {
    a: [u8; 1000000],
    b: [u8; 1000000],
    c: [u8; 1000000],
    d: [u8; 1000000],
    n: i64
}

fn bump(k: &mut C) {
    k.n += 1;
    k.a[10] = 5;
    k.d[999999] = 9;
}

fn main() -> i32 {
    var k: Box<C> = box(zero(C));
    bump(&mut *k);
    printf("%lld %lld %lld\n", k.n, k.a[10] as i64, k.d[999999] as i64);
    return 0;
}
