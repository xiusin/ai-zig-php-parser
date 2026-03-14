<?php
// 闭包数组测试 8
$funcs = [];
for ($j = 0; $j < 5; $j++) {
    $funcs[] = fn($x) => $x * $j;
}

$result = 0;
foreach ($funcs as $f) {
    $result += $f(2);
}
echo $result;
echo "
";
?>