-- The same measurement under LuaJIT: token count, error count, checksum, and time.
if os.getenv("JIT_OFF") then require("jit").off() end
local bench = require("nupp.bench.lexbench")
local installed = pcall(bench.setup)
io.stderr:write(installed and "table arena provider\n" or "arena provider already selected by the toolchain (ffi)\n")
local f = assert(io.open(arg[1], "rb")); local source = f:read("*a"); f:close()
local tokens, errors, sum = bench.lex(source)
io.stderr:write(("lex\ttokens %d\terrors %d\tchecksum %d\n"):format(tokens, errors, sum))
local best = math.huge
for _ = 1, 7 do local t = os.clock(); bench.lex(source); local e = os.clock() - t; if e < best then best = e end end
print(("lexer\t%s\t%.2f ms per lex\t%.1f ns per byte\t(%d bytes, %d tokens)"):format(arg[2] or "luajit", best * 1e3, best / #source * 1e9, #source, tokens))
io.stdout:write(("%d,%d,%d\n"):format(tokens, errors, sum))
