<?php
// 测试56: 模式匹配模拟 (使用match)
$data = [
    ['type' => 'user', 'name' => 'Alice', 'role' => 'admin'],
    ['type' => 'user', 'name' => 'Bob', 'role' => 'user'],
    ['type' => 'product', 'name' => 'Laptop', 'price' => 999],
    ['type' => 'unknown', 'value' => 'test'],
];

foreach ($data as $item) {
    $result = match($item['type']) {
        'user' => match($item['role']) {
            'admin' => "Admin user: {$item['name']}",
            'user' => "Regular user: {$item['name']}",
            default => "Unknown role: {$item['name']}",
        },
        'product' => "Product: {$item['name']} at \${$item['price']}",
        default => "Unknown type: {$item['type']}",
    };
    echo $result . "\n";
}

// 复杂条件匹配
$score = 85;
$grade = match(true) {
    $score >= 90 && $score <= 100 => 'A',
    $score >= 80 && $score < 90 => 'B',
    $score >= 70 && $score < 80 => 'C',
    $score >= 60 && $score < 70 => 'D',
    $score >= 0 && $score < 60 => 'F',
    default => throw new InvalidArgumentException("Invalid score: $score"),
};
echo "Grade: $grade\n";

// 多条件匹配
$status = match(200) {
    200, 201, 204 => 'Success',
    301, 302, 304 => 'Redirect',
    400, 401, 403, 404 => 'Client Error',
    500, 502, 503 => 'Server Error',
    default => 'Unknown',
};
echo "HTTP Status: $status\n";
?>
