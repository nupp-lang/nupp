_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\0004") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\0005") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\0006") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\0007") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\0008") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\0009") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00010") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00011") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00012") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00013") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00014") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00015") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00016") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00017") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00018") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00019") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00020") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00021") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00022") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00023") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00024") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00025") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00026") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00027") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00028") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00029") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00030") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00031") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00032") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00033") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00034") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00035") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00036") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00037") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00038") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00039") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00040") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00041") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00042") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00043") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00044") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00045") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00046") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00047") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00048") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00049") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00050") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00051") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00052") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00053") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00054") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00055") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00056") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00057") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00058") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00059") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00060") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00061") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00062") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00063") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00064") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00065") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00066") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00067") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00068") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00069") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00070") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00071") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00072") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00073") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00074") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00075") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00076") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00077") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00078") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00079") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00080") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00081") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00082") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00083") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00084") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00085") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00086") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00087") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00088") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00089") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00090") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00091") , _G.nupp.__reflect.declaration("nupp.compiler.aot.scalar\0runtime\00092") };

























local scalarIR = { }





scalarIR . VERSION = 45













scalarIR . NUMERIC_CONTRACT = 4








local function identifierTail ( name ) 
local snake = name : gsub ( "(%u)(%u%l)" , "%1_%2" ) : gsub ( "(%l)(%u)" , "%1_%2" )
snake = snake : gsub ( "[^%w_]" , "_" ) : lower ( )
local canonical = snake : gsub ( "_([%l%d])" , function ( character ) 
return character : upper ( )
end )
if canonical == name then
return snake
end
local encoded = { }
for index = 1 , # name do
encoded [ index ] = ("%02x") : format ( name : byte ( index ) )
end

return snake .. "__" .. table . concat ( encoded )
end

function scalarIR . privateSymbol ( name ) 
return "ks_" .. identifierTail ( name )
end



function scalarIR . symbolPrefix ( filename ) 
return "ks_" .. require ( "nupp.compiler.hash" ) . digest ( filename ) : sub ( 1 , 16 ) .. "_"
end




function scalarIR . qualifiedPrivateSymbol ( filename , name ) 
return scalarIR . symbolPrefix ( filename ) .. scalarIR . privateSymbol ( name ) : sub ( 4 )
end





function scalarIR . identifier ( prefix , name ) 
return prefix .. "_" .. name : gsub ( "[^%w_]" , "_" )
end






scalarIR.Source = {} scalarIR.Source.__index = scalarIR.Source ;_G.nupp.__reflect.link(scalarIR.Source,__nuppT1[1],{ })

















scalarIR.Constant = {} scalarIR.Constant.__index = scalarIR.Constant ;_G.nupp.__reflect.link(scalarIR.Constant,__nuppT1[2],{ __nuppT1[1] })











scalarIR.IntConstant = {} scalarIR.IntConstant.__index = scalarIR.IntConstant ;_G.nupp.__reflect.link(scalarIR.IntConstant,__nuppT1[3],{ __nuppT1[1] })










scalarIR.Int64Constant = {} scalarIR.Int64Constant.__index = scalarIR.Int64Constant ;_G.nupp.__reflect.link(scalarIR.Int64Constant,__nuppT1[4],{ __nuppT1[1] })







scalarIR.Bool = {} scalarIR.Bool.__index = scalarIR.Bool ;_G.nupp.__reflect.link(scalarIR.Bool,__nuppT1[5],{ __nuppT1[1] })







scalarIR.LuaNil = {} scalarIR.LuaNil.__index = scalarIR.LuaNil ;_G.nupp.__reflect.link(scalarIR.LuaNil,__nuppT1[6],{ __nuppT1[1] })












scalarIR.ConstantBytes = {} scalarIR.ConstantBytes.__index = scalarIR.ConstantBytes ;_G.nupp.__reflect.link(scalarIR.ConstantBytes,__nuppT1[7],{ })













scalarIR.LuaString = {} scalarIR.LuaString.__index = scalarIR.LuaString ;_G.nupp.__reflect.link(scalarIR.LuaString,__nuppT1[8],{ __nuppT1[1] })







