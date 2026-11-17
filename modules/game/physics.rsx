struct Circle {
    x: f64,
    y: f64,
    r: f64,
    vx: f64,
    vy: f64,
    inv_m: f64,
    rest: f64
}

struct AABB {
    x: f64,
    y: f64,
    hw: f64,
    hh: f64,
    vx: f64,
    vy: f64,
    inv_m: f64,
    rest: f64
}

fn phy_sign(v: f64) -> f64 {
    if (v < 0.0) {
        return -1.0;
    }
    return 1.0;
}

fn phy_integrate_circle(c: &mut Circle, gravity: f64, dt: f64) {
    c.vy = c.vy + gravity * dt;
    c.x = c.x + c.vx * dt;
    c.y = c.y + c.vy * dt;
}

fn phy_integrate_aabb(b: &mut AABB, gravity: f64, dt: f64) {
    b.vy = b.vy + gravity * dt;
    b.x = b.x + b.vx * dt;
    b.y = b.y + b.vy * dt;
}

fn phy_overlap_circle(a: &Circle, b: &Circle) -> i64 {
    let dx: f64 = b.x - a.x;
    let dy: f64 = b.y - a.y;
    let min_d: f64 = a.r + b.r;
    return (dx * dx + dy * dy < min_d * min_d) as i64;
}

fn phy_overlap_aabb(a: &AABB, b: &AABB) -> i64 {
    let dx: f64 = b.x - a.x;
    if (fabs(dx) >= a.hw + b.hw) {
        return 0;
    }
    let dy: f64 = b.y - a.y;
    if (fabs(dy) >= a.hh + b.hh) {
        return 0;
    }
    return 1;
}

fn phy_resolve_circle(a: &mut Circle, b: &mut Circle) -> i64 {
    let dx: f64 = b.x - a.x;
    let dy: f64 = b.y - a.y;
    let d2: f64 = dx * dx + dy * dy;
    let min_d: f64 = a.r + b.r;
    if (d2 >= min_d * min_d) {
        return 0;
    }
    var nx: f64 = 1.0;
    var ny: f64 = 0.0;
    if (d2 != 0.0) {
        let d: f64 = fsqrt(d2);
        nx = dx / d;
        ny = dy / d;
    }
    let d: f64 = fsqrt(d2);
    let overlap: f64 = min_d - d;
    let total: f64 = a.inv_m + b.inv_m;
    if (total == 0.0) {
        return 1;
    }
    a.x = a.x - nx * overlap * (a.inv_m / total);
    a.y = a.y - ny * overlap * (a.inv_m / total);
    b.x = b.x + nx * overlap * (b.inv_m / total);
    b.y = b.y + ny * overlap * (b.inv_m / total);
    let rvx: f64 = b.vx - a.vx;
    let rvy: f64 = b.vy - a.vy;
    let vel: f64 = rvx * nx + rvy * ny;
    if (vel > 0.0) {
        return 1;
    }
    let e: f64 = fmin(a.rest, b.rest);
    let jimp: f64 = -(1.0 + e) * vel / total;
    a.vx = a.vx - jimp * nx * a.inv_m;
    a.vy = a.vy - jimp * ny * a.inv_m;
    b.vx = b.vx + jimp * nx * b.inv_m;
    b.vy = b.vy + jimp * ny * b.inv_m;
    if (fabs(a.vx) < 0.05 && fabs(a.vy) < 0.05) {
        a.vx = 0.0;
        a.vy = 0.0;
    }
    if (fabs(b.vx) < 0.05 && fabs(b.vy) < 0.05) {
        b.vx = 0.0;
        b.vy = 0.0;
    }
    return 1;
}

