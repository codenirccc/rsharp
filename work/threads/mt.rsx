extern "kernel32" fn CreateThread(attr: ptr<u8>, stack: u64,
                                  start: fn(ptr<u8>) -> u32, param: ptr<u8>,
                                  flags: u32, tid: ptr<u32>) -> i64;
extern "kernel32" fn WaitForSingleObject(h: i64, ms: u32) -> u32;
extern "kernel32" fn CloseHandle(h: i64) -> i32;
extern fn printf(fmt: ptr<u8>, ...) -> i32;

struct MtParam {
    lo: i64,
    hi: i64,
    out: ptr<i64>
}

fn square_sum(lo: i64, hi: i64) -> i64 {
    var sum: i64 = 0;
    var i: i64 = lo;
    while (i < hi) {
        sum += i * i;
        i += 1;
    }
    return sum;
}

fn mt_worker(p: ptr<u8>) -> u32 {
    unsafe {
        let q: ptr<MtParam> = p as ptr<MtParam>;
        let lo: i64 = q.lo;
        let hi: i64 = q.hi;
        let out: ptr<i64> = q.out;
        out[0] = square_sum(lo, hi);
    }
    return 0;
}

fn main() -> i32 {
    let n: i64 = 1000000;
    var partials: [i64; 4] = [0, 0, 0, 0];
    var params: [MtParam; 4] = [
        MtParam { lo: 0, hi: 250000, out: null },
        MtParam { lo: 250000, hi: 500000, out: null },
        MtParam { lo: 500000, hi: 750000, out: null },
        MtParam { lo: 750000, hi: 1000000, out: null }
    ];
    var i: i64 = 0;
    unsafe {
        let bq: ptr<MtParam> = &params[0] as ptr<MtParam>;
        let bp: ptr<i64> = &partials[0] as ptr<i64>;
        while (i < 4) {
            bq[i].out = bp + i;
            i += 1;
        }
    }

    var handles: [i64; 4] = [0, 0, 0, 0];
    i = 0;
    unsafe {
        let bq: ptr<MtParam> = &params[0] as ptr<MtParam>;
        while (i < 4) {
            let h: i64 = CreateThread(null, 0, mt_worker, &bq[i] as ptr<u8>, 0, null);
            if (h == -1) {
                printf("mt: thread %lld failed\n", i);
                return 1;
            }
            handles[i] = h;
            i += 1;
        }
        i = 0;
        while (i < 4) {
            WaitForSingleObject(handles[i], 60000);
            CloseHandle(handles[i]);
            i += 1;
        }
    }

    var total: i64 = 0;
    i = 0;
    while (i < 4) {
        total += partials[i];
        i += 1;
    }

    var want: i64 = square_sum(0, n);
    if (total != want) {
        printf("mt: total %lld != %lld\n", total, want);
        return 1;
    }
    printf("sum = %lld (4 threads + serial agree)\n", total);
    printf("mt: ok\n");
    return 0;
}
