<?php
// 测试16: JSON编码解码边界测试
$data = [
    'string' => 'Hello World',
    'number' => 12345,
    'float' => 3.14159,
    'bool' => true,
    'null' => null,
    'array' => [1, 2, 3],
    'nested' => [
        'a' => 1,
        'b' => ['x', 'y', 'z']
    ]
];

// 编码
$json = json_encode($data);
echo "JSON: $json\n";

// 解码
$decoded = json_decode($json, true);
print_r($decoded);

// 对象解码
$objDecoded = json_decode($json);
echo "Object access: " . $objDecoded->nested->b[0] . "\n";

// 特殊字符
$special = [
    'quotes' => 'He said "Hello"',
    'newline' => "Line1\nLine2",
    'tab' => "Col1\tCol2",
    'slash' => "Path\\to\\file",
    'unicode' => "Hello \u4e16\u754c"
];
$specialJson = json_encode($special);
echo "Special JSON: $specialJson\n";
$specialDecoded = json_decode($specialJson, true);
print_r($specialDecoded);

// 错误处理
$invalidJson = '{"invalid": json}';
$result = json_decode($invalidJson);
echo "Decode error: " . json_last_error_msg() . "\n";

// 深度限制
$deep = ['level' => 1, 'child' => ['level' => 2, 'child' => ['level' => 3]]];
$deepJson = json_encode($deep);
$deepDecoded = json_decode($deepJson, true, 2);
echo "Deep decode error: " . json_last_error_msg() . "\n";

// 大数据
$large = array_fill(0, 100, ['data' => str_repeat('x', 50)]);
$largeJson = json_encode($large);
echo "Large JSON length: " . strlen($largeJson) . "\n";
?>