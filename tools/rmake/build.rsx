include "base.rsx";
include "scan.rsx";
include "manifest.rsx";

fn tp_put(c: &mut Ctx, at: i64, p: ptr<u8>) -> i64 {
    let n: i64 = sl(p);
    if (tp_room(c, at, n) == 0) {
        return -1;
    }
    var k: i64 = 0;
    while (k < n) {
        wr8(c.tp, at + k, rd8(p, k));
        k += 1;
    }
    return at + n;
}

fn plat_ext(p: ptr<u8>) -> ptr<u8> {
    if (sq(p, "windows") == 1 || sq(p, "win") == 1 || sq(p, "win64") == 1 || sq(p, "pe") == 1) {
        return ".exe";
    }
    if (sq(p, "vm") == 1) {
        return ".rvm";
    }
    return "";
}

fn find_tgt(c: &mut Ctx, o: i64) -> i64 {
    var i: i64 = 0;
    while (i < c.nt) {
        if (sq(ob(c.bp, c.tg[i].name), ob(c.bp, o)) == 1) {
            return i;
        }
        i += 1;
    }
    return -1;
}

fn mk_out(c: &mut Ctx, i: i64) -> i32 {
    if (c.tg[i].out != 0) {
        return 1;
    }
    if (c.tg[i].plat == 0) {
        c.tg[i].plat = c.hostplat;
    }
    var n: i64 = tp_put(c, TS4, ob(c.bp, c.outdir));
    if (n >= 0) {
        n = tp_put(c, n, "/");
    }
    if (n >= 0) {
        n = tp_put(c, n, ob(c.bp, c.tg[i].name));
    }
    if (n >= 0) {
        n = tp_put(c, n, plat_ext(ob(c.bp, c.tg[i].plat)));
    }
    if (n < 0) {
        return 0;
    }
    wr8(c.tp, n, 0);
    c.tg[i].out = intern_str(c, ob(c.tp, TS4));
    if (c.err != 0) {
        return 0;
    }
    return 1;
}

fn stamp_path(c: &mut Ctx, i: i64) -> ptr<u8> {
    var n: i64 = tp_put(c, TS3, ".rmake/");
    if (n >= 0) {
        n = tp_put(c, n, ob(c.bp, c.tg[i].name));
    }
    if (n >= 0) {
        n = tp_put(c, n, ".stamp");
    }
    if (n < 0) {
        wr8(c.tp, TS3, 0);
        return ob(c.tp, TS3);
    }
    wr8(c.tp, n, 0);
    return ob(c.tp, TS3);
}

fn sb_ptr(c: &mut Ctx) -> ptr<u8> {
    var q: ptr<u8> = null;
    unsafe { q = &mut c.sb[0] as ptr<u8>; }
    return q;
}

fn fill_sb(c: &mut Ctx, h: u64) {
    var x: u64 = h;
    var k: i64 = 0;
    while (k < 8) {
        c.sb[k] = (x % 256) as u8;
        x = x / 256;
        k += 1;
    }
}

fn stamp_match(c: &mut Ctx, i: i64, h: u64) -> i32 {
    fill_sb(c, h);
    let p: ptr<u8> = stamp_path(c, i);
    let f: ptr<u8> = fopen(p, "rb");
    if (f == null) {
        return 0;
    }
    let got: u64 = fread(ob(c.tp, TS1), 1, 8, f);
    fclose(f);
    if (got != 8) {
        return 0;
    }
    var k: i64 = 0;
    while (k < 8) {
        if (rd8(ob(c.tp, TS1), k) != c.sb[k]) {
            return 0;
        }
        k += 1;
    }
    return 1;
}

fn stamp_write(c: &mut Ctx, i: i64, h: u64) {
    fill_sb(c, h);
    let p: ptr<u8> = stamp_path(c, i);
    let f: ptr<u8> = fopen(p, "wb");
    if (f == null) {
        return;
    }
    let src: ptr<u8> = sb_ptr(c);
    fwrite(src, 1, 8, f);
    fclose(f);
}

fn target_hash(c: &mut Ctx, i: i64) -> u64 {
    var h: u64 = HSEED;
    h = mix_str(h, "rmake/1");
    h = mix_str(h, ob(c.bp, c.tg[i].plat));
    h = mix_str(h, ob(c.bp, c.tg[i].out));
    c.nseen = 0;
    h = walk(c, c.tg[i].src, 0, h);
    var k: i64 = 0;
    while (k < c.tg[i].nassets) {
        h = hash_file(c, c.ast[c.tg[i].ast0 + k], h);
        k += 1;
    }
    return h;
}

