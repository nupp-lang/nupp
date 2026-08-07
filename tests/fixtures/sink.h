/* Fixture mirroring a project's own C header: self-contained, no
 * preprocessor needed. */
#ifndef NUPP_SINK_H
#define NUPP_SINK_H

#include <stdbool.h>

struct SinkPoint { double x; double y; };

bool nuppSinkOpen(const char *path);
void nuppSinkCategory(int base, int category, const char *name);
void nuppSinkClose(void);
unsigned long nuppSinkCount(void);
double nuppSinkScale(float factor, struct SinkPoint *p);

#endif
