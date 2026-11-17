extern "msvcrt" fn malloc(n: u64) -> ptr<u8>;
extern "msvcrt" fn free(p: ptr<u8>);
extern "msvcrt" fn memset(p: ptr<u8>, v: i32, n: u64) -> ptr<u8>;
extern fn printf(fmt: ptr<u8>, ...) -> i32;
