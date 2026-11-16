extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;

mod m {
    const N: i64 = 4;

    fn f() -> i32 {
        var a: [u8; N] = [0];
        a[0] = 9;
        return a[0] as i32;
    }
}

fn main() -> i32 {
    printf("f=%d\n", m::f());
    fflush(null);
    return 0;
}
