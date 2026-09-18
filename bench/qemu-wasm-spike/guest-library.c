#include <stddef.h>
#include <stdint.h>

double spike_sum(const double *values, size_t count) {
    double total = 0;
    for (size_t i = 0; i < count; ++i) total += values[i];
    return total;
}

int spike_callback(int (*callback)(int), int value) {
    return callback(value) + 1;
}
/* The host publishes its monotonic clock as atomic integer microseconds. Reading it must
 * not suspend: the task scheduler itself asks for it while deciding to park. */
double spike_clock(const void *mailbox) {
    return (double)__atomic_load_n((const uint64_t *)mailbox, __ATOMIC_RELAXED) / 1000.0;
}
