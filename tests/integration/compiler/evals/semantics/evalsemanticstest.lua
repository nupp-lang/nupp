local M = {}
function M.gradesAndSummarizesEvaluationResults()
    local root = require("helpers.paths").root
    local project = require("helpers.contractproject").open(root)
    local output = project.run("tests/fixtures/evals/semantics.nupp", true)
    assert(output:find("evaluation harness self-test passed", 1, true), output)
end

return M
