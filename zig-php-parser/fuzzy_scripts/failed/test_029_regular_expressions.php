<?php
// 测试29: 正则表达式复杂测试
$text = "The quick brown fox jumps over 13 lazy dogs at 3:45 PM on 2024-03-15";

// 基本匹配
preg_match('/quick/', $text, $matches);
echo "Match 'quick': " . ($matches[0] ?? "not found") . "\n";

// 捕获组
preg_match('/(\w+) (\w+) (\w+)/', $text, $matches);
echo "First 3 words: " . implode(", ", array_slice($matches, 1)) . "\n";

// 所有匹配
preg_match_all('/\b\w{4,}\b/', $text, $words);
echo "Words 4+ chars: " . implode(", ", $words[0]) . "\n";

// 数字匹配
preg_match_all('/\d+/', $text, $numbers);
echo "Numbers: " . implode(", ", $numbers[0]) . "\n";

// 日期匹配
preg_match('/(\d{4})-(\d{2})-(\d{2})/', $text, $date);
if ($date) {
    echo "Date: {$date[1]}-{$date[2]}-{$date[3]}\n";
}

// 替换
$replaced = preg_replace('/\d+/', '[NUM]', $text);
echo "Replaced: $replaced\n";

// 回调替换
$callbackReplace = preg_replace_callback('/\d+/', function($m) {
    return '[' . ($m[0] * 2) . ']';
}, $text);
echo "Callback replace: $callbackReplace\n";

// 分割
$parts = preg_split('/\s+/', $text, -1, PREG_SPLIT_NO_EMPTY);
echo "Split count: " . count($parts) . "\n";

// 带偏移分割
$partsWithOffset = preg_split('/\s+/', $text, -1, PREG_SPLIT_OFFSET_CAPTURE);
foreach (array_slice($partsWithOffset, 0, 3) as $part) {
    echo "Word '{$part[0]}' at offset {$part[1]}\n";
}

// 过滤数组
$items = ['test1', 'TEST2', 'hello', 'WORLD', '123', 'abc'];
$filtered = preg_grep('/^[a-z]+$/', $items);
echo "Lowercase only: " . implode(", ", $filtered) . "\n";

// 复杂模式
$email = "test@example.com";
$emailPattern = '/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/';
echo "Email valid: " . (preg_match($emailPattern, $email) ? "yes" : "no") . "\n";

// 贪婪vs非贪婪
$html = "<div>First</div><div>Second</div>";
preg_match_all('/<div>(.*)<\/div>/', $html, $greedy);
preg_match_all('/<div>(.*?)<\/div>/', $html, $nonGreedy);
echo "Greedy: " . implode(", ", $greedy[1]) . "\n";
echo "Non-greedy: " . implode(", ", $nonGreedy[1]) . "\n";

// 命名捕获组
preg_match('/(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/', $text, $named);
if ($named) {
    echo "Named groups: year={$named['year']}, month={$named['month']}, day={$named['day']}\n";
}
?>
