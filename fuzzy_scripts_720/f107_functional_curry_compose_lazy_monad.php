<?php
// 极度混搭: 函数式编程 + 柯里化 + 组合 + 惰性求值 + Monad
echo "=== f107: Functional + Curry + Compose + Lazy + Monad ===\n";

class F {
    public static function curry(callable $fn): callable {
        $ref = new ReflectionFunction($fn);
        $arity = $ref->getNumberOfParameters();
        $curried = function(...$args) use (&$curried, $fn, $arity) {
            if (count($args) >= $arity) return $fn(...$args);
            return fn(...$more) => $curried(...array_merge($args, $more));
        };
        return $curried;
    }

    public static function compose(callable ...$fns): callable {
        return fn($x) => array_reduce(array_reverse($fns), fn($carry, $fn) => $fn($carry), $x);
    }

    public static function pipe(callable ...$fns): callable {
        return fn($x) => array_reduce($fns, fn($carry, $fn) => $fn($carry), $x);
    }

    public static function memoize(callable $fn): callable {
        $cache = [];
        return function(...$args) use ($fn, &$cache) {
            $key = serialize($args);
            if (!isset($cache[$key])) $cache[$key] = $fn(...$args);
            return $cache[$key];
        };
    }

    public static function partial(callable $fn, ...$args): callable {
        return fn(...$more) => $fn(...array_merge($args, $more));
    }

    public static function map(callable $fn, array $list): array { return array_map($fn, $list); }
    public static function filter(callable $fn, array $list): array { return array_values(array_filter($list, $fn)); }
    public static function reduce(callable $fn, array $list, mixed $initial = null): mixed { return array_reduce($list, $fn, $initial); }

    public static function flatMap(callable $fn, array $list): array {
        $result = [];
        foreach ($list as $item) $result = array_merge($result, $fn($item));
        return $result;
    }

    public static function zip(array ...$arrays): array {
        $result = [];
        $min = min(array_map('count', $arrays));
        for ($i = 0; $i < $min; $i++) {
            $tuple = [];
            foreach ($arrays as $arr) $tuple[] = $arr[$i];
            $result[] = $tuple;
        }
        return $result;
    }

    public static function chunk(array $list, int $size): array {
        return array_chunk($list, $size);
    }

    public static function take(array $list, int $n): array { return array_slice($list, 0, $n); }
    public static function drop(array $list, int $n): array { return array_slice($list, $n); }
}

class LazySeq {
    private array $buffer = [];
    private int $position = 0;
    private bool $exhausted = false;

    public function __construct(private \Generator $gen) {}

    public function next(): mixed {
        if ($this->exhausted) return null;
        if (!$this->gen->valid()) { $this->exhausted = true; return null; }
        $val = $this->gen->current();
        $this->buffer[] = $val;
        $this->gen->next();
        return $val;
    }

    public function take(int $n): array {
        $result = [];
        // 从buffer取
        while (count($result) < $n && $this->position < count($this->buffer)) {
            $result[] = $this->buffer[$this->position++];
        }
        // 从generator取
        while (count($result) < $n && !$this->exhausted) {
            $val = $this->next();
            if ($val === null && $this->exhausted) break;
            $result[] = $val;
        }
        return $result;
    }

    public function filter(callable $fn): self {
        $gen = $this->gen;
        $newGen = (function() use ($gen, $fn) {
            foreach ($gen as $val) {
                if ($fn($val)) yield $val;
            }
        })();
        return new self($newGen);
    }

    public function map(callable $fn): self {
        $gen = $this->gen;
        $newGen = (function() use ($gen, $fn) {
            foreach ($gen as $val) yield $fn($val);
        })();
        return new self($newGen);
    }
}

class Maybe {
    private function __construct(private mixed $value) {}
    public static function just(mixed $v): self { return new self($v); }
    public static function nothing(): self { return new self(null); }

    public static function from(mixed $v): self {
        return $v === null ? self::nothing() : self::just($v);
    }

    public function map(callable $fn): self {
        return $this->value === null ? $this : self::just($fn($this->value));
    }

    public function flatMap(callable $fn): self {
        return $this->value === null ? $this : $fn($this->value);
    }

    public function getOrElse(mixed $default): mixed {
        return $this->value ?? $default;
    }

    public function isJust(): bool { return $this->value !== null; }
    public function isNothing(): bool { return $this->value === null; }
    public function get(): mixed { return $this->value; }
}

class Either {
    private function __construct(private bool $isRight, private mixed $value) {}
    public static function right(mixed $v): self { return new self(true, $v); }
    public static function left(mixed $v): self { return new self(false, $v); }

    public function map(callable $fn): self {
        return $this->isRight ? self::right($fn($this->value)) : $this;
    }

    public function flatMap(callable $fn): self {
        return $this->isRight ? $fn($this->value) : $this;
    }

