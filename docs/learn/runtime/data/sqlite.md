---
order: 195
title: SQLite databases
---

# SQLite databases

`sqlite` opens SQLite databases, over the pinned SQLite amalgamation
(3.54.1). It is bound with checked FFI calls on the native core, with no C of
Nupp's own between, and it is a builtin: a program that never reaches it
carries none of it ([builtin libraries](../../projects/builtins.md)).

```nupp:fragment
local db = sqlite.open("library.db", {journal = "wal"})
db:exec("create table if not exists shows (id integer primary key, title text not null)")
db:run("insert into shows (title) values (?)", "Severance")
for row in db:rows("select id, title from shows order by id") do
    print(row.id, row.title)
end
```

Every call runs on the calling thread and blocks it while SQLite works, as it
does in any embedding. A connection is not shared across threads.

## Connections

`sqlite.open(path, options)` opens a [](sqlite.Connection), creating the file
unless told not to; `:memory:` opens a database in memory. The connection
closes at the end of its scope, or with `close()`.

| Option | Default | Meaning |
| --- | --- | --- |
| `readonly` | `false` | Open it read-only. |
| `create` | `true` | Create the file when it is missing. |
| `journal` | the file's | `"delete"`, `"wal"` or `"memory"`. |
| `busytimeout` | `5000` | Milliseconds a call waits for another connection's lock before failing with `sqlite.BUSY`. |
| `foreignkeys` | `true` | Enforce foreign keys. |

`foreignkeys` is on by default, which SQLite's own default is not: it is what
a new program expects. A connection also runs in SQLite's defensive mode,
which refuses SQL able to corrupt the file, and extension loading is not
compiled in.

| Method | Does |
| --- | --- |
| `exec(sql)` | Runs every statement in `sql`, ignoring rows. |
| `run(sql, ...)` | Runs one statement and answers how many rows it changed. |
| `rows(sql, ...)` | Iterates one statement's rows, as tables keyed by column name. |
| `first(sql, ...)` | The first row, or nil. |
| `rowsas(binding, sql, ...)`, `firstas(binding, sql, ...)` | The same, decoded into records. |
| `prepare(sql)` | A [](sqlite.Statement). |
| `transaction(body, mode)` | Runs `body` in a transaction. |
| `changes()`, `totalchanges()`, `lastrowid()` | SQLite's counters. |

The `...` of `run`, `rows`, `first` and their record forms bind the
statement's parameters in order, and there must be as many values as the
statement takes. `run`, `rows`, `first` and `prepare` take one statement;
`exec` takes several.

A loop over `rows` holds the statement and finalizes it when the loop ends,
whether it runs out, leaves by `break` or is left by a raised error. A row with
two columns of one name is refused, with a hint to rename one with `AS`.

## Statements

`prepare(sql)` answers a statement, finalized at the end of its scope. It
borrows the connection, so the checker refuses a statement that would outlive
it.

```nupp:fragment
local db = sqlite.open(":memory:")
local statement = db:prepare("select :title as title, typeof(:title) as kind")
statement:bind("title", "Andor")
while statement:step() do
    print(statement:column(1), statement:columntype(1))
end
statement:reset()
```

`bind(at, value)` takes a parameter's index, from one as SQLite numbers them,
or its name, with or without its prefix (`:title`, `@title` and `$title`).
`bindall(...)` binds every parameter in order. `step()` answers true while a
row is ready. `column(i)`, `columntype(i)`, `columns()` and `row()` read the
current row, numbering columns from one; `reset()` and `clearbindings()` are
SQLite's.

## Values

Values cross exactly, with no lossy conversion either way.

| SQLite | Nupp |
| --- | --- |
| NULL | `nil` |
| INTEGER | a 64-bit integer |
| REAL | a float |
| TEXT | a string of its exact bytes |
| BLOB | a string of its exact bytes |

`columntype(i)` tells TEXT from BLOB: `"integer"`, `"float"`, `"text"`,
`"blob"` or `"null"`. A string binds as TEXT and `sqlite.blob(s)` as BLOB.
A boolean binds as 0 or 1, and a float stays REAL even when it is integral.
Binding any other value raises before SQLite is called. Text is not checked
for UTF-8, since SQLite keeps bytes, and every value read is copied out of
SQLite's memory before it is answered.

## Errors

A call SQLite fails raises a [](sqlite.Error):

| Field | Holds |
| --- | --- |
| `code` | The extended result code, such as 2067. |
| `primary` | `code & 0xff`, to compare with `sqlite.BUSY`, `sqlite.LOCKED`, `sqlite.CONSTRAINT` and the rest. |
| `name` | Its symbolic name, such as `SQLITE_CONSTRAINT_UNIQUE`. |
| `message` | SQLite's message. |
| `sql` | The statement's text. |
| `offset` | The byte offset of a syntax error in `sql`, from zero, when SQLite reports one. |

A busy or locked database is told apart by `primary`, without reading the
message. Misuse found before SQLite is called, such as a value no parameter
binds, a parameter the statement does not have, or a closed connection,
raises an ordinary error.

## Transactions

`transaction(body, mode)` begins a transaction, `"deferred"` by default or
`"immediate"` or `"exclusive"`, and calls `body` with the connection. It
commits when `body` returns, answering what it returned, and rolls back when it
raises, raising the same error again. A rollback that fails too is recorded in
the error's `suppressed` list. A transaction begun inside `body` nests in a
savepoint, at any depth.

```nupp:fragment
local db = sqlite.open("library.db")
db:transaction(function(borrows connection: sqlite.Connection): nil
    local _ = connection:run("update shows set title = ? where id = ?", "Andor", 2)
end, "immediate")
```

`body` takes the connection borrowed, so the checker refuses a suspension
inside it while that borrow is live. Until the transaction ends, another
coroutine that uses the connection, such as one sharing it through
`own.manage`, is refused rather than let into the middle of it.

## Records

`rowsas(binding, sql, ...)` and `firstas` decode each row through a
[serde binding](serde.md), one member per column, by the fields' declared
names. A name `serde.FieldOptions` gives a field is a codec's wire name and
does not apply here; rename the column with `AS` instead. A column the query
leaves out takes the field's default, and one with no default is refused; an
extra column follows the binding's `unknownmembers`. A storage class the field
cannot take is refused, naming the column.

```nupp:fragment
local record Show
    id: integer
    title: string
end
local db = sqlite.open("library.db")
local shows = serde.binding(Show)
for show in db:rowsas(shows, "select id, title from shows") do
    print(show.title)
end
local insert = db:prepare("insert into shows (id, title) values (:id, :title)")
insert:bindrecord(shows, Show(id = 3, title = "Pluribus"))
insert:step()
```

`bindrecord(binding, value)` binds each named parameter from the member declared
with that name, and refuses a parameter no member is named for.

## Hosts

`sqlite` is provided on the native core: macOS, Linux and Windows on ARM64.
A target whose host cannot provide it, such as the browser, fails to build a
program that reaches it.
