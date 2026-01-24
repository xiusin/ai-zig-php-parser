<?php
// 性能对比测试：单块函数 vs 多块函数

// 单块函数：简单的加法（应该被优化）
function simple_add($a, $b) {
    return $a + $b;
}

// 多块函数：带条件的加法（使用状态机）
function conditional_add($a, $b) {
    if ($a > 0) {
        return $a + $b;
    } else {
        return $b;
    }
}

// 测试循环次数
$iterations = 1000;

// 测试单块函数
echo "Testing simple_add (optimized)...\n";
$i = 0;
while ($i < $iterations) {
    $result = simple_add($i, 100);
    $i = $i + 1;
}
echo "Completed ";
echo $iterations;
echo " iterations\n";

// 测试多块函数
echo "Testing conditional_add (state machine)...\n";
$j = 0;
while ($j < $iterations) {
    $result = conditional_add($j, 100);
    $j = $j + 1;
}
echo "Completed ";
echo $iterations;
echo " iterations\n";

echo "Performance test completed!\n";
