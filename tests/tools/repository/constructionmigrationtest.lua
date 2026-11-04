local paths = require("helpers.paths")
local migrate = assert(loadfile(paths.tests .. "/../scripts/migrate-construction.lua"))("library")
local M = {}

function M.removesOnlyConstructionTokens()
    local cases = {
        {"return new Point(x = 1)", "return Point(x = 1)"},
        {"return new m.Box<integer>(new Point(1))", "return m.Box<integer>(Point(1))"},
        {"return (new Point(1)):length()", "return (Point(1)):length()"},
        {"return new --[[keep]] Point(1)", "return --[[keep]] Point(1)"},
        {"local p = new\tPoint(1)\r\nreturn p\r\n", "local p = Point(1)\r\nreturn p\r\n"},
        {"return `literal new Point() ${new Point(1)}`", "return `literal new Point() ${Point(1)}`"},
        {
            "local s = 'new Point()' -- new Point()\nreturn new Point(1)",
            "local s = 'new Point()' -- new Point()\nreturn Point(1)"
        },
        {
            "local s = [==[new Point()]==]\n--[=[new Point()]=]\nreturn new Point(1)",
            "local s = [==[new Point()]==]\n--[=[new Point()]=]\nreturn Point(1)"
        },
        {
            "local new = 1\nlocal held = new\nreturn buffer.new()",
            "local new = 1\nlocal held = new\nreturn buffer.new()"
        },
        {"-- café\nreturn new Point(1)", "-- café\nreturn Point(1)"},
        {"@!internal\nreturn new Point(1)", "@!internal\nreturn Point(1)"},
    }
    for _, case in ipairs(cases) do
        local plan, problem = migrate.plan(case[1], "fixture.nupp")
        assert(plan, problem and problem.msg)
        assert(plan.output == case[2], plan.output)
        local again = assert(migrate.plan(plan.output, "fixture.nupp"))
        assert(#again.edits == 0 and again.output == plan.output, "migration must be idempotent")
    end
end

function M.refusesMalformedInput()
    for _, source in ipairs({"return new Point", "return new Point(", "local = new Point()"}) do
        local plan, problem = migrate.plan(source, "broken.nupp")
        assert(plan == nil and problem.msg, "malformed source must not be rewritten")
    end
end

function M.reportsCallContractsWithoutRewritingThem()
    local source = [[local record Handler
    value: string
    constructor(self, value: string) self.value = value end
    metamethod __call: function(self): string
end
Handler.__call = function(self: Handler): string return self.value end
local h = new Handler('hello')
return h()
]]
    local plan = assert(migrate.plan(source, "handler.nupp"))
    assert(#plan.edits == 1 and #plan.review == 2)
    assert(plan.records == 1 and plan.constructors == 1)
    assert(plan.output == source:gsub("new Handler", "Handler"))
end

return M
