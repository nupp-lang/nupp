---
order: 196
title: Host requests
---

# Host requests

[](nupp.host) asks whatever runs the program for something and waits for the
answer: the page's JavaScript in a browser, or the C or Rust application that
embeds the runtime natively. Use it when a library needs a facility the host
has and Nupp does not, such as a canvas, a clipboard, an engine's asset loader
or its input devices, and should not care which host it runs under.

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
up to 64 MiB and bytes answered up to 8 MiB, on both hosts, so a kind that works
natively cannot fail in the browser on size alone. Large assets are better named
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

## Answering in a browser

A packaged application's page answers through the `host` option of `run`:

```js
import {run, push} from "./nupp-browser-app.mjs";

const result = await run({
  host: {
    handlers: {
      "app.image.decode": async ([url], {signal}) => {
        const image = await createImageBitmap(await (await fetch(url, {signal})).blob());
        return [registerTexture(image), image.width, image.height];
      },
      "app.image.release": ([id]) => releaseTexture(id),
    },
    module: new URL("./host-worker.mjs", import.meta.url),
    end: () => console.log("the application finished"),
  },
});

addEventListener("pointermove", (event) => push("app.pointer.move", event.x, event.y));
```

A handler receives the request's values as an array and answers with an array
of results, or one value, or nothing. Bytes arrive and leave as `Uint8Array`. Its
`signal` aborts when the caller stops waiting. A handler may be an object with
`call` and `release`; `release(results)` runs for results the program never came
to own. `handlers` run on the page, where the DOM and audio are. `module` names
a module loaded into the application's Worker, whose exported `handlers` answer
there without a hop to the page and whose `start({push})` receives a push
function of its own. `push` on the entry module queues an inbound message from
anywhere on the page.

`nupp-audio.mjs` answers an outbound stream of interleaved 32-bit float samples
with an AudioWorklet:

```js
import {audioStream} from "./nupp-audio.mjs";

const audio = await audioStream({kind: "app.audio", channels: 2, bufferAheadMs: 50});
await run({host: {handlers: {...audio.handlers}}});
```

The buffer-ahead is the latency, and what a slow frame may spend before playback
runs dry. In the browser guest, 50 ms played twenty seconds without an underrun;
less did not. No SharedArrayBuffer or cross-origin isolation is needed.

## Answering natively

An application embedding the runtime registers a C handler per kind and answers
at once or later from its own loop; see
[Answering host requests](../projects/embedding.md#answering-host-requests). A
program run on its own with `nupp run` has no host, and `host.attached()` says
so.

Natively a park blocks inside the call the application made, so a request the
application answers later must run under a suspension handler. [](nupp.host.pump)
is one: it runs an operation until it finishes or parks, and the application
polls it from its loop.

## What a frame costs

In the browser the program runs in an emulated machine, and every frame it
takes crosses to the page and back. A frame's host traffic, however many calls,
posts, sends and inbound messages, travels as one request carrying binary
records, and the page answers into the same buffer. Make the channel the
frame's boundary, a call that waits for the page's next frame, rather than
waiting on a timer beside it: a frame that took its input on a route, sent a
small packet and called the host now and then cost the guest no more than an
empty frame did.

A call that waits alone for its answer takes one frame each way. Many calls made
together share their frames, so issue independent calls from separate tasks in
a [task scope](concurrency/task-scopes.md) rather than one after another.

::: seealso
- [](nupp.host) for the full API
- [suspension.md](concurrency/suspension.md) for what a wait does under a handler
- [embedding.md](../projects/embedding.md) for the C side of the channel
:::
