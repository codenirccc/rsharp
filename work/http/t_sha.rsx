// work/http/t_sha.rsx — SHA-256 against the FIPS 180-4 / NIST vectors.
include "../../modules/http/rt.rsx";
include "../../modules/http/sha256.rsx";

fn hexwrite(out: ptr<u8>, inb: ptr<u8>, n: i64) {
    rt_hex_str(out, inb, n);
}

fn check(name: ptr<u8>, msg: ptr<u8>, len: i64, want: ptr<u8>) -> i32 {
    var d: [u8; 32] = [0];
    var dp: ptr<u8> = null;
    unsafe { dp = &mut d[0] as ptr<u8>; }
    sha256(msg, len, dp);

    var hx: [u8; 80] = [0];
    var hp: ptr<u8> = null;
    unsafe { hp = &mut hx[0] as ptr<u8>; }
    hexwrite(hp, dp, 32);
    let same: i32 = strcmp(hp, want);
    if (same == 0) {
        printf("%s ok\n", name);
        return 1;
    }
    printf("%s FAIL got %s want %s\n", name, hp, want);
    return 0;
}

fn main() -> i32 {
    var ok: i32 = 0;
    ok += check("empty", "", 0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    ok += check("abc", "abc", 3, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    ok += check("448bit", "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56,
                "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");

    // streaming in uneven pieces must equal the one-shot digest
    var c: Sha256 = zero(Sha256);
    sha256_init(&mut c);
    sha256_update(&mut c, "abc", 3);
    sha256_update(&mut c, "defghijklmnopqrstuvwxyz", 23);
    sha256_update(&mut c, "0123456789", 10);
    var d2: [u8; 32] = [0];
    var d2p: ptr<u8> = null;
    unsafe { d2p = &mut d2[0] as ptr<u8>; }
    sha256_final(&mut c, d2p);

    var one: [u8; 32] = [0];
    var onep: ptr<u8> = null;
    unsafe { onep = &mut one[0] as ptr<u8>; }
    sha256("abcdefghijklmnopqrstuvwxyz0123456789", 36, onep);

    var s: i32 = 1;
    var j: i64 = 0;
    while (j < 32) {
        unsafe {
            if (d2[j] != one[j]) {
                s = 0;
            }
        }
        j += 1;
    }
    printf("stream_split_equal=%d\n", s);
    ok += s;

    // 1,000,000 'a' — the long vector, streamed in 1000-byte chunks
    var big: [u8; 1000] = [0];
    var i2: i64 = 0;
    while (i2 < 1000) {
        big[i2] = 97;
        i2 += 1;
    }
    var cb: Sha256 = zero(Sha256);
    sha256_init(&mut cb);
    var bp2: ptr<u8> = null;
    unsafe { bp2 = &mut big[0] as ptr<u8>; }
    var k: i64 = 0;
    while (k < 1000) {
        sha256_update(&mut cb, bp2, 1000);
        k += 1;
    }
    var d3: [u8; 32] = [0];
    var d3p: ptr<u8> = null;
    unsafe { d3p = &mut d3[0] as ptr<u8>; }
    sha256_final(&mut cb, d3p);

    var hx2: [u8; 80] = [0];
    var hp2: ptr<u8> = null;
    unsafe { hp2 = &mut hx2[0] as ptr<u8>; }
    hexwrite(hp2, d3p, 32);
    let m: i32 = strcmp(hp2, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
    if (m == 0) {
        printf("million_a ok\n");
        ok += 1;
    } else {
        printf("million_a FAIL %s\n", hp2);
    }

    printf("sha256_passed=%d of 5\n", ok);
    if (ok == 5) {
        return 0;
    }
    return 1;
}
