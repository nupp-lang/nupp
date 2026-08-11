/* Test fixture for nupp import-c: a small self-contained C header. */

#define MINI_MAX 64
#define MINI_FLAG (1 << 3)
#define MINI_NAME "mini"
#define MINI_SKIP do_not_import(this)

struct miniPoint {
    double x;
    double y;
};

struct miniBox {
    struct miniPoint min;
    struct miniPoint max;
    unsigned int flags;
};

int mini_add(int a, int b);
double mini_scale(double v, float factor);
const char *mini_name(void);
void mini_fill(struct miniPoint *p, unsigned int n);
size_t mini_len(const char *s);
int mini_printf(const char *fmt, ...);
struct miniPoint mini_translate(struct miniPoint p, double dx, double dy);

/* function pointer parameter */
void mini_each(void (*fn)(int), int n);
