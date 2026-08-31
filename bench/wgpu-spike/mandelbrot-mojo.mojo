from std.gpu import global_idx
from std.collections import List
from std.time import perf_counter_ns

from max.gpu.host import DeviceContext


comptime WIDTH = 1024
comptime HEIGHT = 768
comptime COUNT = WIDTH * HEIGHT
comptime MAX_ITERATIONS = 256
comptime THREADS = 256


def mandelbrot_kernel(
    points: Pointer[Float32, ImmutAnyOrigin],
    escapes: Pointer[UInt32, MutAnyOrigin],
    count: Int32,
    max_iterations: Int32,
):
    """The exact point-input/result-output workload used by Nupp's benchmark."""
    var index = global_idx.x
    if index >= Int(count):
        return

    var cx = points[unsafe_offset=2 * index]
    var cy = points[unsafe_offset=2 * index + 1]
    var cardioid_x = cx - Float32(0.25)
    var y_squared = cy * cy
    var cardioid_square = cardioid_x * cardioid_x
    var q = cardioid_square + y_squared
    var cardioid_sum = q + cardioid_x
    var cardioid_metric = q * cardioid_sum
    var cardioid_limit = Float32(0.25) * y_squared
    var inside = Int32(0)
    if cardioid_metric <= cardioid_limit:
        inside = 1
    var shifted = cx + Float32(1.0)
    var bulb_square = shifted * shifted
    var bulb_metric = bulb_square + y_squared
    if bulb_metric <= Float32(0.0625):
        inside = 1

    var zx = Float32(0.0)
    var zy = Float32(0.0)
    var zx_squared = Float32(0.0)
    var zy_squared = Float32(0.0)
    var iteration = Int32(0)
    var escaped = UInt32(0)
    if inside == 1:
        iteration = max_iterations
    while iteration < max_iterations:
        var radius_squared = zx_squared + zy_squared
        if radius_squared > Float32(4.0):
            escaped = 1
            break
        var doubled_zx = zx * Float32(2.0)
        var product = doubled_zx * zy
        zy = product + cy
        var difference = zx_squared - zy_squared
        zx = difference + cx
        zx_squared = zx * zx
        zy_squared = zy * zy
        iteration += 1
    if iteration < max_iterations:
        escaped = 1
    escapes[unsafe_offset=2 * index] = UInt32(iteration)
    escapes[unsafe_offset=2 * index + 1] = escaped


