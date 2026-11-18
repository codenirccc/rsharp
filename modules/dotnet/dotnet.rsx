extern "kernel32" fn LoadLibraryA(path: ptr<u8>) -> ptr<u8>;
extern "kernel32" fn FreeLibrary(module: ptr<u8>) -> i32;
extern "kernel32" fn GetProcAddress(module: ptr<u8>, name: ptr<u8>) -> ptr<u8>;
extern "kernel32" fn GetFileAttributesA(path: ptr<u8>) -> u32;
extern "kernel32" fn GetEnvironmentVariableA(name: ptr<u8>, dst: ptr<u8>, cap: u32) -> u32;
extern "kernel32" fn FindFirstFileA(pattern: ptr<u8>, data: ptr<u8>) -> ptr<u8>;
extern "kernel32" fn FindNextFileA(handle: ptr<u8>, data: ptr<u8>) -> i32;
extern "kernel32" fn FindClose(handle: ptr<u8>) -> i32;
extern fn printf(fmt: ptr<u8>, ...) -> i32;

struct ClrHost {
    module: ptr<u8>,
    handle: ptr<u8>,
    load16: ptr<u8>
}

fn clr_str_put(dst: ptr<u8>, cap: i64, off: ptr<i64>, s: ptr<u8>) -> i64 {
    unsafe {
        if (cap < 2) {
            return 0;
        }
        let base: i64 = off[0];
        var i: i64 = 0;
        while (s[i] != 0) {
            if (base + i + 1 >= cap) {
                dst[cap - 1] = 0;
                return 0;
            }
            dst[base + i] = s[i];
            i += 1;
        }
        dst[base + i] = 0;
        off[0] = base + i;
        return 1;
    }
}

fn clr_utf8_to_utf16(src: ptr<u8>, dst: ptr<u16>, cap: i64) -> i64 {
    unsafe {
        if (cap < 1) {
            return 0 - 1;
        }
        var i: i64 = 0;
        var o: i64 = 0;
        while (src[i] != 0) {
            let b: i64 = src[i] as i64;
            var cp: i64 = 0;
            var n: i64 = 0;
            if (b < 0x80) {
                cp = b;
                n = 1;
            } else if (b >= 0xC2 && b <= 0xDF) {
                cp = b & 0x1F;
                n = 2;
            } else if (b >= 0xE0 && b <= 0xEF) {
                cp = b & 0x0F;
                n = 3;
            } else if (b >= 0xF0 && b <= 0xF4) {
                cp = b & 0x07;
                n = 4;
            } else {
                return 0 - 2;
            }
            var k: i64 = 1;
            while (k < n) {
                let c: i64 = src[i + k] as i64;
                if (c < 0x80 || c > 0xBF) {
                    return 0 - 2;
                }
                cp = (cp << 6) | (c & 0x3F);
                k += 1;
            }
            if ((n == 3 && cp < 0x800) || (n == 4 && (cp < 0x10000 || cp > 0x10FFFF))) {
                return 0 - 2;
            }
            if (cp >= 0xD800 && cp <= 0xDFFF) {
                return 0 - 2;
            }
            i += n;
            if (cp >= 0x10000) {
                if (o + 2 >= cap) {
                    return 0 - 1;
                }
                cp = cp - 0x10000;
                dst[o] = (0xD800 | (cp >> 10)) as u16;
                dst[o + 1] = (0xDC00 | (cp & 0x3FF)) as u16;
                o += 2;
            } else {
                if (o + 1 >= cap) {
                    return 0 - 1;
                }
                dst[o] = cp as u16;
                o += 1;
            }
        }
        dst[o] = 0;
        return o;
    }
}

fn clr_utf16_to_utf8(src: ptr<u16>, dst: ptr<u8>, cap: i64) -> i64 {
    unsafe {
        if (cap < 1) {
            return 0 - 1;
        }
        var i: i64 = 0;
        var o: i64 = 0;
        while (src[i] != 0) {
            var u: i64 = src[i] as i64;
            if (u >= 0xD800 && u < 0xDC00 && src[i + 1] != 0) {
                let lo: i64 = src[i + 1] as i64;
                if (lo >= 0xDC00 && lo < 0xE000) {
                    u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00);
                    i += 1;
                }
            }
            i += 1;
            if (u < 0x80) {
                if (o + 1 >= cap) {
                    return 0 - 1;
                }
                dst[o] = u as u8;
                o += 1;
            } else if (u < 0x800) {
                if (o + 2 >= cap) {
                    return 0 - 1;
                }
                dst[o] = (0xC0 | (u >> 6)) as u8;
                dst[o + 1] = (0x80 | (u & 0x3F)) as u8;
                o += 2;
            } else if (u < 0x10000) {
                if (o + 3 >= cap) {
                    return 0 - 1;
                }
                dst[o] = (0xE0 | (u >> 12)) as u8;
                dst[o + 1] = (0x80 | ((u >> 6) & 0x3F)) as u8;
                dst[o + 2] = (0x80 | (u & 0x3F)) as u8;
                o += 3;
            } else {
                if (o + 4 >= cap) {
                    return 0 - 1;
                }
                dst[o] = (0xF0 | (u >> 18)) as u8;
                dst[o + 1] = (0x80 | ((u >> 12) & 0x3F)) as u8;
                dst[o + 2] = (0x80 | ((u >> 6) & 0x3F)) as u8;
                dst[o + 3] = (0x80 | (u & 0x3F)) as u8;
                o += 4;
            }
        }
        dst[o] = 0;
        return o;
    }
}

