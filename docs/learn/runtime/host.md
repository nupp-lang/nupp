---
order: 196
title: Host requests
---

# Host requests

[](nupp.host) asks whatever runs the program for something and waits for the
answer. It is meant for a library that needs a facility the host has and Nupp
does not, such as a canvas, a clipboard, an engine's asset loader or its input
devices, and should not care which host it runs under.

::: warning
Nothing answers host requests on the VM yet. There `host.attached()` is
`false`, and every call, post, send and route is refused by name: `nupp: no host
answers app.image.decode; no embedding application is attached`. The VM's
[Rust embedding](../projects/native-modules.md#embedding-the-vm) has no host
channel.
:::

The host answers by kind, a dotted name such as `app.image.decode`. Nupp owns
the channel and nothing that travels on it: what a kind means is between the
library that sends it and the host that answers it.

## Calling a kind

Declare a kind's signature once as a function type and bind it. Callers then get
named arguments and a checked call, and nothing is gathered into a table on the
way through:

```nupp:fragment
local host = nupp.host

--- Returns the host's id for the decoded image, and its width and height.
local type DecodeImage = function(url: string): (integer, integer, integer)
local decodeImage = host.bind<DecodeImage>("app.image.decode")

local id, width, height = decodeImage(url = "sprites.png")
```

A call suspends through [](nupp.suspension) until the host answers, so it
composes with [task scopes](concurrency/task-scopes.md), deadlines and
cancellation. A host failure is raised in the caller with the host's message,
and a kind no host answers is refused by name. `host.call(kind, ...)` is the
same call unbound.

Nothing checks that the host's answer matches the declared results; the
signature is the library's promise about its host, as a C declaration is.

## Values

Arguments and results are a count of flat values: `nil`, booleans, numbers,
strings and bytes. Every position is kept, so interior and trailing `nil`s
arrive as written. A number must be finite and a string must be UTF-8 text of at
most 64 KiB; anything else is bytes. Tables and functions are refused, naming
the argument's position. Structured data is encoded into bytes by the library
that owns it, for example with [](nupp.serde).

Bytes are a [](nupp.mem.span) of bytes. A span is a borrow, so it crosses through
a bound kind whose signature says so; `call` and `post` take `any`, which a
borrow cannot cross:

```nupp:fragment
local host = nupp.host
local span = nupp.mem.span

local type Digest = function(borrows bytes: span.ByteSpan): (integer, span.ByteSpan)
local digest = host.bind<Digest>("app.digest")

const text = "hello"
local length, echoed = digest(bytes = span.fromString(text))
```

A byte result arrives as a span the caller owns. Bytes sent to the host may be
up to 64 MiB and bytes answered up to 8 MiB. Large assets are better named
than carried: give the host a URL or a path and let it answer with an id.

## Results nobody waits for

A call cancelled after it reached the host may still be answered. When its
results name a host resource, bind the kind with `late`, which receives those
results where no task is waiting. It must not suspend, so it releases through
`post`, which queues a request and returns at once:

```nupp:fragment
local host = nupp.host

local type ReleaseImage = function(id: integer): nil
local releaseImage = host.bindPost<ReleaseImage>("app.image.release")

local type DecodeImage = function(url: string): (integer, integer, integer)
local decodeImage = host.bind<DecodeImage>("app.image.decode",
    late = function(id: any, ...: any): nil releaseImage(id) end)
```

A kind without `late` drops a late answer. The host owns a result until the
program holds all of it, so a result whose bytes were still being fetched when
its caller gave up is the host's to release, not `late`'s.

## Streams

A stream carries messages one way, without answers. `send` and `bindSend`
append to an outbound stream that ships with the frame it was sent in.
`route` delivers a kind's inbound messages as [](nupp.events) on a bus the
program owns, each message's values filling the event's fields in declaration
order:

```nupp:fragment
local host = nupp.host
local events = nupp.events
local span = nupp.mem.span

@derive(events.Event)
local struct PointerMove
    x: number
    y: number
end

local input: events.MessageBus<integer> = events.newMessageBus()
input:observe(1, PointerMove, |move| -> print(move.x, move.y), "cursor")
local route = host.route("app.pointer.move", PointerMove, input, 1, "latest")

local type Packet = function(borrows packet: span.ByteSpan): nil
local sendPacket = host.bindSend<Packet>("app.render.packet", "latest")
```

Messages arrive at a turn boundary and an event nothing observes is never
built. A stream that fills applies its policy: `block` suspends the sender until
its frame ships, `latest` keeps only the newest message, and `dropOldest` keeps
the newest up to its limit and counts what it drops (`route:dropped()`). The
host applies an inbound route's policy before the messages cross, so what a
route would drop never costs the program anything. An inbound message carries
scalars and strings, which is what an event's fields hold.

::: seealso
- [](nupp.host) for the full API
- [suspension.md](concurrency/suspension.md) for what a wait does under a handler
:::
