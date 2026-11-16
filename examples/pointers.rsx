extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern fn malloc(n: u64) -> ptr<u8>;
extern fn free(p: ptr<u8>);

fn sum(buf: ptr<i32>, n: i64) -> i64 {
    var total: i64 = 0;
    var i: i64 = 0;
    unsafe {
        while (i < n) {
            total += buf[i] as i64;
            i += 1;
        }
    }
    return total;
}

fn main() -> i32 {
    let n: i64 = 16;
    let raw: ptr<u8> = malloc((n * 4) as u64);
    let buf: ptr<i32> = raw as ptr<i32>;

    var i: i64 = 0;
    while (i < n) {
        unsafe {
            buf[i] = (i * i) as i32;
        }
        i += 1;
    }

    let total: i64 = sum(buf, n);
    printf("sum of squares 0..%lld = %lld\n", n - 1, total);
    free(raw);
    return 0;
}
