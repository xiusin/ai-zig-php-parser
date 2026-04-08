<?php
// OOP基础测试

// 类定义
class Person {
    // 属性
    public $name;
    public $age;
    private $secret = 'hidden';
    protected $protected = 'protected';

    // 静态属性
    public static $count = 0;

    // 常量
    const SPECIES = 'Human';

    // 构造函数
    public function __construct($name, $age) {
        $this->name = $name;
        $this->age = $age;
        self::$count++;
    }

    // 析构函数
    public function __destruct() {
        self::$count--;
    }

    // 方法
    public function greet() {
        return "Hello, I'm {$this->name}, {$this->age} years old.";
    }

    // 静态方法
    public static function getCount() {
        return self::$count;
    }

    // Getter
    public function getSecret() {
        return $this->secret;
    }

    // Setter
    public function setSecret($value) {
        $this->secret = $value;
    }
}

// 实例化
$person1 = new Person('Alice', 25);
$person2 = new Person('Bob', 30);

echo $person1->greet() . "\n";
echo $person2->greet() . "\n";

// 访问属性
echo "Name: " . $person1->name . "\n";
echo "Age: " . $person1->age . "\n";

// 访问常量
echo "Species: " . Person::SPECIES . "\n";

// 访问静态属性
echo "Count: " . Person::$count . "\n";

// 调用静态方法
echo "Static count: " . Person::getCount() . "\n";

// Getter/Setter
echo "Secret: " . $person1->getSecret() . "\n";
$person1->setSecret('new secret');
echo "New secret: " . $person1->getSecret() . "\n";

// instanceof检查
echo "is Person: " . var_export($person1 instanceof Person, true) . "\n";

// unset销毁对象
unset($person2);
echo "After unset count: " . Person::$count . "\n";

// 类变量类型检查
class Container {
    public ?Person $owner = null;

    public function setOwner(?Person $p): void {
        $this->owner = $p;
    }
}

$container = new Container();
echo "Owner before: " . var_export($container->owner, true) . "\n";
$container->setOwner($person1);
echo "Owner after: " . $container->owner->name . "\n";

// 匿名类
$anon = new class {
    public function sayHello() {
        return "Hello from anonymous class!";
    }
};
echo $anon->sayHello() . "\n";

// 带构造函数的匿名类
$anonWithCtor = new class('Test') {
    public function __construct(private string $value) {}

    public function getValue(): string {
        return $this->value;
    }
};
echo "Anonymous value: " . $anonWithCtor->getValue() . "\n";

// 属性类型声明
class TypedClass {
    public int $integer = 0;
    public float $float = 0.0;
    public string $string = '';
    public bool $bool = false;
    public array $array = [];

    public function __construct() {
        $this->integer = 42;
        $this->float = 3.14;
        $this->string = 'hello';
        $this->bool = true;
        $this->array = [1, 2, 3];
    }
}

$typed = new TypedClass();
echo "Typed int: {$typed->integer}\n";
echo "Typed float: {$typed->float}\n";
echo "Typed string: {$typed->string}\n";
echo "Typed bool: " . var_export($typed->bool, true) . "\n";
echo "Typed array count: " . count($typed->array) . "\n";
