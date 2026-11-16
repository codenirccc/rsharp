extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;





fn main() -> i32 {
    let s: ptr<u8> = "a/*not a comment*/b";
    printf("ok s=%s\n", s);
    fflush(null);
    return 0;
}
