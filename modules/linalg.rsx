struct Mat2 {
    a: f64,
    b: f64,
    c: f64,
    d: f64
}

struct Mat3 {
    m00: f64,
    m01: f64,
    m02: f64,
    m10: f64,
    m11: f64,
    m12: f64,
    m20: f64,
    m21: f64,
    m22: f64
}

fn mat2_det(m: &Mat2) -> f64 {
    return m.a * m.d - m.b * m.c;
}

fn mat2_mul(a: &Mat2, b: &Mat2) -> Mat2 {
    var out: Mat2 = Mat2 {
        a: a.a * b.a + a.b * b.c,
        b: a.a * b.b + a.b * b.d,
        c: a.c * b.a + a.d * b.c,
        d: a.c * b.b + a.d * b.d
    };
    return out;
}

fn mat2_vec(m: &Mat2, x: f64, y: f64) -> (f64, f64) {
    return (m.a * x + m.b * y, m.c * x + m.d * y);
}

fn mat2_inv(m: &Mat2) -> Mat2 {
    let det: f64 = mat2_det(m);
    var out: Mat2 = Mat2 {
        a: m.d / det,
        b: 0.0 - m.b / det,
        c: 0.0 - m.c / det,
        d: m.a / det
    };
    return out;
}

fn mat2_solve(m: &Mat2, bx: f64, by: f64) -> (f64, f64) {
    let det: f64 = mat2_det(m);
    let x: f64 = (bx * m.d - m.b * by) / det;
    let y: f64 = (m.a * by - bx * m.c) / det;
    return (x, y);
}

fn mat3_det(m: &Mat3) -> f64 {
    return m.m00 * (m.m11 * m.m22 - m.m12 * m.m21)
         - m.m01 * (m.m10 * m.m22 - m.m12 * m.m20)
         + m.m02 * (m.m10 * m.m21 - m.m11 * m.m20);
}

fn mat3_mul(a: &Mat3, b: &Mat3) -> Mat3 {
    var out: Mat3 = Mat3 {
        m00: a.m00 * b.m00 + a.m01 * b.m10 + a.m02 * b.m20,
        m01: a.m00 * b.m01 + a.m01 * b.m11 + a.m02 * b.m21,
        m02: a.m00 * b.m02 + a.m01 * b.m12 + a.m02 * b.m22,
        m10: a.m10 * b.m00 + a.m11 * b.m10 + a.m12 * b.m20,
        m11: a.m10 * b.m01 + a.m11 * b.m11 + a.m12 * b.m21,
        m12: a.m10 * b.m02 + a.m11 * b.m12 + a.m12 * b.m22,
        m20: a.m20 * b.m00 + a.m21 * b.m10 + a.m22 * b.m20,
        m21: a.m20 * b.m01 + a.m21 * b.m11 + a.m22 * b.m21,
        m22: a.m20 * b.m02 + a.m21 * b.m12 + a.m22 * b.m22
    };
    return out;
}

fn mat3_vec(m: &Mat3, x: f64, y: f64, z: f64) -> (f64, f64, f64) {
    return (
        m.m00 * x + m.m01 * y + m.m02 * z,
        m.m10 * x + m.m11 * y + m.m12 * z,
        m.m20 * x + m.m21 * y + m.m22 * z
    );
}

fn mat3_inv(m: &Mat3) -> Mat3 {
    let det: f64 = mat3_det(m);
    var out: Mat3 = Mat3 {
        m00: (m.m11 * m.m22 - m.m12 * m.m21) / det,
        m01: (m.m02 * m.m21 - m.m01 * m.m22) / det,
        m02: (m.m01 * m.m12 - m.m02 * m.m11) / det,
        m10: (m.m12 * m.m20 - m.m10 * m.m22) / det,
        m11: (m.m00 * m.m22 - m.m02 * m.m20) / det,
        m12: (m.m02 * m.m10 - m.m00 * m.m12) / det,
        m20: (m.m10 * m.m21 - m.m11 * m.m20) / det,
        m21: (m.m01 * m.m20 - m.m00 * m.m21) / det,
        m22: (m.m00 * m.m11 - m.m01 * m.m10) / det
    };
    return out;
}

fn mat3_solve(m: &Mat3, bx: f64, by: f64, bz: f64) -> (f64, f64, f64) {
    let det: f64 = mat3_det(m);
    var a: Mat3 = Mat3 {
        m00: bx, m01: m.m01, m02: m.m02,
        m10: by, m11: m.m11, m12: m.m12,
        m20: bz, m21: m.m21, m22: m.m22
    };
    var b: Mat3 = Mat3 {
        m00: m.m00, m01: bx, m02: m.m02,
        m10: m.m10, m11: by, m12: m.m12,
        m20: m.m20, m21: bz, m22: m.m22
    };
    var c: Mat3 = Mat3 {
        m00: m.m00, m01: m.m01, m02: bx,
        m10: m.m10, m11: m.m11, m12: by,
        m20: m.m20, m21: m.m21, m22: bz
    };
    let xa: f64 = mat3_det(&a);
    let xb: f64 = mat3_det(&b);
    let xc: f64 = mat3_det(&c);
    return (xa / det, xb / det, xc / det);
}

fn mat3_identity() -> Mat3 {
    return Mat3 {
        m00: 1.0, m01: 0.0, m02: 0.0,
        m10: 0.0, m11: 1.0, m12: 0.0,
        m20: 0.0, m21: 0.0, m22: 1.0
    };
}
