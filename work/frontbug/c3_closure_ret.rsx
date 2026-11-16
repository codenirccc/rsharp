extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;

fn main() -> i32 {
    let g: fn(i32) -> i32 = |x: i32| -> i32 { return x + 1; };
    printf("g=%d\n", g(4));
    fflush(null);
    return 0;
}
