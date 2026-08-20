# Refinements

An interface may carry a `satisfies` declaration naming the runtime test that
decides whether a value is one of these. `x is T` compiles to that test, so an
interface can answer `is` for a value this program never built.

```nupp:playground
local interface Shape
    kind: string
end

local interface Circle is Shape
    kind: string
    radius: number

    satisfies |self| -> self.kind == "circle"
end

local function area(s: Shape): number
    if s is Circle then
        return 3 * s.radius * s.radius
    end
    return 0
end
```

`s is Circle` becomes `type(s) == "table" and s.kind == "circle"`. The table
test is part of the compiled predicate, because `is` is asked about values that
may be anything at all. See [Interfaces](interfaces.md) for the rest of what an
interface declares.

## Refinement forms

A refinement is a function of the value, so it is written as one, in either
form a function takes anywhere else: the arrow above, or a body whose single
`return` says the same thing.

```nupp
local interface Circle
    kind: string
    radius: number

    satisfies(self): boolean
        return self.kind == "circle"
    end
end
```

## Only interfaces carry refinements

A record is identified by the metatable `new` stamps and a struct by its ctype,
so both already answer `is` exactly. A refinement beside either would be a
second answer to a settled question, and which answer `is R` gave would depend
on whether a body happened to carry one. See [Records and
structs](records.md#records) for the identities those declarations get.

An interface has no runtime table at all, so this is the only identity it can
have. That is also what makes it useful: a table off a JSON decoder, or
anything an untyped library returned, never received a metatable, so nothing
else could identify it.

```nupp
local interface Circle
    kind: string
    radius: number

    satisfies |self| -> self.kind == "circle"
end

local function radiusOf(decoded: any): number
    if decoded is Circle then
        return decoded.radius
    end
    return 0
end
```

::: deepdive
A refined type is entered by running the test, not by writing the name. An
annotation on its own establishes nothing a consumer can use, because it lowers
to exactly the Lua that writing no annotation lowers to. A name that reads as a
guarantee and proves nothing is worse than no name: every consumer that wanted
the fact still has to test for it, and every reader believes something untrue.
Running the test at `is` is what turns the name into a fact the checker
carries. See [Narrowing](narrowing.md#narrowing-tests) for the operations that
establish one.
:::

## Tests read `self` and nothing else

A refinement runs wherever `is` is written, so it reads the declaration's own
fields through `self`: comparisons against literals, `type()` tests, and `and`,
`or` and `not`. A call, arithmetic, or a name from outside the subject is
reported.

A refinement that always answers the same way is reported as well. Always
true identifies every value and always false leaves the type uninhabited, and
neither is a test.

A subject that is not a plain name is evaluated once and handed to the test,
since a refinement may read it more than once. Reaching through a field guards
the step before it with `?.`, because the test runs against values that are not
of the type yet, so `satisfies |self| -> self.a.b == "x"` compiles to
`s.a?.b == "x"`.

::: deepdive
The grammar of a test is small because the checker reads it as well as running
it. Comparisons against literals and `type()` tests reduce to facts the checker
can compare against a declaration's own fields, which is what lets `record C is
Shape` be proved rather than trusted. An arbitrary function body would have to
be executed to answer that question, and it would run once per `is` in a
program that may write thousands of them.
:::

## Conformance claims are proved

`record C is Shape` is a claim the checker proves, and `Shape`'s refinement is
what `is Shape` runs. Fields that provably fail it are reported, because
the alternative is a value the checker calls a `Shape` and `is` calls
otherwise.

```nupp
local interface Circle
    kind: string
    radius: number

    satisfies |self| -> self.kind == "circle"
end

local record Square is Circle
    kind: "square" -- NUPP2122: "square" provably fails Circle's refinement
    radius: number
end
```

::: seealso
- [interfaces.md](interfaces.md) for what an interface declares and how
  satisfaction is decided without a refinement
- [narrowing.md](narrowing.md) for the tests that establish a fact and the
  assignments that drop it
- [records.md](records.md) for the nominal identity a record and a struct get
  instead
:::
