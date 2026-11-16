extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;

struct P {
    x: i32
}

impl P {
    fn get(self: &P) -> i32 {
        return self.x;
    }
}

fn main() -> i32 {
    var p: P;
    p.x = 7;
    let v: i32 = p.get();
    printf("v=%d\n", v);
    fflush(null);
    return 0;
}
