extern "objc" fn objc_getClass(n: ptr<u8>) -> ptr<u8>;
extern "objc" fn sel_registerName(n: ptr<u8>) -> ptr<u8>;
extern "objc" fn objc_msgSend(a: ptr<u8>, b: ptr<u8>, ...) -> ptr<u8>;
extern "coregraphics" fn CGColorSpaceCreateDeviceRGB() -> ptr<u8>;
extern "system" fn dlopen(p: ptr<u8>, m: i32) -> ptr<u8>;
extern fn printf(fmt: ptr<u8>, ...) -> i32;

struct PRect {
    x: f64,
    y: f64,
    w: f64,
    h: f64
}

fn probe_imp(self_: ptr<u8>, cmd: ptr<u8>, ev: ptr<u8>) {
}

fn main() -> i32 {
    var r: PRect = zero(PRect);
    r.x = 1.5;
    r.w = 320.0;
    let c: ptr<u8> = objc_getClass("NSView");
    let s: ptr<u8> = sel_registerName("tag");
    let v: ptr<u8> = objc_msgSend(c, s, 1 as i64, 2 as i64);
    var p: ptr<u8> = null;
    unsafe { p = &mut r as ptr<u8>; }
    let q: ptr<f64> = p as ptr<f64>;
    var n: i64 = 0;
    unsafe { n = q[0] as i64; }
    let cs: ptr<u8> = CGColorSpaceCreateDeviceRGB();
    let h: ptr<u8> = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", 2);
    let imp: ptr<u8> = probe_imp as ptr<u8>;
    printf("%lld %lld %lld %lld %lld\n", n, v as i64, imp as i64, s as i64, cs as i64);
    objc_msgSend(c, s, 2.5, 3.5);
    let x: f64 = 3.75;
    let y: i64 = x as i64;
    printf("%lld %lld\n", y, h as i64);
    return 0;
}
