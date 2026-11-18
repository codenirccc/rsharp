include "parse.rsx";


extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern fn strlen(s: ptr<u8>) -> u64;

fn tp_note(what: ptr<u8>) -> i32 {
    printf("parse: %s\n", what);
    return 1;
}

fn tp_emit(src: ptr<u8>, out: &mut Sb) -> i32 {
    var f: Fr = fr_new();
    if (fr_lex(&mut f, src, strlen(src) as i64) == 0) {
        let ep: ptr<u8> = fr_err_ptr(&mut f);
        let en: i64 = fr_err_len(&mut f);
        sb_put(out, ep, en);
        fr_free(&mut f);
        return 0;
    }
    var p: Pr = fr_parse(&mut f);
    if (fr_ok(&mut f) == 0) {
        let ep: ptr<u8> = fr_err_ptr(&mut f);
        let en: i64 = fr_err_len(&mut f);
        sb_put(out, ep, en);
        fr_free(&mut f);
        return 0;
    }
    fr_emit(&mut f, &mut p, out);
    fr_free(&mut f);
    return 1;
}

fn tp_same(got: ptr<u8>, n: i64, want: ptr<u8>) -> i32 {
    let wn: i64 = strlen(want) as i64;
    if (n != wn) {
        return 0;
    }
    var i: i64 = 0;
    unsafe {
        while (i < n) {
            if (got[i] != want[i]) {
                return 0;
            }
            i += 1;
        }
    }
    return 1;
}

fn tp_show(tag: ptr<u8>, p: ptr<u8>, n: i64) {
    if (n <= 0) {
        printf("parse: %s: empty\n", tag);
        return;
    }
    var b: Sb = sb_new(256);
    sb_put(&mut b, p, n);
    sb_putc(&mut b, 0);
    printf("parse: %s: %s\n", tag, b.p);
    sb_free(&mut b);
}

fn tp_expect(name: ptr<u8>, src: ptr<u8>, want: ptr<u8>) -> i32 {
    var b: Sb = sb_new(1024);
    if (tp_emit(src, &mut b) == 0) {
        tp_show(name, b.p, b.n);
        sb_free(&mut b);
        return 1;
    }
    let wn: i64 = strlen(want) as i64;
    if (tp_same(b.p, b.n, want) == 0) {
        printf("parse: %s: %d bytes, want %d\n", name, b.n as i32, wn as i32);
        tp_show(name, b.p, b.n);
        sb_free(&mut b);
        return 1;
    }
    sb_free(&mut b);
    return 0;
}

fn tp_err(name: ptr<u8>, src: ptr<u8>, want: ptr<u8>) -> i32 {
    var f: Fr = fr_new();
    if (fr_lex(&mut f, src, strlen(src) as i64) == 0) {
        printf("parse: %s: lexer rejected the source\n", name);
        fr_free(&mut f);
        return 1;
    }
    var p: Pr = fr_parse(&mut f);
    if (fr_ok(&mut f) == 1) {
        printf("parse: %s: expected a parse error\n", name);
        fr_free(&mut f);
        return 1;
    }
    let gp: ptr<u8> = fr_err_ptr(&mut f);
    let gn: i64 = fr_err_len(&mut f);
    var bad: i32 = 0;
    if (tp_same(gp, gn, want) == 0) {
        tp_show(name, gp, gn);
        bad = 1;
    }
    fr_free(&mut f);
    return bad;
}

fn tp_hello() -> i32 {
    let src: ptr<u8> = "fn main() -> i32 {\n    return 0;\n}\n" as ptr<u8>;
    let want: ptr<u8> = "(program\n  (fn main\n    (ret i32)\n    (body\n      (return (int 0))\n    )\n  )\n)\n" as ptr<u8>;
    return tp_expect("hello" as ptr<u8>, src, want);
}

fn tp_decls() -> i32 {
    let src: ptr<u8> = "const N: i64 = 10;\nstatic mut G: i32 = 1;\nstruct P {\n    x: i64,\n    y: i64\n}\nenum E {\n    A,\n    B(i32),\n    C(i64, i64)\n}\nextern \"c\" fn puts(s: ptr<u8>) -> i32;\nfn sum(a: i64, b: i64) -> i64 {\n    return a + b * 2 - 1;\n}\n" as ptr<u8>;
    let want: ptr<u8> = "(program\n  (const N i64 (int 10))\n  (static G i32 (int 1) mut)\n  (struct P\n    (field x i64)\n    (field y i64)\n  )\n  (enum E\n    (variant A)\n    (variant B (payload i32))\n    (variant C (payload i64 i64))\n  )\n  (extern puts\n    (lib \"c\")\n    (param (ptr u8))\n    (ret i32)\n  )\n  (fn sum\n    (param a i64)\n    (param b i64)\n    (ret i64)\n    (body\n      (return (bin - (bin + (var a) (bin * (var b) (int 2))) (int 1)))\n    )\n  )\n)\n" as ptr<u8>;
    return tp_expect("decls" as ptr<u8>, src, want);
}

