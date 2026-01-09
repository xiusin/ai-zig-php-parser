<?php
// 随机测试脚本 #1 - 复杂控制流和嵌套

$test_id = 1;
echo "=== Random Test #{$test_id} ===\n";

// 随机数组操作
$data = [];
for ($i = 0; $i < 10; $i++) {
    $key = "key_" . $i . "_" . str_repeat("x", $i % 5);
    $data[$key] = [
        "id" => $i,
        "name" => "item_$i",
        "values" => range($i, $i + 5),
        "nested" => [
            "a" => ["x" => 1, "y" => 2],
            "b" => [1, 2, 3, 4, 5]
        ]
    ];
}

// 条件嵌套
$result = 0;
foreach ($data as $item) {
    if ($item["id"] > 3) {
        if ($item["id"] < 8) {
            foreach ($item["values"] as $v) {
                if ($v % 2 == 0) {
                    $result += $v;
                }
            }
        } else {
            $result += $item["id"];
        }
    } else {
        $result += array_sum($item["values"]);
    }
}

echo "Result: $result\n";

// 字符串操作
$str = "hello world test string";
$parts = explode(" ", $str);
$joined = implode("_", $parts);
echo "String: $joined\n";

// 闭包测试
$multiplier = function($factor) {
    return function($x) use ($factor) {
        return $x * $factor;
    };
};

$double = $multiplier(2);
$triple = $multiplier(3);

$test_values = [1, 2, 3, 4, 5];
foreach ($test_values as $v) {
    echo "Double($v)=" . $double($v) . " ";
    echo "Triple($v)=" . $triple($v) . "\n";
}

echo "=== Test #{$test_id} Complete ===\n";
