extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;

mod a {
    mod b {
        struct S {
            v: i32
        }
    }

    fn make() -> b::S {
        var s: b::S;
        s.v = 4;
        return s;
    }

    fn nested() -> i32 {
        let s: b::S = make();
        return s.v;
    }
}

fn main() -> i32 {
    printf("v=%d\n", a::nested());
    fflush(null);
    return 0;
}