fn clr_ver_part(s: ptr<u8>, pos: ptr<i64>) -> i64 {
    unsafe {
        var v: i64 = 0;
        while (s[pos[0]] >= 0x30 && s[pos[0]] <= 0x39) {
            v = v * 10 + (s[pos[0]] as i64 - 0x30);
            pos[0] = pos[0] + 1;
        }
        if (s[pos[0]] == 0x2E) {
            pos[0] = pos[0] + 1;
        }
        return v;
    }
}

fn clr_ver_cmp(a: ptr<u8>, b: ptr<u8>) -> i64 {
    var ia: [i64; 1] = [0];
    var ib: [i64; 1] = [0];
    var pap: ptr<i64> = null;
    var pbp: ptr<i64> = null;
    unsafe {
        pap = &mut ia[0] as ptr<i64>;
        pbp = &mut ib[0] as ptr<i64>;
    }
    var k: i64 = 0;
    while (k < 4) {
        unsafe {
            ia[0] = 0;
            ib[0] = 0;
        }
        let pa: i64 = clr_ver_part(a, pap);
        let pb: i64 = clr_ver_part(b, pbp);
        if (pa != pb) {
            return pa - pb;
        }
        k += 1;
    }
    return 0;
}

fn clr_file_exists(path: ptr<u8>) -> i64 {
    unsafe {
        if (GetFileAttributesA(path) == 0xFFFFFFFF) {
            return 0;
        }
        return 1;
    }
}

fn clr_pick_version(root: ptr<u8>, name: ptr<u8>, cap: i64) -> i64 {
    var pattern: [u8; 512] = [0];
    var data: [u8; 1024] = [0];
    var off: [i64; 1] = [0];
    var pp: ptr<u8> = null;
    var dp: ptr<u8> = null;
    var op: ptr<i64> = null;
    unsafe {
        pp = &pattern[0] as ptr<u8>;
        dp = &data[0] as ptr<u8>;
        op = &mut off[0] as ptr<i64>;
    }
    if (clr_str_put(pp, 512, op, root) == 0) {
        return 0;
    }
    if (clr_str_put(pp, 512, op, "\\host\\fxr\\*") == 0) {
        return 0;
    }
    unsafe {
        var find: ptr<u8> = FindFirstFileA(pp, dp);
        if (find == (0 - 1) as ptr<u8> || find == null) {
            return 0;
        }
        var best: i64 = 0;
        var o: [i64; 1] = [0];
        var copy: ptr<i64> = null;
        copy = &mut o[0] as ptr<i64>;
        while (true) {
            let attrs: u32 = (data[0] as u32) | ((data[1] as u32) << 8) | ((data[2] as u32) << 16) | ((data[3] as u32) << 24);
            let entry: ptr<u8> = &data[44] as ptr<u8>;
            if ((attrs & 0x10) != 0 && entry[0] != 0x2E) {
                if (best == 0 || clr_ver_cmp(entry, name) > 0) {
                    o[0] = 0;
                    if (clr_str_put(name, cap, copy, entry) == 1) {
                        best = 1;
                    }
                }
            }
            if (FindNextFileA(find, dp) == 0) {
                break;
            }
        }
        FindClose(find);
        return best;
    }
}

