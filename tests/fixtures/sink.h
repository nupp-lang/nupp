/**
 * @file
 * @brief Exercises reading a self-contained header through checked C interop.
 *
 * The fixture can be read without a system C preprocessor.
 */

#ifndef NUPP_SINK_H
#define NUPP_SINK_H

#include <stdbool.h>

struct SinkPoint { double x; double y; };

bool nuppSinkOpen(const char *path);
void nuppSinkCategory(int base, int category, const char *name);
void nuppSinkClose(void);
unsigned long nuppSinkCount(void);
double nuppSinkScale(float factor, struct SinkPoint *p);
unsigned char *nuppSinkBytes(unsigned char *data, const unsigned char *source);

#endif
