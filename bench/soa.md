# SoA lowering benchmark

Run the comparative suite from the repository root:

```sh
./bin/nupp bench --file bench/soa.bench.nupp --geo
```

It compares compiler-lowered `rows[i].field` access with four hand-written
single-field cdata arrays and the canonical AoS struct. Each invocation creates
and initializes 100,000 particles, advances them for 30 steps, and returns a
checksum that observes every updated `x` and `y` value. The shared benchmark
harness owns warmup, sampling, process isolation, allocation accounting, and
result reporting.

Use `--variant` to select one representation, `--profile` to collect collapsed
stacks for its measured callback, and `--json` for raw samples and compiler
accounts. The compiler-lowered loop remains the representation decision this
benchmark is intended to guard.
