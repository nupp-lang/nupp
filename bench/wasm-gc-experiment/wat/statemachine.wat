;; Suspension lowered by the compiler: a suspendable function is a state
;; machine over a heap frame; a park is a return, a resume a call. One level,
;; then three levels of suspendable calls per park.
(module
  (type $gen (struct (field $i (mut i64)) (field $n i64) (field $out (mut i64))))
  ;; Yields the next value into $out; 1 while running, 0 when finished.
  (func $gen_step (param $g (ref $gen)) (result i32)
    (local $i i64)
    (local.set $i (struct.get $gen $i (local.get $g)))
    (if (i64.ge_s (local.get $i) (struct.get $gen $n (local.get $g))) (then (return (i32.const 0))))
    (struct.set $gen $out (local.get $g) (local.get $i))
    (struct.set $gen $i (local.get $g) (i64.add (local.get $i) (i64.const 1)))
    (i32.const 1))
  (func (export "park1") (param $n i64) (result i64)
    (local $g (ref $gen)) (local $sum i64)
    (local.set $g (struct.new $gen (i64.const 0) (local.get $n) (i64.const 0)))
    (block $done (loop $l
      (br_if $done (i32.eqz (call $gen_step (local.get $g))))
      (local.set $sum (i64.add (local.get $sum) (struct.get $gen $out (local.get $g))))
      (br $l)))
    (local.get $sum))
  ;; Three suspendable frames: outer calls middle calls inner, which parks.
  ;; Each level checks its callee's state and returns through on a park.
  (type $frame (struct (field $pc (mut i32)) (field $callee (mut (ref null $frame))) (field $gen (mut (ref null $gen)))))
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
  (func (export "park3") (param $n i64) (result i64)
    (local $g (ref $gen)) (local $f (ref $frame)) (local $sum i64)
    (local.set $g (struct.new $gen (i64.const 0) (local.get $n) (i64.const 0)))
    (local.set $f (struct.new $frame (i32.const 0) (ref.null $frame) (local.get $g)))
    (block $done (loop $l
      (br_if $done (i32.eqz (call $outer_step (local.get $f))))
      (local.set $sum (i64.add (local.get $sum) (struct.get $gen $out (local.get $g))))
      (br $l)))
    (local.get $sum))
)
