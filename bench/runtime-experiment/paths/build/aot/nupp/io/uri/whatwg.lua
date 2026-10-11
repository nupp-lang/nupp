_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

























local contracts = require ( "nupp.io.uri.spi" )

local whatwg = { }

const DEFAULT_PORTS = { http = 80 , https = 443 , ws = 80 , wss = 443 , ftp = 21 , }

const HEX = "0123456789ABCDEF"



const C0_SET = 0
const FRAGMENT_SET = 1
const QUERY_SET = 2
const SPECIAL_QUERY_SET = 3
const PATH_SET = 4
const USERINFO_SET = 5

local function inSet ( byte , set ) 
if byte < 32 or byte > 126 then
return true
end
if set == 0 then
return false
end
if byte == 32 or byte == 34 or byte == 60 or byte == 62 then
return true
end
if set == 1 then
return byte == 96
end
if byte == 35 then
return true
end
if set == 2 then
return false
end
if set == 3 then
return byte == 39
end
if byte == 63 or byte == 96 or byte == 123 or byte == 125 then
return true
end
if set == 4 then
return false
end

return byte == 47
or byte == 58
or byte == 59
or byte == 61
or byte == 64
or ( byte >= 91 and byte <= 94 )
or byte == 124
end

local function encodeByte ( byte , set ) 
if inSet ( byte , set ) then
local high = math . floor ( byte / 16 )
local low = byte % 16
return "%" .. ("0123456789ABCDEF") : sub ( high + 1 , high + 1 ) .. ("0123456789ABCDEF") : sub ( low + 1 , low + 1 )
end

return string . char ( byte )
end

local function encodeText ( text , set ) 
local out = { }
for index = 1 , # text do
out [ index ] = encodeByte ( text : byte ( index ) , set )
end

return table . concat ( out )
end

local function hexValue ( byte ) 
if byte == nil then
return nil
elseif byte >= 48 and byte <= 57 then
return byte - 48
elseif byte >= 65 and byte <= 70 then
return byte - 55
elseif byte >= 97 and byte <= 102 then
return byte - 87
end

return nil
end

