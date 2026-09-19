local test = require("assert")
local cplan = require("nupp.compiler.aot.cplan")
local M = {}
local function fixture()
    local layout = {fields={{name="x",type="f32",sourceType="float"},{name="y",type="f32",sourceType="float"}}}
    local function load(field)
        return {op="let",name=field,cName=field,type="simd_vector_f32_fixed4",value={
            op="simd_field_load",span="points",layout="Point",field=field,
            cursor="cursor",cursorCName="cursor",type="simd_vector_f32_fixed4",args={{},{}}
        }}
    end
    return load("x"),load("y"),{Point=layout}
end
function M.onlyAdjacentWholeHomogeneousPairsAreSelected()
    local first, second, layouts = fixture()
    assert(cplan.neonFieldPair(first,second,layouts))
    local reversed = assert(cplan.neonFieldPair(second,first,layouts))
    test.equal(reversed.leftIndex,1)
    test.equal(reversed.rightIndex,0)
    test.equal(next(cplan.fieldPairs({first,{op="assign"},second},layouts)),nil)
    second.value.args[3]={}
    test.equal(cplan.neonFieldPair(first,second,layouts),nil)
    second.value.args[3]=nil
    second.value.cursor="other"
    test.equal(cplan.neonFieldPair(first,second,layouts),nil)
    second.value.cursor="cursor"
    layouts.Point.fields[2].sourceType="uint32"
    test.equal(cplan.neonFieldPair(first,second,layouts),nil)
    layouts.Point.fields[2].sourceType="float"
    layouts.Point.fields[3]={name="z",type="f32",sourceType="float"}
    test.equal(cplan.neonFieldPair(first,second,layouts),nil)
end
return M
