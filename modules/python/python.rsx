extern fn printf(fmt: ptr<u8>, ...) -> i32;

struct PyLib {
    ok: i32,
    lib: ptr<u8>,
    init: extern fn() -> void,
    fini: extern fn() -> i32,
    run: extern fn(ptr<u8>) -> i32,
    imp: extern fn(ptr<u8>) -> ptr<u8>,
    attr: extern fn(ptr<u8>, ptr<u8>) -> ptr<u8>,
    call3: extern fn(ptr<u8>, ptr<u8>, ptr<u8>) -> ptr<u8>,
    call1: extern fn(ptr<u8>, ptr<u8>) -> ptr<u8>,
    call0: extern fn(ptr<u8>) -> ptr<u8>,
    tup_new: extern fn(i64) -> ptr<u8>,
    tup_set: extern fn(ptr<u8>, i64, ptr<u8>) -> i32,
    repr: extern fn(ptr<u8>) -> ptr<u8>,
    text: extern fn(ptr<u8>) -> ptr<u8>,
    aslong: extern fn(ptr<u8>) -> i64,
    asdouble: extern fn(ptr<u8>) -> f64,
    err: extern fn() -> ptr<u8>,
    report: extern fn() -> void,
    drop: extern fn(ptr<u8>) -> void
}

fn py_ready(t: PyLib) -> i32 {
    return t.ok;
}

fn py_start(t: PyLib) {
    t.init();
}

fn py_stop(t: PyLib) -> i32 {
    return t.fini();
}

fn py_run(t: PyLib, code: ptr<u8>) -> i32 {
    return t.run(code);
}

fn py_import(t: PyLib, name: ptr<u8>) -> ptr<u8> {
    return t.imp(name);
}

fn py_attr(t: PyLib, obj: ptr<u8>, name: ptr<u8>) -> ptr<u8> {
    return t.attr(obj, name);
}

fn py_call(t: PyLib, f: ptr<u8>, args: ptr<u8>) -> ptr<u8> {
    return t.call3(f, args, 0 as ptr<u8>);
}

fn py_call1(t: PyLib, f: ptr<u8>, a: ptr<u8>) -> ptr<u8> {
    return t.call1(f, a);
}

fn py_call0(t: PyLib, f: ptr<u8>) -> ptr<u8> {
    return t.call0(f);
}

fn py_args(t: PyLib, n: i64) -> ptr<u8> {
    return t.tup_new(n);
}

fn py_arg(t: PyLib, args: ptr<u8>, i: i64, obj: ptr<u8>) -> i32 {
    return t.tup_set(args, i, obj);
}

fn py_repr(t: PyLib, obj: ptr<u8>) -> ptr<u8> {
    return t.repr(obj);
}

fn py_text(t: PyLib, obj: ptr<u8>) -> ptr<u8> {
    return t.text(obj);
}

fn py_int(t: PyLib, obj: ptr<u8>) -> i64 {
    return t.aslong(obj);
}

fn py_float(t: PyLib, obj: ptr<u8>) -> f64 {
    return t.asdouble(obj);
}

fn py_failed(t: PyLib) -> i32 {
    if ((t.err() as i64) != 0) {
        return 1;
    }
    return 0;
}

fn py_report(t: PyLib) {
    t.report();
}

fn py_drop(t: PyLib, obj: ptr<u8>) {
    if ((obj as i64) != 0) {
        t.drop(obj);
    }
}

fn py_show(t: PyLib, obj: ptr<u8>) {
    if ((obj as i64) == 0) {
        printf("<null>\n");
        return;
    }
    let s: ptr<u8> = t.repr(obj);
    if ((s as i64) != 0) {
        printf("%s\n", t.text(s));
        t.drop(s);
    }
}
