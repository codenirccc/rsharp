include "../../modules/dotnet/dotnet.rsx";

fn str_eq(a: ptr<u8>, b: ptr<u8>) -> bool {
    unsafe {
        var i: i64 = 0;
        while (a[i] != 0 || b[i] != 0) {
            if (a[i] != b[i]) {
                return false;
            }
            i += 1;
        }
        return true;
    }
}

fn ck(name: ptr<u8>, ok: bool) -> i64 {
    if (ok) {
        return 0;
    }
    printf("clr: fail %s\n", name);
    return 1;
}

fn ck_i32(name: ptr<u8>, got: i32, want: i32) -> i64 {
    if (got == want) {
        return 0;
    }
    printf("clr: fail %s got %d want %d\n", name, got, want);
    return 1;
}

fn ck_i64(name: ptr<u8>, got: i64, want: i64) -> i64 {
    if (got == want) {
        return 0;
    }
    printf("clr: fail %s got %lld want %lld\n", name, got, want);
    return 1;
}

fn ck_f64(name: ptr<u8>, got: f64, want: f64) -> i64 {
    if (got == want) {
        return 0;
    }
    printf("clr: fail %s got %.17g want %.17g\n", name, got, want);
    return 1;
}

fn main() -> i32 {
    var fails: i64 = 0;
    var u16buf: [u16; 128] = [0];
    var u8buf: [u8; 256] = [0];
    var round: [u16; 128] = [0];
    var round8: [u8; 256] = [0];

    var host: ClrHost = clr_host_open("fixture/bin/Release/net10.0/fixture.runtimeconfig.json" as ptr<u8>);
    if (!clr_host_ready(&host)) {
        printf("clr: host did not open\n");
        return 1;
    }

    let asm: ptr<u8> = "fixture/bin/Release/net10.0/fixture.dll" as ptr<u8>;
    let tn: ptr<u8> = "rsharp_dotnet_fixture.Fixture, fixture" as ptr<u8>;

    var add_p: ptr<u8> = clr_host_find(&host, asm, tn, "Add" as ptr<u8>, "rsharp_dotnet_fixture.AddDelegate, fixture" as ptr<u8>);
    var mul_p: ptr<u8> = clr_host_find(&host, asm, tn, "Mul" as ptr<u8>, "rsharp_dotnet_fixture.AddDelegate, fixture" as ptr<u8>);
    var sum_p: ptr<u8> = clr_host_find(&host, asm, tn, "SumTo" as ptr<u8>, "rsharp_dotnet_fixture.SumDelegate, fixture" as ptr<u8>);
    var echo_p: ptr<u8> = clr_host_find(&host, asm, tn, "Echo64" as ptr<u8>, "rsharp_dotnet_fixture.EchoDelegate, fixture" as ptr<u8>);
    var scale_p: ptr<u8> = clr_host_find(&host, asm, tn, "Scale" as ptr<u8>, "rsharp_dotnet_fixture.ScaleDelegate, fixture" as ptr<u8>);
    var fill_p: ptr<u8> = clr_host_find(&host, asm, tn, "Fill" as ptr<u8>, "rsharp_dotnet_fixture.FillDelegate, fixture" as ptr<u8>);
    var twice_p: ptr<u8> = clr_host_find(&host, asm, tn, "Twice" as ptr<u8>, null);
    var pack_p: ptr<u8> = clr_host_find(&host, asm, tn, "Pack" as ptr<u8>, "rsharp_dotnet_fixture.PackDelegate, fixture" as ptr<u8>);
    var blend_p: ptr<u8> = clr_host_find(&host, asm, tn, "Blend" as ptr<u8>, "rsharp_dotnet_fixture.BlendDelegate, fixture" as ptr<u8>);

    fails += ck("resolve Add" as ptr<u8>, add_p != null);
    fails += ck("resolve Mul" as ptr<u8>, mul_p != null);
    fails += ck("resolve SumTo" as ptr<u8>, sum_p != null);
    fails += ck("resolve Echo64" as ptr<u8>, echo_p != null);
    fails += ck("resolve Scale" as ptr<u8>, scale_p != null);
    fails += ck("resolve Fill" as ptr<u8>, fill_p != null);
    fails += ck("resolve Twice" as ptr<u8>, twice_p != null);
    fails += ck("resolve Pack" as ptr<u8>, pack_p != null);
    fails += ck("resolve Blend" as ptr<u8>, blend_p != null);

    var arg: i64 = 0x1122334455667788;
    var want_echo: i64 = arg;
    want_echo = want_echo ^ 0x0F0F0F0F0F0F0F0F;

    unsafe {
        var add: extern fn(i32, i32) -> i32 = add_p as extern fn(i32, i32) -> i32;
        var mul: extern fn(i32, i32) -> i32 = mul_p as extern fn(i32, i32) -> i32;
        var sum: extern fn(i32) -> i32 = sum_p as extern fn(i32) -> i32;
        var echo: extern fn(i64) -> i64 = echo_p as extern fn(i64) -> i64;
        var scale: extern fn(f64, f64) -> f64 = scale_p as extern fn(f64, f64) -> f64;
        var fill: extern fn(ptr<u16>, i32) -> i32 = fill_p as extern fn(ptr<u16>, i32) -> i32;

        fails += ck_i32("Add(6, 7)" as ptr<u8>, add(6, 7), 13);
        fails += ck_i32("Mul(6, 7)" as ptr<u8>, mul(6, 7), 42);
        fails += ck_i32("SumTo(100)" as ptr<u8>, sum(100), 5050);
        fails += ck_i64("Echo64" as ptr<u8>, echo(arg), want_echo);
        fails += ck_f64("Scale(1.5, 4.0)" as ptr<u8>, scale(1.5, 4.0), 6.0);
        var twice: extern fn(i32) -> i32 = twice_p as extern fn(i32) -> i32;
        fails += ck_i32("Twice(21)" as ptr<u8>, twice(21), 42);
        var pack: extern fn(i32, i32, i32, i32, i32, i32) -> i32 = pack_p as extern fn(i32, i32, i32, i32, i32, i32) -> i32;
        fails += ck_i32("Pack(1..6)" as ptr<u8>, pack(1, 2, 3, 4, 5, 6), 123456);
        var blend: extern fn(f64, i32, f64, i32, f64) -> f64 = blend_p as extern fn(f64, i32, f64, i32, f64) -> f64;
        fails += ck_f64("Blend(1.5, 2, 2.5, 3, 3.5)" as ptr<u8>, blend(1.5, 2, 2.5, 3, 3.5), 31.5);

        let up: ptr<u16> = &u16buf[0] as ptr<u16>;
        let bp: ptr<u8> = &u8buf[0] as ptr<u8>;
        let rc: i32 = fill(up, 128);
        fails += ck_i32("Fill length" as ptr<u8>, rc, 18);
        let n: i64 = clr_utf16_to_utf8(up, bp, 256);
        fails += ck_i64("Fill decode length" as ptr<u8>, n, 22);
        fails += ck("Fill text" as ptr<u8>, str_eq(bp, "Hello from .NET 世界" as ptr<u8>));

        let src: ptr<u8> = "a\360\237\230\200e\314\201" as ptr<u8>;
        let r16: ptr<u16> = &round[0] as ptr<u16>;
        let r8: ptr<u8> = &round8[0] as ptr<u8>;
        let units: i64 = clr_utf8_to_utf16(src, r16, 128);
        fails += ck_i64("roundtrip units" as ptr<u8>, units, 5);
        let back: i64 = clr_utf16_to_utf8(r16, r8, 256);
        fails += ck_i64("roundtrip bytes" as ptr<u8>, back, 8);
        fails += ck("roundtrip text" as ptr<u8>, str_eq(r8, src));

        var tiny: [u16; 4] = [0];
        var small: [u8; 4] = [0];
        let tp8: ptr<u16> = &tiny[0] as ptr<u16>;
        let sp8: ptr<u8> = &small[0] as ptr<u8>;
        fails += ck_i64("exact fit" as ptr<u8>, clr_utf8_to_utf16("abc" as ptr<u8>, tp8, 4), 3);
        fails += ck_i64("exact fit term" as ptr<u8>, tiny[3] as i64, 0);
        fails += ck_i64("u8 exact fit" as ptr<u8>, clr_utf16_to_utf8(tp8, sp8, 4), 3);
        fails += ck_i64("u8 exact fit term" as ptr<u8>, small[3] as i64, 0);
        fails += ck_i64("overflow" as ptr<u8>, clr_utf8_to_utf16("abcd" as ptr<u8>, tp8, 4), 0 - 1);
        fails += ck_i64("overflow kept" as ptr<u8>, tiny[3] as i64, 0);
        fails += ck_i64("u8 overflow" as ptr<u8>, clr_utf16_to_utf8(tp8, sp8, 3), 0 - 1);
        fails += ck_i64("zero cap" as ptr<u8>, clr_utf8_to_utf16("a" as ptr<u8>, tp8, 0), 0 - 1);
        var bad1: [u8; 4] = [0];
        var bad2: [u8; 4] = [0];
        var bad3: [u8; 4] = [0];
        var bad4: [u8; 4] = [0];
        bad1[0] = 0xC3;
        bad2[0] = 0x80;
        bad3[0] = 0xC0;
        bad3[1] = 0xAF;
        bad4[0] = 0xF0;
        bad4[1] = 0x9F;
        fails += ck_i64("bad continuation" as ptr<u8>, clr_utf8_to_utf16(&bad1[0] as ptr<u8>, tp8, 4), 0 - 2);
        fails += ck_i64("bad lead" as ptr<u8>, clr_utf8_to_utf16(&bad2[0] as ptr<u8>, tp8, 4), 0 - 2);
        fails += ck_i64("overlong" as ptr<u8>, clr_utf8_to_utf16(&bad3[0] as ptr<u8>, tp8, 4), 0 - 2);
        fails += ck_i64("truncated 4" as ptr<u8>, clr_utf8_to_utf16(&bad4[0] as ptr<u8>, tp8, 4), 0 - 2);

        var putbuf: [u8; 4] = [0];
        var putoff: [i64; 1] = [0];
        let pp8: ptr<u8> = &putbuf[0] as ptr<u8>;
        let op8: ptr<i64> = &mut putoff[0] as ptr<i64>;
        fails += ck_i64("put fit" as ptr<u8>, clr_str_put(pp8, 4, op8, "abc" as ptr<u8>), 1);
        fails += ck_i64("put term" as ptr<u8>, putbuf[3] as i64, 0);
        fails += ck_i64("put overflow" as ptr<u8>, clr_str_put(pp8, 4, op8, "d" as ptr<u8>), 0);
        fails += ck_i64("put kept" as ptr<u8>, putbuf[3] as i64, 0);
    }

    clr_host_close(&mut host);
    fails += ck("host closed" as ptr<u8>, host.handle == null && host.module == null);

    if (fails == 0) {
        printf("dotnet suite: ok\n");
        return 0;
    }
    printf("dotnet suite: FAIL %lld\n", fails);
    return 1;
}
