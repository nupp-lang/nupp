#ifndef _WIN32
/* getifaddrs is outside strict C11 on glibc. */
#define _DEFAULT_SOURCE 1
#endif

#include "nupp_native.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>
#ifndef _WIN32
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <unistd.h>
#endif

_Static_assert(offsetof(NuppNativeNetSlice, length) == sizeof(void *),
    "network slice length has an unexpected offset");
_Static_assert(offsetof(NuppNativeNetAddress, port) == 16,
    "network address port has an unexpected offset");
_Static_assert(offsetof(NuppNativeNetAddress, family) == 18,
    "network address family has an unexpected offset");
_Static_assert(offsetof(NuppNativeNetEndpoint, family) == 4,
    "network endpoint family has an unexpected offset");
_Static_assert(offsetof(NuppNativeNetEndpoint, port) == 6,
    "network endpoint port has an unexpected offset");
_Static_assert(offsetof(NuppNativeNetEndpoint, scope_id) == 8,
    "network endpoint scope has an unexpected offset");
_Static_assert(offsetof(NuppNativeNetEndpoint, flowinfo) == 12,
    "network endpoint flow label has an unexpected offset");
_Static_assert(offsetof(NuppNativeNetEndpoint, address) == 16,
    "network endpoint address has an unexpected offset");
_Static_assert(sizeof(NuppNativeNetEndpoint) == 32,
    "network endpoint has an unexpected size");

static int failed(const char *operation, int32_t status) {
    fprintf(stderr, "%s: status %d: %s\n", operation, status,
        nuppNativeLastError());
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
            status = nuppNativeNetConnectPoll(connect, &state, &stream);
            if (status != NUPP_NATIVE_OK) return failed("connect poll", status);
            if (state == NUPP_NATIVE_NET_CONNECT_FAILED) {
                fprintf(stderr, "loopback connect failed: %s\n",
                    nuppNativeLastError());
                return 1;
            }
            if (state == NUPP_NATIVE_NET_CONNECT_READY) *client = stream;
        }
        if (*server == 0) {
            status = nuppNativeNetListenerAccept(listener, &state, &stream);
            if (status != NUPP_NATIVE_OK) return failed("listener accept", status);
            if (state == NUPP_NATIVE_NET_ACCEPTED) *server = stream;
        }
        if (*client == 0 || *server == 0) {
            status = nuppNativePoll(&generation);
            if (status != NUPP_NATIVE_OK) return failed("network poll", status);
            status = nuppNativeWait(generation, 50, &generation);
            if (status != NUPP_NATIVE_OK) return failed("network wait", status);
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
        int32_t status = nuppNativeNetStreamRead(
            stream, bytes, sizeof bytes, &state, &length);
        if (status != NUPP_NATIVE_OK) return failed("stream read", status);
        if (state == NUPP_NATIVE_NET_READ_DATA) {
            if (length != count || memcmp(bytes, expected, count) != 0) {
                fprintf(stderr, "network read changed its payload\n");
                return 1;
            }
            return 0;
        }
        status = nuppNativePoll(&generation);
        if (status != NUPP_NATIVE_OK) return failed("network poll", status);
        status = nuppNativeWait(generation, 50, &generation);
        if (status != NUPP_NATIVE_OK) return failed("network wait", status);
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
        int32_t status = nuppNativeNetStreamRead(
            stream, &byte, 1, &state, &length);
        if (status != NUPP_NATIVE_OK) return failed("EOF read", status);
        if (state == NUPP_NATIVE_NET_READ_EOF) return 0;
        status = nuppNativePoll(&generation);
        if (status != NUPP_NATIVE_OK) return failed("network poll", status);
        status = nuppNativeWait(generation, 50, &generation);
        if (status != NUPP_NATIVE_OK) return failed("EOF wait", status);
    }
    fprintf(stderr, "half-close did not reach EOF\n");
    return 1;
}

