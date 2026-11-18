include "base.rsx";

extern "kernel32" fn GetCommandLineA() -> ptr<u8>;
extern "kernel32" fn CreateFileA(path: ptr<u8>, access: u32, share: u32, sa: ptr<u8>, disp: u32,
                                 flags: u32, templ: ptr<u8>) -> i64;
extern "kernel32" fn GetFileSize(h: i64, high: ptr<u32>) -> u32;
extern "kernel32" fn ReadFile(h: i64, buf: ptr<u8>, want: u32, got: ptr<u32>, ov: ptr<u8>) -> i32;
extern "kernel32" fn WriteFile(h: i64, buf: ptr<u8>, n: u32, wrote: ptr<u32>, ov: ptr<u8>) -> i32;
extern "kernel32" fn CloseHandle(h: i64) -> i32;
extern "kernel32" fn GetStdHandle(kind: i32) -> i64;

extern fn malloc(n: u64) -> ptr<u8>;
extern fn free(p: ptr<u8>) -> void;
extern fn memcpy(d: ptr<u8>, s: ptr<u8>, n: u64) -> ptr<u8>;
extern fn strlen(s: ptr<u8>) -> u64;

struct Buf {
    p: ptr<u8>,
    n: i64
}

fn io_at(p: ptr<u8>, i: i64) -> u8 {
    var c: u8 = 0;
    unsafe { c = p[i]; }
    return c;
}

fn io_read(path: ptr<u8>) -> Buf {
    var r: Buf = zero(Buf);
    let h: i64 = CreateFileA(path, 2147483648, 1, null, 3, 128, null);
    if (h == -1) {
        return r;
    }
    let size: u32 = GetFileSize(h, null);
    let cap: i64 = (size as i64) + 1;
    var p: ptr<u8> = malloc(cap as u64);
    if (p == null) {
        CloseHandle(h);
        return r;
    }
    var got: u32 = 0;
    var total: i64 = 0;
    while (total < size as i64) {
        let want: u32 = (size as u32) - (total as u32);
        let at: ptr<u8> = p_off(p, total);
        let gp: ptr<u32> = p_u32(&mut got);
        if (ReadFile(h, at, want, gp, null) == 0) {
            break;
        }
        if (got == 0) {
            break;
        }
        total += got as i64;
    }
    CloseHandle(h);
    unsafe { p[total] = 0; }
    r.p = p;
    r.n = total;
    return r;
}

fn io_write(path: ptr<u8>, p: ptr<u8>, n: i64) -> i32 {
    let h: i64 = CreateFileA(path, 1073741824, 0, null, 2, 128, null);
    if (h == -1) {
        return 0;
    }
    var wrote: u32 = 0;
    var total: i64 = 0;
    while (total < n) {
        let want: u32 = (n as u32) - (total as u32);
        let at: ptr<u8> = p_off(p, total);
        let wp: ptr<u32> = p_u32(&mut wrote);
        if (WriteFile(h, at, want, wp, null) == 0) {
            CloseHandle(h);
            return 0;
        }
        total += wrote as i64;
    }
    CloseHandle(h);
    return 1;
}

fn io_argc() -> i64 {
    let cl: ptr<u8> = GetCommandLineA();
    var i: i64 = 0;
    var n: i64 = 0;
    while (true) {
        while (io_at(cl, i) == 32 || io_at(cl, i) == 9) {
            i += 1;
        }
        if (io_at(cl, i) == 0) {
            break;
        }
        n += 1;
        if (io_at(cl, i) == 34) {
            i += 1;
            while (io_at(cl, i) != 0 && io_at(cl, i) != 34) {
                i += 1;
            }
            if (io_at(cl, i) == 34) {
                i += 1;
            }
        } else {
            while (io_at(cl, i) != 0 && io_at(cl, i) != 32 && io_at(cl, i) != 9) {
                i += 1;
            }
        }
    }
    return n;
}

fn io_arg(i: i64, dst: ptr<u8>, cap: i64) -> i64 {
    let cl: ptr<u8> = GetCommandLineA();
    var at: i64 = 0;
    var k: i64 = 0;
    while (k <= i) {
        while (io_at(cl, at) == 32 || io_at(cl, at) == 9) {
            at += 1;
        }
        if (io_at(cl, at) == 0) {
            unsafe { dst[0] = 0; }
            return 0;
        }
        if (io_at(cl, at) == 34) {
            at += 1;
            let start: i64 = at;
            while (io_at(cl, at) != 0 && io_at(cl, at) != 34) {
                at += 1;
            }
            if (k == i) {
                return io_copy(dst, cap, p_off(cl, start), at - start);
            }
            if (io_at(cl, at) == 34) {
                at += 1;
            }
        } else {
            let start2: i64 = at;
            while (io_at(cl, at) != 0 && io_at(cl, at) != 32 && io_at(cl, at) != 9) {
                at += 1;
            }
            if (k == i) {
                return io_copy(dst, cap, p_off(cl, start2), at - start2);
            }
        }
        k += 1;
    }
    unsafe { dst[0] = 0; }
    return 0;
}

fn io_copy(dst: ptr<u8>, cap: i64, src: ptr<u8>, n: i64) -> i64 {
    var k: i64 = 0;
    while (k < n && k + 1 < cap) {
        unsafe { dst[k] = src[k]; }
        k += 1;
    }
    unsafe { dst[k] = 0; }
    return n;
}

fn io_out(p: ptr<u8>, n: i64) {
    let h: i64 = GetStdHandle(-11);
    var wrote: u32 = 0;
    let wp: ptr<u32> = p_u32(&mut wrote);
    WriteFile(h, p, n as u32, wp, null);
}

fn io_err(p: ptr<u8>, n: i64) {
    let h: i64 = GetStdHandle(-12);
    var wrote: u32 = 0;
    let wp: ptr<u32> = p_u32(&mut wrote);
    WriteFile(h, p, n as u32, wp, null);
}

fn io_out_s(p: ptr<u8>) {
    io_out(p, strlen(p) as i64);
}