local function percentDecode ( text ) 
if text : find ( "%" , 1 , true ) == nil then
return text
end
local out = { }
local index = 1
while index <= # text do
local byte = text : byte ( index )
local high = hexValue ( text : byte ( index + 1 ) )
local low = hexValue ( text : byte ( index + 2 ) )
if byte == 37 and high ~= nil and low ~= nil then
out [ # out + 1 ] = string . char ( high * 16 + low )
index = index + 3
else
out [ # out + 1 ] = string . char ( byte )
index = index + 1
end
end

return table . concat ( out )
end

local function validUtf8 ( text ) 
local at , length = 1 , # text
while at <= length do
local first = text : byte ( at )
if first < 128 then
at = at + 1
else
local count = first >= 194 and first <= 223 and 1
or first >= 224 and first <= 239 and 2
or first >= 240 and first <= 244 and 3
or 0
if count == 0 or at + count > length then
return false
end
local second = text : byte ( at + 1 )
if second < 128
or second > 191
or first == 224 and second < 160
or first == 237 and second > 159
or first == 240 and second < 144
or first == 244 and second > 143
then
return false
end
for offset = 2 , count do
local continuation = text : byte ( at + offset )
if continuation < 128 or continuation > 191 then
return false
end
end
at = at + count + 1
end
end

return true
end





local function ipv4Number ( text ) 
if text == "" then
return nil
end
local radix = 10
local digits = text
if text : sub ( 1 , 2 ) == "0x" or text : sub ( 1 , 2 ) == "0X" then
radix = 16
digits = text : sub ( 3 )
elseif # text >= 2 and text : sub ( 1 , 1 ) == "0" then
radix = 8
digits = text : sub ( 2 )
end
if digits == "" then
return 0
end
local pattern = radix == 16 and "^%x+$" or radix == 8 and "^[0-7]+$" or "^%d+$"
if digits : match ( pattern ) == nil then
return nil
end





local value = 0
for index = 1 , # digits do
value = value * radix + ( tonumber ( digits : sub ( index , index ) , 16 ) )
end

return value
end

local function endsInANumber ( text ) 
local parts = { }
for part in ( text .. "." ) : gmatch ( "([^.]*)%." ) do
parts [ # parts + 1 ] = part
end
if parts [ # parts ] == "" then
if # parts == 1 then
return false
end
parts [ # parts ] = nil
end
local last = parts [ # parts ]
if last ~= "" and last : match ( "^%d+$" ) ~= nil then
return true
end

return ipv4Number ( last ) ~= nil
end

local function ipv4 ( text ) 
local parts = { }
for part in ( text .. "." ) : gmatch ( "([^.]*)%." ) do
parts [ # parts + 1 ] = part
end
if parts [ # parts ] == "" and # parts > 1 then
parts [ # parts ] = nil
end
if # parts > 4 then
return nil , "invalid IPv4 address"
end
local numbers = { }
for index , part in ipairs ( parts ) do
local value = ipv4Number ( part )
if value == nil then
return nil , "invalid IPv4 address"
end
if value > 255 and index < # parts then
return nil , "invalid IPv4 address"
end
numbers [ index ] = value
end
local last = numbers [ # numbers ]
if last >= 256 ^ ( 5 - # numbers ) then
return nil , "invalid IPv4 address"
end
local address = last
for index = 1 , # numbers - 1 do
address = address + numbers [ index ] * 256 ^ ( 4 - index )
end
local octets = { }
for index = 4 , 1 , -1 do
octets [ index ] = tostring ( math . floor ( address % 256 ) )
address = math . floor ( address / 256 )
end

return table . concat ( octets , "." ) , nil
end

local function ipv6 ( text ) 

local pieces = { 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0 }
local pieceIndex = 1
local compress = nil
local at = 1
local length = # text
if text : byte ( 1 ) == 58 then
if text : byte ( 2 ) ~= 58 then
return nil , "invalid IPv6 address"
end
at = 3
pieceIndex = pieceIndex + 1
compress = pieceIndex
end
while at <= length do
if pieceIndex == 9 then
return nil , "invalid IPv6 address"
end
if text : byte ( at ) == 58 then
if compress ~= nil then
return nil , "invalid IPv6 address"
end
at = at + 1
pieceIndex = pieceIndex + 1
compress = pieceIndex
else
local value = 0
local count = 0
while count < 4 and hexValue ( text : byte ( at ) ) ~= nil do
value = value * 16 + ( hexValue ( text : byte ( at ) ) )
at = at + 1
count = count + 1
end
if text : byte ( at ) == 46 then
if count == 0 then
return nil , "invalid IPv6 address"
end
at = at - count
if pieceIndex > 7 then
return nil , "invalid IPv6 address"
end
local numbersSeen = 0
while at <= length do
local ipv4Piece = nil
if numbersSeen > 0 then
if text : byte ( at ) == 46 and numbersSeen < 4 then
at = at + 1
else
return nil , "invalid IPv6 address"
end
end
local byte = text : byte ( at )
if byte == nil or byte < 48 or byte > 57 then
return nil , "invalid IPv6 address"
end
while true do
local digit = text : byte ( at )
if digit == nil or digit < 48 or digit > 57 then
do break end
end
local number = digit - 48
if ipv4Piece == nil then
ipv4Piece = number
elseif ipv4Piece == 0 then
return nil , "invalid IPv6 address"
else
ipv4Piece = ipv4Piece * 10 + number
end
if ( ipv4Piece ) > 255 then
return nil , "invalid IPv6 address"
end
at = at + 1
end
pieces [ pieceIndex ] = pieces [ pieceIndex ] * 256 + ( ipv4Piece )
numbersSeen = numbersSeen + 1
if numbersSeen == 2 or numbersSeen == 4 then
pieceIndex = pieceIndex + 1
end
end
if numbersSeen ~= 4 then
return nil , "invalid IPv6 address"
end
do break end
elseif text : byte ( at ) == 58 then
at = at + 1
if at > length then
return nil , "invalid IPv6 address"
end
elseif at <= length then
return nil , "invalid IPv6 address"
end
pieces [ pieceIndex ] = value
pieceIndex = pieceIndex + 1
end
end
if compress ~= nil then
local swaps = pieceIndex - compress
pieceIndex = 8
while pieceIndex ~= 1 and swaps > 0 do
local from = compress + swaps - 1
pieces [ pieceIndex ] , pieces [ from ] = pieces [ from ] , pieces [ pieceIndex ]
pieceIndex = pieceIndex - 1
swaps = swaps - 1
end
elseif pieceIndex ~= 9 then
return nil , "invalid IPv6 address"
end


local runStart = nil
local runLength = 1
local index = 1
while index <= 8 do
if pieces [ index ] == 0 then
local finish = index
while finish <= 8 and pieces [ finish ] == 0 do
finish = finish + 1
end
if finish - index > runLength then
runStart = index
runLength = finish - index
end
index = finish
else
index = index + 1
end
end
local out = { }
local ignoring = false
for position = 1 , 8 do
if not ( ignoring and pieces [ position ] == 0 ) then
ignoring = false
if runStart == position then
out [ # out + 1 ] = position == 1 and "::" or ":"
ignoring = true
else
out [ # out + 1 ] = ("%x") : format ( pieces [ position ] )
if position ~= 8 then
out [ # out + 1 ] = ":"
end
end
end
end

return "[" .. table . concat ( out ) .. "]" , nil
end



local function forbiddenHost ( byte ) 
return byte == 0
or byte == 9
or byte == 10
or byte == 13
or byte == 32
or byte == 35
or byte == 47
or byte == 58
or byte == 60
or byte == 62
or byte == 63
or byte == 64
or ( byte >= 91 and byte <= 94 )
or byte == 124
end

local function parseHost ( input , opaque , trustHosts ) 
if input : sub ( 1 , 1 ) == "[" then
if input : sub ( -1 ) ~= "]" then
return nil , "invalid IPv6 address"
end
return ipv6 ( input : sub ( 2 , -2 ) )
end
if opaque then
for index = 1 , # input do
if forbiddenHost ( input : byte ( index ) ) then
return nil , "invalid domain character"
end
end
return encodeText ( input , 0 ) , nil
end
local domain = percentDecode ( input )
local international = domain : find ( "[€-ÿ]" ) ~= nil
if not international then
domain = domain : lower ( )
international = ( "." .. domain ) : find ( ".xn--" , 1 , true ) ~= nil
end
if international then
if trustHosts then
return input , nil
end
return nil , "internationalized host needs a host URL parser"
end
if domain == "" then
return nil , "empty host"
end
for index = 1 , # domain do
local byte = domain : byte ( index )
if ( byte == 0 or byte == 9 or byte == 10 or byte == 13 or byte == 32 or byte == 35 or byte == 47 or byte == 58 or byte == 60 or byte == 62 or byte == 63 or byte == 64 or ( byte >= 91 and byte <= 94 ) or byte == 124 ) or byte < 32 or byte == 37 or byte == 127 then
return nil , "invalid domain character"
end
end
if endsInANumber ( domain ) then
return ipv4 ( domain )
end

return domain , nil
end





local function windowsDriveLetter ( text , normalized ) 
if # text ~= 2 or text : match ( "^%a" ) == nil then
return false
end
local second = text : sub ( 2 , 2 )

return second == ":" or ( not normalized and second == "|" )
end

local function startsWithDriveLetter ( text , from ) 
if not windowsDriveLetter ( text : sub ( from , from + 1 ) , false ) then
return false
end
local third = text : sub ( from + 2 , from + 2 )

return third == "" or third == "/" or third == "\\" or third == "?" or third == "#"
end

local function singleDot ( segment ) 
return segment == "." or segment : lower ( ) == "%2e"
end

local function doubleDot ( segment ) 
local lowered = segment : lower ( )
return lowered == ".." or lowered == ".%2e" or lowered == "%2e." or lowered == "%2e%2e"
end

local function shorten ( url ) 
local path = url . path
if url . scheme == "file" and # path == 1 and windowsDriveLetter ( path [ 1 ] , true ) then
return
end
path [ # path ] = nil
end

local function copyPath ( path ) 
if type ( path ) ~= "table" then
return path
end
local copy = { }
for index , segment in ipairs ( path ) do
copy [ index ] = segment
end

return copy
end



local function fromParts ( parts ) 
local path
if parts . authority == nil and parts . path : sub ( 1 , 1 ) ~= "/" then
path = parts . path
else
local segments = { }
if parts . path ~= "" then
for segment in ( parts . path : sub ( 2 ) .. "/" ) : gmatch ( "([^/]*)/" ) do
segments [ # segments + 1 ] = segment
end
end
path = segments
end
local host = nil
if parts . authority ~= nil then
host = parts . host or ""
end

return {
scheme = parts . scheme ,
username = parts . username ,
password = parts . password or "" ,
host = host ,
port = parts . port ,
path = path ,
query = parts . query ,
fragment = parts . fragment ,
}
end

local function serialize ( url ) 
local authority = nil
local out = url . scheme .. ":"
if url . host ~= nil then
local userInfo = ""
if url . username ~= "" or url . password ~= "" then
userInfo = url . username .. ( url . password ~= "" and ":" .. url . password or "" ) .. "@"
end
authority = userInfo .. url . host .. ( url . port ~= nil and ":" .. tostring ( url . port ) or "" )
out = out .. "//" .. authority
end
local path
if type ( url . path ) == "string" then
path = url . path
else
local segments = { }
for index , segment in ipairs ( url . path ) do
segments [ index ] = "/" .. segment
end
path = table . concat ( segments )
if url . host == nil and # url . path > 1 and url . path [ 1 ] == "" then
out = out .. "/."
end
end
out = out .. path
if url . query ~= nil then
out = out .. "?" .. url . query
end
if url . fragment ~= nil then
out = out .. "#" .. url . fragment
end

return ( _G.setmetatable({ text =
out ,  scheme =
url . scheme ,  authority =
authority ,  username =
url . username ,  password =
url . password ~= "" and url . password or nil ,  host =
url . host ~= "" and url . host or nil ,  port =
url . port ,  path =
path ,  query =
url . query ,  fragment =
url . fragment }, contracts.UriParts) )

end





const SCHEME_START = 1
const SCHEME = 2
const NO_SCHEME = 3
const SPECIAL_RELATIVE_OR_AUTHORITY = 4
const PATH_OR_AUTHORITY = 5
const RELATIVE = 6
const RELATIVE_SLASH = 7
const SPECIAL_AUTHORITY_SLASHES = 8
const SPECIAL_AUTHORITY_IGNORE_SLASHES = 9
const AUTHORITY = 10
const HOST = 11
const PORT = 12
const FILE = 13
const FILE_SLASH = 14
const FILE_HOST = 15
const PATH_START = 16
const PATH = 17
const OPAQUE_PATH = 18
const QUERY = 19
const FRAGMENT = 20

local function isSpecial ( scheme ) 
return DEFAULT_PORTS [ scheme ] ~= nil or scheme == "file"
end








function whatwg . refusal ( text ) 
if text : find ( "\0" , 1 , true ) ~= nil then
return "URI contains a NUL byte"
end
if not validUtf8 ( text ) then
return "URI is not valid UTF-8"
end

return nil
end









function whatwg . parse ( text , base , trustHosts ) 
local refused = whatwg . refusal ( text )
if refused ~= nil then
return nil , refused
end
local trusted = trustHosts == true
local input = text : gsub ( "^[%z\1- ]+" , "" ) : gsub ( "[%z\1- ]+$" , "" ) : gsub ( "[\9\n\13]" , "" )
local baseUrl = base ~= nil and fromParts ( base ) or nil
local url = {
scheme = "" ,
username = "" ,
password = "" ,
host = nil ,
port = nil ,
path = { } ,
query = nil ,
fragment = nil ,
}
local state = 1
local buffer = { }
local atSignSeen = false
local insideBrackets = false
local passwordTokenSeen = false
local length = # input
local pointer = 1

local function remainingStartsWith ( value ) 
return input : sub ( pointer + 1 , pointer + # value ) == value
end

while true do
local c = input : sub ( pointer , pointer )
local eof = pointer > length
local special = isSpecial ( url . scheme )
if state == 1 then
if c : match ( "^%a$" ) ~= nil then
buffer [ # buffer + 1 ] = c : lower ( )
state = 2
else
state = 3
pointer = pointer - 1
end
elseif state == 2 then
if c : match ( "^[%w+.-]$" ) ~= nil then
buffer [ # buffer + 1 ] = c : lower ( )
elseif c == ":" then
url . scheme = table . concat ( buffer )
buffer = { }
special = isSpecial ( url . scheme )
if url . scheme == "file" then
state = 13
elseif special and baseUrl ~= nil and baseUrl . scheme == url . scheme then
state = 4
elseif special then
state = 8
elseif remainingStartsWith ( "/" ) then
state = 5
pointer = pointer + 1
else
url . path = ""
state = 18
end
else
buffer = { }
url . scheme = ""
state = 3
pointer = 0
end
elseif state == 3 then
if baseUrl == nil then
return nil , "relative URL without a base"
elseif type ( baseUrl . path ) == "string" then
if c ~= "#" then
return nil , "relative URL with a cannot-be-a-base base"
end
url . scheme = baseUrl . scheme
url . path = baseUrl . path
url . query = baseUrl . query
url . fragment = ""
state = 20
elseif baseUrl . scheme ~= "file" then
state = 6
pointer = pointer - 1
else
state = 13
pointer = pointer - 1
end
elseif state == 4 then
if c == "/" and remainingStartsWith ( "/" ) then
state = 9
pointer = pointer + 1
else
state = 6
pointer = pointer - 1
end
elseif state == 5 then
if c == "/" then
state = 10
else
state = 17
pointer = pointer - 1
end
elseif state == 6 then
url . scheme = baseUrl . scheme
special = isSpecial ( url . scheme )
if c == "/" or ( special and c == "\\" ) then
state = 7
else
url . username = baseUrl . username
url . password = baseUrl . password
url . host = baseUrl . host
url . port = baseUrl . port
url . path = copyPath ( baseUrl . path )
url . query = baseUrl . query
if c == "?" then
url . query = ""
state = 19
elseif c == "#" then
url . fragment = ""
state = 20
elseif not eof then
url . query = nil
shorten ( url )
state = 17
pointer = pointer - 1
end
end
elseif state == 7 then
if special and ( c == "/" or c == "\\" ) then
state = 9
elseif c == "/" then
state = 10
else
url . username = baseUrl . username
url . password = baseUrl . password
url . host = baseUrl . host
url . port = baseUrl . port
state = 17
pointer = pointer - 1
end
elseif state == 8 then
if c == "/" and remainingStartsWith ( "/" ) then
state = 9
pointer = pointer + 1
else
state = 9
pointer = pointer - 1
end
elseif state == 9 then
if c ~= "/" and c ~= "\\" then
state = 10
pointer = pointer - 1
end
elseif state == 10 then
if c == "@" then
if atSignSeen then
table . insert ( buffer , 1 , "%40" )
end
atSignSeen = true
local collected = table . concat ( buffer )
for index = 1 , # collected do
local byte = collected : byte ( index )
if byte == 58 and not passwordTokenSeen then
passwordTokenSeen = true
elseif passwordTokenSeen then
url . password = url . password .. encodeByte ( byte , 5 )
else
url . username = url . username .. encodeByte ( byte , 5 )
end
end
buffer = { }
elseif eof or c == "/" or c == "?" or c == "#" or ( special and c == "\\" ) then
local collected = table . concat ( buffer )
if atSignSeen and collected == "" then
return nil , "empty host"
end
pointer = pointer - # collected - 1
buffer = { }
state = 11
else
buffer [ # buffer + 1 ] = c
end
elseif state == 11 then
if c == ":" and not insideBrackets then
local collected = table . concat ( buffer )
if collected == "" then
return nil , "empty host"
end
local host , reason = parseHost ( collected , not special , trusted )
if host == nil then
return nil , reason
end
url . host = host
buffer = { }
state = 12
elseif eof or c == "/" or c == "?" or c == "#" or ( special and c == "\\" ) then
pointer = pointer - 1
local collected = table . concat ( buffer )
if special and collected == "" then
return nil , "empty host"
end
local host , reason = parseHost ( collected , not special , trusted )
if host == nil then
return nil , reason
end
url . host = host
buffer = { }
state = 16
else
if c == "[" then
insideBrackets = true
elseif c == "]" then
insideBrackets = false
end
buffer [ # buffer + 1 ] = c
end
elseif state == 12 then
if c : match ( "^%d$" ) ~= nil then
buffer [ # buffer + 1 ] = c
elseif eof or c == "/" or c == "?" or c == "#" or ( special and c == "\\" ) then
local collected = table . concat ( buffer )
if collected ~= "" then
local port = tonumber ( collected )
if port > 65535 then
return nil , "invalid port number"
end
if DEFAULT_PORTS [ url . scheme ] == port then
url . port = nil
else
url . port = port
end
buffer = { }
end
state = 16
pointer = pointer - 1
else
return nil , "invalid port number"
end
elseif state == 13 then
url . scheme = "file"
special = true
url . host = ""
if c == "/" or c == "\\" then
state = 14
elseif baseUrl ~= nil and baseUrl . scheme == "file" then
url . host = baseUrl . host
url . path = copyPath ( baseUrl . path )
url . query = baseUrl . query
if c == "?" then
url . query = ""
state = 19
elseif c == "#" then
url . fragment = ""
state = 20
elseif not eof then
url . query = nil
if not startsWithDriveLetter ( input , pointer ) then
shorten ( url )
else
url . path = { }
end
state = 17
pointer = pointer - 1
end
else
state = 17
pointer = pointer - 1
end
elseif state == 14 then
if c == "/" or c == "\\" then
state = 15
else
if baseUrl ~= nil and baseUrl . scheme == "file" then
url . host = baseUrl . host
local first = type ( baseUrl . path ) == "table" and baseUrl . path [ 1 ] or nil
if not startsWithDriveLetter ( input , pointer )
and first ~= nil
and windowsDriveLetter ( first , true )
then
url . path [ # url . path + 1 ] = first
end
end
state = 17
pointer = pointer - 1
end
elseif state == 15 then
if eof or c == "/" or c == "\\" or c == "?" or c == "#" then
pointer = pointer - 1
local collected = table . concat ( buffer )
if windowsDriveLetter ( collected , false ) then


state = 17
elseif collected == "" then
url . host = ""
state = 16
else
local host , reason = parseHost ( collected , not special , trusted )
if host == nil then
return nil , reason
elseif host == "localhost" then
host = ""
end
url . host = host
buffer = { }
state = 16
end
else
buffer [ # buffer + 1 ] = c
end
elseif state == 16 then
if special then
state = 17
if c ~= "/" and c ~= "\\" then
pointer = pointer - 1
end
elseif c == "?" then
url . query = ""
state = 19
elseif c == "#" then
url . fragment = ""
state = 20
elseif not eof then
state = 17
if c ~= "/" then
pointer = pointer - 1
end
end
elseif state == 17 then
local slash = c == "/" or ( special and c == "\\" )
if eof or slash or c == "?" or c == "#" then
local segment = table . concat ( buffer )
if doubleDot ( segment ) then
shorten ( url )
if not slash then
url . path [ # url . path + 1 ] = ""
end
elseif singleDot ( segment ) then
if not slash then
url . path [ # url . path + 1 ] = ""
end
else
if url . scheme == "file" and # url . path == 0 and windowsDriveLetter ( segment , false ) then
segment = segment : sub ( 1 , 1 ) .. ":"
end
url . path [ # url . path + 1 ] = segment
end
buffer = { }
if c == "?" then
url . query = ""
state = 19
elseif c == "#" then
url . fragment = ""
state = 20
end
else
buffer [ # buffer + 1 ] = encodeByte ( c : byte ( ) , 4 )
end
elseif state == 18 then
if eof or c == "?" or c == "#" then
url . path = table . concat ( buffer )
buffer = { }
if c == "?" then
url . query = ""
state = 19
elseif c == "#" then
url . fragment = ""
state = 20
end
else
buffer [ # buffer + 1 ] = encodeByte ( c : byte ( ) , 0 )
end
elseif state == 19 then
if eof or c == "#" then
local collected = table . concat ( buffer )
url . query = url . query .. encodeText ( collected , special and 3 or 2 )
buffer = { }
if c == "#" then
url . fragment = ""
state = 20
end
else
buffer [ # buffer + 1 ] = c
end
elseif state == 20 then
if not eof then
buffer [ # buffer + 1 ] = encodeByte ( c : byte ( ) , 1 )
end
end

if pointer > length then
do break end
end
pointer = pointer + 1
end
if state == 20 then
url . fragment = url . fragment .. table . concat ( buffer )
end

return serialize ( url ) , nil
end

local __nuppExportValue= whatwg ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.io.uri.whatwg"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.uri.whatwg"]=__nuppExports;return __nuppExports