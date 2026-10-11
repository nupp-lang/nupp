#!/bin/sh
# Five runs each of the prototype and the Lua bars; medians are computed by summarize.py.
set -e
cd "$(dirname "$0")"
BIN=${BIN:-../../build/rust/target/release/runtime-experiment}
mkdir -p evidence
: > evidence/runs.tsv
for i in 1 2 3 4 5; do
  for mode in fib trees churn map dot park; do "$BIN" "$mode" 2>/dev/null | sed "s/^/proto\t/" >> evidence/runs.tsv; done
  for f in fib trees churn; do
    lua lua/$f.lua | sed "s/^/lua54\t/" >> evidence/runs.tsv
    luajit -joff lua/$f.lua | sed "s/^/luajit-interp\t/" >> evidence/runs.tsv
    luajit lua/$f.lua | sed "s/^/luajit-jit\t/" >> evidence/runs.tsv
  done
done
python3 summarize.py
