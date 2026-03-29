<?php
// Test 044: Arrow functions, fn() =>, and closures
class ArrowLab {
    public function process(): string {
        $out = "";

        $simple = fn() => 42;
        $out .= "fn() => 42: " . $simple() . "\n";

        $add = fn(int $a, int $b) => $a + $b;
        $out .= "fn(\$a, \$b) => \$a + \$b, (5, 3): " . $add(5, 3) . "\n";

        $capture = 10;
        $captured = fn(int $x) => $x + $capture;
        $out .= "Captured \$capture=10, fn(\$x) => \$x + \$capture, (5): " . $captured(5) . "\n";

        $closure = function(int $x) use ($capture) {
            return $x + $capture;
        };
        $out .= "Equivalent closure, (5): " . $closure(5) . "\n";

        $arrowArray = array_map(fn($x) => $x * 2, [1, 2, 3, 4, 5]);
        $out .= "array_map arrow, [1,2,3,4,5] * 2: " . implode(',', $arrowArray) . "\n";

        $arrowFilter = array_filter([1, 2, 3, 4, 5, 6], fn($x) => $x % 2 === 0);
        $out .= "array_filter arrow, evens: " . implode(',', $arrowFilter) . "\n";

        $arrowReduce = array_reduce([1, 2, 3, 4], fn($carry, $item) => $carry + $item, 0);
        $out .= "array_reduce arrow, sum: " . $arrowReduce . "\n";

        return $out;
    }

    public function chainArrow(): string {
        $out = "";

        $numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

        $result = array_values(
            array_filter(
                array_map(fn($x) => $x * 2, $numbers),
                fn($x) => $x > 5
            )
        );

        $out .= "Chain: map(*2), filter(>5): " . implode(',', $result) . "\n";

        $chained = (fn($arr) =>
            array_values(
                array_filter($arr, fn($x) => $x > 5)
            )
        )([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

        $out .= "Single arrow chain: " . implode(',', $chained) . "\n";

        return $out;
    }

    public function arrowWithObjects(): string {
        $out = "";

        $obj = new class {
            public int $value = 100;
        };

        $getValue = fn() => $obj->value;
        $setValue = fn(int $v) => $obj->value = $v;

        $out .= "Arrow get obj->value: " . $getValue() . "\n";
        $setValue(200);
        $out .= "After setValue(200), get: " . $getValue() . "\n";

        return $out;
    }
}

echo "=== Arrow Functions Lab ===\n";
$lab = new ArrowLab();
echo $lab->process();

echo "\n=== Arrow chaining ===\n";
echo $lab->chainArrow();

echo "\n=== Arrow with objects ===\n";
echo $lab->arrowWithObjects();

echo "\n=== Arrow functions as callbacks ===\n";
$callbacks = [
    'double' => fn($x) => $x * 2,
    'square' => fn($x) => $x * $x,
    'negate' => fn($x) => -$x,
];

foreach ($callbacks as $name => $cb) {
    echo "$name(5): " . $cb(5) . "\n";
}

echo "\n=== Arrow returning array ===\n";
$pair = fn($a, $b) => [$a, $b];
$result = $pair('first', 'second');
echo "Pair result: " . json_encode($result) . "\n";

echo "\n=== Arrow with spread ===\n";
$apply = fn(callable $fn, ...$args) => $fn(...$args);
echo "apply(fn(\$a,\$b) => \$a+\$b, 10, 20): " . $apply(fn($a, $b) => $a + $b, 10, 20) . "\n";