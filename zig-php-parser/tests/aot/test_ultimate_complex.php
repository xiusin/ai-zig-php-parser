<?php
echo "=== 终极复杂度测试 ===\n";

// 测试 1: 超级复杂数学表达式 - 多层嵌套 + 所有运算符
$a = 10;
$b = 3;
$c = 2;
$d = 5;
$e = 7;

// 15 层嵌套数学运算
$math1 = ((($a * $b + $c) / $d - $e % $b) * (($a - $b) + ($c * $d))) / ((($e + $a) * $b) - (($c + $d) / $b));
$math2 = pow($a, $c) + sqrt(floatval($b * $b + $c * $c)) * abs($d - $e) / round($a / $b);
$math3 = floor(($math1 + $math2) * 1.5) + ceil(($math1 - $math2) / 2.3) + round($math1 * $math2 / 100);
echo "超级数学: " . strval($math3) . "\n";

// 测试 2: 极限字符串拼接 + 类型转换链
$str1 = "Value:";
$str2 = strval(intval(floatval(strval($a))));
$str3 = strval(floatval(intval(strval($b))));
$str4 = strval(intval(floatval(strval($c))));
$concat1 = $str1 . $str2 . "," . $str3 . "," . $str4;
$concat2 = strtoupper(substr($concat1, 0, 10)) . strtolower(substr($concat1, 10, strlen($concat1)));
$concat3 = str_replace("VALUE", "RESULT", $concat2);
echo "字符串链: " . $concat3 . "\n";

// 测试 3: 数学 + 字符串 + 类型转换混合
$num1 = intval("123") + floatval("45.67");
$num2 = intval(strval($num1)) * floatval(strval($a));
$num3 = floatval(strval($num2)) / intval(strval($b));
$str_num = strval($num3) . "=" . strval(intval($num3));
echo "混合转换: " . $str_num . "\n";

// 测试 4: 复杂条件 + 数学运算
$i = 0;
$sum = 0;
while ($i < 10) {
    $temp1 = $i * $i;
    $temp2 = $temp1 + $i;
    $temp3 = $temp2 * 2;
    $temp4 = $temp3 - $i;
    $temp5 = $temp4 / ($i + 1);
    $sum = $sum + intval($temp5);
    $i = $i + 1;
}
echo "循环数学: " . strval($sum) . "\n";

// 测试 5: 数组 + 复杂运算
$arr = array();
$j = 0;
while ($j < 5) {
    $val1 = $j * $j * $j;
    $val2 = pow($j, 2) + pow($j, 3);
    $val3 = sqrt(floatval($val1 + $val2));
    $val4 = round($val3 * 10) / 10;
    array_push($arr, intval($val4));
    $j = $j + 1;
}
$arr_sum = 0;
$k = 0;
while ($k < count($arr)) {
    $arr_sum = $arr_sum + $arr[$k];
    $k = $k + 1;
}
echo "数组运算: " . strval($arr_sum) . "\n";

// 测试 6: 字符串数学混合 + 多重转换
$base = "100";
$mult = "2.5";
$result1 = intval($base) * floatval($mult);
$result2 = strval($result1) . "x" . strval(intval($result1 / 10));
$result3 = strlen($result2) + intval(substr($result2, 0, 3));
$result4 = strval($result3) . "=" . strval($result3 * 2);
echo "字符串数学: " . $result4 . "\n";

// 测试 7: 超级嵌套函数调用
$nested1 = abs(round(sqrt(pow(floatval($a), 2) + pow(floatval($b), 2)) * 1.5));
$nested2 = floor(ceil(round(abs($nested1 - $a) / $b) * $c) + $d);
$nested3 = intval(strval(floatval(strval(intval(strval($nested2))))));
echo "嵌套函数: " . strval($nested3) . "\n";

// 测试 8: 复杂表达式 + 字符串操作
$expr1 = ($a + $b) * ($c + $d) - ($e * $a) / ($b + $c);
$expr2 = pow($expr1, 2) / 100 + sqrt(abs($expr1)) * 10;
$expr_str = "Result=" . strval(intval($expr2));
$expr_upper = strtoupper($expr_str);
$expr_len = strlen($expr_upper);
$expr_final = substr($expr_upper, 0, $expr_len - 1) . strval($expr_len);
echo "表达式字符串: " . $expr_final . "\n";

