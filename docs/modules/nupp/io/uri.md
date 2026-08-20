`nupp.io.uri` parses one absolute URI into an immutable value and answers its
components from the parse rather than from a substring. Reach for it when a
program routes, rewrites or inspects a resource identifier.

```nupp
const uri = require("nupp.io.uri")

local endpoint, reason = uri.new("https://user@example.com:8443/api?q=1#top")
assert(endpoint, reason)
assert(endpoint:scheme() == "https")
assert(endpoint:host() == "example.com")
assert(endpoint:port() == 8443)
```

Two URIs are equal when their normalized text is, so a host or scheme written in
another case does not make one URI unequal to an otherwise identical one. The
parsed handle is released by the collector, so nothing has to be closed.

## Reading components

`scheme` and `path` answer a string, and `path` is empty rather than nil when
the URI names none. `username` is empty when there is no user information.
Every other component is optional and answers nil when the URI does not write
it:

```nupp
const uri = require("nupp.io.uri")

local plain = assert(uri.new("mailto:someone@example.com"))
assert(plain:host() == nil)
assert(plain:port() == nil)
assert(plain:path() == "someone@example.com")
```

The remaining accessors are `authority`, `password`, `userInfo`, `query` and
`fragment`. `toString` answers the normalized complete URI, and `tostring(uri)`
is the same call.

## Validating untrusted text

`uri.new` answers nil and a reason for malformed input, because bad text is an
ordinary answer. `uri.validate` asks the same question without retaining an
object, and `uri.isURI` separates a URI from a string or a record:

```nupp
const uri = require("nupp.io.uri")

local ok, why = uri.validate("http://[")
assert(not ok and why)
assert(not uri.isURI("https://example.com"))
```

::: deepdive Parsing answers a reason, modification raises
A parse takes text from somewhere else, so failure is data and the caller is
handed it. A `with` operation starts from a URI that already parsed, so a
failure means the caller asked for something the grammar cannot express, which
is a mistake at the call site rather than a bad input. Text that came from
outside the program therefore goes through `uri.new`, `uri.validate` or
`resolve`, all of which answer a reason.
:::

## Deriving a new URI

Every `with` operation answers a new URI and leaves the original unchanged.
Supplying a component equal to its current normalized value answers the
receiver itself rather than reparsing:

```nupp
const uri = require("nupp.io.uri")

local endpoint = assert(uri.new("https://user:pass@example.com:8443/api?q=1"))
local production = endpoint:withUserInfo(nil):withHost("api.example.com")
assert(production:userInfo() == nil)
assert(production:host() == "api.example.com")
assert(endpoint:host() == "example.com")
```

The operations are `withScheme`, `withUserInfo`, `withHost`, `withPort`,
`withPath`, `withQuery` and `withFragment`. Passing nil removes an optional
component. A port must be an integer from 0 through 65535, and anything else
raises.

`concatPath` appends path text without interpreting it as a reference:

```nupp
const uri = require("nupp.io.uri")

local api = assert(uri.new("https://api.example.com/v1"))
assert(api:concatPath("users"):path() == "/v1/users")
```

`withEndpoint(endpoint)` takes another URI's scheme and authority and keeps the
receiver's path, query and fragment, which is what reroutes a request URI
through a configured service address.

## Resolving a reference

`resolve` applies RFC reference resolution, the way a browser resolves a link
against the page it is on. It answers nil and a reason when the reference
cannot be resolved:

```nupp
const uri = require("nupp.io.uri")

local page = assert(uri.new("https://example.com/docs/guide/index.html"))
local image, reason = page:resolve("../images/avatar.png")
assert(image, reason)
assert(image:path() == "/docs/images/avatar.png")
```

## Building from components

`uri.new` also accepts a `nupp.io.uri.Components` record. The components are
assembled into text and then parsed, so one grammar decides what is valid:

```nupp
const uri = require("nupp.io.uri")

local status = assert(uri.new({
    scheme = "https",
    userInfo = "reader:secret",
    host = "example.com",
    path = "/status",
    query = "full=1",
}))
assert(status:userInfo() == "reader:secret")
```

`scheme` is required and may not be empty. `userInfo`, `host`, `path`, `query`
and `fragment` are optional strings, and `port` is an optional integer from 0
through 65535. Every field is URI text rather than a filesystem name.

::: seealso
- [path.md](path.md) for filesystem names, where the platform's separators and
  `..` rules apply instead
- [standard-library.md](../../../concepts/standard-library.md) for how reaching
  a module selects the provider behind it
:::
