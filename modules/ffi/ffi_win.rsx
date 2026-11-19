extern "kernel32" fn LoadLibraryA(path: ptr<u8>) -> ptr<u8>;
extern "kernel32" fn GetProcAddress(module: ptr<u8>, name: ptr<u8>) -> ptr<u8>;
extern "kernel32" fn FreeLibrary(module: ptr<u8>) -> i32;
extern "kernel32" fn GetLastError() -> u32;
extern "kernel32" fn FormatMessageA(flags: u32, src: ptr<u8>, id: u32, lang: u32, buf: ptr<u8>, cap: u32, args: ptr<u8>) -> u32;

fn ffi_open(path: ptr<u8>) -> ptr<u8> {
    return LoadLibraryA(path);
}

fn ffi_sym(lib: ptr<u8>, name: ptr<u8>) -> ptr<u8> {
    if ((lib as i64) == 0) {
        return 0 as ptr<u8>;
    }
    return GetProcAddress(lib, name);
}

fn ffi_close(lib: ptr<u8>) -> i32 {
    if ((lib as i64) == 0) {
        return 0;
    }
    return FreeLibrary(lib);
}

fn ffi_error(dst: ptr<u8>, cap: i64) -> i64 {
    if (cap < 2) {
        return 0;
    }
    let room: u32 = cap as u32;
    let n: u32 = FormatMessageA(0x1000 | 0x200, 0 as ptr<u8>, GetLastError(), 0, dst, room, 0 as ptr<u8>);
    if (n == 0) {
        unsafe {
            dst[0] = 0;
        }
        return 0;
    }
    var len: i64 = n as i64;
    unsafe {
        while (len > 0) {
            let c: u8 = dst[len - 1];
            if (c != 10 && c != 13) {
                break;
            }
            dst[len - 1] = 0;
            len -= 1;
        }
    }
    return len;
}
