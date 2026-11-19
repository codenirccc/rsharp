include "base.rsx";
include "scan.rsx";

fn slurp(c: &mut Ctx, p: ptr<u8>, cap: i64) -> i64 {
    let f: ptr<u8> = fopen(p, "rb");
    if (f == null) {
        return -1;
    }
    var n: i64 = 0;
    while (n < cap) {
        let got: u64 = fread(ob(c.mp, n), 1, (cap - n) as u64, f);
        if (got == 0) {
            break;
        }
        n += got as i64;
    }
    var over: u64 = 0;
    if (n == cap) {
        over = fread(ob(c.tp, TS1), 1, 1, f);
    }
    fclose(f);
    if (over > 0) {
        printf("rmake: '%s' is larger than %d bytes\n", p, cap as i32);
        c.err = 1;
        return -1;
    }
    c.mn = n;
    return n;
}

fn trim_a(c: &mut Ctx, a: i64, b: i64) -> i64 {
    var i: i64 = a;
    while (i < b && ws(rd8(c.mp, i)) == 1) {
        i += 1;
    }
    return i;
}

fn trim_b(c: &mut Ctx, a: i64, b: i64) -> i64 {
    var j: i64 = b;
    while (j > a && ws(rd8(c.mp, j - 1)) == 1) {
        j -= 1;
    }
    return j;
}

fn load_args(c: &mut Ctx) -> i64 {
    var path: ptr<u8> = ".rmake/cmd.txt";
    let env: ptr<u8> = getenv("RMAKE_CMD");
    if (env != null && sl(env) > 0) {
        path = env;
    }
    let n: i64 = slurp(c, path, MBUF);
    if (n < 0) {
        c.nargs = 0;
        return 0;
    }
    var i: i64 = 0;
    var k: i64 = 0;
    while (i < n) {
        var j: i64 = i;
        while (j < n && rd8(c.mp, j) != NEWLINE) {
            j += 1;
        }
        var a: i64 = trim_a(c, i, j);
        let b: i64 = trim_b(c, a, j);
        if (b > a && rd8(c.mp, a) != HASH) {
            if (k < NARG) {
                c.args[k] = intern(c, c.mp, a, b);
                k += 1;
            } else {
                printf("rmake: more than %d arguments\n", NARG as i32);
                c.err = 1;
                return 0;
            }
        }
        i = j + 1;
    }
    c.nargs = k;
    return k;
}

fn split_list(c: &mut Ctx, a: i64, b: i64, kind: i32) {
    var i: i64 = a;
    while (i < b) {
        while (i < b && ws(rd8(c.mp, i)) == 1) {
            i += 1;
        }
        var j: i64 = i;
        while (j < b && ws(rd8(c.mp, j)) == 0) {
            j += 1;
        }
        if (j > i) {
            let o: i64 = intern(c, c.mp, i, j);
            if (kind == 0) {
                if (c.ndep >= NDEP) {
                    printf("rmake: more than %d deps in '%s'\n", NDEP as i32, ob(c.bp, c.tg[c.cur].name));
                    c.err = 1;
                    return;
                }
                c.dep[c.ndep] = o;
                c.ndep += 1;
                c.tg[c.cur].ndeps += 1;
            } else {
                if (c.nast >= NDEP) {
                    printf("rmake: more than %d assets in '%s'\n", NDEP as i32, ob(c.bp, c.tg[c.cur].name));
                    c.err = 1;
                    return;
                }
                c.ast[c.nast] = o;
                c.nast += 1;
                c.tg[c.cur].nassets += 1;
            }
        }
        i = j;
    }
}

