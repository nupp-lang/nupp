`nupp.io.http` sends HTTP requests over the native Reqwest/Tokio provider
without blocking the caller's frame. Reach for it when a program needs a client
that works the same in a CLI, a scheduler and a game host.

```nupp
local http = require("nupp.io.http")
local uri = require("nupp.io.uri")

local client = new http.Client()
local response = assert(client:send(new http.Request(
    url = assert(uri.newURI("https://example.com/"))
)))
print(response.status)
response:close()
client:close()
```

Calls suspend through [`nupp.suspension`](../../../concepts/suspension.md): a
CLI blocks on the provider's condvar, while a scheduler or SDL host only drives
the nonblocking source. See
[0005-suspension.md](../../../neps/0005-suspension.md) for why waiting is a
suspension rather than a block.

A response status is an answer, 4xx and 5xx included. Transport and body
failures are returned as reasons instead. Response bodies and generic request
readers are progressive and bounded, so a large body is read in pieces against
a limit rather than assembled first.

## Requests that go out together

Requests share a client and go out together when something drives them
together. `nupp.suspension` runs each body in a coroutine of its own, and the
one waiting on the network is what lets the next one send:

```nupp
local http = require("nupp.io.http")
local suspension = require("nupp.suspension")
local uri = require("nupp.io.uri")

local client = new http.Client()

local function status(url: string): integer
    local response = assert(client:send(new http.Request(
        url = assert(uri.newURI(url))
    )))
    local code = response.status
    response:close()

    return code
end

local codes = suspension.all({function(): integer
    return status("https://example.com/")
end, function(): integer
    return status("https://example.org/")
end,})

print(codes[1], codes[2])
client:close()
```

A body calls a function holding the client rather than capturing the client
itself, because a closure that captures an owner directly cannot be stored.

Two bounds decide how much of that happens at once. `maxConnectionsPerHost`
bounds what one host is asked to carry, and `suspension.batch` bounds how many
requests are in flight at all.

## Ownership

A client, a response and its body are all owners, so each closes at its lexical
boundary unless it is transferred.

::: seealso
- [ownership.md](../../../type-system/ownership.md) for the complete contract
  reference
- [suspension.md](../../../concepts/suspension.md) for what a wait does under a
  handler
- [uri.md](uri.md) for the URI values a request is addressed with
:::
