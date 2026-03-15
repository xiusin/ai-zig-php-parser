<?php
// 测试13: 日期时间函数复杂测试
$now = time();
$yesterday = strtotime("-1 day");
$nextWeek = strtotime("+1 week");

// 格式化
$formatted = date("Y-m-d H:i:s", $now);
$custom = date("l, F j, Y", $now);

// 解析
$parsed = strtotime("2024-12-25 15:30:00");
$relative = strtotime("next Monday", $now);

// 计算差值
$diff = $now - $yesterday;
echo "Seconds in a day: $diff\n";

// mktime
$timestamp = mktime(15, 30, 0, 12, 25, 2024);
echo "mktime result: " . date("Y-m-d H:i:s", $timestamp) . "\n";

// getdate
$dateInfo = getdate($now);
print_r($dateInfo);

// microtime
$micro = microtime(true);
echo "Microtime: $micro\n";

// idate
$year = idate('Y', $now);
$month = idate('n', $now);
echo "Year: $year, Month: $month\n";

// checkdate
$valid = checkdate(2, 29, 2024);
$invalid = checkdate(2, 30, 2024);
echo "2024-02-29 valid: " . ($valid ? "yes" : "no") . "\n";
echo "2024-02-30 valid: " . ($invalid ? "yes" : "no") . "\n";

// gmdate
$gm = gmdate("Y-m-d H:i:s");
echo "GMT: $gm\n";

// strftime (deprecated but test it)
// $strftime = strftime("%A, %B %d, %Y", $now);
// echo "Strftime: $strftime\n";

echo "Now: $formatted\n";
echo "Custom: $custom\n";
echo "Parsed: " . date("Y-m-d H:i:s", $parsed) . "\n";
?>