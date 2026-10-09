/* An embedding application answering the host channel's contract scenarios.
 *
 * It loads a component exporting `contract.start`, `contract.poll` and
 * `contract.result`, registers a C handler per `test.*` kind, and runs one
 * scenario the way a game loop would: start it, then until it stops parking,
 * answer whatever has come due, poll the runtime, and poll the pump. Some kinds
 * answer inside the handler and some later from this loop, which is the case
 * the channel exists for.
 *
 * Usage: driver COMPONENT SCENARIOS NAME [direct]
 * `direct` runs the scenario as a plain call with no pump around it.
 * Prints the scenario's JSON result, then `cancels=N live=N`, then the result
 * of probing nupp_host_answer's refusals.
 */

#include "nupp.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_LATER 4096

typedef struct Later {
    uint64_t request;
    double due;
    int kind; /* 0 answers a number, 1 opens a resource */
    double number;
} Later;

static nupp_runtime *runtime;
static Later later[MAX_LATER];
static size_t later_count;
static int live;
static int next_resource = 1;
static int cancels;
static int seen_count;
static char notes[4096];
static char outbound[4096];
static uint64_t last_request;

static double now_ms(void) {
    struct timespec spec;
    clock_gettime(CLOCK_MONOTONIC, &spec);
    return (double)spec.tv_sec * 1000.0 + (double)spec.tv_nsec / 1e6;
}

static void sleep_ms(double ms) {
    struct timespec spec;
    spec.tv_sec = (time_t)(ms / 1000);
    spec.tv_nsec = (long)(fmod(ms, 1000.0) * 1e6);
    nanosleep(&spec, NULL);
}

static void check(nupp_status status, nupp_error *error, const char *what) {
    if (status != NUPP_STATUS_OK) {
        fprintf(stderr, "%s: %s\n", what, error ? nupp_error_message(error) : "(no detail)");
        exit(1);
    }
}

static nupp_value number(double value) {
    nupp_value result = {0};
    result.kind = NUPP_VALUE_NUMBER;
    result.number = value;
    return result;
}

static nupp_value bytes(unsigned char *data, size_t length) {
    nupp_value result = {0};
    result.kind = NUPP_VALUE_BYTES;
    result.data = data;
    result.length = length;
    return result;
}

static nupp_value text(const char *value) {
    nupp_value result = {0};
    result.kind = NUPP_VALUE_STRING;
    result.data = (unsigned char *)value;
    result.length = strlen(value);
    return result;
}

static unsigned char *pattern(size_t size, int seed) {
    unsigned char *data = (unsigned char *)malloc(size ? size : 1);
    for (size_t index = 0; index < size; index++) data[index] = (unsigned char)((index * 31 + (size_t)seed) % 251);
    return data;
}

static double sum(const unsigned char *data, size_t length) {
    double total = 0;
    for (size_t index = 0; index < length; index++) {
        total = fmod(total + (double)data[index] * (double)(index % 7 + 1), 2147483647.0);
    }
    return total;
}

static void answer(uint64_t request, const nupp_value *values, size_t count) {
    nupp_error *error = NULL;
    check(nupp_host_answer(runtime, request, values, count, &error), error, "nupp_host_answer");
}

static void defer(uint64_t request, double ms, int kind, double value) {
    if (later_count == MAX_LATER) {
        fprintf(stderr, "too many deferred answers\n");
        exit(1);
    }
    later[later_count].request = request;
    later[later_count].due = now_ms() + ms;
    later[later_count].kind = kind;
    later[later_count].number = value;
    later_count++;
}

