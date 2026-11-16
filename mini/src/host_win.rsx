extern "kernel32" fn GetStdHandle(kind: i32) -> i64;
extern "kernel32" fn ReadFile(h: i64, buf: ptr<u8>, want: u32, got: ptr<u32>, ov: ptr<u8>) -> i32;
extern "kernel32" fn WriteFile(h: i64, buf: ptr<u8>, n: u32, wrote: ptr<u32>, ov: ptr<u8>) -> i32;
extern "kernel32" fn ExitProcess(code: u32);
extern "kernel32" fn CreateFileA(path: ptr<u8>, access: u32, share: u32, sa: ptr<u8>, disp: u32,
                                 flags: u32, tmpl: i64) -> i64;
extern "kernel32" fn CloseHandle(h: i64) -> i32;
extern "kernel32" fn DeleteFileA(path: ptr<u8>) -> i32;
extern "kernel32" fn VirtualAlloc(addr: ptr<u8>, size: u64, kind: u32, protect: u32) -> ptr<u8>;
extern "kernel32" fn GetCommandLineA() -> ptr<u8>;
extern "kernel32" fn GetModuleFileNameA(mod_: i64, buf: ptr<u8>, n: u32) -> u32;
extern "kernel32" fn GetTempPathA(n: u32, buf: ptr<u8>) -> u32;
extern "kernel32" fn GetCurrentProcessId() -> u32;
extern "kernel32" fn CreateProcessA(app: ptr<u8>, cmd: ptr<u8>, pa: ptr<u8>, ta: ptr<u8>, inherit: i32,
                                    flags: u32, env: ptr<u8>, cwd: ptr<u8>, si: ptr<u8>, pi: ptr<u8>) -> i32;
extern "kernel32" fn WaitForSingleObject(h: i64, ms: u32) -> u32;
extern "kernel32" fn GetExitCodeProcess(h: i64, code: ptr<u32>) -> i32;

fn host_len(s: ptr<u8>, cap: i64) -> i64 {
    var i: i64 = 0;
    unsafe {
        while (i < cap && s[i] != 0) {
            i += 1;
        }
    }
    return i;
}

fn host_out(s: ptr<u8>, n: i64) {
    let h: i64 = GetStdHandle(-11);
    var wrote: u32 = 0;
    var off: i64 = 0;
    var ok: i32 = 1;
    unsafe {
        while (ok == 1 && off < n) {
            ok = WriteFile(h, s + off, (n - off) as u32, &wrote as ptr<u32>, null);
            if (ok != 1 || wrote == 0) {
                break;
            }
            off += wrote as i64;
        }
    }
}

fn host_err(s: ptr<u8>) {
    let h: i64 = GetStdHandle(-12);
    var wrote: u32 = 0;
    let n: i64 = host_len(s, 65535);
    unsafe {
        WriteFile(h, s, n as u32, &wrote as ptr<u32>, null);
        WriteFile(h, "\n" as ptr<u8>, 1, &wrote as ptr<u32>, null);
    }
}

fn host_exit(code: i32) {
    ExitProcess(code as u32);
}

fn host_grab(n: i64) -> ptr<u8> {
    return VirtualAlloc(null, n as u64, 12288, 4);
}

fn host_read_stdin(buf: ptr<u8>, want: i64) -> i64 {
    let h: i64 = GetStdHandle(-10);
    var got: u32 = 0;
    var ok: i32 = 0;
    unsafe {
        ok = ReadFile(h, buf, want as u32, &got as ptr<u32>, null);
    }
    if (ok != 1) {
        return -1;
    }
    return got as i64;
}

fn host_read_file(path: ptr<u8>, buf: ptr<u8>, want: i64) -> i64 {
    let h: i64 = CreateFileA(path, 0x80000000, 1, null, 3, 0x80, 0);
    if (h == -1) {
        return -1;
    }
    var got: u32 = 0;
    var total: i64 = 0;
    unsafe {
        while (total < want) {
            let ok: i32 = ReadFile(h, buf + total, (want - total) as u32, &got as ptr<u32>, null);
            if (ok != 1 || got == 0) {
                break;
            }
            total += got as i64;
        }
    }
    CloseHandle(h);
    return total;
}

