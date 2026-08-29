#include "control.h"

void tbMandelbrot(TbEscape *restrict escapes, const TbPoint *points,
                  int32_t maxIterations, size_t count)
{
    for (size_t i = 0; i < count; i++) {
        double cx = (double)points[i].re;
        double cy = (double)points[i].im;
        double zx = 0.0;
        double zy = 0.0;
        double zxSquared = 0.0;
        double zySquared = 0.0;
        int32_t iteration = 0;
        uint32_t escaped = 0;

        while (iteration < maxIterations) {
            if (zxSquared + zySquared > 4.0) {
                escaped = 1;
                break;
            }
            zy = 2.0 * zx * zy + cy;
            zx = zxSquared - zySquared + cx;
            zxSquared = zx * zx;
            zySquared = zy * zy;
            iteration += 1;
        }

        escapes[i].iterations = iteration;
        escapes[i].escaped = escaped;
    }
}

void tbAdvance(TbBody *restrict output, const TbBody *input,
               double dt, double drag, size_t count)
{
    for (size_t i = 0; i < count; i++) {
        double vx = (double)input[i].vx * drag;
        double vy = (double)input[i].vy * drag;
        output[i].x = (float)((double)input[i].x + vx * dt);
        output[i].y = (float)((double)input[i].y + vy * dt);
        output[i].vx = (float)vx;
        output[i].vy = (float)vy;
    }
}

double tbSumSquares(const double *values, size_t count)
{
    double total = 0.0;
    for (size_t i = 0; i < count; i++) {
        total = total + values[i] * values[i];
    }
    return total;
}

void tbMix(uint32_t *restrict output, const uint32_t *input, size_t count)
{
    for (size_t i = 0; i < count; i++) {
        uint32_t state = input[i];
        for (int round = 0; round < 4; round++) {
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
        }
        output[i] = state;
    }
}