static void handle(nupp_runtime *owner, uint64_t request, const char *kind,
    const nupp_value *args, size_t count, void *userdata) {
    (void)owner;
    (void)userdata;
    last_request = request;
    if (strcmp(kind, "test.echo") == 0) {
        answer(request, args, count);
    } else if (strcmp(kind, "test.results") == 0) {
        nupp_value values[3] = {{0}, number(2), {0}};
        answer(request, values, 3);
    } else if (strcmp(kind, "test.fail") == 0) {
        char message[256];
        nupp_error *error = NULL;
        snprintf(message, sizeof message, "failed because %.*s", (int)args[0].length, (const char *)args[0].data);
        check(nupp_host_fail(runtime, request, message, &error), error, "nupp_host_fail");
    } else if (strcmp(kind, "test.digest") == 0) {
        nupp_value values[3] = {number((double)args[0].length), number(sum(args[0].data, args[0].length)),
            bytes(args[0].data, args[0].length)};
        answer(request, values, 3);
    } else if (strcmp(kind, "test.count") == 0) {
        double total = 0;
        seen_count++;
        for (size_t index = 0; index < count; index++) total += (double)args[index].length;
        nupp_value value = number(total);
        answer(request, &value, 1);
    } else if (strcmp(kind, "test.make") == 0) {
        size_t size = (size_t)args[0].number;
        unsigned char *data = pattern(size, (int)args[1].number);
        nupp_value value = bytes(data, size);
        answer(request, &value, 1);
        free(data);
    } else if (strcmp(kind, "test.slow") == 0) {
        defer(request, args[1].number, 0, (double)args[0].length);
    } else if (strcmp(kind, "test.open") == 0) {
        defer(request, args[0].number, 1, 0);
    } else if (strcmp(kind, "test.close") == 0) {
        live--;
        answer(request, NULL, 0);
    } else if (strcmp(kind, "test.live") == 0) {
        nupp_value value = number(live);
        answer(request, &value, 1);
    } else if (strcmp(kind, "test.seen") == 0) {
        nupp_value value = number(seen_count);
        answer(request, &value, 1);
    } else if (strcmp(kind, "test.note") == 0) {
        char note[64];
        snprintf(note, sizeof note, "%s%.0f:%zu", notes[0] ? "," : "", args[0].number, args[1].length);
        strncat(notes, note, sizeof notes - strlen(notes) - 1);
        answer(request, NULL, 0);
    } else if (strcmp(kind, "test.notes") == 0) {
        nupp_value value = text(notes);
        answer(request, &value, 1);
    } else if (strcmp(kind, "test.pushInput") == 0) {
        nupp_error *error = NULL;
        for (int index = 1; index <= (int)args[0].number; index++) {
            nupp_value move[2] = {number(index), number(index * 10)};
            check(nupp_host_push(runtime, "test.move", move, 2, &error), error, "nupp_host_push");
        }
        nupp_value down[2] = {text("a"), {0}};
        down[1].kind = NUPP_VALUE_BOOLEAN;
        down[1].boolean = 1;
        check(nupp_host_push(runtime, "test.key", down, 2, &error), error, "nupp_host_push");
        nupp_value up[2] = {text("b"), {0}};
        up[1].kind = NUPP_VALUE_BOOLEAN;
        check(nupp_host_push(runtime, "test.key", up, 2, &error), error, "nupp_host_push");
        answer(request, NULL, 0);
    } else if (strcmp(kind, "test.packet") == 0 || strcmp(kind, "test.log") == 0 ||
        strcmp(kind, "test.block") == 0) {
        char entry[160];
        if (request != 0) {
            fprintf(stderr, "a send arrived with request %llu\n", (unsigned long long)request);
            exit(1);
        }
        if (strcmp(kind, "test.packet") == 0) {
            snprintf(entry, sizeof entry, "%spacket:%zu", outbound[0] ? " " : "", args[0].length);
        } else {
            snprintf(entry, sizeof entry, "%s%s:%.*s", outbound[0] ? " " : "", kind + 5,
                (int)args[0].length, (const char *)args[0].data);
        }
        strncat(outbound, entry, sizeof outbound - strlen(outbound) - 1);
    } else if (strcmp(kind, "test.outbound") == 0) {
        nupp_value value = text(outbound);
        answer(request, &value, 1);
    } else {
        nupp_error *error = NULL;
        check(nupp_host_fail(runtime, request, "unexpected kind", &error), error, "nupp_host_fail");
    }
}

static void cancelled(nupp_runtime *owner, uint64_t request, void *userdata) {
    (void)owner;
    (void)request;
    (void)userdata;
    cancels++;
}

static void answer_due(void) {
    double now = now_ms();
    size_t kept = 0;
    for (size_t index = 0; index < later_count; index++) {
        Later item = later[index];
        if (item.due > now) {
            later[kept++] = item;
            continue;
        }
        if (item.kind == 1) {
            live++;
            nupp_value value = number(next_resource++);
            answer(item.request, &value, 1);
        } else {
            nupp_value value = number(item.number);
            answer(item.request, &value, 1);
        }
    }
    later_count = kept;
}

static unsigned char *read_all(const char *path, size_t *length) {
    FILE *file = fopen(path, "rb");
    long end;
    unsigned char *data;
    if (!file || fseek(file, 0, SEEK_END) != 0 || (end = ftell(file)) < 0 || fseek(file, 0, SEEK_SET) != 0) return NULL;
    data = (unsigned char *)malloc((size_t)end + 1);
    if (!data || fread(data, 1, (size_t)end, file) != (size_t)end) return NULL;
    fclose(file);
    *length = (size_t)end;
    return data;
}

static const char *state_of(const nupp_value *value) {
    static char buffer[32];
    size_t length = value->length < sizeof buffer - 1 ? value->length : sizeof buffer - 1;
    memcpy(buffer, value->data, length);
    buffer[length] = 0;
    return buffer;
}

static const char *const KINDS[] = {
    "test.echo", "test.results", "test.fail", "test.digest", "test.count", "test.make", "test.slow",
    "test.open", "test.close", "test.live", "test.seen", "test.note", "test.notes", "test.pushInput",
    "test.packet", "test.log", "test.block", "test.outbound", NULL,
};

