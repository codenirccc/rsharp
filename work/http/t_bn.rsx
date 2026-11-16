include "../../modules/http/rt.rsx";
include "../../modules/http/bignum.rsx";

fn bn_from_hex(r: &mut Bn, s: ptr<u8>) {
    var tmp: [u8; 600] = [0];
    var tp: ptr<u8> = null;
    unsafe { tp = &mut tmp[0] as ptr<u8>; }
    let n: i64 = rt_parse_hex(s, tp, 600);
    bn_from_be(r, tp, n);
}

fn bn_hex(a: &mut Bn, out: ptr<u8>, bytes: i64) {
    var tmp: [u8; 600] = [0];
    var tp: ptr<u8> = null;
    unsafe { tp = &mut tmp[0] as ptr<u8>; }
    bn_to_be(a, tp, bytes);
    rt_hex_str(out, tp, bytes);
}

fn bn_u64(a: &mut Bn) -> u64 {
    var v: u64 = 0;
    if (a.n > 0) {
        v = a.d[0] as u64;
    }
    if (a.n > 1) {
        v = v | ((a.d[1] as u64) << 26);
    }
    if (a.n > 2) {
        v = v | ((a.d[2] as u64) << 52);
    }
    return v;
}

fn main() -> i32 {
    var ok: i32 = 0;

    var a: Bn = zero(Bn);
    var b: Bn = zero(Bn);
    var m: Bn = zero(Bn);
    var r: Bn = zero(Bn);

    bn_set_u64(&mut a, 2);
    bn_set_u64(&mut b, 10);
    bn_set_u64(&mut m, 1000);
    bn_modexp(&mut r, &mut a, &mut b, &mut m);
    let v1: u64 = bn_u64(&mut r);
    printf("modexp_2_10=%llu (want 24)\n", v1);
    if (v1 == 24) {
        ok += 1;
    }

    bn_set_u64(&mut a, 3);
    bn_set_u64(&mut b, 200);
    bn_set_u64(&mut m, 1000000007);
    bn_modexp(&mut r, &mut a, &mut b, &mut m);
    let v2: u64 = bn_u64(&mut r);
    printf("modexp_3_200=%llu (want 136318165)\n", v2);
    if (v2 == 136318165) {
        ok += 1;
    }

    bn_set_u64(&mut a, 12345);
    bn_set_u64(&mut b, 67890);
    bn_mul(&mut r, &mut a, &mut b);
    let v3: u64 = bn_u64(&mut r);
    printf("mul=%llu (want 838102050)\n", v3);
    if (v3 == 838102050) {
        ok += 1;
    }

    bn_set_u64(&mut a, 999999999);
    bn_set_u64(&mut b, 999999999);
    bn_add(&mut r, &mut a, &mut b);
    bn_set_u64(&mut m, 1000000007);
    bn_mod_self(&mut r, &mut m);
    let v4: u64 = bn_u64(&mut r);
    printf("add_mod=%llu (want 999999991)\n", v4);
    if (v4 == 999999991) {
        ok += 1;
    }

    var nn: Bn = zero(Bn);
    var bb: Bn = zero(Bn);
    var ee: Bn = zero(Bn);
    var rr: Bn = zero(Bn);
    bn_from_hex(&mut nn, "cb4d8474a3ea284d3bd0334684e55160320094ead7a94ded97491e2370c6a5b85387f61376c468aec7321cc007b37e14998092253deffa38e12b2b8f30b17d0b09208a650f3ebdd3102b938b8743feb6d4ea65d003d716849f8558a628518867a66b0d389d95847ebd299753a767779673f778aaf6fa5db8656abd72fb710734986e86cb0ab8ab67a26b7f62b1852f27e3eff9c0cf44dd3f89e7d15f17362f25244caf9c4dabb4817253edc6181879932fa91425cb0088539d2c67eda13ffe7979cb9e86830c71c2cdcc69292f45e678309d6b79965eda32dae445508201e2bd73ab48767734d7c1c7fde805ec99108ddb5b5fab8f4d3e27dda1494c73cf256d");
    bn_from_hex(&mut bb, "20f23ad91e24c9172d28e59271e86197d1e041967d7b0703b862511aa5886f5b02b6a5d9ce4b9aa9e594bc32bf98feba994fadb86333fac8afca0c7ee20127096256e8aa567edcf8a54ed69273b4cef28b33f5757479ff836ddfaaccc0b60c7846e79508981a85d5797e748b58bc3eec3b5df843e1eeed5c9ee83192f9d13ce878ad03df5839e1b2a80d1d512734853437a90223973bbcd191b947cfacf5424b6bdd67b2c44e763e9549e49431e60c1d53a354546fcada1324df3ad4af760382c73a2e213226913947806981a7d27762bde580c66886cb7fb23b9c8a7d6482cbf4775e3bd000d75adfa32c8a887a81a93a6673341a490cc7238bc55a0c21fcbc");
    bn_set_u64(&mut ee, 65537);
    bn_modexp(&mut rr, &mut bb, &mut ee, &mut nn);

    var got: [u8; 600] = [0];
    var gotp: ptr<u8> = null;
    unsafe { gotp = &mut got[0] as ptr<u8>; }
    bn_hex(&mut rr, gotp, 256);
    let want: ptr<u8> = "5e14e0dd852b755ee5001911278bf4a293b70535fe0e61800942d0cf972b8f9d4dc4d07136a40de674b1fe3b9c68cab42e8674f346dce348ceab9c674630eb522a233e49124665509b07de1b9952231251c4e56fa6a6534acd8bc4782814e8d13402f3e9b85b0ff181951c3db187d01b51c7af8ad6abf04b39ee7b7713e34e70948ce2dd4958b89a38979d8114e89c7de4910496efda4680ee4e119b05bdc622a6167af45287fcd6b227d58937a4fbdbde427539be27b17fc295d6cb88c3349673588c9afa4b2bc321a8bbcb59c39f61c86a1ac67b8fe46ac8d12b48bf0c7680dc0b539e7aacbc7c50d3fd1f6d1847aa322189347a661b73519e8d3f0e3f9c67";
    if (rt_eq(gotp, want) == 1) {
        printf("modexp_2048_65537 ok\n");
        ok += 1;
    } else {
        printf("modexp_2048_65537 FAIL\n   got  %s\n   want %s\n", gotp, want);
    }

    var rt1: Bn = zero(Bn);
    var buf: [u8; 32] = [0];
    var bufp: ptr<u8> = null;
    unsafe { bufp = &mut buf[0] as ptr<u8>; }
    bn_from_hex(&mut rt1, "0123456789abcdeffedcba987654321000112233445566778899aabbccddeeff");
    bn_to_be(&mut rt1, bufp, 32);
    var rt2: Bn = zero(Bn);
    bn_from_be(&mut rt2, bufp, 32);
    if (bn_cmp(&mut rt1, &mut rt2) == 0) {
        printf("bytes_roundtrip ok\n");
        ok += 1;
    } else {
        printf("bytes_roundtrip FAIL\n");
    }

    printf("bn_passed=%d of 6\n", ok);
    if (ok == 6) {
        return 0;
    }
    return 1;
}
