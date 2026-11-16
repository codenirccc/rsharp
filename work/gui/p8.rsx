extern fn printf(fmt: ptr<u8>, ...) -> i32;

struct S {
    n: i64
}

fn bump(s: &mut S) {
    s.n += 10;
}

fn main() -> i32 {
    var s: S = zero(S);
    s.n = 5;
    bump(&mut s);
    var p: ptr<S> = null;
    unsafe { p = &mut s as ptr<S>; }
    unsafe { bump(&mut *p); }
    var q: ptr<S> = null;
    unsafe { q = p; }
    unsafe { bump(&mut *q); }
    printf("n=%lld\n", s.n);
    return 0;
}