fn tp_stmts() -> i32 {
    let src: ptr<u8> = "fn main() -> i32 {\n    let x: i64 = 1;\n    var y: i64 = 2;\n    y = x + 3;\n    if (y > 2) {\n        y = y - 1;\n    } else {\n        y = 0;\n    }\n    while (y < 10) {\n        y += 1;\n    }\n    loop {\n        break;\n    }\n    match y {\n        0 => {\n            y = 1;\n        }\n        1..=3 => {\n            y = 2;\n        }\n        _ => {\n            y = 3;\n        }\n    }\n    unsafe {\n        var p: ptr<i64> = null;\n        *p = y;\n    }\n    return y;\n}\n" as ptr<u8>;
    let want: ptr<u8> = "(program\n  (fn main\n    (ret i32)\n    (body\n      (let x i64 (int 1))\n      (var y i64 (int 2))\n      (assign = (var y) (bin + (var x) (int 3)))\n      (if (bin > (var y) (int 2))\n        (then\n          (assign = (var y) (bin - (var y) (int 1)))\n        )\n        (else\n          (assign = (var y) (int 0))\n        )\n      )\n      (while (bin < (var y) (int 10))\n        (assign += (var y) (int 1))\n      )\n      (loop\n        (break)\n      )\n      (match (var y)\n        (arm (pat lit 0)\n          (body\n            (assign = (var y) (int 1))\n          )\n        )\n        (arm (pat range 1 3)\n          (body\n            (assign = (var y) (int 2))\n          )\n        )\n        (arm (pat wild)\n          (body\n            (assign = (var y) (int 3))\n          )\n        )\n      )\n      (unsafe\n        (var p (ptr i64) (null))\n        (assign = (deref (var p)) (var y))\n      )\n      (return (var y))\n    )\n  )\n)\n" as ptr<u8>;
    return tp_expect("stmts" as ptr<u8>, src, want);
}

fn tp_exprs() -> i32 {
    let src: ptr<u8> = "struct P {\n    x: i64,\n    y: i64\n}\nfn f(a: i32, b: i32) -> i32 {\n    let c: i32 = (a + b) * (a - b) / 2 % 3;\n    let d: i64 = sizeof(P) as i64;\n    let e: P = P { x: d, y: 1 };\n    let g: i64 = e.x + e.y;\n    let h: i64 = zero(i64);\n    let i: bool = c > 0 && !(b == 0) || a != 0;\n    let j: i64 = -a as i64;\n    let k: [i32; 3] = [1, 2, 3];\n    let l: i64 = k[0] as i64;\n    return c + g as i32 + h as i32 + l as i32 + j as i32 + i as i32;\n}\n" as ptr<u8>;
    let want: ptr<u8> = "(program\n  (struct P\n    (field x i64)\n    (field y i64)\n  )\n  (fn f\n    (param a i32)\n    (param b i32)\n    (ret i32)\n    (body\n      (let c i32 (bin % (bin / (bin * (bin + (var a) (var b)) (bin - (var a) (var b))) (int 2)) (int 3)))\n      (let d i64 (cast (sizeof (named P)) i64))\n      (let e (named P) (structlit P (field x (var d)) (field y (int 1))))\n      (let g i64 (bin + (field (var e) x) (field (var e) y)))\n      (let h i64 (zero i64))\n      (let i bool (bin || (bin && (bin > (var c) (int 0)) (un ! (bin == (var b) (int 0)))) (bin != (var a) (int 0))))\n      (let j i64 (cast (un - (var a)) i64))\n      (let k (array i32 3) (arraylit (int 1) (int 2) (int 3)))\n      (let l i64 (cast (index (var k) (int 0)) i64))\n      (return (bin + (bin + (bin + (bin + (bin + (var c) (cast (var g) i32)) (cast (var h) i32)) (cast (var l) i32)) (cast (var j) i32)) (cast (var i) i32)))\n    )\n  )\n)\n" as ptr<u8>;
    return tp_expect("exprs" as ptr<u8>, src, want);
}

