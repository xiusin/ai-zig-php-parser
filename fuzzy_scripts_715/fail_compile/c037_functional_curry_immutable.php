<?php
// 极度混搭: 函数式编程 + 柯里化 + 模式匹配 + 不可变数据 + 尾递归
echo "=== c037: Functional Programming + Curry + Pattern + Immutable ===\n\n";

class FP {
    public static function compose(callable ...$fns): callable {
        return function($x) use ($fns) {
            return array_reduce(
                array_reverse($fns),
                fn($acc, $fn) => $fn($acc),
                $x
            );
        };
    }

    public static function pipe(callable ...$fns): callable {
        return function($x) use ($fns) {
            return array_reduce($fns, fn($acc, $fn) => $fn($acc), $x);
        };
    }

    public static function curry(callable $fn, int $arity = null): callable {
        $arity = $arity ?? (new ReflectionFunction($fn))->getNumberOfParameters();
        return function(...$args) use ($fn, $arity) {
            if (count($args) >= $arity) {
                return $fn(...$args);
            }
            return self::curry(function(...$more) use ($fn, $args) {
                return $fn(...array_merge($args, $more));
            }, $arity - count($args));
        };
    }

    public static function partial(callable $fn, ...$args): callable {
        return function(...$more) use ($fn, $args) {
            return $fn(...array_merge($args, $more));
        };
    }

    public static function memoize(callable $fn): callable {
        $cache = [];
        return function($x) use ($fn, &$cache) {
            $key = is_array($x) ? json_encode($x) : (string)$x;
            if (!isset($cache[$key])) {
                $cache[$key] = $fn($x);
            }
            return $cache[$key];
        };
    }

    public static function debounce(callable $fn, int $delay = 0): callable {
        $lastCall = 0;
        $lastResult = null;
        return function(...$args) use ($fn, &$lastCall, &$lastResult, $delay) {
            $now = 1;
            if ($now - $lastCall >= $delay) {
                $lastResult = $fn(...$args);
                $lastCall = $now;
            }
            return $lastResult;
        };
    }

    public static function map(callable $fn, array $list): array {
        return array_map($fn, $list);
    }

    public static function filter(callable $fn, array $list): array {
        return array_values(array_filter($list, $fn));
    }

    public static function reduce(callable $fn, array $list, $initial = null) {
        return array_reduce($list, $fn, $initial);
    }

    public static function flatMap(callable $fn, array $list): array {
        $result = [];
        foreach ($list as $item) {
            $mapped = $fn($item);
            foreach ($mapped as $m) {
                $result[] = $m;
            }
        }
        return $result;
    }

    public static function zip(array ...$arrays): array {
        $result = [];
        $min = min(array_map('count', $arrays));
        for ($i = 0; $i < $min; $i++) {
            $tuple = [];
            foreach ($arrays as $arr) {
                $tuple[] = $arr[$i];
            }
            $result[] = $tuple;
        }
        return $result;
    }

    public static function take(array $list, int $n): array {
        return array_slice($list, 0, $n);
    }

    public static function drop(array $list, int $n): array {
        return array_slice($list, $n);
    }

    public static function chunk(array $list, int $size): array {
        return array_chunk($list, $size);
    }

    public static function range(int $start, int $end, int $step = 1): array {
        $result = [];
        for ($i = $start; $i <= $end; $i += $step) {
            $result[] = $i;
        }
        return $result;
    }

    public static function unfold(callable $fn, $seed, int $limit = 100): array {
        $result = [];
        $current = $seed;
        for ($i = 0; $i < $limit; $i++) {
            $next = $fn($current);
            if ($next === null) break;
            $result[] = $next[0];
            $current = $next[1];
        }
        return $result;
    }
}

class ImmutableList {
    private array $data;

    private function __construct(array $data) {
        $this->data = $data;
    }

    public static function of(array $data): self {
        return new self(array_values($data));
    }

    public static function empty(): self {
        return new self([]);
    }

    public function add(mixed $value): self {
        $new = $this->data;
        $new[] = $value;
        return new self($new);
    }

    public function remove(int $index): self {
        $new = $this->data;
        array_splice($new, $index, 1);
        return new self($new);
    }

    public function map(callable $fn): self {
        return new self(array_map($fn, $this->data));
    }

    public function filter(callable $fn): self {
        return new self(array_values(array_filter($this->data, $fn)));
    }

    public function reduce(callable $fn, $initial = null): mixed {
        return array_reduce($this->data, $fn, $initial);
    }

    public function get(int $index): mixed {
        return $this->data[$index] ?? null;
    }

    public function size(): int {
        return count($this->data);
    }