scalarIR.LuaStringMatch = {} scalarIR.LuaStringMatch.__index = scalarIR.LuaStringMatch ;_G.nupp.__reflect.link(scalarIR.LuaStringMatch,__nuppT1[9],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })








scalarIR.LuaConcat = {} scalarIR.LuaConcat.__index = scalarIR.LuaConcat ;_G.nupp.__reflect.link(scalarIR.LuaConcat,__nuppT1[10],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })








scalarIR.LuaSubstring = {} scalarIR.LuaSubstring.__index = scalarIR.LuaSubstring ;_G.nupp.__reflect.link(scalarIR.LuaSubstring,__nuppT1[11],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })









scalarIR.LuaStringByte = {} scalarIR.LuaStringByte.__index = scalarIR.LuaStringByte ;_G.nupp.__reflect.link(scalarIR.LuaStringByte,__nuppT1[12],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })








scalarIR.LuaTableGet = {} scalarIR.LuaTableGet.__index = scalarIR.LuaTableGet ;_G.nupp.__reflect.link(scalarIR.LuaTableGet,__nuppT1[13],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })








scalarIR.LuaStringBuffer = {} scalarIR.LuaStringBuffer.__index = scalarIR.LuaStringBuffer ;_G.nupp.__reflect.link(scalarIR.LuaStringBuffer,__nuppT1[14],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })







scalarIR.LuaStringBufferFinish = {} scalarIR.LuaStringBufferFinish.__index = scalarIR.LuaStringBufferFinish ;_G.nupp.__reflect.link(scalarIR.LuaStringBufferFinish,__nuppT1[15],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })







scalarIR.LuaField = {} scalarIR.LuaField.__index = scalarIR.LuaField ;_G.nupp.__reflect.link(scalarIR.LuaField,__nuppT1[16],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })











scalarIR.LuaNewTable = {} scalarIR.LuaNewTable.__index = scalarIR.LuaNewTable ;_G.nupp.__reflect.link(scalarIR.LuaNewTable,__nuppT1[17],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[16] , __nuppT1[1] })












scalarIR.LuaBuilder = {} scalarIR.LuaBuilder.__index = scalarIR.LuaBuilder ;_G.nupp.__reflect.link(scalarIR.LuaBuilder,__nuppT1[18],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })



















scalarIR.LuaScratchU32 = {} scalarIR.LuaScratchU32.__index = scalarIR.LuaScratchU32 ;_G.nupp.__reflect.link(scalarIR.LuaScratchU32,__nuppT1[19],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })

























scalarIR.LuaScratchU32Get = {} scalarIR.LuaScratchU32Get.__index = scalarIR.LuaScratchU32Get ;_G.nupp.__reflect.link(scalarIR.LuaScratchU32Get,__nuppT1[20],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })




















scalarIR.LuaScratchU32Length = {} scalarIR.LuaScratchU32Length.__index = scalarIR.LuaScratchU32Length ;_G.nupp.__reflect.link(scalarIR.LuaScratchU32Length,__nuppT1[21],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })






scalarIR.LuaScratchU8 = {} scalarIR.LuaScratchU8.__index = scalarIR.LuaScratchU8 ;_G.nupp.__reflect.link(scalarIR.LuaScratchU8,__nuppT1[22],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })




















scalarIR.LuaScratchU8Get = {} scalarIR.LuaScratchU8Get.__index = scalarIR.LuaScratchU8Get ;_G.nupp.__reflect.link(scalarIR.LuaScratchU8Get,__nuppT1[23],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })













scalarIR.LuaBytes = {} scalarIR.LuaBytes.__index = scalarIR.LuaBytes ;_G.nupp.__reflect.link(scalarIR.LuaBytes,__nuppT1[24],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })










scalarIR.LuaBuilderFinish = {} scalarIR.LuaBuilderFinish.__index = scalarIR.LuaBuilderFinish ;_G.nupp.__reflect.link(scalarIR.LuaBuilderFinish,__nuppT1[25],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })








scalarIR.LuaBuilderQuery = {} scalarIR.LuaBuilderQuery.__index = scalarIR.LuaBuilderQuery ;_G.nupp.__reflect.link(scalarIR.LuaBuilderQuery,__nuppT1[26],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })












