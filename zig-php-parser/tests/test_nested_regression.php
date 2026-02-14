<?php
// 回归测试套件：嵌套循环类型推导
// 验证 i64/f64 不会退化为 Value

// Case 1: 简单累加器类型保持 i64
$sum = 0;
for ($i = 0; $i < 10; $i++) {
    $sum += $i;
}
echo $sum; // 45

// Case 2: 嵌套循环累加器类型传递
$outer_sum = 0;
for ($i = 0; $i < 5; $i++) {
    $inner_sum = 0;
    for ($j = 0; $j < 5; $j++) {
        $inner_sum += $j;
    }
    $outer_sum += $inner_sum;
}
echo $outer_sum; // 50

// Case 3: 浮点类型在循环中保持 f64
$pi_approx = 0.0;
for ($i = 0; $i < 100; $i++) {
    $sign = 1.0;
    if ($i % 2 == 1) {
        $sign = -1.0;
    }
    $pi_approx += $sign / (2 * $i + 1);
}
$pi_approx *= 4.0;
echo $pi_approx; // ~3.1315

// Case 4: break/continue 在嵌套循环中
$found = 0;
for ($i = 0; $i < 10; $i++) {
    for ($j = 0; $j < 10; $j++) {
        if ($i * $j > 20) {
            $found = $i * $j;
            break;
        }
    }
}
echo $found; // 21

// Case 5: 循环变量在多层嵌套中的作用域
$matrix_sum = 0;
for ($row = 0; $row < 3; $row++) {
    for ($col = 0; $col < 3; $col++) {
        $matrix_sum += $row * 3 + $col;
    }
}
echo $matrix_sum; // 36
