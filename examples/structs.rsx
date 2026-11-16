struct Vec2 {
    x: f64,
    y: f64
}

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn dot(a: Vec2, b: Vec2) -> f64 {
    return a.x * b.x + a.y * b.y;
}

fn scale(v: Vec2, k: f64) -> Vec2 {
    var out: Vec2 = v;
    out.x *= k;
    out.y *= k;
    return out;
}

fn main() -> i32 {
    let a: Vec2 = Vec2 { x: 1.0, y: 2.0 };
    let b: Vec2 = Vec2 { x: 3.0, y: 4.0 };

    printf("dot = %f\n", dot(a, b));

    let s: Vec2 = scale(a, 2.5);
    printf("scaled = %f %f\n", s.x, s.y);

    unsafe {
        let p: ptr<Vec2> = &s as ptr<Vec2>;
        printf("through p = %f\n", p.x);
    }

    return 0;
}