scalarIR.LuaBuilderNumberToken = {} scalarIR.LuaBuilderNumberToken.__index = scalarIR.LuaBuilderNumberToken ;_G.nupp.__reflect.link(scalarIR.LuaBuilderNumberToken,__nuppT1[27],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })


















scalarIR.Name = {} scalarIR.Name.__index = scalarIR.Name ;_G.nupp.__reflect.link(scalarIR.Name,__nuppT1[28],{ __nuppT1[1] })
















scalarIR.SpanCount = {} scalarIR.SpanCount.__index = scalarIR.SpanCount ;_G.nupp.__reflect.link(scalarIR.SpanCount,__nuppT1[29],{ __nuppT1[1] })











scalarIR.LoopIndex = {} scalarIR.LoopIndex.__index = scalarIR.LoopIndex ;_G.nupp.__reflect.link(scalarIR.LoopIndex,__nuppT1[30],{ __nuppT1[1] })






scalarIR.WorkgroupIndex = {} scalarIR.WorkgroupIndex.__index = scalarIR.WorkgroupIndex ;_G.nupp.__reflect.link(scalarIR.WorkgroupIndex,__nuppT1[31],{ __nuppT1[1] })






scalarIR.SharedLoad = {} scalarIR.SharedLoad.__index = scalarIR.SharedLoad ;_G.nupp.__reflect.link(scalarIR.SharedLoad,__nuppT1[32],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })








scalarIR.Load = {} scalarIR.Load.__index = scalarIR.Load ;_G.nupp.__reflect.link(scalarIR.Load,__nuppT1[33],{ __nuppT1[1] })




























scalarIR.ElementRef = {} scalarIR.ElementRef.__index = scalarIR.ElementRef ;_G.nupp.__reflect.link(scalarIR.ElementRef,__nuppT1[34],{ __nuppT1[1] })


















scalarIR.FieldLoad = {} scalarIR.FieldLoad.__index = scalarIR.FieldLoad ;_G.nupp.__reflect.link(scalarIR.FieldLoad,__nuppT1[35],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })







































scalarIR.Binary = {} scalarIR.Binary.__index = scalarIR.Binary ;_G.nupp.__reflect.link(scalarIR.Binary,__nuppT1[36],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })










scalarIR.Unary = {} scalarIR.Unary.__index = scalarIR.Unary ;_G.nupp.__reflect.link(scalarIR.Unary,__nuppT1[37],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })







scalarIR.Math = {} scalarIR.Math.__index = scalarIR.Math ;_G.nupp.__reflect.link(scalarIR.Math,__nuppT1[38],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })






























































scalarIR.Fixed = {} scalarIR.Fixed.__index = scalarIR.Fixed ;_G.nupp.__reflect.link(scalarIR.Fixed,__nuppT1[39],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })





















scalarIR.FixedUnary = {} scalarIR.FixedUnary.__index = scalarIR.FixedUnary ;_G.nupp.__reflect.link(scalarIR.FixedUnary,__nuppT1[40],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })









scalarIR.Corrected = {} scalarIR.Corrected.__index = scalarIR.Corrected ;_G.nupp.__reflect.link(scalarIR.Corrected,__nuppT1[41],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })









































scalarIR.Convert = {} scalarIR.Convert.__index = scalarIR.Convert ;_G.nupp.__reflect.link(scalarIR.Convert,__nuppT1[42],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })










scalarIR.AggregateNew = {} scalarIR.AggregateNew.__index = scalarIR.AggregateNew ;_G.nupp.__reflect.link(scalarIR.AggregateNew,__nuppT1[43],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })








scalarIR.AggregateField = {} scalarIR.AggregateField.__index = scalarIR.AggregateField ;_G.nupp.__reflect.link(scalarIR.AggregateField,__nuppT1[44],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })








scalarIR.HelperCall = {} scalarIR.HelperCall.__index = scalarIR.HelperCall ;_G.nupp.__reflect.link(scalarIR.HelperCall,__nuppT1[45],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })














scalarIR.Simd = {} scalarIR.Simd.__index = scalarIR.Simd ;_G.nupp.__reflect.link(scalarIR.Simd,__nuppT1[46],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })




































