// 测试 9: 多重循环 + 复杂计算
$total = 0;
$m = 0;
while ($m < 5) {
    $n = 0;
    $inner_sum = 0;
    while ($n < 5) {
        $calc1 = $m * $n;
        $calc2 = $calc1 + $m + $n;
        $calc3 = $calc2 * 2;
        $calc4 = $calc3 - ($m + $n);
        $inner_sum = $inner_sum + $calc4;
        $n = $n + 1;
    }
    $total = $total + $inner_sum;
    $m = $m + 1;
}
echo "多重循环: " . strval($total) . "\n";

// 测试 10: 字符串拼接 + 数学 + 类型转换链
$chain1 = strval($a) . strval($b) . strval($c);
$chain2 = intval($chain1);
$chain3 = $chain2 / 100;
$chain4 = strval($chain3) . "." . strval(intval($chain3 * 100));
$chain5 = strlen($chain4) + intval(substr($chain4, 0, 1));
$chain6 = strval($chain5) . "x" . strval($chain5 * 2);
echo "转换链: " . $chain6 . "\n";

// 测试 11: 极限复杂组合
$combo1 = pow(abs($a - $b), 2) + sqrt(floatval($c * $d)) * $e;
$combo2 = floor($combo1 / $b) + ceil($combo1 / $c) + round($combo1 / $d);
$combo3 = intval(strval($combo2)) * floatval(strval($a)) / intval(strval($b));
$combo4 = strval(intval($combo3)) . "=" . strval(round($combo3 * 10) / 10);
$combo5 = strtoupper(substr($combo4, 0, 5)) . strtolower(substr($combo4, 5, strlen($combo4)));
echo "极限组合: " . $combo5 . "\n";

// 测试 12: 数组 + 字符串 + 数学混合
$mix_arr = array();
$p = 1;
while ($p <= 5) {
    $val = strval($p * 10) . "." . strval($p * 5);
    array_push($mix_arr, $val);
    $p = $p + 1;
}
$mix_str = "";
$q = 0;
while ($q < count($mix_arr)) {
    $mix_str = $mix_str . $mix_arr[$q];
    if ($q < count($mix_arr) - 1) {
        $mix_str = $mix_str . ",";
    }
    $q = $q + 1;
}
$mix_len = strlen($mix_str);
$mix_final = substr($mix_str, 0, 20) . "..." . strval($mix_len);
echo "数组混合: " . $mix_final . "\n";

// 测试 13: 超级复杂数学链
$chain_a = $a * $b + $c * $d - $e;
$chain_b = pow($chain_a, 2) / 10 + sqrt(abs($chain_a)) * 5;
$chain_c = floor($chain_b) + ceil($chain_b) + round($chain_b);
$chain_d = $chain_c * $a / $b + $chain_c * $c / $d;
$chain_e = intval($chain_d) + floatval(strval($chain_d));
$chain_f = strval(intval($chain_e)) . "." . strval(intval(($chain_e - intval($chain_e)) * 100));
echo "数学链: " . $chain_f . "\n";

// 测试 14: 字符串操作 + 数学运算
$op1 = "Hello";
$op2 = "World";
$op3 = $op1 . " " . $op2;
$op4 = strlen($op3) * 10;
$op5 = strval($op4) . "=" . strval($op4 / 2);
$op6 = strtoupper(substr($op5, 0, 5)) . strtolower(substr($op5, 5, strlen($op5)));
$op7 = str_replace("=", "->", $op6);
$op8 = $op7 . "[" . strval(strlen($op7)) . "]";
echo "字符串操作: " . $op8 . "\n";

