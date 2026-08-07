# Modules and types

Nupp follows Lua's module model: a file builds a value and returns it. Typed
declarations say where they live with the same three choices as ordinary Lua:
local to the file, attached to a table, or explicitly global.

## Export through one table

Create `src/models.nupp`:

```nupp
local models = {}

local type UserId = uint64

record models.User
   id: UserId
   displayName: string
end

function models.newUser(id: UserId, displayName: string): models.User
   return models.User{id = id, displayName = displayName}
end

return models
```

The module table is the public runtime surface. `models.User` and
`models.newUser` are intentionally qualified, while `UserId` remains a
private implementation detail.

Prefer this shape for application modules:

- keep helpers and internal aliases `local`;
- attach exported records, structs, functions, and values to the module table;
- return that table once at the end;
- reserve `global` for the rare contract that truly belongs to the whole
  project.

Nupp rejects an unqualified typed declaration such as `record User`. Write
`local record User`, `record models.User`, or `global record User` so its
visibility cannot be mistaken for Lua's implicit-global behavior.

## Require the runtime value

Use the module from `src/app/main.nupp`:

```nupp
local models = require("models")

local currentUser: models.User = models.newUser(42, "Ada")
print(currentUser.displayName)
```

The type `models.User` and the constructor value come from the same explicit
module name. A fully qualified type path can be resolved by the checker, but
the runtime table still needs `require`. Keeping the import makes that runtime
fact obvious and avoids the `missing-require` lint.

## Name things consistently

Use camelCase for functions, methods, locals, parameters, fields, and Nupp
module filenames. Use PascalCase for nominal types such as `User`,
`HttpClient`, and `ReadBuffer`. Use uppercase names only for constants that
are genuinely constant and benefit from standing out.

Prefer names that explain the domain role: `loadProfile` says more than
`doLoad`, and `retryCount` says more than `n`. Avoid leading underscores for
public API. The documentation generator treats members beginning with `_`,
source files beginning with `_`, and files under `internal/` as private unless
the docs target explicitly opts into private output.

## Keep boundaries typed

Annotate exported function parameters and returns. Let obvious locals infer
their types unless an annotation documents an important constraint.

```nupp
function models.findUser(id: UserId): models.User?
   if id == 0 then return nil end
   return models.newUser(id, "Unknown")
end
```

This keeps public contracts stable without making the function body noisy.
Reach for records when identity and behavior matter, structs when fixed FFI
layout matters, and type aliases when a name clarifies an existing type.

The [module reference](../modules/index.html) covers declaration files,
nested types, module inference, and all visibility rules. The
[metamethod reference](../../reference/metamethods/index.html) covers methods,
interfaces, and trusted operator contracts.

