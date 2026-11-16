// literals.rsx - a bare integer literal takes the type of the other operand.
// `n` is i64, so `48 + n` is an i64 sum; it used to default the 48 to i32 and
// report a mismatch the writer never asked for.

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn digit(n: i64) -> u8
    // the shape that used to need a temporary: literal first, typed value second
    let d = (48 + (n % 10)) as u8;
    return d;
end;

fn main() -> i32
    let n: i64 = 27;

    printf("digit      %c\n", digit(n));
    printf("literal+   %lld\n", 1000 + n);
    printf("literal-   %lld\n", 1000 - n);
    printf("literal*   %lld\n", 3 * n);
    printf("literal/   %lld\n", 1000 / n);
    printf("literal%%   %lld\n", 1000 % n);
    printf("compare    %d\n", 48 == n);
    printf("less       %d\n", 0 < n);
    printf("bitor      %lld\n", 1 | n);
    printf("shift      %lld\n", n << 1);
    printf("expect     %lld\n", 48 + n);

    let small: u8 = 5 + 3;
    printf("u8 sum     %d\n", small as i32);

    return 0;
end;
