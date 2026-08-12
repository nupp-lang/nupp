# Tasks

The build tool runs arbitrary build and maintenance commands that the manifest
names. `nupp task <name>` builds what that task says to build, then runs its
argv with your arguments appended, and `nupp tasks` lists what the project is
configured to do and prints any one entry's effective configuration.

```bash
nupp tasks                        # build targets, test, fixpoint, and tasks
nupp tasks docs-serve             # one entry's effective configuration
nupp task docs-serve              # run it
nupp task docs-serve --no-build   # arguments after the name reach the command
```

## Task configuration

A task is an entry in the manifest's `tasks` table, keyed by the name
`nupp task` takes:

```lua
return {
   include = { "src" },

   tasks = {
      ["docs-serve"] = {
         description = "Build the docs site and serve it",
         argv = { "node", "scripts/docs-serve.mjs" },
      },

      migrate = {
         description = "Apply pending schema migrations",
         build = "app",
         argv = { "luajit", "build/app/migrate.lua" },
         env = { DATABASE_URL = "postgres://localhost/app" },
      },
   },
}
```

| Key | Required | Means |
| --- | --- | --- |
| `argv` | yes | The command, as an argv array of strings |
| `description` | no | One line, shown by `nupp tasks` |
| `build` | no | A build target to build before the command runs |
| `env` | no | Environment variables, as string to string |

Any non-empty string is a name. One that is not a Lua identifier is written as
a key, as `["docs-serve"]` above. The four keys are the whole set, and a key
that is not among them is refused by name before anything runs, with the
nearest spelling when there is one:

```text
nupp: tasks.release has no key "descrption"; did you mean "description"?
```

## Writing a task in Nupp

A task's argv is any command, so a maintenance tool written in Nupp is a build
target plus a task that runs what the target produced. Write the tool:

```nupp
local channel = os.getenv("RELEASE_CHANNEL") or "dev"
print("stamping " .. channel .. " release")
for index = 1, select("#", ...) do
    print("argument: " .. tostring((select(index, ...))))
end
```

A `bundle` target compiles it to one file that `luajit` can run directly, and
the task builds that target before running it:

```lua
return {
   include = { "src" },

   build = {
      outDir = "build",
      default = "tools",
      targets = {
         tools = {
            kind = "bundle",
            description = "Build the maintenance tools",
            entries = { "tools.release" },
            output = "build/release.lua",
         },
      },
   },

   tasks = {
      release = {
         description = "Stamp a release archive",
         build = "tools",
         argv = { "luajit", "build/release.lua" },
         env = { RELEASE_CHANNEL = "stable" },
      },
   },
}
```

```text [nupp task release v1.2.0]
stamping stable release
argument: v1.2.0
```

A `modules` target works the same way with one more step: it writes
`build/tools/release.lua` beside the rest of the project's modules, so the
command needs the output directory on its path, as
`env = { LUA_PATH = "build/?.lua;;" }`. See
[project builds](build.md) for what each target kind produces.

## Building a target first

`build` names one of `build.targets`, which is built before the command runs.
A build that fails stops there: the command does not run and `nupp task` exits
1. Unlike `test`, which always builds because there is exactly one test command
and it answers for code that has to exist first, a task builds only when it
says to. Most tasks name no target at all, and a manifest with no `build`
section can still define and run them.

Naming a target also puts the project's rock tree on `LUA_PATH` and `LUA_CPATH`
for the command, since a task that built something usually wants to run it, and
those rocks live in a tree the project owns rather than a global one.

## Environment

`env` adds to what the command already inherits rather than replacing it. A
task that sets `CHANNEL` still sees `HOME`, `PATH`, and everything else the
shell that ran `nupp task` had:

```lua
envcheck = {
   argv = { "sh", "-c", "echo home=$HOME channel=$CHANNEL" },
   env = { CHANNEL = "beta" },
},
```

```text [nupp task envcheck]
home=/home/you channel=beta
```

Keys and values are strings, and a key has to be a plain identifier, since the
assignment is written in front of the command. Values are quoted for the
platform's shell, so spaces and quotes in a value are safe.

## Arguments and exit status

Arguments after the task name belong to the command, so `nupp task` does not
read them. The consequences:

- `-h` and `--help` are answered only before the name. After it they are the
  command's, and `nupp task -- --help` names a task called `--help`.
- The exit status is the command's own. A task whose command exits 7 makes
  `nupp task` exit 7.
- A name no task matches exits 1, and says to run `nupp tasks` for the list.

The command runs with the project root as its working directory, whatever
directory you invoked `nupp task` from.

## Listing and inspecting

`nupp tasks` covers everything the manifest configured, not just the `tasks`
table: each build target, with the default one marked, the configured test
command, the self-host action `nupp fixpoint` runs, and each named task.

```text [nupp tasks]
release - Stamp a release archive
tools (default) - Build the maintenance tools
```

`nupp tasks <name>` prints that entry's effective configuration, filled in with
the defaults a build would actually use, and prints only the fields the entry
has, so the shape of the output says what kind of entry it is:

```text [nupp tasks release]
Name: release
Default: no
Description: Stamp a release archive
Kind: task
Category: task
Command: nupp task release
Build target: tools
Arguments:
  - luajit
  - build/release.lua
Environment:
  - RELEASE_CHANNEL=stable
```

Both forms take `--json`, and `nupp tasks --schema` prints the shape they
write. A task named the same as a build target is listed as `command:<name>`,
because the build target holds the plain name; `nupp task <name>` still runs
the task, since it looks only at the `tasks` table.

::: warning
`nupp tasks` reports `nupp: build is not configured` in a project whose
manifest has no `build` section, because the list it prints is mostly build
targets. `nupp task <name>` has no such requirement and runs the task.
:::

## Limits

`nupp task` runs one argv and returns its exit code, the same as `nupp test`
does. It is not a process supervisor: a task that starts a server runs in the
foreground until it is stopped, exactly as running that command directly would.

Tasks do not depend on other tasks. The one ordering a task can express is
`build`, and anything more is the command's own business, which is what a shell
or a script written in Nupp is for.

## Next

- [build.md](build.md): the targets a task's `build` key names, and what each
  kind writes.
- [testing.md](testing.md): `test`, which is the same shape fixed to one
  purpose.
