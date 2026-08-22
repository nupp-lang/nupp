/* The native provider's shared surface.
 *
 * Everything a facility exports is declared in the Lua binding that calls it,
 * not here: `src/nupp/io/files.nupp` and its siblings carry the `cdef` block
 * that is the ABI. What this header holds is what the implementation files
 * share -- the error slot every failure writes, the byte buffer every answer
 * comes back in, and the argument checking each entry point starts with.
 */

#ifndef NUPP_NATIVE_H
#define NUPP_NATIVE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#   define NUPP_EXPORT __declspec(dllexport)
#   define NUPP_THREAD_LOCAL __declspec(thread)
#   define NUPP_WINDOWS 1
#else
#   define NUPP_EXPORT __attribute__((visibility("default")))
#   define NUPP_THREAD_LOCAL __thread
#   define NUPP_WINDOWS 0
#endif

/* Every entry point here is spelled `nuppc...` where the ABI says `nupp...`.
 *
 * That is temporary and it is a linker's doing. While the provider is half C and
 * half Rust the library is Cargo's shared object, and Cargo builds one with an
 * export list naming the Rust crate's own symbols and nothing else -- a C symbol
 * linked into it is not on that list and is dropped. So the public name is a
 * Rust alias that forwards here, and this is the name it forwards to. When the
 * Rust half goes, the alias goes with it and these names lose the `c`.
 */

/* --- the error slot ----------------------------------------------------- */

/* One message per thread, replaced by each failure and read by the binding
 * immediately after one. A caller that asks for the error without having failed
 * gets whatever it last failed at, which is why every entry point that can fail
 * writes here before it answers.
 */
NUPP_EXPORT const char *nuppcNativeError(void);

/* Records a failure. `nupp_fail_format` takes a printf format; `nupp_fail_errno`
 * appends the platform's text for an error number, which is what a system call
 * has to say for itself.
 */
void nupp_fail(const char *message);
void nupp_fail_format(const char *format, ...);
void nupp_fail_errno(const char *what, int number);

/* The platform's text for an error number, into a caller-owned buffer. Windows
 * and POSIX disagree about the spelling of every one of these calls. */
void nupp_platform_error_text(int number, char *into, size_t capacity);

/* --- returned bytes ----------------------------------------------------- */

/* One answer's bytes, owned by the caller until it destroys them. The layout is
 * private: the binding reaches the contents through the three functions below,
 * which is what lets an answer be a string, a NUL-separated list, or a packed
 * record without the ABI changing shape.
 */
typedef struct NuppBytes NuppBytes;

NUPP_EXPORT const uint8_t *nuppcBytesData(const NuppBytes *bytes);
NUPP_EXPORT size_t nuppcBytesLength(const NuppBytes *bytes);
NUPP_EXPORT void nuppcBytesDestroy(NuppBytes *bytes);

/* Takes ownership of `data`, which must have come from malloc. Answers NULL and
 * records a failure when the allocation cannot be made, freeing `data` first, so
 * a caller never has to unwind an allocation it has already handed over. */
NuppBytes *nupp_bytes_adopt(uint8_t *data, size_t length);

/* Copies `length` bytes into a fresh answer. */
NuppBytes *nupp_bytes_copy(const uint8_t *data, size_t length);

/* --- growable byte buffer ----------------------------------------------- */

/* What an answer is assembled in before it becomes a `NuppBytes`. Growth
 * failures are recorded in the buffer rather than reported at each append, so a
 * caller appends in a loop and checks once.
 */
typedef struct {
    uint8_t *data;
    size_t length;
    size_t capacity;
    bool failed;
} NuppBuffer;

void nupp_buffer_init(NuppBuffer *buffer);
void nupp_buffer_free(NuppBuffer *buffer);
void nupp_buffer_append(NuppBuffer *buffer, const void *data, size_t length);
void nupp_buffer_push(NuppBuffer *buffer, uint8_t byte);

/* Hands the buffer's bytes to a `NuppBytes` and leaves the buffer empty. A
 * buffer that failed to grow answers NULL with the failure already recorded. */
NuppBytes *nupp_buffer_finish(NuppBuffer *buffer);

/* --- text from the binding ---------------------------------------------- */

/* A borrowed string argument, checked and NUL-terminated.
 *
 * Every path, pattern and name arriving from Lua is a pointer and a length. The
 * platform wants a NUL-terminated string, and the value has to be valid UTF-8
 * with no interior NUL before it can become one -- a path holding either is a
 * different path from the one the caller named. Short values are terminated in
 * the inline buffer; longer ones borrow the heap, which `nupp_text_free`
 * returns.
 */
#define NUPP_TEXT_INLINE 256

typedef struct {
    char *value;
    size_t length;
    char inlined[NUPP_TEXT_INLINE];
    bool heap;
} NuppText;

/* Answers false and records why when the value is absent, not UTF-8, or holds a
 * NUL byte. `what` names the argument in that message. */
bool nupp_text(NuppText *text, const uint8_t *data, size_t length, const char *what);
void nupp_text_free(NuppText *text);

/* Whether `length` bytes at `data` are valid UTF-8. */
bool nupp_is_utf8(const uint8_t *data, size_t length);

/* --- platform ----------------------------------------------------------- */

/* Path separators are `/` on the way out, whatever the platform writes them as,
 * because the binding's paths are one shape everywhere. Rewrites in place. */
void nupp_normalize_separators(char *path);

/* Milliseconds on a clock that only moves forwards. */
double nupp_monotonic_ms(void);

/* Milliseconds since the Unix epoch, on the clock that tracks the world and can
 * therefore step. What a timestamp is made of, as against a duration. */
uint64_t nupp_unix_ms(void);

#endif /* NUPP_NATIVE_H */
