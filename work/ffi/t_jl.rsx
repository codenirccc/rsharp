include "modules/julia/julia_win.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn main() -> i32 {
    let jl: JlLib = jl_open("julia.dll");
    if (jl_ready(jl) == 0) {
        printf("julia not found - put julia.dll on the DLL search path\n");
        return 1;
    }
    jl_start(jl);

    let n: ptr<u8> = jl_eval(jl, "1 + 2");
    printf("jl 1 + 2 = %lld\n", jl_int(jl, n));

    let s: ptr<u8> = jl_eval(jl, "string(round(pi, digits = 6))");
    printf("jl pi = %s\n", jl_text(jl, s));

    let r: ptr<u8> = jl_eval(jl, "sqrt(2.5)");
    printf("jl sqrt(2.5) = %f\n", jl_float(jl, r));

    let k: ptr<u8> = jl_box_int(jl, 41);
    printf("jl boxed 41 -> %lld\n", jl_int(jl, k));

    if (jl_failed(jl) != 0) {
        printf("julia raised an exception\n");
        jl_stop(jl);
        jl_close(jl);
        return 2;
    }
    jl_collect(jl);
    jl_stop(jl);
    jl_close(jl);
    printf("t_jl done\n");
    return 0;
}
