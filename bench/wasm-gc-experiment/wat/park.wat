;; Suspension through the stack-switching proposal: a generator suspends on
;; a control tag n times, the driver resumes it each time.
(module
  (type $ft (func))
  (type $ct (cont $ft))
  (tag $yield)
  (global $count (mut i64) (i64.const 0))
  (func $gen
    (block $done (loop $l
      (br_if $done (i64.le_s (global.get $count) (i64.const 0)))
      (global.set $count (i64.sub (global.get $count) (i64.const 1)))
      (suspend $yield)
      (br $l))))
  (elem declare func $gen)
  (func (export "park") (param $n i64) (result i64)
    (local $k (ref null $ct)) (local $resumes i64)
    (global.set $count (local.get $n))
    (local.set $k (cont.new $ct (ref.func $gen)))
    (block $finished
      (loop $drive
        (block $on_yield (result (ref $ct))
          (resume $ct (on $yield $on_yield) (local.get $k))
          (br $finished))
        (local.set $k)
        (local.set $resumes (i64.add (local.get $resumes) (i64.const 1)))
        (br $drive)))
    (local.get $resumes))
)
