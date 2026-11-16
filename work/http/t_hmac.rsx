include "../../modules/http/rt.rsx";
include "../../modules/http/sha256.rsx";
include "../../modules/http/hmac.rsx";

fn hx(name: ptr<u8>, got: ptr<u8>, n: i64, want: ptr<u8>) -> i32 {
    var buf: [u8; 160] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut buf[0] as ptr<u8>; }
    rt_hex_str(bp, got, n);
    if (rt_eq(bp, want) == 1) {
        printf("%s ok\n", name);
        return 1;
    }
    printf("%s FAIL %s\n   want %s\n", name, bp, want);
    return 0;
}

fn main() -> i32 {
    var ok: i32 = 0;
    var out: [u8; 32] = [0];
    var op: ptr<u8> = null;
    unsafe { op = &mut out[0] as ptr<u8>; }

    hmac_sha256("key", 3, "The quick brown fox jumps over the lazy dog", 43, op);
    ok += hx("hmac_case1", op, 32, "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8");

    hmac_sha256("Jefe", 4, "what do ya want for nothing?", 28, op);
    ok += hx("hmac_case2", op, 32, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");

    var k3: [u8; 20] = [0];
    var d3: [u8; 50] = [0];
    var i: i64 = 0;
    while (i < 20) {
        k3[i] = 170;
        i += 1;
    }
    i = 0;
    while (i < 50) {
        d3[i] = 221;
        i += 1;
    }
    var k3p: ptr<u8> = null;
    var d3p: ptr<u8> = null;
    unsafe {
        k3p = &mut k3[0] as ptr<u8>;
        d3p = &mut d3[0] as ptr<u8>;
    }
    hmac_sha256(k3p, 20, d3p, 50, op);
    ok += hx("hmac_case3", op, 32, "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe");

    var ikm: [u8; 22] = [0];
    i = 0;
    while (i < 22) {
        ikm[i] = 11;
        i += 1;
    }
    var salt: [u8; 13] = [0];
    i = 0;
    while (i < 13) {
        salt[i] = i as u8;
        i += 1;
    }
    var info: [u8; 10] = [0];
    i = 0;
    while (i < 10) {
        info[i] = (240 + i) as u8;
        i += 1;
    }
    var ikmp: ptr<u8> = null;
    var saltp: ptr<u8> = null;
    var infop: ptr<u8> = null;
    unsafe {
        ikmp = &mut ikm[0] as ptr<u8>;
        saltp = &mut salt[0] as ptr<u8>;
        infop = &mut info[0] as ptr<u8>;
    }

    var prk: [u8; 32] = [0];
    var prkp: ptr<u8> = null;
    unsafe { prkp = &mut prk[0] as ptr<u8>; }
    hkdf_extract(saltp, 13, ikmp, 22, prkp);
    ok += hx("hkdf_prk", prkp, 32, "077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5");

    var okm: [u8; 42] = [0];
    var okmp: ptr<u8> = null;
    unsafe { okmp = &mut okm[0] as ptr<u8>; }
    hkdf_expand(prkp, 32, infop, 10, okmp, 42);
    ok += hx("hkdf_okm", okmp, 42, "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865");

    printf("hmac_hkdf_passed=%d of 5\n", ok);
    if (ok == 5) {
        return 0;
    }
    return 1;
}
