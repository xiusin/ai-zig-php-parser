<?php
// 测试：字符串操作 + 数组操作 + 条件判断
$words = ["hello", "world", "php", "zig"];
$result = [];

foreach ($words as $word) {
    $len = strlen($word);
    if ($len > 3) {
        $upper = strtoupper($word);
        $result[] = $upper . "(" . $len . ")";
    }
}

echo "Filtered and transformed words:\n";
foreach ($result as $item) {
    echo $item . "\n";
}

// 字符串拼接测试
$sentence = "";
foreach ($words as $i => $word) {
    if ($i > 0) {
        $sentence .= " ";
    }
    $sentence .= $word;
}
echo "\nSentence: $sentence\n";

// 字符串查找
$search = "php";
$found = false;
foreach ($words as $word) {
    if ($word == $search) {
        $found = true;
        break;
    }
}
echo "Found '$search': " . ($found ? "yes" : "no") . "\n";
