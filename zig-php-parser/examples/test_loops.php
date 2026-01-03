<?php

echo "=== 测试循环功能 ===\n";

// 测试 1: 无限循环 for { }
echo "\n测试 1: for 无限循环 (带 break)\n";
$count = 0;
for {
    $count = $count + 1;
    echo "循环次数: " . $count . "\n";
    if ($count >= 3) {
        break;
    }
}
echo "循环结束，总次数: " . $count . "\n";

// 测试 2: for range 循环
echo "\n测试 2: for range 循环\n";
for range 5 {
    echo "执行一次\n";
}

// 测试 3: for range 带变量
echo "\n测试 3: for range 带索引变量\n";
for range 5 as $i {
    echo "索引: " . $i . "\n";
}

// 测试 4: break 语句
echo "\n测试 4: break 提前退出\n";
for range 10 as $i {
    if ($i >= 3) {
        break;
    }
    echo "i = " . $i . "\n";
}

// 测试 5: continue 语句
echo "\n测试 5: continue 跳过偶数\n";
for range 6 as $i {
    if ($i == 2) {
        continue;
    }
    if ($i == 4) {
        continue;
    }
    echo "i = " . $i . "\n";
}

// 测试 6: 嵌套循环 + break
echo "\n测试 6: 嵌套循环\n";
for range 3 as $i {
    for range 3 as $j {
        echo "i=" . $i . ", j=" . $j . "\n";
        if ($j >= 1) {
            break;
        }
    }
}

// 测试 7: while 循环 + break/continue
echo "\n测试 7: while 循环控制流\n";
$n = 0;
while ($n < 5) {
    $n = $n + 1;
    if ($n == 2) {
        continue;
    }
    if ($n == 4) {
        break;
    }
    echo "n = " . $n . "\n";
}

// 测试 8: 标准 for 循环 + break/continue
echo "\n测试 8: 标准 for 循环\n";
for ($x = 0; $x < 5; $x = $x + 1) {
    if ($x == 2) {
        continue;
    }
    echo "x = " . $x . "\n";
}

echo "\n=== 所有测试完成 ===\n";
