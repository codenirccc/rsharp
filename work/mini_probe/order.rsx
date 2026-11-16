fn main() -> i32 {
    puts(hi());
    later(3);
    return 0;
}

fn hi() -> ptr<u8> {
    return "ok";
}

fn later(n: i64) {
    printf("%lld\n", n);
}

extern fn puts(s: ptr<u8>) -> i32;
extern fn printf(fmt: ptr<u8>, ...) -> i32;
