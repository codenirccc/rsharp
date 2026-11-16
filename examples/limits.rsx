// limits.rsx - an integer literal is checked against the type it lands in, so a
// u16 is held to 65535 instead of being truncated to 4464 without a word.

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn main() -> i32 {
    var top: u16 = 65535;
    printf("u16 max       %u\n", top);

    var wrapped: u16 = top + 1;
    printf("u16 wrap      %u\n", wrapped);

    var mask: u32 = -1 as u32;
    printf("u32 mask      %u\n", mask);

    var big: u32 = 4294967295 as u32;
    printf("u32 max       %u\n", big);

    var wide: i64 = 17947401034630457;
    printf("i64 wide      %lld\n", wide);

    var neg: i8 = -128;
    printf("i8 min        %d\n", neg as i32);

    var byte: u8 = 255;
    printf("u8 max        %d\n", byte as i32);

    return 0;
}
