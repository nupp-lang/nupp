/* Times one frame's boundary traffic between an embedding application and the
 * `framebench` component, three ways (see src/framebench.nupp):
 *
 *   n1  Tecs's winit host today: an export per input event, the frame export,
 *       the packet returned from an export, a polling export per queue.
 *   n2  the host channel answered at once: input pushed and routed by a poll,
 *       one frame export, the packet sent on a stream to a borrowing handler.
 *   n3  the host channel answered later: the frame waits on a call this loop
 *       answers, driven by nupp.host.pump.
 *
 * Usage: bench COMPONENT MODE PACKET_BYTES FRAMES
 * Prints: MODE PACKET_BYTES FRAMES NS_PER_FRAME EVENTS_CONSUMED
 */

#include "nupp.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define EVENTS 17
#define WARMUP 2000

static nupp_runtime *runtime;
static uint64_t pending_tick;
static size_t packet_seen;

static void check(nupp_status status, nupp_error *error, const char *what) {
    if (status != NUPP_STATUS_OK) {
        fprintf(stderr, "%s: %s\n", what, error ? nupp_error_message(error) : "(no detail)");
        exit(1);
    }
}

static uint64_t now_ns(void) {
    struct timespec spec;
    clock_gettime(CLOCK_MONOTONIC, &spec);
    return (uint64_t)spec.tv_sec * 1000000000u + (uint64_t)spec.tv_nsec;
}

static nupp_value number(double value) {
    nupp_value result = {0};
    result.kind = NUPP_VALUE_NUMBER;
    result.number = value;
    return result;
}

static void handle(nupp_runtime *owner, uint64_t request, const char *kind,
    const nupp_value *args, size_t count, void *userdata) {
    (void)owner;
    (void)userdata;
    if (strcmp(kind, "bench.packet") == 0) {
        /* Borrowed for this call: a renderer would read it here. */
        packet_seen += count > 0 ? args[0].length : 0;
    } else if (strcmp(kind, "bench.tick") == 0) {
        pending_tick = request;
    }
}

static unsigned char *read_all(const char *path, size_t *length) {
    FILE *file = fopen(path, "rb");
    long end;
    unsigned char *bytes;
    if (!file || fseek(file, 0, SEEK_END) != 0 || (end = ftell(file)) < 0 || fseek(file, 0, SEEK_SET) != 0) return NULL;
    bytes = (unsigned char *)malloc((size_t)end + 1);
    if (!bytes || fread(bytes, 1, (size_t)end, file) != (size_t)end) return NULL;
    fclose(file);
    *length = (size_t)end;
    return bytes;
}

static nupp_handle *find(nupp_component *component, const char *name) {
    nupp_handle *handle = NULL;
    nupp_error *error = NULL;
    check(nupp_export_find(runtime, component, name, &handle, &error), error, name);
    return handle;
}

static void call(nupp_handle *callable, const nupp_value *args, size_t count, const char *what) {
    nupp_value results[2] = {{0}, {0}};
    size_t written = 0;
    nupp_error *error = NULL;
    check(nupp_call(runtime, callable, args, count, results, 2, &written, &error), error, what);
    for (size_t index = 0; index < written; index++) nupp_value_release(runtime, &results[index], NULL);
}

static void push_input(void) {
    nupp_error *error = NULL;
    for (int index = 0; index < EVENTS; index++) {
        nupp_value move[2] = {number(index * 1.5), number(index * 0.5)};
        check(nupp_host_push(runtime, "bench.move", move, 2, &error), error, "nupp_host_push");
    }
}