scalarIR.ReducerInit = {} scalarIR.ReducerInit.__index = scalarIR.ReducerInit ;_G.nupp.__reflect.link(scalarIR.ReducerInit,__nuppT1[47],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })
























scalarIR.ReducerAdd = {} scalarIR.ReducerAdd.__index = scalarIR.ReducerAdd ;_G.nupp.__reflect.link(scalarIR.ReducerAdd,__nuppT1[48],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })


























scalarIR.VectorReducerAdd = {} scalarIR.VectorReducerAdd.__index = scalarIR.VectorReducerAdd ;_G.nupp.__reflect.link(scalarIR.VectorReducerAdd,__nuppT1[49],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })

























scalarIR.ReducerRegionAccumulator = {} scalarIR.ReducerRegionAccumulator.__index = scalarIR.ReducerRegionAccumulator ;_G.nupp.__reflect.link(scalarIR.ReducerRegionAccumulator,__nuppT1[50],{ })




























scalarIR.ReducerRegion = {} scalarIR.ReducerRegion.__index = scalarIR.ReducerRegion ;_G.nupp.__reflect.link(scalarIR.ReducerRegion,__nuppT1[51],{ __nuppT1[59] , __nuppT1[72] , __nuppT1[73] , __nuppT1[74] , __nuppT1[71] , __nuppT1[68] , __nuppT1[55] , __nuppT1[63] , __nuppT1[64] , __nuppT1[65] , __nuppT1[61] , __nuppT1[62] , __nuppT1[58] , __nuppT1[77] , __nuppT1[48] , __nuppT1[51] , __nuppT1[70] , __nuppT1[75] , __nuppT1[76] , __nuppT1[46] , __nuppT1[60] , __nuppT1[49] , __nuppT1[69] , __nuppT1[50] , __nuppT1[1] })







scalarIR.ReducerValue = {} scalarIR.ReducerValue.__index = scalarIR.ReducerValue ;_G.nupp.__reflect.link(scalarIR.ReducerValue,__nuppT1[52],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })


















































































scalarIR.Target = {} scalarIR.Target.__index = scalarIR.Target ;_G.nupp.__reflect.link(scalarIR.Target,__nuppT1[53],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] })











scalarIR.Assignment = {} scalarIR.Assignment.__index = scalarIR.Assignment ;_G.nupp.__reflect.link(scalarIR.Assignment,__nuppT1[54],{ __nuppT1[53] , __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] })





scalarIR.Let = {} scalarIR.Let.__index = scalarIR.Let ;_G.nupp.__reflect.link(scalarIR.Let,__nuppT1[55],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })























scalarIR.Carried = {} scalarIR.Carried.__index = scalarIR.Carried ;_G.nupp.__reflect.link(scalarIR.Carried,__nuppT1[56],{ })









scalarIR.Binding = {} scalarIR.Binding.__index = scalarIR.Binding ;_G.nupp.__reflect.link(scalarIR.Binding,__nuppT1[57],{ __nuppT1[1] })




















scalarIR.MultiLet = {} scalarIR.MultiLet.__index = scalarIR.MultiLet ;_G.nupp.__reflect.link(scalarIR.MultiLet,__nuppT1[58],{ __nuppT1[45] , __nuppT1[57] , __nuppT1[1] })







scalarIR.Assign = {} scalarIR.Assign.__index = scalarIR.Assign ;_G.nupp.__reflect.link(scalarIR.Assign,__nuppT1[59],{ __nuppT1[54] , __nuppT1[1] })






scalarIR.Store = {} scalarIR.Store.__index = scalarIR.Store ;_G.nupp.__reflect.link(scalarIR.Store,__nuppT1[60],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })
















scalarIR.LuaSet = {} scalarIR.LuaSet.__index = scalarIR.LuaSet ;_G.nupp.__reflect.link(scalarIR.LuaSet,__nuppT1[61],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })








scalarIR.LuaStringBufferAppend = {} scalarIR.LuaStringBufferAppend.__index = scalarIR.LuaStringBufferAppend ;_G.nupp.__reflect.link(scalarIR.LuaStringBufferAppend,__nuppT1[62],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })












scalarIR.LuaBuild = {} scalarIR.LuaBuild.__index = scalarIR.LuaBuild ;_G.nupp.__reflect.link(scalarIR.LuaBuild,__nuppT1[63],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })




































