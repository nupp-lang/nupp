/* How long one mixed-width body takes, against its own scalar oracle.
 *
 * The question this exists to answer is what the all-or-nothing gang-width rule
 * costs. `mixedwidth.nupp` carries one binary64 running total and one binary64
 * step counter, so the whole loop takes the binary64 gang; `mixedwidth_f32.nupp`
 * is the same arithmetic with both narrowed, so it takes the 32-bit gang and
 * twice the lanes. Building this driver against each in turn gives the ratio,
 * and that ratio is the ceiling on what mixed-width gang sizing could recover.
 *
 * It reports against the forced-scalar body from the same source rather than in
 * absolute time, because the two kernels do not do the same arithmetic -- one
 * accumulates wide and one narrow -- so their absolute times are not comparable
 * and their speedups over their own scalar bodies are.
 *
 * Timed in C, with no LuaJIT in the process, for the same reason the
 * differentials are: what is being measured is the generated code.
 */
#include <stdio.h>
#include <string.h>
#include <time.h>

#include KERNEL_C

#define COUNT 4093
#define STEPS 64
#define REPEATS 200

static void fill(KsBody *bodies) {
    for (int index = 0; index < COUNT; index += 1) {
        float radius = 0.05f + (float)(index % 97) * 0.031f;
        bodies[index].x = radius * (1.0f - 2.0f * (float)(index % 3) / 2.0f);
        bodies[index].y = radius * (1.0f - 2.0f * (float)(index % 5) / 4.0f);
        bodies[index].vx = 0.01f * (float)(index % 7) - 0.03f;
        bodies[index].vy = 0.01f * (float)(index % 11) - 0.05f;
    }
}

static double seconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);

    return (double)now.tv_sec + (double)now.tv_nsec * 1e-9;
}

int main(void) {
    static KsBody bodies[COUNT];
    static KsTrack out[COUNT];
    fill(bodies);

    /* Interleaved rather than one batch each, so a machine that changes speed
     * partway through slows both bodies rather than whichever went second. The
     * minimum is reported because the fastest run is the one least interrupted;
     * a mean would be measuring the rest of the machine. */
    double lanes = 1e9;
    double scalar = 1e9;
    for (int repeat = 0; repeat < REPEATS; repeat += 1) {
        double at = seconds();
        ks_integrate(out, bodies, 1, COUNT, STEPS, 0.5f, 0.25f, 0.125f, COUNT);
        double took = seconds() - at;
        if (took < lanes) { lanes = took; }

        at = seconds();
        ks_integrate_forced_scalar(out, bodies, 1, COUNT, STEPS, 0.5f, 0.25f, 0.125f, COUNT);
        took = seconds() - at;
        if (took < scalar) { scalar = took; }
    }

    printf("%s: scalar %.3f ms, lanes %.3f ms, %.2fx\n", KERNEL_NAME,
           scalar * 1e3, lanes * 1e3, scalar / lanes);

    return 0;
}
