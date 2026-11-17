extern "user32" fn RegisterClassExA(cls: ptr<u8>) -> u16;
extern "user32" fn CreateWindowExA(ex: u32, cls: ptr<u8>, title: ptr<u8>, style: u32,
                                   x: i32, y: i32, w: i32, h: i32,
                                   parent: ptr<u8>, menu: u64, inst: ptr<u8>, param: ptr<u8>) -> ptr<u8>;
extern "user32" fn DestroyWindow(h: ptr<u8>) -> i32;
extern "user32" fn DefWindowProcA(h: ptr<u8>, m: u32, wp: u64, lp: i64) -> i64;
extern "user32" fn GetDC(h: ptr<u8>) -> ptr<u8>;
extern "kernel32" fn GetModuleHandleA(name: ptr<u8>) -> ptr<u8>;
extern "gdi32" fn ChoosePixelFormat(dc: ptr<u8>, pfd: ptr<u8>) -> i32;
extern "gdi32" fn SetPixelFormat(dc: ptr<u8>, fmt: i32, pfd: ptr<u8>) -> i32;
extern "opengl32" fn wglCreateContext(dc: ptr<u8>) -> ptr<u8>;
extern "opengl32" fn wglMakeCurrent(dc: ptr<u8>, ctx: ptr<u8>) -> i32;
extern "opengl32" fn wglDeleteContext(ctx: ptr<u8>) -> i32;
extern "opengl32" fn wglGetProcAddress(name: ptr<u8>) -> ptr<u8>;
extern "opengl32" fn glGetString(name: u32) -> ptr<u8>;
extern "opengl32" fn glViewport(x: i32, y: i32, w: i32, h: i32);
extern "opengl32" fn glClearColor(r: f32, g: f32, b: f32, a: f32);
extern "opengl32" fn glClear(mask: u32);
extern "opengl32" fn glReadPixels(x: i32, y: i32, w: i32, h: i32, fmt: u32, typ: u32, pixels: ptr<u8>);
extern "opengl32" fn glGetIntegerv(name: u32, p: ptr<i32>) -> void;
extern "opengl32" fn glTexImage2D(target: u32, level: i32, internalformat: i32, w: i32, h: i32, border: i32, fmt: u32, typ: u32, pixels: ptr<u8>);
extern "opengl32" fn glTexParameteri(target: u32, pname: u32, param: i32);
extern "opengl32" fn glDrawBuffer(mode: u32);
include "gpu_sys.rsx";

const GW_WM_DESTROY: u32 = 2;
const GW_WM_CLOSE: u32 = 16;

const GL_TRIANGLES: u32 = 0x0004;
const GL_COLOR_BUFFER_BIT: u32 = 0x4000;
const GL_FRAMEBUFFER: u32 = 0x8D40;
const GL_COLOR_ATTACHMENT0: u32 = 0x8CE0;
const GL_FRAMEBUFFER_COMPLETE: u32 = 0x8CD5;
const GL_TEXTURE_2D: u32 = 0x0DE1;
const GL_TEXTURE_MIN_FILTER: u32 = 0x2801;
const GL_TEXTURE_MAG_FILTER: u32 = 0x2800;
const GL_TEXTURE_WRAP_S: u32 = 0x2802;
const GL_TEXTURE_WRAP_T: u32 = 0x2803;
const GL_NEAREST: i32 = 0x2600;
const GL_CLAMP_TO_EDGE: i32 = 0x812F;
const GL_RGBA: u32 = 0x1908;
const GL_RGBA8: i32 = 0x8058;
const GL_UNSIGNED_BYTE: u32 = 0x1401;
const GL_FLOAT: u32 = 0x1406;
const GL_ARRAY_BUFFER: u32 = 0x8892;
const GL_STATIC_DRAW: u32 = 0x88E4;
const GL_VERTEX_SHADER: u32 = 0x8B31;
const GL_FRAGMENT_SHADER: u32 = 0x8B30;
const GL_COMPILE_STATUS: u32 = 0x8B81;
const GL_LINK_STATUS: u32 = 0x8B82;
const GL_VENDOR: u32 = 0x1F00;
const GL_RENDERER: u32 = 0x1F01;
const GL_VERSION: u32 = 0x1F02;

