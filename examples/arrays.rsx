const COUNT: i64 = 4 * 2;
const SCALE: i32 = 1 + 2;

struct Reading {
    id: i32,
    value: i32
}

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn total(buf: &[i32; 8], n: i64) -> i64 {
    var sum: i64 = 0;
    var i: i64 = 0;
    while (i < n) {
        sum += buf[i] as i64;
        i += 1;
    }
    return sum;
}

fn main() -> i32 {
    var squares: [i32; COUNT] = [0, 1, 4, 9, 16, 25, 36, 49];

    var i: i64 = 0;
    while (i < COUNT) {
        squares[i] *= SCALE;
        i += 1;
    }

    let r: Reading = Reading { id: 7, value: squares[3] };

    if (r.value > 20) {
        printf("reading %d is loud: %d\n", r.id, r.value);
    } else if (r.value > 10) {
        printf("reading %d is warm: %d\n", r.id, r.value);
    } else {
        printf("reading %d is quiet: %d\n", r.id, r.value);
    }

    printf("total = %lld\n", total(&squares, COUNT));
    return 0;
}
