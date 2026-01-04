<?php
// 安全导航操作符最小测试
// 使用 ?-> 进行安全属性访问

echo "=== 安全导航操作符最小测试 ===\n\n";

class User {
    public $name;
    public $address;

    function __construct($name, $address = null) {
        $this->name = $name;
        $this->address = $address;
    }
}

class Address {
    public $city;

    function __construct($city) {
        $this->city = $city;
    }
}

// 测试 1: 对象存在，属性存在
echo "测试 1: 对象存在，属性存在\n";
$address = new Address("北京");
$user = new User("张三", $address);
echo "城市: " . $user->address->city . "\n";
echo "城市（安全导航）: " . ($user?->address?->city) . "\n";
echo "\n";

// 测试 2: 对象存在，属性为 null
echo "测试 2: 对象存在，属性为 null\n";
$user2 = new User("李四", null);
echo "城市（安全导航）: " . ($user2?->address?->city) . "\n";
echo "\n";

// 测试 3: 对象为 null
echo "测试 3: 对象为 null\n";
$user3 = null;
echo "城市（安全导航）: " . ($user3?->address?->city) . "\n";
echo "\n";

echo "=== 测试完成 ===\n";
