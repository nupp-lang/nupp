# Tasks

```bash
nupp tasks                  # list build targets, test, self-host, and tasks
nupp tasks docs-serve       # one task's effective configuration
nupp task docs-serve        # run it
nupp task docs-serve --no-build   # extra arguments reach the task's command
```

`nupp tasks` (plural) lists what a project is configured to do, covering build
targets, the configured test command, self-hosting and named tasks, and inspects
any one of them by name. `nupp task` (singular) is the one that runs a named
task: builds `tasks.<name>.build` first if it names one, then execs
`tasks.<name>.argv` with anything after `<name>` appended.

## Configuring one

```lua
return {
   include = { "src" },

   tasks = {
      ["docs-serve"] = {
         description = "Build the docs site and serve it",
         argv = { "node", "scripts/docs-serve.mjs" },
      },
   },
}
```

```
 Key          Required  Means
 ───────────  ────────  ──────────────────────────────────────────
 argv         yes       The command, as an argv array
 description  no        Shown by `nupp tasks`
 build        no        A build target to build first
 env          no        Environment variables, as string to string
```

Unlike `test`, which always builds because there is exactly one test command and
it answers for code that has to exist first, a task only builds when `build`
names a target. Most won't: `argv` can be anything that runs, and building is
one thing a task might need on the way, not something every task means.

## Why tasks exist

`test` and `selfHost` are two fixed-purpose instances of the same shape: build
something, then run a command. `tasks` generalizes that to any number of named
ones: the commands a project runs by hand often enough to want a name for,
rather than a comment saying what to type. A dev server that serves the docs
site and the playground together
([`scripts/docs-serve.mjs`](https://github.com/nupp-lang/nupp/blob/main/scripts/docs-serve.mjs))
is this repository's own `tasks.docs-serve`.

It is not a general process supervisor: `nupp task` runs one argv and returns
its exit code, the same as `nupp test` does. A task that starts a server
runs in the foreground until it's stopped (Ctrl+C), same as running that
command directly would.
