fn main() -> i32 {
    var b: [u8; 512] = [0];
    var p: ptr<u8> = null;
    unsafe {
        p = &mut b[0] as ptr<u8>;
    }
    let n: i64 = host_argc();
    host_err("probe");
    var i: i64 = 0;
    while (i < n) {
        host_arg(i, p, 512);
        host_out(p, host_len(p, 512));
        host_out("\n", 1);
        i += 1;
    }
    host_temp(p, 512);
    host_out(p, host_len(p, 512));
    host_self(p, 512);
    host_out("\n", 1);
    host_out(p, host_len(p, 512));
    host_out("\n", 1);
    let mem: ptr<u8> = host_grab(16);
    if (mem == null) {
        host_exit(1);
    }
    unsafe {
        mem[0] = 65;
    }
    host_out(mem, 1);
    host_out("\n", 1);
    return 0;
}
