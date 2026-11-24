-- The hot guest handlers' dispatch paths (run.lua's handler cases): the
-- shortest run of instructions from entry to the indirect branch that
-- dispatches the next instruction, and the memory operations on it.
-- `budget` is what s0 selects today and may not grow; lower it as the
-- backend improves. `clang` is the same handler written in C
-- (bench/codegen-oracle/handlers.c) at clang -O2: the target.
return {
    {name = "Move", budget = {29, 13}, clang = {22, 11}},
    {name = "Jmp", budget = {26, 8}, clang = {29, 17}},
    {name = "JmpIf", budget = {27, 11}, clang = {35, 19}},
    {name = "K", budget = {53, 20}, clang = {57, 26}},
    {name = "GetUpval", budget = {46, 17}, clang = {36, 15}},
    {name = "GetCell", budget = {56, 33}},
    {name = "Eq", budget = {71, 41}},
    {name = "GetIdx", budget = {145, 89}}
}
