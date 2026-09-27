local text = require("nupp.compiler.aot.text")

local M = {}

local function localValue(name, valueType)
    return {op = "local", name = name, cName = name, type = valueType}
end

local function exact(value, valueType)
    return {op = valueType == "u64" and "constant_i64" or "constant_i32", value = tostring(value), type = valueType,}
end

function M.retainsEveryDecimalBuilderOperand()
    local line = text.block(
        {
            {
                op = "lua_builder_decimal64",
                builder = localValue("builder", "lua_builder"),
                sourceBytes = localValue("source", "lua_string"),
                start = exact(0, "u32"),
                length = exact(3, "u32"),
                value = exact(123, "u64"),
                exponent = exact(-2, "i32"),
                negative = {op = "bool", value = false, type = "bool"},
                exact = {op = "bool", value = true, type = "bool"},
                type = "lua_effect",
            }
        },
        0
    )[1]
    assert(line:find("constant:u64 123, constant:i32 -2, bool false, bool true", 1, true), line)
end

function M.closesNestedBlocks()
    local lines = text.block({{op = "block", body = {{op = "break"}}}, {op = "continue"},}, 0)
    assert(table.concat(lines, "\n") == "block\n  break\nend\ncontinue")
end

return M
