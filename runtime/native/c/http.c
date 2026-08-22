/* The HTTP transport.
 *
 * One client owns one libcurl multi handle and one thread to drive it. That
 * thread is the only one that touches libcurl: every call into this file from
 * Lua either reads state under a lock or leaves a note and wakes the reactor.
 * `curl_multi_wakeup` is the one multi call documented as safe from another
 * thread, and everything crossing the boundary goes through it.
 *
 * A reactor per client rather than one for the process. Two runtimes embedded
 * in one host asked for their own limits, their own proxy and their own
 * cancellation, and a shared reactor would give them each other's.
 *
 * Nothing here calls Lua. A transfer's progress lands in buffers and raises
 * readiness tokens on a bounded, deduplicated queue; the Lua side drains that
 * queue when it chooses, which is what lets one caller wait by sleeping and
 * another by parking a task and pumping this from its frame.
 */

#include "platform.h"

#include <curl/curl.h>

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Ceilings, all of them because a queue that grows with its callers eventually
 * takes the process with it. */
#define MAX_HEADER_BYTES (256u * 1024u)
#define RESPONSE_WINDOW_BYTES (1024u * 1024u)
#define UPLOAD_WINDOW_BYTES (1024u * 1024u)
#define MAX_UPLOAD_OFFER (512u * 1024u)
#define READY_BATCH 256u

#define BODY_NONE 0u
#define BODY_INLINE 1u
#define BODY_UPLOAD 2u
#define BODY_FILE 3u

#define HEAD_PENDING 0u
#define HEAD_READY 1u
#define HEAD_FAILED 2u

#define BODY_DATA 1u
#define BODY_PENDING 2u
#define BODY_EOF 3u
#define BODY_FAILED 4u
#define BODY_CLOSED 5u

#define TOKEN_HEADERS 1u
#define TOKEN_BODY 2u
#define TOKEN_UPLOAD_SPACE 4u
#define TOKEN_FAILED 8u

#define UPLOAD_CLOSED (-1)
#define UPLOAD_BACKPRESSURE 0
#define UPLOAD_ACCEPTED 1

/* --- the shapes the binding passes ------------------------------------- */

typedef struct {
    const uint8_t *data;
    size_t length;
} NuppHttpSlice;

typedef struct {
    NuppHttpSlice name;
    NuppHttpSlice value;
} NuppHttpHeader;

typedef struct {
    uint64_t connectTimeoutMs;
    uint32_t maxRedirects;
    uint32_t maxPendingRequests;
    uint32_t maxConnections;
    uint32_t maxConnectionsPerHost;
    int compressed;
    int hasInsecureHosts;
    int proxyMode;
    NuppHttpSlice proxy;
    int noProxySet;
    NuppHttpSlice noProxy;
    NuppHttpSlice proxyCredentials;
} NuppHttpClientOptions;

typedef struct {
    const void *uri;
    NuppHttpSlice method;
    const NuppHttpHeader *headers;
    size_t headerCount;
    NuppHttpSlice body;
    uint32_t bodyKind;
    int64_t bodyLength;
    uint64_t timeoutMs;
    uint64_t stallTimeoutMs;
    uint64_t maxBytes;
    int insecure;
} NuppHttpRequest;

typedef struct {
    uint16_t status;
    uint8_t version;
    const uint8_t *url;
    size_t urlLength;
    const uint8_t *headers;
    size_t headersLength;
} NuppHttpResponseHead;

typedef struct {
    const void *transfer;
    uint32_t tokens;
} NuppHttpReady;

/* The URI provider's accessor, so a request reads the normalised text the
 * caller's handle already holds rather than the text they typed. */
extern const uint8_t *nuppcUriPart(const void *uri, uint32_t kind, size_t *length);

/* --- transfers ---------------------------------------------------------- */

typedef struct Segment {
    struct Segment *next;
    size_t length;
    size_t offset;
    uint8_t bytes[1];
} Segment;

typedef struct NuppHttpClient NuppHttpClient;

typedef struct NuppHttpTransfer {
    atomic_int references;
    NuppHttpClient *client;

    CURL *easy;
    struct curl_slist *requestHeaders;
    char *url;

    NuppMutex *guard;

    uint32_t head;
    uint16_t status;
    uint8_t version;
    char *effectiveUrl;
    uint8_t *headers;
    size_t headersLength;
    NuppBuffer rawHeaders;
    char *error;

    Segment *bodyHead;
    Segment *bodyTail;
    size_t buffered;
    uint32_t bodyTerminal;
    uint64_t received;
    uint64_t maxBytes;

    uint8_t *upload;
    size_t uploadLength;
    size_t uploadOffset;
    size_t uploadCapacity;
    bool uploadFinished;
    FILE *uploadFile;
    uint8_t *inlineBody;
    size_t inlineLength;

    bool writePaused;
    bool readPaused;
    bool wantsResume;

    atomic_uint tokens;
    atomic_bool queued;
    atomic_bool retired;
    bool cancelled;
    bool finished;
    bool added;
} NuppHttpTransfer;

struct NuppHttpClient {
    atomic_int references;

    CURLM *multi;
    NuppMutex *guard;
    NuppCondition *arrived;

    NuppHttpTransfer **incoming;
    size_t incomingCount;
    size_t incomingCapacity;

    NuppHttpTransfer **readyQueue;
    size_t readyHead;
    size_t readyCount;
    size_t readyCapacity;

    /* What the reactor has on the multi handle. Its own list, touched only by
     * it, because everything in it is a handle libcurl is driving and those are
     * not another thread's to speak to. */
    NuppHttpTransfer **attached;
    size_t attachedCount;
    size_t attachedCapacity;

    size_t active;
    bool stopping;
    bool started;

    uint64_t connectTimeoutMs;
    uint32_t maxRedirects;
    uint32_t maxPendingRequests;
    int compressed;
    int proxyMode;
    char *proxy;
    char *noProxy;
    char *proxyCredentials;
    bool noProxySet;
};

/* --- odds and ends ------------------------------------------------------ */

static char *own(const uint8_t *data, size_t length) {
    char *copy = malloc(length + 1);
    if (copy == NULL) {
        return NULL;
    }
    if (length != 0) {
        memcpy(copy, data, length);
    }
    copy[length] = '\0';
    return copy;
}

/* The reason a transfer failed, replaced rather than appended: the first thing
 * that went wrong is what the caller is told, and a later cascade of
 * consequences is noise. */
static void record(NuppHttpTransfer *transfer, const char *text) {
    if (transfer->error == NULL) {
        transfer->error = own((const uint8_t *)text, strlen(text));
    }
}

static void raise_tokens(NuppHttpTransfer *transfer, uint32_t tokens);
static void retire(NuppHttpTransfer *transfer);
static void client_release(NuppHttpClient *client);
static void transfer_release(NuppHttpTransfer *transfer);

