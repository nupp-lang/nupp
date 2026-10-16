/*
 * `demo.counter` as a C extension, built independently of the VM with the
 * system compiler against nothing but `include/nupp_extension.h`. It leaves
 * marker files beside itself so a test can see what ran: `<library>.init`
 * when a VM initialized it, `<library>.shutdown` when one shut it down, and
 * `<library>.unloaded` when the platform unloaded it.
 *
 * Built with -DCOUNTER_NUMBERS, `add` registers function(number, number):
 * number, which no declaration of the module matches.
 */
#define _GNU_SOURCE
#include "nupp_extension.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static nupp_status add(const nupp_host *, nupp_call *, void *, void *, const nupp_slot *, size_t, nupp_slot *, size_t);

static void mark(const char *suffix) {
    Dl_info info;
    if (dladdr((void *)&add, &info) && info.dli_fname) {
        char path[4096];
        snprintf(path, sizeof path, "%s.%s", info.dli_fname, suffix);
        FILE *file = fopen(path, "a");
        if (file) {
            fputc('x', file);
            fclose(file);
        }
    }
}

__attribute__((destructor)) static void unloaded(void) { mark("unloaded"); }

typedef struct {
    nupp_handle kept;
} instance;

typedef struct {
    int64_t value;
} counter;

#define RAISE(text) return host->raise(call, (text), strlen(text))

static nupp_status init(const nupp_host *host, nupp_vm *vm, void **out) {
    (void)vm;
    if (host->abi_version != NUPP_EXTENSION_ABI_VERSION || host->size < sizeof(nupp_host)) return NUPP_ERROR;
    *out = calloc(1, sizeof(instance));
    mark("init");
    return *out ? NUPP_OK : NUPP_ERROR;
}

static void shutdown(const nupp_host *host, void *self) {
    (void)host;
    free(self);
    mark("shutdown");
}

static void integer(nupp_slot *slot, int64_t value) {
    slot->kind = NUPP_INTEGER;
    slot->as.integer = value;
}

static nupp_status add(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args, size_t nargs,
                       nupp_slot *results, size_t nresults) {
    (void)self, (void)data, (void)nargs, (void)nresults;
#ifdef COUNTER_NUMBERS
    results[0].kind = NUPP_NUMBER;
    results[0].as.number = args[0].as.number + args[1].as.number;
    (void)host, (void)call;
    return NUPP_OK;
#else
    int64_t sum;
    if (__builtin_add_overflow(args[0].as.integer, args[1].as.integer, &sum)) RAISE("the sum overflows");
    integer(&results[0], sum);
    return NUPP_OK;
#endif
}

static nupp_status new_counter(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args,
                               size_t nargs, nupp_slot *results, size_t nresults) {
    (void)self, (void)data, (void)nargs, (void)nresults;
    counter *c = malloc(sizeof *c);
    if (!c) RAISE("out of memory");
    c->value = args[0].as.integer;
    nupp_handle h = host->new_resource(call, 0, c);
    if (!h) {
        free(c);
        return NUPP_ERROR;
    }
    results[0].kind = NUPP_HANDLE;
    results[0].as.handle = h;
    return NUPP_OK;
}

static nupp_status bump(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args, size_t nargs,
                        nupp_slot *results, size_t nresults) {
    (void)self, (void)data, (void)nargs, (void)nresults;
    counter *c = args[0].kind == NUPP_HANDLE ? host->resource(call, args[0].as.handle, 0) : NULL;
    if (!c) RAISE("the value is not a live resource of this type");
    c->value += args[1].as.integer;
    integer(&results[0], c->value);
    return NUPP_OK;
}

static nupp_status close_counter(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args,
                                 size_t nargs, nupp_slot *results, size_t nresults) {
    (void)self, (void)data, (void)nargs, (void)results, (void)nresults;
    if (args[0].kind != NUPP_HANDLE) RAISE("the value is not a live resource of this type");
    return host->close_resource(call, args[0].as.handle, 0);
}

static nupp_status call_with(const nupp_host *host, nupp_call *call, nupp_handle f, int64_t x, int64_t *out) {
    nupp_slot arg, result;
    integer(&arg, x);
    if (host->invoke(call, f, &arg, 1, &result, 1) != NUPP_OK) return NUPP_ERROR;
    if (result.kind == NUPP_NUMBER) {
        *out = (int64_t)result.as.number;
    } else if (result.kind == NUPP_INTEGER) {
        *out = result.as.integer;
    } else {
        RAISE("the function did not answer an integer");
    }
    return NUPP_OK;
}

static nupp_status apply(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args, size_t nargs,
                         nupp_slot *results, size_t nresults) {
    (void)self, (void)data, (void)nargs, (void)nresults;
    int64_t y;
    if (call_with(host, call, args[0].as.handle, args[1].as.integer, &y) != NUPP_OK) return NUPP_ERROR;
    integer(&results[0], y + 1);
    return NUPP_OK;
}

