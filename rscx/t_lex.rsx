include "lex.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern fn strlen(s: ptr<u8>) -> u64;
extern fn strcmp(a: ptr<u8>, b: ptr<u8>) -> i32;

fn t_same(a: ptr<u8>, b: ptr<u8>) -> bool {
    return strcmp(a, b) == 0;
}

fn t_note(what: ptr<u8>) -> i32 {
    printf("lex: %s\n", what);
    return 1;
}

fn t_span(lx: &mut Lexer, i: i64, text: ptr<u8>) -> i32 {
    let want: i64 = strlen(text) as i64;
    if (lex_tok_slen(lx, i) != want) {
        return t_note(text);
    }
    var k: i64 = 0;
    var bad: i32 = 0;
    unsafe {
        while (k < want) {
            if (lex_tok_sp(lx, i)[k] != text[k]) {
                bad = 1;
            }
            k = k + 1;
        }
    }
    return bad;
}

fn t_tok(lx: &mut Lexer, i: i64, kind: i32, line: i64, col: i64, text: ptr<u8>) -> i32 {
    var fails: i32 = 0;
    if (lex_tok_kind(lx, i) != kind) {
        fails = fails + t_note(text);
    }
    if (lex_tok_line(lx, i) != line) {
        fails = fails + t_note(text);
    }
    if (col > 0 && lex_tok_col(lx, i) != col) {
        fails = fails + t_note(text);
    }
    fails = fails + t_span(lx, i, text);
    return fails;
}

fn t_basic() -> i32 {
    var fails: i32 = 0;
    let src: ptr<u8> = "let x: i64 = 0x1f;\nlet y = 2.5e3;\n\"hi\\n\"\n" as ptr<u8>;
    var lx: Lexer = lex_new();
    if (lex_run(&mut lx, src, strlen(src) as i64) == 0) {
        fails = fails + t_note(lex_err(&mut lx));
        lex_free(&mut lx);
        return fails;
    }
    if (lex_tok_count(&mut lx) != 14) {
        fails = fails + t_note("basic count" as ptr<u8>);
    }
    fails = fails + t_tok(&mut lx, 0, TK_IDENT, 1, 1, "let" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 1, TK_IDENT, 1, 5, "x" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 2, TK_SYM, 1, 6, ":" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 3, TK_IDENT, 1, 8, "i64" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 4, TK_SYM, 1, 12, "=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 5, TK_INT, 1, 14, "0x1f" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 6, TK_SYM, 1, 18, ";" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 7, TK_IDENT, 2, 1, "let" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 8, TK_IDENT, 2, 5, "y" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 9, TK_SYM, 2, 7, "=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 10, TK_FLOAT, 2, 9, "2.5e3" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 11, TK_SYM, 2, 14, ";" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 12, TK_STR, 3, 1, "hi\n" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 13, TK_EOF, 4, 1, "" as ptr<u8>);
    if (lex_tok_num(&mut lx, 5) != 31) {
        fails = fails + t_note("basic hex" as ptr<u8>);
    }
    if (lex_tok_fp(&mut lx, 10) != 2500.0) {
        fails = fails + t_note("basic float" as ptr<u8>);
    }
    lex_free(&mut lx);
    return fails;
}

fn t_ints() -> i32 {
    var fails: i32 = 0;
    let src: ptr<u8> = "1_000 0x0 0xff 0XaB 9223372036854775807" as ptr<u8>;
    var lx: Lexer = lex_new();
    if (lex_run(&mut lx, src, strlen(src) as i64) == 0) {
        fails = fails + t_note(lex_err(&mut lx));
        lex_free(&mut lx);
        return fails;
    }
    if (lex_tok_num(&mut lx, 0) != 1000) {
        fails = fails + t_note("int underscore" as ptr<u8>);
    }
    if (lex_tok_num(&mut lx, 1) != 0) {
        fails = fails + t_note("int zero hex" as ptr<u8>);
    }
    if (lex_tok_num(&mut lx, 2) != 255) {
        fails = fails + t_note("int hex ff" as ptr<u8>);
    }
    if (lex_tok_num(&mut lx, 3) != 171) {
        fails = fails + t_note("int hex case" as ptr<u8>);
    }
    if (lex_tok_num(&mut lx, 4) != 9223372036854775807) {
        fails = fails + t_note("int i64 max" as ptr<u8>);
    }
    lex_free(&mut lx);
    return fails;
}

