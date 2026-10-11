;; The prototype's park benchmark: 1,000 tasks, each parking 1,000 times
;; inside a three-frame suspendable call chain, scheduled round-robin. Each
;; task resumes at its own frame state. The scheduler runs in Wasm
;; (`run`), or the host drives one step at a time (`step`).
(module
  (type $gen (struct (field $i (mut i64)) (field $n i64) (field $out (mut i64))))
  (type $frame (struct (field $pc (mut i32)) (field $callee (mut (ref null $frame))) (field $gen (mut (ref null $gen)))))
  (type $tasks (array (mut (ref null $frame))))
  (global $tasks (mut (ref null $tasks)) (ref.null $tasks))
  (global $parks (mut i64) (i64.const 0))
  (func $gen_step (param $g (ref $gen)) (result i32)
    (local $i i64)
    (local.set $i (struct.get $gen $i (local.get $g)))
    (if (i64.ge_s (local.get $i) (struct.get $gen $n (local.get $g))) (then (return (i32.const 0))))
    (struct.set $gen $out (local.get $g) (local.get $i))
    (struct.set $gen $i (local.get $g) (i64.add (local.get $i) (i64.const 1)))
    (global.set $parks (i64.add (global.get $parks) (i64.const 1)))
    (i32.const 1))
  (func $inner_step (param $f (ref $frame)) (result i32)
    (call $gen_step (ref.as_non_null (struct.get $frame $gen (local.get $f)))))
  (func $middle_step (param $f (ref $frame)) (result i32)
    (if (i32.eqz (struct.get $frame $pc (local.get $f))) (then
      (struct.set $frame $callee (local.get $f) (struct.new $frame (i32.const 0) (ref.null $frame) (struct.get $frame $gen (local.get $f))))
      (struct.set $frame $pc (local.get $f) (i32.const 1))))
    (call $inner_step (ref.as_non_null (struct.get $frame $callee (local.get $f)))))
  (func $outer_step (param $f (ref $frame)) (result i32)
    (if (i32.eqz (struct.get $frame $pc (local.get $f))) (then
      (struct.set $frame $callee (local.get $f) (struct.new $frame (i32.const 0) (ref.null $frame) (struct.get $frame $gen (local.get $f))))
      (struct.set $frame $pc (local.get $f) (i32.const 1))))
    (call $middle_step (ref.as_non_null (struct.get $frame $callee (local.get $f)))))
  (func (export "spawn") (param $count i32) (param $n i64)
    (local $i i32) (local $t (ref $tasks))
    (local.set $t (array.new $tasks (ref.null $frame) (local.get $count)))
    (block $done (loop $l
      (br_if $done (i32.ge_u (local.get $i) (local.get $count)))
      (array.set $tasks (local.get $t) (local.get $i) (struct.new $frame (i32.const 0) (ref.null $frame) (struct.new $gen (i64.const 0) (local.get $n) (i64.const 0))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (global.set $tasks (local.get $t))
    (global.set $parks (i64.const 0)))
  ;; Round-robin until every task has finished; returns the parks taken.
  (func (export "run") (result i64)
    (local $t (ref $tasks)) (local $i i32) (local $n i32) (local $live i32) (local $f (ref null $frame))
    (local.set $t (ref.as_non_null (global.get $tasks)))
    (local.set $n (array.len (local.get $t)))
    (local.set $live (local.get $n))
    (block $all (loop $round
      (local.set $i (i32.const 0))
      (block $end (loop $each
        (br_if $end (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $f (array.get $tasks (local.get $t) (local.get $i)))
        (if (i32.eqz (ref.is_null (local.get $f))) (then
          (if (i32.eqz (call $outer_step (ref.as_non_null (local.get $f)))) (then
            (array.set $tasks (local.get $t) (local.get $i) (ref.null $frame))
            (local.set $live (i32.sub (local.get $live) (i32.const 1)))))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $each)))
      (br_if $all (i32.eqz (local.get $live)))
      (br $round)))
    (global.get $parks))
  ;; One step of task i for a host-side scheduler: 1 parked, 0 finished, -1 absent.
  (func (export "step") (param $i i32) (result i32)
    (local $t (ref $tasks)) (local $f (ref null $frame))
    (local.set $t (ref.as_non_null (global.get $tasks)))
    (local.set $f (array.get $tasks (local.get $t) (local.get $i)))
    (if (ref.is_null (local.get $f)) (then (return (i32.const -1))))
    (if (i32.eqz (call $outer_step (ref.as_non_null (local.get $f)))) (then
      (array.set $tasks (local.get $t) (local.get $i) (ref.null $frame))
      (return (i32.const 0))))
    (i32.const 1))
  (func (export "parks") (result i64) (global.get $parks))
)
