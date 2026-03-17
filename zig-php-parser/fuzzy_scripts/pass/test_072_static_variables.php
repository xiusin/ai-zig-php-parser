<?php
// 测试72: 静态变量与递归函数中的静态变量
function counter() {
    static $count = 0;
    return ++$count;
}

function fibonacciStatic(int $n): int {
    static $cache = [];
    if (isset($cache[$n])) return $cache[$n];
    if ($n < 2) return $n;
    $cache[$n] = fibonacciStatic($n - 1) + fibonacciStatic($n - 2);
    return $cache[$n];
}

class StaticExample {
    private static $instanceCount = 0;
    private $id;
    
    public function __construct() {
        $this->id = ++self::$instanceCount;
    }
    
    public static function getCount(): int {
        return self::$instanceCount;
    }
}

echo "Counter: " . counter() . " " . counter() . " " . counter() . "
";
echo "Fibonacci 10: " . fibonacciStatic(10) . "
";
echo "Fibonacci 20: " . fibonacciStatic(20) . "
";
echo "Instances: " . StaticExample::getCount() . "
";
$obj1 = new StaticExample();
$obj2 = new StaticExample();
echo "After 2 instances: " . StaticExample::getCount() . "
";
?>