const GLX_CONTEXT_MAJOR_VERSION: i32 = 0x2091;
const GLX_CONTEXT_MINOR_VERSION: i32 = 0x2092;
const GLX_CONTEXT_PROFILE_MASK: i32 = 0x9126;
const GLX_CONTEXT_CORE_PROFILE_BIT: i32 = 1;

struct GWndClass {
    cbSize: u32,
    style: u32,
    proc: ptr<u8>,
    clsExtra: i32,
    wndExtra: i32,
    inst: ptr<u8>,
    icon: ptr<u8>,
    cursor: ptr<u8>,
    brush: ptr<u8>,
    menuName: ptr<u8>,
    className: ptr<u8>,
    iconSm: ptr<u8>
}

struct GPixelFormatDesc {
    nSize: u16,
    nVersion: u16,
    dwFlags: u32,
    iPixelType: u8,
    cColorBits: u8,
    cRedBits: u8,
    cRedShift: u8,
    cGreenBits: u8,
    cGreenShift: u8,
    cBlueBits: u8,
    cBlueShift: u8,
    cAlphaBits: u8,
    cAlphaShift: u8,
    cAccumBits: u8,
    cAccumRedBits: u8,
    cAccumGreenBits: u8,
    cAccumBlueBits: u8,
    cAccumAlphaBits: u8,
    cDepthBits: u8,
    cStencilBits: u8,
    cAuxBuffers: u8,
    iLayerType: u8,
    bReserved: u8,
    dwLayerMask: u32,
    dwVisibleMask: u32,
    dwDamageMask: u32
}

struct GLx {
    hwnd: ptr<u8>,
    dc: ptr<u8>,
    legacy: ptr<u8>,
    ctx: ptr<u8>,
    fbo: u32,
    tex: u32,
    vao: u32,
    vbo: u32,
    prog: u32,
    w: i32,
    h: i32
}

fn gw_proc(h: ptr<u8>, m: u32, wp: u64, lp: i64) -> i64 {
    if (m == GW_WM_CLOSE || m == GW_WM_DESTROY) {
        return 0;
    }
    return DefWindowProcA(h, m, wp, lp);
}

fn glx_load(name: ptr<u8>) -> ptr<u8> {
    unsafe {
        return wglGetProcAddress(name);
    }
}

