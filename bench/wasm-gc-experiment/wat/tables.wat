;; A Lua table on Wasm GC: open addressing over GC arrays, string keys
;; interned so equality is identity, the hash carried in the string. Numbers
;; are boxed f64 structs, as in the untyped encoding.
(module
  (type $num (struct (field f64)))
  (type $bytes (array (mut i8)))
  (type $str (struct (field $hash i32) (field $data (ref $bytes))))
  (type $keys (array (mut eqref)))
  (type $vals (array (mut anyref)))
  (type $tbl (struct (field $keys (mut (ref $keys))) (field $vals (mut (ref $vals))) (field $count (mut i32)) (field $mask (mut i32))))
  (global $ikeys (mut (ref null $keys)) (ref.null $keys))
  (global $icount (mut i32) (i32.const 0))
  (global $imask (mut i32) (i32.const 0))
  (global $key_x (mut (ref null $str)) (ref.null $str))
  (global $probes (mut i32) (i32.const 0))

  (func $box (param f64) (result anyref) (struct.new $num (local.get 0)))
  (func $unbox (param anyref) (result f64) (struct.get $num 0 (ref.cast (ref $num) (local.get 0))))

  (func $hash_bytes (param $b (ref $bytes)) (result i32)
    (local $h i32) (local $i i32) (local $n i32)
    (local.set $h (i32.const 0x811c9dc5))
    (local.set $n (array.len (local.get $b)))
    (block $done (loop $l
      (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
      (local.set $h (i32.mul (i32.xor (local.get $h) (array.get_u $bytes (local.get $b) (local.get $i))) (i32.const 0x01000193)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (local.get $h))

  (func $bytes_eq (param $a (ref $bytes)) (param $b (ref $bytes)) (result i32)
    (local $i i32) (local $n i32)
    (local.set $n (array.len (local.get $a)))
    (if (i32.ne (local.get $n) (array.len (local.get $b))) (then (return (i32.const 0))))
    (block $done (loop $l
      (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
      (if (i32.ne (array.get_u $bytes (local.get $a) (local.get $i)) (array.get_u $bytes (local.get $b) (local.get $i))) (then (return (i32.const 0))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (i32.const 1))

  ;; The intern table: the one string object per distinct byte sequence.
  (func $intern (param $b (ref $bytes)) (result (ref $str))
    (local $h i32) (local $slot i32) (local $cur eqref) (local $s (ref $str)) (local $keys (ref $keys))
    (local.set $h (call $hash_bytes (local.get $b)))
    (local.set $keys (ref.as_non_null (global.get $ikeys)))
    (local.set $slot (i32.and (local.get $h) (global.get $imask)))
    (block $miss (loop $l
      (global.set $probes (i32.add (global.get $probes) (i32.const 1)))
      (local.set $cur (array.get $keys (local.get $keys) (local.get $slot)))
      (br_if $miss (ref.is_null (local.get $cur)))
      (local.set $s (ref.cast (ref $str) (local.get $cur)))
      (if (i32.and (i32.eq (struct.get $str $hash (local.get $s)) (local.get $h)) (call $bytes_eq (struct.get $str $data (local.get $s)) (local.get $b)))
        (then (return (local.get $s))))
      (local.set $slot (i32.and (i32.add (local.get $slot) (i32.const 1)) (global.get $imask)))
      (br $l)))
    (local.set $s (struct.new $str (local.get $h) (local.get $b)))
    (array.set $keys (local.get $keys) (local.get $slot) (local.get $s))
    (global.set $icount (i32.add (global.get $icount) (i32.const 1)))
    (if (i32.gt_u (i32.mul (global.get $icount) (i32.const 2)) (global.get $imask)) (then (call $intern_grow)))
    (local.get $s))

  (func $intern_grow
    (local $old (ref $keys)) (local $new (ref $keys)) (local $i i32) (local $n i32) (local $cur eqref) (local $s (ref $str)) (local $slot i32) (local $mask i32)
    (local.set $old (ref.as_non_null (global.get $ikeys)))
    (local.set $n (array.len (local.get $old)))
    (local.set $mask (i32.sub (i32.mul (local.get $n) (i32.const 2)) (i32.const 1)))
    (local.set $new (array.new $keys (ref.null eq) (i32.mul (local.get $n) (i32.const 2))))
    (block $done (loop $l
      (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
      (local.set $cur (array.get $keys (local.get $old) (local.get $i)))
      (if (i32.eqz (ref.is_null (local.get $cur))) (then
        (local.set $s (ref.cast (ref $str) (local.get $cur)))
        (local.set $slot (i32.and (struct.get $str $hash (local.get $s)) (local.get $mask)))
        (block $placed (loop $p
          (br_if $placed (ref.is_null (array.get $keys (local.get $new) (local.get $slot))))
          (local.set $slot (i32.and (i32.add (local.get $slot) (i32.const 1)) (local.get $mask)))
          (br $p)))
        (array.set $keys (local.get $new) (local.get $slot) (local.get $s))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (global.set $ikeys (local.get $new))
    (global.set $imask (local.get $mask)))

  (func $tbl_new (result (ref $tbl))
    (struct.new $tbl (array.new $keys (ref.null eq) (i32.const 8)) (array.new $vals (ref.null any) (i32.const 8)) (i32.const 0) (i32.const 7)))

  ;; The slot holding key k, or -1.
  (func $tbl_find (param $t (ref $tbl)) (param $k (ref $str)) (result i32)
    (local $slot i32) (local $keys (ref $keys)) (local $mask i32) (local $cur eqref)
    (local.set $keys (struct.get $tbl $keys (local.get $t)))
    (local.set $mask (struct.get $tbl $mask (local.get $t)))
    (local.set $slot (i32.and (struct.get $str $hash (local.get $k)) (local.get $mask)))
    (loop $l
      (local.set $cur (array.get $keys (local.get $keys) (local.get $slot)))
      (if (ref.is_null (local.get $cur)) (then (return (i32.const -1))))
      (if (ref.eq (local.get $cur) (local.get $k)) (then (return (local.get $slot))))
      (local.set $slot (i32.and (i32.add (local.get $slot) (i32.const 1)) (local.get $mask)))
      (br $l))
    (unreachable))

  (func $tbl_get (param $t (ref $tbl)) (param $k (ref $str)) (result anyref)
    (local $i i32)
    (local.set $i (call $tbl_find (local.get $t) (local.get $k)))
    (if (i32.lt_s (local.get $i) (i32.const 0)) (then (return (ref.null any))))
    (array.get $vals (struct.get $tbl $vals (local.get $t)) (local.get $i)))

  (func $tbl_set (param $t (ref $tbl)) (param $k (ref $str)) (param $v anyref)
    (local $i i32) (local $keys (ref $keys)) (local $mask i32)
    (local.set $i (call $tbl_find (local.get $t) (local.get $k)))
    (if (i32.ge_s (local.get $i) (i32.const 0)) (then
      (array.set $vals (struct.get $tbl $vals (local.get $t)) (local.get $i) (local.get $v))
      (return)))
    (if (i32.gt_u (i32.mul (i32.add (struct.get $tbl $count (local.get $t)) (i32.const 1)) (i32.const 2)) (struct.get $tbl $mask (local.get $t))) (then (call $tbl_grow (local.get $t))))
    (local.set $keys (struct.get $tbl $keys (local.get $t)))
    (local.set $mask (struct.get $tbl $mask (local.get $t)))
    (local.set $i (i32.and (struct.get $str $hash (local.get $k)) (local.get $mask)))
    (block $placed (loop $p
      (br_if $placed (ref.is_null (array.get $keys (local.get $keys) (local.get $i))))
      (local.set $i (i32.and (i32.add (local.get $i) (i32.const 1)) (local.get $mask)))
      (br $p)))
    (array.set $keys (local.get $keys) (local.get $i) (local.get $k))
    (array.set $vals (struct.get $tbl $vals (local.get $t)) (local.get $i) (local.get $v))
    (struct.set $tbl $count (local.get $t) (i32.add (struct.get $tbl $count (local.get $t)) (i32.const 1))))

  (func $tbl_grow (param $t (ref $tbl))
    (local $old (ref $keys)) (local $oldv (ref $vals)) (local $n i32) (local $i i32) (local $cur eqref) (local $slot i32) (local $mask i32) (local $keys (ref $keys)) (local $vals (ref $vals))
    (local.set $old (struct.get $tbl $keys (local.get $t)))
    (local.set $oldv (struct.get $tbl $vals (local.get $t)))
    (local.set $n (array.len (local.get $old)))
    (local.set $mask (i32.sub (i32.mul (local.get $n) (i32.const 2)) (i32.const 1)))
    (local.set $keys (array.new $keys (ref.null eq) (i32.mul (local.get $n) (i32.const 2))))
    (local.set $vals (array.new $vals (ref.null any) (i32.mul (local.get $n) (i32.const 2))))
    (block $done (loop $l
      (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
      (local.set $cur (array.get $keys (local.get $old) (local.get $i)))
      (if (i32.eqz (ref.is_null (local.get $cur))) (then
        (local.set $slot (i32.and (struct.get $str $hash (ref.cast (ref $str) (local.get $cur))) (local.get $mask)))
        (block $placed (loop $p
          (br_if $placed (ref.is_null (array.get $keys (local.get $keys) (local.get $slot))))
          (local.set $slot (i32.and (i32.add (local.get $slot) (i32.const 1)) (local.get $mask)))
          (br $p)))
        (array.set $keys (local.get $keys) (local.get $slot) (local.get $cur))
        (array.set $vals (local.get $vals) (local.get $slot) (array.get $vals (local.get $oldv) (local.get $i)))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (struct.set $tbl $keys (local.get $t) (local.get $keys))
    (struct.set $tbl $vals (local.get $t) (local.get $vals))
    (struct.set $tbl $mask (local.get $t) (local.get $mask)))

  (func $init
    (global.set $ikeys (array.new $keys (ref.null eq) (i32.const 4096)))
    (global.set $imask (i32.const 4095))
    (global.set $key_x (call $intern (array.new_fixed $bytes 1 (i32.const 120)))))
  (start $init)

  ;; t = {}; t.x = 0; for i = 1..n: t.x = t.x + i; return t.x
  (func (export "churn") (param $n f64) (result f64)
    (local $t (ref $tbl)) (local $i f64) (local $x (ref $str))
    (local.set $x (ref.as_non_null (global.get $key_x)))
    (local.set $t (call $tbl_new))
    (call $tbl_set (local.get $t) (local.get $x) (call $box (f64.const 0)))
    (local.set $i (f64.const 1))
    (block $done (loop $l
      (br_if $done (f64.gt (local.get $i) (local.get $n)))
      (call $tbl_set (local.get $t) (local.get $x) (call $box (f64.add (call $unbox (call $tbl_get (local.get $t) (local.get $x))) (local.get $i))))
      (local.set $i (f64.add (local.get $i) (f64.const 1)))
      (br $l)))
    (call $unbox (call $tbl_get (local.get $t) (local.get $x))))

  ;; n four-byte strings built and interned; a second call with the same n
  ;; finds every one. Returns the sum of the low hash bits as a checksum.
  (func (export "intern") (param $n i32) (result i32)
    (local $i i32) (local $acc i32) (local $s (ref $str))
    (block $done (loop $l
      (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
      (local.set $s (call $intern (array.new_fixed $bytes 4 (i32.const 112) (i32.and (local.get $i) (i32.const 255)) (i32.and (i32.shr_u (local.get $i) (i32.const 8)) (i32.const 255)) (i32.and (i32.shr_u (local.get $i) (i32.const 16)) (i32.const 255)))))
      (local.set $acc (i32.add (local.get $acc) (i32.and (struct.get $str $hash (local.get $s)) (i32.const 1))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (local.get $acc))
  (func (export "interned") (result i32) (global.get $icount))
  ;; The same field loop with i31 values: table work with no allocation.
  (func (export "churn_i31") (param $n i32) (result i32)
    (local $t (ref $tbl)) (local $i i32) (local $x (ref $str))
    (local.set $x (ref.as_non_null (global.get $key_x)))
    (local.set $t (call $tbl_new))
    (call $tbl_set (local.get $t) (local.get $x) (ref.i31 (i32.const 0)))
    (local.set $i (i32.const 1))
    (block $done (loop $l
      (br_if $done (i32.gt_s (local.get $i) (local.get $n)))
      (call $tbl_set (local.get $t) (local.get $x) (ref.i31 (i32.add (i31.get_s (ref.cast (ref i31) (call $tbl_get (local.get $t) (local.get $x)))) (local.get $i))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (i31.get_s (ref.cast (ref i31) (call $tbl_get (local.get $t) (local.get $x)))))
  ;; Allocate a box and store it into an old array slot, each iteration.
  (func (export "alloc_store") (param $n i32) (result i32)
    (local $i i32) (local $vals (ref $vals))
    (local.set $vals (array.new $vals (ref.null any) (i32.const 8)))
    (block $done (loop $l
      (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
      (array.set $vals (local.get $vals) (i32.and (local.get $i) (i32.const 7)) (call $box (f64.convert_i32_u (local.get $i))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (i32.trunc_f64_u (call $unbox (array.get $vals (local.get $vals) (i32.const 7)))))
  ;; What one reference store into an existing array costs, against a
  ;; number store into a struct: the collector's write barrier, isolated.
  (type $cell (struct (field $f (mut f64))))
  (func (export "refstore") (param $n i32) (result i32)
    (local $i i32) (local $vals (ref $vals)) (local $v anyref)
    (local.set $vals (array.new $vals (ref.null any) (i32.const 8)))
    (local.set $v (call $box (f64.const 1)))
    (block $done (loop $l
      (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
      (array.set $vals (local.get $vals) (i32.and (local.get $i) (i32.const 7)) (local.get $v))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (array.len (local.get $vals)))
  (func (export "numstore") (param $n i32) (result i32)
    (local $i i32) (local $c (ref $cell))
    (local.set $c (struct.new $cell (f64.const 0)))
    (block $done (loop $l
      (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
      (struct.set $cell $f (local.get $c) (f64.convert_i32_u (local.get $i)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (i32.trunc_f64_u (struct.get $cell $f (local.get $c))))
  (func (export "probes") (result i32) (local $p i32) (local.set $p (global.get $probes)) (global.set $probes (i32.const 0)) (local.get $p))
)
