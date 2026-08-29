#include <SDL3/SDL.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static void fail(const char *what) {
    fprintf(stderr, "%s: %s\n", what, SDL_GetError());
    exit(1);
}

static double batch(SDL_AsyncIOQueue *queue, const char *path, int concurrency) {
    SDL_AsyncIOOutcome outcome;
    Uint64 started = SDL_GetPerformanceCounter();
    int submitted;
    int completed = 0;

    for (submitted = 0; submitted < concurrency; submitted++) {
        if (!SDL_LoadFileAsync(path, queue, (void *)(uintptr_t)submitted)) {
            fail("SDL_LoadFileAsync");
        }
    }
    while (completed < concurrency) {
        if (!SDL_WaitAsyncIOResult(queue, &outcome, -1)) {
            continue;
        }
        if (outcome.type != SDL_ASYNCIO_TASK_READ
            || outcome.result != SDL_ASYNCIO_COMPLETE) {
            fail("asynchronous read");
        }
        SDL_free(outcome.buffer);
        completed++;
    }
    return (double)(SDL_GetPerformanceCounter() - started) * 1000.0
        / (double)SDL_GetPerformanceFrequency();
}

int main(int argc, char **argv) {
    SDL_AsyncIOQueue *queue;
    double total = 0.0;
    int concurrency;
    int repeats;
    int iteration;

    if (argc != 4) {
        fprintf(stderr, "usage: asyncio-sdl FILE CONCURRENCY REPEATS\n");
        return 2;
    }
    concurrency = atoi(argv[2]);
    repeats = atoi(argv[3]);
    queue = SDL_CreateAsyncIOQueue();
    if (!queue) fail("SDL_CreateAsyncIOQueue");
    (void)batch(queue, argv[1], concurrency);
    for (iteration = 0; iteration < repeats; iteration++) {
        total += batch(queue, argv[1], concurrency);
    }
    printf("SDL AsyncIO: %d reads, %.3f ms/batch, %.3f ms/read\n",
        concurrency, total / repeats, total / repeats / concurrency);
    SDL_DestroyAsyncIOQueue(queue);
    return 0;
}
