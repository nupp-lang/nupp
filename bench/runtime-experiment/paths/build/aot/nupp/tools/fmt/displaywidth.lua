_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.tools.fmt.displaywidth"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local clip;__nuppExports["clip"]=function(...) return clip(...) end;local displayWidth;__nuppExports["displayWidth"]=function(...) return displayWidth(...) end;












local ZERO_WIDTH = {
{ 768 , 879 } ,
{ 1155 , 1161 } ,
{ 1425 , 1469 } ,
{ 1471 , 1471 } ,
{ 1473 , 1474 } ,
{ 1476 , 1477 } ,
{ 1479 , 1479 } ,
{ 1536 , 1541 } ,
{ 1552 , 1562 } ,
{ 1564 , 1564 } ,
{ 1611 , 1631 } ,
{ 1648 , 1648 } ,
{ 1750 , 1757 } ,
{ 1759 , 1764 } ,
{ 1767 , 1768 } ,
{ 1770 , 1773 } ,
{ 1807 , 1807 } ,
{ 1809 , 1809 } ,
{ 1840 , 1866 } ,
{ 1958 , 1968 } ,
{ 2027 , 2035 } ,
{ 2045 , 2045 } ,
{ 2070 , 2073 } ,
{ 2075 , 2083 } ,
{ 2085 , 2087 } ,
{ 2089 , 2093 } ,
{ 2137 , 2139 } ,
{ 2192 , 2193 } ,
{ 2200 , 2306 } ,
{ 2362 , 2364 } ,
{ 2369 , 2376 } ,
{ 2381 , 2381 } ,
{ 2385 , 2391 } ,
{ 2402 , 2403 } ,
{ 2433 , 2433 } ,
{ 2492 , 2492 } ,
{ 2497 , 2500 } ,
{ 2509 , 2509 } ,
{ 2530 , 2531 } ,
{ 2561 , 2562 } ,
{ 2620 , 2620 } ,
{ 2625 , 2626 } ,
{ 2631 , 2632 } ,
{ 2635 , 2637 } ,
{ 2641 , 2641 } ,
{ 2672 , 2673 } ,
{ 2677 , 2677 } ,
{ 2689 , 2690 } ,
{ 2748 , 2748 } ,
{ 2753 , 2757 } ,
{ 2759 , 2760 } ,
{ 2765 , 2765 } ,
{ 2786 , 2787 } ,
{ 2817 , 2817 } ,
{ 2876 , 2876 } ,
{ 2879 , 2879 } ,
{ 2881 , 2884 } ,
{ 2893 , 2893 } ,
{ 2901 , 2902 } ,
{ 2914 , 2915 } ,
{ 2946 , 2946 } ,
{ 3008 , 3008 } ,
{ 3021 , 3021 } ,
{ 3072 , 3072 } ,
{ 3076 , 3076 } ,
{ 3132 , 3132 } ,
{ 3134 , 3136 } ,
{ 3142 , 3144 } ,
{ 3146 , 3149 } ,
{ 3157 , 3158 } ,
{ 3170 , 3171 } ,
{ 3201 , 3201 } ,
{ 3260 , 3260 } ,
{ 3263 , 3263 } ,
{ 3270 , 3270 } ,
{ 3276 , 3277 } ,
{ 3298 , 3299 } ,
{ 3328 , 3329 } ,
{ 3387 , 3388 } ,
{ 3393 , 3396 } ,
{ 3405 , 3405 } ,
{ 3426 , 3427 } ,
{ 3457 , 3457 } ,
{ 3530 , 3530 } ,
{ 3538 , 3540 } ,
{ 3542 , 3542 } ,
{ 3633 , 3633 } ,
{ 3636 , 3642 } ,
{ 3655 , 3662 } ,
{ 3761 , 3761 } ,
{ 3764 , 3772 } ,
{ 3784 , 3790 } ,
{ 3864 , 3865 } ,
{ 3893 , 3893 } ,
{ 3895 , 3895 } ,
{ 3897 , 3897 } ,
{ 3953 , 3966 } ,
{ 3968 , 3972 } ,
{ 3974 , 3975 } ,
{ 3981 , 3991 } ,
{ 3993 , 4028 } ,
{ 4038 , 4038 } ,
{ 4141 , 4144 } ,
{ 4146 , 4151 } ,
{ 4153 , 4154 } ,
{ 4157 , 4158 } ,
{ 4184 , 4185 } ,
{ 4190 , 4192 } ,
{ 4209 , 4212 } ,
{ 4226 , 4226 } ,
{ 4229 , 4230 } ,
{ 4237 , 4237 } ,
{ 4253 , 4253 } ,
{ 4957 , 4959 } ,
{ 5906 , 5908 } ,
{ 5938 , 5939 } ,
{ 5970 , 5971 } ,
{ 6002 , 6003 } ,
{ 6068 , 6069 } ,
{ 6071 , 6077 } ,
{ 6086 , 6086 } ,
{ 6089 , 6099 } ,
{ 6109 , 6109 } ,
{ 6155 , 6159 } ,
{ 6277 , 6278 } ,
{ 6313 , 6313 } ,
{ 6432 , 6434 } ,
{ 6439 , 6440 } ,
{ 6450 , 6450 } ,
{ 6457 , 6459 } ,
{ 6679 , 6680 } ,
{ 6683 , 6683 } ,
{ 6742 , 6742 } ,
{ 6744 , 6750 } ,
{ 6752 , 6752 } ,
{ 6754 , 6754 } ,
{ 6757 , 6764 } ,
{ 6771 , 6780 } ,
{ 6783 , 6783 } ,
{ 6832 , 6862 } ,
{ 6912 , 6915 } ,
{ 6964 , 6964 } ,
{ 6966 , 6970 } ,
{ 6972 , 6972 } ,
{ 6978 , 6978 } ,
{ 7019 , 7027 } ,
{ 7040 , 7041 } ,
{ 7074 , 7077 } ,
{ 7080 , 7081 } ,
{ 7083 , 7085 } ,
{ 7142 , 7142 } ,
{ 7144 , 7145 } ,
{ 7149 , 7149 } ,
{ 7151 , 7153 } ,
{ 7212 , 7219 } ,
{ 7222 , 7223 } ,
{ 7376 , 7378 } ,
{ 7380 , 7392 } ,
{ 7394 , 7400 } ,
{ 7405 , 7405 } ,
{ 7412 , 7412 } ,
{ 7416 , 7417 } ,
{ 7616 , 7679 } ,
{ 8203 , 8207 } ,
{ 8234 , 8238 } ,
{ 8288 , 8292 } ,
{ 8294 , 8303 } ,
{ 8400 , 8432 } ,
{ 11503 , 11505 } ,
{ 11647 , 11647 } ,
{ 11744 , 11775 } ,
{ 12330 , 12335 } ,
{ 12441 , 12442 } ,
{ 42607 , 42610 } ,
{ 42612 , 42621 } ,
{ 42654 , 42655 } ,
{ 42736 , 42737 } ,
{ 43010 , 43010 } ,
{ 43014 , 43014 } ,
{ 43019 , 43019 } ,
{ 43045 , 43046 } ,
{ 43052 , 43052 } ,
{ 43204 , 43205 } ,
{ 43232 , 43249 } ,
{ 43263 , 43263 } ,
{ 43302 , 43309 } ,
{ 43335 , 43345 } ,
{ 43392 , 43394 } ,
{ 43443 , 43443 } ,
{ 43446 , 43449 } ,
{ 43452 , 43453 } ,
{ 43493 , 43493 } ,
{ 43561 , 43566 } ,
{ 43569 , 43570 } ,
{ 43573 , 43574 } ,
{ 43587 , 43587 } ,
{ 43596 , 43596 } ,
{ 43644 , 43644 } ,
{ 43696 , 43696 } ,
{ 43698 , 43700 } ,
{ 43703 , 43704 } ,
{ 43710 , 43711 } ,
{ 43713 , 43713 } ,
{ 43756 , 43757 } ,
{ 43766 , 43766 } ,
{ 44005 , 44005 } ,
{ 44008 , 44008 } ,
{ 44013 , 44013 } ,
{ 64286 , 64286 } ,
{ 65024 , 65039 } ,
{ 65056 , 65071 } ,
{ 65279 , 65279 } ,
{ 66045 , 66045 } ,
{ 66272 , 66272 } ,
{ 66422 , 66426 } ,
{ 68097 , 68099 } ,
{ 68101 , 68102 } ,
{ 68108 , 68111 } ,
{ 68152 , 68154 } ,
{ 68159 , 68159 } ,
{ 68325 , 68326 } ,
{ 68900 , 68903 } ,
{ 69291 , 69292 } ,
{ 69446 , 69456 } ,
{ 69633 , 69633 } ,
{ 69688 , 69702 } ,
{ 69744 , 69744 } ,
{ 69747 , 69748 } ,
{ 69759 , 69761 } ,
{ 69811 , 69814 } ,
{ 69817 , 69818 } ,
{ 69826 , 69826 } ,
{ 69888 , 69890 } ,
{ 69927 , 69931 } ,
{ 69933 , 69940 } ,
{ 70003 , 70003 } ,
{ 70016 , 70017 } ,
{ 70070 , 70078 } ,
{ 70089 , 70092 } ,
{ 70095 , 70095 } ,
{ 70191 , 70193 } ,
{ 70196 , 70196 } ,
{ 70198 , 70199 } ,
{ 70206 , 70206 } ,
{ 70209 , 70209 } ,
{ 70367 , 70367 } ,
{ 70371 , 70378 } ,
{ 70400 , 70401 } ,
{ 70459 , 70460 } ,
{ 70464 , 70464 } ,
{ 70502 , 70508 } ,
{ 70512 , 70516 } ,
{ 70712 , 70719 } ,
{ 70722 , 70724 } ,
{ 70726 , 70726 } ,
{ 70750 , 70750 } ,
{ 70835 , 70840 } ,
{ 70842 , 70842 } ,
{ 70847 , 70848 } ,
{ 70850 , 70851 } ,
{ 71090 , 71093 } ,
{ 71100 , 71101 } ,
{ 71103 , 71104 } ,
{ 71132 , 71133 } ,
{ 71219 , 71226 } ,
{ 71229 , 71229 } ,
{ 71231 , 71232 } ,
{ 71339 , 71339 } ,
{ 71341 , 71341 } ,
{ 71344 , 71349 } ,
{ 71351 , 71351 } ,
{ 71453 , 71455 } ,
{ 71458 , 71461 } ,
{ 71463 , 71467 } ,
{ 71727 , 71735 } ,
{ 71737 , 71738 } ,
{ 71995 , 71996 } ,
{ 71998 , 71998 } ,
{ 72003 , 72003 } ,
{ 72148 , 72151 } ,
{ 72154 , 72155 } ,
{ 72160 , 72160 } ,
{ 72193 , 72202 } ,
{ 72243 , 72248 } ,
{ 72251 , 72254 } ,
{ 72263 , 72263 } ,
{ 72273 , 72278 } ,
{ 72281 , 72283 } ,
{ 72330 , 72342 } ,
{ 72344 , 72345 } ,
{ 72752 , 72758 } ,
{ 72760 , 72765 } ,
{ 72767 , 72767 } ,
{ 72850 , 72871 } ,
{ 72874 , 72880 } ,
{ 72882 , 72883 } ,
{ 72885 , 72886 } ,
{ 73009 , 73014 } ,
{ 73018 , 73018 } ,
{ 73020 , 73021 } ,
{ 73023 , 73029 } ,
{ 73031 , 73031 } ,
{ 73104 , 73105 } ,
{ 73109 , 73109 } ,
{ 73111 , 73111 } ,
{ 73459 , 73460 } ,
{ 78896 , 78904 } ,
{ 92912 , 92916 } ,
{ 92976 , 92982 } ,
{ 94031 , 94031 } ,
{ 94095 , 94098 } ,
{ 94180 , 94180 } ,
{ 113821 , 113822 } ,
{ 113824 , 113827 } ,
{ 118528 , 118573 } ,
{ 118576 , 118598 } ,
{ 119143 , 119145 } ,
{ 119155 , 119170 } ,
{ 119173 , 119179 } ,
{ 119210 , 119213 } ,
{ 119362 , 119364 } ,
{ 121344 , 121398 } ,
{ 121403 , 121452 } ,
{ 121461 , 121461 } ,
{ 121476 , 121476 } ,
{ 121499 , 121503 } ,
{ 121505 , 121519 } ,
{ 122880 , 122886 } ,
{ 122888 , 122904 } ,
{ 122907 , 122913 } ,
{ 122915 , 122916 } ,
{ 122918 , 122922 } ,
{ 123023 , 123023 } ,
{ 123184 , 123190 } ,
{ 123566 , 123566 } ,
{ 123628 , 123631 } ,
{ 124140 , 124143 } ,
{ 125136 , 125142 } ,
{ 125252 , 125258 } ,
{ 127995 , 127999 } ,
{ 917505 , 917505 } ,
{ 917536 , 917631 } ,
{ 917760 , 917999 } ,
}