static int wait_for_stream_flag(uint64_t stream, uint32_t expected,
        const char *message) {
    size_t attempts;

    for (attempts = 0; attempts != 100; ++attempts) {
        uint32_t flags = 0;
        uint64_t generation = 0;
        int32_t status = nuppNativePoll(&generation);
        if (status != NUPP_NATIVE_OK) return failed("network poll", status);
        status = nuppNativeNetStreamState(stream, &flags);
        if (status != NUPP_NATIVE_OK) return failed("stream state", status);
        if ((flags & expected) != 0) return 0;
        if ((flags & (NUPP_NATIVE_NET_STREAM_CLOSED
                | NUPP_NATIVE_NET_STREAM_WRITE_FAILED)) != 0) break;
        status = nuppNativeWait(generation, 50, &generation);
        if (status != NUPP_NATIVE_OK) return failed("stream state wait", status);
    }
    fprintf(stderr, "%s\n", message);
    return 1;
}

static int receive_datagram(uint64_t socket, uint8_t *bytes, size_t capacity,
        size_t expected, int32_t expected_truncated,
        NuppNativeNetAddress *address) {
    size_t attempts;

    for (attempts = 0; attempts != 100; ++attempts) {
        uint32_t state = 0;
        size_t length = 0;
        int32_t truncated = 0;
        uint64_t generation = 0;
        int32_t status = nuppNativeNetDatagramReceive(
            socket, bytes, capacity, &state, &length, address, &truncated);
        if (status != NUPP_NATIVE_OK) return failed("datagram receive", status);
        if (state == NUPP_NATIVE_NET_DATAGRAM_MESSAGE) {
            if (length != expected || truncated != expected_truncated) {
                fprintf(stderr, "datagram receive changed length or truncation\n");
                return 1;
            }
            return 0;
        }
        status = nuppNativePoll(&generation);
        if (status != NUPP_NATIVE_OK) return failed("datagram poll", status);
        status = nuppNativeWait(generation, 50, &generation);
        if (status != NUPP_NATIVE_OK) return failed("datagram wait", status);
    }
    fprintf(stderr, "datagram did not become ready\n");
    return 1;
}

static int test_datagrams(uint64_t wrong_kind) {
    static const uint8_t payload[] = "truncated";
    NuppNativeNetDatagramOptions options = {0};
    NuppNativeNetAddress destination = {{127, 0, 0, 1}, 0,
        NUPP_NATIVE_NET_ADDRESS_V4};
    NuppNativeNetAddress source = {{0}, 0, 0};
    uint8_t bytes[16] = {0};
    uint64_t sender = 0;
    uint64_t receiver = 0;
    uint16_t port = 0;
    uint32_t state = 0;
    size_t sent = 0;
    int32_t status;

    options.host.data = (const uint8_t *)"127.0.0.1";
    options.host.length = sizeof "127.0.0.1" - 1;
    status = nuppNativeNetDatagramCreate(&options, &sender);
    if (status != NUPP_NATIVE_OK) return failed("sender create", status);
    status = nuppNativeNetDatagramCreate(&options, &receiver);
    if (status != NUPP_NATIVE_OK) return failed("receiver create", status);
    status = nuppNativeNetDatagramPort(receiver, &port);
    if (status != NUPP_NATIVE_OK) return failed("datagram port", status);
    if (port == 0) {
        fprintf(stderr, "datagram retained ephemeral port zero\n");
        return 1;
    }
    if (nuppNativeNetDatagramPort(wrong_kind, &port)
            != NUPP_NATIVE_INVALID_ARGUMENT) {
        fprintf(stderr, "datagram accepted a wrong-kind handle\n");
        return 1;
    }
    destination.port = port;
    status = nuppNativeNetDatagramSend(
        sender, &destination, NULL, 0, &state, &sent);
    if (status != NUPP_NATIVE_OK) return failed("empty datagram send", status);
    if (state != NUPP_NATIVE_NET_DATAGRAM_SENT || sent != 0) {
        fprintf(stderr, "empty datagram was not sent as one message\n");
        return 1;
    }
    if (receive_datagram(receiver, bytes, sizeof bytes, 0, 0, &source) != 0)
        return 1;
    if (source.family != NUPP_NATIVE_NET_ADDRESS_V4 || source.port == 0) {
        fprintf(stderr, "empty datagram lost its sender\n");
        return 1;
    }
    status = nuppNativeNetDatagramSend(sender, &destination,
        payload, sizeof payload - 1, &state, &sent);
    if (status != NUPP_NATIVE_OK) return failed("datagram send", status);
    if (state != NUPP_NATIVE_NET_DATAGRAM_SENT
        || sent != sizeof payload - 1) {
        fprintf(stderr, "datagram send changed its length\n");
        return 1;
    }
    if (receive_datagram(receiver, bytes, 4, 4, 1, &source) != 0) return 1;
    if (memcmp(bytes, payload, 4) != 0) {
        fprintf(stderr, "truncated datagram changed its prefix\n");
        return 1;
    }
    status = nuppNativeNetDatagramSetBroadcast(sender, 1);
    if (status != NUPP_NATIVE_OK) return failed("datagram broadcast", status);
    status = nuppNativeNetDatagramSetMulticastTtl(sender, 1);
    if (status != NUPP_NATIVE_OK) return failed("datagram multicast ttl", status);
    status = nuppNativeNetDatagramSetMulticastLoop(sender, 0);
    if (status != NUPP_NATIVE_OK) return failed("datagram multicast loop", status);
    status = nuppNativeNetDatagramRelease(receiver);
    if (status != NUPP_NATIVE_OK) return failed("receiver release", status);
    if (nuppNativeNetDatagramRelease(receiver) != NUPP_NATIVE_STALE_HANDLE) {
        fprintf(stderr, "released datagram handle was revived\n");
        return 1;
    }
    status = nuppNativeNetDatagramRelease(sender);
    if (status != NUPP_NATIVE_OK) return failed("sender release", status);
    return 0;
}

