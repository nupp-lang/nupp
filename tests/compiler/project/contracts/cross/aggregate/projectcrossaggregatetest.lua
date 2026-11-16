local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local exists = fixture.exists

local cross = require("helpers.crossproject")
local M = {}

-- `--platform all` still builds each configured platform on its own and reports
-- every one, so the refusal of each is reported per platform and the aggregate
-- fails without writing an output for any of them.
function M.anAggregateBuildReportsEveryPlatformRefused()
    cross.withProject(function(context)
        local dir = context.dir
        local produced, diagnostics = {}, {}
        testAssert.eq(
            project.build(dir, {platform = "all", produced = produced, diagnostics = diagnostics}),
            1,
            "the aggregate fails"
        )
        testAssert.eq(#produced.platforms, #context.platforms, "every configured platform is reported")
        for index, platform in ipairs(context.platforms) do
            local entry = produced.platforms[index]
            testAssert.eq(entry.platform, platform, "platforms are reported in configured order")
            testAssert.eq(entry.status, "failed", platform .. " is refused")
            testAssert.eq(#entry.outputs, 0, platform .. " produced nothing")
        end
        testAssert.eq(#produced.outputs, 0, "the aggregate produced nothing")
        assert(cross.refused(diagnostics), "the refusal names the VM program contract")
        assert(not exists(dir .. "/build/default"), "no platform output directory was written")
    end)
end

return M
