<?php
// 极端压力测试：深度嵌套循环
// 验证 AOT 编译器支持任意深度嵌套

// 测试1：3层嵌套 for 循环 + 累加器
$sum = 0;
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        for ($k = 0; $k < 3; $k++) {
            $sum += $i + $j + $k;
        }
    }
}
echo $sum; // 期望: 81

// 测试2：4层嵌套 for 循环
$count = 0;
for ($a = 0; $a < 2; $a++) {
    for ($b = 0; $b < 2; $b++) {
        for ($c = 0; $c < 2; $c++) {
            for ($d = 0; $d < 2; $d++) {
                $count += 1;
            }
        }
    }
}
echo $count; // 期望: 16

// 测试3：5层嵌套 while 循环
$total = 0;
$i = 0;
while ($i < 2) {
    $j = 0;
    while ($j < 2) {
        $k = 0;
        while ($k < 2) {
            $l = 0;
            while ($l < 2) {
                $m = 0;
                while ($m < 2) {
                    $total += 1;
                    $m++;
                }
                $l++;
            }
            $k++;
        }
        $j++;
    }
    $i++;
}
echo $total; // 期望: 32

// 测试4：混合 for/while 嵌套
$result = 0;
for ($i = 0; $i < 3; $i++) {
    $j = 0;
    while ($j < 3) {
        for ($k = 0; $k < 3; $k++) {
            $result += $i * $j * $k;
        }
        $j++;
    }
}
echo $result; // 期望: 81

// 测试5：嵌套循环中的类型一致性
$int_sum = 0;
$float_sum = 0.0;
for ($i = 0; $i < 5; $i++) {
    for ($j = 0; $j < 5; $j++) {
        $int_sum += $i + $j;
        $float_sum += ($i + $j) * 1.5;
    }
}
echo $int_sum;   // 期望: 100
echo $float_sum; // 期望: 150.0
