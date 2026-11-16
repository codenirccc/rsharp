extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern fn puts(s: ptr<u8>) -> i32;

fn main() -> i32 {
    puts("direct");
    printf("%lld %lld %s\n", later(20), later(21), "tail");
    return 0;
}

fn later(n: i64) -> i64 {
    if (n < 2) { return n; }
    return later(n - 1) + later(n - 2);
}
