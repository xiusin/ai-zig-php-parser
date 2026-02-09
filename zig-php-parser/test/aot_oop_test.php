<?php
/**
 * AOT 简化高级特性测试
 */

echo "=== 基础类测试 ===\n";

class Person {
    private $name;
    private $age;
    
    public function __construct($name, $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function getName() {
        return $this->name;
    }
    
    public function getAge() {
        return $this->age;
    }
    
    public function greet() {
        return "Hello, I'm " . $this->name;
    }
}

$person = new Person("Alice", 30);
echo $person->greet() . "\n";
echo "Age: " . $person->getAge() . "\n";

echo "\n=== 继承测试 ===\n";

class Employee extends Person {
    private $salary;
    
    public function __construct($name, $age, $salary) {
        parent::__construct($name, $age);
        $this->salary = $salary;
    }
    
    public function getSalary() {
        return $this->salary;
    }
    
    public function greet() {
        return parent::greet() . " and I work here";
    }
}

$emp = new Employee("Bob", 25, 50000);
echo $emp->greet() . "\n";
echo "Salary: " . $emp->getSalary() . "\n";

echo "\n=== 静态方法测试 ===\n";

class Math {
    public static function add($a, $b) {
        return $a + $b;
    }
    
    public static function multiply($a, $b) {
        return $a * $b;
    }
}

echo "Math::add(5, 3) = " . Math::add(5, 3) . "\n";
echo "Math::multiply(4, 7) = " . Math::multiply(4, 7) . "\n";

echo "\n=== 递归函数测试 ===\n";

function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

echo "factorial(5) = " . factorial(5) . "\n";
echo "factorial(10) = " . factorial(10) . "\n";

function fibonacci($n) {
    if ($n <= 1) {
        return $n;
    }
    return fibonacci($n - 1) + fibonacci($n - 2);
}

echo "fibonacci(10) = " . fibonacci(10) . "\n";

echo "\n=== 链式调用测试 ===\n";

class Calculator {
    private $value = 0;
    
    public function add($n) {
        $this->value += $n;
        return $this;
    }
    
    public function multiply($n) {
        $this->value *= $n;
        return $this;
    }
    
    public function subtract($n) {
        $this->value -= $n;
        return $this;
    }
    
    public function getValue() {
        return $this->value;
    }
}

$calc = new Calculator();
$result = $calc->add(10)->multiply(2)->subtract(5)->getValue();
echo "Chain result: " . $result . "\n";

echo "\n=== 所有测试完成 ===\n";
