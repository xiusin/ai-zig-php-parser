<?php
// 测试80: 偏函数应用与柯里化

// 基础偏函数
function partial(callable $fn, ...$args): callable {
    return function(...$moreArgs) use ($fn, $args) {
        return $fn(...$args, ...$moreArgs);
    };
}

function add($a, $b, $c) {
    return $a + $b + $c;
}

$add5 = partial('add', 5);
$add5and10 = partial($add5, 10);
echo "add(5, 10, 3): " . $add5and10(3) . "
";

// 柯里化
function curry(callable $fn): callable {
    return function(...$args) use ($fn) {
        if (count($args) >= (new ReflectionFunction($fn))->getNumberOfRequiredParameters()) {
            return $fn(...$args);
        }
        return curry(function(...$moreArgs) use ($fn, $args) {
            return $fn(...$args, ...$moreArgs);
        });
    };
}

$curriedAdd = curry(function($a, $b, $c) {
    return $a + $b + $c;
});

echo "Curried: " . $curriedAdd(1)(2)(3) . "
";
echo "Partial: " . $curriedAdd(1, 2)(3) . "
";

// 管道操作
$pipe = fn(...$fns) => fn($x) => array_reduce($fns, fn($v, $f) => $f($v), $x);

$process = $pipe(
    fn($x) => $x + 1,
    fn($x) => $x * 2,
    fn($x) => $x ** 2
);
echo "Pipeline (3+1)*2^2: " . $process(3) . "
";

// 组合函数
$compose = fn(...$fns) => fn($x) => array_reduce(array_reverse($fns), fn($v, $f) => $f($v), $x);

$composed = $compose(
    fn($x) => $x + 1,
    fn($x) => $x * 2,
    fn($x) => $x ** 2
);
echo "Composed (3^2)*2+1: " . $composed(3) . "
";

// 函数装饰器
function memoize(callable $fn): callable {
    $cache = [];
    return function(...$args) use ($fn, &$cache) {
        $key = serialize($args);
        return $cache[$key] ??= $fn(...$args);
    };
}

$fib = memoize(function($n) use (&$fib) {
    return $n < 2 ? $n : $fib($n - 1) + $fib($n - 2);
});

echo "Fibonacci 30: " . $fib(30) . "
";
echo "Fibonacci 35: " . $fib(35) . "
";

// 延迟求值
function lazy(callable $fn): object {
    return new class($fn) {
        private $value;
        private $evaluated = false;
        private $fn;
        
        public function __construct(callable $fn) {
            $this->fn = $fn;
        }
        
        public function get() {
            if (!$this->evaluated) {
                $this->value = ($this->fn)();
                $this->evaluated = true;
            }
            return $this->value;
        }
    };
}

$lazyValue = lazy(fn() => {
    echo "Computing...";
    return 42;
});
echo "Not computed yet
";
echo "Value: " . $lazyValue->get() . "
";
echo "Value again: " . $lazyValue->get() . "
";
?>