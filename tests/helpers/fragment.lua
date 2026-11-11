-- The checker, as the tests reach it.
--
-- A test source is a fragment rather than a program. It binds what the case is
-- about and stops: it does not return its module, does not use what it declares,
-- calls a helper to see that the call checks rather than for the answer, and
-- shadows names it has no use for on purpose. Those are the two lints that ask a
-- file to be a whole program, so the fragment default turns both off. Leaving
-- them on would mean every fixture in the suite carried a `return` it is not
-- about, which is a worse fixture and a worse test. A fragment also reaches a
-- module by its full path when that path is what the case is about, which
-- `inline-module-path` would ask it to spell as an import instead.
--
-- A project's own `lints` still apply on top of the default, so a fixture that
-- turns a lint off in its configuration checks the way the project would. A
-- case that is about either lint asks for it back by passing its own `lints`
-- table -- `opts.lints` replaces this wholesale, the same as it replaces a
-- project's. Everything else about `nupp.compiler.check` is passed straight
-- through.

local check = require("nupp.compiler.check")

local FRAGMENT_LINTS = {["unused-binding"] = "off", ["discarded-result"] = "off", ["inline-module-path"] = "off",}

local fragment = {}

for key, value in pairs(check) do
    fragment[key] = value
end

function fragment.check(result, filename, env, opts)
    local merged = {}
    for key, value in pairs(opts or {}) do
        merged[key] = value
    end
    if opts and opts.lints then
        merged.lints = opts.lints
    else
        local lints = {}
        for name, level in pairs(FRAGMENT_LINTS) do
            lints[name] = level
        end
        for name, level in pairs(env and env.config and env.config.lints or {}) do
            lints[name] = level
        end
        merged.lints = lints
    end
    local diagnostics, moduleType, exports = check.check(result, filename, env, merged)
    -- What the check found, kept on the parse, so a core-side compile of this
    -- fragment uses these diagnostics rather than checking it again.
    result.fragmentCheck = {
        root = result.root,
        symbols = result.symbols,
        path = filename,
        moduleName = result.moduleName,
        diagnostics = diagnostics,
    }

    return diagnostics, moduleType, exports
end

return fragment
