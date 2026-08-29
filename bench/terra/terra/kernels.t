-- The same four kernels in Terra, compiled ahead of time to a shared library.
--
-- Terra normally JIT-compiles into its own process, and this benchmark does not
-- run there: measuring the Nupp routes needs the repository's LuaJIT, and
-- Terra's release embeds bytecode only its own LuaJIT can load, so the two
-- cannot share an interpreter. `terralib.saveobj` settles it. The kernels are
-- compiled by exactly the LLVM pipeline a JIT-compiled Terra function gets --
-- `optimize` is the sixth argument and it is the default -- and are then
-- reached over the same FFI boundary as the C control, so what separates the
-- Terra column from the C column is the code generator and not the call.
--
-- `benchmark.lua` checks that claim rather than asserting it: it measures
-- `sumSquares` over a single element, where the per-call cost is almost all
-- there is, and reports what the boundary costs on each of the four routes.
--
-- Terra has no `restrict`. Nupp's `exclusive` spans and the C control's output
-- pointers both carry it, so where a kernel's output and input could alias,
-- Terra is compiling a weaker promise than the other two. That is a real
-- difference between the languages and it is left in.

local output = assert(arg[1], "usage: terra kernels.t OUTPUT")

struct TbEscape {
    iterations: int32
    escaped: uint32
}

struct TbPoint {
    re: float
    im: float
}

struct TbBody {
    x: float
    y: float
    vx: float
    vy: float
}

terra tbMandelbrot(escapes: &TbEscape, points: &TbPoint,
                   maxIterations: int32, count: uint64)
    for i = 0ULL, count do
        var cx: double = points[i].re
        var cy: double = points[i].im
        var zx: double = 0.0
        var zy: double = 0.0
        var zxSquared: double = 0.0
        var zySquared: double = 0.0
        var iteration: int32 = 0
        var escaped: uint32 = 0

        while iteration < maxIterations do
            if zxSquared + zySquared > 4.0 then
                escaped = 1
                break
            end
            zy = 2.0 * zx * zy + cy
            zx = zxSquared - zySquared + cx
            zxSquared = zx * zx
            zySquared = zy * zy
            iteration = iteration + 1
        end

        escapes[i].iterations = iteration
        escapes[i].escaped = escaped
    end
end

terra tbAdvance(output: &TbBody, input: &TbBody, dt: double, drag: double, count: uint64)
    for i = 0ULL, count do
        var vx: double = [double](input[i].vx) * drag
        var vy: double = [double](input[i].vy) * drag
        output[i].x = [float]([double](input[i].x) + vx * dt)
        output[i].y = [float]([double](input[i].y) + vy * dt)
        output[i].vx = [float](vx)
        output[i].vy = [float](vy)
    end
end

terra tbSumSquares(values: &double, count: uint64): double
    var total: double = 0.0
    for i = 0ULL, count do
        total = total + values[i] * values[i]
    end
    return total
end

terra tbMix(output: &uint32, input: &uint32, count: uint64)
    for i = 0ULL, count do
        var state: uint32 = input[i]
        for round = 0, 4 do
            state = state ^ (state << 13)
            state = state ^ (state >> 17)
            state = state ^ (state << 5)
        end
        output[i] = state
    end
end

terralib.saveobj(output, "sharedlibrary", {
    tbMandelbrot = tbMandelbrot,
    tbAdvance = tbAdvance,
    tbSumSquares = tbSumSquares,
    tbMix = tbMix,
}, nil, nil, true)