#ifndef _WIN32
static int receive_endpoint(uint64_t socket, uint8_t *bytes, size_t capacity,
        const char *expected, NuppNativeNetEndpoint *peer) {
    size_t attempts;

    for (attempts = 0; attempts != 100; ++attempts) {
        uint32_t state = 0;
        size_t length = 0;
        int32_t truncated = 0;
        uint64_t generation = 0;
        int32_t status = nuppNativeNetDatagramReceiveEndpoint(
            socket, bytes, capacity, &state, &length, peer, &truncated);
        if (status != NUPP_NATIVE_OK) {
            return failed("endpoint datagram receive", status);
        }
        if (state == NUPP_NATIVE_NET_DATAGRAM_MESSAGE) {
            if (length != strlen(expected)
                || memcmp(bytes, expected, length) != 0) {
                fprintf(stderr, "endpoint datagram changed its payload\n");
                return 1;
            }
            return 0;
        }
        status = nuppNativePoll(&generation);
        if (status != NUPP_NATIVE_OK) return failed("datagram poll", status);
        status = nuppNativeWait(generation, 50, &generation);
        if (status != NUPP_NATIVE_OK) return failed("datagram wait", status);
    }
    fprintf(stderr, "endpoint datagram did not become ready\n");
    return 1;
}

/* A link-local IPv6 address this machine holds, written as `address%zone`
 * with its interface's name. Zero when it has none. */
static int link_local_address(char *text, size_t capacity) {
    struct ifaddrs *all = NULL;
    struct ifaddrs *each;
    int found = 0;

    if (getifaddrs(&all) != 0) return 0;
    for (each = all; each && !found; each = each->ifa_next) {
        struct sockaddr_in6 address;
        char literal[INET6_ADDRSTRLEN];
        if (!each->ifa_addr || each->ifa_addr->sa_family != AF_INET6
            || !(each->ifa_flags & IFF_UP)) {
            continue;
        }
        memcpy(&address, each->ifa_addr, sizeof address);
        if (!IN6_IS_ADDR_LINKLOCAL(&address.sin6_addr)) continue;
        /* BSD kernels embed the interface index in the second word. */
        address.sin6_addr.s6_addr[2] = 0;
        address.sin6_addr.s6_addr[3] = 0;
        if (!inet_ntop(AF_INET6, &address.sin6_addr, literal, sizeof literal)) {
            continue;
        }
        snprintf(text, capacity, "%s%%%s", literal, each->ifa_name);
        found = 1;
    }
    freeifaddrs(all);
    return found;
}
#endif