def main() raises:
    with DeviceContext() as ctx:
        # Ordinary pageable arrays match the spans passed to Nupp and WGPU.
        var points = List[Float32](length=2 * COUNT, fill=Float32(0.0))
        var escapes = List[UInt32](length=2 * COUNT, fill=UInt32(0))
        var host_points = ctx.enqueue_create_host_buffer[.float32](2 * COUNT)
        var host_escapes = ctx.enqueue_create_host_buffer[.uint32](2 * COUNT)
        var device_points = ctx.enqueue_create_buffer[.float32](2 * COUNT)
        var device_escapes = ctx.enqueue_create_buffer[.uint32](2 * COUNT)
        ctx.synchronize()

        var dx = Float32(3.0) / Float32(WIDTH)
        var dy = Float32(2.4) / Float32(HEIGHT)
        for y in range(HEIGHT):
            var y_offset = Float32(y) * dy
            var cy = Float32(-1.2) + y_offset
            for x in range(WIDTH):
                var x_offset = Float32(x) * dx
                var index = y * WIDTH + x
                points[2 * index] = Float32(-2.0) + x_offset
                points[2 * index + 1] = cy

        var compiled = ctx.compile_function[mandelbrot_kernel]()
        comptime blocks = (COUNT + THREADS - 1) // THREADS

        ctx.enqueue_copy(src=Span(points), dst_buf=device_points)
        ctx.enqueue_function(
            compiled,
            device_points,
            device_escapes,
            Int32(COUNT),
            Int32(MAX_ITERATIONS),
            grid_dim=blocks,
            block_dim=THREADS,
        )
        ctx.enqueue_copy(src_buf=device_escapes, dst=Span(escapes))
        ctx.synchronize()

        var checksum = UInt64(0)
        for i in range(COUNT):
            checksum += UInt64(escapes[2 * i])
        if checksum != 46372998:
            print("Mojo checksum:", checksum)
            raise Error(
                "Mojo result does not match Nupp; run with --fp-mode"
                " contract=off"
            )

        for _ in range(3):
            ctx.enqueue_function(
                compiled,
                device_points,
                device_escapes,
                Int32(COUNT),
                Int32(MAX_ITERATIONS),
                grid_dim=blocks,
                block_dim=THREADS,
            )
            ctx.synchronize()

        var started = perf_counter_ns()
        var passes = 0
        while perf_counter_ns() - started < 1_000_000_000:
            ctx.enqueue_function(
                compiled,
                device_points,
                device_escapes,
                Int32(COUNT),
                Int32(MAX_ITERATIONS),
                grid_dim=blocks,
                block_dim=THREADS,
            )
            ctx.synchronize()
            passes += 1
        var resident_elapsed = Float64(perf_counter_ns() - started) / Float64(
            passes
        )

        for _ in range(3):
            ctx.enqueue_copy(src=Span(points), dst_buf=device_points)
            ctx.enqueue_function(
                compiled,
                device_points,
                device_escapes,
                Int32(COUNT),
                Int32(MAX_ITERATIONS),
                grid_dim=blocks,
                block_dim=THREADS,
            )
            ctx.enqueue_copy(src_buf=device_escapes, dst=Span(escapes))
            ctx.synchronize()

        started = perf_counter_ns()
        passes = 0
        while perf_counter_ns() - started < 1_000_000_000:
            ctx.enqueue_copy(src=Span(points), dst_buf=device_points)
            ctx.enqueue_function(
                compiled,
                device_points,
                device_escapes,
                Int32(COUNT),
                Int32(MAX_ITERATIONS),
                grid_dim=blocks,
                block_dim=THREADS,
            )
            ctx.enqueue_copy(src_buf=device_escapes, dst=Span(escapes))
            ctx.synchronize()
            passes += 1
        var pageable_elapsed = Float64(perf_counter_ns() - started) / Float64(
            passes
        )

        # Also expose Mojo's preferred pinned-memory boundary. It is useful, but
        # it does not match the ordinary CPU spans in the existing benchmark.
        ctx.enqueue_copy(src=Span(points), dst_buf=host_points)
        ctx.synchronize()
        for _ in range(3):
            ctx.enqueue_copy(src_buf=host_points, dst_buf=device_points)
            ctx.enqueue_function(
                compiled,
                device_points,
                device_escapes,
                Int32(COUNT),
                Int32(MAX_ITERATIONS),
                grid_dim=blocks,
                block_dim=THREADS,
            )
            ctx.enqueue_copy(src_buf=device_escapes, dst_buf=host_escapes)
            ctx.synchronize()

        started = perf_counter_ns()
        passes = 0
        while perf_counter_ns() - started < 1_000_000_000:
            ctx.enqueue_copy(src_buf=host_points, dst_buf=device_points)
            ctx.enqueue_function(
                compiled,
                device_points,
                device_escapes,
                Int32(COUNT),
                Int32(MAX_ITERATIONS),
                grid_dim=blocks,
                block_dim=THREADS,
            )
            ctx.enqueue_copy(src_buf=device_escapes, dst_buf=host_escapes)
            ctx.synchronize()
            passes += 1
        var pinned_elapsed = Float64(perf_counter_ns() - started) / Float64(
            passes
        )

        print(
            "Mandelbrot:",
            WIDTH,
            "x",
            HEIGHT,
            ",",
            MAX_ITERATIONS,
            "max iterations, checksum",
            checksum,
        )
        print("Mojo GPU:", THREADS, "threads/group on", ctx.name())
        print(
            "Mojo resident ",
            resident_elapsed,
            "ns/frame ",
            Float64(COUNT) / resident_elapsed * 1000.0,
            "MPix/s",
        )
        print(
            "Mojo pageable ",
            pageable_elapsed,
            "ns/frame ",
            Float64(COUNT) / pageable_elapsed * 1000.0,
            "MPix/s",
        )
        print(
            "Mojo pinned   ",
            pinned_elapsed,
            "ns/frame ",
            Float64(COUNT) / pinned_elapsed * 1000.0,
            "MPix/s",
        )
