<?php
// 闭包高级特性测试

// 自动绑定$this
class Counter {
    private int $count = 0;

    public function getIncrementer(): Closure {
        return function() {
            return ++$this->count;
        };
    }

    public function getCount(): int {
        return $this->count;
    }
}

$counter = new Counter();
$incrementer = $counter->getIncrementer();
echo "First increment: " . $incrementer() . "\n";
echo "Second increment: " . $incrementer() . "\n";
echo "Counter count: " . $counter->getCount() . "\n";

// Closure::bind 创建新绑定
class Value {
    private $value;

    public function __construct($value) {
        $this->value = $value;
    }
}

$getPrivate = function() {
    return $this->value;
};

$value = new Value('secret');
$boundClosure = Closure::bind($getPrivate, $value, Value::class);
echo "Private value: " . $boundClosure() . "\n";

// bindTo 链式调用
class Multiplier {
    private int $factor = 2;

    public function getFactor(): int {
        return $this->factor;
    }
}

$getFactor = function() {
    return $this->factor;
};

$multiplier = new Multiplier();
$boundGetFactor = $getFactor->bindTo($multiplier, Multiplier::class);
echo "Bound factor: " . $boundGetFactor() . "\n";

// call 方法直接调用
$result = $getPrivate->call($value);
echo "call result: $result\n";

// fromCallable 转换
function addNumbers(int $a, int $b): int {
    return $a + $b;
}

$addClosure = Closure::fromCallable('addNumbers');
echo "fromCallable: " . $addClosure(3, 4) . "\n";

// 静态闭包
$staticClosure = static function() {
    return "static closure";
};
echo $staticClosure() . "\n";

// 闭包作为数组元素
$operations = [
    'add' => fn($a, $b) => $a + $b,
    'sub' => fn($a, $b) => $a - $b,
    'mul' => fn($a, $b) => $a * $b,
    'div' => fn($a, $b) => $a / $b,
];

echo "add: " . $operations['add'](5, 3) . "\n";
echo "mul: " . $operations['mul'](5, 3) . "\n";

// 闭包柯里化
function curry(callable $fn, ...$args): Closure {
    return function(...$moreArgs) use ($fn, $args) {
        $allArgs = array_merge($args, $moreArgs);
        $ref = new ReflectionFunction($fn);
        if (count($allArgs) >= $ref->getNumberOfRequiredParameters()) {
            return $fn(...$allArgs);
        }
        return curry($fn, ...$allArgs);
    };
}

$add3 = fn($a, $b, $c) => $a + $b + $c;
$curriedAdd = curry($add3);
$step1 = $curriedAdd(1);
$step2 = $step1(2);
echo "Curried result: " . $step2(3) . "\n";

// 闭包记忆化
function memoize(callable $fn): Closure {
    $cache = [];
    return function($arg) use ($fn, &$cache) {
        if (!array_key_exists($arg, $cache)) {
            $cache[$arg] = $fn($arg);
        }
        return $cache[$arg];
    };
}

$slowSquare = function($n) {
    return $n * $n;
};

$fastSquare = memoize($slowSquare);
echo "Memoized 1: " . $fastSquare(5) . "\n";
echo "Memoized 2 (cached): " . $fastSquare(5) . "\n";

// 闭包组合
function compose(callable ...$functions): Closure {
    return function($value) use ($functions) {
        return array_reduce(
            $functions,
            fn($carry, $fn) => $fn($carry),
            $value
        );
    };
}

$double = fn($x) => $x * 2;
$addOne = fn($x) => $x + 1;
$toString = fn($x) => "Result: $x";

$composed = compose($double, $addOne, $toString);
echo "Composed: " . $composed(5) . "\n";

echo "Advanced closures tests completed\n";
