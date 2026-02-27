<?php
echo "=== 最终复杂度测试 ===\n";

$a = 10;
$b = 3;
$c = 2;
$d = 5;
$e = 7;

// 测试 1: 超级复杂数学
$m1 = $a * $b + $c * $d - $e;
$m2 = $m1 * $m1;
$m3 = $m2 + $a * $b * $c;
$m4 = $m3 - $d * $e;
$m5 = $m4 * 2 + $m1;
echo "数学运算: " . strval($m5) . "\n";

// 测试 2: 字符串拼接
$s1 = "A" . strval($a) . "B" . strval($b);
$s2 = strtoupper($s1);
$s3 = strtolower($s1);
$s4 = $s2 . $s3;
echo "字符串拼接: " . $s4 . "\n";

// 测试 3: 循环运算
$sum = 0;
$i = 0;
while ($i < 10) {
    $t1 = $i * $i;
    $t2 = $t1 + $i * 2;
    $t3 = $t2 * 3;
    $sum = $sum + $t3;
    $i = $i + 1;
}
echo "循环运算: " . strval($sum) . "\n";

// 测试 4: 数组运算
$arr = array();
$j = 0;
while ($j < 5) {
    array_push($arr, $j * 10 + $j);
    $j = $j + 1;
}
$arr_sum = 0;
$k = 0;
while ($k < count($arr)) {
    $arr_sum = $arr_sum + $arr[$k];
    $k = $k + 1;
}
echo "数组运算: " . strval($arr_sum) . "\n";

// 测试 5: 嵌套运算
$n1 = ($a + $b) * ($c + $d);
$n2 = ($n1 - $e) * 2;
$n3 = $n2 + ($a * $b * $c);
$n4 = $n3 - ($d * $e * 2);
$n5 = $n4 * 3 + $n1;
echo "嵌套运算: " . strval($n5) . "\n";

// 测试 6: 多重循环
$total = 0;
$m = 0;
while ($m < 5) {
    $n = 0;
    while ($n < 5) {
        $total = $total + $m * $n + $m + $n;
        $n = $n + 1;
    }
    $m = $m + 1;
}
echo "多重循环: " . strval($total) . "\n";

// 测试 7: 复杂表达式
$e1 = $a * $b * $c;
$e2 = $d * $e * 2;
$e3 = $e1 + $e2;
$e4 = $e3 * 2 - $e1;
$e5 = $e4 + $e2 - $e3;
$e6 = $e5 * 3 + $e4 * 2 + $e3;
echo "复杂表达式: " . strval($e6) . "\n";

// 测试 8: 字符串数学混合
$mix1 = strval($a * 10);
$mix2 = strval($b * 20);
$mix3 = $mix1 . "+" . $mix2;
echo "字符串数学: " . $mix3 . "\n";

// 测试 9: 超级组合
$combo1 = $a * $b * $c * $d;
$combo2 = $combo1 + $e * 10;
$combo3 = $combo2 * 2 - $combo1;
$combo4 = $combo3 + $combo2 - $combo1;
$combo5 = $combo4 * 3 + $combo3 * 2 + $combo2;
echo "超级组合: " . strval($combo5) . "\n";

// 测试 10: 1000 次运算
$mega = 0;
$r = 0;
while ($r < 100) {
    $mega = $mega + $r * 2 + $r;
    $r = $r + 1;
}
echo "1000次运算: " . strval($mega) . "\n";

// 测试 11: 终极挑战
$final1 = $a * $b * $c * $d * $e;
$final2 = $final1 + $final1;
$final3 = $final2 * 2 - $final1;
$final4 = $final3 + $final2 - $final1;
$final5 = $final4 * 3 + $final3 * 2 + $final2;
echo "终极挑战: " . strval($final5) . "\n";

// 测试 12: 所有功能混合
$all1 = $a + $b + $c + $d + $e;
$all2 = $all1 * $all1;
$all3 = $all2 + $all1 * 5;
$all4 = $all3 * 2 - $all2;
$all5 = $all4 + $all3 - $all2;
$all6 = $all5 * 3 + $all4 * 2 + $all3;
echo "所有功能混合: " . strval($all6) . "\n";

echo "=== 测试完成 ===\n";
