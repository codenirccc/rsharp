include "../ffi/ffi_win.rsx";
include "python.rsx";

fn py_open(path: ptr<u8>) -> PyLib {
    let h: ptr<u8> = ffi_open(path);
    var ok: i32 = 1;
    if ((h as i64) == 0) {
        ok = 0;
    }
    let p_init: ptr<u8> = ffi_sym(h, "Py_Initialize");
    let p_fini: ptr<u8> = ffi_sym(h, "Py_FinalizeEx");
    let p_run: ptr<u8> = ffi_sym(h, "PyRun_SimpleString");
    let p_imp: ptr<u8> = ffi_sym(h, "PyImport_ImportModule");
    let p_attr: ptr<u8> = ffi_sym(h, "PyObject_GetAttrString");
    let p_call3: ptr<u8> = ffi_sym(h, "PyObject_Call");
    let p_call1: ptr<u8> = ffi_sym(h, "PyObject_CallOneArg");
    let p_call0: ptr<u8> = ffi_sym(h, "PyObject_CallNoArgs");
    let p_tnew: ptr<u8> = ffi_sym(h, "PyTuple_New");
    let p_tset: ptr<u8> = ffi_sym(h, "PyTuple_SetItem");
    let p_repr: ptr<u8> = ffi_sym(h, "PyObject_Repr");
    let p_text: ptr<u8> = ffi_sym(h, "PyUnicode_AsUTF8");
    let p_long: ptr<u8> = ffi_sym(h, "PyLong_AsLongLong");
    let p_dbl: ptr<u8> = ffi_sym(h, "PyFloat_AsDouble");
    let p_err: ptr<u8> = ffi_sym(h, "PyErr_Occurred");
    let p_rep: ptr<u8> = ffi_sym(h, "PyErr_Print");
    var p_drop: ptr<u8> = ffi_sym(h, "Py_DecRef");
    if ((p_drop as i64) == 0) {
        p_drop = ffi_sym(h, "_Py_DecRef");
    }
    if ((p_init as i64) == 0 || (p_fini as i64) == 0 || (p_run as i64) == 0 || (p_imp as i64) == 0 || (p_attr as i64) == 0 || (p_call3 as i64) == 0 || (p_call1 as i64) == 0 || (p_call0 as i64) == 0 || (p_tnew as i64) == 0 || (p_tset as i64) == 0 || (p_repr as i64) == 0 || (p_text as i64) == 0 || (p_long as i64) == 0 || (p_dbl as i64) == 0 || (p_err as i64) == 0 || (p_rep as i64) == 0 || (p_drop as i64) == 0) {
        ok = 0;
    }
    let t: PyLib = PyLib {
        ok: ok,
        lib: h,
        init: p_init as extern fn() -> void,
        fini: p_fini as extern fn() -> i32,
        run: p_run as extern fn(ptr<u8>) -> i32,
        imp: p_imp as extern fn(ptr<u8>) -> ptr<u8>,
        attr: p_attr as extern fn(ptr<u8>, ptr<u8>) -> ptr<u8>,
        call3: p_call3 as extern fn(ptr<u8>, ptr<u8>, ptr<u8>) -> ptr<u8>,
        call1: p_call1 as extern fn(ptr<u8>, ptr<u8>) -> ptr<u8>,
        call0: p_call0 as extern fn(ptr<u8>) -> ptr<u8>,
        tup_new: p_tnew as extern fn(i64) -> ptr<u8>,
        tup_set: p_tset as extern fn(ptr<u8>, i64, ptr<u8>) -> i32,
        repr: p_repr as extern fn(ptr<u8>) -> ptr<u8>,
        text: p_text as extern fn(ptr<u8>) -> ptr<u8>,
        aslong: p_long as extern fn(ptr<u8>) -> i64,
        asdouble: p_dbl as extern fn(ptr<u8>) -> f64,
        err: p_err as extern fn() -> ptr<u8>,
        report: p_rep as extern fn() -> void,
        drop: p_drop as extern fn(ptr<u8>) -> void
    };
    return t;
}

fn py_close(t: PyLib) -> i32 {
    return ffi_close(t.lib);
}
