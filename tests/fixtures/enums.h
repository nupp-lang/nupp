/* Test fixture for nupp import-c: enum members as named constants. */

enum miniStatus {
    MINI_OK = 0,
    MINI_BUSY = 1,
    MINI_GONE = 7
};

/* An anonymous enum names its type and nothing else; the members are the
   reason the header declared it at all. */
typedef enum {
    MINI_READ = 1,
    MINI_WRITE = 2
} miniMode;

/* -1 is the value LuaJIT cannot report through the slot it keeps the others
   in, because there it means "no size". */
enum miniSigned {
    MINI_ERROR = -1,
    MINI_NONE = 0
};

/* A macro may reuse a name an enum already took. It has to come after the
   enum: before it, cpp would rewrite the member and the enum would not
   compile. The first meaning is the one that survives. */
#define MINI_OK 999

int mini_status(enum miniStatus s);