local function inRanges ( cp , ranges ) 
local low , high = 1 , # ranges
while low <= high do
local mid = math . floor ( ( low + high ) / 2 )
local range = ranges [ mid ]
if cp < range [ 1 ] then
high = mid - 1
elseif cp > range [ 2 ] then
low = mid + 1
else
return true
end
end

return false
end

local function nextCodepoint ( text , pos ) 
local b1 = text : byte ( pos )
if not b1 or b1 < 128 then
return b1 , pos + 1
end
local count , cp
if b1 >= 194 and b1 <= 223 then
count , cp = 2 , b1 - 192
elseif b1 >= 224 and b1 <= 239 then
count , cp = 3 , b1 - 224
elseif b1 >= 240 and b1 <= 244 then
count , cp = 4 , b1 - 240
else
return b1 , pos + 1
end
for j = 2 , count do
local byte = text : byte ( pos + j - 1 )
if not byte or byte < 128 or byte > 191 then
return b1 , pos + 1
end
cp = cp * 64 + byte - 128
end
if ( count == 3 and cp < 2048 )
or ( count == 4 and cp < 65536 )
or cp > 1114111
or ( cp >= 55296 and cp <= 57343 )
then
return b1 , pos + 1
end

return cp , pos + count
end

local function codepointWidth ( cp ) 
if cp == 0 or cp < 32 or ( cp >= 127 and cp < 160 ) or inRanges ( cp , ZERO_WIDTH ) then
return 0
end
if ( cp >= 4352 and cp <= 4447 )
or cp == 8986
or cp == 8987
or cp == 9001
or cp == 9002
or ( cp >= 9193 and cp <= 9196 )
or cp == 9200
or cp == 9203
or ( cp >= 9725 and cp <= 9726 )
or ( cp >= 9748 and cp <= 9749 )
or ( cp >= 9800 and cp <= 9811 )
or cp == 9855
or cp == 9875
or cp == 9889
or ( cp >= 9898 and cp <= 9899 )
or ( cp >= 9917 and cp <= 9918 )
or cp == 9924
or cp == 9925
or cp == 9934
or cp == 9940
or cp == 9962
or cp == 9970
or cp == 9971
or cp == 9973
or cp == 9978
or cp == 9981
or cp == 9989
or cp == 9994
or cp == 9995
or cp == 10024
or cp == 10060
or cp == 10062
or ( cp >= 10067 and cp <= 10069 )
or cp == 10071
or ( cp >= 10133 and cp <= 10135 )
or cp == 10160
or cp == 10175
or ( cp >= 11035 and cp <= 11036 )
or cp == 11088
or cp == 11093
or ( cp >= 11904 and cp <= 42191 and cp ~= 12351 )
or ( cp >= 44032 and cp <= 55203 )
or ( cp >= 63744 and cp <= 64255 )
or ( cp >= 65040 and cp <= 65049 )
or ( cp >= 65072 and cp <= 65135 )
or ( cp >= 65280 and cp <= 65376 )
or ( cp >= 65504 and cp <= 65510 )
or cp == 126980
or cp == 127183
or cp == 127374
or ( cp >= 127377 and cp <= 127386 )
or ( cp >= 127488 and cp <= 127490 )
or ( cp >= 127504 and cp <= 127547 )
or ( cp >= 127552 and cp <= 127560 )
or ( cp >= 127568 and cp <= 127569 )
or ( cp >= 127744 and cp <= 128591 )
or ( cp >= 128640 and cp <= 128767 )
or ( cp >= 129280 and cp <= 129535 )
or ( cp >= 129648 and cp <= 129791 )
or ( cp >= 131072 and cp <= 262141 )
then
return 2
end