/* --- the readiness queue ------------------------------------------------ */

static void transfer_retain(NuppHttpTransfer *transfer) {
    atomic_fetch_add(&transfer->references, 1);
}

/* Puts a transfer on the client's queue, once. A transfer already queued has
 * its tokens raised instead, which is what keeps one busy download from filling
 * the queue with itself. */
static void raise_tokens(NuppHttpTransfer *transfer, uint32_t tokens) {
    NuppHttpClient *client = transfer->client;
    bool wasQueued;
    if (client == NULL || tokens == 0) {
        return;
    }
    atomic_fetch_or(&transfer->tokens, tokens);
    wasQueued = atomic_exchange(&transfer->queued, true);
    if (wasQueued) {
        return;
    }
    nupp_mutex_lock(client->guard);
    if (client->readyCount == client->readyCapacity) {
        size_t next = client->readyCapacity < 64 ? 64 : client->readyCapacity * 2;
        NuppHttpTransfer **grown = malloc(next * sizeof *grown);
        size_t at;
        if (grown == NULL) {
            nupp_mutex_unlock(client->guard);
            atomic_store(&transfer->queued, false);
            return;
        }
        for (at = 0; at < client->readyCount; at++) {
            grown[at] = client->readyQueue[(client->readyHead + at) % client->readyCapacity];
        }
        free(client->readyQueue);
        client->readyQueue = grown;
        client->readyHead = 0;
        client->readyCapacity = next;
    }
    transfer_retain(transfer);
    client->readyQueue[(client->readyHead + client->readyCount) % client->readyCapacity] =
        transfer;
    client->readyCount++;
    nupp_condition_broadcast(client->arrived);
    nupp_mutex_unlock(client->guard);
}

/* --- libcurl callbacks, all on the reactor thread ----------------------- */

/* One response header line. libcurl hands them over one at a time, ending with
 * the blank line that closes the block -- which is where the head becomes
 * readable, because until then the caller would be looking at half of it. */
static size_t on_header(char *buffer, size_t size, size_t count, void *raw) {
    NuppHttpTransfer *transfer = raw;
    size_t length = size * count;
    bool complete = false;

    nupp_mutex_lock(transfer->guard);
    if (length <= 2 && (length == 0 || buffer[0] == '\r' || buffer[0] == '\n')) {
        complete = true;
    } else if (length > 5 && strncmp(buffer, "HTTP/", 5) == 0) {
        /* A status line, and there may be several: a redirect chain and a 100
         * Continue both send one, and only the last is the response. */
        nupp_buffer_free(&transfer->rawHeaders);
        nupp_buffer_init(&transfer->rawHeaders);
    } else {
        nupp_buffer_append(&transfer->rawHeaders, buffer, length);
        if (transfer->rawHeaders.length > MAX_HEADER_BYTES) {
            record(transfer, "response headers exceeded 262144 bytes");
            transfer->head = HEAD_FAILED;
            nupp_mutex_unlock(transfer->guard);
            raise_tokens(transfer, TOKEN_HEADERS | TOKEN_FAILED);
            return 0;
        }
    }
    nupp_mutex_unlock(transfer->guard);
    (void)complete;
    return length;
}

/* Packs the collected header lines into the table the binding reads: a count,
 * then four little-endian offsets and lengths per header, then the bytes. Names
 * are lowered, because a header written in another case is the same header and
 * every caller above looks one up by name. */
static bool pack_headers(NuppHttpTransfer *transfer) {
    const char *scan = (const char *)transfer->rawHeaders.data;
    size_t remaining = transfer->rawHeaders.length;
    size_t count = 0;
    NuppBuffer table;
    NuppBuffer text;
    size_t at;

    if (scan == NULL) {
        remaining = 0;
    }
    nupp_buffer_init(&table);
    nupp_buffer_init(&text);
    while (remaining != 0) {
        const char *lineEnd = memchr(scan, '\n', remaining);
        size_t lineLength = lineEnd != NULL ? (size_t)(lineEnd - scan) : remaining;
        size_t consumed = lineEnd != NULL ? lineLength + 1 : remaining;
        const char *colon;
        size_t nameLength, valueLength, valueStart;
        uint8_t entry[16];

        while (lineLength != 0 && (scan[lineLength - 1] == '\r' || scan[lineLength - 1] == '\n')) {
            lineLength--;
        }
        colon = memchr(scan, ':', lineLength);
        if (colon == NULL) {
            scan += consumed;
            remaining -= consumed;
            continue;
        }
        nameLength = (size_t)(colon - scan);
        valueStart = nameLength + 1;
        while (valueStart < lineLength && (scan[valueStart] == ' ' || scan[valueStart] == '\t')) {
            valueStart++;
        }
        valueLength = lineLength - valueStart;

        for (at = 0; at < 4; at++) {
            memset(entry + at * 4, 0, 4);
        }
        nupp_buffer_append(&table, entry, sizeof entry);
        {
            size_t nameOffset = text.length;
            size_t valueOffset;
            for (at = 0; at < nameLength; at++) {
                char letter = scan[at];
                nupp_buffer_push(&text,
                    (uint8_t)((letter >= 'A' && letter <= 'Z') ? letter - 'A' + 'a' : letter));
            }
            valueOffset = text.length;
            nupp_buffer_append(&text, scan + valueStart, valueLength);
            /* Filled in below, once the table's own size is known and the text
             * offsets can be shifted past it. */
            {
                uint8_t *slot = table.data + table.length - 16;
                uint32_t numbers[4] = {
                    (uint32_t)nameOffset, (uint32_t)nameLength,
                    (uint32_t)valueOffset, (uint32_t)valueLength,
                };
                for (at = 0; at < 4; at++) {
                    slot[at * 4] = (uint8_t)numbers[at];
                    slot[at * 4 + 1] = (uint8_t)(numbers[at] >> 8);
                    slot[at * 4 + 2] = (uint8_t)(numbers[at] >> 16);
                    slot[at * 4 + 3] = (uint8_t)(numbers[at] >> 24);
                }
            }
        }
        count++;
        scan += consumed;
        remaining -= consumed;
    }

    {
        size_t header = 4 + count * 16;
        size_t total = header + text.length;
        uint8_t *packed = malloc(total + 1);
        if (packed == NULL || table.failed || text.failed) {
            free(packed);
            nupp_buffer_free(&table);
            nupp_buffer_free(&text);
            return false;
        }
        packed[0] = (uint8_t)count;
        packed[1] = (uint8_t)(count >> 8);
        packed[2] = (uint8_t)(count >> 16);
        packed[3] = (uint8_t)(count >> 24);
        memcpy(packed + 4, table.data, count * 16);
        /* The offsets were measured within the text alone; they are absolute in
         * the answer, so each is shifted past the table that precedes it. */
        for (at = 0; at < count; at++) {
            uint8_t *slot = packed + 4 + at * 16;
            unsigned which;
            for (which = 0; which < 4; which += 2) {
                uint32_t value = (uint32_t)slot[which * 4]
                    | ((uint32_t)slot[which * 4 + 1] << 8)
                    | ((uint32_t)slot[which * 4 + 2] << 16)
                    | ((uint32_t)slot[which * 4 + 3] << 24);
                value += (uint32_t)header;
                slot[which * 4] = (uint8_t)value;
                slot[which * 4 + 1] = (uint8_t)(value >> 8);
                slot[which * 4 + 2] = (uint8_t)(value >> 16);
                slot[which * 4 + 3] = (uint8_t)(value >> 24);
            }
        }
        if (text.length != 0) {
            memcpy(packed + header, text.data, text.length);
        }
        packed[total] = 0;
        free(transfer->headers);
        transfer->headers = packed;
        transfer->headersLength = total;
    }
    nupp_buffer_free(&table);
    nupp_buffer_free(&text);
    return true;
}

