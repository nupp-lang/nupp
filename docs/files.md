`nupp.io.files` reads what the filesystem knows about a name: whether it
resolves, what it refers to, what a directory contains, and where the platform
keeps a user's folders. It also moves and removes names.

```nupp:playground
local files = nupp.io.files
for _, entry in ipairs(assert(files.list("src"))) do
    print(entry.kind, entry.name)
end
```

A file's bytes move through the same `Reader` and `Writer` contracts a buffer
uses, so a parser written against [byte I/O](io.md) works over a file without
knowing one is there.

A path argument is a string or a [`Path`](path-uri.md#paths); a path result is a
string. Operations that fail because of the environment answer `nil, reason` or
`false, reason`; a malformed argument raises at the call site.

## Querying a name

```nupp
local info, reason = files.info("nupp.lua")
assert(info, reason)
assert(info.kind == "file")
print(info.size, info.modified, info.readOnly)
```

`info` follows symbolic links, so it describes what a name refers to rather than
the name itself. `size` is a byte count, `modified` is seconds since the Unix
epoch with whatever fractional part the platform records, and `readOnly` is the
platform's write refusal rather than a permission model.

`exists`, `isFile` and `isDirectory` answer the same question without the record
and without a reason. A missing path is `false` rather than an error:

```nupp
if files.isDirectory(candidate) then
    return files.list(candidate)
end
```

`isSymlink` is the one query that does not follow, because following is what
would hide the answer:

```nupp
assert(files.createSymlink("target.txt", "alias"))
assert(files.isSymlink("alias"))
assert(files.isFile("alias"))
assert(files.readLink("alias") == "target.txt")
```

`createSymlink` takes an optional third argument, `"file"` or `"directory"`.
Only Windows distinguishes the two; elsewhere it is ignored.

## Listing a directory

```nupp
local entries, reason = files.list("src/nupp")
assert(entries, reason)
```

Each entry has a `name` without any directory part and a `kind` describing the
entry *itself*, so a link inside a listing reads as `symlink` rather than as
what it points at. The order is the platform's, which is not sorted.

The kind comes from the directory itself rather than a second query per name, so
listing a large directory costs one call.

## Matching paths

`glob` expands a pattern into sorted path strings. `*` and `?` stay within one
path component, `[abc]` and `[!abc]` select characters, and `**` crosses
directory boundaries. No matches is an empty list; an invalid pattern or a
filesystem error answers a reason.

```nupp
for _, path in ipairs(assert(files.glob("src/**/*.nupp"))) do
    print(path)
end
```

## Creating, moving and removing

```nupp
assert(files.createDirectory("out/lib/native"))
assert(files.rename("out/report.tmp", "out/report.json"))
assert(files.remove("out/stale", true))
```

`createDirectory` creates every missing parent, and an existing directory
succeeds, which is what a caller building a tree wants rather than a race with
its own earlier call. `rename` replaces an existing destination. `remove` takes
a file, a symbolic link, or an empty directory; the second argument removes a
directory's contents with it, and without it a populated directory answers a
reason.

`setReadOnly` sets or clears the write refusal that `info` reports.

## Temporary names

```nupp
local scratch, reason = files.createTemporaryDirectory({prefix = "build-"})
assert(scratch, reason)
```

The file or directory is *created*, not proposed, so no second caller can take
the name between the answer and the use. `directory` selects where, defaulting
to the platform's temporary directory; `prefix` and `suffix` bracket the
generated part, which is what puts an extension on a temporary file.

A temporary is an owner: closing it removes what it created, and the checker
runs that cleanup at the end of the scope whether the block falls through,
returns early, or raises.

```nupp
do
    local scratch = assert(files.createTemporaryFile({suffix = ".json"}))
    assert(files.write(scratch:toString(), encoded))
    assert(scratch:persist("out/report.json"))
end
```

`persist` moves it somewhere permanent and discharges the obligation, so the
close that follows does nothing. That pair is the reason to make one: write to a
name nobody else can take, then put it where it belongs, so a reader never sees
a half-written file under the final name.

## Reading and writing a whole file

```nupp
local text, reason = files.read("nupp.lua")
assert(text, reason)
assert(files.write("out/report.json", encoded))
```

`append` adds to the end and creates a missing file. `copy` duplicates one path
over another. `writeAtomic` writes through a temporary beside the destination
and renames over it, so an interrupted write leaves the destination as it was
rather than half replaced. A failed write removes the temporary rather than
leaving it behind.

A NUL byte is content, not a terminator, in every direction.

```nupp
for line in assert(files.lines("access.log")) do
    print(line)
end
```

`lines` closes the file when it reaches the end. A trailing carriage return is
removed, so a file written on either platform reads the same. Abandoning the
iterator early leaves the file open until it is collected; open it yourself when
you mean to stop.

## Reading and writing through a cursor

`open` hands over a `File` and the obligation to close it:

```nupp
do
    local file = assert(files.open("image.png"))
    local reader = file:newReader()
    print(reader:read(8))
end
```

The reader and writer satisfy `nupp.io.Reader` and `nupp.io.Writer`, so `read`,
`readInto`, `transferTo`, `write`, `writeFrom`, `writeView` and `flush` mean
what they mean over a buffer. `readInto` lands bytes in the destination
buffer's own storage rather than in a string on the way there, and `transferTo`
streams a file of any size through a fixed window:

```nupp
do
    local source = assert(files.open("input.bin"))
    local sink = assert(files.open("output.bin", "w"))
    print(source:newReader():transferTo(sink:newWriter()))
end
```

`mode` is `r`, `w`, `a`, or the update modes `r+`, `w+` and `a+`, matching C and
Lua. `seek(offset, origin)` moves the cursor, with `origin` one of `set`,
`current` or `end`; `position` and `size` answer where it is and how long the
file is. A reader or writer over a closed file answers a reason rather than
raising.

## Platform directories

```nupp
print(assert(files.currentDirectory()))
print(assert(files.userFolder("documents")))
```

`userFolder` takes `home`, `documents`, `downloads`, `desktop`, `pictures`,
`music` or `videos`. It resolves from the environment: the `XDG_*` variables
where they are set, and the platform's conventional names under the home
directory otherwise. A desktop that records its folders somewhere else is not
consulted, and a folder that does not exist answers a reason rather than a path
that is not there.

## Waiting

A whole-file `read`, `write`, `append`, `writeAtomic` or `copy` settles on a
worker thread rather than on yours, and the call waits for it by suspending.
What that means depends on where the call runs, and on nothing the call says:

| Where it runs | What waiting means |
| --- | --- |
| an ordinary program | it sleeps, driving the readiness pump |
| under an installed handler | it parks, and the handler resumes it |
| inside a `nosuspend` region | NUPP2701, at compile time |

One call site covers all three. A library that reads a file works inside a game
frame and inside a command-line program without knowing which it is in, and a
transfer that settled before it was observed never reaches any of this.

The immediate operations are declared `nosuspend`, so a region that forbids
waiting still permits asking what a path is, listing a directory, or renaming
one:

```nupp
nosuspend do
    if files.isDirectory(candidate) then
        print(#assert(files.list(candidate)))
    end
    print(files.read(candidate)) -- NUPP2701: `read` may suspend
end
```

## Cost

Reaching `nupp.io.files` selects a Rust provider, built with only this feature
and loaded on first use. A program that never reaches it links nothing and
initializes nothing, which is the rule for every
[standard facility](stdlib.md#availability-detection-and-lazy-loading). A target
that uses it also carries the suspension runtime, because that is what answers
the wait above.

The lane those workers run is bounded three ways: how many transfers may be
live, how many bytes they may hold between them, and how large one may be. Past
any of the three a submission answers a reason rather than queueing, because a
queue that grows with its callers eventually takes the process with it.
`pendingTransfers` answers what the lane is holding.

Metadata, listings and cursor reads through an open `File` do not use the lane.
Scheduling a transfer costs more than those cost to run.

## Diagnostics

- **NUPP2701**: a non-suspending region can reach suspension, which a
  filesystem call inside `nosuspend` reports at compile time.

## Next

- [docs/io.md](io.md): the buffer, reader and writer contracts a file
  implements.
- [docs/ownership.md](ownership.md): what an owner is, and when its cleanup
  runs.
- [docs/path-uri.md](path-uri.md): building and normalizing the names this
  namespace takes.
