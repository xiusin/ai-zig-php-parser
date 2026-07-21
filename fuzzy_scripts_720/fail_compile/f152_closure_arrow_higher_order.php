<?php
// 闭包深入：箭头函数、高阶函数、柯里化、偏应用、记忆化
echo "=== f152: Closures + Arrow Functions + Higher-Order ===\n";

// 柯里化
function curry(callable $fn): callable {
    $ref = new ReflectionFunction($fn);
    $params = $ref->getNumberOfParameters();

    $build = function(array $args) use (&$build, $fn, $params): callable {
        return function(...$more) use ($build, $fn, $params, $args) {
            $all = array_merge($args, $more);
            if (count($all) >= $params) {
                return $fn(...$all);
            }
            return $build($all);
        };
    };

    return $build([]);
}

// 记忆化
function memoize(callable $fn): callable {
    $cache = [];
    return function(...$args) use (&$cache, $fn): mixed {
        $key = serialize($args);
        if (!isset($cache[$key])) {
            $cache[$key] = $fn(...$args);
        }
        return $cache[$key];
    };
}

// 偏应用
function partial(callable $fn, ...$fixed): callable {
    return function(...$args) use ($fn, $fixed): mixed {
        return $fn(...$fixed, ...$args);
    };
}

// 函数组合
function compose(callable ...$fns): callable {
    return function(mixed $value) use ($fns): mixed {
        $result = $value;
        foreach (array_reverse($fns) as $fn) {
            $result = $fn($result);
        }
        return $result;
    };
}

// 管道
function pipe(callable ...$fns): callable {
    return function(mixed $value) use ($fns): mixed {
        $result = $value;
        foreach ($fns as $fn) {
            $result = $fn($result);
        }
        return $result;
    };
}

// 测试
echo "--- Currying ---\n";
$add = fn($a, $b, $c) => $a + $b + $c;
$curriedAdd = curry($add);
echo "  add(1,2,3) = " . $add(1, 2, 3) . "\n";
echo "  curried(1)(2)(3) = " . $curriedAdd(1)(2)(3) . "\n";
echo "  curried(1,2)(3) = " . $curriedAdd(1, 2)(3) . "\n";

$multiply = fn($a, $b) => $a * $b;
$curriedMul = curry($multiply);
echo "  mul(3,4) = " . $multiply(3, 4) . "\n";
echo "  curried(3)(4) = " . $curriedMul(3)(4) . "\n";

echo "\n--- Memoization ---\n";
$callCount = 0;
$slowSquare = function(int $n) use (&$callCount): int {
    $callCount++;
    return $n * $n;
};
$memoSquare = memoize($slowSquare);
echo "  memo(5) = " . $memoSquare(5) . " (calls: $callCount)\n";
echo "  memo(5) = " . $memoSquare(5) . " (calls: $callCount)\n";
echo "  memo(6) = " . $memoSquare(6) . " (calls: $callCount)\n";
echo "  memo(5) = " . $memoSquare(5) . " (calls: $callCount)\n";

echo "\n--- Partial Application ---\n";
$addThen = fn($a, $b, $c) => $a + $b * $c;
$add10 = partial($addThen, 10);
echo "  partial(10)(2,3) = " . $add10(2, 3) . "\n";
$add10Mul2 = partial($addThen, 10, 2);
echo "  partial(10,2)(3) = " . $add10Mul2(3) . "\n";

echo "\n--- Function Composition ---\n";
$double = fn($x) => $x * 2;
$inc = fn($x) => $x + 1;
$toString = fn($x) => "Value: $x";
$composed = compose($toString, $inc, $double);
echo "  compose(toStr, inc, double)(5) = " . $composed(5) . "\n";

echo "\n--- Pipeline ---\n";
$pipeline = pipe(
    fn($x) => $x + 1,
    fn($x) => $x * 2,
    fn($x) => $x - 3,
    fn($x) => "Result: $x"
);
echo "  pipe(inc, double, dec, toStr)(5) = " . $pipeline(5) . "\n";

echo "\n--- Higher-Order Array Operations ---\n";
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
echo "  Original: " . implode(', ', $numbers) . "\n";
echo "  Evens: " . implode(', ', array_filter($numbers, fn($n) => $n % 2 === 0)) . "\n";
echo "  Squared: " . implode(', ', array_map(fn($n) => $n * $n, $numbers)) . "\n";
echo "  Sum: " . array_sum($numbers) . "\n";
echo "  Product: " . array_reduce($numbers, fn($c, $i) => $c * $i, 1) . "\n";

echo "\n--- Arrow Function Chains ---\n";
$result = collect([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    ->filter(fn($n) => $n % 2 === 0)
    ->map(fn($n) => $n * $n)
    ->reduce(fn($c, $n) => $c + $n, 0);
echo "  Sum of even squares (1-10): $result\n";

function collect(array $items): FuncCollection {
    return new FuncCollection($items);
}
class FuncCollection {
    private array $items;
    public function __construct(array $items) { $this->items = $items; }
    public function filter(callable $fn): self {
        return new self(array_filter($this->items, $fn));
    }
    public function map(callable $fn): self {
        return new self(array_map($fn, $this->items));
    }
    public function reduce(callable $fn, mixed $initial = null): mixed {
        return array_reduce($this->items, $fn, $initial);
    }
}

echo "\n--- Closure Variables ---\n";
$counter = (function() {
    $count = 0;
    return [
        'inc' => function() use (&$count) { return ++$count; },
        'dec' => function() use (&$count) { return --$count; },
        'get' => function() use (&$count) { return $count; },
        'reset' => function() use (&$count) { $count = 0; },
    ];
})();
echo "  inc: " . $counter['inc']() . "\n";
echo "  inc: " . $counter['inc']() . "\n";
echo "  inc: " . $counter['inc']() . "\n";
echo "  get: " . $counter['get']() . "\n";
echo "  dec: " . $counter['dec']() . "\n";
echo "  get: " . $counter['get']() . "\n";
$counter['reset']();
echo "  reset, get: " . $counter['get']() . "\n";

echo "=== f152 Done ===\n";
