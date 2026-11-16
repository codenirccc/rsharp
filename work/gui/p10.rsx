extern fn strlen(s: ptr<u8>) -> u64;
extern fn strlen(s: ptr<u8>) -> u64;

extern fn printf(fmt: ptr<u8>, ...) -> i32;

include "dup_inc.rsx";

fn main() -> i32 {
    printf("len=%lld\n", strlen("abcd") as i64);
    return 0;
}
