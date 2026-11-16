extern fn strlen(s: ptr<u8>) -> u64;

fn dup_len(s: ptr<u8>) -> i64 {
    return strlen(s) as i64;
}
