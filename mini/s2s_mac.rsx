include "s2s_core.rsx";

extern "system" fn read(fd: i32, buf: ptr<u8>, n: u64) -> i64;
extern "system" fn write(fd: i32, buf: ptr<u8>, n: u64) -> i64;
extern "system" fn exit(code: i32);
extern "system" fn calloc(n: u64, sz: u64) -> ptr<u8>;
extern "system" fn free(p: ptr<u8>);

const SRC_MAX: i64 = 1048576;
const OUT_MAX: i64 = 1048576;

fn host_grab(n: i64) -> ptr<u8> {
    return calloc(1, n as u64);
}

fn host_err(msg: ptr<u8>, n: i64) {
    var off: i64 = 0;
    unsafe {
        while (off < n) {
            let w: i64 = write(2, msg + off, (n - off) as u64);
            if (w <= 0) {
                return;
            }
            off += w;
        }
    }
}

fn host_exit(code: i32) {
    exit(code);
}

fn host_read_stdin(dst: ptr<u8>, want: i64) -> i64 {
    var total: i64 = 0;
    unsafe {
        while (total < want) {
            let got: i64 = read(0, dst + total, (want - total) as u64);
            if (got <= 0) {
                break;
            }
            total += got;
        }
    }
    return total;
}

fn host_write_stdout(src: ptr<u8>, n: i64) {
    var off: i64 = 0;
    unsafe {
        while (off < n) {
            let w: i64 = write(1, src + off, (n - off) as u64);
            if (w <= 0) {
                return;
            }
            off += w;
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
