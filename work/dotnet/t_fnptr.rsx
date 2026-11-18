include "../../modules/dotnet/dotnet.rsx";

struct Ops {
    add: extern fn(i32, i32) -> i32
}

struct ROps {
    f: fn(i64) -> i64
}

fn triple(x: i64) -> i64 {
    return x * 3;
}

fn apply(f: extern fn(i32, i32) -> i32, a: i32, b: i32) -> i32 {
    return f(a, b);
}

fn pick(f: extern fn(i32, i32) -> i32) -> extern fn(i32, i32) -> i32 {
    return f;
}

fn via_ref(o: &Ops) -> i32 {
    return o.add(5, 6);
}

fn main() -> i32 {
    var host: ClrHost = clr_host_open("fixture/bin/Release/net10.0/fixture.runtimeconfig.json" as ptr<u8>);
    if (!clr_host_ready(&host)) {
        printf("fnptr: host did not open\n");
        return 1;
    }
    let tn: ptr<u8> = "rsharp_dotnet_fixture.Fixture, fixture" as ptr<u8>;
    let asm: ptr<u8> = "fixture/bin/Release/net10.0/fixture.dll" as ptr<u8>;
    let del: ptr<u8> = "rsharp_dotnet_fixture.AddDelegate, fixture" as ptr<u8>;
    let add_p: ptr<u8> = clr_host_find(&host, asm, tn, "Add" as ptr<u8>, del);
    var fails: i32 = 0;
    unsafe {
        var add: extern fn(i32, i32) -> i32 = add_p as extern fn(i32, i32) -> i32;
        var ops: Ops = zero(Ops);
        ops.add = add;
        if (ops.add(2, 3) != 5) {
            printf("fnptr: field call\n");
            fails += 1;
        }
        if (apply(add, 4, 5) != 9) {
            printf("fnptr: param call\n");
            fails += 1;
        }
        let again: extern fn(i32, i32) -> i32 = pick(add);
        if (again(6, 7) != 13) {
            printf("fnptr: return call\n");
            fails += 1;
        }
        if (via_ref(&ops) != 11) {
            printf("fnptr: ref call\n");
            fails += 1;
        }
        var rops: ROps = zero(ROps);
        rops.f = triple;
        if (rops.f(4) != 12) {
            printf("fnptr: r# abi field call\n");
            fails += 1;
        }
        let one: ptr<u8> = add_p;
        if (one == null) {
            printf("fnptr: address\n");
            fails += 1;
        }
    }
    clr_host_close(&mut host);
    if (fails == 0) {
        printf("fnptr suite: ok\n");
        return 0;
    }
    return 1;
}