fn t_floats() -> i32 {
    var fails: i32 = 0;
    let src: ptr<u8> = "0.1 1.5 1e308 1.7976931348623157e308 2.2250738585072014e-308 1e-5" as ptr<u8>;
    var lx: Lexer = lex_new();
    if (lex_run(&mut lx, src, strlen(src) as i64) == 0) {
        fails = fails + t_note(lex_err(&mut lx));
        lex_free(&mut lx);
        return fails;
    }
    if (lex_tok_fp(&mut lx, 0) != 0.1) {
        fails = fails + t_note("float 0.1" as ptr<u8>);
    }
    if (lex_tok_fp(&mut lx, 1) != 1.5) {
        fails = fails + t_note("float 1.5" as ptr<u8>);
    }
    if (lex_tok_fp(&mut lx, 2) != 1e308) {
        fails = fails + t_note("float 1e308" as ptr<u8>);
    }
    if (lex_tok_fp(&mut lx, 3) != 1.7976931348623157e308) {
        fails = fails + t_note("float f64 max" as ptr<u8>);
    }
    if (lex_tok_fp(&mut lx, 4) != 2.2250738585072014e-308) {
        fails = fails + t_note("float f64 min" as ptr<u8>);
    }
    if (lex_tok_fp(&mut lx, 5) != 1e-5) {
        fails = fails + t_note("float 1e-5" as ptr<u8>);
    }
    lex_free(&mut lx);
    return fails;
}

