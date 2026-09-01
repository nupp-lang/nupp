#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <process.h>
#else
#include <unistd.h>
#endif

#ifndef NUPP_PACK_CC_RELATIVE
#error "NUPP_PACK_CC_RELATIVE must name the pack compiler"
#endif

static void fail(const char *message) {
    fprintf(stderr, "nupp compiler pack: %s\n", message);
    exit(1);
}

static char *path_join(const char *root, const char *relative) {
    size_t root_length = strlen(root);
    size_t relative_length = strlen(relative);
    char *path = malloc(root_length + relative_length + 2);
    if (path == NULL) fail("out of memory");
    memcpy(path, root, root_length);
    path[root_length] = '/';
    memcpy(path + root_length + 1, relative, relative_length + 1);
    return path;
}

static char *pack_root(const char *program) {
    char *root = malloc(strlen(program) + 1);
    char *slash;
    if (root == NULL) fail("out of memory");
    strcpy(root, program);
    slash = strrchr(root, '/');
#ifdef _WIN32
    {
        char *backslash = strrchr(root, '\\');
        if (backslash != NULL && (slash == NULL || backslash > slash)) slash = backslash;
    }
#endif
    if (slash == NULL) fail("linkHost must be invoked by path");
    *slash = '\0';
    slash = strrchr(root, '/');
#ifdef _WIN32
    {
        char *backslash = strrchr(root, '\\');
        if (backslash != NULL && (slash == NULL || backslash > slash)) slash = backslash;
    }
#endif
    if (slash == NULL) fail("linkHost is not inside the compiler pack");
    *slash = '\0';
    return root;
}

static void append(const char ***cursor, const char *value) {
    **cursor = value;
    *cursor += 1;
}

int main(int argc, char **argv) {
    static const char *libraries[] = {
        "host/lib/liblpeg.a",
        "host/lib/liblua-utf8.a",
        "host/lib/libluajit.a",
    };
    const char **command;
    const char **cursor;
    char *root;
    char *compiler;
    char *host;
    char *resolved_libraries[sizeof(libraries) / sizeof(libraries[0])];
    int separator = 3;
    int index;

    if (argc < 4) fail("usage: linkHost FEATURES OUTPUT ARCHIVE... -- LINK_FLAG...");
    while (separator < argc && strcmp(argv[separator], "--") != 0) separator += 1;
    if (separator == argc) fail("linkHost arguments have no -- separator");

    root = pack_root(argv[0]);
    compiler = path_join(root, NUPP_PACK_CC_RELATIVE);
    host = path_join(root, "host/lib/libnupp-host.a");
    for (index = 0; index < (int)(sizeof(libraries) / sizeof(libraries[0])); index += 1) {
        resolved_libraries[index] = path_join(root, libraries[index]);
    }

    command = calloc((size_t)argc + 40, sizeof(*command));
    if (command == NULL) fail("out of memory");
    cursor = command;
    append(&cursor, compiler);
    append(&cursor, "-o");
    append(&cursor, argv[2]);
    append(&cursor, "-Wl,--whole-archive");
    append(&cursor, host);
    append(&cursor, "-Wl,--no-whole-archive");
    for (index = 0; index < (int)(sizeof(libraries) / sizeof(libraries[0])); index += 1) {
        append(&cursor, resolved_libraries[index]);
    }
#ifdef __APPLE__
    append(&cursor, "-Wl,-force_load");
    append(&cursor, path_join(root, "host/lib/libnupp_native_v2.a"));
#else
    append(&cursor, "-Wl,--whole-archive");
    append(&cursor, path_join(root, "host/lib/libnupp_native_v2.a"));
    append(&cursor, "-Wl,--no-whole-archive");
#endif
    if (separator > 3) {
        append(&cursor, "-Wl,--whole-archive");
        for (index = 3; index < separator; index += 1) append(&cursor, argv[index]);
        append(&cursor, "-Wl,--no-whole-archive");
    }
    for (index = separator + 1; index < argc; index += 1) append(&cursor, argv[index]);
#ifdef _WIN32
    append(&cursor, "-lpthread");
    append(&cursor, "-lpsapi");
    append(&cursor, "-luser32");
    append(&cursor, "-ladvapi32");
    append(&cursor, "-liphlpapi");
    append(&cursor, "-luserenv");
    append(&cursor, "-lws2_32");
    append(&cursor, "-ldbghelp");
    append(&cursor, "-lole32");
    append(&cursor, "-lshell32");
    append(&cursor, "-lbcrypt");
    append(&cursor, "-lcrypt32");
    append(&cursor, "-Wl,--export-all-symbols");
#elif defined(__APPLE__)
    append(&cursor, "-lm");
    append(&cursor, "-lpthread");
    append(&cursor, "-framework");
    append(&cursor, "CoreFoundation");
    append(&cursor, "-framework");
    append(&cursor, "Security");
    append(&cursor, "-Wl,-export_dynamic");
#else
    append(&cursor, "-lm");
    append(&cursor, "-lpthread");
    append(&cursor, "-ldl");
    append(&cursor, "-Wl,-E");
#endif
    *cursor = NULL;

#ifdef _WIN32
    int status = (int)_spawnv(_P_WAIT, compiler, command);
    if (status == -1) {
        fprintf(stderr, "nupp compiler pack: cannot run %s: %s\n", compiler, strerror(errno));
        return 1;
    }
    return status;
#else
    execv(compiler, (char *const *)command);
    fprintf(stderr, "nupp compiler pack: cannot run %s: %s\n", compiler, strerror(errno));
    return 1;
#endif
}
