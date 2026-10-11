;; The untyped tier on Wasm GC: every value is anyref, numbers are boxed f64
;; structs, records are structs of anyref, every operation casts.
(module
  (type $num (struct (field f64)))
  (type $node (struct (field (mut anyref)) (field (mut anyref))))
  (func $box (param f64) (result anyref) (struct.new $num (local.get 0)))
  (func $unbox (param anyref) (result f64) (struct.get $num 0 (ref.cast (ref $num) (local.get 0))))
  (func $fib (param $n anyref) (result anyref)
    (local $x f64)
    (local.set $x (call $unbox (local.get $n)))
    (if (f64.lt (local.get $x) (f64.const 2)) (then (return (local.get $n))))
    (call $box (f64.add
      (call $unbox (call $fib (call $box (f64.sub (local.get $x) (f64.const 1)))))
      (call $unbox (call $fib (call $box (f64.sub (local.get $x) (f64.const 2))))))))
  (func (export "fib") (param f64) (result f64) (call $unbox (call $fib (call $box (local.get 0)))))
  (func $make (param $d anyref) (result anyref)
    (local $x f64)
    (local.set $x (call $unbox (local.get $d)))
    (if (f64.eq (local.get $x) (f64.const 0)) (then (return (struct.new $node (ref.null any) (ref.null any)))))
    (struct.new $node
      (call $make (call $box (f64.sub (local.get $x) (f64.const 1))))
      (call $make (call $box (f64.sub (local.get $x) (f64.const 1))))))
  (func $check (param $t anyref) (result anyref)
    (local $n (ref $node))
    (local.set $n (ref.cast (ref $node) (local.get $t)))
    (if (ref.is_null (struct.get $node 0 (local.get $n))) (then (return (call $box (f64.const 1)))))
    (call $box (f64.add (f64.add
      (call $unbox (call $check (struct.get $node 0 (local.get $n))))
      (call $unbox (call $check (struct.get $node 1 (local.get $n)))))
      (f64.const 1))))
  (func (export "trees") (param $iters f64) (param $depth f64) (result f64)
    (local $i f64) (local $s f64)
    (block $done (loop $l
      (br_if $done (f64.ge (local.get $i) (local.get $iters)))
      (local.set $s (f64.add (local.get $s) (call $unbox (call $check (call $make (call $box (local.get $depth)))))))
      (local.set $i (f64.add (local.get $i) (f64.const 1)))
      (br $l)))
    (local.get $s))
)
