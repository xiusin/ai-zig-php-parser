<?php
// 测试42: 数组哈希与冲突
// 字符串键的哈希行为
$keys = ["a", "b", "c", "0", "1", "2", "00", "01", "true", "false", "null", ""];
$arr = [];
foreach ($keys as $key) {
    $arr[$key] = "value_$key";
}
echo "Array with string keys:\n";
print_r($arr);

// 数字字符串键转换
$numKeys = ["0" => "zero", "1" => "one", "2" => "two"];
$intKeys = [0 => "zero_int", 1 => "one_int"];
echo "Numeric string vs int keys:\n";
echo "numKeys[0]: " . $numKeys[0] . "\n";
echo "numKeys['0']: " . $numKeys["0"] . "\n";

// 大数组性能
$large = [];
for ($i = 0; $i < 1000; $i++) {
    $large["key_$i"] = $i;
}
echo "Large array size: " . count($large) . "\n";
echo "Memory usage: " . memory_get_usage() . " bytes\n";

// 稀疏数组
$sparse = [];
$sparse[0] = "first";
$sparse[1000] = "middle";
$sparse[10000] = "last";
echo "Sparse array count: " . count($sparse) . "\n";
echo "Array keys: " . implode(", ", array_keys($sparse)) . "\n";

// 数组指针操作
$arr = ["a" => 1, "b" => 2, "c" => 3];
reset($arr);
while (key($arr) !== null) {
    echo key($arr) . " => " . current($arr) . "\n";
    next($arr);
}

// each()函数 (已废弃，但测试兼容性)
// reset($arr);
// while (list($key, $val) = each($arr)) {
//     echo "$key => $val\n";
// }
?>
