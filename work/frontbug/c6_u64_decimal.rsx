extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;

fn main() -> i32 {
    let d: u64 = 18446744073709551615;
    printf("d=%lld\n", d);
    fflush(null);
    return 0;
}
