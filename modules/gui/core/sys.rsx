extern fn malloc(n: u64) -> ptr<u8>;

extern fn free(p: ptr<u8>) -> void;

extern fn memset(d: ptr<u8>, v: i32, n: u64) -> ptr<u8>;

extern fn strlen(s: ptr<u8>) -> u64;
