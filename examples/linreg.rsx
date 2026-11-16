extern fn printf(fmt: ptr<u8>, ...) -> i32;

struct Fit {
    slope: f64,
    intercept: f64,
    r2: f64
}

fn fabsf(d: f64) -> f64 {
    if (d < 0.0) {
        return 0.0 - d;
    }
    return d;
}

fn mean(xs: ptr<f64>, n: i64) -> f64 {
    var total: f64 = 0.0;
    var i: i64 = 0;
    unsafe {
        while (i < n) {
            total += xs[i];
            i += 1;
        }
    }
    return total / (n as f64);
}

fn linreg_fit(xs: ptr<f64>, ys: ptr<f64>, n: i64) -> Fit {
    let mx: f64 = mean(xs, n);
    let my: f64 = mean(ys, n);
    var sxy: f64 = 0.0;
    var sxx: f64 = 0.0;
    var i: i64 = 0;
    unsafe {
        while (i < n) {
            let dx: f64 = xs[i] - mx;
            let dy: f64 = ys[i] - my;
            sxy += dx * dy;
            sxx += dx * dx;
            i += 1;
        }
    }
    let slope: f64 = sxy / sxx;
    let intercept: f64 = my - slope * mx;
    var ss_res: f64 = 0.0;
    var ss_tot: f64 = 0.0;
    i = 0;
    unsafe {
        while (i < n) {
            let r: f64 = ys[i] - (slope * xs[i] + intercept);
            let d: f64 = ys[i] - my;
            ss_res += r * r;
            ss_tot += d * d;
            i += 1;
        }
    }
    return Fit { slope: slope, intercept: intercept, r2: 1.0 - ss_res / ss_tot };
}

fn predict(f: Fit, x: f64) -> f64 {
    return f.slope * x + f.intercept;
}

fn check(got: f64, want: f64) -> i64 {
    if (fabsf(got - want) > 0.0001) {
        return 1;
    }
    return 0;
}

fn run(name: ptr<u8>, xs: ptr<f64>, ys: ptr<f64>, n: i64,
       want_slope: f64, want_intercept: f64, want_r2: f64, want_p11: f64) -> i64 {
    let f: Fit = linreg_fit(xs, ys, n);
    let p11: f64 = predict(f, 11.0);
    printf("%s slope=%.6f intercept=%.6f r2=%.6f predict(11)=%.6f\n", name, f.slope, f.intercept, f.r2, p11);
    var bad: i64 = 0;
    bad += check(f.slope, want_slope);
    bad += check(f.intercept, want_intercept);
    bad += check(f.r2, want_r2);
    bad += check(p11, want_p11);
    return bad;
}

fn main() -> i32 {
    var xs: [f64; 10] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0];
    var ya: [f64; 10] = [3.75, 5.5, 7.25, 9.0, 10.75, 12.5, 14.25, 16.0, 17.75, 19.5];
    var yb: [f64; 10] = [3.1, 5.8, 7.2, 10.9, 12.6, 15.3, 17.0, 19.4, 21.1, 23.9];

    var bad: i64 = 0;
    unsafe {
        let xp: ptr<f64> = &xs[0] as ptr<f64>;
        let yap: ptr<f64> = &ya[0] as ptr<f64>;
        let ybp: ptr<f64> = &yb[0] as ptr<f64>;
        bad += run("A" as ptr<u8>, xp, yap, 10, 1.75, 2.0, 1.0, 21.25);
        bad += run("B" as ptr<u8>, xp, ybp, 10, 2.280606, 1.086667, 0.996135, 26.173333);
    }

    if (bad == 0) {
        printf("linreg: ok\n");
        return 0;
    }
    printf("linreg: %lld check(s) off\n", bad);
    return 1;
}
