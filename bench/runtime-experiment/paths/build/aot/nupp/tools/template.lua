_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.template\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.tools.template\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.tools.template\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.tools.template\0runtime\0004") , _G.nupp.__reflect.declaration("nupp.tools.template\0runtime\0005") };
































const files2 = require ( "nupp.io.files" )

local bundled = require ( "nupp.compiler.bundledlist" )
local fs = require ( "nupp.compiler.fs" )
local process = require ( "nupp.compiler.process" )
local syntax = require ( "nupp.compiler.shellsyntax" )

local join , normalize = fs . join , fs . normalize
local basename = fs . basename
local readFile , writeFile , exists = fs . readFile , fs . writeFile , fs . exists

local template = { }






const BUILTIN_PREFIX = "/templates"






const STEPS = { git = true , check = true , build = true , test = true }


const REMOTE_STEPS = { git = true }






const FORBIDDEN_IN_VALUE = "[/\\%z]"


template.Source = {} template.Source.__index = template.Source ;_G.nupp.__reflect.link(template.Source,__nuppT1[1],{ })

























template.Variable = {} template.Variable.__index = template.Variable ;_G.nupp.__reflect.link(template.Variable,__nuppT1[2],{ })














template.Manifest = {} template.Manifest.__index = template.Manifest ;_G.nupp.__reflect.link(template.Manifest,__nuppT1[3],{ __nuppT1[2] })







template.File = {} template.File.__index = template.File ;_G.nupp.__reflect.link(template.File,__nuppT1[4],{ })













template.Plan = {} template.Plan.__index = template.Plan ;_G.nupp.__reflect.link(template.Plan,__nuppT1[5],{ __nuppT1[1] , __nuppT1[4] })























local function isPathSpelling ( spelling ) 
return spelling : sub ( 1 , 1 ) == "."
or spelling : sub ( 1 , 1 ) == "/"
or spelling : sub ( 1 , 1 ) == "~"
or spelling : match ( "^[A-Za-z]:[/\\]" ) ~= nil
end

local function isUrlSpelling ( spelling ) 
return spelling : match ( "^[a-z][a-z0-9+.-]*://" ) ~= nil
or spelling : match ( "^git@" ) ~= nil
or spelling : match ( "^ssh://" ) ~= nil
end







