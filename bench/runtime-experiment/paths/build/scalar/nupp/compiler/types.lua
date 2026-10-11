_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppBuffer = require("nupp.text"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\0004") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\0005") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\0006") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\0007") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\0008") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\0009") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00010") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00011") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00012") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00013") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00014") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00015") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00016") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00017") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00018") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00019") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00020") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00021") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00022") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00023") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00024") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00025") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00026") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00027") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00028") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00029") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00030") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00031") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00032") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00033") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00034") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00035") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00036") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00037") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00038") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00039") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00040") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00041") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00042") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00043") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00044") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00045") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00046") , _G.nupp.__reflect.declaration("nupp.compiler.types\0runtime\00047") };


















local types = { }











































types.Prim = {} types.Prim.__index = types.Prim ;_G.nupp.__reflect.link(types.Prim,__nuppT1[1],{ })





types.Array = {} types.Array.__index = types.Array ;_G.nupp.__reflect.link(types.Array,__nuppT1[2],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })














types.Map = {} types.Map.__index = types.Map ;_G.nupp.__reflect.link(types.Map,__nuppT1[3],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })
















types.Tuple = {} types.Tuple.__index = types.Tuple ;_G.nupp.__reflect.link(types.Tuple,__nuppT1[4],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })






types.Shape = {} types.Shape.__index = types.Shape ;_G.nupp.__reflect.link(types.Shape,__nuppT1[5],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })


























types.Union = {} types.Union.__index = types.Union ;_G.nupp.__reflect.link(types.Union,__nuppT1[6],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })












types.Intersection = {} types.Intersection.__index = types.Intersection ;_G.nupp.__reflect.link(types.Intersection,__nuppT1[7],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })








types.Ptr = {} types.Ptr.__index = types.Ptr ;_G.nupp.__reflect.link(types.Ptr,__nuppT1[8],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })






types.CArray = {} types.CArray.__index = types.CArray ;_G.nupp.__reflect.link(types.CArray,__nuppT1[9],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] , __nuppT1[10] , __nuppT1[12] , __nuppT1[11] })








types.ConstLiteral = {} types.ConstLiteral.__index = types.ConstLiteral ;_G.nupp.__reflect.link(types.ConstLiteral,__nuppT1[10],{ })







types.ConstVar = {} types.ConstVar.__index = types.ConstVar ;_G.nupp.__reflect.link(types.ConstVar,__nuppT1[11],{ })








types.ConstOp = {} types.ConstOp.__index = types.ConstOp ;_G.nupp.__reflect.link(types.ConstOp,__nuppT1[12],{ __nuppT1[10] , __nuppT1[12] , __nuppT1[11] })








types.ComptimeTypeArgument = {} types.ComptimeTypeArgument.__index = types.ComptimeTypeArgument ;_G.nupp.__reflect.link(types.ComptimeTypeArgument,__nuppT1[13],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })




types.ComptimePackArgument = {} types.ComptimePackArgument.__index = types.ComptimePackArgument ;_G.nupp.__reflect.link(types.ComptimePackArgument,__nuppT1[14],{ __nuppT1[30] })




types.ComptimeConstArgument = {} types.ComptimeConstArgument.__index = types.ComptimeConstArgument ;_G.nupp.__reflect.link(types.ComptimeConstArgument,__nuppT1[15],{ __nuppT1[10] , __nuppT1[12] , __nuppT1[11] })











types.Cleanup = {} types.Cleanup.__index = types.Cleanup ;_G.nupp.__reflect.link(types.Cleanup,__nuppT1[16],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] , __nuppT1[16] , __nuppT1[10] , __nuppT1[12] , __nuppT1[11] })

















types.Affine = {} types.Affine.__index = types.Affine ;_G.nupp.__reflect.link(types.Affine,__nuppT1[17],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] , __nuppT1[16] , __nuppT1[20] })














types.Borrowed = {} types.Borrowed.__index = types.Borrowed ;_G.nupp.__reflect.link(types.Borrowed,__nuppT1[18],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })






types.Pinned = {} types.Pinned.__index = types.Pinned ;_G.nupp.__reflect.link(types.Pinned,__nuppT1[19],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })








types.Obligation = {} types.Obligation.__index = types.Obligation ;_G.nupp.__reflect.link(types.Obligation,__nuppT1[20],{ __nuppT1[16] , __nuppT1[20] })







types.Loan = {} types.Loan.__index = types.Loan ;_G.nupp.__reflect.link(types.Loan,__nuppT1[21],{ })








types.PinnedAnchor = {} types.PinnedAnchor.__index = types.PinnedAnchor ;_G.nupp.__reflect.link(types.PinnedAnchor,__nuppT1[22],{ })





types.ForeignRetention = {} types.ForeignRetention.__index = types.ForeignRetention ;_G.nupp.__reflect.link(types.ForeignRetention,__nuppT1[23],{ })







types.CapabilityFacts = {} types.CapabilityFacts.__index = types.CapabilityFacts ;_G.nupp.__reflect.link(types.CapabilityFacts,__nuppT1[24],{ __nuppT1[21] , __nuppT1[22] , __nuppT1[23] })
























types.Capability = {} types.Capability.__index = types.Capability ;_G.nupp.__reflect.link(types.Capability,__nuppT1[25],{ __nuppT1[20] , __nuppT1[21] , __nuppT1[22] , __nuppT1[23] })








types.ValueSlot = {} types.ValueSlot.__index = types.ValueSlot ;_G.nupp.__reflect.link(types.ValueSlot,__nuppT1[26],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] , __nuppT1[25] })





types.Const = {} types.Const.__index = types.Const ;_G.nupp.__reflect.link(types.Const,__nuppT1[27],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })






types.CType = {} types.CType.__index = types.CType ;_G.nupp.__reflect.link(types.CType,__nuppT1[28],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })






types.PackVar = {} types.PackVar.__index = types.PackVar ;_G.nupp.__reflect.link(types.PackVar,__nuppT1[29],{ })


















types.Pack = {} types.Pack.__index = types.Pack ;_G.nupp.__reflect.link(types.Pack,__nuppT1[30],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] , __nuppT1[30] })













types.ProtocolThread = {} types.ProtocolThread.__index = types.ProtocolThread ;_G.nupp.__reflect.link(types.ProtocolThread,__nuppT1[31],{ __nuppT1[30] })









types.GenericAlias = {} types.GenericAlias.__index = types.GenericAlias ;_G.nupp.__reflect.link(types.GenericAlias,__nuppT1[32],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] , __nuppT1[29] , __nuppT1[11] })













types.Func = {} types.Func.__index = types.Func ;_G.nupp.__reflect.link(types.Func,__nuppT1[33],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] , __nuppT1[30] , __nuppT1[29] , __nuppT1[11] })

























































































































types.Literal = {} types.Literal.__index = types.Literal ;_G.nupp.__reflect.link(types.Literal,__nuppT1[34],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })





















types.Constrained = {} types.Constrained.__index = types.Constrained ;_G.nupp.__reflect.link(types.Constrained,__nuppT1[35],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })





















types.TypeVar = {} types.TypeVar.__index = types.TypeVar ;_G.nupp.__reflect.link(types.TypeVar,__nuppT1[36],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })















types.TypeHandle = {} types.TypeHandle.__index = types.TypeHandle ;_G.nupp.__reflect.link(types.TypeHandle,__nuppT1[37],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })






types.PackResult = {} types.PackResult.__index = types.PackResult ;_G.nupp.__reflect.link(types.PackResult,__nuppT1[38],{ __nuppT1[30] })







types.Neutral = {} types.Neutral.__index = types.Neutral ;_G.nupp.__reflect.link(types.Neutral,__nuppT1[39],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] , __nuppT1[10] , __nuppT1[12] , __nuppT1[11] , __nuppT1[15] , __nuppT1[14] , __nuppT1[13] })























types.Metatable = {} types.Metatable.__index = types.Metatable ;_G.nupp.__reflect.link(types.Metatable,__nuppT1[40],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })








types.TypeObject = {} types.TypeObject.__index = types.TypeObject ;_G.nupp.__reflect.link(types.TypeObject,__nuppT1[41],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })














types.Projection = {} types.Projection.__index = types.Projection ;_G.nupp.__reflect.link(types.Projection,__nuppT1[42],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })
















types.AssociatedRequirement = {} types.AssociatedRequirement.__index = types.AssociatedRequirement ;_G.nupp.__reflect.link(types.AssociatedRequirement,__nuppT1[43],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })























types.AssociatedAnswer = {} types.AssociatedAnswer.__index = types.AssociatedAnswer ;_G.nupp.__reflect.link(types.AssociatedAnswer,__nuppT1[44],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })



















types.AssociatedReached = {} types.AssociatedReached.__index = types.AssociatedReached ;_G.nupp.__reflect.link(types.AssociatedReached,__nuppT1[45],{ __nuppT1[43] , __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] })
























types.AssociatedLookup = {} types.AssociatedLookup.__index = types.AssociatedLookup ;_G.nupp.__reflect.link(types.AssociatedLookup,__nuppT1[46],{ __nuppT1[45] , __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] , __nuppT1[44] })
































types.Nominal = {} types.Nominal.__index = types.Nominal ;_G.nupp.__reflect.link(types.Nominal,__nuppT1[47],{ __nuppT1[17] , __nuppT1[2] , __nuppT1[18] , __nuppT1[9] , __nuppT1[28] , __nuppT1[27] , __nuppT1[35] , __nuppT1[33] , __nuppT1[32] , __nuppT1[7] , __nuppT1[34] , __nuppT1[3] , __nuppT1[40] , __nuppT1[39] , __nuppT1[47] , __nuppT1[38] , __nuppT1[19] , __nuppT1[1] , __nuppT1[42] , __nuppT1[31] , __nuppT1[8] , __nuppT1[5] , __nuppT1[4] , __nuppT1[37] , __nuppT1[41] , __nuppT1[36] , __nuppT1[6] , __nuppT1[44] , __nuppT1[43] , __nuppT1[16] , __nuppT1[30] , __nuppT1[10] , __nuppT1[12] , __nuppT1[11] , __nuppT1[29] })














































































































































































































































































































local arena = { }

local packArena = { }
local packVarArena = { }
local capabilityArena = { }
local capabilityIdentity = setmetatable ( { } , { __mode = "k" } )
local nextCapabilityIdentity = 0
local identityNamespace = ""
local constArena = { }

local function flowIdentity ( value ) 
if value == nil then
return 0
end
local found = capabilityIdentity [ value ]
if found then
return found
end
nextCapabilityIdentity = nextCapabilityIdentity + 1
capabilityIdentity [ value ] = nextCapabilityIdentity

return nextCapabilityIdentity
end














local nextSerial = 0

local function serial ( prefix ) 
nextSerial = nextSerial + 1

return prefix .. identityNamespace .. nextSerial
end













local MARK_TYPEVAR = "!t"

local MARK_PACKVAR = "!p"
local MARK_CONSTVAR = "!c"
local MARK_PROJECTION = "!j"
local MARKS = { "!t" , "!p" , "!c" , "!j" }


