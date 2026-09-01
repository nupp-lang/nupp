#include "nupp_native_v2.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>

_Static_assert(offsetof(NuppNativeV2NetSlice, length) == sizeof(void *),
    "network slice length has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2NetAddress, port) == 16,
    "network address port has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2NetAddress, family) == 18,
    "network address family has an unexpected offset");

static int failed(const char *operation, int32_t status) {
    fprintf(stderr, "%s: status %d: %s\n", operation, status,
        nuppNativeV2LastError());
    return 1;
}

static int wait_for_pair(uint64_t listener, uint64_t connect,
        uint64_t *client, uint64_t *server) {
    uint64_t generation = 0;
    size_t attempts;

    for (attempts = 0; attempts != 100 && (*client == 0 || *server == 0);
            ++attempts) {
        uint32_t state = 0;
        uint64_t stream = 0;
        int32_t status;

        if (*client == 0) {
            status = nuppNativeV2NetConnectPoll(connect, &state, &stream);
            if (status != NUPP_NATIVE_V2_OK) return failed("connect poll", status);
            if (state == NUPP_NATIVE_V2_NET_CONNECT_FAILED) {
                fprintf(stderr, "loopback connect failed: %s\n",
                    nuppNativeV2LastError());
                return 1;
            }
            if (state == NUPP_NATIVE_V2_NET_CONNECT_READY) *client = stream;
        }
        if (*server == 0) {
            status = nuppNativeV2NetListenerAccept(listener, &state, &stream);
            if (status != NUPP_NATIVE_V2_OK) return failed("listener accept", status);
            if (state == NUPP_NATIVE_V2_NET_ACCEPTED) *server = stream;
        }
        if (*client == 0 || *server == 0) {
            status = nuppNativeV2NetPoll(&generation);
            if (status != NUPP_NATIVE_V2_OK) return failed("network poll", status);
            status = nuppNativeV2NetWait(generation, 50, &generation);
            if (status != NUPP_NATIVE_V2_OK) return failed("network wait", status);
        }
    }
    if (*client == 0 || *server == 0) {
        fprintf(stderr, "loopback connection did not become ready\n");
        return 1;
    }
    return 0;
}

static int read_exact(uint64_t stream, const uint8_t *expected, size_t count) {
    uint8_t bytes[64];
    size_t length = 0;
    size_t attempts;

    for (attempts = 0; attempts != 100; ++attempts) {
        uint32_t state = 0;
        uint64_t generation = 0;
        int32_t status = nuppNativeV2NetStreamRead(
            stream, bytes, sizeof bytes, &state, &length);
        if (status != NUPP_NATIVE_V2_OK) return failed("stream read", status);
        if (state == NUPP_NATIVE_V2_NET_READ_DATA) {
            if (length != count || memcmp(bytes, expected, count) != 0) {
                fprintf(stderr, "network read changed its payload\n");
                return 1;
            }
            return 0;
        }
        status = nuppNativeV2NetPoll(&generation);
        if (status != NUPP_NATIVE_V2_OK) return failed("network poll", status);
        status = nuppNativeV2NetWait(generation, 50, &generation);
        if (status != NUPP_NATIVE_V2_OK) return failed("network wait", status);
    }
    fprintf(stderr, "network read did not become ready\n");
    return 1;
}

static int wait_for_eof(uint64_t stream) {
    uint8_t byte = 0;
    size_t attempts;

    for (attempts = 0; attempts != 100; ++attempts) {
        uint32_t state = 0;
        size_t length = 0;
        uint64_t generation = 0;
        int32_t status = nuppNativeV2NetStreamRead(
            stream, &byte, 1, &state, &length);
        if (status != NUPP_NATIVE_V2_OK) return failed("EOF read", status);
        if (state == NUPP_NATIVE_V2_NET_READ_EOF) return 0;
        status = nuppNativeV2NetPoll(&generation);
        if (status != NUPP_NATIVE_V2_OK) return failed("network poll", status);
        status = nuppNativeV2NetWait(generation, 50, &generation);
        if (status != NUPP_NATIVE_V2_OK) return failed("EOF wait", status);
    }
    fprintf(stderr, "half-close did not reach EOF\n");
    return 1;
}

