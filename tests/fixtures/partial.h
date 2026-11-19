/**
 * @file
 * @brief Exercises partial imports when the layout of a field is unavailable.
 *
 * One record needs the layout of an incomplete type. The other declarations
 * can still be imported when that record is skipped.
 */

struct partialOpaque;

struct partialHolder {
    struct partialOpaque inner;
};

int partial_add(int a, int b);
double partial_scale(double v);