fn tp_module() -> i32 {
    let src: ptr<u8> = "mod m {\n    const K: i64 = 3;\n    fn helper(v: i64) -> i64 {\n        return v + K;\n    }\n    fn run(v: i64) -> i64 {\n        return helper(v) + K;\n    }\n}\nfn main() -> i32 {\n    return m::run(1) as i32;\n}\n" as ptr<u8>;
    let want: ptr<u8> = "(program\n  (const m__K i64 (int 3))\n  (fn m__helper\n    (param v i64)\n    (ret i64)\n    (body\n      (return (bin + (var v) (var m__K)))\n    )\n  )\n  (fn m__run\n    (param v i64)\n    (ret i64)\n    (body\n      (return (bin + (call m__helper (var v)) (var m__K)))\n    )\n  )\n  (fn main\n    (ret i32)\n    (body\n      (return (cast (call m__run (int 1)) i32))\n    )\n  )\n)\n" as ptr<u8>;
    return tp_expect("module" as ptr<u8>, src, want);
}

fn tp_methods() -> i32 {
    let src: ptr<u8> = "struct C {\n    n: i64\n}\nimpl C {\n    fn bump(self: &mut C, d: i64) {\n        self.n = self.n + d;\n    }\n    fn get(self: &C) -> i64 {\n        return self.n;\n    }\n}\nfn main() -> i32 {\n    var c: C = C { n: 0 };\n    c.bump(2);\n    return c.get() as i32;\n}\n" as ptr<u8>;
    let want: ptr<u8> = "(program\n  (struct C\n    (field n i64)\n  )\n  (fn C__bump\n    (param self (refmut (named C)))\n    (param d i64)\n    (ret void)\n    (body\n      (assign = (field (var self) n) (bin + (field (var self) n) (var d)))\n    )\n  )\n  (fn C__get\n    (param self (ref (named C)))\n    (ret i64)\n    (body\n      (return (field (var self) n))\n    )\n  )\n  (fn main\n    (ret i32)\n    (body\n      (var c (named C) (structlit C (field n (int 0))))\n      (expr (call C__bump (addrmut (var c)) (int 2)))\n      (return (cast (call C__get (addr (var c))) i32))\n    )\n  )\n)\n" as ptr<u8>;
    return tp_expect("methods" as ptr<u8>, src, want);
}

fn tp_errors() -> i32 {
    var fails: i32 = 0;
    let s_missingsemi: ptr<u8> = "fn main() -> i32 {\n    return 0\n}\n" as ptr<u8>;
    fails += tp_err("missingsemi" as ptr<u8>, s_missingsemi, "line 3:1: expected ';', found '}'" as ptr<u8>);
    let s_unclosed: ptr<u8> = "fn main() {\n    let x: i64 = 1;\n" as ptr<u8>;
    fails += tp_err("unclosed" as ptr<u8>, s_unclosed, "line 3:1: unexpected end of file inside a block" as ptr<u8>);
    let s_baditem: ptr<u8> = "let x: i64 = 1;\n" as ptr<u8>;
    fails += tp_err("baditem" as ptr<u8>, s_baditem, "line 1:1: expected 'const', 'struct', 'enum', 'extern', 'static', 'mod', 'impl' or 'fn', found 'let'" as ptr<u8>);
    let s_dupparam: ptr<u8> = "fn f(a: i64, a: i64) -> i64 {\n    return a;\n}\n" as ptr<u8>;
    fails += tp_err("dupparam" as ptr<u8>, s_dupparam, "duplicate parameter 'a' in fn 'f'" as ptr<u8>);
    let s_badif: ptr<u8> = "fn main() -> i32 {\n    if 1 {\n        return 0;\n    }\n    return 1;\n}\n" as ptr<u8>;
    fails += tp_err("badif" as ptr<u8>, s_badif, "line 2:8: expected '(', found integer 1" as ptr<u8>);
    return fails;
}


fn main() -> i32 {
    var fails: i32 = 0;
    fails += tp_hello();
    fails += tp_decls();
    fails += tp_stmts();
    fails += tp_exprs();
    fails += tp_module();
    fails += tp_methods();
    fails += tp_errors();
    if (fails != 0) {
        printf("parse suite: %d failure(s)\n", fails);
        return 1;
    }
    printf("parse suite: ok\n");
    return 0;
}
