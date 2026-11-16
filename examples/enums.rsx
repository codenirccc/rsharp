enum Color {
  Red,
  Green,
  Blue,
}

enum Shape {
  Circle(i64),
  Rect(i64, i64),
  Nil,
}

struct Pair {
  a: i64,
  b: i64,
}

fn pick(c: Color) -> i64 {
  match c {
    Color::Red => {
      return 10;
    }
    Color::Green => {
      return 20;
    }
    _ => {
      return 30;
    }
  }
}

fn area(s: Shape) -> i64 {
  match s {
    Shape::Circle(r) => {
      return 3 * r * r;
    }
    Shape::Rect(w, h) => {
      return w * h;
    }
    Shape::Nil => {
      return 0;
    }
  }
}

fn sum(n: i64) -> i64 {
  var total: i64 = 0;
  for i in 0..n {
    if (i % 2 == 0) {
      continue;
    }
    total += i;
  }
  return total;
}

fn main() -> i32 {
  let c: Color = Color::Green;
  let s: Shape = Shape::Rect(6, 7);
  let t: Shape = Shape::Circle(4);
  var acc: i64 = pick(c) + area(s) + area(t);
  acc += sum(10);
  return acc as i32;
}
