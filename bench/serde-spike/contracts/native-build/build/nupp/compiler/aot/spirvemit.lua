_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()









local scalarIR = require ( "nupp.compiler.aot.scalar" )

local spirv = { }


const OP = {
Name = 5 ,
MemberName = 6 ,
ExtInstImport = 11 ,
ExtInst = 12 ,
MemoryModel = 14 ,
EntryPoint = 15 ,
ExecutionMode = 16 ,
Capability = 17 ,
TypeVoid = 19 ,
TypeBool = 20 ,
TypeInt = 21 ,
TypeFloat = 22 ,
TypeVector = 23 ,
TypeArray = 28 ,
TypeRuntimeArray = 29 ,
TypeStruct = 30 ,
TypePointer = 32 ,
TypeFunction = 33 ,
ConstantTrue = 41 ,
ConstantFalse = 42 ,
Constant = 43 ,
ConstantComposite = 44 ,
Function = 54 ,
FunctionParameter = 55 ,
FunctionEnd = 56 ,
FunctionCall = 57 ,
Variable = 59 ,
Load = 61 ,
Store = 62 ,
AccessChain = 65 ,
Decorate = 71 ,
MemberDecorate = 72 ,
CompositeConstruct = 80 ,
CompositeExtract = 81 ,
ConvertFToU = 109 ,
ConvertFToS = 110 ,
ConvertSToF = 111 ,
ConvertUToF = 112 ,
UConvert = 113 ,
SConvert = 114 ,
Bitcast = 124 ,
FNegate = 127 ,
IAdd = 128 ,
FAdd = 129 ,
ISub = 130 ,
FSub = 131 ,
IMul = 132 ,
FMul = 133 ,
UDiv = 134 ,
FDiv = 136 ,
UMod = 137 ,
IsNan = 156 ,
LogicalEqual = 164 ,
LogicalNotEqual = 165 ,
LogicalOr = 166 ,
LogicalAnd = 167 ,
LogicalNot = 168 ,
Select = 169 ,
IEqual = 170 ,
INotEqual = 171 ,
UGreaterThan = 172 ,
SGreaterThan = 173 ,
UGreaterThanEqual = 174 ,
SGreaterThanEqual = 175 ,
ULessThan = 176 ,
SLessThan = 177 ,
ULessThanEqual = 178 ,
SLessThanEqual = 179 ,
FOrdEqual = 180 ,
FOrdNotEqual = 182 ,
FOrdLessThan = 184 ,
FOrdGreaterThan = 186 ,
FOrdLessThanEqual = 188 ,
FOrdGreaterThanEqual = 190 ,
ShiftRightLogical = 194 ,
ShiftRightArithmetic = 195 ,
ShiftLeftLogical = 196 ,
BitwiseOr = 197 ,
BitwiseXor = 198 ,
BitwiseAnd = 199 ,
ControlBarrier = 224 ,
SelectionMerge = 247 ,
LoopMerge = 246 ,
Label = 248 ,
Branch = 249 ,
BranchConditional = 250 ,
Return = 253 ,
ReturnValue = 254 ,
}

const STORAGE = { Input = 1 , Uniform = 2 , Workgroup = 4 , Function = 7 , StorageBuffer = 12 }
const DECORATION = {
Block = 2 ,
ArrayStride = 6 ,
BuiltIn = 11 ,
NonWritable = 24 ,
Binding = 33 ,
DescriptorSet = 34 ,
Offset = 35 ,
NoContraction = 42 ,
}

