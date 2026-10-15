-- Differential checks for the VM's native LPeg: run under LuaJIT with the
-- reference C module and under the VM, and compare the printed lines.
--
--   luajit tests/lpeg-differential.lua > ref.txt
--   ./bin/nupp run tests/lpeg-differential.lua > vm.txt   (on the VM CLI)
--
-- Error messages are compared without the position prefix LuaJIT adds to
-- some of them, and with the function name in "bad argument" removed.

local m = require("lpeg")
local re = require("re")

local function ser(v, seen)
    local t = type(v)
    if t == "string" then
        return '"' .. v:gsub('[%c"\\\128-\255]', function(c)
            return string.format("\\%03d", c:byte())
        end) .. '"'
    end
    if t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then
            return string.format("%d", v)
        end
        return string.format("%.14g", v)
    end
    if t == "table" then
        seen = seen or {}
        if seen[v] then
            return "<cycle>"
        end
        seen[v] = true
        local keys = {}
        for k in pairs(v) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then
                return ta < tb
            end

            return a < b
        end)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = "[" .. ser(k, seen) .. "]=" .. ser(v[k], seen)
        end
        seen[v] = nil
        return "{" .. table.concat(parts, ",") .. "}"
    end
    if t == "userdata" and m.type(v) == "pattern" then
        return "<pattern>"
    end
    if t == "function" then
        return "<function>"
    end

    return tostring(v)
end

local function norm(e)
    e = tostring(e)
    e = e:gsub("^[^\n]-:%d+: ", "")
    e = e:gsub("to '[^']*'", "to '?'")
    return e
end

local count = 0

local function show(label, ...)
    count = count + 1
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        parts[i] = ser((select(i, ...)))
    end
    print(label .. ": " .. table.concat(parts, " "))
end

local function try(label, f, ...)
    local r = {pcall(f, ...)}
    if r[1] then
        show(label, unpack(r, 2, table.maxn(r)))
    else
        count = count + 1;
        print(label .. ": error " .. norm(r[2]))
    end
end

local function mt(label, p, s, ...)
    try(label, m.match, p, s, ...)
end

