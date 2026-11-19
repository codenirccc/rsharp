struct JlLib {
    ok: i32,
    lib: ptr<u8>,
    init: extern fn() -> void,
    stop: extern fn(i32) -> void,
    eval: extern fn(ptr<u8>) -> ptr<u8>,
    exc: extern fn() -> ptr<u8>,
    unbox_i: extern fn(ptr<u8>) -> i64,
    unbox_f: extern fn(ptr<u8>) -> f64,
    box_i: extern fn(i64) -> ptr<u8>,
    box_f: extern fn(f64) -> ptr<u8>,
    str_ptr: extern fn(ptr<u8>) -> ptr<u8>,
    collect: extern fn(i32) -> void
}

fn jl_ready(t: JlLib) -> i32 {
    return t.ok;
}

fn jl_start(t: JlLib) {
    t.init();
}

fn jl_stop(t: JlLib) {
    t.stop(0);
}

fn jl_eval(t: JlLib, code: ptr<u8>) -> ptr<u8> {
    return t.eval(code);
}

fn jl_failed(t: JlLib) -> i32 {
    if ((t.exc() as i64) != 0) {
        return 1;
    }
    return 0;
}

fn jl_text(t: JlLib, v: ptr<u8>) -> ptr<u8> {
    if ((v as i64) == 0) {
        return 0 as ptr<u8>;
    }
    return t.str_ptr(v);
}

fn jl_int(t: JlLib, v: ptr<u8>) -> i64 {
    return t.unbox_i(v);
}

fn jl_float(t: JlLib, v: ptr<u8>) -> f64 {
    return t.unbox_f(v);
}

fn jl_box_int(t: JlLib, v: i64) -> ptr<u8> {
    return t.box_i(v);
}

fn jl_box_float(t: JlLib, v: f64) -> ptr<u8> {
    return t.box_f(v);
}

fn jl_collect(t: JlLib) {
    t.collect(1);
}
