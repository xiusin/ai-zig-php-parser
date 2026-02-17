<?php
// 综合验证测试：嵌套循环、类型推导、控制流

// 测试1：3层嵌套乘法（已验证通过）
function test_3layer_mul() {
    $sum = 0;
    for ($i = 0; $i < 5; $i++) {
        for ($j = 0; $j < 5; $j++) {
            for ($k = 0; $k < 5; $k++) {
                $sum += $i * $j * $k;
            }
        }
    }
    return $sum;
}

// 测试2：多顺序循环（测试BUG1修复）
function test_sequential_loops() {
    $sum1 = 0;
    for ($i = 0; $i < 10; $i++) {
        $sum1 += $i;
    }
    
    $sum2 = 0;
    for ($j = 0; $j < 10; $j++) {
        $sum2 += $j * 2;
    }
    
    return $sum1 + $sum2;
}

// 测试3：嵌套循环中的条件分支
function test_nested_with_condition() {
    $count = 0;
    for ($i = 0; $i < 5; $i++) {
        for ($j = 0; $j < 5; $j++) {
            if ($i > $j) {
                $count += 1;
            } else {
                $count += 2;
            }
        }
    }
    return $count;
}

// 测试4：深度嵌套（4层）
function test_4layer() {
    $sum = 0;
    for ($a = 0; $a < 2; $a++) {
        for ($b = 0; $b < 2; $b++) {
            for ($c = 0; $c < 2; $c++) {
                for ($d = 0; $d < 2; $d++) {
                    $sum += $a + $b + $c + $d;
                }
            }
        }
    }
    return $sum;
}

$r1 = test_3layer_mul();
$r2 = test_sequential_loops();
$r3 = test_nested_with_condition();
$r4 = test_4layer();

echo "3层嵌套乘法: $r1 (期望 1000)\n";
echo "多顺序循环: $r2 (期望 135)\n";
echo "嵌套+条件: $r3 (期望 40)\n";
echo "4层嵌套: $r4 (期望 48)\n";

if ($r1 == 1000 && $r2 == 135 && $r3 == 40 && $r4 == 48) {
    echo "✅ 所有测试通过！\n";
} else {
    echo "❌ 部分测试失败\n";
}
