extern fn puts(s: ptr<u8>) -> i32;
extern fn printf(fmt: ptr<u8>, ...) -> i32;

async fn slow_mul(x: i64, y: i64) -> i64 {
  puts("body: slow_mul ran");
  return x * y;
}

async fn relay(n: i64) -> i64 {
  let inner: Task<i64> = slow_mul(n, 3);
  let v: i64 = await inner;
  return v + 1;
}

async fn pair(a: i64) -> (i64, i64) {
  puts("body: pair ran");
  return (a, a * 2);
}

fn main() -> i32 {
  puts("main: before");
  let t: Task<i64> = slow_mul(6, 7);
  puts("main: after construct");
  let once: i64 = poll(t);
  printf("poll returned %lld\n", once);
  let v: i64 = await t;
  printf("value %lld\n", v);
  let r: i64 = await relay(10);
  printf("relay %lld\n", r);
  let p: (i64, i64) = await pair(5);
  printf("pair %lld %lld\n", p.0, p.1);
  return (v + r + p.0 + p.1) as i32;
}
