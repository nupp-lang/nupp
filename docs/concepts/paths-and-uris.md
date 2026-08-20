# Paths and URIs

`nupp.io.path` and `nupp.io.uri` are modules of their own beside `nupp.io`, each
answering an immutable value object. Their public API contains only Nupp values;
parsing and normalization are delegated to a feature-gated Rust provider.
Selecting either builds the shared provider once with only the required Cargo
features -- and a program that reaches neither carries neither, which is why they
are modules rather than members of `nupp.io`.

```nupp
const {Path} = require("nupp.io.path")

local source = new Path("src", "main.nupp")
assert(source:extension() == "nupp")
```

## Paths

A path is platform-native UTF-8 text, and `new Path(...)` joins its components
using the current platform's rules. `path.currentDirectory` and
`path.separator` are functions on the module beside it, because neither builds
a path from components:

```nupp:playground
const path = require("nupp.io.path")
const {Path} = path

local source = (new Path("src", "app", "..", "main.nupp")):normalize()
assert(source:toString() == "src" .. path.separator() .. "main.nupp")
local name, stem, extension = source:fileName(), source:stem(), source:extension()
assert(name == "main.nupp")
assert(stem == "main")
assert(extension == "nupp")
```

`join` appends components. `normalize` removes lexical `.` and `..` components
without touching the filesystem. `absolute` resolves against the current working
directory; `resolve(parts...)` makes absolute, appends parts and normalizes.
`canonicalize` asks the filesystem for the real path and therefore can fail.
`relativeTo(base)` computes a relative path when both values share a coordinate
system. Fallible operations return `nil, reason`.

`parent` returns another Path or nil. `fileName`, `stem`, and `extension` return
component strings or nil. `withFileName` and `withExtension` replace one
component and reject separators in the replacement. `isAbsolute` and
`isRelative` classify without accessing the filesystem.

```nupp
local current, reason = nupp.io.path.currentDirectory()
assert(current, reason)
local log = current:join("var", "app.log"):withExtension("jsonl")
```

- `new Path(first, parts...)`: `nupp.io.path.Path`.
- `path.currentDirectory()`: `nupp.io.path.Path?, reason?`.
- `path.separator()`: platform separator string.
- `toString()`, `tostring(path)`: native UTF-8 path string.
- `join(parts...)`, `normalize()`: `nupp.io.path.Path`.
- `absolute()`, `resolve(parts...)`, `canonicalize()`: `nupp.io.path.Path?, reason?`.
- `relativeTo(base)`: `nupp.io.path.Path?, reason?`.
- `parent()`: `nupp.io.path.Path?`.
- `fileName()`, `stem()`, `extension()`: component `string?`.
- `withFileName(name)`, `withExtension(extension)`: `nupp.io.path.Path`.
- `isAbsolute()`, `isRelative()`: `boolean`.

Path equality compares its native text. `tostring(path)` and `path:toString()`
are equivalent.

## URIs

`nupp.io.uri.new` parses and normalizes one absolute URI. It returns
`nil, reason` for malformed input. `nupp.io.uri.validate` checks without
retaining an object; `nupp.io.uri.isURI` distinguishes URI objects from strings
and records.

```nupp
local endpoint, reason = nupp.io.uri.new("https://user:pass@example.com:8443/api?q=1#top")
assert(endpoint, reason)
assert(endpoint:scheme() == "https")
assert(endpoint:host() == "example.com")
assert(endpoint:port() == 8443)
assert(endpoint:path() == "/api")
```

The accessors are `scheme`, `authority`, `username`, `password`, `userInfo`,
`host`, `port`, `path`, `query`, and `fragment`. Optional components return nil.
`toString` returns the normalized complete URI.

Every `with...` method returns a new URI and leaves the original unchanged:

```nupp
local production = endpoint:withUserInfo(nil):withHost("api.example.com"):withPort(nil):withQuery(nil):withFragment(nil)
local users = production:concatPath("users")
local avatar, resolveReason = users:resolve("../images/avatar.png")
assert(avatar, resolveReason)
```

A malformed replacement passed to `withScheme`, `withUserInfo`, `withHost`,
`withPort`, `withPath`, `withQuery`, `withFragment`, `concatPath`, or
`withEndpoint` raises at the call site. Use `URI.new`, `URI.validate`, and
`resolve`
when the text came from an untrusted source and must be handled as a fallible
value. Ports must be integers from 0 through 65535. Supplying a component equal
to its current normalized value returns the receiver itself.

`concatPath` joins path text without interpreting it as a reference. `resolve`
applies RFC URL-reference resolution. `withEndpoint(endpoint)` replaces scheme
and authority with another URI while retaining the receiver's path, query and
fragment; it is useful when a request URI must be rerouted through a configured
service endpoint.

A component record can be passed instead of text:

```nupp
local uri = assert(
    nupp.io.uri.new({
        scheme = "https",
        userInfo = "reader:secret",
        host = "example.com",
        path = "/status",
        query = "full=1",
    })
)
```

The input record type is `nupp.io.uri.Components`. Components are URI text, not
filesystem paths. Use
[Path](#paths) for filesystem semantics and URI for network/resource identity.

- `uri.new(textOrComponents)`: `nupp.io.uri.URI?, reason?`.
- `URI.validate(text)`: `boolean, reason?`.
- `URI.isURI(value)`: `boolean`.
- `toString()`, `tostring(uri)`: normalized absolute URI string.
- `scheme()`, `username()`, `path()`: required component string.
- `authority()`, `userInfo()`, `password()`, `host()`: optional component
  string.
- `port()`: `integer?`.
- `query()`, `fragment()`: optional component string.
- `withScheme`, `withUserInfo`, `withHost`, `withPort`: modified `nupp.io.uri.URI`.
- `withPath`, `withQuery`, `withFragment`, `concatPath`: modified `nupp.io.uri.URI`.
- `withEndpoint(endpoint)`: endpoint-rerouted `nupp.io.uri.URI`.
- `resolve(reference)`: `nupp.io.uri.URI?, reason?`.

URI equality compares normalized values, so case normalization in a host or
scheme does not make two otherwise identical URIs unequal.
