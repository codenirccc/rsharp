// Zero-cost generics: every call site below is monomorphised at compile time.
// No box, no vtable, no indirect call; `max<i32>` and `max<f64>` are two
// ordinary functions in the image.

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn max<T>(a: T, b: T) -> T {
    if (a > b) {
        return a;
    }
    return b;
}

fn min<T>(a: T, b: T) -> T {
    if (a < b) {
        return a;
    }
    return b;
}

// Two parameters, so the copy is named after both: clamp$i32$i32.
fn clamp<T>(x: T, lo: T, hi: T) -> T {
    return min(max(x, lo), hi);
}

// A generic that takes a reference and returns a reference: no copy of the
// pointee, just a different static type on the same address.
fn pick<T>(a: &T, b: &T, first: bool) -> &T {
    if (first) {
        return a;
    }
    return b;
}

// A generic over a tuple. The tuple is laid out inline in the frame; the
// generic adds no indirection over the concrete version.
fn swap<T, U>(p: (T, U)) -> (U, T) {
    return (p.1, p.0);
}

struct Vec2 {
    x: f64,
    y: f64
}

fn dot<T>(a: T, b: T) -> f64 {
    return a.x * b.x + a.y * b.y;
}

fn main() -> i32 {
    printf("max i32   = %d\n", max(3, 9));
    printf("max f64   = %f\n", max(1.5, 0.25));
    printf("min u8    = %d\n", min(200 as u8, 41 as u8));
    printf("clamp     = %d\n", clamp(120, 0, 100));

    let left: i32 = 7;
    let right: i32 = 11;
    printf("pick a    = %d\n", *pick(&left, &right, true));
    printf("pick b    = %d\n", *pick(&left, &right, false));

    let p: (i32, f64) = (9, 2.5);
    let q: (f64, i32) = swap(p);
    printf("swap      = %f %d\n", q.0, q.1);

    let u: Vec2 = Vec2 { x: 1.5, y: 2.0 };
    let v: Vec2 = Vec2 { x: 3.0, y: 4.5 };
    printf("dot       = %f\n", dot(u, v));
    return 0;
}