/* Response bytes. Buffered in segments up to the window, and past that the
 * transfer is paused: libcurl stops reading the socket, the peer's window
 * closes, and the sender slows down. That is backpressure reaching the far end
 * rather than a buffer growing until something falls over. */
static size_t on_body(char *buffer, size_t size, size_t count, void *raw) {
    NuppHttpTransfer *transfer = raw;
    size_t length = size * count;
    Segment *segment;

    nupp_mutex_lock(transfer->guard);
    if (transfer->maxBytes != 0 && transfer->received + length > transfer->maxBytes) {
        record(transfer, "HTTP response exceeded maxBytes");
        transfer->bodyTerminal = BODY_FAILED;
        nupp_mutex_unlock(transfer->guard);
        raise_tokens(transfer, TOKEN_BODY | TOKEN_FAILED);
        return 0;
    }
    if (transfer->buffered >= RESPONSE_WINDOW_BYTES) {
        transfer->writePaused = true;
        nupp_mutex_unlock(transfer->guard);
        return CURL_WRITEFUNC_PAUSE;
    }
    segment = malloc(sizeof *segment + length);
    if (segment == NULL) {
        record(transfer, "out of memory");
        transfer->bodyTerminal = BODY_FAILED;
        nupp_mutex_unlock(transfer->guard);
        raise_tokens(transfer, TOKEN_BODY | TOKEN_FAILED);
        return 0;
    }
    segment->next = NULL;
    segment->length = length;
    segment->offset = 0;
    memcpy(segment->bytes, buffer, length);
    if (transfer->bodyTail != NULL) {
        transfer->bodyTail->next = segment;
    } else {
        transfer->bodyHead = segment;
    }
    transfer->bodyTail = segment;
    transfer->buffered += length;
    transfer->received += length;
    nupp_mutex_unlock(transfer->guard);
    raise_tokens(transfer, TOKEN_BODY);
    return length;
}

/* Request bytes, from whichever of the three shapes the caller chose. An upload
 * with nothing offered yet pauses rather than ending: a stream that has not
 * finished has more to say. */
static size_t on_read(char *buffer, size_t size, size_t count, void *raw) {
    NuppHttpTransfer *transfer = raw;
    size_t room = size * count;
    size_t moved;

    if (transfer->uploadFile != NULL) {
        return fread(buffer, 1, room, transfer->uploadFile);
    }
    nupp_mutex_lock(transfer->guard);
    if (transfer->uploadOffset == transfer->uploadLength) {
        if (transfer->uploadFinished) {
            nupp_mutex_unlock(transfer->guard);
            return 0;
        }
        transfer->readPaused = true;
        nupp_mutex_unlock(transfer->guard);
        return CURL_READFUNC_PAUSE;
    }
    moved = transfer->uploadLength - transfer->uploadOffset;
    if (moved > room) {
        moved = room;
    }
    memcpy(buffer, transfer->upload + transfer->uploadOffset, moved);
    transfer->uploadOffset += moved;
    if (transfer->uploadOffset == transfer->uploadLength) {
        transfer->uploadOffset = 0;
        transfer->uploadLength = 0;
    }
    nupp_mutex_unlock(transfer->guard);
    raise_tokens(transfer, TOKEN_UPLOAD_SPACE);
    return moved;
}

/* --- the reactor -------------------------------------------------------- */

static void settle_transfer(NuppHttpTransfer *transfer, CURLcode result) {
    uint32_t tokens = TOKEN_BODY;
    nupp_mutex_lock(transfer->guard);
    transfer->finished = true;
    if (result == CURLE_OK) {
        long status = 0;
        long version = 0;
        char *effective = NULL;
        curl_easy_getinfo(transfer->easy, CURLINFO_RESPONSE_CODE, &status);
        curl_easy_getinfo(transfer->easy, CURLINFO_HTTP_VERSION, &version);
        curl_easy_getinfo(transfer->easy, CURLINFO_EFFECTIVE_URL, &effective);
        transfer->status = (uint16_t)status;
        transfer->version = (uint8_t)(version == CURL_HTTP_VERSION_1_0 ? 10
            : version == CURL_HTTP_VERSION_2_0 ? 20 : 11);
        if (effective != NULL && transfer->effectiveUrl == NULL) {
            transfer->effectiveUrl = own((const uint8_t *)effective, strlen(effective));
        }
        if (transfer->head == HEAD_PENDING) {
            if (pack_headers(transfer)) {
                transfer->head = HEAD_READY;
            } else {
                record(transfer, "out of memory");
                transfer->head = HEAD_FAILED;
            }
            tokens |= TOKEN_HEADERS;
        }
        if (transfer->bodyTerminal == BODY_PENDING) {
            transfer->bodyTerminal = BODY_EOF;
        }
    } else {
        record(transfer, curl_easy_strerror(result));
        if (transfer->head == HEAD_PENDING) {
            transfer->head = HEAD_FAILED;
            tokens |= TOKEN_HEADERS;
        }
        if (transfer->bodyTerminal == BODY_PENDING) {
            transfer->bodyTerminal = BODY_FAILED;
        }
        tokens |= TOKEN_FAILED;
    }
    nupp_mutex_unlock(transfer->guard);
    raise_tokens(transfer, tokens | TOKEN_UPLOAD_SPACE);
}

/* Everything a transfer's head needs before the body starts arriving.
 *
 * libcurl has no callback for "the head is complete"; the first body byte is
 * the signal, and a response with no body reaches it at the end. So this is
 * called from both places and does nothing the second time. */
