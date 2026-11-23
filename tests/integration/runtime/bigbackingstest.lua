-- A program may hold many more large tables than the runtime once kept page
-- mappings for: on the core each array part past 4,096 words is a mapping of
-- its own, and the ledger used to refuse the 4,097th.
local test = require("assert")
local M = {}

-- Past the pooled backings' largest size, so each table's array part is
-- mapped by itself.
local WORDS = 4097
local TABLES = 5000

function M.manyLiveLargeTablesKeepTheirValues()
    local held = {}
    for i = 1, TABLES do
        local t = {}
        for j = 1, WORDS do
            t[j] = j
        end
        held[i] = t
    end
    test.eq(#held, TABLES)
    test.eq(held[1][WORDS], WORDS)
    test.eq(held[TABLES][1], 1)
    test.eq(#held[TABLES], WORDS)
end

return M
