// work/http/t_x25519.rsx — RFC 7748 §5.2 vectors and the §6.1 DH exchange.
include "../../modules/http/rt.rsx";
include "../../modules/http/x25519.rsx";

// RFC 7748 publishes the scalars and u-coordinates as the byte strings that
// X25519 consumes directly, so the hex is copied in order: no reversal here.
fn bytes_from_hex(out: ptr<u8>, s: ptr<u8>) -> i64 {
    var buf: [u8; 64] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut buf[0] as ptr<u8>; }
    let n: i64 = rt_parse_hex(s, bp, 64);
    var i: i64 = 0;
    while (i < n) {
        var b: u8 = 0;
        unsafe { b = buf[i]; }
        unsafe { out[i] = b; }
        i += 1;
    }
    return n;
}

fn le_eq(name: ptr<u8>, got: ptr<u8>, want_hex: ptr<u8>) -> i32 {
    // The RFC prints u-coordinates as the little-endian byte string, which is
    // exactly what x25519 writes, so the comparison is byte-for-byte in hex.
    var hex: [u8; 80] = [0];
    var hp: ptr<u8> = null;
    unsafe { hp = &mut hex[0] as ptr<u8>; }
    rt_hex_str(hp, got, 32);
    if (rt_eq(hp, want_hex) == 1) {
        printf("%s ok\n", name);
        return 1;
    }
    printf("%s FAIL\n   got  %s\n   want %s\n", name, hp, want_hex);
    return 0;
}

fn main() -> i32 {
    var ok: i32 = 0;

    var sc: [u8; 32] = [0];
    var u: [u8; 32] = [0];
    var out: [u8; 32] = [0];
    var scp: ptr<u8> = null;
    var up: ptr<u8> = null;
    var op: ptr<u8> = null;
    unsafe {
        scp = &mut sc[0] as ptr<u8>;
        up = &mut u[0] as ptr<u8>;
        op = &mut out[0] as ptr<u8>;
    }

    // §5.2 vector 1
    bytes_from_hex(scp, "a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4");
    bytes_from_hex(up, "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c");
    x25519(op, scp, up);
    ok += le_eq("rfc7748_v1", op, "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552");

    // §5.2 vector 2
    bytes_from_hex(scp, "4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d");
    bytes_from_hex(up, "e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493");
    x25519(op, scp, up);
    ok += le_eq("rfc7748_v2", op, "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957");

    // §6.1: Alice and Bob agree.
    var alice_priv: [u8; 32] = [0];
    var bob_priv: [u8; 32] = [0];
    var alice_pub: [u8; 32] = [0];
    var bob_pub: [u8; 32] = [0];
    var shared_a: [u8; 32] = [0];
    var shared_b: [u8; 32] = [0];
    var ap: ptr<u8> = null;
    var bp: ptr<u8> = null;
    var apub: ptr<u8> = null;
    var bpub: ptr<u8> = null;
    var sa: ptr<u8> = null;
    var sb: ptr<u8> = null;
    unsafe {
        ap = &mut alice_priv[0] as ptr<u8>;
        bp = &mut bob_priv[0] as ptr<u8>;
        apub = &mut alice_pub[0] as ptr<u8>;
        bpub = &mut bob_pub[0] as ptr<u8>;
        sa = &mut shared_a[0] as ptr<u8>;
        sb = &mut shared_b[0] as ptr<u8>;
    }

    bytes_from_hex(ap, "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");
    bytes_from_hex(bp, "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb");
    x25519_base(apub, ap);
    ok += le_eq("rfc7748_alice_pub", apub, "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a");
    x25519_base(bpub, bp);
    ok += le_eq("rfc7748_bob_pub", bpub, "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f");

    x25519(sa, ap, bpub);
    x25519(sb, bp, apub);
    ok += le_eq("rfc7748_shared", sa, "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742");

    var same: i32 = 1;
    var i: i64 = 0;
    while (i < 32) {
        if (shared_a[i] != shared_b[i]) {
            same = 0;
        }
        i += 1;
    }
    printf("dh_agree=%d\n", same);
    ok += same;

    // Clamping sets and clears the right bits.
    var cl: [u8; 32] = [0];
    var clp: ptr<u8> = null;
    unsafe { clp = &mut cl[0] as ptr<u8>; }
    i = 0;
    while (i < 32) {
        cl[i] = 255;
        i += 1;
    }
    x25519_clamp(clp);
    if (cl[0] == 248 && cl[31] == 127) {
        printf("clamp ok\n");
        ok += 1;
    } else {
        printf("clamp FAIL %u %u\n", cl[0] as u32, cl[31] as u32);
    }

    printf("x25519_passed=%d of 7\n", ok);
    if (ok == 7) {
        return 0;
    }
    return 1;
}