int main(void) {
    static const uint8_t host[] = "localhost";
    static const uint8_t payload[] = "ping";
    NuppNativeV2NetListenOptions listen_options = {0};
    NuppNativeV2NetConnectOptions connect_options = {0};
    NuppNativeV2NetAddress address = {{0}, 0, 0};
    uint64_t listener = 0;
    uint64_t connect = 0;
    uint64_t canceled_connect = 0;
    uint64_t client = 0;
    uint64_t server = 0;
    uint16_t port = 0;
    uint32_t state = 0;
    uint32_t flags = 0;
    size_t accepted = 0;
    size_t pending = 0;
    uint64_t generation = 0;
    int32_t status;

    if ((nuppNativeV2Features() & NUPP_NATIVE_V2_FEATURE_NET) == 0) {
        fprintf(stderr, "Rust-native network feature bit is absent\n");
        return 1;
    }
    if (nuppNativeV2NetListenerCreate(NULL, &listener)
            != NUPP_NATIVE_V2_INVALID_ARGUMENT
        || nuppNativeV2NetPoll(NULL) != NUPP_NATIVE_V2_INVALID_ARGUMENT
        || nuppNativeV2NetWait(0, 0, NULL) != NUPP_NATIVE_V2_INVALID_ARGUMENT) {
        fprintf(stderr, "network ABI accepted a null pointer\n");
        return 1;
    }

    listen_options.host.data = (const uint8_t *)"127.0.0.1";
    listen_options.host.length = sizeof "127.0.0.1" - 1;
    listen_options.backlog = 16;
    status = nuppNativeV2NetListenerCreate(&listen_options, &listener);
    if (status != NUPP_NATIVE_V2_OK) return failed("listener create", status);
    status = nuppNativeV2NetListenerPort(listener, &port);
    if (status != NUPP_NATIVE_V2_OK) return failed("listener port", status);
    if (port == 0) {
        fprintf(stderr, "loopback listener retained ephemeral port zero\n");
        return 1;
    }

    connect_options.host.data = host;
    connect_options.host.length = sizeof host - 1;
    connect_options.port = port;
    connect_options.timeout_ms = 5000;
    status = nuppNativeV2NetConnectCreate(&connect_options, &connect);
    if (status != NUPP_NATIVE_V2_OK) return failed("connect create", status);
    if (nuppNativeV2NetListenerPort(connect, &port)
            != NUPP_NATIVE_V2_INVALID_ARGUMENT
        || nuppNativeV2NetStreamPendingWrite(listener, &pending)
            != NUPP_NATIVE_V2_INVALID_ARGUMENT) {
        fprintf(stderr, "network ABI accepted a wrong-kind handle\n");
        return 1;
    }
    if (wait_for_pair(listener, connect, &client, &server) != 0) return 1;
    status = nuppNativeV2NetConnectPoll(connect, &state, &canceled_connect);
    if (status != NUPP_NATIVE_V2_OK
        || state != NUPP_NATIVE_V2_NET_CONNECT_FAILED
        || canceled_connect != 0) {
        fprintf(stderr, "connect result was collected more than once\n");
        return 1;
    }
    status = nuppNativeV2NetConnectCreate(&connect_options, &canceled_connect);
    if (status != NUPP_NATIVE_V2_OK) return failed("cancel connect create", status);
    status = nuppNativeV2NetConnectCancel(canceled_connect);
    if (status != NUPP_NATIVE_V2_OK) return failed("connect cancel", status);
    {
        uint64_t canceled_stream = 1;
        status = nuppNativeV2NetConnectPoll(
            canceled_connect, &state, &canceled_stream);
        if (status != NUPP_NATIVE_V2_OK
            || state != NUPP_NATIVE_V2_NET_CONNECT_FAILED
            || canceled_stream != 0) {
            fprintf(stderr, "canceled connect did not report failure\n");
            return 1;
        }
    }
    status = nuppNativeV2NetConnectRelease(canceled_connect);
    if (status != NUPP_NATIVE_V2_OK) return failed("canceled connect release", status);
    if (nuppNativeV2NetConnectCancel(listener)
            != NUPP_NATIVE_V2_INVALID_ARGUMENT) {
        fprintf(stderr, "listener was accepted as a connect\n");
        return 1;
    }

    status = nuppNativeV2NetStreamLocalAddress(client, &address);
    if (status != NUPP_NATIVE_V2_OK) return failed("local address", status);
    if (address.family != 4 || address.port == 0) {
        fprintf(stderr, "loopback local address is invalid\n");
        return 1;
    }
    status = nuppNativeV2NetStreamPeerAddress(client, &address);
    if (status != NUPP_NATIVE_V2_OK) return failed("peer address", status);
    if (address.family != 4 || address.port == 0) {
        fprintf(stderr, "loopback peer address is invalid\n");
        return 1;
    }
    status = nuppNativeV2NetStreamSetNoDelay(client, 1);
    if (status != NUPP_NATIVE_V2_OK) return failed("set no-delay", status);
    status = nuppNativeV2NetStreamSetKeepAlive(client, 1, 30);
    if (status != NUPP_NATIVE_V2_OK) return failed("set keep-alive", status);

    {
        size_t attempts;
        for (attempts = 0; attempts != 100; ++attempts) {
            status = nuppNativeV2NetStreamWrite(client, payload,
                sizeof payload - 1, &state, &accepted);
            if (status != NUPP_NATIVE_V2_OK) return failed("stream write", status);
            if (state == NUPP_NATIVE_V2_NET_WRITE_ACCEPTED) break;
            if (state == NUPP_NATIVE_V2_NET_WRITE_CLOSED) {
                fprintf(stderr, "loopback stream closed before its write\n");
                return 1;
            }
            status = nuppNativeV2NetPoll(&generation);
            if (status != NUPP_NATIVE_V2_OK) return failed("network poll", status);
            status = nuppNativeV2NetWait(generation, 50, &generation);
            if (status != NUPP_NATIVE_V2_OK) return failed("write wait", status);
        }
        if (state != NUPP_NATIVE_V2_NET_WRITE_ACCEPTED) {
            fprintf(stderr, "network write did not become ready\n");
            return 1;
        }
    }
    if (accepted != sizeof payload - 1) {
        fprintf(stderr, "network write did not accept its payload\n");
        return 1;
    }
    status = nuppNativeV2NetStreamPendingWrite(client, &pending);
    if (status != NUPP_NATIVE_V2_OK) return failed("pending write", status);
    if (read_exact(server, payload, sizeof payload - 1) != 0) return 1;

    status = nuppNativeV2NetStreamShutdownWrite(client);
    if (status != NUPP_NATIVE_V2_OK) return failed("shutdown write", status);
    status = nuppNativeV2NetStreamState(client, &flags);
    if (status != NUPP_NATIVE_V2_OK) return failed("shutdown state", status);
    if ((flags & (NUPP_NATIVE_V2_NET_STREAM_SHUTTING_DOWN
            | NUPP_NATIVE_V2_NET_STREAM_WRITE_CLOSED)) == 0) {
        fprintf(stderr, "stream state missed the pending half-close\n");
        return 1;
    }
    if (wait_for_eof(server) != 0) return 1;
    status = nuppNativeV2NetStreamState(client, &flags);
    if (status != NUPP_NATIVE_V2_OK) return failed("stream state", status);
    if ((flags & NUPP_NATIVE_V2_NET_STREAM_WRITE_CLOSED) == 0) {
        fprintf(stderr, "stream state missed the local half-close\n");
        return 1;
    }

    status = nuppNativeV2NetStreamClose(server);
    if (status != NUPP_NATIVE_V2_OK) return failed("stream close", status);
    status = nuppNativeV2NetStreamRelease(server);
    if (status != NUPP_NATIVE_V2_OK) return failed("server release", status);
    if (nuppNativeV2NetStreamRelease(server) != NUPP_NATIVE_V2_STALE_HANDLE) {
        fprintf(stderr, "released network stream handle was revived\n");
        return 1;
    }
    status = nuppNativeV2NetStreamRelease(client);
    if (status != NUPP_NATIVE_V2_OK) return failed("client release", status);
    status = nuppNativeV2NetConnectRelease(connect);
    if (status != NUPP_NATIVE_V2_OK) return failed("connect release", status);
    status = nuppNativeV2NetListenerRelease(listener);
    if (status != NUPP_NATIVE_V2_OK) return failed("listener release", status);
    if (nuppNativeV2NetListenerRelease(listener) != NUPP_NATIVE_V2_STALE_HANDLE) {
        fprintf(stderr, "released network listener handle was revived\n");
        return 1;
    }
    return 0;
}
