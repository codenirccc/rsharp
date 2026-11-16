extern fn puts(s: ptr<u8>) -> i32;

fn main() -> i32 {
    puts("hello from R#");
    return 0;
}
