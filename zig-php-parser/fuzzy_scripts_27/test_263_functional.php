<?php
function tap(mixed $value, callable $fn): mixed {
    $fn($value);
    return $value;
}

function pipe(mixed $value, callable ...$fns): mixed {
    foreach ($fns as $fn) {
        $value = $fn($value);
    }
    return $value;
}

function spread(callable $fn, array $args): mixed {
    return $fn(...$args);
}

function juxt(callable ...$fns): callable {
    return function(...$args) use ($fns) {
        return array_map(fn($fn) => $fn(...$args), $fns);
    };
}

$result = tap(10, fn($v) => print_r("Tapped: $v\n"));
echo $result . "\n";

$result = pipe(5, fn($x) => $x * 2, fn($x) => $x + 10);
echo $result . "\n";

$result = spread(fn($a, $b, $c) => $a + $b + $c, [1, 2, 3]);
echo $result . "\n";

$operations = juxt(fn($x) => $x * 2, fn($x) => $x + 10, fn($x) => $x ** 2);
echo implode(',', $operations(5)) . "\n";
echo "OK\n";
