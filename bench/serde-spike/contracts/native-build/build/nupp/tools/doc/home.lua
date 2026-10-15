_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()















local pageMod = require ( "nupp.tools.doc.page" )

local home = { }

local HERO_OPEN , HERO_CLOSE = "<!-- nupp:hero -->" , "<!-- /nupp:hero -->"
local FEATURES_OPEN , FEATURES_CLOSE = "<!-- nupp:features -->" , "<!-- /nupp:features -->"



















local function region ( markdown , open , close , replacement ) 
local from , opened = markdown : find ( open , 1 , true )
if not from or not opened then
return nil , markdown
end
local closed , to = markdown : find ( close , opened , true )
if not closed or not to then
return nil , markdown
end

return markdown : sub ( opened + 1 , closed - 1 ) , markdown : sub ( 1 , from - 1 ) .. replacement .. markdown : sub ( to + 1 )
end

local function paragraphs ( text ) 
local out = { }
for block in ( text .. "\n\n" ) : gmatch ( "(.-)\n%s*\n" ) do
local trimmed = block : match ( "^%s*(.-)%s*$" )
if trimmed ~= "" then
out [ # out + 1 ] = trimmed
end
end

return out
end




local function actions ( block ) 
local found = { }
local remainder = block
for text , path in block : gmatch ( "%[([^%]]*)%]%(([^%)]*)%)" ) do
local action = { path = path , text = text , theme = # found == 0 and "brand" or nil }
found [ # found + 1 ] = action
remainder = remainder : gsub ( "%[[^%]]*%]%([^%)]*%)" , "" , 1 )
end
if # found == 0 or remainder : match ( "%S" ) then
return nil
end

return found
end





function home . parse ( markdown ) 
local sections = { markdown = markdown }
local hero
hero , sections . markdown = region ( sections . markdown , "<!-- nupp:hero -->" , "<!-- /nupp:hero -->" , "" )
if hero then
local copy = { }
for _ , block in ipairs ( paragraphs ( hero ) ) do
local heading = block : match ( "^#%s+(.*)$" )
local alt , image = block : match ( "^!%[([^%]]*)%]%(([^%)]*)%)$" )
if heading then
sections . heroTitle = heading
elseif image then
sections . heroImage , sections . heroImageAlt = image , alt
else
local links = actions ( block )
if links then
sections . heroActions = links
else
copy [ # copy + 1 ] = ( block : gsub ( "%s*\n%s*" , " " ) )
end
end
end
sections . heroText = copy [ 1 ]
if # copy > 1 then
sections . heroContent = table . concat ( copy , " " , 2 )
end


sections . markdown = ( sections . markdown : gsub ( "^\n+" , "" ) )
end
local features
features , sections . markdown = region ( sections . markdown , "<!-- nupp:features -->" , "<!-- /nupp:features -->" , "<!-- nupp:features -->" )
if features then
sections . features = home . features ( features )
end

return sections
end






function home . features ( text ) 



text = text : gsub ( "\13\n" , "\n" ) : gsub ( "\13" , "\n" )
local found = { }


local fences = { }

local function hold ( fence ) 
fences [ # fences + 1 ] = fence

return "\n\0" .. # fences .. "\0\n"
end

local function release ( index ) 
return fences [ tonumber ( index ) ]
end

local stripped = "\n" .. ( text : gsub ( "\n```[^\n]*\n.-\n```" , hold ) )



local opens , titles = { } , { }
local position = 1
while true do
local from , to = stripped : find ( "\n##[ \9]+" , position )
if not from or not to then
do break end
end
opens [ # opens + 1 ] = from
titles [ # titles + 1 ] = to + 1
position = to + 1
end
for index , start in ipairs ( titles ) do
local block = stripped : sub ( start , ( opens [ index + 1 ] or # stripped + 1 ) - 1 )
local title , body = block : match ( "^([^\n]*)\n?(.*)$" )
local restored = ( body : gsub ( "%z(%d+)%z" , release ) )
local language , code = restored : match ( "\n?```([^\n]*)\n(.-)\n```" )
local details = { }
for _ , paragraph in ipairs ( paragraphs ( ( restored : gsub ( "\n?```[^\n]*\n.-\n```" , "" ) ) ) ) do
local alt , image = paragraph : match ( "^!%[([^%]]*)%]%(([^%)]*)%)$" )
if image then
local illustrated = { title = title , image = image , imageAlt = alt }
found [ # found + 1 ] = illustrated
else
details [ # details + 1 ] = paragraph
end
end
local card = found [ # found ]
if not card or card . title ~= title then
local plain = { title = title }
card , found [ # found + 1 ] = plain , plain
end
card . details = # details > 0 and table . concat ( details , "\n\n" ) or nil
if code and not card . image then
card . code , card . codeLanguage = code , language ~= "" and language or nil
end
end

return found
end



function home . decorated ( markdown ) 
return markdown : find ( "<!-- nupp:hero -->" , 1 , true ) ~= nil or markdown : find ( "<!-- nupp:features -->" , 1 , true ) ~= nil
end

home . FEATURES = "<!-- nupp:features -->"

local __nuppExportValue= home ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc.home"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc.home"]=__nuppExports;return __nuppExports