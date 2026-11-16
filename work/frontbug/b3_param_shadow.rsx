extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;

mod m {
    fn helper() -> i32 {
        return 1;
    }

    fn use_it(helper: i32) -> i32 {
        return helper;
    }
}

fn main() -> i32 {
    printf("r=%d\n", m::use_it(5));
    fflush(null);
    return 0;
}
