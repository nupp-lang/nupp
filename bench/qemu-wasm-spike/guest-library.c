#include <stddef.h>

double spike_sum(const double *values, size_t count) {
    double total = 0;
    for (size_t i = 0; i < count; ++i) total += values[i];
    return total;
}

int spike_callback(int (*callback)(int), int value) {
    return callback(value) + 1;
}