#ifndef _WIN32
/* The POSIX half of N-4: send from a link-local IPv6 address and answer the
 * peer the datagram arrived from, which needs the scope it carried. */
static int link_local_round_trip(void) {
    NuppNativeNetDatagramOptions options = {0};
    NuppNativeNetEndpoint destination = {0};
    NuppNativeNetEndpoint peer = {0};
    NuppNativeNetEndpoint reply = {0};
    NuppNativeNetSlice host;
    char zoned[INET6_ADDRSTRLEN + IF_NAMESIZE + 2];
    uint8_t text[96];
    uint8_t bytes[16];
    size_t length = 0;
    size_t sent = 0;
    uint64_t sender = 0;
    uint64_t receiver = 0;
    uint16_t port = 0;
    uint32_t state = 0;
    int32_t status;

    destination.size = sizeof destination;
    if (!link_local_address(zoned, sizeof zoned)) {
        fprintf(stderr, "no link-local IPv6 address; skipping the reply\n");
        return 0;
    }
    options.host.data = (const uint8_t *)"::";
    options.host.length = 2;
    status = nuppNativeNetDatagramCreate(&options, &receiver);
    if (status != NUPP_NATIVE_OK) return failed("IPv6 receiver create", status);
    status = nuppNativeNetDatagramCreate(&options, &sender);
    if (status != NUPP_NATIVE_OK) return failed("IPv6 sender create", status);
    status = nuppNativeNetDatagramPort(receiver, &port);
    if (status != NUPP_NATIVE_OK) return failed("IPv6 receiver port", status);

    host.data = (const uint8_t *)zoned;
    host.length = strlen(zoned);
    status = nuppNativeNetEndpointParse(host, port, &destination);
    if (status != NUPP_NATIVE_OK) return failed("zoned endpoint parse", status);
    if (destination.family != NUPP_NATIVE_NET_ADDRESS_V6
        || destination.scope_id == 0 || destination.port != port
        || destination.size != sizeof destination) {
        fprintf(stderr, "%s parsed without its scope\n", zoned);
        return 1;
    }
    status = nuppNativeNetEndpointText(&destination, text, sizeof text, &length);
    if (status != NUPP_NATIVE_OK) return failed("endpoint text", status);
    if (!memchr(text, '%', length)) {
        fprintf(stderr, "endpoint text dropped its scope\n");
        return 1;
    }
    if (nuppNativeNetEndpointText(&destination, text, 2, &length)
            != NUPP_NATIVE_BUFFER_TOO_SMALL || length <= 2) {
        fprintf(stderr, "a short endpoint text output was not too small\n");
        return 1;
    }

    status = nuppNativeNetDatagramSendEndpoint(sender, &destination,
        (const uint8_t *)"ping", 4, &state, &sent);
    if (status != NUPP_NATIVE_OK) return failed("link-local send", status);
    peer.size = sizeof peer;
    if (receive_endpoint(receiver, bytes, sizeof bytes, "ping", &peer) != 0) {
        return 1;
    }
    if (peer.family != NUPP_NATIVE_NET_ADDRESS_V6 || peer.scope_id == 0) {
        fprintf(stderr, "the link-local peer arrived without its scope\n");
        return 1;
    }
    status = nuppNativeNetDatagramSendEndpoint(receiver, &peer,
        (const uint8_t *)"pong", 4, &state, &sent);
    if (status != NUPP_NATIVE_OK) return failed("link-local reply", status);
    if (state != NUPP_NATIVE_NET_DATAGRAM_SENT || sent != 4) {
        fprintf(stderr, "the link-local reply was not sent\n");
        return 1;
    }
    reply.size = sizeof reply;
    if (receive_endpoint(sender, bytes, sizeof bytes, "pong", &reply) != 0) {
        return 1;
    }
    nuppNativeNetDatagramRelease(sender);
    nuppNativeNetDatagramRelease(receiver);
    return 0;
}
#endif