int main(int argc, char **argv) {
    nupp_component *component = NULL;
    nupp_handle *start = NULL, *poll = NULL, *result = NULL, *direct = NULL, *load = NULL;
    nupp_error *error = NULL;
    nupp_value argument = {0}, state = {0};
    size_t count = 0, length = 0;
    unsigned char *component_bytes;
    double began;

    if ((argc != 4 && argc != 5) || !(component_bytes = read_all(argv[1], &length))) return 2;
    check(nupp_runtime_new(NULL, &runtime, &error), error, "nupp_runtime_new");
    for (const char *const *kind = KINDS; *kind; kind++) {
        check(nupp_host_register(runtime, *kind, handle, cancelled, NULL, &error), error, "nupp_host_register");
    }
    check(nupp_component_load(runtime, component_bytes, length, argv[1], &component, &error), error, "load");
    check(nupp_component_start(runtime, component, 0, NULL, &error), error, "start");
    check(nupp_export_find(runtime, component, "contract.start", &start, &error), error, "find start");
    check(nupp_export_find(runtime, component, "contract.poll", &poll, &error), error, "find poll");
    check(nupp_export_find(runtime, component, "contract.result", &result, &error), error, "find result");
    check(nupp_export_find(runtime, component, "contract.direct", &direct, &error), error, "find direct");
    check(nupp_export_find(runtime, component, "contract.load", &load, &error), error, "find load");
    argument = text(argv[2]);
    check(nupp_call(runtime, load, &argument, 1, &state, 0, &count, &error), error, "contract.load");
    nupp_handle_release(runtime, load, NULL);

    argument = text(argv[3]);
    if (argc == 5) {
        check(nupp_call(runtime, direct, &argument, 1, &state, 1, &count, &error), error, "contract.direct");
        printf("%.*s\n", (int)state.length, (const char *)state.data);
        nupp_value_release(runtime, &state, NULL);
        /* The host still answers what it was asked; nothing is waiting for it. */
        while (later_count > 0) {
            answer_due();
            check(nupp_runtime_poll(runtime, &error), error, "nupp_runtime_poll");
            sleep_ms(1);
        }
        printf("cancels=%d live=%d\n", cancels, live);
        nupp_handle_release(runtime, direct, NULL);
        nupp_handle_release(runtime, start, NULL);
        nupp_handle_release(runtime, poll, NULL);
        nupp_handle_release(runtime, result, NULL);
        nupp_component_release(runtime, component, NULL);
        check(nupp_runtime_shutdown(runtime, &error), error, "shutdown");
        nupp_runtime_free(runtime);
        return 0;
    }
    check(nupp_call(runtime, start, &argument, 1, &state, 1, &count, &error), error, "contract.start");
    began = now_ms();
    while (strcmp(state_of(&state), "parked") == 0) {
        nupp_value_release(runtime, &state, NULL);
        if (now_ms() - began > 60000) {
            fprintf(stderr, "the scenario was still parked after a minute\n");
            return 1;
        }
        answer_due();
        check(nupp_runtime_poll(runtime, &error), error, "nupp_runtime_poll");
        check(nupp_call(runtime, poll, NULL, 0, &state, 1, &count, &error), error, "contract.poll");
        sleep_ms(1);
    }
    nupp_value_release(runtime, &state, NULL);
    check(nupp_call(runtime, result, NULL, 0, &state, 1, &count, &error), error, "contract.result");
    printf("%.*s\n", (int)state.length, (const char *)state.data);
    nupp_value_release(runtime, &state, NULL);
    printf("cancels=%d live=%d\n", cancels, live);

    /* What nupp_host_answer refuses, as statuses. */
    {
        nupp_value refused = {0};
        refused.kind = NUPP_VALUE_HANDLE;
        printf("unknown=%d", (int)nupp_host_answer(runtime, 999999, NULL, 0, NULL));
        printf(" handle=%d", (int)nupp_host_answer(runtime, last_request, &refused, 1, NULL));
        refused = number(NAN);
        printf(" nan=%d", (int)nupp_host_answer(runtime, last_request, &refused, 1, NULL));
        refused = text("\xff\xfe");
        printf(" text=%d", (int)nupp_host_answer(runtime, last_request, &refused, 1, NULL));
        printf(" reserved=%d", (int)nupp_host_register(runtime, "nupp.secret", handle, NULL, NULL, NULL));
        printf(" malformed=%d\n", (int)nupp_host_register(runtime, "nodots", handle, NULL, NULL, NULL));
    }

    nupp_handle_release(runtime, direct, NULL);
    nupp_handle_release(runtime, start, NULL);
    nupp_handle_release(runtime, poll, NULL);
    nupp_handle_release(runtime, result, NULL);
    nupp_component_release(runtime, component, NULL);
    check(nupp_runtime_shutdown(runtime, &error), error, "shutdown");
    nupp_runtime_free(runtime);
    free(component_bytes);
    return 0;
}