local function inheritedMarks ( key ) 
local __nuppBuf_1 = __nuppBuffer.newBuffer()
for _ , mark in ipairs ( MARKS ) do
if key : find ( mark , 1 , true ) then
__nuppBuf_1:put( mark )
end
end

return __nuppBuf_1:tostring()
end













local function canonicalOrder ( a , b ) 
if a . tag ~= b . tag then
return a . tag < b . tag
end
if a . tag == "literal" then
local left = tostring ( ( a ) . constant )
local right = tostring ( ( b ) . constant )
if left ~= right then
return left < right
end
end
if a . tag == "nominal" then
local left , right = ( a ) . name , ( b ) . name
if left ~= right then
return left < right
end
end

return a . id < b . id
end





local function intern ( key , made ) 
local found = arena [ key ]
if found then
return found
end
made . id = inheritedMarks ( key ) .. serial ( "t" )
arena [ key ] = made

return made
end














local function interned ( key ) 
return arena [ key ]
end


local function prim ( tag ) 
local existing = ( arena [ tag ] )
if existing then
return existing
end

return intern ( tag , _G.setmetatable({ tag =  tag ,  id =  "" }, types.Prim) )
end

types . any = prim ( "any" )



types . unknown = prim ( "unknown" )


types . never = prim ( "never" )





types . open = prim ( "open" )
types . nil_ = prim ( "nil" )
types . boolean = prim ( "boolean" )
types . string = prim ( "string" )
types . number = prim ( "number" )
types . integer = prim ( "integer" )
types . table_ = prim ( "table" )
types . thread = prim ( "thread" )
types . userdata = prim ( "userdata" )



types . float = prim ( "float" )


types . cdata = prim ( "cdata" )


types . cstring = prim ( "cstring" )
types . voidptr = prim ( "voidptr" )

types . int8 = prim ( "int8" )
types . int16 = prim ( "int16" )
types . int32 = prim ( "int32" )
types . int64 = prim ( "int64" )
types . uint8 = prim ( "uint8" )
types . uint16 = prim ( "uint16" )
types . uint32 = prim ( "uint32" )
types . uint64 = prim ( "uint64" )


types . type_ = prim ( "type" )
types . typepack = prim ( "typepack" )
types . functionConst = prim ( "functionconst" )



local TABLE_SHAPED

= { array = true , map = true , tuple = true , shape = true , metatable = true , typeobject = true , nominal = true , }


local builtins

= {
any = types . any ,
unknown = types . unknown ,
never = types . never ,
boolean = types . boolean ,
string = types . string ,
number = types . number ,
integer = types . integer ,
table = types . table_ ,
thread = types . thread ,
userdata = types . userdata ,
float = types . float ,
int8 = types . int8 ,
int16 = types . int16 ,
int32 = types . int32 ,
int64 = types . int64 ,
uint8 = types . uint8 ,
uint16 = types . uint16 ,
uint32 = types . uint32 ,
uint64 = types . uint64 ,
cstring = types . cstring ,
voidptr = types . voidptr ,
cdata = types . cdata ,
type = types . type_ ,
typepack = types . typepack ,
[ "nil" ] = types . nil_ ,
}

types . builtins = builtins










function types . array ( elem , elems , fresh ) 
local internKey = "{" .. elem . id .. "}"
if elems then
local ids = { }
for j , e in ipairs ( elems ) do
ids [ j ] = e . id
end
internKey = internKey .. "!fresh(" .. table . concat ( ids , "," ) .. ")"
elseif fresh then
internKey = internKey .. "!fresh"
end

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern (
internKey ,
_G.setmetatable({ tag =  "array" ,  elem =  elem ,  fresh =  ( elems or fresh ) and true or nil ,  elems =  elems ,  id =  "" }, types.Array)
)
end



function types . map ( key , value ) 
return types . indexer ( key , value , key , value )
end


function types . indexer (
readKey ,
readValue ,
writeKey ,
writeValue
) 
local key = readKey or writeKey or types . never
local value = readValue or writeValue or types . never
local id = "index(" .. (
readKey and readKey . id or "-"
) .. ":" .. (
readValue and readValue . id or "-"
) .. "," .. ( writeKey and writeKey . id or "-" ) .. ":" .. ( writeValue and writeValue . id or "-" ) .. ")"

local existing = ( arena [ id ] )
if existing then
return existing
end

return intern (
id ,
_G.setmetatable({ tag =
"map" ,  key =
key ,  value =
value ,  readable =
readValue ~= nil ,  writeKey =
writeKey ,  writeValue =
writeValue ,  id =  "" }, types.Map)

)
end


function types . tuple ( elems ) 
local ids = { }
for j , e in ipairs ( elems ) do
ids [ j ] = e . id
end

local internKey = "tuple(" .. table . concat ( ids , "," ) .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "tuple" ,  elems =  elems ,  id =  "" }, types.Tuple) )
end







function types . shape ( fields , indexer , fresh , closed ) 
local sorted = { }
for j , f in ipairs ( fields ) do
sorted [ j ] = f
end
table . sort ( sorted , function ( a , b ) 
return a . name < b . name
end )
local parts = { }
local byname = { }
local writeByname = { }
for _ , f in ipairs ( sorted ) do
local read = f . read
local write = f . write
if f . type then
if f . capability == "read" then
read = f . type
elseif f . capability == "write" then
write = f . type
else
read , write = f . type , f . type
end
end
f . read , f . write = read , write
parts [ # parts + 1 ] = f . name .. ":r=" .. ( read and read . id or "-" ) .. ":w=" .. ( write and write . id or "-" )
if read then
byname [ f . name ] = read
end
if write then
writeByname [ f . name ] = write
end
end
local irk = indexer and indexer . readKey or nil
local irv = indexer and indexer . readValue or nil
local iwk = indexer and indexer . writeKey or nil
local iwv = indexer and indexer . writeValue or nil
parts [
# parts + 1
] = "[r=" .. (
irk and irk . id or "-"
) .. ":" .. ( irv and irv . id or "-" ) .. ":w=" .. ( iwk and iwk . id or "-" ) .. ":" .. ( iwv and iwv . id or "-" ) .. "]"
local key = "shape(" .. table . concat (
parts ,
","
) .. ")" .. ( fresh and "!fresh" or "" ) .. ( closed and "!closed" or "" )

local existing = ( arena [ key ] )
if existing then
return existing
end

return intern (
key ,
_G.setmetatable({ tag =
"shape" ,  fields =
sorted ,  byname =
byname ,  writeByname =
writeByname ,  indexReadKey =
irk ,  indexReadValue =
irv ,  indexWriteKey =
iwk ,  indexWriteValue =
iwv ,  fresh =
fresh or nil ,  closed =
closed or nil ,  id =  "" }, types.Shape)

)
end








local LUA_TYPE_NAME

= {
string = "string" ,
number = "number" ,
boolean = "boolean" ,
table = "table" ,
thread = "thread" ,
userdata = "userdata" ,
integer = "number" ,
float = "number" ,
int8 = "number" ,
int16 = "number" ,
int32 = "number" ,
int64 = "number" ,
uint8 = "number" ,
uint16 = "number" ,
uint32 = "number" ,
uint64 = "number" ,
}

function types . luaTypeName ( t ) 
if not t then
return nil
end
return LUA_TYPE_NAME [ t . tag ]
end




function types . settled ( t ) 
if t . tag == "array" and t . fresh then
return types . array ( types . settled ( t . elem ) )
elseif t . tag == "union" then
local members , changed = { } , false
for j , member in ipairs ( t . members ) do
members [ j ] = types . settled ( member )
changed = changed or members [ j ] ~= member
end
return changed and types . union ( members ) or t
end
if t . tag ~= "shape" or not t . fresh then
return t
end
local fields = { }
for j , f in ipairs ( t . fields ) do
fields [
j
] = {
name = f . name ,
read = f . read and types . settled ( f . read ) or nil ,
write = f . write and types . settled ( f . write ) or nil ,
}
end

return types . shape ( fields , {
readKey = t . indexReadKey ,
readValue = t . indexReadValue and types . settled ( t . indexReadValue ) or nil ,
writeKey = t . indexWriteKey ,
writeValue = t . indexWriteValue and types . settled ( t . indexWriteValue ) or nil ,
} )
end








local function pushUnionMember (
t ,
seen ,
flat ,
functionByContract
) 
if t . tag == "union" then
for _ , m in ipairs ( t . members ) do
pushUnionMember ( m , seen , flat , functionByContract )
end
elseif t == types . never then


return
elseif t . tag == "func" and functionByContract [ t . unlabeledId ] then
local at = functionByContract [ t . unlabeledId ]
local prior = flat [ at ]
if prior ~= t then




local sendable = prior . sendable and ( t ) . sendable or nil
local merged = types . funcWith ( prior , { paramNames = false , sendable = sendable or false } )
seen [ prior ] = nil
seen [ merged ] = true
flat [ at ] = merged
end
elseif not seen [ t ] then
seen [ t ] = true
flat [ # flat + 1 ] = t
if t . tag == "func" then
functionByContract [ t . unlabeledId ] = # flat
end
end
end








function types . union ( members ) 
local seen = { }
local flat = { }
local functionByContract = { }

for _ , m in ipairs ( members ) do
pushUnionMember ( m , seen , flat , functionByContract )
end
if # flat == 0 then
return types . never
end
if # flat == 1 then
return flat [ 1 ]
end

for _ , m in ipairs ( flat ) do
if m == types . any then
return types . any
end
end





local structured = false
for _ , m in ipairs ( flat ) do
if TABLE_SHAPED [ m . tag ] then
structured = true
end
end
if structured then
local kept = { }
for _ , m in ipairs ( flat ) do
if m ~= types . table_ then
kept [ # kept + 1 ] = m
end
end
flat = kept
if # flat == 1 then
return flat [ 1 ]
end
end
table . sort ( flat , canonicalOrder )
local ids = { }
for j , m in ipairs ( flat ) do
ids [ j ] = m . id
end

local internKey = "union(" .. table . concat ( ids , "|" ) .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

local hasNil = false
for _ , m in ipairs ( flat ) do
if m == types . nil_ then
hasNil = true
end
end

return intern ( internKey , _G.setmetatable({ tag =  "union" ,  members =  flat ,  hasNil =  hasNil ,  id =  "" }, types.Union) )
end







local function pushIntersectionMember ( t , seen , flat ) 
if t == types . any then
seen [ types . any ] = true
elseif t == types . never then
for index = # flat , 1 , -1 do
flat [ index ] = nil
end
for member in pairs ( seen ) do
seen [ member ] = nil
end
flat [ 1 ] = types . never
seen [ types . never ] = true
elseif t . tag == "intersection" then
for _ , m in ipairs ( t . members ) do
pushIntersectionMember ( m , seen , flat )
end
elseif t ~= types . unknown and not seen [ t ] and not seen [ types . never ] then
seen [ t ] = true
flat [ # flat + 1 ] = t
end
end







function types . intersection ( members ) 
local seen = { }
local flat = { }

for _ , m in ipairs ( members ) do
pushIntersectionMember ( m , seen , flat )
end
if # flat == 0 then
if seen [ types . any ] then
return types . any
end
return types . unknown
end
if # flat == 1 then
return flat [ 1 ]
end
table . sort ( flat , canonicalOrder )
local ids = { }
for j , m in ipairs ( flat ) do
ids [ j ] = m . id
end

local internKey = "intersection(" .. table . concat ( ids , "&" ) .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "intersection" ,  members =  flat ,  id =  "" }, types.Intersection) )
end


function types . optional ( t ) 
if t . tag == "affine" and # ( t . cleanups or { } ) > 0 then
local payload = types . union ( { types . unwrapOwnership ( t ) , types . nil_ } )
return types . withOwnershipPayload ( t , payload , { } )
end

return types . union ( { t , types . nil_ } )
end


function types . ptr ( t ) 
local internKey = t . id .. "*"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "ptr" ,  elem =  t ,  id =  "" }, types.Ptr) )
end


