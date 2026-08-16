/* Does the lane-parallel body answer what the scalar one does, on this target?
 *
 * The Lua differentials prove the generated C against ordinary Nupp, which is
 * the semantic question. This is the architectural one, and it is separate: the
 * lane body is written in compiler vector extensions, and what those lower to is
 * completely different on NEON, SSE2 and AVX2 -- a select is a blend, a mask
 * lane is a different width, and a horizontal test is a different instruction.
 * Everything measured to date ran on one architecture.
 *
 * So this compares the two generated bodies and nothing else. It needs no
 * LuaJIT and no host Nupp, which is what lets it run wherever the C compiles --
 * on a second architecture, cross-compiled and emulated, or on a platform the
 * shell harnesses do not cover.
 */
#include <stdio.h>
#include <string.h>

#include KERNEL_C

/* Deliberately not a multiple of either gang width, so the scalar tail runs. */
#define COUNT 4093
#define LIMIT 256

int main(void) {
    static KsPoint points[COUNT];
    static KsEscape lanes[COUNT];
    static KsEscape scalar[COUNT];

    /* Across the escape boundary and through the interior, so lanes in one gang
     * retire on different iterations and the divergent path is what is
     * compared rather than a loop every lane runs to the end. */
    for (int index = 0; index < COUNT; index += 1) {
        points[index].re = -2.2f + 3.1f * (float)(index % 97) / 96.0f;
        points[index].im = -1.2f + 2.4f * (float)(index % 89) / 88.0f;
    }

    ks_mandelbrot(lanes, points, 1, COUNT, LIMIT, COUNT);
    ks_mandelbrot_forced_scalar(scalar, points, 1, COUNT, LIMIT, COUNT);

    for (int index = 0; index < COUNT; index += 1) {
        if (lanes[index].iterations != scalar[index].iterations
            || lanes[index].escaped != scalar[index].escaped) {
            printf("mandelbrot: element %d differs: lanes %d/%u, scalar %d/%u\n",
                index, lanes[index].iterations, lanes[index].escaped,
                scalar[index].iterations, scalar[index].escaped);
            return 1;
        }
    }

    printf("mandelbrot: %d elements agree between lane-parallel and scalar C\n", COUNT);
    return 0;
}