scalarIR.LuaScratchU32Set = {} scalarIR.LuaScratchU32Set.__index = scalarIR.LuaScratchU32Set ;_G.nupp.__reflect.link(scalarIR.LuaScratchU32Set,__nuppT1[64],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })












scalarIR.LuaScratchU8Set = {} scalarIR.LuaScratchU8Set.__index = scalarIR.LuaScratchU8Set ;_G.nupp.__reflect.link(scalarIR.LuaScratchU8Set,__nuppT1[65],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })






























scalarIR . ONE_ELEMENT = "1"






scalarIR.RoomTransfer = {} scalarIR.RoomTransfer.__index = scalarIR.RoomTransfer ;_G.nupp.__reflect.link(scalarIR.RoomTransfer,__nuppT1[66],{ })









scalarIR.Clause = {} scalarIR.Clause.__index = scalarIR.Clause ;_G.nupp.__reflect.link(scalarIR.Clause,__nuppT1[67],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[59] , __nuppT1[72] , __nuppT1[73] , __nuppT1[74] , __nuppT1[71] , __nuppT1[68] , __nuppT1[55] , __nuppT1[61] , __nuppT1[62] , __nuppT1[58] , __nuppT1[77] , __nuppT1[51] , __nuppT1[70] , __nuppT1[75] , __nuppT1[76] , __nuppT1[60] , __nuppT1[69] , __nuppT1[1] })






scalarIR.If = {} scalarIR.If.__index = scalarIR.If ;_G.nupp.__reflect.link(scalarIR.If,__nuppT1[68],{ __nuppT1[67] , __nuppT1[59] , __nuppT1[72] , __nuppT1[73] , __nuppT1[74] , __nuppT1[71] , __nuppT1[68] , __nuppT1[55] , __nuppT1[63] , __nuppT1[64] , __nuppT1[65] , __nuppT1[61] , __nuppT1[62] , __nuppT1[58] , __nuppT1[77] , __nuppT1[48] , __nuppT1[51] , __nuppT1[70] , __nuppT1[75] , __nuppT1[76] , __nuppT1[46] , __nuppT1[60] , __nuppT1[49] , __nuppT1[69] , __nuppT1[1] })






scalarIR.While = {} scalarIR.While.__index = scalarIR.While ;_G.nupp.__reflect.link(scalarIR.While,__nuppT1[69],{ __nuppT1[59] , __nuppT1[72] , __nuppT1[73] , __nuppT1[74] , __nuppT1[71] , __nuppT1[68] , __nuppT1[55] , __nuppT1[63] , __nuppT1[64] , __nuppT1[65] , __nuppT1[61] , __nuppT1[62] , __nuppT1[58] , __nuppT1[77] , __nuppT1[48] , __nuppT1[51] , __nuppT1[70] , __nuppT1[75] , __nuppT1[76] , __nuppT1[46] , __nuppT1[60] , __nuppT1[49] , __nuppT1[69] , __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[22] , __nuppT1[23] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[29] , __nuppT1[37] , __nuppT1[31] , __nuppT1[56] , __nuppT1[1] })



















scalarIR.Repeat = {} scalarIR.Repeat.__index = scalarIR.Repeat ;_G.nupp.__reflect.link(scalarIR.Repeat,__nuppT1[70],{ __nuppT1[59] , __nuppT1[72] , __nuppT1[73] , __nuppT1[74] , __nuppT1[71] , __nuppT1[68] , __nuppT1[55] , __nuppT1[63] , __nuppT1[64] , __nuppT1[65] , __nuppT1[61] , __nuppT1[62] , __nuppT1[58] , __nuppT1[77] , __nuppT1[48] , __nuppT1[51] , __nuppT1[70] , __nuppT1[75] , __nuppT1[76] , __nuppT1[46] , __nuppT1[60] , __nuppT1[49] , __nuppT1[69] , __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[22] , __nuppT1[23] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[29] , __nuppT1[37] , __nuppT1[31] , __nuppT1[56] , __nuppT1[1] })












