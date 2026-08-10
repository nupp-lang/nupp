# Associated types

An interface may state a type it does not name. Whatever takes the contract
names it, and the name is reached through the value that answered it.

```nupp
local interface Reader
    associated type Item

    function read(self): self.Item?
end

local record Lines is Reader
    associated type Item = string

    handle: LuaFile

    function read(self): string?
        return self.handle:read("*l")
    end
end
```

`Lines.Item` is `string`. A function generic over readers reads it back through
the type parameter:

```nupp
local function collect<T is Reader>(source: T): {T.Item}
```

## Why not a type parameter

`Reader<T>` says the same thing until you try to use it. A parameter is an input
the caller chooses, so nothing stops one declaration from taking `Reader<string>`
and `Reader<integer>` both, and `collect(source)` then has nothing to infer `T`
from. An associated type is an output the implementor chooses, so it is a
function of the argument and inference resolves it.

Parameters also propagate. Every function that touches a reader carries the
parameter whether or not it mentions the element type, and each layer adds one.
An associated type stays where it was declared.

The rule is which side chooses. When the caller chooses, write a parameter.

## It is not a nested type alias

A declaration body may also hold a plain `type` alias, and the two are different
members:

```nupp
local interface Shape
    type Unit = number      -- a static alias
    associated type Scale   -- a requirement

    size: Unit
end
```

`Unit` is lexically scoped in the body, reachable from outside as `Shape.Unit`,
and **not inherited** — a declaration taking `Shape` does not get it and cannot
name it. `Scale` is the opposite on every count: inherited, answered per
implementor, and reached through whatever answered it.

That is why they are spelled differently. Sharing one word would have made the
meaning of every existing nested alias depend on whether its declaration was
ever inherited.

## Stating one

`associated type` is contextual, and `type` has to follow it on the same line,
so a field named `associated` is still a field.

```nupp
local interface Codec
    associated type Encoded              -- unbounded
    associated type Decoded is Named     -- bounded
    associated type Error = string       -- with a default
end
```

A bound says what may answer, and an answer that does not fit it is
**NUPP2116**. A default answers the requirement on the interface itself: an
implementor that says nothing inherits it, and one that says something replaces
it. No `@override` — a type member has no body to replace.

## Answering one

```nupp
local record JSON is Codec
    associated type Encoded = string
    associated type Decoded = any
end
```

`Error` is not written, so `JSON.Error` is the inherited `string`.

Leaving a requirement unanswered is **NUPP2127**. Answering a name no contract
declares is **NUPP2131**, and so is stating a requirement anywhere but an
interface — nothing inherits from a record, so nobody could answer it. When the
name is meant to be private, a plain `type` alias already is.

The binding side is marked as well as the declaring side, which is what
`@override` does for a member replacing an inherited default: a reader of the
record sees that the member answers a contract without going to read the
interface.

## Reaching one

Through a concrete declaration, by path:

```nupp
local text: Lines.Item = "a line"
```

Through a type parameter, in any type position:

```nupp
local function collect<T is Reader>(source: T): {T.Item}
```

Through the receiver, inside a body:

```nupp
function read(self): self.Item?
```

Inside an interface body the name is never bare. `Item` alone does not resolve
there, because what it stands for varies by implementor; `self.Item` is
required. In a declaration that answered it, the bare name does resolve, because
answering it makes it an alias like any other.

## What it costs at run time

Nothing. An associated type is erased exactly as a type parameter is, and an
interface that adds only associated types still emits nothing. There is no
reflection over one, and a `matches` refinement cannot test one — an interface
carrying both an unanswered requirement and a refinement is **NUPP2129**,
because the refinement would claim to identify values it cannot distinguish.
