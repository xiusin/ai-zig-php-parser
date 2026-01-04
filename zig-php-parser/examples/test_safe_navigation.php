<?php
// 安全导航操作符测试（PHP 模式）
// 使用 ?-> 进行安全属性访问

echo "=== 安全导航操作符测试（PHP 模式）===\n\n";

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
    public $country;

    function __construct($city, $country) {
        $this->city = $city;
        $this->country = $country;
    }
}

// 测试 1: 对象存在，属性存在
echo "测试 1: 对象存在，属性存在\n";
$address = new Address("北京", "中国");
$user = new User("张三", $address);
echo "城市: " . $user->address->city . "\n"; // 正常访问
echo "城市（安全导航）: " . ($user?->address?->city) . "\n"; // 安全导航
echo "\n";

// 测试 2: 对象存在，属性为 null
echo "测试 2: 对象存在，属性为 null\n";
$user2 = new User("李四", null);
// echo "城市: " . $user2->address->city . "\n"; // 这会报错
echo "城市（安全导航）: " . ($user2?->address?->city) . "\n"; // 返回 null，不报错
echo "\n";

// 测试 3: 对象为 null
echo "测试 3: 对象为 null\n";
$user3 = null;
// echo "城市: " . $user3->address->city . "\n"; // 这会报错
echo "城市（安全导航）: " . ($user3?->address?->city) . "\n"; // 返回 null，不报错
echo "\n";

// 测试 4: 链式安全导航
echo "测试 4: 链式安全导航\n";
$user4 = new User("王五", new Address("上海", "中国"));
echo "国家: " . ($user4?->address?->country) . "\n"; // 返回 "中国"

$user5 = new User("赵六", null);
echo "国家: " . ($user5?->address?->country) . "\n"; // 返回 null

$user6 = null;
echo "国家: " . ($user6?->address?->country) . "\n"; // 返回 null
echo "\n";

// 测试 5: 在条件中使用
echo "测试 5: 在条件中使用\n";
$user7 = new User("钱七", null);
if ($user7?->address?->city) {
    echo "用户住在: " . $user7->address->city . "\n";
} else {
    echo "用户没有地址信息\n";
}
echo "\n";

// 测试 6: 与字符串拼接
echo "测试 6: 与字符串拼接\n";
$user8 = new User("孙八", new Address("深圳", "中国"));
echo "用户 " . $user8->name . " 住在 " . ($user8?->address?->city ?? "未知") . "\n";

$user9 = new User("周九", null);
echo "用户 " . $user9->name . " 住在 " . ($user9?->address?->city ?? "未知") . "\n";
echo "\n";

echo "=== 所有测试完成 ===\n";