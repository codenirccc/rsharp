include "../../modules/game/game.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn close(a: f64, b: f64, tol: f64) -> i64 {
    var d: f64 = a - b;
    if (d < 0.0) {
        d = 0.0 - d;
    }
    if (d <= tol) {
        return 1;
    }
    return 0;
}

fn expect_close(name: ptr<u8>, got: f64, want: f64, tol: f64) -> i64 {
    if (close(got, want, tol) != 1) {
        printf("t_physics: fail %s got %.10f want %.10f\n", name, got, want);
        return 1;
    }
    return 0;
}

fn main() -> i32 {
    var fails: i64 = 0;

    var a: Circle = Circle { x: 0.0, y: 0.0, r: 1.0, vx: 1.0, vy: 0.0, inv_m: 1.0, rest: 0.5 };
    var b: Circle = Circle { x: 1.5, y: 0.0, r: 1.0, vx: 0.0, vy: 0.0, inv_m: 1.0, rest: 0.5 };
    phy_resolve_circle(&mut a, &mut b);
    fails += expect_close("a_x" as ptr<u8>, a.x, -0.25, 0.000000001);
    fails += expect_close("a_vx" as ptr<u8>, a.vx, 0.25, 0.000000001);
    fails += expect_close("b_x" as ptr<u8>, b.x, 1.75, 0.000000001);
    fails += expect_close("b_vx" as ptr<u8>, b.vx, 0.75, 0.000000001);

    var ball: Circle = Circle { x: 0.0, y: 10.0, r: 0.5, vx: 0.0, vy: 0.0, inv_m: 1.0, rest: 0.5 };
    var floor: AABB = AABB { x: 0.0, y: 0.0, hw: 5.0, hh: 0.25, vx: 0.0, vy: 0.0, inv_m: 0.0, rest: 0.5 };
    var i: i64 = 0;
    while (i < 600) {
        phy_integrate_circle(&mut ball, 0.0 - 9.8, 0.016);
        phy_resolve_circle_aabb(&mut ball, &mut floor);
        i += 1;
    }
    fails += expect_close("rest_y" as ptr<u8>, ball.y, 0.75, 0.000000001);
    fails += expect_close("rest_vy" as ptr<u8>, ball.vy, 0.0, 0.0);

    var b1: AABB = AABB { x: 0.0, y: 0.0, hw: 0.5, hh: 0.5, vx: 2.0, vy: 0.0, inv_m: 1.0, rest: 0.25 };
    var b2: AABB = AABB { x: 0.9, y: 0.0, hw: 0.5, hh: 0.5, vx: 0.0, vy: 0.0, inv_m: 1.0, rest: 0.25 };
    phy_resolve_aabb(&mut b1, &mut b2);
    fails += expect_close("aabb_a" as ptr<u8>, b1.x, -0.05, 0.000000001);
    fails += expect_close("aabb_a_vx" as ptr<u8>, b1.vx, 0.75, 0.000000001);
    fails += expect_close("aabb_b" as ptr<u8>, b2.x, 0.95, 0.000000001);
    fails += expect_close("aabb_b_vx" as ptr<u8>, b2.vx, 1.25, 0.000000001);

    var overlap: i64 = phy_overlap_circle(&a, &b);
    if (overlap != 0) {
        printf("t_physics: fail overlap\n");
        fails += 1;
    }
    overlap = phy_overlap_aabb(&b1, &b2);
    if (overlap != 0) {
        printf("t_physics: fail aabb overlap\n");
        fails += 1;
    }

    if (fails == 0) {
        printf("physics suite: ok\n");
        return 0;
    }
    printf("physics suite: FAIL %lld\n", fails);
    return 1;
}
