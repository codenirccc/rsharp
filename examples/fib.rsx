extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn fib(n: i64) -> i64 {
    if (n < 2) {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

fn main() -> i32 {
    var i: i64 = 0;
    while (i < 20) {
        printf("%lld\n", fib(i));
        i += 1;
    }
    return 0;
}
