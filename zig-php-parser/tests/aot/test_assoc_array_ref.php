<?php
// 测试：关联数组 + 引用 + 复杂操作
$users = [
    "alice" => ["age" => 25, "score" => 85],
    "bob" => ["age" => 30, "score" => 92],
    "charlie" => ["age" => 22, "score" => 78]
];

echo "Original users:\n";
foreach ($users as $name => $data) {
    echo "$name: age=" . $data["age"] . ", score=" . $data["score"] . "\n";
}

// 使用引用增加所有分数
foreach ($users as $name => &$data) {
    $data["score"] += 10;
    if ($data["score"] > 100) {
        $data["score"] = 100;
    }
}

echo "\nAfter score boost (+10, max 100):\n";
foreach ($users as $name => $data) {
    echo "$name: age=" . $data["age"] . ", score=" . $data["score"] . "\n";
}

// 计算平均分
$total_score = 0;
$count = 0;
foreach ($users as $data) {
    $total_score += $data["score"];
    $count++;
}
$avg = $total_score / $count;
echo "\nAverage score: $avg\n";

// 查找最高分
$max_score = 0;
$top_user = "";
foreach ($users as $name => $data) {
    if ($data["score"] > $max_score) {
        $max_score = $data["score"];
        $top_user = $name;
    }
}
echo "Top user: $top_user with score $max_score\n";
