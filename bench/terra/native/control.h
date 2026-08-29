/* The C the other three implementations are read against.
 *
 * Idiomatic C rather than a transcription of Nupp's generated C: its job is to
 * be the number a reader already has an intuition for. The arithmetic is
 * nonetheless exactly the arithmetic the Nupp kernels specify, including where
 * a float is widened to double and narrowed back, so all four implementations
 * agree bit for bit and the differential test can demand that rather than a
 * tolerance.
 *
 * The output pointers are `restrict` because Nupp's ownership rules prove the
 * same thing about an `exclusive` span and its generated C says so. Terra has
 * no way to spell it; that difference is the benchmark's, not a mistake.
 */
#ifndef NUPP_TERRA_BENCH_CONTROL_H
#define NUPP_TERRA_BENCH_CONTROL_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    int32_t iterations;
    uint32_t escaped;
} TbEscape;

typedef struct {
    float re;
    float im;
} TbPoint;

typedef struct {
    float x;
    float y;
    float vx;
    float vy;
} TbBody;

void tbMandelbrot(TbEscape *restrict escapes, const TbPoint *points,
                  int32_t maxIterations, size_t count);
void tbAdvance(TbBody *restrict output, const TbBody *input,
               double dt, double drag, size_t count);
double tbSumSquares(const double *values, size_t count);
void tbMix(uint32_t *restrict output, const uint32_t *input, size_t count);

#endif
