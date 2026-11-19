include "modules/python/python_win.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn main() -> i32 {
    let py: PyLib = py_open("C:/Users/1234.DESKTOP-KICPMJN/AppData/Local/Programs/Python/Python312/python312.dll");
    if (py_ready(py) == 0) {
        printf("py_open failed\n");
        return 1;
    }
    py_start(py);
    printf("py_start ok\n");

    let rc: i32 = py_run(py, "print('hello from python', 2 ** 10)");
    printf("py_run rc=%d\n", rc);

    let m: ptr<u8> = py_import(py, "math");
    if ((m as i64) == 0) {
        printf("import failed\n");
        py_report(py);
        py_stop(py);
        return 2;
    }
    let sqrt: ptr<u8> = py_attr(py, m, "sqrt");
    let pi: ptr<u8> = py_attr(py, m, "pi");
    let r: ptr<u8> = py_call1(py, sqrt, pi);
    if (py_failed(py) != 0) {
        printf("call failed\n");
        py_report(py);
        py_stop(py);
        return 3;
    }
    printf("sqrt(pi)=%f\n", py_float(py, r));
    py_show(py, r);
    py_drop(py, r);
    py_drop(py, pi);
    py_drop(py, sqrt);
    py_drop(py, m);

    let bad: ptr<u8> = py_attr(py, m, "no_such_name");
    if (py_failed(py) != 0) {
        printf("error path ok\n");
        py_report(py);
        py_drop(py, bad);
    }

    py_stop(py);
    py_close(py);
    printf("t_py done\n");
    return 0;
}
