<?php
// 测试48: PHP 8.0空安全运算符
class Address {
    public ?string $street = null;
    public ?string $city = "Beijing";
}

class Person {
    public ?Address $address = null;
    public ?string $name = "Anonymous";
}

class Company {
    public ?Person $ceo = null;
}

$company = new Company();

// 传统写法会产生警告
// $street = $company->ceo->address->street;

// 空安全写法
$street = $company?->ceo?->address?->street;
echo "Street: " . ($street ?? "unknown") . "\n";

// 链式调用
$name = $company?->ceo?->name ?? "No CEO";
echo "CEO Name: $name\n";

// 非空情况
$company->ceo = new Person();
$company->ceo->address = new Address();
$company->ceo->address->street = "Main St";

$street2 = $company?->ceo?->address?->street;
echo "Street2: $street2\n";

// 与null合并结合
$city = $company?->ceo?->address?->city ?? "Unknown City";
echo "City: $city\n";

// 数组访问链
$arr = ['data' => ['items' => [['name' => 'Item1']]]];
$itemName = $arr['data']['items'][0]['name'] ?? 'default';
echo "Item: $itemName\n";

// 混合链
$data = new class {
    public $items = [
        ['nested' => new class {
            public $value = "found";
        }]
    ];
};
$result = $data->items[0]['nested']?->value ?? "not found";
echo "Result: $result\n";
?>