scalarIR.Fornum = {} scalarIR.Fornum.__index = scalarIR.Fornum ;_G.nupp.__reflect.link(scalarIR.Fornum,__nuppT1[71],{ __nuppT1[57] , __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[59] , __nuppT1[72] , __nuppT1[73] , __nuppT1[74] , __nuppT1[71] , __nuppT1[68] , __nuppT1[55] , __nuppT1[61] , __nuppT1[62] , __nuppT1[58] , __nuppT1[77] , __nuppT1[51] , __nuppT1[70] , __nuppT1[75] , __nuppT1[76] , __nuppT1[60] , __nuppT1[69] , __nuppT1[56] , __nuppT1[1] })



















scalarIR.Block = {} scalarIR.Block.__index = scalarIR.Block ;_G.nupp.__reflect.link(scalarIR.Block,__nuppT1[72],{ __nuppT1[59] , __nuppT1[72] , __nuppT1[73] , __nuppT1[74] , __nuppT1[71] , __nuppT1[68] , __nuppT1[55] , __nuppT1[63] , __nuppT1[64] , __nuppT1[65] , __nuppT1[61] , __nuppT1[62] , __nuppT1[58] , __nuppT1[77] , __nuppT1[48] , __nuppT1[51] , __nuppT1[70] , __nuppT1[75] , __nuppT1[76] , __nuppT1[46] , __nuppT1[60] , __nuppT1[49] , __nuppT1[69] , __nuppT1[1] })









scalarIR.Break = {} scalarIR.Break.__index = scalarIR.Break ;_G.nupp.__reflect.link(scalarIR.Break,__nuppT1[73],{ __nuppT1[1] })




scalarIR.Continue = {} scalarIR.Continue.__index = scalarIR.Continue ;_G.nupp.__reflect.link(scalarIR.Continue,__nuppT1[74],{ __nuppT1[1] })





scalarIR.Return = {} scalarIR.Return.__index = scalarIR.Return ;_G.nupp.__reflect.link(scalarIR.Return,__nuppT1[75],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })







scalarIR.SharedStore = {} scalarIR.SharedStore.__index = scalarIR.SharedStore ;_G.nupp.__reflect.link(scalarIR.SharedStore,__nuppT1[76],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })









scalarIR.Phase = {} scalarIR.Phase.__index = scalarIR.Phase ;_G.nupp.__reflect.link(scalarIR.Phase,__nuppT1[77],{ __nuppT1[59] , __nuppT1[72] , __nuppT1[73] , __nuppT1[74] , __nuppT1[71] , __nuppT1[68] , __nuppT1[55] , __nuppT1[63] , __nuppT1[64] , __nuppT1[65] , __nuppT1[61] , __nuppT1[62] , __nuppT1[58] , __nuppT1[77] , __nuppT1[48] , __nuppT1[51] , __nuppT1[70] , __nuppT1[75] , __nuppT1[76] , __nuppT1[46] , __nuppT1[60] , __nuppT1[49] , __nuppT1[69] , __nuppT1[1] })







































scalarIR.Field = {} scalarIR.Field.__index = scalarIR.Field ;_G.nupp.__reflect.link(scalarIR.Field,__nuppT1[78],{ __nuppT1[1] })














scalarIR.Layout = {} scalarIR.Layout.__index = scalarIR.Layout ;_G.nupp.__reflect.link(scalarIR.Layout,__nuppT1[79],{ __nuppT1[78] , __nuppT1[1] })



























scalarIR.Term = {} scalarIR.Term.__index = scalarIR.Term ;_G.nupp.__reflect.link(scalarIR.Term,__nuppT1[80],{ })

















scalarIR.Relation = {} scalarIR.Relation.__index = scalarIR.Relation ;_G.nupp.__reflect.link(scalarIR.Relation,__nuppT1[81],{ __nuppT1[80] , __nuppT1[1] })












scalarIR.RangeGuard = {} scalarIR.RangeGuard.__index = scalarIR.RangeGuard ;_G.nupp.__reflect.link(scalarIR.RangeGuard,__nuppT1[82],{ __nuppT1[1] })











scalarIR.SoaColumn = {} scalarIR.SoaColumn.__index = scalarIR.SoaColumn ;_G.nupp.__reflect.link(scalarIR.SoaColumn,__nuppT1[83],{ })














