<?php
// 测试：类和对象 + 方法调用
class Calculator {
    private $result;
    
    public function __construct() {
        $this->result = 0;
    }
    
    public function add($n) {
        $this->result += $n;
        return $this;
    }
    
    public function multiply($n) {
        $this->result *= $n;
        return $this;
    }
    
    public function getResult() {
        return $this->result;
    }
}

$calc = new Calculator();
$calc->add(10)->add(5)->multiply(2);
echo "Result: " . $calc->getResult() . "\n";

// 测试静态方法
class MathHelper {
    public static function square($n) {
        return $n * $n;
    }
    
    public static function cube($n) {
        return $n * $n * $n;
    }
}

echo "5^2 = " . MathHelper::square(5) . "\n";
echo "3^3 = " . MathHelper::cube(3) . "\n";
