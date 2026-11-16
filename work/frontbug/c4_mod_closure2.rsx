mod m {
    fn helper() -> i32 {
        return 7;
    }

    fn f() -> i32 {
        let g: fn(i32) -> i32 = |x: i32| -> i32 { return helper() + x; };
        return g(1);
    }
}

extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;

fn main() -> i32 {
    printf("g=%d\n", m::f());
    fflush(null);
    return 0;
}
