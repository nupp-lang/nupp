# Native Markdown

The documentation renderer uses unchanged upstream
[cmark-gfm 27d942c8b0a62d192f616e5bf3578f4b6a89e180](https://github.com/github/cmark-gfm/tree/27d942c8b0a62d192f616e5bf3578f4b6a89e180),
plus the separate Nupp C extension in `native/markdown/definition-list.c`.
That upstream revision includes the September 2026 autolink pointer-overflow
fix. Its generated version still says `0.29.0.gfm.13`; that version string
alone is insufficient to identify the source or extension ABI.

`scripts/toolchain.pins` pins the exact archive URL and SHA-256. The extension
is first-party source, revisioned with Nupp. Its public-hook ABI is
`definition-list-1`; the cache key additionally hashes every extension/header/
build source. Changing upstream requires rebuilding and retesting that exact
pair. No parser source or generated scanner is patched.

## Dialect and bytes

Only tables and colon definition lists are attached. Smart punctuation,
strikethrough, autolinks, task lists, tag filtering and footnotes stay disabled.
Raw HTML, comments and unsafe URL schemes retain the previous policy. Rendering
does not sanitize HTML. Table layout uses public AST accessors to retain the
old HTML bytes. Output is checked exactly against frozen pulldown-cmark 0.13.4
outputs, including attributes, code whitespace and block ownership.

The core checks guest types and lengths, performs Rust-compatible lossy UTF-8
decoding, and owns the foreign document through `own.Closeable`. The frozen VM
has a small direct C caller using the same provider, with Rust's existing lossy
decoder. Both cap original and decoded input at 8 MiB, HTML at 32 MiB and
cumulative native budget at 128 MiB. It covers C allocations and literal-search
work for the rare NUL/raw-HTML transport. Allocation/budget failures release the
operation's tracked allocations and raise an error. No guest callback,
scheduler or collector runs inside the provider.

cmark consumes NUL and an initial BOM before extension hooks. A bounded literal
byte transport preserves them without rewriting Markdown syntax. Its control
sequence and its URL encoding are absent from both the source and an initial
upstream rendering, including decoded entities. Whitespace in the marker keeps
NUL from becoming a bare link destination; angle destinations retain `%00`.
Upstream AST nodes identify raw HTML that needs opaque transport. Fence-language
info and raw HTML line endings are retained through the public AST API.
Restoration uses explicit lengths, including NUL in HTML output. The core
copies bounded C-string segments while its document owner remains live.

The parser, AST and per-call extension are freed before returning HTML. The
document owns the returned buffer until the matching `nupp_markdown_free`.
The private upstream registry has process lifetime; calls are serialized around
upstream global state. Fixed-size registry/extension construction uses the default
allocator; document parsing, ASTs, custom state, compatibility buffers and HTML
use the bounded allocator. There is no guarantee of recoverable system OOM
during upstream's fixed-size registry/extension construction itself.

## Build and packaging

```sh
./scripts/toolchain cmark
sh .github/scripts/test-markdown.sh
```

Provisioning builds C sources with CMake, without Cargo, rustc, rustup, cargo-c
or Python. The installed artifact includes matched headers, upstream static
archives, `nupp_markdown`, the upstream notice, `identity` and `files.sha256`.
The shared cross-worktree cache verifies source, toolchain, configuration,
extension sources and every installed header, library, executable and notice
before reuse. Each build's artifact
digests are recorded; they are not a cross-toolchain binary reproducibility claim.

Supported native SDK targets are macOS ARM64/x64, Linux ARM64/x64 and Windows
x64 MSVC. The frozen Windows VM also builds matching MinGW static archives.
The frozen VM links these C archives for the single-file compiler release.
Its existing `nupp.vm.markdown` builtin validates guest input, calls C, and
copies the returned bytes. The VM’s generic foreign loader needs a separate
shared library for non-system symbols, so that route would change the
standalone release.

The standalone core guest runner
provisions the pinned build when it selects a Markdown case. The core package
carries the shared module as a native sidecar. To test an explicit module, set
`NUPP_MARKDOWN_LIBRARY` to its path. Each module embeds its matching upstream
parser and table implementation.

```sh
cd tests/core/guests
NUPP_COMPILER_ROOT="$PWD/../../.." ../../../bin/nupp run run.lua markdown clihosts
```

The five-target C library workflow blocks Rust tools, checks cold/warm
provisioning, builds against installed headers, and runs the fixtures after
relocation. No browser Markdown consumer was found: the exposed service is the
native VM/internal documentation host. This native provider does not establish
browser parity.

The 30 definition examples and frozen focused outputs retain their source
license in `tests/fixtures/markdown/LICENSE-pulldown.txt`. The redistributed
upstream notice is `host/notices/cmark-gfm-LICENSE.txt`. Owned extension and
allocation/byte compatibility glue are counted as native C, not upstream code.
