include "../../modules/http/sha1.rsx";
include "../../modules/http/sha512.rsx";

fn check(name: ptr<u8>, got: ptr<u8>, want: ptr<u8>) -> i32 {
    if (rt_eq(got, want) == 1) {
        return 1;
    }
    printf("%s FAIL\n   got  %s\n   want %s\n", name, got, want);
    return 0;
}

fn main() -> i32 {
    var ok: i32 = 0;
    var total: i32 = 0;
    var buf: [u8; 8192] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut buf[0] as ptr<u8>; }
    var h: [u8; 64] = [0];
    var hp: ptr<u8> = null;
    unsafe { hp = &mut h[0] as ptr<u8>; }
    var hex: [u8; 160] = [0];
    var hx: ptr<u8> = null;
    unsafe { hx = &mut hex[0] as ptr<u8>; }
    var i: i64 = 0;

    i = 0;
    while (i < 0) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 0, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_0", hx, "da39a3ee5e6b4b0d3255bfef95601890afd80709");
    total += 1;
    sha384(bp, 0, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_0", hx, "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b");
    total += 1;
    sha512(bp, 0, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_0", hx, "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e");
    total += 1;

    i = 0;
    while (i < 1) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 1, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_1", hx, "86f7e437faa5a7fce15d1ddcb9eaeaea377667b8");
    total += 1;
    sha384(bp, 1, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_1", hx, "54a59b9f22b0b80880d8427e548b7c23abd873486e1f035dce9cd697e85175033caa88e6d57bc35efae0b5afd3145f31");
    total += 1;
    sha512(bp, 1, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_1", hx, "1f40fc92da241694750979ee6cf582f2d5d7d28e18335de05abc54d0560e0f5302860c652bf08d560252aa5e74210546f369fbbbce8c12cfc7957b2652fe9a75");
    total += 1;

    i = 0;
    while (i < 3) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 3, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_3", hx, "7e240de74fb1ed08fa08d38063f6a6a91462a815");
    total += 1;
    sha384(bp, 3, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_3", hx, "8e07e5bdd64aa37536c1f257a6b44963cc327b7d7dcb2cb47a22073d33414462bfa184487cf372ce0a19dfc83f8336d8");
    total += 1;
    sha512(bp, 3, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_3", hx, "d6f644b19812e97b5d871658d6d3400ecd4787faeb9b8990c1e7608288664be77257104a58d033bcf1a0e0945ff06468ebe53e2dff36e248424c7273117dac09");
    total += 1;

    i = 0;
    while (i < 55) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 55, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_55", hx, "c1c8bbdc22796e28c0e15163d20899b65621d65a");
    total += 1;
    sha384(bp, 55, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_55", hx, "5d91ac7e74e62b5c728904b40f10784d66b7af9cb6302123e48c92f0432ceb8d2a92c02de77dcb29ed75c4b42bde46f4");
    total += 1;
    sha512(bp, 55, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_55", hx, "b0220c772cbf6c1822e2cb38a437d0e1d58772417a4bbb21c961364f8b6143e05aa6316dca8d1d7b19e16448419076395f6086cb55101fbd6d5497b148e1745f");
    total += 1;

    i = 0;
    while (i < 56) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 56, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_56", hx, "c2db330f6083854c99d4b5bfb6e8f29f201be699");
    total += 1;
    sha384(bp, 56, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_56", hx, "8a8d9649ea04e993a6ca7135af7e3392cc5fca84f8531cac7aa3feed4eb98f55dcbe0f3284b61c6f35f98b02cc644b4c");
    total += 1;
    sha512(bp, 56, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_56", hx, "962b64aae357d2a4fee3ded8b539bdc9d325081822b0bfc55583133aab44f18bafe11d72a7ae16c79ce2ba620ae2242d5144809161945f1367f41b3972e26e04");
    total += 1;

    i = 0;
    while (i < 57) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 57, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_57", hx, "f08f24908d682555111be7ff6f004e78283d989a");
    total += 1;
    sha384(bp, 57, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_57", hx, "5e872b76ee122b6d638d95a087344fded7836f53a3ff200aea18e3c9e952b2410ffb78b8b346dbd4d6bfe855d3fb7a91");
    total += 1;
    sha512(bp, 57, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_57", hx, "d3115798e872fc1ca6b276368e8ea0926daec6ab1f8f08297e4348ff5f5fe4c6e5205413271babafd4929b070754bc5800e5db44790666ec4e2f6ac52a17e163");
    total += 1;

    i = 0;
    while (i < 63) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 63, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_63", hx, "03f09f5b158a7a8cdad920bddc29b81c18a551f5");
    total += 1;
    sha384(bp, 63, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_63", hx, "7e7f097e95b52bb8f53383450ecaf9868187c130981730c03b6d573adfc0b991e365244e5b4bfa082bfb43c517d37120");
    total += 1;
    sha512(bp, 63, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_63", hx, "c1b0f5c6d3b03dfe4a2602e67242f54e344090b66e01100a469b129f583f016c7e27dddeaa438393dcc7ec54b0b57c9ba7af007f9b56db5f6fb677d972a31362");
    total += 1;

    i = 0;
    while (i < 64) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 64, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_64", hx, "0098ba824b5c16427bd7a1122a5a442a25ec644d");
    total += 1;
    sha384(bp, 64, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_64", hx, "2e404b9339da795776e510d96930b3be2904c500395b8cb7413334b82d4dec413b4b8113045a05bbbcff846f027423f6");
    total += 1;
    sha512(bp, 64, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_64", hx, "01d35c10c6c38c2dcf48f7eebb3235fb5ad74a65ec4cd016e2354c637a8fb49b695ef3c1d6f7ae4cd74d78cc9c9bcac9d4f23a73019998a7f73038a5c9b2dbde");
    total += 1;

    i = 0;
    while (i < 65) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 65, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_65", hx, "11655326c708d70319be2610e8a57d9a5b959d3b");
    total += 1;
    sha384(bp, 65, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_65", hx, "a2b797de45aa1d20594e2ea0cb1801d6dd7ffa3a58281c37dde04029f1c98157bb6eb005e90dd76b79a1d6ddd52dd58d");
    total += 1;
    sha512(bp, 65, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_65", hx, "b83086cd8494e55708ad7ecd82dfb4bca1bda61ecbb7caf0c68967902e709345e5d8305eb7ac0d588afc6cbb75161aa9c8c7e0ea986bd833dafe5e1ccd37345a");
    total += 1;

    i = 0;
    while (i < 127) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 127, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_127", hx, "89d95fa32ed44a7c610b7ee38517ddf57e0bb975");
    total += 1;
    sha384(bp, 127, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_127", hx, "9bd06b1763c2cf7aef40e795dc65bc96d59c41b537f3ad72ebdefd485476b5717c1aeb37c327fe9c1831b12b9efd08ae");
    total += 1;
    sha512(bp, 127, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_127", hx, "828613968b501dc00a97e08c73b118aa8876c26b8aac93df128502ab360f91bab50a51e088769a5c1eff4782ace147dce3642554199876374291f5d921629502");
    total += 1;

    i = 0;
    while (i < 128) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 128, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_128", hx, "ad5b3fdbcb526778c2839d2f151ea753995e26a0");
    total += 1;
    sha384(bp, 128, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_128", hx, "edb12730a366098b3b2beac75a3bef1b0969b15c48e2163c23d96994f8d1bef760c7e27f3c464d3829f56c0d53808b0b");
    total += 1;
    sha512(bp, 128, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_128", hx, "b73d1929aa615934e61a871596b3f3b33359f42b8175602e89f7e06e5f658a243667807ed300314b95cacdd579f3e33abdfbe351909519a846d465c59582f321");
    total += 1;

    i = 0;
    while (i < 129) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 129, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_129", hx, "d96debf1bdcbc896e6c134ea76e8141f40d78536");
    total += 1;
    sha384(bp, 129, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_129", hx, "39b6f5a7b0e781dbc419f72e49b30eaac10f2c98c4403bc610da31067fd1b48f324138c8615d2b496d08d73d5e865326");
    total += 1;
    sha512(bp, 129, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_129", hx, "4f681e0bd53cda4b5a2041cc8a06f2eabde44fb16c951fbd5b87702f07aeab611565b19c47fde30587177ebb852e3971bbd8d3fd30da18d71037dfbd98420429");
    total += 1;

    i = 0;
    while (i < 1000) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 1000, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_1000", hx, "291e9a6c66994949b57ba5e650361e98fc36b1ba");
    total += 1;
    sha384(bp, 1000, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_1000", hx, "f54480689c6b0b11d0303285d9a81b21a93bca6ba5a1b4472765dca4da45ee328082d469c650cd3b61b16d3266ab8ced");
    total += 1;
    sha512(bp, 1000, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_1000", hx, "67ba5535a46e3f86dbfbed8cbbaf0125c76ed549ff8b0b9e03e0c88cf90fa634fa7b12b47d77b694de488ace8d9a65967dc96df599727d3292a8d9d447709c97");
    total += 1;

    i = 0;
    while (i < 4096) {
        buf[i] = 97;
        i += 1;
    }
    sha1(bp, 4096, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_4096", hx, "8c51fb6a0b587ec95ca74acfa43df7539b486297");
    total += 1;
    sha384(bp, 4096, hp);
    rt_hex_str(hx, hp, 48);
    ok += check("sha384_4096", hx, "abc1d4d2d01083c290896b326969cbf848d806bc21dfe77e2af4e45d158770e94ab8f0d35575ef6f3d1a28ef13cef09e");
    total += 1;
    sha512(bp, 4096, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_4096", hx, "eb7040948a189a59d72d1e53869fba1aeacb6c3be33c7be5d1f03f31a9660033b2018649b33325b48b317944664d8e71a64a7c6f29dd18acf162c8b0d13a214e");
    total += 1;

    i = 0;
    while (i < 300) {
        buf[i] = 97;
        i += 1;
    }
    var c1: Sha1 = zero(Sha1);
    sha1_init(&mut c1);
    sha1_update(&mut c1, bp, 1);
    sha1_update(&mut c1, rt_add(bp, 1), 62);
    sha1_update(&mut c1, rt_add(bp, 63), 237);
    sha1_final(&mut c1, hp);
    rt_hex_str(hx, hp, 20);
    ok += check("sha1_stream", hx, "003ef1ba9ea9f2f4dab3a2004e505ca8a4e7e5a3");
    total += 1;

    var c2: Sha512 = zero(Sha512);
    sha512_init(&mut c2);
    sha512_update(&mut c2, bp, 127);
    sha512_update(&mut c2, rt_add(bp, 127), 1);
    sha512_update(&mut c2, rt_add(bp, 128), 172);
    sha512_final(&mut c2, hp);
    rt_hex_str(hx, hp, 64);
    ok += check("sha512_stream", hx, "a6a77010dd9696c23831e6549de51724df332c2075039b75fcfe6c2e6de42fbd3c80ed4073267e00c8c320712c3cdd9d65a96f90a3fe4a58a6b70a103be08e83");
    total += 1;

    printf("hash_passed=%d of %d\n", ok, total);
    if (ok == total) {
        return 0;
    }
    return 1;
}
