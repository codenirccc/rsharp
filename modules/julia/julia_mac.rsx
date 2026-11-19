include "../ffi/ffi_mac.rsx";
include "julia.rsx";

fn jl_open(path: ptr<u8>) -> JlLib {
    let h: ptr<u8> = ffi_open(path);
    var ok: i32 = 1;
    if ((h as i64) == 0) {
        ok = 0;
    }
    let p_init: ptr<u8> = ffi_sym(h, "jl_init");
    let p_stop: ptr<u8> = ffi_sym(h, "jl_atexit_hook");
    let p_eval: ptr<u8> = ffi_sym(h, "jl_eval_string");
    let p_exc: ptr<u8> = ffi_sym(h, "jl_exception_occurred");
    let p_ui: ptr<u8> = ffi_sym(h, "jl_unbox_longlong");
    let p_uf: ptr<u8> = ffi_sym(h, "jl_unbox_double");
    let p_bi: ptr<u8> = ffi_sym(h, "jl_box_longlong");
    let p_bf: ptr<u8> = ffi_sym(h, "jl_box_double");
    let p_sp: ptr<u8> = ffi_sym(h, "jl_string_ptr");
    let p_gc: ptr<u8> = ffi_sym(h, "jl_gc_collect");
    if ((p_init as i64) == 0 || (p_stop as i64) == 0 || (p_eval as i64) == 0 || (p_exc as i64) == 0 || (p_ui as i64) == 0 || (p_uf as i64) == 0 || (p_bi as i64) == 0 || (p_bf as i64) == 0 || (p_sp as i64) == 0 || (p_gc as i64) == 0) {
        ok = 0;
    }
    let t: JlLib = JlLib {
        ok: ok,
        lib: h,
        init: p_init as extern fn() -> void,
        stop: p_stop as extern fn(i32) -> void,
        eval: p_eval as extern fn(ptr<u8>) -> ptr<u8>,
        exc: p_exc as extern fn() -> ptr<u8>,
        unbox_i: p_ui as extern fn(ptr<u8>) -> i64,
        unbox_f: p_uf as extern fn(ptr<u8>) -> f64,
        box_i: p_bi as extern fn(i64) -> ptr<u8>,
        box_f: p_bf as extern fn(f64) -> ptr<u8>,
        str_ptr: p_sp as extern fn(ptr<u8>) -> ptr<u8>,
        collect: p_gc as extern fn(i32) -> void
    };
    return t;
}

fn jl_close(t: JlLib) -> i32 {
    return ffi_close(t.lib);
}
