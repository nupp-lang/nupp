;; The same programs with integers as i31 references: no allocation for a
;; number that fits 31 bits, a cast and an unwrap per use.
(module
  (type $node (struct (field (mut anyref)) (field (mut anyref))))
  (func $box (param i32) (result anyref) (ref.i31 (local.get 0)))
  (func $unbox (param anyref) (result i32) (i31.get_s (ref.cast (ref i31) (local.get 0))))
  (func $fib (param $n anyref) (result anyref)
    (local $x i32)
    (local.set $x (call $unbox (local.get $n)))
    (if (i32.lt_s (local.get $x) (i32.const 2)) (then (return (local.get $n))))
    (call $box (i32.add
      (call $unbox (call $fib (call $box (i32.sub (local.get $x) (i32.const 1)))))
      (call $unbox (call $fib (call $box (i32.sub (local.get $x) (i32.const 2))))))))
  (func (export "fib") (param f64) (result f64) (f64.convert_i32_s (call $unbox (call $fib (call $box (i32.trunc_f64_s (local.get 0)))))))
  (func $make (param $d anyref) (result anyref)
    (local $x i32)
    (local.set $x (call $unbox (local.get $d)))
    (if (i32.eqz (local.get $x)) (then (return (struct.new $node (ref.null any) (ref.null any)))))
    (struct.new $node
      (call $make (call $box (i32.sub (local.get $x) (i32.const 1))))
      (call $make (call $box (i32.sub (local.get $x) (i32.const 1))))))
  (func $check (param $t anyref) (result anyref)
    (local $n (ref $node))
    (local.set $n (ref.cast (ref $node) (local.get $t)))
    (if (ref.is_null (struct.get $node 0 (local.get $n))) (then (return (call $box (i32.const 1)))))
    (call $box (i32.add (i32.add
      (call $unbox (call $check (struct.get $node 0 (local.get $n))))
      (call $unbox (call $check (struct.get $node 1 (local.get $n)))))
      (i32.const 1))))
  (func (export "trees") (param $iters f64) (param $depth f64) (result f64)
    (local $i i32) (local $s i32) (local $n i32)
    (local.set $n (i32.trunc_f64_s (local.get $iters)))
    (block $done (loop $l
      (br_if $done (i32.ge_s (local.get $i) (local.get $n)))
      (local.set $s (i32.add (local.get $s) (call $unbox (call $check (call $make (call $box (i32.trunc_f64_s (local.get $depth))))))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (f64.convert_i32_s (local.get $s)))
)