fn glx_create(w: i32, h: i32) -> GLx {
    var g: GLx = zero(GLx);
    g.w = w;
    g.h = h;
    unsafe {
        var cls: GWndClass = zero(GWndClass);
        cls.cbSize = 80;
        cls.proc = gw_proc as ptr<u8>;
        cls.inst = GetModuleHandleA(null);
        cls.className = "RSharpGLX" as ptr<u8>;
        let atom: u16 = RegisterClassExA(&cls as ptr<u8>);
        if (atom == 0) {
            printf("glx: RegisterClassExA failed\n");
            return g;
        }
        let hwnd: ptr<u8> = CreateWindowExA(0, "RSharpGLX" as ptr<u8>, "rsharp glx" as ptr<u8>,
                                           0x00C00000 | 0x00080000,
                                           0, 0, w, h,
                                           null, 0, cls.inst, null);
        if (hwnd == null) {
            printf("glx: CreateWindowExA failed\n");
            return g;
        }
        let dc: ptr<u8> = GetDC(hwnd);
        var pfd: GPixelFormatDesc = zero(GPixelFormatDesc);
        pfd.nSize = 40;
        pfd.nVersion = 1;
        pfd.dwFlags = 2 | 32 | 1;
        pfd.iPixelType = 0;
        pfd.cColorBits = 32;
        pfd.cDepthBits = 24;
        pfd.cStencilBits = 8;
        pfd.iLayerType = 0;
        let fmt: i32 = ChoosePixelFormat(dc, &pfd as ptr<u8>);
        if (fmt == 0 || SetPixelFormat(dc, fmt, &pfd as ptr<u8>) == 0) {
            printf("glx: pixel format failed\n");
            DestroyWindow(hwnd);
            return g;
        }
        let legacy: ptr<u8> = wglCreateContext(dc);
        if (legacy == null) {
            printf("glx: wglCreateContext failed\n");
            DestroyWindow(hwnd);
            return g;
        }
        if (wglMakeCurrent(dc, legacy) == 0) {
            printf("glx: wglMakeCurrent failed\n");
            DestroyWindow(hwnd);
            return g;
        }
        let pCreateAttribs: ptr<u8> = glx_load("wglCreateContextAttribsARB\0" as ptr<u8>);
        if (pCreateAttribs != null) {
            var attrs: [i32; 9] = [GLX_CONTEXT_MAJOR_VERSION, 3,
                                   GLX_CONTEXT_MINOR_VERSION, 3,
                                   GLX_CONTEXT_PROFILE_MASK, GLX_CONTEXT_CORE_PROFILE_BIT,
                                   0, 0, 0];
            var f: fn(ptr<u8>, ptr<u8>, ptr<i32>) -> ptr<u8> = pCreateAttribs as fn(ptr<u8>, ptr<u8>, ptr<i32>) -> ptr<u8>;
            let ctx: ptr<u8> = f(dc, null, &attrs[0] as ptr<i32>);
            if (ctx != null) {
                wglMakeCurrent(null, null);
                wglDeleteContext(legacy);
                wglMakeCurrent(dc, ctx);
                g.ctx = ctx;
            } else {
                g.ctx = legacy;
            }
        } else {
            g.ctx = legacy;
        }
        g.hwnd = hwnd;
        g.dc = dc;
    }
    return g;
}

fn glx_destroy(g: &mut GLx) {
    unsafe {
        wglMakeCurrent(null, null);
        if (g.ctx != null && g.ctx != g.legacy) {
            wglDeleteContext(g.ctx);
        }
        if (g.legacy != null) {
            wglDeleteContext(g.legacy);
        }
        if (g.hwnd != null) {
            DestroyWindow(g.hwnd);
        }
        g.ctx = null;
        g.legacy = null;
        g.dc = null;
        g.hwnd = null;
    }
}

