extern "system" fn write(fd: i32, buf: ptr<u8>, n: i64) -> i64;
extern "system" fn read(fd: i32, buf: ptr<u8>, n: i64) -> i64;
extern "system" fn open(path: ptr<u8>, flags: i32, ...) -> i32;
extern "system" fn close(fd: i32) -> i32;
extern "system" fn unlink(path: ptr<u8>) -> i32;
extern "system" fn system(cmd: ptr<u8>) -> i32;
extern "system" fn exit(code: i32);
extern "system" fn getenv(name: ptr<u8>) -> ptr<u8>;
extern "system" fn getpid() -> i32;
extern "system" fn calloc(n: u64, sz: u64) -> ptr<u8>;
extern "system" fn _NSGetArgc() -> ptr<i32>;
extern "system" fn _NSGetArgv() -> ptr<ptr<u8>>;
extern "system" fn _NSGetExecutablePath(buf: ptr<u8>, size: ptr<u32>) -> i32;

fn host_len(s: ptr<u8>, cap: i64) -> i64 {
    var i: i64 = 0;
    unsafe {
        while (i < cap && s[i] != 0) {
            i += 1;
        }
    }
    return i;
}

fn host_fd_write(fd: i32, s: ptr<u8>, n: i64) {
    var off: i64 = 0;
    unsafe {
        while (off < n) {
            let w: i64 = write(fd, s + off, n - off);
            if (w <= 0) {
                return;
            }
            off += w;
        }
    }
}

fn host_out(s: ptr<u8>, n: i64) {
    host_fd_write(1, s, n);
}

fn host_err(s: ptr<u8>) {
    host_fd_write(2, s, host_len(s, 65536));
    host_fd_write(2, "\n", 1);
}

fn host_exit(code: i32) {
    exit(code);
}

fn host_grab(n: i64) -> ptr<u8> {
    return calloc(1 as u64, n as u64);
}

fn host_read_stdin(buf: ptr<u8>, want: i64) -> i64 {
    let got: i64 = read(0, buf, want);
    if (got < 0) {
        return -1;
    }
    return got;
}

fn host_read_file(path: ptr<u8>, buf: ptr<u8>, want: i64) -> i64 {
    let fd: i32 = open(path, 0);
    if (fd < 0) {
        return -1;
    }
    var total: i64 = 0;
    unsafe {
        while (total < want) {
            let got: i64 = read(fd, buf + total, want - total);
            if (got <= 0) {
                break;
            }
            total += got;
        }
    }
    close(fd);
    return total;
}

fn host_write_file(path: ptr<u8>, buf: ptr<u8>, n: i64) -> i32 {
    let fd: i32 = open(path, 0x601, 0x1A4);
    if (fd < 0) {
        return 1;
    }
    var off: i64 = 0;
    unsafe {
        while (off < n) {
            let w: i64 = write(fd, buf + off, n - off);
            if (w <= 0) {
                break;
            }
            off += w;
        }
    }
    close(fd);
    if (off == n) {
        return 0;
    }
    return 1;
}

fn host_delete(path: ptr<u8>) {
    unlink(path);
}

fn host_temp(dst: ptr<u8>, cap: i64) -> i64 {
    var k: i64 = 0;
    let t: ptr<u8> = getenv("TMPDIR");
    unsafe {
        if (t != null) {
            while (t[k] != 0 && k < cap - 2) {
                dst[k] = t[k];
                k += 1;
            }
        }
        if (k == 0) {
            dst[0] = 47;
            dst[1] = 116;
            dst[2] = 109;
            dst[3] = 112;
            dst[4] = 47;
            k = 5;
        } else if (dst[k - 1] != 47) {
            dst[k] = 47;
            k += 1;
        }
        dst[k] = 0;
    }
    return k;
}

fn host_pid() -> i64 {
    return getpid() as i64;
}

fn host_argc() -> i64 {
    let p: ptr<i32> = _NSGetArgc();
    if (p == null) {
        return 0;
    }
    unsafe {
        return p[0] as i64;
    }
}

fn host_arg(i: i64, dst: ptr<u8>, cap: i64) -> i64 {
    let n: i64 = host_argc();
    if (i < 0 || i >= n) {
        return -1;
    }
    let av: ptr<ptr<u8>> = _NSGetArgv();
    if (av == null) {
        return -1;
    }
    var s: ptr<u8> = null;
    unsafe {
        s = av[i];
    }
    if (s == null) {
        return -1;
    }
    var k: i64 = 0;
    unsafe {
        while (s[k] != 0 && k < cap - 1) {
            dst[k] = s[k];
            k += 1;
        }
        dst[k] = 0;
    }
    return k;
}

fn host_self(dst: ptr<u8>, cap: i64) -> i64 {
    var size: u32 = cap as u32;
    var sp: ptr<u32> = null;
    unsafe {
        sp = &mut size as ptr<u32>;
    }
    if (_NSGetExecutablePath(dst, sp) != 0) {
        unsafe {
            dst[0] = 0;
        }
        return 0;
    }
    return host_len(dst, cap);
}

fn host_run(line: ptr<u8>) -> i32 {
    let st: i32 = system(line);
    if (st < 0) {
        return -1;
    }
    return (st >> 8) & 255;
}

fn host_target() -> ptr<u8> {
    return "macos";
}

fn host_ext() -> ptr<u8> {
    return "";
}
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
