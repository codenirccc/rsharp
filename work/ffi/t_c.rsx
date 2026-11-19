extern "c_add.dll" {
    fn c_add(a: i64, b: i64) -> i64;
    fn c_sum(xs: ptr<i64>, n: i64) -> i64;
    fn c_mean(xs: ptr<f64>, n: i64) -> f64;
    fn c_greet() -> ptr<u8>;
}

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn main() -> i32 {
    var xs: [i64; 4] = [10, 20, 30, 40];
    var fs: [f64; 4] = [1.5, 2.5, 3.5, 4.5];

    printf("c_add(2, 3) = %lld\n", c_add(2, 3));
    unsafe {
        printf("c_sum(xs, 4) = %lld\n", c_sum(&xs as ptr<i64>, 4));
        printf("c_mean(fs, 4) = %f\n", c_mean(&fs as ptr<f64>, 4));
    }
    printf("c_greet() = %s\n", c_greet());
    return 0;
}