scalarIR.Param = {} scalarIR.Param.__index = scalarIR.Param ;_G.nupp.__reflect.link(scalarIR.Param,__nuppT1[84],{ __nuppT1[83] , __nuppT1[1] })



































scalarIR.Region = {} scalarIR.Region.__index = scalarIR.Region ;_G.nupp.__reflect.link(scalarIR.Region,__nuppT1[85],{ __nuppT1[1] })

















scalarIR.AliasFact = {} scalarIR.AliasFact.__index = scalarIR.AliasFact ;_G.nupp.__reflect.link(scalarIR.AliasFact,__nuppT1[86],{ })







scalarIR.Guard = {} scalarIR.Guard.__index = scalarIR.Guard ;_G.nupp.__reflect.link(scalarIR.Guard,__nuppT1[87],{ __nuppT1[1] })







scalarIR.Helper = {} scalarIR.Helper.__index = scalarIR.Helper ;_G.nupp.__reflect.link(scalarIR.Helper,__nuppT1[88],{ __nuppT1[28] , __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })


























scalarIR.Loop = {} scalarIR.Loop.__index = scalarIR.Loop ;_G.nupp.__reflect.link(scalarIR.Loop,__nuppT1[89],{ __nuppT1[59] , __nuppT1[72] , __nuppT1[73] , __nuppT1[74] , __nuppT1[71] , __nuppT1[68] , __nuppT1[55] , __nuppT1[63] , __nuppT1[64] , __nuppT1[65] , __nuppT1[61] , __nuppT1[62] , __nuppT1[58] , __nuppT1[77] , __nuppT1[48] , __nuppT1[51] , __nuppT1[70] , __nuppT1[75] , __nuppT1[76] , __nuppT1[46] , __nuppT1[60] , __nuppT1[49] , __nuppT1[69] , __nuppT1[1] })












scalarIR.Shared = {} scalarIR.Shared.__index = scalarIR.Shared ;_G.nupp.__reflect.link(scalarIR.Shared,__nuppT1[90],{ __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[63] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[64] , __nuppT1[22] , __nuppT1[23] , __nuppT1[65] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[48] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[46] , __nuppT1[29] , __nuppT1[37] , __nuppT1[49] , __nuppT1[31] , __nuppT1[1] })









scalarIR.Workgroup = {} scalarIR.Workgroup.__index = scalarIR.Workgroup ;_G.nupp.__reflect.link(scalarIR.Workgroup,__nuppT1[91],{ __nuppT1[59] , __nuppT1[72] , __nuppT1[73] , __nuppT1[74] , __nuppT1[71] , __nuppT1[68] , __nuppT1[55] , __nuppT1[63] , __nuppT1[64] , __nuppT1[65] , __nuppT1[61] , __nuppT1[62] , __nuppT1[58] , __nuppT1[77] , __nuppT1[48] , __nuppT1[51] , __nuppT1[70] , __nuppT1[75] , __nuppT1[76] , __nuppT1[46] , __nuppT1[60] , __nuppT1[49] , __nuppT1[69] , __nuppT1[44] , __nuppT1[43] , __nuppT1[36] , __nuppT1[5] , __nuppT1[2] , __nuppT1[42] , __nuppT1[41] , __nuppT1[34] , __nuppT1[35] , __nuppT1[39] , __nuppT1[40] , __nuppT1[45] , __nuppT1[4] , __nuppT1[3] , __nuppT1[33] , __nuppT1[30] , __nuppT1[18] , __nuppT1[25] , __nuppT1[27] , __nuppT1[26] , __nuppT1[24] , __nuppT1[10] , __nuppT1[17] , __nuppT1[6] , __nuppT1[19] , __nuppT1[20] , __nuppT1[21] , __nuppT1[22] , __nuppT1[23] , __nuppT1[8] , __nuppT1[14] , __nuppT1[15] , __nuppT1[12] , __nuppT1[9] , __nuppT1[11] , __nuppT1[13] , __nuppT1[38] , __nuppT1[28] , __nuppT1[47] , __nuppT1[52] , __nuppT1[32] , __nuppT1[29] , __nuppT1[37] , __nuppT1[31] , __nuppT1[90] , __nuppT1[1] })


