static void publish_head(NuppHttpTransfer *transfer) {
    long status = 0;
    long version = 0;
    char *effective = NULL;
    bool ready = false;

    nupp_mutex_lock(transfer->guard);
    if (transfer->head == HEAD_PENDING) {
        curl_easy_getinfo(transfer->easy, CURLINFO_RESPONSE_CODE, &status);
        curl_easy_getinfo(transfer->easy, CURLINFO_HTTP_VERSION, &version);
        curl_easy_getinfo(transfer->easy, CURLINFO_EFFECTIVE_URL, &effective);
        transfer->status = (uint16_t)status;
        transfer->version = (uint8_t)(version == CURL_HTTP_VERSION_1_0 ? 10
            : version == CURL_HTTP_VERSION_2_0 ? 20 : 11);
        if (effective != NULL) {
            free(transfer->effectiveUrl);
            transfer->effectiveUrl = own((const uint8_t *)effective, strlen(effective));
        }
        if (pack_headers(transfer)) {
            transfer->head = HEAD_READY;
        } else {
            record(transfer, "out of memory");
            transfer->head = HEAD_FAILED;
        }
        ready = true;
    }
    nupp_mutex_unlock(transfer->guard);
    if (ready) {
        raise_tokens(transfer, TOKEN_HEADERS);
    }
}

/* The write callback runs after the head is complete, so the head is published
 * from the front of it. */
static size_t on_body_entry(char *buffer, size_t size, size_t count, void *raw) {
    publish_head(raw);
    return on_body(buffer, size, count, raw);
}

static void reactor(void *raw) {
    NuppHttpClient *client = raw;
    for (;;) {
        int running = 0;
        int waiting = 0;
        CURLMsg *message;
        int remaining = 0;
        size_t at;
        NuppHttpTransfer **arrivals = NULL;
        size_t arrivalCount = 0;
        bool stopping;

        nupp_mutex_lock(client->guard);
        stopping = client->stopping;
        arrivals = client->incoming;
        arrivalCount = client->incomingCount;
        client->incoming = NULL;
        client->incomingCount = 0;
        client->incomingCapacity = 0;
        nupp_mutex_unlock(client->guard);

        for (at = 0; at < arrivalCount; at++) {
            NuppHttpTransfer *transfer = arrivals[at];
            if (curl_multi_add_handle(client->multi, transfer->easy) != CURLM_OK) {
                nupp_mutex_lock(transfer->guard);
                record(transfer, "the HTTP client could not start the transfer");
                transfer->head = HEAD_FAILED;
                transfer->bodyTerminal = BODY_FAILED;
                transfer->finished = true;
                nupp_mutex_unlock(transfer->guard);
                raise_tokens(transfer, TOKEN_HEADERS | TOKEN_BODY | TOKEN_FAILED);
                transfer_release(transfer);
                continue;
            }
            transfer->added = true;
            if (client->attachedCount == client->attachedCapacity) {
                size_t next = client->attachedCapacity < 16
                    ? 16 : client->attachedCapacity * 2;
                NuppHttpTransfer **grown =
                    realloc(client->attached, next * sizeof *grown);
                if (grown == NULL) {
                    continue;
                }
                client->attached = grown;
                client->attachedCapacity = next;
            }
            client->attached[client->attachedCount++] = transfer;
        }
        free(arrivals);

        /* Resuming and cancelling, both of them here. `curl_easy_pause` and
         * `curl_multi_remove_handle` on a handle this thread is inside is not
         * another thread's call to make: the Lua side leaves a note and wakes
         * the poll, and this is where the note is read. */
        for (at = 0; at < client->attachedCount; at++) {
            NuppHttpTransfer *transfer = client->attached[at];
            bool resume = false;
            bool cancelled;
            nupp_mutex_lock(transfer->guard);
            resume = transfer->wantsResume;
            transfer->wantsResume = false;
            cancelled = transfer->cancelled;
            nupp_mutex_unlock(transfer->guard);
            if (resume && !cancelled) {
                curl_easy_pause(transfer->easy, CURLPAUSE_CONT);
            }
            if (cancelled && transfer->added) {
                curl_multi_remove_handle(client->multi, transfer->easy);
                transfer->added = false;
                nupp_mutex_lock(transfer->guard);
                transfer->finished = true;
                nupp_mutex_unlock(transfer->guard);
                raise_tokens(transfer, TOKEN_BODY | TOKEN_UPLOAD_SPACE);
                client->attached[at] = client->attached[--client->attachedCount];
                at--;
                transfer_release(transfer);
            }
        }

        curl_multi_perform(client->multi, &running);

        while ((message = curl_multi_info_read(client->multi, &remaining)) != NULL) {
            if (message->msg != CURLMSG_DONE) {
                continue;
            }
            {
                NuppHttpTransfer *transfer = NULL;
                CURL *easy = message->easy_handle;
                CURLcode result = message->data.result;
                curl_easy_getinfo(easy, CURLINFO_PRIVATE, (char **)&transfer);
                curl_multi_remove_handle(client->multi, easy);
                if (transfer != NULL) {
                    size_t scan;
                    transfer->added = false;
                    for (scan = 0; scan < client->attachedCount; scan++) {
                        if (client->attached[scan] == transfer) {
                            client->attached[scan] =
                                client->attached[--client->attachedCount];
                            break;
                        }
                    }
                    publish_head(transfer);
                    settle_transfer(transfer, result);
                    /* The reactor's reference, taken when the transfer was
                     * handed over. Whatever the caller still holds outlives
                     * this. */
                    transfer_release(transfer);
                }
            }
        }

        if (stopping) {
            /* Whatever is still attached is taken off, so `running` reaches
             * zero and this thread ends rather than spinning on a transfer
             * nobody is left to read. */
            while (client->attachedCount != 0) {
                NuppHttpTransfer *transfer = client->attached[--client->attachedCount];
                if (transfer->added) {
                    curl_multi_remove_handle(client->multi, transfer->easy);
                    transfer->added = false;
                }
                nupp_mutex_lock(transfer->guard);
                transfer->finished = true;
                if (transfer->bodyTerminal == BODY_PENDING) {
                    transfer->bodyTerminal = BODY_CLOSED;
                }
                nupp_mutex_unlock(transfer->guard);
                raise_tokens(transfer, TOKEN_BODY | TOKEN_UPLOAD_SPACE | TOKEN_HEADERS);
                transfer_release(transfer);
            }
            break;
        }

        curl_multi_poll(client->multi, NULL, 0, 50, &waiting);
    }
    /* The client's own teardown owns what it allocated; this thread owns only
     * the reference it was given. */
    client_release(client);
}

/* --- resuming ----------------------------------------------------------- */

/* Asks the reactor to look again. Every cross-thread nudge is this: leave the
 * note under the lock, then wake the poll. */
static void nudge(NuppHttpClient *client) {
    curl_multi_wakeup(client->multi);
}

/* --- lifetime ----------------------------------------------------------- */

