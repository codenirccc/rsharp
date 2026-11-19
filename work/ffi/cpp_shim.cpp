#include <cstdint>
#include <algorithm>
#include <string>
#include <vector>

#if defined(_WIN32)
#define RSH_EXPORT extern "C" __declspec(dllexport)
#else
#define RSH_EXPORT extern "C" __attribute__((visibility("default")))
#endif

RSH_EXPORT int64_t cpp_median(const int64_t *xs, int64_t n) {
    if (n <= 0) return 0;
    std::vector<int64_t> v(xs, xs + n);
    std::sort(v.begin(), v.end());
    return v[static_cast<size_t>((n - 1) / 2)];
}

RSH_EXPORT double cpp_var(const double *xs, int64_t n) {
    if (n <= 1) return 0.0;
    double sum = 0.0;
    for (int64_t i = 0; i < n; i++) sum += xs[i];
    const double mean = sum / static_cast<double>(n);
    double acc = 0.0;
    for (int64_t i = 0; i < n; i++) {
        const double d = xs[i] - mean;
        acc += d * d;
    }
    return acc / static_cast<double>(n - 1);
}

RSH_EXPORT int64_t cpp_count_words(const char *s) {
    if (s == nullptr) return 0;
    std::string text(s);
    int64_t words = 0;
    bool in_word = false;
    for (char c : text) {
        const bool space = (c == ' ' || c == '\t' || c == '\n' || c == '\r');
        if (!space && !in_word) {
            words += 1;
            in_word = true;
        } else if (space) {
            in_word = false;
        }
    }
    return words;
}

RSH_EXPORT const char *cpp_kind(void) { return "std::vector<int64_t>"; }
