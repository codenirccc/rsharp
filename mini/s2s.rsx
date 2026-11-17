include "s2s_core.rsx";

extern "kernel32" fn GetStdHandle(kind: i32) -> i64;
extern "kernel32" fn ReadFile(h: i64, buf: ptr<u8>, want: u32, got: ptr<u32>, ov: ptr<u8>) -> i32;
extern "kernel32" fn WriteFile(h: i64, buf: ptr<u8>, n: u32, wrote: ptr<u32>, ov: ptr<u8>) -> i32;
extern "msvcrt" fn calloc(n: u64, sz: u64) -> ptr<u8>;
extern "msvcrt" fn free(p: ptr<u8>);
extern "kernel32" fn ExitProcess(code: u32);

const SRC_MAX: i64 = 1048576;
const OUT_MAX: i64 = 1048576;

fn host_grab(n: i64) -> ptr<u8> {
    return calloc(1, n as u64);
}

fn host_err(msg: ptr<u8>, n: i64) {
    var wrote: u32 = 0;
    var off: i64 = 0;
    unsafe {
        let h: i64 = GetStdHandle(-12);
        while (off < n) {
            let ok: i32 = WriteFile(h, msg + off, (n - off) as u32, &wrote as ptr<u32>, null);
            if (ok != 1 || wrote == 0) {
                return;
            }
            off += wrote as i64;
        }
    }
}

fn host_exit(code: i32) {
    unsafe {
        ExitProcess(code as u32);
    }
}

fn host_read_stdin(dst: ptr<u8>, want: i64) -> i64 {
    var got: u32 = 0;
    var total: i64 = 0;
    unsafe {
        let h: i64 = GetStdHandle(-10);
        while (total < want) {
            let ok: i32 = ReadFile(h, dst + total, (want - total) as u32, &got as ptr<u32>, null);
            if (ok != 1 || got == 0) {
                break;
            }
            total += got as i64;
        }
    }
    return total;
}

fn host_write_stdout(src: ptr<u8>, n: i64) {
    var wrote: u32 = 0;
    var off: i64 = 0;
    unsafe {
        let h: i64 = GetStdHandle(-11);
        while (off < n) {
            let ok: i32 = WriteFile(h, src + off, (n - off) as u32, &wrote as ptr<u32>, null);
            if (ok != 1 || wrote == 0) {
                return;
            }
            off += wrote as i64;
        }
    }
}

fn main() -> i32 {
    let src: ptr<u8> = host_grab(SRC_MAX);
    let out: ptr<u8> = host_grab(OUT_MAX);
    if (src == null || out == null) {
        let m: ptr<u8> = "s2s: cannot allocate the buffers\n" as ptr<u8>;
        host_err(m, 32);
        host_exit(1);
    }
    let slen: i64 = host_read_stdin(src, SRC_MAX);
    let written: i64 = s2s_run(src, slen, out);
    host_write_stdout(out, written);
    unsafe {
        free(src);
        free(out);
    }
    host_exit(0);
    return 0;
}
