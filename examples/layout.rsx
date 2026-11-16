// Unboxed layout, proved with numbers.
//
// A struct is its fields, in order, with no header and no pointer. An array
// of structs is one contiguous run of those bytes. A generic over the
// element type is a copy of the loop with the element size baked in, so the
// stride is a constant and nothing chases a pointer.

extern fn printf(fmt: ptr<u8>, ...) -> i32;

struct Vec2 {
    x: f64,
    y: f64
}

struct Grid {
    label: i32,
    cell: Vec2,
    tail: i32
}

// Every instance gets its own body with a known element type and a known
// width. No Box, no trait object, no dynamic call: `total$i32` and
// `total$f64` are separate direct functions.
fn total<T>(xs: &[T; 4]) -> T {
    var s: T = xs[0];
    var i: i64 = 1;
    while (i < 4) {
        s = s + xs[i];
        i += 1;
    }
    return s;
}

fn main() -> i32 {
    printf("sizeof(Vec2)   = %d\n", sizeof(Vec2));
    printf("sizeof(Grid)   = %d\n", sizeof(Grid));
    printf("sizeof([Vec2; 4]) = %d\n", sizeof([Vec2; 4]));

    var v: [Vec2; 4] = [
        Vec2 { x: 1.0, y: 0.5 },
        Vec2 { x: 2.0, y: 1.5 },
        Vec2 { x: 3.0, y: 2.5 },
        Vec2 { x: 4.0, y: 3.5 }
    ];
    // The address difference between neighbours is the whole element, so the
    // elements are inline and adjacent, not pointers to somewhere else.
    var step: u64 = 0;
    unsafe {
        let p: ptr<Vec2> = &v[1] as ptr<Vec2>;
        let q: ptr<Vec2> = &v[0] as ptr<Vec2>;
        step = (p as u64) - (q as u64);
    }
    printf("stride(Vec2)   = %d\n", step);
    printf("last.y         = %f\n", v[3].y);

    var xs: [i32; 4] = [10, 20, 30, 40];
    var fs: [f64; 4] = [1.5, 2.5, 3.5, 4.5];
    printf("total i32      = %d\n", total(&xs));
    printf("total f64      = %f\n", total(&fs));

    var g: Grid = Grid { label: 7, cell: Vec2 { x: 0.25, y: 0.75 }, tail: 9 };
    printf("grid           = %d %f %d\n", g.label, g.cell.y, g.tail);
    return 0;
}