return 1
end

displayWidth=function ( text ) 
local width , pos = 0 , 1
local wideBase , joined = false , false
while pos <= # text do
local cp , nextPos = nextCodepoint ( text , pos )
local advance = codepointWidth ( cp )
local rawWidth = advance
if joined and wideBase and advance == 2 then
advance = 0
end
if cp == 0x200d then
joined = wideBase
elseif rawWidth > 0 then
joined = false
wideBase = rawWidth == 2
end
width = width + advance
pos = nextPos
end

return width
end ;__nuppExports["displayWidth"]=displayWidth














clip=function ( text , columns ) 
if columns <= 0 then
return ""
end
local width , pos = 0 , 1
local safeEnd = 0
local wideBase , joined = false , false
local pendingJoiner = false
while pos <= # text do
local cp , nextPos = nextCodepoint ( text , pos )
local advance = codepointWidth ( cp )
local rawWidth = advance
if joined and wideBase and advance == 2 then
advance = 0
end
if width + advance > columns then
return text : sub ( 1 , safeEnd )
end
if cp == 0x200d then
joined = wideBase
pendingJoiner = true
elseif rawWidth > 0 then
joined = false
wideBase = rawWidth == 2
pendingJoiner = false
safeEnd = nextPos - 1
elseif not pendingJoiner then
safeEnd = nextPos - 1
end
width = width + advance
pos = nextPos
end

return text : sub ( 1 , safeEnd )
end ;__nuppExports["clip"]=clip
local __nuppWorkerSendables=_G.rawget(_G.nupp,"__workerSendables");if _G.type(__nuppWorkerSendables)~="table" then __nuppWorkerSendables=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerSendables",__nuppWorkerSendables) end;__nuppWorkerSendables[__nuppExports["displayWidth"]]={module="nupp.tools.fmt.displaywidth",member="displayWidth",captures={values={},count=0},input="string",output="number"}; end);if not __nuppOk then package.loaded["nupp.tools.fmt.displaywidth"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.fmt.displaywidth"]=__nuppExports;return __nuppExports