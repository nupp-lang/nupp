# Recorded editor sessions

Each file here is one session an editor could have produced: a project, the
documents that were open, and the succession of buffer states one of them
passed through as somebody typed into it — including the states that do not
parse, which is most of them while a line is being written.

`tests/lsptest.lua` replays each recording against a real server and compares
the end of it against a second server that was handed the final text and
nothing else. That comparison is the whole point: a burst of edits has to leave
the session in the state one edit would have, or the editor is showing
diagnostics and definitions that depend on how fast the user types.

A recording returns:

    files     path -> text, written to disk before the session starts
    open      paths opened, in order, with their text as written
    document  the one being typed into
    states    its successive full texts; the first is what it was opened with
    probes    positions asked for definition and hover at the end

Add one by dropping a `.lua` file in this directory. It becomes its own test
case, named after the file.