fn check(c: &mut Ctx) -> i32 {
    if (c.nt == 0) {
        printf("rmake: no targets in '%s'\n", ob(c.bp, c.man));
        return 0;
    }
    var i: i64 = 0;
    while (i < c.nt) {
        if (c.tg[i].src == 0) {
            printf("rmake: target '%s' has no src\n", ob(c.bp, c.tg[i].name));
            return 0;
        }
        if (isfile(ob(c.bp, c.tg[i].src)) == 0) {
            printf("rmake: target '%s': cannot read src '%s'\n", ob(c.bp, c.tg[i].name), ob(c.bp, c.tg[i].src));
            return 0;
        }
        if (mk_out(c, i) == 0) {
            return 0;
        }
        var j: i64 = i + 1;
        while (j < c.nt) {
            if (sq(ob(c.bp, c.tg[i].name), ob(c.bp, c.tg[j].name)) == 1) {
                printf("rmake: duplicate target '%s'\n", ob(c.bp, c.tg[i].name));
                return 0;
            }
            j += 1;
        }
        j = 0;
        while (j < i) {
            if (sq(ob(c.bp, c.tg[i].out), ob(c.bp, c.tg[j].out)) == 1) {
                printf("rmake: '%s' and '%s' both write '%s'\n", ob(c.bp, c.tg[j].name), ob(c.bp, c.tg[i].name), ob(c.bp, c.tg[i].out));
                return 0;
            }
            j += 1;
        }
        i += 1;
    }
    return 1;
}

fn visit(c: &mut Ctx, i: i64) -> i32 {
    if (c.tg[i].state == 2) {
        return 1;
    }
    if (c.tg[i].state == 1) {
        printf("rmake: dependency cycle at '%s'\n", ob(c.bp, c.tg[i].name));
        c.err = 1;
        return 0;
    }
    c.tg[i].state = 1;
    var k: i64 = 0;
    while (k < c.tg[i].ndeps) {
        let nm: i64 = c.dep[c.tg[i].dep0 + k];
        let j: i64 = find_tgt(c, nm);
        if (j < 0) {
            printf("rmake: '%s' depends on unknown target '%s'\n", ob(c.bp, c.tg[i].name), ob(c.bp, nm));
            c.err = 1;
            return 0;
        }
        if (visit(c, j) == 0) {
            return 0;
        }
        k += 1;
    }
    c.tg[i].state = 2;
    c.ord[c.nord] = i;
    c.nord += 1;
    return 1;
}

