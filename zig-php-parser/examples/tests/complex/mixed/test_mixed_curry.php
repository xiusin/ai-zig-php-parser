<?php
function curry($callback, $arity = null) {
    if ($arity === null) {
        $arity = (new ReflectionFunction($callback))->getNumberOfParameters();
    }

    return function use ($callback, $arity) {
        return function(...$args) use ($callback, $arity, $args) {
            if (count($args) >= $arity) {
                return $callback(...$args);
            }
            return curry(fn(...$more) => $callback(...$args, ...$more), $arity - count($args));
        };
    }();
}

$add = curry(fn($a, $b, $c) => $a + $b + $c);

$add5 = $add(5);
$add5and10 = $add5(10);
$result = $add5and10(3);

echo "curry(add)(5)(10)(3) = $result\n";
