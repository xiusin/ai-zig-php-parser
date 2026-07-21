<?php
// 极度混搭: 闭包高级特性 + use引用 + 高阶函数 + 柯里化 + 部分应用 + 组合
echo "=== f047: Closures Advanced + Currying + Composition ===\n";

class Functional {
    public static function curry(callable $fn): callable {
        $ref = new \ReflectionFunction($fn);
        $numArgs = $ref->getNumberOfParameters();

        $curried = function(...$args) use ($fn, $numArgs, &$curried) {
            if (count($args) >= $numArgs) {
                return $fn(...$args);
            }
            return function(...$more) use ($args, &$curried) {
                return $curried(...array_merge($args, $more));
            };
        };
        return $curried;
    }

    public static function partial(callable $fn, ...$fixedArgs): callable {
        return function(...$args) use ($fn, $fixedArgs) {
            return $fn(...array_merge($fixedArgs, $args));
        };
    }

    public static function compose(callable ...$fns): callable {
        return function($value) use ($fns) {
            for ($i = count($fns) - 1; $i >= 0; $i--) {
                $value = $fns[$i]($value);
            }
            return $value;
        };
    }

    public static function pipe(callable ...$fns): callable {
        return function($value) use ($fns) {
            foreach ($fns as $fn) $value = $fn($value);
            return $value;
        };
    }

    public static function memoize(callable $fn): callable {
        $cache = [];
        return function() use ($fn, &$cache) {
            $args = func_get_args();
            $key = serialize($args);
            if (!isset($cache[$key])) {
                $cache[$key] = $fn(...$args);
            }
            return $cache[$key];
        };
    }

    public static function debounce(callable $fn, int $delay): callable {
        return function(...$args) use ($fn, $delay) {
            static $lastCall = 0;
            $now = microtime(true);
            if ($now - $lastCall >= $delay / 1000) {
                $lastCall = $now;
                return $fn(...$args);
            }
            return null;
        };
    }

    public static function once(callable $fn): callable {
        $called = false;
        $result = null;
        return function() use ($fn, &$called, &$result) {
            if (!$called) {
                $called = true;
                $result = $fn(...func_get_args());
            }
            return $result;
        };
    }

    public static function throttle(callable $fn, int $limit): callable {
        $calls = [];
        return function() use ($fn, $limit, &$calls) {
            $now = microtime(true);
            $calls = array_filter($calls, fn($t) => $t > $now - $limit);
            if (count($calls) < $limit) {
                $calls[] = $now;
                return $fn(...func_get_args());
            }
            return null;
        };
    }
}

// 测试
echo "--- Curry ---\n";
$add = fn($a, $b, $c) => $a + $b + $c;
$curriedAdd = Functional::curry($add);
echo "add(1,2,3) = " . $add(1, 2, 3) . "\n";
echo "curried(1)(2)(3) = " . $curriedAdd(1)(2)(3) . "\n";
echo "curried(1,2)(3) = " . $curriedAdd(1, 2)(3) . "\n";
echo "curried(1)(2,3) = " . $curriedAdd(1)(2, 3) . "\n";

echo "\n--- Partial Application ---\n";
$multiply = fn($a, $b, $c) => $a * $b * $c;
$double = Functional::partial($multiply, 2);
$triple = Functional::partial($multiply, 2, 3);
echo "multiply(2,3,4) = " . $multiply(2, 3, 4) . "\n";
echo "partial(2)(3,4) = " . $double(3, 4) . "\n";
echo "partial(2,3)(4) = " . $triple(4) . "\n";

echo "\n--- Compose ---\n";
$toUpper = fn($s) => strtoupper($s);
$reverse = fn($s) => strrev($s);
$addExclaim = fn($s) => $s . '!';
$composed = Functional::compose($addExclaim, $toUpper, $reverse);
echo "compose(reverse, upper, exclaim)('hello') = " . $composed('hello') . "\n";

echo "\n--- Pipe ---\n";
$piped = Functional::pipe($reverse, $toUpper, $addExclaim);
echo "pipe(reverse, upper, exclaim)('hello') = " . $piped('hello') . "\n";

echo "\n--- Memoize ---\n";
$callCount = 0;
$expensive = Functional::memoize(function($n) use (&$callCount) {
    $callCount++;
    $result = 1;
    for ($i = 2; $i <= $n; $i++) $result *= $i;
    return $result;
});
echo "memo(5) = " . $expensive(5) . " (calls=$callCount)\n";
echo "memo(5) = " . $expensive(5) . " (calls=$callCount)\n";
echo "memo(10) = " . $expensive(10) . " (calls=$callCount)\n";
echo "memo(5) = " . $expensive(5) . " (calls=$callCount)\n";

echo "\n--- Once ---\n";
$initCount = 0;
$initialize = Functional::once(function() use (&$initCount) {
    $initCount++;
    return "initialized";
});
echo "once() = " . $initialize() . " (count=$initCount)\n";
echo "once() = " . $initialize() . " (count=$initCount)\n";
echo "once() = " . $initialize() . " (count=$initCount)\n";

echo "\n--- Closure use (&) ---\n";
$counter = 0;
$inc = function() use (&$counter) { return ++$counter; };
$dec = function() use (&$counter) { return --$counter; };
echo "inc: " . $inc() . "\n";
echo "inc: " . $inc() . "\n";
echo "inc: " . $inc() . "\n";
echo "dec: " . $dec() . "\n";
echo "counter: $counter\n";

echo "\n--- Higher-order: map/filter/reduce with closures ---\n";
$nums = range(1, 10);
$squaredEvens = array_values(array_filter(
    array_map(fn($n) => $n * $n, $nums),
    fn($n) => $n % 2 === 0
));
echo "squaredEvens(1-10): " . implode(', ', $squaredEvens) . "\n";

$sum = array_reduce($nums, fn($acc, $n) => $acc + $n, 0);
echo "sum(1-10): $sum\n";

echo "=== f047 Done ===\n";
