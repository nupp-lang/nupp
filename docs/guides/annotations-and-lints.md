# Annotations and lints

Annotations add checked, type-erased metadata to declarations. Lints report
code that is valid but likely unintended. Use both to make project policy
explicit and keep exceptions narrow.

## Define focused annotations

An annotation is a record marked with `@annotation`. Restrict it to the
semantic targets where it makes sense:

```nupp
@annotation(targets = {"record", "struct"})
record wireFormat
   name: string
   version: integer?
end

@wireFormat(name = "user", version = 2)
local record UserMessage
   userId: uint64
end
```

Use camelCase for annotation names and fields. Prefer a small domain-specific
contract such as `wireFormat` over a vague bag of options. Annotation values
are compile-time constants and disappear from generated Lua.

For a one-value annotation, mark one field with `@annotationValue` so call
sites stay readable:

```nupp
@annotation(targets = {"record", "field"})
record documentation
   @annotationValue
   text: string
end

@documentation("A user returned by the account service")
local record AccountUser
   @documentation("The stable account identifier")
   accountId: uint64
end
```

## Set lint policy once

Configure project-wide levels in `nupp.lua`:

```lua
return {
   include = { "src" },

   lints = {
      correctness = "error",
      pedantic = "warning",
      style = "warning",
      ["enum-exhaustiveness"] = "error",
   },
}
```

Categories establish the broad policy; a named lint overrides its category.
Run `nupp lints` to see every lint, stable code, summary, and effective default
before choosing a project override.

## Suppress the smallest statement

When an exception is intentional, name the lint on the exact statement:

```nupp
@allow("missing-require")
local externalMath = injectedRuntimeModule.double(21)
```

Prefer a named `@allow` over bare `@allow`, and explain a non-obvious exception
in a nearby comment. Do not turn off a category because one line is unusual.
An allow can suppress a lint at any level, but it cannot suppress a type error.

The [annotations reference](../../reference/annotations/index.html) lists
targets, built-in annotations, references, and validation rules. The
[lints reference](../../reference/lints/index.html) explains resolution,
severity, and how compiler contributors add a lint.

