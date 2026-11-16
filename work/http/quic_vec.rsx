fn qvec_dcid_a() -> ptr<u8> {
    return "8394c8f03e515708";
}

fn qvec_dcid_b() -> ptr<u8> {
    return "c0ffee0001020304";
}

fn qvec_initial_a() -> ptr<u8> {
    return "7db5df06e7a69e432496adedb00851923595221596ae2ae9fb8115c1e9ed0a44";
}

fn qvec_client_secret_a() -> ptr<u8> {
    return "c00cf151ca5be075ed0ebfb5c80323c42d6b7db67881289af4008f1f6c357aea";
}

fn qvec_server_secret_a() -> ptr<u8> {
    return "3c199828fd139efd216c155ad844cc81fb82fa8d7446fa7d78be803acdda951b";
}

fn qvec_client_key_a() -> ptr<u8> {
    return "1f369613dd76d5467730efcbe3b1a22d";
}

fn qvec_client_iv_a() -> ptr<u8> {
    return "fa044b2f42a3fd3b46fb255c";
}

fn qvec_client_hp_a() -> ptr<u8> {
    return "9f50449e04a0e810283a1e9933adedd2";
}

fn qvec_server_key_a() -> ptr<u8> {
    return "cf3a5331653c364c88f0f379b6067e37";
}

fn qvec_server_iv_a() -> ptr<u8> {
    return "0ac1493ca1905853b0bba03e";
}

fn qvec_server_hp_a() -> ptr<u8> {
    return "c206b8d9b9f0f37644430b490eeaa314";
}

fn qvec_cases() -> i64 {
    return 3;
}

fn qvec_dcid(i: i64) -> ptr<u8> {
    var t: [ptr<u8>; 3] = [
        "8394c8f03e515708",
        "c0ffee0001020304",
        "8394c8f03e515708"
    ];
    if (i < 0 || i >= 3) {
        return "";
    }
    return t[i];
}

fn qvec_header(i: i64) -> ptr<u8> {
    var t: [ptr<u8>; 3] = [
        "c300000001088394c8f03e5157080000407700000002",
        "c10000000108c0ffee0001020304088394c8f03e5157080040531234",
        "408394c8f03e51570807"
    ];
    if (i < 0 || i >= 3) {
        return "";
    }
    return t[i];
}

fn qvec_payload(i: i64) -> ptr<u8> {
    var t: [ptr<u8>; 3] = [
        "06380068747470332d746573742d636c69656e7468656c6c6f2d627974657368747470332d746573742d636c69656e7468656c6c6f2d627974657300000000000000000000000000000000000000000000000000000000000000000000000000000000",
        "01000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
        "0170696e672d7061796c6f61640000000000000000"
    ];
    if (i < 0 || i >= 3) {
        return "";
    }
    return t[i];
}

fn qvec_packet(i: i64) -> ptr<u8> {
    var t: [ptr<u8>; 3] = [
        "c400000001088394c8f03e51570800004077717a2c82d1898914a21cef66c2665cc93f584ede88668f08e48eb9ae9e4ad1b1c6430c6d57470eebbe2e4e83cff87f4a63b2a96a7dd773e8863819ca3e77ffa643a3b75e4dc0173c6983db885a738fb7529ec4de9057ed1dee02c8bdfbb97c650e2b7acb05876c87433c0823b4cf2fde47cc8e55b91ba7",
        "c80000000108c0ffee0001020304088394c8f03e515708004053c7afaee038858be53709025fbaa6edd30e3b1ea751c1a4c797c67d30a6289e1ee75abe4083935c1a30f4775980bdeb541ea057f4111dc9a960a575c1dee18669315b85b69a6fc68ef418859b729384f9022d6a",
        "588394c8f03e51570880bb3118b16559887edea585b91da52159c6aad401d6c58a23aec96e08f728d246361a0a24cf"
    ];
    if (i < 0 || i >= 3) {
        return "";
    }
    return t[i];
}

fn qvec_pn(i: i64) -> i64 {
    var t: [i64; 3] = [2, 4660, 7];
    if (i < 0 || i >= 3) {
        return -1;
    }
    return t[i];
}

fn qvec_ty(i: i64) -> i32 {
    var t: [i32; 3] = [0, 0, -1];
    if (i < 0 || i >= 3) {
        return -2;
    }
    return t[i];
}

fn qvec_pnlen(i: i64) -> i64 {
    var t: [i64; 3] = [4, 2, 1];
    if (i < 0 || i >= 3) {
        return -1;
    }
    return t[i];
}

fn qvec_initial_b() -> ptr<u8> {
    return "1d7e7d3b5b3604c6f3515016970bed52d07cc587d79b9660f00b879f928e0b1c";
}