scalarIR.Program = {} scalarIR.Program.__index = scalarIR.Program ;_G.nupp.__reflect.link(scalarIR.Program,__nuppT1[92],{ __nuppT1[84] , __nuppT1[79] , __nuppT1[85] , __nuppT1[86] , __nuppT1[81] , __nuppT1[87] , __nuppT1[88] , __nuppT1[7] , __nuppT1[89] , __nuppT1[91] , __nuppT1[59] , __nuppT1[72] , __nuppT1[73] , __nuppT1[74] , __nuppT1[71] , __nuppT1[68] , __nuppT1[55] , __nuppT1[63] , __nuppT1[64] , __nuppT1[65] , __nuppT1[61] , __nuppT1[62] , __nuppT1[58] , __nuppT1[77] , __nuppT1[48] , __nuppT1[51] , __nuppT1[70] , __nuppT1[75] , __nuppT1[76] , __nuppT1[46] , __nuppT1[60] , __nuppT1[49] , __nuppT1[69] , __nuppT1[82] , __nuppT1[1] })






















































































































function scalarIR . storedVectorField ( field ) 
return tostring ( field . type ) : match ( "^simd_vector_" ) ~= nil
end


function scalarIR . holdsStoredVector ( layout ) 
for _ , field in ipairs ( layout . fields ) do
if scalarIR . storedVectorField ( field ) then
return true
end
end

return false
end

function scalarIR . nativeOnlyType ( typeName ) 
local name = tostring ( typeName )

return name : match ( "^simd_vector_" ) ~= nil or name : match ( "^simd_mask_" ) ~= nil or name : match ( "^aggregate:" ) ~= nil
end


function scalarIR . aggregateLayout ( typeName ) 
return tostring ( typeName ) : match ( "^aggregate:(.+)$" )
end

function scalarIR . sameSoaView ( left , right ) 
return left ~= nil
and right ~= nil
and left . soa ~= nil
and right . soa ~= nil
and left . soa . view == right . soa . view
and left . soa . layout == right . soa . layout
end

local function exactIntegerText ( text ) 
local sign , body = text : match ( "^([+-]?)(.+)$" )
if body == nil then
sign , body = "" , text
end
local mantissa , exponentText = ( body ) : match ( "^([^eE]+)[eE]([+-]?%d+)$" )
if mantissa == nil then
mantissa , exponentText = body , "0"
end
local whole , fraction = ( mantissa ) : match ( "^(%d*)%.(%d*)$" )
if whole == nil then
whole = ( mantissa ) : match ( "^(%d+)$" )
fraction = ""
end
if whole == nil or ( whole == "" and fraction == "" ) then
return nil
end
local exponent = tonumber ( exponentText )
if exponent == nil or exponent % 1 ~= 0 or math . abs ( exponent ) > 100000 then
return nil
end
local digits = ( whole ) .. ( fraction )
local decimal = # ( whole ) + exponent
if decimal < # digits then
if digits : sub ( decimal + 1 ) : match ( "[^0]" ) ~= nil then
return nil
end
digits = decimal > 0 and digits : sub ( 1 , decimal ) or "0"
elseif decimal > # digits then
digits = digits .. string . rep ( "0" , decimal - # digits )
end
digits = digits : gsub ( "^0+" , "" )
if digits == "" then
digits = "0"
end

if # digits > 16 or ( # digits == 16 and digits > "9007199254740992" ) then
return nil
end

return tonumber ( ( sign ) .. digits )
end



function scalarIR . exactInteger ( node ) 
if node . op ~= "constant" and node . op ~= "constant_i32" and node . op ~= "constant_i64" then
return nil
end
return exactIntegerText ( tostring ( ( node ) . value ) )
end


function scalarIR . isSpan ( param ) 
return param . kind == "write_span" or param . kind == "read_span"
end






function scalarIR . independentCounts ( program ) 
if program . body ~= nil or program . workgroup ~= nil then
return true
end
local spans = 0
for _ , param in ipairs ( program . params ) do
if scalarIR . isSpan ( param ) then
spans = spans + 1
end
end

return # program . guards < spans - 1
end

local __nuppExportValue= scalarIR ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.scalar"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.scalar"]=__nuppExports;return __nuppExports