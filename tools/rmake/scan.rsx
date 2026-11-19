include "base.rsx";

fn mix(h: u64, b: u8) -> u64 {
    return (h ^ (b as u64)) * 1099511628211;
}

fn mix_buf(h: u64, p: ptr<u8>, n: i64) -> u64 {
    var x: u64 = h;
    var k: i64 = 0;
    while (k < n) {
        x = mix(x, rd8(p, k));
        k += 1;
    }
    return x;
}

fn mix_str(h: u64, p: ptr<u8>) -> u64 {
    let n: i64 = sl(p);
    var x: u64 = mix_buf(h, p, n);
    x = mix(x, 255);
    return x;
}

fn isfile(p: ptr<u8>) -> i32 {
    let f: ptr<u8> = fopen(p, "rb");
    if (f == null) {
        return 0;
    }
    fclose(f);
    return 1;
}

fn intern(c: &mut Ctx, p: ptr<u8>, a: i64, b: i64) -> i64 {
    let len: i64 = b - a;
    if (c.at + len + 2 > ARENA) {
        printf("rmake: string arena exhausted\n");
        c.err = 1;
        return 0;
    }
    let o: i64 = c.at;
    var k: i64 = a;
    while (k < b) {
        wr8(c.bp, c.at, rd8(p, k));
        c.at += 1;
        k += 1;
    }
    wr8(c.bp, c.at, 0);
    c.at += 1;
    return o;
}

fn intern_str(c: &mut Ctx, p: ptr<u8>) -> i64 {
    return intern(c, p, 0, sl(p));
}

fn dir_of(c: &mut Ctx, path: i64) -> i64 {
    let p: ptr<u8> = ob(c.bp, path);
    let n: i64 = sl(p);
    var k: i64 = n - 1;
    var cut: i64 = 0;
    var hit: i32 = 0;
    while (k >= 0) {
        let v: u8 = rd8(p, k);
        if (v == SLASH || v == BSLASH) {
            cut = k;
            hit = 1;
            k = -1;
        } else {
            k -= 1;
        }
    }
    if (hit == 0) {
        cut = 0;
    }
    if (cut >= TS3 - TS2) {
        printf("rmake: directory part of '%s' is too long\n", p);
        c.err = 1;
        return 0;
    }
    var j: i64 = 0;
    while (j < cut) {
        wr8(c.tp, TS2 + j, rd8(p, j));
        j += 1;
    }
    wr8(c.tp, TS2 + cut, 0);
    return cut;
}

fn root_len(dirp: ptr<u8>, dlen: i64) -> i64 {
    if (dlen >= 2 && rd8(dirp, 1) == COLON) {
        return 2;
    }
    if (dlen >= 1 && rd8(dirp, 0) == SLASH) {
        return 1;
    }
    return 0;
}

fn drop_dir(dirp: ptr<u8>, dlen: i64, root: i64) -> i64 {
    var k: i64 = dlen - 1;
    while (k >= 1) {
        let v: u8 = rd8(dirp, k);
        if (v == SLASH || v == BSLASH) {
            return k;
        }
        k -= 1;
    }
    return root;
}

fn cand(c: &mut Ctx, dirp: ptr<u8>, dlen: i64, midp: ptr<u8>, namep: ptr<u8>) -> ptr<u8> {
    var need: i64 = dlen + sl(namep) + 3;
    if (midp != null) {
        need += sl(midp);
    }
    if (need > TS2) {
        printf("rmake: path too long while resolving '%s'\n", namep);
        c.err = 1;
        wr8(c.tp, TS1, 0);
        return ob(c.tp, TS1);
    }
    var n: i64 = 0;
    var k: i64 = 0;
    while (k < dlen) {
        wr8(c.tp, TS1 + n, rd8(dirp, k));
        n += 1;
        k += 1;
    }
    if (midp != null) {
        if (dlen > 0) {
            wr8(c.tp, TS1 + n, SLASH);
            n += 1;
        }
        let mn: i64 = sl(midp);
        k = 0;
        while (k < mn) {
            wr8(c.tp, TS1 + n, rd8(midp, k));
            n += 1;
            k += 1;
        }
        wr8(c.tp, TS1 + n, SLASH);
        n += 1;
    } else {
        if (dlen > 0) {
            wr8(c.tp, TS1 + n, SLASH);
            n += 1;
        }
    }
    let nn: i64 = sl(namep);
    k = 0;
    while (k < nn) {
        wr8(c.tp, TS1 + n, rd8(namep, k));
        n += 1;
        k += 1;
    }
    wr8(c.tp, TS1 + n, 0);
    return ob(c.tp, TS1);
}

fn resolve(c: &mut Ctx, from: i64, name: i64) -> i64 {
    let dlen: i64 = dir_of(c, from);
    if (c.err != 0) {
        return 0;
    }
    let dirp: ptr<u8> = ob(c.tp, TS2);
    let namep: ptr<u8> = ob(c.bp, name);
    let first: ptr<u8> = cand(c, dirp, dlen, null, namep);
    if (c.err != 0) {
        return 0;
    }
    if (isfile(first) == 1) {
        return intern_str(c, first);
    }
    let root: i64 = root_len(dirp, dlen);
    var d: i64 = dlen;
    while (1 == 1) {
        let probe: ptr<u8> = cand(c, dirp, d, "lib", namep);
        if (c.err != 0) {
            return 0;
        }
        if (isfile(probe) == 1) {
            return intern_str(c, probe);
        }
        if (d <= root) {
            break;
        }
        d = drop_dir(dirp, d, root);
    }
    if (isfile(namep) == 1) {
        return intern_str(c, namep);
    }
    return 0;
}