function types . functionCleanup ( key , name , functionType ) 
return ( _G.setmetatable({ id =
"function:" .. key ,  kind =
"function" ,  key =
key ,  name =
name ,  functionType =
functionType ,  constTerm =
types . constLiteral ( "function" , key ) }, types.Cleanup) )

end


function types . constFunctionCleanup ( term , name , functionType ) 
local key = term . tag == "constLiteral" and term . domain == "function" and term . value or nil
return ( _G.setmetatable({ id =
key and "function:" .. key or "functionconst:" .. term . id ,  kind =
"function" ,  key =
key ,  name =
name or key and ( key : match ( "#(.*)$" ) or key ) or types . tostringConst ( term ) ,  functionType =
functionType ,  constTerm =
term }, types.Cleanup) )

end


function types . closureCleanup ( ) 
return ( _G.setmetatable({ id =  "generated:closure" ,  kind =  "closure" }, types.Cleanup) )
end


function types . methodCleanup ( name ) 
return ( _G.setmetatable({ id =  "method:" .. name ,  kind =  "method" ,  name =  name }, types.Cleanup) )
end


function types . fieldCleanup ( field , cleanup ) 
return ( _G.setmetatable({ id =
"field:" .. field .. ":" .. cleanup . id ,  kind =
"field" ,  field =
field ,  cleanup =
cleanup }, types.Cleanup) )

end


function types . dropFieldCleanup ( field ) 
return ( _G.setmetatable({ id =  "dropfield:" .. field ,  kind =  "dropfield" ,  field =  field }, types.Cleanup) )
end







local function obligationId ( obligation ) 
if not obligation then
return "none"
end
if obligation . kind == "cleanup" then
return "cleanup(" .. (
obligation . cleanup and obligation . cleanup . id or "?"
) .. ")@" .. ( obligation . component or "" )
elseif obligation . kind == "transfer-only" then
return "transfer@" .. ( obligation . component or "" )
elseif obligation . kind ~= "aggregate" then
return "none"
end
local children = { }
for j , child in ipairs ( obligation . children or { } ) do
children [ j ] = obligationId ( child )
end

return "aggregate(" .. table . concat ( children , "," ) .. ")@" .. ( obligation . component or "" )
end

function types . cleanupObligation ( cleanup , component ) 
return ( _G.setmetatable({ kind =  "cleanup" ,  cleanup =  cleanup ,  component =  component }, types.Obligation) )
end

function types . transferObligation ( component ) 
return ( _G.setmetatable({ kind =  "transfer-only" ,  component =  component }, types.Obligation) )
end

function types . aggregateObligation ( children , component ) 
return ( _G.setmetatable({ kind =  "aggregate" ,  children =  children ,  component =  component }, types.Obligation) )
end

local function obligationFrom ( cleanups , transferOnly ) 
local children = { }
for _ , cleanup in ipairs ( cleanups ) do
children [ # children + 1 ] = types . cleanupObligation ( cleanup , cleanup . field )
end
if transferOnly or # children == 0 then
children [ # children + 1 ] = types . transferObligation ( )
end
if # children == 1 and not children [ 1 ] . component then
return children [ 1 ]
end

return types . aggregateObligation ( children )
end

function types . affine (
t ,
cleanups ,
transferOnly ,
obligation
) 
local list = { }
local ids = { }
for j , cleanup in ipairs ( cleanups or { } ) do
list [ j ] = cleanup
ids [ j ] = cleanup . id
end

obligation = obligation or obligationFrom ( list , transferOnly )
if t . tag == "affine" and obligationId ( t . obligation ) == obligationId ( obligation ) then
return t
end
local internKey = "affine(" .. table . concat (
ids ,
","
) .. ":" .. t . id .. ( transferOnly and ":transfer" or "" ) .. ":" .. obligationId ( obligation ) .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern (
internKey ,
_G.setmetatable({ tag =
"affine" ,  inner =
t ,  cleanups =
list ,  transferOnly =
transferOnly == true ,  obligation =
obligation ,  id =  "" }, types.Affine)

)
end


function types . inherentOwner ( t ) 
local raw = types . unwrapOwnership ( t )
local representation = raw
if representation . tag == "typevar" then
local seen = { }
while representation . tag == "typevar" and representation . bound and not seen [ representation ] do
seen [ representation ] = true
representation = types . unwrapOwnership ( representation . bound )
end
end
local nominal = representation . tag == "nominal" and representation or nil
if not nominal and raw . tag == "union" and raw . hasNil then
for _ , member in ipairs ( raw . members ) do
if member ~= types . nil_ then
if nominal or member . tag ~= "nominal" then
nominal = nil
do break end
end
nominal = member
end
end
end


if nominal and nominal . selfType == raw then
return t
end
local cleanup = nominal and nominal . inherentCleanup or nil
if cleanup then
return types . affine ( raw , { cleanup } )
end
if raw . tag == "typevar" then
return t
end
if nominal and nominal . affineFields and # nominal . affineFields > 0 then
local cleanups , obligations , transferOnly = { } , { } , false
for j = # nominal . affineFields , 1 , -1 do
local name = nominal . affineFields [ j ]
local field = nominal . byname [ name ]
local capability = field and types . capability ( field ) or nil
if capability and capability . obligation then
transferOnly = transferOnly or types . capabilityTransferOnly ( capability )
obligations [ # obligations + 1 ] = types . aggregateObligation ( { capability . obligation } , name )
for _ , fieldCleanup in ipairs ( types . capabilityCleanups ( capability ) ) do
cleanups [ # cleanups + 1 ] = types . fieldCleanup ( name , fieldCleanup )
end
end
end
if # obligations > 0 then
return types . affine ( raw , cleanups , transferOnly , types . aggregateObligation ( obligations ) )
end
end

return t
end

function types . obligationFor ( t ) 
return t . tag == "affine" and t . obligation or nil
end

function types . borrowed ( t ) 
local internKey = "borrowed(" .. t . id .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "borrowed" ,  inner =  t ,  id =  "" }, types.Borrowed) )
end




function types . pinned ( t ) 
local internKey = "pinned(" .. t . id .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "pinned" ,  inner =  t ,  id =  "" }, types.Pinned) )
end


function types . unwrapOwnership ( t ) 
if t . tag == "affine" or t . tag == "borrowed" or t . tag == "pinned" then
return t . inner
end
return t
end

