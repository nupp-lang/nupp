local summary = require("tests.simd.native-summary")
local M = {}

local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for k,v in pairs(value) do result[k]=copy(v) end; return result
end

local function selection()
    return {compilers={"clang"},tiers={"neon"},families={"reducers"},types={"number"},algorithms={},lanes={2,3}}
end

local function row(family,element,lanes)
    family,element=family or "reducers",element or "number"
    local generated=require("tests.simd." .. family).generate{types={element},lanes=lanes or {2,3}}
    local calls,probes={},0
    for module,names in pairs(generated.probes) do for _,name in ipairs(names) do calls[module .. "." .. name]=1; probes=probes+1 end end
    local execution={ok=true,tier="neon",compilerCommand="clang",cases=100,probes=probes,nativeCalls=probes,calls=calls}
    execution.scalarC=copy(execution); execution.scalarC.route="scalar-C"
    execution.scalarC.symbols={}; for key in pairs(calls) do execution.scalarC.symbols[key]="ks_" .. key:gsub("%.","_") .. "_forced_scalar__neon" end
    return {compiler="1",tier="neon",family=family,element=element,status="executed",execution=execution}
end

local function rejects(rows,selected)
    local result=summary.summarize(selected or selection(),rows)
    assert(result.failed>0 and not result.requested_native_matrix_complete and not result.available_execution_pass)
    return result
end

function M.acceptsBothCompletedRoutesForTheRequestedInventory()
    for _,family in ipairs({"primitives","reducers"}) do
        for _,element in ipairs({"float","number","int8","uint8","int16","uint16","int32","uint32","int64","uint64"}) do
            local selected=selection(); selected.families={family}; selected.types={element}
            local result=summary.summarize(selected,{row(family,element)})
            assert(result.requested_native_matrix_complete and result.executed==1 and result.failed==0)
        end
    end
end

function M.rejectsAnOmittedRequestedRowAndEmptyMatrix()
    local selected=selection(); selected.types={"number","int32"}
    local result=rejects({row()},selected)
    assert(#result.rows==2 and result.rows[2].element=="int32" and result.rows[2].reason:find("missing"))
    rejects({})
end

function M.rejectsDuplicateAndUnrequestedRows()
    rejects({row(),row()})
    local extra=row(); extra.element="int32"; rejects({row(),extra})
end

function M.retainsFailureAndUnavailableHardwareWithoutClaimingCompletion()
    local failed={compiler="1",tier="neon",family="reducers",element="number",status="failed",evidence="original-driver.log"}
    local report=rejects({failed})
    assert(report.rows[1].evidence=="original-driver.log")
    local unavailable={compiler="1",tier="neon",family="-",element="-",status="not-executed",evidence="tiers.txt"}
    report=summary.summarize(selection(),{unavailable})
    assert(report.failed==0 and report.unavailable==1 and not report.requested_native_matrix_complete)
    rejects({copy(unavailable),row()})
    unavailable.status="failed"; report=rejects({unavailable}); assert(#report.rows==1)
end

function M.rejectsMissingOrDifferentScalarRoute()
    local actual=row(); actual.execution.scalarC=nil; rejects({actual})
    actual=row(); actual.execution.scalarC.route="native"; rejects({actual})
    actual=row(); actual.execution.scalarC.cases=99; rejects({actual})
    actual=row(); actual.execution.scalarC.symbols[next(actual.execution.calls)]="ks_native__neon"; rejects({actual})
end

function M.rejectsPartialActualWidthsDespiteFullCoverageMetadata()
    for _,family in ipairs({"primitives","reducers"}) do
        local selected=selection(); selected.families={family}
        local actual=row(family,"number",{2})
        actual.execution.coverage={types={"number"},lanes={2,3}}
        rejects({actual},selected)
        actual=row(family,"number")
        actual.execution.scalarC=row(family,"number",{2}).execution.scalarC
        actual.execution.scalarC.probes=actual.execution.probes
        rejects({actual},selected)
    end
end

function M.rejectsDeclaredButUncalledAndMismatchedProbeCounts()
    local actual=row(); actual.execution.calls[next(actual.execution.calls)]=0; rejects({actual})
    actual=row(); actual.execution.probes=actual.execution.probes+1; rejects({actual})
    actual=row(); actual.execution.nativeCalls=actual.execution.nativeCalls+1; rejects({actual})
end

function M.rejectsMissingReducerContractsAndPrimitiveFamilies()
    for _,family in ipairs({"primitives","reducers"}) do
        local selected=selection(); selected.families={family}
        local actual=row(family,"number")
        local match=family=="primitives" and "simd_memory" or "simd_masked_reducers"
        for key in pairs(actual.execution.calls) do
            if key:find(match,1,true) then actual.execution.calls[key]=nil; actual.execution.probes=actual.execution.probes-1; actual.execution.nativeCalls=actual.execution.nativeCalls-1 end
        end
        rejects({actual},selected)
    end
end

function M.keepsAvailableSuccessSeparateFromMissingHardware()
    local selected=selection(); selected.tiers={"neon","avx2"}
    local unavailable={compiler="1",tier="avx2",family="-",element="-",status="not-executed",evidence="tiers.txt"}
    local report=summary.summarize(selected,{row(),unavailable})
    assert(report.failed==0 and report.executed==1 and report.unavailable==1 and report.available_execution_pass and not report.requested_native_matrix_complete)
end

function M.acceptsPreferredWithoutInventingTransposeOrScalarOnlyReducers()
    for _, family in ipairs({"primitives","reducers"}) do
        for _, element in ipairs({"float","number","int8","uint8","int16","uint16","int32","uint32","int64","uint64"}) do
            local selected=selection(); selected.families={family}; selected.types={element}; selected.lanes={2,"preferred"}
            assert(summary.summarize(selected,{row(family,element,selected.lanes)}).requested_native_matrix_complete)
        end
    end
end

function M.rejectsWrongCompilerAndMissingAlgorithmExecution()
    local actual=row(); actual.execution.compilerCommand="gcc"; rejects({actual})
    local selected=selection(); selected.algorithms={"utf8simd"}; rejects({row()},selected)
    local algorithm={compiler="1",tier="neon",family="algorithms",element="utf8simd",status="executed",execution={ok=true,tier="neon",compiler="clang",algorithm="utf8simd",cases=3,nativeCalls=2}}
    assert(summary.summarize(selected,{row(),algorithm}).requested_native_matrix_complete)
    algorithm.execution.algorithm="base64simd"; rejects({row(),algorithm},selected)
end

return M
