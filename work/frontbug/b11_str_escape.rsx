extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern fn fflush(p: ptr<u8>) -> i32;

fn main() -> i32 {
    let s: ptr<u8> = "tab\there nul\060one u64\060two";
    printf("s=%s\n", s);
    let big: u64 = 0xFFFFFFFFFFFFFFFF;
    printf("big=%lld\n", big);
    fflush(null);
    return 0;
}