/* N-4: a datagram from a link-local IPv6 peer can be answered. An address
 * without a scope names no interface, so the reply has to carry the one the
 * datagram arrived with. */
static int test_link_local_reply(void) {
    NuppNativeNetEndpoint destination = {0};
    NuppNativeNetSlice host;

    if ((nuppNativeFeatures() & NUPP_NATIVE_FEATURE_NET_ENDPOINT) == 0) {
        fprintf(stderr, "network endpoint feature bit is absent\n");
        return 1;
    }
    destination.size = 8;
    host.data = (const uint8_t *)"::1";
    host.length = 3;
    if (nuppNativeNetEndpointParse(host, 1, &destination)
            != NUPP_NATIVE_INVALID_ARGUMENT) {
        fprintf(stderr, "a short endpoint size was accepted\n");
        return 1;
    }
    destination.size = sizeof destination;
    host.data = (const uint8_t *)"127.0.0.1%1";
    host.length = sizeof "127.0.0.1%1" - 1;
    if (nuppNativeNetEndpointParse(host, 1, &destination)
            != NUPP_NATIVE_INVALID_ARGUMENT) {
        fprintf(stderr, "an IPv4 address with a zone was accepted\n");
        return 1;
    }
#ifdef _WIN32
    return 0;
#else
    return link_local_round_trip();
#endif
}

#ifndef _WIN32
static int test_path_stream(void) {
    static const uint8_t payload[] = "path";
    char path[104];
    NuppNativeNetPathListenOptions listen_options = {0};
    NuppNativeNetPathConnectOptions connect_options = {0};
    NuppNativeNetAddress address = {{0}, 0, 0};
    uint64_t listener = 0;
    uint64_t connect = 0;
    uint64_t client = 0;
    uint64_t server = 0;
    uint32_t kind = 0;
    uint32_t state = 0;
    size_t accepted = 0;
    int32_t status;

    snprintf(path, sizeof path, "/tmp/nupp-net-abi-%ld.sock", (long)getpid());
    unlink(path);
    listen_options.path.data = (const uint8_t *)path;
    listen_options.path.length = strlen(path);
    listen_options.backlog = 8;
    status = nuppNativeNetPathListenerCreate(&listen_options, &listener);
    if (status != NUPP_NATIVE_OK) return failed("path listener", status);
    status = nuppNativeNetListenerKind(listener, &kind);
    if (status != NUPP_NATIVE_OK) return failed("path listener kind", status);
    if (kind != NUPP_NATIVE_NET_LISTENER_PATH) {
        fprintf(stderr, "path listener reported the wrong kind\n");
        return 1;
    }
    connect_options.path = listen_options.path;
    connect_options.timeout_ms = 5000;
    status = nuppNativeNetPathConnectCreate(&connect_options, &connect);
    if (status != NUPP_NATIVE_OK) return failed("path connect", status);
    if (wait_for_pair(listener, connect, &client, &server) != 0) return 1;
    status = nuppNativeNetStreamPeerAddress(client, &address);
    if (status != NUPP_NATIVE_OK) return failed("path address", status);
    if (address.family != NUPP_NATIVE_NET_ADDRESS_NONE) {
        fprintf(stderr, "path stream invented an internet address\n");
        return 1;
    }
    status = nuppNativeNetStreamWrite(client, payload,
        sizeof payload - 1, &state, &accepted);
    if (status != NUPP_NATIVE_OK) return failed("path write", status);
    if (state != NUPP_NATIVE_NET_WRITE_ACCEPTED
        || accepted != sizeof payload - 1) {
        fprintf(stderr, "path write was not accepted\n");
        return 1;
    }
    if (read_exact(server, payload, sizeof payload - 1) != 0) return 1;
    status = nuppNativeNetStreamRelease(server);
    if (status != NUPP_NATIVE_OK) return failed("path server release", status);
    status = nuppNativeNetStreamRelease(client);
    if (status != NUPP_NATIVE_OK) return failed("path client release", status);
    status = nuppNativeNetConnectRelease(connect);
    if (status != NUPP_NATIVE_OK) return failed("path connect release", status);
    status = nuppNativeNetListenerRelease(listener);
    if (status != NUPP_NATIVE_OK) return failed("path listener release", status);
    if (unlink(path) != 0) {
        fprintf(stderr, "path listener removed or retained an unusable path\n");
        return 1;
    }
    return 0;
}
#else
static int test_path_stream(void) { return 0; }
#endif

