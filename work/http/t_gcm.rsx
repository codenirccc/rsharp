// work/http/t_gcm.rsx — AES-128-GCM against NIST SP 800-38D test cases 1-4.
include "../../modules/http/rt.rsx";
include "../../modules/http/aes_gcm.rsx";

fn eqhex(name: ptr<u8>, got: ptr<u8>, n: i64, want: ptr<u8>) -> i32 {
    var buf: [u8; 400] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut buf[0] as ptr<u8>; }
    rt_hex_str(bp, got, n);
    if (rt_eq(bp, want) == 1) {
        printf("%s ok\n", name);
        return 1;
    }
    printf("%s FAIL\n   got  %s\n   want %s\n", name, bp, want);
    return 0;
}

fn main() -> i32 {
    var ok: i32 = 0;
    var key: [u8; 16] = [0];
    var iv: [u8; 16] = [0];
    var pt: [u8; 80] = [0];
    var aad: [u8; 32] = [0];
    var ct: [u8; 80] = [0];
    var tag: [u8; 16] = [0];
    var back: [u8; 80] = [0];

    var kp: ptr<u8> = null;
    var ip: ptr<u8> = null;
    var pp: ptr<u8> = null;
    var ap: ptr<u8> = null;
    var cp: ptr<u8> = null;
    var tp: ptr<u8> = null;
    var bk: ptr<u8> = null;
    unsafe {
        kp = &mut key[0] as ptr<u8>;
        ip = &mut iv[0] as ptr<u8>;
        pp = &mut pt[0] as ptr<u8>;
        ap = &mut aad[0] as ptr<u8>;
        cp = &mut ct[0] as ptr<u8>;
        tp = &mut tag[0] as ptr<u8>;
        bk = &mut back[0] as ptr<u8>;
    }

    var ks: Aes128 = zero(Aes128);

    // Case 1 — empty plaintext, empty AAD, zero key, zero nonce.
    rt_parse_hex("00000000000000000000000000000000", kp, 16);
    rt_parse_hex("000000000000000000000000", ip, 12);
    aes128_init(&mut ks, kp);
    aes128_gcm_seal(&ks, ip, ap, 0, pp, 0, cp, tp);
    ok += eqhex("gcm_case1_t", tp, 16, "58e2fccefa7e3061367f1d57a4e7455a");

    // Case 2 — one zero block.
    rt_parse_hex("00000000000000000000000000000000", pp, 16);
    aes128_gcm_seal(&ks, ip, ap, 0, pp, 16, cp, tp);
    ok += eqhex("gcm_case2_c", cp, 16, "0388dace60b6a392f328c2b971b2fe78");
    ok += eqhex("gcm_case2_t", tp, 16, "ab6e47d42cec13bdf53a67b21257bddf");

    // Case 3 — 64 bytes, no AAD.
    rt_parse_hex("feffe9928665731c6d6a8f9467308308", kp, 16);
    rt_parse_hex("cafebabefacedbaddecaf888", ip, 12);
    let n3: i64 = rt_parse_hex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255", pp, 80);
    aes128_init(&mut ks, kp);
    aes128_gcm_seal(&ks, ip, ap, 0, pp, n3, cp, tp);
    ok += eqhex("gcm_case3_c", cp, n3, "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985");
    ok += eqhex("gcm_case3_t", tp, 16, "4d5c2af327cd64a62cf35abd2ba6fab4");

    // Opening that ciphertext must return the plaintext unchanged.
    let opn: i32 = aes128_gcm_open(&ks, ip, ap, 0, cp, n3, bk, tp);
    var same: i32 = 1;
    if (opn != 0) {
        same = 0;
    }
    var i: i64 = 0;
    while (i < n3) {
        unsafe {
            if (pt[i] != back[i]) {
                same = 0;
            }
        }
        i += 1;
    }
    printf("gcm_roundtrip=%d\n", same);
    ok += same;

    // Case 4 — 60 bytes (case 3 truncated by 4) plus 20 bytes of AAD.
    let na: i64 = rt_parse_hex("feedfacedeadbeeffeedfacedeadbeefabaddad2", ap, 32);
    aes128_gcm_seal(&ks, ip, ap, na, pp, 60, cp, tp);
    ok += eqhex("gcm_case4_c", cp, 60, "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091");
    ok += eqhex("gcm_case4_t", tp, 16, "5bc94fbc3221a5db94fae95ae7121a47");

    // A flipped tag byte must be rejected.
    var badtag: [u8; 16] = [0];
    var btp: ptr<u8> = null;
    unsafe {
        btp = &mut badtag[0] as ptr<u8>;
        rt_copy(btp, tp, 16);
        badtag[0] = (badtag[0] ^ 1) as u8;
    }
    let rej: i32 = aes128_gcm_open(&ks, ip, ap, na, cp, 60, bk, btp);
    printf("gcm_reject_bad_tag=%d\n", rej);
    if (rej != 0) {
        ok += 1;
    }

    printf("gcm_passed=%d of 9\n", ok);
    if (ok == 9) {
        return 0;
    }
    return 1;
}
