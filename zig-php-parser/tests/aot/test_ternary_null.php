<?php
// 测试：三元运算符和 null 合并
function get_grade($score) {
    return $score >= 90 ? "A" :
           ($score >= 80 ? "B" :
           ($score >= 70 ? "C" :
           ($score >= 60 ? "D" : "F")));
}

$scores = [95, 85, 75, 65, 55];
$i = 0;
while ($i < count($scores)) {
    $score = $scores[$i];
    $grade = get_grade($score);
    echo "Score $score: Grade $grade\n";
    $i++;
}

// 测试 null 合并
$value = null;
$default = "default";
$result = $value ?? $default;
echo "null ?? 'default': '$result'\n";

$value = "actual";
$result = $value ?? $default;
echo "'actual' ?? 'default': '$result'\n";

// 嵌套三元
$x = 10;
$y = 20;
$max = $x > $y ? $x : $y;
echo "max($x, $y) = $max\n";

// 条件赋值
$status = true;
$message = $status ? "Success" : "Failed";
echo "Status: $message\n";
