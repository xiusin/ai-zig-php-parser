<?php
// 测试11: 三元运算符与空合并
$a = null;
$b = 0;
$c = "";
$d = false;
$e = [];
$f = "valid";

// 空合并链
$result1 = $a ?? $b ?? $c ?? $d ?? $e ?? $f;
$result2 = $g ?? $h ?? $i ?? "default";

// 三元嵌套
$age = 25;
$category = $age < 13 ? "child" : ($age < 20 ? "teen" : ($age < 60 ? "adult" : "senior"));

// Elvis运算符 (PHP 5.3+)
$val1 = $a ?: "fallback1";
$val2 = $b ?: "fallback2";
$val3 = $f ?: "fallback3";

// 复杂条件链
$complex = ($x = $a ?? $b) !== null ? ($x > 0 ? "positive" : "non-positive") : "null";

// 数组中的空合并
$arr = [
    'key1' => $_GET['key1'] ?? 'default1',
    'key2' => $config['key2'] ?? $defaults['key2'] ?? 'default2',
];

// 对象属性空合并
$obj = new stdClass();
$obj->name = null;
$displayName = $obj->name ?? $obj->username ?? $obj->email ?? "Anonymous";

echo "Result1: $result1\n";
echo "Result2: $result2\n";
echo "Category: $category\n";
echo "Val1: $val1, Val2: $val2, Val3: $val3\n";
echo "Complex: $complex\n";
echo "DisplayName: $displayName\n";
?>