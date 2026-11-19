extern "cpp_shim.dll" {
    fn cpp_median(xs: ptr<i64>, n: i64) -> i64;
    fn cpp_var(xs: ptr<f64>, n: i64) -> f64;
    fn cpp_count_words(s: ptr<u8>) -> i64;
    fn cpp_kind() -> ptr<u8>;
}

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn main() -> i32 {
    var xs: [i64; 5] = [7, 1, 9, 3, 5];
    var fs: [f64; 4] = [2.0, 4.0, 4.0, 6.0];

    unsafe {
        printf("cpp_median(xs, 5) = %lld\n", cpp_median(&xs as ptr<i64>, 5));
        printf("cpp_var(fs, 4) = %f\n", cpp_var(&fs as ptr<f64>, 4));
    }
    printf("cpp_count_words = %lld\n", cpp_count_words("one two  three four"));
    printf("cpp_kind = %s\n", cpp_kind());
    return 0;
}
