<?php
// 测试70: 对象克隆与__clone魔术方法深度测试
// 测试目的：验证深拷贝、浅拷贝和克隆行为

class Address {
    public string $street;
    public string $city;
    
    public function __construct(string $street, string $city) {
        $this->street = $street;
        $this->city = $city;
    }
    
    public function __clone(): void {
        // 创建新的独立实例
        echo "  Address cloned\n";
    }
}

class Person {
    public string $name;
    public int $age;
    public Address $address;
    public ?self $spouse = null;
    public array $hobbies = [];
    
    public function __construct(string $name, int $age, Address $address) {
        $this->name = $name;
        $this->age = $age;
        $this->address = $address;
    }
    
    public function __clone(): void {
        echo "Person {$this->name} being cloned\n";
        
        // 深拷贝：克隆关联对象
        $this->address = clone $this->address;
        
        // 深拷贝：数组是值类型，自动复制
        $this->hobbies = $this->hobbies;
        
        // spouse设为null避免循环引用问题
        if ($this->spouse !== null) {
            echo "  Breaking spouse reference\n";
            $this->spouse = null;
        }
    }
    
    public function marry(self $spouse): void {
        $this->spouse = $spouse;
        $spouse->spouse = $this;
    }
}

// 基本克隆
$addr = new Address("123 Main St", "Beijing");
$person1 = new Person("Alice", 30, $addr);
$person1->hobbies = ['reading', 'swimming'];

echo "Original person: {$person1->name}, {$person1->address->street}\n";

$person2 = clone $person1;
$person2->name = "Bob";
$person2->address->street = "456 Oak Ave";

echo "\nAfter clone and modify:\n";
echo "Person1: {$person1->name}, {$person1->address->street}\n";
echo "Person2: {$person2->name}, {$person2->address->street}\n";

// 循环引用克隆
echo "\n--- Spouse cloning ---\n";
$spouse1 = new Person("Carol", 28, new Address("789 Pine Rd", "Shanghai"));
$spouse2 = new Person("Dave", 30, new Address("789 Pine Rd", "Shanghai"));
$spouse1->marry($spouse2);

echo "Original: {$spouse1->name} married to {$spouse1->spouse->name}\n";

$cloned = clone $spouse1;
echo "Cloned: {$cloned->name} has spouse: " . ($cloned->spouse?->name ?? 'null') . "\n";

// 序列化克隆（深拷贝的另一种方式）
$deep = new Person("Eve", 35, new Address("999 Elm St", "Guangzhou"));
$deep->hobbies = ['coding', new class { public $name = 'dynamic'; }];

$serialized = serialize($deep);
$unserialized = unserialize($serialized);

echo "\nSerialized clone:\n";
echo "Same object: " . ($deep === $unserialized ? 'yes' : 'no') . "\n";
echo "Address same: " . ($deep->address === $unserialized->address ? 'yes' : 'no') . "\n";

// clone vs new
class Counter {
    public static int $instances = 0;
    public int $id;
    
    public function __construct() {
        $this->id = ++self::$instances;
        echo "  Constructed #$this->id\n";
    }
    
    public function __clone(): void {
        $this->id = ++self::$instances;
        echo "  Cloned as #$this->id\n";
    }
}

echo "\n--- Construction vs Cloning ---\n";
$c1 = new Counter();
$c2 = new Counter();
$c3 = clone $c1;
echo "Total instances: " . Counter::$instances . "\n";
?>