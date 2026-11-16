extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "kernel32" fn VirtualAlloc(addr: ptr<u8>, size: u64, kind: u32, protect: u32) -> ptr<u8>;

struct Node {
    kind: i64,
    a: i64,
    b: i64
}

struct C {
    src: ptr<u8>,
    nodes: ptr<Node>,
    n: i64
}

fn sb(c: &C, i: i64) -> u8 {
    unsafe {
        return c.src[i];
    }
}

fn sset(c: &mut C, i: i64, v: u8) {
    unsafe {
        c.src[i] = v;
    }
}

fn bump(c: &mut C) {
    let i: i64 = c.n;
    c.n += 1;
    unsafe {
        c.nodes[i].kind = 7;
        c.nodes[i].a = 11;
        c.nodes[i].b = 13;
    }
}

fn main() -> i32 {
    var c: C = zero(C);
    c.src = VirtualAlloc(null, 1000000, 12288, 4);
    var np: ptr<u8> = null;
    unsafe {
        np = VirtualAlloc(null, 4000000, 12288, 4) as ptr<u8>;
    }
    c.nodes = np as ptr<Node>;
    sset(&mut c, 0, 65);
    sset(&mut c, 1, 66);
    bump(&mut c);
    bump(&mut c);
    unsafe {
        printf("%lld %lld %lld %c %c\n", c.nodes[1].kind, c.nodes[0].a, c.nodes[0].b, sb(&c, 0), sb(&c, 1));
    }
    return 0;
}