static nupp_status keep(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args, size_t nargs,
                        nupp_slot *results, size_t nresults) {
    (void)data, (void)nargs, (void)results, (void)nresults;
    instance *i = self;
    nupp_handle kept = host->retain(call, args[0].as.handle);
    if (!kept) return NUPP_ERROR;
    if (i->kept) host->release(host->vm(call), i->kept);
    i->kept = kept;
    return NUPP_OK;
}

static nupp_status call_kept(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args,
                             size_t nargs, nupp_slot *results, size_t nresults) {
    (void)data, (void)nargs, (void)nresults;
    instance *i = self;
    if (!i->kept) RAISE("nothing is kept");
    int64_t y;
    if (call_with(host, call, i->kept, args[0].as.integer, &y) != NUPP_OK) return NUPP_ERROR;
    integer(&results[0], y);
    return NUPP_OK;
}

static nupp_status forget(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args, size_t nargs,
                          nupp_slot *results, size_t nresults) {
    (void)data, (void)args, (void)nargs, (void)results, (void)nresults;
    instance *i = self;
    if (i->kept) host->release(host->vm(call), i->kept);
    i->kept = 0;
    return NUPP_OK;
}

typedef struct {
    const nupp_host *host;
    nupp_request *request;
    char *text;
    size_t length;
    int64_t ms;
} later_job;

static void *later_thread(void *arg) {
    later_job *job = arg;
    usleep((useconds_t)(job->ms > 0 ? job->ms : 0) * 1000);
    if (job->ms < 0) {
        const char *message = "a negative delay";
        job->host->fail(job->request, message, strlen(message));
    } else {
        nupp_slot result;
        result.kind = NUPP_STRING;
        result.as.string.bytes = job->text;
        result.as.string.length = job->length;
        job->host->complete(job->request, &result, 1);
    }
    free(job->text);
    free(job);
    return NULL;
}

static nupp_status later(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args, size_t nargs,
                         nupp_slot *results, size_t nresults) {
    (void)self, (void)data, (void)nargs, (void)results, (void)nresults;
    later_job *job = calloc(1, sizeof *job);
    if (!job) RAISE("out of memory");
    job->length = args[0].as.string.length;
    job->text = malloc(job->length + 1);
    for (size_t k = 0; k < job->length; k++) job->text[k] = args[0].as.string.bytes[job->length - 1 - k];
    job->ms = args[1].as.integer;
    job->host = host;
    job->request = host->suspend(call);
    if (!job->request) {
        free(job->text);
        free(job);
        return NUPP_ERROR;
    }
    pthread_t thread;
    pthread_create(&thread, NULL, later_thread, job);
    pthread_detach(thread);
    return NUPP_SUSPENDED;
}

static nupp_status fail(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args, size_t nargs,
                        nupp_slot *results, size_t nresults) {
    (void)self, (void)data, (void)nargs, (void)results, (void)nresults;
    return host->raise(call, args[0].as.string.bytes, args[0].as.string.length);
}

static void drop_counter(void *self, void *type_data, void *data) {
    (void)self, (void)type_data;
    free(data);
}

static nupp_status save_counter(void *self, void *type_data, void *data, nupp_write write, void *sink) {
    (void)self, (void)type_data;
    write(sink, &((counter *)data)->value, sizeof(int64_t));
    return NUPP_OK;
}

static nupp_status restore_counter(void *self, void *type_data, const void *bytes, size_t length, void **data) {
    (void)self, (void)type_data;
    if (length != sizeof(int64_t)) return NUPP_ERROR;
    counter *c = malloc(sizeof *c);
    if (!c) return NUPP_ERROR;
    memcpy(&c->value, bytes, sizeof(int64_t));
    *data = c;
    return NUPP_OK;
}

static const nupp_function_entry functions[] = {
#ifdef COUNTER_NUMBERS
    {"add", "function(a: number, b: number): number", add, NULL, 0, 0},
#else
    {"add", "function(a: integer, b: integer): integer", add, NULL, 0, 0},
#endif
    {"new", "function(start: integer): any", new_counter, NULL, 0, 0},
    {"bump", "function(counter: any, n: integer): integer", bump, NULL, 0, 0},
    {"close", "function(counter: any)", close_counter, NULL, 0, 0},
    {"apply", "function(f: function(integer): integer, x: integer): integer", apply, NULL, 0, 0},
    {"keep", "function(f: function(integer): integer)", keep, NULL, 0, 0},
    {"callKept", "function(x: integer): integer", call_kept, NULL, 0, 0},
    {"forget", "function()", forget, NULL, 0, 0},
    {"later", "function(text: string, ms: integer): string", later, NULL, 0, 0},
    {"fail", "function(message: string)", fail, NULL, 0, 0},
};

static const nupp_resource_type types[] = {
    {"Counter", NULL, drop_counter, save_counter, restore_counter},
};

static const nupp_extension extension = {
    NUPP_EXTENSION_ABI_VERSION,
    sizeof(nupp_extension),
    "demo.counter",
    NUPP_EXTENSION_TARGET,
    functions,
    sizeof functions / sizeof functions[0],
    types,
    sizeof types / sizeof types[0],
    init,
    shutdown,
};

const nupp_extension *NUPP_EXTENSION_ENTRY(void) { return &extension; }
