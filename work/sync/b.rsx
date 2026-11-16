static COUNTER: i32 = 7;
static mut HITS: i32 = 0;

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn main() -> i32 {
    printf("static %d\n", COUNTER);
    HITS = HITS + 1;
    printf("hits %d\n", HITS);
    return 0;
}
