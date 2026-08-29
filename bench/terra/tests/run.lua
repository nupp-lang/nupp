-- The four implementations against each other, before either of them is timed.
--
-- A fast wrong answer is the failure mode a benchmark is most likely to reward,
-- and three of the four here are compiled by different compilers from different
-- source text, so agreement is a claim that has to be checked rather than
-- assumed. It is checked exactly. None of these kernels is specified to a
-- tolerance: Nupp's arithmetic is binary64, neither contracted nor
-- reassociated, the C control is built `-ffp-contract=off`, and Terra's code
-- generator is asked for no relaxation either, so the same program over the
-- same bytes has one answer and all four must produce it.
--
-- Sizes are chosen around the edges of the lane-lowered loops rather than for
-- being round. A kernel that lowers four lanes at a time has a vector body and
-- a scalar tail, and a length that is a multiple of four never runs the tail.
local implementations = require("implementations")

local failures = 0
local checks = 0

local function check(condition, message)
   checks = checks + 1
   if not condition then
      failures = failures + 1
      io.write("  FAIL ", message, "\n")
   end
end

-- Nothing, one, either side of a lane group, either side of two lane groups,
-- and a size big enough to have a body and a tail both.
local sizes = {0, 1, 2, 3, 4, 5, 7, 8, 9, 16, 17, 63, 64, 65, 1000, 1024}

for _, kernel in ipairs(implementations.kernels) do
   io.write(kernel.name, "\n")
   for _, count in ipairs(sizes) do
      local answers = {}
      for _, name in ipairs(implementations.order) do
         local work = kernel:allocate(count)
         kernel:clear(work)
         kernel.calls[name](work, kernel)
         answers[name] = kernel:checksum(work)
      end

      local expected = answers.c
      for _, name in ipairs(implementations.order) do
         check(answers[name] == expected, ("%s: %s disagrees at %d elements"):format(
            kernel.name, implementations.titles[name], count))
      end
   end

   -- The kernel has to actually do something, or every implementation agreeing
   -- would mean nothing. `mandelbrot` on an all-interior strip and `mix` on a
   -- span of zeroes would both pass the loop above while measuring almost
   -- nothing, so the answer at a real size is required to be non-trivial.
   local work = kernel:allocate(1024)
   kernel:clear(work)
   local empty = kernel:checksum(work)
   kernel.calls.c(work, kernel)
   check(kernel:checksum(work) ~= empty,
      ("%s: writes nothing at 1024 elements"):format(kernel.name))
end

io.write(("\n%d checks, %d failures\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
