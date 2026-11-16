extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;

fn main() -> i32 {
    let self: i32 = 1;
    let end: i32 = 2;
    printf("self=%d end=%d\n", self, end);
    fflush(null);
    return 0;
}