    public function getOrElse(mixed $default): mixed {
        return $this->isRight ? $this->value : $default;
    }

    public function isRight(): bool { return $this->isRight; }
    public function isLeft(): bool { return !$this->isRight; }
    public function get(): mixed { return $this->value; }
}

// 测试
echo "--- Currying ---\n";
$add = fn($a, $b, $c) => $a + $b + $c;
$curriedAdd = F::curry($add);
echo "add(1,2,3) = " . $add(1, 2, 3) . "\n";
echo "curriedAdd(1)(2)(3) = " . $curriedAdd(1)(2)(3) . "\n";
echo "curriedAdd(1,2)(3) = " . $curriedAdd(1, 2)(3) . "\n";

echo "\n--- Composition ---\n";
$addOne = fn($x) => $x + 1;
$double = fn($x) => $x * 2;
$square = fn($x) => $x * $x;

$composed = F::compose($square, $double, $addOne);
echo "compose(square, double, addOne)(3) = " . $composed(3) . " (= (3+1)*2)^2 = 64)\n";

$piped = F::pipe($addOne, $double, $square);
echo "pipe(addOne, double, square)(3) = " . $piped(3) . " (= ((3+1)*2)^2 = 64)\n";

echo "\n--- Partial Application ---\n";
$addTen = F::partial(fn($a, $b) => $a + $b, 10);
echo "addTen(5) = " . $addTen(5) . "\n";

echo "\n--- Map/Filter/Reduce ---\n";
$nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
$squared = F::map(fn($x) => $x * $x, $nums);
echo "map: " . json_encode($squared) . "\n";
$evens = F::filter(fn($x) => $x % 2 === 0, $nums);
echo "filter: " . json_encode($evens) . "\n";
$sum = F::reduce(fn($carry, $x) => $carry + $x, $nums, 0);
echo "reduce sum: $sum\n";
$product = F::reduce(fn($carry, $x) => $carry * $x, $nums, 1);
echo "reduce product: $product\n";

echo "\n--- FlatMap ---\n";
$doubled = F::flatMap(fn($x) => [$x, $x * 10], [1, 2, 3]);
echo "flatMap: " . json_encode($doubled) . "\n";

echo "\n--- Zip ---\n";
$zipped = F::zip([1, 2, 3], ['a', 'b', 'c'], [true, false, true]);
echo "zip: " . json_encode($zipped) . "\n";

echo "\n--- Chunk/Take/Drop ---\n";
echo "chunk([1..10], 3): " . json_encode(F::chunk(range(1, 10), 3)) . "\n";
echo "take([1..10], 3): " . json_encode(F::take(range(1, 10), 3)) . "\n";
echo "drop([1..10], 7): " . json_encode(F::drop(range(1, 10), 7)) . "\n";

echo "\n--- Memoization ---\n";
$callCount = 0;
$slowFn = F::memoize(function($n) use (&$callCount) {
    $callCount++;
    $result = 1;
    for ($i = 2; $i <= $n; $i++) $result *= $i;
    return $result;
});
echo "fact(5) = " . $slowFn(5) . " (calls=$callCount)\n";
echo "fact(5) = " . $slowFn(5) . " (calls=$callCount, cached)\n";
echo "fact(6) = " . $slowFn(6) . " (calls=$callCount)\n";

echo "\n--- Maybe Monad ---\n";
$user = ['name' => 'Alice', 'address' => ['city' => 'NYC']];
$getName = fn($u) => Maybe::from($u['name'] ?? null);
$upper = fn($s) => strtoupper($s);

$result = Maybe::from($user)->map(fn($u) => $u['name'])->map($upper);
echo "Name: " . $result->get() . "\n";

$result2 = Maybe::from($user['missing'] ?? null)->map($upper);
echo "Missing: " . $result2->getOrElse('N/A') . "\n";

echo "\n--- Either Monad ---\n";
$divide = fn($a, $b) => $b === 0 ? Either::left('Division by zero') : Either::right($a / $b);
$r1 = $divide(10, 2)->map(fn($x) => $x * 3);
echo "10/2*3 = " . $r1->getOrElse('error') . "\n";
$r2 = $divide(10, 0)->map(fn($x) => $x * 3);
echo "10/0*3 = " . $r2->getOrElse('error: ' . ($r2->isLeft() ? $r2->get() : '')) . "\n";

echo "\n--- Pipeline Example ---\n";
$processNumbers = F::pipe(
    fn($arr) => F::filter(fn($x) => $x > 3, $arr),
    fn($arr) => F::map(fn($x) => $x * 2, $arr),
    fn($arr) => F::reduce(fn($c, $x) => $c + $x, $arr, 0)
);
echo "processNumbers([1..10]) = " . $processNumbers(range(1, 10)) . "\n";

echo "=== f107 Done ===\n";
