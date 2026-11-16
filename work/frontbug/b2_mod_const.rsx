extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;

mod m {
    const A: i32 = 3;
    const B: i32 = A + 1;
}

fn main() -> i32 {
    printf("b=%d\n", m::B);
    fflush(null);
    return 0;
}