local function push ( into , values ) 
for _ , value in ipairs ( values ) do
into [ # into + 1 ] = value
end
end

local function instruction ( into , opcode , operands ) 
into [ # into + 1 ] = opcode + ( # operands + 1 ) * 65536
push ( into , operands )
end

local function stringWords ( value ) 
local bytes = value .. "\0"
local out = { }
local at = 1
while at <= # bytes do
local word = 0
local scale = 1
for offset = 0 , 3 do
local byte = bytes : byte ( at + offset ) or 0
word = word + byte * scale
scale = scale * 256
end
out [ # out + 1 ] = word
at = at + 4
end

return out
end

local function namedOperands ( prefix , name , suffix ) 
local out = { }
push ( out , prefix )
push ( out , stringWords ( name ) )
push ( out , suffix or { } )

return out
end

local function wordBytes ( word ) 
local b0 = word % 256
local b1 = math . floor ( word / 256 ) % 256
local b2 = math . floor ( word / 65536 ) % 256
local b3 = math . floor ( word / 16777216 ) % 256

return string . char ( b0 , b1 , b2 , b3 )
end


local function f32Bits ( value ) 
if value ~= value then
return 2143289344
end
local sign = 0
if value < 0 or ( value == 0 and 1 / value < 0 ) then
sign = 2147483648
end
local magnitude = math . abs ( value )
if magnitude == math . huge then
return ( sign + 2139095040 )
elseif magnitude == 0 then
return sign
end

local fraction , exponent = math . frexp ( magnitude )
local biased = exponent + 126
local mantissa
if biased <= 0 then
mantissa = magnitude / ( 2 ^ -149 )
biased = 0
else
mantissa = ( fraction * 2 - 1 ) * 8388608
end
local lower = math . floor ( mantissa )
local remainder = mantissa - lower
if remainder > 0.5 or ( remainder == 0.5 and lower % 2 == 1 ) then
lower = lower + 1
end
if biased == 0 and lower >= 8388608 then
biased = 1
lower = 0
elseif lower >= 8388608 then
biased = biased + 1
lower = 0
end
if biased >= 255 then
return ( sign + 2139095040 )
end

return ( sign + biased * 8388608 + lower )
end

local function align ( value , alignment ) 
return ( math . floor ( ( value + alignment - 1 ) / alignment ) * alignment )
end

local function physical ( type_ , sourceType ) 
local stored = sourceType or type_
if stored == "float" or type_ == "f32" then
return "f32" , 4 , 4
elseif stored == "int8" then
return "i8" , 1 , 1
elseif stored == "uint8" then
return "u8" , 1 , 1
elseif stored == "int16" then
return "i16" , 2 , 2
elseif stored == "uint16" then
return "u16" , 2 , 2
elseif stored == "int32" or type_ == "i32" then
return "i32" , 4 , 4
elseif stored == "uint32" or type_ == "u32" then
return "u32" , 4 , 4
end

return type_ , 0 , 0
end


function spirv . program (
program ,
readonly ,
writable ,
uniforms ,
threads
) 
local capabilities = { }
local entry = { }
local debug = { }
local annotations = { }
local declarations = { }
local functions = { }
local nextId = 1

local function id ( ) 
local answer = nextId
nextId = nextId + 1
return answer
end

local function name ( target , value ) 
instruction ( debug , OP . Name , namedOperands ( { target } , value ) )
end

local function decorate ( target , decoration , values ) 
local operands = { target , decoration }
push ( operands , values or { } )
instruction ( annotations , OP . Decorate , operands )
end

instruction ( capabilities , OP . Capability , { 1 } )
local needs8 , needs16 = false , false
for _ , layout in ipairs ( program . layouts or { } ) do
for _ , field in ipairs ( layout . fields ) do
local _ , size = physical ( field . type , field . sourceType )
needs8 = needs8 or size == 1
needs16 = needs16 or size == 2
end
end
for _ , param in ipairs ( program . params ) do
local _ , size = physical ( param . type , param . sourceType )
needs8 = needs8 or size == 1
needs16 = needs16 or size == 2
end
if needs8 then
instruction ( capabilities , OP . Capability , { 39 } )
instruction ( capabilities , OP . Capability , { 4448 } )
end
if needs16 then
instruction ( capabilities , OP . Capability , { 22 } )
instruction ( capabilities , OP . Capability , { 4433 } )
end

local ext = id ( )
instruction ( capabilities , OP . ExtInstImport , namedOperands ( { ext } , "GLSL.std.450" ) )
instruction ( capabilities , OP . MemoryModel , { 0 , 1 } )

local types = { }

local function scalarType ( key ) 
local cached = types [ key ]
if cached then
return cached
end
local answer = id ( )
types [ key ] = answer
if key == "void" then
instruction ( declarations , OP . TypeVoid , { answer } )
elseif key == "bool" then
instruction ( declarations , OP . TypeBool , { answer } )
elseif key == "f32" then
instruction ( declarations , OP . TypeFloat , { answer , 32 } )
else
local width = tonumber ( key : match ( "%d+" ) )
local signed = key : sub ( 1 , 1 ) == "i" and 1 or 0
instruction ( declarations , OP . TypeInt , { answer , width , signed } )
end

return answer
end

local voidType = scalarType ( "void" )
local boolType = scalarType ( "bool" )
local f32Type = scalarType ( "f32" )
local i32Type = scalarType ( "i32" )
local u32Type = scalarType ( "u32" )
local vec2fType = id ( )
instruction ( declarations , OP . TypeVector , { vec2fType , f32Type , 2 } )
local vec3uType = id ( )
instruction ( declarations , OP . TypeVector , { vec3uType , u32Type , 3 } )

local function pointerType ( storage , pointee ) 
local key = tostring ( storage ) .. ":" .. tostring ( pointee )
local cached = types [ key ]
if cached then
return cached
end
local answer = id ( )
types [ key ] = answer
instruction ( declarations , OP . TypePointer , { answer , storage , pointee } )

return answer
end

local function functionType ( result , params ) 
local key = "fn:" .. tostring ( result ) .. ":" .. table . concat ( params , "," )
local cached = types [ key ]
if cached then
return cached
end
local answer = id ( )
types [ key ] = answer
local operands = { answer , result }
push ( operands , params )
instruction ( declarations , OP . TypeFunction , operands )

return answer
end

local constants = { }

local function constant ( typeId , word ) 
local key = tostring ( typeId ) .. ":" .. tostring ( word )
local cached = constants [ key ]
if cached then
return cached
end
local answer = id ( )
constants [ key ] = answer
instruction ( declarations , OP . Constant , { typeId , answer , word } )

return answer
end

local zeroU = constant ( u32Type , 0 )
local oneU = constant ( u32Type , 1 )
local zeroF = constant ( f32Type , 0 )
local canonicalNanBits = constant ( u32Type , 2143289344 )

local function canonicalNan ( ) 
local value = id ( )
instruction ( functions , OP . Bitcast , { f32Type , value , canonicalNanBits } )

return value
end

local falseId = id ( )
instruction ( declarations , OP . ConstantFalse , { boolType , falseId } )
local trueId = id ( )
instruction ( declarations , OP . ConstantTrue , { boolType , trueId } )

local layoutTypes = { }
local layoutFields = { }
local layoutStride = { }
for _ , layout in ipairs ( program . layouts or { } ) do
local members = { }
local offsets = { }
local byName = { }
local offset = 0
local largest = 1
for index , field in ipairs ( layout . fields ) do
local key , size , alignment = physical ( field . type , field . sourceType )
assert ( size > 0 , "SPIR-V struct field must have fixed-width storage" )
offset = align ( offset , alignment )
offsets [ index ] = offset
members [ index ] = scalarType ( key )
byName [ field . name ] = index - 1
offset = offset + size
largest = math . max ( largest , alignment )
end
local typeId = id ( )
local operands = { typeId }
push ( operands , members )
instruction ( declarations , OP . TypeStruct , operands )
name ( typeId , layout . name )
for index , field in ipairs ( layout . fields ) do
instruction ( debug , OP . MemberName , namedOperands ( { typeId , index - 1 } , field . name ) )
instruction ( annotations , OP . MemberDecorate , { typeId , index - 1 , DECORATION . Offset , offsets [ index ] } )
end
layoutTypes [ layout . name ] = typeId
layoutFields [ layout . name ] = byName
layoutStride [ layout . name ] = align ( offset , largest )
end


local uniformMembers = { u32Type }
local uniformIndex = { [ "\0count" ] = 0 }
local spans = { }
for _ , param in ipairs ( readonly ) do
spans [ # spans + 1 ] = param
end
for _ , param in ipairs ( writable ) do
spans [ # spans + 1 ] = param
end
for _ , param in ipairs ( spans ) do
uniformIndex [ param . name .. "_count" ] = # uniformMembers
uniformMembers [ # uniformMembers + 1 ] = u32Type
end
for _ , param in ipairs ( spans ) do
uniformIndex [ param . name .. "_offset" ] = # uniformMembers
uniformMembers [ # uniformMembers + 1 ] = u32Type
end
for _ , param in ipairs ( uniforms ) do
uniformIndex [ param . name ] = # uniformMembers
uniformMembers [ # uniformMembers + 1 ] = scalarType ( param . type )
end
local uniformStruct = id ( )
local uniformOperands = { uniformStruct }
push ( uniformOperands , uniformMembers )
instruction ( declarations , OP . TypeStruct , uniformOperands )
name ( uniformStruct , "NuppUniforms" )
decorate ( uniformStruct , DECORATION . Block )
for index = 0 , # uniformMembers - 1 do
instruction ( annotations , OP . MemberDecorate , { uniformStruct , index , DECORATION . Offset , index * 4 } )
end
local uniformPointer = pointerType ( STORAGE . Uniform , uniformStruct )
local uniformsVar = id ( )
instruction ( declarations , OP . Variable , { uniformPointer , uniformsVar , STORAGE . Uniform } )
name ( uniformsVar , "uniforms" )
decorate ( uniformsVar , DECORATION . DescriptorSet , { 2 } )
decorate ( uniformsVar , DECORATION . Binding , { 0 } )

local bufferVars = { }
local bufferElement = { }
local bufferPhysical = { }

local function declareBuffer ( param , set , binding , readonlyBuffer ) 
local key , size = physical ( param . type , param . sourceType )
local element = layoutTypes [ param . type : match ( "^struct:(.+)$" ) or "" ] or scalarType ( key )
local stride = layoutStride [ param . type : match ( "^struct:(.+)$" ) or "" ] or size
assert ( stride > 0 , "SPIR-V span must have fixed-width storage" )
local arrayType = id ( )
instruction ( declarations , OP . TypeRuntimeArray , { arrayType , element } )
decorate ( arrayType , DECORATION . ArrayStride , { stride } )
local blockType = id ( )
instruction ( declarations , OP . TypeStruct , { blockType , arrayType } )
decorate ( blockType , DECORATION . Block )
instruction ( annotations , OP . MemberDecorate , { blockType , 0 , DECORATION . Offset , 0 } )
if readonlyBuffer then
instruction ( annotations , OP . MemberDecorate , { blockType , 0 , DECORATION . NonWritable } )
end
local pointer = pointerType ( STORAGE . StorageBuffer , blockType )
local variable = id ( )
instruction ( declarations , OP . Variable , { pointer , variable , STORAGE . StorageBuffer } )
name ( variable , param . name )
decorate ( variable , DECORATION . DescriptorSet , { set } )
decorate ( variable , DECORATION . Binding , { binding } )
if readonlyBuffer then
decorate ( variable , DECORATION . NonWritable )
end
bufferVars [ param . name ] = variable
bufferElement [ param . name ] = element
bufferPhysical [ param . name ] = key
end

for index , param in ipairs ( readonly ) do
declareBuffer ( param , 0 , index - 1 , true )
end
for index , param in ipairs ( writable ) do
declareBuffer ( param , 1 , index - 1 , false )
end

local globalPointer = pointerType ( STORAGE . Input , vec3uType )
local globalId = id ( )
instruction ( declarations , OP . Variable , { globalPointer , globalId , STORAGE . Input } )
name ( globalId , "global_invocation_id" )
decorate ( globalId , DECORATION . BuiltIn , { 28 } )


local workgroupCountId = id ( )
instruction ( declarations , OP . Variable , { globalPointer , workgroupCountId , STORAGE . Input } )
name ( workgroupCountId , "num_workgroups" )
decorate ( workgroupCountId , DECORATION . BuiltIn , { 24 } )

local workgroup = program . workgroup
local groupId = nil
local localId = nil
local sharedVars = { }
local sharedElements = { }
if workgroup ~= nil then
groupId = id ( )
instruction ( declarations , OP . Variable , { globalPointer , groupId , STORAGE . Input } )
name ( groupId , "workgroup_id" )
decorate ( groupId , DECORATION . BuiltIn , { 26 } )
localId = id ( )
instruction ( declarations , OP . Variable , { globalPointer , localId , STORAGE . Input } )
name ( localId , "local_invocation_id" )
decorate ( localId , DECORATION . BuiltIn , { 27 } )
for _ , scratch in ipairs ( ( workgroup ) . shared ) do
local element = scalarType ( scratch . element )
local arrayType = id ( )
instruction ( declarations , OP . TypeArray , { arrayType , element , constant ( u32Type , scratch . count ) } )
decorate ( arrayType , DECORATION . ArrayStride , { 4 } )
local variable = id ( )
instruction ( declarations , OP . Variable , {
pointerType ( STORAGE . Workgroup , arrayType ) ,
variable ,
STORAGE . Workgroup
} )
name ( variable , scratch . name )
sharedVars [ scratch . name ] = variable
sharedElements [ scratch . name ] = element
end
end

local fnVoid = functionType ( voidType , { } )
local fnU32U32 = functionType ( u32Type , { u32Type , u32Type } )
local fnF32F32 = functionType ( f32Type , { f32Type , f32Type } )
local fnFma = functionType ( f32Type , { f32Type , f32Type , f32Type } )
local fnF32 = functionType ( f32Type , { f32Type } )
local fnF32FromU32 = functionType ( f32Type , { u32Type } )
local fnU32FromF32 = functionType ( u32Type , { f32Type } )

local function safeUnsigned ( opcode , helperName ) 
local fn = id ( )
name ( fn , helperName )
instruction ( functions , OP . Function , { u32Type , fn , 0 , fnU32U32 } )
local left , right = id ( ) , id ( )
instruction ( functions , OP . FunctionParameter , { u32Type , left } )
instruction ( functions , OP . FunctionParameter , { u32Type , right } )
local first , zeroBlock , valueBlock , merge = id ( ) , id ( ) , id ( ) , id ( )
instruction ( functions , OP . Label , { first } )
local isZero = id ( )
instruction ( functions , OP . IEqual , { boolType , isZero , right , zeroU } )
instruction ( functions , OP . SelectionMerge , { merge , 0 } )
instruction ( functions , OP . BranchConditional , { isZero , zeroBlock , valueBlock } )
instruction ( functions , OP . Label , { zeroBlock } )
instruction ( functions , OP . ReturnValue , { zeroU } )
instruction ( functions , OP . Label , { valueBlock } )
local value = id ( )
instruction ( functions , opcode , { u32Type , value , left , right } )
instruction ( functions , OP . ReturnValue , { value } )
instruction ( functions , OP . Label , { merge } )
instruction ( functions , OP . ReturnValue , { zeroU } )
instruction ( functions , OP . FunctionEnd , { } )

return fn
end

local divFn = safeUnsigned ( OP . UDiv , "nupp_u32_div" )
local modFn = safeUnsigned ( OP . UMod , "nupp_u32_mod" )

local fmaFn = id ( )
name ( fmaFn , "nupp_f32_fma" )
instruction ( functions , OP . Function , { f32Type , fmaFn , 0 , fnFma } )
local fa , fb , fc = id ( ) , id ( ) , id ( )
instruction ( functions , OP . FunctionParameter , { f32Type , fa } )
instruction ( functions , OP . FunctionParameter , { f32Type , fb } )
instruction ( functions , OP . FunctionParameter , { f32Type , fc } )
local fmaLabel = id ( )
instruction ( functions , OP . Label , { fmaLabel } )
local fused = id ( )
instruction ( functions , OP . ExtInst , { f32Type , fused , ext , 50 , fa , fb , fc } )
local fusedNan = id ( )
instruction ( functions , OP . IsNan , { boolType , fusedNan , fused } )
local fusedOut = id ( )
instruction ( functions , OP . Select , { f32Type , fusedOut , fusedNan , canonicalNan ( ) , fused } )
instruction ( functions , OP . ReturnValue , { fusedOut } )
instruction ( functions , OP . FunctionEnd , { } )

local function correctedPair ( helperName , minimum ) 
local fn = id ( )
name ( fn , helperName )
instruction ( functions , OP . Function , { f32Type , fn , 0 , fnF32F32 } )
local left , right = id ( ) , id ( )
instruction ( functions , OP . FunctionParameter , { f32Type , left } )
instruction ( functions , OP . FunctionParameter , { f32Type , right } )
local label = id ( )
instruction ( functions , OP . Label , { label } )
local leftNan , rightNan , anyNan = id ( ) , id ( ) , id ( )
instruction ( functions , OP . IsNan , { boolType , leftNan , left } )
instruction ( functions , OP . IsNan , { boolType , rightNan , right } )
instruction ( functions , OP . LogicalOr , { boolType , anyNan , leftNan , rightNan } )
local equal , isZero = id ( ) , id ( )
instruction ( functions , OP . FOrdEqual , { boolType , equal , left , right } )
instruction ( functions , OP . FOrdEqual , { boolType , isZero , left , zeroF } )
local leftBits , rightBits , zeroBits = id ( ) , id ( ) , id ( )
instruction ( functions , OP . Bitcast , { u32Type , leftBits , left } )
instruction ( functions , OP . Bitcast , { u32Type , rightBits , right } )
instruction ( functions , minimum and OP . BitwiseOr or OP . BitwiseAnd , { u32Type , zeroBits , leftBits , rightBits , } )
local signedZero = id ( )
instruction ( functions , OP . Bitcast , { f32Type , signedZero , zeroBits } )
local equalValue = id ( )
instruction ( functions , OP . Select , { f32Type , equalValue , isZero , signedZero , left } )
local ordered = id ( )
instruction ( functions , minimum and OP . FOrdLessThan or OP . FOrdGreaterThan , { boolType , ordered , left , right , } )
local unequalValue = id ( )
instruction ( functions , OP . Select , { f32Type , unequalValue , ordered , left , right } )
local finiteValue = id ( )
instruction ( functions , OP . Select , { f32Type , finiteValue , equal , equalValue , unequalValue } )
local result = id ( )
instruction ( functions , OP . Select , { f32Type , result , anyNan , canonicalNan ( ) , finiteValue } )
instruction ( functions , OP . ReturnValue , { result } )
instruction ( functions , OP . FunctionEnd , { } )

return fn
end

local minFn = correctedPair ( "nupp_f32_min" , true )
local maxFn = correctedPair ( "nupp_f32_max" , false )

local halfToFloatFn = id ( )
name ( halfToFloatFn , "nupp_f16_to_f32" )
instruction ( functions , OP . Function , { f32Type , halfToFloatFn , 0 , fnF32FromU32 } )
local halfBits = id ( )
instruction ( functions , OP . FunctionParameter , { u32Type , halfBits } )
local halfLabel = id ( )
instruction ( functions , OP . Label , { halfLabel } )
local unpacked = id ( )
instruction ( functions , OP . ExtInst , { vec2fType , unpacked , ext , 62 , halfBits } )
local unpackedLow = id ( )
instruction ( functions , OP . CompositeExtract , { f32Type , unpackedLow , unpacked , 0 } )
local unpackedNan = id ( )
instruction ( functions , OP . IsNan , { boolType , unpackedNan , unpackedLow } )
local unpackedOut = id ( )
instruction ( functions , OP . Select , { f32Type , unpackedOut , unpackedNan , canonicalNan ( ) , unpackedLow } )
instruction ( functions , OP . ReturnValue , { unpackedOut } )
instruction ( functions , OP . FunctionEnd , { } )

local floatToHalfFn = id ( )
name ( floatToHalfFn , "nupp_f32_to_f16" )
instruction ( functions , OP . Function , { u32Type , floatToHalfFn , 0 , fnU32FromF32 } )
local floatValue = id ( )
instruction ( functions , OP . FunctionParameter , { f32Type , floatValue } )
local packLabel = id ( )
instruction ( functions , OP . Label , { packLabel } )
local valueNan = id ( )
instruction ( functions , OP . IsNan , { boolType , valueNan , floatValue } )
local canonicalValue = id ( )
instruction ( functions , OP . Select , { f32Type , canonicalValue , valueNan , canonicalNan ( ) , floatValue } )
local pair = id ( )
instruction ( functions , OP . CompositeConstruct , { vec2fType , pair , canonicalValue , canonicalValue } )
local packed = id ( )
instruction ( functions , OP . ExtInst , { u32Type , packed , ext , 58 , pair } )
local lowMask = constant ( u32Type , 65535 )
local packedLow = id ( )
instruction ( functions , OP . BitwiseAnd , { u32Type , packedLow , packed , lowMask } )
instruction ( functions , OP . ReturnValue , { packedLow } )
instruction ( functions , OP . FunctionEnd , { } )

local bf16ToFloatFn = id ( )
name ( bf16ToFloatFn , "nupp_bf16_to_f32" )
instruction ( functions , OP . Function , { f32Type , bf16ToFloatFn , 0 , fnF32FromU32 } )
local bf16Bits = id ( )
instruction ( functions , OP . FunctionParameter , { u32Type , bf16Bits } )
local bf16LoadLabel = id ( )
instruction ( functions , OP . Label , { bf16LoadLabel } )
local bf16Low = id ( )
instruction ( functions , OP . BitwiseAnd , { u32Type , bf16Low , bf16Bits , lowMask } )
local bf16Wide = id ( )
instruction ( functions , OP . ShiftLeftLogical , { u32Type , bf16Wide , bf16Low , constant ( u32Type , 16 ) } )
local bf16Value = id ( )
instruction ( functions , OP . Bitcast , { f32Type , bf16Value , bf16Wide } )
local bf16Nan = id ( )
instruction ( functions , OP . IsNan , { boolType , bf16Nan , bf16Value } )
local bf16Out = id ( )
instruction ( functions , OP . Select , { f32Type , bf16Out , bf16Nan , canonicalNan ( ) , bf16Value } )
instruction ( functions , OP . ReturnValue , { bf16Out } )
instruction ( functions , OP . FunctionEnd , { } )

local floatToBf16Fn = id ( )
name ( floatToBf16Fn , "nupp_f32_to_bf16" )
instruction ( functions , OP . Function , { u32Type , floatToBf16Fn , 0 , fnU32FromF32 } )
local bf16Input = id ( )
instruction ( functions , OP . FunctionParameter , { f32Type , bf16Input } )
local bf16StoreLabel = id ( )
instruction ( functions , OP . Label , { bf16StoreLabel } )
local bf16InputNan = id ( )
instruction ( functions , OP . IsNan , { boolType , bf16InputNan , bf16Input } )
local bf16InputBits = id ( )
instruction ( functions , OP . Bitcast , { u32Type , bf16InputBits , bf16Input } )
local bf16Upper = id ( )
instruction ( functions , OP . ShiftRightLogical , { u32Type , bf16Upper , bf16InputBits , constant ( u32Type , 16 ) } )
local bf16Lsb = id ( )
instruction ( functions , OP . BitwiseAnd , { u32Type , bf16Lsb , bf16Upper , constant ( u32Type , 1 ) } )
local bf16Bias = id ( )
instruction ( functions , OP . IAdd , { u32Type , bf16Bias , constant ( u32Type , 32767 ) , bf16Lsb } )
local bf16Rounded = id ( )
instruction ( functions , OP . IAdd , { u32Type , bf16Rounded , bf16InputBits , bf16Bias } )
local bf16Stored = id ( )
instruction ( functions , OP . ShiftRightLogical , { u32Type , bf16Stored , bf16Rounded , constant ( u32Type , 16 ) } )
local bf16Canonical = constant ( u32Type , 32704 )
local bf16Result = id ( )
instruction ( functions , OP . Select , { u32Type , bf16Result , bf16InputNan , bf16Canonical , bf16Stored } )
instruction ( functions , OP . ReturnValue , { bf16Result } )
instruction ( functions , OP . FunctionEnd , { } )

local sqrtFn = id ( )
name ( sqrtFn , "nupp_f32_sqrt" )
instruction ( functions , OP . Function , { f32Type , sqrtFn , 0 , fnF32 } )
local sqrtValue = id ( )
instruction ( functions , OP . FunctionParameter , { f32Type , sqrtValue } )
local sqrtLabel = id ( )
instruction ( functions , OP . Label , { sqrtLabel } )
local sqrtOut = id ( )
instruction ( functions , OP . ExtInst , { f32Type , sqrtOut , ext , 31 , sqrtValue } )
instruction ( functions , OP . ReturnValue , { sqrtOut } )
instruction ( functions , OP . FunctionEnd , { } )




local expFn = id ( )
name ( expFn , "nupp_f32_exp" )
instruction ( functions , OP . Function , { f32Type , expFn , 0 , fnF32 } )
local expValue = id ( )
instruction ( functions , OP . FunctionParameter , { f32Type , expValue } )
local expLabel = id ( )
instruction ( functions , OP . Label , { expLabel } )
local expNan = id ( )
instruction ( functions , OP . IsNan , { boolType , expNan , expValue } )
local expCanonical = id ( )
instruction ( functions , OP . Select , { f32Type , expCanonical , expNan , canonicalNan ( ) , expValue } )
local low = constant ( f32Type , f32Bits ( -104 ) )
local high = constant ( f32Type , f32Bits ( 88 ) )
local below = id ( )
instruction ( functions , OP . FOrdLessThan , { boolType , below , expCanonical , low } )
local clampedLow = id ( )
instruction ( functions , OP . Select , { f32Type , clampedLow , below , low , expCanonical } )
local above = id ( )
instruction ( functions , OP . FOrdGreaterThan , { boolType , above , clampedLow , high } )
local bounded = id ( )
instruction ( functions , OP . Select , { f32Type , bounded , above , high , clampedLow } )
local scaled = id ( )
instruction ( functions , OP . FMul , { f32Type , scaled , bounded , constant ( f32Type , f32Bits ( 0.0078125 ) ) } )
if program . fpContract ~= true then
decorate ( scaled , DECORATION . NoContraction )
end
local polynomial = constant ( f32Type , f32Bits ( 0.0000000020876757 ) )
for _ , coefficient in ipairs ( {
0.000000025052108 ,
0.00000027557319 ,
0.0000027557319 ,
0.000024801587 ,
0.0001984127 ,
0.0013888889 ,
0.0083333333 ,
0.041666667 ,
0.16666667 ,
0.5 ,
1 ,
1 ,
} ) do
local nextValue = id ( )
instruction ( functions , OP . FunctionCall , {
f32Type ,
nextValue ,
fmaFn ,
polynomial ,
scaled ,
constant ( f32Type , f32Bits ( coefficient ) ) ,
} )
polynomial = nextValue
end
for _ = 1 , 7 do
local squared = id ( )
instruction ( functions , OP . FMul , { f32Type , squared , polynomial , polynomial } )
if program . fpContract ~= true then
decorate ( squared , DECORATION . NoContraction )
end
polynomial = squared
end
instruction ( functions , OP . ReturnValue , { polynomial } )
instruction ( functions , OP . FunctionEnd , { } )

local main = id ( )
local entryOperands = { 5 , main }
push ( entryOperands , stringWords ( program . symbol .. "_gpu" ) )
entryOperands [ # entryOperands + 1 ] = globalId
entryOperands [ # entryOperands + 1 ] = workgroupCountId
if groupId ~= nil and localId ~= nil then
entryOperands [ # entryOperands + 1 ] = groupId
entryOperands [ # entryOperands + 1 ] = localId
end
instruction ( entry , OP . EntryPoint , entryOperands )
instruction ( entry , OP . ExecutionMode , { main , 17 , threads , 1 , 1 } )
name ( main , program . symbol .. "_gpu" )

instruction ( functions , OP . Function , { voidType , main , 0 , fnVoid } )
local mainLabel = id ( )
instruction ( functions , OP . Label , { mainLabel } )

local localPointers = { }
local forCounters = { }
local forDone = { }
local references = { }




local readonlyReferences = { }

local readonlyReferenceValues = { }

local function valueType ( type_ ) 
if type_ : match ( "^ref:" ) then
error ( "SPIR-V references do not have value types" , 0 )
end
return scalarType ( type_ == "f64" and "f32" or type_ )
end

local function collect ( statements ) 
for _ , statement in ipairs ( statements ) do
if statement . op == "let" and not statement . type : match ( "^ref:" ) then
local pointer = id ( )
localPointers [ statement . uniqueName ] = pointer
instruction ( functions , OP . Variable , {
pointerType ( STORAGE . Function , valueType ( statement . type ) ) ,
pointer ,
STORAGE . Function
} )
name ( pointer , statement . uniqueName )
elseif statement . op == "fornum" then
local binding , counter = id ( ) , id ( )
localPointers [ statement . binding . uniqueName ] = binding
forCounters [ statement . binding . uniqueName ] = counter
local done = id ( )
forDone [ statement . binding . uniqueName ] = done
instruction ( functions , OP . Variable , { pointerType ( STORAGE . Function , boolType ) , done , STORAGE . Function } )
for _ , pointer in ipairs ( { binding , counter } ) do
instruction ( functions , OP . Variable , {
pointerType ( STORAGE . Function , i32Type ) ,
pointer ,
STORAGE . Function
} )
end
name ( binding , statement . binding . uniqueName )
collect ( statement . body )
elseif statement . op == "while"
or statement . op == "repeat"
or statement . op == "block"
or statement . op == "phase"
then
collect ( statement . body )
elseif statement . op == "if" then
for _ , clause in ipairs ( statement . clauses ) do
collect ( clause . body )
end
collect ( statement . elseBody or { } )
end
end
end

local loop = program . loop
local scalarStatements = loop ~= nil and ( loop ) . statements
or ( workgroup ) . statements
if workgroup ~= nil then
collect ( ( workgroup ) . prelude )
end
collect ( scalarStatements )





local loadedGlobal = id ( )
instruction ( functions , OP . Load , { vec3uType , loadedGlobal , globalId } )
local globalColumn , globalRow = id ( ) , id ( )
instruction ( functions , OP . CompositeExtract , { u32Type , globalColumn , loadedGlobal , 0 } )
instruction ( functions , OP . CompositeExtract , { u32Type , globalRow , loadedGlobal , 1 } )
local loadedWorkgroupCount = id ( )
instruction ( functions , OP . Load , { vec3uType , loadedWorkgroupCount , workgroupCountId } )
local rowGroups = id ( )
instruction ( functions , OP . CompositeExtract , { u32Type , rowGroups , loadedWorkgroupCount , 0 } )
local threadsU = constant ( u32Type , threads )
local rowWidth = id ( )
instruction ( functions , OP . IMul , { u32Type , rowWidth , rowGroups , threadsU } )
local rowStart = id ( )
instruction ( functions , OP . IMul , { u32Type , rowStart , globalRow , rowWidth } )
local dispatch = id ( )
instruction ( functions , OP . IAdd , { u32Type , dispatch , rowStart , globalColumn } )
local groupIndex = nil
local localIndex = nil
if workgroup ~= nil then
local loadedGroup = id ( )
instruction ( functions , OP . Load , { vec3uType , loadedGroup , groupId } )
local groupColumn , groupRow = id ( ) , id ( )
instruction ( functions , OP . CompositeExtract , { u32Type , groupColumn , loadedGroup , 0 } )
instruction ( functions , OP . CompositeExtract , { u32Type , groupRow , loadedGroup , 1 } )
local groupRowStart = id ( )
instruction ( functions , OP . IMul , { u32Type , groupRowStart , groupRow , rowGroups } )
groupIndex = id ( )
instruction ( functions , OP . IAdd , { u32Type , groupIndex , groupRowStart , groupColumn } )
local loadedLocal = id ( )
instruction ( functions , OP . Load , { vec3uType , loadedLocal , localId } )
localIndex = id ( )
instruction ( functions , OP . CompositeExtract , { u32Type , localIndex , loadedLocal , 0 } )
end

local uniformValues = { }
local uniformTypes = { }

local function uniform ( name_ , typeId ) 
local existing = uniformValues [ name_ ]
if existing ~= nil then
assert ( uniformTypes [ name_ ] == typeId , "GPU uniform has inconsistent scalar types" )
return existing
end
local member = constant ( u32Type , uniformIndex [ name_ ] )
local pointer = id ( )
instruction ( functions , OP . AccessChain , { pointerType ( STORAGE . Uniform , typeId ) , pointer , uniformsVar , member } )
local loaded = id ( )
instruction ( functions , OP . Load , { typeId , loaded , pointer } )
uniformValues [ name_ ] = loaded
uniformTypes [ name_ ] = typeId

return loaded
end





uniform ( "\0count" , u32Type )
for _ , param in ipairs ( spans ) do
uniform ( param . name .. "_count" , u32Type )
end
for _ , param in ipairs ( spans ) do
uniform ( param . name .. "_offset" , u32Type )
end
for _ , param in ipairs ( uniforms ) do
uniform ( param . name , scalarType ( param . type ) )
end









local count = uniform ( "\0count" , u32Type )
local inRange = id ( )
if workgroup == nil then
local countRow , countColumn = id ( ) , id ( )
instruction ( functions , OP . UDiv , { u32Type , countRow , count , rowWidth } )
instruction ( functions , OP . UMod , { u32Type , countColumn , count , rowWidth } )
local earlierRow , sameRow , earlierColumn , tail = id ( ) , id ( ) , id ( ) , id ( )
instruction ( functions , OP . ULessThan , { boolType , earlierRow , globalRow , countRow } )
instruction ( functions , OP . IEqual , { boolType , sameRow , globalRow , countRow } )
instruction ( functions , OP . ULessThan , { boolType , earlierColumn , globalColumn , countColumn } )
instruction ( functions , OP . LogicalAnd , { boolType , tail , sameRow , earlierColumn } )
instruction ( functions , OP . LogicalOr , { boolType , inRange , earlierRow , tail } )
else
local whole = id ( )
instruction ( functions , OP . UDiv , { u32Type , whole , count , threadsU } )
instruction ( functions , OP . ULessThan , { boolType , inRange , groupIndex , whole } )
end
local bodyLabel , returnLabel = id ( ) , id ( )
local entryMerge = id ( )
instruction ( functions , OP . SelectionMerge , { entryMerge , 0 } )
instruction ( functions , OP . BranchConditional , { inRange , bodyLabel , returnLabel } )
instruction ( functions , OP . Label , { returnLabel } )
instruction ( functions , OP . Return , { } )
instruction ( functions , OP . Label , { bodyLabel } )

local currentBreak = { }
local currentContinue = { }
local terminated = false
local expression

local function bufferPointer ( value ) 
local indexId = dispatch
if value . cursor ~= nil then
if value . cursorOffset ~= nil then


error ( "SPIR-V subset does not emit a displaced cursor access" , 0 )
end
local pointer = assert ( localPointers [ value . cursorUniqueName ] )
indexId = id ( )
instruction ( functions , OP . Load , { u32Type , indexId , pointer } )
end
local physicalIndex = id ( )
instruction ( functions , OP . IAdd , { u32Type , physicalIndex , uniform ( value . span .. "_offset" , u32Type ) , indexId , } )
local element = assert ( bufferElement [ value . span ] )
local pointer = id ( )
instruction ( functions , OP . AccessChain , {
pointerType ( STORAGE . StorageBuffer , element ) ,
pointer ,
assert ( bufferVars [ value . span ] ) ,
zeroU ,
physicalIndex
} )

return pointer , element
end

expression = function ( value ) 
local op = value . op
if op == "local" then
if value . type : match ( "^ref:" ) then
return assert ( references [ value . uniqueName or value . name ] ) , layoutTypes [ value . type : match ( "^ref:(.+)$" ) ]
or 0
end
local pointer = assert ( localPointers [ value . uniqueName or value . name ] )
local typeId = valueType ( value . type )
local loaded = id ( )
instruction ( functions , OP . Load , { typeId , loaded , pointer } )
return loaded , typeId
elseif op == "uniform" then
local typeId = valueType ( value . type )
return uniform ( value . name , typeId ) , typeId
elseif op == "loop_index" then
local result = id ( )
instruction ( functions , OP . IAdd , { u32Type , result , dispatch , oneU } )
return result , u32Type
elseif op == "workgroup_index" then
return groupIndex , u32Type
elseif op == "local_index" then
return localIndex , u32Type
elseif op == "shared_load" then
local indexId = expression ( value . index )
local element = assert ( sharedElements [ value . shared ] )
local pointer = id ( )
instruction ( functions , OP . AccessChain , {
pointerType ( STORAGE . Workgroup , element ) ,
pointer ,
assert ( sharedVars [ value . shared ] ) ,
indexId
} )
local loaded = id ( )
instruction ( functions , OP . Load , { element , loaded , pointer } )
return loaded , element
elseif op == "span_count" then
return uniform ( value . span .. "_count" , u32Type ) , u32Type
elseif op == "element_ref" then
return bufferPointer ( value )
elseif op == "load" then
local pointer , storedType = bufferPointer ( value )
local loaded = id ( )
instruction ( functions , OP . Load , { storedType , loaded , pointer } )
local expected = valueType ( value . type )
if storedType ~= expected then
local converted = id ( )
local conversion = ( bufferPhysical [ value . span ] ) : sub ( 1 , 1 ) == "i" and OP . SConvert
or OP . UConvert
instruction ( functions , conversion , { expected , converted , loaded } )
return converted , expected
end
return loaded , storedType
elseif op == "field_load" then
local fieldIndex = assert ( assert ( layoutFields [ value . layout ] ) [ value . field ] )
local storedKey = physical ( value . type , value . sourceType )
local storedType = scalarType ( storedKey )
local referenceName = value . object . op == "local" and ( value . object . uniqueName or value . object . name ) or nil
local loaded
if referenceName ~= nil and readonlyReferences [ referenceName ] == true then
local whole = readonlyReferenceValues [ referenceName ]
if whole == nil then
local object , objectType = expression ( value . object )
whole = id ( )
instruction ( functions , OP . Load , { objectType , whole , object } )
readonlyReferenceValues [ referenceName ] = whole
end
loaded = id ( )
instruction ( functions , OP . CompositeExtract , { storedType , loaded , whole , fieldIndex } )
else
local object = expression ( value . object )
local member = constant ( u32Type , fieldIndex )
local pointer = id ( )
instruction ( functions , OP . AccessChain , {
pointerType ( STORAGE . StorageBuffer , storedType ) ,
pointer ,
object ,
member
} )
loaded = id ( )
instruction ( functions , OP . Load , { storedType , loaded , pointer } )
end
local expected = valueType ( value . type )
if storedType ~= expected then
local converted = id ( )
instruction ( functions , storedKey : sub ( 1 , 1 ) == "i" and OP . SConvert or OP . UConvert , {
expected ,
converted ,
loaded
} )
return converted , expected
end
return loaded , storedType
elseif op == "constant" then
return constant ( f32Type , f32Bits ( assert ( tonumber ( value . value ) ) ) ) , f32Type
elseif op == "constant_i32" then
local typeId = valueType ( value . type )
local numeric = assert ( tonumber ( value . value ) )
if numeric < 0 then
numeric = numeric + 4294967296
end
return constant ( typeId , numeric ) , typeId
elseif op == "bool" then
return value . value and trueId or falseId , boolType
elseif op == "int_to_f64" then


local input , inputType = expression ( value . value )
if inputType == f32Type then
return input , f32Type
end
assert (
inputType == i32Type or inputType == u32Type ,
"GPU integer widening source must already be fixed-width"
)
local converted = id ( )
instruction ( functions , inputType == i32Type and OP . ConvertSToF or OP . ConvertUToF , {
f32Type ,
converted ,
input
} )
return converted , f32Type
elseif op == "widen_f32_f64" or op == "narrow_f64_f32" then


return expression ( value . value )
elseif op == "numeric_cast" or op == "store_cast" then


local operand = value . value


if ( value . type == "u32" or value . type == "i32" )
and operand . op == "int_to_f64"
and ( operand . value . type == "u32" or operand . value . type == "i32" )
then
operand = operand . value
end
local input , inputType = expression ( operand )
local outputType = valueType ( value . type )
if inputType == outputType then
return input , outputType
end
local converted = id ( )
local opcode = outputType == u32Type and ( inputType == f32Type and OP . ConvertFToU or OP . Bitcast )
or outputType == i32Type and ( inputType == f32Type and OP . ConvertFToS or OP . Bitcast )
or outputType == f32Type and ( inputType == i32Type and OP . ConvertSToF or OP . ConvertUToF )
or OP . Bitcast
instruction ( functions , opcode , { outputType , converted , input } )
return converted , outputType
elseif op == "u32_div" or op == "u32_mod" then
local left = expression ( value . left )
local right = expression ( value . right )
local result = id ( )
instruction ( functions , OP . FunctionCall , { u32Type , result , op == "u32_div" and divFn or modFn , left , right } )
return result , u32Type
elseif op == "f32_fma" then
local a = expression ( value . args [ 1 ] )
local b = expression ( value . args [ 2 ] )
local c = expression ( value . args [ 3 ] )
local result = id ( )
instruction ( functions , OP . FunctionCall , { f32Type , result , fmaFn , a , b , c } )
return result , f32Type
elseif op == "f32_min" or op == "f32_max" then
local left = expression ( value . left )
local right = expression ( value . right )
local result = id ( )
instruction ( functions , OP . FunctionCall , { f32Type , result , op == "f32_min" and minFn or maxFn , left , right , } )
return result , f32Type
elseif op == "f16_to_f32"
or op == "f32_to_f16"
or op == "bf16_to_f32"
or op == "f32_to_bf16"
or op == "f32_sqrt"
or op == "f32_exp"
then
local input = expression ( value . value )
local resultType = ( op == "f32_to_f16" or op == "f32_to_bf16" ) and u32Type or f32Type
if op == "f32_exp" and program . fpTranscendentals == true then
local result = id ( )
instruction ( functions , OP . ExtInst , { f32Type , result , ext , 27 , input } )
return result , f32Type
end
local helper = op == "f16_to_f32" and halfToFloatFn
or op == "f32_to_f16" and floatToHalfFn
or op == "bf16_to_f32" and bf16ToFloatFn
or op == "f32_to_bf16" and floatToBf16Fn
or op == "f32_exp" and expFn
or sqrtFn
local result = id ( )
instruction ( functions , OP . FunctionCall , { resultType , result , helper , input } )
return result , resultType
elseif op == "neg" or op == "not" or op == "bnot" or op == "u32_not" then
local input , typeId = expression ( value . value )
local result = id ( )
if op == "not" then
instruction ( functions , OP . LogicalNot , { boolType , result , input } )
return result , boolType
elseif op == "neg" then
if typeId == f32Type then
instruction ( functions , OP . FNegate , { typeId , result , input } )
else
instruction ( functions , OP . ISub , { typeId , result , constant ( typeId , 0 ) , input } )
end
else
local all = constant ( typeId , 4294967295 )
instruction ( functions , OP . BitwiseXor , { typeId , result , input , all } )
end
return result , typeId
end

local left , leftType = expression ( value . left )
local right , rightType = expression ( value . right )
local resultType = valueType ( value . type )
local opcode = (
{
f32_add = OP . FAdd ,
f32_sub = OP . FSub ,
f32_mul = OP . FMul ,
f32_div = OP . FDiv ,
i32_add = OP . IAdd ,
i32_sub = OP . ISub ,
i32_mul = OP . IMul ,
u32_add = OP . IAdd ,
u32_sub = OP . ISub ,
u32_mul = OP . IMul ,
u32_and = OP . BitwiseAnd ,
u32_or = OP . BitwiseOr ,
u32_xor = OP . BitwiseXor ,
u32_shl = OP . ShiftLeftLogical ,
u32_shr = OP . ShiftRightLogical ,
add = leftType == f32Type and OP . FAdd or OP . IAdd ,
sub = leftType == f32Type and OP . FSub or OP . ISub ,
mul = leftType == f32Type and OP . FMul or OP . IMul ,
div = leftType == f32Type and OP . FDiv or OP . UDiv ,
mod = OP . UMod ,
band = OP . BitwiseAnd ,
bor = OP . BitwiseOr ,
bxor = OP . BitwiseXor ,
lshift = OP . ShiftLeftLogical ,
rshift = OP . ShiftRightLogical ,
arshift = OP . ShiftRightArithmetic ,
[ "and" ] = OP . LogicalAnd ,
[ "or" ] = OP . LogicalOr ,
}
) [ op ]
if not opcode then
local floatCompare = {
eq = OP . FOrdEqual ,
ne = OP . FOrdNotEqual ,
lt = OP . FOrdLessThan ,
le = OP . FOrdLessThanEqual ,
gt = OP . FOrdGreaterThan ,
ge = OP . FOrdGreaterThanEqual
}
local unsignedCompare = {
eq = OP . IEqual ,
ne = OP . INotEqual ,
lt = OP . ULessThan ,
le = OP . ULessThanEqual ,
gt = OP . UGreaterThan ,
ge = OP . UGreaterThanEqual
}
local signedCompare = {
eq = OP . IEqual ,
ne = OP . INotEqual ,
lt = OP . SLessThan ,
le = OP . SLessThanEqual ,
gt = OP . SGreaterThan ,
ge = OP . SGreaterThanEqual
}
opcode = (
leftType == f32Type and floatCompare or leftType == i32Type and signedCompare or unsignedCompare
) [ op ]
end
assert ( opcode ~= nil , "SPIR-V subset does not emit expression " .. tostring ( op ) )
if opcode == OP . ShiftLeftLogical or opcode == OP . ShiftRightLogical or opcode == OP . ShiftRightArithmetic then
local masked = id ( )
instruction ( functions , OP . BitwiseAnd , { rightType , masked , right , constant ( rightType , 31 ) } )
right = masked
end
local result = id ( )
instruction ( functions , opcode , { resultType , result , left , right } )
if program . fpContract ~= true and ( opcode == OP . FAdd or opcode == OP . FSub or opcode == OP . FMul ) then
decorate ( result , DECORATION . NoContraction )
end

return result , resultType
end

local function workgroupBarrier ( ) 



if workgroup ~= nil and # ( workgroup ) . shared > 0 then
instruction ( functions , OP . ControlBarrier , {
constant ( u32Type , 2 ) ,
constant ( u32Type , 2 ) ,
constant ( u32Type , 264 )
} )
end
end

local statements
statements = function ( values ) 
for _ , statement in ipairs ( values ) do
if terminated then
return
end
local op = statement . op
if op == "let" then
if statement . type : match ( "^ref:" ) then
references [ statement . uniqueName ] = bufferPointer ( statement . value )
readonlyReferences [ statement . uniqueName ] = statement . value . mutable ~= true
readonlyReferenceValues [ statement . uniqueName ] = nil
else
local value = expression ( statement . value )
instruction ( functions , OP . Store , { assert ( localPointers [ statement . uniqueName ] ) , value } )
end
elseif op == "assign" then
assert ( # statement . values == 1 , "SPIR-V subset does not emit parallel assignment" )
local assignment = statement . values [ 1 ]
local value = expression ( assignment . value )
if assignment . target . kind == "local" then
instruction ( functions , OP . Store , {
assert ( localPointers [ assignment . target . uniqueName or assignment . target . name ] ) ,
value
} )
elseif assignment . target . kind == "field" then
local object = expression ( assignment . target . object )
local fieldIndex = assert ( assert ( layoutFields [ assignment . target . layout ] ) [ assignment . target . field ] )
local storedKey = physical ( assignment . target . type , assignment . target . sourceType )
local storedType = scalarType ( storedKey )
local member = constant ( u32Type , fieldIndex )
local pointer = id ( )
instruction ( functions , OP . AccessChain , {
pointerType ( STORAGE . StorageBuffer , storedType ) ,
pointer ,
object ,
member
} )
local expected = valueType ( assignment . target . type )
if expected ~= storedType then
local narrowed = id ( )
instruction ( functions , storedKey : sub ( 1 , 1 ) == "i" and OP . SConvert or OP . UConvert , {
storedType ,
narrowed ,
value
} )
value = narrowed
end
instruction ( functions , OP . Store , { pointer , value } )
else
error ( "SPIR-V subset does not emit assignment target " .. tostring ( assignment . target . kind ) , 0 )
end
elseif op == "store" then
local pointer , storedType = bufferPointer ( statement )
local value , valueTypeId = expression ( statement . value )
if storedType ~= valueTypeId then
local narrowed = id ( )
local storedKey = bufferPhysical [ statement . span ]
instruction ( functions , storedKey : sub ( 1 , 1 ) == "i" and OP . SConvert or OP . UConvert , {
storedType ,
narrowed ,
value
} )
value = narrowed
end
instruction ( functions , OP . Store , { pointer , value } )
elseif op == "shared_store" then
local indexId = expression ( statement . index )
local element = assert ( sharedElements [ statement . shared ] )
local pointer = id ( )
instruction ( functions , OP . AccessChain , {
pointerType ( STORAGE . Workgroup , element ) ,
pointer ,
assert ( sharedVars [ statement . shared ] ) ,
indexId
} )
local value = expression ( statement . value )
instruction ( functions , OP . Store , { pointer , value } )
elseif op == "phase" then
readonlyReferenceValues = { }
statements ( statement . body )
if not terminated then
workgroupBarrier ( )
end
readonlyReferenceValues = { }
elseif op == "if" then
readonlyReferenceValues = { }
local merge = id ( )
for index , clause in ipairs ( statement . clauses ) do
local yes = id ( )
local no = id ( )
local condition = expression ( clause . condition )
instruction ( functions , OP . SelectionMerge , { merge , 0 } )
instruction ( functions , OP . BranchConditional , { condition , yes , no } )
instruction ( functions , OP . Label , { yes } )
terminated = false
statements ( clause . body )
if not terminated then
instruction ( functions , OP . Branch , { merge } )
end
instruction ( functions , OP . Label , { no } )
terminated = false
if index == # statement . clauses then
statements ( statement . elseBody or { } )
if not terminated then
instruction ( functions , OP . Branch , { merge } )
end
end
end
instruction ( functions , OP . Label , { merge } )
terminated = false
readonlyReferenceValues = { }
elseif op == "fornum" then
readonlyReferenceValues = { }
local binding = assert ( localPointers [ statement . binding . uniqueName ] )
local counter = assert ( forCounters [ statement . binding . uniqueName ] )
local completion = assert ( forDone [ statement . binding . uniqueName ] )
local first , firstType = expression ( statement . from )
local last , lastType = expression ( statement . to )
assert ( firstType == i32Type and lastType == i32Type , "GPU counted loop bounds must be int32" )
instruction ( functions , OP . Store , { counter , first } )
local header , body , continuing , merge = id ( ) , id ( ) , id ( ) , id ( )
instruction ( functions , OP . Branch , { header } )
instruction ( functions , OP . Label , { header } )
local current , inside = id ( ) , id ( )
instruction ( functions , OP . Load , { i32Type , current , counter } )
instruction ( functions , OP . SLessThanEqual , { boolType , inside , current , last } )
instruction ( functions , OP . LoopMerge , { merge , continuing , 0 } )
instruction ( functions , OP . BranchConditional , { inside , body , merge } )
instruction ( functions , OP . Label , { body } )
instruction ( functions , OP . Store , { binding , current } )
currentBreak [ # currentBreak + 1 ] = merge
currentContinue [ # currentContinue + 1 ] = continuing
terminated = false
statements ( statement . body )
currentBreak [ # currentBreak ] = nil
currentContinue [ # currentContinue ] = nil
if not terminated then
instruction ( functions , OP . Branch , { continuing } )
end
instruction ( functions , OP . Label , { continuing } )
local done , step , next = id ( ) , id ( ) , id ( )
instruction ( functions , OP . IEqual , { boolType , done , current , last } )
instruction ( functions , OP . Store , { completion , done } )




instruction ( functions , OP . Select , { i32Type , step , done , constant ( i32Type , 0 ) , constant ( i32Type , 1 ) } )
instruction ( functions , OP . IAdd , { i32Type , next , current , step } )
instruction ( functions , OP . Store , { counter , next } )


local completed = id ( )
instruction ( functions , OP . Load , { boolType , completed , completion } )
instruction ( functions , OP . BranchConditional , { completed , merge , header } )
instruction ( functions , OP . Label , { merge } )
terminated = false
readonlyReferenceValues = { }
elseif op == "while" then
if statement . conditionBody ~= nil then
error ( "statementful loop conditions are not admitted by this GPU profile" , 0 )
end
readonlyReferenceValues = { }
local header , body , continuing , merge = id ( ) , id ( ) , id ( ) , id ( )
instruction ( functions , OP . Branch , { header } )
instruction ( functions , OP . Label , { header } )
local condition = expression ( statement . condition )
instruction ( functions , OP . LoopMerge , { merge , continuing , 0 } )
instruction ( functions , OP . BranchConditional , { condition , body , merge } )
instruction ( functions , OP . Label , { body } )
currentBreak [ # currentBreak + 1 ] = merge
currentContinue [ # currentContinue + 1 ] = continuing
terminated = false
statements ( statement . body )
currentBreak [ # currentBreak ] = nil
currentContinue [ # currentContinue ] = nil
if not terminated then
instruction ( functions , OP . Branch , { continuing } )
end
instruction ( functions , OP . Label , { continuing } )
instruction ( functions , OP . Branch , { header } )
instruction ( functions , OP . Label , { merge } )
terminated = false
readonlyReferenceValues = { }
elseif op == "repeat" then
if statement . conditionBody ~= nil then
error ( "statementful loop conditions are not admitted by this GPU profile" , 0 )
end
readonlyReferenceValues = { }
local header , body , continuing , merge = id ( ) , id ( ) , id ( ) , id ( )
instruction ( functions , OP . Branch , { header } )
instruction ( functions , OP . Label , { header } )
instruction ( functions , OP . LoopMerge , { merge , continuing , 0 } )
instruction ( functions , OP . Branch , { body } )
instruction ( functions , OP . Label , { body } )
currentBreak [ # currentBreak + 1 ] = merge
currentContinue [ # currentContinue + 1 ] = continuing
terminated = false
statements ( statement . body )
currentBreak [ # currentBreak ] = nil
currentContinue [ # currentContinue ] = nil
if not terminated then
instruction ( functions , OP . Branch , { continuing } )
end
instruction ( functions , OP . Label , { continuing } )
local condition = expression ( statement . condition )
instruction ( functions , OP . BranchConditional , { condition , merge , header } )
instruction ( functions , OP . Label , { merge } )
terminated = false
readonlyReferenceValues = { }
elseif op == "break" then
instruction ( functions , OP . Branch , { assert ( currentBreak [ # currentBreak ] ) } )
terminated = true
elseif op == "continue" then
instruction ( functions , OP . Branch , { assert ( currentContinue [ # currentContinue ] ) } )
terminated = true
elseif op == "block" then
statements ( statement . body )
else
error ( "SPIR-V subset does not emit statement " .. tostring ( op ) , 0 )
end
end
end
if workgroup ~= nil then
statements ( ( workgroup ) . prelude )
for _ , scratch in ipairs ( ( workgroup ) . shared ) do
local element = assert ( sharedElements [ scratch . name ] )
local pointer = id ( )
instruction ( functions , OP . AccessChain , {
pointerType ( STORAGE . Workgroup , element ) ,
pointer ,
assert ( sharedVars [ scratch . name ] ) ,
localIndex
} )
local initial = expression ( scratch . initial )
instruction ( functions , OP . Store , { pointer , initial } )
end
workgroupBarrier ( )
end
statements ( scalarStatements )
if not terminated then
instruction ( functions , OP . Branch , { entryMerge } )
end
instruction ( functions , OP . Label , { entryMerge } )
instruction ( functions , OP . Return , { } )
instruction ( functions , OP . FunctionEnd , { } )

local words = { 119734787 , 66304 , 0 , nextId , 0 }
push ( words , capabilities )
push ( words , entry )
push ( words , debug )
push ( words , annotations )
push ( words , declarations )
push ( words , functions )
local bytes = { }
for _ , word in ipairs ( words ) do
bytes [ # bytes + 1 ] = wordBytes ( word )
end

return table . concat ( bytes )
end

local __nuppExportValue= spirv ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.spirvemit"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.spirvemit"]=__nuppExports;return __nuppExports