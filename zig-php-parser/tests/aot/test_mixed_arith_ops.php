<?php
// 混合类型 sub/mul/div/mod：覆盖 runtime.php_* 返回值提取与快速路径
// 期望：同时验证 int/float 结果不会退化为 runtime.Value 输出异常

$a = 10;
$b = 3;

$intSub = $a - $b;         // 7
$intMul = $a * $b;         // 30
$intDiv = ($a - ($a % $b)) / $b;  // 3
$intMod = $a % $b;         // 1

echo "IntOps: $intSub,$intMul,$intDiv,$intMod (expect 7,30,3,1)\n";

$x = 10.5;
$y = 2;

$floatSub = $x - $y;  // 8.5
$floatMul = $x * $y;  // 21
$floatDiv = $x / $y;  // 5.25

echo "FloatOps: $floatSub,$floatMul,$floatDiv (expect 8.5,21,5.25)\n";

$m1 = 10.5;
$m2 = 3;

$mixSub = $m1 - $m2; // 7.5
$mixMul = $m1 * $m2; // 31.5
$mixDiv = $m1 / $m2; // 3.5
$mixMod = $m2 % 2;   // 1

echo "MixOps: $mixSub,$mixMul,$mixDiv,$mixMod (expect 7.5,31.5,3.5,1)\n";
