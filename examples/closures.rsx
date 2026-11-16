fn triple(x: i64) -> i64 {
  return x * 3;
}

fn apply(f: fn(i64) -> i64, x: i64) -> i64 {
  return f(x);
}

fn twice(f: fn(i64) -> i64, x: i64) -> i64 {
  return f(f(x));
}

fn main() -> i32 {
  let double = |x: i64| -> i64 { return x * 2; };
  let inc: fn(i64) -> i64 = |x: i64| -> i64 { return x + 1; };
  let named: fn(i64) -> i64 = triple;
  let pair: (fn(i64) -> i64, fn(i64) -> i64) = (double, inc);
  var acc: i64 = apply(pair.0, 10);
  acc += apply(pair.1, 10);
  acc += apply(named, 10);
  acc += twice(|x: i64| -> i64 { return x * x; }, 3);
  return acc as i32;
}
