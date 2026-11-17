include "../../modules/linalg.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn main() -> i32 {
    var m2: Mat2 = Mat2 { a: 2.0, b: 1.0, c: 5.0, d: 3.0 };
    var n2: Mat2 = Mat2 { a: 1.0, b: 0.0 - 1.0, c: 3.0, d: 4.0 };
    var m3: Mat3 = Mat3 { m00: 1.0, m01: 2.0, m02: 3.0, m10: 0.0, m11: 1.0, m12: 4.0, m20: 5.0, m21: 6.0, m22: 0.0 };
    var n3: Mat3 = Mat3 { m00: 2.0, m01: 1.0, m02: 0.0, m10: 4.0, m11: 1.0, m12: 1.0, m20: 3.0, m21: 0.0 - 1.0, m22: 1.0 };

    printf("det2 = %.6f\n", mat2_det(&m2));
    printf("det3 = %.6f\n", mat3_det(&m3));

    let p2: Mat2 = mat2_mul(&m2, &n2);
    printf("mul2_a = %.6f\n", p2.a);
    printf("mul2_b = %.6f\n", p2.b);
    printf("mul2_c = %.6f\n", p2.c);
    printf("mul2_d = %.6f\n", p2.d);

    let p3: Mat3 = mat3_mul(&m3, &n3);
    printf("mul3_00 = %.6f\n", p3.m00);
    printf("mul3_01 = %.6f\n", p3.m01);
    printf("mul3_02 = %.6f\n", p3.m02);
    printf("mul3_10 = %.6f\n", p3.m10);
    printf("mul3_11 = %.6f\n", p3.m11);
    printf("mul3_12 = %.6f\n", p3.m12);
    printf("mul3_20 = %.6f\n", p3.m20);
    printf("mul3_21 = %.6f\n", p3.m21);
    printf("mul3_22 = %.6f\n", p3.m22);

    let mv2: (f64, f64) = mat2_vec(&m2, 3.0, 7.0);
    printf("mv2_x = %.6f\n", mv2.0);
    printf("mv2_y = %.6f\n", mv2.1);

    let mv3: (f64, f64, f64) = mat3_vec(&m3, 1.0, 2.0, 0.0 - 2.0);
    printf("mv3_x = %.6f\n", mv3.0);
    printf("mv3_y = %.6f\n", mv3.1);
    printf("mv3_z = %.6f\n", mv3.2);

    let inv2: Mat2 = mat2_inv(&m2);
    printf("inv2_a = %.6f\n", inv2.a);
    printf("inv2_b = %.6f\n", inv2.b);
    printf("inv2_c = %.6f\n", inv2.c);
    printf("inv2_d = %.6f\n", inv2.d);

    let inv3: Mat3 = mat3_inv(&m3);
    printf("inv3_00 = %.6f\n", inv3.m00);
    printf("inv3_01 = %.6f\n", inv3.m01);
    printf("inv3_02 = %.6f\n", inv3.m02);
    printf("inv3_10 = %.6f\n", inv3.m10);
    printf("inv3_11 = %.6f\n", inv3.m11);
    printf("inv3_12 = %.6f\n", inv3.m12);
    printf("inv3_20 = %.6f\n", inv3.m20);
    printf("inv3_21 = %.6f\n", inv3.m21);
    printf("inv3_22 = %.6f\n", inv3.m22);

    let s2: (f64, f64) = mat2_solve(&m2, 13.0, 31.0);
    printf("solve2_x = %.6f\n", s2.0);
    printf("solve2_y = %.6f\n", s2.1);

    let s3: (f64, f64, f64) = mat3_solve(&m3, 14.0, 9.0, 17.0);
    printf("solve3_x = %.6f\n", s3.0);
    printf("solve3_y = %.6f\n", s3.1);
    printf("solve3_z = %.6f\n", s3.2);

    let id3: Mat3 = mat3_mul(&m3, &inv3);
    printf("re1_00 = %.6f\n", id3.m00);
    printf("re1_01 = %.6f\n", id3.m01);
    printf("re1_22 = %.6f\n", id3.m22);
    return 0;
}