fn order(c: &mut Ctx, from: i64) -> i32 {
    var i: i64 = 0;
    while (i < c.nt) {
        c.tg[i].state = 0;
        i += 1;
    }
    c.nord = 0;
    if (from >= 0) {
        return visit(c, from);
    }
    i = 0;
    while (i < c.nt) {
        if (visit(c, i) == 0) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn build_one(c: &mut Ctx, i: i64, force: i32) -> i32 {
    if (mk_out(c, i) == 0) {
        return 0;
    }
    let name: ptr<u8> = ob(c.bp, c.tg[i].name);
    let src: ptr<u8> = ob(c.bp, c.tg[i].src);
    let out: ptr<u8> = ob(c.bp, c.tg[i].out);
    let plat: ptr<u8> = ob(c.bp, c.tg[i].plat);
    let h: u64 = target_hash(c, i);
    if (c.err == 1) {
        return 0;
    }
    let fresh: i32 = stamp_match(c, i, h);
    if (c.err == 1) {
        return 0;
    }
    if (force == 0 && fresh == 1 && isfile(out) == 1) {
        printf("  ok    %s\n", name);
        c.skipped += 1;
        return 1;
    }
    let rsc: ptr<u8> = ob(c.bp, c.rsc);
    cmd_begin(c);
    cmd_arg(c, rsc);
    cmd_sp(c);
    if (sq(plat, "vm") == 1) {
        cmd_raw(c, "--vm");
    } else {
        cmd_raw(c, "-t");
        cmd_sp(c);
        cmd_raw(c, plat);
    }
    cmd_sp(c);
    cmd_arg(c, src);
    cmd_sp(c);
    cmd_arg(c, out);
    printf("  rsc   %s\n", name);
    let rc: i32 = spawn(c);
    if (rc_ok(rc) == 0) {
        printf("rmake: target '%s' failed\n", name);
        return 0;
    }
    stamp_write(c, i, h);
    c.built += 1;
    return 1;
}

fn build_seq(c: &mut Ctx, force: i32) -> i32 {
    var k: i64 = 0;
    while (k < c.nord) {
        if (build_one(c, c.ord[k], force) == 0) {
            return 0;
        }
        k += 1;
    }
    return 1;
}

fn build_all(c: &mut Ctx, force: i32) -> i32 {
    c.built = 0;
    c.skipped = 0;
    if (order(c, -1) == 0) {
        return 0;
    }
    if (build_seq(c, force) == 0) {
        return 0;
    }
    printf("rmake: %d built, %d up to date\n", c.built, c.skipped);
    return 1;
}

fn sib_rsi(c: &mut Ctx, i: i64) -> ptr<u8> {
    let p: ptr<u8> = ob(c.bp, c.tg[i].src);
    let n: i64 = sl(p);
    var k: i64 = n - 1;
    var cut: i64 = n;
    while (k >= 0) {
        let v: u8 = rd8(p, k);
        if (v == SLASH || v == BSLASH) {
            k = -1;
        } else if (v == PERIOD) {
            cut = k;
            k = -1;
        } else {
            k -= 1;
        }
    }
    if (tp_room(c, TS4, cut + 4) == 0) {
        return p;
    }
    var m: i64 = 0;
    while (m < cut) {
        wr8(c.tp, TS4 + m, rd8(p, m));
        m += 1;
    }
    m = tp_put(c, TS4 + cut, ".rsi");
    if (m < 0) {
        return p;
    }
    wr8(c.tp, m, 0);
    return ob(c.tp, TS4);
}

fn clean_all(c: &mut Ctx) -> i32 {
    var k: i64 = 0;
    while (k < c.nt) {
        let i: i64 = k;
        if (mk_out(c, i) == 0) {
            return 0;
        }
        let out: ptr<u8> = ob(c.bp, c.tg[i].out);
        let stamp: ptr<u8> = stamp_path(c, i);
        if (remove(out) == 0) {
            printf("  rm    %s\n", out);
        }
        remove(stamp);
        let rsi: ptr<u8> = sib_rsi(c, i);
        if (sq(rsi, ob(c.bp, c.tg[i].src)) == 1) {
            remove(rsi);
        }
        k += 1;
    }
    return 1;
}

fn list_all(c: &mut Ctx) -> i32 {
    var i: i64 = 0;
    while (i < c.nt) {
        if (mk_out(c, i) == 0) {
            return 0;
        }
        var kind: ptr<u8> = "exe";
        if (c.tg[i].kind == KIND_TEST) {
            kind = "test";
        }
        printf("%-6s %s\n", kind, ob(c.bp, c.tg[i].name));
        printf("       src  %s\n", ob(c.bp, c.tg[i].src));
        printf("       out  %s\n", ob(c.bp, c.tg[i].out));
        printf("       tgt  %s\n", ob(c.bp, c.tg[i].plat));
        if (c.tg[i].ndeps > 0) {
            printf("       deps");
            var k: i64 = 0;
            while (k < c.tg[i].ndeps) {
                printf(" %s", ob(c.bp, c.dep[c.tg[i].dep0 + k]));
                k += 1;
            }
            printf("\n");
        }
        i += 1;
    }
    return 1;
}

fn exec_out(c: &mut Ctx, i: i64) -> i32 {
    let out: ptr<u8> = ob(c.bp, c.tg[i].out);
    cmd_begin(c);
    cmd_arg(c, out);
    let rc: i32 = spawn(c);
    return rc_ok(rc);
}

fn run_one(c: &mut Ctx, o: i64) -> i32 {
    let j: i64 = find_tgt(c, o);
    if (j < 0) {
        printf("rmake: no target named '%s'\n", ob(c.bp, o));
        return 0;
    }
    if (order(c, j) == 0) {
        return 0;
    }
    if (build_seq(c, 0) == 0) {
        return 0;
    }
    let name: ptr<u8> = ob(c.bp, c.tg[j].name);
    printf("rmake: run %s\n", name);
    if (exec_out(c, j) == 0) {
        printf("rmake: '%s' exited non-zero\n", name);
        return 0;
    }
    return 1;
}

fn run_tests(c: &mut Ctx) -> i32 {
    if (order(c, -1) == 0) {
        return 0;
    }
    if (build_seq(c, 0) == 0) {
        return 0;
    }
    var pass: i32 = 0;
    var fail: i32 = 0;
    var i: i64 = 0;
    while (i < c.nt) {
        if (c.tg[i].kind == KIND_TEST) {
            let name: ptr<u8> = ob(c.bp, c.tg[i].name);
            printf("  test  %s\n", name);
            if (exec_out(c, i) == 1) {
                pass += 1;
            } else {
                printf("rmake: test '%s' failed\n", name);
                fail += 1;
            }
        }
        i += 1;
    }
    printf("rmake: %d passed, %d failed\n", pass, fail);
    if (fail > 0) {
        return 0;
    }
    return 1;
}

fn usage() {
    printf("rmake - build tool for R#\n");
    printf("usage: rmake <command> [options]\n");
    printf("       build      compile every target\n");
    printf("       rebuild    compile every target, ignoring stamps\n");
    printf("       test       build, then run every [test] target\n");
    printf("       run NAME   build NAME and its deps, then run it\n");
    printf("       clean      remove every artifact and stamp\n");
    printf("       list       show targets and their dependencies\n");
    printf("       install P  fetch, verify, and unpack package P into lib/\n");
    printf("       remove P   delete package P and its files\n");
    printf("       packages   list installed packages\n");
    printf("options:\n");
    printf("       --rsc PATH       rsc launcher (default: rsc on PATH)\n");
    printf("       --manifest PATH  build file (default: RMakefile)\n");
    printf("       --outdir DIR     artifact directory (default: build)\n");
    printf("       --tgt PLATFORM   build for windows, macos, linux, or vm\n");
    printf("                        (targets with their own tgt keep it)\n");
    printf("       --repo URL       package repository\n");
    printf("                        (default: https://www.plaguevm.publicvm.com/basicRresp)\n");
    printf("                        RMAKE_REPO sets the same thing\n");
}
