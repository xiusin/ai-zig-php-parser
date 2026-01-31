<?php
/**
 * OOP功能综合测试
 * 验证解释器模式与AOT模式的一致性
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

// ============================================================================
// 1. 基本类定义和实例化
// ============================================================================
echo "\n=== 基本类定义 ===\n";

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
    
    public function distanceFromOrigin() {
        return sqrt($this->x * $this->x + $this->y * $this->y);
    }
}

$p = new Point(3, 4);
test("类实例化", is_object($p));
test("属性访问 x", $p->x == 3);
test("属性访问 y", $p->y == 4);
test("方法调用 getX()", $p->getX() == 3);
test("方法调用 getY()", $p->getY() == 4);
test("方法调用 distanceFromOrigin()", $p->distanceFromOrigin() == 5);

// ============================================================================
// 2. 继承
// ============================================================================
echo "\n=== 继承 ===\n";

class Animal {
    protected $name;
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    public function getName() {
        return $this->name;
    }
    
    public function speak() {
        return "Some sound";
    }
}

class Dog extends Animal {
    private $breed;
    
    public function __construct($name, $breed) {
        parent::__construct($name);
        $this->breed = $breed;
    }
    
    public function getBreed() {
        return $this->breed;
    }
    
    public function speak() {
        return "Woof!";
    }
}

class Cat extends Animal {
    public function speak() {
        return "Meow!";
    }
}

$dog = new Dog("Buddy", "Labrador");
$cat = new Cat("Whiskers");

test("继承 - Dog实例化", is_object($dog));
test("继承 - 父类方法 getName()", $dog->getName() == "Buddy");
test("继承 - 子类方法 getBreed()", $dog->getBreed() == "Labrador");
test("方法重写 - Dog speak()", $dog->speak() == "Woof!");
test("方法重写 - Cat speak()", $cat->speak() == "Meow!");

// ============================================================================
// 3. 静态属性和方法
// ============================================================================
echo "\n=== 静态成员 ===\n";

class Counter {
    private static $count = 0;
    
    public static function increment() {
        self::$count++;
    }
    
    public static function getCount() {
        return self::$count;
    }
    
    public static function reset() {
        self::$count = 0;
    }
}

Counter::reset();
test("静态方法 - 初始值", Counter::getCount() == 0);
Counter::increment();
test("静态方法 - 增加后", Counter::getCount() == 1);
Counter::increment();
Counter::increment();
test("静态方法 - 多次增加", Counter::getCount() == 3);

// ============================================================================
// 4. 访问修饰符
// ============================================================================
echo "\n=== 访问修饰符 ===\n";

class BankAccount {
    private $balance;
    protected $accountNumber;
    public $ownerName;
    
    public function __construct($owner, $account, $initial) {
        $this->ownerName = $owner;
        $this->accountNumber = $account;
        $this->balance = $initial;
    }
    
    public function getBalance() {
        return $this->balance;
    }
    
    public function deposit($amount) {
        if ($amount > 0) {
            $this->balance += $amount;
            return true;
        }
        return false;
    }
    
    public function withdraw($amount) {
        if ($amount > 0 && $amount <= $this->balance) {
            $this->balance -= $amount;
            return true;
        }
        return false;
    }
}

$account = new BankAccount("John", "12345", 1000);
test("public属性访问", $account->ownerName == "John");
test("private通过方法访问", $account->getBalance() == 1000);
test("deposit方法", $account->deposit(500) && $account->getBalance() == 1500);
test("withdraw方法", $account->withdraw(200) && $account->getBalance() == 1300);

// ============================================================================
// 5. 常量
// ============================================================================
echo "\n=== 类常量 ===\n";

class MathConstants {
    const PI = 3.14159;
    const E = 2.71828;
    
    public static function getCircleArea($radius) {
        return self::PI * $radius * $radius;
    }
}

test("类常量 PI", abs(MathConstants::PI - 3.14159) < 0.00001);
test("类常量 E", abs(MathConstants::E - 2.71828) < 0.00001);
test("使用常量计算", abs(MathConstants::getCircleArea(2) - 12.56636) < 0.001);

// ============================================================================
// 6. 抽象类
// ============================================================================
echo "\n=== 抽象类 ===\n";

abstract class Shape {
    abstract public function area();
    abstract public function perimeter();
    
    public function describe() {
        return "Area: " . $this->area() . ", Perimeter: " . $this->perimeter();
    }
}

class Rectangle extends Shape {
    private $width;
    private $height;
    
    public function __construct($w, $h) {
        $this->width = $w;
        $this->height = $h;
    }
    
    public function area() {
        return $this->width * $this->height;
    }
    
    public function perimeter() {
        return 2 * ($this->width + $this->height);
    }
}

class Circle extends Shape {
    private $radius;
    
    public function __construct($r) {
        $this->radius = $r;
    }
    
    public function area() {
        return 3.14159 * $this->radius * $this->radius;
    }
    
    public function perimeter() {
        return 2 * 3.14159 * $this->radius;
    }
}

$rect = new Rectangle(4, 5);
$circle = new Circle(3);

test("抽象类 - Rectangle area", $rect->area() == 20);
test("抽象类 - Rectangle perimeter", $rect->perimeter() == 18);
test("抽象类 - Circle area", abs($circle->area() - 28.27431) < 0.001);
test("抽象类 - 继承的describe方法", strpos($rect->describe(), "Area: 20") !== false);

// ============================================================================
// 7. 接口
// ============================================================================
echo "\n=== 接口 ===\n";

interface Printable {
    public function print();
}

interface Serializable {
    public function serialize();
}

class Document implements Printable, Serializable {
    private $content;
    
    public function __construct($content) {
        $this->content = $content;
    }
    
    public function print() {
        return "Printing: " . $this->content;
    }
    
    public function serialize() {
        return json_encode(["content" => $this->content]);
    }
}

$doc = new Document("Hello World");
test("接口实现 - print()", $doc->print() == "Printing: Hello World");
test("接口实现 - serialize()", strpos($doc->serialize(), "Hello World") !== false);

// ============================================================================
// 8. instanceof 运算符
// ============================================================================
echo "\n=== instanceof ===\n";

test("instanceof - Dog是Animal", $dog instanceof Animal);
test("instanceof - Dog是Dog", $dog instanceof Dog);
test("instanceof - Cat是Animal", $cat instanceof Animal);
test("instanceof - Dog不是Cat", !($dog instanceof Cat));
test("instanceof - Document是Printable", $doc instanceof Printable);

// ============================================================================
// 9. 类型检查和反射
// ============================================================================
echo "\n=== 类型检查 ===\n";

test("get_class", get_class($dog) == "Dog");
test("get_parent_class", get_parent_class($dog) == "Animal");
test("class_exists - 存在", class_exists("Point"));
test("class_exists - 不存在", !class_exists("NonExistent"));
test("method_exists - 存在", method_exists($dog, "speak"));
test("method_exists - 不存在", !method_exists($dog, "fly"));
test("property_exists - 存在", property_exists($p, "x"));

// ============================================================================
// 10. 魔术方法
// ============================================================================
echo "\n=== 魔术方法 ===\n";

class MagicBox {
    private $data = [];
    
    public function __get($name) {
        return $this->data[$name] ?? null;
    }
    
    public function __set($name, $value) {
        $this->data[$name] = $value;
    }
    
    public function __isset($name) {
        return isset($this->data[$name]);
    }
    
    public function __unset($name) {
        unset($this->data[$name]);
    }
    
    public function __toString() {
        return "MagicBox with " . count($this->data) . " items";
    }
}

$box = new MagicBox();
$box->foo = "bar";
test("__set 和 __get", $box->foo == "bar");
test("__isset", isset($box->foo));
test("__toString", strpos((string)$box, "MagicBox") !== false);

// ============================================================================
// 11. 链式调用
// ============================================================================
echo "\n=== 链式调用 ===\n";

class StringBuilder {
    private $str = "";
    
    public function append($text) {
        $this->str .= $text;
        return $this;
    }
    
    public function prepend($text) {
        $this->str = $text . $this->str;
        return $this;
    }
    
    public function toString() {
        return $this->str;
    }
}

$builder = new StringBuilder();
$result = $builder->append("Hello")->append(" ")->append("World")->toString();
test("链式调用", $result == "Hello World");

// ============================================================================
// 12. 克隆
// ============================================================================
echo "\n=== 克隆 ===\n";

$p1 = new Point(10, 20);
$p2 = clone $p1;
$p2->x = 100;

test("克隆 - 原对象不变", $p1->x == 10);
test("克隆 - 新对象修改", $p2->x == 100);

// ============================================================================
// 总结
// ============================================================================
echo "\n========================================\n";
echo "OOP测试结果: $passed 通过, $failed 失败\n";
echo "========================================\n";

if ($failed > 0) {
    exit(1);
}
