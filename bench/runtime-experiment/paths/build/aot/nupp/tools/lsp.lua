_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppT96={}; local function __nuppT93(...) return {n=select("#",...),...} end; local __nuppT97,__nuppT98,__nuppT99,__nuppT100,__nuppT101,__nuppT102,__nuppT103,__nuppT104=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT94(value) return value end; local function __nuppT95(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT102({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT103(v.primary) for _,reason in __nuppT104(v.suppressed) do text=text.."\ncleanup: "..__nuppT103(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppManagedCleanup2 = function(__nuppV) local __first,__suppressed=nil,0; do local __ok,__reason=pcall(__nuppCleanup1,__nuppV); if not __ok then if __first==nil then __first=__reason else __suppressed=__suppressed+1 end end end; if __first~=nil then if __suppressed>0 then _G.error(_G.tostring(__first).." (suppressed ".._G.tostring(__suppressed).." cleanup failure(s))",0) else _G.error(__first,0) end end end;local __nuppDrop3 = function(__nuppV) if __nuppV == nil then return end __nuppV:close();  end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()













local incremental = require ( "nupp.compiler.project.incremental" )

local cst = require ( "nupp.compiler.syntax.cst" )
local fs = require ( "nupp.compiler.fs" )
local envMod = require ( "nupp.compiler.project.env" )
local fmt = require ( "nupp.tools.fmt" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local T = require ( "nupp.compiler.types" )
local annotationMod = require ( "nupp.compiler.annotations" )

local lsp = { }




function lsp . siteUrl ( pointer ) 
local path , anchor = pointer : match ( "^docs/([^#]+)%.md(#?[^#]*)$" )
if not path then
return nil
end
local route = ( path ) : gsub ( "/index$" , "" ) : gsub ( "^index$" , "" )

return "https://nupp.org/" .. route .. anchor
end



local text = require ( "nupp.tools.lsp.text" )
local lspDiagnostics = require ( "nupp.tools.lsp.diagnostics" )
local navigate = require ( "nupp.tools.lsp.navigate" )
local tree = require ( "nupp.tools.lsp.tree" )
local wire = require ( "nupp.tools.lsp.wire" )
local symbols = require ( "nupp.tools.lsp.symbols" )
local complete = require ( "nupp.tools.lsp.complete" )
local semantic = require ( "nupp.tools.lsp.semantic" )
local artifactsMod = require ( "nupp.tools.lsp.artifacts" )
local transportMod = require ( "nupp.tools.lsp.transport" )



local CONTRACT_TARGETS = { localFuncStmt = true , funcStmt = true , inlineMethod = true , constructorDecl = true }
local enclosingChain = tree . enclosingChain
local functionSignature = tree . functionSignature
local lineHunks = text . lineHunks
local lineStarts = text . lineStarts
local memberOccurrences = tree . memberOccurrences
local offsetAtPosition = text . offsetAtPosition
local positionAtOffset , spanRange = text . positionAtOffset , text . spanRange
local splitLines = text . splitLines
local symbolKey = tree . symbolKey
local tokenAt = tree . tokenAt
local tokenRange = text . tokenRange
local pathToUri = text . pathToUri
local QUICKFIX = "quickfix"
local SYMBOL_KINDS = symbols . SYMBOL_KINDS
local documentSymbols = symbols . documentSymbols
local foldableSpans = symbols . foldableSpans
local semanticModifiers = semantic . semanticModifiers
local semanticTypes = semantic . semanticTypes
local signatureAt = complete . signatureAt
local uriToPath = text . uriToPath


















local function bySpanStart ( a , b ) 
return a . from < b . from
end

local function byRenamePath ( a , b ) 
return a . path < b . path
end












































local json = wire . json








function lsp . newSession ( rootDir , emit , host ) 
rootDir = rootDir or "."





local s = {
root = rootDir ,




folders = { } ,
documents = { } ,


lexed = { } ,



clientOptions = { } ,
}

local running = true


local initialized , shutDown = false , false

local send = emit



local function notify ( method , params ) 
send ( { jsonrpc = "2.0" , method = method , params = params } )
end




local resolvedDeps = { }
















local function resolveTypeDependencies ( root ) 
if resolvedDeps [ root ] then
return
end
resolvedDeps [ root ] = true
local manifest = require ( "nupp.tools.build.manifest" )



local config = manifest . load ( root )
if not config then
return
end
local selectedTarget = ( require ( "nupp.tools.build.tasks" ) ) . targetConfig ( config )
local selected = { }
if selectedTarget and selectedTarget . compileDependencies ~= nil then
for _ , name in ipairs ( selectedTarget . compileDependencies ) do
selected [ name ] = true
end
else
for name , dep in pairs ( config . dependencies or { } ) do
if type ( dep ) == "table" and ( dep ) . kind == "types" then
selected [ name ] = true
end
end
end
local pending = { }
for name , dep in pairs ( config . dependencies or { } ) do
if selected [ name ] and type ( dep ) == "table" and ( dep ) . kind == "types" then
if not fs . exists ( fs . join ( root , ".nupp/deps/" .. name .. "/.git/HEAD" ) ) then
pending [ # pending + 1 ] = name
end
end
end
table . sort ( pending )
if # pending > 0 then


notify ( "window/logMessage" , {
type = 3 ,
message = "nupp: fetching type dependencies for " .. root .. ": " .. table . concat ( pending , ", " ) ,
} )
end
local outDir = config . build and config . build . outDir or "build"
local compileConfig = { }
for key , value in pairs ( config ) do
compileConfig [ key ] = value
end
compileConfig . generators = { }
compileConfig . _target = {
dependencies = { } ,
compileDependencies = selectedTarget and selectedTarget . compileDependencies or nil ,
}
local ok , built , err = pcall (
( require ( "nupp.tools.build.deps" ) ) . build ,
root ,
outDir ,
compileConfig ,
{ } ,
compileConfig . _target
)
if not ok then
notify ( "window/logMessage" , { type = 1 , message = "nupp: " .. tostring ( built ) } )
elseif not built then
notify ( "window/logMessage" , { type = 1 , message = "nupp: " .. tostring ( err ) } )
elseif # pending > 0 then
notify ( "window/logMessage" , { type = 3 , message = "nupp: type dependencies ready for " .. root , } )
end
end



local function absoluteRoot ( entry ) 
if not entry . absolute then
entry . absolute = fs . absolute ( entry . root )
end

return entry . absolute
end



local function identityRoot ( entry ) 
if not entry . identity then
entry . identity = fs . canonical ( entry . root )
end

return entry . identity
end
















local function graphFor ( entry ) 
if not entry . inc then
resolveTypeDependencies ( entry . root )
local others = { }
for _ , other in ipairs ( s . roots ) do
if identityRoot ( other ) ~= identityRoot ( entry ) then
others [ # others + 1 ] = other . root
end
end
local inc = incremental . new ( entry . root , { folders = others , traceInspection = true } )
inc . env . host = host






for _ , problem in ipairs ( inc . env . ambientTypeProblems or { } ) do
notify ( "window/logMessage" , {
type = 2 ,
message = "nupp: type dependency declaration not imported: " .. problem . path .. ":" .. tostring (
problem . line
) .. ": " .. problem . msg ,
} )
end



for uri , doc in pairs ( s . documents ) do
inc . openDocument ( uriToPath ( uri ) , doc . text )
end
entry . inc = inc
end

return entry . inc
end





local function eachGraph ( fn ) 
for _ , entry in ipairs ( s . roots ) do
if entry . inc then
fn ( entry . inc )
end
end
end















local nestedRoots = { }

local function projectRootFor ( folder , path ) 
local dir = fs . dirname ( fs . absolute ( path ) )
local memo = nestedRoots [ dir ]
if memo ~= nil then
return memo
end




local bound = fs . absolute ( folder )
local found , at = folder , dir
while at ~= bound do
if at : sub ( 1 , # bound + 1 ) ~= bound .. "/" then
do break end
end
if fs . exists ( fs . join ( at , "nupp.lua" ) ) then
found = at
do break end
end
local up = fs . dirname ( at )
if up == at then
do break end
end
at = up
end
nestedRoots [ dir ] = found

return found
end




local function setRoots ( folders ) 
s . folders = folders
s . roots = { }
nestedRoots = { }




local seen = { }
for _ , root in ipairs ( folders ) do
local entry = { root = root }
if not seen [ identityRoot ( entry ) ] then
seen [ identityRoot ( entry ) ] = true
s . roots [ # s . roots + 1 ] = entry
end
end
local launched = { root = rootDir }
if not seen [ identityRoot ( launched ) ] then
table . insert ( s . roots , 1 , launched )
end
s . inc = graphFor ( s . roots [ 1 ] )
end





local function rootFor ( path ) 
local absolute = fs . absolute ( path )
local owner , longest = nil , -1
for _ , entry in ipairs ( s . roots ) do
local root = absoluteRoot ( entry )
if ( absolute == root or absolute : sub ( 1 , # root + 1 ) == root .. "/" ) and # root > longest then
owner , longest = entry , # root
end
end
owner = owner or s . roots [ 1 ]
local nested = projectRootFor ( owner . root , absolute )
if nested == owner . root then
return owner
end
for _ , entry in ipairs ( s . roots ) do
if entry . root == nested or absoluteRoot ( entry ) == nested then
return entry
end
end
local entry = { root = nested }
s . roots [ # s . roots + 1 ] = entry

return entry
end




function s . useRoot ( path ) 
local entry = path and rootFor ( path ) or s . roots [ 1 ]
s . inc = graphFor ( entry )
s . currentRoot = entry . root

return entry . root
end

setRoots ( { } )




local answering = nil









local function overtaken ( ) 
if not answering or not host or not answering . version then
return false
end
local arrived = host . documentVersion ( answering . uri )

return arrived ~= nil and arrived > answering . version
end





local function respond ( id , result ) 
if host and host . isCancelled ( id ) then
host . clearCancelled ( id )
send ( { jsonrpc = "2.0" , id = id , error = { code = -32800 , message = "request cancelled" } } )
return
end
if overtaken ( ) then
send ( { jsonrpc = "2.0" , id = id , error = { code = -32801 , message = "document changed while answering" } } )
return
end
send ( { jsonrpc = "2.0" , id = id , result = result } )
end

local function respondError ( id , code , message ) 
send ( { jsonrpc = "2.0" , id = id , error = { code = code , message = message } } )
end

s . notify , s . respond , s . respondError = notify , respond , respondError



local diags = lspDiagnostics . install ( s )
local toLspDiagnostics = diags . toLspDiagnostics
local checkAndPublish = diags . checkAndPublish
local refreshOpenDocuments = diags . refreshOpenDocuments

local nav = navigate . install ( s )
local definitionLocation = nav . definitionLocation
local documentationFor , documentAt = nav . documentationFor , nav . documentAt
local symbolAt = nav . symbolAt
local isProjectDefinition = nav . isProjectDefinition
local referencesFor = nav . referencesFor
local memberDeclaration , memberAt = nav . memberDeclaration , nav . memberAt
local memberLocation , memberReferences = nav . memberLocation , nav . memberReferences
local memberHover , memberDocumentation = nav . memberHover , nav . memberDocumentation

local completions = complete . install ( s , nav )
local completionItems = completions . completionItems

local tokens = semantic . install ( s )
local semanticEntries , encodeSemanticEntries = tokens . semanticEntries , tokens . encodeSemanticEntries
local rememberTokens , tokenEdits = tokens . rememberTokens , tokens . tokenEdits
local lastSentTokens = tokens . lastSent

local compiled = artifactsMod . install ( s )









local function reroot ( nextFolders ) 
setRoots ( nextFolders )
local uris = { }
for uri , doc in pairs ( s . documents ) do
uris [ # uris + 1 ] = uri
doc . checkResult = nil
end
table . sort ( uris )
for _ , uri in ipairs ( uris ) do
checkAndPublish ( uri , true )
end
end


local function folderPaths ( list ) 
local paths = { }
for _ , folder in ipairs ( list or { } ) do
local uri = type ( folder ) == "table" and folder . uri or folder
if type ( uri ) == "string" and uri : match ( "^[Ff][Ii][Ll][Ee]:" ) then
paths [ # paths + 1 ] = uriToPath ( uri )
end
end

return paths
end















local function shownType ( tok , def ) 
if def and def . kind == "function" and def . type and def . token == tok then
return def . type
end

return tok . inferredType or def and def . type
end

local handlers = __nuppNew(0,36)

handlers [ "initialize" ] = function ( id , params ) 




local options = params and params . initializationOptions
s . clientOptions = type ( options ) == "table" and options or { }
local inspectCommand = nil
local artifactOptions = s . clientOptions . artifacts
if type ( artifactOptions ) == "table" and type ( artifactOptions . inspectCommand ) == "string" then
inspectCommand = artifactOptions . inspectCommand
end
compiled . useInspectCommand ( inspectCommand )



local opened = folderPaths ( params and params . workspaceFolders )
if # opened == 0 and params and params . rootUri then
opened = folderPaths ( { params . rootUri } )
end
if # opened > 0 then
reroot ( opened )
end
respond ( id , {
capabilities = {
textDocumentSync = 1 ,
definitionProvider = true ,
implementationProvider = true ,
hoverProvider = true ,
completionProvider = { triggerCharacters = wire . array ( { "." , ":" } ) , } ,
signatureHelpProvider = { triggerCharacters = wire . array ( { "(" , "," } ) , } ,
referencesProvider = true ,
renameProvider = { prepareProvider = true } ,
semanticTokensProvider = {
legend = { tokenTypes = semanticTypes , tokenModifiers = semanticModifiers , } ,
full = { delta = true } ,
range = true ,
} ,
documentFormattingProvider = true ,
documentRangeFormattingProvider = true ,
documentSymbolProvider = true ,
workspaceSymbolProvider = true ,
documentHighlightProvider = true ,
foldingRangeProvider = true ,
selectionRangeProvider = true ,
codeActionProvider = { codeActionKinds = wire . array ( { "quickfix" } ) , } ,



codeLensProvider = inspectCommand and { resolveProvider = false } or nil ,
workspace = { workspaceFolders = { supported = true , changeNotifications = true , } , } ,



experimental = { nuppArtifacts = wire . array ( artifactsMod . KINDS ) } ,
} ,
serverInfo = { name = "nupp-lsp" , version = "0.1" } ,
} )
end

handlers [ "initialized" ] = function ( ) 
end

handlers [ "workspace/didChangeWorkspaceFolders" ] = function ( _ , params ) 
local event = params and params . event or { }
local removed = { }
for _ , path in ipairs ( folderPaths ( event . removed ) ) do
removed [ path ] = true
end
local next_ , seen = { } , { }

local function keep ( path ) 
if removed [ path ] or seen [ path ] then
return
end
seen [ path ] = true
next_ [ # next_ + 1 ] = path
end

for _ , path in ipairs ( s . folders ) do
keep ( path )
end
for _ , path in ipairs ( folderPaths ( event . added ) ) do
keep ( path )
end
reroot ( next_ )
end

handlers [ "workspace/didChangeWatchedFiles" ] = function ( _ , params ) 










local changes = { }
for _ , change in ipairs ( params . changes or { } ) do
local uri = type ( change . uri ) == "string" and change . uri or ""
if uri : match ( "^[Ff][Ii][Ll][Ee]:" ) and not uri : find ( "/%.nupp/" ) then
if uri : match ( "/nupp%.lua$" ) then




resolvedDeps = { }
reroot ( s . folders )

return
end
changes [ # changes + 1 ] = change
end
end



eachGraph ( function ( inc ) 
for _ , change in ipairs ( changes ) do
inc . diskChanged ( uriToPath ( change . uri ) , change . type )
end
end )
refreshOpenDocuments ( nil )
end

handlers [ "textDocument/didOpen" ] = function ( _ , params ) 
local doc = params . textDocument
s . documents [ doc . uri ] = { text = doc . text , version = doc . version }
eachGraph ( function ( inc ) 
inc . openDocument ( uriToPath ( doc . uri ) , doc . text )
end )
refreshOpenDocuments ( doc . uri )
end

handlers [ "textDocument/didChange" ] = function ( _ , params ) 



local full = nil
for _ , change in ipairs ( params . contentChanges or { } ) do
if change . text and not change . range then
full = change
end
end
if full then
local uri = params . textDocument . uri
local doc = s . documents [ uri ] or { }
doc . text = full . text


doc . version = params . textDocument . version
s . documents [ uri ] = doc
eachGraph ( function ( inc ) 
inc . changeDocument ( uriToPath ( uri ) , full . text )
end )
refreshOpenDocuments ( uri )
end
end

handlers [ "textDocument/implementation" ] = function ( id , params ) 
local _ , doc , token , offset = nav . symbolAt ( params )
local member = doc and offset and require ( "nupp.tools.lsp.tree" ) . moduleMemberAt ( doc . result , offset )
respond ( id , require ( "nupp.tools.lsp.spi" ) . implementations ( s . inc , member , token ) )
end

handlers [ "textDocument/definition" ] = function ( id , params ) 
local uri = params and params . textDocument and params . textDocument . uri
local doc = uri and s . documents [ uri ]
if not doc or not doc . result or not params . position then
respond ( id , json . NULL )
return
end
local offset = offsetAtPosition ( doc . text , params . position )
if not offset then
respond ( id , json . NULL ) ;
return
end


local tok = tokenAt ( doc . result , offset )
if not tok then
respond ( id , json . NULL )
return
end
local member = memberAt ( doc , offset )
if member then
respond ( id , memberLocation ( member ) )
return
end
if tok . additionalDefinitions and # tok . additionalDefinitions > 1 then
local locations = wire . array ( { } )
for _ , definition in ipairs ( tok . additionalDefinitions ) do
local found = definitionLocation ( definition )
if found ~= json . NULL then
locations [ # locations + 1 ] = found
end
end
if # locations > 0 then
respond ( id , locations )
return
end
end
respond ( id , definitionLocation ( tok . definition ) )
end

local function capabilityDetail ( t ) 
local capability = T . capability ( t )
local kind = T . capabilityKind ( capability )
if not kind then
return nil
end
local parts = { }
if capability . obligation then
if T . capabilityTransferOnly ( capability ) then
parts [ # parts + 1 ] = "transfer-only obligation"
end
local names = { }
for _ , cleanup in ipairs ( T . capabilityCleanups ( capability ) ) do
names [ # names + 1 ] = cleanup . name or cleanup . key or cleanup . id
end
if # names > 0 then
parts [ # parts + 1 ] = "cleanup `" .. table . concat ( names , "`, then `" ) .. "`"
end
end
if # capability . loans > 0 then
parts [ # parts + 1 ] = capability . loans [ 1 ] . access .. " rooted loan"
end
if # capability . anchors > 0 then
parts [ # parts + 1 ] = "pinned anchor"
end
if # capability . retentions > 0 then
parts [ # parts + 1 ] = "foreign retention"
end

return # parts > 0 and table . concat ( parts , "; " ) or kind
end

handlers [ "textDocument/hover" ] = function ( id , params ) 
local _ , doc , tok , offset = symbolAt ( params )
local comptimeNode = doc and offset and tree . comptimeAt ( doc . result , offset ) or nil
if comptimeNode and comptimeNode . comptimeResultType then
local hoverOffset = offset
local from , to = tree . nodeBounds ( comptimeNode )
local value = "```nupp\ncomptime: " .. T . tostring ( comptimeNode . comptimeResultType ) .. "\n```"
local literal = comptimeNode . comptimeValue
if literal then
if # literal > 160 then
literal = literal : sub ( 1 , 157 ) .. "..."
end
value = value .. "\n\nCanonical value: `" .. literal : gsub ( "`" , "\\`" ) .. "`"
elseif comptimeNode . materializationObservation then
local observation = comptimeNode . materializationObservation
value = value .. ("\n\nMaterialized by `%s` (`%s`, %d-byte blueprint).")

: format ( tostring ( observation . provider ) , tostring ( observation . backend ) , observation . blueprintSize or 0 )
end
respond ( id , {
contents = { kind = "markdown" , value = value } ,
range = spanRange ( doc . text , from or hoverOffset , to or hoverOffset ) ,
} )
return
end
local def = tok and tok . definition
local t = tok and shownType ( tok , def )




if tok then
local member = memberAt ( doc , offset )
local value = member and memberHover ( member )
if value then
local deprecated = annotationMod . deprecationMarkdown ( def and def . deprecated )
if deprecated then
value = value .. "\n\n" .. deprecated
end
respond ( id , { contents = { kind = "markdown" , value = value } , range = tokenRange ( doc . text , tok ) , } )
return
end
end
if tok and def and def . doc and ( def . kind == "annotation" or def . kind == "property" ) then



local label = def . kind == "annotation" and ( "@" .. ( def . name or tok . text ) )
or ( def . name or tok . text ) .. ( t and ( ": " .. T . tostring ( t ) ) or "" )
local value = "```nupp\n" .. label .. "\n```\n\n" .. def . doc
local url = def . docsPath and lsp . siteUrl ( def . docsPath ) or nil
if url then
value = value .. "\n\n[Reference on nupp.org](" .. url .. ")"
end
respond ( id , { contents = { kind = "markdown" , value = value } , range = tokenRange ( doc . text , tok ) , } )
return
end
if not tok or not t then
respond ( id , json . NULL ) ;
return
end
local name = def and def . name or tok . text
local prefix = def and def . cdef and "cdef " or def and def . constant and "const " or ""
local capability = capabilityDetail ( t )
local displayed = capability and T . tostring ( T . unwrapOwnership ( t ) ) or T . tostring ( t )
local value = "```nupp\n" .. prefix .. name .. ": " .. displayed .. "\n```"
if capability then
value = value .. "\n\nCapability: " .. capability .. "."
end
if def and def . generatedBy then
value = value .. ("\n\nGenerated by `@derive(%s)` for `%s`.")

: format ( def . generatedBy , def . generatedOwner or "<anonymous>" )
if def . generatedInterface then
value = value .. "\n\nImplements `" .. def . generatedInterface .. "`."
end
if def . generatedHelper then
value = value .. "\n\nForwards to `" .. def . generatedHelper .. "`."
end
if def . generatedRecipeFingerprint then
value = value .. "\n\nRecipe fingerprint: `" .. def . generatedRecipeFingerprint .. "`."
end
end
local automatic = def and def . automaticCleanup
if automatic then
if automatic . status == "moved" then
value = value .. "\n\nOwnership moves before the lexical cleanup boundary."
else
value = value .. ("\n\nAutomatically destroyed after line %d with `%s`.")

: format ( automatic . line , table . concat ( automatic . cleanups or { } , "`, then `" ) )
end
end
local docs = documentationFor ( def )
if docs then
value = value .. "\n\n" .. docs
end
local deprecated = annotationMod . deprecationMarkdown ( def and def . deprecated )
if deprecated then
value = value .. "\n\n" .. deprecated
end
respond ( id , { contents = { kind = "markdown" , value = value } , range = tokenRange ( doc . text , tok ) , } )
end











local function associatedState ( t ) 
if not t or t . tag ~= "projection" then
return nil
end
local generics = require ( "nupp.compiler.types.generics" )
local associated = require ( "nupp.compiler.types.associated" )
local reduced = generics . normalize ( t )
if reduced . cycle then
return "cyclic: " .. table . concat ( reduced . cycle , " -> " )
end
if reduced . gradual and # reduced . gradual > 0 then
return "gradual"
end
if reduced . type . tag ~= "projection" then
return "resolves to " .. T . tostring ( reduced . type )
end
local found = associated . lookup ( t . of , t . name )
if found . bound then
return "opaque with bound " .. T . tostring ( found . bound )
end

return "opaque"
end

handlers [ "nupp/inspect" ] = function ( id , params ) 
local _ , doc , tok , offset = symbolAt ( params )
if not tok then
respond ( id , json . NULL ) ;
return
end
local member = memberAt ( doc , offset )
if member then
local path , memberTok , stat = memberDeclaration ( member . moduleName , member . name )
local documentation = path and memberDocumentation ( path , memberTok ) or nil
respond ( id , {
name = member . name ,
kind = "function" ,
detail = stat and functionSignature ( stat ) or nil ,
documentation = documentation ,
definition = memberLocation ( member ) ,
range = tokenRange ( doc . text , tok ) ,
root = s . currentRoot ,
} )
return
end
local def = tok . definition
local t = shownType ( tok , def )
if not t then
respond ( id , json . NULL ) ;
return
end
respond ( id , {
name = def and def . name or tok . text ,
kind = def and def . kind or "variable" ,
type = T . tostring ( t ) ,
capability = capabilityDetail ( t ) ,
associated = associatedState ( t ) ,
documentation = documentationFor ( def ) ,
definition = definitionLocation ( def ) ,
range = tokenRange ( doc . text , tok ) ,
automaticCleanup = def and def . automaticCleanup or nil ,
deprecated = def and def . deprecated or nil ,
generatedBy = def and def . generatedBy or nil ,
generatedOwner = def and def . generatedOwner or nil ,
generatedNamespace = def and def . generatedNamespace or nil ,
generatedRecipeFingerprint = def and def . generatedRecipeFingerprint or nil ,
soaColumn = tok . soaColumn ,



root = s . currentRoot ,
} )
end




handlers [ "nupp/traceCheck" ] = function ( id , params ) 
local _ , doc = documentAt ( params )
local position = params and params . position
local offset = doc and position and offsetAtPosition ( doc . text , position ) or nil
local analysis = doc and doc . result and doc . result . traceAnalysis or nil
if not offset or not analysis then
respond ( id , json . NULL )
return
end
local selected , foundFrom , foundTo = tree . functionAt ( analysis . functions , offset )
if not selected then
respond ( id , json . NULL )
return
end


local selectedFrom , selectedTo = foundFrom , foundTo
local findings = wire . array ( { } )
for _ , finding in ipairs ( selected . traceFindings or { } ) do
local from , to = tree . nodeBounds ( finding . at or finding . callAt )
local range = nil
if from and to then
range = spanRange ( doc . text , from , to )
end
findings [
# findings + 1
] = {
reason = finding . reason ,
class = finding . class ,
message = finding . message ,
help = finding . help ,
callPath = wire . array ( finding . callPath or { } ) ,
range = range ,
}
end
local profile = analysis . profile




local addContract = nil
local declared = selected . node and CONTRACT_TARGETS [ selected . node . kind ]
if declared and not ( selected . body and selected . body . jitRequired ) then
local lineStart = selectedFrom
while lineStart > 1 and doc . text : sub ( lineStart - 1 , lineStart - 1 ) ~= "\n" do
lineStart = lineStart - 1
end
local before = doc . text : sub ( lineStart , selectedFrom - 1 )
addContract = {
range = spanRange ( doc . text , selectedFrom , selectedFrom ) ,
newText = before : match ( "^%s*$" ) and "@jit\n" .. before or "@jit " ,
}
end
respond ( id , {
name = selected . traceName ,
range = spanRange ( doc . text , selectedFrom , selectedTo ) ,
findings = findings ,
traceProfile = profile ,
reasonCatalog = analysis . reasonCatalog ,
contract = selected . body and selected . body . jitRequired and "@jit" or "inspection" ,
addContract = addContract ,
} )
end




handlers [ "nupp/artifacts" ] = function ( id , params ) 
respond ( id , compiled . discover ( params ) )
end

handlers [ "nupp/artifact" ] = function ( id , params ) 
respond ( id , compiled . resolve ( params ) )
end

handlers [ "textDocument/codeLens" ] = function ( id , params ) 
respond ( id , compiled . lenses ( params ) )
end



handlers [ "nupp/migrate" ] = function ( id , params ) 
local document = params and params . textDocument
local uri = type ( document ) == "table" and document . uri or nil
local source = params and params . text
if type ( uri ) ~= "string" or type ( source ) ~= "string" then
respond ( id , { ok = false , error = "a file URI and current document text are required" } )
return
end
local plan , problem = require ( "nupp.tools.migrate" ) . plan ( source , uriToPath ( uri ) , params . dialect or "auto" )
if not plan then
respond ( id , { ok = false , error = problem } )
return
end
respond ( id , {
ok = true ,
sourceUri = uri ,
destinationUri = pathToUri ( plan . destination ) ,
text = plan . text ,
edits = wire . array ( plan . edits ) ,
warnings = wire . array ( plan . warnings ) ,
dialect = plan . dialect ,
} )
end

handlers [ "textDocument/completion" ] = function ( id , params ) 
local _ , doc = documentAt ( params )
if not doc or not doc . result or not params . position then
respond ( id , json . asArray ( { } ) )
return
end
local offset = offsetAtPosition ( doc . text , params . position ) or 1
respond ( id , completionItems ( doc , offset ) )
end

handlers [ "textDocument/signatureHelp" ] = function ( id , params ) 
local _ , doc = documentAt ( params )
if not doc or not doc . result or not params . position then
respond ( id , json . NULL )
return
end
local offset = offsetAtPosition ( doc . text , params . position )
local call = offset and signatureAt ( doc . result , offset )
if not call then
respond ( id , json . NULL ) ;
return
end
local ft = call . signatureType
local candidates = call . overloadCandidates or { ft }
local name = "call"
if call . kind == "methodCall" and call . name then
name = call . name . text
elseif call . obj and call . obj . kind == "name" then
name = call . obj . token . text
end
local activeParameter = 0
for _ , child in ipairs ( call . args or { } ) do
if cst . isToken ( child ) and child . kind == "," and child . offset < offset then
activeParameter = activeParameter + 1
end
end
local signatures = wire . array ( { } )
local activeSignature = 0
for candidateIndex , candidate in ipairs ( candidates ) do
local parameters = wire . array ( { } )
for index , param in ipairs ( candidate . paramPack . head or { } ) do
local mode = candidate . paramPack . modes [ index ]
parameters [
# parameters + 1
] = { label = ( mode and mode ~= "plain" and mode .. " " or "" ) .. T . tostring ( param ) }
end
if candidate . paramPack . tail then
local tail = candidate . paramPack . tail
parameters [
# parameters + 1
] = {
label = tail . kind == "homogeneous" and ( "...: " .. T . tostring ( tail . type ) )
or tail . kind == "generic" and ( tail . var . name .. "..." )
or tail . kind == "computed" and ( "...: unpackof " .. T . tostring ( tail . type ) )
or "..."
}
end
signatures [ # signatures + 1 ] = { label = name .. ": " .. T . tostring ( candidate ) , parameters = parameters , }
if call . overloadWinner == candidate then
activeSignature = candidateIndex - 1
end
end
local active = candidates [ activeSignature + 1 ]


local parameterCount = active and ( # active . paramPack . head + ( active . paramPack . tail and 1 or 0 ) ) or 0
if parameterCount > 0 then
activeParameter = math . min ( activeParameter , parameterCount - 1 )
else
activeParameter = 0
end
respond ( id , { signatures = signatures , activeSignature = activeSignature , activeParameter = activeParameter , } )
end

handlers [ "textDocument/references" ] = function ( id , params ) 
local _ , doc , tok , offset = symbolAt ( params )
if not tok then
respond ( id , json . asArray ( { } ) ) ;
return
end
local includeDeclaration = params . context and params . context . includeDeclaration or false
local member = memberAt ( doc , offset )
if member then
respond ( id , memberReferences ( member , includeDeclaration ) )
return
end
respond ( id , referencesFor ( tok . definition , includeDeclaration ) )
end




local function unaliasedPatternDefinition ( tok ) 
local definition = tok and tok . definition
local declaration = definition and definition . token
local path = definition and definition . filename
if not declaration or not path then
return nil
end
local source , result
for uri , open in pairs ( s . documents ) do
if uriToPath ( uri ) == path then
source , result = open . text , open . result
do break end
end
end
if not result then
source = s . inc . fileText ( path )
local checked = source and s . inc . checkFile ( path ) or nil
result = checked and checked . result or nil
end
local entry = nil
if result then
tree . walkNodes ( result . root , function ( node ) 
if not entry
and node . kind == "bindingEntry"
and not node . alias
and node . sourceName
and node . sourceName . offset == declaration . offset
then
entry = node
end
end )
end

return entry , source , pathToUri ( path )
end

local function renameSubject ( params ) 
local _ , doc , tok , offset = symbolAt ( params )
if not tok then
return doc , nil , nil , nil
end
if tok . definition and tok . definition . generatedBy then
return doc , nil , nil , tok . definition
end
local member = memberAt ( doc , offset )
local path = member and s . inc . modulePath ( member . moduleName )
if path then
for _ , projectPath in ipairs ( s . inc . projectFiles ( ) ) do
if projectPath == path then
return doc , tok , function ( includeDeclaration ) 
return memberReferences ( member , includeDeclaration )
end , nil , member
end
end
end
if tok . definition and isProjectDefinition ( tok . definition ) then
return doc , tok , function ( includeDeclaration ) 
return referencesFor ( tok . definition , includeDeclaration )
end
end

return doc , nil , nil , nil
end

handlers [ "textDocument/prepareRename" ] = function ( id , params ) 
local doc , tok = renameSubject ( params )
if not tok then
respond ( id , json . NULL ) ;
return
end
respond ( id , { range = tokenRange ( doc . text , tok ) , placeholder = tok . text , } )
end



local function renameInput ( path ) 
for uri , open in pairs ( s . documents ) do
if uriToPath ( uri ) == path and open . result then
return open . text , open . result , true
end
end
local source = s . inc . fileText ( path )
local checked = source and s . inc . checkFile ( path ) or nil

return source , checked and checked . result or nil , false
end















local function renameCapture ( changes , target , newName ) 
local targetKey = symbolKey ( target )
if not targetKey then
return nil
end
local files = { }
local list = { }
for uri , edits in pairs ( changes ) do
local path = uriToPath ( uri )
local source , result , open = renameInput ( path )
if not source or not result or not result . tokens then
return nil
end
local spans = { }
for _ , edit in ipairs ( edits ) do
local from = offsetAtPosition ( source , edit . range . start )
local to = offsetAtPosition ( source , edit . range [ "end" ] )
if not from or not to then
return nil
end
spans [ # spans + 1 ] = { from = from , to = to , text = edit . newText }
end
table . sort ( spans , bySpanStart )
local pieces = { }
local at = 1
for _ , span in ipairs ( spans ) do
pieces [ # pieces + 1 ] = source : sub ( at , span . from - 1 )
pieces [ # pieces + 1 ] = span . text
at = span . to
end
pieces [ # pieces + 1 ] = source : sub ( at )
local file = {
path = path ,
source = source ,
result = result ,
open = open ,
spans = spans ,
text = table . concat ( pieces )
}
files [ path ] = file
list [ # list + 1 ] = file
end
table . sort ( list , byRenamePath )




local function moved ( path , offset ) 
local file = files [ path ]
if not file then
return offset
end
local shift = 0
for _ , span in ipairs ( file . spans ) do
if span . from == offset then
return offset + shift + # span . text - # newName
elseif span . from < offset then
shift = shift + # span . text - ( span . to - span . from )
end
end

return offset + shift
end

local function movedKey ( key ) 
local path , offset = ( key or "" ) : match ( "^(.*):(%d+)$" )
if not path or not offset then
return key
end

return path .. ":" .. tostring ( moved ( path , tonumber ( offset ) ) )
end

local renamedKey = movedKey ( targetKey )

local function compare ( ) 
for _ , file in ipairs ( list ) do
s . inc . changeDocument ( file . path , file . text )
end
for _ , file in ipairs ( list ) do
local path = file . path
local checked = s . inc . checkFile ( path )
local after = { }
for _ , tok in ipairs ( checked and checked . result and checked . result . tokens or { } ) do
after [ tok . offset ] = tok
end
for _ , tok in ipairs ( file . result . tokens ) do
if tok . kind == "name" then
local before = symbolKey ( tok . definition )
local at = moved ( path , tok . offset )
local now = after [ at ]
local nowKey = now and symbolKey ( now . definition ) or nil
local captured = before
and movedKey ( before ) ~= nowKey
and ( before == targetKey or nowKey == renamedKey )
if captured or ( not before and nowKey == renamedKey ) then
local lineStart = at
while lineStart > 1 and file . text : byte ( lineStart - 1 ) ~= 10 do
lineStart = lineStart - 1
end

return ("renaming to %s would change which declaration %s at %s:%d:%d refers to")

: format (
newName ,
now and now . text or tok . text ,
path ,
positionAtOffset ( file . text , at ) . line + 1 ,
at - lineStart + 1
)
end
end
end
end

return nil
end

local ok , problem = pcall ( compare )
for _ , file in ipairs ( list ) do
if file . open then
s . inc . changeDocument ( file . path , file . source )
else
s . inc . closeDocument ( file . path )
end
end
if not ok then
error ( problem , 0 )
end

return problem
end

handlers [ "textDocument/rename" ] = function ( id , params ) 
local newName = params and params . newName
if not newName or not newName : match ( "^[A-Za-z_][A-Za-z0-9_]*$" ) or lexer . KEYWORDS [ newName ] then
respondError ( id , -32602 , "new name is not a valid identifier" )
return
end
local _ , tok , references , generated , member = renameSubject ( params )
if not tok then
if generated then
respondError (
id ,
-32602 ,
("generated member %q cannot be renamed; change or remove @derive(%s)")

: format ( generated . name , generated . generatedBy )
)
else
respondError ( id , -32602 , "symbol cannot be renamed" )
end
return
end
local patternEntry , patternSource , patternUri = unaliasedPatternDefinition ( tok )
local patternRange = patternEntry and patternSource and tokenRange ( patternSource , patternEntry . sourceName )
or nil
local changes = { }
for _ , location in ipairs ( references ( true ) ) do
local edits = changes [ location . uri ]
if not edits then
edits = wire . array ( { } )
changes [ location . uri ] = edits
end
local declarationEdit = patternRange
and location . uri == patternUri
and location . range . start . line == patternRange . start . line
and location . range . start . character == patternRange . start . character
edits [
# edits + 1
] = {
range = location . range ,
newText = declarationEdit and ( patternEntry . sourceName . text .. " as " .. newName ) or newName ,
}
end
local capture = nil
if member then



if newName ~= member . name and memberDeclaration ( member . moduleName , newName ) then
capture = ("%s already declares a member named %s") : format ( member . moduleName , newName )
end
else
capture = renameCapture ( changes , tok . definition , newName )
end
if capture then
respondError ( id , -32602 , capture )
return
end
respond ( id , { changes = changes } )
end



local function toTextEdits ( source , edits ) 
local out = wire . array ( { } )
for _ , edit in ipairs ( edits ) do
out [ # out + 1 ] = { range = spanRange ( source , edit . offset , edit . offset + edit . length ) , newText = edit . newText , }
end

return out
end

handlers [ "textDocument/codeAction" ] = function ( id , params ) 
local uri , doc = documentAt ( params )
local range = params and params . range
if not doc or not doc . result or not range then
respond ( id , json . asArray ( { } ) )
return
end
local from = offsetAtPosition ( doc . text , range . start )
local to = offsetAtPosition ( doc . text , range [ "end" ] ) or from
if not from then
respond ( id , json . asArray ( { } ) )
return
end

local wanted = nil
for _ , kind in ipairs ( params . context and params . context . only or { } ) do
wanted = wanted or { }
wanted [ kind ] = true
end
local offers = wire . array ( { } )

local function offer ( kind , title , edits , diagnostic ) 
if wanted and not wanted [ kind ] then
return
end
if not edits or # edits == 0 then
return
end
offers [ # offers + 1 ] = {
title = title ,
kind = kind ,
diagnostics = diagnostic and wire . array ( {
diagnostic
} ) or nil ,
edit = { changes = { [ uri ] = toTextEdits ( doc . text , edits ) } } ,
}
end




local diagnostics = doc . checkResult and doc . checkResult . diags or { }
for _ , e in ipairs ( diagnostics ) do
if e . fixes and e . offset and e . offset > 0 then
local tok = tokenAt ( doc . result , e . offset )
local start = tok and tok . offset or e . offset
local stop = tok and tok . offset + # tok . text or e . offset + 1
if start <= to and from <= stop then
local reported = toLspDiagnostics ( { e } , doc . text ) [ 1 ]
for _ , fix in ipairs ( e . fixes ) do
offer ( "quickfix" , fix . title , fix . edits , reported )
end
end
end
end

respond ( id , offers )
end

handlers [ "textDocument/semanticTokens/full" ] = function ( id , params ) 
local uri , doc = documentAt ( params )
if not doc or not doc . result then
respond ( id , { data = json . asArray ( { } ) } )
return
end
local data = encodeSemanticEntries ( semanticEntries ( doc ) )
respond ( id , { resultId = rememberTokens ( uri , data ) , data = data } )
end

handlers [ "textDocument/semanticTokens/full/delta" ] = function ( id , params ) 
local uri , doc = documentAt ( params )
if not doc or not doc . result then
respond ( id , { data = json . asArray ( { } ) } )
return
end
local data = encodeSemanticEntries ( semanticEntries ( doc ) )
local previous = lastSentTokens ( uri )


if not previous or previous . resultId ~= params . previousResultId then
respond ( id , { resultId = rememberTokens ( uri , data ) , data = data } )
return
end
local edits = tokenEdits ( previous . data , data )
respond ( id , { resultId = rememberTokens ( uri , data ) , edits = edits } )
end

handlers [ "textDocument/semanticTokens/range" ] = function ( id , params ) 
local _ , doc = documentAt ( params )
local range = params and params . range
if not doc or not doc . result or not range then
respond ( id , { data = json . asArray ( { } ) } )
return
end
local within = { }
for _ , entry in ipairs ( semanticEntries ( doc ) ) do



if entry . line >= range . start . line and entry . line <= range [ "end" ] . line then
within [ # within + 1 ] = entry
end
end
respond ( id , { data = encodeSemanticEntries ( within ) } )
end




local function formattedText ( uri , doc , bindImports ) 
local path = uriToPath ( uri )
local formatted , errors = fmt . format ( doc . text , path , {
environment = s . inc . env ,
bindImports = bindImports ,
annotations = s . inc . env . annotations ,
resolveAnnotation = function ( name ) 
return s . inc . env . resolveProjectAnnotation ( s . inc . env , path , name )
end ,
methodParens = envMod . fmtMethodParensDefault ( s . inc . env ) ,
} )
if # errors > 0 or formatted == doc . text then
return nil
end

return formatted
end








local function formattingEdits ( uri , doc , bindImports ) 
local formatted = formattedText ( uri , doc , bindImports )
if not formatted then
return nil
end
local before , after = splitLines ( doc . text ) , splitLines ( formatted )
local starts = lineStarts ( doc . text )
local edits = { }
for _ , hunk in ipairs ( lineHunks ( before , after ) ) do
local from = starts [ hunk . from ] or ( # doc . text + 1 )
local to = starts [ hunk . to ] or ( # doc . text + 1 )
edits [
# edits + 1
] = {
fromLine = hunk . from - 1 ,
toLine = hunk . to - 1 ,
range = spanRange ( doc . text , from , to ) ,
newText = table . concat ( hunk . lines ) ,
}
end

return edits
end

local function respondWithEdits ( id , edits , keep ) 
if not edits then
respond ( id , json . asArray ( { } ) ) ;
return
end
local out = wire . array ( { } )
for _ , edit in ipairs ( edits ) do
if not keep or keep ( edit ) then
out [ # out + 1 ] = { range = edit . range , newText = edit . newText }
end
end
respond ( id , out )
end

handlers [ "textDocument/formatting" ] = function ( id , params ) 
local uri , doc = documentAt ( params )
if not doc then
respond ( id , json . asArray ( { } ) ) ;
return
end
respondWithEdits ( id , formattingEdits ( uri , doc ) )
end

handlers [ "textDocument/rangeFormatting" ] = function ( id , params ) 
local uri , doc = documentAt ( params )
local range = params and params . range
if not doc or not range then
respond ( id , json . asArray ( { } ) ) ;
return
end







respondWithEdits ( id , formattingEdits ( uri , doc , false ) , function ( edit ) 
return edit . fromLine >= range . start . line and edit . toLine <= range [ "end" ] . line + 1
end )
end

handlers [ "textDocument/documentSymbol" ] = function ( id , params ) 
local _ , doc = documentAt ( params )
if not doc or not doc . result then
respond ( id , json . asArray ( { } ) )
return
end
respond ( id , documentSymbols ( doc . result , doc . text ) )
end

handlers [ "workspace/symbol" ] = function ( id , params ) 
local query = params and params . query or ""
local found = wire . array ( { } )






local seen = { }
local wanted = query : lower ( )
if wanted ~= "" then
local open = { }
for uri , doc in pairs ( s . documents ) do
open [ uriToPath ( uri ) ] = doc
end
for _ , path in ipairs ( s . inc . projectFiles ( ) ) do
local doc = open [ path ]
local source = doc and doc . text or s . inc . fileText ( path )
if source and source : lower ( ) : find ( wanted , 1 , true ) then
local result = doc and doc . result
if not result then
local checked = s . inc . checkFile ( path )
result = checked and checked . result
end
local uri = pathToUri ( path )
for _ , symbol in ipairs ( result and result . root and documentSymbols ( result , source ) or { } ) do
local isFunction = symbol . kind == SYMBOL_KINDS [ "function" ] or symbol . kind == SYMBOL_KINDS . method
if isFunction and symbol . name : lower ( ) : find ( wanted , 1 , true ) then
local start = symbol . selectionRange . start
seen [ uri .. ":" .. start . line .. ":" .. start . character ] = true
found [
# found + 1
] = {
name = symbol . name ,
kind = symbol . kind ,
containerName = result . moduleName ,
location = { uri = uri , range = symbol . selectionRange } ,
data = { root = rootFor ( path ) . root } ,
}
end
end
end
end
end
for name , entries in pairs ( s . inc . projectIndex ( ) . byName or { } ) do
if query == "" or name : lower ( ) : find ( query : lower ( ) , 1 , true ) then
for _ , entry in ipairs ( entries ) do
local location = definitionLocation ( entry . definition )
local start = location ~= json . NULL and location . range . start or nil
if start and not seen [ location . uri .. ":" .. start . line .. ":" .. start . character ] then
found [ # found + 1 ] = {
name = name ,
kind = SYMBOL_KINDS [ entry . kind ] or SYMBOL_KINDS . variable ,
containerName = entry . moduleName ,
location = location ,



data = { root = rootFor ( uriToPath ( location . uri ) ) . root } ,
}
end
end
end
end
table . sort ( found , function ( a , b ) 
if a . name ~= b . name then
return a . name < b . name
end
return a . location . uri < b . location . uri
end )
respond ( id , found )
end

handlers [ "textDocument/documentHighlight" ] = function ( id , params ) 
local _ , doc , tok , offset = symbolAt ( params )
if not tok then
respond ( id , json . asArray ( { } ) ) ;
return
end
local highlights = wire . array ( { } )
local member = memberAt ( doc , offset )
local wanted = not member and symbolKey ( tok . definition ) or nil
if wanted then
for _ , other in ipairs ( doc . result . tokens or { } ) do
if symbolKey ( other . definition ) == wanted then
highlights [ # highlights + 1 ] = { range = tokenRange ( doc . text , other ) }
end
end
else
for _ , hit in ipairs ( member and memberOccurrences ( doc . result , member . moduleName , member . name ) or { } ) do
highlights [ # highlights + 1 ] = { range = tokenRange ( doc . text , hit . token ) }
end
end
respond ( id , highlights )
end

handlers [ "textDocument/foldingRange" ] = function ( id , params ) 
local _ , doc = documentAt ( params )
if not doc or not doc . result then
respond ( id , json . asArray ( { } ) )
return
end
local ranges , seen = wire . array ( { } ) , { }
for _ , span in ipairs ( foldableSpans ( doc . result ) ) do
local from = positionAtOffset ( doc . text , span [ 1 ] )
local to = positionAtOffset ( doc . text , span [ 2 ] )


local key = from . line .. ":" .. to . line
if to . line > from . line and not seen [ key ] then
seen [ key ] = true
ranges [ # ranges + 1 ] = { startLine = from . line , endLine = to . line - 1 , }
end
end
table . sort ( ranges , function ( a , b ) 
if a . startLine ~= b . startLine then
return a . startLine < b . startLine
end
return a . endLine > b . endLine
end )
respond ( id , ranges )
end

handlers [ "textDocument/selectionRange" ] = function ( id , params ) 
local _ , doc = documentAt ( params )
if not doc or not doc . result or not params . positions then
respond ( id , json . asArray ( { } ) )
return
end
local out = wire . array ( { } )
for _ , position in ipairs ( params . positions ) do
local offset = offsetAtPosition ( doc . text , position )
local chain = offset and enclosingChain ( doc . result , offset ) or { }


local built = nil
for index = 1 , # chain do
local span = chain [ index ]
built = { range = spanRange ( doc . text , span . from , span . to ) , parent = built }
end
out [ # out + 1 ] = built or { range = { start = position , [ "end" ] = position , } }
end
respond ( id , out )
end







handlers [ "$/cancelRequest" ] = function ( _ , params ) 
if host and params then
host . cancel ( params . id )
end
end
handlers [ "$/setTrace" ] = function ( ) 
end

handlers [ "textDocument/didClose" ] = function ( _ , params ) 
local uri = params . textDocument . uri
s . documents [ uri ] = nil
eachGraph ( function ( inc ) 
inc . closeDocument ( uriToPath ( uri ) )
end )
refreshOpenDocuments ( nil )
notify ( "textDocument/publishDiagnostics" , { uri = uri , diagnostics = json . asArray ( { } ) , } )
end








handlers [ "shutdown" ] = function ( id ) 
eachGraph ( function ( inc ) 
pcall ( function ( ) 
inc . persist ( )
end )
end )
shutDown = true
respond ( id , json . NULL )
end

handlers [ "exit" ] = function ( ) 
running = false
end









local function subject ( msg ) 
local textDocument = type ( msg . params ) == "table" and msg . params . textDocument or nil
local uri = type ( textDocument ) == "table" and textDocument . uri or nil

return type ( uri ) == "string" and uri or nil
end

local function dispatch ( msg ) 
if type ( msg ) == "table" and msg . method then
if msg . method ~= "exit" and ( shutDown or ( not initialized and msg . method ~= "initialize" ) ) then
if msg . id ~= nil then
send ( {
jsonrpc = "2.0" ,
id = msg . id ,
error = shutDown and { code = -32600 , message = "the server is shutting down" }
or { code = -32002 , message = "the server is not initialized" } ,
} )
end
return
end
initialized = true
if msg . id and host and host . isCancelled ( msg . id ) then
host . clearCancelled ( msg . id )
send ( { jsonrpc = "2.0" , id = msg . id , error = { code = -32800 , message = "request cancelled" } } )
return
end
local uri = subject ( msg )
s . useRoot ( uri and uriToPath ( uri ) or nil )




answering = msg . id and uri and { uri = uri , version = host and host . documentVersion ( uri ) or nil } or nil
local handler = handlers [ msg . method ]
if handler then
local hOk , err = pcall ( handler , msg . id , msg . params )
answering = nil
if not hOk and host and err == host . cancellation then



if msg . id then
host . clearCancelled ( msg . id )
send ( { jsonrpc = "2.0" , id = msg . id , error = { code = -32800 , message = "request cancelled" } } )
end
elseif not hOk then
io . stderr : write ( "nupp-lsp: error in " .. msg . method .. ": " .. tostring ( err ) .. "\n" )
if msg . id then
send ( { jsonrpc = "2.0" , id = msg . id , error = { code = -32603 , message = tostring ( err ) } } )
end
end
elseif msg . id then

send ( { jsonrpc = "2.0" , id = msg . id , error = { code = -32601 , message = "method not found" } } )
end
end
end

return {
dispatch = dispatch ,
running = function ( ) 
return running
end ,
exitCode = function ( ) 
return shutDown and 0 or 1
end ,
}
end







function lsp . readerMain ( ) 
io . stdout : setvbuf ( "no" )
while true do
local contentLength = nil
while true do
local line = io . stdin : read ( "*l" )
if line == nil then
return 0
end
line = line : gsub ( "\13$" , "" )
if line == "" then
do break end
end
local length = line : match ( "^[Cc]ontent%-[Ll]ength:%s*(%d+)" )
if length then



if # length > 12 or ( tonumber ( length ) or 0 ) > transportMod . MAX_FRAME then
io . stderr : write (
("nupp-lsp: frame declares %s bytes, more than the %d a frame may hold\n")

: format ( length , transportMod . MAX_FRAME )
)
return 1
end
contentLength = tonumber ( length )
end
end
if not contentLength then
io . stderr : write ( "nupp-lsp: frame has no Content-Length header\n" )
return 1
end
local body = io . stdin : read ( contentLength )
if body == nil or # body ~= contentLength then
io . stderr : write ( "nupp-lsp: input ended inside a frame\n" )
return 1
end
io . stdout : write ( "Content-Length: " .. # body .. "\13\n\13\n" .. body )
end
end






do local __nuppT90=function ( rootDir ) 
io . stdout : setvbuf ( "no" )

local function send ( msg ) 
local body = json . encode ( msg )
io . stdout : write ( "Content-Length: " .. # body .. "\13\n\13\n" .. body )
end

local process = require ( "nupp.io.process" )
local compilerRoot = os . getenv ( "NUPP_COMPILER_ROOT" )
local executable = compilerRoot and compilerRoot .. "/bin/nupp"
or type ( arg ) == "table" and type ( arg [ 0 ] ) == "string" and arg [ 0 ]
or nil
if not executable then
io . stderr : write ( "nupp-lsp: cannot identify the current executable\n" )
return 1
end
local relayArgs = { executable , "__lsp-reader" }
if compilerRoot and package . config : sub ( 1 , 1 ) == "\\" then
local path = ("package.path=%q .. package.path") : format ( compilerRoot .. "/build/?.lua;" )
relayArgs = { "luajit" , "-e" , path , compilerRoot .. "/build/nupp/tools/main.lua" , "__lsp-reader" , }
end
local relayOptions = { args = relayArgs , stdin = "inherit" , stdout = "pipe" , stderr = "inherit" , }





do local __nuppT105=0; local  __nuppT111,__nuppT113 ; local __nuppT112=false ; local __nuppT114=false ; local __nuppT106,__nuppT107,__nuppT108=__nuppT98(function() do local __nuppT115=__nuppT93( process . spawn ( relayOptions ) ); __nuppT111= __nuppT115[1] ; __nuppT105=1;  __nuppT112=true;  local  spawned , spawnProblem = __nuppT115[1] , __nuppT115[2] ;
if spawned == nil then
io . stderr : write ( "nupp-lsp: cannot start the input relay: " .. tostring ( spawnProblem ) .. "\n" )
return "return",__nuppT93( 1 )
end
local __nuppT116= (function(__nuppT117)  __nuppT112=false;  return __nupp.__manage(__nuppT117,__nuppManagedCleanup2,"affine(Process, close)|method:close")  end)( spawned ) ; __nuppT113= __nuppT116 ; __nuppT105=2;  __nuppT114=true;  local relayOwner=__nuppT113;
local relay = relayOwner : alias ( )




local frames = transportMod . new ( )


local broken = nil
local host






local function read ( waiting ) 
local chunk , problem = relay : with ( function ( child ) 
local reader = child . stdout
if reader == nil then
return nil
end
if waiting then
local got = reader : read ( 65536 )
if got == nil or got == "" then
return nil
end

return got
end

return reader : poll ( ) or ""
end )
if problem ~= nil then
error ( "nupp-lsp: " .. problem . message , 0 )
end

return chunk
end

local function feed ( chunk ) 
if not broken then
broken = frames . feed ( chunk )
end
end

local function pump ( ) 
while true do
local chunk = read ( false )
if chunk == nil or # chunk == 0 then
do break end
end
feed ( chunk )
end
end

host = {
currentId = nil ,
cancellation = { } ,
pump = pump ,
cancelled = function ( ) 
return host . currentId ~= nil and frames . isCancelled ( host . currentId )
end ,
cancel = frames . cancel ,
isCancelled = frames . isCancelled ,
clearCancelled = frames . clearCancelled ,
documentVersion = frames . documentVersion ,
}

local session = lsp . newSession ( rootDir , send , host )




local ended = false
while session . running ( ) and not ended and not broken do
pump ( )
while not frames . pending ( ) and not broken do
local chunk = read ( true )
if chunk == nil then
ended = true
do break end
end
feed ( chunk )
end
local msg = not ended and not broken and frames . take ( ) or nil
if msg and msg . malformed then
send ( { jsonrpc = "2.0" , id = json . NULL , error = { code = msg . code , message = msg . message } } )
elseif msg then
host . currentId = msg . id
session . dispatch ( msg )
host . currentId = nil
end
end



local relayFailed = false
if ended then
relay : with ( function ( child ) 
relayFailed = not child : wait ( ) : succeeded ( )
end )
end
do __nuppT114=false; __nuppDrop3( relayOwner ) end
if broken then
io . stderr : write ( "nupp-lsp: " .. broken .. "\n" )
return "return",__nuppT93( 1 )
end
if relayFailed then
return "return",__nuppT93( 1 )
end

return "return",__nuppT93( session . exitCode ( ) ) end; return "normal" end,__nuppT94); local __nuppT109={}; local __nuppT110=0; if __nuppT105>=2 and __nuppT114 then  local __nuppT124,__nuppT125=__nuppT97(__nuppCleanup1,__nuppT113);  if not __nuppT124 then __nuppT110=__nuppT110+1; __nuppT109[__nuppT110]=__nuppT125 end; end; if __nuppT105>=1 and __nuppT112 and __nuppT111~=nil then  local __nuppT126,__nuppT127=__nuppT97(__nuppCleanup1,__nuppT111);  if not __nuppT126 then __nuppT110=__nuppT110+1; __nuppT109[__nuppT110]=__nuppT127 end; end; if not __nuppT106 then if __nuppT110>0 then __nuppT99(__nuppT95(__nuppT107,__nuppT109,1),0) else __nuppT99(__nuppT107,0) end end; if __nuppT110>0 then if __nuppT110>1 then __nuppT99(__nuppT95(__nuppT109[1],__nuppT109,2),0) else __nuppT99(__nuppT109[1],0) end end; if __nuppT107=="return" then  return __nuppT100(__nuppT108,1,__nuppT108.n)  end; end
end lsp . run =__nuppT90; end

local __nuppExportValue= lsp ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.lsp"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.lsp"]=__nuppExports;return __nuppExports