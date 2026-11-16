struct Counter {
    hits: i32,
    total: i64
}

struct Pair {
    a: i32,
    b: i32
}

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn bump(c: &mut Counter, by: i32) {
    c.hits += 1;
    c.total += by as i64;
}

fn report(c: &Counter) -> i64 {
    return c.total;
}

fn sum(xs: &[i32; 6]) -> i64 {
    var s: i64 = 0;
    var i: i64 = 0;
    while (i < 6) {
        s += xs[i] as i64;
        i += 1;
    }
    return s;
}

fn make_pair(a: i32, b: i32) -> Box<Pair> {
    return box(Pair { a: a, b: b });
}

fn main() -> i32 {
    var c: Counter = Counter { hits: 0, total: 0 };
    bump(&mut c, 10);
    bump(&mut c, 25);
    printf("hits = %d total = %lld\n", c.hits, report(&c));

    let xs: [i32; 6] = [3, 1, 4, 1, 5, 9];
    printf("sum = %lld last = %d\n", sum(&xs), xs[5]);

    let ints: Box<i32> = box(21 * 2);
    printf("boxed = %d\n", *ints);

    let p: Box<Pair> = make_pair(7, 9);
    printf("pair = %d %d\n", p.a, p.b);
    return 0;
}
