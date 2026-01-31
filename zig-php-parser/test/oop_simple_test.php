<?php
/**
 * OOP简化测试 - 验证核心功能
 */

$passed = 0;
$failed = 0;

function test($name, $condition) {
    global $passed, $failed;
    if ($condition) {
        $passed++;
        echo "[PASS] $name\n";
    } else {
        $failed++;
        echo "[FAIL] $name\n";
    }
}

echo "=== 基本类 ===\n";

class Point {
    public $x;
    public $y;
    
    public function __construct($x, $y) {
        $this->x = $x;
        $this->y = $y;
    }
    
    public function getX() {
        return $this->x;
    }
    
    public function getY() {
        return $this->y;
    }
}

$p = new Point(3, 4);
test("实例化", is_object($p));
test("属性x", $p->x == 3);
test("属性y", $p->y == 4);
test("方法getX", $p->getX() == 3);
test("方法getY", $p->getY() == 4);

echo "\n=== 继承 ===\n";

class Animal {
    public $name;
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    public function getName() {
        return $this->name;
    }
    
    public function speak() {
        return "sound";
    }
}

class Dog extends Animal {
    public function speak() {
        return "Woof";
    }
}

$dog = new Dog("Buddy");
test("继承实例化", is_object($dog));
test("继承属性", $dog->name == "Buddy");
test("继承方法", $dog->getName() == "Buddy");
test("方法重写", $dog->speak() == "Woof");
test("instanceof Animal", $dog instanceof Animal);
test("instanceof Dog", $dog instanceof Dog);

echo "\n=== 静态成员 ===\n";

class Counter {
    public static $count = 0;
    
    public static function increment() {
        self::$count = self::$count + 1;
    }
    
    public static function getCount() {
        return self::$count;
    }
}

test("静态属性初始", Counter::$count == 0);
Counter::increment();
test("静态方法调用", Counter::$count == 1);
test("静态getter", Counter::getCount() == 1);

echo "\n=== 类常量 ===\n";

class Math {
    const PI = 3.14159;
}

test("类常量", abs(Math::PI - 3.14159) < 0.0001);

echo "\n=== 类型检查 ===\n";

test("get_class", get_class($dog) == "Dog");
test("class_exists存在", class_exists("Point"));
test("class_exists不存在", !class_exists("NotExist"));
test("method_exists", method_exists($dog, "speak"));

echo "\n=== 链式调用 ===\n";

class Builder {
    public $value = "";
    
    public function add($s) {
        $this->value = $this->value . $s;
        return $this;
    }
    
    public function get() {
        return $this->value;
    }
}

$b = new Builder();
$result = $b->add("Hello")->add(" ")->add("World")->get();
test("链式调用", $result == "Hello World");

echo "\n========================================\n";
echo "测试结果: $passed 通过, $failed 失败\n";
echo "========================================\n";
