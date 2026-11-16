extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "kernel32" fn CreateProcessA(app: ptr<u8>, cmd: ptr<u8>, pa: ptr<u8>, ta: ptr<u8>, inherit: i32,
                                    flags: u32, env: ptr<u8>, cwd: ptr<u8>, si: ptr<u8>, pi: ptr<u8>) -> i32;
extern "kernel32" fn WaitForSingleObject(h: i64, ms: u32) -> u32;
extern "kernel32" fn GetExitCodeProcess(h: i64, code: ptr<u32>) -> i32;
extern "kernel32" fn CloseHandle(h: i64) -> i32;

struct C {
    si: [u8; 128],
    pi: [u8; 64],
    buf: [u8; 512]
}

fn copy(p: ptr<u8>, s: ptr<u8>) -> i64 {
    var i: i64 = 0;
    unsafe {
        while (s[i] != 0) {
            p[i] = s[i];
            i += 1;
        }
        p[i] = 0;
    }
    return i;
}

fn main() -> i32 {
    var c: C = zero(C);
    var sp: ptr<u8> = null;
    var pp: ptr<u8> = null;
    var bp: ptr<u8> = null;
    unsafe {
        sp = &mut c.si[0] as ptr<u8>;
        pp = &mut c.pi[0] as ptr<u8>;
        bp = &mut c.buf[0] as ptr<u8>;
    }
    copy(bp, "cmd.exe /c echo spawned-ok");
    var si: ptr<u8> = null;
    unsafe {
        si = &mut c.si[0] as ptr<u8>;
        c.si[0] = 104;
    }
    let ok: i32 = CreateProcessA(null, bp, null, null, 1, 0, null, null, si, pp);
    printf("create=%d\n", ok as i64);
    if (ok == 0) {
        return 3;
    }
    var h: i64 = 0;
    unsafe {
        h = pp[0] as i64;
    }
    printf("handle=%lld\n", h);
    WaitForSingleObject(h, 30000);
    var code: u32 = 0;
    var cp: ptr<u32> = null;
    unsafe {
        cp = &mut code as ptr<u32>;
    }
    GetExitCodeProcess(h, cp);
    printf("exit=%d\n", code as i64);
    CloseHandle(h);
    return 0;
}