fn inc_head(p: ptr<u8>, n: i64, inblk: i32) -> i32 {
    if (inblk != 0) {
        return 0;
    }
    var i: i64 = 0;
    while (i < n && ws(rd8(p, i)) == 1) {
        i += 1;
    }
    if (i + 8 > n) {
        return 0;
    }
    if (sn(ob(p, i), "include", 7) == 0) {
        return 0;
    }
    if (ws(rd8(p, i + 7)) != 1) {
        return 0;
    }
    i += 7;
    while (i < n && ws(rd8(p, i)) == 1) {
        i += 1;
    }
    if (i >= n || rd8(p, i) != QUOTE) {
        return 0;
    }
    i += 1;
    while (i < n) {
        if (rd8(p, i) == QUOTE) {
            return 1;
        }
        i += 1;
    }
    return 0;
}

fn inc_scan(p: ptr<u8>, n: i64, inblk: i32) -> i32 {
    var blk: i32 = inblk;
    var ins: i32 = 0;
    var i: i64 = 0;
    while (i < n) {
        if (blk == 1) {
            if (i + 1 < n && rd8(p, i) == STAR && rd8(p, i + 1) == SLASH) {
                blk = 0;
                i += 2;
            } else {
                i += 1;
            }
        } else if (ins == 1) {
            if (rd8(p, i) == BSLASH) {
                i += 2;
            } else if (rd8(p, i) == QUOTE) {
                ins = 0;
                i += 1;
            } else {
                i += 1;
            }
        } else if (rd8(p, i) == QUOTE) {
            ins = 1;
            i += 1;
        } else if (i + 1 < n && rd8(p, i) == SLASH && rd8(p, i + 1) == SLASH) {
            return blk;
        } else if (i + 1 < n && rd8(p, i) == SLASH && rd8(p, i + 1) == STAR) {
            blk = 1;
            i += 2;
        } else {
            i += 1;
        }
    }
    return blk;
}

fn inc_name(c: &mut Ctx, p: ptr<u8>, n: i64) -> i64 {
    var i: i64 = 0;
    while (i < n && ws(rd8(p, i)) == 1) {
        i += 1;
    }
    i += 7;
    while (i < n && ws(rd8(p, i)) == 1) {
        i += 1;
    }
    if (i >= n || rd8(p, i) != QUOTE) {
        return 0;
    }
    i += 1;
    let a: i64 = i;
    while (i < n && rd8(p, i) != QUOTE) {
        i += 1;
    }
    if (i >= n || i == a) {
        return 0;
    }
    return intern(c, p, a, i);
}

fn walk(c: &mut Ctx, path: i64, depth: i64, h: u64) -> u64 {
    if (depth > 16) {
        printf("rmake: includes nested more than 16 deep, here at '%s'\n", ob(c.bp, path));
        c.err = 1;
        return h;
    }
    var k: i64 = 0;
    while (k < c.nseen) {
        if (sq(ob(c.bp, c.seen[k]), ob(c.bp, path)) == 1) {
            return h;
        }
        k += 1;
    }
    if (c.nseen >= NSEEN) {
        printf("rmake: include set too large\n");
        c.err = 1;
        return h;
    }
    c.seen[c.nseen] = path;
    c.nseen += 1;
    let buf: ptr<u8> = c.lp;
    let f: ptr<u8> = fopen(ob(c.bp, path), "rb");
    if (f == null) {
        printf("rmake: cannot read '%s'\n", ob(c.bp, path));
        c.err = 1;
        return h;
    }
    var x: u64 = mix_str(h, ob(c.bp, path));
    var blk: i32 = 0;
    var line: ptr<u8> = fgets(buf, MAXL, f);
    while (line != null) {
        let n: i64 = sl(buf);
        x = mix_buf(x, buf, n);
        let found: i32 = inc_head(buf, n, blk);
        blk = inc_scan(buf, n, blk);
        if (found == 1) {
            let nm: i64 = inc_name(c, buf, n);
            if (nm != 0) {
                let res: i64 = resolve(c, path, nm);
                if (c.err != 0) {
                    return h;
                }
                if (res == 0) {
                    printf("rmake: %s: cannot find include '%s'\n", ob(c.bp, path), ob(c.bp, nm));
                    c.err = 1;
                } else {
                    x = walk(c, res, depth + 1, x);
                }
            }
        }
        line = fgets(buf, MAXL, f);
    }
    fclose(f);
    return x;
}

fn hash_file(c: &mut Ctx, path: i64, h: u64) -> u64 {
    let f: ptr<u8> = fopen(ob(c.bp, path), "rb");
    if (f == null) {
        printf("rmake: cannot read '%s'\n", ob(c.bp, path));
        c.err = 1;
        return h;
    }
    var x: u64 = mix_str(h, ob(c.bp, path));
    let buf: ptr<u8> = ob(c.tp, TS1);
    var got: u64 = fread(buf, 1, 1024, f);
    while (got > 0) {
        x = mix_buf(x, buf, got as i64);
        got = fread(buf, 1, 1024, f);
    }
    fclose(f);
    return x;
}
