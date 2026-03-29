<?php
// 测试21: Switch与Match表达式
$day = 3;
$month = "March";

// Switch语句
switch ($day) {
    case 1:
        echo "Monday\n";
        break;
    case 2:
        echo "Tuesday\n";
        break;
    case 3:
    case 4:
    case 5:
        echo "Mid-week\n";
        break;
    default:
        echo "Weekend\n";
}

// Switch fallthrough
$grade = 85;
switch (true) {
    case $grade >= 90:
        echo "A";
        break;
    case $grade >= 80:
        echo "B";
        break;
    case $grade >= 70:
        echo "C";
        break;
    default:
        echo "F";
}
echo "\n";

// Match表达式 (PHP 8+)
$result = match($month) {
    "January" => 1,
    "February" => 2,
    "March" => 3,
    "April" => 4,
    default => 0,
};
echo "Month number: $result\n";

// Match with conditions
$score = 75;
$level = match(true) {
    $score >= 90 => "Excellent",
    $score >= 80 => "Good",
    $score >= 60 => "Pass",
    default => "Fail",
};
echo "Level: $level\n";

// Match多个值
$status = match($day) {
    1, 2, 3, 4, 5 => "Weekday",
    6, 7 => "Weekend",
    default => "Invalid",
};
echo "Status: $status\n";

// Match混合类型
$value = "42";
$matched = match($value) {
    42 => "integer",
    "42" => "string",
    true => "boolean",
    default => "other",
};
echo "Matched: $matched\n";
?>