// 测试 15: 终极复杂度 - 所有功能混合
$ultimate1 = pow(abs($a * $b - $c * $d), 2) / 100;
$ultimate2 = sqrt(floatval($ultimate1)) * $e + floor($ultimate1 / $b);
$ultimate3 = intval(strval($ultimate2)) + floatval(strval(intval($ultimate2)));
$ultimate4 = strval($ultimate3) . "x" . strval(round($ultimate3 * 1.5));
$ultimate5 = strtoupper(substr($ultimate4, 0, 3)) . strtolower(substr($ultimate4, 3, strlen($ultimate4)));
$ultimate6 = str_replace("X", "*", $ultimate5);
$ultimate7 = strlen($ultimate6) + intval(substr($ultimate6, 0, 2));
$ultimate8 = strval($ultimate7) . "=" . strval($ultimate7 * 3);
echo "终极复杂: " . $ultimate8 . "\n";

// 测试 16: 1000 次复杂运算
$mega_sum = 0;
$r = 0;
while ($r < 100) {
    $temp_a = $r * 2 + 1;
    $temp_b = pow($temp_a, 2) / 10;
    $temp_c = sqrt(abs($temp_b)) * 3;
    $temp_d = floor($temp_c) + ceil($temp_c);
    $temp_e = intval($temp_d) + floatval(strval($temp_d));
    $mega_sum = $mega_sum + intval($temp_e);
    $r = $r + 1;
}
echo "1000次运算: " . strval($mega_sum) . "\n";

// 测试 17: 超级字符串拼接
$super_str = "";
$s = 0;
while ($s < 20) {
    $part1 = strval($s);
    $part2 = strval($s * 2);
    $part3 = strval($s * 3);
    $super_str = $super_str . $part1 . "," . $part2 . "," . $part3 . ";";
    $s = $s + 1;
}
$super_len = strlen($super_str);
$super_final = substr($super_str, 0, 50) . "..." . strval($super_len);
echo "超级字符串: " . $super_final . "\n";

// 测试 18: 复杂类型转换循环
$convert_sum = 0;
$t = 1;
while ($t <= 10) {
    $cv1 = strval($t);
    $cv2 = intval($cv1);
    $cv3 = floatval(strval($cv2));
    $cv4 = intval(strval($cv3));
    $cv5 = strval($cv4);
    $cv6 = intval($cv5) * 2;
    $convert_sum = $convert_sum + $cv6;
    $t = $t + 1;
}
echo "类型转换循环: " . strval($convert_sum) . "\n";

// 测试 19: 数组 + 复杂字符串操作
$str_arr = array();
$u = 0;
while ($u < 10) {
    $item = "Item" . strval($u) . "=" . strval($u * 10);
    array_push($str_arr, $item);
    $u = $u + 1;
}
$joined = "";
$v = 0;
while ($v < count($str_arr)) {
    $joined = $joined . $str_arr[$v];
    if ($v < count($str_arr) - 1) {
        $joined = $joined . "|";
    }
    $v = $v + 1;
}
$joined_len = strlen($joined);
$joined_final = substr($joined, 0, 40) . "..." . strval($joined_len);
echo "数组字符串: " . $joined_final . "\n";

// 测试 20: 终极挑战 - 所有功能 + 最大复杂度
$final1 = pow(abs($a * $b * $c - $d * $e), 2) / 1000;
$final2 = sqrt(floatval($final1 + 100)) * $a + floor($final1 / $b) * $c;
$final3 = ceil($final2 / $d) + round($final2 / $e) + abs($final2 - 100);
$final4 = intval(strval($final3)) + floatval(strval(intval(strval($final3))));
$final5 = strval(intval($final4)) . "." . strval(intval(($final4 - intval($final4)) * 1000));
$final6 = strtoupper(substr($final5, 0, 5)) . strtolower(substr($final5, 5, strlen($final5)));
$final7 = str_replace(".", "->", $final6);
$final8 = $final7 . "[" . strval(strlen($final7)) . "]";
$final9 = strlen($final8) + intval(substr($final8, 0, 3));
$final10 = strval($final9) . "=" . strval($final9 * 5) . "=" . strval($final9 * 10);
echo "终极挑战: " . $final10 . "\n";

echo "=== 测试完成 ===\n";
