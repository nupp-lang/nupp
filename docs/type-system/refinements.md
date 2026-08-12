# Refinements

An interface may carry a `satisfies` declaration naming the runtime test that
decides whether a value is one of these. `x is T` compiles to that test, so an
interface can answer `is` for a value this program never built.

```nupp
local m = {}

interface m.Shape
    kind: string
end

interface m.Circle is m.Shape
    kind: string
    radius: number

    satisfies |self| -> self.kind == "circle"
end

function m.area(s: m.Shape): number
    if s is m.Circle then
        return 3 * s.radius * s.radius
    end
    return 0
end

return m
```

`s is m.Circle` becomes `type(s) == "table" and s.kind == "circle"`.

## Refinements are functions of the value

It is written as one, in either spelling a function takes anywhere else: the
arrow form above, or a body whose single `return` says the same thing.

```nupp
local m = {}

interface m.Circle
    kind: string
    radius: number

    satisfies(self): boolean
        return self.kind == "circle"
    end
end

return m
```

## Only an interface carries one

A record is identified by the metatable `new` stamps and a struct by its ctype,
so both already answer `is` exactly. A refinement beside either would be a
second answer to a settled question, and which answer `is R` gave would depend
on whether a body happened to carry one.

An interface has no runtime table at all, so this is the only identity it can
have. That is also what makes it useful: a table off a JSON decoder, or anything
an untyped library returned, never received a metatable, so nothing else could
identify it.

## Tests read self and nothing else

It runs wherever `is` is written, so it reads the declaration's own fields
through `self`: comparisons against literals, `type()` tests, and `and`, `or`
and `not`. A call, arithmetic, or a name from outside the subject is
**NUPP2122**.

So is a refinement that always answers the same way. Always true identifies
every value and always false leaves the type uninhabited, and neither is a test.

A subject that is not a plain name is evaluated once and handed to the test,
since a refinement may read it more than once. Reaching through a field guards
the step before it with `?.`, because the test runs against values that are not
of the type yet, so `satisfies |self| -> self.a.b == "x"` compiles to
`s.a?.b == "x"`.

## Declarations are held to what they declare

`record C is Shape` is a claim the checker proves, and `Shape`'s refinement is
what `is Shape` runs. Fields that provably fail it are **NUPP2122**, because the
alternative is a value the checker calls a `Shape` and `is` calls otherwise.

## Diagnostics

- **NUPP2122**: a refinement cannot be enforced. It reads something other than
  `self`, always answers the same way, sits on a record or struct, or a
  declaration's own fields provably fail an interface it declares.

## Next

- [Interfaces](interfaces.md): structural satisfaction, and what `is` means
  without a refinement.
- [Narrowing](narrowing.md): what `is` proves once it has answered.
