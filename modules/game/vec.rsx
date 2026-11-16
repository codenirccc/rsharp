fn v2_dot(ax: f64, ay: f64, bx: f64, by: f64) -> f64 {
    return ax * bx + ay * by;
}

fn v2_cross(ax: f64, ay: f64, bx: f64, by: f64) -> f64 {
    return ax * by - ay * bx;
}

fn v2_len(x: f64, y: f64) -> f64 {
    return fsqrt(x * x + y * y);
}

fn v2_dist(ax: f64, ay: f64, bx: f64, by: f64) -> f64 {
    let dx: f64 = ax - bx;
    let dy: f64 = ay - by;
    return fsqrt(dx * dx + dy * dy);
}

fn v2_norm_x(x: f64, y: f64) -> f64 {
    return x / v2_len(x, y);
}

fn v2_norm_y(x: f64, y: f64) -> f64 {
    return y / v2_len(x, y);
}

fn v2_lerp(ax: f64, ay: f64, bx: f64, by: f64, t: f64) -> (f64, f64) {
    return (ax + (bx - ax) * t, ay + (by - ay) * t);
}

fn v3_dot(ax: f64, ay: f64, az: f64, bx: f64, by: f64, bz: f64) -> f64 {
    return ax * bx + ay * by + az * bz;
}

fn v3_len(x: f64, y: f64, z: f64) -> f64 {
    return fsqrt(x * x + y * y + z * z);
}

fn v3_cross_x(ay: f64, az: f64, by: f64, bz: f64) -> f64 {
    return ay * bz - az * by;
}

fn v3_cross_y(az: f64, ax: f64, bz: f64, bx: f64) -> f64 {
    return az * bx - ax * bz;
}

fn v3_cross_z(ax: f64, ay: f64, bx: f64, by: f64) -> f64 {
    return ax * by - ay * bx;
}

fn angle_wrap(a: f64) -> f64 {
    var v: f64 = a;
    while (v > PI) {
        v = v - 2.0 * PI;
    }
    while (v < 0.0 - PI) {
        v = v + 2.0 * PI;
    }
    return v;
}