fn clr_fxr_in(root: ptr<u8>, dst: ptr<u8>, cap: i64) -> i64 {
    var ver: [u8; 128] = [0];
    var vp: ptr<u8> = null;
    unsafe { vp = &ver[0] as ptr<u8>; }
    if (clr_pick_version(root, vp, 128) == 0) {
        return 0;
    }
    var off: [i64; 1] = [0];
    var op: ptr<i64> = null;
    unsafe { op = &mut off[0] as ptr<i64>; }
    if (clr_str_put(dst, cap, op, root) == 0) {
        return 0;
    }
    if (clr_str_put(dst, cap, op, "\\host\\fxr\\") == 0) {
        return 0;
    }
    if (clr_str_put(dst, cap, op, vp) == 0) {
        return 0;
    }
    if (clr_str_put(dst, cap, op, "\\hostfxr.dll") == 0) {
        return 0;
    }
    if (clr_file_exists(dst) == 0) {
        return 0;
    }
    unsafe {
        return off[0];
    }
}

fn clr_fxr_path(dst: ptr<u8>, cap: i64) -> i64 {
    var env: [u8; 512] = [0];
    var ep: ptr<u8> = null;
    unsafe { ep = &env[0] as ptr<u8>; }
    unsafe {
        let got: u32 = GetEnvironmentVariableA("DOTNET_ROOT" as ptr<u8>, ep, 512);
        if (got > 0 && got < 512) {
            if (clr_fxr_in(ep, dst, cap) > 0) {
                return 1;
            }
        }
    }
    if (clr_fxr_in("C:\\Program Files\\dotnet" as ptr<u8>, dst, cap) > 0) {
        return 1;
    }
    if (clr_fxr_in("C:\\Program Files (x86)\\dotnet" as ptr<u8>, dst, cap) > 0) {
        return 1;
    }
    var pf: [u8; 512] = [0];
    var pfp: ptr<u8> = null;
    unsafe { pfp = &pf[0] as ptr<u8>; }
    unsafe {
        let got: u32 = GetEnvironmentVariableA("ProgramFiles" as ptr<u8>, pfp, 512);
        if (got > 0 && got < 512) {
            var root: [u8; 512] = [0];
            var off: [i64; 1] = [0];
            var rp: ptr<u8> = null;
            var op: ptr<i64> = null;
            rp = &root[0] as ptr<u8>;
            op = &mut off[0] as ptr<i64>;
            if (clr_str_put(rp, 512, op, pfp) == 1 && clr_str_put(rp, 512, op, "\\dotnet") == 1) {
                if (clr_fxr_in(rp, dst, cap) > 0) {
                    return 1;
                }
            }
        }
    }
    return 0;
}

fn clr_host_open(cfg_utf8: ptr<u8>) -> ClrHost {
    var h: ClrHost = zero(ClrHost);
    var path: [u8; 1024] = [0];
    var pp: ptr<u8> = null;
    unsafe { pp = &path[0] as ptr<u8>; }
    if (clr_fxr_path(pp, 1024) == 0) {
        printf("clr: no hostfxr.dll on this host\n");
        return h;
    }
    unsafe {
        h.module = LoadLibraryA(pp);
    }
    if (h.module == null) {
        printf("clr: LoadLibraryA failed for %s\n", pp);
        return h;
    }
    var cfg16: [u16; 1024] = [0];
    var cp: ptr<u16> = null;
    unsafe { cp = &cfg16[0] as ptr<u16>; }
    if (clr_utf8_to_utf16(cfg_utf8, cp, 1024) < 0) {
        printf("clr: runtime config path is too long or not valid UTF-8\n");
        unsafe { FreeLibrary(h.module); }
        h.module = null;
        return h;
    }
    var name_init: [u8; 64] = [0];
    var name_delegate: [u8; 64] = [0];
    var off: [i64; 1] = [0];
    var op: ptr<i64> = null;
    var ip: ptr<u8> = null;
    var gp: ptr<u8> = null;
    unsafe {
        op = &mut off[0] as ptr<i64>;
        ip = &name_init[0] as ptr<u8>;
        gp = &name_delegate[0] as ptr<u8>;
    }
    if (clr_str_put(ip, 64, op, "hostfxr_initialize_for_runtime_config") == 0) {
        printf("clr: export name is too long\n");
        unsafe { FreeLibrary(h.module); }
        h.module = null;
        return h;
    }
    unsafe { off[0] = 0; }
    if (clr_str_put(gp, 64, op, "hostfxr_get_runtime_delegate") == 0) {
        printf("clr: export name is too long\n");
        unsafe { FreeLibrary(h.module); }
        h.module = null;
        return h;
    }
    unsafe {
        let init_ptr: ptr<u8> = GetProcAddress(h.module, ip);
        let delegate_ptr: ptr<u8> = GetProcAddress(h.module, gp);
        if (init_ptr == null || delegate_ptr == null) {
            printf("clr: hostfxr exports missing\n");
            FreeLibrary(h.module);
            h.module = null;
            return h;
        }
        var init: extern fn(ptr<u16>, ptr<u8>, ptr<ptr<u8>>) -> i32 = init_ptr as extern fn(ptr<u16>, ptr<u8>, ptr<ptr<u8>>) -> i32;
        var get_delegate: extern fn(ptr<u8>, i32, ptr<ptr<u8>>) -> i32 = delegate_ptr as extern fn(ptr<u8>, i32, ptr<ptr<u8>>) -> i32;
        let rc: i32 = init(cp, null, &mut h.handle as ptr<ptr<u8>>);
        if (rc < 0) {
            printf("clr: hostfxr_initialize_for_runtime_config rc=0x%08X\n", rc);
            FreeLibrary(h.module);
            h.module = null;
            h.handle = null;
            return h;
        }
        var load_ptr: ptr<u8> = null;
        let drc: i32 = get_delegate(h.handle, 5, &mut load_ptr as ptr<ptr<u8>>);
        if (drc < 0 || load_ptr == null) {
            printf("clr: hostfxr_get_runtime_delegate rc=0x%08X\n", drc);
            FreeLibrary(h.module);
            h.module = null;
            h.handle = null;
            return h;
        }
        h.load16 = load_ptr;
    }
    return h;
}