int main(void) {
    static const uint8_t host[] = "localhost";
    static const uint8_t payload[] = "ping";
    NuppNativeNetListenOptions listen_options = {0};
    NuppNativeNetConnectOptions connect_options = {0};
    NuppNativeNetAddress address = {{0}, 0, 0};
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

    if ((nuppNativeFeatures() & NUPP_NATIVE_FEATURE_NET) == 0) {
        fprintf(stderr, "Rust-native network feature bit is absent\n");
        return 1;
    }
    if (nuppNativeNetListenerCreate(NULL, &listener)
            != NUPP_NATIVE_INVALID_ARGUMENT
        || nuppNativeNetPoll(NULL) != NUPP_NATIVE_INVALID_ARGUMENT
        || nuppNativeNetWait(0, 0, NULL) != NUPP_NATIVE_INVALID_ARGUMENT) {
        fprintf(stderr, "network ABI accepted a null pointer\n");
        return 1;
    }

    listen_options.host.data = (const uint8_t *)"127.0.0.1";
    listen_options.host.length = sizeof "127.0.0.1" - 1;
    listen_options.backlog = 16;
    status = nuppNativeNetListenerCreate(&listen_options, &listener);
    if (status != NUPP_NATIVE_OK) return failed("listener create", status);
    status = nuppNativeNetListenerPort(listener, &port);
    if (status != NUPP_NATIVE_OK) return failed("listener port", status);
    if (port == 0) {
        fprintf(stderr, "loopback listener retained ephemeral port zero\n");
        return 1;
    }

    connect_options.host.data = host;
    connect_options.host.length = sizeof host - 1;
    connect_options.port = port;
    connect_options.timeout_ms = 5000;
    status = nuppNativeNetConnectCreate(&connect_options, &connect);
    if (status != NUPP_NATIVE_OK) return failed("connect create", status);
    if (nuppNativeNetListenerPort(connect, &port)
            != NUPP_NATIVE_INVALID_ARGUMENT
        || nuppNativeNetStreamPendingWrite(listener, &pending)
            != NUPP_NATIVE_INVALID_ARGUMENT) {
        fprintf(stderr, "network ABI accepted a wrong-kind handle\n");
        return 1;
    }
    if (wait_for_pair(listener, connect, &client, &server) != 0) return 1;
    status = nuppNativeNetConnectPoll(connect, &state, &canceled_connect);
    if (status != NUPP_NATIVE_OK
        || state != NUPP_NATIVE_NET_CONNECT_FAILED
        || canceled_connect != 0) {
        fprintf(stderr, "connect result was collected more than once\n");
        return 1;
    }
    {
        uint64_t unused = 1;
        if (nuppNativeNetConnectPoll(listener, &state, &unused)
                != NUPP_NATIVE_INVALID_ARGUMENT) {
            fprintf(stderr, "listener was accepted as a connect\n");
            return 1;
        }
    }

    status = nuppNativeNetStreamLocalAddress(client, &address);
    if (status != NUPP_NATIVE_OK) return failed("local address", status);
    if (address.family != 4 || address.port == 0) {
        fprintf(stderr, "loopback local address is invalid\n");
        return 1;
    }
    status = nuppNativeNetStreamPeerAddress(client, &address);
    if (status != NUPP_NATIVE_OK) return failed("peer address", status);
    if (address.family != 4 || address.port == 0) {
        fprintf(stderr, "loopback peer address is invalid\n");
        return 1;
    }
    status = nuppNativeNetStreamSetNoDelay(client, 1);
    if (status != NUPP_NATIVE_OK) return failed("set no-delay", status);
    status = nuppNativeNetStreamSetKeepAlive(client, 1, 30);
    if (status != NUPP_NATIVE_OK) return failed("set keep-alive", status);
    status = nuppNativeNetStreamSetKeepAliveMs(client, 1, 30000);
    if (status != NUPP_NATIVE_OK) return failed("set keep-alive ms", status);
    if (nuppNativeNetStreamSetKeepAliveMs(client, 1, 0)
            != NUPP_NATIVE_INVALID_ARGUMENT) {
        fprintf(stderr, "a zero keep-alive delay was accepted\n");
        return 1;
    }

    {
        size_t attempts;
        for (attempts = 0; attempts != 100; ++attempts) {
            status = nuppNativeNetStreamWrite(client, payload,
                sizeof payload - 1, &state, &accepted);
            if (status != NUPP_NATIVE_OK) return failed("stream write", status);
            if (state == NUPP_NATIVE_NET_WRITE_ACCEPTED) break;
            if (state == NUPP_NATIVE_NET_WRITE_CLOSED) {
                fprintf(stderr, "loopback stream closed before its write\n");
                return 1;
            }
            status = nuppNativePoll(&generation);
            if (status != NUPP_NATIVE_OK) return failed("network poll", status);
            status = nuppNativeWait(generation, 50, &generation);
            if (status != NUPP_NATIVE_OK) return failed("write wait", status);
        }
        if (state != NUPP_NATIVE_NET_WRITE_ACCEPTED) {
            fprintf(stderr, "network write did not become ready\n");
            return 1;
        }
    }
    if (accepted != sizeof payload - 1) {
        fprintf(stderr, "network write did not accept its payload\n");
        return 1;
    }
    status = nuppNativeNetStreamPendingWrite(client, &pending);
    if (status != NUPP_NATIVE_OK) return failed("pending write", status);
    if (read_exact(server, payload, sizeof payload - 1) != 0) return 1;

    status = nuppNativeNetStreamShutdownWrite(client);
    if (status != NUPP_NATIVE_OK) return failed("shutdown write", status);
    status = nuppNativeNetStreamState(client, &flags);
    if (status != NUPP_NATIVE_OK) return failed("shutdown state", status);
    if ((flags & (NUPP_NATIVE_NET_STREAM_SHUTTING_DOWN
            | NUPP_NATIVE_NET_STREAM_WRITE_CLOSED)) == 0) {
        fprintf(stderr, "stream state missed the pending half-close\n");
        return 1;
    }
    if (wait_for_eof(server) != 0) return 1;
    if (wait_for_stream_flag(client, NUPP_NATIVE_NET_STREAM_WRITE_CLOSED,
            "stream state missed the local half-close") != 0) return 1;
    if (test_datagrams(listener) != 0) return 1;
    if (test_link_local_reply() != 0) return 1;
    if (test_path_stream() != 0) return 1;

    status = nuppNativeNetStreamRelease(server);
    if (status != NUPP_NATIVE_OK) return failed("server release", status);
    if (nuppNativeNetStreamRelease(server) != NUPP_NATIVE_STALE_HANDLE) {
        fprintf(stderr, "released network stream handle was revived\n");
        return 1;
    }
    status = nuppNativeNetStreamRelease(client);
    if (status != NUPP_NATIVE_OK) return failed("client release", status);
    status = nuppNativeNetConnectRelease(connect);
    if (status != NUPP_NATIVE_OK) return failed("connect release", status);
    status = nuppNativeNetListenerRelease(listener);
    if (status != NUPP_NATIVE_OK) return failed("listener release", status);
    if (nuppNativeNetListenerRelease(listener) != NUPP_NATIVE_STALE_HANDLE) {
        fprintf(stderr, "released network listener handle was revived\n");
        return 1;
    }
    return 0;
}