fn phy_resolve_circle_aabb(c: &mut Circle, b: &mut AABB) -> i64 {
    var cx: f64 = c.x;
    var cy: f64 = c.y;
    if (cx < b.x - b.hw) {
        cx = b.x - b.hw;
    } else if (cx > b.x + b.hw) {
        cx = b.x + b.hw;
    }
    if (cy < b.y - b.hh) {
        cy = b.y - b.hh;
    } else if (cy > b.y + b.hh) {
        cy = b.y + b.hh;
    }
    let dx: f64 = cx - c.x;
    let dy: f64 = cy - c.y;
    let d2: f64 = dx * dx + dy * dy;
    if (d2 >= c.r * c.r) {
        return 0;
    }
    var nx: f64 = 1.0;
    var ny: f64 = 0.0;
    if (d2 != 0.0) {
        let d: f64 = fsqrt(d2);
        nx = dx / d;
        ny = dy / d;
    }
    let d: f64 = fsqrt(d2);
    let overlap: f64 = c.r - d;
    let total: f64 = c.inv_m + b.inv_m;
    if (total == 0.0) {
        return 1;
    }
    c.x = c.x - nx * overlap * (c.inv_m / total);
    c.y = c.y - ny * overlap * (c.inv_m / total);
    b.x = b.x + nx * overlap * (b.inv_m / total);
    b.y = b.y + ny * overlap * (b.inv_m / total);
    let rvx: f64 = b.vx - c.vx;
    let rvy: f64 = b.vy - c.vy;
    let vel: f64 = rvx * nx + rvy * ny;
    if (vel > 0.0) {
        return 1;
    }
    let e: f64 = fmin(c.rest, b.rest);
    let jimp: f64 = -(1.0 + e) * vel / total;
    c.vx = c.vx - jimp * nx * c.inv_m;
    c.vy = c.vy - jimp * ny * c.inv_m;
    b.vx = b.vx + jimp * nx * b.inv_m;
    b.vy = b.vy + jimp * ny * b.inv_m;
    if (fabs(c.vx) < 0.05 && fabs(c.vy) < 0.05) {
        c.vx = 0.0;
        c.vy = 0.0;
    }
    if (fabs(b.vx) < 0.05 && fabs(b.vy) < 0.05) {
        b.vx = 0.0;
        b.vy = 0.0;
    }
    return 1;
}

fn phy_resolve_aabb(a: &mut AABB, b: &mut AABB) -> i64 {
    let dx: f64 = b.x - a.x;
    let px: f64 = a.hw + b.hw - fabs(dx);
    if (px <= 0.0) {
        return 0;
    }
    let dy: f64 = b.y - a.y;
    let py: f64 = a.hh + b.hh - fabs(dy);
    if (py <= 0.0) {
        return 0;
    }
    let total: f64 = a.inv_m + b.inv_m;
    if (total == 0.0) {
        return 1;
    }
    var nx: f64 = 0.0;
    var ny: f64 = 0.0;
    var overlap: f64 = px;
    if (px < py) {
        nx = phy_sign(dx);
        overlap = px;
    } else {
        ny = phy_sign(dy);
        overlap = py;
    }
    a.x = a.x - nx * overlap * (a.inv_m / total);
    a.y = a.y - ny * overlap * (a.inv_m / total);
    b.x = b.x + nx * overlap * (b.inv_m / total);
    b.y = b.y + ny * overlap * (b.inv_m / total);
    let rvx: f64 = b.vx - a.vx;
    let rvy: f64 = b.vy - a.vy;
    let vel: f64 = rvx * nx + rvy * ny;
    if (vel > 0.0) {
        return 1;
    }
    let e: f64 = fmin(a.rest, b.rest);
    let jimp: f64 = -(1.0 + e) * vel / total;
    a.vx = a.vx - jimp * nx * a.inv_m;
    a.vy = a.vy - jimp * ny * a.inv_m;
    b.vx = b.vx + jimp * nx * b.inv_m;
    b.vy = b.vy + jimp * ny * b.inv_m;
    if (fabs(a.vx) < 0.05 && fabs(a.vy) < 0.05) {
        a.vx = 0.0;
        a.vy = 0.0;
    }
    if (fabs(b.vx) < 0.05 && fabs(b.vy) < 0.05) {
        b.vx = 0.0;
        b.vy = 0.0;
    }
    return 1;
}
