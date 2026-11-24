-- The hot guest handlers' dispatch paths (run.lua's handler cases): the
-- shortest run of instructions from entry to the indirect branch that
-- dispatches the next instruction, and the memory operations on it.
-- `budget` is what s0 selects today and may not grow; lower it as the
-- backend improves. `clang` is the same handler written in C
-- (bench/codegen-oracle/handlers.c) at clang -O2: the target.
return {
    {name = "Move", budget = {23, 12}, clang = {22, 11}},
    {name = "Jmp", budget = {22, 8}, clang = {29, 17}},
    {name = "JmpIf", budget = {23, 10}, clang = {35, 19}},
    {name = "K", budget = {43, 18}, clang = {57, 26}},
    {name = "GetUpval", budget = {37, 16}, clang = {36, 15}},
    {name = "GetCell", budget = {34, 15}},
    {name = "Eq", budget = {54, 28}},
    {name = "GetIdx", budget = {87, 36}},
    {name = "CallK", budget = {107, 56}},
    {name = "Ret", budget = {58, 31}}
}
