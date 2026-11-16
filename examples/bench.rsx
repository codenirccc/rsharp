extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern fn GetTickCount64() -> u64;

fn blur(xs: &mut [i32; 256], rounds: i32) {
    var r: i32 = 0;
    while (r < rounds) {
        var i: i64 = 0;
        while (i < 256) {
            xs[i] = xs[i] * 3 + (i as i32);
            i += 1;
        }
        r += 1;
    }
}

fn main() -> i32 {
    var xs: [i32; 256];

    let t0: u64 = GetTickCount64();
    blur(&mut xs, 1000000);
    let t1: u64 = GetTickCount64();

    var sum: i64 = 0;
    var i: i64 = 0;
    while (i < 256) {
        sum += xs[i] as i64;
        i += 1;
    }

    printf("%lld in %llu ms\n", sum, t1 - t0);
    return 0;
}
