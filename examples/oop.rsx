extern fn printf(fmt: ptr<u8>, ...) -> i32;

class Counter {
  hits: i64,
  step: i64
}

impl Counter {
  fn new(step: i64) -> Counter {
    return Counter { hits: 0, step: step };
  }

  fn bump(&mut self) -> i64 {
    self.hits += self.step;
    return self.hits;
  }

  fn peek(&self) -> i64 {
    return self.hits;
  }
}

trait Shape {
  fn area(&self) -> i64;
  fn name(&self) -> i64;
}

struct Sq {
  side: i64
}

struct Rect {
  w: i64,
  h: i64
}

impl Shape for Sq {
  fn area(&self) -> i64 {
    return self.side * self.side;
  }

  fn name(&self) -> i64 {
    return 1;
  }
}

impl Shape for Rect {
  fn area(&self) -> i64 {
    return self.w * self.h;
  }

  fn name(&self) -> i64 {
    return 2;
  }
}

fn total(a: dyn Shape, b: dyn Shape) -> i64 {
  return a.area() + b.area() + a.name() * 10 + b.name() * 10;
}

fn apply(f: Fn(i64) -> i64, x: i64) -> i64 {
  return f(x);
}

fn main() -> i32 {
  var c: Counter = Counter::new(7);
  printf("bump %lld\n", c.bump());
  printf("bump %lld\n", c.bump());
  printf("peek %lld\n", c.peek());

  let s: Sq = Sq { side: 6 };
  let r: Rect = Rect { w: 4, h: 9 };
  printf("total %lld\n", total(s, r));

  let base: i64 = 5;
  let addbase = |x: i64| -> i64 { return x + base; };
  let scale = |x: i64| -> i64 { return x * base; };
  printf("closure %lld\n", apply(addbase, 11));
  printf("closure %lld\n", apply(scale, 11));
  return 0;
}