-- basic patterns
local P, S, R, C, V = m.P, m.S, m.R, m.C, m.V
mt("literal", P"abc", "abcdef")
mt("literal fail", P"abd", "abcdef")
mt("empty", P"", "x")
mt("any n", P(3), "abcd")
mt("any n fail", P(5), "abcd")
mt("not any", P(-3), "ab")
mt("not any fail", P(-2), "ab")
mt("true", P(true), "")
mt("false", P(false), "")
mt("set", S"xyz" ^ 1, "zyxa")
mt("range", R("az", "09") ^ 1, "ab12-")
mt("range empty", R(), "a")
mt("choice", P"a" + "b" + "c", "c")
mt("seq", P"a" * "b" * "c", "abc")
mt("diff", (R"az" - S"aeiou") ^ 1, "bcdea")
mt("diff pattern", (1 - P"end") ^ 0 * "end", "the end")
mt("and", #P"a" * "ab", "ab")
mt("not", -P"a" * 1, "b")
mt("rep min", P"a" ^ 2, "aaab")
mt("rep min fail", P"a" ^ 4, "aaab")
mt("rep max", P"a" ^ -2, "aaab")
mt("rep max zero", (P"a" * "b") ^ -1, "ac")
mt("behind", P"b" * m.B"b", "bc")
mt("behind fail", 1 * m.B"x", "a")
mt("behind set", P(2) * m.B(S"ab" * 1), "abc")
mt("init", P"b", "abc", 2)
mt("init neg", C(P(1) ^ 0), "abcdef", -2)
mt("init big", P(0), "abc", 10)
mt("init neg big", C(P(1) ^ 0), "abc", -10)
mt("utf", m.utfR(0x100, 0x10ffff) ^ 1, "\xc4\x80\xf0\x9f\x98\x80x")
mt("utf ascii", m.utfR(97, 122) ^ 1, "abc1")
mt("utf bad", m.utfR(0x80, 0x7ff), "\xc0\x80")
mt("utf mixed", C(m.utfR(0, 0x7f) + m.utfR(0x80, 0x7ff)) ^ 0, "a\xc3\xa9b")

-- captures
mt("C", C(P"a" ^ 1) * C(P"b" ^ 1), "aabbc")
mt("C nested", C(C"a" * C"b"), "ab")
mt("Cc", m.Cc(1, "x", true), "")
mt("Cc nil", m.Cc(nil), "")
mt("Cc none", m.Cc(), "ab")
mt("Cp", m.Cp() * "ab" * m.Cp(), "abc")
mt("Ct", m.Ct(C(1) ^ 0), "abc")
mt("Ct named", m.Ct(m.Cg(C(1), "x") * m.Cg(C(1) * C(1), "y") * C(1)), "abcde")
mt("Cg anon", m.Cg(C"a" * C"b"), "ab")
mt("Cg named outside", m.Cg(C"a", "n") * C"b", "ab")
mt("Cb", m.Cg(C(1), "x") * m.Cb"x" * m.Cb"x", "q")
mt("Cb missing", m.Cb"nope", "q")
mt("Cs", m.Cs((P"a" / "A" + 1) ^ 0), "banana")
mt("Cs nested", m.Cs((m.Cs(P"ab" / "x") + 1) ^ 0), "abcab")
mt("Cs keep", m.Cs((C"a" / {} + 1) ^ 0), "aba")
mt(
    "Cf",
    m.Cf(C(R"09") * (C(R"09")) ^ 0, function(a, b)
        return a .. "+" .. b
    end),
    "1234"
)
mt("Cf empty", m.Cf(P"x", print), "x")
mt(
    "acc",
    m.Ct(
        (C(1) % function(t, c)
            t[#t + 1] = c:upper();
            return t
        end) ^ 0
    ),
    "abc"
)
mt("div string", C(R"az" ^ 1) / "<%1>", "hello")
mt("div string %0", (P"a" * C"b") / "%0-%1", "ab")
mt("div string pct", P"a" / "100%%", "a")
mt("div string bad", P"a" / "%2", "a")
mt("div number", (C"a" * C"b" * C"c") / 2, "abc")
mt("div number 0", (C"a" * C"b") / 0, "ab")
mt("div number bad", C"a" / 3, "a")
mt("div table", C(R"az" ^ 1) / {hello = "HI"}, "hello")
mt("div table miss", C(R"az" ^ 1) / {}, "hello")
mt("div function", C(R"az" ^ 1) / string.upper, "hello")
mt(
    "div function many",
    (C"a" * C"b") / function(a, b)
        return b, a, 3
    end,
    "ab"
)
mt(
    "div function none",
    C"a" / function()
    end,
    "a"
)
mt("Carg", m.Carg(1) * m.Carg(2), "", 1, "x", "y")
mt("Carg missing", m.Carg(2), "", 1, "x")
mt(
    "Cmt pos",
    m.Cmt(P"ab", function(s, i)
        return i + 1
    end),
    "abcd"
)
mt(
    "Cmt values",
    m.Cmt(C(P"x" ^ 1), function(s, i, c)
        return i, #c, c:upper()
    end),
    "xxxy"
)
mt(
    "Cmt false",
    m.Cmt(P"a", function()
        return false
    end) + C(1),
    "ab"
)
mt(
    "Cmt true",
    m.Cmt(P"a", function()
        return true, "v"
    end) * C(1),
    "ab"
)
mt(
    "Cmt bad pos",
    m.Cmt(P"a", function()
        return 10
    end),
    "ab"
)
mt(
    "Cmt nested",
    m.Cmt(
        m.Cmt(C"a", function(s, i, x)
            return i, x .. "!"
        end) * C"b",
        function(s, i, a, b)
            return i, a .. b
        end
    ),
    "ab"
)
mt(
    "Cmt backtrack",
    (m.Cmt(C(1), function(s, i, c)
        return c == "b" and i, c
    end) + 1) ^ 0 * m.Cp(),
    "abcb"
)
mt(
    "Cmt in predicate",
    #m.Cmt(P"a", function()
        return true, 1
    end) * m.Cmt(P"a", function()
        return true, 2
    end),
    "a"
)
try("fn pattern loop", function()
    return P(function()
    end) ^ 0
end)
mt(
    "fn pattern",
    (P(function(s, i)
        if i <= 3 then
            return i + 1, i
        end
    end) * 1) ^ 0,
    "abcdef"
)
mt("deep subst", m.Cs((m.Cs(C"a" / "x" * (C"b" / "y")) + 1) ^ 0), "abab")
mt("simple many", C(C(1) * C(1) * C(1) * C(1)), "abcd")

-- grammars
local arith = P{
    "Exp",
    Exp = m.Cf(V"Term" * m.Cg(C(S"+-") * V"Term") ^ 0, function(a, op, b)
        if op == "+" then
            return a + b
        else
            return a - b
        end
    end),
    Term = m.Cf(V"Fact" * m.Cg(C(S"*/") * V"Fact") ^ 0, function(a, op, b)
        if op == "*" then
            return a * b
        else
            return a / b
        end
    end),
    Fact = (R"09" ^ 1 / tonumber) + "(" * V"Exp" * ")",
}
mt("arith", arith, "2*(3+4)-5")
mt("arith2", arith, "10/4+1")
local balanced = P{"(" * ((1 - S"()") + V(1)) ^ 0 * ")"}
mt("balanced", balanced, "(a(b)(c(d)))x")
mt("balanced fail", balanced, "(a(b)")
local nums = {[1] = "list", list = m.Ct(V"num" * ("," * V"num") ^ 0), num = R"09" ^ 1 / tonumber}
mt("grammar named start", P(nums), "1,22,333")
local even = P{"S", S = "0" * V"O" + "1" * V"S" + -1, O = "0" * V"S" + "1" * V"O"}
mt("even zeros", even, "1001")
mt("even zeros fail", even, "1000")
try("left recursion", P, {V"a", a = V"a" * "x"})
try("left recursion indirect", P, {V"a", a = V"b" * "x", b = P"y" ^ -1 * V"a"})
try("undefined rule", P, {V"b"})
try("outside grammar", m.match, V"x", "a")
try("not a pattern", P, {V"a", a = "b"})
try("no initial", P, {})
try("initial not pattern", P, {"x"})
try("empty loop", function()
    return P{V"a", a = (P"x" * V"b") ^ 0, b = P"y" ^ -1}
end)
try("loop body", function()
    return P(true) ^ 0
end)
try("behind var", m.B, P"a" ^ 1)
try("behind cap", m.B, C"a")
mt("unused rule", P{"a", a = P"x", b = V"c" * 1, c = P"y"}, "x")
local nested = P{"a", a = P{"b", b = C"q"} * V"c", c = C"r"}
mt("nested grammar", nested, "qr")

-- errors
try("P nil", P, nil)
try("mul nil", function()
    return P(1) * nil
end)
try("pow string", function()
    return P(1) ^ "x"
end)
try("R bad", R, "abc")
try("div nil", function()
    return P(1) / nil
end)
try("div bool", function()
    return P(1) / true
end)
try("Cf bad", m.Cf, P(1), 3)
try("Carg 0", m.Carg, 0)
try("acc ctx", m.match, m.Cs(P"a" % print), "a")
try("acc first", m.match, P"a" % print, "a")
try("fold none", m.match, m.Cf(P"a", print), "a")
try("utfR empty", m.utfR, 10, 1)
try("setmaxstack", m.setmaxstack, 0)
try("subject missing", m.match, P(1))
try(
    "replacement table",
    m.match,
    m.Cs(P"a" / function()
        return {}
    end),
    "a"
)
try("V nil", V, nil)

-- stack limits
local deep = P{"0" * V(1) + "0"}
try("stack overflow", m.match, deep, string.rep("0", 1000))
m.setmaxstack(2004)
try("stack raised", m.match, deep, string.rep("0", 1000))
m.setmaxstack(400)
local rep = P{("a" * V(1)) ^ 0 * "b" + "c"}
mt("call stack", rep, string.rep("a", 150) .. "c" .. string.rep("b", 150))
mt("long repetition", (P"ab" + P"a") ^ 0, string.rep("ab", 50000))
mt("long choice backtrack", (P"x" ^ 0 * "y" + "x") ^ 0, string.rep("x", 20000))

-- methods and operators
show("type", m.type(P"a"), m.type("a"), m.type({}), type(P"a"))
show("version", m.version)
mt("method", P"a" * P"b", "ab")
show("method call", (P"a" ^ 1):match("aaa"))
show("len", #P"a" ~= nil)
local loc = m.locale()
local cats = {}
for _, k in ipairs{
    "alnum",
    "alpha",
    "cntrl",
    "digit",
    "graph",
    "lower",
    "print",
    "punct",
    "space",
    "upper",
    "xdigit"
} do
    cats[#cats + 1] = k .. "=" .. m.match(m.Cs((loc[k] + P(1) / "") ^ 0), " aZ9!\t~\127\0\200")
end
show("locale", table.concat(cats, ";"))

-- re
local function rt(label, ...)
    try(label, ...)
end

rt("re.match", re.match, "hello world", "{%a+} ' ' {%a+}")
rt("re.find", re.find, "the number 423 is odd", "[0-9]+")
rt("re.find init", re.find, "a1b22c333", "[0-9]+", 4)
rt("re.find none", re.find, "abc", "[0-9]+")
rt("re.gsub", re.gsub, "hello world", "[aeiou]", "<%0>")
rt("re.gsub fn", re.gsub, "a1b2", "%d", function(d)
    return d .. d
end)
rt("re.compile", function()
    return re.compile("{| {%d+} (',' {%d+})* |}"):match("1,2,3")
end)
rt("re grammar", function()
    local p = re.compile([[
        S <- (number (%s+ number)*) ~> add
        number <- %d+ -> tonumber
    ]], {
        tonumber = tonumber,
        add = function(a, b)
            return a + b
        end
    })

    return p:match("10 20 30 40")
end)
rt("re named", function()
    return re.match("key=value", "{:k: [a-z]+ :} '=' {:v: [a-z]+ :} -> {}")
end)
rt("re backref", function()
    return re.match("abcabc", "{:x: ... :} =x")
end)
rt("re string cap", function()
    return re.match("01234567890123456789", "({....}{...}) -> '%2%1'")
end)
rt("re predicates", function()
    return {re.match("abceefe", "( ( & 'e' {} ) ? . ) * ")}
end)
rt("re classes", function()
    return re.match("Hello, World!", "{| ({%w+} / .)* |}")
end)
rt("re error", re.compile, "x <- ")
rt("re undefined", re.compile, "a <- b")
rt("re updatelocale", function()
    re.updatelocale();
    return re.match("ab12", "%a+")
end)

-- randomized patterns over a small alphabet
local seed = 12345

local function rnd(n)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed % n
end

local function gen(depth)
    local k = rnd(depth > 3 and 4 or 20)
    if k == 0 then
        return P(({"a", "b", "ab", "ba", ""})[rnd(5) + 1])
    end
    if k == 1 then
        return S(({"a", "b", "ab"})[rnd(3) + 1])
    end
    if k == 2 then
        return P(rnd(3))
    end
    if k == 3 then
        return C(P(1))
    end
    if k == 4 then
        return gen(depth + 1) * gen(depth + 1)
    end
    if k == 5 then
        return gen(depth + 1) + gen(depth + 1)
    end
    if k == 6 then
        local ok, p = pcall(function()
            return gen(depth + 1) ^ (rnd(3) - 1)
        end)
        return ok and p or P"a"
    end
    if k == 7 then
        return -gen(depth + 1)
    end
    if k == 8 then
        return #gen(depth + 1)
    end
    if k == 9 then
        return C(gen(depth + 1))
    end
    if k == 10 then
        return m.Ct(gen(depth + 1))
    end
    if k == 11 then
        return gen(depth + 1) - gen(depth + 1)
    end
    if k == 12 then
        return m.Cs(gen(depth + 1))
    end
    if k == 13 then
        return gen(depth + 1) / "<%0>"
    end
    if k == 14 then
        return C(gen(depth + 1)) / {a = "A", ab = 1}
    end
    if k == 15 then
        return m.Cp() * gen(depth + 1)
    end
    if k == 16 then
        return m.Cg(gen(depth + 1), "g") * m.Cb"g"
    end
    if k == 17 then
        return m.Cmt(gen(depth + 1), function(_, i, ...)
            return i, select("#", ...)
        end)
    end
    if k == 18 then
        return m.B(S"ab") * gen(depth + 1)
    end

    return P{"s", s = gen(depth + 1) * (V"s" + "b") + "a"}
end

local subjects = {"", "a", "b", "ab", "ba", "aab", "abab", "bbaa", "aaaa", "babab"}
local agg = {}
for i = 1, 1000 do
    local p = gen(0)
    local line = {}
    for _, s in ipairs(subjects) do
        local r = {pcall(m.match, p, s)}
        line[#line + 1] = r[1] and ser({unpack(r, 2, table.maxn(r))}) or ("E:" .. norm(r[2]))
    end
    agg[#agg + 1] = table.concat(line, "|")
end
for i = 1, #agg, 50 do
    show("random " .. i, table.concat(agg, "\n", i, math.min(i + 49, #agg)))
end

print("checks: " .. count)
