include "build.rsx";

fn main() -> i32 {
    var c: Ctx;
    c.bp = zalloc(ARENA);
    c.mp = zalloc(MBUF);
    c.lp = zalloc(LBUF);
    c.cp = zalloc(CBUF);
    c.tp = zalloc(TBUF);
    if (c.bp == null || c.mp == null || c.lp == null || c.cp == null || c.tp == null) {
        printf("rmake: out of memory\n");
        return 1;
    }
    c.win = host_win();
    c.cur = -1;
    var hostp: ptr<u8> = "linux";
    if (c.win == 1) {
        hostp = "windows";
    }
    let hp: i64 = intern_str(&mut c, hostp);
    c.hostplat = hp;
    let r: i64 = intern_str(&mut c, "rsc");
    c.rsc = r;
    let o: i64 = intern_str(&mut c, "build");
    c.outdir = o;
    let m: i64 = intern_str(&mut c, "RMakefile");
    c.man = m;
    c.man_def = 1;
    load_args(&mut c);
    if (c.err == 1) {
        return 1;
    }

    var ov_rsc: i64 = 0;
    var ov_out: i64 = 0;
    var ov_tgt: i64 = 0;
    var ov_man: i64 = 0;
    var pos: [i64; 4];
    var npos: i64 = 0;
    var i: i64 = 0;
    while (i < c.nargs) {
        let a: i64 = c.args[i];
        let ap: ptr<u8> = ob(c.bp, a);
        if (sq(ap, "--rsc") == 1) {
            i += 1;
            if (i < c.nargs) {
                ov_rsc = c.args[i];
            }
        } else if (sq(ap, "--outdir") == 1) {
            i += 1;
            if (i < c.nargs) {
                ov_out = c.args[i];
            }
        } else if (sq(ap, "--tgt") == 1) {
            i += 1;
            if (i < c.nargs) {
                ov_tgt = c.args[i];
            }
        } else if (sq(ap, "--manifest") == 1) {
            i += 1;
            if (i < c.nargs) {
                ov_man = c.args[i];
            }
        } else if (npos < 4) {
            pos[npos] = a;
            npos += 1;
        }
        i += 1;
    }
    if (npos == 0) {
        usage();
        return 2;
    }
    if (ov_man != 0) {
        c.man = ov_man;
        c.man_def = 0;
    }
    let cmd: ptr<u8> = ob(c.bp, pos[0]);
    if (sq(cmd, "help") == 1 || sq(cmd, "--help") == 1 || sq(cmd, "-h") == 1) {
        usage();
        return 0;
    }
    let lr: i32 = load_manifest(&mut c);
    if (lr != 1) {
        if (lr == -1) {
            return 3;
        }
        return 1;
    }
    if (ov_rsc != 0) {
        c.rsc = ov_rsc;
    }
    if (ov_out != 0) {
        c.outdir = ov_out;
    }
    if (ov_tgt != 0) {
        c.hostplat = ov_tgt;
    }
    if (check(&mut c) == 0) {
        return 1;
    }
    if (c.win == 1) {
        system("if not exist .rmake mkdir .rmake");
    } else {
        system("mkdir -p .rmake");
    }

    if (sq(cmd, "build") == 1) {
        if (build_all(&mut c, 0) == 0) {
            return 1;
        }
        return 0;
    }
    if (sq(cmd, "rebuild") == 1) {
        if (build_all(&mut c, 1) == 0) {
            return 1;
        }
        return 0;
    }
    if (sq(cmd, "test") == 1) {
        if (run_tests(&mut c) == 0) {
            return 1;
        }
        return 0;
    }
    if (sq(cmd, "list") == 1) {
        if (list_all(&mut c) == 0) {
            return 1;
        }
        return 0;
    }
    if (sq(cmd, "clean") == 1) {
        if (clean_all(&mut c) == 0) {
            return 1;
        }
        printf("rmake: clean\n");
        return 0;
    }
    if (sq(cmd, "run") == 1) {
        if (npos < 2) {
            printf("rmake: run needs a target name\n");
            return 2;
        }
        if (run_one(&mut c, pos[1]) == 0) {
            return 1;
        }
        return 0;
    }
    usage();
    return 2;
}
