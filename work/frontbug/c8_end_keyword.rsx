extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;

fn f(n: i32) -> i32 {
    if (n > 0)
        let end: i32 = 3;
        printf("end=%d\n", end);
    end;
    return n;
}

fn main() -> i32 {
    printf("r=%d\n", f(1));
    fflush(null);
    return 0;
}