static void transfer_free(NuppHttpTransfer *transfer) {
    Segment *segment = transfer->bodyHead;
    while (segment != NULL) {
        Segment *next = segment->next;
        free(segment);
        segment = next;
    }
    if (transfer->easy != NULL) {
        curl_easy_cleanup(transfer->easy);
    }
    if (transfer->requestHeaders != NULL) {
        curl_slist_free_all(transfer->requestHeaders);
    }
    if (transfer->uploadFile != NULL) {
        fclose(transfer->uploadFile);
    }
    nupp_buffer_free(&transfer->rawHeaders);
    nupp_mutex_free(transfer->guard);
    free(transfer->url);
    free(transfer->effectiveUrl);
    free(transfer->headers);
    free(transfer->error);
    free(transfer->upload);
    free(transfer->inlineBody);
    free(transfer);
}

static void transfer_release(NuppHttpTransfer *transfer) {
    if (transfer == NULL || atomic_fetch_sub(&transfer->references, 1) != 1) {
        return;
    }
    {
        NuppHttpClient *client = transfer->client;
        transfer_free(transfer);
        if (client != NULL) {
            client_release(client);
        }
    }
}

static void client_free(NuppHttpClient *client) {
    if (client->multi != NULL) {
        curl_multi_cleanup(client->multi);
    }
    nupp_mutex_free(client->guard);
    nupp_condition_free(client->arrived);
    free(client->incoming);
    free(client->readyQueue);
    free(client->attached);
    free(client->proxy);
    free(client->noProxy);
    free(client->proxyCredentials);
    free(client);
}

static void client_release(NuppHttpClient *client) {
    if (client != NULL && atomic_fetch_sub(&client->references, 1) == 1) {
        client_free(client);
    }
}

/* --- the client --------------------------------------------------------- */

NUPP_EXPORT NuppHttpClient *nuppcHttpClientCreate(const NuppHttpClientOptions *options) {
    NuppHttpClient *client;
    if (options == NULL) {
        nupp_fail("HTTP client options are null");
        return NULL;
    }
    if (options->connectTimeoutMs == 0) {
        nupp_fail("HTTP connection timeouts and limits must be positive");
        return NULL;
    }
    /* Once per process, before any handle exists. libcurl says so and means it:
     * the lazy path is not safe when two threads arrive together. */
    curl_global_init(CURL_GLOBAL_DEFAULT);

    client = calloc(1, sizeof *client);
    if (client == NULL) {
        nupp_fail("out of memory");
        return NULL;
    }
    atomic_init(&client->references, 1);
    client->multi = curl_multi_init();
    client->guard = nupp_mutex_new();
    client->arrived = nupp_condition_new();
    if (client->multi == NULL || client->guard == NULL || client->arrived == NULL) {
        client_free(client);
        nupp_fail("cannot create an HTTP client");
        return NULL;
    }
    client->connectTimeoutMs = options->connectTimeoutMs;
    client->maxRedirects = options->maxRedirects;
    client->maxPendingRequests = options->maxPendingRequests;
    client->compressed = options->compressed;
    client->proxyMode = options->proxyMode;
    client->noProxySet = options->noProxySet != 0;
    if (options->proxy.length != 0) {
        client->proxy = own(options->proxy.data, options->proxy.length);
    }
    if (options->noProxy.length != 0) {
        client->noProxy = own(options->noProxy.data, options->noProxy.length);
    }
    if (options->proxyCredentials.length != 0) {
        client->proxyCredentials =
            own(options->proxyCredentials.data, options->proxyCredentials.length);
    }
    if (options->maxConnections != 0) {
        curl_multi_setopt(client->multi, CURLMOPT_MAX_TOTAL_CONNECTIONS,
            (long)options->maxConnections);
    }
    if (options->maxConnectionsPerHost != 0) {
        curl_multi_setopt(client->multi, CURLMOPT_MAX_HOST_CONNECTIONS,
            (long)options->maxConnectionsPerHost);
    }

    /* The reactor holds a reference of its own, released when it stops. */
    atomic_fetch_add(&client->references, 1);
    if (!nupp_thread_spawn(reactor, client)) {
        atomic_fetch_sub(&client->references, 1);
        client_free(client);
        return NULL;
    }
    client->started = true;
    return client;
}

NUPP_EXPORT void nuppcHttpClientDestroy(NuppHttpClient *client) {
    if (client == NULL) {
        return;
    }
    nupp_mutex_lock(client->guard);
    client->stopping = true;
    nupp_mutex_unlock(client->guard);
    nudge(client);
    /* Whatever is still queued is the caller's to release; this hands back only
     * the handle they were given. */
    client_release(client);
}

NUPP_EXPORT size_t nuppcHttpClientPending(const NuppHttpClient *client) {
    size_t active;
    if (client == NULL) {
        return 0;
    }
    nupp_mutex_lock(((NuppHttpClient *)client)->guard);
    active = client->active;
    nupp_mutex_unlock(((NuppHttpClient *)client)->guard);
    return active;
}

NUPP_EXPORT double nuppcHttpMonotonicMs(void) {
    return nupp_monotonic_ms();
}

/* --- sending ------------------------------------------------------------ */

static bool set_request_headers(NuppHttpTransfer *transfer, const NuppHttpRequest *request) {
    size_t at;
    for (at = 0; at < request->headerCount; at++) {
        const NuppHttpHeader *header = &request->headers[at];
        NuppBuffer line;
        struct curl_slist *grown;
        nupp_buffer_init(&line);
        nupp_buffer_append(&line, header->name.data, header->name.length);
        nupp_buffer_append(&line, ": ", 2);
        nupp_buffer_append(&line, header->value.data, header->value.length);
        nupp_buffer_push(&line, 0);
        if (line.failed) {
            nupp_buffer_free(&line);
            return false;
        }
        grown = curl_slist_append(transfer->requestHeaders, (const char *)line.data);
        nupp_buffer_free(&line);
        if (grown == NULL) {
            return false;
        }
        transfer->requestHeaders = grown;
    }
    /* libcurl adds an `Expect: 100-continue` to a large upload of its own
     * accord, and a peer that never answers it costs a second of dead time per
     * request. The callers here stream rather than wait. */
    {
        struct curl_slist *grown = curl_slist_append(transfer->requestHeaders, "Expect:");
        if (grown == NULL) {
            return false;
        }
        transfer->requestHeaders = grown;
    }
    return true;
}