local function sortedFlowValues ( values ) 
local result , seen = { } , { }
for _ , value in ipairs ( values or { } ) do
if value ~= nil and not seen [ value ] then
seen [ value ] = true
result [ # result + 1 ] = value
end
end
table . sort ( result , function ( left , right ) 
return flowIdentity ( left ) < flowIdentity ( right )
end )

return result
end

local function loanId ( loan ) 
local roots = { }
for j , root in ipairs ( loan . roots ) do
roots [ j ] = tostring ( flowIdentity ( root ) )
end

return loan . access .. ":" .. tostring (
flowIdentity ( loan . regionRoot )
) .. ":" .. loan . regionPath .. ":" .. table . concat ( roots , "," ) .. "@" .. ( loan . component or "" )
end

local function anchorId ( anchor ) 
return tostring ( flowIdentity ( anchor . root ) ) .. "@" .. ( anchor . component or "" )
end

local function retentionId ( retention ) 
return tostring ( flowIdentity ( retention . identity ) ) .. "@" .. ( retention . component or "" )
end




local function insertById ( list , idOf ) 
for j = 2 , # list do
local value , k = list [ j ] , j - 1
local id = idOf ( value )
while k > 0 and id < idOf ( list [ k ] ) do
list [ k + 1 ] = list [ k ]
k = k - 1
end
list [ k + 1 ] = value
end
end


function types . hasCopyableBound ( t , seen ) 
if t . tag == "nominal" then
if ( ( t . origin or t ) ) . intrinsicCopyable then
return true
end
if not t . supertypes or # t . supertypes == 0 then
return false
end
end
seen = seen or { }
if seen [ t ] then
return false
end
seen [ t ] = true
if t . tag == "nominal" then
for _ , parent in ipairs ( t . supertypes or { } ) do
if types . hasCopyableBound ( parent , seen ) then
return true
end
end
elseif t . tag == "typevar" and t . bound then
return types . hasCopyableBound ( t . bound , seen )
elseif t . tag == "intersection" or t . tag == "union" then
for _ , member in ipairs ( t . members ) do
if types . hasCopyableBound ( member , seen ) then
return true
end
end
end

return false
end



function types . capability ( t , facts ) 




if t . tag ~= "affine"
and t . tag ~= "borrowed"
and t . tag ~= "pinned"
and (
not facts
or facts . loans == nil
and facts . roots == nil
and facts . regionRoot == nil
and facts . anchors == nil
and facts . retentions == nil
and facts . retention == nil
)
then
local id = "none:loans=:anchors=:retentions="
local found = capabilityArena [ "none:loans=:anchors=:retentions=" ]
if not found then
found = _G.setmetatable({ id =  id ,  loans =  { } ,  anchors =  { } ,  retentions =  { } }, types.Capability)
capabilityArena [ "none:loans=:anchors=:retentions=" ] = found
end
return found
end
facts = facts or _G.setmetatable({ }, types.CapabilityFacts)
local obligation = types . obligationFor ( t )
local loans = { }
for _ , loan in ipairs ( facts . loans or { } ) do
loans [ # loans + 1 ] = loan
end
local roots = sortedFlowValues ( facts . roots )
if t . tag == "borrowed" or # roots > 0 or facts . regionRoot then
loans [
# loans + 1
] = _G.setmetatable({ roots =
roots ,  access =
facts . exclusive and "exclusive" or "shared" ,  regionRoot =
facts . regionRoot or roots [ 1 ] ,  regionPath =
facts . regionPath or "" ,  component =
facts . component }, types.Loan)

end
insertById ( loans , loanId )

local anchors = { }
for _ , anchor in ipairs ( facts . anchors or { } ) do
anchors [ # anchors + 1 ] = anchor
end
if t . tag == "pinned" and # anchors == 0 then
anchors [ 1 ] = _G.setmetatable({ root =  facts . anchor or t ,  component =  facts . component }, types.PinnedAnchor)
end
insertById ( anchors , anchorId )

local retentions = { }
for _ , retention in ipairs ( facts . retentions or { } ) do
retentions [ # retentions + 1 ] = retention
end
if facts . retention then
retentions [
# retentions + 1
] = _G.setmetatable({ identity =  facts . retention ,  component =  facts . component }, types.ForeignRetention)
end
insertById ( retentions , retentionId )

local loanIds , anchorIds , retentionIds = { } , { } , { }
for j , loan in ipairs ( loans ) do
loanIds [ j ] = loanId ( loan )
end
for j , anchor in ipairs ( anchors ) do
anchorIds [ j ] = ( tostring ( flowIdentity ( anchor . root ) ) .. "@" .. ( anchor . component or "" ) )
end
for j , retention in ipairs ( retentions ) do
retentionIds [ j ] = ( tostring ( flowIdentity ( retention . identity ) ) .. "@" .. ( retention . component or "" ) )
end
local id = obligationId (
obligation
) .. ":loans=" .. table . concat (
loanIds ,
";"
) .. ":anchors=" .. table . concat ( anchorIds , ";" ) .. ":retentions=" .. table . concat ( retentionIds , ";" )
local found = capabilityArena [ id ]
if found then
return found
end
local made = _G.setmetatable({ id =
id ,  obligation =
obligation ,  loans =
loans ,  anchors =
anchors ,  retentions =
retentions }, types.Capability)

capabilityArena [ id ] = made

return made
end

function types . capabilityKind ( capability ) 
if capability . obligation then
return "affine"
elseif # capability . anchors > 0 or # capability . retentions > 0 then
return "pinned"
elseif # capability . loans > 0 then
return "borrowed"
end

return nil
end




function types . containedOwnershipKind ( t ) 
local direct = types . capabilityKind ( types . capability ( t ) )
if direct then
return direct
end
if t . tag == "union" or t . tag == "intersection" then
local found = nil
for _ , member in ipairs ( t . members ) do
local kind = types . containedOwnershipKind ( member )
if kind == "affine" then
return kind
elseif kind then
found = found or kind
end
end
return found
end

return nil
end




function types . containedOwnershipPayload ( t ) 
if t . tag == "affine" or t . tag == "borrowed" or t . tag == "pinned" then
return types . containedOwnershipPayload ( t . inner )
end
if t . tag == "union" then
local members = { }
for j , member in ipairs ( t . members ) do
members [ j ] = types . containedOwnershipPayload ( member )
end
return types . union ( members )
end

return t
end

function types . capabilityHasMovable ( capability ) 
return capability . obligation ~= nil or # capability . anchors > 0 or # capability . retentions > 0
end

local function collectObligationCleanups ( obligation , into ) 
if not obligation then
return
end
if obligation . kind == "cleanup" and obligation . cleanup then
into [ # into + 1 ] = obligation . cleanup
else
for _ , child in ipairs ( obligation . children or { } ) do
collectObligationCleanups ( child , into )
end
end
end

function types . capabilityCleanups ( capability ) 
local cleanups = { }
collectObligationCleanups ( capability . obligation , cleanups )
return cleanups
end

local function obligationHasTransfer ( obligation ) 
if not obligation then
return false
end
if obligation . kind == "transfer-only" then
return true
elseif obligation . kind == "cleanup" then
return false
elseif obligation . kind ~= "aggregate" then
return false
end
for _ , child in ipairs ( obligation . children or { } ) do
if obligationHasTransfer ( child ) then
return true
end
end

return false
end

function types . capabilityTransferOnly ( capability ) 
return obligationHasTransfer ( capability . obligation )
end

function types . valueSlot ( t , facts ) 
return ( _G.setmetatable({ payload =  types . unwrapOwnership ( t ) ,  capability =  types . capability ( t , facts ) }, types.ValueSlot) )
end




local function regionAppend ( path , kind , value ) 
return ( path or "" ) .. "/" .. kind .. tostring ( # value ) .. ":" .. value
end

function types . regionField ( path , name ) 
return ( ( path or "" ) .. "/" .. "F" .. tostring ( # name ) .. ":" .. name )
end

function types . regionTupleSlot ( path , slot ) 
return regionAppend ( path , "T" , tostring ( slot ) )
end

function types . regionDeref ( path ) 
return ( ( path or "" ) .. "/" .. "D" .. tostring ( 0 ) .. ":" )
end

function types . regionIndex ( path , index ) 
return regionAppend ( path , index and "I" or "U" , index and tostring ( index ) or "" )
end



function types . regionRange ( path , first , last ) 
if not first or not last then
return ( ( path or "" ) .. "/" .. "U" .. tostring ( 0 ) .. ":" )
end

return regionAppend ( path , "R" , tostring ( first ) .. ":" .. tostring ( last ) )
end

function types . regionPartition ( path , side ) 
return ( ( path or "" ) .. "/" .. "P" .. tostring ( # side ) .. ":" .. side )
end

local function regionSegments ( path ) 



local result = { }
path = path or ""
local at = 1
while at <= # path do
if path : sub ( at , at ) ~= "/" then
return { { kind = "U" , value = "" } }
else
local kind = path : sub ( at + 1 , at + 1 )
local colon = path : find ( ":" , at + 2 , true )
if not colon then
return { { kind = "U" , value = "" } }
end
local length = tonumber ( path : sub ( at + 2 , colon - 1 ) )
if not length then
return { { kind = "U" , value = "" } }
end
local value = path : sub ( colon + 1 , colon + length )
result [ # result + 1 ] = { kind = kind , value = value }
at = colon + length + 1
end
end

return result
end

function types . regionsOverlap ( left , right ) 
local a , b = regionSegments ( left ) , regionSegments ( right )
local common = math . min ( # a , # b )
for j = 1 , common do
local x , y = a [ j ] , b [ j ]
if x . kind == "U" or y . kind == "U" then
return true
end
if x . kind == "R" and y . kind == "R" then
local xf , xl = x . value : match ( "^(-?%d+):(-?%d+)$" )
local yf , yl = y . value : match ( "^(-?%d+):(-?%d+)$" )
if not xf or not yf then
return true
end
if tonumber ( xl ) < tonumber ( yf ) or tonumber ( yl ) < tonumber ( xf ) then
return false
end
elseif x . kind == "R" and y . kind == "I" or x . kind == "I" and y . kind == "R" then
local range , index = x . kind == "R" and x or y , x . kind == "I" and x or y
local first , last = range . value : match ( "^(-?%d+):(-?%d+)$" )
local at = tonumber ( index . value )
if not first or not at then
return true
end
if at < tonumber ( first ) or at > tonumber ( last ) then
return false
end
elseif x . kind ~= y . kind or x . value ~= y . value then
return false
end
end

return true
end

function types . regionContains ( parent , child ) 
local a , b = regionSegments ( parent ) , regionSegments ( child )
if # a > # b then
return false
end
for j = 1 , # a do
if a [ j ] . kind ~= b [ j ] . kind or a [ j ] . value ~= b [ j ] . value then
return false
end
end

return true
end

function types . regionLastPartition ( path ) 
local segments = regionSegments ( path )
local last = segments [ # segments ]
return last and last . kind == "P" and last . value or nil
end

local function preservedPath ( t , target , seen ) 
if types . unwrapOwnership ( t ) . id == target . id then
return { }
end
t = types . unwrapOwnership ( t )
seen = seen or { }
if seen [ t ] then
return nil
end
seen [ t ] = true
local found = nil

local function consider ( name , child ) 
local suffix = preservedPath ( child , target , seen )
if suffix then
local path = { name }
for _ , segment in ipairs ( suffix ) do
path [ # path + 1 ] = segment
end
if found then
found = nil
return false
end
found = path
end

return true
end

if t . tag == "nominal" then
for name in pairs ( t . fieldDefs or { } ) do
local child = t . byname [ name ]
if child and not consider ( name , child ) then
return nil
end
end
elseif t . tag == "shape" then
for _ , field in ipairs ( t . fields ) do
local child = field . type or field . read or field . write
if child and not consider ( field . name , child ) then
return nil
end
end
elseif t . tag == "tuple" then
for j , child in ipairs ( t . elems ) do
if not consider ( tostring ( j ) , child ) then
return nil
end
end
elseif t . tag == "union" or t . tag == "intersection" then





for _ , member in ipairs ( t . members ) do
if member ~= types . nil_ then
local path = preservedPath ( member , target , seen )
if path then
if found and table . concat ( found , "." ) ~= table . concat ( path , "." ) then
return nil
end
found = path
end
end
end
elseif t . tag == "neutral" and t . op == "mapped" and not t . remap then




local keys = t . keys
local value = t . value
local subject = keys and keys . tag == "neutral" and keys . op == "keyof" and keys . subject or nil
if subject
and value
and value . tag == "neutral"
and value . op == "member"
and value . subject == subject
and value . key == t . binder
then
found = preservedPath ( subject , target , seen )
end
end
seen [ t ] = nil

return found
end

local function cleanupAtPath ( cleanup , path ) 
for j = # path , 1 , -1 do
cleanup = types . fieldCleanup ( path [ j ] , cleanup )
end
return cleanup
end

local function obligationAtPath ( obligation , path ) 
local component = table . concat ( path , "." )
if obligation . kind == "cleanup" and obligation . cleanup then
return types . cleanupObligation ( cleanupAtPath ( obligation . cleanup , path ) , component )
elseif obligation . kind == "transfer-only" then
return types . transferObligation ( component )
end
local children = { }
for j , child in ipairs ( obligation . children or { } ) do
children [ j ] = obligationAtPath ( child , path )
end

return types . aggregateObligation ( children , component )
end






function types . withOwnershipPayload ( source , payload , selectedPath ) 
local slot = types . valueSlot ( source )
if slot . capability . obligation then


local owned = source . tag == "affine" and ( source ) . cleanups
or types . capabilityCleanups ( slot . capability )
local path = selectedPath or preservedPath ( payload , slot . payload )
if path and # path > 0 then
local cleanups = { }
for j , cleanup in ipairs ( owned ) do
cleanups [ j ] = cleanupAtPath ( cleanup , path )
end
return types . affine (
payload ,
cleanups ,
types . capabilityTransferOnly ( slot . capability ) ,
obligationAtPath ( slot . capability . obligation , path )
)
end
return types . affine ( payload , owned , types . capabilityTransferOnly ( slot . capability ) , slot . capability . obligation )
elseif # slot . capability . loans > 0 then
return types . borrowed ( payload )
elseif # slot . capability . anchors > 0 then
return types . pinned ( payload )
end

return payload
end



function types . preservationPath ( payload , source ) 
return preservedPath ( payload , types . unwrapOwnership ( source ) )
end

local function packTailId ( tail ) 
if not tail then
return ""
end
if tail . kind == "homogeneous" then
return "..." .. ( tail . mode or "plain" ) .. ":" .. tail . type . id
end
if tail . kind == "generic" then
return tail . var . id .. "..."
end
if tail . kind == "computed" then
return "unpackof(" .. tail . type . id .. ")"
end
if tail . kind == "slice" then
return "slice(" .. tostring ( tail . id ) .. ")"
end

return "...unknown"
end


function types . pack ( head , tail , modes , names ) 
local hs , ms , copied = { } , { } , { }
local named = false
local copiedNames = { }
for j , t in ipairs ( head or { } ) do
copied [ j ] , hs [ j ] = t , t . id
ms [ j ] = modes and modes [ j ] or "plain"
copiedNames [ j ] = names and names [ j ] or ""
named = named or copiedNames [ j ] ~= ""
end
local keyParts = { }
for j , id in ipairs ( hs ) do
keyParts [ j ] = ms [ j ] .. ":" .. id .. ( copiedNames [ j ] ~= "" and ( "=" .. copiedNames [ j ] ) or "" )
end
local key = "pack(" .. table . concat ( keyParts , "," ) .. packTailId ( tail ) .. ")"
local found = packArena [ key ]
if found then
return found
end
local made = _G.setmetatable({ tag =  "pack" ,  head =  copied ,  modes =  ms ,  tail =  tail ,  id =  "" }, types.Pack)
if named then
made . names = copiedNames
end
made . id = inheritedMarks ( key ) .. serial ( "p" )
packArena [ key ] = made

return made
end

function types . packvar ( name , identity ) 
local key = "pv(" .. ( identity or name ) .. ")"
local found = packVarArena [ key ]
if found then
return found
end
local made = _G.setmetatable({ tag =  "packvar" ,  name =  name ,  identity =  identity ,  id =  "" }, types.PackVar)
made . id = "!p" .. serial ( "pv" )
packVarArena [ key ] = made

return made
end





local function internSpelling ( value ) 
if type ( value ) == "number" then
return string . format ( "%.17g" , value )
end

return tostring ( value )
end

function types . constLiteral ( domain , value ) 
local key = "cl(" .. domain .. ":" .. internSpelling ( value ) .. ")"
local found = constArena [ key ]
if found then
return found
end
local made = _G.setmetatable({ tag =  "constLiteral" ,  domain =  domain ,  value =  value ,  id =  "" }, types.ConstLiteral)
made . id = serial ( "c" )
constArena [ key ] = made

return made
end

function types . constvar ( name , domain , identity ) 
local key = "cv(" .. ( identity or name ) .. ":" .. domain .. ")"
local found = constArena [ key ]
if found then
return found
end
local made = _G.setmetatable({ tag =  "constVar" ,  name =  name ,  domain =  domain ,  identity =  identity ,  id =  "" }, types.ConstVar)
made . id = "!c" .. serial ( "c" )
constArena [ key ] = made

return made
end

function types . constOp ( operation , operands ) 
local ids = { }
for j , operand in ipairs ( operands ) do
ids [ j ] = operand . id
end
local key = "co(" .. operation .. ":" .. table . concat ( ids , "," ) .. ")"
local found = constArena [ key ]
if found then
return found
end
local made = _G.setmetatable({ tag =  "constOp" ,  operation =  operation ,  operands =  operands ,  id =  "" }, types.ConstOp)
made . id = inheritedMarks ( key ) .. serial ( "c" )
constArena [ key ] = made

return made
end


const ESCAPES

= {
[ 7 ] = "\\a" ,
[ 8 ] = "\\b" ,
[ 9 ] = "\\t" ,
[ 10 ] = "\\n" ,
[ 11 ] = "\\v" ,
[ 12 ] = "\\f" ,
[ 13 ] = "\\r" ,
[ 34 ] = "\\\"" ,
[ 92 ] = "\\\\" ,
}









local function quoteConstant ( value ) 
if value == true then
return "true"
elseif value == false then
return "false"
end
local out = { "\"" }
for index = 1 , # value do
local code = ( value : byte ( index ) or 0 )
local escape = ESCAPES [ code ]
if escape then
out [ # out + 1 ] = escape
elseif code < 32 or code >= 127 then
local following = ( value : byte ( index + 1 ) or 0 )
local digits = following >= 48 and following <= 57 and "\\%03d" or "\\%d"
out [ # out + 1 ] = ( digits ) : format ( code )
else
out [ # out + 1 ] = string . char ( code )
end
end
out [ # out + 1 ] = "\""

return table . concat ( out )
end

function types . tostringConst ( term ) 
if term . tag == "constLiteral" then



if term . domain == "function" then
local value = term . value

return value : match ( "#(.*)$" ) or value
end

return term . domain == "string" and quoteConstant ( term . value ) or tostring ( term . value )
elseif term . tag == "constVar" then
return term . name
end
if # term . operands == 1 then
return term . operation .. types . tostringConst ( term . operands [ 1 ] )
end

return "(" .. types . tostringConst (
term . operands [ 1 ]
) .. " " .. term . operation .. " " .. types . tostringConst ( term . operands [ 2 ] ) .. ")"
end

function types . packUnion ( alternatives ) 
local flat = { }
local seen , ids = { } , { }
for _ , p in ipairs ( alternatives ) do
for _ , q in ipairs ( p . alternatives or { p } ) do
if not seen [ q . id ] then
seen [ q . id ] = true ;
flat [ # flat + 1 ] = q
end
end
end
table . sort ( flat , function ( a , b ) 
return a . id < b . id
end )
if # flat == 1 then
return flat [ 1 ]
end
for j , p in ipairs ( flat ) do
ids [ j ] = p . id
end
local key = "packunion(" .. table . concat ( ids , "|" ) .. ")"
local found = packArena [ key ]
if found then
return found
end
local made = _G.setmetatable({ tag =  "pack" ,  head =  { } ,  modes =  { } ,  alternatives =  flat ,  id =  "" }, types.Pack)
made . id = key
packArena [ key ] = made

return made
end

function types . packAt ( pack , index ) 
if pack . alternatives then
local members = { }
for _ , arm in ipairs ( pack . alternatives ) do
members [ # members + 1 ] = types . packAt ( arm , index ) or types . nil_
end
return types . union ( members )
end
if pack . head [ index ] then
return pack . head [ index ]
end
local tail = pack . tail
if tail and ( tail . kind == "homogeneous" or tail . kind == "unknown" ) then
return tail . type or types . any
end

return nil
end

function types . protocolThread (
startPack ,
resumePack ,
yieldPack ,
returnPack
) 
local key = "thread<" .. startPack . id .. "," .. resumePack . id .. "," .. yieldPack . id .. "," .. returnPack . id .. ">"
local existing = ( arena [ key ] )
if existing then
return existing
end

return intern (
key ,
_G.setmetatable({ tag =
"protocolThread" ,  startPack =
startPack ,  resumePack =
resumePack ,  yieldPack =
yieldPack ,  returnPack =
returnPack ,  id =  "" }, types.ProtocolThread)

)
end

function types . genericAlias (
name ,
body ,
typeParams ,
typeBounds ,
packParams ,
constParams ,
paramKinds ,
paramDefaults
) 
local parts = { "alias(" .. name , body . id }
for _ , tv in ipairs ( typeParams or { } ) do
parts [ # parts + 1 ] = tv . id
end
for _ , pv in ipairs ( packParams or { } ) do
parts [ # parts + 1 ] = pv . id
end
for _ , cv in ipairs ( constParams or { } ) do
parts [ # parts + 1 ] = cv . id
end
local key = table . concat ( parts , "|" ) .. ")"

local existing = ( arena [ key ] )
if existing then




local alias = existing
alias . typeBounds = typeBounds or { }
alias . paramKinds = paramKinds or { }
alias . paramDefaults = paramDefaults or { }
return alias
end

return intern (
key ,
_G.setmetatable({ tag =
"genericAlias" ,  name =
name ,  body =
body ,  typeParams =
typeParams or { } ,  typeBounds =
typeBounds or { } ,  packParams =
packParams or { } ,  constParams =
constParams or { } ,  paramKinds =
paramKinds or { } ,  paramDefaults =
paramDefaults or { } ,  id =  "" }, types.GenericAlias)

)
end

function types . tostringPack ( pack ) 
if pack . alternatives then
local arms = { }
for j , arm in ipairs ( pack . alternatives ) do
arms [ j ] = types . tostringPack ( arm )
end
return "(" .. table . concat ( arms , " | " ) .. ")"
end
local parts = { }
for j , t in ipairs ( pack . head ) do
parts [ j ] = types . tostring ( t )
end
if pack . tail then
if pack . tail . kind == "homogeneous" then
parts [ # parts + 1 ] = "..." .. types . tostring ( pack . tail . type )
elseif pack . tail . kind == "generic" then
parts [ # parts + 1 ] = pack . tail . var . name .. "..."
elseif pack . tail . kind == "computed" then
parts [ # parts + 1 ] = "unpackof " .. types . tostring ( pack . tail . type )
else



parts [ # parts + 1 ] = "..." .. types . tostring ( pack . tail . type or types . any )
end
end

return "(" .. table . concat ( parts , ", " ) .. ")"
end







function types . func (
params ,
rets ,
vararg ,
paramModes ,
predicate ,
typeParams ,
typeBounds ,
borrowsParam ,
borrowsSelf ,
borrowsParams ,
ffiOut ,
varargType ,
noreturn ,
paramPack ,
retPack ,
packParams ,
yieldPack ,
resumePack ,
noYield ,
paramNames ,
preservesResults ,
foreign ,
constParams ,
paramKinds ,
partitionResults ,
comptimeOnly ,
explicitPreserves ,
sendable ,
borrowsResult
) 



if # rets == 1 and rets [ 1 ] == types . never then
noreturn = true
end
local modes = { }
local names = { }
local preservesPaths = { }
for j = 1 , # params do
modes [ j ] = paramModes and paramModes [ j ] or "plain"
names [ j ] = paramNames and paramNames [ j ] or ""
end
paramPack = paramPack
or types . pack (
params ,
vararg and { kind = varargType and "homogeneous" or "unknown" , type = varargType or types . any } or nil ,
modes
)
retPack = retPack or types . pack ( rets )





vararg = paramPack . tail ~= nil
local key = "fn" .. paramPack . id .. ":" .. retPack . id
if predicate then
key = key .. "|is" .. predicate . param .. ":" .. predicate . type . id
end
if typeParams and # typeParams > 0 then
local genericParts = { }
for j , tv in ipairs ( typeParams ) do
genericParts [ j ] = tv . id .. "<:" .. ( ( typeBounds and typeBounds [ j ] ) and typeBounds [ j ] . id or "any" )
end
key = key .. "|<" .. table . concat ( genericParts , "," ) .. ">"
end
if packParams and # packParams > 0 then
local pp = { }
for j , pv in ipairs ( packParams ) do
pp [ j ] = pv . id
end
key = key .. "|<" .. table . concat ( pp , "," ) .. ">"
end
if constParams and # constParams > 0 then
local cp = { }
for j , cv in ipairs ( constParams ) do
cp [ j ] = cv . id
end
key = key .. "|<const " .. table . concat ( cp , "," ) .. ">"
end
if paramKinds and # paramKinds > 0 then
key = key .. "|kinds(" .. table . concat ( paramKinds , "," ) .. ")"
end
if yieldPack then
key = key .. "|yields" .. yieldPack . id
end
if resumePack then
key = key .. "|resumes" .. resumePack . id
end
if borrowsParam then
key = key .. "|borrows" .. borrowsParam
end
if borrowsParams and # borrowsParams > 0 then
key = key .. "|borrows(" .. table . concat ( borrowsParams , "," ) .. ")"
end
if borrowsResult and borrowsResult ~= 1 then
key = key .. "|borrowsinto" .. borrowsResult
end
for _ , output in ipairs ( ffiOut or { } ) do
local cleanupIds = { }
for j , cleanup in ipairs ( output . cleanups or { } ) do
cleanupIds [ j ] = cleanup . id
end
local sourceIds = { }
for j , sourceParam in ipairs ( output . sourceParams or { } ) do
sourceIds [ j ] = tostring ( sourceParam )
end
key = key .. "|out:" .. (
output . kind or "affine"
) .. ":" .. output . name .. ":" .. table . concat (
cleanupIds ,
","
) .. ":" .. ( output . success or "always" ) .. ":" .. table . concat ( sourceIds , "," )
end
if borrowsSelf then
key = key .. "|borrowsself"
end
if preservesResults then
for result = 1 , # rets do
local source = preservesResults [ result ]
if source then
key = key .. "|preserves" .. tostring ( result ) .. ":" .. tostring ( source )
local path = params [ source ] and types . preservationPath ( rets [ result ] , params [ source ] ) or nil
if path then
preservesPaths [ result ] = path
key = key .. "@" .. table . concat ( path , "." )
else
key = key .. "@ambiguous"
end
end
end
end
if partitionResults then
for result = 1 , # rets do
local fields = partitionResults [ result ]
if fields then
local fieldNames = { }
for name in pairs ( fields ) do
fieldNames [ # fieldNames + 1 ] = name
end
table . sort ( fieldNames )
for _ , name in ipairs ( fieldNames ) do
key = key .. "|partition" .. tostring ( result ) .. ":" .. name .. "=" .. tostring ( fields [ name ] )
end
end
end
end
if noreturn then
key = key .. "|noreturn"
end
if noYield then
key = key .. "|noyield"
end
if foreign then
key = key .. "|foreign"
end
if comptimeOnly then
key = key .. "|comptime"
end
local unlabeledId = key


if sendable then
key = key .. "|sendable"
end
if explicitPreserves then
local written = { }
for result = 1 , # rets do
if explicitPreserves [ result ] then
written [ # written + 1 ] = tostring ( result )
end
end
if # written > 0 then
key = key .. "|written-preserves(" .. table . concat ( written , "," ) .. ")"
end
end
if paramNames then
key = key .. "|names(" .. table . concat ( names , "," ) .. ")"
end

local existing = ( arena [ key ] )
if existing then
return existing
end

return intern (
key ,
_G.setmetatable({ tag =
"func" ,  params =
params ,  rets =
rets ,  vararg =
vararg or false ,  varargType =
vararg and varargType or nil ,  paramModes =
modes ,  paramNames =
names ,  unlabeledId =
unlabeledId ,  predicate =
predicate ,  typeParams =
typeParams ,  typeBounds =
typeBounds ,  borrowsParam =
borrowsParam ,  borrowsSelf =
borrowsSelf ,  borrowsParams =
borrowsParams ,  borrowsResult =
borrowsResult ,  preservesResults =
preservesResults ,  explicitPreserves =
explicitPreserves ,  preservesPaths =
next ( preservesPaths ) and preservesPaths or nil ,  partitionResults =
partitionResults ,  foreign =
foreign or nil ,  ffiOut =
ffiOut ,  noreturn =
noreturn or nil ,  noYield =
noYield or nil ,  paramPack =
paramPack ,  retPack =
retPack ,  packParams =
packParams ,  constParams =
constParams ,  paramKinds =
paramKinds ,  yieldPack =
yieldPack ,  resumePack =
resumePack ,  comptimeOnly =
comptimeOnly or nil ,  sendable =
sendable or nil ,  id =  "" }, types.Func)

)
end




local FUNC_FIELDS

= {
"params" ,
"rets" ,
"vararg" ,
"paramModes" ,
"predicate" ,
"typeParams" ,
"typeBounds" ,
"borrowsParam" ,
"borrowsSelf" ,
"borrowsParams" ,
"ffiOut" ,
"varargType" ,
"noreturn" ,
"paramPack" ,
"retPack" ,
"packParams" ,
"yieldPack" ,
"resumePack" ,
"noYield" ,
"paramNames" ,
"preservesResults" ,
"foreign" ,
"constParams" ,
"paramKinds" ,
"partitionResults" ,
"comptimeOnly" ,
"explicitPreserves" ,
"sendable" ,
"borrowsResult" ,
}

















function types . funcWith ( fn , overrides ) 
local known = { }
local field = { }
for _ , name in ipairs ( FUNC_FIELDS ) do
known [ name ] = true
local value = ( fn ) [ name ]
local override = overrides [ name ]
if override ~= nil then
value = override or nil
end
field [ name ] = value
end
for name in pairs ( overrides ) do
if not known [ name ] then
error ( "types.funcWith: a function has no field " .. tostring ( name ) )
end
end

return types . func (
field . params ,
field . rets ,
field . vararg ,
field . paramModes ,
field . predicate ,
field . typeParams ,
field . typeBounds ,
field . borrowsParam ,
field . borrowsSelf ,
field . borrowsParams ,
field . ffiOut ,
field . varargType ,
field . noreturn ,
field . paramPack ,
field . retPack ,
field . packParams ,
field . yieldPack ,
field . resumePack ,
field . noYield ,
field . paramNames ,
field . preservesResults ,
field . foreign ,
field . constParams ,
field . paramKinds ,
field . partitionResults ,
field . comptimeOnly ,
field . explicitPreserves ,
field . sendable ,
field . borrowsResult
)
end






function types . withYields ( ft , mayYield ) 
if ft . tag ~= "func" then
return ft
end
local fn = ft
local want = not mayYield or nil
if ( fn . noYield or nil ) == want then
return ft
end

return types . funcWith ( fn , { noYield = not mayYield } )
end








function types . withSendable ( ft ) 
if ft . tag ~= "func" then
return ft
end
local fn = ft
if fn . sendable then
return ft
end

return types . funcWith ( fn , { sendable = true } )
end





function types . foreignFunction ( ft ) 
if ft . tag ~= "func" or ft . foreign then
return ft
end
local fn = ft

return types . funcWith ( fn , { foreign = true } )
end


function types . withFirstResult ( ft , first ) 
if ft . tag ~= "func" or not ft . rets [ 1 ] or ft . retPack . alternatives then
return ft
end
local fn = ft
local rets = { }
for j , result in ipairs ( fn . rets ) do
rets [ j ] = j == 1 and first or result
end
local retPack = types . pack ( rets , fn . retPack . tail , fn . retPack . modes )

return types . funcWith ( fn , { rets = rets , retPack = retPack } )
end




function types . withPartitionResults ( ft , partitionResults ) 
if ft . tag ~= "func" then
return ft
end
local fn = ft

return types . funcWith ( fn , { partitionResults = partitionResults } )
end





function types . literal ( value , base ) 
local of = base or types . string
local internKey = "lit(" .. of . id .. ":" .. internSpelling ( value ) .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "literal" ,  constant =  value ,  base =  of ,  id =  "" }, types.Literal) )
end









function types . constrained ( base , node , key , label ) 
local internKey = "con(" .. base . id .. ":" .. key .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern (
internKey ,
_G.setmetatable({ tag =  "constrained" ,  base =  base ,  predicate =  node ,  constraintKey =  key ,  label =  label ,  id =  "" }, types.Constrained)
)
end


function types . constraintOf ( t ) 
if t and t . tag == "constrained" then
return ( t ) . predicate
end

return nil
end






function types . unconstrained ( t ) 
if t . tag == "constrained" then
return ( t ) . base
end

return t
end





function types . carray ( elem , count , countTerm ) 
local term = countTerm or ( count and types . constLiteral ( "integer" , count ) or nil )
local internKey = "carray(" .. elem . id .. "," .. ( term and term . id or "?" ) .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "carray" ,  elem =  elem ,  count =  count ,  countTerm =  term ,  id =  "" }, types.CArray) )
end



function types . constOf ( t ) 
if t . tag == "const" then
return t
end
local internKey = "const(" .. t . id .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "const" ,  inner =  t ,  id =  "" }, types.Const) )
end


function types . ctype ( t ) 
local internKey = "ctype(" .. t . id .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "ctype" ,  of =  t ,  id =  "" }, types.CType) )
end




function types . typevar ( name , identity ) 


local internKey = "!ttv(" .. ( identity or name ) .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "typevar" ,  name =  name ,  identity =  identity ,  id =  "" }, types.TypeVar) )
end

function types . typeHandle ( bound ) 
local key = "type<" .. bound . id .. ">"
local existing = ( arena [ key ] )
if existing then
return existing
end

return intern ( key , _G.setmetatable({ tag =  "typeHandle" ,  bound =  bound ,  id =  "" }, types.TypeHandle) )
end

function types . packResult ( pack ) 
local key = "packResult(" .. pack . id .. ")"
local existing = ( arena [ key ] )
if existing then
return existing
end

return intern ( key , _G.setmetatable({ tag =  "packResult" ,  pack =  pack ,  id =  "" }, types.PackResult) )
end




function types . neutral (
op ,
subject ,
key ,
capability ,
binder ,
keys ,
value ,
remap ,
constTerm ,
templateParts
) 





local templateIds = { }
for j , part in ipairs ( templateParts or { } ) do
templateIds [ j ] = type ( part ) == "string" and "s" .. # ( part ) .. ":" .. ( part )
or "t:" .. ( part ) . id
end
local id = "neutral(" .. op .. ":" .. (
capability or "-"
) .. ":" .. (
subject and subject . id or "-"
) .. ":" .. (
key and key . id or "-"
) .. ":" .. (
binder and binder . id or "-"
) .. ":" .. (
keys and keys . id or "-"
) .. ":" .. (
value and value . id or "-"
) .. ":" .. (
remap and remap . id or "-"
) .. ":" .. ( constTerm and constTerm . id or "-" ) .. ":" .. table . concat ( templateIds , "," ) .. ")"

local existing = ( arena [ id ] )
if existing then
return existing
end

return intern (
id ,
_G.setmetatable({ tag =
"neutral" ,  op =
op ,  capability =
capability ,  subject =
subject ,  key =
key ,  binder =
binder ,  keys =
keys ,  value =
value ,  remap =
remap ,  constTerm =
constTerm ,  templateParts =
templateParts ,  id =  "" }, types.Neutral)

)
end




function types . comptimeCall (
identity ,
helper ,
arguments ,
bound ,
resultPack
) 
local ids = { identity , bound and bound . id or types . unknown . id , resultPack and "pack" or "type" }
for _ , argument in ipairs ( arguments ) do
if argument . kind == "type" then
ids [ # ids + 1 ] = "t:" .. argument . value . id
elseif argument . kind == "typepack" then
ids [ # ids + 1 ] = "p:" .. argument . value . id
else
ids [ # ids + 1 ] = "c:" .. argument . value . id
end
end
local id = "neutral(comptime:" .. table . concat ( ids , "," ) .. ")"

local existing = ( arena [ id ] )
if existing then
local neutral = existing
if helper ~= nil and neutral . comptimeHelper == nil then
neutral . comptimeHelper = helper
end
return existing
end

return intern (
id ,
_G.setmetatable({ tag =
"neutral" ,  op =
"comptimeCall" ,  comptimeIdentity =
identity ,  comptimeHelper =
helper ,  comptimeArguments =
arguments ,  comptimeBound =
bound or types . unknown ,  comptimeResultPack =
resultPack ,  id =  "" }, types.Neutral)

)
end

function types . metatable ( t ) 
local internKey = "metatable(" .. t . id .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "metatable" ,  of =  t ,  id =  "" }, types.Metatable) )
end


function types . typeObject ( t ) 
local internKey = "Type(" .. t . id .. ")"
local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "typeobject" ,  of =  t ,  id =  "" }, types.TypeObject) )
end


function types . projection ( of , name ) 
local internKey = "!jproj(" .. of . id .. "," .. name .. ")"

local existing = ( arena [ internKey ] )
if existing then
return existing
end

return intern ( internKey , _G.setmetatable({ tag =  "projection" ,  of =  of ,  name =  name ,  id =  "" }, types.Projection) )
end



function types . hasProjection ( t ) 
return t . id : find ( "!j" , 1 , true ) ~= nil
end


local function packHasTypevar ( pack ) 
if pack . id : find ( "!t" , 1 , true )
or pack . id : find ( "!p" , 1 , true )
or pack . id : find ( "!c" , 1 , true )
then
return true
end
for _ , member in ipairs ( pack . head ) do
if types . hasTypevar ( member ) then
return true
end
end
local tail = pack . tail
if tail and tail . type and types . hasTypevar ( tail . type ) then
return true
end
for _ , alternative in ipairs ( pack . alternatives or { } ) do
if packHasTypevar ( alternative ) then
return true
end
end

return false
end


function types . hasTypevar ( t ) 
if t . tag == "nominal" and t . origin then
for _ , argument in ipairs ( t . typeArgs or { } ) do
if types . hasTypevar ( argument ) then
return true
end
end
for _ , argument in ipairs ( t . packArgs or { } ) do
if argument . id : find ( "!t" , 1 , true )
or argument . id : find ( "!p" , 1 , true )
or argument . id : find ( "!c" , 1 , true )
then
return true
end
end
for _ , argument in ipairs ( t . constArgs or { } ) do
if argument . id : find ( "!c" , 1 , true ) then
return true
end
end
end







local marked = t . id : find ( "!t" , 1 , true ) ~= nil
or t . id : find ( "!p" , 1 , true ) ~= nil
or t . id : find ( "!c" , 1 , true ) ~= nil
if marked then
return true
end

local tag = t . tag
if tag == "affine" or tag == "borrowed" or tag == "pinned" or tag == "const" then
return types . hasTypevar ( t . inner )
elseif tag == "ctype" or tag == "metatable" then
return types . hasTypevar ( t . of )
elseif tag == "ptr" or tag == "carray" or tag == "array" then
return types . hasTypevar ( t . elem )
elseif tag == "typeHandle" then
return types . hasTypevar ( t . bound )
elseif tag == "map" then
return ( t . key and types . hasTypevar ( t . key ) )
or ( t . value and types . hasTypevar ( t . value ) )
or ( t . writeKey and types . hasTypevar ( t . writeKey ) )
or ( t . writeValue and types . hasTypevar ( t . writeValue ) )
or false
elseif tag == "tuple" then
for _ , member in ipairs ( t . elems ) do
if types . hasTypevar ( member ) then
return true
end
end
elseif tag == "shape" then
for _ , field in ipairs ( t . fields ) do
if field . read and types . hasTypevar ( field . read ) then
return true
end
if field . write and types . hasTypevar ( field . write ) then
return true
end
end
elseif tag == "union" or tag == "intersection" then
for _ , member in ipairs ( t . members ) do
if types . hasTypevar ( member ) then
return true
end
end
elseif tag == "func" then
for _ , member in ipairs ( t . params ) do
if types . hasTypevar ( member ) then
return true
end
end
for _ , member in ipairs ( t . rets ) do
if types . hasTypevar ( member ) then
return true
end
end
elseif tag == "projection" then
return types . hasTypevar ( t . of )
elseif tag == "packResult" then
return packHasTypevar ( t . pack )
elseif tag == "protocolThread" then
return packHasTypevar ( t . startPack )
or packHasTypevar ( t . resumePack )
or packHasTypevar ( t . yieldPack )
or packHasTypevar ( t . returnPack )
elseif tag == "neutral" then




if ( t . subject and types . hasTypevar ( t . subject ) )
or ( t . key and types . hasTypevar ( t . key ) )
or ( t . keys and types . hasTypevar ( t . keys ) )
or ( t . value and types . hasTypevar ( t . value ) )
or ( t . remap and types . hasTypevar ( t . remap ) )
or ( t . comptimeBound and types . hasTypevar ( t . comptimeBound ) )
then
return true
end
if t . constTerm and t . constTerm . id : find ( "!c" , 1 , true ) then
return true
end
for _ , part in ipairs ( t . templateParts or { } ) do
if type ( part ) == "table" and types . hasTypevar ( part ) then
return true
end
end
for _ , argument in ipairs ( t . comptimeArguments or { } ) do
if argument . kind == "type" then
if types . hasTypevar ( argument . value ) then
return true
end
elseif argument . kind == "typepack" then
if packHasTypevar ( argument . value ) then
return true
end
elseif argument . value . id : find ( "!c" , 1 , true ) then
return true
end
end
end

return false
end





local nominalCounter = 0



local declaredNominals = { }













function types . nominal ( name , declKind , declarationKey ) 
local shared = declarationKey ~= nil and identityNamespace ~= ""
if shared then
local known = declaredNominals [ declarationKey ]
if known ~= nil then
return known
end
end
nominalCounter = nominalCounter + 1
local t = _G.setmetatable({ tag =
"nominal" ,  declKind =
declKind ,  name =
name ,  byname =
{ } ,  writeByname =
{ } ,  staticByname =
{ } ,  staticWriteByname =
{ } ,  metamethods =
{ } ,  nestedTypes =
{ } ,  declarationKey =
declarationKey ,  id =  "" }, types.Nominal)

t . id = "nominal#" .. identityNamespace .. nominalCounter .. "(" .. name .. ")"
if shared then
declaredNominals [ declarationKey ] = t
end

return t
end



function types . nestedDeclarationKey ( owner , offset ) 
local key = owner . declarationKey
if key == nil then
return nil
end

return key .. "\0nested\0" .. tostring ( offset or 0 )
end






function types . tostring ( t ) 
local tag = t . tag
if tag == "constrained" then



return ( t ) . label or types . tostring ( ( t ) . base ) .. " (constrained)"
elseif tag == "nominal" then
if # ( t . typeArgs or { } ) > 0 or # ( t . packArgs or { } ) > 0 or # ( t . constArgs or { } ) > 0 then
local parts = { }
local typeAt , packAt , constAt = 1 , 1 , 1
for _ , kind in ipairs ( t . paramKinds or { } ) do
if kind == "type" then
parts [ # parts + 1 ] = types . tostring ( ( t . typeArgs ) [ typeAt ] )
typeAt = typeAt + 1
elseif kind == "pack" then
parts [ # parts + 1 ] = types . tostringPack ( ( t . packArgs ) [ packAt ] )
packAt = packAt + 1
elseif kind == "const" then
parts [ # parts + 1 ] = types . tostringConst ( ( t . constArgs ) [ constAt ] )
constAt = constAt + 1
end
end
if # parts == 0 then
for _ , argument in ipairs ( t . typeArgs or { } ) do
parts [ # parts + 1 ] = types . tostring ( argument )
end
for _ , argument in ipairs ( t . packArgs or { } ) do
parts [ # parts + 1 ] = types . tostringPack ( argument )
end
for _ , argument in ipairs ( t . constArgs or { } ) do
parts [ # parts + 1 ] = types . tostringConst ( argument )
end
end
return t . name .. "<" .. table . concat ( parts , ", " ) .. ">"
end
return t . name
elseif tag == "array" then
return "{" .. types . tostring ( t . elem ) .. "}"
elseif tag == "map" then
if t . readable and t . writeKey == t . key and t . writeValue == t . value then
return "{[" .. types . tostring ( t . key ) .. "]: " .. types . tostring ( t . value ) .. "}"
end
local parts = { }
if t . readable then
parts [ # parts + 1 ] = "@readonly [" .. types . tostring ( t . key ) .. "]: " .. types . tostring ( t . value )
end
if t . writeKey and t . writeValue then
parts [ # parts + 1 ] = "@writeonly [" .. types . tostring ( t . writeKey ) .. "]: " .. types . tostring ( t . writeValue )
end
return "{" .. table . concat ( parts , ", " ) .. "}"
elseif tag == "tuple" then
local parts = { }
for j , e in ipairs ( t . elems ) do
parts [ j ] = types . tostring ( e )
end
if # parts == 1 then
parts [ 1 ] = parts [ 1 ] .. ","
end
return "{" .. table . concat ( parts , ", " ) .. "}"
elseif tag == "shape" then
local parts = { }
for j , f in ipairs ( t . fields ) do
if f . read and f . write and f . read == f . write then
parts [ # parts + 1 ] = f . name .. ": " .. types . tostring ( f . read )
else
if f . read then
parts [ # parts + 1 ] = "@readonly " .. f . name .. ": " .. types . tostring ( f . read )
end
if f . write then
parts [ # parts + 1 ] = "@writeonly " .. f . name .. ": " .. types . tostring ( f . write )
end
end
end
if t . indexReadKey and t . indexReadValue then
parts [
# parts + 1
] = "@readonly [" .. types . tostring ( t . indexReadKey ) .. "]: " .. types . tostring ( t . indexReadValue )
end
if t . indexWriteKey and t . indexWriteValue then
parts [
# parts + 1
] = "@writeonly [" .. types . tostring ( t . indexWriteKey ) .. "]: " .. types . tostring ( t . indexWriteValue )
end
return "{" .. table . concat ( parts , ", " ) .. "}"
elseif tag == "union" then

if t . hasNil and # t . members == 2 then
local other = t . members [ 1 ] == types . nil_ and t . members [ 2 ] or t . members [ 1 ]
local rendered = types . tostring ( other )
if other . tag == "intersection" then
rendered = "(" .. rendered .. ")"
end
return rendered .. "?"
end
local parts = { }
for j , m in ipairs ( t . members ) do
parts [ j ] = types . tostring ( m )
end
return table . concat ( parts , " | " )
elseif tag == "intersection" then
local parts = { }
for j , m in ipairs ( t . members ) do
local rendered = types . tostring ( m )
if m . tag == "union" then
rendered = "(" .. rendered .. ")"
end
parts [ j ] = rendered
end
return table . concat ( parts , " & " )
elseif tag == "const" then
return "const " .. types . tostring ( t . inner )
elseif tag == "ctype" then
return "ctype<" .. types . tostring ( t . of ) .. ">"
elseif tag == "carray" then
local elem = types . tostring ( t . elem )
if t . elem . tag == "union" or t . elem . tag == "intersection" then
elem = "(" .. elem .. ")"
end
return elem .. "[" .. ( t . countTerm and types . tostringConst ( t . countTerm ) or "?" ) .. "]"
elseif tag == "ptr" then
local elem = types . tostring ( t . elem )
if t . elem . tag == "union" or t . elem . tag == "intersection" then
elem = "(" .. elem .. ")"
end
return elem .. "*"
elseif tag == "affine" then
local terminal = t . cleanups and t . cleanups [ 1 ]
return "affine(" .. types . tostring (
t . inner
) .. ( terminal and ", " .. ( terminal . name or terminal . id ) or "" ) .. ")"
elseif tag == "borrowed" then
return types . tostring ( t . inner )
elseif tag == "pinned" then
return "pinned(" .. types . tostring ( t . inner ) .. ")"
elseif tag == "typevar" then
return t . name
elseif tag == "typeHandle" then
return "type<" .. types . tostring ( t . bound ) .. ">"
elseif tag == "packResult" then
return "typepack(" .. types . tostringPack ( t . pack ) .. ")"
elseif tag == "neutral" then
if t . op == "comptimeCall" then
local arguments = { }
for _ , argument in ipairs ( t . comptimeArguments or { } ) do
if argument . kind == "type" then
arguments [ # arguments + 1 ] = types . tostring ( argument . value )
elseif argument . kind == "typepack" then
arguments [ # arguments + 1 ] = types . tostringPack ( argument . value )
else
arguments [ # arguments + 1 ] = types . tostringConst ( argument . value )
end
end
local helper = t . comptimeHelper
local name = helper and helper . name and helper . name . text or "<type function>"
return name .. "(" .. table . concat ( arguments , ", " ) .. ")"
elseif t . op == "singleton" then
return types . tostringConst ( t . constTerm )
elseif t . op == "keyof" then
return ( t . capability == "write" and "writekeyof " or "keyof " ) .. types . tostring ( t . subject )
elseif t . op == "member" then
return (
t . capability == "write" and "writeof " or ""
) .. types . tostring ( t . subject ) .. ".[" .. types . tostring ( t . key ) .. "]"
elseif t . op == "mapped" then
return "{" .. (
t . capability == "write" and "@writeonly" or "@readonly"
) .. " [" .. (
t . binder and t . binder . name or "K"
) .. " in " .. types . tostring ( t . keys ) .. "]: " .. types . tostring ( t . value ) .. "}"
elseif t . op == "template" then
local parts = { }
for j , part in ipairs ( t . templateParts or { } ) do
parts [ j ] = type ( part ) == "string" and part or "${" .. types . tostring ( part ) .. "}"
end
return "`" .. table . concat ( parts ) .. "`"
elseif t . op == "tupleConcat" then
local prefix = t . subject
local parts = { }
for j , elem in ipairs ( prefix . elems ) do
parts [ j ] = types . tostring ( elem )
end
parts [ # parts + 1 ] = "unpackof " .. types . tostring ( t . key )
return "{" .. table . concat ( parts , ", " ) .. "}"
end
return "<" .. t . op .. ">"
elseif tag == "metatable" then
return "metatable<" .. types . tostring ( t . of ) .. ">"
elseif tag == "typeobject" then
return "Type<" .. types . tostring ( t . of ) .. ">"
elseif tag == "projection" then
return types . tostring ( t . of ) .. "." .. t . name
elseif tag == "literal" then
if t . base == types . string then
return quoteConstant ( t . constant )
end
return tostring ( t . constant )
elseif tag == "func" then
local ps = { }
for j , p in ipairs ( t . params ) do
local mode = t . paramModes and t . paramModes [ j ]
local label = t . paramNames and t . paramNames [ j ]
ps [
j
] = (
mode and mode ~= "plain" and mode .. " " or ""
) .. ( label and label ~= "" and label .. ": " or "" ) .. types . tostring ( p )
end
local paramTail = t . paramPack . tail
if paramTail then
if paramTail . kind == "homogeneous" then
ps [
# ps + 1
] = (
paramTail . mode and paramTail . mode ~= "plain" and paramTail . mode .. " " or ""
) .. "...: " .. types . tostring ( paramTail . type )
elseif paramTail . kind == "generic" then
ps [ # ps + 1 ] = paramTail . var . name .. "..."
elseif paramTail . kind == "computed" then
ps [ # ps + 1 ] = "...: unpackof " .. types . tostring ( paramTail . type )
else
ps [ # ps + 1 ] = "..."
end
end
local renderedResults = { }
for j , result in ipairs ( t . retPack . head ) do
local rendered = types . tostring ( result )
local source = t . preservesResults and t . preservesResults [ j ]
if source then
local name = t . paramNames and t . paramNames [ source ]
rendered = rendered .. " preserves " .. ( name and name ~= "" and name or ( "#" .. tostring ( source ) ) )
end
renderedResults [ j ] = rendered
end
local hasRet = # t . retPack . head > 0 or t . retPack . tail ~= nil or t . retPack . alternatives ~= nil
local ret = ""
if hasRet then
ret = ": " .. (
# t . retPack . head == 1 and not t . retPack . tail and not t . retPack . alternatives and renderedResults [ 1 ]
or ( t . retPack . alternatives or t . retPack . tail ) and types . tostringPack ( t . retPack )
or "(" .. table . concat ( renderedResults , ", " ) .. ")"
)
end
local protocol = t . yieldPack
and (
" yields " .. types . tostringPack (
t . yieldPack
) .. " resumes " .. types . tostringPack (
t . resumePack or types . pack ( { } , {
kind = "unknown" ,
type = types . any
} )
)
)
or ""
local binders = { }
local typeParams = t . typeParams or { }
local packParams = t . packParams or { }
local constParams = t . constParams or { }
local typeAt = 1
local packAt = 1
local constAt = 1
for _ , kind in ipairs ( t . paramKinds or { } ) do
if kind == "type" then
binders [ # binders + 1 ] = typeParams [ typeAt ] . name
typeAt = typeAt + 1
elseif kind == "pack" then
binders [ # binders + 1 ] = packParams [ packAt ] . name .. "..."
packAt = packAt + 1
elseif kind == "const" then
local cv = constParams [ constAt ]
binders [ # binders + 1 ] = "const " .. cv . name .. ": " .. cv . domain
constAt = constAt + 1
end
end
if # binders == 0 then
for _ , tv in ipairs ( typeParams ) do
binders [ # binders + 1 ] = tv . name
end
for _ , pv in ipairs ( packParams ) do
binders [ # binders + 1 ] = pv . name .. "..."
end
for _ , cv in ipairs ( constParams ) do
binders [ # binders + 1 ] = "const " .. cv . name .. ": " .. cv . domain
end
end
local generic = # binders > 0 and "<" .. table . concat ( binders , ", " ) .. ">" or ""



local sendable = t . sendable and "sendable " or ""

return sendable .. "function" .. generic .. "(" .. table . concat ( ps , ", " ) .. ")" .. ret .. protocol
elseif tag == "protocolThread" then
return "thread<" .. types . tostringPack (
t . startPack
) .. ", " .. types . tostringPack (
t . resumePack
) .. ", " .. types . tostringPack ( t . yieldPack ) .. ", " .. types . tostringPack ( t . returnPack ) .. ">"
elseif tag == "genericAlias" then
return t . name
elseif tag == "open" then


return "..."
end

return tag
end




local C_NAME

= {
number = "double" ,
float = "float" ,
boolean = "bool" ,
integer = "int32_t" ,
int8 = "int8_t" ,
int16 = "int16_t" ,
int32 = "int32_t" ,
int64 = "int64_t" ,
uint8 = "uint8_t" ,
uint16 = "uint16_t" ,
uint32 = "uint32_t" ,
uint64 = "uint64_t" ,
cstring = "const char *" ,
voidptr = "void *" ,
}










function types . cName ( t ) 
if not t then
return nil
end
local tag = t . tag
if C_NAME [ tag ] then
return C_NAME [ tag ]
end
if tag == "nominal" and t . declKind == "struct" then



return t . name
end
if tag == "ptr" then



local inner = types . cName ( t . elem )
return ( inner or "void" ) .. " *"

elseif tag == "carray" then
local elem = types . cName ( t . elem )
if elem and t . count then
return elem .. "[" .. tostring ( t . count ) .. "]"
end
return nil
end
if tag == "union" and # t . members == 2 and t . hasNil then


local other = t . members [ 1 ] == types . nil_ and t . members [ 2 ] or t . members [ 1 ]
if other . tag == "ptr" or other == types . cstring or other == types . voidptr then
return types . cName ( other )
end
end
if tag == "nominal" then



local targetLayout = require ( "nupp.compiler.targetlayout" )
local element , lanes = targetLayout . storageVector ( t )
if element ~= nil and C_NAME [ element ] ~= nil then
local bytes = targetLayout . VECTOR_ELEMENT_BYTES [ element ]
local count = lanes
local alignment = targetLayout . luaVectorAlignment ( bytes , count )

return ("__attribute__((aligned(%d))) %s[%d]") : format ( alignment , C_NAME [ element ] , count )
end
end

return nil
end






























local ARENAS

= { types = arena , packs = packArena , packVars = packVarArena , capabilities = capabilityArena , consts = constArena , }


function types . identity ( ) 
return {
arenas = ARENAS ,
serial = nextSerial ,
capability = nextCapabilityIdentity ,
nominal = nominalCounter ,
}
end








function types . setIdentityNamespace ( namespace , lane ) 
if namespace == "" or lane < 1 or lane > 1000 then
error ( "invalid type identity namespace" , 2 )
end
local wanted = "@" .. namespace .. ":" .. tostring ( lane ) .. ":"
if identityNamespace ~= "" and identityNamespace ~= wanted then
error ( "type identity namespace already set" , 2 )
end
identityNamespace = wanted
end







function types . adopt ( bucket , key , value ) 
local into = ARENAS [ bucket ]
if into == nil then
return nil
end
local found = into [ key ]
if found ~= nil then
return found
end
into [ key ] = value

return value
end


function types . interned ( bucket , key ) 
local from = ARENAS [ bucket ]

return from ~= nil and from [ key ] or nil
end








function types . resumeIdentity ( identity ) 
if type ( identity ) ~= "table" then
return
end
local serialAt = tonumber ( identity . serial ) or 0
if serialAt > nextSerial then
nextSerial = serialAt
end
local capabilityAt = tonumber ( identity . capability ) or 0
if capabilityAt > nextCapabilityIdentity then
nextCapabilityIdentity = capabilityAt
end
local nominalAt = tonumber ( identity . nominal ) or 0
if nominalAt > nominalCounter then
nominalCounter = nominalAt
end
end

local __nuppExportValue= types ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.types"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.types"]=__nuppExports;return __nuppExports