fn t_syms() -> i32 {
    var fails: i32 = 0;
    let src: ptr<u8> = "... ..= .. . :: : -> -= - => == = != ! <<= <= << < >>= >= > && &= & || |= | ^= ^ += + *= * /= / %= % ; , ( ) { } [ ] ~ '" as ptr<u8>;
    var lx: Lexer = lex_new();
    if (lex_run(&mut lx, src, strlen(src) as i64) == 0) {
        fails = fails + t_note(lex_err(&mut lx));
        lex_free(&mut lx);
        return fails;
    }
    if (lex_tok_count(&mut lx) != 48) {
        fails = fails + t_note("sym count" as ptr<u8>);
    }
    fails = fails + t_tok(&mut lx, 0, TK_SYM, 1, 0, "..." as ptr<u8>);
    fails = fails + t_tok(&mut lx, 1, TK_SYM, 1, 0, "..=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 2, TK_SYM, 1, 0, ".." as ptr<u8>);
    fails = fails + t_tok(&mut lx, 3, TK_SYM, 1, 0, "." as ptr<u8>);
    fails = fails + t_tok(&mut lx, 4, TK_SYM, 1, 0, "::" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 5, TK_SYM, 1, 0, ":" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 6, TK_SYM, 1, 0, "->" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 7, TK_SYM, 1, 0, "-=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 8, TK_SYM, 1, 0, "-" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 9, TK_SYM, 1, 0, "=>" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 10, TK_SYM, 1, 0, "==" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 11, TK_SYM, 1, 0, "=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 12, TK_SYM, 1, 0, "!=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 13, TK_SYM, 1, 0, "!" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 14, TK_SYM, 1, 0, "<<=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 15, TK_SYM, 1, 0, "<=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 16, TK_SYM, 1, 0, "<<" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 17, TK_SYM, 1, 0, "<" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 18, TK_SYM, 1, 0, ">>=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 19, TK_SYM, 1, 0, ">=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 20, TK_SYM, 1, 0, ">" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 21, TK_SYM, 1, 0, "&&" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 22, TK_SYM, 1, 0, "&=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 23, TK_SYM, 1, 0, "&" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 24, TK_SYM, 1, 0, "||" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 25, TK_SYM, 1, 0, "|=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 26, TK_SYM, 1, 0, "|" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 27, TK_SYM, 1, 0, "^=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 28, TK_SYM, 1, 0, "^" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 29, TK_SYM, 1, 0, "+=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 30, TK_SYM, 1, 0, "+" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 31, TK_SYM, 1, 0, "*=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 32, TK_SYM, 1, 0, "*" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 33, TK_SYM, 1, 0, "/=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 34, TK_SYM, 1, 0, "/" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 35, TK_SYM, 1, 0, "%=" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 36, TK_SYM, 1, 0, "%" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 37, TK_SYM, 1, 0, ";" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 38, TK_SYM, 1, 0, "," as ptr<u8>);
    fails = fails + t_tok(&mut lx, 39, TK_SYM, 1, 0, "(" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 40, TK_SYM, 1, 0, ")" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 41, TK_SYM, 1, 0, "{" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 42, TK_SYM, 1, 0, "}" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 43, TK_SYM, 1, 0, "[" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 44, TK_SYM, 1, 0, "]" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 45, TK_SYM, 1, 0, "~" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 46, TK_SYM, 1, 0, "'" as ptr<u8>);
    fails = fails + t_tok(&mut lx, 47, TK_EOF, 1, 0, "" as ptr<u8>);
    lex_free(&mut lx);
    return fails;
}

fn t_gt_split() -> i32 {
    var fails: i32 = 0;
    let src: ptr<u8> = "a >> b" as ptr<u8>;
    var lx: Lexer = lex_new();
    if (lex_run(&mut lx, src, strlen(src) as i64) == 0) {
        fails = fails + t_note(lex_err(&mut lx));
        lex_free(&mut lx);
        return fails;
    }
    if (lex_tok_count(&mut lx) != 5) {
        fails = fails + t_note("gt count" as ptr<u8>);
    } else {
        fails = fails + t_tok(&mut lx, 1, TK_SYM, 1, 3, ">" as ptr<u8>);
        fails = fails + t_tok(&mut lx, 2, TK_SYM, 1, 4, ">" as ptr<u8>);
    }
    lex_free(&mut lx);
    return fails;
}

fn t_escapes() -> i32 {
    var fails: i32 = 0;
    let src: ptr<u8> = "\"a\\tb\\r\\n\\\\\\\"\\'\\101\\0\" \"\\303\\251\"" as ptr<u8>;
    var lx: Lexer = lex_new();
    if (lex_run(&mut lx, src, strlen(src) as i64) == 0) {
        fails = fails + t_note(lex_err(&mut lx));
        lex_free(&mut lx);
        return fails;
    }
    if (lex_tok_slen(&mut lx, 0) != 10) {
        fails = fails + t_note("escape length" as ptr<u8>);
    }
    if (lex_tok_slen(&mut lx, 1) != 2) {
        fails = fails + t_note("escape octal pair" as ptr<u8>);
    } else {
        let q: ptr<u8> = lex_tok_sp(&mut lx, 1);
        var bad: i32 = 0;
        unsafe {
            if (q[0] != 0xC3 || q[1] != 0xA9) {
                bad = 1;
            }
        }
        if (bad != 0) {
            fails = fails + t_note("escape octal bytes" as ptr<u8>);
        }
    }
    lex_free(&mut lx);
    return fails;
}

fn t_comment() -> i32 {
    var fails: i32 = 0;
    let src: ptr<u8> = "a // tail\nb /* one\ntwo */ c" as ptr<u8>;
    var lx: Lexer = lex_new();
    if (lex_run(&mut lx, src, strlen(src) as i64) == 0) {
        fails = fails + t_note(lex_err(&mut lx));
        lex_free(&mut lx);
        return fails;
    }
    if (lex_tok_count(&mut lx) != 4) {
        fails = fails + t_note("comment count" as ptr<u8>);
    } else {
        fails = fails + t_tok(&mut lx, 0, TK_IDENT, 1, 1, "a" as ptr<u8>);
        fails = fails + t_tok(&mut lx, 1, TK_IDENT, 2, 1, "b" as ptr<u8>);
        fails = fails + t_tok(&mut lx, 2, TK_IDENT, 3, 8, "c" as ptr<u8>);
    }
    lex_free(&mut lx);
    return fails;
}

fn t_bad(name: ptr<u8>, src: ptr<u8>, want: ptr<u8>) -> i32 {
    var fails: i32 = 0;
    var lx: Lexer = lex_new();
    if (lex_run(&mut lx, src, strlen(src) as i64) != 0) {
        fails = fails + t_note(name);
    } else if (!t_same(lex_err(&mut lx), want)) {
        printf("lex: %s: got %s\n", name, lex_err(&mut lx));
        fails = fails + 1;
    }
    lex_free(&mut lx);
    return fails;
}

fn t_errors() -> i32 {
    var fails: i32 = 0;
    fails = fails + t_bad("block" as ptr<u8>, "a /* open" as ptr<u8>,
                          "line 1: unterminated block comment" as ptr<u8>);
    fails = fails + t_bad("hex" as ptr<u8>, "0x" as ptr<u8>,
                          "line 1: empty hex literal" as ptr<u8>);
    fails = fails + t_bad("hexbig" as ptr<u8>, "0xffffffffffffffff" as ptr<u8>,
                          "line 1: hex literal does not fit in 64 bits" as ptr<u8>);
    fails = fails + t_bad("intbig" as ptr<u8>, "9223372036854775808" as ptr<u8>,
                          "line 1: integer literal out of range" as ptr<u8>);
    fails = fails + t_bad("fltbig" as ptr<u8>, "1e400" as ptr<u8>,
                          "line 1: float literal out of range" as ptr<u8>);
    fails = fails + t_bad("streof" as ptr<u8>, "\"open" as ptr<u8>,
                          "line 1: unterminated string literal" as ptr<u8>);
    fails = fails + t_bad("esc" as ptr<u8>, "\"a\\" as ptr<u8>,
                          "line 1: unterminated escape" as ptr<u8>);
    fails = fails + t_bad("unk" as ptr<u8>, "\"a\\q\"" as ptr<u8>,
                          "line 1: unknown escape '\\q'" as ptr<u8>);
    fails = fails + t_bad("nl" as ptr<u8>, "\"a\nb\"" as ptr<u8>,
                          "line 1: newline inside string literal" as ptr<u8>);
    fails = fails + t_bad("utf8" as ptr<u8>, "\"\\377\"" as ptr<u8>,
                          "line 1: string literal is not valid UTF-8" as ptr<u8>);
    fails = fails + t_bad("octal" as ptr<u8>, "\"\\777\"" as ptr<u8>,
                          "line 1: octal escape is larger than a byte" as ptr<u8>);
    fails = fails + t_bad("char" as ptr<u8>, "a @ b" as ptr<u8>,
                          "line 1: unexpected character '@'" as ptr<u8>);
    fails = fails + t_bad("deep" as ptr<u8>, "a\nb\n@" as ptr<u8>,
                          "line 3: unexpected character '@'" as ptr<u8>);
    return fails;
}

fn t_empty() -> i32 {
    var fails: i32 = 0;
    var lx: Lexer = lex_new();
    if (lex_run(&mut lx, "" as ptr<u8>, 0) == 0) {
        fails = fails + t_note(lex_err(&mut lx));
    } else {
        fails = fails + t_tok(&mut lx, 0, TK_EOF, 1, 1, "" as ptr<u8>);
    }
    lex_free(&mut lx);
    return fails;
}

fn main() -> i32 {
    var fails: i32 = 0;
    fails = fails + t_empty();
    fails = fails + t_basic();
    fails = fails + t_ints();
    fails = fails + t_floats();
    fails = fails + t_syms();
    fails = fails + t_gt_split();
    fails = fails + t_escapes();
    fails = fails + t_comment();
    fails = fails + t_errors();
    if (fails != 0) {
        printf("lex suite: %lld failures\n", fails as i64);
        return 1;
    }
    printf("lex suite: ok\n");
    return 0;
}
