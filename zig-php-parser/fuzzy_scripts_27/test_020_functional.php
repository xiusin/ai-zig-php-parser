<?php
// Test 020: Functional programming, callbacks, and higher-order functions
class FunctionalLab {
    public function pipeline(mixed ...$funcs): Closure {
        return function(mixed $initial) use ($funcs): mixed {
            $result = $initial;
            foreach ($funcs as $func) {
                $result = $func($result);
            }
            return $result;
        };
    }

    public function compose(mixed ...$funcs): Closure {
        return function(mixed $initial) use ($funcs): mixed {
            $result = $initial;
            for ($i = count($funcs) - 1; $i >= 0; $i--) {
                $result = $funcs[$i]($result);
            }
            return $result;
        };
    }

    public function curry(callable $fn, int $arity): Closure {
        return function(mixed ...$args) use ($fn, $arity) {
            if (count($args) >= $arity) {
                return $fn(...$args);
            }
            return function(mixed ...$more) use ($fn, $args, $arity) {
                return $fn(...$args, ...$more);
            };
        };
    }

    public function memoize(callable $fn): Closure {
        $cache = [];
        return function(mixed ...$args) use (&$cache, $fn): mixed {
            $key = json_encode($args);
            if (!isset($cache[$key])) {
                $cache[$key] = $fn(...$args);
            }
            return $cache[$key];
        };
    }
}

echo "=== Pipeline ===\n";
$lab = new FunctionalLab();
$pipeline = $lab->pipeline(
    fn($x) => $x * 2,
    fn($x) => $x + 10,
    fn($x) => "Result: $x"
);
echo $pipeline(5) . "\n";

echo "\n=== Compose ===\n";
$compose = $lab->compose(
    fn($x) => $x * 2,
    fn($x) => $x + 10,
    fn($x) => $x - 5
);
echo "compose((x-5), (x+10), (x*2)) applied to 5: " . $compose(5) . "\n";

echo "\n=== Curry ===\n";
$add = fn(int $a, int $b, int $c) => $a + $b + $c;
$curriedAdd = $lab->curry($add, 3);
$step1 = $curriedAdd(1);
$step2 = $step1(2);
$result = $step2(3);
echo "Curried add(1)(2)(3): $result\n";

echo "\n=== Memoize ===\n";
$computations = 0;
$expensive = $lab->memoize(function(int $n) use (&$computations): int {
    $computations++;
    return $n * $n;
});

echo "First call expensive(5): " . $expensive(5) . " (computations: $computations)\n";
echo "Second call expensive(5): " . $expensive(5) . " (computations: $computations)\n";
echo "Call expensive(6): " . $expensive(6) . " (computations: $computations)\n";

echo "\n=== Array functions with callbacks ===\n";
$data = [
    ['name' => 'Alice', 'age' => 30, 'city' => 'NYC'],
    ['name' => 'Bob', 'age' => 25, 'city' => 'LA'],
    ['name' => 'Charlie', 'age' => 35, 'city' => 'NYC'],
];

$names = array_column($data, 'name');
echo "array_column names: " . implode(', ', $names) . "\n";

$ages = array_column($data, 'age');
echo "array_column ages sum: " . array_sum($ages) . "\n";

$keyed = array_column($data, null, 'name');
echo "array_column keyed by name: " . implode(', ', array_keys($keyed)) . "\n";

$sorted = array_values(array_column($data, 'name', 'name'));
sort($sorted);
echo "Sorted names: " . implode(', ', $sorted) . "\n";

echo "\n=== Array multisort ===\n";
$items = [
    ['name' => 'Apple', 'price' => 3],
    ['name' => 'Banana', 'price' => 1],
    ['name' => 'Cherry', 'price' => 2],
];

$prices = array_column($items, 'price');
$names = array_column($items, 'name');
array_multisort($prices, SORT_DESC, $names, SORT_ASC, $items);
echo "Sorted by price desc, name asc:\n";
foreach ($items as $item) {
    echo "  {$item['name']}: {$item['price']}\n";
}

echo "\n=== Array walk recursive ===\n";
$nested = [1, [2, [3, [4]]]];
$result = [];
array_walk_recursive($nested, function($v, $k) use (&$result) {
    $result[] = $v;
});
echo "Flattened: " . implode(',', $result) . "\n";