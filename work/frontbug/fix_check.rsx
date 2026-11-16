mod m {
    const A: i32 = 3;
    const B: i32 = A + 1;
    const N: i64 = 4;

    mod b {
        struct S {
            v: i32
        }
    }

    fn helper() -> i32 {
        return 7;
    }

    fn use_it(helper: i32) -> i32 {
        return helper;
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

    fn arr() -> i32 {
        var a: [u8; N] = [0];
        a[0] = 9;
        return a[0] as i32;
    }

    fn clo() -> i32 {
        let g: fn(i32) -> i32 = |x: i32| -> i32 { return helper() + x; };
        return g(1);
    }
}

struct P {
    x: i32
}

impl P {
    fn get(self: &P) -> i32 {
        return self.x;
    }
}

extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;

fn main() -> i32 {
    var p: P;
    p.x = 7;
    let v: i32 = p.get();
    let z: fn() -> i32 = || -> i32 { return 5; };
    printf("method=%d modconst=%d param=%d arr=%d nested=%d closure=%d zero=%d\n",
        v, m::B, m::use_it(5), m::arr(), m::nested(), m::clo(), z());
    fflush(null);
    return 0;
}
