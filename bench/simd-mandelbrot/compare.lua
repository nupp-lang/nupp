-- Compare preserved native Mandelbrot libraries, with the baseline scalar
-- function as a colocated control. Run separate processes for duration evidence.
local ffi = require("ffi")
local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "clock.lua")
ffi.cdef[[
typedef struct { int32_t iterations; uint32_t escaped; } KsEscape;
typedef struct { float re; float im; } KsPoint;
void ks_mandelbrot(KsEscape *, const KsPoint *, double, double, int32_t, size_t);
void ks_mandelbrot_forced_scalar(KsEscape *, const KsPoint *, double, double, int32_t, size_t);
]]
local baseline = ffi.load(assert(arg[1], "baseline library required"))
local candidate = ffi.load(assert(arg[2], "candidate library required"))
local width = tonumber(os.getenv("MANDELBROT_WIDTH") or 1024)
local height = tonumber(os.getenv("MANDELBROT_HEIGHT") or 768)
local maxIterations = tonumber(os.getenv("MANDELBROT_ITERATIONS") or 256)
local samples = tonumber(os.getenv("MANDELBROT_SAMPLES") or 21)
local count = width * height
local cell = ffi.new("float[1]")

local function f32(value)
    cell[0] = value
    return tonumber(cell[0])
end

-- Construct the grid with an explicit binary32 rounding point after each step.
local points = ffi.new("KsPoint[?]", count)
local dx = f32(f32(3.0) / f32(width))
local dy = f32(f32(2.4) / f32(height))
for y = 0, height - 1 do
    local yOffset = f32(f32(y) * dy)
    local cy = f32(f32(-1.2) + yOffset)
    for x = 0, width - 1 do
        local xOffset = f32(f32(x) * dx)
        local point = points[y * width + x]
        point.re = f32(f32(-2.0) + xOffset)
        point.im = cy
    end
end

local bodies = {
    {name = "baseline", entry = baseline.ks_mandelbrot},
    {name = "candidate", entry = candidate.ks_mandelbrot},
    {name = "control", entry = baseline.ks_mandelbrot_forced_scalar},
}

local function run(body)
    body.entry(body.output, points, 1, count, maxIterations, count)
end

for _, body in ipairs(bodies) do
    body.output = ffi.new("KsEscape[?]", count)
    run(body)
end
local checksum = 0
for i = 0, count - 1 do
    local expected = bodies[3].output[i]
    for j = 1, 2 do
        local value = bodies[j].output[i]
        assert(
            value.iterations == expected.iterations and value.escaped == expected.escaped,
            bodies[j].name .. " disagrees at pixel " .. i
        )
    end
    checksum = checksum + expected.iterations
end
io.stderr:write(
    (
        "%dx%d, iterations=%d, checksum=%d; both native libraries match scalar\n"
    ):format(width, height, maxIterations, checksum)
)
for _, body in ipairs(bodies) do
    for _ = 1, 3 do
        run(body)
    end
end
io.write("round,variant,seconds\n")
for round = 1, samples do
    for offset = 1, #bodies do
        local body = bodies[(round + offset - 2) % #bodies + 1]
        local started = now()
        run(body)
        local elapsed = now() - started
        io.write(("%d,%s,%.9f\n"):format(round, body.name, elapsed))
    end
end