fn section(c: &mut Ctx, a: i64, b: i64) {
    var e: i64 = b;
    if (e > a && rd8(c.mp, e - 1) == RBR) {
        e -= 1;
    }
    var k: i64 = a + 1;
    while (k < e && ws(rd8(c.mp, k)) == 0) {
        k += 1;
    }
    let kw: i64 = k - (a + 1);
    var v: i64 = k;
    while (v < e && ws(rd8(c.mp, v)) == 1) {
        v += 1;
    }
    if (kw == 3 && sn(ob(c.mp, a + 1), "exe", 3) == 1) {
        if (c.nt >= NT) {
            printf("rmake: too many targets\n");
            c.err = 1;
            return;
        }
        c.tg[c.nt].kind = KIND_EXE;
    } else if (kw == 4 && sn(ob(c.mp, a + 1), "test", 4) == 1) {
        if (c.nt >= NT) {
            printf("rmake: too many targets\n");
            c.err = 1;
            return;
        }
        c.tg[c.nt].kind = KIND_TEST;
    } else {
        printf("rmake: unknown section '%.*s'\n", (b - a) as i32, ob(c.mp, a));
        c.err = 1;
        return;
    }
    if (v >= e) {
        printf("rmake: section needs a name\n");
        c.err = 1;
        return;
    }
    c.tg[c.nt].name = intern(c, c.mp, v, e);
    c.tg[c.nt].dep0 = c.ndep;
    c.tg[c.nt].ast0 = c.nast;
    c.cur = c.nt;
    c.nt += 1;
}

fn kv(c: &mut Ctx, a: i64, b: i64) {
    var k: i64 = a;
    while (k < b && ws(rd8(c.mp, k)) == 0) {
        k += 1;
    }
    let kl: i64 = k - a;
    var v: i64 = k;
    while (v < b && ws(rd8(c.mp, v)) == 1) {
        v += 1;
    }
    let key: ptr<u8> = ob(c.mp, a);
    var has: i32 = 0;
    if (v < b) {
        has = 1;
    }
    if (kl == 6 && sn(key, "outdir", 6) == 1) {
        if (has == 1) {
            c.outdir = intern(c, c.mp, v, b);
        }
        return;
    }
    if (kl == 3 && sn(key, "rsc", 3) == 1) {
        if (has == 1) {
            c.rsc = intern(c, c.mp, v, b);
        }
        return;
    }
    if (kl == 8 && sn(key, "manifest", 8) == 1) {
        if (has == 1) {
            c.man = intern(c, c.mp, v, b);
        }
        return;
    }
    if (c.cur < 0) {
        printf("rmake: unknown setting '%.*s' outside a section\n", kl as i32, key);
        c.err = 1;
        return;
    }
    if (has == 0) {
        printf("rmake: setting '%.*s' needs a value\n", kl as i32, key);
        c.err = 1;
        return;
    }
    if (kl == 3 && sn(key, "src", 3) == 1) {
        c.tg[c.cur].src = intern(c, c.mp, v, b);
        return;
    }
    if (kl == 3 && sn(key, "out", 3) == 1) {
        c.tg[c.cur].out = intern(c, c.mp, v, b);
        return;
    }
    if (kl == 3 && sn(key, "tgt", 3) == 1) {
        c.tg[c.cur].plat = intern(c, c.mp, v, b);
        return;
    }
    if (kl == 4 && sn(key, "deps", 4) == 1) {
        split_list(c, v, b, 0);
        return;
    }
    if (kl == 6 && sn(key, "assets", 6) == 1) {
        split_list(c, v, b, 1);
        return;
    }
    printf("rmake: unknown setting '%.*s'\n", kl as i32, key);
    c.err = 1;
}

fn load_manifest(c: &mut Ctx) -> i32 {
    let n: i64 = slurp(c, ob(c.bp, c.man), MBUF);
    if (n < 0) {
        if (c.err == 1) {
            return 0;
        }
        if (c.man_def == 1 && getenv("RMAKE_SEEK") != null) {
            return -1;
        }
        printf("rmake: cannot read '%s'\n", ob(c.bp, c.man));
        printf("rmake: run rmake from the directory that holds the build file, or pass --manifest PATH\n");
        return 0;
    }
    c.cur = -1;
    var i: i64 = 0;
    while (i < n) {
        var j: i64 = i;
        while (j < n && rd8(c.mp, j) != NEWLINE) {
            j += 1;
        }
        let a: i64 = trim_a(c, i, j);
        let b: i64 = trim_b(c, a, j);
        if (b > a && rd8(c.mp, a) != HASH) {
            if (rd8(c.mp, a) == LBR) {
                section(c, a, b);
            } else {
                kv(c, a, b);
            }
        }
        if (c.err == 1) {
            return 0;
        }
        i = j + 1;
    }
    return 1;
}