fn host_write_file(path: ptr<u8>, buf: ptr<u8>, n: i64) -> i32 {
    let h: i64 = CreateFileA(path, 0x40000000, 0, null, 2, 0x80, 0);
    if (h == -1) {
        return 1;
    }
    var wrote: u32 = 0;
    var off: i64 = 0;
    var ok: i32 = 1;
    unsafe {
        while (ok == 1 && off < n) {
            ok = WriteFile(h, buf + off, (n - off) as u32, &wrote as ptr<u32>, null);
            if (ok != 1 || wrote == 0) {
                break;
            }
            off += wrote as i64;
        }
    }
    CloseHandle(h);
    if (off == n) {
        return 0;
    }
    return 1;
}

fn host_delete(path: ptr<u8>) {
    DeleteFileA(path);
}

fn host_temp(dst: ptr<u8>, cap: i64) -> i64 {
    return GetTempPathA(cap as u32, dst) as i64;
}

fn host_pid() -> i64 {
    return GetCurrentProcessId() as i64;
}

fn host_self(dst: ptr<u8>, cap: i64) -> i64 {
    return GetModuleFileNameA(0, dst, cap as u32) as i64;
}

fn host_argc() -> i64 {
    let cmd: ptr<u8> = GetCommandLineA();
    var i: i64 = 0;
    var n: i64 = 0;
    while (true) {
        while (pb(cmd, i) == 32 || pb(cmd, i) == 9) {
            i += 1;
        }
        if (pb(cmd, i) == 0) {
            return n;
        }
        if (pb(cmd, i) == 34) {
            i += 1;
            while (pb(cmd, i) != 0 && pb(cmd, i) != 34) {
                i += 1;
            }
            if (pb(cmd, i) == 34) {
                i += 1;
            }
        } else {
            while (pb(cmd, i) != 0 && pb(cmd, i) != 32 && pb(cmd, i) != 9) {
                i += 1;
            }
        }
        n += 1;
    }
    return n;
}

fn host_arg(want: i64, dst: ptr<u8>, cap: i64) -> i64 {
    let cmd: ptr<u8> = GetCommandLineA();
    var i: i64 = 0;
    var n: i64 = 0;
    var k: i64 = 0;
    while (true) {
        while (pb(cmd, i) == 32 || pb(cmd, i) == 9) {
            i += 1;
        }
        if (pb(cmd, i) == 0) {
            return -1;
        }
        if (n == want) {
            if (pb(cmd, i) == 34) {
                i += 1;
                while (pb(cmd, i) != 0 && pb(cmd, i) != 34) {
                    if (k < cap - 1) {
                        pset(dst, k, pb(cmd, i));
                        k += 1;
                    }
                    i += 1;
                }
            } else {
                while (pb(cmd, i) != 0 && pb(cmd, i) != 32 && pb(cmd, i) != 9) {
                    if (k < cap - 1) {
                        pset(dst, k, pb(cmd, i));
                        k += 1;
                    }
                    i += 1;
                }
            }
            pset(dst, k, 0);
            return k;
        }
        if (pb(cmd, i) == 34) {
            i += 1;
            while (pb(cmd, i) != 0 && pb(cmd, i) != 34) {
                i += 1;
            }
            if (pb(cmd, i) == 34) {
                i += 1;
            }
        } else {
            while (pb(cmd, i) != 0 && pb(cmd, i) != 32 && pb(cmd, i) != 9) {
                i += 1;
            }
        }
        n += 1;
    }
    return -1;
}

fn host_run(line: ptr<u8>) -> i32 {
    var si: [u8; 128] = [0];
    var pi: [u8; 64] = [0];
    var sp: ptr<u8> = null;
    var pp: ptr<u8> = null;
    unsafe {
        sp = &mut si[0] as ptr<u8>;
        pp = &mut pi[0] as ptr<u8>;
    }
    pset(sp, 0, 104);
    let ok: i32 = CreateProcessA(null, line, null, null, 1, 0, null, null, sp, pp);
    if (ok == 0) {
        return -1;
    }
    var hp: i64 = 0;
    var tp: i64 = 0;
    unsafe {
        hp = (pp as ptr<i64>)[0];
        tp = (pp as ptr<i64>)[1];
    }
    WaitForSingleObject(hp, 600000);
    var code: u32 = 0;
    var cp: ptr<u32> = null;
    unsafe {
        cp = &mut code as ptr<u32>;
    }
    GetExitCodeProcess(hp, cp);
    CloseHandle(tp);
    CloseHandle(hp);
    return code as i32;
}

fn host_target() -> ptr<u8> {
    return "windows";
}

fn host_sep() -> ptr<u8> {
    return "\\";
}

fn host_ext() -> ptr<u8> {
    return ".exe";
}
