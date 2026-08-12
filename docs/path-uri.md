# Paths and URIs

`nupp.io.Path` and `nupp.io.URI` are immutable value objects, nested under
`nupp.io` alongside the other byte and filesystem facilities. Their public API
contains only Nupp values; parsing and normalization are delegated to a
feature-gated Rust provider. Selecting either builds the shared provider once
with only the required Cargo features.

## Paths

A path is platform-native UTF-8 text. Constructing joins components using the
current platform's rules:

```nupp
local source = nupp.io.Path.new("src", "app", "..", "main.nupp"):normalize()
assert(source:toString() == "src" .. nupp.io.Path.separator() .. "main.nupp")
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
local current, reason = nupp.io.Path.currentDirectory()
assert(current, reason)
local log = current:join("var", "app.log"):withExtension("jsonl")
```

- `Path.new(first, parts...)`: `nupp.io.Path`.
- `Path.currentDirectory()`: `nupp.io.Path?, reason?`.
- `Path.separator()`: platform separator string.
- `toString()`, `tostring(path)`: native UTF-8 path string.
- `join(parts...)`, `normalize()`: `nupp.io.Path`.
- `absolute()`, `resolve(parts...)`, `canonicalize()`: `nupp.io.Path?, reason?`.
- `relativeTo(base)`: `nupp.io.Path?, reason?`.
- `parent()`: `nupp.io.Path?`.
- `fileName()`, `stem()`, `extension()`: component `string?`.
- `withFileName(name)`, `withExtension(extension)`: `nupp.io.Path`.
- `isAbsolute()`, `isRelative()`: `boolean`.

Path equality compares its native text. `tostring(path)` and `path:toString()`
are equivalent.

## URIs

`nupp.io.URI.new` parses and normalizes one absolute URI. It returns `nil,
reason` for malformed input. `nupp.io.URI.validate` checks without retaining an
object; `nupp.io.URI.isURI` distinguishes URI objects from strings and records.

```nupp
local endpoint, reason = nupp.io.URI.new("https://user:pass@example.com:8443/api?q=1#top")
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

```nupp:static
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

```nupp:static
local uri = assert(
    nupp.io.URI.new({
        scheme = "https",
        userInfo = "reader:secret",
        host = "example.com",
        path = "/status",
        query = "full=1",
    })
)
```

The input record type is `nupp.io.URI.Components`. Components are URI text, not
filesystem paths. Use
[Path](#paths) for filesystem semantics and URI for network/resource identity.

- `URI.new(textOrComponents)`: `nupp.io.URI?, reason?`.
- `URI.validate(text)`: `boolean, reason?`.
- `URI.isURI(value)`: `boolean`.
- `toString()`, `tostring(uri)`: normalized absolute URI string.
- `scheme()`, `username()`, `path()`: required component string.
- `authority()`, `userInfo()`, `password()`, `host()`: optional component
  string.
- `port()`: `integer?`.
- `query()`, `fragment()`: optional component string.
- `withScheme`, `withUserInfo`, `withHost`, `withPort`: modified `nupp.io.URI`.
- `withPath`, `withQuery`, `withFragment`, `concatPath`: modified `nupp.io.URI`.
- `withEndpoint(endpoint)`: endpoint-rerouted `nupp.io.URI`.
- `resolve(reference)`: `nupp.io.URI?, reason?`.

URI equality compares normalized values, so case normalization in a host or
scheme does not make two otherwise identical URIs unequal.