fn clr_host_find(h: &ClrHost, assembly: ptr<u8>, type_name: ptr<u8>, method: ptr<u8>, delegate_name: ptr<u8>) -> ptr<u8> {
    var asm16: [u16; 1024] = [0];
    var type16: [u16; 512] = [0];
    var meth16: [u16; 256] = [0];
    var del16: [u16; 512] = [0];
    var ap: ptr<u16> = null;
    var tp: ptr<u16> = null;
    var mp: ptr<u16> = null;
    var dp: ptr<u16> = null;
    unsafe {
        ap = &asm16[0] as ptr<u16>;
        tp = &type16[0] as ptr<u16>;
        mp = &meth16[0] as ptr<u16>;
        dp = &del16[0] as ptr<u16>;
    }
    if (clr_utf8_to_utf16(assembly, ap, 1024) < 0) {
        printf("clr: assembly path is too long or not valid UTF-8\n");
        return null;
    }
    if (clr_utf8_to_utf16(type_name, tp, 512) < 0) {
        printf("clr: type name is too long or not valid UTF-8\n");
        return null;
    }
    if (clr_utf8_to_utf16(method, mp, 256) < 0) {
        printf("clr: method name is too long or not valid UTF-8\n");
        return null;
    }
    if (delegate_name != null && clr_utf8_to_utf16(delegate_name, dp, 512) < 0) {
        printf("clr: delegate type name is too long or not valid UTF-8\n");
        return null;
    }
    if (h.load16 == null) {
        printf("clr: host is not open\n");
        return null;
    }
    var fn_ptr: ptr<u8> = null;
    unsafe {
        var load: extern fn(ptr<u16>, ptr<u16>, ptr<u16>, ptr<u16>, ptr<u8>, ptr<ptr<u8>>) -> i32 =
            h.load16 as extern fn(ptr<u16>, ptr<u16>, ptr<u16>, ptr<u16>, ptr<u8>, ptr<ptr<u8>>) -> i32;
        var del: ptr<u16> = dp;
        if (delegate_name == null) {
            del = (0 - 1) as ptr<u16>;
        }
        let rc: i32 = load(ap, tp, mp, del, null, &mut fn_ptr as ptr<ptr<u8>>);
        if (rc < 0 || fn_ptr == null) {
            printf("clr: %s rc=0x%08X\n", method, rc);
            return null;
        }
    }
    return fn_ptr;
}

fn clr_host_close(h: &mut ClrHost) {
    var name_close: [u8; 32] = [0];
    var off: [i64; 1] = [0];
    var np: ptr<u8> = null;
    var op: ptr<i64> = null;
    unsafe {
        np = &name_close[0] as ptr<u8>;
        op = &mut off[0] as ptr<i64>;
    }
    if (clr_str_put(np, 32, op, "hostfxr_close") == 0) {
        printf("clr: export name is too long\n");
        return;
    }
    unsafe {
        if (h.handle != null && h.module != null) {
            let close_ptr: ptr<u8> = GetProcAddress(h.module, np);
            if (close_ptr != null) {
                var close: extern fn(ptr<u8>) -> i32 = close_ptr as extern fn(ptr<u8>) -> i32;
                close(h.handle);
            }
        }
        h.handle = null;
        h.load16 = null;
        if (h.module != null) {
            FreeLibrary(h.module);
            h.module = null;
        }
    }
}

fn clr_host_ready(h: &ClrHost) -> bool {
    return h.handle != null && h.load16 != null;
}
