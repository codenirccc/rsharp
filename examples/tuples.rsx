fn swap(p: (i64, i64)) -> (i64, i64) {
  return (p.1, p.0);
}

fn sum3(t: (i64, i32, i64)) -> i64 {
  return t.0 + (t.1 as i64) + t.2;
}

fn main() -> i32 {
  let a: (i64, i64) = (300, 4);
  let b = swap(a);
  let n = b.0;
  let n = n * 10;
  let c: (i64, i32, i64) = (10, 20, 30);
  let total = sum3(c);
  return (n + b.1 + total) as i32;
}