int main(int argc, char **argv) {
    nupp_component *component = NULL;
    nupp_error *error = NULL;
    size_t length = 0;
    unsigned char *bytes;
    if (argc != 5 || !(bytes = read_all(argv[1], &length))) {
        fprintf(stderr, "usage: bench COMPONENT n1|n2|n3 PACKET_BYTES FRAMES\n");
        return 2;
    }
    const char *mode = argv[2];
    int packet = atoi(argv[3]);
    long frames = atol(argv[4]);
    int channel = strcmp(mode, "n1") != 0;

    check(nupp_runtime_new(NULL, &runtime, &error), error, "nupp_runtime_new");
    check(nupp_host_register(runtime, "bench.packet", handle, NULL, NULL, &error), error, "register");
    check(nupp_host_register(runtime, "bench.tick", handle, NULL, NULL, &error), error, "register");
    check(nupp_component_load(runtime, bytes, length, argv[1], &component, &error), error, "load");
    check(nupp_component_start(runtime, component, 0, NULL, &error), error, "start");
    nupp_handle *setup = find(component, "framebench.setup");
    nupp_handle *push = find(component, "framebench.pushPointerMove");
    nupp_handle *iterate = find(component, "framebench.iterate");
    nupp_handle *render = find(component, "framebench.renderPacket");
    nupp_handle *images = find(component, "framebench.nextImageCommand");
    nupp_handle *captures = find(component, "framebench.nextCapture");
    nupp_handle *models = find(component, "framebench.nextModelUpload");
    nupp_handle *crashed = find(component, "framebench.crashed");
    nupp_handle *frame = find(component, "framebench.frame");
    nupp_handle *start = find(component, "framebench.startLoop");
    nupp_handle *poll = find(component, "framebench.pollLoop");
    nupp_handle *received = find(component, "framebench.received");

    nupp_value setup_args[2] = {number(packet), {0}};
    setup_args[1].kind = NUPP_VALUE_BOOLEAN;
    setup_args[1].boolean = channel;
    call(setup, setup_args, 2, "setup");
    if (strcmp(mode, "n3") == 0) call(start, NULL, 0, "startLoop");

    uint64_t began = 0;
    for (long index = 0; index < frames + WARMUP; index++) {
        if (index == WARMUP) began = now_ns();
        if (strcmp(mode, "n1") == 0) {
            for (int event = 0; event < EVENTS; event++) {
                nupp_value move[2] = {number(event * 1.5), number(event * 0.5)};
                call(push, move, 2, "pushPointerMove");
            }
            nupp_value dt = number(1.0 / 60.0);
            call(iterate, &dt, 1, "iterate");
            call(render, NULL, 0, "renderPacket");
            call(images, NULL, 0, "nextImageCommand");
            call(captures, NULL, 0, "nextCapture");
            call(models, NULL, 0, "nextModelUpload");
            call(crashed, NULL, 0, "crashed");
        } else if (strcmp(mode, "n2") == 0) {
            push_input();
            check(nupp_runtime_poll(runtime, &error), error, "nupp_runtime_poll");
            call(frame, NULL, 0, "frame");
        } else if (strcmp(mode, "n2-input") == 0) {
            push_input();
            check(nupp_runtime_poll(runtime, &error), error, "nupp_runtime_poll");
        } else if (strcmp(mode, "n2-poll") == 0) {
            check(nupp_runtime_poll(runtime, &error), error, "nupp_runtime_poll");
        } else if (strcmp(mode, "n2-send") == 0) {
            call(frame, NULL, 0, "frame");
        } else if (strcmp(mode, "n1-input") == 0) {
            for (int event = 0; event < EVENTS; event++) {
                nupp_value move[2] = {number(event * 1.5), number(event * 0.5)};
                call(push, move, 2, "pushPointerMove");
            }
        } else if (strcmp(mode, "n1-rest") == 0) {
            nupp_value dt = number(1.0 / 60.0);
            call(iterate, &dt, 1, "iterate");
            call(render, NULL, 0, "renderPacket");
            call(images, NULL, 0, "nextImageCommand");
            call(captures, NULL, 0, "nextCapture");
            call(models, NULL, 0, "nextModelUpload");
            call(crashed, NULL, 0, "crashed");
        } else {
            push_input();
            nupp_value now = number((double)index);
            uint64_t tick = pending_tick;
            pending_tick = 0;
            check(nupp_host_answer(runtime, tick, &now, 1, &error), error, "nupp_host_answer");
            /* The pump's poll is the readiness pass. */
            call(poll, NULL, 0, "pollLoop");
        }
    }
    uint64_t elapsed = now_ns() - began;

    nupp_value consumed = {0};
    size_t written = 0;
    check(nupp_call(runtime, received, NULL, 0, &consumed, 1, &written, &error), error, "received");
    printf("%s %d %ld %.1f %.0f\n", mode, packet, frames, (double)elapsed / (double)frames, consumed.number);
    return 0;
}
