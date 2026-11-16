fn ease_quad_in(t: f64) -> f64 {
    return t * t;
}

fn ease_quad_out(t: f64) -> f64 {
    return t * (2.0 - t);
}

fn ease_quad_inout(t: f64) -> f64 {
    if (t < 0.5) {
        return 2.0 * t * t;
    }
    return -1.0 + (4.0 - 2.0 * t) * t;
}

fn ease_cubic_in(t: f64) -> f64 {
    return t * t * t;
}

fn ease_cubic_out(t: f64) -> f64 {
    let u: f64 = t - 1.0;
    return u * u * u + 1.0;
}

fn ease_cubic_inout(t: f64) -> f64 {
    if (t < 0.5) {
        return 4.0 * t * t * t;
    }
    let u: f64 = t - 1.0;
    let v: f64 = 2.0 * t - 2.0;
    return u * (v * v) + 1.0;
}

fn ease_sine_in(t: f64) -> f64 {
    return 1.0 - fcos(t * (PI / 2.0));
}

fn ease_sine_out(t: f64) -> f64 {
    return fsin(t * (PI / 2.0));
}

fn ease_sine_inout(t: f64) -> f64 {
    return 0.5 * (1.0 - fcos(PI * t));
}

fn lerp_f64(a: f64, b: f64, t: f64) -> f64 {
    return a + (b - a) * t;
}

fn smoothstep_f64(t: f64) -> f64 {
    return t * t * (3.0 - 2.0 * t);
}