function template . builtins ( ) 
local seen = { }
local names = { }
for _ , path in ipairs ( bundled . list ( "/templates" ) ) do
local name = path : sub ( 12 ) : match ( "^([^/]+)/" )
if name and not seen [ name ] then
seen [ name ] = true
names [ # names + 1 ] = name
end
end
table . sort ( names )

return names
end








function template . builtinDescription ( name ) 
local text = bundled . source ( "/templates" .. "/" .. name .. "/template.lua" )
if not text then
return ""
end
local manifest = template . manifest ( text , name .. "/template.lua" )

return manifest and manifest . description or ""
end








function template . resolve ( spelling , from , rev ) 
if from then
if spelling then
return nil , "--from names the template, so a template argument is one too many"
end
if rev then
return nil , "--rev has no meaning for a template directory"
end

return ( _G.setmetatable({ kind =  "directory" ,  path =  normalize ( from ) }, template.Source) )
end
spelling = spelling or "app"
if isPathSpelling ( spelling ) then
if rev then
return nil , "--rev has no meaning for a template directory"
end

return ( _G.setmetatable({ kind =  "directory" ,  path =  normalize ( spelling ) }, template.Source) )
end
local asked , attached = spelling , nil
local base , suffix = spelling : match ( "^(.-)@([^@/]+)$" )
if base and not isUrlSpelling ( spelling ) then
asked , attached = base , suffix
end
if attached and rev then
return nil , "the revision is given twice, once as @" .. attached .. " and once as --rev"
end
local wanted = attached or rev
if isUrlSpelling ( asked ) then
return ( _G.setmetatable({ kind =  "remote" ,  url =  asked ,  rev =  wanted }, template.Source) )
end
if not asked : find ( "/" , 1 , true ) then
if wanted then
return nil , "a built-in template has no revisions to choose between"
end
for _ , name in ipairs ( template . builtins ( ) ) do
if name == asked then
return ( _G.setmetatable({ kind =  "builtin" ,  name =  name }, template.Source) )
end
end

return nil , "no built-in template is called " .. asked .. "; the built-ins are " .. table . concat (
template . builtins ( ) ,
", "
)
end
local owner , repo , subdir = asked : match ( "^([^/]+)/([^/]+)/?(.*)$" )
if not owner or owner == "" or repo == "" then
return nil , "a repository template is spelled owner/repo, optionally followed by a path"
end

return ( _G.setmetatable({ kind =
"remote" ,  url =
"https://github.com/" .. owner .. "/" .. repo ,  subdir =
subdir ~= "" and subdir or nil ,  rev =
wanted }, template.Source) )

end





function template . describe ( source ) 
if source . kind == "builtin" then
return "built-in template " .. tostring ( source . name )
end
if source . kind == "directory" then
return tostring ( source . path )
end
local where = tostring ( source . url )
if source . subdir then
where = where .. " (" .. source . subdir .. ")"
end
if source . commit then
return where .. " at " .. source . commit
end

return where .. ( source . rev and ( " at " .. source . rev ) or "" )
end














local function walk ( root ) 
local found = { }
local pending = { "" }
while # pending > 0 do
local relative = table . remove ( pending )
local entries , listErr = files2 . list ( join ( root , relative ) )
if not entries then
return nil , "cannot read " .. join ( root , relative ) .. ": " .. tostring ( listErr )
end
for _ , entry in ipairs ( entries ) do
local child = relative == "" and entry . name or relative .. "/" .. entry . name
if entry . kind == "symlink" then
return nil , child .. " is a symbolic link, which a template may not contain"

elseif entry . kind == "directory" then



if entry . name ~= ".git" then
pending [ # pending + 1 ] = child
end

elseif entry . kind == "file" then
if child ~= "template.lua" then
found [ # found + 1 ] = child
end
end
end
end
table . sort ( found )

return found
end

local function copyOf ( library ) 
local copy = { }
for key , value in pairs ( library ) do
copy [ key ] = value
end

return copy
end
















local function sandbox ( ) 
return {
pairs = pairs ,
ipairs = ipairs ,
type = type ,
tostring = tostring ,
tonumber = tonumber ,
select = select ,
error = error ,
string = copyOf ( string ) ,
table = copyOf ( table ) ,
math = copyOf ( math ) ,
}
end



const INSTRUCTION_BUDGET = 200000

local function loadSandboxed ( text , where ) 
local chunk , loadErr = loadstring ( text , "=" .. where )
if not chunk then
return nil , where .. " does not parse: " .. tostring ( loadErr )
end
setfenv ( chunk , ( { pairs = pairs , ipairs = ipairs , type = type , tostring = tostring , tonumber = tonumber , select = select , error = error , string = copyOf ( string ) , table = copyOf ( table ) , math = copyOf ( math ) , } ) )






if jit then
jit . off ( chunk , true )
end
local hooked = false


local hostHook , hostMask , hostCount = ( debug . gethook ) ( )
debug . sethook (
function ( ) 
hooked = true
error ( where .. " did not finish loading" , 0 )
end ,
"" ,
200000
)
local ok , result = pcall ( chunk )
debug . sethook ( hostHook , hostMask , hostCount )
if not ok then
if hooked then
return nil , where .. " runs too long to be a data literal"
end

return nil , where .. ": " .. tostring ( result )
end
if type ( result ) ~= "table" then
return nil , where .. " must return a table"
end

return result
end

local function stringList ( value , label ) 
if value == nil then
return { }
end
if type ( value ) ~= "table" then
return nil , label .. " must be a list of strings"
end
local count , maximum = 0 , 0
for index , entry in pairs ( value ) do
if type ( index ) ~= "number" or index < 1 or index ~= math . floor ( index ) then
return nil , label .. " must be a dense list of strings"
end
if type ( entry ) ~= "string" then
return nil , label .. "[" .. index .. "] must be a string"
end
count = count + 1
maximum = math . max ( maximum , index )
end
if count ~= maximum then
return nil , label .. " must be a dense list of strings"
end
local list = { }
for index , entry in ipairs ( value ) do
if type ( entry ) ~= "string" then
return nil , label .. "[" .. index .. "] must be a string"
end
list [ # list + 1 ] = entry
end

return list
end



const DERIVED = { moduleName = true , directory = true }

local function readVariables ( value ) 
if value == nil then
return { }
end
if type ( value ) ~= "table" then
return nil , "variables must be a table"
end
local variables = { }
for name , declared in pairs ( value ) do
local label = "variables." .. tostring ( name )
if type ( name ) ~= "string" then
return nil , "variables must be keyed by name"
end
if DERIVED [ name ] then
return nil , label .. " is derived from the project name and cannot be declared"
end
if type ( declared ) ~= "table" then
return nil , label .. " must be a table"
end
local entry = declared
for key in pairs ( entry ) do
if key ~= "description"
and key ~= "default"
and key ~= "required"
and key ~= "pattern"
and key ~= "invalid"
then
return nil , label .. "." .. tostring ( key ) .. " is not a variable field"
end
end
if name == "name" and entry . default ~= nil then
return nil , label
.. " cannot have a default, since the project name comes from --name or the directory"

end
for _ , key in ipairs ( { "description" , "default" , "pattern" , "invalid" } ) do
if entry [ key ] ~= nil and type ( entry [ key ] ) ~= "string" then
return nil , label .. "." .. key .. " must be a string"
end
end
if entry . required ~= nil and type ( entry . required ) ~= "boolean" then
return nil , label .. ".required must be a boolean"
end
variables [
name
] = _G.setmetatable({ description =
entry . description ,  default =
entry . default ,  required =
entry . required ,  pattern =
entry . pattern ,  invalid =
entry . invalid }, template.Variable)

end

return variables
end







function template . manifest ( text , where ) 
local loaded , loadErr = loadSandboxed ( text , where )
if not loaded then
return nil , loadErr
end
local table_ = loaded
for key in pairs ( table_ ) do
if key ~= "description" and key ~= "variables" and key ~= "raw" and key ~= "after" then
return nil , where .. ": " .. tostring ( key ) .. " is not a template field"
end
end
if table_ . description ~= nil and type ( table_ . description ) ~= "string" then
return nil , where .. ": description must be a string"
end
local variables , variablesErr = readVariables ( table_ . variables )
if not variables then
return nil , where .. ": " .. tostring ( variablesErr )
end
local raw , rawErr = stringList ( table_ . raw , "raw" )
if not raw then
return nil , where .. ": " .. tostring ( rawErr )
end
local after , afterErr = stringList ( table_ . after , "after" )
if not after then
return nil , where .. ": " .. tostring ( afterErr )
end
for _ , step in ipairs ( after ) do
if not STEPS [ step ] then
local known = { }
for name in pairs ( STEPS ) do
known [ # known + 1 ] = name
end
table . sort ( known )

return nil , where .. ": " .. step .. " is not a post-init step" .. "\nAvailable: " .. table . concat (
known ,
", "
)
end
end

return ( _G.setmetatable({ description =
table_ . description ,  variables =
variables ,  raw =
raw ,  after =
after }, template.Manifest) )

end










local function substitute ( text , values , where ) 
local failure = nil

local parts = { }
local index = 1
while index <= # text do
local at = text : find ( "$${" , index , true )
if not at then
parts [ # parts + 1 ] = text : sub ( index )
do break end
end
parts [ # parts + 1 ] = text : sub ( index , at - 1 )
parts [ # parts + 1 ] = "\0ESCAPED\0"
index = at + 3
end
local joined = table . concat ( parts )
local expanded = joined : gsub ( "%${([^}]*)}" , function ( name ) 
if failure then
return ""
end
local replacement = values [ name ]
if replacement == nil then
failure = where .. " uses ${" .. name .. "}, which the template does not declare"
return ""
end

return replacement
end )
if failure then
return nil , failure
end

return ( expanded : gsub ( "%zESCAPED%z" , "${" ) )
end

template . substitute = substitute










function template . values (
manifest ,
name ,
directory ,
supplied
) 
local given = supplied or { }
for key in pairs ( given ) do




if key == "name" or DERIVED [ key ] then
return nil , key
.. " is derived from the project name\nName the project with --name, or by naming the directory."

end
if not manifest . variables [ key ] then
local declared = { }
for declaredName in pairs ( manifest . variables ) do
if declaredName ~= "name" then
declared [ # declared + 1 ] = declaredName
end
end
table . sort ( declared )
local hint = # declared > 0 and ( "\nDeclared: " .. table . concat ( declared , ", " ) )
or "\nThis template declares no variables to set."

return nil , key .. " is not a variable of this template" .. hint
end
end
local values = { name = name , moduleName = ( name : gsub ( "[-_]" , "" ) ) , directory = directory , }
for key , declared in pairs ( manifest . variables ) do
if key ~= "name" then
local value = given [ key ] or declared . default
if value == nil then
return nil , "this template needs a value for " .. key .. (
declared . description and ( ": " .. declared . description ) or ""
) .. "\nGive one with --set " .. key .. "=VALUE."
end
values [ key ] = value
end
end
for key , value in pairs ( values ) do
local declared = manifest . variables [ key ]





if key ~= "directory" and value : find ( "[/\\%z]" ) then
return nil , key .. " may not contain a path separator"
end
if declared and declared . pattern and not value : match ( declared . pattern ) then
return nil , declared . invalid or ( key .. " does not match " .. declared . pattern )
end
end

return values
end







local function readTree ( source ) 
if source . kind == "builtin" then
local prefix = "/templates" .. "/" .. tostring ( source . name )
local files = { }
local any = false
for _ , path in ipairs ( bundled . list ( prefix ) ) do
local relative = path : sub ( # prefix + 2 )
local text = bundled . source ( path )
if not text then
return nil , "this compiler carries no " .. path
end
files [ relative ] = text
any = true
end
if not any then
return nil , "this compiler carries no template called " .. tostring ( source . name )
end

return files
end
local root = tostring ( source . path )
if not exists ( join ( root , "template.lua" ) ) then
return nil , root .. " has no template.lua, so it is not a template"
end
local paths , walkErr = walk ( root )
if not paths then
return nil , walkErr
end
local files = { }
for _ , relative in ipairs ( paths ) do
local text , readErr = readFile ( join ( root , relative ) )
if not text then
return nil , tostring ( readErr )
end
files [ relative ] = text
end
files [ "template.lua" ] = readFile ( join ( root , "template.lua" ) )

return files
end





local byteAt = string . byte

const SLASH , BACKSLASH , DOT , COLON = 47 , 92 , 46 , 58

local function isLetter ( code ) 
return code ~= nil and ( ( code >= 65 and code <= 90 ) or ( code >= 97 and code <= 122 ) )
end






local function componentsAreSafe ( path ) 
local length = # path
local first = byteAt ( path , 1 )
if first == 47 or first == 92 or ( ( first ~= nil and ( ( first >= 65 and first <= 90 ) or ( first >= 97 and first <= 122 ) ) ) and byteAt ( path , 2 ) == 58 ) then
return false , path .. " is absolute, and a template writes only under its destination"
end
local start = 1
for index = 1 , length + 1 do
local code = index <= length and byteAt ( path , index ) or 47
if code == 47 or code == 92 then
local size = index - start
if size == 0 then
return false , path .. " has an empty path component"

elseif size == 2 and byteAt ( path , start ) == 46 and byteAt ( path , start + 1 ) == 46 then
return false , path .. " leaves the destination directory"

elseif size == 1 and byteAt ( path , start ) == 46 then
return false , path .. " has an empty path component"
end
start = index + 1
end
end

return true
end






local function destinationIsFree ( destination ) 
local entries = files2 . list ( destination )
if not entries then
return true
end
for _ , entry in ipairs ( entries ) do
if entry . name ~= ".git" then
return false , destination .. " is not empty"
end
end

return true
end









function template . plan ( source , destination , opts


) 
local asked = opts or { }
destination = normalize ( destination )
local free , freeErr = destinationIsFree ( destination )
if not free then
return nil , freeErr
end
local tree , treeErr = readTree ( source )
if not tree then
return nil , treeErr
end
local manifestText = tree [ "template.lua" ]
if not manifestText then
return nil , template . describe ( source ) .. " has no template.lua, so it is not a template"
end
local manifest , manifestErr = template . manifest ( manifestText , "template.lua" )
if not manifest then
return nil , manifestErr
end
local name = asked . name or basename ( destination )
local values , valuesErr = template . values ( manifest , name , destination , asked . set )
if not values then
return nil , valuesErr
end
local isRaw = { }
for _ , glob in ipairs ( manifest . raw ) do
isRaw [ # isRaw + 1 ] = syntax . glob ( glob )
end
local files = { }
local sources = { }
for relative in pairs ( tree ) do
if relative ~= "template.lua" then
sources [ # sources + 1 ] = relative
end
end
table . sort ( sources )
local claimed = { }
for _ , relative in ipairs ( sources ) do
local verbatim = false
for _ , matches in ipairs ( isRaw ) do
if matches ( relative ) then
verbatim = true
do break end
end
end
local output , outputErr = substitute ( relative , values , "the path " .. relative )
if not output then
return nil , outputErr
end
local safe , safeErr = componentsAreSafe ( output )
if not safe then
return nil , safeErr
end
local collision = claimed [ output ]
if collision then
return nil , collision .. " and " .. relative .. " both become " .. output
end
claimed [ output ] = relative
local text = tree [ relative ]
if not verbatim then
local substituted , textErr = substitute ( text , values , relative )
if not substituted then
return nil , textErr
end
text = substituted
end
files [ # files + 1 ] = _G.setmetatable({ source =  relative ,  output =  output ,  text =  text ,  verbatim =  verbatim }, template.File)
end
if # files == 0 then
return nil , template . describe ( source ) .. " contains no files to write"
end
local steps = { }
local dropped = { }
local allowed = source . kind == "remote" and REMOTE_STEPS or STEPS
for _ , step in ipairs ( manifest . after ) do
if allowed [ step ] then
steps [ # steps + 1 ] = step
else
dropped [ # dropped + 1 ] = step
end
end

return ( _G.setmetatable({ source =
source ,  destination =
destination ,  files =
files ,  values =
values ,  steps =
steps ,  dropped =
dropped }, template.Plan) )

end














function template . write ( plan ) 
local written = { }
for _ , file in ipairs ( plan . files ) do
local path = join ( plan . destination , file . output )
local ok , err = writeFile ( path , file . text )
if not ok then
return nil , tostring ( err )
end
written [ # written + 1 ] = path
end

return written
end













function template . fetch ( source , into ) 
local url = tostring ( source . url )
local checkout = join ( into , "checkout" )




local clone = { "git" , "-c" , "advice.detachedHead=false" , "clone" , "--quiet" , "--depth" , "1" }
if source . rev then


clone [ # clone + 1 ] = "--branch"
clone [ # clone + 1 ] = source . rev
end
clone [ # clone + 1 ] = url
clone [ # clone + 1 ] = checkout
local code , output = process . capture ( clone )
if code ~= 0 and source . rev then
files2 . remove ( checkout , true )
local fullCode , fullOutput = process . capture ( {
"git" ,
"-c" ,
"advice.detachedHead=false" ,
"clone" ,
"--quiet" ,
url ,
checkout
} )
if fullCode ~= 0 then
return nil , "cannot clone " .. url .. "\n" .. fullOutput
end



local verifyCode , verified = process . capture (
{ "git" , "rev-parse" , "--verify" , "--quiet" , source . rev .. "^{commit}" } ,
{ cwd = checkout }
)
if verifyCode ~= 0 then
return nil , url .. " has no revision " .. tostring ( source . rev )
end
local outCode , outOutput = process . capture (
{ "git" , "-c" , "advice.detachedHead=false" , "checkout" , "--quiet" , "--detach" , ( verified : gsub ( "%s+$" , "" ) ) } ,
{ cwd = checkout }
)
if outCode ~= 0 then
return nil , "cannot check out " .. tostring ( source . rev ) .. " of " .. url .. "\n" .. outOutput
end
elseif code ~= 0 then
return nil , "cannot clone " .. url .. "\n" .. output
end
local revCode , head = process . capture ( { "git" , "rev-parse" , "HEAD" } , { cwd = checkout } )
if revCode ~= 0 then
return nil , "cannot read the commit " .. url .. " resolved to"
end
source . commit = ( head : gsub ( "%s+$" , "" ) )
source . path = source . subdir and join ( checkout , source . subdir ) or checkout
if not exists ( join ( source . path , "template.lua" ) ) then
return nil , template . describe ( source ) .. " has no template.lua, so it is not a template"
end

return source
end














function template . step ( step , destination , nupp , env ) 
if step == "git" then
if exists ( join ( destination , ".git" ) ) then
return true
end

return process . run ( { "git" , "init" , "--quiet" , destination } ) == 0
end
local argv = { nupp , step }

return process . run ( argv , { cwd = destination , env = env } ) == 0
end

local __nuppExportValue= template ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.template"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.template"]=__nuppExports;return __nuppExports