include "../../modules/http/rsa.rsx";

fn load(out: ptr<u8>, s: ptr<u8>, maxn: i64) -> i64 {
    return rt_parse_hex(s, out, maxn);
}

fn check(name: ptr<u8>, got: i64, want: i64) -> i32 {
    if (got == want) {
        printf("%s ok\n", name);
        return 1;
    }
    printf("%s FAIL got=%lld want=%lld\n", name, got, want);
    return 0;
}

fn main() -> i32 {
    var ok: i32 = 0;
    var total: i32 = 0;

    var pk: [u8; 1024] = [0];
    var pkp: ptr<u8> = null;
    unsafe { pkp = &mut pk[0] as ptr<u8>; }
    let pkn: i64 = load(pkp, "30820122300d06092a864886f70d01010105000382010f003082010a0282010100ccc7a5faeb9432cb9259518ebb742407fe8c99943705f3cc53d8ffbf00b9306d58169ee146c53335f17e1e0f60b8969329cf3d87dde2dfefb14944990a5c4ad9e056058c7c4d6acfb2f93d0daaf67da96694380568a461f2ab4b0402404dd0c2c8e6b5a657f34ef9dd72f93b548d2749a5261549b6950fced254e6151f09398b10d11555a817285455c0674eec3294b2274e95e6bee697f364433946bb7a048a08f8dfce3c5f4a3ce4bca80c50461892a15c7eaeadcbec16e7f88165cc7e2bb4069a14ae0cce02f145ef141a403c2a1987f36404c28be7718fe3e4d83d3fdc275b38324a1e17d4f0df8acc682f3d523251dbbdbd3bfdc81555a9ef2dfeb8aaf70203010001", 1024);
    var key: RsaKey = zero(RsaKey);
    ok += check("load_ca_spki", rsa_load(pkp, pkn, &mut key) as i64, 0);
    total += 1;
    ok += check("modulus_bytes", key.nbytes, 256);
    total += 1;

    var tbs: [u8; 1024] = [0];
    var tbl: i64 = 0;
    var tsp: ptr<u8> = null;
    unsafe { tsp = &mut tbs[0] as ptr<u8>; }
    tbl = load(tsp, "308201e1a00302010202080fedcba987654321300d06092a864886f70d01010b0500302a3113301106035504030c0a5223205465737420434131133011060355040a0c0a6f6c6c74617465726678301e170d3234303630313030303030305a170d3236303630313030303030305a30143112301006035504030c096c6561662e7465737430820122300d06092a864886f70d01010105000382010f003082010a0282010100c0eb1a2115f1c4b16c69a063f6570f69e2ad8dd3e797080a3503bd1d280f94d5cc80272f4620ddebce46ca045fd5549b7f15980f32492d107b8cc7f3c048d874be387db809edb61cfbf7d887d2b2ce095cefe4461dc62db20387eb4548db37c3f339de47db91abe8806e982a274dfcba44b3fe4253054da68b069c9e1f2c33806e1eab5bab77c11de1eccf533570f5690f8ed2328eed162e89ba7339efb771f849604da49726917e9bd7e8f784b82d50f546c9e7c33d9aa9c45e0e8623473bbc09f5e3f7cdb8b66121c1cae0daedad4d20f449975cd3b84125eeebc9569790bbea9a88f0920a3240a697c77119b36b2765a1918e2dbe22218ecc9736015fb4b70203010001a3393037300c0603551d130101ff0402300030170603551d110410300e820c6578616d706c652e74657374300e0603551d0f0101ff0404030205a0", 1024);
    var sg: [u8; 512] = [0];
    var sgp: ptr<u8> = null;
    unsafe { sgp = &mut sg[0] as ptr<u8>; }
    let sgl: i64 = load(sgp, "40dcfc230cd01feebef09e7491cf4d6c8aed5c137dc42c5ca77348729360942cd08e0e6ff7ed71cccce4d45fbaff6bbfddaf21d6b68c3538c13f25d167399fb1c673a7f2389376d3d982cc1651e97682dc9cf7e4a85e71748ea674f468ed2b41cb7b81ce41995e20e0bd2a9435bf667fca569ce537bf16359ae43d9052d0a735c6cf1032467eacfb4d617927a3266b3c04254595d6acad0d773168a64863229a891df02896c16de9be0ce095eee7f9c9a617fe62b117bf3a22c4019e378623bede9427e3d0649d5a7ce88ca4a4bc410ff9c5459a5835bb5d81e9a38fce19a964ae361613bd292896929dc01c47dc1daf3369103c12efbba0e46c328f881a5124", 512);

    var h: [u8; 32] = [0];
    var hp: ptr<u8> = null;
    unsafe { hp = &mut h[0] as ptr<u8>; }
    sha256(tsp, tbl, hp);
    ok += check("pkcs1_good", rsa_pkcs1_verify(&mut key, hp, 32, sgp, sgl) as i64, 1);
    total += 1;

    var h2: [u8; 32] = [0];
    var h2p: ptr<u8> = null;
    unsafe { h2p = &mut h2[0] as ptr<u8>; }
    rt_copy(h2p, hp, 32);
    h2[7] = (h2[7] ^ 1) as u8;
    ok += check("pkcs1_bad_hash", rsa_pkcs1_verify(&mut key, h2p, 32, sgp, sgl) as i64, 0);
    total += 1;

    var sg2: [u8; 512] = [0];
    var sg2p: ptr<u8> = null;
    unsafe { sg2p = &mut sg2[0] as ptr<u8>; }
    rt_copy(sg2p, sgp, sgl);
    sg2[0] = (sg2[0] ^ 128) as u8;
    ok += check("pkcs1_bad_sig", rsa_pkcs1_verify(&mut key, hp, 32, sg2p, sgl) as i64, 0);
    total += 1;

    var lpk: [u8; 1024] = [0];
    var lpkp: ptr<u8> = null;
    unsafe { lpkp = &mut lpk[0] as ptr<u8>; }
    let lpkn: i64 = load(lpkp, "30820122300d06092a864886f70d01010105000382010f003082010a0282010100c0eb1a2115f1c4b16c69a063f6570f69e2ad8dd3e797080a3503bd1d280f94d5cc80272f4620ddebce46ca045fd5549b7f15980f32492d107b8cc7f3c048d874be387db809edb61cfbf7d887d2b2ce095cefe4461dc62db20387eb4548db37c3f339de47db91abe8806e982a274dfcba44b3fe4253054da68b069c9e1f2c33806e1eab5bab77c11de1eccf533570f5690f8ed2328eed162e89ba7339efb771f849604da49726917e9bd7e8f784b82d50f546c9e7c33d9aa9c45e0e8623473bbc09f5e3f7cdb8b66121c1cae0daedad4d20f449975cd3b84125eeebc9569790bbea9a88f0920a3240a697c77119b36b2765a1918e2dbe22218ecc9736015fb4b70203010001", 1024);
    var lkey: RsaKey = zero(RsaKey);
    ok += check("load_leaf_spki", rsa_load(lpkp, lpkn, &mut lkey) as i64, 0);
    total += 1;

    var mh: [u8; 32] = [0];
    var mhp: ptr<u8> = null;
    unsafe { mhp = &mut mh[0] as ptr<u8>; }
    load(mhp, "dd0f753f959a0896fdf2fd6155b6b4266204f3ca348c09afd7ff44b04ab3bdfe", 32);
    var psig: [u8; 512] = [0];
    var psigp: ptr<u8> = null;
    unsafe { psigp = &mut psig[0] as ptr<u8>; }
    let psigl: i64 = load(psigp, "8c60462594b728937d38b7d15dc59e8916cfc1b2255d33c7fb204151d1f89915a84627d86de66cf4b94c3efa36d4a1fc634e4d0e96bacd7e5669322dc0f3285aa7088c461129624edaf7522f90d2c4c1e689323c77b7992f80dc0b80c4b0805f23c7216f72b0f9ab05030514c5591d0575d3f9954328d226e3fc0bf98af8b3541834bf532b5937fd4d9075a3b70cd27bc86e981da227ab492a288092e343f6f8770f6ee9539591c63ef9c7a1e66a6cf4eda7f88014a18d2f773debaeca4667d37618a3a3d571ccbad5f2bec29495e909c66a50817257c9dc9d6a6bb68bd5de25a6276fec767fc2f9351f024f14e6c5aa6d2e3a752550007ed88167ac3349c208", 512);
    var po: i32 = rsa_pss_verify(&mut lkey, mhp, 32, psigp, psigl);
    ok += check("pss_good", po as i64, 1);
    total += 1;

    var bad: [u8; 32] = [0];
    var badp: ptr<u8> = null;
    unsafe { badp = &mut bad[0] as ptr<u8>; }
    rt_copy(badp, mhp, 32);
    bad[31] = (bad[31] ^ 2) as u8;
    ok += check("pss_bad_hash", rsa_pss_verify(&mut lkey, badp, 32, psigp, psigl) as i64, 0);
    total += 1;



    printf("rsa_passed=%d of %d\n", ok, total);
    if (ok == total) {
        return 0;
    }
    return 1;
}
