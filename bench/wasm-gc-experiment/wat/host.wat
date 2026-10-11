;; The host boundary: a loop of calls into an imported Rust function.
(module
  (import "host" "nop" (func $nop (param i64) (result i64)))
  (func (export "callhost") (param $n i64) (result i64)
    (local $i i64) (local $acc i64)
    (block $done (loop $l
      (br_if $done (i64.ge_s (local.get $i) (local.get $n)))
      (local.set $acc (call $nop (local.get $acc)))
      (local.set $i (i64.add (local.get $i) (i64.const 1)))
      (br $l)))
    (local.get $acc))
)
