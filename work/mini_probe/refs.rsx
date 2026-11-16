extern fn printf(fmt: ptr<u8>, ...) -> i32;

struct C {
    n: i64
}

fn rd(c: &mut C) -> i64 {
    return c.n;
}

fn bump(c: &mut C) {
    c.n += 1;
}

fn indirect(c: &mut C) -> i64 {
    bump(c);
    return rd(c);
}

fn go(c: &mut C) -> i32 {
    return rd(c) as i32;
}

fn main() -> i32 {
    var c: C = zero(C);
    bump(&mut c);
    let x: i64 = indirect(&mut c);
    printf("%lld %lld\n", x, rd(&mut c));
    let r: i32 = go(&mut c);
    return r;
}
