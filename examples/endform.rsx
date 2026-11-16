
extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn fib(n: i64) -> i64
    if (n < 2)
        return n;
    end;
    return fib(n - 1) + fib(n - 2);
end;

fn classify(total: i64) -> i64
    var grade: i64 = 0;
    if (total > 100)
        grade = 1;
    else if (total > 10)
        grade = 2;
    else
        grade = 3;
    end;
    return grade;
end;

fn main() -> i32
    var i: i64 = 0;
    while (i < 10)
        printf("%lld ", fib(i));
        i += 1;
    end;
    printf("\n");

    let xs: [i64; 5] = [3, 1, 4, 1, 5];
    var sum: i64 = 0;
    for j in 0..5
        sum += xs[j];
    end;
    printf("sum = %lld\n", sum);

    printf("grade = %lld\n", classify(sum));

    {
        let doubled: i64 = sum * 2;
        printf("doubled = %lld\n", doubled);
    }

    unsafe
        let p: ptr<i64> = &sum as ptr<i64>;
        printf("through a pointer = %lld\n", p[0]);
    end;

    return 0;
end;
