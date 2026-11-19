extern "system" fn dlopen(path: ptr<u8>, flags: i32) -> ptr<u8>;
extern "system" fn dlsym(lib: ptr<u8>, name: ptr<u8>) -> ptr<u8>;
extern "system" fn dlerror() -> ptr<u8>;
extern "system" fn dlclose(lib: ptr<u8>) -> i32;

fn ffi_open_flags(path: ptr<u8>, flags: i32) -> ptr<u8> {
    dlerror();
    return dlopen(path, flags);
}

fn ffi_open(path: ptr<u8>) -> ptr<u8> {
    return ffi_open_flags(path, 0xA);
}

fn ffi_sym(lib: ptr<u8>, name: ptr<u8>) -> ptr<u8> {
    if ((lib as i64) == 0) {
        return 0 as ptr<u8>;
    }
    dlerror();
    return dlsym(lib, name);
}

fn ffi_close(lib: ptr<u8>) -> i32 {
    if ((lib as i64) == 0) {
        return 0;
    }
    return dlclose(lib);
}

fn ffi_error(dst: ptr<u8>, cap: i64) -> i64 {
    if (cap < 1) {
        return 0;
    }
    let msg: ptr<u8> = dlerror();
    if ((msg as i64) == 0) {
        unsafe {
            dst[0] = 0;
        }
        return 0;
    }
    var i: i64 = 0;
    unsafe {
        while (msg[i] != 0 && i + 1 < cap) {
            dst[i] = msg[i];
            i += 1;
        }
        dst[i] = 0;
    }
    return i;
}
