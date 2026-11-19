#include <stdint.h>

#if defined(_WIN32)
#define RSH_EXPORT __declspec(dllexport)
#else
#define RSH_EXPORT __attribute__((visibility("default")))
#endif

RSH_EXPORT int64_t c_add(int64_t a, int64_t b) { return a + b; }

RSH_EXPORT int64_t c_sum(const int64_t *xs, int64_t n) {
    int64_t s = 0;
    for (int64_t i = 0; i < n; i++) s += xs[i];
    return s;
}

RSH_EXPORT double c_mean(const double *xs, int64_t n) {
    if (n <= 0) return 0.0;
    double s = 0.0;
    for (int64_t i = 0; i < n; i++) s += xs[i];
    return s / (double)n;
}

RSH_EXPORT const char *c_greet(void) { return "hello from c"; }