fn glx_fbo_init(g: &mut GLx) -> i64 {
    var ok: i64 = 0;
    let pGenFramebuffers: ptr<u8> = glx_load("glGenFramebuffers\0" as ptr<u8>);
    let pBindFramebuffer: ptr<u8> = glx_load("glBindFramebuffer\0" as ptr<u8>);
    let pFramebufferTexture2D: ptr<u8> = glx_load("glFramebufferTexture2D\0" as ptr<u8>);
    let pCheckFramebufferStatus: ptr<u8> = glx_load("glCheckFramebufferStatus\0" as ptr<u8>);
    let pGenTextures: ptr<u8> = glx_load("glGenTextures\0" as ptr<u8>);
    let pBindTexture: ptr<u8> = glx_load("glBindTexture\0" as ptr<u8>);
    if (pGenFramebuffers == null || pBindFramebuffer == null || pFramebufferTexture2D == null ||
        pCheckFramebufferStatus == null || pGenTextures == null || pBindTexture == null) {
        printf("glx: fbo entry points missing\n");
        return 0;
    }
    var fbo: u32 = 0;
    var tex: u32 = 0;
    unsafe {
        var genFbo: fn(i32, ptr<u32>) = pGenFramebuffers as fn(i32, ptr<u32>);
        var genTex: fn(i32, ptr<u32>) = pGenTextures as fn(i32, ptr<u32>);
        genFbo(1, &fbo as ptr<u32>);
        genTex(1, &tex as ptr<u32>);
        var bindFbo: fn(u32, u32) = pBindFramebuffer as fn(u32, u32);
        bindFbo(GL_FRAMEBUFFER, fbo);
        var bindTex: fn(u32, u32) = pBindTexture as fn(u32, u32);
        bindTex(GL_TEXTURE_2D, tex);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, g.w, g.h, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        var fbTex: fn(u32, u32, u32, u32, i32) = pFramebufferTexture2D as fn(u32, u32, u32, u32, i32);
        fbTex(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
        glDrawBuffer(GL_COLOR_ATTACHMENT0);
        var checkStatus: fn(u32) -> u32 = pCheckFramebufferStatus as fn(u32) -> u32;
        let status: u32 = checkStatus(GL_FRAMEBUFFER);
        if (status == GL_FRAMEBUFFER_COMPLETE) {
            ok = 1;
        } else {
            printf("glx: framebuffer incomplete 0x%x\n", status);
        }
        bindFbo(GL_FRAMEBUFFER, fbo);
        g.fbo = fbo;
        g.tex = tex;
    }
    return ok;
}

fn glx_shader(src: ptr<u8>, kind: u32) -> u32 {
    let pCreateShader: ptr<u8> = glx_load("glCreateShader\0" as ptr<u8>);
    let pShaderSource: ptr<u8> = glx_load("glShaderSource\0" as ptr<u8>);
    let pCompileShader: ptr<u8> = glx_load("glCompileShader\0" as ptr<u8>);
    let pGetShaderiv: ptr<u8> = glx_load("glGetShaderiv\0" as ptr<u8>);
    let pGetShaderInfoLog: ptr<u8> = glx_load("glGetShaderInfoLog\0" as ptr<u8>);
    let pDeleteShader: ptr<u8> = glx_load("glDeleteShader\0" as ptr<u8>);
    if (pCreateShader == null || pShaderSource == null || pCompileShader == null ||
        pGetShaderiv == null || pGetShaderInfoLog == null || pDeleteShader == null) {
        printf("glx: shader entry points missing\n");
        return 0;
    }
    var createShader: fn(u32) -> u32 = pCreateShader as fn(u32) -> u32;
    let shader: u32 = createShader(kind);
    if (shader == 0) {
        printf("glx: glCreateShader failed\n");
        return 0;
    }
    var shaderSource: fn(u32, u32, ptr<ptr<u8>>, ptr<i32>) = pShaderSource as fn(u32, u32, ptr<ptr<u8>>, ptr<i32>);
    var strings: [ptr<u8>; 1] = [src];
    unsafe {
        shaderSource(shader, 1, (&strings[0]) as ptr<ptr<u8>>, null);
    }
    var compileShader: fn(u32) = pCompileShader as fn(u32);
    compileShader(shader);
    var getShaderiv: fn(u32, u32, ptr<i32>) = pGetShaderiv as fn(u32, u32, ptr<i32>);
    var compiled: i32 = 0;
    unsafe {
        getShaderiv(shader, GL_COMPILE_STATUS, (&mut compiled) as ptr<i32>);
    }
    if (compiled == 1) {
        return shader;
    }
    var getShaderInfoLog: fn(u32, i32, ptr<i32>, ptr<u8>) = pGetShaderInfoLog as fn(u32, i32, ptr<i32>, ptr<u8>);
    var log: [u8; 1024] = [0];
    var length: i32 = 0;
    unsafe {
        getShaderInfoLog(shader, 1024, (&mut length) as ptr<i32>, &log[0] as ptr<u8>);
    }
    var log_s: ptr<u8> = null;
    unsafe {
        log_s = &log[0] as ptr<u8>;
    }
    printf("glx: shader compile failed\n%s\n", log_s);
    var deleteShader: fn(u32) = pDeleteShader as fn(u32);
    deleteShader(shader);
    return 0;
}

fn glx_program(vertex: u32, fragment: u32) -> u32 {
    let pCreateProgram: ptr<u8> = glx_load("glCreateProgram\0" as ptr<u8>);
    let pAttachShader: ptr<u8> = glx_load("glAttachShader\0" as ptr<u8>);
    let pLinkProgram: ptr<u8> = glx_load("glLinkProgram\0" as ptr<u8>);
    let pGetProgramiv: ptr<u8> = glx_load("glGetProgramiv\0" as ptr<u8>);
    let pGetProgramInfoLog: ptr<u8> = glx_load("glGetProgramInfoLog\0" as ptr<u8>);
    let pDeleteProgram: ptr<u8> = glx_load("glDeleteProgram\0" as ptr<u8>);
    if (pCreateProgram == null || pAttachShader == null || pLinkProgram == null ||
        pGetProgramiv == null || pGetProgramInfoLog == null || pDeleteProgram == null) {
        printf("glx: program entry points missing\n");
        return 0;
    }
    var createProgram: fn() -> u32 = pCreateProgram as fn() -> u32;
    let prog: u32 = createProgram();
    if (prog == 0) {
        printf("glx: glCreateProgram failed\n");
        return 0;
    }
    var attachShader: fn(u32, u32) = pAttachShader as fn(u32, u32);
    attachShader(prog, vertex);
    attachShader(prog, fragment);
    var linkProgram: fn(u32) = pLinkProgram as fn(u32);
    linkProgram(prog);
    var getProgramiv: fn(u32, u32, ptr<i32>) = pGetProgramiv as fn(u32, u32, ptr<i32>);
    var linked: i32 = 0;
    unsafe {
        getProgramiv(prog, GL_LINK_STATUS, (&mut linked) as ptr<i32>);
    }
    if (linked == 1) {
        return prog;
    }
    var getProgramInfoLog: fn(u32, i32, ptr<i32>, ptr<u8>) = pGetProgramInfoLog as fn(u32, i32, ptr<i32>, ptr<u8>);
    var log: [u8; 1024] = [0];
    var length: i32 = 0;
    unsafe {
        getProgramInfoLog(prog, 1024, (&mut length) as ptr<i32>, &log[0] as ptr<u8>);
    }
    var log_p: ptr<u8> = null;
    unsafe {
        log_p = &log[0] as ptr<u8>;
    }
    printf("glx: program link failed\n%s\n", log_p);
    var deleteProgram: fn(u32) = pDeleteProgram as fn(u32);
    deleteProgram(prog);
    return 0;
}

fn glx_draw_triangle(g: &mut GLx) {
    let pUseProgram: ptr<u8> = glx_load("glUseProgram\0" as ptr<u8>);
    let pGenVertexArrays: ptr<u8> = glx_load("glGenVertexArrays\0" as ptr<u8>);
    let pBindVertexArray: ptr<u8> = glx_load("glBindVertexArray\0" as ptr<u8>);
    let pGenBuffers: ptr<u8> = glx_load("glGenBuffers\0" as ptr<u8>);
    let pBindBuffer: ptr<u8> = glx_load("glBindBuffer\0" as ptr<u8>);
    let pBufferData: ptr<u8> = glx_load("glBufferData\0" as ptr<u8>);
    let pVertexAttribPointer: ptr<u8> = glx_load("glVertexAttribPointer\0" as ptr<u8>);
    let pEnableVertexAttribArray: ptr<u8> = glx_load("glEnableVertexAttribArray\0" as ptr<u8>);
    let pDrawArrays: ptr<u8> = glx_load("glDrawArrays\0" as ptr<u8>);
    if (pUseProgram == null || pGenVertexArrays == null || pBindVertexArray == null ||
        pGenBuffers == null || pBindBuffer == null || pBufferData == null ||
        pVertexAttribPointer == null || pEnableVertexAttribArray == null || pDrawArrays == null) {
        printf("glx: draw entry points missing\n");
        return;
    }
    var verts: [f32; 18] = [0.0 - 0.7, 0.0 - 0.7, 0.0, 1.0, 0.0, 0.0,
                            0.7, 0.0 - 0.7, 0.0, 1.0, 0.0, 0.0,
                            0.0, 0.7, 0.0, 1.0, 0.0, 0.0];
    var useProgram: fn(u32) = pUseProgram as fn(u32);
    useProgram(g.prog);
    var genVertexArrays: fn(i32, ptr<u32>) = pGenVertexArrays as fn(i32, ptr<u32>);
    var bindVertexArray: fn(u32) = pBindVertexArray as fn(u32);
    var genBuffers: fn(i32, ptr<u32>) = pGenBuffers as fn(i32, ptr<u32>);
    var bindBuffer: fn(u32, u32) = pBindBuffer as fn(u32, u32);
    var bufferData: fn(u32, i64, ptr<u8>, u32) = pBufferData as fn(u32, i64, ptr<u8>, u32);
    var vertexAttribPointer: fn(u32, i32, u32, u32, i32, ptr<u8>) = pVertexAttribPointer as fn(u32, i32, u32, u32, i32, ptr<u8>);
    var enableAttrib: fn(u32) = pEnableVertexAttribArray as fn(u32);
    var drawArrays: fn(u32, i32, i32) = pDrawArrays as fn(u32, i32, i32);
    unsafe {
        genVertexArrays(1, (&mut g.vao) as ptr<u32>);
        bindVertexArray(g.vao);
        genBuffers(1, (&mut g.vbo) as ptr<u32>);
        bindBuffer(GL_ARRAY_BUFFER, g.vbo);
        bufferData(GL_ARRAY_BUFFER, 72, &verts[0] as ptr<u8>, GL_STATIC_DRAW);
        vertexAttribPointer(0, 3, GL_FLOAT, 0, 24, null);
        enableAttrib(0);
    }
    glClearColor(0.16, 0.16, 0.19, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    drawArrays(GL_TRIANGLES, 0, 3);
}

fn glx_sample() -> i32 {
    var fails: i64 = 0;
    var g: GLx = glx_create(256, 256);
    if (g.ctx == null) {
        printf("glx: context setup failed\n");
        glx_destroy(&mut g);
        return 1;
    }
    let vendor: ptr<u8> = glGetString(GL_VENDOR);
    let renderer: ptr<u8> = glGetString(GL_RENDERER);
    let version: ptr<u8> = glGetString(GL_VERSION);
    printf("gl: %s\n", vendor);
    printf("gl: %s\n", renderer);
    printf("gl: %s\n", version);
    let fbo_ok: i64 = glx_fbo_init(&mut g);
    if (fbo_ok != 1) {
        fails += 1;
    }
    let vshader: u32 = glx_shader("#version 330 core\nlayout(location = 0) in vec3 aPos;\nvoid main() { gl_Position = vec4(aPos, 1.0); }\0" as ptr<u8>, GL_VERTEX_SHADER);
    let fshader: u32 = glx_shader("#version 330 core\nout vec4 FragColor;\nvoid main() { FragColor = vec4(0.94, 0.13, 0.10, 1.0); }\0" as ptr<u8>, GL_FRAGMENT_SHADER);
    if (vshader == 0 || fshader == 0) {
        fails += 1;
    } else {
        g.prog = glx_program(vshader, fshader);
        if (g.prog == 0) {
            fails += 1;
        }
    }
    glViewport(0, 0, g.w, g.h);
    glx_draw_triangle(&mut g);
    var pixels: [u8; 4] = [0];
    unsafe {
        glReadPixels(g.w / 2, g.h / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixels[0] as ptr<u8>);
    }
    printf("gl: center pixel %u %u %u %u\n", pixels[0], pixels[1], pixels[2], pixels[3]);
    if (pixels[0] >= 200 && pixels[1] <= 80 && pixels[2] <= 80) {
        printf("gl: triangle center is red\n");
    } else {
        printf("gl: triangle center mismatch\n");
        fails += 1;
    }
    glx_destroy(&mut g);
    return fails as i32;
}