    public function toArray(): array {
        return $this->data;
    }

    public function concat(ImmutableList $other): self {
        return new self(array_merge($this->data, $other->toArray()));
    }

    public function sort(callable $cmp): self {
        $new = $this->data;
        usort($new, $cmp);
        return new self($new);
    }

    public function reverse(): self {
        return new self(array_reverse($this->data));
    }

    public function slice(int $offset, ?int $length = null): self {
        return new self(array_slice($this->data, $offset, $length));
    }
}

// === 测试 ===

echo "--- Compose & Pipe ---\n";
$double = fn($x) => $x * 2;
$addOne = fn($x) => $x + 1;
$toString = fn($x) => "Result: $x";
$square = fn($x) => $x * $x;

$composed = FP::compose($toString, $addOne, $double, $square);
echo "compose(square, double, addOne, toString)(5) = " . $composed(5) . "\n";

$piped = FP::pipe($square, $double, $addOne, $toString);
echo "pipe(square, double, addOne, toString)(5) = " . $piped(5) . "\n";

echo "\n--- Currying ---\n";
$add = fn($a, $b, $c) => $a + $b + $c;
$curriedAdd = FP::curry($add);

$step1 = $curriedAdd(1);
$step2 = $step1(2);
$result = $step2(3);
echo "curry(add)(1)(2)(3) = $result\n";

$allAtOnce = $curriedAdd(10, 20, 30);
echo "curry(add)(10, 20, 30) = $allAtOnce\n";

echo "\n--- Partial Application ---\n";
$greet = fn($greeting, $name) => "$greeting, $name!";
$sayHello = FP::partial($greet, 'Hello');
echo $sayHello('Alice') . "\n";
echo $sayHello('Bob') . "\n";

echo "\n--- Memoize ---\n";
$callCount = 0;
$slowFn = function($n) use (&$callCount) {
    $callCount++;
    return $n * $n;
};
$memoized = FP::memoize($slowFn);

echo $memoized(5) . "\n";
echo $memoized(5) . "\n";
echo $memoized(6) . "\n";
echo $memoized(5) . "\n";
echo "Total calls: $callCount (should be 2)\n";

echo "\n--- Functional List Operations ---\n";
$nums = FP::range(1, 10);
echo "Range: " . implode(",", $nums) . "\n";

$squared = FP::map(fn($x) => $x * $x, $nums);
echo "Squared: " . implode(",", $squared) . "\n";

$evens = FP::filter(fn($x) => $x % 2 == 0, $nums);
echo "Evens: " . implode(",", $evens) . "\n";

$sum = FP::reduce(fn($acc, $x) => $acc + $x, $nums, 0);
echo "Sum: $sum\n";

$flattened = FP::flatMap(fn($x) => [$x, $x * 10], [1, 2, 3]);
echo "FlatMap: " . implode(",", $flattened) . "\n";

echo "\n--- Unfold ---\n";
$fibonacci = FP::unfold(function($state) {
    [$a, $b] = $state;
    if ($a > 100) return null;
    return [$a, [$b, $a + $b]];
}, [0, 1], 20);
echo "Fibonacci: " . implode(",", $fibonacci) . "\n";

echo "\n--- Immutable List ---\n";
$list = ImmutableList::of([3, 1, 4, 1, 5, 9, 2, 6]);
echo "Original: " . implode(",", $list->toArray()) . " size=" . $list->size() . "\n";

$added = $list->add(10);
echo "After add(10): " . implode(",", $added->toArray()) . "\n";

$mapped = $list->map(fn($x) => $x * 2);
echo "Mapped *2: " . implode(",", $mapped->toArray()) . "\n";

$filtered = $list->filter(fn($x) => $x > 3);
echo "Filtered >3: " . implode(",", $filtered->toArray()) . "\n";

$sorted = $list->sort(fn($a, $b) => $a <=> $b);
echo "Sorted: " . implode(",", $sorted->toArray()) . "\n";

$reversed = $sorted->reverse();
echo "Reversed: " . implode(",", $reversed->toArray()) . "\n";

echo "\nOriginal unchanged: " . implode(",", $list->toArray()) . "\n";

echo "\n--- Zip & Chunk ---\n";
$zipped = FP::zip([1, 2, 3], ['a', 'b', 'c'], [true, false, true]);
foreach ($zipped as $z) {
    echo "  (" . implode(",", array_map(fn($v) => var_export($v, true), $z)) . ")\n";
}

$chunked = FP::chunk(FP::range(1, 10), 3);
foreach ($chunked as $i => $c) {
    echo "  Chunk $i: [" . implode(",", $c) . "]\n";
}

echo "\n=== c037 Done ===\n";
