local fixture = require("helpers.deriveprovider")
local STRICT = fixture.STRICT
local checksStrictly = fixture.checksStrictly
local ran = fixture.ran

local M = {}

function M.attachesADeriveThroughAnExportWrapper()
    -- `@derive(...) export record R` decorates R, the way it does without the
    -- visibility; the export is a wrapper the annotation looks through.
    checksStrictly(STRICT.exported, "the exported-derive main checks strictly")
    local output = ran(STRICT.exported, "the exported-derive main runs")
    assert(output == "Point { x = 3 }\n", output)
end

function M.publishesAnExportedRecordAsItsWitness()
    -- Reached through its module, an exported record is the `Type<R>` its own
    -- scope binds, so a `Type<T>` directed API and a construction pack take it
    -- from either side of the boundary.
    checksStrictly(STRICT.witness, "the exported-witness main checks strictly")
    local output = ran(STRICT.witness, "the exported-witness main runs")
    assert(output == "true\t1\t2\nspawned\tnumber\n", output)
end

function M.forwardsAReflectedAnnotationTypeAsARuntimeWitness()
    checksStrictly(STRICT.annotationWitness, "the annotation-witness consumer checks strictly")
    ran(STRICT.annotationWitness, "the annotation-witness consumer runs")
end

return M
