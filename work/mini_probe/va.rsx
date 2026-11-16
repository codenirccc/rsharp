extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "kernel32" fn VirtualAlloc(addr: ptr<u8>, size: u64, kind: u32, protect: u32) -> ptr<u8>;

struct C {
    src: ptr<u8>,
    out: ptr<u8>,
    n: i64
}

fn put(k: &mut C, i: i64, b: u8) {
    unsafe {
        k.out[i] = b;
    }
}

fn main() -> i32 {
    var k: C = zero(C);
    k.src = VirtualAlloc(null, 1000000, 12288, 4);
    k.out = VirtualAlloc(null, 8000000, 12288, 4);
    put(&mut k, 0, 65);
    put(&mut k, 1, 66);
    put(&mut k, 2, 0);
    unsafe {
        printf("%s %lld\n", k.out, k.src as i64);
    }
    return 0;
}