NUPP_EXPORT const NuppHttpTransfer *nuppcHttpClientSend(
    NuppHttpClient *client, const NuppHttpRequest *request
) {
    NuppHttpTransfer *transfer;
    const uint8_t *url;
    size_t urlLength = 0;

    if (client == NULL || request == NULL) {
        nupp_fail("HTTP client or request is null");
        return NULL;
    }
    nupp_mutex_lock(client->guard);
    if (client->stopping) {
        nupp_mutex_unlock(client->guard);
        nupp_fail("the HTTP client is closed");
        return NULL;
    }
    if (client->maxPendingRequests != 0 && client->active >= client->maxPendingRequests) {
        nupp_mutex_unlock(client->guard);
        nupp_fail("the HTTP client has reached maxPendingRequests");
        return NULL;
    }
    client->active++;
    nupp_mutex_unlock(client->guard);

    url = nuppcUriPart(request->uri, 0, &urlLength);
    if (url == NULL) {
        nupp_mutex_lock(client->guard);
        client->active--;
        nupp_mutex_unlock(client->guard);
        nupp_fail("URI is null");
        return NULL;
    }

    transfer = calloc(1, sizeof *transfer);
    if (transfer == NULL) {
        nupp_mutex_lock(client->guard);
        client->active--;
        nupp_mutex_unlock(client->guard);
        nupp_fail("out of memory");
        return NULL;
    }
    /* One for the caller, one for the reactor. */
    atomic_init(&transfer->references, 2);
    atomic_init(&transfer->tokens, 0);
    atomic_init(&transfer->queued, false);
    atomic_init(&transfer->retired, false);
    transfer->client = client;
    atomic_fetch_add(&client->references, 1);
    transfer->guard = nupp_mutex_new();
    transfer->easy = curl_easy_init();
    transfer->url = own(url, urlLength);
    transfer->head = HEAD_PENDING;
    transfer->bodyTerminal = BODY_PENDING;
    transfer->maxBytes = request->maxBytes;
    nupp_buffer_init(&transfer->rawHeaders);
    if (transfer->guard == NULL || transfer->easy == NULL || transfer->url == NULL) {
        goto refuse;
    }

    curl_easy_setopt(transfer->easy, CURLOPT_URL, transfer->url);
    curl_easy_setopt(transfer->easy, CURLOPT_PRIVATE, transfer);
    curl_easy_setopt(transfer->easy, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(transfer->easy, CURLOPT_HEADERFUNCTION, on_header);
    curl_easy_setopt(transfer->easy, CURLOPT_HEADERDATA, transfer);
    curl_easy_setopt(transfer->easy, CURLOPT_WRITEFUNCTION, on_body_entry);
    curl_easy_setopt(transfer->easy, CURLOPT_WRITEDATA, transfer);
    curl_easy_setopt(transfer->easy, CURLOPT_CONNECTTIMEOUT_MS,
        (long)client->connectTimeoutMs);
    if (request->timeoutMs != 0) {
        curl_easy_setopt(transfer->easy, CURLOPT_TIMEOUT_MS, (long)request->timeoutMs);
    }
    if (request->stallTimeoutMs != 0) {
        /* A transfer moving no bytes at all for this long has stalled. libcurl
         * counts in seconds, and a stall shorter than one is not one. */
        long seconds = (long)((request->stallTimeoutMs + 999) / 1000);
        curl_easy_setopt(transfer->easy, CURLOPT_LOW_SPEED_LIMIT, 1L);
        curl_easy_setopt(transfer->easy, CURLOPT_LOW_SPEED_TIME, seconds);
    }
    if (client->maxRedirects != 0) {
        curl_easy_setopt(transfer->easy, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(transfer->easy, CURLOPT_MAXREDIRS, (long)client->maxRedirects);
    }
    if (client->compressed) {
        curl_easy_setopt(transfer->easy, CURLOPT_ACCEPT_ENCODING, "");
    }
    if (request->insecure) {
        curl_easy_setopt(transfer->easy, CURLOPT_SSL_VERIFYPEER, 0L);
        curl_easy_setopt(transfer->easy, CURLOPT_SSL_VERIFYHOST, 0L);
    }
    switch (client->proxyMode) {
        case 1:
            curl_easy_setopt(transfer->easy, CURLOPT_NOPROXY, "*");
            break;
        case 2:
            curl_easy_setopt(transfer->easy, CURLOPT_PROXY, client->proxy);
            if (client->proxyCredentials != NULL) {
                curl_easy_setopt(transfer->easy, CURLOPT_PROXYUSERPWD,
                    client->proxyCredentials);
            }
            if (client->noProxySet && client->noProxy != NULL) {
                curl_easy_setopt(transfer->easy, CURLOPT_NOPROXY, client->noProxy);
            }
            break;
        default:
            break;
    }
    if (request->method.length != 0) {
        char *method = own(request->method.data, request->method.length);
        if (method == NULL) {
            goto refuse;
        }
        if (strcmp(method, "HEAD") == 0) {
            curl_easy_setopt(transfer->easy, CURLOPT_NOBODY, 1L);
        }
        curl_easy_setopt(transfer->easy, CURLOPT_CUSTOMREQUEST, method);
        /* libcurl copies the string, so the original is this call's to free. */
        free(method);
    }
    if (!set_request_headers(transfer, request)) {
        goto refuse;
    }
    curl_easy_setopt(transfer->easy, CURLOPT_HTTPHEADER, transfer->requestHeaders);

    switch (request->bodyKind) {
        case BODY_INLINE:
            transfer->inlineBody = (uint8_t *)own(request->body.data, request->body.length);
            if (transfer->inlineBody == NULL) {
                goto refuse;
            }
            transfer->inlineLength = request->body.length;
            curl_easy_setopt(transfer->easy, CURLOPT_POSTFIELDS, transfer->inlineBody);
            curl_easy_setopt(transfer->easy, CURLOPT_POSTFIELDSIZE_LARGE,
                (curl_off_t)request->body.length);
            break;
        case BODY_FILE: {
            char *path = own(request->body.data, request->body.length);
            if (path == NULL) {
                goto refuse;
            }
            transfer->uploadFile = fopen(path, "rb");
            free(path);
            if (transfer->uploadFile == NULL) {
                nupp_fail("cannot open the request body file");
                goto refuse;
            }
            curl_easy_setopt(transfer->easy, CURLOPT_UPLOAD, 1L);
            curl_easy_setopt(transfer->easy, CURLOPT_READFUNCTION, on_read);
            curl_easy_setopt(transfer->easy, CURLOPT_READDATA, transfer);
            /* A file has a length, and saying so is what makes the request carry
             * a Content-Length rather than chunked encoding. The caller has no
             * way to supply one -- it named a path -- so it is measured here.
             * A peer that reads the header and not the chunks would otherwise
             * see an empty body, which is a real thing peers do. */
            {
                long size = -1;
                if (fseek(transfer->uploadFile, 0, SEEK_END) == 0) {
                    size = ftell(transfer->uploadFile);
                    rewind(transfer->uploadFile);
                }
                if (request->bodyLength >= 0) {
                    size = (long)request->bodyLength;
                }
                if (size >= 0) {
                    curl_easy_setopt(transfer->easy, CURLOPT_INFILESIZE_LARGE,
                        (curl_off_t)size);
                }
            }
            break;
        }
        case BODY_UPLOAD:
            curl_easy_setopt(transfer->easy, CURLOPT_UPLOAD, 1L);
            curl_easy_setopt(transfer->easy, CURLOPT_READFUNCTION, on_read);
            curl_easy_setopt(transfer->easy, CURLOPT_READDATA, transfer);
            if (request->bodyLength >= 0) {
                curl_easy_setopt(transfer->easy, CURLOPT_INFILESIZE_LARGE,
                    (curl_off_t)request->bodyLength);
            }
            break;
        default:
            break;
    }

    nupp_mutex_lock(client->guard);
    if (client->incomingCount == client->incomingCapacity) {
        size_t next = client->incomingCapacity < 16 ? 16 : client->incomingCapacity * 2;
        NuppHttpTransfer **grown = realloc(client->incoming, next * sizeof *grown);
        if (grown == NULL) {
            nupp_mutex_unlock(client->guard);
            goto refuse;
        }
        client->incoming = grown;
        client->incomingCapacity = next;
    }
    client->incoming[client->incomingCount++] = transfer;
    nupp_mutex_unlock(client->guard);
    nudge(client);
    return transfer;

refuse:
    nupp_mutex_lock(client->guard);
    client->active--;
    nupp_mutex_unlock(client->guard);
    /* Both references, since neither side ever received it. */
    atomic_store(&transfer->references, 1);
    transfer_release(transfer);
    return NULL;
}

/* --- observing a transfer ----------------------------------------------- */

NUPP_EXPORT uint32_t nuppcHttpTransferPollHeaders(
    const NuppHttpTransfer *handle, NuppHttpResponseHead *output
) {
    NuppHttpTransfer *transfer = (NuppHttpTransfer *)handle;
    uint32_t answer;
    if (transfer == NULL) {
        return HEAD_FAILED;
    }
    nupp_mutex_lock(transfer->guard);
    answer = transfer->head;
    if (answer == HEAD_READY) {
        if (output == NULL) {
            nupp_mutex_unlock(transfer->guard);
            nupp_fail("HTTP response head output is null");
            return HEAD_FAILED;
        }
        output->status = transfer->status;
        output->version = transfer->version;
        output->url = (const uint8_t *)transfer->effectiveUrl;
        output->urlLength = transfer->effectiveUrl != NULL
            ? strlen(transfer->effectiveUrl) : 0;
        output->headers = transfer->headers;
        output->headersLength = transfer->headersLength;
    }
    nupp_mutex_unlock(transfer->guard);
    return answer;
}

NUPP_EXPORT const char *nuppcHttpTransferError(const NuppHttpTransfer *handle) {
    NuppHttpTransfer *transfer = (NuppHttpTransfer *)handle;
    const char *text;
    if (transfer == NULL) {
        return NULL;
    }
    nupp_mutex_lock(transfer->guard);
    text = transfer->error;
    nupp_mutex_unlock(transfer->guard);
    return text;
}

NUPP_EXPORT const char *nuppcHttpBodyError(const NuppHttpTransfer *handle) {
    return nuppcHttpTransferError(handle);
}

/* A second handle on the same transfer, for the caller that hands the body on
 * while keeping the head. */
NUPP_EXPORT const NuppHttpTransfer *nuppcHttpTransferTakeBody(const NuppHttpTransfer *handle) {
    NuppHttpTransfer *transfer = (NuppHttpTransfer *)handle;
    if (transfer == NULL) {
        return NULL;
    }
    transfer_retain(transfer);
    return transfer;
}

/* Says the caller is reading the body, so a response nobody reads does not hold
 * its slot. */
NUPP_EXPORT bool nuppcHttpBodyArm(const NuppHttpTransfer *handle) {
    return handle != NULL;
}

NUPP_EXPORT bool nuppcHttpBodyPeek(
    const NuppHttpTransfer *handle, const uint8_t **data, size_t *length, uint32_t *state
) {
    NuppHttpTransfer *transfer = (NuppHttpTransfer *)handle;
    bool finished;
    if (data == NULL || length == NULL || state == NULL) {
        nupp_fail("HTTP body peek output is null");
        return false;
    }
    if (transfer == NULL) {
        return false;
    }
    nupp_mutex_lock(transfer->guard);
    *data = NULL;
    *length = 0;
    if (transfer->bodyHead != NULL) {
        *data = transfer->bodyHead->bytes + transfer->bodyHead->offset;
        *length = transfer->bodyHead->length - transfer->bodyHead->offset;
        *state = BODY_DATA;
    } else {
        *state = transfer->bodyTerminal;
    }
    finished = transfer->bodyHead == NULL && transfer->bodyTerminal != BODY_PENDING;
    nupp_mutex_unlock(transfer->guard);
    if (finished) {
        retire(transfer);
    }
    return true;
}

NUPP_EXPORT bool nuppcHttpBodyConsume(const NuppHttpTransfer *handle, size_t count) {
    NuppHttpTransfer *transfer = (NuppHttpTransfer *)handle;
    bool resume = false;
    if (transfer == NULL) {
        return false;
    }
    nupp_mutex_lock(transfer->guard);
    if (transfer->bodyHead == NULL) {
        nupp_mutex_unlock(transfer->guard);
        nupp_fail("HTTP body has no bytes to consume");
        return false;
    }
    if (count > transfer->bodyHead->length - transfer->bodyHead->offset) {
        nupp_mutex_unlock(transfer->guard);
        nupp_fail("HTTP body consume exceeds the preceding peek");
        return false;
    }
    transfer->bodyHead->offset += count;
    transfer->buffered -= count;
    if (transfer->bodyHead->offset == transfer->bodyHead->length) {
        Segment *done = transfer->bodyHead;
        transfer->bodyHead = done->next;
        if (transfer->bodyHead == NULL) {
            transfer->bodyTail = NULL;
        }
        free(done);
    }
    /* Room again, so the socket may be read again. The unpause itself belongs to
     * the reactor: `curl_easy_pause` on a handle another thread is driving is
     * not this thread's call to make. */
    if (transfer->writePaused && transfer->buffered < RESPONSE_WINDOW_BYTES) {
        transfer->writePaused = false;
        transfer->wantsResume = true;
        resume = true;
    }
    nupp_mutex_unlock(transfer->guard);
    if (resume && transfer->client != NULL) {
        nudge(transfer->client);
    }
    return true;
}

/* --- offering a request body -------------------------------------------- */

NUPP_EXPORT int nuppcHttpTransferOffer(
    const NuppHttpTransfer *handle, const uint8_t *data, size_t length, bool finished
) {
    NuppHttpTransfer *transfer = (NuppHttpTransfer *)handle;
    bool resume = false;
    if (transfer == NULL) {
        return UPLOAD_CLOSED;
    }
    if (length > MAX_UPLOAD_OFFER) {
        nupp_fail("an HTTP upload chunk must contain 1 through 524288 bytes");
        return UPLOAD_CLOSED;
    }
    nupp_mutex_lock(transfer->guard);
    if (transfer->finished || transfer->cancelled) {
        nupp_mutex_unlock(transfer->guard);
        return UPLOAD_CLOSED;
    }
    if (transfer->uploadFinished && length != 0) {
        nupp_mutex_unlock(transfer->guard);
        nupp_fail("a finished HTTP upload must have an empty chunk");
        return UPLOAD_CLOSED;
    }
    if (length != 0 && transfer->uploadLength + length > UPLOAD_WINDOW_BYTES) {
        nupp_mutex_unlock(transfer->guard);
        return UPLOAD_BACKPRESSURE;
    }
    if (length != 0) {
        if (transfer->uploadLength + length > transfer->uploadCapacity) {
            size_t next = transfer->uploadCapacity < 4096 ? 4096 : transfer->uploadCapacity;
            uint8_t *grown;
            while (next < transfer->uploadLength + length) {
                next *= 2;
            }
            grown = realloc(transfer->upload, next);
            if (grown == NULL) {
                nupp_mutex_unlock(transfer->guard);
                nupp_fail("out of memory");
                return UPLOAD_CLOSED;
            }
            transfer->upload = grown;
            transfer->uploadCapacity = next;
        }
        memcpy(transfer->upload + transfer->uploadLength, data, length);
        transfer->uploadLength += length;
    }
    if (finished) {
        transfer->uploadFinished = true;
    }
    if (transfer->readPaused) {
        transfer->readPaused = false;
        transfer->wantsResume = true;
        resume = true;
    }
    nupp_mutex_unlock(transfer->guard);
    if (resume && transfer->client != NULL) {
        nudge(transfer->client);
    }
    return UPLOAD_ACCEPTED;
}

/* --- ending a transfer -------------------------------------------------- */

NUPP_EXPORT void nuppcHttpTransferCancel(const NuppHttpTransfer *handle) {
    NuppHttpTransfer *transfer = (NuppHttpTransfer *)handle;
    if (transfer == NULL) {
        return;
    }
    nupp_mutex_lock(transfer->guard);
    transfer->cancelled = true;
    if (transfer->bodyTerminal == BODY_PENDING) {
        transfer->bodyTerminal = BODY_CLOSED;
    }
    nupp_mutex_unlock(transfer->guard);
    /* The reactor takes it off the multi handle when it next looks; a transfer
     * cancelled from here must not be touching libcurl. */
    if (transfer->client != NULL) {
        nudge(transfer->client);
    }
}

/* Gives the transfer's admission slot back, once.
 *
 * A slot is held for as long as the caller might still be reading, which is not
 * the same as for as long as the handle exists: a response whose body has been
 * read to its end is finished with the client whatever the caller does with the
 * handle afterwards. Waiting for the handle instead would park the next request
 * behind a reply somebody had already read. */
static void retire(NuppHttpTransfer *transfer) {
    NuppHttpClient *client = transfer->client;
    if (client == NULL || atomic_exchange(&transfer->retired, true)) {
        return;
    }
    nupp_mutex_lock(client->guard);
    if (client->active != 0) {
        client->active--;
    }
    nupp_condition_broadcast(client->arrived);
    nupp_mutex_unlock(client->guard);
}

NUPP_EXPORT void nuppcHttpTransferDestroy(const NuppHttpTransfer *handle) {
    NuppHttpTransfer *transfer = (NuppHttpTransfer *)handle;
    if (transfer == NULL) {
        return;
    }
    nuppcHttpTransferCancel(handle);
    retire(transfer);
    transfer_release(transfer);
}

NUPP_EXPORT void nuppcHttpBodyDestroy(const NuppHttpTransfer *handle) {
    transfer_release((NuppHttpTransfer *)handle);
}

NUPP_EXPORT void nuppcHttpReadyRelease(const NuppHttpTransfer *handle) {
    transfer_release((NuppHttpTransfer *)handle);
}

/* --- draining readiness ------------------------------------------------- */

static size_t drain(
    NuppHttpClient *client, NuppHttpReady *output, size_t capacity, bool *more
) {
    size_t count = 0;
    if (capacity > READY_BATCH) {
        capacity = READY_BATCH;
    }
    nupp_mutex_lock(client->guard);
    while (count < capacity && client->readyCount != 0) {
        NuppHttpTransfer *transfer = client->readyQueue[client->readyHead];
        uint32_t tokens;
        client->readyHead = (client->readyHead + 1) % client->readyCapacity;
        client->readyCount--;
        atomic_store(&transfer->queued, false);
        tokens = atomic_exchange(&transfer->tokens, 0);
        /* A token raised between the swap above and the flag below would
         * otherwise be lost, so the transfer goes back on rather than waiting
         * for the next event to carry it. */
        if (atomic_load(&transfer->tokens) != 0
            && !atomic_exchange(&transfer->queued, true)) {
            transfer_retain(transfer);
            client->readyQueue[(client->readyHead + client->readyCount) % client->readyCapacity] =
                transfer;
            client->readyCount++;
        }
        output[count].transfer = transfer;
        output[count].tokens = tokens;
        count++;
    }
    if (more != NULL) {
        *more = client->readyCount != 0;
    }
    nupp_mutex_unlock(client->guard);
    return count;
}

NUPP_EXPORT size_t nuppcHttpClientPoll(
    NuppHttpClient *client, NuppHttpReady *output, size_t capacity, bool *more
) {
    if (client == NULL) {
        nupp_fail("HTTP client is null");
        return 0;
    }
    if (capacity != 0 && output == NULL) {
        nupp_fail("HTTP ready output is null");
        return 0;
    }
    return drain(client, output, capacity, more);
}

NUPP_EXPORT size_t nuppcHttpClientWait(
    NuppHttpClient *client, uint64_t milliseconds,
    NuppHttpReady *output, size_t capacity, bool *more
) {
    size_t count;
    if (client == NULL) {
        nupp_fail("HTTP client is null");
        return 0;
    }
    if (capacity != 0 && output == NULL) {
        nupp_fail("HTTP ready output is null");
        return 0;
    }
    count = drain(client, output, capacity, more);
    if (count != 0) {
        return count;
    }
    nupp_mutex_lock(client->guard);
    if (client->readyCount == 0) {
        nupp_condition_wait_for(client->arrived, client->guard, milliseconds);
    }
    nupp_mutex_unlock(client->guard);
    return drain(client, output, capacity, more);
}
