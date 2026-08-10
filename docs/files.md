# Filesystem metadata and directories

`nupp.io.files` reads what the filesystem knows about a name: whether it
resolves, what it refers to, what a directory contains, and where the platform
keeps a user's folders. It also moves and removes names.

```nupp
local files = nupp.io.files
for _, entry in ipairs(assert(files.list("src"))) do
    print(entry.kind, entry.name)
end
```

Every operation here answers before a transfer could have started. Reading and
writing a file's bytes is a separate layer, and until it lands the byte
vocabulary on [byte I/O](io.md) works over memory only.

A path argument is a string or a [`Path`](path-uri.md#paths); a path result is a
string. Operations that fail because of the environment answer `nil, reason` or
`false, reason`; a malformed argument raises at the call site.

## Asking what a name is

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
and without a reason — a missing path is `false`, not an error:

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

## Creating, moving and removing

```nupp
assert(files.createDirectory("out/lib/native"))
assert(files.rename("out/report.tmp", "out/report.json"))
assert(files.remove("out/stale", true))
```

`createDirectory` creates every missing parent, and an existing directory
succeeds — a caller building a tree wants that rather than a race with its own
earlier call. `rename` replaces an existing destination. `remove` takes a file, a
symbolic link, or an empty directory; the second argument removes a directory's
contents with it, and without it a populated directory answers a reason.

`setReadOnly` sets or clears the write refusal that `info` reports.

## Temporary names

```nupp
local scratch, reason = files.createTemporaryDirectory({prefix = "build-"})
assert(scratch, reason)
```

The file or directory is *created*, not proposed, so no second caller can take
the name between the answer and the use. `directory` selects where, defaulting to
the platform's temporary directory; `prefix` and `suffix` bracket the generated
part, which is what puts an extension on a temporary file.

Nothing removes these for you. Pair one with `files.remove` — this is the
operation an owner and a `with` scope will cover once files own resources.

## Where the platform keeps things

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

## What this costs

Reaching `nupp.io.files` selects a Rust provider, built with only this feature
and loaded on first use. A program that never reaches it links nothing and
initializes nothing, which is the rule for every
[standard facility](stdlib.md#availability-detection-and-lazy-loading).

## Next

- [docs/io.md](io.md) — the buffer, reader and writer contracts a file layer
  will implement.
- [docs/path-uri.md](path-uri.md) — building and normalizing the names this
  namespace takes.
